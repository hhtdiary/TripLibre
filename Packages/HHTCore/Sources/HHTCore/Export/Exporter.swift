import Foundation

/// Writes the dataset as CSV tables, full JSON, GeoJSON and a SQLite snapshot. All tables share stable IDs.
/// Column definitions: docs/data-model.md.
public final class Exporter {
    public let store: TravelStore
    public init(store: TravelStore) { self.store = store }

    public struct Options: Sendable {
        public var range: DateRange?          // nil = everything
        public var includeRawPoints = true
        public var includeSQLite = true
        public var csv = true
        public var json = true
        public var geojson = true
        public init(range: DateRange? = nil) { self.range = range }
    }

    // MARK: - Formatting helpers

    static func utc(_ d: Date?) -> String? { iso(d) }

    static func local(_ d: Date?, tz: String?) -> String? {
        guard let d else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = tz.flatMap(TimeZone.init(identifier:)) ?? .current
        return f.string(from: d)
    }

    static func num(_ x: Double?, _ digits: Int = 1) -> String? {
        guard let x, x.isFinite else { return nil }
        return String(format: "%.\(digits)f", x)
    }

    static func coord(_ x: Double?) -> String? { num(x, 6) }

    // MARK: - Canonical HHTS-style trip table

    public struct TripRow {
        public var trip: Trip
        public var personDayID: String
        public var sequence: Int
        public var originPlace: Place?
        public var destinationPlace: Place?
        public var purposeFinal: TripPurpose?
        public var origin: Coordinate?
        public var destination: Coordinate?
    }

    public func tripRows(range: DateRange?) throws -> [TripRow] {
        let trips = try (range.map { try store.trips(overlapping: $0.start, $0.end) } ?? store.allTrips(withSegments: true))
            .filter { range?.contains($0.departure) ?? true }
        var visits: [String: Visit] = [:]
        var places: [String: Place] = [:]
        for p in try store.places() { places[p.id] = p }
        func visit(_ id: String?) throws -> Visit? {
            guard let id else { return nil }
            if let v = visits[id] { return v }
            let v = try store.visit(id)
            visits[id] = v
            return v
        }
        var seqByDay: [String: Int] = [:]
        return try trips.map { t in
            let ov = try visit(t.originVisitID), dv = try visit(t.destinationVisitID)
            let op = (ov?.placeID ?? t.originPlaceID).flatMap { places[$0] }
            let dp = (dv?.placeID ?? t.destinationPlaceID).flatMap { places[$0] }
            let day = Analytics.dayKey(t.departure, tz: t.timeZone)
            let seq = (seqByDay[day] ?? 0) + 1
            seqByDay[day] = seq
            let purpose = t.purpose ?? dv?.purpose ?? dp?.category?.defaultPurpose
            return TripRow(trip: t, personDayID: day, sequence: seq, originPlace: op, destinationPlace: dp,
                           purposeFinal: purpose, origin: ov?.coordinate ?? op?.coordinate,
                           destination: dv?.coordinate ?? dp?.coordinate)
        }
    }

    public func tripsCSV(range: DateRange?) throws -> String {
        let header = ["person_day_id", "trip_id", "trip_seq", "origin_visit_id", "destination_visit_id",
                      "origin_place_id", "origin_place_name", "origin_category", "origin_lat", "origin_lon",
                      "destination_place_id", "destination_place_name", "destination_category", "destination_lat", "destination_lon",
                      "departure_utc", "arrival_utc", "departure_local", "arrival_local", "tz", "day_of_week",
                      "travel_time_min", "distance_m", "mode", "mode_group", "mode_auto", "mode_confidence", "mode_user",
                      "n_segments", "segment_modes", "purpose", "has_gap", "auto_confidence", "source", "user_status", "notes",
                      "route_polyline"]
        let rows: [[String?]] = try tripRows(range: range).map { r in
            let t = r.trip
            let dow = Analytics.localCalendar(t.timeZone).component(.weekday, from: t.departure)
            return [r.personDayID, t.id, String(r.sequence), t.originVisitID, t.destinationVisitID,
                    r.originPlace?.id, r.originPlace?.displayName, r.originPlace?.category?.rawValue,
                    Self.coord(r.origin?.latitude), Self.coord(r.origin?.longitude),
                    r.destinationPlace?.id, r.destinationPlace?.displayName, r.destinationPlace?.category?.rawValue,
                    Self.coord(r.destination?.latitude), Self.coord(r.destination?.longitude),
                    Self.utc(t.departure), Self.utc(t.arrival), Self.local(t.departure, tz: t.timeZone),
                    Self.local(t.arrival, tz: t.timeZone), t.timeZone, String(dow),
                    Self.num(t.duration / 60, 2), Self.num(t.distance, 1), t.mode.rawValue, t.mode.group.rawValue,
                    t.modeAuto?.rawValue, Self.num(t.modeConfidence, 2), t.modeUser?.rawValue,
                    String(t.segments.count), t.segments.map(\.mode.rawValue).joined(separator: "|"),
                    r.purposeFinal?.rawValue, t.hasGap ? "1" : "0", Self.num(t.autoConfidence, 2), t.source.rawValue,
                    t.userStatus.rawValue, t.notes, t.routePolyline]
        }
        return CSV.write(header: header, rows: rows)
    }

    // MARK: - Other tables

    func whereRange(_ col: String, _ range: DateRange?) -> (String, [SQLBindable]) {
        guard let r = range else { return ("", []) }
        return ("WHERE \(col) >= ? AND \(col) <= ?", [r.start, r.end])
    }

    /// Dump a SQL query as CSV, converting *_ts columns into ISO-8601 UTC strings (keeping the raw epoch too).
    public func queryCSV(_ sql: String, _ args: [SQLBindable] = []) throws -> String {
        let cols = try store.db.columnNames(sql)
        var header: [String] = []
        for c in cols {
            header.append(c)
            if c.hasSuffix("_ts") || c == "ts" { header.append(c == "ts" ? "time_utc" : String(c.dropLast(3)) + "_utc") }
        }
        let rows: [[String?]] = try store.db.query(sql, args).map { r in
            var out: [String?] = []
            for c in cols {
                let v = r[c]
                out.append(v == .null ? nil : v.description)
                if c.hasSuffix("_ts") || c == "ts" { out.append(Self.utc(r.date(c))) }
            }
            return out
        }
        return CSV.write(header: header, rows: rows)
    }

    // MARK: - GeoJSON

    func feature(_ geometry: [String: Any], _ props: [String: Any?]) -> [String: Any] {
        ["type": "Feature", "geometry": geometry, "properties": props.compactMapValues { $0 }]
    }

    public func placesGeoJSON() throws -> Data {
        let stats = try store.placeStats()
        let feats = try store.places().map { p -> [String: Any] in
            let s = stats[p.id]
            return feature(["type": "Point", "coordinates": [p.coordinate.longitude, p.coordinate.latitude]],
                           ["place_id": p.id, "name": p.name, "category": p.category?.rawValue, "code": p.code,
                            "radius_m": p.radius, "city": p.city, "country": p.country,
                            "visit_count": s?.visitCount, "total_dwell_h": s.map { $0.totalDwell / 3600 },
                            "first_visit": Self.utc(s?.firstVisit), "last_visit": Self.utc(s?.lastVisit)])
        }
        return try JSONSerialization.data(withJSONObject: ["type": "FeatureCollection", "features": feats], options: [.prettyPrinted, .sortedKeys])
    }

    public func tripsGeoJSON(range: DateRange?) throws -> Data {
        let feats = try tripRows(range: range).compactMap { r -> [String: Any]? in
            let route = r.trip.route
            guard route.count >= 2 else { return nil }
            return feature(["type": "LineString", "coordinates": route.map { [$0.longitude, $0.latitude] }],
                           ["trip_id": r.trip.id, "person_day_id": r.personDayID, "trip_seq": r.sequence,
                            "mode": r.trip.mode.rawValue, "purpose": r.purposeFinal?.rawValue,
                            "departure_local": Self.local(r.trip.departure, tz: r.trip.timeZone),
                            "arrival_local": Self.local(r.trip.arrival, tz: r.trip.timeZone),
                            "distance_m": r.trip.distance, "origin": r.originPlace?.displayName,
                            "destination": r.destinationPlace?.displayName])
        }
        return try JSONSerialization.data(withJSONObject: ["type": "FeatureCollection", "features": feats], options: [.sortedKeys])
    }

    public func tripEndsGeoJSON(range: DateRange?) throws -> Data {
        var feats: [[String: Any]] = []
        for r in try tripRows(range: range) {
            for (kind, c, p, t) in [("origin", r.origin, r.originPlace, r.trip.departure),
                                    ("destination", r.destination, r.destinationPlace, r.trip.arrival)] {
                guard let c else { continue }
                feats.append(feature(["type": "Point", "coordinates": [c.longitude, c.latitude]],
                                     ["trip_id": r.trip.id, "end": kind, "place_id": p?.id, "place_name": p?.displayName,
                                      "time_local": Self.local(t, tz: r.trip.timeZone), "mode": r.trip.mode.rawValue]))
            }
        }
        return try JSONSerialization.data(withJSONObject: ["type": "FeatureCollection", "features": feats], options: [.sortedKeys])
    }

    // MARK: - Full JSON

    public func fullJSON(range: DateRange?) throws -> Data {
        func rows(_ sql: String, _ args: [SQLBindable] = []) throws -> [[String: Any]] {
            try store.db.query(sql, args).map { r in
                r.columns.mapValues { v -> Any in
                    switch v {
                    case .null: return NSNull()
                    case .int(let i): return i
                    case .double(let d): return d
                    case .text(let s): return s
                    }
                }
            }
        }
        let (vw, va) = whereRange("arrival_ts", range)
        let (tw, ta) = whereRange("departure_ts", range)
        let (sw, sa) = whereRange("ts", range)
        let obj: [String: Any] = [
            "format": "hht-personal-travel-diary",
            "schema_version": store.schemaVersion,
            "exported_at": Self.utc(Date()) ?? "",
            "range": range.map { ["start": Self.utc($0.start) ?? "", "end": Self.utc($0.end) ?? ""] } ?? NSNull(),
            "places": try rows("SELECT * FROM places"),
            "visits": try rows("SELECT * FROM visits \(vw)", va),
            "trips": try rows("SELECT * FROM trips \(tw)", ta),
            "trip_segments": try rows("SELECT s.* FROM trip_segments s JOIN trips t ON t.id = s.trip_id \(tw.replacingOccurrences(of: "departure_ts", with: "t.departure_ts"))", ta),
            "flights": try rows("SELECT * FROM flights"),
            "journeys": try rows("SELECT * FROM journeys"),
            "journey_members": try rows("SELECT * FROM journey_members"),
            "life_phases": try rows("SELECT * FROM life_phases"),
            "stamps": try rows("SELECT * FROM stamps \(sw)", sa),
            "audit_log": try rows("SELECT * FROM audit_log"),
        ]
        return try JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
    }

    // MARK: - Bundle

    /// Write a complete export into a new timestamped folder under `directory`. Returns the folder URL.
    @discardableResult
    public func exportBundle(to directory: URL, options: Options = Options()) throws -> URL {
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyyMMdd-HHmmss"
        let folder = directory.appendingPathComponent("hht-export-\(stamp.string(from: Date()))", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        func write(_ name: String, _ s: String) throws { try s.write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8) }
        func write(_ name: String, _ d: Data) throws { try d.write(to: folder.appendingPathComponent(name)) }
        let r = options.range
        let (vw, va) = whereRange("arrival_ts", r)
        let (tw, ta) = whereRange("t.departure_ts", r)
        let (pw, pa) = whereRange("ts", r)

        if options.csv {
            try write("trips.csv", try tripsCSV(range: r))
            try write("trip_segments.csv", try queryCSV("""
                SELECT s.id AS segment_id, s.trip_id, s.seq, s.start_ts, s.end_ts,
                       COALESCE(s.mode_user, s.mode_auto, 'unknown') AS mode, s.mode_auto, s.mode_confidence, s.mode_user,
                       s.distance_m, s.route_polyline
                FROM trip_segments s JOIN trips t ON t.id = s.trip_id \(tw.isEmpty ? "WHERE" : tw + " AND") t.deleted = 0
                ORDER BY s.start_ts
                """, ta))
            try write("visits.csv", try queryCSV("""
                SELECT v.id AS visit_id, v.place_id, p.name AS place_name, p.category AS place_category,
                       v.arrival_ts, v.departure_ts, v.tz,
                       ROUND((COALESCE(v.departure_ts, strftime('%s','now')) - v.arrival_ts) / 60.0, 2) AS duration_min,
                       v.lat, v.lon, v.purpose, v.auto_confidence, v.source, v.user_status, v.point_count, v.notes
                FROM visits v LEFT JOIN places p ON p.id = v.place_id
                \(vw.isEmpty ? "WHERE" : vw.replacingOccurrences(of: "arrival_ts", with: "v.arrival_ts") + " AND") v.deleted = 0
                ORDER BY v.arrival_ts
                """, va))
            try write("places.csv", try queryCSV("""
                SELECT p.id AS place_id, p.name, p.category, p.code, p.lat, p.lon, p.radius_m, p.address, p.city, p.region,
                       p.country, p.favorite, p.source, p.merged_into, p.notes, p.created_at AS created_ts,
                       (SELECT COUNT(*) FROM visits v WHERE v.place_id = p.id AND v.deleted = 0) AS visit_count,
                       (SELECT MIN(arrival_ts) FROM visits v WHERE v.place_id = p.id AND v.deleted = 0) AS first_visit_ts,
                       (SELECT MAX(arrival_ts) FROM visits v WHERE v.place_id = p.id AND v.deleted = 0) AS last_visit_ts
                FROM places p WHERE p.deleted = 0 ORDER BY p.name
                """))
            try write("flights.csv", try queryCSV("SELECT id AS flight_id, * FROM flights ORDER BY date"))
            try write("life_phases.csv", try queryCSV("SELECT * FROM life_phases ORDER BY start_date"))
            try write("stamps.csv", try queryCSV("""
                SELECT s.id AS stamp_id, s.ts, s.tz, s.lat, s.lon, s.uncertainty_m, s.fix_accuracy_m, s.fix_age_s,
                       CASE WHEN v.id IS NULL THEN NULL ELSE s.visit_id END AS visit_id, s.note
                FROM stamps s LEFT JOIN visits v ON v.id = s.visit_id AND v.deleted = 0
                \(pw.isEmpty ? "WHERE" : pw.replacingOccurrences(of: "ts", with: "s.ts") + " AND") s.deleted = 0
                ORDER BY s.ts
                """, pa))
            try write("audit_log.csv", try queryCSV("SELECT * FROM audit_log ORDER BY id"))
            if options.includeRawPoints {
                try write("raw_location_points.csv", try queryCSV("SELECT * FROM raw_location_points \(pw) ORDER BY ts", pa))
                try write("motion_activities.csv", try queryCSV("SELECT * FROM motion_activities \(pw) ORDER BY ts", pa))
            }
        }
        if options.json { try write("data.json", try fullJSON(range: r)) }
        if options.geojson {
            try write("places.geojson", try placesGeoJSON())
            try write("trips.geojson", try tripsGeoJSON(range: r))
            try write("trip_ends.geojson", try tripEndsGeoJSON(range: r))
        }
        if options.includeSQLite { try store.backup(to: folder.appendingPathComponent("travel.sqlite")) }
        try write("README.txt", Self.readme(schemaVersion: store.schemaVersion))
        return folder
    }

    static func readme(schemaVersion: Int) -> String {
        """
        HHT personal travel diary export (schema v\(schemaVersion))

        trips.csv            one row per trip, HHTS-style (person_day_id = local date of departure, trip_seq within the day)
        trip_segments.csv    mode segments of multimodal trips (join on trip_id)
        visits.csv           stays / activities (join trips.origin_visit_id / destination_visit_id)
        places.csv           personal place database (join *_place_id)
        flights.csv          flights (optionally linked to trip_id)
        life_phases.csv      user-defined periods for comparisons
        stamps.csv           one-tap self-reports ("a stop happened around here, around now"); coarse location only;
                             visit_id = the visit inference attached it to, empty if unmatched
        audit_log.csv        every user correction (old → new)
        raw_location_points.csv, motion_activities.csv   raw sensor observations (if included)
        data.json            everything above with relationships, full fidelity
        *.geojson            places, trip routes (LineString), trip ends (Point) — WGS84
        travel.sqlite        complete database snapshot (open with sqlite3, DuckDB, R/DBI, pandas, QGIS)

        Times: *_utc columns are ISO-8601 UTC; *_local use the device time zone recorded in `tz`; *_ts are Unix seconds.
        Distances in metres. route_polyline = Google encoded polyline, precision 1e-5 (lat,lon).
        mode = user correction if present, else automatic classification (mode_auto, mode_confidence).
        Column definitions: docs/data-model.md in the app repository.
        """
    }
}
