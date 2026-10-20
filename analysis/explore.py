"""
Quick look at an HHT export. Usage:

    python explore.py ~/Downloads/hht-export-20260927-120000      # or path/to/travel.sqlite

Prints the headline metrics and writes a few figures to ./figures/.
"""
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from hht import load, mode_share, summary


def main(src: str) -> None:
    d = load(src)
    t = d.trips
    print(f"{len(t)} trips over {t['person_day_id'].nunique()} person-days\n")
    print(summary(d).round(2).to_string(), "\n")
    print("Mode share (trips):\n", mode_share(t).round(3).to_string(), "\n")
    print("Mode share (distance):\n", mode_share(t, "distance_m").round(3).to_string(), "\n")

    out = Path("figures")
    out.mkdir(exist_ok=True)

    # departures by hour of day
    hours = t["departure_utc"].dt.tz_convert(t["tz"].dropna().iloc[0] if t["tz"].notna().any() else "UTC").dt.hour
    ax = hours.value_counts().reindex(range(24), fill_value=0).plot.bar(figsize=(8, 3), color="#3b6fb6")
    ax.set(xlabel="hour of departure (local)", ylabel="trips", title="Departure-time distribution")
    plt.tight_layout(); plt.savefig(out / "departures_by_hour.png", dpi=150); plt.close()

    # daily trips & distance over time
    daily = t.groupby("person_day_id").agg(trips=("trip_id", "count"), km=("distance_m", lambda s: s.sum() / 1000))
    daily.index = daily.index.astype("datetime64[ns]")
    fig, axes = plt.subplots(2, 1, figsize=(9, 5), sharex=True)
    daily["trips"].plot(ax=axes[0], marker="o", title="Trips per day")
    daily["km"].plot(ax=axes[1], marker="o", color="#e07b39", title="Distance per day (km)")
    plt.tight_layout(); plt.savefig(out / "daily.png", dpi=150); plt.close()

    # top origin–destination pairs
    o = t["origin_place_name"].fillna(t["origin_place_id"].str[:8])
    dst = t["destination_place_name"].fillna(t["destination_place_id"].str[:8])
    od = t.groupby([o.rename("origin"), dst.rename("destination")]).size().sort_values(ascending=False).head(10)
    print("Top OD pairs:\n", od.to_string())
    print(f"\nFigures written to {out.resolve()}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    main(sys.argv[1])
