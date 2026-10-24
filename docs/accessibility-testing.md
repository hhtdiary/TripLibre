# Accessibility testing (iOS app)

The docs site has its own automated check (`make a11y`, axe-core). This page covers the native SwiftUI app
(issue #64): automated XCUITest flows and audits, plus the manual checks they can't replace.

## Automated: `make ui-test`

```sh
make ui-test                                    # all UI tests, iPhone 17 simulator
make ui-test SIM_NAME="iPhone 17e"              # another simulator
make ui-test ONLY=HHTUITests/CoreFlowTests      # one class (or HHTUITests/Class/testMethod)
```

Needs Xcode 15+ (audits need iOS 17+ simulators) and xcodegen. The tests launch the app with `-hhtUITest YES`,
which (simulator builds only) opens a fresh throwaway database, seeds three days of demo travel, skips onboarding and
never starts location collection, so runs are reproducible and never touch your real diary.

| Suite | What it covers |
| --- | --- |
| `CoreFlowTests` | Every tab opens and is announced as selected; trip and visit details open from the diary and close; the day navigation buttons have labels; Map › layers menu; Settings › Create export finishes and offers Share. |
| `AccessibilityAuditTests` | `performAccessibilityAudit(for: .all)` on Today, a day with trips, Trip detail, Visit detail, Timeline, Map, Stats, Places and Settings. |

When an audit fails, the test log has one `[a11y] <screen>: <audit type>: <description> — <element>` line per issue.
An audit with unexpected findings runs a second time and fails only on the findings that show up in both passes: on
a slow simulator (CI) the contrast check flags different elements from run to run on the same screen. An audit that
times out is also run again once.
Xcode's test report also attaches a screenshot with the element highlighted.

### Known exceptions

Accepted findings live in `KnownIssue` in `UITests/AccessibilityAuditTests.swift`. Each one matches the audit type
*and* the element, so a new problem of the same kind on another element still fails. Keep this list in sync:

| Exception | Screens | Why it's accepted |
| --- | --- | --- |
| `mapKitAttribution` | Map, Today, Trip/Visit detail | Apple Maps' logo and "Legal" link are drawn by MapKit; their size and contrast aren't ours to change. |
| `mapKitMarkers` | Trip detail, Visit detail | MapKit's `Marker` pins are under 44 pt and not exposed as elements; they're informational and the same places are named right below the map. |
| `textClippedFalsePositive` | Today, Trip/Visit detail | "Stamp this moment", the origin/destination labels under the trip map and "Name this place" are reported as clipped but render in full (screenshot-checked on iPhone 17). Matched by exact text. |
| `systemBarButton` | Settings, Trip/Visit detail | The system "Done" button in a sheet's navigation bar (Liquid Glass) stops growing at the system's bar-button size (long-press shows the large content viewer) and the contrast check measures the glass behind it. Its title is ink. Matched by being a button inside the navigation bar. |
| `underNavigationBar` | Spending | Contrast findings on elements whose top edge is still under the navigation bar (the period pills right under Spending's inline title): iOS 26 blurs and fades content there (scroll edge effect) and the audit samples that strip. The pills are ink on white or white on ink; the same pills under Stats' large title pass. |
| `systemDrawnText` | Map, Today, Trip/Visit detail; sheets | Text the system draws outside our view hierarchy, reported with no element: MapKit's street and place labels, and the dimmed screen behind a sheet. |
| `behindKeyboard` | Add a cost | Rows under the on-screen keyboard (the sheet opens with the amount field focused), or within 24 pt above it, where the glass keyboard's edge blurs them: the audit measures the keys, and reads their captions as text with no element. |
| `behindTabBar` | Today and other tab screens | Elements partly under the floating tab bar: the audit measures the bar's pixels and the smaller visible area. Matched by the element's frame reaching under the bar; text the bar cuts off is reported as clipped with no element. |
| `fullWidthRowContrast` | Today, Settings, sheets | Contrast findings on text whose element is a whole `List`/`Form` row: section headers on the dot grid, and Pip's speech bubble on Today (a List row reports it with the mascot's frame). The audit samples the row and takes the dots (1.3:1 on butter) or the mascot for the text colour, so these findings come and go between runs. The text is `Toon.muted` on butter (6.6:1; 5.2:1 even on a dot) or `Toon.ink` on white. Smaller text elements are still checked. |
| `listRowPushedOffScreen` | Today, Timeline, Settings, Trip/Visit detail | Dynamic Type / clipping findings on `List` text and button rows below the top third of the screen: as the audit enlarges the text they're pushed off screen and List removes them, so they can't be measured. The same rows pass when they sit higher up; these screens are checked at the largest size by hand (below). |

### Dynamic Type and contrast

Both audits fail the tests (issue #67; there are no report-only audit types left, see `reportOnly`). What keeps them
passing:

- **Type** — app text uses `.font(.toon(size, weight))`, which scales like the nearest text style (13 pt like
  `.footnote`, 34 pt like `.largeTitle`). The widgets use `Font.toonFixed`, since their canvas doesn't grow. Use
  `toonLineLimit(_:)` rather than `lineLimit` + `minimumScaleFactor`: it lifts the limit at accessibility sizes.
- **Layout** — rows that put text beside chips or buttons use `ToonRowStack`, which becomes a column at accessibility
  sizes; two-up stat tiles use `StickerGrid` (one column there); filter and period pills use `ToonFlow`, which wraps.
  Give anything with text a `minHeight`, never a fixed `height`. The tab bar shows icons only at accessibility sizes.
- **Colour** — form section headers and footers use `toonSectionText()` and `LabeledContent` values `Toon.muted`
  (~7:1 on butter and white); the system grey is under 4.5:1 there. Toolbar Done/Save buttons use `confirmTint()`.
  Keep a sticker's `Text` as its own element (don't hang the card's padding and outline on the `Text` itself), or the
  contrast check samples the outline.

### CI

The *UI tests + accessibility audits* job in `.github/workflows/ci.yml` runs the full `make ui-test` on every pull
request and push to `main`, on the iPhone 17 simulator (or the newest iPhone the runner's Xcode has). When it fails,
download the `ui-tests-xcresult` artifact from the run and open it in Xcode to see the failing step, its screenshot
and the audit findings. Running `make ui-test` locally before pushing UI changes is still quicker than waiting on CI.

## Manual checklist

Automated audits can't judge whether a label *makes sense*, whether reading order is logical, or whether a flow is
usable without sight. Before a release, go through these on a device (or the simulator with Accessibility Inspector:
Xcode › Open Developer Tool › Accessibility Inspector).

### VoiceOver (Settings › Accessibility › VoiceOver)

- [ ] Floating tab bar: each tab reads its name; the current one reads "Selected".
- [ ] Today: Settings, Previous day, Choose day, Next day are named; Next day is dimmed on today.
- [ ] "Stamp this moment" reads its hint; the Undo button after stamping is reachable.
- [ ] A visit row reads place, times, duration and purpose as one item, then "Button"; double-tap opens it.
- [ ] A trip row reads modes, times, duration and distance as one item; double-tap opens it. On a "Did I get that
      right?" trip, swipe up/down offers the quick mode picks and "Confirm …" as actions.
- [ ] Trip detail: mode picker, segment rows ("Set by you" / "Detected automatically"), Confirm, Split, Delete and
      Done are all reachable and named; delete asks for confirmation.
- [ ] Visit detail: Wrong place?, purpose, times, Save times, Confirm, Split and Remove are reachable and named.
- [ ] Map: Period and Map layers are named; each place marker reads its name and visit count. The same information
      is available without the map in Places (list with visit counts) and Stats.
- [ ] Settings: permission state is read as text; "Open iOS Settings to allow “Always”" is a button; Create export
      reports progress and then "Share N files…".
- [ ] Onboarding: the feature list reads in order; "Allow location & start" and "Not now" are buttons.

### Display and motion

- [ ] Dynamic Type at the largest accessibility size (Settings › Accessibility › Display & Text Size › Larger Text):
      diary rows, trip/visit detail and Settings wrap instead of truncating essential text; nothing overlaps the tab bar.
- [ ] Bold Text and Increase Contrast: text stays readable on the coloured stickers.
- [ ] Reduce Motion: the mascot stops bobbing; tab switches don't spring.
- [ ] Touch targets: icon buttons (tab bar, toolbar, quick mode picks) are at least 44×44 pt — check with
      Accessibility Inspector's audit on a device.

## Known limitations

- **Dark mode**: the app forces the light appearance (`preferredColorScheme(.light)` in RootView) because the sticker
  palette has no dark variant yet; contrast is checked in light only.
- **Dynamic Type in charts and on the map**: chart axis labels, the week chart's day letters and the Map's stats card
  grow with the text but share their space with the drawing, so at the largest sizes they get tight. The widgets keep
  fixed sizes. Track regressions found with the checklist above as separate issues.
- **Map gestures**: panning/zooming the map has no non-gesture equivalent; the information it shows (places, visit
  counts, trip totals) is available in Places, Stats and the day lists.
