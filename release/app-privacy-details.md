# App Privacy details (App Store Connect) and privacy manifest

## App Privacy questionnaire

App Store Connect › App Privacy › *Get Started*.

**Do you or your third-party partners collect data from this app?** → **No, we do not collect data from this app.**

Why that's the right answer under Apple's definitions: "collect" means data transmitted off the device in a way that
lets the developer or a partner access it beyond what's needed to serve a request in real time. TripLibre:

| Data | Leaves the device? | Counts as collected? |
|---|---|---|
| Precise location (GPS fixes, visits, trips) | No. Stored only in the app container | No |
| Motion activity | No | No |
| Place names, notes, costs, flights | No | No |
| Address lookup (optional, off by default) | One coordinate to Apple's CLGeocoder, answered in real time | No: Apple's own service, not retained by the developer |
| Map tiles | Visible area to Apple MapKit | No: Apple framework, same as any MapKit app |
| Airport list download | Plain GET of a public CSV; sends nothing about the user | No |
| Exports | Only when the user shares them, to a destination they pick | No: user-initiated sharing isn't collection |
| Crash logs | Only Apple's own opt-in diagnostics | No: not via a developer SDK |

Resulting label on the store: **Data Not Collected**.

Also answer:

- **Tracking (ATT)**: No. The app doesn't track users across apps or websites, so no `NSUserTrackingUsageDescription`.
- **Privacy Policy URL**: see `app-store-listing.md`.
- **User Privacy Choices URL** (optional): `https://triplibre.hhtdiary.org/docs/privacy.html#youre-in-control` (check
  the anchor exists after publishing).

If any of these change (cloud sync, analytics, a crash SDK, a server-side agent), re-answer the questionnaire before
the release that ships it.

## Export compliance

`ITSAppUsesNonExemptEncryption = false` is already in `Info.plist` (the app only uses Apple's built-in HTTPS), so
App Store Connect won't ask on every upload.

## Privacy manifest (added)

Both bundles now ship a manifest, and the build copies them into the `.app` and the widget `.appex`:

| Target | File | Declares |
|---|---|---|
| App | `App/Support/PrivacyInfo.xcprivacy` | No tracking, no tracking domains, no collected data; `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1` (the app's own settings) |
| Widgets | `Widgets/PrivacyInfo.xcprivacy` | No tracking, no collected data, no required-reason APIs (the widgets only read the App Group summary file) |

Checked on 2026-10-25: no other required-reason API is used in `App/`, `Widgets/` or `Packages/HHTCore/Sources`
(no file timestamp keys, `systemUptime`, disk space or keyboard APIs; backups are pruned by file name, not date).
Re-check when adding code like that, or if a widget starts reading `UserDefaults` (then declare `1C8F.1` there).
After archiving, Xcode › Organizer › *Generate Privacy Report* should show no collected data and the one API reason.

## Permission strings (Info.plist)

Updated in `project.yml` (the source of `Info.plist`) on 2026-10-25, so they no longer claim that nothing ever leaves
the phone (optional address lookup and map tiles go to Apple). The website was not changed.

| Key | Text |
|---|---|
| `NSLocationWhenInUseUsageDescription` | TripLibre uses your location to build your travel diary of visits and trips. Your diary is saved only on this iPhone; TripLibre has no account or server. |
| `NSLocationAlwaysAndWhenInUseUsageDescription` | Allow "Always" so TripLibre can log trips while it's in the background. GPS runs only while you're moving, and your diary is saved only on this iPhone. |
| `NSMotionUsageDescription` | Motion activity (walking, cycling, in a vehicle) helps TripLibre tell travel modes apart. It's used only on this iPhone. |
