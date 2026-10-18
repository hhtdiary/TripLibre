# Inference: from GPS fixes to visits and trips

All thresholds are fields of `InferenceConfig` (`Packages/HHTCore/Sources/HHTCore/Inference/InferenceConfig.swift`).
Defaults shown in brackets. Everything is deterministic and rule-based; tests in
`Packages/HHTCore/Tests/HHTCoreTests/InferenceTests.swift` cover the 14 fixture scenarios from the brief.

## 1. Cleaning
- Drop fixes with horizontal accuracy > `maxHorizontalAccuracy` [100 m] (CLVisit events: [250 m]). They stay in the raw table.
- Drop single-point spikes: A→B and B→C both faster than `maxPlausibleSpeed` [320 m/s] while A→C is not.

## 2. Stay (visit) detection — sequential clustering
Walk through fixes in time order. A fix reporting speed > 1.5 m/s cannot start a cluster. From a seed fix, keep adding
fixes while they are within `stayRadius` [100 m] of the running, accuracy-weighted centroid (fixes moving > 1 m/s count 10× less).

When a fix falls outside the radius:
- **Drift**: if the cluster is established (≥ 60 s) and a later fix within `driftMaxDuration` [120 s] returns inside,
  the excursion is GPS drift and skipped.
- **Departure**: otherwise the cluster ends.

**Data gaps** (> `gapThreshold` [15 min] between fixes) are normal: the collector deliberately stops GPS when stationary.
A gap is treated as *stationary* if CoreMotion shows < `gapMovingSeconds` [20 min] of walking/running/cycling/automotive
during it, or — with no motion data — if the last fix was recorded in `stationary` collector mode. (20 min, not 5, was
calibrated on real days: indoor pottering adds up to 5–20 min of "walking" over a long silence at one place; see
[research/inference-calibration.md](research/inference-calibration.md).)
- Stationary gap, next fix inside the radius → the stay continues through the gap.
- Next fix outside → if the motion log shows a movement bout (≥ `minSegmentDuration`, blips ≤ 3 min joined) that began
  early enough to cover the distance at a plausible speed, the departure is the start of the latest such bout
  (e.g. a walk to a building next door while location was silent). Otherwise, for a stationary gap, the departure is
  back-dated from the next fix by distance ÷ a plausible speed (1.4 m/s < 2 km, 10 m/s < 50 km, 25 m/s < 500 km, else 220 m/s air).
- Moving gap, next fix inside → the stay ends (the person left and came back; the loop becomes a trip).
- **Drift before a silence**: a few non-moving fixes outside the radius (but within `mergeMaxExcursionDistance`), then a
  stationary gap, then a fix back inside → drift; the stay continues.
- **Data ends inside a stay**: it is ongoing unless the motion log says we are moving *now* and have been for
  ≥ `minSegmentDuration` (then it ended when that movement began).

A cluster becomes a visit if it lasts ≥ `minStayDuration` [5 min]. Its arrival/departure are trimmed to the first/last
fix within the **core radius** (max(`stayCoreRadius` [35 m], 1.5 × median member distance)) after re-centring on the
inner half, removing the walk-in / walk-out bias of radius clustering. Exception: when the collector went quiet right
after the last non-core fix (stationary gap before the first core fix), that fix is the arrival — we had already arrived. If the data ends inside a stay that is plausibly
still ongoing, the visit gets no departure.

**Merging**: consecutive stays ≤ `mergeDistance` [150 m] apart, separated by an excursion shorter than
`mergeMaxExcursionDuration` [10 min] that never went beyond `mergeMaxExcursionDistance` [250 m], are merged.

## 3. Places
Each stay is matched to the nearest active place whose radius + `placeMatchSlack` [40 m] contains its centroid
(named places win over unnamed ones). Otherwise an unnamed place is created with radius `newPlaceRadius` [80 m].
Naming or categorising a place therefore makes all future visits to it recognised automatically.

## 4. Trips and modes
A trip connects consecutive visits; its path is every cleaned fix between departure and arrival plus both visit centroids.
Distance = path length (straight line across gaps). `has_gap` = any > 15 min hole.

**Per-interval class** between consecutive fixes (speed = distance / time; CoreMotion activity at the midpoint):
- ≥ `airMinSpeed` [70 m/s] → air
- motion walking / running / cycling → walk / run / bike (vehicle if faster than plausible); automotive → vehicle
- no motion: < 0.3 m/s still; ≤ `walkMaxSpeed` [2.2] walk; ≤ `bikeMaxSpeed` [7] bike (vehicle across a signal gap); else vehicle
- "still" intervals take the class of the next moving interval (waiting precedes boarding).

**Segmentation**: run-length encode the classes; repeatedly absorb the shortest run under `minSegmentDuration` [120 s]
into its longer neighbour. Short access walks under 2 min are therefore folded into the vehicle segment.
A walk run whose straight-line displacement is ≥ `walkCheckMinDisplacement` [1 km] at > `walkMaxDisplacementSpeed`
[2.5 m/s] becomes a vehicle run: sparse station fixes plus walking-like CoreMotion on a train otherwise read as a walk.

**Segment refinement**: an air run shorter than `airMinDistance` [50 km] is a GPS jump and is refined as vehicle.
Vehicle runs, in order (issue #46 round 2 added the road-evidence and no-evidence rules):
1. airplane if avg ≥ 0.6·air speed over > 150 km; intercity rail if ≥ 60 km with p90 speed 38–70 m/s (conf 0.35);
2. **road evidence → car**: CoreMotion automotive ≥ `roadMinAutomotiveShare` [60 %] of covered time and ≥
   `roadMinGoodFixShare` [50 %] (and ≥ `roadMinGoodFixes` [5]) of fixes are "good" (accuracy ≤ `roadFixMaxAccuracy`
   [20 m] with reported speed ≥ `roadFixMinSpeed` [3 m/s]). Conf 0.6, or 0.45 if one hole exceeds `gapThreshold`.
   The collector leaves ~5 min holes during car rides; without this rule they looked like tunnels;
3. subway if > 40 % of time is signal loss (no fix for > `movingGapThreshold` [120 s] while covering > 300 m) at
   4–25 m/s over < 40 km (conf 0.4);
4. **no road evidence → subway**: motion covered, automotive < `undergroundMaxAutomotiveShare` [50 %], good fixes
   < `undergroundMaxGoodFixShare` [20 %], avg < 25 m/s, < 40 km (conf 0.35). Underground, CoreMotion mostly says
   unknown or walking and fixes are coarse Wi-Fi/cell ones without speed;
5. else car (conf 0.4–0.5).

Bus vs car vs taxi is not separable without GTFS; buses mostly land in subway (same transit group). Above-ground rail at
road speeds with automotive motion and clean GPS reads as car. Correct it once and personalisation handles repeats.

**Main mode** = highest in: airplane > intercity rail > coach > ferry > commuter rail > subway > light rail > bus >
shuttle > taxi > car (driver/passenger/unspecified) > e-bike > bicycle > scooter > run > walk, among segments ≥ 2 min or ≥ 300 m.

**Personalisation**: if the user has corrected earlier trips between the same origin and destination places and ≥ 60 %
of those corrections agree, that mode is used (confidence grows with the number of corrections). Needs ≥ 2 corrections
when it contradicts the geometry's mode group.

A trip **needs review** when it is untouched and its mode is unknown or has confidence < 0.5.

Airplane trips also create a `flights` row. When reprocessing rebuilds an airplane trip, the flight left behind by the
old trip is re-attached (keeping seat, flight number, notes) instead of a new row being added; inferred flights that end up
with no trip and no user-entered details are removed.

## 5. Confidence
- Visit: 0.5 + 0.5 × min(1, fixes/5) × min(1, duration/20 min).
- Trip existence: 0.5 with a data gap, else 0.6 + 0.1 × fixes per minute (≤ 0.95).

## 6. Incremental runs and reprocessing
`processNew()` runs on launch, on foreground, when the collector declares a stop, and from background refresh.
It reprocesses from the arrival of the latest visit, loading `contextMargin` [30 min] of earlier fixes so the anchor
stay is detected exactly as in a full run. `process(from:to:)` rebuilds any range (window widened to whole visits).

Rules that keep user corrections safe:
1. Records with `user_status ≠ auto`, and auto visits referenced by such trips, are **locked** — never modified
   (an ongoing locked visit may receive its departure time; logged as `infer_departure`).
2. A detected stay overlapping a locked trip or a user-deleted visit is ignored (the user said it was travel / not a stop).
3. A detected stay overlapping a locked visit is absorbed by it.
4. Auto visits matched by a detection are updated **in place** (stable IDs); unmatched ones are deleted with their auto trips.
5. Auto trips in the window are rebuilt; no trip is created where a locked trip already covers the interval.
6. Self-reported stamps (§8) add stays before rules 2–5 apply, so a user deletion or a locked trip still wins over a stamp.

Tests assert: incremental == one-shot, repeated runs change nothing, edits survive full rebuilds, deleted stops stay deleted.

## 7. Calibration against a real diary
`hht-calibrate` replays raw points through this engine offline (batch or streaming), and `analysis/calibrate.py`
scores the result against a human-corrected diary. Protocol, matching rules, results and limitations:
[research/inference-calibration.md](research/inference-calibration.md).

## 8. Self-reported stamps
*Stamp this moment* on Today saves a **stamp**: "something worth recording happened around here, around now".
It is user evidence, not ground truth for the stop's position, and it complements passive detection instead of
overriding it. Code: `Inference/StampAnchoring.swift`; thresholds in `InferenceConfig` (`stamp*`).

**What a stamp stores.** The tap time, and only a coarse location: the latest fix rounded to 3 decimals (≈ 110 m)
with an uncertainty radius = fix accuracy + half a rounding cell (≈ 70 m) + 1.4 m/s × fix age. A fix older than
10 min is not used; the stamp is then saved with its time only. Poor GPS just makes the radius larger.

**How inference uses it** (after stays are detected and merged, before they are resolved to visits):
1. *Match.* A stay accounts for a stamp if the tap is within the stay ± `stampTimeTolerance` [10 min] and, when the stamp
   has a location, the stay centroid is within its uncertainty + `stayRadius` + `placeMatchSlack`. Nothing changes.
2. *Conflict.* A tap inside a stay that is too far away contradicts the sensors; the stamp stays unmatched.
3. *Short stop.* Otherwise the cleaned fixes within ± `stampSearchWindow` [10 min] (and between the neighbouring stays) are
   searched. From the fix nearest the tap (inside the stamp's radius), a cluster grows both ways while fixes stay within
   `stayRadius` of it, with no minimum dwell: the stamp is the evidence of the stop. The centroid, arrival and departure
   come from those fixes (stretched to include the tap). With no fix nearby, the stamp's coarse coordinate is used.
   The stop lasts at least `stampMinStayDuration` [60 s], never overlaps its neighbours, is open (`departure` NULL) if it
   runs to the newest fix and that fix is recent, and gets confidence `stampStayConfidence` [0.8].
4. The new stay then goes through §6 like any other: it becomes an ordinary auto visit (`source = inferred`), splits
   the trip it interrupted, and keeps a stable ID across runs.
5. *Link.* At the end of each run every stamp in the window gets `stamps.visit_id` = the visit that matches it (nearest in
   time, then space), or NULL. That link is the only thing inference ever writes to a stamp.

The distinction between inferred and self-reported is kept in the data: visits stay inferred, and the stamp rows say
which of them the user vouched for. Deleting the visit ("This wasn't a stop") wins on every later run; withdrawing the
stamp removes a stop that only it supported. Stamps are human input, so the calibration replay (§7) ignores them,
like every other correction.

## Known limitations / next steps
- Bus vs car vs ride-hail needs GTFS/route matching.
- Short (< 2 min) access/egress walks are merged into the main segment.
- The collector's region-exit wake-up can lag departure by a few minutes; CLVisit departure events and back-dating correct most of it.
- Place centroids of inferred places are not re-estimated from later visits yet.
- Arrival after a walk hidden in a location silence is dated by the next fix (only the departure side uses the motion log).
- Consecutive stays at buildings < 100 m apart with no fix between them merge into one visit.
- A stamp tapped while the phone already sat in one long stay is absorbed by it; two stops a block apart need GPS between them.
- Stamps carry no activity type yet (a note can be stored, but there is no UI for it).
