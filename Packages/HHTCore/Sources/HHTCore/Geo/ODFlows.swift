import Foundation

/// Origin–destination flow view of trips for overview maps: instead of drawing GPS traces, every directed
/// place-to-place pair becomes one smooth arc whose weight is the number of trips. Display only — trips,
/// routes and raw points are untouched.
public enum ODFlows {

    /// One end of a trip: a place id when known (so repeated trips merge), plus where to draw it.
    public struct Endpoint: Hashable, Sendable {
        public var key: String
        public var coordinate: Coordinate
        public init(key: String, coordinate: Coordinate) { self.key = key; self.coordinate = coordinate }
        /// Fallback for trips without a place: snap to a ~100 m grid so near-identical endpoints still merge.
        public init(coordinate c: Coordinate) {
            self.init(key: String(format: "~%.3f,%.3f", c.latitude, c.longitude), coordinate: c)
        }
    }

    public struct Flow: Identifiable, Sendable {
        public var id: String { origin.key + "→" + destination.key }
        public var origin: Endpoint
        public var destination: Endpoint
        public var trips: Int
        /// Most frequent mode on this pair (ties broken by first seen).
        public var mode: TravelMode
    }

    /// Groups trips by directed origin→destination pair. Pairs closer than `minDistance` (m) and
    /// round trips to the same place are dropped: they would be a dot, not an arc.
    public static func aggregate(_ trips: [(origin: Endpoint, destination: Endpoint, mode: TravelMode)],
                                 minDistance: Double = 100) -> [Flow] {
        var order: [String] = []
        var flows: [String: Flow] = [:]
        var modes: [String: [TravelMode: Int]] = [:]
        var firstSeen: [String: [TravelMode]] = [:]
        for t in trips where t.origin.key != t.destination.key
            && Geo.distance(t.origin.coordinate, t.destination.coordinate) >= minDistance {
            let id = t.origin.key + "→" + t.destination.key
            if flows[id] == nil {
                order.append(id)
                flows[id] = Flow(origin: t.origin, destination: t.destination, trips: 0, mode: t.mode)
            }
            flows[id]!.trips += 1
            modes[id, default: [:]][t.mode, default: 0] += 1
            if !(firstSeen[id] ?? []).contains(t.mode) { firstSeen[id, default: []].append(t.mode) }
        }
        return order.map { id in
            var f = flows[id]!
            let counts = modes[id]!
            if let best = counts.values.max(), let m = firstSeen[id]!.first(where: { counts[$0] == best }) { f.mode = m }
            return f
        }
    }

    /// A quadratic Bézier arc from `a` to `b`, bowed sideways by `bend` × the distance. It always bows to the
    /// right of the direction of travel, so A→B and B→A form a lens instead of overlapping.
    public static func arc(from a: Coordinate, to b: Coordinate, bend: Double = 0.2, samples: Int = 32) -> [Coordinate] {
        guard samples >= 2, a != b else { return [a, b] }
        let mid = Coordinate((a.latitude + b.latitude) / 2, (a.longitude + b.longitude) / 2)
        let p0 = Geo.project(a, origin: mid), p2 = Geo.project(b, origin: mid)
        let dx = p2.x - p0.x, dy = p2.y - p0.y
        // right-hand normal of (dx, dy) is (dy, -dx); the curve's apex sits at half the control offset
        let c = (x: dy * bend * 2, y: -dx * bend * 2)
        return (0..<samples).map { i in
            let t = Double(i) / Double(samples - 1), u = 1 - t
            let x = u * u * p0.x + 2 * u * t * c.x + t * t * p2.x
            let y = u * u * p0.y + 2 * u * t * c.y + t * t * p2.y
            return i == 0 ? a : i == samples - 1 ? b : Geo.unproject((x, y), origin: mid)
        }
    }
}
