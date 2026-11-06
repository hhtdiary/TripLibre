import Foundation

/// Schematic day map (issue #109): every trip is drawn as a smooth, deterministic curve from its inferred origin to its
/// inferred destination, styled by mode, instead of a GPS trail. Raw fixes are never read, so drift, sparse sampling
/// and false jumps cannot draw loops or misleading lines. The curves say "this trip went from here to there by this
/// mode", never "this is the road taken".
///
/// Display only: raw points, stored routes, trips, distances and exports are untouched.
public enum SchematicTrips {

    /// Rendering family of a mode. The app maps each kind to a colour and dash pattern; geometry is decided here.
    public enum Kind: String, CaseIterable, Sendable {
        case walking, cycling, driving, bus, rail, ferry, flight, other
    }

    public static func kind(of mode: TravelMode) -> Kind {
        switch mode {
        case .walk, .run: return .walking
        case .bicycle, .ebike, .scooter: return .cycling
        case .car, .carDriver, .carPassenger, .taxi: return .driving
        case .bus, .coach, .shuttle: return .bus
        case .subway, .lightRail, .commuterRail, .intercityRail: return .rail
        case .ferry: return .ferry
        case .airplane: return .flight
        case .other, .unknown: return .other
        }
    }

    public struct Options: Sendable, Equatable {
        /// How far a connection bows out at its middle, as a share of the origin–destination distance, per kind.
        public var bend: [Kind: Double] = [
            .walking: 0.08, .cycling: 0.08, .rail: 0.06,
            .driving: 0.14, .bus: 0.14, .ferry: 0.12,
            .flight: 0.25, .other: 0.11,
        ]
        /// Each further trip on the same directed pair bows this much more (×base), so repeats fan out.
        public var repeatSpread: Double = 0.8
        /// Connections shorter than this share of the day's extent bow up to 50 % more, so they stay visible.
        public var shortShare: Double = 0.15
        public var maxBend: Double = 0.45
        /// Origin and destination closer than this (m), or the same place, make a round trip drawn as a loop.
        public var loopDistance: Double = 40
        /// Loop size as a share of the day's extent, clamped to `loopRadius`.
        public var loopShare: Double = 0.06
        public var loopRadius: ClosedRange<Double> = 40...600
        /// Points per curve.
        public var samples: Int = 32

        public init() {}
    }

    /// What to draw for one trip. `modes` are (mode, weight) in travel order; weights split the curve between them.
    public struct Leg: Sendable, Equatable {
        public var id: String
        public var origin: ODFlows.Endpoint?
        public var destination: ODFlows.Endpoint?
        public var modes: [Mode]
        public struct Mode: Sendable, Equatable {
            public var mode: TravelMode
            public var weight: Double
            public init(_ mode: TravelMode, weight: Double = 1) { self.mode = mode; self.weight = weight }
        }
        public init(id: String, origin: ODFlows.Endpoint?, destination: ODFlows.Endpoint?, modes: [Mode]) {
            self.id = id; self.origin = origin; self.destination = destination; self.modes = modes
        }
    }

    /// A stretch of one connection drawn in one mode.
    public struct Span: Sendable, Equatable {
        public var mode: TravelMode
        public var coordinates: [Coordinate]
        public var kind: Kind { SchematicTrips.kind(of: mode) }
    }

    /// One drawable trip connection.
    public struct Connection: Identifiable, Sendable, Equatable {
        public var id: String
        /// 1-based position in the day, in the order the legs were given (chronological).
        public var order: Int
        public var origin: ODFlows.Endpoint
        public var destination: ODFlows.Endpoint
        public var isLoop: Bool
        /// The whole curve, origin first.
        public var path: [Coordinate]
        public var spans: [Span]
        /// Where to put the trip's marker: half-way along the curve (a loop's far end).
        public var marker: Coordinate
        /// The mode that covers most of the trip.
        public var mainMode: TravelMode
    }

    /// Lays out `legs` (in chronological order). Legs without both endpoints are left out: there is nothing honest
    /// to draw for them. The same input always gives the same geometry.
    public static func layout(_ legs: [Leg], options o: Options = Options()) -> [Connection] {
        let drawable = legs.enumerated().compactMap { i, l -> (Int, Leg, ODFlows.Endpoint, ODFlows.Endpoint)? in
            guard let a = l.origin, let b = l.destination else { return nil }
            return (i + 1, l, a, b)
        }
        let extent = dayExtent(drawable.flatMap { [$0.2.coordinate, $0.3.coordinate] })
        var pairCount: [String: Int] = [:]
        var loopCount: [String: Int] = [:]
        return drawable.map { order, leg, a, b in
            let modes = leg.modes.isEmpty ? [Leg.Mode(.unknown)] : leg.modes
            let main = modes.max { $0.weight < $1.weight }?.mode ?? .unknown
            let chord = Geo.distance(a.coordinate, b.coordinate)
            let isLoop = a.key == b.key || chord < o.loopDistance
            let path: [Coordinate]
            let marker: Coordinate
            if isLoop {
                let k = loopCount[a.key, default: 0]; loopCount[a.key] = k + 1
                let r = min(max(extent * o.loopShare, o.loopRadius.lowerBound), o.loopRadius.upperBound) * (1 + 0.35 * Double(k))
                path = loop(at: a.coordinate, radius: r, angle: Double(k) * 70 - 45, samples: o.samples)
                marker = path[path.count / 2]
            } else {
                let key = a.key + "→" + b.key
                let k = pairCount[key, default: 0]; pairCount[key] = k + 1
                let base = o.bend[kind(of: main)] ?? 0.11
                let short = extent > 0 ? max(0, 1 - chord / (o.shortShare * extent)) : 0
                let bend = min(o.maxBend, base * (1 + 0.5 * short) * (1 + o.repeatSpread * Double(k)))
                // always bows right of travel, so a reciprocal trip bows the other way instead of overlapping
                path = ODFlows.arc(from: a.coordinate, to: b.coordinate, bend: bend, samples: o.samples)
                marker = point(along: path, at: 0.5)
            }
            return Connection(id: leg.id, order: order, origin: a, destination: b, isLoop: isLoop, path: path,
                              spans: split(path, modes: modes), marker: marker, mainMode: main)
        }
    }

    /// The diagonal (m) of the box around all endpoints.
    static func dayExtent(_ coords: [Coordinate]) -> Double {
        guard let first = coords.first else { return 0 }
        var minX = 0.0, maxX = 0.0, minY = 0.0, maxY = 0.0
        for c in coords {
            let p = Geo.project(c, origin: first)
            minX = min(minX, p.x); maxX = max(maxX, p.x); minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return ((maxX - minX) * (maxX - minX) + (maxY - minY) * (maxY - minY)).squareRoot()
    }

    /// A petal leaving `c` and coming back, its far end `radius` m away at `angle` degrees (0 = east, counter-clockwise).
    static func loop(at c: Coordinate, radius: Double, angle: Double, samples: Int) -> [Coordinate] {
        let a = angle * .pi / 180, spread = 35.0 * .pi / 180, reach = radius * 1.33   // cubic apex ≈ 0.75 × controls
        let c1 = (x: reach * cos(a - spread), y: reach * sin(a - spread))
        let c2 = (x: reach * cos(a + spread), y: reach * sin(a + spread))
        let n = max(samples, 4)
        return (0...n).map { i in
            if i == 0 || i == n { return c }
            let t = Double(i) / Double(n), u = 1 - t
            let x = 3 * u * u * t * c1.x + 3 * u * t * t * c2.x
            let y = 3 * u * u * t * c1.y + 3 * u * t * t * c2.y
            return Geo.unproject((x, y), origin: c)
        }
    }

    /// The point `fraction` of the way along `path` by length.
    static func point(along path: [Coordinate], at fraction: Double) -> Coordinate {
        cut(path, from: fraction, to: fraction).first ?? path[0]
    }

    /// Splits `path` between `modes` in proportion to their weights; adjacent stretches share their boundary point,
    /// and consecutive stretches of the same mode are merged.
    static func split(_ path: [Coordinate], modes: [Leg.Mode]) -> [Span] {
        var merged: [Leg.Mode] = []
        for m in modes {
            if merged.last?.mode == m.mode { merged[merged.count - 1].weight += max(0, m.weight) }
            else { merged.append(Leg.Mode(m.mode, weight: max(0, m.weight))) }
        }
        let total = merged.reduce(0) { $0 + $1.weight }
        if merged.count == 1 || total <= 0 { return [Span(mode: merged.first?.mode ?? .unknown, coordinates: path)] }
        var out: [Span] = []
        var start = 0.0
        for (i, m) in merged.enumerated() where m.weight > 0 {
            let end = i == merged.count - 1 ? 1 : start + m.weight / total
            out.append(Span(mode: m.mode, coordinates: cut(path, from: start, to: end)))
            start = end
        }
        return out
    }

    /// The part of `path` between two length fractions, with interpolated ends.
    static func cut(_ path: [Coordinate], from f0: Double, to f1: Double) -> [Coordinate] {
        guard path.count >= 2 else { return path }
        var lengths = [0.0]
        for (a, b) in zip(path, path.dropFirst()) { lengths.append(lengths[lengths.count - 1] + Geo.distance(a, b)) }
        let total = lengths[lengths.count - 1]
        guard total > 0 else { return [path[0], path[path.count - 1]] }
        func at(_ d: Double) -> Coordinate {
            let i = max(1, lengths.firstIndex { $0 >= d } ?? lengths.count - 1)
            let seg = lengths[i] - lengths[i - 1]
            let t = seg > 0 ? (d - lengths[i - 1]) / seg : 0
            let a = path[i - 1], b = path[i]
            return Coordinate(a.latitude + (b.latitude - a.latitude) * t, a.longitude + (b.longitude - a.longitude) * t)
        }
        let d0 = min(max(f0, 0), 1) * total, d1 = min(max(f1, 0), 1) * total
        if d1 <= d0 { return [at(d0)] }
        var out = [at(d0)]
        for (i, l) in lengths.enumerated() where l > d0 && l < d1 { out.append(path[i]) }
        out.append(at(d1))
        return out
    }
}

extension SchematicTrips {
    /// Where a trip starts and ends for the schematic map: the stop's place when known (so pins and lines meet and
    /// repeat trips share endpoints), else the stop's observed centre, else a trip-level place, else the first/last
    /// point of the stored route. Missing visits or places are simply skipped.
    public static func leg(for trip: Trip, visits: [String: Visit], places: [String: Place]) -> Leg {
        func end(visitID: String?, placeID: String?, fallback: Coordinate?) -> ODFlows.Endpoint? {
            if let v = visitID.flatMap({ visits[$0] }) {
                if let p = v.placeID.flatMap({ places[$0] }) { return ODFlows.Endpoint(key: "p:" + p.id, coordinate: p.coordinate) }
                return ODFlows.Endpoint(coordinate: v.coordinate)
            }
            if let p = placeID.flatMap({ places[$0] }) { return ODFlows.Endpoint(key: "p:" + p.id, coordinate: p.coordinate) }
            return fallback.map { ODFlows.Endpoint(coordinate: $0) }
        }
        let route = trip.route
        let origin = end(visitID: trip.originVisitID, placeID: trip.originPlaceID, fallback: route.first)
        let destination = end(visitID: trip.destinationVisitID, placeID: trip.destinationPlaceID,
                              fallback: route.count >= 2 ? route.last : nil)
        var modes = [Leg.Mode(trip.mode)]
        let segs = trip.segments.sorted { $0.sequence < $1.sequence }
        if trip.displayModes.count > 1, segs.count > 1 {
            let byDistance = segs.allSatisfy { $0.distance > 0 }
            modes = segs.map { Leg.Mode($0.mode, weight: byDistance ? $0.distance : max(0, $0.end.timeIntervalSince($0.start))) }
        }
        return Leg(id: trip.id, origin: origin, destination: destination, modes: modes)
    }
}
