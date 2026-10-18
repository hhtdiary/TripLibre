import Foundation

/// Rule-based travel-mode classification and multimodal segmentation (docs/inference.md §4).
public struct ModeClassifier: Sendable {
    public var config: InferenceConfig
    public init(config: InferenceConfig = .default) { self.config = config }

    /// Coarse per-interval movement class before segment-level refinement.
    enum Coarse: String { case walk, run, bike, vehicle, air, still }

    struct Interval {
        var start: Date
        var end: Date
        var from: Coordinate
        var to: Coordinate
        var distance: Double
        var speed: Double
        var coarse: Coarse
        var isGap: Bool
        var goodFix: Bool    // the interval ends on an accurate fix with a valid moving speed (see InferenceConfig)
        var isFix: Bool      // the interval ends on an observed fix, not a synthetic visit anchor
        var duration: TimeInterval { end.timeIntervalSince(start) }
    }

    public struct SegmentResult: Equatable, Sendable {
        public var start: Date
        public var end: Date
        public var mode: TravelMode
        public var confidence: Double
        public var coordinates: [Coordinate]
        public var distance: Double
    }

    /// Split a movement into mode segments. `path` must include the origin and destination anchor points.
    public func segment(path: [RawPoint], motion: MotionTimeline) -> [SegmentResult] {
        guard path.count >= 2 else { return [] }
        var intervals: [Interval] = []
        for i in 1..<path.count {
            let a = path[i - 1], b = path[i]
            let dt = max(1, b.timestamp.timeIntervalSince(a.timestamp))
            let d = Geo.distance(a.coordinate, b.coordinate)
            let v = d / dt
            let mid = a.timestamp.addingTimeInterval(dt / 2)
            // the collector samples every few seconds while moving, so a multi-minute hole is signal loss
            let isGap = dt > config.movingGapThreshold && d > 300
            let good = (b.horizontalAccuracy ?? .infinity) <= config.roadFixMaxAccuracy && (b.speed ?? -1) >= config.roadFixMinSpeed
            intervals.append(Interval(start: a.timestamp, end: b.timestamp, from: a.coordinate, to: b.coordinate,
                                      distance: d, speed: v,
                                      coarse: coarse(speed: v, reported: b.speed, activity: motion.activity(at: mid), isGap: isGap),
                                      isGap: isGap, goodFix: b.source != "anchor" && good, isFix: b.source != "anchor"))
        }
        // "still" intervals (waiting at a stop, red light) join the neighbouring class
        resolveStill(&intervals)

        // run-length encode
        var runs: [[Interval]] = []
        for iv in intervals {
            if let last = runs.last?.last, last.coarse == iv.coarse { runs[runs.count - 1].append(iv) } else { runs.append([iv]) }
        }
        // absorb short runs into the longer neighbour, repeatedly
        var changed = true
        while changed && runs.count > 1 {
            changed = false
            guard let idx = runs.indices.filter({ runDuration(runs[$0]) < config.minSegmentDuration })
                .min(by: { runDuration(runs[$0]) < runDuration(runs[$1]) }) else { break }
            let left = idx > 0 ? idx - 1 : nil
            let right = idx + 1 < runs.count ? idx + 1 : nil
            let target: Int
            switch (left, right) {
            case let (l?, r?): target = runDuration(runs[l]) >= runDuration(runs[r]) ? l : r
            case let (l?, nil): target = l
            case let (nil, r?): target = r
            default: target = idx
            }
            guard target != idx else { break }
            let cls = runs[target][0].coarse
            let moved = runs[idx].map { iv -> Interval in var c = iv; c.coarse = cls; return c }
            if target < idx { runs[target].append(contentsOf: moved) } else { runs[target].insert(contentsOf: moved, at: 0) }
            runs.remove(at: idx)
            // merge now-adjacent equal runs
            var merged: [[Interval]] = []
            for r in runs {
                if let last = merged.last, last[0].coarse == r[0].coarse { merged[merged.count - 1].append(contentsOf: r) } else { merged.append(r) }
            }
            runs = merged
            changed = true
        }

        // a "walk" that covers ground faster than anyone walks is a ride whose fixes were too sparse to show it
        // (underground, with CoreMotion reading the train's vibration as walking)
        var relabelled = false
        for k in runs.indices where runs[k][0].coarse == .walk {
            let disp = Geo.distance(runs[k][0].from, runs[k].last!.to)
            if disp >= config.walkCheckMinDisplacement && disp / max(1, runDuration(runs[k])) > config.walkMaxDisplacementSpeed {
                for i in runs[k].indices { runs[k][i].coarse = .vehicle }
                relabelled = true
            }
        }
        if relabelled {
            var merged: [[Interval]] = []
            for r in runs {
                if let last = merged.last, last[0].coarse == r[0].coarse { merged[merged.count - 1].append(contentsOf: r) } else { merged.append(r) }
            }
            runs = merged
        }

        return runs.map { run in
            var coords = [run[0].from]
            coords.append(contentsOf: run.map { $0.to })
            let dist = run.reduce(0) { $0 + $1.distance }
            let (mode, conf) = refine(run: run, motion: motion)
            return SegmentResult(start: run.first!.start, end: run.last!.end, mode: mode, confidence: conf,
                                 coordinates: coords, distance: dist)
        }
    }

    private func runDuration(_ r: [Interval]) -> TimeInterval { r.reduce(0) { $0 + $1.duration } }

    private func coarse(speed v: Double, reported: Double?, activity: MotionSample.Activity?, isGap: Bool) -> Coarse {
        if v >= config.airMinSpeed { return .air }
        switch activity {
        case .walking?: return v > config.bikeMaxSpeed ? .vehicle : .walk
        case .running?: return v > config.bikeMaxSpeed ? .vehicle : .run
        case .cycling?: return v > 12 ? .vehicle : .bike
        case .automotive?: return .vehicle
        case .stationary?: if v < 0.5 { return .still }
        default: break
        }
        let s = (reported ?? -1) >= 0 && !isGap ? max(v, reported!) : v
        if s < 0.3 { return .still }
        if s <= config.walkMaxSpeed { return .walk }
        if s <= config.bikeMaxSpeed { return isGap ? .vehicle : .bike }
        return .vehicle
    }

    private func resolveStill(_ ivs: inout [Interval]) {
        guard ivs.contains(where: { $0.coarse != .still }) else {
            for i in ivs.indices { ivs[i].coarse = .walk }
            return
        }
        for i in ivs.indices where ivs[i].coarse == .still {
            // nearest non-still neighbour, preferring the following one (waiting precedes boarding)
            var j = i + 1
            while j < ivs.count && ivs[j].coarse == .still { j += 1 }
            if j < ivs.count { ivs[i].coarse = ivs[j].coarse; continue }
            var k = i - 1
            while k >= 0 && ivs[k].coarse == .still { k -= 1 }
            if k >= 0 { ivs[i].coarse = ivs[k].coarse }
        }
    }

    private func percentile(_ xs: [Double], _ p: Double) -> Double {
        guard !xs.isEmpty else { return 0 }
        let s = xs.sorted()
        return s[min(s.count - 1, max(0, Int((Double(s.count - 1) * p).rounded())))]
    }

    /// Turn a coarse run into a specific mode with a confidence in [0, 1].
    private func refine(run: [Interval], motion: MotionTimeline) -> (TravelMode, Double) {
        let dist = run.reduce(0) { $0 + $1.distance }
        let dur = max(1, runDuration(run))
        let avg = dist / dur
        let speeds = run.filter { !$0.isGap }.map { $0.speed }
        let p90 = percentile(speeds, 0.9)
        let gapTime = run.filter { $0.isGap }.reduce(0) { $0 + $1.duration }
        let activity = motion.seconds(from: run.first!.start, to: run.last!.end)
        let covered = activity.values.reduce(0, +)
        let hasMotion = covered > 0
        let automotiveShare = hasMotion ? (activity[.automotive] ?? 0) / covered : 0
        let fixes = run.filter(\.isFix).count
        let goodFixes = run.filter(\.goodFix).count
        let goodShare = fixes > 0 ? Double(goodFixes) / Double(fixes) : 0

        switch run[0].coarse {
        case .walk: return (.walk, hasMotion ? 0.85 : 0.65)
        case .run: return (.run, hasMotion ? 0.8 : 0.5)
        case .bike: return (.bicycle, hasMotion ? 0.75 : 0.4)
        case .air where dist >= config.airMinDistance: return (.airplane, dist > 100_000 ? 0.9 : 0.6)
        case .still: return (.unknown, 0.2)
        case .air, .vehicle:   // a short "air" run is a GPS jump, not a flight
            if avg >= config.airMinSpeed * 0.6 && dist > 150_000 { return (.airplane, 0.75) }
            if dist >= config.intercityMinDistance && p90 >= config.intercityRailMinSpeed && p90 < config.airMinSpeed {
                return (.intercityRail, 0.35)
            }
            // sustained automotive motion with GPS that keeps seeing the vehicle move: a road vehicle, even if the
            // collector left holes in the track. A blackout longer than a data gap could still hide a rail leg: flag it.
            if automotiveShare >= config.roadMinAutomotiveShare && goodFixes >= config.roadMinGoodFixes
                && goodShare >= config.roadMinGoodFixShare {
                let longestHole = run.filter { $0.isGap }.map(\.duration).max() ?? 0
                return (.car, longestHole > config.gapThreshold ? 0.45 : 0.6)
            }
            // long stretches without GPS at urban speeds suggest underground rail
            if gapTime / dur > 0.4 && avg > 4 && avg < 25 && dist < 40_000 { return (.subway, 0.4) }
            // moving at vehicle speed, yet neither CoreMotion nor the GPS sees a road vehicle: underground rail
            if hasMotion && automotiveShare < config.undergroundMaxAutomotiveShare && goodShare < config.undergroundMaxGoodFixShare
                && avg < 25 && dist < 40_000 {
                return (.subway, 0.35)
            }
            return (.car, hasMotion ? 0.5 : 0.4)
        }
    }

    /// HHTS-style main-mode hierarchy: the highest-ranked mode among substantial segments.
    public static let mainModePriority: [TravelMode] = [
        .airplane, .intercityRail, .coach, .ferry, .commuterRail, .subway, .lightRail, .bus, .shuttle,
        .taxi, .carDriver, .carPassenger, .car, .ebike, .bicycle, .scooter, .run, .walk, .other, .unknown,
    ]

    public static func mainMode(_ segments: [(mode: TravelMode, duration: TimeInterval, distance: Double)]) -> TravelMode {
        let substantial = segments.filter { $0.duration >= 120 || $0.distance >= 300 }
        let pool = substantial.isEmpty ? segments : substantial
        for m in mainModePriority where pool.contains(where: { $0.mode == m }) { return m }
        return .unknown
    }
}
