# Import formats

Settings › Import. CSV must have a header row; column names are case-insensitive; extra columns are ignored.
Times are local to `tz` (IANA name) if given, else the phone's current time zone.

## Past trips — `trips.csv`

```csv
date,start_time,end_time,origin,destination,mode,distance_km,purpose,notes
2026-08-18,08:00,10:30,PHL,SLC,airplane,,travel,
2026-08-19,23:30,00:15,Home,Penn,subway,,school,"end time before start = next day"
```

Optional: `origin_lat, origin_lon, destination_lat, destination_lon, tz`.

Origin/destination resolution: 3-letter uppercase code → airport (needs the airport list) → existing place by name or
code → coordinates (creates a place) → otherwise the name is kept in `notes`.
`mode` uses the codes in data-model.md (`walk, bicycle, car_driver, bus, subway, commuter_rail, intercity_rail, airplane, …`);
`purpose` likewise (`home, work, school, meal, shopping, recreation, social, personal_business, medical, travel, transfer, escort, other`).
Airplane rows also create a flight. Imported trips are `source = imported_csv`, `user_status = manual`.

## Flights — `flights.csv`

```csv
date,origin,destination,departure_time,arrival_time,airline,flight_number,aircraft_type,seat,cabin,notes
2026-08-18,PHL,SLC,08:00,10:30,DL,1234,A321,23C,economy,
```

Only `date, origin, destination` are required. Distances need the airport list (Settings › Download airport list).

## GPX

Track points (`trkpt`), route points and waypoints with a `<time>` are imported as raw observations
(`source = imported_gpx`); visits and trips for that period are then reconstructed automatically.
