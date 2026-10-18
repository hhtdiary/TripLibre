# Privacy

## What is stored
Everything lives in one SQLite file inside the app's sandbox (`Library/Application Support/HHT/travel.sqlite`):
raw GPS fixes, CoreMotion activity episodes, inferred and corrected visits/trips, your places, flights, life phases,
stamps you tapped and an audit log of every edit. A stamp keeps only a coarse location (rounded to ≈ 110 m) and works
without a precise fix, or any fix, at all. Daily snapshots go to `Documents/Backups` (last 7) and exports to `Documents/Exports`;
both are visible in the Files app under *On My iPhone › HHT*.

## What leaves the device
| What | When | To |
|---|---|---|
| Nothing by default | — | — |
| One place coordinate at a time | only if **Settings › Look up addresses** is on (off by default) | Apple CLGeocoder |
| Map tile requests for the area on screen | whenever a map is shown | Apple Maps |
| Nothing about you; downloads a public CSV | only when you tap **Download airport list** | ourairports.com (GitHub Pages) |
| Whatever you choose to share | Export › Share | the destination you pick |

No account, no analytics SDK, no server, no network sync. The iOS device backup (iCloud or Finder) includes the app
container like any other app's data; turn off iCloud Backup for HHT if you don't want that.

## Control
- Stop collection any time (Settings › Record location). Raw history is kept until you erase it.
- Export everything (CSV / JSON / GeoJSON / SQLite) at any time.
- **Erase all data** permanently deletes the database contents (two confirmations). Backups/exports in Files are left alone
  so you can delete them yourself.
- Soft-deleted records remain in the database (for the audit trail) until Erase.

## Sharing safely
Raw and daily traces reveal home, work and routines. For anything public, share aggregates only: cities, airports,
flight routes, mode shares — never `raw_location_points`, `visits` or trip routes near home. A public "profile" export
is a possible future feature and must only include intentionally selected aggregates.
