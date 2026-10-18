import Foundation

/// Repository for every table. All times are stored as UTC Unix seconds (REAL); the device time zone
/// at record time is stored alongside in `tz`.
public final class TravelStore: @unchecked Sendable {
    public let db: SQLiteConnection

    public init(path: String) throws {
        db = try SQLiteConnection(path: path)
        try Schema.migrate(db)
    }

    public static func inMemory() throws -> TravelStore { try TravelStore(path: ":memory:") }

    public var schemaVersion: Int { db.userVersion }

    // MARK: - Meta

    public func meta(_ key: String) -> String? {
        (try? db.query("SELECT value FROM app_meta WHERE key = ?", key).first?.string("value")) ?? nil
    }

    public func setMeta(_ key: String, _ value: String?) throws {
        try db.run("INSERT INTO app_meta(key, value) VALUES(?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value", key, value)
    }

    // MARK: - Audit

    public func audit(_ entityType: String, _ entityID: String, _ action: String,
                      field: String? = nil, old: String? = nil, new: String? = nil) throws {
        try db.run("INSERT INTO audit_log(ts, entity_type, entity_id, action, field, old_value, new_value) VALUES (?,?,?,?,?,?,?)",
                   Date(), entityType, entityID, action, field, old, new)
    }

    public func auditLog(entityID: String) throws -> [AuditEntry] {
        try db.query("SELECT * FROM audit_log WHERE entity_id = ? ORDER BY id", entityID).map {
            AuditEntry(timestamp: $0.date("ts") ?? Date(), entityType: $0.string("entity_type") ?? "",
                       entityID: $0.string("entity_id") ?? "", action: $0.string("action") ?? "",
                       field: $0.string("field"), oldValue: $0.string("old_value"), newValue: $0.string("new_value"))
        }
    }

    // MARK: - Raw points

    @discardableResult
    public func insertPoint(_ p: RawPoint) throws -> Int64 {
        try db.run("""
            INSERT INTO raw_location_points(ts, lat, lon, h_accuracy, altitude, v_accuracy, speed, speed_accuracy,
                course, source, collector_mode, tz, inserted_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)
            """, p.timestamp, p.coordinate.latitude, p.coordinate.longitude, p.horizontalAccuracy, p.altitude,
            p.verticalAccuracy, p.speed, p.speedAccuracy, p.course, p.source, p.collectorMode, p.timeZone, Date())
        return db.lastInsertRowID
    }

    public func insertPoints(_ ps: [RawPoint]) throws {
        try db.transaction { for p in ps { try insertPoint(p) } }
    }

    public func points(from: Date, to: Date) throws -> [RawPoint] {
        try db.query("SELECT * FROM raw_location_points WHERE ts >= ? AND ts <= ? ORDER BY ts, id", from, to).map(Self.point)
    }

    public func pointCount() -> Int { (try? db.scalar("SELECT COUNT(*) FROM raw_location_points").description).flatMap { Int($0) } ?? 0 }

    public func firstPointDate() -> Date? {
        (try? db.query("SELECT MIN(ts) AS t FROM raw_location_points").first?.date("t")) ?? nil
    }

    public func lastPoint() -> RawPoint? {
        (try? db.query("SELECT * FROM raw_location_points ORDER BY ts DESC, id DESC LIMIT 1").first.map(Self.point)) ?? nil
    }

    static func point(_ r: Row) -> RawPoint {
        RawPoint(id: r.int("id").map(Int64.init), timestamp: r.date("ts") ?? Date(),
                 coordinate: Coordinate(r.double("lat") ?? 0, r.double("lon") ?? 0),
                 horizontalAccuracy: r.double("h_accuracy"), altitude: r.double("altitude"),
                 verticalAccuracy: r.double("v_accuracy"), speed: r.double("speed"),
                 speedAccuracy: r.double("speed_accuracy"), course: r.double("course"),
                 source: r.string("source") ?? "gps", collectorMode: r.string("collector_mode"), timeZone: r.string("tz"))
    }

    // MARK: - Motion

    public func insertMotion(_ samples: [MotionSample]) throws {
        try db.transaction {
            for s in samples {
                try db.run("INSERT OR IGNORE INTO motion_activities(ts, activity, confidence) VALUES (?,?,?)",
                           s.timestamp, s.activity.rawValue, s.confidence)
            }
        }
    }

    public func motion(from: Date, to: Date) throws -> [MotionSample] {
        // include the sample active at `from`
        let prior = try db.query("SELECT * FROM motion_activities WHERE ts < ? ORDER BY ts DESC LIMIT 1", from)
        let inRange = try db.query("SELECT * FROM motion_activities WHERE ts >= ? AND ts <= ? ORDER BY ts", from, to)
        return (prior + inRange).map {
            MotionSample(timestamp: $0.date("ts") ?? Date(),
                         activity: MotionSample.Activity(rawValue: $0.string("activity") ?? "") ?? .unknown,
                         confidence: $0.int("confidence") ?? 0)
        }
    }

    public func lastMotionDate() -> Date? {
        (try? db.query("SELECT MAX(ts) AS t FROM motion_activities").first?.date("t")) ?? nil
    }

    // MARK: - Places

    public func upsertPlace(_ p: Place) throws {
        try db.run("""
            INSERT INTO places(id, name, lat, lon, radius_m, address, city, region, country, category, code, favorite,
                notes, source, merged_into, deleted, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            ON CONFLICT(id) DO UPDATE SET name=excluded.name, lat=excluded.lat, lon=excluded.lon,
                radius_m=excluded.radius_m, address=excluded.address, city=excluded.city, region=excluded.region,
                country=excluded.country, category=excluded.category, code=excluded.code, favorite=excluded.favorite,
                notes=excluded.notes, source=excluded.source, merged_into=excluded.merged_into,
                deleted=excluded.deleted, updated_at=excluded.updated_at
            """, p.id, p.name, p.coordinate.latitude, p.coordinate.longitude, p.radius, p.address, p.city, p.region,
            p.country, p.category?.rawValue, p.code, p.favorite, p.notes, p.source.rawValue, p.mergedInto,
            p.deleted, p.createdAt, p.updatedAt)
    }

    public func place(_ id: String) throws -> Place? {
        try db.query("SELECT * FROM places WHERE id = ?", id).first.map(Self.place)
    }

    /// Active (non-merged, non-deleted) places.
    public func places() throws -> [Place] {
        try db.query("SELECT * FROM places WHERE merged_into IS NULL AND deleted = 0 ORDER BY name IS NULL, name COLLATE NOCASE").map(Self.place)
    }

    /// Nearest active place whose radius (plus `slack`) contains the coordinate.
    public func matchPlace(_ c: Coordinate, slack: Double = 0) throws -> Place? {
        // coarse bounding box prefilter (~2 km), exact test in Swift
        let dLat = 0.02, dLon = 0.02 / max(0.1, cos(c.latitude * .pi / 180))
        let candidates = try db.query("""
            SELECT * FROM places WHERE merged_into IS NULL AND deleted = 0 AND lat BETWEEN ? AND ? AND lon BETWEEN ? AND ?
            """, c.latitude - dLat, c.latitude + dLat, c.longitude - dLon, c.longitude + dLon).map(Self.place)
        return candidates
            .map { ($0, Geo.distance($0.coordinate, c)) }
            .filter { $0.1 <= $0.0.radius + slack }
            .min { a, b in
                // prefer named places, then nearest
                if a.0.isNamed != b.0.isNamed { return a.0.isNamed }
                return a.1 < b.1
            }?.0
    }

    public func placesNear(_ c: Coordinate, within meters: Double) throws -> [Place] {
        try places().filter { Geo.distance($0.coordinate, c) <= meters }
            .sorted { Geo.distance($0.coordinate, c) < Geo.distance($1.coordinate, c) }
    }

    /// Remove inferred, unnamed, uncategorised places that no longer have any visit.
    public func pruneOrphanPlaces() throws {
        try db.run("""
            DELETE FROM places WHERE source = 'inferred' AND name IS NULL AND category IS NULL AND merged_into IS NULL
              AND notes IS NULL AND favorite = 0
              AND id NOT IN (SELECT place_id FROM visits WHERE place_id IS NOT NULL)
              AND id NOT IN (SELECT merged_into FROM places WHERE merged_into IS NOT NULL)
            """)
    }

    static func place(_ r: Row) -> Place {
        Place(id: r.string("id") ?? "", name: r.string("name"),
              coordinate: Coordinate(r.double("lat") ?? 0, r.double("lon") ?? 0), radius: r.double("radius_m") ?? 100,
              address: r.string("address"), city: r.string("city"), region: r.string("region"), country: r.string("country"),
              category: r.string("category").flatMap(PlaceCategory.init(rawValue:)), code: r.string("code"),
              favorite: r.bool("favorite"), notes: r.string("notes"),
              source: RecordSource(rawValue: r.string("source") ?? "") ?? .inferred, mergedInto: r.string("merged_into"),
              deleted: r.bool("deleted"), createdAt: r.date("created_at") ?? Date(), updatedAt: r.date("updated_at") ?? Date())
    }

    public struct PlaceStats: Sendable {
        public var visitCount: Int
        public var totalDwell: TimeInterval
        public var firstVisit: Date?
        public var lastVisit: Date?
    }

    public func placeStats() throws -> [String: PlaceStats] {
        let now = Date().timeIntervalSince1970
        var out: [String: PlaceStats] = [:]
        for r in try db.query("""
            SELECT place_id, COUNT(*) AS n, SUM(COALESCE(departure_ts, ?) - arrival_ts) AS dwell,
                   MIN(arrival_ts) AS first, MAX(arrival_ts) AS last
            FROM visits WHERE deleted = 0 AND place_id IS NOT NULL GROUP BY place_id
            """, now) {
            if let id = r.string("place_id") {
                out[id] = PlaceStats(visitCount: r.int("n") ?? 0, totalDwell: r.double("dwell") ?? 0,
                                     firstVisit: r.date("first"), lastVisit: r.date("last"))
            }
        }
        return out
    }

    // MARK: - Visits

    public func upsertVisit(_ v: Visit) throws {
        try db.run("""
            INSERT INTO visits(id, place_id, arrival_ts, departure_ts, lat, lon, purpose, auto_confidence, source,
                user_status, deleted, tz, point_count, notes, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            ON CONFLICT(id) DO UPDATE SET place_id=excluded.place_id, arrival_ts=excluded.arrival_ts,
                departure_ts=excluded.departure_ts, lat=excluded.lat, lon=excluded.lon, purpose=excluded.purpose,
                auto_confidence=excluded.auto_confidence, source=excluded.source, user_status=excluded.user_status,
                deleted=excluded.deleted, tz=excluded.tz, point_count=excluded.point_count, notes=excluded.notes,
                updated_at=excluded.updated_at
            """, v.id, v.placeID, v.arrival, v.departure, v.coordinate.latitude, v.coordinate.longitude,
            v.purpose?.rawValue, v.autoConfidence, v.source.rawValue, v.userStatus.rawValue, v.deleted, v.timeZone,
            v.pointCount, v.notes, v.createdAt, v.updatedAt)
    }

    public func visit(_ id: String) throws -> Visit? {
        try db.query("SELECT * FROM visits WHERE id = ?", id).first.map(Self.visit)
    }

    /// Visits overlapping [from, to]. Ongoing visits (no departure) extend to +∞.
    public func visits(overlapping from: Date, _ to: Date, includeDeleted: Bool = false) throws -> [Visit] {
        try db.query("""
            SELECT * FROM visits WHERE arrival_ts <= ? AND (departure_ts IS NULL OR departure_ts >= ?)
            \(includeDeleted ? "" : "AND deleted = 0") ORDER BY arrival_ts
            """, to, from).map(Self.visit)
    }

    public func visits(atPlace placeID: String) throws -> [Visit] {
        try db.query("SELECT * FROM visits WHERE place_id = ? AND deleted = 0 ORDER BY arrival_ts DESC", placeID).map(Self.visit)
    }

    public func allVisits() throws -> [Visit] {
        try db.query("SELECT * FROM visits WHERE deleted = 0 ORDER BY arrival_ts").map(Self.visit)
    }

    public func latestVisit(includeDeleted: Bool = false) throws -> Visit? {
        try db.query("SELECT * FROM visits \(includeDeleted ? "" : "WHERE deleted = 0") ORDER BY arrival_ts DESC LIMIT 1")
            .first.map(Self.visit)
    }

    static func visit(_ r: Row) -> Visit {
        Visit(id: r.string("id") ?? "", placeID: r.string("place_id"), arrival: r.date("arrival_ts") ?? Date(),
              departure: r.date("departure_ts"), coordinate: Coordinate(r.double("lat") ?? 0, r.double("lon") ?? 0),
              purpose: r.string("purpose").flatMap(TripPurpose.init(rawValue:)), autoConfidence: r.double("auto_confidence"),
              source: RecordSource(rawValue: r.string("source") ?? "") ?? .inferred,
              userStatus: UserStatus(rawValue: r.string("user_status") ?? "") ?? .auto, deleted: r.bool("deleted"),
              timeZone: r.string("tz"), pointCount: r.int("point_count"), notes: r.string("notes"),
              createdAt: r.date("created_at") ?? Date(), updatedAt: r.date("updated_at") ?? Date())
    }

    // MARK: - Trips

    public func upsertTrip(_ t: Trip, replaceSegments: Bool = true) throws {
        try db.transaction {
            try db.run("""
                INSERT INTO trips(id, origin_visit_id, destination_visit_id, origin_place_id, destination_place_id, departure_ts, arrival_ts, distance_m, mode_auto,
                    mode_confidence, mode_user, purpose, route_polyline, has_gap, auto_confidence, source, user_status, deleted,
                    tz, notes, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET origin_visit_id=excluded.origin_visit_id,
                    origin_place_id=excluded.origin_place_id, destination_place_id=excluded.destination_place_id,
                    destination_visit_id=excluded.destination_visit_id, departure_ts=excluded.departure_ts,
                    arrival_ts=excluded.arrival_ts, distance_m=excluded.distance_m, mode_auto=excluded.mode_auto,
                    mode_confidence=excluded.mode_confidence, mode_user=excluded.mode_user, purpose=excluded.purpose,
                    route_polyline=excluded.route_polyline, has_gap=excluded.has_gap, auto_confidence=excluded.auto_confidence,
                    source=excluded.source, user_status=excluded.user_status, deleted=excluded.deleted, tz=excluded.tz,
                    notes=excluded.notes, updated_at=excluded.updated_at
                """, t.id, t.originVisitID, t.destinationVisitID, t.originPlaceID, t.destinationPlaceID, t.departure, t.arrival, t.distance, t.modeAuto?.rawValue,
                t.modeConfidence, t.modeUser?.rawValue, t.purpose?.rawValue, t.routePolyline, t.hasGap, t.autoConfidence,
                t.source.rawValue, t.userStatus.rawValue, t.deleted, t.timeZone, t.notes, t.createdAt, t.updatedAt)
            if replaceSegments {
                try db.run("DELETE FROM trip_segments WHERE trip_id = ?", t.id)
                for s in t.segments {
                    try db.run("""
                        INSERT INTO trip_segments(id, trip_id, seq, start_ts, end_ts, mode_auto, mode_confidence, mode_user,
                            distance_m, route_polyline) VALUES (?,?,?,?,?,?,?,?,?,?)
                        """, s.id, t.id, s.sequence, s.start, s.end, s.modeAuto?.rawValue, s.modeConfidence,
                        s.modeUser?.rawValue, s.distance, s.routePolyline)
                }
            }
        }
    }

    public func trip(_ id: String) throws -> Trip? {
        guard var t = try db.query("SELECT * FROM trips WHERE id = ?", id).first.map(Self.trip) else { return nil }
        t.segments = try segments(tripID: id)
        return t
    }

    public func segments(tripID: String) throws -> [TripSegment] {
        try db.query("SELECT * FROM trip_segments WHERE trip_id = ? ORDER BY seq", tripID).map {
            TripSegment(id: $0.string("id") ?? "", tripID: tripID, sequence: $0.int("seq") ?? 0,
                        start: $0.date("start_ts") ?? Date(), end: $0.date("end_ts") ?? Date(),
                        modeAuto: $0.string("mode_auto").flatMap(TravelMode.init(rawValue:)),
                        modeConfidence: $0.double("mode_confidence"),
                        modeUser: $0.string("mode_user").flatMap(TravelMode.init(rawValue:)),
                        distance: $0.double("distance_m") ?? 0, routePolyline: $0.string("route_polyline"))
        }
    }

    public func trips(overlapping from: Date, _ to: Date, includeDeleted: Bool = false, withSegments: Bool = true) throws -> [Trip] {
        var ts = try db.query("""
            SELECT * FROM trips WHERE departure_ts <= ? AND arrival_ts >= ? \(includeDeleted ? "" : "AND deleted = 0")
            ORDER BY departure_ts
            """, to, from).map(Self.trip)
        if withSegments { for i in ts.indices { ts[i].segments = try segments(tripID: ts[i].id) } }
        return ts
    }

    public func allTrips(withSegments: Bool = false) throws -> [Trip] {
        try trips(overlapping: .distantPast, .distantFuture, withSegments: withSegments)
    }

    public func tripsReferencing(visitID: String, includeDeleted: Bool = false) throws -> [Trip] {
        try db.query("SELECT * FROM trips WHERE (origin_visit_id = ? OR destination_visit_id = ?)"
                     + (includeDeleted ? "" : " AND deleted = 0"), visitID, visitID).map(Self.trip)
    }

    /// When the user last cleared this visit's departure ("still here"), if that is their latest time edit.
    public func heldOpenAt(visitID: String) throws -> Date? {
        guard let r = try db.query("""
            SELECT ts, new_value FROM audit_log
            WHERE entity_id = ? AND action = 'set_times' AND field = 'departure_ts' ORDER BY id DESC LIMIT 1
            """, visitID).first, r.string("new_value") == nil else { return nil }
        return r.date("ts")
    }

    static func trip(_ r: Row) -> Trip {
        Trip(id: r.string("id") ?? "", originVisitID: r.string("origin_visit_id"),
             destinationVisitID: r.string("destination_visit_id"), originPlaceID: r.string("origin_place_id"),
             destinationPlaceID: r.string("destination_place_id"), departure: r.date("departure_ts") ?? Date(),
             arrival: r.date("arrival_ts") ?? Date(), distance: r.double("distance_m") ?? 0,
             modeAuto: r.string("mode_auto").flatMap(TravelMode.init(rawValue:)), modeConfidence: r.double("mode_confidence"),
             modeUser: r.string("mode_user").flatMap(TravelMode.init(rawValue:)),
             purpose: r.string("purpose").flatMap(TripPurpose.init(rawValue:)), routePolyline: r.string("route_polyline"),
             hasGap: r.bool("has_gap"), autoConfidence: r.double("auto_confidence"),
             source: RecordSource(rawValue: r.string("source") ?? "") ?? .inferred,
             userStatus: UserStatus(rawValue: r.string("user_status") ?? "") ?? .auto, deleted: r.bool("deleted"),
             timeZone: r.string("tz"), notes: r.string("notes"), createdAt: r.date("created_at") ?? Date(),
             updatedAt: r.date("updated_at") ?? Date())
    }

    /// Mode chosen by the user on previous trips between the same two places (most recent first).
    public func correctedModes(originPlaceID: String, destinationPlaceID: String) throws -> [TravelMode] {
        try db.query("""
            SELECT t.mode_user FROM trips t
            JOIN visits o ON o.id = t.origin_visit_id JOIN visits d ON d.id = t.destination_visit_id
            WHERE t.deleted = 0 AND t.mode_user IS NOT NULL AND o.place_id = ? AND d.place_id = ?
            ORDER BY t.departure_ts DESC LIMIT 20
            """, originPlaceID, destinationPlaceID).compactMap { $0.string("mode_user").flatMap(TravelMode.init(rawValue:)) }
    }

    /// The user's most frequently chosen modes, for ordering quick-pick chips.
    public func frequentModes(limit: Int = 4) throws -> [TravelMode] {
        try db.query("""
            SELECT COALESCE(mode_user, mode_auto) AS m, COUNT(*) AS n FROM trips
            WHERE deleted = 0 AND COALESCE(mode_user, mode_auto) NOT IN ('unknown') GROUP BY m ORDER BY n DESC LIMIT ?
            """, limit).compactMap { $0.string("m").flatMap(TravelMode.init(rawValue:)) }
    }

    public func reviewCount(since: Date? = nil) throws -> Int {
        let rows = try db.query("""
            SELECT COUNT(*) AS n FROM trips WHERE deleted = 0 AND user_status = 'auto'
            AND (mode_auto IS NULL OR mode_auto = 'unknown' OR COALESCE(mode_confidence, 0) < 0.5)
            AND departure_ts >= ?
            """, since ?? .distantPast)
        return rows.first?.int("n") ?? 0
    }

    // MARK: - Flights

    public func upsertFlight(_ f: Flight) throws {
        try db.run("""
            INSERT INTO flights(id, trip_id, journey_id, date, origin_code, destination_code, origin_lat, origin_lon,
                destination_lat, destination_lon, departure_ts, arrival_ts, airline, flight_number, aircraft_type, seat, cabin,
                distance_m, booking_reference, notes, source, created_at, updated_at)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            ON CONFLICT(id) DO UPDATE SET trip_id=excluded.trip_id, journey_id=excluded.journey_id, date=excluded.date,
                origin_code=excluded.origin_code, destination_code=excluded.destination_code, origin_lat=excluded.origin_lat,
                origin_lon=excluded.origin_lon, destination_lat=excluded.destination_lat,
                destination_lon=excluded.destination_lon, departure_ts=excluded.departure_ts, arrival_ts=excluded.arrival_ts,
                airline=excluded.airline, flight_number=excluded.flight_number, aircraft_type=excluded.aircraft_type,
                seat=excluded.seat, cabin=excluded.cabin, distance_m=excluded.distance_m,
                booking_reference=excluded.booking_reference, notes=excluded.notes, source=excluded.source,
                updated_at=excluded.updated_at
            """, f.id, f.tripID, f.journeyID, f.date, f.originCode, f.destinationCode, f.origin?.latitude, f.origin?.longitude,
            f.destination?.latitude, f.destination?.longitude, f.departure, f.arrival, f.airline, f.flightNumber,
            f.aircraftType, f.seat, f.cabin, f.distance ?? f.effectiveDistance, f.bookingReference, f.notes,
            f.source.rawValue, f.createdAt, f.updatedAt)
    }

    public func flights() throws -> [Flight] {
        try db.query("SELECT * FROM flights ORDER BY date DESC, departure_ts DESC").map(Self.flight)
    }

    public func flight(tripID: String) throws -> Flight? {
        try db.query("SELECT * FROM flights WHERE trip_id = ?", tripID).first.map(Self.flight)
    }

    /// An inferred flight that lost its trip (the trip was rebuilt or deleted) and overlaps the given window.
    public func unlinkedFlight(overlapping start: Date, _ end: Date) throws -> Flight? {
        try db.query("""
            SELECT * FROM flights WHERE trip_id IS NULL AND source = 'inferred'
              AND departure_ts <= ? AND COALESCE(arrival_ts, departure_ts) >= ?
            ORDER BY updated_at DESC LIMIT 1
            """, end, start).first.map(Self.flight)
    }

    /// Drop inferred flights that have no trip and nothing the user typed into them.
    public func pruneOrphanFlights() throws {
        try db.run("""
            DELETE FROM flights WHERE trip_id IS NULL AND journey_id IS NULL AND source = 'inferred'
              AND airline IS NULL AND flight_number IS NULL AND aircraft_type IS NULL AND seat IS NULL
              AND cabin IS NULL AND booking_reference IS NULL AND notes IS NULL
              AND updated_at - created_at < 1
            """)
    }

    public func deleteFlight(_ id: String) throws {
        try db.run("DELETE FROM flights WHERE id = ?", id)
        try audit("flight", id, "delete")
    }

    static func flight(_ r: Row) -> Flight {
        func coord(_ a: String, _ b: String) -> Coordinate? {
            guard let la = r.double(a), let lo = r.double(b) else { return nil }
            return Coordinate(la, lo)
        }
        return Flight(id: r.string("id") ?? "", tripID: r.string("trip_id"), journeyID: r.string("journey_id"),
                      date: r.string("date") ?? "", originCode: r.string("origin_code"),
                      destinationCode: r.string("destination_code"), origin: coord("origin_lat", "origin_lon"),
                      destination: coord("destination_lat", "destination_lon"), departure: r.date("departure_ts"),
                      arrival: r.date("arrival_ts"), airline: r.string("airline"), flightNumber: r.string("flight_number"),
                      aircraftType: r.string("aircraft_type"), seat: r.string("seat"), cabin: r.string("cabin"),
                      distance: r.double("distance_m"), bookingReference: r.string("booking_reference"),
                      notes: r.string("notes"), source: RecordSource(rawValue: r.string("source") ?? "") ?? .manual,
                      createdAt: r.date("created_at") ?? Date(), updatedAt: r.date("updated_at") ?? Date())
    }

    // MARK: - Stamps

    public func insertStamp(_ s: Stamp) throws {
        try db.run("""
            INSERT INTO stamps(id, ts, lat, lon, uncertainty_m, fix_accuracy_m, fix_age_s, visit_id, note, tz, deleted,
                created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)
            """, s.id, s.timestamp, s.coordinate?.latitude, s.coordinate?.longitude, s.uncertainty, s.fixAccuracy,
            s.fixAge, s.visitID, s.note, s.timeZone, s.deleted, s.createdAt, s.updatedAt)
    }

    public func stamp(_ id: String) throws -> Stamp? {
        try db.query("SELECT * FROM stamps WHERE id = ?", id).first.map(Self.stamp)
    }

    /// Stamps tapped within [from, to], oldest first.
    public func stamps(from: Date, to: Date, includeDeleted: Bool = false) throws -> [Stamp] {
        try db.query("""
            SELECT * FROM stamps WHERE ts >= ? AND ts <= ? \(includeDeleted ? "" : "AND deleted = 0") ORDER BY ts
            """, from, to).map(Self.stamp)
    }

    /// Stamps inference attached to a visit, oldest first.
    public func stamps(visitID: String) throws -> [Stamp] {
        try db.query("SELECT * FROM stamps WHERE visit_id = ? AND deleted = 0 ORDER BY ts", visitID).map(Self.stamp)
    }

    /// Inference's only write to a stamp: which visit it belongs to (nil = unmatched).
    func setStampVisit(_ stampID: String, _ visitID: String?) throws {
        try db.run("UPDATE stamps SET visit_id = ? WHERE id = ? AND visit_id IS NOT ?", visitID, stampID, visitID)
    }

    static func stamp(_ r: Row) -> Stamp {
        var c: Coordinate?
        if let la = r.double("lat"), let lo = r.double("lon") { c = Coordinate(la, lo) }
        return Stamp(id: r.string("id") ?? "", timestamp: r.date("ts") ?? Date(), coordinate: c,
                     uncertainty: r.double("uncertainty_m"), fixAccuracy: r.double("fix_accuracy_m"),
                     fixAge: r.double("fix_age_s"), visitID: r.string("visit_id"), note: r.string("note"),
                     timeZone: r.string("tz"), deleted: r.bool("deleted"),
                     createdAt: r.date("created_at") ?? Date(), updatedAt: r.date("updated_at") ?? Date())
    }

    // MARK: - Life phases

    public func upsertLifePhase(_ p: LifePhase) throws {
        try db.run("""
            INSERT INTO life_phases(id, name, kind, start_date, end_date, notes, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?)
            ON CONFLICT(id) DO UPDATE SET name=excluded.name, kind=excluded.kind, start_date=excluded.start_date,
                end_date=excluded.end_date, notes=excluded.notes, updated_at=excluded.updated_at
            """, p.id, p.name, p.kind, p.startDate, p.endDate, p.notes, Date(), Date())
    }

    public func lifePhases() throws -> [LifePhase] {
        try db.query("SELECT * FROM life_phases ORDER BY start_date DESC").map {
            LifePhase(id: $0.string("id") ?? "", name: $0.string("name") ?? "", kind: $0.string("kind"),
                      startDate: $0.string("start_date") ?? "", endDate: $0.string("end_date"), notes: $0.string("notes"))
        }
    }

    public func deleteLifePhase(_ id: String) throws { try db.run("DELETE FROM life_phases WHERE id = ?", id) }

    // MARK: - Maintenance

    /// Write a consistent, self-contained copy of the database (for backup / analysis in R, Python, QGIS…).
    public func backup(to url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        try db.run("VACUUM INTO ?", url.path)
    }

    public func counts() -> [String: Int] {
        var out: [String: Int] = [:]
        for t in ["raw_location_points", "motion_activities", "places", "visits", "trips", "trip_segments", "flights", "stamps", "audit_log"] {
            out[t] = (try? db.scalar("SELECT COUNT(*) FROM \(t)").description).flatMap { Int($0) } ?? 0
        }
        return out
    }

    /// Permanently erase everything (user-initiated from Settings).
    public func eraseAll() throws {
        try db.transaction {
            for t in ["journey_members", "trip_segments", "flights", "trips", "visits", "journeys", "places",
                      "raw_location_points", "motion_activities", "stamps", "life_phases", "audit_log", "app_meta"] {
                try db.run("DELETE FROM \(t)")
            }
        }
    }
}
