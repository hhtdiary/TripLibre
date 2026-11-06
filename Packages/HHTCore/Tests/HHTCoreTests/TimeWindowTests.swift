import Foundation
import Testing
@testable import HHTCore

/// Regression tests for issue #101: trip construction locates each trip's fixes by binary search
/// instead of filtering the whole cleaned point array, with identical strict `(dep, arr)` semantics.
@Suite("Time-window point lookup")
struct TimeWindowTests {
    private static let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    private func pt(_ s: Double, id: Int64? = nil, _ c: Coordinate = Philly.home) -> RawPoint {
        RawPoint(id: id, timestamp: Self.t0.addingTimeInterval(s), coordinate: c)
    }
    private func at(_ s: Double) -> Date { Self.t0.addingTimeInterval(s) }

    /// The pre-#101 behaviour, kept as the oracle.
    private func reference(_ pts: [RawPoint], _ a: Date, _ b: Date) -> [RawPoint] {
        pts.filter { $0.timestamp > a && $0.timestamp < b }
    }

    @Test func boundariesAreExclusive() {
        let pts = [0.0, 10, 20, 30, 40].map { pt($0) }
        let got = Array(pts.strictlyBetween(at(10), at(30)))
        #expect(got == [pt(20)])
        #expect(got == reference(pts, at(10), at(30)))
    }

    @Test func emptyWindows() {
        let pts = [0.0, 10, 20].map { pt($0) }
        #expect(pts.strictlyBetween(at(10), at(10)).isEmpty)        // zero-length
        #expect(pts.strictlyBetween(at(20), at(10)).isEmpty)        // inverted
        #expect(pts.strictlyBetween(at(11), at(19)).isEmpty)        // no fix inside
        #expect(pts.strictlyBetween(at(-50), at(-10)).isEmpty)      // before all data
        #expect(pts.strictlyBetween(at(30), at(90)).isEmpty)        // after all data
        #expect(pts.strictlyBetween(at(10), at(20)).isEmpty)        // adjacent fixes, both on the bounds
        #expect([RawPoint]().strictlyBetween(at(0), at(100)).isEmpty)
    }

    @Test func windowCoveringEverything() {
        let pts = [0.0, 10, 20].map { pt($0) }
        #expect(Array(pts.strictlyBetween(at(-1), at(21))) == pts)
    }

    @Test func duplicateTimestampsKeepOrderAndBoundaryRules() {
        // clean() orders equal timestamps by id; the slice must keep that order and treat every duplicate alike
        let pts = [pt(0, id: 1), pt(10, id: 2), pt(10, id: 3), pt(20, id: 4), pt(20, id: 5), pt(20, id: 6), pt(30, id: 7)]
        #expect(Array(pts.strictlyBetween(at(0), at(30))).map(\.id) == [2, 3, 4, 5, 6])
        #expect(Array(pts.strictlyBetween(at(10), at(30))).map(\.id) == [4, 5, 6])
        #expect(Array(pts.strictlyBetween(at(0), at(20))).map(\.id) == [2, 3])
        #expect(pts.strictlyBetween(at(10), at(20)).isEmpty)
    }

    @Test func sparseData() {
        let sparse: [Double] = [0, 3600, 7200 * 3]
        let pts = sparse.map { pt($0) }
        #expect(Array(pts.strictlyBetween(at(1), at(7200 * 3))) == [pt(3600)])
        #expect(Array(pts.strictlyBetween(at(3600), at(7200 * 3 + 1))) == [pt(7200 * 3)])
    }

    @Test func matchesFilterOnRandomWindows() {
        var rng = SplitMix(seed: 101)
        var s = 0.0
        var pts: [RawPoint] = []
        for i in 0..<500 {
            // irregular sampling with frequent duplicates and occasional long gaps
            let r = rng.nextDouble()
            s += r < 0.2 ? 0 : (r < 0.95 ? 1 + 30 * rng.nextDouble() : 3600)
            pts.append(pt(s.rounded(), id: Int64(i)))
        }
        let span = s + 100
        for _ in 0..<2000 {
            // pick bounds that often land exactly on existing timestamps
            func bound() -> Date {
                rng.nextDouble() < 0.5 ? pts[Int(rng.nextDouble() * Double(pts.count))].timestamp
                                       : at((rng.nextDouble() * span - 50).rounded())
            }
            let a = bound(), b = bound()
            #expect(Array(pts.strictlyBetween(a, b)) == reference(pts, a, b))
        }
    }

    @Test func multipleConsecutiveTripsBuildAsBefore() throws {
        // three trips sharing boundary fixes with the visits on either side
        var tr = Trajectory(start: Trajectory.date("2026-09-16 08:00"), at: Philly.home)
        tr.stay(minutes: 30)
        tr.move(to: Philly.penn, speed: 9, activity: .automotive)
        tr.stay(minutes: 60)
        tr.move(to: Philly.restaurant, speed: 1.3, activity: .walking)
        tr.stay(minutes: 30)
        tr.move(to: Philly.home, speed: 9, activity: .automotive)
        tr.stay(minutes: 30)

        let store = try makeStore(tr)
        let engine = InferenceEngine(store: store)
        let clean = StayDetector(config: engine.config).clean(tr.points)
        let motion = MotionTimeline(tr.motion)
        try engine.processNew(now: tr.t.addingTimeInterval(60))
        let visits = try store.allVisits()
        let trips = try store.allTrips(withSegments: true)
        #expect(visits.count == 4)
        #expect(trips.count == 3)

        for i in 1..<visits.count {
            let a = visits[i - 1], b = visits[i]
            let got = try engine.buildTrip(from: a, to: b, points: clean, motion: motion)
            let want = try referenceTrip(engine, from: a, to: b, points: clean, motion: motion)
            #expect(got.departure == want.departure && got.arrival == want.arrival)
            #expect(got.distance == want.distance)
            #expect(got.routePolyline == want.routePolyline)
            #expect(got.hasGap == want.hasGap)
            #expect(got.autoConfidence == want.autoConfidence)
            #expect(got.mode == want.mode)
            #expect(got.segments.map(\.modeAuto) == want.segments.map(\.modeAuto))
            #expect(got.segments.map(\.routePolyline) == want.segments.map(\.routePolyline))
            // and the stored trip from the full run agrees too
            #expect(trips[i - 1].routePolyline == want.routePolyline)
        }
    }

    @Test func tripWithNoInteriorFixesKeepsAnchors() throws {
        let store = try TravelStore.inMemory()
        let engine = InferenceEngine(store: store)
        let a = Visit(arrival: at(0), departure: at(100), coordinate: Philly.home)
        let b = Visit(arrival: at(900), departure: nil, coordinate: Philly.penn)
        // fixes only on the boundaries and outside the trip
        let pts = [pt(50), pt(100), pt(900), pt(950)]
        let got = try engine.buildTrip(from: a, to: b, points: pts, motion: MotionTimeline([]))
        let want = try referenceTrip(engine, from: a, to: b, points: pts, motion: MotionTimeline([]))
        #expect(got.departure == at(100) && got.arrival == at(900))
        #expect(got.routePolyline == want.routePolyline)
        #expect(got.distance == want.distance)
        #expect(got.hasGap == want.hasGap)
        #expect(got.autoConfidence == want.autoConfidence)
    }

    /// The pre-#101 path construction fed through the same classifier, for comparison.
    private func referenceTrip(_ engine: InferenceEngine, from a: Visit, to b: Visit,
                               points: [RawPoint], motion: MotionTimeline) throws -> Trip {
        let dep = a.departure ?? a.arrival
        let arr = b.arrival
        var path = points.filter { $0.timestamp > dep && $0.timestamp < arr }
        path.insert(RawPoint(timestamp: dep, coordinate: a.coordinate, source: "anchor"), at: 0)
        path.append(RawPoint(timestamp: arr, coordinate: b.coordinate, source: "anchor"))
        // buildTrip only depends on the path, so rebuilding from exactly these points must give the same trip
        let only = Array(path.dropFirst().dropLast())
        #expect(only == Array(points.strictlyBetween(dep, arr)))
        return try engine.buildTrip(from: a, to: b, points: only, motion: motion)
    }
}
