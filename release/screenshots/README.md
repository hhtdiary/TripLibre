# App Store screenshots

`iphone-6.9/` holds nine 1320 × 2868 portrait PNGs (RGB, no alpha), the size App Store Connect requires for the
6.9" iPhone display. App Store Connect scales them down for smaller iPhones, so no other sizes are needed. The app is
iPhone-only, so there are no iPad screenshots.

| File | Screen | Shows |
|---|---|---|
| `01-today.png` | Today, Thu Oct 22 | Mascot summary, day map, trip/distance/time/places tiles, "Spent this day" |
| `02-diary.png` | Today, scrolled | "Your day, step by step": visits, multimodal trips, costs, confirmed badges |
| `03-fix-a-trip.png` | Trip detail | Route map and the one-tap mode grid |
| `04-timeline.png` | Timeline | Week chart, Find trips, Flights, Life phases, day list |
| `05-map.png` | Map, 7 days | Routes, places and activity space with radius of gyration |
| `06-stats.png` | Stats, 30 days | Per-day metrics, spending summary, mode share |
| `07-spending.png` | Spending, 30 days | Travel vs destinations, day-by-day chart, categories |
| `08-places.png` | Places | Named places with visit counts and time spent |
| `09-settings-privacy.png` | Settings | Recording status, the on-device privacy statement, export |

Captions and upload order are in `../app-store-listing.md`.

## How they were made

1. **Real data.** The database was copied from the iPhone with
   `xcrun devicectl device copy from --domain-type appDataContainer --domain-identifier com.zyang91.hht` into
   `calibration-data/snapshots/release-20261024-233921/` (gitignored, never committed).
2. **De-identified copy.** A script (kept next to the snapshot, also gitignored, because its rename table contains the
   original place names) wrote `screenshot-safe.sqlite`:
   - Home was moved to a decoy point several hundred metres away. Every GPS fix, visit, stamp and route point within a
     few hundred metres of the real home was snapped to the decoy, and routes that start or end at home were
     extended to it, so no route end points at the real address.
   - Workplace, appointment and personal place names were generalised (e.g. *Office*, *Lecture hall*, *Teaching
     lab*, *Hotel*, *Barber*); typos in other names were tidied.
   - One sensitive appointment visit and its two trips were left out entirely.
   - All notes, geocoded addresses, flight numbers, seats and booking references, and the whole audit log were
     cleared. Address lookup stayed off, so the simulator never geocoded anything.
3. **Simulator.** iPhone 18 Pro Max simulator (iOS 27.0), Debug build of `main`, status bar overridden to 9:41, full
   battery, full signal. The de-identified database was copied into the app's container; `-hhtDaysAgo 2` opened Today
   on Oct 22, and `hhtTab` picked the starting tab. Captured with `xcrun simctl io <udid> screenshot`, then flattened
   to RGB.

## What can still be inferred

The screenshots are de-identified, not anonymous. They still show the general area (Center City and University City,
Philadelphia), a nearby grocery, the campus and real dates in October 2026. That fits what the public README already
says about the project; swap in demo data if that's too much.

## Retaking them

The private snapshot and script are in `calibration-data/snapshots/release-20261024-233921/`. To retake after a UI
change, rebuild (`make build`), install on the same simulator, copy `work/screenshot-safe.sqlite` to
`Library/Application Support/HHT/travel.sqlite` in the app container, set `onboarded`, `reverseGeocoding=NO` and
`hhtTab` with `xcrun simctl spawn <udid> defaults write com.zyang91.hht …`, and launch with `-hhtDaysAgo <n>`. Dates are
relative to today, so `n` changes from day to day.
