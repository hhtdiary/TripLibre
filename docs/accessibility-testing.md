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
Xcode's test report also attaches a screenshot with the element highlighted.

### Known exceptions

Accepted findings live in `KnownIssue` in `UITests/AccessibilityAuditTests.swift`. Each one matches the audit type
*and* the element, so a new problem of the same kind on another element still fails. Keep this list in sync:

| Exception | Screens | Why it's accepted |
| --- | --- | --- |
| `mapKitAttribution` | Map, Today, Trip/Visit detail | Apple Maps' logo and "Legal" link are drawn by MapKit; their size and contrast aren't ours to change. |
| `mapKitMarkers` | Trip detail, Visit detail | MapKit's `Marker` pins are under 44 pt and not exposed as elements; they're informational and the same places are named right below the map. |
| `textClippedFalsePositive` | Today, Trip detail | "Stamp this moment" and the origin/destination labels under the trip map are reported as clipped but render in full (screenshot-checked on iPhone 17). Matched by exact text. |
| `mapKitLabels` | Map | Annotation titles and street names are drawn by MapKit; the element-detection audit sees text it can't attribute to an element. |

### Report-only audits

Two audit types are logged (`[a11y] <screen>: report-only: …`) but don't fail the tests yet:

- **Dynamic Type** — `Font.toon(_:)` uses fixed point sizes throughout the app, so nearly every text element is
  flagged. Making it scale means reworking the fixed-height sticker cards and pill buttons, which is its own piece of
  work.
- **Contrast** — the audit flags ink-on-white text inside the tilted, shadowed sticker cards (the palette gives
  ≥ 12:1 there), so its results are mostly noise until those cards change. Colour changes are checked against the
  palette by hand instead; `Toon.accentDeep` (toolbar and link tint) was darkened to `#C73D22` for 5.1:1 on white.

Once either is fixed, remove it from `reportOnly` in `UITests/AccessibilityAuditTests.swift`.

### CI

Not in CI yet: macOS runners cost ~10× Linux minutes and simulator UI tests are slower and flakier than the rest of
the pipeline. Run `make ui-test` locally before merging UI changes. Revisit with a small smoke subset
(`ONLY=HHTUITests/CoreFlowTests`) on a schedule once the suite has been stable for a while.

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
- **Custom fonts and Dynamic Type**: `Font.toon(_:)` sizes are fixed points; very large text sizes rely on SwiftUI's
  scaling of the rounded system font. Track regressions found with the checklist above as separate issues.
- **Map gestures**: panning/zooming the map has no non-gesture equivalent; the information it shows (places, visit
  counts, trip totals) is available in Places, Stats and the day lists.
