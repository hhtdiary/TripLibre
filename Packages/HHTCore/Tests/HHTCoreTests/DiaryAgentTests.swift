import Foundation
import Testing
@testable import HHTCore

private let t0 = Trajectory.date("2026-10-21 08:00")

private func visit(_ id: String, at minutes: Double, for dwell: Double, place: String? = nil) -> Visit {
    Visit(id: id, placeID: place, arrival: t0.addingTimeInterval(minutes * 60),
          departure: t0.addingTimeInterval((minutes + dwell) * 60), coordinate: Philly.home)
}

private func trip(_ id: String = "t", km: Double = 4, minutes: Double = 16, mode: TravelMode = .bus,
                  confidence: Double = 0.9) -> Trip {
    Trip(id: id, originVisitID: "a", destinationVisitID: "b", departure: t0, arrival: t0.addingTimeInterval(minutes * 60),
         distance: km * 1000, modeAuto: mode, modeConfidence: confidence)
}

@Suite("Diary agent")
struct DiaryAgentTests {

    @Test func recallAsksOnlyAboutUntouchedUnnamedLongStops() {
        let named = Place(id: "home", name: "Home", coordinate: Philly.home, radius: 50)
        var answered = visit("answered", at: 300, for: 40)
        answered.purpose = .meal
        var edited = visit("edited", at: 400, for: 40)
        edited.userStatus = .edited
        var ongoing = visit("ongoing", at: 500, for: 0)
        ongoing.departure = nil
        let visits = [visit("long", at: 200, for: 38), visit("short", at: 100, for: 4), visit("overnight", at: 600, for: 30 * 60),
                      visit("home", at: 0, for: 60, place: "home"), answered, edited, ongoing]
        let asked = DiaryAgent.recallCandidates(visits: visits, places: ["home": named], now: t0.addingTimeInterval(86_400))
        #expect(asked.map(\.id) == ["long"])
    }

    @Test func summaryChainsStopsAndLegsInTimeOrder() {
        let home = Place(id: "home", name: "Home", coordinate: Philly.home, radius: 50)
        var leg = trip()
        leg.departure = t0.addingTimeInterval(60 * 60)
        let s = DiaryAgent.summarize(visits: [visit("x", at: 90, for: 30), visit("h", at: 0, for: 60, place: "home")],
                                     trips: [leg], places: ["home": home], asking: ["x"], label: { _ in "?" })
        #expect(s.chain == [.stop(label: "Home", askingVisitID: nil), .leg(.bus), .stop(label: "?", askingVisitID: "x")])
        #expect(s.trips == 1 && s.places == 2 && s.distance == 4000)
    }

    @Test func habitBeatsTheClassifier() throws {
        let p = try #require(DiaryAgent.modeProposal(for: trip(), history: [.bicycle, .bicycle, .bus, .bicycle]))
        #expect(p.current == .bus && p.proposed == .bicycle)
        #expect(p.reasons.first == .habit(mode: .bicycle, count: 3, of: 4))
    }

    @Test func noProposalWithoutAClearHabitOrDoubt() {
        // one past correction is not a habit, and a split history is not a majority
        #expect(DiaryAgent.modeProposal(for: trip(), history: [.bicycle]) == nil)
        #expect(DiaryAgent.modeProposal(for: trip(), history: [.bicycle, .bicycle, .walk, .walk]) == nil)
        // the habit already matches
        #expect(DiaryAgent.modeProposal(for: trip(), history: [.bus, .bus]) == nil)
        // the user already reviewed the trip
        var reviewed = trip()
        reviewed.userStatus = .confirmed
        #expect(DiaryAgent.modeProposal(for: reviewed, history: [.bicycle, .bicycle]) == nil)
    }

    @Test func doubtfulTripAsksTheUserToPick() throws {
        let p = try #require(DiaryAgent.modeProposal(for: trip(confidence: 0.3), history: []))
        #expect(p.proposed == nil)
        #expect(p.reasons.first == .lowConfidence(0.3))
    }

    @Test func habitTiesGoToTheMostRecent() {
        #expect(DiaryAgent.habit([.walk, .bicycle, .bicycle, .walk, .walk, .bicycle]) == nil)  // 50 %: not a majority
        #expect(DiaryAgent.habit([.walk, .walk, .bicycle]).map(\.0) == .walk)
    }

    @Test func questionsRouteToTopics() {
        #expect(DiaryAgent.topic(for: "How has my commute changed since September?") == .modeShare)
        #expect(DiaryAgent.topic(for: "How far did I bike this month?") == .distance)
        #expect(DiaryAgent.topic(for: "Where do I spend the most time?") == .places)
        #expect(DiaryAgent.topic(for: "How many trips did I make?") == .trips)
        #expect(DiaryAgent.topic(for: "What's the weather?") == nil)
    }

    @Test func answerComparesTwoEqualPeriods() throws {
        let store = try TravelStore(path: ":memory:")
        let a = try DiaryAgent.answer(.trips, store: store, now: t0, days: 30)
        #expect(a.current.range.start == a.previous.range.end.addingTimeInterval(0.001))
        #expect(a.current.trips == 0 && a.previous.trips == 0)
    }
}
