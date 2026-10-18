import Foundation

/// Piecewise-constant motion activity timeline built from CoreMotion samples.
public struct MotionTimeline: Sendable {
    public let samples: [MotionSample]   // sorted by time

    public init(_ samples: [MotionSample]) {
        self.samples = samples.sorted { $0.timestamp < $1.timestamp }
    }

    public var isEmpty: Bool { samples.isEmpty }

    /// Activity in effect at `t` (latest sample at or before t), ignoring low-confidence samples.
    public func activity(at t: Date) -> MotionSample.Activity? {
        var lo = 0, hi = samples.count - 1, found: Int? = nil
        while lo <= hi {
            let mid = (lo + hi) / 2
            if samples[mid].timestamp <= t { found = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        guard var i = found else { return nil }
        while i >= 0 {
            if samples[i].confidence >= 1 { return samples[i].activity }
            i -= 1
        }
        return nil
    }

    /// Seconds spent in each activity within [from, to] (only covered time is counted).
    public func seconds(from: Date, to: Date) -> [MotionSample.Activity: TimeInterval] {
        guard to > from, !samples.isEmpty else { return [:] }
        var out: [MotionSample.Activity: TimeInterval] = [:]
        for (i, s) in samples.enumerated() where s.confidence >= 1 {
            let start = max(s.timestamp, from)
            let end = min(i + 1 < samples.count ? samples[i + 1].timestamp : to, to)
            if end > start { out[s.activity, default: 0] += end.timeIntervalSince(start) }
        }
        return out
    }

    public func movingSeconds(from: Date, to: Date) -> TimeInterval {
        let s = seconds(from: from, to: to)
        return (s[.walking] ?? 0) + (s[.running] ?? 0) + (s[.cycling] ?? 0) + (s[.automotive] ?? 0)
    }

    /// Start of the movement still going on at `to`, walking back over brief non-moving blips (≤ `tolerance`).
    /// nil if the timeline isn't moving at `to`.
    public func movementStart(from: Date, to: Date, tolerance: TimeInterval = 180) -> Date? {
        var start: Date? = nil
        var quiet: TimeInterval = 0
        for i in samples.indices.reversed() where samples[i].timestamp < to && samples[i].confidence >= 1 {
            let s = samples[i]
            let end = min(i + 1 < samples.count ? samples[i + 1].timestamp : to, to)
            if [.walking, .running, .cycling, .automotive].contains(s.activity) {
                start = max(s.timestamp, from); quiet = 0
            } else {
                quiet += end.timeIntervalSince(max(s.timestamp, from))
                if quiet > tolerance { break }
            }
            if s.timestamp <= from { break }
        }
        return start
    }

    /// Bouts of walking/running/cycling/automotive within [from, to], joined across non-moving blips ≤ `tolerance`.
    public func movementBouts(from: Date, to: Date, tolerance: TimeInterval = 180) -> [(start: Date, end: Date)] {
        guard to > from else { return [] }
        var bouts: [(start: Date, end: Date)] = []
        for (i, s) in samples.enumerated() where s.confidence >= 1 {
            let start = max(s.timestamp, from)
            let end = min(i + 1 < samples.count ? samples[i + 1].timestamp : to, to)
            guard end > start, [.walking, .running, .cycling, .automotive].contains(s.activity) else { continue }
            if let last = bouts.last, start.timeIntervalSince(last.end) <= tolerance {
                bouts[bouts.count - 1].end = max(last.end, end)
            } else {
                bouts.append((start, end))
            }
        }
        return bouts
    }

    public func hasCoverage(from: Date, to: Date) -> Bool {
        seconds(from: from, to: to).values.reduce(0, +) > 0
    }
}

/// A stay (stationary cluster) found in the point stream.
public struct DetectedStay: Equatable, Sendable {
    public var start: Date
    /// Estimated departure; nil = still there.
    public var end: Date?
    public var centroid: Coordinate
    public var pointCount: Int
    public var confidence: Double
}

/// Transparent, sequential stay-point detection (see docs/inference.md §2).
public struct StayDetector: Sendable {
    public var config: InferenceConfig
    public init(config: InferenceConfig = .default) { self.config = config }

    /// Drop inaccurate points and isolated GPS jumps.
    public func clean(_ points: [RawPoint]) -> [RawPoint] {
        let sorted = points.sorted { $0.timestamp == $1.timestamp ? ($0.id ?? 0) < ($1.id ?? 0) : $0.timestamp < $1.timestamp }
        var accurate: [RawPoint] = sorted.filter { p in
            let limit = p.source.hasPrefix("visit") ? config.maxVisitEventAccuracy : config.maxHorizontalAccuracy
            return (p.horizontalAccuracy ?? 0) >= 0 && (p.horizontalAccuracy ?? 0) <= limit
        }
        // remove single-point spikes: A → B → C where A→B and B→C are both implausibly fast but A→C is not
        guard accurate.count >= 3 else { return accurate }
        var keep = [Bool](repeating: true, count: accurate.count)
        for i in 1..<(accurate.count - 1) {
            let a = accurate[i - 1], b = accurate[i], c = accurate[i + 1]
            let v1 = Geo.distance(a.coordinate, b.coordinate) / max(1, b.timestamp.timeIntervalSince(a.timestamp))
            let v2 = Geo.distance(b.coordinate, c.coordinate) / max(1, c.timestamp.timeIntervalSince(b.timestamp))
            let v3 = Geo.distance(a.coordinate, c.coordinate) / max(1, c.timestamp.timeIntervalSince(a.timestamp))
            if v1 > config.maxPlausibleSpeed && v2 > config.maxPlausibleSpeed && v3 < config.maxPlausibleSpeed { keep[i] = false }
        }
        accurate = accurate.enumerated().filter { keep[$0.offset] }.map { $0.element }
        return accurate
    }

    /// Was the person plausibly stationary between two times with no location data?
    public func stationaryDuringGap(from: Date, to: Date, lastPoint: RawPoint, motion: MotionTimeline) -> Bool {
        if motion.hasCoverage(from: from, to: to) {
            return motion.movingSeconds(from: from, to: to) < config.gapMovingSeconds
        }
        // No motion data: trust the collector. It only goes quiet deliberately when it believes we're stationary.
        return lastPoint.collectorMode != "moving"
    }

    public func detect(_ rawPoints: [RawPoint], motion: MotionTimeline = MotionTimeline([]), now: Date) -> [DetectedStay] {
        let pts = clean(rawPoints)
        let n = pts.count
        var stays: [DetectedStay] = []
        var i = 0
        while i < n {
            // a fix reporting clear movement cannot start a stay
            if (pts[i].speed ?? 0) > 1.5 { i += 1; continue }
            var memberIdx = [i]
            var centroid = pts[i].coordinate
            var weightSum = weight(pts[i])
            var k = i + 1
            var estimatedEnd: Date? = nil
            var brokeOnMove = false

            func add(_ idx: Int) {
                let w = weight(pts[idx])
                let c = pts[idx].coordinate
                centroid = Coordinate((centroid.latitude * weightSum + c.latitude * w) / (weightSum + w),
                                      (centroid.longitude * weightSum + c.longitude * w) / (weightSum + w))
                weightSum += w
                memberIdx.append(idx)
            }

            while k < n {
                let last = pts[memberIdx.last!]
                let p = pts[k]
                let d = Geo.distance(p.coordinate, centroid)
                let gap = p.timestamp.timeIntervalSince(last.timestamp)
                let isGap = gap > config.gapThreshold

                if d <= config.stayRadius {
                    if isGap && !stationaryDuringGap(from: last.timestamp, to: p.timestamp, lastPoint: last, motion: motion) {
                        // left and came back while we had no data: close the stay here; the loop becomes a trip
                        brokeOnMove = true
                        break
                    }
                    add(k); k += 1
                    continue
                }

                // Outside the radius. Short excursion that returns = drift.
                var m = k + 1
                var returned = false
                while m < n && pts[m].timestamp.timeIntervalSince(p.timestamp) <= config.driftMaxDuration {
                    if Geo.distance(pts[m].coordinate, centroid) <= config.stayRadius { returned = true; break }
                    m += 1
                }
                let established = last.timestamp.timeIntervalSince(pts[memberIdx[0]].timestamp) >= 60
                if returned && !isGap && established {
                    k = m   // skip the drift points
                    continue
                }
                // Drift just before the collector went quiet: a few fixes barely outside, then a stationary silence,
                // then the next fix is back inside. Nobody left; don't end the stay on a stray fix.
                if !returned && established && m < n && m > k,
                   Geo.distance(pts[m].coordinate, centroid) <= config.stayRadius,
                   pts[m].timestamp.timeIntervalSince(pts[m - 1].timestamp) > config.gapThreshold,
                   (k..<m).allSatisfy({ Geo.distance(pts[$0].coordinate, centroid) <= config.mergeMaxExcursionDistance
                                        && (pts[$0].speed ?? 0) <= 1.5 }),
                   !isGap || stationaryDuringGap(from: last.timestamp, to: p.timestamp, lastPoint: last, motion: motion),
                   stationaryDuringGap(from: pts[m - 1].timestamp, to: pts[m].timestamp, lastPoint: pts[m - 1], motion: motion) {
                    k = m
                    continue
                }

                // Real departure.
                if isGap, let b = departureBout(from: last.timestamp, to: p.timestamp, distance: d, motion: motion) {
                    // the walk/ride that got us there shows up in the motion log: that is when we left
                    estimatedEnd = b
                } else if isGap && stationaryDuringGap(from: last.timestamp, to: p.timestamp, lastPoint: last, motion: motion) {
                    // stayed until shortly before the next fix; back off by travel time at a plausible speed
                    let v = max(p.speed ?? 0, Self.plausibleTravelSpeed(distance: d))
                    let travel = min(d / v, gap)
                    estimatedEnd = max(last.timestamp, p.timestamp.addingTimeInterval(-travel))
                } else if isGap, let m = motion.movementStart(from: last.timestamp, to: p.timestamp) {
                    // moved around during a long silence: left when the movement that reached the next fix began
                    estimatedEnd = m
                }
                brokeOnMove = true
                break
            }

            // Trim the approach/departure: members near the radius edge are usually still walking in or out.
            var dists = memberIdx.map { Geo.distance(pts[$0].coordinate, centroid) }
            var median = dists.sorted()[dists.count / 2]
            // re-centre on the inner half so approach/departure points don't drag the centroid
            let inner = memberIdx.enumerated().filter { dists[$0.offset] <= max(median, config.stayCoreRadius) }.map { pts[$0.element] }
            if let c = Geo.centroid(inner.map(\.coordinate), weights: inner.map(weight)) {
                centroid = c
                dists = memberIdx.map { Geo.distance(pts[$0].coordinate, centroid) }
                median = dists.sorted()[dists.count / 2]
            }
            let core = max(config.stayCoreRadius, min(config.stayRadius, 1.5 * median))
            var firstCore = dists.firstIndex { $0 <= core } ?? 0
            // …unless the collector went quiet right after it: a stationary silence means we had already arrived
            if firstCore > 0 {
                let a = pts[memberIdx[firstCore - 1]], b = pts[memberIdx[firstCore]]
                if b.timestamp.timeIntervalSince(a.timestamp) > config.gapThreshold,
                   stationaryDuringGap(from: a.timestamp, to: b.timestamp, lastPoint: a, motion: motion) {
                    firstCore -= 1
                }
            }
            let lastCore = dists.lastIndex { $0 <= core } ?? (dists.count - 1)
            let first = pts[memberIdx[firstCore]]
            let last = pts[memberIdx[estimatedEnd == nil ? lastCore : dists.count - 1]]
            var end: Date? = estimatedEnd ?? last.timestamp
            var effectiveEnd = end!
            if !brokeOnMove && k >= n {
                // cluster runs to the end of the data: ongoing if plausibly still there
                let quiet = now.timeIntervalSince(last.timestamp) < config.gapThreshold
                if quiet {
                    end = nil
                    effectiveEnd = max(now, last.timestamp)
                } else if motion.hasCoverage(from: last.timestamp, to: now) {
                    // judge by what we're doing now, not by every walk-around since the last fix
                    let movingNow = motion.activity(at: now).map { [.walking, .running, .cycling, .automotive].contains($0) } ?? false
                    if movingNow, let m = motion.movementStart(from: last.timestamp, to: now),
                       motion.movingSeconds(from: m, to: now) >= config.minSegmentDuration {
                        end = m; effectiveEnd = m
                    } else {
                        end = nil
                        effectiveEnd = max(now, last.timestamp)
                    }
                } else if stationaryDuringGap(from: last.timestamp, to: now, lastPoint: last, motion: motion) {
                    end = nil
                    effectiveEnd = max(now, last.timestamp)
                }
            }
            let duration = effectiveEnd.timeIntervalSince(first.timestamp)
            if duration >= config.minStayDuration {
                let conf = confidence(pointCount: memberIdx.count, duration: duration)
                stays.append(DetectedStay(start: first.timestamp, end: end, centroid: centroid,
                                          pointCount: memberIdx.count, confidence: conf))
                i = k
            } else {
                i += 1
            }
        }
        return stays
    }

    /// Start of the movement that most plausibly carried us from a stay to a fix `distance` away, seen only in the
    /// motion log because location was silent: the latest bout of at least `minSegmentDuration` that began early enough
    /// to cover the distance at a plausible speed. nil when the gap has no motion coverage or no such bout.
    func departureBout(from: Date, to: Date, distance: Double, motion: MotionTimeline) -> Date? {
        guard motion.hasCoverage(from: from, to: to) else { return nil }
        let needed = distance / Self.plausibleTravelSpeed(distance: distance)
        return motion.movementBouts(from: from, to: to)
            .filter { $0.end.timeIntervalSince($0.start) >= config.minSegmentDuration && to.timeIntervalSince($0.start) >= needed }
            .last?.start
    }

    /// Typical door-to-door speed for a trip of this length (used only to back-date a departure hidden in a gap).
    static func plausibleTravelSpeed(distance d: Double) -> Double {
        switch d {
        case ..<2_000: return 1.4        // walking
        case ..<50_000: return 10        // urban vehicle / transit
        case ..<500_000: return 25       // highway / intercity rail
        default: return 220              // air
        }
    }

    /// Inverse-accuracy weight; fixes that report walking-or-faster speed count much less toward a stay centroid.
    private func weight(_ p: RawPoint) -> Double {
        let w = 1 / max(5, p.horizontalAccuracy ?? 30)
        return (p.speed ?? 0) > 1.0 ? w * 0.1 : w
    }

    private func confidence(pointCount: Int, duration: TimeInterval) -> Double {
        let byPoints = min(1, Double(pointCount) / 5)
        let byDuration = min(1, duration / (20 * 60))
        return (0.5 + 0.5 * byPoints * byDuration).rounded(toPlaces: 2)
    }

    /// Merge consecutive stays separated by a short, local excursion (e.g. GPS wander, stepping outside).
    public func mergeStays(_ stays: [DetectedStay], points: [RawPoint]) -> [DetectedStay] {
        guard stays.count > 1 else { return stays }
        var out: [DetectedStay] = [stays[0]]
        for s in stays.dropFirst() {
            var prev = out[out.count - 1]
            guard let prevEnd = prev.end else { out.append(s); continue }
            let close = Geo.distance(prev.centroid, s.centroid) <= config.mergeDistance
            let short = s.start.timeIntervalSince(prevEnd) <= config.mergeMaxExcursionDuration
            let excursion = points.filter { $0.timestamp > prevEnd && $0.timestamp < s.start }
                .map { Geo.distance($0.coordinate, prev.centroid) }.max() ?? 0
            if close && short && excursion <= config.mergeMaxExcursionDistance {
                let total = Double(prev.pointCount + s.pointCount)
                prev.centroid = Coordinate(
                    (prev.centroid.latitude * Double(prev.pointCount) + s.centroid.latitude * Double(s.pointCount)) / total,
                    (prev.centroid.longitude * Double(prev.pointCount) + s.centroid.longitude * Double(s.pointCount)) / total)
                prev.end = s.end
                prev.pointCount += s.pointCount
                prev.confidence = max(prev.confidence, s.confidence)
                out[out.count - 1] = prev
            } else {
                out.append(s)
            }
        }
        return out
    }
}

extension Double {
    func rounded(toPlaces p: Int) -> Double {
        let f = pow(10, Double(p))
        return (self * f).rounded() / f
    }
}
