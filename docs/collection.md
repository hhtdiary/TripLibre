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
- A `CLBackgroundActivitySession` is held while collection is enabled (recreated on background relaunch) so iOS keeps
  delivering moving-mode updates in the background.
- While collecting, live CoreMotion activity (if already authorized) feeds the stationary decision. The ~7-day history is
  also queried whenever inference runs.
- A background refresh task (`com.zyang91.hht.refresh`, ~every 2 h when iOS allows) runs inference and the daily backup.

Permissions: Location **Always** (required for background), Motion & Fitness (optional but improves modes).
The blue background-location indicator is disabled; iOS still shows the location arrow in the status bar.

Battery: GPS runs only while moving. Expect a few % per day for a typical urban routine; "Precise" costs more.
