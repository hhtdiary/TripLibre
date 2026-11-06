import Foundation

/// Display-only trajectory for the day map, built from timestamped raw observations (issue #100).
///
/// Stored route polylines join every fix into one line, so a recording gap, a poor-accuracy fix or a single GPS
/// jump becomes a long straight connector or a triangle that never happened. Here the polyline is instead broken
/// wherever continuity is implausible, leaving a visible gap rather than a fabricated straight line:
/// 1. drop fixes whose `horizontalAccuracy` is worse than `maxAccuracy`,
/// 2. drop isolated A→B→C spikes (B far from both neighbours while A and C agree, or reached at an impossible speed),
/// 3. split between consecutive fixes more than `maxTimeGap` apart, silent for `maxSilentGap` while covering more than
///    `maxSilentDistance` (signal lost in a tunnel), or implying a speed above `maxSpeed`,
/// 4. lightly simplify each remaining piece,
/// 5. for a trip, join the loose ends across each gap with an arc in the gap's mode colour (never a straight line).
///
/// Nothing is persisted: raw points, stored routes and trip/stay inference are untouched.
public enum DisplayTrajectory {

    public struct Options: Sendable, Equatable {
        /// Fixes with worse horizontal accuracy (m) are not drawn.
        public var maxAccuracy: Double = 65
        /// Consecutive drawn fixes further apart in time than this are not joined. Above the collector's 3–5 min
        /// cadence while moving (p99 ≈ 5–9 min on real days, issue #100), so normal sampling is not a gap.
        public var maxTimeGap: TimeInterval = 10 * 60
        /// On rail (`signalLossModes`), consecutive fixes this far apart in time (s)…
        public var maxSilentGap: TimeInterval = 120
        /// …and further apart than this (m) are not joined: the signal was lost underground, and the line between
        /// stations is not straight. Same rule as `InferenceConfig.movingGapThreshold`. Not applied on the road or on
        /// foot, where the collector's normal 3–5 min cadence leaves chords that do follow the path.
        public var maxSilentDistance: Double = 300
        public var signalLossModes: Set<TravelMode> = [.subway, .lightRail, .commuterRail]
        /// Consecutive fixes implying a faster speed (m/s, after allowing for both accuracies) are not joined.
        /// ~324 km/h: above high-speed rail, below airliners (flights are drawn from their stored route).
        public var maxSpeed: Double = 90
        /// A fix is a spike when both legs to its neighbours are at least this long (m)…
        public var spikeMinLeg: Double = 200
        /// …the detour through it is this many times longer than skipping it…
        public var spikeRatio: Double = 3
        /// …and its neighbours are no further apart in time than this.
        public var spikeMaxDuration: TimeInterval = 3 * 60
        /// Douglas–Peucker tolerance (m) applied to each piece.
        public var simplifyTolerance: Double = 5
        /// Loose ends closer than this (m) are left as they are rather than joined by a connector arc.
        public var connectorMinDistance: Double = 50
        /// How far a connector arc bows out at its middle, as a share of the distance it spans.
        public var connectorBulge: Double = 0.15

        public init() {}
    }

    /// One drawable piece of a trip, coloured by its mode. A connector is not measured: it is the arc drawn across a
    /// gap between the loose ends of the measured line (or from origin to destination when nothing was measured).
    public struct Piece: Equatable, Sendable {
        public var mode: TravelMode
        public var coordinates: [Coordinate]
        public var isConnector: Bool
        public init(mode: TravelMode, coordinates: [Coordinate], isConnector: Bool = false) {
            self.mode = mode; self.coordinates = coordinates; self.isConnector = isConnector
        }
    }

    /// Source tag of the synthetic origin/destination points: never filtered as inaccurate or as a spike.
    static let anchorSource = "anchor"

    /// Continuous pieces of a timestamped path travelled by `mode`. Points need not be sorted; empty when nothing
    /// should be drawn.
    public static func pieces(_ points: [RawPoint], mode: TravelMode = .unknown, options o: Options = Options()) -> [[Coordinate]] {
        runs(points, mode: mode, options: o).map { Geo.simplify($0.map(\.coordinate), tolerance: o.simplifyTolerance) }
    }

    /// The continuous runs of fixes (at least two each) that survive filtering, in time order.
    static func runs(_ points: [RawPoint], mode: TravelMode, options o: Options) -> [[RawPoint]] {
        let sorted = points.sorted { $0.timestamp < $1.timestamp }
        let accurate = sorted.filter { isAnchor($0) || isAccurate($0, limit: o.maxAccuracy) }
        let kept = despike(accurate, options: o)
        return split(kept, signalLoss: o.signalLossModes.contains(mode), options: o).filter { $0.count >= 2 }
    }

    /// Drawable pieces for a trip, one mode per piece, from the raw points around it: any superset, sorted by
    /// timestamp (as `TravelStore.points(from:to:)` returns them), so the trip's fixes are found by binary search.
    ///
    /// Each segment is rebuilt from its own fixes; the trip's stored endpoints are kept as anchors so lines still
    /// meet the stop pins when the fixes allow. Where the measured line is broken (or there is none), the loose ends
    /// are joined by an arc (`isConnector`) in the mode of the segment the gap falls in: the trip still visibly goes
    /// from its origin to its destination, but the curve says "not measured" instead of faking a straight route.
    /// Flights, and trips the user entered without any fixes, keep their stored geometry: that line is the record
    /// itself, not an artifact of sampling.
    public static func pieces(for trip: Trip, points: [RawPoint], options o: Options = Options()) -> [Piece] {
        let route = trip.route
        let inner = points.strictlyBetween(trip.departure, trip.arrival)
        if inner.isEmpty && trip.source != .inferred {
            return stored(trip)
        }
        var path: [RawPoint] = []
        if let o = route.first { path.append(anchor(o, at: trip.departure)) }
        path.append(contentsOf: inner)
        if let d = route.last, route.count >= 2 { path.append(anchor(d, at: trip.arrival)) }

        let segments = trip.segments.sorted { $0.sequence < $1.sequence }
        var measured: [Run] = []
        if segments.count > 1 {
            for s in segments {
                if s.mode == .airplane {
                    if let p = s.routePolyline.map(Polyline.decode), p.count >= 2 {
                        measured.append(Run(mode: s.mode, coordinates: p, start: s.start, end: s.end))
                    }
                    continue
                }
                // adjacent segments share their boundary fix; start from the last fix at or before the boundary so
                // the pieces meet, without reaching back past it (that would redraw the previous segment's connector)
                let lo = path.lastIndex { $0.timestamp <= s.start } ?? 0
                let within = path[lo...].prefix { $0.timestamp <= s.end }
                measured += runs(Array(within), mode: s.mode, options: o).map { Run($0, mode: s.mode, options: o) }
            }
        } else {
            if trip.mode == .airplane { return stored(trip) }
            measured = runs(path, mode: trip.mode, options: o).map { Run($0, mode: trip.mode, options: o) }
        }

        func modeAt(_ t: Date) -> TravelMode {
            segments.count > 1 ? (segments.first { $0.start <= t && t <= $0.end }?.mode ?? trip.mode) : trip.mode
        }
        var out: [Piece] = []
        var loose: (Coordinate, Date)? = path.first.map { ($0.coordinate, $0.timestamp) }
        func bridge(to c: Coordinate, at t: Date) {
            guard let (a, ta) = loose, Geo.distance(a, c) > o.connectorMinDistance else { return }
            let mid = ta.addingTimeInterval(t.timeIntervalSince(ta) / 2)
            out.append(Piece(mode: modeAt(mid), coordinates: arc(from: a, to: c, bulge: o.connectorBulge), isConnector: true))
        }
        for r in measured {
            bridge(to: r.coordinates[0], at: r.start)
            out.append(Piece(mode: r.mode, coordinates: r.coordinates))
            loose = (r.coordinates[r.coordinates.count - 1], r.end)
        }
        if let last = path.last, path.count >= 2 { bridge(to: last.coordinate, at: last.timestamp) }
        return out
    }

    /// A measured stretch with its time span, before connectors are added.
    struct Run {
        var mode: TravelMode
        var coordinates: [Coordinate]
        var start: Date
        var end: Date
        init(mode: TravelMode, coordinates: [Coordinate], start: Date, end: Date) {
            self.mode = mode; self.coordinates = coordinates; self.start = start; self.end = end
        }
        init(_ pts: [RawPoint], mode: TravelMode, options o: Options) {
            self.init(mode: mode, coordinates: Geo.simplify(pts.map(\.coordinate), tolerance: o.simplifyTolerance),
                      start: pts[0].timestamp, end: pts[pts.count - 1].timestamp)
        }
    }

    /// A gentle circular-looking arc from `a` to `b` (quadratic Bézier in a local metric plane), bowing to the left of
    /// the direction of travel by `bulge` × the chord length, so it never reads as a measured straight road.
    public static func arc(from a: Coordinate, to b: Coordinate, bulge: Double, samples: Int = 24) -> [Coordinate] {
        let p = Geo.project(b, origin: a)
        let len = (p.x * p.x + p.y * p.y).squareRoot()
        guard len > 0 else { return [a, b] }
        // a quadratic Bézier peaks at half its control point's offset, so offset by twice the wanted bulge
        let control = (x: p.x / 2 - p.y * bulge * 2, y: p.y / 2 + p.x * bulge * 2)
        return (0...samples).map { i in
            if i == 0 { return a }
            if i == samples { return b }
            let t = Double(i) / Double(samples), u = 1 - t
            let x = 2 * u * t * control.x + t * t * p.x
            let y = 2 * u * t * control.y + t * t * p.y
            return Geo.unproject((x, y), origin: a)
        }
    }

    // MARK: - Steps

    static func isAnchor(_ p: RawPoint) -> Bool { p.source == anchorSource }

    static func isAccurate(_ p: RawPoint, limit: Double) -> Bool {
        guard let a = p.horizontalAccuracy else { return true }
        return a >= 0 && a <= limit
    }

    static func anchor(_ c: Coordinate, at t: Date) -> RawPoint {
        RawPoint(timestamp: t, coordinate: c, horizontalAccuracy: 0, source: anchorSource)
    }

    private static func stored(_ trip: Trip) -> [Piece] {
        let segs = trip.segments.sorted { $0.sequence < $1.sequence }
        if segs.count > 1 {
            return segs.compactMap { s in
                guard let p = s.routePolyline.map(Polyline.decode), p.count >= 2 else { return nil }
                return Piece(mode: s.mode, coordinates: p)
            }
        }
        return trip.route.count >= 2 ? [Piece(mode: trip.mode, coordinates: trip.route)] : []
    }

    /// Speed (m/s) implied between two fixes, giving the benefit of the doubt for their stated accuracy.
    static func impliedSpeed(_ a: RawPoint, _ b: RawPoint) -> Double {
        let slack = max(0, a.horizontalAccuracy ?? 0) + max(0, b.horizontalAccuracy ?? 0)
        let d = max(0, Geo.distance(a.coordinate, b.coordinate) - slack)
        return d / max(1, abs(b.timestamp.timeIntervalSince(a.timestamp)))
    }

    /// Repeatedly removes single fixes forming an out-and-back excursion: geometrically (B far from both
    /// neighbours while A and C are close in space and time) or kinematically (A→B and B→C impossible, A→C not).
    static func despike(_ pts: [RawPoint], options o: Options) -> [RawPoint] {
        var pts = pts
        var changed = true
        while changed && pts.count > 2 {
            changed = false
            var out = [pts[0]]
            for i in 1..<(pts.count - 1) {
                let a = out[out.count - 1], b = pts[i], c = pts[i + 1]
                if !isAnchor(b) && isSpike(a, b, c, options: o) { changed = true } else { out.append(b) }
            }
            out.append(pts[pts.count - 1])
            pts = out
        }
        return pts
    }

    static func isSpike(_ a: RawPoint, _ b: RawPoint, _ c: RawPoint, options o: Options) -> Bool {
        let d1 = Geo.distance(a.coordinate, b.coordinate), d2 = Geo.distance(b.coordinate, c.coordinate)
        let d3 = Geo.distance(a.coordinate, c.coordinate)
        let span = c.timestamp.timeIntervalSince(a.timestamp)
        if span <= o.spikeMaxDuration && min(d1, d2) >= o.spikeMinLeg && d1 + d2 > o.spikeRatio * max(d3, 1) {
            return true
        }
        return impliedSpeed(a, b) > o.maxSpeed && impliedSpeed(b, c) > o.maxSpeed && impliedSpeed(a, c) <= o.maxSpeed
    }

    static func split(_ pts: [RawPoint], signalLoss: Bool, options o: Options) -> [[RawPoint]] {
        guard let first = pts.first else { return [] }
        var pieces: [[RawPoint]] = [[first]]
        for (a, b) in zip(pts, pts.dropFirst()) {
            let dt = b.timestamp.timeIntervalSince(a.timestamp)
            let gap = dt > o.maxTimeGap
                || (signalLoss && dt > o.maxSilentGap && Geo.distance(a.coordinate, b.coordinate) > o.maxSilentDistance)
            if gap || impliedSpeed(a, b) > o.maxSpeed { pieces.append([]) }
            pieces[pieces.count - 1].append(b)
        }
        return pieces
    }
}
