# Changelog

All released versions of TripLibre (called HHT before the rename in #77). Each GitHub release is archived on Zenodo under the concept DOI
[10.5281/zenodo.23307589](https://doi.org/10.5281/zenodo.23307589), which always resolves to the latest version.
Full notes for each release are on [GitHub Releases](https://github.com/zyang91/TripLibre/releases); this file is the
single summary, so release notes aren't kept anywhere else in the repository.

## 2.2.0 — 2026-11-12

- **Sample-day tutorial**: the welcome screen now starts with a language menu (the same eleven choices as Settings ›
  Language, applied at once) and offers **Try a demo**, a one-minute tutorial on a made-up day
  ("You visited Mingming's Home"), and **Skip for now**. On the app's real diary rows and day map you select a stop,
  name it, give it a place category and a trip purpose, correct a travel mode that was guessed as Car to Walk, and remove
  a stop that never happened (a wait at a crossing), which joins the two walks around it back into one trip. Tapping the highlighted row opens the app's real Visit, Place
  or Trip screen on the sample day (a throwaway in-memory database), and what you change there carries on in the
  tutorial; each
  step says which question the label answers (what you call it, what kind of place, why you went this time, how you got
  there) and where the same edit is in your diary. Two closing steps explain how tracking works and what it can miss
  (the "Always" permission, gaps when iOS stops the app, GPS drift, guessed modes) and recap the four labels. Every step
  has Back, Next and Skip, and Next fills in the example answer. The sample day lives in memory only (`SampleDay`): it
  is never written to the database, so it cannot reach the diary, stats, widgets, backups or exports. **Settings › Help**
  has **Replay tutorial** and **How tracking works**; a one-time tip above the diary rows opens the tutorial for people
  who skipped it or installed earlier; the Visit and Trip screens say in a line what the place name, category, purpose
  and mode each mean. Documented in Using the app, the UI guide, Architecture and Privacy (#114).

- **Confirm places on Today**: a stop whose place is still a guess among your saved places nearby (two floors of one
  building, a saved place next door, or a saved place passed over for an unsaved one) gets a card on Today, like the cost
  prompts. One tap on a nearby saved place confirms it; **None of these** leaves the stop unspecified; **Choose or
  create…** opens the full picker. A lone saved place nearby, and a home or work place recognised again and again, are
  never asked about. One card shows at a time, with **More to check** for the rest of the day. Closing a card does not
  confirm the guess; the Visit screen keeps full editing (#116).

- **New logo**: the app icon, README, website and docs use the new TripLibre logo, a white T over travel-mode
  symbols, hills and a winding road. The white border of the original artwork is removed; see `docs/branding.md`. Earlier
  logos are kept on a new Logo & brand page in the docs.

- **Schematic day map**: the Today map no longer draws GPS trails. Each trip is a smooth curve from where it started to
  where it ended, styled by mode: walking dotted, cycling short dashes, car solid, bus long dashes, rail solid, ferry
  dash-dot, flights a long-dashed wide arc and unknown modes grey dashes, in the same mode colours as the diary. A trip
  back the other way bows to the other side, repeat trips fan out, round trips are small loops and multimodal trips change
  colour part-way. Numbered markers give the order of the day; tap one to see that trip's mode, places and times, and
  **Details** for the trip itself, whose recorded route is still shown there. A note on the map says the lines join
  stops and are not the routes taken. Everything is drawn on the iPhone from the trips and places already inferred, with
  no routing service or downloads; raw GPS, distances, inference and exports are unchanged (`SchematicTrips` in
  `Geo/SchematicTrips.swift`, #109)
- **Cleaner day maps**: the day map no longer draws false straight-line jumps or triangles. Each trip is redrawn from
  its GPS fixes and the line is broken (leaving a gap) across a silence of more than 10 minutes, a subway or rail
  tunnel (no fix for 2 minutes while covering more than 300 m), a speed no ground travel reaches, fixes less accurate
  than 65 m, and single fixes that jump away and back. The thresholds were tuned on six weeks of real days; the usual
  3–5 minute sampling in cars and buses is not treated as a gap. Each gap is bridged by a thin dashed arc in that
  stretch's mode colour (for example blue across a subway tunnel), so every trip still visibly joins its origin and
  destination without pretending a straight route was measured. Flights and trips you entered by hand keep their
  stored line. This is display only: raw GPS, exports and inferred stops and trips are
  unchanged (`DisplayTrajectory` in `Geo/DisplayTrajectory.swift`, #100)
- **Saved places nearby**: when you review a stop, TripLibre lists the places you saved within 150 m (adjustable in
  Settings › Display), nearest first, so you can tell apart places at nearly the same spot, such as two floors of one
  building. Pick one, say **None of these**, add a **New place**, or **Skip for now**; nothing is chosen for you, and
  the search runs on the iPhone only. Places get an optional **Floor / unit** field shown in the list. Exports add
  `place_status` (`auto`, `confirmed` or `unspecified`) and `place_unit` to `visits.csv` and `unit` to `places.csv`,
  so the place you confirmed stays separate from the detected stop (schema v7, #95)
- **TripLibre is on the App Store**: [download it here](https://apps.apple.com/us/app/triplibre-your-trip-diary/id6826907636).
  The README, website and installation docs now link to it; building from source is still documented
- Developers: trip construction finds each trip's GPS fixes by binary search over the time-sorted cleaned points instead
  of scanning every point once per trip, so long rebuilds no longer cost O(N × T). Inferred visits and trips are
  unchanged. Developer API › Point order and trip windows documents the sorted-input contract and the internal
  `strictlyBetween` helper in `Inference/TimeWindow.swift` (#101, #102)
- **Multilingual: TripLibre now speaks 11 languages**: English, Chinese (Simplified and Traditional), French, German,
  Spanish, Portuguese, Russian, Arabic (right to left), Japanese and Korean. Settings › Language picks one or follows
  the iPhone; dates, units, money and plurals follow it, and the location and motion permission prompts are translated
  too. Exports and stored codes stay English, so analysis scripts keep working. The experimental diary agent and the
  Home Screen widgets are English for now (#90)
- Developers: translations live in `App/Localizable.xcstrings` and `App/InfoPlist.xcstrings`; text built in code
  goes through `L(…)`. `scripts/check_localizations.py` (in `make lint` and CI) checks every key is translated into
  every language with matching format specifiers (#90)
- Website: the homepage announces the new languages, and the docs cover them: Using the app › Languages, Developer
  API › Localization, Contributing › Translations, and notes in Architecture, Privacy and the Data dictionary (#90)
- Website: TripLibre now has its own site at triplibre.hhtdiary.org, published from `docs/`: overview at `/`, docs at
  `/docs/`, story at `/story/`. The HHT Diary organization pages (home, Products, Vision, Roadmap, About) moved to
  [hhtdiary/hhtdiary.github.io](https://github.com/hhtdiary/hhtdiary.github.io) and stay at hhtdiary.org, where the
  old `/triplibre/...` URLs redirect to the new site

- App Store: release kit in `release/` (listing text, privacy policy, App Privacy answers, review notes, accessibility
  labels and disclaimer, button checklist, 6.9" screenshots, a sample GPX day for App Review) (#41)
- Privacy manifests for the app and the widget extension: no tracking, no collected data, `UserDefaults` declared for
  the app's own settings (#41)
- Location and motion permission prompts say the diary is saved only on this iPhone, instead of claiming that nothing
  ever leaves it (#41)
- The app's version now follows the GitHub release: 2.1.0 (#41)

## 2.1.0 — 2026-10-24

- Brand: the TripLibre app icon, README, product website and docs now share the colourful infinity-route T logo.
  The original artwork, crop details and asset usage are documented in `docs/branding.md` (#85)
- Accessibility: a static `a11y-check` job on the SwiftUI source replaces the runtime audits in CI (#83). Its
  findings are fixed by hand (score 21.3 → 98.0): the diary agent scales with Dynamic Type, form fields show visible
  labels, decorative icons are hidden from VoiceOver, every row that opens on tap is announced as a button, and
  History's week arrows respect Reduce Motion (#67, #84)

## 2.0.0 — 2026-10-24

- Accessibility: text follows the Dynamic Type size in Settings, all the way to the largest accessibility sizes.
  Sticker rows, buttons and stat tiles grow with it and switch to a stacked layout when a row no longer fits; the tab
  bar shows icons only at accessibility sizes (long-press a tab for its name). Section headers, footers and secondary
  values use a darker grey that meets 4.5:1 on the butter background, and Done/Save buttons are ink. Widgets keep their
  fixed sizes. The `make ui-test` audits now fail on Dynamic Type and contrast issues too (#67)
- Renamed the app to TripLibre; HHT Diary is now the parent organization. README, docs, website, `CITATION.cff` and
  Zenodo metadata use the new name and the `zyang91/TripLibre` repository. The app shows as TripLibre on the Home
  Screen, in Settings, in the Files app and on the widgets; the bundle ID and code names stay HHT, so installing
  over an older build keeps its data (#77)
- Website: hhtdiary.org now separates the organization from the product. HHT Diary keeps the home page, Products,
  Vision, Roadmap and a new About page, with its own mark and navy palette; TripLibre has its own overview at
  `/triplibre/`, docs at `/triplibre/docs/` and story at `/triplibre/story/`, in the app's coral and sun colours with
  a "by HHT Diary" line. The old paths (`/installation.html` and the other docs pages, `/docs/`, `/products/ios/`,
  `/backup/`) are gone, with no redirects (#77)
- Website: HHT Diary has a new logo, a house whose path winds out into a "D" past mountains and a plane. The mark
  (`docs/assets/hhtdiary-mark.png`) is the header logo and favicon on the organization pages, and the full
  "HHT Diary · Household Travel Diary" lockup is at `docs/assets/hhtdiary-logo.png`
- Costs: note what a trip or a stop cost. Today asks about the latest transit, taxi or flight trip ("Free" or the usual
  fare in one tap), a "Spent today" card adds costs to any day, and a Spending page (from Today or Stats) breaks totals
  down by travel vs destinations, category, mode (per trip, per km) and place. Exported as `expenses.csv` (#17)
- Costs: Today asks about every unpaid transit, taxi or flight trip and every stop at a paid place (restaurants, shops,
  hotels…), one card each, instead of only the latest trip. Fixed: the Add-a-cost sheet closing by itself after you
  picked a category, and the trip or visit picked under "For" being reset (#75)
- Website: organization homepage for HHT Diary, top-level Vision, Roadmap and Products pages, `/docs/` landing;
  old `vision.html` and `roadmap.html` redirect (#70)
- Docs: Vision, Roadmap, Research uses & limitations, Validation and Data dictionary pages; landing page, privacy
  (export contents, erase, re-identification risk) and contributing updates; citation metadata aligned (#45)
- Home Screen widgets: Tracking, Today and Last 7 days, read-only (#47, #60)
- Stamp widget: one tap opens HHT and stamps through the same path as Today's button; repeat taps within 30 s keep one stamp (#47)
- XCUITest flows and accessibility audits for the iOS app (#64, #68)
- Linting for docs, Markdown, Python and Swift; axe-core accessibility check for the docs site (#61, #62, #66)
- Dependency security fixes (#65)

## 1.3.0 — 2026-10-19

- Inference calibration harness and two calibration rounds: stay splitting, departures and travel modes (#46, #52)
- One-tap self-reported stamps for short stops (#32, #53)
- Place types: 13 new categories, grouped searchable picker, custom types (#56, #59)
- Collector: don't switch to stationary on a moving vehicle (#51)
- Docs site becomes the homepage; project story moves to `/backup/` (#57, #58); Vercel previews for docs PRs (#50)
- README: Zenodo DOI badge and citation section (#44)

## 1.2.1 — 2026-10-12

- Sync `.zenodo.json` with `CITATION.cff` (#43)

## 1.2.0 — 2026-10-12

First release archived on Zenodo.

- Trips: keep and edit multimodal segments on manually edited trips (#35, #40)
- `CITATION.cff` and `.zenodo.json` for the Zenodo DOI and GitHub's "Cite this repository"
- App version comes from `MARKETING_VERSION` in `project.yml` instead of a hard-coded `1.0`

## 1.1.2 — 2026-10-11

- Map: clean up trajectories and GPS drift for display (#38, #39)

## 1.1.1 — 2026-10-08

- Places: delete places that aren't real (#36)
- Flights: stop duplicating flights on every inference run (#27, #37)
- Docs: sticker-style diagrams and Meet the developer page (#31)

## 1.1.0 — 2026-10-06

- Standalone multi-page documentation site, UI guide and app-styled docs home (#29, #30)

## 1.0.0 — 2026-10-04

- Cartoon sticker-style UI redesign (#28)
- Logo, badges and banners in the README (#25)
- CI hardening for CodeQL; Dependabot (#21, #26)

## 0.3.0 — 2026-10-02

- Pin where you stopped on a map when splitting a trip (#14)
- Show when the diary is still being built (#15)

## 0.2.0 — 2026-10-02

- A deleted open visit no longer suppresses every later stay (#9)
- Stats mode-share chart laid out one row per mode (#10)
- Split-visit and split-trip sheets no longer crash on open (#12)

## 0.1.2 — 2026-09-29

- End open pinned visits when you show up elsewhere; better gap departures (#3)
