# Installing / reinstalling TripLibre

## Routine reinstall (every 7 days, or after code changes)

With a free Apple ID the signature **expires after 7 days**. After that the app won't open **and won't record anything**.
Reinstall on a fixed day each week (e.g. Sunday) instead of waiting for it to expire.

1. Connect the iPhone to the Mac with a cable and **unlock the phone**.
2. In Terminal:

   ```bash
   cd ~/Desktop/HHT-app
   ```

   ```bash
   make phone
   ```

3. When you see `✓ Installed`, you're done. All data is kept.

**Alternative:** open `HHT.xcodeproj` in Xcode, pick your iPhone as the run destination at the top, press ▶.

> ⚠️ **Never delete TripLibre from the phone before reinstalling.** Deleting the app deletes all recorded data.
> Just install over the existing app.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `No iPhone found` | Check the cable and unlock the phone; tap **Trust** on "Trust This Computer?"; make sure Settings › Privacy & Security › **Developer Mode** is on |
| Xcode says "Preparing iPhone…" | Happens on first connection or after an iOS update. Wait a few minutes and run again |
| Signing / Team / provisioning error | Xcode › Settings › Accounts: check the Apple ID is still signed in (sign in again after a password change), then rerun `make phone` |
| "Untrusted Developer" when opening the app | Settings › General › VPN & Device Management › tap your Apple ID › **Trust** |
| Installed but not recording | Settings › HHT › Location: **Always** + **Precise Location** on; Settings › HHT › **Motion & Fitness** on |
| `make: command not found` / `xcodegen: command not found` | Run `xcode-select --install`, then `brew install xcodegen` |

## New Mac / starting from scratch

1. Install Xcode (App Store) and open it once to accept the license.
2. Install XcodeGen: `brew install xcodegen`
3. Get the code: `git clone git@github.com:zyang91/TripLibre.git`, then `cd TripLibre`
4. Xcode › Settings › **Accounts** › `+` › sign in with your Apple ID.
5. `DEVELOPMENT_TEAM` in `project.yml` is the current Apple ID's Team ID (`8HRS3Q2SF3`). If you use a different Apple ID,
   change it to the new one, then run `make project`.
6. Phone: connect by cable → trust the computer → Settings › Privacy & Security › turn on **Developer Mode** (restarts the phone).
7. Run `make phone`.
8. After the first install: Settings › General › VPN & Device Management › Trust; open the app → allow location "Always",
   allow Motion & Fitness.

## New iPhone

Restoring a new phone from an iCloud / computer backup of the old one also restores the app's data (if the backup
includes TripLibre). To be safe, export first on the old phone: gear icon (top left of Today) › **Create export**, and save the
files to your computer or cloud storage. Then do steps 6–8 of "starting from scratch" on the new phone.

## Backups

- The app saves a daily database snapshot to **Files › On My iPhone › HHT › Backups** (last 7 kept), but those are
  still on the phone.
- Export regularly to somewhere off the phone: gear › **Create export** › share / save to your computer.
- To stop reinstalling every 7 days: join the Apple Developer Program ($99/year). Signatures then last a year, and
  TestFlight allows wireless installs.
