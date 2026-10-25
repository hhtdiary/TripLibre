# TripLibre App Store release kit

Materials for the first App Store submission of TripLibre ([#41](https://github.com/zyang91/TripLibre/issues/41),
target **2026-11-02**). Everything to paste into App Store Connect is in this folder.

| File | Paste into / use for |
|---|---|
| [`app-store-listing.md`](app-store-listing.md) | App Information, Pricing, Version page: name, subtitle, description, keywords, URLs, category, age rating |
| [`privacy-policy.md`](privacy-policy.md) | Privacy Policy URL (publish on hhtdiary.org) |
| [`app-privacy-details.md`](app-privacy-details.md) | App Privacy section ("nutrition label") + the privacy manifest the build still needs |
| [`app-review-notes.md`](app-review-notes.md) | App Review Information › Notes, and answers for likely review questions |
| [`accessibility-and-disclaimer.md`](accessibility-and-disclaimer.md) | Accessibility Nutrition Labels + disclaimer text for the listing, website and app |
| [`button-qa-checklist.md`](button-qa-checklist.md) | Pre-submission button and flow check on a device |
| [`review-demo/`](review-demo/) | Sample GPX day for the reviewer (App Review attachment) |
| [`screenshots/`](screenshots/) | iPhone 6.9" screenshots (1320 × 2868), captions, how they were made |

## Issue #41 checklist

| Item | Status | Notes |
|---|---|---|
| Description | ✅ Drafted | `app-store-listing.md` |
| Screenshots | ✅ 9 × 6.9" | Real diary data, de-identified; see `screenshots/README.md` |
| Privacy statement | ✅ Drafted | `privacy-policy.md` (publish it); `app-privacy-details.md` for App Store Connect |
| Other requirements | ⚠️ Open items below | Privacy manifest, permission strings and reviewer demo data are done |
| All button bug checks | 🟡 Partly done | `make ui-test` + manual pass while taking screenshots; full device pass in `button-qa-checklist.md` |
| Accessibility & disclaimer | ✅ Drafted | `accessibility-and-disclaimer.md` |

## Blockers and to-dos before you submit

Things found while preparing this kit. None of them are fixed in this folder.

1. ~~Privacy manifest is missing.~~ **Done:** `App/Support/PrivacyInfo.xcprivacy` and `Widgets/PrivacyInfo.xcprivacy`
   (details in `app-privacy-details.md`).
2. ~~Version number.~~ **Done:** `MARKETING_VERSION` is `2.1.0`, matching the latest GitHub release (v2.1.0,
   2026-10-25); `CURRENT_PROJECT_VERSION` is `1` for the first upload. Bump `CURRENT_PROJECT_VERSION` for every
   further upload of 2.1.0, and `MARKETING_VERSION` with the next GitHub release.
3. **Paid Apple Developer Program membership** and an App Store Connect app record for bundle ID `com.zyang91.hht`
   (the App Group `group.com.zyang91.hht` must be registered on the same team). Free personal teams can't upload.
4. **Release build + archive.** `xcodebuild archive` with the Release configuration, then upload through Xcode
   Organizer or `xcrun altool` / Transporter. Check that demo data and `-hhtUITest` stay simulator-only (they are
   behind `#if targetEnvironment(simulator)`).
5. **Publish the privacy policy** at a stable URL (suggested `https://hhtdiary.org/triplibre/privacy/`), or point
   App Store Connect at the existing docs page `https://hhtdiary.org/triplibre/docs/privacy.html` after updating its
   "App Store privacy details" box.
6. **`SECURITY.md` is still GitHub's template** (it lists versions 4.0–5.1 that don't exist). Replace it with a real
   contact before linking it from the listing.
7. ~~Location permission strings make an absolute claim.~~ **Done:** reworded in `project.yml` (website unchanged).
8. **"Always" permission.** The app asks for When In Use first and then explains how to upgrade to Always, which is what
   guideline 5.1.5 expects. Keep it that way; don't gate the app on Always.
9. ~~Reviewer data.~~ **Done:** `review-demo/sample-day.gpx` (one de-identified day; attach it for App Review).
10. **Experimental agent tab** (Settings › Experimental). It makes no network calls today (the only `URLSession` use
    in the app is the airport download). If it ever calls a model server, the privacy answers have to change.
