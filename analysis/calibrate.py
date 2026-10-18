#!/usr/bin/env python3
"""
Inference calibration harness (issue #46). Standard library only, so it runs on a fresh checkout.

The engine itself is never re-implemented here: predictions come from the Swift replay tool
(`hht-calibrate replay`, which runs the production InferenceEngine). This script only
  * exports a human reference from a diary snapshot          (export)
  * freezes a whole-day calibration/validation split          (split)
  * matches predictions to the reference and scores them      (evaluate)
  * compares two evaluations on the same days                 (compare)

Everything it writes may contain precise locations and must stay in a gitignored folder
(calibration-data/ by default). Reports written by `evaluate` contain times and counts only.
See docs/research/inference-calibration.md for the matching rules and the review protocol.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import random
import shutil
import sqlite3
import statistics
import sys
import tempfile
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

REFERENCE_VERSION = 1
HUMAN = {"edited", "confirmed", "manual"}          # user_status values that mean a person touched the record

MODE_GROUP = {
    **dict.fromkeys(["walk", "run", "bicycle", "ebike", "scooter"], "active"),
    **dict.fromkeys(["car", "car_driver", "car_passenger", "taxi"], "car"),
    **dict.fromkeys(["bus", "subway", "light_rail", "commuter_rail", "ferry", "shuttle"], "transit"),
    **dict.fromkeys(["intercity_rail", "coach", "airplane"], "long_distance"),
    **dict.fromkeys(["other", "unknown"], "other"),
}

# Matching tolerances (documented in docs/research/inference-calibration.md §Matching).
DEFAULT_TOL = {
    "visit_max_distance_m": 300.0,   # centroid ↔ reference location
    "min_overlap_share": 0.5,        # temporal overlap ≥ this share of the shorter interval…
    "endpoint_tolerance_s": 15 * 60, # …or both endpoints within this
}


# ----------------------------------------------------------------------------- helpers

def ts(x) -> float | None:
    if x is None:
        return None
    if isinstance(x, (int, float)):
        return float(x)
    return datetime.fromisoformat(x.replace("Z", "+00:00")).timestamp()


def haversine(lat1, lon1, lat2, lon2) -> float:
    r = 6_371_008.8
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = p2 - p1, math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def local(t: float, tz: str | None) -> datetime:
    return datetime.fromtimestamp(t, ZoneInfo(tz or "UTC"))


def day_of(t: float, tz: str | None) -> str:
    return local(t, tz).date().isoformat()


def hm(t: float | None, tz: str | None) -> str:
    return "open" if t is None else local(t, tz).strftime("%H:%M")


def overlap(a0, a1, b0, b1) -> float:
    return max(0.0, min(a1, b1) - max(a0, b0))


def pct(xs, q):
    if not xs:
        return None
    s = sorted(xs)
    k = (len(s) - 1) * q
    lo, hi = math.floor(k), math.ceil(k)
    return s[lo] + (s[hi] - s[lo]) * (k - lo)


def r(x, n=2):
    return None if x is None else round(x, n)


def write_json(path: Path, obj):
    path.write_text(json.dumps(obj, indent=2, sort_keys=True, default=str) + "\n")


# ----------------------------------------------------------------------------- export

def open_snapshot(db: Path) -> tuple[sqlite3.Connection, Path]:
    """Open a private copy (with WAL) read-only, so the snapshot itself is never modified."""
    tmp = Path(tempfile.mkdtemp(prefix="hht-ref-"))
    for ext in ("", "-wal", "-shm"):
        if Path(str(db) + ext).exists():
            shutil.copy(str(db) + ext, tmp / ("travel.sqlite" + ext))
    con = sqlite3.connect(f"file:{tmp / 'travel.sqlite'}?mode=ro", uri=True)
    con.row_factory = sqlite3.Row
    return con, tmp


def quality_checks(con) -> dict:
    q = {}
    one = lambda sql: con.execute(sql).fetchone()[0]
    q["points"] = one("SELECT COUNT(*) FROM raw_location_points")
    q["points_invalid_coordinates"] = one(
        "SELECT COUNT(*) FROM raw_location_points WHERE lat NOT BETWEEN -90 AND 90 OR lon NOT BETWEEN -180 AND 180 OR (lat = 0 AND lon = 0)")
    q["points_duplicate_timestamps"] = one(
        "SELECT COUNT(*) FROM (SELECT ts FROM raw_location_points GROUP BY ts HAVING COUNT(*) > 1)")
    q["points_out_of_order_by_id"] = one(
        "SELECT COUNT(*) FROM raw_location_points a JOIN raw_location_points b ON b.id = a.id + 1 WHERE b.ts < a.ts")
    q["points_negative_accuracy"] = one("SELECT COUNT(*) FROM raw_location_points WHERE h_accuracy < 0")
    q["visits_negative_duration"] = one("SELECT COUNT(*) FROM visits WHERE deleted = 0 AND departure_ts < arrival_ts")
    q["trips_negative_duration"] = one("SELECT COUNT(*) FROM trips WHERE deleted = 0 AND arrival_ts < departure_ts")
    q["visits_overlapping_next"] = one("""
        SELECT COUNT(*) FROM (SELECT arrival_ts, departure_ts,
               LEAD(arrival_ts) OVER (ORDER BY arrival_ts) AS nxt FROM visits WHERE deleted = 0)
        WHERE departure_ts IS NOT NULL AND nxt < departure_ts - 60""")
    q["open_visits"] = one("SELECT COUNT(*) FROM visits WHERE deleted = 0 AND departure_ts IS NULL")
    q["trips_orphan_visit_refs"] = one("""
        SELECT COUNT(*) FROM trips t WHERE t.deleted = 0 AND (
          (t.origin_visit_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM visits v WHERE v.id = t.origin_visit_id AND v.deleted = 0)) OR
          (t.destination_visit_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM visits v WHERE v.id = t.destination_visit_id AND v.deleted = 0)))""")
    q["segments_orphan"] = one("SELECT COUNT(*) FROM trip_segments s WHERE NOT EXISTS (SELECT 1 FROM trips t WHERE t.id = s.trip_id)")
    # sampling gaps (> 15 min between consecutive fixes) — normal while stationary, informative while moving
    rows = con.execute("SELECT ts, collector_mode FROM raw_location_points ORDER BY ts, id").fetchall()
    gaps = [(b[0] - a[0], a[1]) for a, b in zip(rows, rows[1:]) if b[0] - a[0] > 900]
    q["sampling_gaps_over_15min"] = len(gaps)
    q["sampling_gaps_over_15min_while_moving_mode"] = sum(1 for g, m in gaps if m == "moving")
    q["sampling_gap_hours_total"] = r(sum(g for g, _ in gaps) / 3600, 1)
    return q


def cmd_export(a):
    db = Path(a.db)
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    con, tmp = open_snapshot(db)
    try:
        pts = con.execute("SELECT MIN(ts), MAX(ts) FROM raw_location_points").fetchone()
        mot = con.execute("SELECT MIN(ts), MAX(ts) FROM motion_activities").fetchone()
        last_inference = con.execute("SELECT value FROM app_meta WHERE key='last_inference_at'").fetchone()
        tz_default = (con.execute("SELECT tz FROM raw_location_points WHERE tz IS NOT NULL ORDER BY ts DESC LIMIT 1").fetchone() or ["UTC"])[0]

        visits = []
        for v in con.execute("SELECT v.*, p.name IS NOT NULL AND p.name != '' AS place_named FROM visits v "
                             "LEFT JOIN places p ON p.id = v.place_id ORDER BY arrival_ts"):
            visits.append({
                "id": v["id"], "arrival": v["arrival_ts"], "departure": v["departure_ts"],
                "lat": v["lat"], "lon": v["lon"], "tz": v["tz"] or tz_default,
                "user_status": v["user_status"], "source": v["source"], "deleted": bool(v["deleted"]),
                "place_named": bool(v["place_named"]),
            })
        segs = defaultdict(list)
        for s in con.execute("SELECT * FROM trip_segments ORDER BY trip_id, seq"):
            segs[s["trip_id"]].append({
                "start": s["start_ts"], "end": s["end_ts"], "mode_auto": s["mode_auto"], "mode_user": s["mode_user"],
                "mode": s["mode_user"] or s["mode_auto"] or "unknown", "distance": s["distance_m"],
            })
        trips = []
        for t in con.execute("SELECT * FROM trips ORDER BY departure_ts"):
            trips.append({
                "id": t["id"], "departure": t["departure_ts"], "arrival": t["arrival_ts"],
                "origin_visit": t["origin_visit_id"], "destination_visit": t["destination_visit_id"],
                "tz": t["tz"] or tz_default, "distance": t["distance_m"],
                "mode_auto": t["mode_auto"], "mode_user": t["mode_user"],
                "mode": t["mode_user"] or t["mode_auto"] or "unknown",
                "user_status": t["user_status"], "source": t["source"], "deleted": bool(t["deleted"]),
                "has_gap": bool(t["has_gap"]), "segments": segs.get(t["id"], []),
            })
        # audit trail: which records a person changed, and when (kept for provenance, not used as input)
        edited_ids = Counter(r_[0] for r_ in con.execute("SELECT entity_id FROM audit_log WHERE action != 'infer_departure'"))
        for rec in visits + trips:
            rec["edit_events"] = edited_ids.get(rec["id"], 0)

        meta = {
            "reference_version": REFERENCE_VERSION,
            "snapshot_sha256": sha256(db),
            "schema_version": con.execute("PRAGMA user_version").fetchone()[0],
            "extracted_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "app_last_inference_at": last_inference[0] if last_inference else None,
            "points_start": pts[0], "points_end": pts[1], "motion_start": mot[0], "motion_end": mot[1],
            "default_tz": tz_default,
            "privacy": "Contains precise coordinates. Keep in a gitignored folder; never commit or upload.",
            "provenance_limits": [
                "Only final diary states exist; the app keeps no snapshot of the original machine output, "
                "so baseline predictions come from replaying raw points, not from the historical app run.",
                "Records with user_status='auto' were produced by an earlier engine and never edited; they are "
                "'accepted' labels, not independently verified ones, and are scored separately.",
                "Manual visits store the place location, not an observed centroid.",
            ],
        }
        ref = {"meta": meta, "quality": quality_checks(con), "visits": visits, "trips": trips}
        write_json(out / "reference.json", ref)

        # per-day review sheet: the user confirms each day (and may exclude events) before it counts as reference
        review = out / "review.csv"
        days = sorted({day_of(v["arrival"], v["tz"]) for v in visits if not v["deleted"]}
                      | {day_of(t["departure"], t["tz"]) for t in trips if not t["deleted"]})
        existing = {}
        if review.exists():
            with open(review) as f:
                existing = {row["date"]: row for row in csv.DictReader(f)}
        with open(review, "w", newline="") as f:
            w = csv.DictWriter(f, ["date", "reviewed", "quality", "note"])
            w.writeheader()
            for d in days:
                row = existing.get(d) or {"date": d, "reviewed": a.reviewed_default, "quality": "", "note": a.review_note}
                w.writerow({k: row.get(k, "") for k in ["date", "reviewed", "quality", "note"]})
        excl = out / "exclusions.csv"
        if not excl.exists():
            excl.write_text("kind,start_local,end_local,reason\n")
        print(f"reference: {sum(not v['deleted'] for v in visits)} visits, {sum(not t['deleted'] for t in trips)} trips, "
              f"{len(days)} days → {out}")
        print("quality:", json.dumps(ref["quality"]))
    finally:
        con.close()
        shutil.rmtree(tmp, ignore_errors=True)


# ----------------------------------------------------------------------------- split

def cmd_split(a):
    ref = json.loads(Path(a.reference, "reference.json").read_text())
    path = Path(a.reference, "split.json")
    if path.exists() and not a.force and not a.validation_after:
        sys.exit(f"{path} exists; the split is frozen (use --force only for a new, versioned protocol)")
    m = ref["meta"]
    days = sorted(d for d in reviewed_days(Path(a.reference))
                  if m["points_start"] <= day_bounds(d, m["default_tz"])[1] and day_bounds(d, m["default_tz"])[0] <= m["points_end"])
    # complete days only: a day where recording starts or stops mid-day is calibration-only
    full = [d for d in days if day_bounds(d, m["default_tz"])[0] >= m["points_start"] and day_bounds(d, m["default_tz"])[1] <= m["points_end"]]
    extra = {}
    if a.validation_after:
        # forward split (protocol v2+): every day up to the cutoff is calibration; validation is only complete days
        # recorded after it, so a later snapshot adds holdout days without moving any calibration day
        cutoff = a.validation_after
        if path.exists():
            old = json.loads(path.read_text())
            if old.get("validation_after") != cutoff or old.get("salt") != a.salt:
                sys.exit(f"{path} was frozen with another protocol; refusing to change it")
            if old.get("validation"):
                sys.exit(f"{path} already has validation days {old['validation']}; the holdout is frozen")
        calibration = sorted(d for d in days if d <= cutoff)
        validation = sorted(d for d in full if d > cutoff)
        excluded = sorted(d for d in days if d > cutoff and d not in validation)
        if path.exists() and json.loads(path.read_text())["calibration"] != calibration:
            sys.exit(f"{path}: calibration days would change; the split is frozen")
        extra = {"validation_after": cutoff, "excluded_incomplete_after_cutoff": excluded}
    else:
        rank = sorted(full, key=lambda d: hashlib.sha256(f"{a.salt}:{d}".encode()).hexdigest())
        n_val = max(1, round(len(full) * a.validation_share))
        validation = sorted(rank[:n_val])
        calibration = sorted(d for d in days if d not in validation)
    write_json(path, {"salt": a.salt, "validation_share": a.validation_share, "created_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
                      "snapshot_sha256": m["snapshot_sha256"], "calibration": calibration, "validation": validation, **extra})
    print(f"split: {len(calibration)} calibration days, {len(validation)} validation days → {path}")


def day_bounds(d: str, tz: str) -> tuple[float, float]:
    z = ZoneInfo(tz)
    start = datetime.fromisoformat(d).replace(tzinfo=z)
    return start.timestamp(), (start + timedelta(days=1)).timestamp()


def reviewed_days(refdir: Path) -> list[str]:
    with open(refdir / "review.csv") as f:
        return [row["date"] for row in csv.DictReader(f) if row["reviewed"].strip().lower() in ("1", "yes", "y", "true")]


def exclusions(refdir: Path, tz: str) -> list[tuple[str, float, float, str]]:
    p = refdir / "exclusions.csv"
    if not p.exists():
        return []
    out = []
    with open(p) as f:
        for row in csv.DictReader(f):
            z = ZoneInfo(tz)
            s = datetime.fromisoformat(row["start_local"]).replace(tzinfo=z).timestamp()
            e = datetime.fromisoformat(row["end_local"]).replace(tzinfo=z).timestamp()
            out.append((row["kind"] or "any", s, e, row["reason"]))
    return out


# ----------------------------------------------------------------------------- matching

@dataclass
class Ev:
    kind: str            # visit | trip
    start: float
    end: float           # open visits end at the evaluation horizon
    open: bool
    tz: str
    lat: float | None = None
    lon: float | None = None
    mode: str | None = None
    mode_human: bool = False
    label: str = "auto"  # reference label source: human | accepted ; predictions: machine
    raw: dict = field(default_factory=dict)
    day: str = ""
    did: str = ""        # day-local id, e.g. 10-03/V2

    @property
    def dur(self):
        return self.end - self.start


def match(refs: list[Ev], preds: list[Ev], tol: dict, spatial: bool) -> list[tuple[int, int]]:
    """Deterministic one-to-one assignment: candidate pairs must overlap enough in time (and, for visits, be close),
    then pairs are taken greedily by temporal IoU (ties: earlier reference, earlier prediction)."""
    cands = []
    for i, a in enumerate(refs):
        for j, b in enumerate(preds):
            if b.start > a.end + tol["endpoint_tolerance_s"]:
                continue
            ov = overlap(a.start, a.end, b.start, b.end)
            shorter = max(1.0, min(a.dur, b.dur))
            close_ends = abs(a.start - b.start) <= tol["endpoint_tolerance_s"] and abs(a.end - b.end) <= tol["endpoint_tolerance_s"]
            if not (ov >= tol["min_overlap_share"] * shorter or (close_ends and ov > 0) or (close_ends and shorter < 120)):
                continue
            if spatial and a.lat is not None and b.lat is not None:
                if haversine(a.lat, a.lon, b.lat, b.lon) > tol["visit_max_distance_m"]:
                    continue
            union = max(a.end, b.end) - min(a.start, b.start)
            cands.append((-(ov / max(1.0, union)), i, j))
    cands.sort()
    used_r, used_p, pairs = set(), set(), []
    for _, i, j in cands:
        if i in used_r or j in used_p:
            continue
        used_r.add(i); used_p.add(j); pairs.append((i, j))
    return sorted(pairs)


# ----------------------------------------------------------------------------- evaluate

def load_events(ref: dict, pred: dict, horizon: tuple[float, float]):
    lo, hi = horizon
    tz0 = ref["meta"]["default_tz"]
    rv, rt, pv, pt = [], [], [], []
    for v in ref["visits"]:
        if v["deleted"]:
            continue
        e = v["departure"] if v["departure"] is not None else hi
        if e <= lo or v["arrival"] >= hi:
            continue
        rv.append(Ev("visit", v["arrival"], e, v["departure"] is None, v["tz"], v["lat"], v["lon"],
                     label="human" if v["user_status"] in HUMAN else "accepted", raw=v))
    for t in ref["trips"]:
        if t["deleted"] or t["arrival"] <= lo or t["departure"] >= hi:
            continue
        human_mode = t["mode_user"] is not None or t["user_status"] == "manual" or any(s["mode_user"] for s in t["segments"])
        rt.append(Ev("trip", t["departure"], t["arrival"], False, t["tz"], mode=t["mode"], mode_human=human_mode,
                     label="human" if t["user_status"] in HUMAN else "accepted", raw=t))
    for v in pred["visits"]:
        s, e = ts(v["arrival"]), ts(v.get("departure"))
        e2 = e if e is not None else hi
        if e2 <= lo or s >= hi:
            continue
        pv.append(Ev("visit", s, e2, e is None, v.get("timeZone") or tz0, v["latitude"], v["longitude"], label="machine", raw=v))
    for t in pred["trips"]:
        s, e = ts(t["departure"]), ts(t["arrival"])
        if e <= lo or s >= hi:
            continue
        pt.append(Ev("trip", s, e, False, tz0, mode=t["mode"], label="machine", raw=t))
    for evs, tag in ((rv, "V"), (rt, "T"), (pv, "v"), (pt, "t")):
        evs.sort(key=lambda x: (x.start, x.end))
        per_day = Counter()
        for x in evs:
            x.day = day_of(x.start, x.tz)
            per_day[x.day] += 1
            x.did = f"{x.day[5:]}/{tag}{per_day[x.day]}"
    return rv, rt, pv, pt


def prf(tp, fp, fn):
    p = tp / (tp + fp) if tp + fp else None
    rc = tp / (tp + fn) if tp + fn else None
    f1 = 2 * p * rc / (p + rc) if p and rc else (0.0 if (p == 0 or rc == 0) else None)
    return {"tp": tp, "fp": fp, "fn": fn, "precision": r(p, 3), "recall": r(rc, 3), "f1": r(f1, 3)}


def timing(diffs_s):
    m = [d / 60 for d in diffs_s]
    if not m:
        return {"n": 0}
    a = [abs(x) for x in m]
    return {"n": len(m), "bias_min": r(statistics.mean(m), 1), "median_abs_min": r(statistics.median(a), 1),
            "mean_abs_min": r(statistics.mean(a), 1), "p90_abs_min": r(pct(a, 0.9), 1)}


def dur_bucket(s):
    return "<15m" if s < 900 else "15-60m" if s < 3600 else "1-4h" if s < 4 * 3600 else ">4h"


def evaluate(ref, pred, days: set[str], points, tol, excl):
    m = ref["meta"]
    horizon = (m["points_start"], ts(pred.get("end")) or m["points_end"])
    rv, rt, pv, pt = load_events(ref, pred, horizon)

    def excluded(e: Ev):
        return any((k in ("any", e.kind)) and overlap(e.start, e.end, s, en) > 0.5 * max(1, e.dur) for k, s, en, _ in excl)

    vpairs = match(rv, pv, tol, spatial=True)
    tpairs = match(rt, pt, tol, spatial=False)
    vm_r = {i: j for i, j in vpairs}; vm_p = {j: i for i, j in vpairs}
    tm_r = {i: j for i, j in tpairs}; tm_p = {j: i for i, j in tpairs}

    # an event counts toward the days it starts on; a matched pair counts if the reference event does
    def in_scope_r(e): return e.day in days and not excluded(e)
    def in_scope_p(e, partner): return (partner.day in days and not excluded(partner)) if partner else (e.day in days and not excluded(e))

    out = {"days": sorted(days), "n_days": len(days), "horizon": [horizon[0], horizon[1]]}

    # ---- visits
    def visit_block(filter_r=lambda e: True, filter_p=lambda e: True):
        tp = sum(1 for i, j in vpairs if in_scope_r(rv[i]) and filter_r(rv[i]))
        fn = sum(1 for i, e in enumerate(rv) if i not in vm_r and in_scope_r(e) and filter_r(e))
        fp = sum(1 for j, e in enumerate(pv) if j not in vm_p and in_scope_p(e, None) and filter_p(e))
        return prf(tp, fp, fn)

    out["visits"] = visit_block()
    out["visits_by_label"] = {lab: visit_block(lambda e, l=lab: e.label == l, lambda e: False) for lab in ("human", "accepted")}
    out["visits_by_duration"] = {b: visit_block(lambda e, b=b: dur_bucket(e.dur) == b, lambda e, b=b: dur_bucket(e.dur) == b)
                                 for b in ("<15m", "15-60m", "1-4h", ">4h")}
    arr, dep, dist = [], [], []
    for i, j in vpairs:
        a, b = rv[i], pv[j]
        if not in_scope_r(a):
            continue
        arr.append(b.start - a.start)
        if not a.open and not b.open:
            dep.append(b.end - a.end)
        if a.raw.get("source") != "manual":
            dist.append(haversine(a.lat, a.lon, b.lat, b.lon))
    out["visit_arrival_error"] = timing(arr)
    out["visit_departure_error"] = timing(dep)
    out["visit_location_error_m"] = {"n": len(dist), "median": r(pct(dist, .5), 0), "p90": r(pct(dist, .9), 0)}

    # ---- trips
    def trip_block(filter_r=lambda e: True, filter_p=lambda e: True):
        tp = sum(1 for i, j in tpairs if in_scope_r(rt[i]) and filter_r(rt[i]))
        fn = sum(1 for i, e in enumerate(rt) if i not in tm_r and in_scope_r(e) and filter_r(e))
        fp = sum(1 for j, e in enumerate(pt) if j not in tm_p and in_scope_p(e, None) and filter_p(e))
        return prf(tp, fp, fn)
    out["trips"] = trip_block()
    out["trips_by_ref_mode_group"] = {g: trip_block(lambda e, g=g: MODE_GROUP.get(e.mode, "other") == g, lambda e: False)
                                      for g in ("active", "car", "transit", "long_distance", "other")}
    # splits / merges: one reference trip overlapped ≥ 50 % by ≥ 2 predictions, and vice versa
    def covered(a, b): return overlap(a.start, a.end, b.start, b.end) > 0.5 * max(60, min(a.dur, b.dur))
    out["trip_split_count"] = sum(1 for e in rt if in_scope_r(e) and sum(covered(e, p) for p in pt) >= 2)
    out["trip_merge_count"] = sum(1 for p in pt if p.day in days and sum(covered(e, p) for e in rt if in_scope_r(e)) >= 2)
    tdep, tarr = [], []
    for i, j in tpairs:
        if in_scope_r(rt[i]):
            tdep.append(pt[j].start - rt[i].start); tarr.append(pt[j].end - rt[i].end)
    out["trip_departure_error"] = timing(tdep)
    out["trip_arrival_error"] = timing(tarr)

    # ---- modes (matched trips; human-labelled modes scored separately from accepted ones; unknown excluded)
    conf = {"human": Counter(), "accepted": Counter()}
    unknown = 0
    for i, j in tpairs:
        a, b = rt[i], pt[j]
        if not in_scope_r(a):
            continue
        if a.mode in ("unknown", None):
            unknown += 1
            continue
        conf["human" if a.mode_human else "accepted"][(a.mode, b.mode)] += 1
    def mode_scores(c: Counter):
        n = sum(c.values())
        exact = sum(v for (x, y), v in c.items() if x == y)
        group = sum(v for (x, y), v in c.items() if MODE_GROUP.get(x) == MODE_GROUP.get(y))
        classes = sorted({x for x, _ in c} | {y for _, y in c})
        per = {}
        for k in classes:
            tp = c[(k, k)]
            ref_n = sum(v for (x, _), v in c.items() if x == k)
            pred_n = sum(v for (_, y), v in c.items() if y == k)
            per[k] = {"ref": ref_n, "pred": pred_n, "precision": r(tp / pred_n, 2) if pred_n else None,
                      "recall": r(tp / ref_n, 2) if ref_n else None}
        return {"n": n, "exact_accuracy": r(exact / n, 3) if n else None, "group_accuracy": r(group / n, 3) if n else None,
                "per_class": per, "confusion": {f"{x}->{y}": v for (x, y), v in sorted(c.items())}}
    out["modes_human_labelled"] = mode_scores(conf["human"])
    out["modes_accepted"] = mode_scores(conf["accepted"])
    out["modes_unknown_reference_excluded"] = unknown

    # ---- whole-day time agreement: per minute, is the person at a stay (and where) or travelling?
    def state_at(evs_v, evs_t, t):
        for e in evs_v:
            if e.start <= t < e.end:
                return ("stay", e)
        for e in evs_t:
            if e.start <= t < e.end:
                return ("travel", None)
        return ("none", None)
    agree_by_day = {}
    tot = Counter()
    for d in sorted(days):
        lo, hi = day_bounds(d, m["default_tz"])
        lo, hi = max(lo, horizon[0]), min(hi, horizon[1])
        c = Counter()
        rvs = [e for e in rv if e.end > lo and e.start < hi and not excluded(e)]
        rts = [e for e in rt if e.end > lo and e.start < hi and not excluded(e)]
        pvs = [e for e in pv if e.end > lo and e.start < hi]
        pts_ = [e for e in pt if e.end > lo and e.start < hi]
        t = lo + 30
        while t < hi:
            rs, re_ = state_at(rvs, rts, t)
            if rs != "none":
                ps, pe = state_at(pvs, pts_, t)
                c["minutes"] += 1
                if rs == ps == "travel" or (rs == ps == "stay" and haversine(re_.lat, re_.lon, pe.lat, pe.lon) <= tol["visit_max_distance_m"]):
                    c["agree"] += 1
                else:
                    c[f"ref_{rs}_pred_{ps}"] += 1
            t += 60
        agree_by_day[d] = r(c["agree"] / c["minutes"], 4) if c["minutes"] else None
        tot.update(c)
    out["time_agreement"] = {"share": r(tot["agree"] / tot["minutes"], 4) if tot["minutes"] else None,
                             "minutes": tot["minutes"],
                             "disagreement_minutes": {k: v for k, v in sorted(tot.items()) if k.startswith("ref_")}}

    # ---- per day
    per_day = {}
    for d in sorted(days):
        nrv = sum(1 for e in rv if e.day == d and not excluded(e)); npv = sum(1 for e in pv if e.day == d)
        nrt = sum(1 for e in rt if e.day == d and not excluded(e)); npt = sum(1 for e in pt if e.day == d)
        tp_v = sum(1 for i, j in vpairs if rv[i].day == d and in_scope_r(rv[i]))
        tp_t = sum(1 for i, j in tpairs if rt[i].day == d and in_scope_r(rt[i]))
        lo, hi = day_bounds(d, m["default_tz"])
        n_pts = sum(1 for p in points if lo <= p[0] < hi)
        per_day[d] = {"ref_visits": nrv, "pred_visits": npv, "matched_visits": tp_v,
                      "ref_trips": nrt, "pred_trips": npt, "matched_trips": tp_t, "points": n_pts,
                      "time_agreement": agree_by_day.get(d)}
    out["per_day"] = per_day

    # ---- failures (day-local ids, local times, no coordinates)
    fails = []
    for i, e in enumerate(rv):
        if i in vm_r or not in_scope_r(e):
            continue
        near = [p for p in points if e.start <= p[0] <= e.end and haversine(p[1], p[2], e.lat, e.lon) <= 150]
        inside = [p for p in points if e.start <= p[0] <= e.end]
        if not inside:
            cause = "no GPS fixes during the stay (recording gap)" if e.raw["source"] != "manual" else "manual stop with no fixes (not observable)"
        elif not near:
            cause = "fixes during the stay are > 150 m away (indoor drift / wrong location label)"
        elif e.dur < 600:
            cause = f"short stop ({int(e.dur // 60)} min) — near minStayDuration"
        else:
            ovt = [p for p in pt if overlap(p.start, p.end, e.start, e.end) > 0.5 * e.dur]
            cause = "absorbed into a predicted trip (walking/moving through the stop?)" if ovt else "merged into a neighbouring stay"
        fails.append({"id": e.did, "kind": "missed visit", "label": e.label, "ref": f"{hm(e.start, e.tz)}–{hm(None if e.open else e.end, e.tz)}",
                      "pred": "", "minutes": int(e.dur // 60), "fixes": len(inside), "fixes_near": len(near), "cause": cause})
    for j, e in enumerate(pv):
        if j in vm_p or not in_scope_p(e, None):
            continue
        ov_trip = [x for x in rt if overlap(x.start, x.end, e.start, e.end) > 0.5 * e.dur]
        ov_visit = [x for x in rv if overlap(x.start, x.end, e.start, e.end) > 0.5 * e.dur]
        if ov_trip:
            cause = f"stationary period inside a reference {ov_trip[0].mode} trip (waiting / slow traffic / transfer?)"
        elif ov_visit:
            dd = haversine(ov_visit[0].lat, ov_visit[0].lon, e.lat, e.lon)
            cause = f"duplicate/split of reference stay {ov_visit[0].did} ({int(dd)} m apart)"
        else:
            cause = "stay where the reference has neither visit nor trip (deleted by user?)"
        fails.append({"id": e.did, "kind": "extra visit", "label": "machine", "ref": "", "pred": f"{hm(e.start, e.tz)}–{hm(None if e.open else e.end, e.tz)}",
                      "minutes": int(e.dur // 60), "fixes": "", "fixes_near": "", "cause": cause})
    for i, j in vpairs:
        a, b = rv[i], pv[j]
        if not in_scope_r(a):
            continue
        da = (b.start - a.start) / 60
        de = (b.end - a.end) / 60 if not (a.open or b.open) else 0
        if abs(da) > 20 or abs(de) > 20:
            fails.append({"id": a.did, "kind": "timing", "label": a.label, "ref": f"{hm(a.start, a.tz)}–{hm(None if a.open else a.end, a.tz)}",
                          "pred": f"{hm(b.start, b.tz)}–{hm(None if b.open else b.end, b.tz)}", "minutes": int(a.dur // 60),
                          "fixes": "", "fixes_near": "", "cause": f"arrival {da:+.0f} min, departure {de:+.0f} min"})
    out["failures"] = sorted(fails, key=lambda f: f["id"])
    return out


def bootstrap(ref, pred, days, points, tol, excl, n=500, seed=0):
    """Day-level cluster bootstrap for visit/trip F1 and arrival error (days resampled with replacement)."""
    rng = random.Random(seed)
    base = sorted(days)
    per = {d: evaluate(ref, pred, {d}, points, tol, excl) for d in base}
    stats = defaultdict(list)
    for _ in range(n):
        sample = [rng.choice(base) for _ in base]
        for key in ("visits", "trips"):
            tp = sum(per[d][key]["tp"] for d in sample); fp = sum(per[d][key]["fp"] for d in sample); fn = sum(per[d][key]["fn"] for d in sample)
            f = prf(tp, fp, fn)["f1"]
            if f is not None:
                stats[f"{key}_f1"].append(f)
        mins = sum(per[d]["time_agreement"]["minutes"] for d in sample)
        if mins:
            stats["time_agreement"].append(sum(per[d]["time_agreement"]["share"] * per[d]["time_agreement"]["minutes"] for d in sample) / mins)
    return {k: {"lo95": r(pct(v, .025), 3), "hi95": r(pct(v, .975), 3)} for k, v in stats.items()} | {"resamples": n, "days": len(base)}


def load_points(dbpath: Path):
    con, tmp = open_snapshot(dbpath)
    try:
        return [tuple(x) for x in con.execute("SELECT ts, lat, lon, h_accuracy FROM raw_location_points ORDER BY ts")]
    finally:
        con.close(); shutil.rmtree(tmp, ignore_errors=True)


def cmd_evaluate(a):
    refdir = Path(a.reference)
    ref = json.loads((refdir / "reference.json").read_text())
    pred = json.loads(Path(a.pred).read_text())
    split = json.loads((refdir / "split.json").read_text()) if (refdir / "split.json").exists() else None
    reviewed = set(reviewed_days(refdir))
    if a.days == "all":
        days = reviewed
    else:
        if not split:
            sys.exit("no split.json; run `calibrate.py split` first or use --days all")
        days = set(split[a.days]) & reviewed
        if not days:
            sys.exit(f"no reviewed {a.days} days in split.json (a forward split fills its holdout from a later export)")
    tol = dict(DEFAULT_TOL)
    points = load_points(Path(a.db)) if a.db else []
    excl = exclusions(refdir, ref["meta"]["default_tz"])
    res = evaluate(ref, pred, days, points, tol, excl)
    res["bootstrap"] = bootstrap(ref, pred, days, points, tol, excl) if len(days) >= 5 else "too few days"
    res["inputs"] = {"prediction_mode": pred["mode"], "config": pred["config"], "reference_sha": ref["meta"]["snapshot_sha256"],
                     "split": a.days, "tolerances": tol, "exclusions": len(excl)}
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    write_json(out / f"metrics-{a.days}.json", res)
    (out / f"report-{a.days}.md").write_text(render(res, a.days))
    print(summary_line(res, a.days))


def summary_line(res, label):
    v, t = res["visits"], res["trips"]
    return (f"[{label}] {res['n_days']} days | time agree={res['time_agreement']['share']} | visits P={v['precision']} R={v['recall']} F1={v['f1']} "
            f"| trips P={t['precision']} R={t['recall']} F1={t['f1']} | arrival MAE={res['visit_arrival_error'].get('median_abs_min')} min (median) "
            f"| modes(human) exact={res['modes_human_labelled']['exact_accuracy']} group={res['modes_human_labelled']['group_accuracy']}")


def render(res, label) -> str:
    L = [f"# Calibration report — {label} days", "",
         f"Days: {res['n_days']}. Prediction mode: {res['inputs']['prediction_mode']}. Reference snapshot {res['inputs']['reference_sha'][:12]}.", "",
         "| | TP | FP | FN | precision | recall | F1 |", "|---|---|---|---|---|---|---|"]
    for k in ("visits", "trips"):
        b = res[k]; L.append(f"| {k} | {b['tp']} | {b['fp']} | {b['fn']} | {b['precision']} | {b['recall']} | {b['f1']} |")
    for k, b in res["visits_by_label"].items():
        L.append(f"| visits ({k} ref, recall) | {b['tp']} | – | {b['fn']} | – | {b['recall']} | – |")
    for k, b in res["visits_by_duration"].items():
        L.append(f"| visits {k} | {b['tp']} | {b['fp']} | {b['fn']} | {b['precision']} | {b['recall']} | {b['f1']} |")
    for k, b in res["trips_by_ref_mode_group"].items():
        if b["tp"] + b["fn"]:
            L.append(f"| trips, ref {k} (recall) | {b['tp']} | – | {b['fn']} | – | {b['recall']} | – |")
    ta = res["time_agreement"]
    L += ["", f"**Whole-day time agreement**: {ta['share']} of {ta['minutes']} reference minutes "
          f"(same stay within {res['inputs']['tolerances']['visit_max_distance_m']:.0f} m, or both travelling). Disagreement minutes: "
          + ", ".join(f"{k} {v}" for k, v in ta["disagreement_minutes"].items())]
    L += ["", f"Trip splits (one reference trip → ≥2 predicted): {res['trip_split_count']}; merges: {res['trip_merge_count']}.", "",
          "| timing (pred − ref) | n | bias | median abs | mean abs | p90 abs |", "|---|---|---|---|---|---|"]
    for k in ("visit_arrival_error", "visit_departure_error", "trip_departure_error", "trip_arrival_error"):
        b = res[k]; L.append(f"| {k} (min) | {b['n']} | {b.get('bias_min')} | {b.get('median_abs_min')} | {b.get('mean_abs_min')} | {b.get('p90_abs_min')} |")
    le = res["visit_location_error_m"]
    L += ["", f"Visit location error (non-manual matched visits): n={le['n']}, median {le['median']} m, p90 {le['p90']} m.", ""]
    for k in ("modes_human_labelled", "modes_accepted"):
        b = res[k]
        L.append(f"**{k}**: n={b['n']}, exact {b['exact_accuracy']}, group {b['group_accuracy']}. Confusion: "
                 + ", ".join(f"{c} ×{n}" for c, n in b["confusion"].items()))
        L.append("")
    L.append(f"Reference trips with unknown mode (excluded): {res['modes_unknown_reference_excluded']}.")
    if isinstance(res.get("bootstrap"), dict):
        b = res["bootstrap"]
        L += ["", f"Day-cluster bootstrap ({b['resamples']} resamples over {b['days']} days, small sample): "
              + ", ".join(f"{k} 95% [{v['lo95']}, {v['hi95']}]" for k, v in b.items() if isinstance(v, dict))]
    L += ["", "## Per day", "", "| day | fixes | time agree | ref V | pred V | matched V | ref T | pred T | matched T |", "|---|---|---|---|---|---|---|---|---|"]
    for d, b in res["per_day"].items():
        L.append(f"| {d} | {b['points']} | {b.get('time_agreement')} | {b['ref_visits']} | {b['pred_visits']} | {b['matched_visits']} | {b['ref_trips']} | {b['pred_trips']} | {b['matched_trips']} |")
    L += ["", "## Failure cases", "", "| id | kind | ref label | reference | predicted | min | fixes | near | plausible cause |", "|---|---|---|---|---|---|---|---|---|"]
    for f in res["failures"]:
        L.append(f"| {f['id']} | {f['kind']} | {f['label']} | {f['ref']} | {f['pred']} | {f['minutes']} | {f['fixes']} | {f['fixes_near']} | {f['cause']} |")
    return "\n".join(L) + "\n"


# ----------------------------------------------------------------------------- compare

def cmd_compare(a):
    A = json.loads(Path(a.baseline).read_text()); B = json.loads(Path(a.candidate).read_text())
    if A["days"] != B["days"]:
        sys.exit("evaluations cover different days; compare only on identical day sets")
    rows = []
    def add(name, x, y, better="higher"):
        d = None if x is None or y is None else round(y - x, 3)
        rows.append((name, x, y, d))
    for k in ("visits", "trips"):
        for m in ("precision", "recall", "f1", "fp", "fn"):
            add(f"{k} {m}", A[k][m], B[k][m])
    for k in ("visit_arrival_error", "visit_departure_error", "trip_departure_error", "trip_arrival_error"):
        add(f"{k} median abs (min)", A[k].get("median_abs_min"), B[k].get("median_abs_min"))
        add(f"{k} bias (min)", A[k].get("bias_min"), B[k].get("bias_min"))
    add("time agreement", A["time_agreement"]["share"], B["time_agreement"]["share"])
    add("trip splits", A["trip_split_count"], B["trip_split_count"]); add("trip merges", A["trip_merge_count"], B["trip_merge_count"])
    for k in ("modes_human_labelled", "modes_accepted"):
        add(f"{k} exact", A[k]["exact_accuracy"], B[k]["exact_accuracy"]); add(f"{k} group", A[k]["group_accuracy"], B[k]["group_accuracy"])
    print(f"{'metric':45} {'baseline':>9} {'candidate':>9} {'Δ':>8}")
    for name, x, y, d in rows:
        print(f"{name:45} {str(x):>9} {str(y):>9} {str(d):>8}")
    # paired per-day changes in matched events
    print("\nper-day matched visits / trips (baseline → candidate):")
    for d in A["days"]:
        pa, pb = A["per_day"][d], B["per_day"][d]
        if (pa["matched_visits"], pa["matched_trips"], pa["pred_visits"]) != (pb["matched_visits"], pb["matched_trips"], pb["pred_visits"]):
            print(f"  {d}: V {pa['matched_visits']}/{pa['ref_visits']} (pred {pa['pred_visits']}) → {pb['matched_visits']}/{pb['ref_visits']} (pred {pb['pred_visits']}); "
                  f"T {pa['matched_trips']}/{pa['ref_trips']} → {pb['matched_trips']}/{pb['ref_trips']}")


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    e = sub.add_parser("export", help="diary snapshot → reference.json + review.csv")
    e.add_argument("--db", required=True); e.add_argument("--out", required=True)
    e.add_argument("--reviewed-default", default="0", help="initial 'reviewed' value for new days in review.csv (default 0)")
    e.add_argument("--review-note", default="")
    s = sub.add_parser("split", help="freeze a whole-day calibration/validation split")
    s.add_argument("--reference", required=True); s.add_argument("--validation-share", type=float, default=0.3)
    s.add_argument("--salt", default="hht-46-v1"); s.add_argument("--force", action="store_true")
    s.add_argument("--validation-after", metavar="YYYY-MM-DD",
                   help="forward split: days up to this date are calibration, complete days after it are validation; "
                        "re-run on a later export to fill the holdout (never changes calibration days)")
    v = sub.add_parser("evaluate", help="match predictions to the reference and score them")
    v.add_argument("--reference", required=True); v.add_argument("--pred", required=True); v.add_argument("--out", required=True)
    v.add_argument("--days", choices=["calibration", "validation", "all"], default="calibration")
    v.add_argument("--db", help="snapshot, for per-day fix counts and failure diagnostics")
    c = sub.add_parser("compare", help="paired baseline vs candidate on the same days")
    c.add_argument("--baseline", required=True); c.add_argument("--candidate", required=True)
    a = p.parse_args(argv)
    {"export": cmd_export, "split": cmd_split, "evaluate": cmd_evaluate, "compare": cmd_compare}[a.cmd](a)


if __name__ == "__main__":
    main()
