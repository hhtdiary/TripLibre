# Changelog

All released versions of TripLibre (called HHT before the rename in #77). Each GitHub release is archived on Zenodo under the concept DOI
[10.5281/zenodo.23307589](https://doi.org/10.5281/zenodo.23307589), which always resolves to the latest version.
Full notes for each release are on [GitHub Releases](https://github.com/zyang91/TripLibre/releases); this file is the
single summary, so release notes aren't kept anywhere else in the repository.

## Unreleased

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
