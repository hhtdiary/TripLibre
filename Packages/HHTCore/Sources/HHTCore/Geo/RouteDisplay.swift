import Foundation

/// Display-only cleanup of stored trip routes for overview maps. Nothing here is persisted: raw points,
/// stored route polylines and trip/stay inference are untouched — only the geometry handed to the map changes.
///
/// Stored routes carry no timestamps (they are already Douglas–Peucker-simplified at
/// `InferenceConfig.routeSimplifyTolerance`), so the pipeline works on shape alone plus the trip's `hasGap` flag:
/// 1. drop near-duplicate vertices,
/// 2. collapse GPS jitter around the origin/destination stays,
/// 3. hide trips whose whole footprint is stationary drift,
/// 4. remove out-and-back spikes (a single fix far off the path),
/// 5. split at the long straight connector a recording gap leaves behind.
/// Zoom-dependent simplification is applied afterwards with `simplify(_:tolerance:)`.
public enum RouteDisplay {

    public struct Options: Sendable {
        /// Consecutive vertices closer than this (m) are merged.
        public var minSpacing: Double = 5
        /// Vertices within this radius (m) of the trip's first/last point, before it leaves / after it arrives,
        /// are treated as stay jitter.
        public var stayRadius: Double = 50
        /// A trip whose points all lie within this radius (m) of their centroid is drawn as nothing.
        public var stationaryRadius: Double = 60
        /// A vertex is a spike when the detour through it is this many times longer than skipping it…
        public var spikeRatio: Double = 4
        /// …and both legs of the detour are at least this long (m).
        public var spikeMinLeg: Double = 300
        /// In a trip with a recording gap, a leg longer than this (m)…
        public var gapJumpMin: Double = 1_000
        /// …and this many times the trip's median leg is assumed to be the gap connector and is not drawn.
        public var gapJumpFactor: Double = 8

        public init() {}
    }

    /// Cleaned pieces of one route, ready for zoom-dependent simplification. Empty when nothing should be drawn.
    public static func clean(_ route: [Coordinate], hasGap: Bool, options o: Options = Options()) -> [[Coordinate]] {
        var pts = dedupe(route, minSpacing: o.minSpacing)
        guard pts.count >= 2 else { return [] }
        if isStationary(pts, radius: o.stationaryRadius) { return [] }
        pts = trimStayJitter(pts, radius: o.stayRadius)
        pts = despike(pts, ratio: o.spikeRatio, minLeg: o.spikeMinLeg)
        let pieces = hasGap ? splitAtGapJumps(pts, minJump: o.gapJumpMin, factor: o.gapJumpFactor) : [pts]
        return pieces.filter { $0.count >= 2 }
    }

    /// Douglas–Peucker plus a final near-duplicate pass, for a map showing `metersPerPoint` metres per screen point.
    public static func simplify(_ piece: [Coordinate], metersPerPoint: Double) -> [Coordinate] {
        let tolerance = tolerance(metersPerPoint: metersPerPoint)
        return dedupe(Geo.simplify(piece, tolerance: tolerance), minSpacing: tolerance / 2)
    }

    /// Simplification tolerance (m) for a zoom level: about 1.5 screen points, never below GPS noise.
    public static func tolerance(metersPerPoint: Double) -> Double {
        max(5, metersPerPoint * 1.5)
    }

    // MARK: - Steps

    static func dedupe(_ pts: [Coordinate], minSpacing: Double) -> [Coordinate] {
        guard pts.count > 2 else { return pts }
        var out = [pts[0]]
        for p in pts.dropFirst().dropLast() where Geo.distance(out[out.count - 1], p) >= minSpacing { out.append(p) }
        // always keep the true endpoint (the destination anchor); replace a too-close predecessor instead
        if out.count > 1, Geo.distance(out[out.count - 1], pts[pts.count - 1]) < minSpacing { out.removeLast() }
        out.append(pts[pts.count - 1])
        return out
    }

    static func isStationary(_ pts: [Coordinate], radius: Double) -> Bool {
        guard let c = Geo.centroid(pts) else { return true }
        return pts.allSatisfy { Geo.distance($0, c) <= radius }
    }

    /// Drops interior vertices hovering around the start before the path first leaves `radius`, and likewise
    /// around the end after the path last enters it, so stay drift does not look like movement.
    static func trimStayJitter(_ pts: [Coordinate], radius: Double) -> [Coordinate] {
        guard pts.count > 2 else { return pts }
        let first = pts[0], last = pts[pts.count - 1]
        var lo = 1, hi = pts.count - 2
        while lo <= hi, Geo.distance(pts[lo], first) <= radius { lo += 1 }
        while hi >= lo, Geo.distance(pts[hi], last) <= radius { hi -= 1 }
        return [first] + (lo <= hi ? Array(pts[lo...hi]) : []) + [last]
    }

    /// Repeatedly removes interior vertices that form a sharp out-and-back excursion (classic GPS jump).
    static func despike(_ pts: [Coordinate], ratio: Double, minLeg: Double) -> [Coordinate] {
        var pts = pts
        var changed = true
        while changed && pts.count > 2 {
            changed = false
            var out = [pts[0]]
            var i = 1
            while i < pts.count - 1 {
                let a = out[out.count - 1], b = pts[i], c = pts[i + 1]
                let d1 = Geo.distance(a, b), d2 = Geo.distance(b, c), d3 = Geo.distance(a, c)
                if min(d1, d2) >= minLeg && d1 + d2 > ratio * max(d3, 1) {
                    changed = true
                } else {
                    out.append(b)
                }
                i += 1
            }
            out.append(pts[pts.count - 1])
            pts = out
        }
        return pts
    }

    static func splitAtGapJumps(_ pts: [Coordinate], minJump: Double, factor: Double) -> [[Coordinate]] {
        guard pts.count > 2 else { return [pts] }
        let legs = zip(pts, pts.dropFirst()).map { Geo.distance($0, $1) }
        let sorted = legs.sorted()
        let median = sorted[(sorted.count - 1) / 2]
        let threshold = max(minJump, factor * median)
        var pieces: [[Coordinate]] = [[pts[0]]]
        for (i, leg) in legs.enumerated() {
            if leg > threshold { pieces.append([]) }
            pieces[pieces.count - 1].append(pts[i + 1])
        }
        return pieces
    }
}
