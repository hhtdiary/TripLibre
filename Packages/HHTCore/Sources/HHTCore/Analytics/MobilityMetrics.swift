import Foundation

/// Inclusive local-date range, e.g. a week, a semester, or all time.
public struct DateRange: Equatable, Sendable {
    public var start: Date
    public var end: Date
    public init(start: Date, end: Date) { self.start = start; self.end = end }

    public static func day(_ d: Date, calendar: Calendar = .current) -> DateRange {
        let s = calendar.startOfDay(for: d)
        return DateRange(start: s, end: calendar.date(byAdding: .day, value: 1, to: s)!.addingTimeInterval(-0.001))
    }

    public static func lastDays(_ n: Int, until: Date = Date(), calendar: Calendar = .current) -> DateRange {
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: until))!.addingTimeInterval(-0.001)
        let start = calendar.date(byAdding: .day, value: -(n - 1), to: calendar.startOfDay(for: until))!
        return DateRange(start: start, end: end)
    }

    /// From a life phase's YYYY-MM-DD bounds.
    public static func phase(_ p: LifePhase, now: Date = Date(), calendar: Calendar = .current) -> DateRange? {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd"
        guard let s = f.date(from: p.startDate) else { return nil }
        let e = p.endDate.flatMap(f.date(from:)).flatMap { calendar.date(byAdding: .day, value: 1, to: $0) }
            ?? calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        return DateRange(start: s, end: e.addingTimeInterval(-0.001))
    }

    public func contains(_ d: Date) -> Bool { d >= start && d <= end }
}

public struct ModeShareRow: Identifiable, Equatable, Sendable {
    public var id: String { mode.rawValue }
    public var mode: TravelMode
    public var trips: Int
    public var distance: Double
    public var time: TimeInterval
}

public struct PlaceUsage: Identifiable, Equatable, Sendable {
    public var id: String { placeID }
    public var placeID: String
    public var name: String
    public var category: PlaceCategory?
    public var visits: Int
    public var dwell: TimeInterval
}

public struct ODPair: Identifiable, Equatable, Sendable {
    public var id: String { "\(origin)->\(destination)" }
    public var origin: String
    public var destination: String
    public var originName: String
    public var destinationName: String
    public var trips: Int
}

/// All metrics for one period. Every metric's definition is in docs/analytics.md.
public struct MobilityMetrics: Equatable, Sendable {
    public var range: DateRange
    public var personDays = 0                 // days in range with ≥1 visit or trip
    public var trips = 0
    public var totalDistance = 0.0            // m
    public var totalTravelTime = 0.0          // s
    public var tripsPerDay = 0.0
    public var distancePerDay = 0.0
    public var travelTimePerDay = 0.0
    public var meanTripDistance = 0.0
    public var meanTripDuration = 0.0
    public var modeShare: [ModeShareRow] = []
    public var groupShareByTrips: [ModeGroup: Double] = [:]
    public var departuresByHour: [Int] = Array(repeating: 0, count: 24)
    public var meanFirstDepartureMinutes: Double?     // minutes after local midnight
    public var meanLastArrivalMinutes: Double?
    public var sdFirstDepartureMinutes: Double?
    public var meanTimeAwayFromHomePerDay: Double?    // s, only over days with a home visit
    public var dwellByCategory: [String: TimeInterval] = [:]
    public var uniquePlaces = 0
    public var newPlaces = 0                  // first-ever visit falls inside the range
    public var topPlaces: [PlaceUsage] = []
    public var topODPairs: [ODPair] = []
    public var repeatODShare: Double?         // share of trips whose OD pair occurred earlier in the range
    public var radiusOfGyrationDwell: Double? // m, dwell-weighted over visits
    public var radiusOfGyrationVisits: Double? // m, visit-weighted
    public var activitySpaceHullArea: Double? // m², convex hull of visited places
    public var activitySpaceHull: [Coordinate] = []
    public var destinationEntropy: Double?    // bits, Shannon over visit counts per place
    public var modeEntropy: Double?           // bits, Shannon over trip counts per mode
    public var tours = 0                      // home-based tours
    public var meanStopsPerTour: Double?
    public var complexTourShare: Double?      // tours with ≥2 intermediate stops
    public var weekdayTripsPerDay: Double?
    public var weekendTripsPerDay: Double?
    public var weekdayModeShare: [ModeGroup: Double] = [:]
    public var weekendModeShare: [ModeGroup: Double] = [:]
    public var reviewPending = 0
}

public enum Analytics {
    static func shannon<T: Hashable>(_ counts: [T: Double]) -> Double? {
        let total = counts.values.reduce(0, +)
        guard total > 0 else { return nil }
        return -counts.values.filter { $0 > 0 }.map { let p = $0 / total; return p * log2(p) }.reduce(0, +)
    }

    static func localCalendar(_ tz: String?) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = tz.flatMap(TimeZone.init(identifier:)) ?? .current
        return c
    }

    static func minutesAfterMidnight(_ d: Date, tz: String?) -> Double {
        let c = localCalendar(tz)
        let comps = c.dateComponents([.hour, .minute, .second], from: d)
        return Double(comps.hour ?? 0) * 60 + Double(comps.minute ?? 0) + Double(comps.second ?? 0) / 60
    }

    static func dayKey(_ d: Date, tz: String?) -> String {
        let c = localCalendar(tz)
        let x = c.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", x.year ?? 0, x.month ?? 0, x.day ?? 0)
    }

    static func isWeekend(_ d: Date, tz: String?) -> Bool { localCalendar(tz).isDateInWeekend(d) }

    /// Compute every metric for `range` from the store.
    public static func compute(store: TravelStore, range: DateRange, now: Date = Date()) throws -> MobilityMetrics {
        let trips = try store.trips(overlapping: range.start, range.end, withSegments: false)
            .filter { range.contains($0.departure) }
        let visits = try store.visits(overlapping: range.start, range.end)
        let places = Dictionary(uniqueKeysWithValues: try store.places().map { ($0.id, $0) })
        let allPlaceFirst = try store.placeStats().mapValues { $0.firstVisit }
        var m = compute(trips: trips, visits: visits, places: places, firstVisitByPlace: allPlaceFirst, range: range, now: now)
        m.reviewPending = trips.filter(\.needsReview).count
        return m
    }

    /// Pure computation (unit-testable).
    public static func compute(trips allTrips: [Trip], visits allVisits: [Visit], places: [String: Place],
                               firstVisitByPlace: [String: Date?] = [:], range: DateRange, now: Date = Date()) -> MobilityMetrics {
        var m = MobilityMetrics(range: range)
        let trips = allTrips.filter { !$0.deleted && range.contains($0.departure) }.sorted { $0.departure < $1.departure }
        let visits = allVisits.filter { !$0.deleted }.sorted { $0.arrival < $1.arrival }
        let visitByID = Dictionary(uniqueKeysWithValues: allVisits.map { ($0.id, $0) })

        func placeOf(_ v: Visit?) -> Place? { v?.placeID.flatMap { places[$0] } }
        func originPlace(_ t: Trip) -> String? { t.originVisitID.flatMap { visitByID[$0]?.placeID } ?? t.originPlaceID }
        func destPlace(_ t: Trip) -> String? { t.destinationVisitID.flatMap { visitByID[$0]?.placeID } ?? t.destinationPlaceID }
        func isHome(_ id: String?) -> Bool { id.flatMap { places[$0]?.category } == .home }

        // clip visits to the range for dwell calculations
        func clippedDwell(_ v: Visit) -> TimeInterval {
            let s = max(v.arrival, range.start), e = min(v.departure ?? now, range.end, now)
            return max(0, e.timeIntervalSince(s))
        }

        // person-days
        var days = Set<String>()
        for t in trips { days.insert(dayKey(t.departure, tz: t.timeZone)) }
        for v in visits where clippedDwell(v) > 0 {
            days.insert(dayKey(max(v.arrival, range.start), tz: v.timeZone))
        }
        m.personDays = days.count
        let nDays = Double(max(1, m.personDays))

        // volume
        m.trips = trips.count
        m.totalDistance = trips.reduce(0) { $0 + $1.distance }
        m.totalTravelTime = trips.reduce(0) { $0 + $1.duration }
        m.tripsPerDay = Double(m.trips) / nDays
        m.distancePerDay = m.totalDistance / nDays
        m.travelTimePerDay = m.totalTravelTime / nDays
        if m.trips > 0 {
            m.meanTripDistance = m.totalDistance / Double(m.trips)
            m.meanTripDuration = m.totalTravelTime / Double(m.trips)
        }

        // modes
        var byMode: [TravelMode: ModeShareRow] = [:]
        for t in trips {
            var r = byMode[t.mode] ?? ModeShareRow(mode: t.mode, trips: 0, distance: 0, time: 0)
            r.trips += 1; r.distance += t.distance; r.time += t.duration
            byMode[t.mode] = r
        }
        m.modeShare = byMode.values.sorted { $0.trips == $1.trips ? $0.distance > $1.distance : $0.trips > $1.trips }
        func groupShare(_ ts: [Trip]) -> [ModeGroup: Double] {
            guard !ts.isEmpty else { return [:] }
            var g: [ModeGroup: Double] = [:]
            for t in ts { g[t.mode.group, default: 0] += 1 }
            return g.mapValues { $0 / Double(ts.count) }
        }
        m.groupShareByTrips = groupShare(trips)
        m.modeEntropy = shannon(Dictionary(grouping: trips, by: \.mode).mapValues { Double($0.count) })

        // temporal
        var firstDep: [String: Double] = [:], lastArr: [String: Double] = [:]
        for t in trips {
            let h = Int(minutesAfterMidnight(t.departure, tz: t.timeZone) / 60)
            m.departuresByHour[min(23, max(0, h))] += 1
            let k = dayKey(t.departure, tz: t.timeZone)
            let dm = minutesAfterMidnight(t.departure, tz: t.timeZone)
            firstDep[k] = min(firstDep[k] ?? .infinity, dm)
            if dayKey(t.arrival, tz: t.timeZone) == k {
                lastArr[k] = max(lastArr[k] ?? -.infinity, minutesAfterMidnight(t.arrival, tz: t.timeZone))
            }
        }
        if !firstDep.isEmpty {
            let xs = Array(firstDep.values)
            let mean = xs.reduce(0, +) / Double(xs.count)
            m.meanFirstDepartureMinutes = mean
            if xs.count > 1 {
                m.sdFirstDepartureMinutes = sqrt(xs.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(xs.count - 1))
            }
        }
        if !lastArr.isEmpty { m.meanLastArrivalMinutes = lastArr.values.reduce(0, +) / Double(lastArr.count) }

        // weekday / weekend
        let wkTrips = trips.filter { !isWeekend($0.departure, tz: $0.timeZone) }
        let weTrips = trips.filter { isWeekend($0.departure, tz: $0.timeZone) }
        let wkDays = days.filter { k in !isWeekendKey(k) }.count
        let weDays = days.count - wkDays
        if wkDays > 0 { m.weekdayTripsPerDay = Double(wkTrips.count) / Double(wkDays) }
        if weDays > 0 { m.weekendTripsPerDay = Double(weTrips.count) / Double(weDays) }
        m.weekdayModeShare = groupShare(wkTrips)
        m.weekendModeShare = groupShare(weTrips)

        // places & dwell
        var usage: [String: PlaceUsage] = [:]
        var homeDwellByDay: [String: TimeInterval] = [:]
        for v in visits {
            let dwell = clippedDwell(v)
            guard dwell > 0 else { continue }
            let p = placeOf(v)
            m.dwellByCategory[p?.category?.rawValue ?? "uncategorized", default: 0] += dwell
            if let pid = v.placeID {
                var u = usage[pid] ?? PlaceUsage(placeID: pid, name: p?.displayName ?? "Unknown", category: p?.category, visits: 0, dwell: 0)
                u.visits += 1; u.dwell += dwell
                usage[pid] = u
            }
            if p?.category == .home {
                // attribute home time to each local day it covers
                var s = max(v.arrival, range.start)
                let e = min(v.departure ?? now, range.end, now)
                let cal = localCalendar(v.timeZone)
                while s < e {
                    let next = min(e, cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: s))!)
                    homeDwellByDay[dayKey(s, tz: v.timeZone), default: 0] += next.timeIntervalSince(s)
                    s = next
                }
            }
        }
        m.uniquePlaces = usage.count
        m.newPlaces = usage.keys.filter { id in (firstVisitByPlace[id] ?? nil).map(range.contains) ?? false }.count
        m.topPlaces = usage.values.sorted { $0.dwell > $1.dwell }.prefix(10).map { $0 }
        m.destinationEntropy = shannon(usage.mapValues { Double($0.visits) })
        let homeDays = homeDwellByDay.filter { days.contains($0.key) }
        if !homeDays.isEmpty {
            // time away = 24 h − time at home, only for complete, observed days with a home visit
            let away = homeDays.map { max(0, 86_400 - $0.value) }
            m.meanTimeAwayFromHomePerDay = away.reduce(0, +) / Double(away.count)
        }

        // spatial
        let located = usage.values.compactMap { u -> (Coordinate, Double, Double)? in
            guard let p = places[u.placeID] else { return nil }
            return (p.coordinate, u.dwell, Double(u.visits))
        }
        if !located.isEmpty {
            m.radiusOfGyrationDwell = Geo.radiusOfGyration(located.map(\.0), weights: located.map(\.1))
            m.radiusOfGyrationVisits = Geo.radiusOfGyration(located.map(\.0), weights: located.map(\.2))
            let hull = Geo.convexHull(located.map(\.0))
            m.activitySpaceHull = hull.hull
            m.activitySpaceHullArea = hull.areaSquareMeters
        }

        // OD pairs
        var odCounts: [String: ODPair] = [:]
        var seen = Set<String>(), repeats = 0, odTrips = 0
        for t in trips {
            guard let o = originPlace(t), let d = destPlace(t) else { continue }
            let key = "\(o)->\(d)"
            odTrips += 1
            if seen.contains(key) { repeats += 1 } else { seen.insert(key) }
            var pair = odCounts[key] ?? ODPair(origin: o, destination: d, originName: places[o]?.displayName ?? "?",
                                               destinationName: places[d]?.displayName ?? "?", trips: 0)
            pair.trips += 1
            odCounts[key] = pair
        }
        m.topODPairs = odCounts.values.sorted { $0.trips > $1.trips }.prefix(10).map { $0 }
        if odTrips > 0 { m.repeatODShare = Double(repeats) / Double(odTrips) }

        // home-based tours: sequence of trips starting at home and ending at the next home arrival
        var stopsPerTour: [Int] = []
        var inTour = false, stops = 0
        for t in trips {
            if isHome(originPlace(t)) { inTour = true; stops = 0 }
            guard inTour else { continue }
            if isHome(destPlace(t)) {
                stopsPerTour.append(stops)
                inTour = false
            } else {
                stops += 1
            }
        }
        m.tours = stopsPerTour.count
        if !stopsPerTour.isEmpty {
            m.meanStopsPerTour = Double(stopsPerTour.reduce(0, +)) / Double(stopsPerTour.count)
            m.complexTourShare = Double(stopsPerTour.filter { $0 >= 2 }.count) / Double(stopsPerTour.count)
        }
        return m
    }

    private static func isWeekendKey(_ key: String) -> Bool {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        guard let d = f.date(from: key) else { return false }
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c.isDateInWeekend(d)
    }

    // MARK: - Flights

    public struct FlightStats: Equatable, Sendable {
        public var flights = 0
        public var distance = 0.0
        public var airTime = 0.0
        public var airports: [String: Int] = [:]
        public var routes: [String: Int] = [:]
        public var airlines: [String: Int] = [:]
        public init() {}
    }

    public static func flightStats(_ flights: [Flight]) -> FlightStats {
        var s = FlightStats()
        for f in flights {
            s.flights += 1
            s.distance += f.effectiveDistance ?? 0
            if let d = f.departure, let a = f.arrival { s.airTime += a.timeIntervalSince(d) }
            for code in [f.originCode, f.destinationCode].compactMap({ $0 }) { s.airports[code, default: 0] += 1 }
            if let o = f.originCode, let d = f.destinationCode { s.routes[[o, d].sorted().joined(separator: "–"), default: 0] += 1 }
            if let a = f.airline, !a.isEmpty { s.airlines[a, default: 0] += 1 }
        }
        return s
    }
}
