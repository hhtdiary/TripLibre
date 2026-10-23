# Data model

One local SQLite database (`Application Support/HHT/travel.sqlite`, WAL mode). Schema versions are
tracked in `PRAGMA user_version`; migrations live in `Packages/HHTCore/Sources/HHTCore/Database/Schema.swift`
and are append-only.

**Conventions**

- `*_ts`: UTC Unix seconds (REAL). `tz`: IANA time zone of the device when recorded (e.g. `America/New_York`).
  "Local" values (person-day, hour of day) are computed with the record's own `tz`, so travel across zones stays correct.
- Coordinates: WGS84 decimal degrees. Distances: metres, great-circle (haversine, R = 6 371 008.8 m).
- IDs: lowercase UUID strings for derived/user records (stable across exports), integer for raw points.
- `route_polyline`: Google encoded polyline, precision 1e-5, simplified with Douglas–Peucker (8 m).
- Nothing the user corrects is hard-deleted: `deleted = 1` soft-deletes; `audit_log` keeps old → new values.

## Three layers

| Layer | Tables | Written by |
|---|---|---|
| 1. Raw observations | `raw_location_points`, `motion_activities` | collector (append-only, never edited) |
| 2. Inferred events | `visits`, `trips`, `trip_segments` with `user_status = 'auto'` | inference engine (may be rebuilt) |
| 3. Canonical, user-corrected | same rows with `user_status ∈ {confirmed, edited, manual}` | edits; locked against rebuilds |

Self-reports (`stamps`) sit beside layer 1: user observations that inference reads but never rewrites (it only sets
`visit_id`, the visit it attached the stamp to).

## Tables

### raw_location_points

| column | meaning |
|---|---|
| id | integer PK |
| ts | fix time (UTC s) |
| lat, lon | position |
| h_accuracy / v_accuracy | 1σ-ish accuracy radius (m) reported by iOS |
| altitude, speed (m/s), speed_accuracy, course (°) | as reported; NULL if invalid |
| source | `gps`, `significant_change`, `region_exit`, `visit_arrival`, `visit_departure`, `stationary_marker`, `imported_gpx` |
| collector_mode | `moving` / `stationary` — lets inference know a silence was deliberate |
| tz | device time zone |
| inserted_at | when written |

`stationary_marker` = the collector's last fix, re-stamped at the moment it stops GPS. `visit_*` = iOS CLVisit events.

### motion_activities

CoreMotion activity episodes: `ts` (start), `activity` (`stationary|walking|running|cycling|automotive|unknown`),
`confidence` (0 low, 1 medium, 2 high). An activity lasts until the next row.

### places

`id, name, lat, lon, radius_m, address, city, region, country, category, category_custom, code, favorite, notes, source, merged_into, deleted, created_at, updated_at`

- `category`: `home, work_school, restaurant, cafe, grocery, shopping, recreation, entertainment, airport, rail_station, transit_station, hotel, friend_family, medical, other`, plus (schema v4, issue #56) `stadium, event_venue, museum, library, convenience_store, gas_station, bar, gym, pharmacy, bank, civic, religious, parking`. Codes are never renamed, so older exports stay valid; the app's picker groups them (home & work, food & drink, shopping & errands, leisure & culture, health & services, travel & transport). Place category is separate from trip purpose and mode: it only supplies a default purpose (`PlaceCategory.defaultPurpose`, mirrored in `v_trips.purpose_final`).
- `category_custom` (schema v5): the user's own type name for a place whose `category` is `other` (e.g. "Volunteering"); NULL otherwise. It is a label only: such places still count as `other` for default purpose and analysis. Exported in `places.csv`, `places.geojson`, `data.json`, and as `place_category_custom` in `visits.csv`.
- `code`: IATA/station code. `source`: `inferred | manual | imported_csv`.
- `merged_into`: set when the user merges duplicates (the row stays as a tombstone; all visits point to the target).
- `deleted`: soft delete (schema v2) when the user deletes a place that isn't real; its visits are soft-deleted too
  and the trips around them joined, as for "this wasn't a stop".
- First/last visit, visit count and dwell are derived (see `places.csv` export or `placeStats()`).

### visits  (activities / stays)

| column | meaning |
|---|---|
| id | UUID |
| place_id | → places |
| arrival_ts, departure_ts | departure NULL = still there |
| lat, lon | observed centroid of the stay |
| purpose | explicit activity purpose (else implied by place category; see `v_trips.purpose_final`) |
| auto_confidence | 0–1, from fix count and duration |
| source | `inferred \| manual \| imported_csv` |
| user_status | `auto \| confirmed \| edited \| manual` |
| deleted | soft delete ("this wasn't a stop") |
| tz, point_count, notes, created_at, updated_at | |

### trips

| column | meaning |
|---|---|
| id | UUID |
| origin_visit_id, destination_visit_id | → visits (NULL for manual/imported history) |
| origin_place_id, destination_place_id | only used when there are no visits (imported history) |
| departure_ts, arrival_ts | |
| distance_m | along the recorded path (straight line across data gaps) |
| mode_auto, mode_confidence | classifier output (see inference.md) |
| mode_user | user correction; **final mode = COALESCE(mode_user, mode_auto, 'unknown')** |
| purpose | explicit trip purpose override |
| route_polyline | simplified route |
| has_gap | a >15 min hole in GPS during the trip |
| auto_confidence, source, user_status, deleted, tz, notes, created_at, updated_at | |

### trip_segments

Mode segments inside a trip: `id, trip_id, seq, start_ts, end_ts, mode_auto, mode_confidence, mode_user, distance_m, route_polyline`.
The trip's `mode_auto` is the main mode of its segments by the HHTS hierarchy (air > rail > transit > car > bike > walk).
A segment with `mode_user` set was chosen or confirmed by the user (added by hand, mode changed, or its boundary moved); hand-made segments have no `mode_auto`. Editing any segment marks the trip `edited`, so its segments are kept as-is when inference reruns. Segments of a trip are contiguous: they start at the trip's departure, end at its arrival, and never overlap.

### flights

`id, trip_id (→ trips, if detected/linked), journey_id, date (local YYYY-MM-DD), origin_code, destination_code, origin_lat/lon, destination_lat/lon, departure_ts, arrival_ts, airline, flight_number, aircraft_type, seat, cabin, distance_m, booking_reference, notes, source, created_at, updated_at`.
Airplane trips create a flight row automatically (codes blank until the airport place has a code).

### journeys, journey_members

Reserved for multi-leg intercity journeys (access trip → flight → egress). Schema present; UI not built yet.

### stamps  (schema v3; self-reported stops, issue #32)

One row per tap of *Stamp this moment*: "something worth recording happened around here, around now".
`id, ts, lat, lon` (coarse: rounded to 3 decimals ≈ 110 m; NULL when there was no fix ≤ 10 min old),
`uncertainty_m` (radius the stop is believed to lie within), `fix_accuracy_m, fix_age_s` (the fix the location came from),
`visit_id` (set by inference: the visit that accounts for the stamp; NULL = unmatched; no foreign key because auto visits
are replaced by deletion), `note, tz, deleted, created_at, updated_at`.
The coordinate is never treated as the stop's true position; see [inference.md §8](inference.md#8-self-reported-stamps).

### expenses  (schema v6; costs, issue #17)

Money spent on a trip, during a stop, or on a day: `id, ts, amount, currency (ISO 4217), category`
(`fare|taxi|fuel|parking|flight|lodging|food|admission|shopping|other`), `trip_id`, `visit_id` (at most one is set; neither =
a cost on the day of `ts`), `note, tz, deleted, created_at, updated_at`. An amount of 0 records "free" (a pass, a lift).
No foreign keys, like stamps; the edit that adds a cost locks its trip or visit (`user_status = 'edited'`) so
reprocessing can't replace it. When trips or visits are merged the costs follow the surviving record; when one is
deleted its costs stay on the day (`trip_id`/`visit_id` set to NULL). Currencies are never converted: summaries use the
most common currency and list the others separately.

### life_phases

`id, name, kind (semester|job|residence|vacation|research_trip|other), start_date, end_date (inclusive, NULL = ongoing), notes`.

### airports

Reference data from OurAirports (public domain), downloaded on request: `iata, icao, name, municipality, country, lat, lon, type`.

### audit_log

`id, ts, entity_type (visit|trip|trip_segment|place|flight|stamp|expense), entity_id, action, field, old_value, new_value`.
Actions include `set_mode, set_purpose, set_place, set_times, merge, split, delete, confirm, create, relink, infer_departure`.
This is also a labelled training set: every `set_mode` row is a ground-truth mode for a trip.

### app_meta

Key/value: `last_inference_at`.

## Views (for SQL users)

- `v_trips`: non-deleted trips + `mode_final`, `purpose_final` (explicit → visit purpose → place-category default),
  `duration_s`, `origin_place_final`, `destination_place_final`.
- `v_visits`: non-deleted visits + place name/category + `duration_s`.

## Export files

The researcher-facing reference for every exported file and column (units, missing values, synthetic examples) is the
[Data dictionary](https://hhtdiary.org/data-dictionary.html) ([`data-dictionary.html`](data-dictionary.html)).
Note that `travel.sqlite` in an export is always the complete database, whatever the range and raw-points options.

`trips.csv` is the canonical HHTS-style table: `person_day_id` (local date of departure), `trip_seq` (order within
the person-day), OD place ids/names/categories/coordinates, UTC and local times, `travel_time_min`, `distance_m`,
`mode`, `mode_group`, `mode_auto`, `mode_confidence`, `mode_user`, `n_segments`, `segment_modes` (`walk|subway|walk`),
`purpose`, `has_gap`, provenance. Every other CSV joins on the same IDs. `stamps.csv` lists the non-deleted stamps
(`stamp_id, ts, time_utc, tz, lat, lon, uncertainty_m, fix_accuracy_m, fix_age_s, visit_id, note`; `visit_id` is empty
unless it points at an exported visit); `analysis/hht.py` loads it as `d.stamps`. `expenses.csv` lists the non-deleted
costs (`expense_id, ts, time_utc, tz, amount, currency, category, trip_id, visit_id, note`; ids empty unless they point
at an exported trip or visit), loaded as `d.expenses`. `*_ts` columns are accompanied by `*_utc` ISO strings.
