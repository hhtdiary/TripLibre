import Foundation

/// Self-reported stamps as extra evidence for stay detection (issue #32, docs/inference.md §8).
///
/// A stamp means "something worth recording happened around here, around now", never "this coordinate is the stop".
/// So it complements passive detection rather than overriding it:
/// * a stamp near a detected stay in time and space adds nothing: the stay already covers it;
/// * otherwise the fixes around the tap are searched for the short stop it marks, and the stop's place, arrival and
///   departure come from those fixes (the stamp's own coarse coordinate is used only when there are none);
/// * a stamp that falls inside a detected stay somewhere else conflicts with the sensors and is left unmatched.
public struct StampAnchoring: Sendable {
    public var config: InferenceConfig
    public init(config: InferenceConfig = .default) { self.config = config }

    /// How far (m) from a stamp's coordinate a stay may lie and still be the stop it marks.
    func reach(_ s: Stamp) -> Double {
        (s.uncertainty ?? 0) + config.stayRadius + config.placeMatchSlack
    }

    /// Does `stay` account for `stamp`? Time: the tap is within the stay, give or take `stampTimeTolerance`.
    /// Space: within the stamp's reach (a stamp without a location matches on time alone).
    func matches(_ stamp: Stamp, start: Date, end: Date?, centroid: Coordinate, now: Date) -> Bool {
        let t = stamp.timestamp
        guard t >= start.addingTimeInterval(-config.stampTimeTolerance),
              t <= (end ?? now).addingTimeInterval(config.stampTimeTolerance) else { return false }
        guard let c = stamp.coordinate else { return true }
        return Geo.distance(c, centroid) <= reach(stamp)
    }

    /// `stays` (sorted, as detected and merged) plus a short stay for every stamp no stay accounts for.
    /// `points` are the cleaned fixes the stays were detected from.
    public func anchor(_ stamps: [Stamp], stays: [DetectedStay], points: [RawPoint], now: Date) -> [DetectedStay] {
        var out = stays
        for stamp in stamps.sorted(by: { $0.timestamp < $1.timestamp }) where !stamp.deleted {
            if out.contains(where: { matches(stamp, start: $0.start, end: $0.end, centroid: $0.centroid, now: now) }) { continue }
            if let s = shortStay(for: stamp, among: out, points: points, now: now) {
                out.append(s)
                out.sort { $0.start < $1.start }
            }
        }
        return out
    }

    /// The short stop a stamp marks, bounded by the stays either side of it. nil when the tap falls inside another stay
    /// (the sensors say we were somewhere else) or there is nothing to place the stop with.
    func shortStay(for stamp: Stamp, among stays: [DetectedStay], points: [RawPoint], now: Date) -> DetectedStay? {
        let t = stamp.timestamp
        if stays.contains(where: { $0.start <= t && ($0.end ?? now) >= t }) { return nil }
        let prevEnd = stays.filter { $0.start < t }.compactMap(\.end).max() ?? .distantPast
        let nextStart = stays.filter { $0.start > t }.map(\.start).min() ?? .distantFuture
        let lo = max(prevEnd, t.addingTimeInterval(-config.stampSearchWindow))
        let hi = min(nextStart, t.addingTimeInterval(config.stampSearchWindow))

        let window = points.filter { $0.timestamp > lo && $0.timestamp < hi }
        let nearStamp: (RawPoint) -> Bool = { p in stamp.coordinate.map { Geo.distance(p.coordinate, $0) <= reach(stamp) } ?? true }
        var centroid: Coordinate
        var start = t, end = t
        var members: [RawPoint] = []
        var reachesDataEnd = false

        if let a = window.indices.filter({ nearStamp(window[$0]) })
            .min(by: { abs(window[$0].timestamp.timeIntervalSince(t)) < abs(window[$1].timestamp.timeIntervalSince(t)) }) {
            // grow a cluster both ways from the fix closest to the tap, as the stay detector would, but with no
            // minimum duration: the stamp is the evidence that this was a stop
            let anchor = window[a].coordinate
            var first = a, last = a
            func joins(_ i: Int, _ j: Int) -> Bool {
                Geo.distance(window[j].coordinate, anchor) <= config.stayRadius
                    && abs(window[j].timestamp.timeIntervalSince(window[i].timestamp)) <= config.gapThreshold
            }
            while first > 0 && joins(first, first - 1) { first -= 1 }
            while last < window.count - 1 && joins(last, last + 1) { last += 1 }
            members = Array(window[first...last])
            centroid = Geo.centroid(members.map(\.coordinate),
                                    weights: members.map { 1 / max(5, $0.horizontalAccuracy ?? 30) }) ?? anchor
            start = min(members.first!.timestamp, t)
            end = max(members.last!.timestamp, t)
            reachesDataEnd = last == window.count - 1 && nextStart == .distantFuture
                && !points.contains { $0.timestamp > members.last!.timestamp }
        } else if let c = stamp.coordinate {
            // no fix near the tap (indoors, collector asleep): the coarse coordinate is all there is
            centroid = c
        } else {
            return nil
        }

        // at least `stampMinStayDuration`, without running into the neighbouring stays
        let short = config.stampMinStayDuration - end.timeIntervalSince(start)
        if short > 0 {
            start = max(start.addingTimeInterval(-short / 2), lo.addingTimeInterval(1))
            end = min(end.addingTimeInterval(short / 2), hi.addingTimeInterval(-1))
        }
        guard end >= start else { return nil }
        // still there: the cluster runs to the newest fix and that fix is recent
        let ongoing = reachesDataEnd && now.timeIntervalSince(end) < config.gapThreshold
        return DetectedStay(start: start, end: ongoing ? nil : end, centroid: centroid, pointCount: members.count,
                            confidence: config.stampStayConfidence)
    }

    /// The visit a stamp belongs to among `visits` (non-deleted): one that matches it, nearest in time, then in space.
    public func visit(for stamp: Stamp, in visits: [Visit], now: Date) -> Visit? {
        func timeOff(_ v: Visit) -> TimeInterval {
            let t = stamp.timestamp
            if t < v.arrival { return v.arrival.timeIntervalSince(t) }
            if let d = v.departure, t > d { return t.timeIntervalSince(d) }
            return 0
        }
        func dist(_ v: Visit) -> Double { stamp.coordinate.map { Geo.distance($0, v.coordinate) } ?? 0 }
        return visits.filter { !$0.deleted && matches(stamp, start: $0.arrival, end: $0.departure, centroid: $0.coordinate, now: now) }
            .min { (timeOff($0), dist($0)) < (timeOff($1), dist($1)) }
    }
}
