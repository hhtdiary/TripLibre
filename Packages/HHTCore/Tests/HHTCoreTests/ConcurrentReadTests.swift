import Foundation
import Testing
@testable import HHTCore

/// The diary must stay readable, and the collector must never wait, while inference holds a write transaction.
@Suite("Reads and point writes during a long transaction")
struct ConcurrentReadTests {

    private func fileStore() throws -> (TravelStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hht-read-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (try TravelStore(path: dir.appendingPathComponent("travel.sqlite").path), dir)
    }

    private func point(_ t: TimeInterval) -> RawPoint {
        RawPoint(timestamp: Date(timeIntervalSince1970: t), coordinate: Philly.home, horizontalAccuracy: 10, source: "gps")
    }

    /// Runs `during` while another thread sits inside a write transaction that has already inserted one point.
    private func whileWriting(_ store: TravelStore, _ during: () throws -> Void) throws {
        let inside = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0), done = DispatchSemaphore(value: 0)
        let writer = Thread {
            try? store.db.transaction {
                try store.insertPoint(self.point(2))
                // its own uncommitted write is visible to the transaction itself
                #expect(store.pointCount() == 2)
                inside.signal()
                release.wait()
            }
            done.signal()
        }
        writer.start()
        inside.wait()
        defer { release.signal(); done.wait() }
        try during()
    }

    @Test func fileDatabasesGetAReaderAndMemoryOnesDoNot() throws {
        let (store, dir) = try fileStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(store.db.hasSeparateReader)
        #expect(try !TravelStore.inMemory().db.hasSeparateReader)
    }

    @Test func readsDoNotWaitForAWriteTransaction() throws {
        let (store, dir) = try fileStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        try store.insertPoint(point(1))
        try whileWriting(store) {
            let t0 = Date()
            // the last committed state, without waiting for the writer
            #expect(store.pointCount() == 1)
            #expect(Date().timeIntervalSince(t0) < 1)
        }
        #expect(store.pointCount() == 2)
    }

    @Test func aWriteOutsideATransactionIsReadBackImmediately() throws {
        let (store, dir) = try fileStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        for i in 1...5 {
            try store.insertPoint(point(Double(i)))
            #expect(store.pointCount() == i)
        }
        try store.setMeta("k", "v")
        #expect(store.meta("k") == "v")
    }

    @Test func pointsRecordedDuringATransactionAreQueuedNotLost() throws {
        let (store, dir) = try fileStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(try store.insertPointWithoutWaiting(point(1)))          // idle: written at once
        try whileWriting(store) {
            let t0 = Date()
            let third = try store.insertPointWithoutWaiting(point(3))
            let fourth = try store.insertPointWithoutWaiting(point(4))
            #expect(!third && !fourth)                                   // busy: queued
            #expect(Date().timeIntervalSince(t0) < 1)
        }
        store.waitForDeferredPoints()
        #expect(try store.points(from: .distantPast, to: .distantFuture).map(\.timestamp.timeIntervalSince1970) == [1, 2, 3, 4])
        #expect(try store.insertPointWithoutWaiting(point(5)))          // queue drained: direct again
    }

    @Test func incrementalRunsRememberWhichPointsTheySaw() throws {
        var tr = Trajectory(start: Trajectory.date("2026-03-02 08:00"), at: Philly.home)
        tr.stay(minutes: 60)
        tr.move(to: Philly.penn, speed: 8)
        tr.stay(minutes: 45)
        let store = try makeStore(tr)
        let engine = InferenceEngine(store: store)
        #expect(engine.hasUnseenPoints)
        try engine.processNew(now: tr.t)
        #expect(!engine.hasUnseenPoints)
        try store.insertPoint(RawPoint(timestamp: tr.t, coordinate: Philly.penn, horizontalAccuracy: 10, source: "gps"))
        #expect(engine.hasUnseenPoints)
        // a range reprocess is not an incremental run: it makes no claim about the newest points
        try engine.process(from: tr.t.addingTimeInterval(-600), to: tr.t.addingTimeInterval(-300), now: tr.t)
        #expect(engine.hasUnseenPoints)
    }

    @Test func eraseDropsPointsStillQueued() throws {
        let (store, dir) = try fileStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        try store.insertPoint(point(1))
        let queued = DispatchSemaphore(value: 0), done = DispatchSemaphore(value: 0), holding = DispatchSemaphore(value: 0)
        // the erase runs while the write handle is still held, so it is certain to come before the flush
        let writer = Thread {
            try? store.db.transaction {
                holding.signal()
                queued.wait()
                try store.eraseAll()
            }
            done.signal()
        }
        writer.start()
        holding.wait()
        #expect(try !store.insertPointWithoutWaiting(point(3)))          // queued behind the transaction
        queued.signal()
        done.wait()
        store.waitForDeferredPoints()
        #expect(store.pointCount() == 0)
        #expect(try store.insertPointWithoutWaiting(point(5)))          // later fixes are kept
        #expect(store.pointCount() == 1)
    }

    /// Arriving after a drive with GPS asleep: one fix at the destination, then the stationary marker 3 min later.
    /// The run at that moment sees too short a stop; later checks must still find work to do (Codex review on #124).
    @Test func aSparseArrivalStaysPendingUntilItResolves() throws {
        var tr = Trajectory(start: Trajectory.date("2026-03-02 08:00"), at: Philly.home)
        tr.stay(minutes: 60)
        tr.move(to: Philly.penn, speed: 8, noGPS: true)
        tr.emit(Philly.penn, speed: 0, mode: "moving")
        tr.gap(minutes: 3)
        tr.emit(Philly.penn, speed: 0, mode: "stationary", source: "stationary_marker")
        let store = try makeStore(tr)
        let engine = InferenceEngine(store: store)
        try engine.processNew(now: tr.t)
        #expect(!engine.hasUnseenPoints)
        #expect(try engine.unresolvedTail(now: tr.t) == nil)                    // too little to show
        #expect(try engine.unresolvedTail(now: tr.t, minPoints: 1) != nil)      // but not settled

        let later = tr.t.addingTimeInterval(10 * 60)
        try engine.processNew(now: later)
        let arrived = try store.visits(overlapping: later, later).contains { Geo.distance($0.coordinate, Philly.penn) < 150 }
        #expect(arrived)
        #expect(try engine.unresolvedTail(now: later, minPoints: 1) == nil)
    }
}
