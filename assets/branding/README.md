# Branding assets (US-27)

| File | What it is | Used for |
|---|---|---|
| `logo_source.png` | Byte-for-byte copy of the supplied artwork (1024x1024 rounded square on off-white padding). Never edited. | Input of the pipeline |
| `logo_master.png` | Artwork cropped out of the padding: opaque, square, full-bleed, no rounded corners (1024x1024, upscaled from the 770 px crop). | iOS icons, web/PWA icons, Android legacy icons, adaptive foreground |
| `logo_mark.png` | `logo_master` with transparent rounded corners (512x512). Registered in `pubspec.yaml`. | Splash 120 dp, onboarding first slide 96 dp, sign-in / sign-up 72 dp (56 dp with keyboard) via `AppLogo` |

## How the icons are made (reproducible)

```
python tool/make_logo.py [path/to/source.png]      # needs Pillow; default source = the file in Downloads
```

1. Finds the artwork bounding box (rows/columns that contain saturated colour).
2. Picks the largest centred square inside it whose whole border ring is artwork colour, i.e. inside the rounded
   corners (no off-white pixel left anywhere), then shrinks it by 8 px against anti-aliasing. Result: 770 px square.
3. Writes `logo_master.png` and `logo_mark.png`.
4. iOS: every size listed in `ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json`, RGB (no alpha), full-bleed.
5. Android: adaptive icon (`mipmap-anydpi-v26/ic_launcher*.xml`, foreground = artwork at 74 % inside the 66 % safe zone with a
   feathered edge, background = vertical gradient sampled from the artwork's left/right edge columns, blended with a plain blue-to-green ramp) + legacy
   `ic_launcher` / `ic_launcher_round` for mdpi..xxxhdpi. No monochrome layer yet (needs a designer silhouette).
6. Web: `favicon.png` 32, `favicon.ico` 16/32/48, `icons/Icon-192|512.png` (full-bleed), `icons/Icon-maskable-192|512.png`
   (artwork at 72 % on the sampled gradient, inside the 80 % maskable safe zone), `icons/apple-touch-icon.png` 180.

## Known limits

- The source is 1024 px with the artwork ~914 px wide, so the cropped master is upscaled 1.33x (slightly soft at 1024).
  A full-bleed vector/PNG from the designer would be better for the App Store icon.
- The rounded corners of the original are cut away rather than re-drawn (about 5 % of each edge is lost, the pin, figures and
  path are untouched).
- The native launch screens (Android `launch_background.xml`, iOS `LaunchImage`) still show the Flutter default; the in-app splash
  (`SplashScreen`) shows the mark.
- Under a circular mask the skyline sides show a slightly darker band where the artwork meets the extended background.
