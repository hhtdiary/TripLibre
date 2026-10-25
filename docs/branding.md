# TripLibre logo and app icon

![TripLibre logo: a colourful infinity route forming a T](assets/triplibre-logo.png)

The TripLibre mark is an infinity-shaped travel route forming a complete **T**, with home, city,
air, rail, walking, cycling and tree symbols on a blue-to-mint background.
It identifies the TripLibre app and product documentation. HHT Diary has its own organization mark.

## Assets

| File | Purpose |
| --- | --- |
| `docs/assets/triplibre-logo-source.jpeg` | Original user-supplied 2048 × 2048 artwork, preserved unchanged |
| `App/Assets.xcassets/AppIcon.appiconset/icon-1024.png` | Shipping iOS app icon, opaque RGB PNG at 1024 × 1024 |
| `docs/assets/triplibre-logo.png` | Identical copy for README, product navigation, docs and favicons |

The source upload was named `Gemini_Generated_Image_weq9v8weq9v8weq9.jpeg`.
The square crop uses source pixel bounds `(200, 80, 1848, 1728)` (left, top, right, bottom;
right and bottom exclusive), then Lanczos resampling from 1648 × 1648 to 1024 × 1024.
This removes the baked-in white corners and excess background while preserving the complete T,
its symbols and shadow. No artwork is regenerated, recoloured or stretched.

## Usage and maintenance

- Keep the icon square, fully opaque and without a baked-in corner mask; iOS applies its own mask.
- Preserve the complete T and surrounding breathing room. Do not crop individual loops or the stem.
- The existing universal iOS 1024 entry in `AppIcon.appiconset/Contents.json` supplies the app icon.
  Both `project.yml` and the generated Xcode project select `AppIcon`; no additional size slots are needed.
- Update the app PNG and documentation PNG together so the app and product pages stay consistent.
- Product headers and favicons already reference `triplibre-logo.png`. Keep HHT Diary organization assets separate.
- This is the existing flat asset-catalog workflow; layered appearance variants are not supplied by this artwork.

See Apple’s [app icon guidance](https://developer.apple.com/design/human-interface-guidelines/app-icons/).
