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
}
