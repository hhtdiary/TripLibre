import Foundation

/// Every inference threshold lives here (documented in docs/inference.md). Nothing else hard-codes them.
public struct InferenceConfig: Sendable, Codable, Equatable {
    /// Points with worse horizontal accuracy (m) are ignored by inference (they stay in the raw table).
    public var maxHorizontalAccuracy: Double = 100
    /// Accuracy limit for OS visit events (CLVisit), which are coarser but very informative.
    public var maxVisitEventAccuracy: Double = 250
    /// Implied speed (m/s) above which an isolated point is treated as a GPS jump.
    public var maxPlausibleSpeed: Double = 320
    /// A stay cluster: all points within this radius (m) of the running centroid.
    public var stayRadius: Double = 100
    /// Stay start/end are trimmed to members within this core radius (m) of the centroid (or 1.5× median spread).
    public var stayCoreRadius: Double = 35
    /// Minimum dwell time for a cluster to become a visit.
    public var minStayDuration: TimeInterval = 5 * 60
    /// Points outside the cluster for less than this, followed by a return, are GPS drift.
    public var driftMaxDuration: TimeInterval = 120
    /// A gap between consecutive points longer than this is a "data gap".
    public var gapThreshold: TimeInterval = 15 * 60
    /// Within a movement, no fix for this long (while covering > 300 m) marks signal loss (tunnel, flight).
    public var movingGapThreshold: TimeInterval = 120
    /// During a gap, this much (s) of non-stationary motion activity means the person was moving.
    /// Calibrated on real days (issue #46): indoor walking adds up to 5–20 min over a long silence at one place.
    public var gapMovingSeconds: TimeInterval = 20 * 60
    /// Two stays closer than this (m) with only a short excursion between them are merged.
    public var mergeDistance: Double = 150
    /// …if the excursion lasted less than this…
    public var mergeMaxExcursionDuration: TimeInterval = 10 * 60
    /// …and never went farther than this (m) from the first stay.
    public var mergeMaxExcursionDistance: Double = 250
    /// Points loaded before an incremental window so its first stay is seen whole.
    public var contextMargin: TimeInterval = 30 * 60
    /// Extra distance (m) beyond a place's radius when matching a stay to a known place.
    public var placeMatchSlack: Double = 40
    /// Radius (m) given to places created automatically.
    public var newPlaceRadius: Double = 80
    /// Mode segments shorter than this are absorbed by neighbours.
    public var minSegmentDuration: TimeInterval = 120
    /// Douglas–Peucker tolerance (m) for stored route geometry. Raw points are kept regardless.
    public var routeSimplifyTolerance: Double = 8
    /// Speed thresholds (m/s) used when no motion activity is available.
    public var walkMaxSpeed: Double = 2.2         // ~8 km/h
    public var bikeMaxSpeed: Double = 7.0         // ~25 km/h
    public var airMinSpeed: Double = 70           // ~250 km/h
    /// Shortest run (m) that can be called a flight; faster-than-car hops below this are GPS jumps.
    public var airMinDistance: Double = 50_000
    public var intercityRailMinSpeed: Double = 38 // ~137 km/h sustained (p90)
    public var intercityMinDistance: Double = 60_000

    public init() {}
    public static let `default` = InferenceConfig()
}
