# Accessibility and disclaimer

## Accessibility Nutrition Labels (App Store Connect)

App Store Connect › App › *Accessibility* lets you declare which features work across the app's **common tasks**.
Only declare a feature once you have checked every common task with it on a device. Common tasks for TripLibre:
onboarding and permissions, reading Today, opening and correcting a trip, naming a place, browsing Timeline, Map and
Stats, adding a cost, and creating an export.

| Feature | Declare? | Evidence / what's left |
|---|---|---|
| **Larger Text** | ✅ Yes | Text follows Dynamic Type up to the largest accessibility sizes; rows and tiles restack; tab bar goes icon-only with large content viewer (#67). `make ui-test` audits fail on Dynamic Type issues |
| **Sufficient Contrast** | ✅ Yes | Secondary text darkened to ≥ 4.5:1 on the butter background (#67); audits check contrast. Known exceptions are system/MapKit-drawn (see `docs/accessibility-testing.md`) |
| **Reduced Motion** | ✅ Yes | Tab-bar spring, timeline and agent scrolling animations are turned off with Reduce Motion (`accessibilityReduceMotion`). Quick manual check recommended |
| **VoiceOver** | 🟡 After a manual pass | Audits run on all main screens and the a11y-check score is 98/100 (#84). Do the manual VoiceOver checklist in `docs/accessibility-testing.md` on a device (map screens, Add a cost, Spending) first |
| **Voice Control** | 🟡 After a manual pass | Buttons have labels, so "Tap …" should work; check the icon-only tab bar and the map layer menu by voice |
| **Differentiate Without Color Alone** | 🟡 Probably yes | Modes have icons and names as well as colours; check the Stats mode bars and the map legend |
| **Dark Interface** | ❌ No | The app forces light mode (`.preferredColorScheme(.light)` in `RootView`) |
| **Captions / Audio Descriptions** | — Not applicable | No video or audio content |

Accessibility URL (optional): link to the accessibility section of the docs once it exists, e.g.
`https://triplibre.hhtdiary.org/docs/ui-guide.html`.

## Disclaimer text

### For the App Store description (already in `app-store-listing.md`)

> Note: continued use of GPS running in the background can decrease battery life. TripLibre is a personal diary, not
> a navigation or safety tool; inferred trips and modes can be wrong, so check anything you rely on.

### For the website and docs (longer)

> **Disclaimer.** TripLibre is provided "as is", free of charge, under the Apache License 2.0, without warranties of
> any kind. Visits, trips, travel modes, distances, costs and statistics are worked out automatically from your
> phone's sensors and can be incomplete or wrong, for example after GPS gaps, indoors or underground. Don't use
> TripLibre for navigation, emergencies, safety-critical decisions, legal or tax records, or as proof of where you
> were. Check and correct anything you rely on.
>
> **Battery.** Background GPS uses battery. TripLibre switches GPS off while you're stationary, but heavy travel days
> use more power.
>
> **Research use.** TripLibre data is not a representative travel survey, and accuracy has only been measured on a
> small sample so far (see *Research uses & limitations* and *Validation* in the docs). Research that involves other
> people's location data usually needs ethics/IRB approval and the participants' informed consent.
>
> **Other people's privacy.** Your diary can reveal other people's homes and routines. Get consent before sharing
> data that shows them.

### In the app (suggested)

There's no disclaimer screen in the app today. A short footer in *Settings › About* (or the onboarding's last line)
is enough:

> Trips and modes are inferred automatically and can be wrong. TripLibre isn't a navigation or safety tool.
> Background GPS uses battery.
