import Foundation

/// Ordered list of schema migrations. Never edit a shipped migration — append a new one.
/// The applied version is tracked in `PRAGMA user_version`.
enum Schema {
    static let migrations: [String] = [
        // v1 — initial schema
        """
        CREATE TABLE app_meta (
            key   TEXT PRIMARY KEY,
            value TEXT
        );

        -- Layer 1: raw observations (append-only)
        CREATE TABLE raw_location_points (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            ts              REAL NOT NULL,
            lat             REAL NOT NULL,
            lon             REAL NOT NULL,
            h_accuracy      REAL,
            altitude        REAL,
            v_accuracy      REAL,
            speed           REAL,
            speed_accuracy  REAL,
            course          REAL,
            source          TEXT NOT NULL,
            collector_mode  TEXT,
            tz              TEXT,
            inserted_at     REAL NOT NULL
        );
        CREATE INDEX idx_raw_ts ON raw_location_points(ts);

        CREATE TABLE motion_activities (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            ts          REAL NOT NULL,
            activity    TEXT NOT NULL,
            confidence  INTEGER NOT NULL,
            UNIQUE(ts, activity)
        );
        CREATE INDEX idx_motion_ts ON motion_activities(ts);

        -- Personal place database
        CREATE TABLE places (
            id          TEXT PRIMARY KEY,
            name        TEXT,
            lat         REAL NOT NULL,
            lon         REAL NOT NULL,
            radius_m    REAL NOT NULL DEFAULT 100,
            address     TEXT,
            city        TEXT,
            region      TEXT,
            country     TEXT,
            category    TEXT,
            code        TEXT,
            favorite    INTEGER NOT NULL DEFAULT 0,
            notes       TEXT,
            source      TEXT NOT NULL,
            merged_into TEXT REFERENCES places(id),
            created_at  REAL NOT NULL,
            updated_at  REAL NOT NULL
        );

        -- Layers 2+3: derived records; user_status != 'auto' marks the user-corrected canonical record
        CREATE TABLE visits (
            id              TEXT PRIMARY KEY,
            place_id        TEXT REFERENCES places(id),
            arrival_ts      REAL NOT NULL,
            departure_ts    REAL,
            lat             REAL NOT NULL,
            lon             REAL NOT NULL,
            purpose         TEXT,
            auto_confidence REAL,
            source          TEXT NOT NULL,
            user_status     TEXT NOT NULL DEFAULT 'auto',
            deleted         INTEGER NOT NULL DEFAULT 0,
            tz              TEXT,
            point_count     INTEGER,
            notes           TEXT,
            created_at      REAL NOT NULL,
            updated_at      REAL NOT NULL
        );
        CREATE INDEX idx_visits_arrival ON visits(arrival_ts);
        CREATE INDEX idx_visits_place ON visits(place_id);

        CREATE TABLE trips (
            id                   TEXT PRIMARY KEY,
            origin_visit_id      TEXT REFERENCES visits(id),
            destination_visit_id TEXT REFERENCES visits(id),
            origin_place_id      TEXT REFERENCES places(id),
            destination_place_id TEXT REFERENCES places(id),
            departure_ts         REAL NOT NULL,
            arrival_ts           REAL NOT NULL,
            distance_m           REAL,
            mode_auto            TEXT,
            mode_confidence      REAL,
            mode_user            TEXT,
            purpose              TEXT,
            route_polyline       TEXT,
            has_gap              INTEGER NOT NULL DEFAULT 0,
            auto_confidence      REAL,
            source               TEXT NOT NULL,
            user_status          TEXT NOT NULL DEFAULT 'auto',
            deleted              INTEGER NOT NULL DEFAULT 0,
            tz                   TEXT,
            notes                TEXT,
            created_at           REAL NOT NULL,
            updated_at           REAL NOT NULL
        );
        CREATE INDEX idx_trips_departure ON trips(departure_ts);

        CREATE TABLE trip_segments (
            id              TEXT PRIMARY KEY,
            trip_id         TEXT NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
            seq             INTEGER NOT NULL,
            start_ts        REAL NOT NULL,
            end_ts          REAL NOT NULL,
            mode_auto       TEXT,
            mode_confidence REAL,
            mode_user       TEXT,
            distance_m      REAL,
            route_polyline  TEXT
        );
        CREATE INDEX idx_segments_trip ON trip_segments(trip_id);

        CREATE TABLE journeys (
            id               TEXT PRIMARY KEY,
            name             TEXT NOT NULL,
            start_ts         REAL,
            end_ts           REAL,
            origin_city      TEXT,
            destination_city TEXT,
            journey_type     TEXT,
            notes            TEXT,
            created_at       REAL NOT NULL,
            updated_at       REAL NOT NULL
        );

        CREATE TABLE flights (
            id                TEXT PRIMARY KEY,
            trip_id           TEXT REFERENCES trips(id),
            journey_id        TEXT REFERENCES journeys(id),
            date              TEXT NOT NULL,
            origin_code       TEXT,
            destination_code  TEXT,
            origin_lat        REAL,
            origin_lon        REAL,
            destination_lat   REAL,
            destination_lon   REAL,
            departure_ts      REAL,
            arrival_ts        REAL,
            airline           TEXT,
            flight_number     TEXT,
            aircraft_type     TEXT,
            seat              TEXT,
            cabin             TEXT,
            distance_m        REAL,
            booking_reference TEXT,
            notes             TEXT,
            source            TEXT NOT NULL,
            created_at        REAL NOT NULL,
            updated_at        REAL NOT NULL
        );
        CREATE INDEX idx_flights_date ON flights(date);

        CREATE TABLE journey_members (
            journey_id  TEXT NOT NULL REFERENCES journeys(id) ON DELETE CASCADE,
            member_type TEXT NOT NULL,
            member_id   TEXT NOT NULL,
            seq         INTEGER NOT NULL,
            PRIMARY KEY (journey_id, member_type, member_id)
        );

        CREATE TABLE life_phases (
            id          TEXT PRIMARY KEY,
            name        TEXT NOT NULL,
            kind        TEXT,
            start_date  TEXT NOT NULL,
            end_date    TEXT,
            notes       TEXT,
            created_at  REAL NOT NULL,
            updated_at  REAL NOT NULL
        );

        -- Reference data: airports (from OurAirports, public domain; downloaded on request)
        CREATE TABLE airports (
            iata         TEXT PRIMARY KEY,
            icao         TEXT,
            name         TEXT NOT NULL,
            municipality TEXT,
            country      TEXT,
            lat          REAL NOT NULL,
            lon          REAL NOT NULL,
            type         TEXT
        );

        CREATE TABLE audit_log (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            ts          REAL NOT NULL,
            entity_type TEXT NOT NULL,
            entity_id   TEXT NOT NULL,
            action      TEXT NOT NULL,
            field       TEXT,
            old_value   TEXT,
            new_value   TEXT
        );
        CREATE INDEX idx_audit_entity ON audit_log(entity_type, entity_id);

        -- Convenience views for analysis (active records, final values resolved)
        CREATE VIEW v_visits AS
        SELECT v.*,
               p.name AS place_name, p.category AS place_category,
               COALESCE(v.departure_ts, strftime('%s','now')) - v.arrival_ts AS duration_s
        FROM visits v LEFT JOIN places p ON p.id = v.place_id
        WHERE v.deleted = 0;

        CREATE VIEW v_trips AS
        SELECT t.*,
               COALESCE(t.mode_user, t.mode_auto, 'unknown') AS mode_final,
               COALESCE(t.purpose, dv.purpose, CASE dp.category
                   WHEN 'home' THEN 'home' WHEN 'work_school' THEN 'work'
                   WHEN 'restaurant' THEN 'meal' WHEN 'cafe' THEN 'meal'
                   WHEN 'grocery' THEN 'shopping' WHEN 'shopping' THEN 'shopping'
                   WHEN 'recreation' THEN 'recreation' WHEN 'entertainment' THEN 'recreation'
                   WHEN 'airport' THEN 'travel' WHEN 'rail_station' THEN 'travel' WHEN 'hotel' THEN 'travel'
                   WHEN 'transit_station' THEN 'transfer' WHEN 'friend_family' THEN 'social'
                   WHEN 'medical' THEN 'medical' END) AS purpose_final,
               t.arrival_ts - t.departure_ts AS duration_s,
               COALESCE(ov.place_id, t.origin_place_id) AS origin_place_final,
               COALESCE(dv.place_id, t.destination_place_id) AS destination_place_final
        FROM trips t
        LEFT JOIN visits ov ON ov.id = t.origin_visit_id
        LEFT JOIN visits dv ON dv.id = t.destination_visit_id
        LEFT JOIN places dp ON dp.id = COALESCE(dv.place_id, t.destination_place_id)
        WHERE t.deleted = 0;
        """,
        // v2 — places can be deleted by the user (soft delete, like visits and trips)
        """
        ALTER TABLE places ADD COLUMN deleted INTEGER NOT NULL DEFAULT 0;
        """,
        // v3 — self-reported stamps ("something worth recording happened around here, around now"; issue #32).
        // A user observation like the raw tables: inference only ever writes visit_id (the visit it attached the
        // stamp to). visit_id has no foreign key because inference replaces auto visits by deleting them.
        """
        CREATE TABLE stamps (
            id              TEXT PRIMARY KEY,
            ts              REAL NOT NULL,
            lat             REAL,
            lon             REAL,
            uncertainty_m   REAL,
            fix_accuracy_m  REAL,
            fix_age_s       REAL,
            visit_id        TEXT,
            note            TEXT,
            tz              TEXT,
            deleted         INTEGER NOT NULL DEFAULT 0,
            created_at      REAL NOT NULL,
            updated_at      REAL NOT NULL
        );
        CREATE INDEX idx_stamps_ts ON stamps(ts);
        """,
        // v4 — more place categories (issue #56): v_trips resolves their default purposes.
        // The CASE must match PlaceCategory.defaultPurpose (checked by a test).
        """
        DROP VIEW v_trips;
        CREATE VIEW v_trips AS
        SELECT t.*,
               COALESCE(t.mode_user, t.mode_auto, 'unknown') AS mode_final,
               COALESCE(t.purpose, dv.purpose, CASE dp.category
                   WHEN 'home' THEN 'home' WHEN 'work_school' THEN 'work'
                   WHEN 'restaurant' THEN 'meal' WHEN 'cafe' THEN 'meal'
                   WHEN 'grocery' THEN 'shopping' WHEN 'shopping' THEN 'shopping'
                   WHEN 'convenience_store' THEN 'shopping' WHEN 'gas_station' THEN 'shopping'
                   WHEN 'recreation' THEN 'recreation' WHEN 'entertainment' THEN 'recreation'
                   WHEN 'stadium' THEN 'recreation' WHEN 'event_venue' THEN 'recreation'
                   WHEN 'museum' THEN 'recreation' WHEN 'library' THEN 'recreation' WHEN 'gym' THEN 'recreation'
                   WHEN 'airport' THEN 'travel' WHEN 'rail_station' THEN 'travel' WHEN 'hotel' THEN 'travel'
                   WHEN 'transit_station' THEN 'transfer' WHEN 'parking' THEN 'transfer'
                   WHEN 'friend_family' THEN 'social' WHEN 'bar' THEN 'social' WHEN 'religious' THEN 'social'
                   WHEN 'medical' THEN 'medical' WHEN 'pharmacy' THEN 'medical'
                   WHEN 'bank' THEN 'personal_business' WHEN 'civic' THEN 'personal_business' END) AS purpose_final,
               t.arrival_ts - t.departure_ts AS duration_s,
               COALESCE(ov.place_id, t.origin_place_id) AS origin_place_final,
               COALESCE(dv.place_id, t.destination_place_id) AS destination_place_final
        FROM trips t
        LEFT JOIN visits ov ON ov.id = t.origin_visit_id
        LEFT JOIN visits dv ON dv.id = t.destination_visit_id
        LEFT JOIN places dp ON dp.id = COALESCE(dv.place_id, t.destination_place_id)
        WHERE t.deleted = 0;
        """,
        // v5 — user-defined place types (issue #56): a custom name for places whose category is 'other'.
        // The category stays 'other', so default purposes and v_trips are unchanged.
        """
        ALTER TABLE places ADD COLUMN category_custom TEXT;
        """,
    ]

    static func migrate(_ db: SQLiteConnection) throws {
        let current = db.userVersion
        guard current < migrations.count else { return }
        for v in current..<migrations.count {
            try db.transaction {
                try db.execute(migrations[v])
                try db.setUserVersion(v + 1)
            }
        }
    }
}
