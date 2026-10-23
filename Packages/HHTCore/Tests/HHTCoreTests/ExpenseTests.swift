import Foundation
import Testing
@testable import HHTCore

/// home → penn → restaurant → penn → home, all walking.
private func lunchDay() -> Trajectory {
    var tr = Trajectory(start: Trajectory.date("2026-09-15 07:00"), at: Philly.home)
    tr.stay(minutes: 60)
    tr.move(to: Philly.penn, speed: 1.4, activity: .walking)
    tr.stay(minutes: 180)
    tr.move(to: Philly.restaurant, speed: 1.3, activity: .walking)
    tr.stay(minutes: 45)
    tr.move(to: Philly.penn, speed: 1.3, activity: .walking)
    tr.stay(minutes: 180)
    tr.move(to: Philly.home, speed: 1.4, activity: .walking)
    tr.stay(minutes: 60)
    return tr
}

private func processed(_ tr: Trajectory) throws -> (TravelStore, InferenceEngine, EditService) {
    let store = try makeStore(tr)
    let engine = InferenceEngine(store: store)
    try engine.processNew(now: tr.t.addingTimeInterval(60))
    return (store, engine, EditService(store: store))
}

private func cost(_ amount: Double, _ category: ExpenseCategory, at t: Date, currency: String = "USD",
                  trip: String? = nil, visit: String? = nil) -> Expense {
    Expense(timestamp: t, amount: amount, currency: currency, category: category, tripID: trip, visitID: visit,
            timeZone: "America/New_York")
}

@Suite("Costs (issue #17)")
struct ExpenseTests {

    @Test func costLocksItsTripAndSurvivesReprocessing() throws {
        let tr = lunchDay()
        let (store, engine, edit) = try processed(tr)
        let trip = try #require(try store.allTrips().first)
        let lunch = try #require(try store.allVisits().first { Geo.distance($0.coordinate, Philly.restaurant) < 150 })
        #expect(trip.userStatus == .auto)

        try edit.saveExpense(cost(2.9, .fare, at: trip.departure, trip: trip.id))
        try edit.saveExpense(cost(14.5, .food, at: lunch.arrival, visit: lunch.id))
        #expect(try store.trip(trip.id)?.userStatus == .edited)
        #expect(try store.visit(lunch.id)?.userStatus == .edited)

        // a full rebuild keeps both records, so the costs still point at them
        try engine.process(from: tr.points[0].timestamp, to: tr.t, now: tr.t.addingTimeInterval(60))
        #expect(try store.trip(trip.id)?.deleted == false)
        #expect(try store.visit(lunch.id)?.deleted == false)
        #expect(try store.expenses(tripID: trip.id).map(\.amount) == [2.9])
        #expect(try store.expenses(visitID: lunch.id).map(\.amount) == [14.5])
    }

    @Test func editingAndDeletingAreAudited() throws {
        let tr = lunchDay()
        let (store, _, edit) = try processed(tr)
        var e = try edit.saveExpense(cost(3, .fare, at: tr.points[0].timestamp, currency: " usd "))
        #expect(e.currency == "USD")
        e.amount = 2.5
        e.note = "  student fare "
        let saved = try edit.saveExpense(e)
        #expect(saved.note == "student fare")
        #expect(try store.expense(e.id)?.amount == 2.5)
        try edit.deleteExpense(e.id)
        #expect(try store.expenses(from: .distantPast, to: .distantFuture).isEmpty)
        let actions = try store.auditLog(entityID: e.id).map { "\($0.action):\($0.field ?? "")" }
        #expect(actions == ["create:amount", "update:amount", "update:note", "delete:amount"])
    }

    @Test func invalidCostsAreRejected() throws {
        let (_, _, edit) = try processed(lunchDay())
        let t = Date()
        #expect(throws: EditError.self) { try edit.saveExpense(cost(-1, .fare, at: t)) }
        #expect(throws: EditError.self) { try edit.saveExpense(cost(1, .fare, at: t, currency: "dollars")) }
        #expect(throws: EditError.self) { try edit.saveExpense(cost(.nan, .fare, at: t)) }
        #expect(throws: EditError.self) { try edit.saveExpense(cost(1, .fare, at: t, trip: "a", visit: "b")) }
        #expect(throws: EditError.self) { try edit.saveExpense(cost(1, .fare, at: t, trip: "missing")) }
        #expect(try edit.saveExpense(cost(0, .fare, at: t)).amount == 0)     // free is a valid answer
    }

    @Test func costsFollowMergesAndStayOnTheDayWhenTheirRecordGoes() throws {
        let (store, _, edit) = try processed(lunchDay())
        let trips = try store.allTrips().sorted { $0.departure < $1.departure }
        let visits = try store.allVisits().sorted { $0.arrival < $1.arrival }
        #expect(trips.count == 4 && visits.count == 5)
        // the restaurant wasn't a stop: trips 2 and 3 join, trip 3's cost moves onto the joined trip
        let onSecond = try edit.saveExpense(cost(1, .fare, at: trips[2].departure, trip: trips[2].id))
        let atLunch = try edit.saveExpense(cost(9, .food, at: visits[2].arrival, visit: visits[2].id))
        try edit.deleteVisit(visits[2].id)
        #expect(try store.expense(onSecond.id)?.tripID == trips[1].id)
        let orphan = try #require(try store.expense(atLunch.id))
        #expect(orphan.visitID == nil && !orphan.deleted)

        // "this trip didn't happen": the visits around it join, the trip's cost stays on the day
        let last = trips[3]
        let onLast = try edit.saveExpense(cost(4, .taxi, at: last.departure, trip: last.id))
        let atHome = try edit.saveExpense(cost(2, .other, at: visits[4].arrival, visit: visits[4].id))
        try edit.deleteTrip(last.id)
        #expect(try store.expense(onLast.id)?.tripID == nil)
        #expect(try store.expense(atHome.id)?.visitID == last.originVisitID)
    }

    @Test func spendingSummary() throws {
        let range = DateRange(start: Trajectory.date("2026-09-15 00:00"), end: Trajectory.date("2026-09-17 00:00"))
        let t0 = Trajectory.date("2026-09-15 08:00"), t1 = Trajectory.date("2026-09-16 12:00")
        let cafe = Place(id: "cafe", name: "Cafe", coordinate: Philly.restaurant, category: .cafe)
        let bus = Trip(id: "bus", originVisitID: nil, destinationVisitID: "v", departure: t0, arrival: t0.addingTimeInterval(900),
                       distance: 4_000, modeAuto: .bus, modeConfidence: 0.9)
        let bus2 = Trip(id: "bus2", originVisitID: nil, destinationVisitID: nil, departure: t1, arrival: t1.addingTimeInterval(900),
                        distance: 6_000, modeAuto: .bus, modeConfidence: 0.9)
        let visit = Visit(id: "v", placeID: "cafe", arrival: t0.addingTimeInterval(900), departure: t0.addingTimeInterval(3_600),
                          coordinate: Philly.restaurant)
        let expenses = [
            cost(2.5, .fare, at: t0, trip: "bus"),
            cost(2.5, .fare, at: t1, trip: "bus2"),
            cost(6, .food, at: t0.addingTimeInterval(1_000), visit: "v"),
            cost(3, .parking, at: t1),                                   // unlinked, a travel category
            cost(1, .shopping, at: t1),                                  // unlinked, spent somewhere
            cost(1, .fare, at: t1, trip: "gone"),                        // its trip no longer exists
            cost(20, .admission, at: t1, currency: "EUR"),
            cost(99, .food, at: Trajectory.date("2026-09-20 12:00")),    // outside the range
        ]
        let s = Analytics.spending(expenses: expenses, trips: ["bus": bus, "bus2": bus2], visits: ["v": visit],
                                   places: ["cafe": cafe], range: range, defaultCurrency: "USD")
        #expect(s.currency == "USD")
        #expect(s.count == 6 && s.days == 2)
        #expect(s.total == 16)
        #expect(s.travel == 9)              // 2 × 2.5 on trips + 3 parking + 1 on the missing trip (fare)
        #expect(s.atDestinations == 7)      // 6 at the cafe + 1 shopping
        #expect(s.perDay == 8)
        #expect(s.otherCurrencies == ["EUR": 20])
        #expect(s.byCategory.first?.category == .fare && s.byCategory.first?.total == 6)
        let row = try #require(s.byMode.first)
        #expect(row.mode == .bus && row.trips == 2 && row.total == 5 && row.perTrip == 2.5)
        #expect(row.perKm == 0.5)
        #expect(s.byPlace.map(\.name) == ["Cafe"])
    }

    @Test func mainCurrencyIsTheMostUsedOne() {
        let r = DateRange(start: .distantPast, end: .distantFuture)
        let t = Date()
        let mostlyEuro = [cost(1, .food, at: t, currency: "EUR"), cost(2, .food, at: t, currency: "EUR"), cost(5, .food, at: t)]
        let s = Analytics.spending(expenses: mostlyEuro, trips: [:], visits: [:], places: [:], range: r, defaultCurrency: "USD")
        #expect(s.currency == "EUR" && s.total == 3 && s.otherCurrencies == ["USD": 5])
        // a tie goes to the default currency
        let tie = Analytics.spending(expenses: [cost(1, .food, at: t, currency: "EUR"), cost(5, .food, at: t)],
                                     trips: [:], visits: [:], places: [:], range: r, defaultCurrency: "USD")
        #expect(tie.currency == "USD")
        #expect(Analytics.spending(expenses: [], trips: [:], visits: [:], places: [:], range: r, defaultCurrency: "JPY").isEmpty)
    }

    @Test func recentAmountsByModeAndPlace() throws {
        let (store, _, edit) = try processed(lunchDay())
        let trip = try #require(try store.allTrips().first)
        try edit.setTripMode(trip.id, .bus)
        try edit.saveExpense(cost(2.9, .fare, at: trip.departure, trip: trip.id))
        #expect(try store.recentExpenses(mode: .bus).map(\.amount) == [2.9])
        #expect(try store.recentExpenses(mode: .subway).isEmpty)
        #expect(store.hasExpenses())
    }

    @Test func exportIncludesCosts() throws {
        let (store, _, edit) = try processed(lunchDay())
        let trip = try #require(try store.allTrips().first)
        try edit.saveExpense(cost(2.9, .fare, at: trip.departure, trip: trip.id))
        try edit.saveExpense(cost(0, .fare, at: trip.arrival))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hht-cost-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let folder = try Exporter(store: store).exportBundle(to: dir)
        let csv = try String(contentsOf: folder.appendingPathComponent("expenses.csv"), encoding: .utf8)
        let lines = csv.split(separator: "\n")
        #expect(lines.first?.hasPrefix("expense_id,ts,time_utc,tz,amount,currency,category,trip_id,visit_id,note") == true)
        #expect(lines.count == 3)
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("data.json"))) as? [String: Any]
        #expect((json?["expenses"] as? [Any])?.count == 2)
        #expect(store.counts()["expenses"] == 2)
    }
}
