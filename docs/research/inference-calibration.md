# Inference calibration against a human-corrected diary

Issue [#46](https://github.com/zyang91/HHT-app/issues/46). This note covers the audit (Phase 0), the reference dataset
and review protocol (1), the offline replay harness (2), matching rules and metrics (3), the first calibration round (4)
and its held-out validation (5). Everything published here is aggregate: no coordinates, places, timelines or
per-day diaries. The private inputs and full reports live in a gitignored `calibration-data/` folder on the
developer's machine.

## 0. Audit: where the data and the decisions live

### Data flow

```
CoreLocation / CLVisit / region exits / significant change ─┐
CoreMotion activity (synced before each run) ───────────────┤
                                                            ▼
   raw_location_points, motion_activities   (layer 1, append-only; never rewritten by inference)
                                                            │  InferenceEngine.processNew() / process(from:to:)
                                                            ▼
   StayDetector.clean → detect → mergeStays   →   visits    (layer 2, user_status = auto)
   ModeClassifier.segment between visits      →   trips + trip_segments
                                                            │  EditService (every user action)
                                                            ▼
   visits / trips with user_status ∈ {confirmed, edited, manual}, deleted = 1 for user deletions
   audit_log: one row per edit (entity, action, field, old → new, timestamp)
```

* **Entry points.** `AppModel.runInference()` calls `processNew()` (on launch, foreground, collector stop, background
  refresh) or `process(from:to:)` for "Rebuild from raw data". Both are in
  `Packages/HHTCore/Sources/HHTCore/Inference/InferenceEngine.swift`.
* **Thresholds.** All of them are fields of `InferenceConfig` (`InferenceConfig.swift`, documented in
  [`docs/inference.md`](../inference.md)). The struct is `Codable`; `hht-calibrate config` prints it as JSON.
* **State machine.** Stay detection is a single sequential pass with the gap, drift, core-trim and merge rules in
  `StayDetector.swift`. The reprocessing contract (locked records, absorption, stable auto IDs) is in
  `InferenceEngine.process`.
* **Engine version.** There is no version field yet. A replay is pinned by git commit + config JSON (in every output).

### Provenance: what the database can and cannot tell us

| Question | Answer from the schema |
|---|---|
| Raw observations kept? | Yes. `raw_location_points` and `motion_activities` are append-only. |
| Edits recorded as events? | Partly. `audit_log` has a timestamped row per edit, but no full before/after record snapshot. |
| Original machine output kept? | **No.** Edited records are updated in place (`user_status` changes, values overwritten). Once a visit is edited, nothing stores what the engine first said. |
| Manual vs inferred? | Yes. `source = manual` / `user_status = manual` for records the user added; `edited` / `confirmed` for inferred records a person changed or accepted. |
| Deletions? | Soft delete (`deleted = 1`), kept and honoured by reprocessing. |
| Untouched records? | `user_status = auto`: produced by some earlier engine version and never edited. |

**Consequence (documented, not worked around):** the historical app output cannot be reproduced. The baseline
prediction is a *replay* of the raw points through the engine at a pinned commit, not "what the app showed at the
time". The snapshot used here had 104 human-touched visits (15 of them deletions), 118 human-touched trips, and 25 visits
/ 9 trips still `auto`.

## 1. Reference dataset and review protocol

`python3 analysis/calibrate.py export --db <snapshot> --out calibration-data/reference` writes:

* `reference.json`: every visit and trip with its label source (`user_status`, `source`), deletion flag, edit-event
  count from `audit_log`, segment modes (`mode_user` vs `mode_auto`), plus metadata: snapshot SHA-256, schema version,
  extraction time, the app's `last_inference_at`, point and motion time ranges, default time zone, privacy notice and
  the provenance limits above.
* `quality` block: invalid coordinates, duplicate timestamps, out-of-order inserts, negative durations, overlapping
  visits, orphaned trip/segment references, open visits, sampling gaps (total and in `moving` collector mode).
* `review.csv`, one row per day: `reviewed`, `quality`, `note`. **Only days marked reviewed are scored.** New days default
  to unreviewed (`--reviewed-default 0`). Re-exporting keeps earlier review decisions.
* `exclusions.csv`: local-time intervals to leave out of scoring (`kind,start_local,end_local,reason`), e.g. a stretch
  you no longer remember or a GPS-dead day.

Label handling:

* *human* = `edited`, `confirmed` or `manual`; *accepted* = `auto` on a reviewed day. Recall is reported separately for
  each. Accepted labels came from an earlier engine, so they are biased toward the engine and are never pooled silently.
* Mode accuracy uses only trips whose mode a person set (`mode_user` on the trip or a segment, or a manual trip).
  Accepted modes are reported separately. Reference trips with mode `unknown` are excluded and counted.
* Manual visits store the place's coordinate, not an observed centroid, so they are left out of the location-error metric.

For this first round the developer stated that every day on the phone had been reviewed, so all 17 days with diary
entries were marked `reviewed=1` with that note. Per-day confirmation and exclusions are still open for later rounds.

### Snapshot quality (aggregate)

20 days of collection, 4,127 fixes, 34,578 motion samples. No invalid coordinates, negative durations, overlapping
visits or orphan references. Two collector issues worth their own investigation, and **not** compensated for by
thresholds:

* 247 timestamps carry duplicate fixes and 698 fixes were inserted out of time order (deferred delivery). The cleaner sorts
  by time, so inference is unaffected, but duplicates inflate point counts.
* 103 of the 216 silences longer than 15 min began in `moving` collector mode. These are walks and rides with no GPS, and they
  drive most of the trip-boundary errors below.

## 2. Offline replay harness

```bash
make calibrate-tool                                   # builds Packages/HHTCore/.build/release/hht-calibrate
hht-calibrate replay --db <snapshot>/travel.sqlite --out pred.json                 # batch ("Rebuild from raw data")
hht-calibrate replay --db … --out pred.json --mode streaming --step 900            # processNew every 15 min of data
hht-calibrate replay --db … --out pred.json --config candidate.json                # partial InferenceConfig override
hht-calibrate reinfer-check --db <snapshot>/travel.sqlite                          # edits survive a full rebuild?
```

* **Same engine.** `Replay` (in `HHTCore/Calibration/Replay.swift`) inserts the snapshot's raw points and motion into a fresh
  in-memory `TravelStore` and calls the production `InferenceEngine`. It never sees places, edits, deletions or the
  audit log, so human corrections cannot leak in as inputs. Python never re-implements inference.
* **No side effects.** The snapshot (and its WAL) is copied to a private temp file. Only the copy is opened, because
  opening runs migrations. The calibration copy of the snapshot is also `chmod a-w`. Its SHA-256 was unchanged after every run.
* **Determinism.** The output has no record IDs or wall-clock fields, keys are sorted, and "now" defaults to the snapshot's
  own `last_inference_at`. Two runs on the same input are byte-identical (checked in CI by `make calibrate-smoke` and in
  `CalibrationTests`).
* **Streaming vs batch.** Streaming feeds the data in steps and runs `processNew` after each one, approximating the live
  app (which runs on events, not a fixed clock). Both modes are scored. They agreed closely here (§5).
* **Config.** `--config` takes a partial JSON object merged onto `InferenceConfig.default`. Unknown keys are rejected.
* **Synthetic CI path.** `make calibrate-smoke` writes a synthetic two-day diary with a known reference
  (`CalibrationTests.writeCalibrationFixture`), replays it twice, checks the outputs are identical, exports, evaluates
  and checks floors (`analysis/check_calibration.py`). No private data is involved.

## 3. Matching rules and metrics

`python3 analysis/calibrate.py evaluate --reference … --pred … --days calibration|validation|all --db <snapshot>`

**Evaluation window.** From the first raw fix to the replay's "now". Open reference visits end at that horizon.

**Day attribution.** An event belongs to the local day it starts on. Matching runs on the whole timeline first and is
then attributed, so midnight cannot split a match. A matched pair counts toward the reference event's day.

**Visit matching (one-to-one, deterministic).** A (reference, prediction) pair is a candidate if the centroids are within
300 m **and** either the temporal overlap is ≥ 50 % of the shorter interval, or both endpoints are within 15 min (with any
overlap). Candidates are assigned greedily by descending temporal IoU (ties: earlier reference, then earlier prediction).
Unmatched references are FN, unmatched predictions are FP. Row order and IDs are never used. **Trips** use the same rule
without the distance test.

**Splits and merges.** A reference trip covered (> 50 % of the shorter one) by ≥ 2 predicted trips is a split. A predicted
trip covering ≥ 2 reference trips is a merge.

**Timing.** Signed error (prediction − reference) in minutes on matched pairs: bias, median and mean absolute, p90.
Departures are only scored when neither side is open.

**Whole-day time agreement.** For each reference minute (sampled every 60 s) the reference state is *at a stay* or
*travelling*. A minute agrees when the prediction says *travelling* too, or a stay whose centroid is within 300 m.
Disagreements are tallied by type (`ref_stay_pred_travel` = phantom trip, `ref_travel_pred_stay` = missed trip, …).
This is the metric most sensitive to split stays and long timing errors, which F1 hides.

**Breakdowns.** Visit P/R/F1 by stay duration (< 15 min, 15–60 min, 1–4 h, > 4 h) and by label source. Trip recall by
reference mode group. A per-day table. A failure table with day-local IDs (`10-02/V3`), local HH:MM intervals, fix
counts and a rule-based *plausible* cause (recording gap, indoor drift, short stop, absorbed into trip, split stay, …),
which is a pointer for diagnosis, not a verdict.

**Uncertainty.** Day-level cluster bootstrap (500 resamples, seed 0) for visit F1, trip F1 and time agreement. Days are
resampled, never points. With 12 + 5 days the intervals are wide and are labelled as small-sample.

`compare --baseline A --candidate B` refuses to compare evaluations over different day sets and prints paired deltas
plus per-day changes.

## 4. Calibration round 1

**Split, frozen before any tuning.** Whole days, salted SHA-256 ranking. Only complete days (collection running all day)
can be validation days: 12 calibration days and 5 validation days (`split.json`, salt `hht-46-v1`).

**Baseline first.** The engine at `cb0abde` with default config was replayed and archived (batch and streaming) before any
change.

**Diagnosis.** On calibration days the baseline disagreed with the diary for 3,439 of 16,126 minutes in one direction:
*diary says at a place, engine says travelling*. Stepping through the worst cases in the raw points turned up four
structural causes, none of them a recording failure:

| # | Failure class | Mechanism | Change |
|---|---|---|---|
| 1 | Evening at home split by a phantom "home → home" trip | ≥ 5 min of *cumulative* CoreMotion walking over a 1.5–3 h location silence counted as "left and came back". Indoor pottering easily reaches 5–20 min. | `gapMovingSeconds` 5 → 20 min (see the grid below) |
| 2 | Stay ended by one stray fix | 1–2 fixes 110–250 m out, then the collector went quiet (stationary), then the next fix was back inside. The drift rule only looked 2 min ahead. | New rule: drift before a stationary silence |
| 3 | Departure to a building next door dated hours late (or early) | The walk happened during a silence. The departure was back-dated from the next fix, which can be hours later. The motion log shows the walk. | Departure = start of the latest motion bout that could cover the distance |
| 4 | Arrival 30–60 min late | The last walk-in fix sat just outside the core radius, then the collector went quiet. Core trimming dropped it. | Keep that fix as the arrival when a stationary silence follows |

Change 1 alone broke the "data ends inside a stay" check (walking out right now was read as stationary). That check now
looks at the *current* movement bout instead of the cumulative total, which also fixed an existing fixture.

**Grid (calibration days only, batch).** Motion during same-place silences overlapped heavily between real out-and-back
trips and indoor movement, so no motion rule separates them cleanly. The tradeoff was measured directly:

| `gapMovingSeconds` | 5 min | 10 | 15 | **20** | 25 | 30 | 40 |
|---|---|---|---|---|---|---|---|
| time agreement, without / with change 2 | 0.778 / 0.785 | 0.878 / 0.886 | 0.918 / 0.925 | 0.934 / 0.941 | — / 0.941 | 0.934 / 0.941 | — / 0.947 |

20 min is the smallest value on the plateau, so it gives up the fewest real short loops. 40 min scored marginally higher and was rejected
as the edge of overfitting. Changes 3 and 4 then took 20 min from 0.941 to 0.953. That candidate was frozen before
validation.

## 5. Results

Batch replay. Streaming (15 min steps) gave the same conclusions, within ±1.1 pp time agreement and identical event counts
on validation. Bootstrap 95 % intervals in brackets. Small sample: 12 and 5 days.

| | Calibration (12 days) baseline | → candidate | **Validation (5 days, run once)** baseline | → candidate |
|---|---|---|---|---|
| Whole-day time agreement | 0.778 [0.70, 0.85] | 0.953 [0.92, 0.98] | 0.827 [0.68, 0.93] | **0.939** [0.91, 0.97] |
| Minutes "at a place" scored as travel | 3,439 | 473 | 1,139 | 307 |
| Minutes "travelling" scored as a stay | 124 | 273 | 108 | 134 |
| Visits P / R / F1 | 0.79 / 0.84 / 0.81 | 0.81 / 0.83 / 0.82 | 0.92 / 0.80 / 0.85 | 0.95 / 0.80 / 0.86 |
| Trips P / R / F1 | 0.76 / 0.81 / 0.78 | 0.82 / 0.84 / 0.83 | 0.95 / 0.80 / 0.86 | 0.95 / 0.80 / 0.86 |
| Visit arrival bias / mean abs (min) | +51.7 / 52.4 | +2.4 / 5.5 | +4.2 / 6.0 | +2.6 / 5.5 |
| Visit departure bias / mean abs / p90 (min) | −33.7 / 39.3 / 98 | +2.2 / 8.9 / 17 | −28.8 / 32.0 / 68 | **+0.3 / 5.6 / 19** |
| Trip merges | 7 | 3 | 4 | 4 |
| Mode, human-labelled: exact / group (n) | 0.34 / 0.47 (38) | 0.42 / 0.49 (41) | 0.36 / 0.56 (25) | 0.35 / 0.54 (26) |

Median absolute timing errors are 0–2 min in every column. The improvement is in the tail, where split stays had put
arrivals and departures off by hours.

**Adverse tradeoffs (reported, not hidden):**

* *Missed trips up.* Minutes of real travel predicted as a stay rose (124 → 273 calibration, 108 → 134 validation).
  Short walks between buildings < 100 m apart, with no fix in between, now merge into one stay (the "multiple nearby
  locations" scenario). Visit recall fell by one event on calibration days.
* One validation day lost a 5-minute stop, swallowed by the now-later departure from the previous stay.
* Accepted (never-edited) modes: one fewer trip correct in each split.

**Release check on real data: edits survive re-inference.** `hht-calibrate reinfer-check` ran a full
`process(from:to:)` over a private copy of the snapshot, edits included. All 104 human-touched visits (15 of them
deletions) and all 118 human-touched trips came through unchanged: times, deletion flags, places, user modes, segments,
endpoints. It created no new visits (+0 / ~0 / −0). It does **not** prove that a deleted stop never hides a real later one.
The synthetic tests cover that case (`deleteVisitMergesTripsAndStaysDeleted`).

## 6. Remaining failure modes (validation and calibration combined)

1. **Unobservable stops.** 8 manually added stops had no GPS fix at all during the stay, so the engine cannot see them.
   This is a collector issue, not an inference one.
2. **Walks during location silence.** "Absorbed into a predicted trip" (5 on validation days) and "stationary period
   inside a reference walk trip" (5 on calibration days) both trace back to the 103 moving-mode silences.
3. **Nearby buildings merged** (3 on calibration days). See the tradeoff above.
4. **Mode classification is the weakest component.** On human-labelled trips, subway is often scored as car or walk, and
   taxi/ride-hail as subway (8 calibration trips). Only 35–55 % are right even at group level. Calibration round 1 did not
   touch modes.
5. **Arrival after a silent walk** is still dated by the next fix. Only the departure side reads the motion log.
6. **Indoor drift of hundreds of metres** at large venues still creates duplicate stays 200–500 m apart.

## 7. Release readiness

| Criterion | Status |
|---|---|
| Synthetic evaluation from a fresh checkout | ✅ `make calibrate-smoke` (in CI) |
| Private evaluation on a phone snapshot | ✅ commands above |
| Deterministic replay and metrics | ✅ byte-identical outputs; tested |
| Raw / machine / human kept apart, replay never mutates data | ✅ for raw and human. ⚠️ Historical machine output is unrecoverable once edited (schema gap, §0) |
| Human edits survive re-inference | ✅ synthetic tests and the real-snapshot `reinfer-check` |
| Tuning checked on untouched days, tradeoffs reported | ✅ §4–5 |
| No personal location history published | ✅ aggregates only. `calibration-data/` is gitignored |
| Regression fixtures for the failure classes found | ✅ `CalibrationTests` (each fails on the old engine) |

**Recommendation:** ship the round-1 changes. They fix a large, systematic diary error (phantom trips splitting long
stays) and showed no data loss. Not release-blocking but open: mode classification (§6.4), moving-mode GPS silences in the
collector (§6.2), and keeping the original machine output when a record is first edited, so future rounds can measure
the app's real behaviour and not only a replay.

## Reproducing

```bash
# 1. pull the diary off the phone into the gitignored workspace (read-only afterwards)
xcrun devicectl device copy from --device <UDID> --domain-type appDataContainer \
  --domain-identifier com.zyang91.hht --source "Library/Application Support" --destination calibration-data/snapshots/<stamp>
chmod a-w calibration-data/snapshots/<stamp>/HHT/travel.sqlite*
S=calibration-data/snapshots/<stamp>/HHT/travel.sqlite
# 2. reference + review sheet, then mark days in review.csv, then freeze the split once
python3 analysis/calibrate.py export --db $S --out calibration-data/reference
python3 analysis/calibrate.py split --reference calibration-data/reference
# 3. replay + evaluate (calibration days while tuning; validation once per protocol version)
make calibrate-tool
Packages/HHTCore/.build/release/hht-calibrate replay --db $S --out calibration-data/results/<name>/batch.json
python3 analysis/calibrate.py evaluate --reference calibration-data/reference --db $S \
  --pred calibration-data/results/<name>/batch.json --out calibration-data/results/<name> --days calibration
python3 analysis/calibrate.py compare --baseline …/metrics-calibration.json --candidate …/metrics-calibration.json
```
