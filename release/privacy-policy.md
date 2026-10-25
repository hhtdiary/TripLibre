# TripLibre Privacy Policy

*Effective 2 November 2026 · TripLibre for iOS, by HHT Diary (Zhanchao Yang)*

TripLibre is a travel diary that runs entirely on your iPhone. It has no account, no server, no analytics, no
advertising and no sync. **The developer never receives your data.**

## What TripLibre stores, and where

All of it stays in the app's private storage on your iPhone:

- **Location** you allow it to record: GPS fixes while you're moving, and the visits, trips and travel modes worked
  out from them.
- **Motion activity** from iOS (walking, running, cycling, in a vehicle), if you allow Motion & Fitness, to help tell
  modes apart.
- **What you enter**: place names and types, corrections, notes, costs, flights, life phases and one-tap stamps (a
  stamp keeps only a coarse location, rounded to about 110 m).
- **An audit log** of your corrections, so a rebuilt diary keeps your changes.
- **A daily backup** of the database (the last 7) and any exports you create, in *Files › On My iPhone › TripLibre*.
- **A small widget summary** (counts, times and names of places you named), shared only with TripLibre's own
  widgets. It has no coordinates, routes or addresses.

## When TripLibre uses the network

Recording, the diary, corrections, stats, widgets, backups and exports work offline. TripLibre goes online only
in these cases:

| What | When | Sent to |
|---|---|---|
| One place's coordinates, to look up its address | Only if you turn on *Settings › Look up addresses* (off by default) | Apple (CLGeocoder) |
| Map tiles for the area on screen | Whenever a map is visible | Apple Maps |
| Nothing about you; a public airport list is downloaded | Only when you tap *Download airport list* | OurAirports data on GitHub Pages |
| Whatever you choose to share | When you use *Export › Share* | The app or person you pick |

Apple's handling of geocoding and map requests is covered by Apple's privacy policy.

## What TripLibre does not do

- No sign-in, no account and no developer server.
- No analytics, crash-reporting or advertising SDKs, and no tracking across apps or websites.
- No selling or sharing of data with anyone. The developer has no copy to share.

## Exports

An export is a folder of CSV, JSON, GeoJSON and SQLite files that you create and share yourself. **Every export
includes `travel.sqlite`, a complete copy of the database with every GPS fix**, whatever range you pick. Delete that
file before sharing a limited export. Location history can identify you even without your name, so think about who
you share it with.

## Your choices

- **Stop recording** any time in *Settings › Record location*, or revoke location or motion access in iOS Settings.
- **Edit or delete** any visit, trip or place.
- **Erase all data** in Settings (two confirmations) removes every record from the database. Backups and exports in
  Files are left for you to delete.
- **Delete the app** to remove everything in its storage at once.

Your iPhone's own iCloud or computer backup includes TripLibre's storage, like any app's. Turn off iCloud Backup for
TripLibre in iOS Settings if you don't want that.

## Children

TripLibre is not directed at children and collects nothing for the developer, from children or anyone else.

## Research use

TripLibre is also used by researchers who study travel behaviour. Using the app doesn't enrol you in any study. If you
choose to give an export to a study, that study's own consent and privacy terms apply, not this policy.

## Changes

If anything about data handling changes, this page will be updated before the release that changes it, with a new
effective date. The source code is public at <https://github.com/zyang91/TripLibre>, so every statement here can be
checked.

## Contact

Questions or privacy concerns: open an issue at <https://github.com/zyang91/TripLibre/issues> (don't attach exports
or GPS logs), or email **[contact address — fill in before publishing]**.
