"""
Contract test between the app's export format and analysis/hht.py.
Usage: python check_export.py <export-folder-or-parent>
Loads both the CSV bundle and the SQLite snapshot and checks they agree.
"""
import sys
from pathlib import Path

from hht import load, summary

REQUIRED_TRIP_COLUMNS = {
    "person_day_id", "trip_id", "trip_seq", "origin_place_id", "destination_place_id",
    "departure_utc", "arrival_utc", "travel_time_min", "distance_m", "mode", "purpose",
}


def main(path: str) -> None:
    p = Path(path)
    if not (p / "trips.csv").exists():
        folders = sorted(p.glob("hht-export-*"))
        assert folders, f"no export found in {p}"
        p = folders[-1]

    csv = load(p)
    db = load(p / "travel.sqlite")

    missing = REQUIRED_TRIP_COLUMNS - set(csv.trips.columns)
    assert not missing, f"trips.csv is missing columns: {missing}"
    assert len(csv.trips) > 0, "no trips exported"
    assert len(csv.trips) == len(db.trips), f"CSV has {len(csv.trips)} trips, SQLite {len(db.trips)}"
    assert set(csv.trips["trip_id"]) == set(db.trips["trip_id"]), "trip ids differ between CSV and SQLite"
    assert set(csv.trips["mode"]) == set(db.trips["mode"]), "final modes differ between CSV and SQLite"
    # every trip endpoint joins to a visit
    visit_ids = set(csv.visits["visit_id"])
    ends = set(csv.trips["origin_visit_id"].dropna()) | set(csv.trips["destination_visit_id"].dropna())
    assert ends <= visit_ids, "trip endpoints reference unknown visits"
    # self-reported stamps: same rows in both, and an attached stamp points at an exported visit
    assert len(csv.stamps) == len(db.stamps), f"CSV has {len(csv.stamps)} stamps, SQLite {len(db.stamps)}"
    if len(csv.stamps):
        assert set(csv.stamps["stamp_id"]) == set(db.stamps["stamp_id"]), "stamp ids differ between CSV and SQLite"
        assert set(csv.stamps["visit_id"].dropna()) <= visit_ids, "stamps reference unknown visits"

    s = summary(db)
    assert s["trips"] == len(db.trips)
    print(summary(csv).round(2).to_string())
    print(f"\nOK: {len(csv.trips)} trips, CSV and SQLite exports agree ({p.name})")


if __name__ == "__main__":
    main(sys.argv[1])
