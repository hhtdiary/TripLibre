# Background collection

Implemented in `App/Location/LocationCollector.swift`.

| State | Location settings | Leaves the state when |
|---|---|---|
| **moving** | continuous updates; Balanced: 10 m accuracy / 15 m filter; Precise: best / 5 m | no fix > 60 m from an anchor for 3 min, last fix ≤ 2 m/s and CoreMotion not walking/running/cycling/automotive → stationary (after 10 min the speed/motion vetoes are ignored) |
| **stationary** | standard updates **off**; 150 m geofence around the stop; CLVisit + significant-change monitoring stay on | geofence exit, CLVisit departure, or a significant-change fix > 150 m away → moving |

- Region exits, visits and significant changes relaunch the app even after it was terminated;
  `AppDelegate` restarts collection on every launch (including background launches).
- Every fix is written immediately to `raw_location_points` with its `collector_mode`. When entering stationary mode the
  last fix is written again as `stationary_marker`, so inference can distinguish "quiet because stationary" from lost signal.
- The decision lives in `StationaryDetector` (HHTCore, unit-tested). Silence alone is not proof of a stop: when iOS
  suspends the app mid-drive and resumes it minutes later, the check is postponed ~5 s so queued fixes arrive first.
- **Safety-net geofence in moving mode.** iOS can suspend the app in moving mode before the dwell completes, typically
  right after a background wake while the phone is still: the distance filter delivers no more fixes and the 60 s timer
  stops with the app. Without a fence, a departure then went unnoticed until the next significant change (30–40 min
  late in the 2026-11-12 snapshot, #46). So whenever the detector's anchor is held by a fix at walking speed or slower
  (or without speed), the same 150 m geofence is armed around it; it moves with the anchor and is withdrawn while the
  last fix is faster than 2 m/s (`StationaryDetector.safetyNet`). An exit wakes the app and restarts moving mode.
- A `CLBackgroundActivitySession` is held while collection is enabled (recreated on background relaunch) so iOS keeps
  delivering moving-mode updates in the background.
- While collecting, live CoreMotion activity (if already authorized) feeds the stationary decision. The ~7-day history is
  also queried whenever inference runs.
- Tapping *Stamp this moment* (docs/inference.md §8) wakes the collector from stationary into moving mode, so the short
  stop and the walk away from it get fixes; the usual 3-minute rule puts it back to sleep if nothing moves.
- A background refresh task (`com.zyang91.hht.refresh`, ~every 2 h when iOS allows) runs inference and the daily backup.

Permissions: Location **Always** (required for background), Motion & Fitness (optional but improves modes).
The blue background-location indicator is disabled; iOS still shows the location arrow in the status bar.

Battery: GPS runs only while moving. Expect a few % per day for a typical urban routine; "Precise" costs more.
