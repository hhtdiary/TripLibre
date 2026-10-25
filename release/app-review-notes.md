# App Review information

## Contact

Fill in App Store Connect › App Review Information: first and last name, phone, email. No sign-in is required, so
leave *Sign-in required* unchecked.

## Notes for the reviewer (paste into "Notes", ≤ 4000)

```text
TripLibre is a private, on-device travel diary. There is no account, no sign-in and no server: all data is stored in the app's sandbox on the iPhone.

HOW TO TRY IT
1. Launch the app and tap "Allow location & start". Grant "While Using", and Motion & Fitness when asked.
2. The diary fills in as the device moves. A stationary review device will show an empty or nearly empty day; this is expected.
3. To see a full diary without travelling, import the attached sample: Settings (gear on Today) › Import › Import GPX track, and pick sample-day.gpx. Then on Today tap the calendar and choose 22 October 2026: it shows about 8 trips (subway and walking) between 9 stops. Timeline, Map and Stats show the same day.
4. Tap any trip to change its travel mode, or any stop to name the place. Settings › Create export writes CSV/JSON/GeoJSON/SQLite files and opens the share sheet.

WHY BACKGROUND LOCATION
The app's core feature is an automatic diary of the user's trips, like a travel survey. Trips happen while the app is in the background, so it uses the "location" background mode. The app first asks for "While Using"; it explains in Settings how to upgrade to "Always", and it works (with gaps) without it. GPS runs only while the user is moving; when they stop, the app switches GPS off and relies on a geofence, visit monitoring and significant-change monitoring to wake again. Recording can be stopped any time in Settings › Record location. The "fetch" background mode refreshes the diary and the widgets (BGTaskScheduler identifier com.zyang91.hht.refresh).

DATA AND NETWORK
Location data never goes to the developer, who runs no server. The only network use is Apple Maps tiles, optional address lookup with Apple's CLGeocoder (off by default), and an on-request download of a public airport list. Exports are only shared when the user picks a destination in the share sheet.

The app is open source (Apache 2.0): https://github.com/zyang91/TripLibre
```

## Before submitting

- [x] Sample GPX for step 3: `review-demo/sample-day.gpx`, from the de-identified data (checked: 9 visits, 8 trips;
      see `review-demo/README.md`). Attach it under App Review Information › Attachment.
- [ ] Optional: also attach a 1–2 minute screen recording of a real day.
- [ ] Confirm the onboarding button text in the note matches the build ("Allow location & start").

## Likely review questions and answers

| Guideline | Risk | Answer / mitigation |
|---|---|---|
| 2.5.4 Background modes | "Location" background mode must serve a feature the user sees | Automatic diary is the main feature; explained in notes and in Settings' collection footer |
| 5.1.1(i)/(ii) Data collection & permission | Purpose strings must be specific; app must work if denied | Strings name the diary and say it's saved only on the iPhone. Without permission the app opens and offers import and manual entry |
| 5.1.5 Location services | Must not require "Always"; must explain battery impact | Asks When In Use first. Battery note is in the description's last paragraph |
| 5.1.2 Data use and sharing | Claims must match behaviour | "Data Not Collected" label, privacy manifest, public source code. The permission strings no longer make the absolute "never leaves your iPhone" claim |
| 4.2 Minimum functionality | Empty app on a stationary device | `review-demo/sample-day.gpx`, as above |
| 1.4 Physical harm | Location apps aren't safety tools | Disclaimer in description and Settings (see `accessibility-and-disclaimer.md`) |
| 2.3.3 Accurate screenshots | Screenshots must show the real app | They are real simulator captures of the release UI with de-identified real data |
