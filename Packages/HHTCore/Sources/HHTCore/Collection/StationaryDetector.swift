import Foundation

/// Decides when the location collector may leave **moving** mode (continuous GPS) for **stationary** mode
/// (GPS off, geofence + visits + significant changes). Pure value type so the app's CoreLocation code stays thin
/// and the rules are unit-testable.
///
/// The old rule was "no fix > 60 m from the anchor for 3 min". With a distance filter that is the right signal when
/// the phone is really at rest, but it also fires when fixes simply stop arriving — notably when iOS suspends the app
/// mid-drive and resumes it minutes later, at which point the overdue timer ran before the queued fix was handled.
/// Silence alone is therefore no longer enough: the dwell must also not be contradicted by the last fix's speed or
/// by CoreMotion, and an evaluation right after a suspension is postponed briefly so pending fixes are seen first.
public struct StationaryDetector: Sendable {
    public enum Decision: Equatable, Sendable {
        case stay
        case enterStationary
        /// The app was just resumed; evaluate again after this many seconds, once queued fixes are delivered.
        case recheck(after: TimeInterval)
    }

    public struct Fix: Equatable, Sendable {
        public var timestamp: Date
        public var coordinate: Coordinate
        public var horizontalAccuracy: Double
        /// Metres per second; nil when CoreLocation reported no valid speed.
        public var speed: Double?
        public init(timestamp: Date, coordinate: Coordinate, horizontalAccuracy: Double, speed: Double? = nil) {
            self.timestamp = timestamp
            self.coordinate = coordinate
            self.horizontalAccuracy = horizontalAccuracy
            self.speed = speed
        }
    }

    public struct Config: Sendable {
        /// Fixes within this distance of the anchor count as "still here".
        public var radius: Double = 60
        /// Minimum time at the anchor before switching.
        public var dwell: TimeInterval = 180
        /// A last fix faster than this (≈ brisk walk) vetoes the switch: the phone was still travelling.
        public var maxSpeed: Double = 2.0
        /// After this long at the anchor, switch even if speed or motion disagree (no GPS in a garage, stuck motion
        /// state), so a lost signal cannot keep GPS on indefinitely.
        public var silenceCap: TimeInterval = 600
        /// Evaluations further apart than this mean the app was suspended in between.
        public var suspensionGap: TimeInterval = 150
        /// After a suspension, wait this long (or for a fix) before deciding on silence.
        public var resumeGrace: TimeInterval = 5
        /// Ignore fixes worse than this for anchoring.
        public var maxAccuracy: Double = 100
        public init() {}
    }

    public var config: Config
    public private(set) var anchor: Fix?
    public private(set) var anchorSince: Date
    public private(set) var lastFix: Fix?
    public private(set) var motion: MotionSample?
    private var lastEvaluation: Date?
    private var resumedAt: Date?

    public init(config: Config = Config(), now: Date = Date()) {
        self.config = config
        self.anchorSince = now
    }

    /// Start over (entering moving mode).
    public mutating func reset(at now: Date) {
        anchor = nil
        anchorSince = now
        lastFix = nil
        lastEvaluation = nil
        resumedAt = nil
    }

    /// Latest CoreMotion activity (activity updates only report changes, so this is the current state).
    public mutating func observe(motion sample: MotionSample) {
        motion = sample
    }

    /// Feed a moving-mode fix. Returns true when it completes a stationary dwell.
    public mutating func observe(_ fix: Fix) -> Bool {
        guard fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= config.maxAccuracy else { return false }
        lastFix = fix
        resumedAt = nil
        if let a = anchor,
           Geo.distance(a.coordinate, fix.coordinate) <= max(config.radius, fix.horizontalAccuracy) {
            return dwellConfirmed(at: fix.timestamp)
        }
        anchor = fix
        anchorSince = fix.timestamp
        return false
    }

    /// Periodic check while no fixes arrive (a still phone produces none because of the distance filter).
    public mutating func evaluate(now: Date) -> Decision {
        defer { lastEvaluation = now }
        if let last = lastEvaluation, now.timeIntervalSince(last) > config.suspensionGap { resumedAt = now }
        if let r = resumedAt {
            let waited = now.timeIntervalSince(r)
            if waited < config.resumeGrace { return .recheck(after: config.resumeGrace - waited) }
            resumedAt = nil
        }
        return dwellConfirmed(at: now) ? .enterStationary : .stay
    }

    private func dwellConfirmed(at now: Date) -> Bool {
        guard anchor != nil else { return false }
        let dwelt = now.timeIntervalSince(anchorSince)
        guard dwelt >= config.dwell else { return false }
        if dwelt >= config.silenceCap { return true }
        if let s = lastFix?.speed, s > config.maxSpeed { return false }
        if let m = motion, m.confidence >= 1, Self.travelling.contains(m.activity) { return false }
        return true
    }

    private static let travelling: Set<MotionSample.Activity> = [.walking, .running, .cycling, .automotive]
}
