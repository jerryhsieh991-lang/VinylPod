# Asset Catalog Migration

This app is moving away from brand assets that imply a single vinyl-record
identity. Create the production catalog at:

```text
Sources/VinylPod/Resources/Assets.xcassets/
```

SwiftPM already processes `Sources/VinylPod/Resources`, so the catalog belongs
there rather than beside the Safari extension catalog.

## 1. Catalog Root

```text
Assets.xcassets/
  Contents.json
  AppIcon.appiconset/
  Brand.colorset/
  Visualizers/
  Localized/
```

`Contents.json`:

```json
{
  "info": {
    "author": "xcode",
    "version": 1
  }
}
```

## 2. App Icon

Use one `AppIcon.appiconset` with complete macOS slots. Do not ship vector-only
or single-size placeholders for production.

```text
AppIcon.appiconset/
  Contents.json
  app-icon-16.png
  app-icon-16@2x.png
  app-icon-32.png
  app-icon-32@2x.png
  app-icon-128.png
  app-icon-128@2x.png
  app-icon-256.png
  app-icon-256@2x.png
  app-icon-512.png
  app-icon-512@2x.png
```

Production constraints:

- Export square PNGs with transparent background only where the final icon art
  intentionally needs it; the final silhouette must respect the macOS squircle
  mask.
- Keep all critical glyphs inside the safe area. Avoid corners and tiny text.
- Provide the full 16, 32, 128, 256, and 512 point macOS matrix at 1x and 2x.
- Name files generically (`app-icon-*`) so old vinyl naming does not survive in
  source control.
- Test the icon in Finder, Dock, Cmd-Tab, Settings Login Items, and low-size
  Spotlight contexts before release.

## 3. Brand Tokens

```text
Brand.colorset/
  Contents.json
```

Use this only for non-album-reactive fallback colors. The in-app visualizer
should continue using `AlbumColorPalette` and `RGBColorToken` for artwork-driven
surfaces.

## 4. Visualizer Placeholders

```text
Visualizers/
  CassettePlaceholder.imageset/
  LiquidDiscPlaceholder.imageset/
  ArtworkFallback.imageset/
```

These are optional static fallback assets for screenshots, onboarding, and
empty states. Runtime rendering remains SwiftUI/Core Graphics only.

## 5. Localized Placeholders

```text
Localized/
  EmptyArtwork.imageset/
  EmptyArtwork.en.imageset/
  EmptyArtwork.zh-Hans.imageset/
```

Use localized variants only when the bitmap itself contains language-specific
text. Prefer text-free artwork so the app does not need duplicated localized
image sets.
