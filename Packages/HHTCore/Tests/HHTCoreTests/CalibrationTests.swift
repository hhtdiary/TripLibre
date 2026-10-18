import Foundation
import Testing
@testable import HHTCore

/// Regression fixtures for failure classes found by the real-device calibration (issue #46,
/// docs/research/inference-calibration.md), and the offline replay harness itself. All data here is synthetic.
@Suite("Calibration regressions + replay")
struct CalibrationTests {
    private func run(_ traj: Trajectory) throws -> [Visit] {
        let store = try makeStore(traj)
        try InferenceEngine(store: store).processNew(now: traj.t.addingTimeInterval(60))
        return try store.allVisits()
    }

    private func minutes(_ a: Date, _ b: Date) -> Double { abs(a.timeIntervalSince(b)) / 60 }

    private func walkingBouts(_ tr: inout Trajectory, at offsets: [Double], from start: Date, minutes: Double = 2) {
        for o in offsets {
            tr.motion.append(MotionSample(timestamp: start.addingTimeInterval(o * 60), activity: .walking, confidence: 2))
            tr.motion.append(MotionSample(timestamp: start.addingTimeInterval((o + minutes) * 60), activity: .stationary, confidence: 2))
        }
    }

    /// An evening at home with the collector quiet: ten minutes of pottering about in short bouts is not a trip.
    @Test func indoorWalkingDuringLongSilenceKeepsTheStay() throws {
        let start = Trajectory.date("2026-09-15 18:00")
        var tr = Trajectory(start: start, at: Philly.home)
        tr.stay(minutes: 180)
        walkingBouts(&tr, at: [30, 60, 90, 120, 150], from: start)          // 5 × 2 min
        tr.stay(minutes: 30)
        let leave = tr.t
        tr.move(to: Philly.penn, speed: 1.4, activity: .walking)
        tr.stay(minutes: 60)
        let visits = try run(tr)
        #expect(visits.count == 2)
        #expect(minutes(visits[0].arrival, start) < 1)
        #expect(minutes(try #require(visits[0].departure), leave) < 2)
    }

    /// One fix outside the radius (beyond mergeDistance), then the collector goes quiet while motion says stationary, then the next fix
    /// is back inside: GPS drift, not a departure.
    @Test func strayFixBeforeSilenceIsDrift() throws {
        let start = Trajectory.date("2026-09-15 16:00")
        var tr = Trajectory(start: start, at: Philly.home)
        tr.stay(minutes: 20)
        tr.emit(Geo.unproject((200, 0), origin: Philly.home), acc: 16, mode: "moving")
        tr.gap(minutes: 120)
        tr.stay(minutes: 30)
        let leave = tr.t
        tr.move(to: Philly.penn, speed: 1.4, activity: .walking)
        tr.stay(minutes: 30)
        let visits = try run(tr)
        #expect(visits.count == 2)
        #expect(minutes(try #require(visits[0].departure), leave) < 2)
    }

    /// Walking to a building 200 m away while location is silent: the motion log, not the next fix, dates the departure.
    @Test func departureToNearbyPlaceComesFromMotion() throws {
        let start = Trajectory.date("2026-09-15 10:00")
        var tr = Trajectory(start: start, at: Philly.penn)
        tr.stay(minutes: 120)
        walkingBouts(&tr, at: [60], from: start, minutes: 4)                 // the walk over, at 11:00
        tr.here = Geo.unproject((200, 0), origin: Philly.penn)
        tr.stay(minutes: 90)
        let visits = try run(tr)
        #expect(visits.count == 2)
        #expect(minutes(try #require(visits[0].departure), start.addingTimeInterval(60 * 60)) < 1)
    }

    /// The last fix of the walk in lands just outside the core radius, then the collector goes quiet: we had arrived.
    @Test func arrivalBeforeSilenceIsNotTrimmed() throws {
        let start = Trajectory.date("2026-09-15 12:00")
        var tr = Trajectory(start: start, at: Philly.home)
        tr.stay(minutes: 30)
        let place = Geo.unproject((900, 0), origin: Philly.home)
        let door = Geo.unproject((840, 0), origin: Philly.home)
        tr.move(to: door, speed: 1.6, activity: .walking)
        for _ in 0..<3 {                                                   // a few fixes at the door, 60 m out
            tr.emit(door, speed: 0.3, mode: "moving")
            tr.t = tr.t.addingTimeInterval(10)
        }
        let lastWalkingFix = try #require(tr.points.last).timestamp
        tr.motion.append(MotionSample(timestamp: tr.t, activity: .stationary, confidence: 2))
        tr.gap(minutes: 40)
        tr.here = place
        tr.stay(minutes: 60, activity: nil)
        let visits = try run(tr)
        #expect(visits.count == 2)
        #expect(minutes(visits[1].arrival, lastWalkingFix) < 1)
    }

    // MARK: - Replay harness

    private func syntheticDay() -> Trajectory {
        var tr = Trajectory(start: Trajectory.date("2026-09-15 07:00"), at: Philly.home)
        tr.stay(minutes: 60)
        tr.move(to: Philly.penn, speed: 1.4, activity: .walking)
        tr.stay(minutes: 240)
        tr.move(to: Philly.restaurant, speed: 1.4, activity: .walking)
        tr.stay(minutes: 45)
        tr.move(to: Philly.home, speed: 8, activity: .automotive)
        tr.stay(minutes: 120)
        return tr
    }

    @Test func replayIsDeterministicAndLeavesTheSourceUntouched() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hht-replay-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("travel.sqlite").path
        let tr = syntheticDay()
        do {
            let store = try TravelStore(path: path)
            try store.insertPoints(tr.points)
            try store.insertMotion(tr.motion)
            try InferenceEngine(store: store).processNew(now: tr.t)     // the source has its own diary; replay ignores it
        }
        let before = try Data(contentsOf: URL(fileURLWithPath: path))

        let input = try Replay.loadInput(databaseAt: path)
        #expect(input.points.count == tr.points.count)
        let a = try Replay.run(input), b = try Replay.run(input)
        let enc = ReplayResult.encoder()
        #expect(try enc.encode(a) == enc.encode(b))
        #expect(a.visits.count == 4 && a.trips.count == 3)
        #expect(a.trips.allSatisfy { t in t.originVisit.map { $0 < a.visits.count } ?? false })
        let streamed = try Replay.run(input, mode: .streaming(step: 600))
        #expect(streamed.visits.count == a.visits.count && streamed.trips.count == a.trips.count)
        #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == before)
    }

    @Test func partialConfigOverridesOnlyNamedKeys() throws {
        let c = try Replay.config(overridingWith: Data(#"{"gapMovingSeconds": 600}"#.utf8))
        var expected = InferenceConfig.default
        expected.gapMovingSeconds = 600
        #expect(c == expected)
        #expect(throws: ReplayError.self) { try Replay.config(overridingWith: Data(#"{"noSuchKey": 1}"#.utf8)) }
    }

    /// `make calibrate-smoke`: writes a synthetic diary with a known "human" reference for the Python evaluator.
    @Test func writeCalibrationFixture() throws {
        guard let dir = ProcessInfo.processInfo.environment["HHT_CALIBRATION_DIR"] else { return }
        let path = URL(fileURLWithPath: dir).appendingPathComponent("fixture.sqlite").path
        try? FileManager.default.removeItem(atPath: path)
        let store = try TravelStore(path: path)

        var tr = Trajectory(start: Trajectory.date("2026-09-14 00:00"), at: Philly.home)
        var truth: [(arrival: Date, departure: Date, at: Coordinate)] = []
        var modes: [TravelMode] = []
        func stay(_ minutes: Double, _ extra: (inout Trajectory, Date) -> Void = { _, _ in }) {
            let a = tr.t
            tr.stay(minutes: minutes)
            extra(&tr, a)
            truth.append((a, tr.t, tr.here))
        }
        func move(_ to: Coordinate, _ speed: Double, _ act: MotionSample.Activity, _ mode: TravelMode) {
            tr.move(to: to, speed: speed, activity: act); modes.append(mode)
        }
        // day 1: an evening of indoor pottering after a normal commute
        stay(8 * 60)
        move(Philly.penn, 1.4, .walking, .walk)
        stay(4 * 60)
        move(Philly.restaurant, 1.4, .walking, .walk)
        stay(50)
        move(Philly.home, 9, .automotive, .car)
        stay(15 * 60) { tr, a in walkingBouts(&tr, at: [60, 120, 200, 300, 420, 600], from: a) }
        // day 2: a stray drift fix at work, then a walk to a nearby building during a silence
        move(Philly.penn, 1.4, .walking, .walk)
        let pennArrive = tr.t
        tr.stay(minutes: 30)
        tr.emit(Geo.unproject((115, 0), origin: Philly.penn), acc: 16, mode: "moving")
        tr.gap(minutes: 90)
        tr.stay(minutes: 120)
        walkingBouts(&tr, at: [200], from: pennArrive, minutes: 4)
        truth.append((pennArrive, pennArrive.addingTimeInterval(200 * 60), Philly.penn))
        modes.append(.walk)
        let annex = Geo.unproject((220, 0), origin: Philly.penn)
        tr.here = annex
        let annexArrive = pennArrive.addingTimeInterval(204 * 60)
        tr.stay(minutes: 120)
        truth.append((annexArrive, tr.t, annex))
        move(Philly.home, 1.4, .walking, .walk)
        stay(180)

        try store.insertPoints(tr.points)
        try store.insertMotion(tr.motion)
        try store.setMeta("last_inference_at", iso(tr.t))
        var visits: [Visit] = []
        for (i, s) in truth.enumerated() {
            let v = Visit(arrival: s.arrival, departure: i == truth.count - 1 ? nil : s.departure, coordinate: s.at,
                          source: .manual, userStatus: .manual, timeZone: "America/New_York")
            try store.upsertVisit(v)
            visits.append(v)
        }
        for (i, m) in modes.enumerated() {
            let a = visits[i], b = visits[i + 1]
            try store.upsertTrip(Trip(originVisitID: a.id, destinationVisitID: b.id, departure: a.departure!, arrival: b.arrival,
                                      distance: Geo.distance(a.coordinate, b.coordinate), modeAuto: nil, modeConfidence: nil,
                                      modeUser: m, source: .manual, userStatus: .manual, timeZone: "America/New_York"))
        }
        print("calibration fixture written to \(path)")
    }
}
