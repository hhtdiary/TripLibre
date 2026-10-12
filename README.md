<p align="center">
  <img src="docs/assets/hht-logo.png" width="112" height="112" alt="HHT logo: a route joining four stops on a dark map grid">
</p>

<h1 align="center">HHT — personal travel diary</h1>

<p align="center">
  <em>A household travel survey for one person, rebuilt from your phone's location every day.</em>
</p>

<p align="center">
  <a href="https://github.com/zyang91/HHT-app/actions/workflows/ci.yml"><img src="https://github.com/zyang91/HHT-app/actions/workflows/ci.yml/badge.svg?branch=main" alt="CI"></a>
  <img src="https://img.shields.io/badge/iOS-17%2B-0f1f3a?logo=apple&logoColor=white" alt="iOS 17+">
  <img src="https://img.shields.io/badge/Swift-SwiftUI-F05138?logo=swift&logoColor=white" alt="Swift / SwiftUI">
  <img src="https://img.shields.io/badge/data-local--first-5ac8a0" alt="Local-first data">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache%202.0-blue" alt="Apache 2.0 license"></a>
  <a href="https://doi.org/10.5281/zenodo.23307589"><img src="https://zenodo.org/badge/DOI/10.5281/zenodo.23307589.svg" alt="DOI 10.5281/zenodo.23307589"></a>
  <a href="https://zhanchaoyang.com/HHT-app/docs/"><img src="https://img.shields.io/badge/docs-website-f4a93b" alt="Documentation"></a>
</p>

<p align="center">
  <img src="docs/assets/hht-daily-journey.png" width="820" alt="A miniature Philadelphia unfolds from a phone, with a looping route connecting home, campus, coffee, cycling and the subway.">
</p>

<p align="center">
  <a href="#install-on-your-iphone-personal-use-no-app-store">Install</a> ·
  <a href="#daily-use">Daily use</a> ·
  <a href="#research-workflow">Research workflow</a> ·
  <a href="#development">Development</a> ·
  <a href="https://zhanchaoyang.com/HHT-app/docs/">Docs</a> ·
  <a href="https://zhanchaoyang.com/HHT-app/">Project story</a>
</p>

---

A private, local-first iOS app that works like a continuous **household travel survey for one person**.
It records location in the background, rebuilds each day into **visits, trips, modes and trip chains**, lets you fix
mistakes in one or two taps, and exports a clean, research-grade dataset (CSV / JSON / GeoJSON / SQLite).
The product brief is in [`design/`](design/personal_travel_tracker_claude_brief.md).

```
App/                    SwiftUI iOS app (Today · Timeline · Map · Stats · Places · Settings)
  Location/             background collector, CoreMotion sync, optional geocoder
  Screens/              UI
Packages/HHTCore/       platform-independent core (Swift package, no dependencies)
  Database/             SQLite wrapper, schema + migrations, repository
  Inference/            stay detection, trip building, mode classification, reprocessing
  Editing/              every correction (mode, place, times, split/merge/delete) + audit log
  Analytics/            HHTS metrics, radius of gyration, entropy, tours…
  Export/               CSV/JSON/GeoJSON/SQLite export; CSV/GPX/airport import
  Tests/                58 tests incl. the brief's 14 synthetic scenarios
analysis/               Python loader + example analysis (pandas)
docs/                   project page (index.html), documentation site (docs/), markdown specs
project.yml             XcodeGen spec (HHT.xcodeproj is generated from it)
```

## Install on your iPhone (personal use, no App Store)

**Reinstalling / renewing every 7 days → see [INSTALL.md](INSTALL.md)** (`make phone`).

1. Open `HHT.xcodeproj` in Xcode.
2. Select the **HHT** target › *Signing & Capabilities* › Team: your Apple ID (add it in Xcode › Settings › Accounts).
   If the bundle ID `com.zyang91.hht` is taken, change it to anything unique.
3. Connect the iPhone (enable *Developer Mode* in Settings › Privacy & Security when asked), pick it as the run destination, press ▶.
4. First launch: on the iPhone, trust the developer profile (Settings › General › VPN & Device Management).
5. In the app: *Allow location & start* → allow *While Using*, then later **Change to Always Allow**; allow Motion & Fitness.

With a free Apple ID the install expires after **7 days**. Re-run from Xcode to renew; your data is kept because the
database lives in the app container. A paid developer account makes it last a year.

After changing `project.yml`, regenerate with `xcodegen generate` (`brew install xcodegen`).

## Daily use
- **Today**: the reconstructed day on a map plus the chronological diary. Uncertain trips show quick mode buttons;
  tap any trip or visit to change mode/segments, place, purpose, times, split, merge/delete or add notes.
- **Places**: name recurring places once (Home, Penn, 30th St…) and they're recognised from then on. Merge duplicates.
- **Timeline**: days by month, trip search/filters, flights, life phases.
- **Map / Stats**: activity space, radius of gyration, mode share, departure times, tours, weekday/weekend, and
  period-vs-period comparisons (e.g. two semesters).
- **Settings** (gear on Today): collection status, export/import, rebuild from raw data, backups, privacy.

## Research workflow
Settings › *Create export* writes a folder (also in Files › On My iPhone › HHT › Exports) and offers a share sheet.

```bash
cd analysis && python3 -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt
```

```bash
python explore.py ~/Downloads/hht-export-20260927-120000
```

```python
from hht import load, summary, mode_share
d = load("~/Downloads/hht-export-…")        # or the travel.sqlite snapshot
d.trips          # one row per trip: person_day_id, trip_seq, OD, times, mode, purpose, distance…
summary(d.phase("Fall 2026"))
```
Or query `travel.sqlite` directly (`v_trips`, `v_visits` views) from R/DBI, DuckDB or QGIS. Every user correction is in
`audit_log`, a ready-made labelled set for improving mode detection later.

## Development
```bash
make help          # list everything
make test          # core test suite (58 tests incl. the brief's 14 scenarios)
make sim           # build + run in the simulator with demo data
make phone         # build, sign and install on the cable-connected iPhone (renews the 7-day signature)
make ci            # what GitHub Actions runs: tests + app build + export→Python contract check
```
CI (`.github/workflows/ci.yml`) runs on every push/PR on a macOS runner: Swift tests, an end-to-end check that the
Python loader reads the app's real export (CSV and SQLite agree), a simulator build, a device build, and a check that
`HHT.xcodeproj` matches `project.yml`.

Why no Docker: iOS apps can only be built and signed on macOS with Xcode, which doesn't run in Linux containers.
The reproducible "package" here is `project.yml` (XcodeGen) + `Makefile` + CI on macOS runners.

The simulator build has a *Load demo data* button in Settings, and launching with `-hhtDemo YES` seeds three
synthetic Philadelphia days. Neither exists in device builds.

Design priorities follow the brief: data integrity → collection reliability → correct reconstruction → fast correction →
exportability → analytics → polish. Raw observations are never modified; inference can be re-run at any time without
touching anything you corrected.

## Citation
If you use HHT in research, please cite the archived software ([`CITATION.cff`](CITATION.cff); GitHub's *Cite this repository* button gives APA and BibTeX):

> Yang, Z. *HHT: An Open-Source, Privacy-First Travel Diary for Mobility Research.* Zenodo. https://doi.org/10.5281/zenodo.23307589

---

<p align="center">
  <img src="docs/assets/qingdao-footer.png" width="720" alt="Line drawing of the Qingdao waterfront: Zhanqiao Pier and its pavilion, the twin-spired cathedral, a lighthouse and a sailboat.">
</p>
