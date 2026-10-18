import Foundation

/// Offline, side-effect-free replay of the production inference engine (issue #46, docs/research/inference-calibration.md).
///
/// Raw points and motion samples go into a fresh in-memory store that holds no places, edits or audit history,
/// so the output is pure machine inference: no human correction can leak in as an input. The same input,
/// config and engine revision always yield the same `ReplayResult` (record IDs are not part of the output).
public enum Replay {
    public enum Mode: Equatable, Sendable {
        /// One `process(from:to:)` over everything, as "Rebuild from raw data" does.
        case batch
        /// Data arrives in steps of `step` seconds and `processNew` runs after each, approximating the live app.
        case streaming(step: TimeInterval)

        public var label: String {
            switch self {
            case .batch: return "batch"
            case .streaming(let s): return "streaming-\(Int(s))s"
            }
        }
    }

    public struct Input: Sendable {
        public var points: [RawPoint]
        public var motion: [MotionSample]
        /// When the source diary last ran inference (its notion of "now"), if known.
        public var recordedUntil: Date?
        public init(points: [RawPoint], motion: [MotionSample], recordedUntil: Date? = nil) {
            self.points = points
            self.motion = motion
            self.recordedUntil = recordedUntil
        }
    }

    /// Reads raw points and motion from a diary database without touching it: the file is copied first and only the copy
    /// is opened (opening runs migrations). Visits, trips, places and edits in the source are ignored.
    public static func loadInput(databaseAt path: String) throws -> Input {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("hht-replay-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let copy = dir.appendingPathComponent("source.sqlite")
        try privateCopy(of: path, to: copy.path)
        let store = try TravelStore(path: copy.path)
        let points = try store.points(from: .distantPast, to: .distantFuture)
        let motion = try store.motion(from: .distantPast, to: .distantFuture)
        return Input(points: points, motion: motion, recordedUntil: store.meta("last_inference_at").flatMap { isoFormatter.date(from: $0) })
    }

    /// Copies a database (and its WAL) to `dest`, writable even when the source is read-only. Only the copy is ever opened.
    static func privateCopy(of path: String, to dest: String) throws {
        let fm = FileManager.default
        for ext in ["", "-wal", "-shm"] where fm.fileExists(atPath: path + ext) {
            try fm.copyItem(atPath: path + ext, toPath: dest + ext)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dest + ext)
        }
    }

    /// Runs the engine. `end` is the replay's "now" (default: the later of the last observation and `recordedUntil`).
    public static func run(_ input: Input, config: InferenceConfig = .default, mode: Mode = .batch,
                           end: Date? = nil) throws -> ReplayResult {
        let points = input.points.sorted { $0.timestamp == $1.timestamp ? ($0.id ?? 0) < ($1.id ?? 0) : $0.timestamp < $1.timestamp }
        let motion = input.motion.sorted { $0.timestamp < $1.timestamp }
        guard let first = points.first?.timestamp else {
            return ReplayResult(mode: mode.label, config: config, pointCount: 0, motionCount: motion.count,
                                start: nil, end: nil, runs: 0, visits: [], trips: [])
        }
        let last = max(points.last!.timestamp, motion.last?.timestamp ?? .distantPast, input.recordedUntil ?? .distantPast)
        let now = end ?? last

        let store = try TravelStore.inMemory()
        let engine = InferenceEngine(store: store, config: config)
        var runs = 0
        switch mode {
        case .batch:
            try store.insertPoints(points.map { var p = $0; p.id = nil; return p })
            try store.insertMotion(motion)
            try engine.process(from: first, to: now, now: now)
            runs = 1
        case .streaming(let step):
            precondition(step > 0, "streaming step must be positive")
            var pi = 0, mi = 0
            var t = first
            while true {
                t = min(t.addingTimeInterval(step), now)
                var batch: [RawPoint] = []
                while pi < points.count && points[pi].timestamp <= t { var p = points[pi]; p.id = nil; batch.append(p); pi += 1 }
                var mBatch: [MotionSample] = []
                while mi < motion.count && motion[mi].timestamp <= t { mBatch.append(motion[mi]); mi += 1 }
                try store.insertPoints(batch)
                try store.insertMotion(mBatch)
                if !batch.isEmpty || t == now {
                    try engine.processNew(now: t)
                    runs += 1
                }
                if t >= now { break }
            }
        }

        let visits = try store.allVisits().filter { !$0.deleted }.sorted { $0.arrival < $1.arrival }
        let trips = try store.trips(overlapping: .distantPast, .distantFuture).filter { !$0.deleted }
            .sorted { $0.departure < $1.departure }
        let visitIndex = Dictionary(uniqueKeysWithValues: visits.enumerated().map { ($0.element.id, $0.offset) })
        return ReplayResult(
            mode: mode.label, config: config, pointCount: points.count, motionCount: motion.count,
            start: first, end: now, runs: runs,
            visits: visits.map {
                .init(arrival: $0.arrival, departure: $0.departure, latitude: $0.coordinate.latitude,
                      longitude: $0.coordinate.longitude, timeZone: $0.timeZone, confidence: $0.autoConfidence,
                      pointCount: $0.pointCount)
            },
            trips: trips.map { t in
                .init(departure: t.departure, arrival: t.arrival,
                      originVisit: t.originVisitID.flatMap { visitIndex[$0] },
                      destinationVisit: t.destinationVisitID.flatMap { visitIndex[$0] },
                      distance: t.distance.rounded(toPlaces: 1), mode: t.modeAuto?.rawValue ?? "unknown",
                      modeConfidence: t.modeConfidence, hasGap: t.hasGap, confidence: t.autoConfidence,
                      segments: t.segments.sorted { $0.sequence < $1.sequence }.map {
                          .init(start: $0.start, end: $0.end, mode: $0.modeAuto?.rawValue ?? "unknown",
                                modeConfidence: $0.modeConfidence, distance: $0.distance.rounded(toPlaces: 1))
                      })
            })
    }

    /// `InferenceConfig.default` with any keys of a (possibly partial) JSON object applied on top.
    public static func config(overridingWith json: Data?) throws -> InferenceConfig {
        guard let json else { return .default }
        let base = try JSONSerialization.jsonObject(with: JSONEncoder().encode(InferenceConfig.default)) as! [String: Any]
        guard let patch = try JSONSerialization.jsonObject(with: json) as? [String: Any] else {
            throw ReplayError.badConfig("config must be a JSON object")
        }
        if let unknown = patch.keys.first(where: { base[$0] == nil }) { throw ReplayError.badConfig("unknown config key '\(unknown)'") }
        let merged = base.merging(patch) { _, new in new }
        return try JSONDecoder().decode(InferenceConfig.self, from: JSONSerialization.data(withJSONObject: merged))
    }
}

extension Replay {
    /// Release check for the reprocessing contract on a real diary: on a private copy (the source is never opened),
    /// re-run inference over everything and report every human-touched visit or trip that changed or disappeared.
    public struct ReinferenceCheck: Codable, Equatable, Sendable {
        public var lockedVisits = 0
        public var lockedTrips = 0
        public var deletedLockedVisits = 0
        public var changedVisits: [String] = []     // "<arrival ISO>: field old → new" (times only, no coordinates)
        public var changedTrips: [String] = []
        public var missingVisits: [String] = []
        public var missingTrips: [String] = []
        public var report: String = ""
        public var passed: Bool { changedVisits.isEmpty && changedTrips.isEmpty && missingVisits.isEmpty && missingTrips.isEmpty }
    }

    public static func reinferenceCheck(databaseAt path: String) throws -> ReinferenceCheck {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("hht-reinfer-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let copy = dir.appendingPathComponent("copy.sqlite").path
        try privateCopy(of: path, to: copy)
        let store = try TravelStore(path: copy)
        let lockedV = try store.db.query("SELECT * FROM visits WHERE user_status != 'auto'").map(TravelStore.visit)
        let lockedT = try store.trips(overlapping: .distantPast, .distantFuture, includeDeleted: true).filter { $0.userStatus.isLocked }
        let engine = InferenceEngine(store: store)
        // through the newest raw fix too: points collected after the app's last run belong in a full rebuild
        guard let end = [engine.lastRunAt, store.lastPoint()?.timestamp].compactMap({ $0 }).max() else { return ReinferenceCheck() }
        guard let first = store.firstPointDate() else { return ReinferenceCheck() }
        let start = min(first, lockedV.map(\.arrival).min() ?? first)
        let r = try engine.process(from: start, to: end, now: end)

        var out = ReinferenceCheck(lockedVisits: lockedV.count, lockedTrips: lockedT.count,
                                   deletedLockedVisits: lockedV.filter(\.deleted).count)
        out.report = "points \(r.pointsConsidered), visits +\(r.visitsCreated) ~\(r.visitsUpdated) -\(r.visitsRemoved), trips +\(r.tripsCreated) -\(r.tripsRemoved)"
        let afterV = Dictionary(uniqueKeysWithValues: try store.db.query("SELECT * FROM visits").map(TravelStore.visit).map { ($0.id, $0) })
        let afterT = Dictionary(uniqueKeysWithValues: try store.trips(overlapping: .distantPast, .distantFuture, includeDeleted: true).map { ($0.id, $0) })
        func t(_ d: Date?) -> String { iso(d) ?? "open" }
        for v in lockedV {
            guard let a = afterV[v.id] else { out.missingVisits.append(t(v.arrival)); continue }
            var diffs: [String] = []
            if a.arrival != v.arrival { diffs.append("arrival \(t(v.arrival)) → \(t(a.arrival))") }
            // an open locked visit may legitimately receive a departure; anything else is a change
            if a.departure != v.departure && v.departure != nil { diffs.append("departure \(t(v.departure)) → \(t(a.departure))") }
            if a.deleted != v.deleted { diffs.append("deleted \(v.deleted) → \(a.deleted)") }
            if a.placeID != v.placeID { diffs.append("place changed") }
            if a.userStatus != v.userStatus { diffs.append("status \(v.userStatus.rawValue) → \(a.userStatus.rawValue)") }
            if !diffs.isEmpty { out.changedVisits.append("\(t(v.arrival)): " + diffs.joined(separator: "; ")) }
        }
        for v in lockedT {
            guard let a = afterT[v.id] else { out.missingTrips.append(t(v.departure)); continue }
            var diffs: [String] = []
            if a.departure != v.departure || a.arrival != v.arrival { diffs.append("times \(t(v.departure))–\(t(v.arrival)) → \(t(a.departure))–\(t(a.arrival))") }
            if a.modeUser != v.modeUser { diffs.append("mode_user \(v.modeUser?.rawValue ?? "nil") → \(a.modeUser?.rawValue ?? "nil")") }
            if a.deleted != v.deleted { diffs.append("deleted \(v.deleted) → \(a.deleted)") }
            if a.originVisitID != v.originVisitID || a.destinationVisitID != v.destinationVisitID { diffs.append("endpoints relinked") }
            if a.segments.map(\.modeUser) != v.segments.map(\.modeUser) || a.segments.count != v.segments.count { diffs.append("segments changed") }
            if !diffs.isEmpty { out.changedTrips.append("\(t(v.departure)): " + diffs.joined(separator: "; ")) }
        }
        return out
    }
}

public enum ReplayError: Error, CustomStringConvertible {
    case badConfig(String)
    public var description: String {
        switch self { case .badConfig(let s): return "invalid config: \(s)" }
    }
}

/// Machine-readable replay output. Times are UTC ISO-8601; visit references are indices into `visits`.
public struct ReplayResult: Codable, Equatable, Sendable {
    public struct VisitOut: Codable, Equatable, Sendable {
        public var arrival: Date
        public var departure: Date?
        public var latitude: Double
        public var longitude: Double
        public var timeZone: String?
        public var confidence: Double?
        public var pointCount: Int?
    }
    public struct SegmentOut: Codable, Equatable, Sendable {
        public var start: Date
        public var end: Date
        public var mode: String
        public var modeConfidence: Double?
        public var distance: Double
    }
    public struct TripOut: Codable, Equatable, Sendable {
        public var departure: Date
        public var arrival: Date
        public var originVisit: Int?
        public var destinationVisit: Int?
        public var distance: Double
        public var mode: String
        public var modeConfidence: Double?
        public var hasGap: Bool
        public var confidence: Double?
        public var segments: [SegmentOut]
    }

    public var mode: String
    public var config: InferenceConfig
    public var pointCount: Int
    public var motionCount: Int
    public var start: Date?
    public var end: Date?
    public var runs: Int
    public var visits: [VisitOut]
    public var trips: [TripOut]

    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }
}
