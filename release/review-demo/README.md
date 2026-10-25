# Sample day for App Review

`sample-day.gpx` is one day of GPS (Thu 22 Oct 2026, Philadelphia, 315 points, 27 KB), so a reviewer who isn't
moving can still see a full diary. Attach it in App Store Connect › App Review Information › Attachment, or link to
it in the review notes.

## What's in it

GPS fixes only (latitude, longitude, time), exported from the de-identified screenshot database (see
`../screenshots/README.md`): Home is the decoy location, fixes near the real home are snapped to it, and there are no
place names, notes, costs or anything else. Speed, accuracy and motion data aren't in GPX, so modes are inferred from
positions alone.

It is still one real person's day of movement around Center City and University City. Keep it out of anything you
publish more widely than the review attachment, or replace it with a synthetic track, if that matters to you.

## Checked on 2026-10-25

Imported with the app's own `Importer.importGPX` and rebuilt with `InferenceEngine.process` on an empty database:
**9 visits and 8 trips**, including three subway/metro trips and several walks. Loaded into a clean simulator
install, Today for Oct 22 showed "8 trips and 12 mi", the subway cost prompts and the quick-check card.

## How the reviewer uses it

1. Settings (gear on Today) › Import › **Import GPX track**, pick `sample-day.gpx`.
2. Wait a few seconds for "visits and trips are being reconstructed".
3. On Today, tap the calendar and choose **22 October 2026** (the day shows in the device's time zone).
