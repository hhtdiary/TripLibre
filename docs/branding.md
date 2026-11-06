# TripLibre logo and app icon

![TripLibre logo: a white T on a sky-blue background, with plane, bus, train, walking, cycling and car symbols over hills and a winding road](assets/triplibre-logo.png)

The TripLibre mark is a bold white **T** on a sky-blue background, with plane, bus, rail, walking,
cycling and car symbols over orange, purple and green hills and a winding road that starts at the T's foot.
It identifies the TripLibre app and product documentation. HHT Diary has its own organization mark.

## Assets

| File | Purpose |
| --- | --- |
| `docs/assets/triplibre-logo-source.webp` | Original user-supplied 1254 × 1254 artwork, preserved unchanged |
| `App/Assets.xcassets/AppIcon.appiconset/icon-1024.png` | Shipping iOS app icon, opaque RGB PNG at 1024 × 1024 |
| `docs/assets/triplibre-logo.png` | Identical copy for README, product navigation, docs and favicons |
| `docs/assets/brand-archive/` | Earlier logos (v1 route grid, v2 infinity T and its source), shown on the docs [Logo & brand](https://triplibre.hhtdiary.org/docs/brand.html) page |

The source artwork is a rounded square on a white background. The crop takes the rounded square's
bounding box, source pixels `(90, 96, 1158, 1164)` (left, top, right, bottom; right and bottom exclusive),
so the complete T, the plane and every symbol stay in frame. The white outside the rounded corners
(plus a 6 px antialiased fringe) is filled from the neighbouring background colours by push-pull
interpolation and softened with a light blur, so no white remains on any edge or corner. The result is
Lanczos-resampled from 1068 × 1068 to 1024 × 1024. The artwork itself is not regenerated, recoloured or
stretched; the filled corners sit almost entirely under the iOS icon mask.

## Usage and maintenance

- Keep the icon square, fully opaque and without a baked-in corner mask; iOS applies its own mask.
- Preserve the complete T and surrounding breathing room. Do not crop individual loops or the stem.
- The existing universal iOS 1024 entry in `AppIcon.appiconset/Contents.json` supplies the app icon.
  Both `project.yml` and the generated Xcode project select `AppIcon`; no additional size slots are needed.
- Update the app PNG and documentation PNG together so the app and product pages stay consistent.
- Product headers and favicons reference `triplibre-logo.png?v=N`. When the logo changes, bump `N` everywhere
  (HTML, `assets/site.js`, `assets/docs.js`) and the `?v=` of those scripts, so browsers and the CDN fetch the new image.
- Move the outgoing logo into `docs/assets/brand-archive/` and add it to the archive on `docs/docs/brand.html`.
- Keep HHT Diary organization assets separate.
- This is the existing flat asset-catalog workflow; layered appearance variants are not supplied by this artwork.

See Apple’s [app icon guidance](https://developer.apple.com/design/human-interface-guidelines/app-icons/).
