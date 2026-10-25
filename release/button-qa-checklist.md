# Button and flow check (issue #41)

Run once on a **Release build on a real iPhone** before each submission, after `make ui-test` passes. Tick each row,
and file an issue for anything broken. Destructive rows (Erase, Delete, Rebuild) go last, on a phone whose data is
backed up (Settings › Back up database now, then copy the backup off the phone).

## Status on 2026-10-24

- **Automated:** `make ui-test` (CoreFlowTests + AccessibilityAuditTests) on the iPhone 17 simulator, iOS 27:
  **19 tests, 0 failures, 1 skipped** (`AccessibilityAuditTests.testSpending`, skipped on purpose, see
  `docs/accessibility-testing.md`). Covered: every tab opens, day navigation labels, Map layers menu, Settings ›
  Create export › Share, trip and visit detail open/close, three cost flows, and audits on 9 screens.
- **Manual, while taking the screenshots** (iPhone 18 Pro Max simulator, de-identified real data): all five tabs, the
  day arrows, the gear (Settings sheet, Done), trip detail (open, Done), the Map period menu (7 days / 30 days), the
  Stats › Spending card, the Spending back button. All worked.
- **Seen but not confirmed as an app bug:** in the simulator, the first tap after scrolling or after a screen change
  was sometimes ignored, and a second tap worked (tab bar, gear, Map period menu, Spending card). It is probably the
  simulator input tool, but check it on the device: tap each tab-bar item, the gear and the Map ⌸ menu **right
  after scrolling** and note whether one tap is enough.

## Onboarding and permissions

- [ ] Fresh install: *Allow location & start* shows the When In Use prompt, then Motion & Fitness
- [ ] *Not now* closes onboarding and the app is usable without permission
- [ ] Settings › *Open iOS Settings to allow "Always"* opens TripLibre's page in iOS Settings
- [ ] Settings › *Record location* off/on stops and restarts collection (status row updates)

## Today

- [ ] *Previous day* / *Next day* arrows, and *Choose day* (calendar) picks a date
- [ ] Gear opens Settings; *Done* closes it
- [ ] *Stamp this moment* adds a stamp; *Undo* removes it; *Remove stamp* from the stamp row
- [ ] Quick mode buttons on an uncertain trip (*Confirm …*, mode chips) update the row
- [ ] Cost prompt cards: *Free / pass*, the usual-fare button, *Not now*-style dismissal
- [ ] "Spent this day" card opens Spending; *+ Cost* opens Add a cost
- [ ] Error banner *Try again* (only if a run fails), gap row *Update*

## Trip detail

- [ ] Mode grid: every mode button, *All modes…*, *Reset to automatic*
- [ ] Segments: open a segment, change its mode, *Remove this segment*
- [ ] *I changed mode on the way* (add segment), *I stopped somewhere (split trip)* → *Split*
- [ ] Purpose and place pickers, *Notes*, *Looks right*
- [ ] *This trip didn't happen* → *Remove and join the visits before/after*
- [ ] *Done* / *Cancel* / *Save* close without losing edits

## Visit detail

- [ ] *Wrong place? Choose or create…* → *Use* / *Create and use*
- [ ] *Arrived* / *Left* times → *Save times*; *Still here*
- [ ] *I left and came back / add a missing stop*, *I went somewhere specific*
- [ ] Activity and Notes, *Looks right*
- [ ] *This wasn't a stop* → *Remove and join the trips before/after*

## Costs

- [ ] Add a cost: amount field, category, *For* (trip/visit) stays selected, *When*, *Currency* / *More currencies*
- [ ] *Save*, *Cancel*; edit an existing cost; *Remove this cost*
- [ ] Spending: period pills, *+* (Add a cost), back button

## Timeline

- [ ] *Previous week* / *Next week*, tapping a weekday bar
- [ ] *Find trips…*: From, To, Origin or destination, Mode, Flight, *Weekends only*
- [ ] *Flights* → *Add flight* → *Save* / *Cancel*; open and edit a flight
- [ ] *Life phases* → *Add life phase* (Start, End, *Ongoing*, Kind) → *Save*
- [ ] Tapping a day opens that day

## Map

- [ ] Period menu: 7 days, 30 days, Year, All time, each life phase
- [ ] *Map layers*: Routes, Places, Flights, Activity space, *Route style*
- [ ] Tapping a place pin

## Stats

- [ ] Period pills, *Compare…* / *No comparison*
- [ ] Mode share *Basis* menu (by trips / distance / time)
- [ ] *How these are calculated*
- [ ] Spending card

## Places

- [ ] Search, *Clear search*; sort pills (Most time, Visits, Recent, A–Z, Named)
- [ ] Open a place: rename, type picker, *Radius*, *Favorite*, *Notes* → *Save changes* / *Discard*
- [ ] *Merge into another place…*
- [ ] *This isn't a real place*, *Delete place* / *Delete place and its visits*

## Settings

- [ ] *Accuracy* picker, *Units*
- [ ] *Look up addresses (Apple)* on → a new place gets an address; off again
- [ ] Export: *Range*, *Include raw GPS points*, *Create export* → *Share N files…* opens the share sheet
- [ ] Import: *Import past trips (CSV)*, *Import flights (CSV)*, *Import GPX track* (with a small test file)
- [ ] *Download airport list (OurAirports)* → *Download* / *Cancel*
- [ ] *Back up database now* (file appears in Files › TripLibre › Backups)
- [ ] *Rebuild last 7 days from raw data*, *Rebuild everything from raw data* (corrections survive)
- [ ] Experimental › *Diary agent* toggle shows/hides its tab; *Ask your diary*, *Send*, *Open this day in the diary*
- [ ] *Erase all data…* → both confirmations → *Erase* (last; on a backed-up phone)
- [ ] *Load demo data (simulator only)* is **absent** in the Release build

## Widgets and links

- [ ] Add each widget (Tracking, Today, Last 7 days, plain/timeline styles, Stamp)
- [ ] Widget taps open `hht://today`, `hht://stats`, `hht://settings`; Stamp widget stamps once per 30 s

## Accessibility spot checks (with the buttons above)

- [ ] Largest accessibility text size: tab bar is icons only and long-press shows each name
- [ ] VoiceOver: every button above is announced with a name
- [ ] Reduce Motion: tab switches don't bounce
