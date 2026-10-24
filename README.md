<p align="center">
  <img src="docs/assets/triplibre-logo.png" width="112" height="112" alt="TripLibre logo: a route joining four stops on a dark map grid">
</p>

<h1 align="center">TripLibre — personal travel diary</h1>

<p align="center">
  <em>From a travel survey of one to travel surveys within reach.</em><br>
  A free, open-source, local-first iOS travel diary that rebuilds each day into visits, trips and modes.
</p>

<p align="center">
  <a href="https://github.com/zyang91/TripLibre/actions/workflows/ci.yml"><img src="https://github.com/zyang91/TripLibre/actions/workflows/ci.yml/badge.svg?branch=main" alt="CI"></a>
  <img src="https://img.shields.io/badge/iOS-17%2B-0f1f3a?logo=apple&logoColor=white" alt="iOS 17+">
  <img src="https://img.shields.io/badge/Swift-SwiftUI-F05138?logo=swift&logoColor=white" alt="Swift / SwiftUI">
  <img src="https://img.shields.io/badge/data-local--first-5ac8a0" alt="Local-first data">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache%202.0-blue" alt="Apache 2.0 license"></a>
  <a href="https://doi.org/10.5281/zenodo.23307589"><img src="https://zenodo.org/badge/DOI/10.5281/zenodo.23307589.svg" alt="DOI 10.5281/zenodo.23307589"></a>
  <a href="https://hhtdiary.org/triplibre/docs/"><img src="https://img.shields.io/badge/docs-hhtdiary.org-f4a93b" alt="Documentation"></a>
</p>

<p align="center">
  <img src="docs/assets/hht-daily-journey.png" width="820" alt="A miniature Philadelphia unfolds from a phone, with a looping route connecting home, campus, coffee, cycling and the subway.">
</p>

<p align="center">
  <a href="#install-on-your-iphone-personal-use-no-app-store">Install</a> ·
  <a href="#daily-use">Daily use</a> ·
  <a href="#research-workflow">Research workflow</a> ·
  <a href="#development">Development</a> ·
  <a href="https://hhtdiary.org/triplibre/docs/">Docs</a> ·
  <a href="https://hhtdiary.org/roadmap/">Roadmap</a> ·
  <a href="https://hhtdiary.org/triplibre/story/">Project story</a>
</p>

---

A private, local-first iOS app that works like a continuous **household travel survey for one person**.
It records location in the background, rebuilds each day into **visits, trips, modes and trip chains**, lets you fix
mistakes in one or two taps, and exports a clean, survey-shaped dataset (CSV / JSON / GeoJSON / SQLite).

TripLibre (formerly HHT) is the first product of [HHT Diary](https://hhtdiary.org/) ([GitHub](https://github.com/hhtdiary)),
the organization led by Zhanchao Yang that builds open, local-first mobility tools. Code names still use HHT (`HHTCore`, `HHT.xcodeproj`,
`analysis/hht.py`, bundle ID `com.zyang91.hht`), so updating an existing install keeps its data (#77).
No account, no server, no analytics: the data stays on the phone unless you export it.

TripLibre began as one transportation researcher's travel survey of one, built with AI assistance (Claude). The longer-term
aim is open, affordable travel data collection for researchers, students and small agencies. That is a plan, not a
feature: see the [Vision](https://hhtdiary.org/vision/) and [Roadmap](https://hhtdiary.org/roadmap/).
The original product brief is in [`design/`](design/personal_travel_tracker_claude_brief.md).

## What it does today

| Capability | Status |
|---|---|
| Background recording (motion-aware GPS, battery-saving stationary mode) | ✅ Available |
| Visits, trips, mode segments and named places, rebuilt deterministically | ✅ Available |
| One- or two-tap corrections, locked against rebuilds, with an audit log | ✅ Available |
| Self-reported stamps for very short stops | ✅ Available |
| Stats (mode share, radius of gyration, tours…), flights, life phases, widgets | ✅ Available |
| Export to CSV, JSON, GeoJSON, SQLite + Python loader | ✅ Available |
| App Store release (target around November 2026) | 🚧 In progress |
| Selective export (chosen dates, trips, detail level) | 📋 Planned |
| Prompted recall and study configuration for research | 📋 Planned |
| Formal accuracy benchmark | 📋 Planned |
| Research edition beside the personal app, sharing the same engine | 🔭 Exploratory |
| Android, multilingual, self-hosted (incl. for cities with limited capacity) | 🔭 Exploratory |

Screenshots of every screen are in the [UI guide](https://hhtdiary.org/triplibre/docs/ui-guide.html).

```text
App/                    SwiftUI iOS app (Today · Timeline · Map · Stats · Places · Settings)
  Location/             background collector, CoreMotion sync, optional geocoder
  Screens/              UI
Widgets/                Home Screen widgets (WidgetKit extension)
Packages/HHTCore/       platform-independent core (Swift package, no dependencies)
  Database/             SQLite wrapper, schema + migrations, repository
  Inference/            stay detection, self-reported stamps, trip building, mode classification, reprocessing
  Editing/              every correction (mode, place, times, split/merge/delete) + audit log
  Analytics/            HHTS metrics, radius of gyration, entropy, tours…
  Export/               CSV/JSON/GeoJSON/SQLite export; CSV/GPX/airport import
  Widget/               the small summary the widgets read (no coordinates)
  Tests/                112 tests incl. the brief's 14 synthetic scenarios
analysis/               Python loader + example analysis (pandas)
docs/                   website (static HTML, published at hhtdiary.org): HHT Diary pages at the top,
                        TripLibre overview + docs in docs/triplibre/, markdown specs
project.yml             XcodeGen spec (HHT.xcodeproj is generated from it)
```

## Install on your iPhone (personal use, no App Store)

TripLibre is not on the App Store yet; you build it from source. Full guide: [Installation](https://hhtdiary.org/triplibre/docs/installation.html).

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
  **Stamp this moment** records, in one tap, that you stopped somewhere around here, around now (coffee, a quick pickup,
  a transfer): stops too short for the ~5-minute rule still make it into the diary, marked as self-reported.
  Only a coarse location is kept ([how stamps are used](docs/inference.md#8-self-reported-stamps)).
- **Places**: name recurring places once (Home, Penn, 30th St…) and they're recognised from then on. Merge duplicates.
- **Timeline**: days by month, trip search/filters, flights, life phases.
- **Map / Stats**: activity space, radius of gyration, mode share, departure times, tours, weekday/weekend, and
  period-vs-period comparisons (e.g. two semesters).
- **Home Screen widgets**: Tracking (is recording healthy?), Today, and Last 7 days, plus plain and timeline styles, and
  a one-tap Stamp that opens the app's own stamp. They show what the app last worked out and never collect location themselves ([UI guide](docs/triplibre/docs/ui-guide.html#widgets)).
- **Settings** (gear on Today): collection status, export/import, rebuild from raw data, backups, privacy.

## Research workflow

Settings › *Create export* writes a folder (also in Files › On My iPhone › TripLibre › Exports) and offers a share sheet.

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
`audit_log`, a ready-made labelled set for improving mode detection later. Every file and column is described in the
[Data dictionary](https://hhtdiary.org/triplibre/docs/data-dictionary.html).

> [!IMPORTANT]
> An export always includes `travel.sqlite`, the **complete** database with every GPS fix, even when you pick
> *Last 30 days* or turn off *Include raw GPS points*. Delete it before sharing a limited export.
> See [Privacy](https://hhtdiary.org/triplibre/docs/privacy.html#what-an-export-contains).

### Research use and limitations

TripLibre data is good for longitudinal N-of-1 studies, trip and mode inference research, human-in-the-loop correction,
pilots and teaching. It is **not** a representative household travel survey: participants self-select, need an
iPhone, and may share only some days; GPS drift, signal loss and collection gaps leave holes; and trajectories alone
don't tell you purpose, companions or household context. Accuracy has been measured only on one person's 17 days so
far. Before using it in a study, read [Research uses & limitations](https://hhtdiary.org/triplibre/docs/research.html) and
[Validation](https://hhtdiary.org/triplibre/docs/validation.html). Research with other people's location data usually needs
ethics/IRB approval.

## Development

```bash
make help          # list everything
make test          # core test suite (112 tests incl. the brief's 14 scenarios)
make sim           # build + run in the simulator with demo data
make phone         # build, sign and install on the cable-connected iPhone (renews the 7-day signature)
make lint          # docs JS/CSS/HTML (incl. accessibility rules), Markdown, Python, Swift; needs node, ruff, swiftlint, swiftformat
make swift-lint    # just SwiftLint (new violations vs. .swiftlint-baseline.json) + SwiftFormat check
make a11y          # axe-core WCAG 2.1 AA check of the rendered docs site, light + dark theme
make ui-test       # XCUITest flows + accessibility audits in the simulator (also in CI)
make ci            # what GitHub Actions runs (minus ui-test): lint + tests + app build + export→Python contract check
```

CI (`.github/workflows/ci.yml`) runs on every push/PR on a macOS runner: Swift tests, an end-to-end check that the
Python loader reads the app's real export (CSV and SQLite agree), a simulator build, a device build, a check that
`HHT.xcodeproj` matches `project.yml`, and the XCUITest flows and accessibility audits (`make ui-test`) in the simulator.
An Ubuntu job runs the linters, including SwiftLint (`.swiftlint.yml`: correctness and VoiceOver rules only; existing
violations are recorded in `.swiftlint-baseline.json`, so only new ones fail) and SwiftFormat in check-only mode
(`.swiftformat`: whitespace hygiene only). Install locally with `brew install swiftlint swiftformat`.

Why no Docker: iOS apps can only be built and signed on macOS with Xcode, which doesn't run in Linux containers.
The reproducible "package" here is `project.yml` (XcodeGen) + `Makefile` + CI on macOS runners.

The simulator build has a *Load demo data* button in Settings, and launching with `-hhtDemo YES` seeds three
synthetic Philadelphia days. Neither exists in device builds.

Design priorities follow the brief: data integrity → collection reliability → correct reconstruction → fast correction →
exportability → analytics → polish. Raw observations are never modified; inference can be re-run at any time without
touching anything you corrected.

## Contributing

Bug reports, fixes and docs are welcome: see [CONTRIBUTING.md](CONTRIBUTING.md) and the
[Code of Conduct](CODE_OF_CONDUCT.md). Please never attach exports or GPS logs to public issues; the contributing guide
explains how to describe an inference problem without them. Security issues go through [SECURITY.md](SECURITY.md).
Release history: [CHANGELOG.md](CHANGELOG.md).

## License

[Apache License 2.0](LICENSE). Free to use, modify and redistribute, including in research and commercial projects,
under the license's terms.

## Citation

If you use TripLibre in research, please cite the archived software ([`CITATION.cff`](CITATION.cff); GitHub's *Cite this repository* button gives APA and BibTeX).
The DOI below is Zenodo's concept DOI: it always resolves to the latest release, and each version also has its own DOI on Zenodo.

> Yang, Z. *TripLibre: An Open-Source, Privacy-First Travel Diary for Mobility Research.* Zenodo. <https://doi.org/10.5281/zenodo.23307589>

---

<p align="center">
  <img src="docs/assets/qingdao-footer.png" width="720" alt="Line drawing of the Qingdao waterfront: Zhanqiao Pier and its pavilion, the twin-spired cathedral, a lighthouse and a sailboat.">
</p>
