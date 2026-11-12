import Foundation
import Testing
@testable import HHTCore

/// On-device recall of saved places near an ambiguous stop (issue #95).
@Suite struct PlaceRecallTests {
    /// Two saved places in one building (different floors) at the same coordinate, a third next door, an untouched
    /// inferred place, and one far away.
    private func seededStore() throws -> (TravelStore, Visit) {
        let store = try TravelStore.inMemory()
        let building = Philly.penn
        try store.upsertPlace(Place(id: "f2", name: "Dentist", coordinate: building, radius: 60, category: .medical,
                                    unit: "Floor 2", source: .manual))
        try store.upsertPlace(Place(id: "f5", name: "Co-working", coordinate: building, radius: 60,
                                    category: .workSchool, unit: "Floor 5", source: .manual))
        try store.upsertPlace(Place(id: "cafe", name: "Cafe", coordinate: Geo.unproject((45, 0), origin: building),
                                    radius: 40, category: .cafe, source: .manual))
        try store.upsertPlace(Place(id: "auto", coordinate: Geo.unproject((5, 5), origin: building), radius: 80,
                                    source: .inferred))
        try store.upsertPlace(Place(id: "far", name: "Home", coordinate: Philly.home, radius: 80, category: .home,
                                    source: .manual))
        let v = Visit(placeID: "f2", arrival: Trajectory.date("2026-10-01 09:00"),
                      departure: Trajectory.date("2026-10-01 10:00"), coordinate: Geo.unproject((3, -4), origin: building))
        try store.upsertVisit(v)
        return (store, v)
    }

    @Test func listsOnlyNearbyUserMarkedPlacesAndKeepsColocatedOnesApart() throws {
        let (store, v) = try seededStore()
        let c = try store.recallCandidates(near: v.coordinate, radius: 150)
        #expect(Set(c.map(\.id)) == ["f2", "f5", "cafe"])         // not the untouched inferred place, not the far one
        #expect(c.last?.id == "cafe")                               // nearest first
        #expect(c.first { $0.id == "f5" }?.place.unit == "Floor 5")
        #expect(try store.recallCandidates(near: v.coordinate, radius: 20).map(\.id).sorted() == ["f2", "f5"])
    }

    @Test func nearTiesGoToTheMoreVisitedPlace() throws {
        let (store, v) = try seededStore()
        for d in 2...4 {
            try store.upsertVisit(Visit(placeID: "f5", arrival: Trajectory.date("2026-10-0\(d) 09:00"),
                                        departure: Trajectory.date("2026-10-0\(d) 10:00"), coordinate: Philly.penn))
        }
        #expect(try store.recallCandidates(near: v.coordinate).prefix(2).map(\.id) == ["f5", "f2"])
    }

    @Test func aPlaceChosenForAVisitCountsAsMarked() throws {
        let (store, v) = try seededStore()
        #expect(try !store.recallCandidates(near: v.coordinate).contains { $0.id == "auto" })
        try EditService(store: store).setVisitPlace(v.id, placeID: "auto")
        #expect(try store.recallCandidates(near: v.coordinate).contains { $0.id == "auto" })
    }

    @Test func recallNeverAssignsAPlace() throws {
        let (store, v) = try seededStore()
        let before = try #require(try store.visit(v.id))
        #expect(try !store.recallCandidates(near: v.coordinate).isEmpty)
        #expect(try store.visit(v.id) == before)
        #expect(before.placeStatus == .auto)
    }

    @Test func choosingAPlaceConfirmsItAndKeepsTheDetectedStop() throws {
        let (store, v) = try seededStore()
        #expect(v.placeStatus == .auto)
        try EditService(store: store).setVisitPlace(v.id, placeID: "f5")
        let after = try #require(try store.visit(v.id))
        #expect(after.placeID == "f5")
        #expect(after.placeStatus == .confirmed)
        #expect(after.coordinate == v.coordinate)                   // the GPS stop is not moved onto the place
        #expect(after.arrival == v.arrival && after.departure == v.departure)
        #expect(try store.auditLog(entityID: v.id).contains { $0.field == "place_status" && $0.newValue == "confirmed" })
    }

    @Test func looksRightConfirmsThePlaceToo() throws {
        let (store, v) = try seededStore()
        try EditService(store: store).confirm(visitID: v.id)
        #expect(try store.visit(v.id)?.placeStatus == .confirmed)
    }

    @Test func noneOfTheseDetachesFromTheSavedPlace() throws {
        let (store, v) = try seededStore()
        try EditService(store: store).setVisitPlaceUnspecified(v.id)
        let after = try #require(try store.visit(v.id))
        #expect(after.placeStatus == .unspecified)
        #expect(after.userStatus.isLocked)                          // survives reprocessing
        let p = try #require(try after.placeID.flatMap(store.place))
        #expect(!p.isNamed && p.id != "f2")
        #expect(p.coordinate == v.coordinate)
        #expect(try store.place("f2") != nil)                       // the saved place itself is untouched
        // the new placeholder is not offered back as a saved place
        #expect(try !store.recallCandidates(near: v.coordinate).contains { $0.id == p.id })
    }

    @Test func noneOfTheseKeepsAnUnmarkedPlace() throws {
        let (store, v) = try seededStore()
        var w = v
        w.placeID = "auto"
        try store.upsertVisit(w)
        try EditService(store: store).setVisitPlaceUnspecified(v.id)
        let after = try #require(try store.visit(v.id))
        #expect(after.placeID == "auto")
        #expect(after.placeStatus == .unspecified)
    }

    /// An unnamed place that counts as saved only because another visit confirmed it is offered by recall, so
    /// rejecting it on an automatically matched visit must detach that visit too (review on #106).
    @Test func noneOfTheseDetachesFromAPlaceConfirmedElsewhere() throws {
        let (store, v) = try seededStore()
        let edit = EditService(store: store)
        let other = Visit(placeID: "auto", arrival: Trajectory.date("2026-10-02 09:00"),
                          departure: Trajectory.date("2026-10-02 10:00"), coordinate: Philly.penn)
        try store.upsertVisit(other)
        try edit.confirm(visitID: other.id)                         // "Looks right": "auto" is now a saved place
        var w = v
        w.placeID = "auto"
        try store.upsertVisit(w)                                    // this visit was matched to it automatically
        #expect(try store.recallCandidates(near: v.coordinate).contains { $0.id == "auto" })

        try edit.setVisitPlaceUnspecified(v.id)
        let after = try #require(try store.visit(v.id))
        #expect(after.placeStatus == .unspecified)
        #expect(after.placeID != "auto")
        #expect(try store.visits(atPlace: "auto").map(\.id) == [other.id])
    }

    @Test func emptyWhenNothingIsSavedNearby() throws {
        let store = try TravelStore.inMemory()
        #expect(try store.recallCandidates(near: Philly.penn).isEmpty)
    }

    @Test func unitIsSavedAuditedAndExported() throws {
        let (store, v) = try seededStore()
        var p = try #require(try store.place("cafe"))
        p.unit = "  Ground floor "
        try EditService(store: store).updatePlace(p)
        #expect(try store.place("cafe")?.unit == "Ground floor")
        #expect(try store.auditLog(entityID: "cafe").contains { $0.field == "unit" })
        try EditService(store: store).setVisitPlace(v.id, placeID: "cafe")

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hht-recall-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let folder = try Exporter(store: store).exportBundle(to: dir)
        let places = try String(contentsOf: folder.appendingPathComponent("places.csv"), encoding: .utf8)
        #expect(places.components(separatedBy: "\n").first?.contains(",unit,") == true)
        #expect(places.contains("Ground floor"))
        let visits = try String(contentsOf: folder.appendingPathComponent("visits.csv"), encoding: .utf8)
        let header = visits.components(separatedBy: "\n").first ?? ""
        #expect(header.contains("place_unit") && header.contains("place_status"))
        #expect(visits.contains("confirmed"))
    }

    /// A v6 database upgrades: visits whose place the user set start out confirmed, the rest stay auto.
    @Test func upgradesV6Database() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("hht-v6-\(UUID().uuidString).sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        do {
            let db = try SQLiteConnection(path: path)
            for v in 0..<6 { try db.execute(Schema.migrations[v]); try db.setUserVersion(v + 1) }
            try db.run("""
                INSERT INTO places(id, name, lat, lon, radius_m, favorite, source, created_at, updated_at)
                VALUES ('p', 'Lab', 39.95, -75.19, 80, 0, 'manual', 0, 0)
                """)
            for (id, source) in [("a", "inferred"), ("b", "inferred"), ("m", "manual")] {
                try db.run("""
                    INSERT INTO visits(id, place_id, arrival_ts, lat, lon, source, created_at, updated_at)
                    VALUES (?, 'p', 0, 39.95, -75.19, ?, 0, 0)
                    """, id, source)
            }
            try db.run("""
                INSERT INTO audit_log(ts, entity_type, entity_id, action, field) VALUES (0, 'visit', 'b', 'set_place', 'place_id')
                """)
        }
        let store = try TravelStore(path: path)
        #expect(store.schemaVersion == Schema.migrations.count)
        #expect(try store.visit("a")?.placeStatus == .auto)
        #expect(try store.visit("b")?.placeStatus == .confirmed)
        #expect(try store.visit("m")?.placeStatus == .confirmed)
        #expect(try store.place("p")?.unit == nil)
    }

    // MARK: - Today's place review (issue #116)

    @Test func reviewAsksWhenSavedPlacesLeaveDoubt() throws {
        let (store, v) = try seededStore()
        let c = try store.recallCandidates(near: v.coordinate)
        #expect(PlaceRecall.needsReview(v, candidates: c))                          // two floors of one building
        var unsaved = v
        unsaved.placeID = "auto"
        #expect(PlaceRecall.needsReview(unsaved, candidates: c))                    // matched past saved places nearby
    }

    @Test func reviewSkipsHighConfidenceAndSettledVisits() throws {
        let (store, v) = try seededStore()
        let c = try store.recallCandidates(near: v.coordinate)
        #expect(!PlaceRecall.needsReview(v, candidates: c.filter { $0.id == "f2" }))  // the only saved place near
        #expect(!PlaceRecall.needsReview(v, candidates: []))
        var ongoing = v
        ongoing.departure = nil
        #expect(!PlaceRecall.needsReview(ongoing, candidates: c))
        var unspecified = v
        unspecified.placeStatus = .unspecified
        #expect(!PlaceRecall.needsReview(unspecified, candidates: c))
    }

    @Test func reviewSkipsHomeOrWorkRecognisedAgainAndAgain() {
        let home = Place(id: "home", name: "Home", coordinate: Philly.home, radius: 80, category: .home, source: .manual)
        let gym = Place(id: "gym", name: "Gym", coordinate: Philly.home, radius: 60, category: .gym, source: .manual)
        let v = Visit(placeID: "home", arrival: Trajectory.date("2026-10-01 18:00"),
                      departure: Trajectory.date("2026-10-01 23:00"), coordinate: Philly.home)
        let gymNear = PlaceRecall.Candidate(place: gym, distance: 4, visitCount: 1)
        #expect(!PlaceRecall.needsReview(v, candidates: [PlaceRecall.Candidate(place: home, distance: 4, visitCount: 3), gymNear]))
        #expect(PlaceRecall.needsReview(v, candidates: [PlaceRecall.Candidate(place: home, distance: 4, visitCount: 2), gymNear]))
    }

    @Test func confirmingFromReviewUpdatesThatVisitAndEndsItsPrompt() throws {
        let (store, v) = try seededStore()
        let other = Visit(placeID: "f2", arrival: Trajectory.date("2026-10-02 09:00"),
                          departure: Trajectory.date("2026-10-02 10:00"), coordinate: v.coordinate)
        try store.upsertVisit(other)
        try EditService(store: store).setVisitPlace(v.id, placeID: "f5")
        let after = try #require(try store.visit(v.id))
        #expect(after.placeID == "f5" && after.placeStatus == .confirmed)
        #expect(!PlaceRecall.needsReview(after, candidates: try store.recallCandidates(near: after.coordinate)))
        let untouched = try #require(try store.visit(other.id))
        #expect(untouched.placeID == "f2" && untouched.placeStatus == .auto)
        #expect(PlaceRecall.needsReview(untouched, candidates: try store.recallCandidates(near: untouched.coordinate)))
    }
}
