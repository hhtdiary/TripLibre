import Foundation
import Testing
@testable import HHTCore

private let coffee = Coordinate(39.9524, -75.1790)    // on the walk from Center City to Penn

/// Home → 3-minute coffee pickup on the way → Penn. Too short for the stay detector on its own.
private func coffeeRun() -> (Trajectory, arrive: Date, leave: Date) {
    var tr = Trajectory(start: Trajectory.date("2026-09-16 07:00"), at: Philly.home)
    tr.stay(minutes: 60)
    tr.move(to: coffee, speed: 1.4, activity: .walking)
    let arrive = tr.t
    tr.stay(minutes: 3, denseMinutes: 3, drift: 8)
    let leave = tr.t
    tr.move(to: Philly.penn, speed: 1.4, activity: .walking)
    tr.stay(minutes: 120)
    return (tr, arrive, leave)
}

private func run(_ tr: Trajectory, stamps: [Stamp] = [], now: Date? = nil) throws -> (TravelStore, [Visit], [Trip]) {
    let store = try makeStore(tr)
    for s in stamps { try store.insertStamp(s) }
    try InferenceEngine(store: store).processNew(now: now ?? tr.t.addingTimeInterval(60))
    return (store, try store.allVisits(), try store.allTrips(withSegments: true))
}

private func minutes(_ a: Date, _ b: Date) -> Double { abs(a.timeIntervalSince(b)) / 60 }

@Suite("Self-reported stamps (issue #32)")
struct StampTests {

    @Test func stampStoresOnlyACoarseLocation() {
        let t = Trajectory.date("2026-09-16 08:00")
        let precise = Coordinate(39.952_437, -75.179_051)
        let s = Stamp.make(at: t, fix: precise, fixAccuracy: 12, fixTime: t.addingTimeInterval(-20))
        #expect(s.coordinate == Coordinate(39.952, -75.179))
        #expect(s.timestamp == t)
        #expect(Geo.distance(s.coordinate!, precise) <= s.uncertainty!)     // the truth is inside the stated radius
        #expect(s.uncertainty! > 12 + 50)                                   // accuracy + rounding cell + drift
        #expect(s.fixAge == 20)

        // poor GPS still gives a valid stamp, just a vaguer one
        let poor = Stamp.make(at: t, fix: precise, fixAccuracy: 1_500, fixTime: t)
        #expect(poor.coordinate != nil && poor.uncertainty! > 1_500)
        // a stale fix or none at all: the stamp is saved with its time only
        let stale = Stamp.make(at: t, fix: precise, fixAccuracy: 10, fixTime: t.addingTimeInterval(-3_600))
        #expect(stale.coordinate == nil && stale.uncertainty == nil)
        let none = Stamp.make(at: t, fix: nil, fixAccuracy: nil, fixTime: nil)
        #expect(none.coordinate == nil && none.timestamp == t)
    }

    @Test func passiveInferenceMissesTheShortStop() throws {
        let (tr, _, _) = coffeeRun()
        let (_, visits, trips) = try run(tr)
        #expect(visits.count == 2)
        #expect(trips.count == 1)
    }

    @Test func unmatchedStampBecomesAShortStop() throws {
        let (tr, arrive, leave) = coffeeRun()
        let tap = arrive.addingTimeInterval(90)
        let fix = tr.points.last { $0.timestamp <= tap }!
        let stamp = Stamp.make(at: tap, fix: fix.coordinate, fixAccuracy: fix.horizontalAccuracy, fixTime: fix.timestamp)
        let (store, visits, trips) = try run(tr, stamps: [stamp])

        #expect(visits.count == 3)
        #expect(trips.count == 2)
        let stop = visits[1]
        // the surrounding fixes, not the coarse tap location, place the stop and its times
        #expect(Geo.distance(stop.coordinate, coffee) < 30)
        #expect(minutes(stop.arrival, arrive) < 2)
        #expect(minutes(stop.departure!, leave) < 2)
        #expect(stop.source == .inferred && stop.userStatus == .auto)
        #expect(stop.autoConfidence == InferenceConfig.default.stampStayConfidence)
        #expect(trips[0].destinationVisitID == stop.id && trips[1].originVisitID == stop.id)
        #expect(try store.stamp(stamp.id)?.visitID == stop.id)
        // the stamp itself is untouched apart from the link
        let saved = try store.stamp(stamp.id)!
        #expect(saved.coordinate == stamp.coordinate && abs(saved.timestamp.timeIntervalSince(stamp.timestamp)) < 0.001)
    }

    @Test func stampWithoutLocationStillPlacesTheStop() throws {
        let (tr, arrive, _) = coffeeRun()
        let stamp = Stamp.make(at: arrive.addingTimeInterval(60), fix: nil, fixAccuracy: nil, fixTime: nil)
        let (store, visits, _) = try run(tr, stamps: [stamp])
        #expect(visits.count == 3)
        #expect(Geo.distance(visits[1].coordinate, coffee) < 30)
        #expect(try store.stamp(stamp.id)?.visitID == visits[1].id)
    }

    @Test func stampAtADetectedVisitAttachesWithoutAddingAStop() throws {
        var tr = Trajectory(start: Trajectory.date("2026-09-16 07:00"), at: Philly.home)
        tr.stay(minutes: 60)
        tr.move(to: Philly.penn, speed: 1.4, activity: .walking)
        let arrive = tr.t
        tr.stay(minutes: 120)
        // tapped from a desk at Penn, the fix 400 m off indoors
        let off = Geo.unproject((400, 0), origin: Philly.penn)
        let stamp = Stamp.make(at: arrive.addingTimeInterval(30 * 60), fix: off, fixAccuracy: 400,
                               fixTime: arrive.addingTimeInterval(29 * 60))
        let (store, visits, trips) = try run(tr, stamps: [stamp])
        #expect(visits.count == 2)
        #expect(trips.count == 1)
        #expect(try store.stamp(stamp.id)?.visitID == visits[1].id)
        #expect(Geo.distance(visits[1].coordinate, Philly.penn) < 30)     // the stamp didn't move the visit
    }

    @Test func stampContradictedBySensorsStaysUnmatched() throws {
        var tr = Trajectory(start: Trajectory.date("2026-09-16 07:00"), at: Philly.home)
        tr.stay(minutes: 60)
        tr.move(to: Philly.penn, speed: 1.4, activity: .walking)
        let arrive = tr.t
        tr.stay(minutes: 120)
        // a stamp claiming to be 3 km away while the phone sat at Penn
        let stamp = Stamp(timestamp: arrive.addingTimeInterval(45 * 60), coordinate: Philly.grocery.offset(3_000), uncertainty: 80)
        let (store, visits, _) = try run(tr, stamps: [stamp])
        #expect(visits.count == 2)
        #expect(try store.stamp(stamp.id)?.visitID == nil)
    }

    @Test func stampInADataGapUsesItsCoarseLocation() throws {
        var tr = Trajectory(start: Trajectory.date("2026-09-16 07:00"), at: Philly.home)
        tr.stay(minutes: 60)
        tr.move(to: Philly.grocery, speed: 1.4, activity: .walking, noGPS: true)   // phone silent the whole way
        let tap = tr.t
        tr.gap(minutes: 4)
        tr.move(to: Philly.penn, speed: 1.4, activity: .walking, noGPS: true)
        tr.stay(minutes: 120)
        let stamp = Stamp.make(at: tap, fix: Philly.grocery, fixAccuracy: 65, fixTime: tap)
        let (store, visits, _) = try run(tr, stamps: [stamp])
        #expect(visits.count == 3)
        #expect(visits[1].coordinate == stamp.coordinate)
        #expect(visits[1].pointCount == 0)
        #expect(visits[1].duration() >= InferenceConfig.default.stampMinStayDuration)
        #expect(try store.stamp(stamp.id)?.visitID == visits[1].id)
    }

    @Test func stampStopIsStableAcrossRuns() throws {
        let (tr, arrive, _) = coffeeRun()
        let store = try makeStore(tr)
        let stamp = Stamp.make(at: arrive.addingTimeInterval(60), fix: coffee, fixAccuracy: 20, fixTime: arrive)
        try store.insertStamp(stamp)
        let engine = InferenceEngine(store: store)
        try engine.processNew(now: tr.t)
        let first = try store.allVisits()
        try engine.process(from: tr.points.first!.timestamp, to: tr.t, now: tr.t.addingTimeInterval(120))
        let second = try store.allVisits()
        #expect(first.map(\.id) == second.map(\.id))
        #expect(try store.stamp(stamp.id)?.visitID == second[1].id)
    }

    @Test func deletingTheStampOrItsStopWins() throws {
        let (tr, arrive, _) = coffeeRun()
        let stamp = Stamp.make(at: arrive.addingTimeInterval(60), fix: coffee, fixAccuracy: 20, fixTime: arrive)
        let (store, visits, _) = try run(tr, stamps: [stamp])
        #expect(visits.count == 3)
        let engine = InferenceEngine(store: store)
        let edit = EditService(store: store)
        let start = tr.points.first!.timestamp, now = tr.t.addingTimeInterval(120)

        // "this wasn't a stop": the user's deletion beats the stamp on every later run
        try edit.deleteVisit(visits[1].id)
        try engine.process(from: start, to: tr.t, now: now)
        #expect(try store.allVisits().count == 2)
        #expect(try store.stamp(stamp.id)?.visitID == nil)

        // withdrawing the stamp itself also removes the stop it alone produced
        let (store2, _, _) = try run(tr, stamps: [stamp])
        try EditService(store: store2).deleteStamp(stamp.id)
        try InferenceEngine(store: store2).process(from: start, to: tr.t, now: now)
        #expect(try store2.allVisits().count == 2)
        #expect(try store2.stamps(from: .distantPast, to: .distantFuture).isEmpty)
        #expect(try store2.auditLog(entityID: stamp.id).map(\.action) == ["delete"])
    }

    @Test func stampWhileStillThereKeepsTheStopOpen() throws {
        var tr = Trajectory(start: Trajectory.date("2026-09-16 07:00"), at: Philly.home)
        tr.stay(minutes: 60)
        tr.move(to: coffee, speed: 1.4, activity: .walking)
        let arrive = tr.t
        tr.stay(minutes: 2, denseMinutes: 2, drift: 8)
        let stamp = Stamp.make(at: arrive.addingTimeInterval(60), fix: coffee, fixAccuracy: 15, fixTime: arrive)
        let (store, visits, trips) = try run(tr, stamps: [stamp], now: tr.t.addingTimeInterval(20))
        #expect(visits.count == 2)
        #expect(visits[1].departure == nil)
        #expect(trips.count == 1)
        #expect(try store.stamp(stamp.id)?.visitID == visits[1].id)
    }

    @Test func shortStopKeepsItsMinimumNextToAStay() {
        let cfg = InferenceConfig.default
        let anchoring = StampAnchoring(config: cfg)
        let t0 = Trajectory.date("2026-09-16 08:00")
        let prev = DetectedStay(start: t0, end: t0.addingTimeInterval(1_800), centroid: Philly.home, pointCount: 10, confidence: 0.9)
        // tapped 10 s after the previous stay ended, nothing after it: the clipped padding moves to the far side
        let tap = prev.end!.addingTimeInterval(10)
        let stamp = Stamp(timestamp: tap, coordinate: coffee, uncertainty: 80)
        let s = anchoring.shortStay(for: stamp, among: [prev], points: [], now: tap.addingTimeInterval(3_600))!
        #expect(s.start > prev.end!)
        #expect(abs(s.end!.timeIntervalSince(s.start) - cfg.stampMinStayDuration) < 0.001)

        // squeezed between two stays 40 s apart: it fills the gap and overlaps neither
        let next = DetectedStay(start: prev.end!.addingTimeInterval(40), end: nil, centroid: Philly.penn, pointCount: 5, confidence: 0.9)
        let squeezed = anchoring.shortStay(for: stamp, among: [prev, next], points: [], now: tap.addingTimeInterval(3_600))!
        #expect(squeezed.start > prev.end! && squeezed.end! < next.start)
        #expect(squeezed.end!.timeIntervalSince(squeezed.start) >= 37)
    }

    @Test func addStampThroughEditServiceIsAudited() throws {
        let store = try TravelStore.inMemory()
        let t = Trajectory.date("2026-09-16 08:00")
        let s = try EditService(store: store).addStamp(at: t, fix: coffee, fixAccuracy: 10, fixTime: t)
        #expect(try store.stamps(from: t, to: t).map(\.id) == [s.id])
        #expect(try store.auditLog(entityID: s.id).map(\.action) == ["create"])
        try EditService(store: store).setNotes(stampID: s.id, "  oat flat white ")
        #expect(try store.stamp(s.id)?.note == "oat flat white")
        #expect(store.schemaVersion >= 3)
    }

    /// A widget link delivered twice, or a double tap, must not leave two stamps (issue #47, phase 2).
    @Test func stampOnceIgnoresARepeatTap() throws {
        let store = try TravelStore.inMemory()
        let edit = EditService(store: store)
        let t = Trajectory.date("2026-09-16 08:00")
        let first = try edit.stampOnce(at: t, fix: coffee, fixAccuracy: 10, fixTime: t)
        let again = try edit.stampOnce(at: t.addingTimeInterval(5), fix: coffee, fixAccuracy: 10, fixTime: t)
        #expect(first.isNew && !again.isNew)
        #expect(again.stamp.id == first.stamp.id)
        #expect(try store.stamps(from: t, to: t.addingTimeInterval(60)).count == 1)

        // past the window, or after an Undo, a tap is a new stamp
        let later = try edit.stampOnce(at: t.addingTimeInterval(EditService.stampRepeatWindow + 1),
                                       fix: nil, fixAccuracy: nil, fixTime: nil)
        #expect(later.isNew)
        try edit.deleteStamp(later.stamp.id)
        let redo = try edit.stampOnce(at: later.stamp.timestamp.addingTimeInterval(2), fix: nil, fixAccuracy: nil, fixTime: nil)
        #expect(redo.isNew && redo.stamp.id != later.stamp.id)
    }
}

private extension Coordinate {
    func offset(_ east: Double) -> Coordinate { Geo.unproject((east, 0), origin: self) }
}
