"""
Load an HHT export (or the raw SQLite database) into pandas for research.

    from hht import load
    d = load("path/to/hht-export-20260927-120000")   # folder, or a .sqlite file
    d.trips.head()

Tables (see docs/data-model.md): trips, segments, visits, places, flights, life_phases,
points (raw GPS, if exported), motion, stamps (one-tap self-reports). Times are tz-aware; *_local columns use each record's tz.
"""
from __future__ import annotations

import math
import sqlite3
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import pandas as pd


@dataclass
class HHT:
    trips: pd.DataFrame
    segments: pd.DataFrame
    visits: pd.DataFrame
    places: pd.DataFrame
    flights: pd.DataFrame
    life_phases: pd.DataFrame
    points: pd.DataFrame | None = None
    motion: pd.DataFrame | None = None
    stamps: pd.DataFrame | None = None   # self-reported stops; visit_id = the visit inference attached it to

    # ---- convenience -------------------------------------------------------
    def phase(self, name: str) -> "HHT":
        """Subset trips/visits/segments to a life phase by name."""
        p = self.life_phases.set_index("name").loc[name]
        start = pd.Timestamp(p["start_date"])
        end = pd.Timestamp(p["end_date"]) + pd.Timedelta(days=1) if isinstance(p["end_date"], str) else pd.Timestamp.max
        return self.between(start, end)

    def between(self, start, end) -> "HHT":
        start, end = pd.Timestamp(start), pd.Timestamp(end)
        day = pd.to_datetime(self.trips["person_day_id"])
        t = self.trips[(day >= start.tz_localize(None)) & (day < end.tz_localize(None))]
        v = self.visits[self.visits["visit_id"].isin(set(t["origin_visit_id"]) | set(t["destination_visit_id"]))]
        s = self.segments[self.segments["trip_id"].isin(t["trip_id"])]
        return HHT(t, s, v, self.places, self.flights, self.life_phases, self.points, self.motion, self.stamps)


def _utc(s: pd.Series) -> pd.Series:
    return pd.to_datetime(s, utc=True, errors="coerce")


def load(path: str | Path) -> HHT:
    path = Path(path).expanduser()
    if path.is_dir() and (path / "trips.csv").exists():
        return _load_csv(path)
    db = path / "travel.sqlite" if path.is_dir() else path
    return _load_sqlite(db)


def _load_csv(folder: Path) -> HHT:
    read = lambda n: pd.read_csv(folder / n) if (folder / n).exists() else pd.DataFrame()
    trips = read("trips.csv")
    for c in ("departure_utc", "arrival_utc"):
        trips[c] = _utc(trips[c])
    visits = read("visits.csv")
    for c in ("arrival_utc", "departure_utc"):
        if c in visits:
            visits[c] = _utc(visits[c])
    seg = read("trip_segments.csv")
    for c in ("start_utc", "end_utc"):
        if c in seg:
            seg[c] = _utc(seg[c])
    pts = read("raw_location_points.csv")
    if len(pts):
        pts["time_utc"] = _utc(pts["time_utc"])
    stamps = read("stamps.csv")
    if len(stamps):
        stamps["time_utc"] = _utc(stamps["time_utc"])
    return HHT(trips, seg, visits, read("places.csv"), read("flights.csv"), read("life_phases.csv"),
               pts if len(pts) else None, read("motion_activities.csv"), stamps)


def _load_sqlite(db: Path) -> HHT:
    con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    q = lambda sql: pd.read_sql_query(sql, con)
    trips = q("""
        SELECT t.id AS trip_id, t.origin_visit_id, t.destination_visit_id,
               t.origin_place_final AS origin_place_id, t.destination_place_final AS destination_place_id,
               op.name AS origin_place_name, dp.name AS destination_place_name,
               op.category AS origin_category, dp.category AS destination_category,
               t.departure_ts, t.arrival_ts, t.tz, t.duration_s, t.distance_m,
               t.mode_final AS mode, t.mode_auto, t.mode_confidence, t.mode_user, t.purpose_final AS purpose,
               t.has_gap, t.source, t.user_status, t.notes, t.route_polyline
        FROM v_trips t
        LEFT JOIN places op ON op.id = t.origin_place_final
        LEFT JOIN places dp ON dp.id = t.destination_place_final
        ORDER BY t.departure_ts""")
    trips["departure_utc"] = pd.to_datetime(trips["departure_ts"], unit="s", utc=True)
    trips["arrival_utc"] = pd.to_datetime(trips["arrival_ts"], unit="s", utc=True)
    trips["travel_time_min"] = trips["duration_s"] / 60
    local = [d.tz_convert(tz or "UTC") for d, tz in zip(trips["departure_utc"], trips["tz"])]
    trips["person_day_id"] = [d.strftime("%Y-%m-%d") for d in local]
    trips["departure_hour_local"] = [d.hour + d.minute / 60 for d in local]
    trips["trip_seq"] = trips.groupby("person_day_id").cumcount() + 1
    trips["mode_group"] = trips["mode"].map(MODE_GROUP).fillna("other")
    visits = q("""SELECT v.id AS visit_id, v.place_id, p.name AS place_name, p.category AS place_category,
                         v.arrival_ts, v.departure_ts, v.tz, v.duration_s / 60.0 AS duration_min, v.lat, v.lon,
                         v.purpose, v.source, v.user_status FROM v_visits v LEFT JOIN places p ON p.id = v.place_id
                  ORDER BY v.arrival_ts""")
    visits["arrival_utc"] = pd.to_datetime(visits["arrival_ts"], unit="s", utc=True)
    visits["departure_utc"] = pd.to_datetime(visits["departure_ts"], unit="s", utc=True)
    seg = q("""SELECT s.id AS segment_id, s.trip_id, s.seq, s.start_ts, s.end_ts,
                      COALESCE(s.mode_user, s.mode_auto, 'unknown') AS mode, s.distance_m
               FROM trip_segments s JOIN trips t ON t.id = s.trip_id WHERE t.deleted = 0""")
    place_cols = {r[1] for r in con.execute("PRAGMA table_info(places)")}
    places = q("SELECT id AS place_id, * FROM places WHERE merged_into IS NULL"
               + (" AND deleted = 0" if "deleted" in place_cols else ""))  # schema v1 has no places.deleted
    pts = q("SELECT * FROM raw_location_points ORDER BY ts")
    pts["time_utc"] = pd.to_datetime(pts["ts"], unit="s", utc=True)
    stamps = pd.DataFrame()
    if con.execute("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'stamps'").fetchone():  # schema v3+
        stamps = q("""SELECT s.id AS stamp_id, s.ts, s.tz, s.lat, s.lon, s.uncertainty_m, s.fix_accuracy_m, s.fix_age_s,
                             CASE WHEN v.id IS NULL THEN NULL ELSE s.visit_id END AS visit_id, s.note
                      FROM stamps s LEFT JOIN visits v ON v.id = s.visit_id AND v.deleted = 0
                      WHERE s.deleted = 0 ORDER BY s.ts""")
        stamps["time_utc"] = pd.to_datetime(stamps["ts"], unit="s", utc=True)
    out = HHT(trips, seg, visits, places, q("SELECT * FROM flights"), q("SELECT * FROM life_phases"),
              pts, q("SELECT * FROM motion_activities"), stamps)
    con.close()
    return out


MODE_GROUP = {
    **dict.fromkeys(["walk", "run", "bicycle", "ebike", "scooter"], "active"),
    **dict.fromkeys(["car", "car_driver", "car_passenger", "taxi"], "car"),
    **dict.fromkeys(["bus", "subway", "light_rail", "commuter_rail", "ferry", "shuttle"], "transit"),
    **dict.fromkeys(["intercity_rail", "coach", "airplane"], "long_distance"),
}

# ---- metrics (same definitions as the app; docs/analytics.md) --------------

R_EARTH = 6_371_008.8


def haversine(lat1, lon1, lat2, lon2):
    p1, p2 = np.radians(lat1), np.radians(lat2)
    dp, dl = p2 - p1, np.radians(np.asarray(lon2) - np.asarray(lon1))
    h = np.sin(dp / 2) ** 2 + np.cos(p1) * np.cos(p2) * np.sin(dl / 2) ** 2
    return 2 * R_EARTH * np.arcsin(np.minimum(1, np.sqrt(h)))


def radius_of_gyration(lat, lon, w=None) -> float:
    """Weighted r_g in metres around the spherical centre of mass."""
    lat, lon = np.radians(np.asarray(lat, float)), np.radians(np.asarray(lon, float))
    w = np.ones_like(lat) if w is None else np.asarray(w, float)
    x, y, z = np.cos(lat) * np.cos(lon), np.cos(lat) * np.sin(lon), np.sin(lat)
    cx, cy, cz = (np.average(v, weights=w) for v in (x, y, z))
    clat, clon = math.degrees(math.atan2(cz, math.hypot(cx, cy))), math.degrees(math.atan2(cy, cx))
    d = haversine(np.degrees(lat), np.degrees(lon), clat, clon)
    return float(np.sqrt(np.average(d ** 2, weights=w)))


def shannon(counts) -> float:
    p = np.asarray(list(counts), float)
    p = p[p > 0] / p.sum()
    return float(-(p * np.log2(p)).sum())


def summary(d: HHT) -> pd.Series:
    t = d.trips
    days = t["person_day_id"].nunique()
    v = d.visits.dropna(subset=["place_id"])
    by_place = v.groupby("place_id").agg(lat=("lat", "mean"), lon=("lon", "mean"),
                                         dwell=("duration_min", "sum"), n=("visit_id", "count"))
    return pd.Series({
        "person_days": days,
        "trips": len(t),
        "trips_per_day": len(t) / max(days, 1),
        "km_per_day": t["distance_m"].sum() / 1000 / max(days, 1),
        "travel_min_per_day": t["travel_time_min"].sum() / max(days, 1),
        "unique_places": by_place.shape[0],
        "rg_dwell_km": radius_of_gyration(by_place.lat, by_place.lon, by_place.dwell) / 1000 if len(by_place) else np.nan,
        "destination_entropy_bits": shannon(by_place.n) if len(by_place) else np.nan,
        "mode_entropy_bits": shannon(t["mode"].value_counts()),
    })


def mode_share(t: pd.DataFrame, by: str = "trips") -> pd.DataFrame:
    """Mode share by trips, distance_m or travel_time_min."""
    val = t.groupby("mode").size() if by == "trips" else t.groupby("mode")[by].sum()
    return (val / val.sum()).sort_values(ascending=False).rename("share").to_frame()


def trips_geodataframe(t: pd.DataFrame):
    """Trips as a GeoDataFrame of LineStrings (needs geopandas, shapely, polyline)."""
    import geopandas as gpd
    import polyline
    from shapely.geometry import LineString

    geoms = [LineString([(lon, lat) for lat, lon in polyline.decode(p)]) if isinstance(p, str) and len(polyline.decode(p)) > 1 else None
             for p in t["route_polyline"]]
    return gpd.GeoDataFrame(t.drop(columns=["route_polyline"]), geometry=geoms, crs="EPSG:4326")
