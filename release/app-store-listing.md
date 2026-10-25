# App Store listing (en-US)

Character limits are App Store Connect's. Counts are for the text as written.

## App information

| Field | Value |
|---|---|
| Name (≤ 30) | **TripLibre: Travel Diary** (23) |
| Subtitle (≤ 30) | **Private trips, visits & modes** (29) |
| Bundle ID | `com.zyang91.hht` |
| SKU | `triplibre-ios` |
| Primary category | Travel |
| Secondary category | Navigation |
| Content rights | Does not contain, show or access third-party content (map tiles come from Apple's MapKit) |
| Age rating | 4+ (answer "None" / "No" to every content question; no user-generated content shared with others, no web access, no messaging) |
| Price | Free, no in-app purchases |
| Availability | All territories (no account or server, so no regional data residency concerns) |
| Copyright | © 2026 Zhanchao Yang |
| Privacy Policy URL | `https://hhtdiary.org/triplibre/docs/privacy.html` (or the new page from `privacy-policy.md`) |
| Support URL | `https://hhtdiary.org/triplibre/docs/` |
| Marketing URL | `https://hhtdiary.org/triplibre/` |
| Devices | iPhone only (`TARGETED_DEVICE_FAMILY = 1`), iOS 17+ |

## Promotional text (≤ 170)

> Your own travel diary, rebuilt every day from GPS: visits, trips and travel modes. No account, no server, no ads.
> Your data stays on your iPhone.

(145 characters. Promotional text can be changed without a new build.)

## Description (≤ 4000)

```text
TripLibre turns your iPhone into a private, automatic travel diary. It records where you go in the background and rebuilds each day into the places you stayed, the trips between them and how you travelled: walking, cycling, bus, subway, car, train or plane.

No account. No server. No ads or analytics. Everything is stored on your iPhone, and nothing leaves it unless you export it.

YOUR DAY, STEP BY STEP
• Today shows the day on a map and as a timeline: home, office, the coffee stop, the subway ride and the walk back.
• Uncertain trips come with quick mode buttons, so fixing one takes a tap.
• Tap any trip or stop to change the mode, the place, the purpose or the times, split or merge trips, or add a note.
• Your corrections are kept when the diary is rebuilt, and every change is logged.
• "Stamp this moment" records a quick stop in one tap, even one too short to detect.

PLACES THAT LEARN
• Name a place once (Home, Office, Gym) and TripLibre recognises it from then on.
• Group places by type, merge duplicates, and see how much time you spend where.

TIMELINE, MAP AND STATS
• Browse days by week and month, search and filter trips, and keep track of flights and life phases such as a semester or a move.
• See your activity space on a map, your mode share, distances, travel time, departure times and tours.
• Compare two periods side by side, like this term and last term.

WHAT YOUR TRAVEL COSTS
• Note fares, taxis, tickets and meals in a tap, then see spending by trip, mode, category and place.

HOME SCREEN WIDGETS
• Check that recording is healthy, see today or the last 7 days, or stamp a stop straight from the Home Screen.

BUILT FOR RESEARCH, OPEN SOURCE
• Export your whole diary as CSV, JSON, GeoJSON or SQLite, with a documented data dictionary and a Python loader.
• TripLibre works like a household travel survey for one person: trips, visits, modes and purposes in survey-ready tables.
• The code is open source under the Apache 2.0 license, so every privacy claim can be checked.

BATTERY-AWARE
• GPS runs only while you're moving. When you stop, TripLibre switches it off and lets iOS wake it when you leave.

PRIVACY
TripLibre has no server, so the developer never receives your data. Optional address lookup (off by default) sends one place coordinate at a time to Apple. Maps load tiles from Apple Maps. Read the full policy at hhtdiary.org.

Note: continued use of GPS running in the background can decrease battery life. TripLibre is a personal diary, not a navigation or safety tool; inferred trips and modes can be wrong, so check anything you rely on.
```

(About 2,600 characters.)

## Keywords (≤ 100, comma-separated, no spaces)

```text
trip,tracker,location,history,journal,timeline,commute,transit,mode,GPS,log,mobility,survey,offline
```

(99 characters. "Travel" and "diary" are already in the name, so they aren't repeated.)

## What's New (first release)

```text
TripLibre's first App Store release: an automatic, private travel diary with visits, trips and travel modes, one-tap corrections, stats, spending, widgets and full data export.
```

## Screenshot order and captions

Upload in this order from `screenshots/iphone-6.9/`. Captions are for an optional framed version (e.g. with a
caption band above the device); the raw screenshots can be uploaded as they are.

| # | File | Caption |
|---|---|---|
| 1 | `01-today.png` | Your day, rebuilt automatically |
| 2 | `02-diary.png` | Every stop and trip, step by step |
| 3 | `03-fix-a-trip.png` | Wrong mode? Fix it in one tap |
| 4 | `04-timeline.png` | Weeks, months, flights and life phases |
| 5 | `05-map.png` | See your activity space |
| 6 | `06-stats.png` | Mode share, distance and travel time |
| 7 | `07-spending.png` | What getting around really costs |
| 8 | `08-places.png` | Places that learn your names |
| 9 | `09-settings-privacy.png` | No account. No server. Your data stays on your iPhone |

## App Preview (optional)

Not prepared. If you want one: 15–30 s portrait recording at 886 × 1920 or 1080 × 1920 from the same simulator
(`xcrun simctl io <udid> recordVideo preview.mov`), showing Today → tap a trip → change mode → Stats.
