import Foundation

/// The small, versioned summary the app hands its Home Screen widgets through the App Group (issue #47).
/// Counts, labels and times only: never raw points, routes or coordinates. The widget extension only reads it;
/// every number here comes from the same store queries the app's own screens use.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version = WidgetSnapshot.currentVersion
    public var generatedAt: Date
    public var tracking: Tracking
    /// Newest raw fix in the database (not "GPS is live": the collector sleeps while you stay put).
    public var lastPointAt: Date?
    /// When inference last finished.
    public var diaryUpdatedAt: Date?
    /// Trips in the last 7 days that could use a check: the same count as Today's review banner.
    public var reviewPending: Int
    /// Newest stamp in the last 7 days, so the Stamp widget can confirm the last one (added in phase 2; optional,
    /// so snapshots written before it still read).
    public var lastStampAt: Date?
    public var usesMetric: Bool
    public var today: Day
    public var week: Week

    public init(generatedAt: Date, tracking: Tracking, lastPointAt: Date?, diaryUpdatedAt: Date?, reviewPending: Int,
                lastStampAt: Date? = nil, usesMetric: Bool, today: Day, week: Week) {
        self.generatedAt = generatedAt; self.tracking = tracking; self.lastPointAt = lastPointAt
        self.diaryUpdatedAt = diaryUpdatedAt; self.reviewPending = reviewPending; self.lastStampAt = lastStampAt
        self.usesMetric = usesMetric
        self.today = today; self.week = week
    }

    public enum Tracking: String, Codable, Sendable {
        case recording
        /// Turned off in HHT.
        case paused
        /// Location access denied, restricted or never granted.
        case permissionNeeded
        /// "While using" only: trips are missed in the background.
        case backgroundLimited
    }

    public struct Day: Codable, Equatable, Sendable {
        /// Local midnight the counts belong to; the widget treats a different day as not yet summarized.
        public var start: Date
        public var trips: Int
        /// Distinct places visited (Today's "places" sticker).
        public var places: Int
        public var distance: Double          // m
        public var travelTime: TimeInterval
        /// Trips today whose mode is uncertain and unreviewed.
        public var unconfirmedTrips: Int
        public var current: Stay?
        public var timeline: [Block]

        public init(start: Date, trips: Int, places: Int, distance: Double, travelTime: TimeInterval,
                    unconfirmedTrips: Int, current: Stay?, timeline: [Block]) {
            self.start = start; self.trips = trips; self.places = places; self.distance = distance
            self.travelTime = travelTime; self.unconfirmedTrips = unconfirmedTrips; self.current = current
            self.timeline = timeline
        }
    }

    /// Where the user is right now, if inference has an ongoing visit.
    public struct Stay: Codable, Equatable, Sendable {
        public var name: String?
        public var category: String?         // PlaceCategory raw value
        public var since: Date

        public init(name: String?, category: String?, since: Date) {
            self.name = name; self.category = category; self.since = since
        }
    }

    public struct Block: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, Sendable { case visit, trip }
        public var kind: Kind
        public var start: Date
        public var end: Date
        public var category: String?         // visits only
        /// The user confirmed, edited or created it; otherwise it is inference's guess.
        public var confirmed: Bool

        public init(kind: Kind, start: Date, end: Date, category: String?, confirmed: Bool) {
            self.kind = kind; self.start = start; self.end = end; self.category = category; self.confirmed = confirmed
        }
    }

    public struct Week: Codable, Equatable, Sendable {
        public var start: Date
        public var end: Date
        /// Trips per local day, oldest first, today last (each counted like that day's Today screen).
        public var tripsPerDay: [Int]
        public var trips: Int
        public var distance: Double
        public var travelTime: TimeInterval
        /// Distance per ModeGroup raw value, largest first.
        public var modeDistance: [ModeShare]
        public var topPlace: PlaceTime?

        public init(start: Date, end: Date, tripsPerDay: [Int], trips: Int, distance: Double, travelTime: TimeInterval,
                    modeDistance: [ModeShare], topPlace: PlaceTime?) {
            self.start = start; self.end = end; self.tripsPerDay = tripsPerDay; self.trips = trips
            self.distance = distance; self.travelTime = travelTime; self.modeDistance = modeDistance; self.topPlace = topPlace
        }
    }

    public struct ModeShare: Codable, Equatable, Sendable {
        public var group: String
        public var distance: Double

        public init(group: String, distance: Double) { self.group = group; self.distance = distance }
    }

    public struct PlaceTime: Codable, Equatable, Sendable {
        public var name: String?
        public var category: String?
        public var dwell: TimeInterval

        public init(name: String?, category: String?, dwell: TimeInterval) {
            self.name = name; self.category = category; self.dwell = dwell
        }
    }

    /// Same content apart from when it was written: lets the app skip reloading widgets for no change.
    public func sameContent(as other: WidgetSnapshot) -> Bool {
        var a = self, b = other
        a.generatedAt = .distantPast
        b.generatedAt = .distantPast
        return a == b
    }
}

extension WidgetSnapshot {
    public static func build(store: TravelStore, tracking: Tracking, diaryUpdatedAt: Date?, usesMetric: Bool,
                             now: Date = Date(), calendar: Calendar = .current) throws -> WidgetSnapshot {
        let places = Dictionary(uniqueKeysWithValues: try store.places().map { ($0.id, $0) })
        return WidgetSnapshot(
            generatedAt: now, tracking: tracking, lastPointAt: store.lastPoint()?.timestamp,
            diaryUpdatedAt: diaryUpdatedAt,
            reviewPending: try store.reviewCount(since: now.addingTimeInterval(-7 * 86_400)),
            lastStampAt: try store.stamps(from: now.addingTimeInterval(-7 * 86_400), to: now).last?.timestamp,
            usesMetric: usesMetric,
            today: try day(store: store, places: places, now: now, calendar: calendar),
            week: try week(store: store, places: places, now: now, calendar: calendar))
    }

    /// Mirrors the Today screen: everything overlapping the local day, so a trip across midnight counts on both days.
    static func day(store: TravelStore, places: [String: Place], now: Date, calendar: Calendar) throws -> Day {
        let r = DateRange.day(now, calendar: calendar)
        let visits = try store.visits(overlapping: r.start, r.end)
        let trips = try store.trips(overlapping: r.start, r.end, withSegments: false)
        let ongoing = visits.last { $0.departure == nil && $0.arrival <= now }
        let current = ongoing.map { v -> Stay in
            let p = v.placeID.flatMap { places[$0] }
            return Stay(name: p.flatMap { $0.isNamed ? $0.name : nil }, category: p?.category?.rawValue, since: v.arrival)
        }
        let clip = { (s: Date, e: Date) in (max(s, r.start), min(e, min(r.end, now))) }
        let blocks = visits.map { v -> Block in
            let (s, e) = clip(v.arrival, v.departure ?? now)
            return Block(kind: .visit, start: s, end: e, category: v.placeID.flatMap { places[$0]?.category?.rawValue },
                         confirmed: v.userStatus != .auto)
        } + trips.map { t -> Block in
            let (s, e) = clip(t.departure, t.arrival)
            return Block(kind: .trip, start: s, end: e, category: nil, confirmed: t.userStatus != .auto)
        }
        return Day(start: r.start, trips: trips.count, places: Set(visits.compactMap(\.placeID)).count,
                   distance: trips.reduce(0) { $0 + $1.distance }, travelTime: trips.reduce(0) { $0 + $1.duration },
                   unconfirmedTrips: trips.filter(\.needsReview).count, current: current,
                   timeline: blocks.filter { $0.end > $0.start }.sorted { $0.start < $1.start })
    }

    /// Mirrors Stats › 7 days for the totals; the per-day bars count like each day's Today screen.
    static func week(store: TravelStore, places: [String: Place], now: Date, calendar: Calendar) throws -> Week {
        let range = DateRange.lastDays(7, until: now, calendar: calendar)
        let m = try Analytics.compute(store: store, range: range, now: now)
        var perDay: [Int] = []
        var day = range.start
        for _ in 0..<7 {
            let r = DateRange.day(day, calendar: calendar)
            perDay.append(try store.trips(overlapping: r.start, r.end, withSegments: false).count)
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        var byGroup: [ModeGroup: Double] = [:]
        for row in m.modeShare { byGroup[row.mode.group, default: 0] += row.distance }
        return Week(start: range.start, end: range.end, tripsPerDay: perDay, trips: m.trips, distance: m.totalDistance,
                    travelTime: m.totalTravelTime,
                    modeDistance: byGroup.filter { $0.value > 0 }.sorted { $0.value > $1.value }
                        .map { ModeShare(group: $0.key.rawValue, distance: $0.value) },
                    topPlace: m.topPlaces.first.map { u in
                        // a place's address stands in for a missing name in Stats; the widget gets real names only
                        PlaceTime(name: places[u.placeID].flatMap { $0.isNamed ? $0.name : nil },
                                  category: u.category?.rawValue, dwell: u.dwell)
                    })
    }

    // MARK: - Shared file

    public static let fileName = "widget-snapshot.json"

    public func write(to url: URL) throws {
        try JSONEncoder().encode(self).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// nil when missing, unreadable, or written by an incompatible app version.
    public static func read(from url: URL) -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(WidgetSnapshot.self, from: data),
              s.version == currentVersion else { return nil }
        return s
    }
}
