# 06 — Design System: Liquid Glass & Album-Reactive Color

VinylPod's whole visual identity is one idea, stated in the header comment of
`Sources/VinylPod/Core/Theme.swift`:

> "Mood: **album-reactive liquid glass** over a calm landscape base. The
> current album art drives the palette used by glass, progress, controls, and
> desktop ambience."

And the founding design brief (`design_system.md`, repo root, §1) puts the
tension in one line:

> "**Stunning enough for the visual lover, simple enough for everyone.**
> Quiet by default. The landscape is the soul; the UI is a whisper of glass on
> top of it."

Two hard rules fall out of that sentence and are enforced structurally
throughout the codebase:

1. **The landscape background never changes color with the track** —
   `design_system.md` §2: *"The background never changes color with the
   track — visual stability is a hard rule."* The landscape does tint softly
   (see §4), but it never becomes a different photo or a flat color wash.
2. **Only small surfaces — glass panels, accents, progress fills — "breathe"
   with each track.** This document is about how that breathing is built:
   where the color comes from, how it is turned into a 4-role palette, and
   the exact layered-blend recipe that turns a blur into "glass that has
   absorbed the color of the record sleeve sitting on it."

This document is the sibling of the existing `design_system.md` (root-level,
screenshot-reverse-engineered widget specs, dated 2026-06-28/29) — it does not
replace that file. Where the two overlap this document cites
`design_system.md` and adds the *why* and *exact current source values*,
which had drifted from the original screenshots as the glass recipe was
iterated. Treat `design_system.md` as the historical product brief; treat
this document as the living token/pipeline reference tied to `Theme.swift`.

---

## 1. Design philosophy

Source comments, in the order they matter:

- `Theme.swift:6-8` — *"Mood: album-reactive liquid glass over a calm
  landscape base. The current album art drives the palette used by glass,
  progress, controls, and desktop ambience."*
- `AdaptiveWidgetGlassBackground.swift:5-10` — *"Panels float as light,
  translucent layers — never opaque solid blocks... Blue covers must read
  visibly blue; monochrome covers become neutral gray glass — without going
  neon."*
- `design_system.md`, "Floating widget adaptive glass pass" — *"Avoid solid
  color fills: the desktop wallpaper must remain visible through the card."*
- `design_system.md`, "Ai Structuer liquid-glass lock" — *"Visibility rule:
  album color must be obvious, not theoretical... `softLight` alone is not
  enough over bright desktop content."*

Read together, these are four constraints, not just mood words:

| Constraint | Enforced by |
|---|---|
| Background is calm and static | `LandscapeBackground` never swaps images per-track; only a thin tint overlay reacts (see §4). |
| Glass must stay translucent | Every widget starts every glass stack with a live `VisualEffectBlur` (`.hudWindow`, `.behindWindow`) as layer 1, before any color is added. |
| Album color must be *visible*, not subliminal | The color membrane (§4, layer 2) is **normal-blended**, not soft-light — the codebase explicitly moved off soft-light because it was too subtle over bright desktop content. |
| No neon / oversaturation | `RGBColorToken.adjusted(...)` clamps saturation to `≤0.94` and brightness to `≤0.98` everywhere colors are derived (`Theme.swift:114-115`). |

---

## 2. Color system

### 2.1 `RGBColorToken` — the sendable color primitive

`Sources/VinylPod/Core/Theme.swift:57-151`. A plain `Sendable` struct (not a
SwiftUI `Color`, which is main-actor-bound) so the CoreImage extraction
pipeline can move color math across actor boundaries without ceremony.

- **`chroma`** (line 76): `max(r,g,b) - min(r,g,b)` — cheap saturation-ish
  spread. Used to decide whether an album's colors are "useful" (§3) and to
  modulate glass bloom intensity (`chromaBoost`).
- **`relativeLuminance`** (lines 80-85): the real WCAG formula — sRGB
  channels linearized (`≤0.03928 → /12.92`, else gamma `2.4`), combined with
  the `0.2126/0.7152/0.0722` Rec. 709 weights. Used everywhere the app needs
  to know "is this artwork bright or dark" to flip legibility scrims and
  stroke opacities (`isBrightArtwork`/`isDarkArtwork` gates appear in
  `AdaptiveWidgetGlassBackground`, the island's `IslandPanelGlass`,
  `SmallGlassWidget`'s bottom strip, `RegularGlassWidget`'s caption).
- **`mixed(with:amount:)`** (lines 87-95): linear channel-wise lerp, clamped
  `t ∈ [0,1]`. Blends dominant partway toward vibrant so it doesn't read as a
  flat gray average (§3).
- **`adjusted(saturation:brightness:maximumBrightness:)`** (lines 97-119):
  converts to HSB, then `outputSaturation = max(saturation, minSaturation)`
  and `outputBrightness = max(brightness, minBrightness)` — both are
  *floors*, never lowered below what the pixel data gave — with
  `maximumBrightness` applied as a **cap** afterward. A hard ceiling then
  applies regardless of caller: `saturation ≤ 0.94`, `brightness ≤ 0.98`
  (lines 114-115) — the anti-neon clamp. This is how the extractor turns raw
  pixels into "a color that looks intentional" (§2.3).
- **`darkened(_:)`** (lines 121-135): raises saturation slightly (`+0.06`,
  capped `0.92`) while multiplying brightness down (`×(1-amount)`, floored
  `0.10`) — used once, to derive `shadow` from `dominant` at `0.68` (§2.2).

### 2.2 `AlbumColorPalette` — the four roles

`Theme.swift:154-166`. Every glass surface, the landscape tint, and the
Dynamic Island read exactly these four `RGBColorToken` fields — there is no
fifth "accent" color independent of this palette (`accentColor` in
`AppSettings` is literally set to `palette.vibrant.color`, see §3).

| Role | Purpose | Where it's used |
|---|---|---|
| `dominant` | Stable "mood" color — the CoreImage area-average, pulled toward vibrant and re-saturated. Drives the *middle* of glass gradients and the landscape tint's mid-tone. | `AdaptiveWidgetGlassBackground` membrane stop 2, `LandscapeBackground` tint, `DesktopWidgetCanvas` background radial. |
| `vibrant` | The saturation-weighted "loudest" color in the artwork. Drives accents: progress-bar fill, play-button glow, top-left bloom, `AppSettings.accentColor`. | `AdaptiveWidgetGlassBackground` bloom + wet-edge, `IslandTimeRow` progress fill, `LargeGlassWidget`/`RegularGlassWidget` control shadows. |
| `muted` | Lower-chroma, mid-brightness sample — the glass "body" tone, less attention-grabbing than vibrant. | Frost layer in `AdaptiveWidgetGlassBackground`, `DesktopWidgetCanvas` background gradient middle stop. |
| `shadow` | `dominant.darkened(0.68)` — adds depth without a static black wash. | Bottom-right corners of every glass gradient, stroke-border bottom stop, caption-panel bottom, Dynamic Island shadow color. |

**`.iceMountain` fallback palette** (`Theme.swift:160-165`) — the default
before any artwork has been analyzed, and the value the pipeline resets to
when there is no track (§3):

| Role | R | G | B | Approx. hex | Character |
|---|---:|---:|---:|---|---|
| `dominant` | 0.36 | 0.76 | 0.94 | `#5CC2F0` | Cool sky blue |
| `vibrant`  | 0.26 | 0.68 | 0.98 | `#42ADFA` | Slightly deeper, more saturated ice blue |
| `muted`    | 0.68 | 0.86 | 0.92 | `#ADDBEB` | Pale glacier blue-white |
| `shadow`   | 0.08 | 0.18 | 0.30 | `#142E4D` | Deep midnight-blue depth |

A coherent single-hue-family palette by design — it's the palette for the
bundled "ice mountain" default background/artwork, so glass, Dynamic Island,
and landscape all agree with the photo behind them before any real album has
played. Also referenced as the ice-blue fallback accent in
`design_system.md`'s "Ai Structuer liquid-glass lock" note (*"fallback
`#5CCEF5` ice blue when artwork is missing"*) — same family, refined
slightly differently between the two write-ups; the values above are read
directly from current `Theme.swift` source and are authoritative.

### 2.3 `adjusted(maximumBrightness:)` in practice — `ArtworkColorExtractor`

`Sources/VinylPod/Audio/ArtworkColorExtractor.swift:29-76` chains all three
`RGBColorToken` operations to turn raw pixels into the 4-role palette:

1. **Dominant, pass 1** — `CIAreaAverage` reduces the whole image to one
   average RGBA pixel (`areaAverage`, lines 82-108) — "stable background
   mood," a genuine average that can't spike from one bright corner.
2. **Vibrant** — `samplePalette` (lines 110-197) downsamples to a **52×52 px
   max-side grid** (line 118) and per-pixel computes a saturation-weighted
   score: `pow(saturation, 1.65) * pow(max(brightness, 0.18), 0.72) *
   midtoneBias * darkColorLift` (lines 171-176) — saturation dominates
   (exponent 1.65 vs 0.72), with a midtone bias favoring brightness near
   `0.56` and a `1.35×` lift for dark, saturated pixels so jewel tones
   survive a bright background. The weighted average is `rawVibrant`.
3. **Chroma gate** — `hasUsefulChroma = max(rawVibrant.chroma,
   averageSaturation) > 0.10 && vibrantWeight > 0.035` (lines 47-48) — the
   grayscale detector. Monochrome/desaturated covers fail this gate and skip
   the saturation floor below, producing genuinely neutral glass, matching
   "monochrome album art should produce neutral gray glass" in
   `design_system.md`'s "Floating widget adaptive glass pass."
4. **Vibrant, finalized** — `rawVibrant.adjusted(saturation:
   hasUsefulChroma ? 0.48 : nil, brightness: hasUsefulChroma ? 0.56 : 0.46,
   maximumBrightness: 0.90)` (lines 50-54): floors saturation at `0.48` (only
   for real color), floors brightness at `0.56`/`0.46`, and **caps brightness
   at `0.90`** — even a floor-bound token can't reach blown-out white, which
   is what keeps "vibrant" from reading as a neon highlighter.
5. **Dominant, finalized** — mixed `24%` toward vibrant (if chroma is
   useful), then `adjusted(saturation: 0.24, brightness:
   relativeLuminance < 0.08 ? 0.22 : nil, maximumBrightness: 0.82)`
   (lines 55-61) — lower floor/cap than vibrant, matching "dominant is the
   calmer mood color." The `relativeLuminance < 0.08` branch rescues
   near-black art from collapsing to invisible.
6. **Muted, finalized** — the low-chroma pass (weighting pixels near
   `saturation ≈ 0.30`, `brightness ≈ 0.50`) mixed `16%` toward vibrant, then
   capped at `maximumBrightness: 0.76` — dimmest, least saturated role,
   matching its job as glass "body" fill rather than an attention layer.
7. **Shadow** — `dominantMood.darkened(0.68)` (line 74).

---

## 3. The adaptive-color pipeline, end to end

```
Album artwork (NSImage)
      │
      ▼
ArtworkColorExtractor.paletteOffMain(from:)      [nonisolated static, off-main-actor safe]
      │  CIAreaAverage → dominant (raw average)
      │  52×52 saturation-weighted scan → vibrant, muted, chroma stats
      │  RGBColorToken.adjusted(...) × 3          [§2.3 above]
      ▼
AlbumColorPalette { dominant, vibrant, muted, shadow }
      │
      ▼
AppSettings.setAlbumPalette(from:)                 [Core/Services.swift:332-350]
      │
      │  guard useAdaptiveAccent, let palette else {
      │      guard albumPalette != .iceMountain else { return }   ← no-op skip
      │      → reset to .iceMountain + accentFallback
      │  }
      │
      │  guard palette != albumPalette else { return }            ← HARD DEDUP RULE
      │
      │  withAnimation(VPTheme.liquid) {
      │      albumPalette = palette
      │      accentColor  = palette.vibrant.color
      │  }
      ▼
@Published AppSettings.albumPalette  (AlbumColorPalette, Equatable)
      │
      ├──► AdaptiveWidgetGlassBackground   (Small/Medium/Regular/Large widget glass, §4)
      ├──► LandscapeBackground             (background tint overlay, §4 note)
      ├──► DesktopWidgetCanvas             (full-screen ambience gradient)
      └──► DynamicIslandWidget             (capsule + expanded-panel glass, §7)
```

### The perf-critical dedup rule (hard constraint)

`AppSettings.setAlbumPalette`, `Core/Services.swift:342-345`:

```swift
// Defense-in-depth: never re-assign an EQUAL palette. Otherwise the
// `.animation(value: albumPalette)` on the glass + landscape re-fires and
// re-renders those expensive views at 60fps for an unchanged cover.
guard palette != albumPalette else { return }
```

**This is a hard constraint, not an optimization nicety.** `albumPalette` is
an `@Published` property observed with `.animation(VPTheme.liquid, value:
settings.albumPalette)` by `AdaptiveWidgetGlassBackground` (lines 190-191),
`LandscapeBackground` (line 82), and `DesktopWidgetCanvas` (line 143) — all
expensive multi-layer gradient/blur stacks. `AlbumColorPalette` derives
`Equatable` from four `RGBColorToken` value structs, so the guard is a
genuine value comparison, not a reference check. Any code path that
re-derives a palette from the *same* artwork **must** go through this setter
rather than assigning `albumPalette` directly, or the event triggers an
unnecessary 60fps re-animation of the glass and landscape simultaneously.
The same discipline repeats for `position` polling in the Dynamic Island
(`DynamicIslandWidget.swift:16-21`, `IslandTimeRow` at line 464-473): coarsen
or dedupe before publishing, never re-fire on identical values.

When there is no artwork / adaptive accent is off, the palette resets to
`.iceMountain` (§2.2) and `accentColor` resets to `VPTheme.accentFallback`
(`iceAccent.opacity(0.92)`, `Theme.swift:26-27`) — also gated by its own
no-op check (`guard albumPalette != .iceMountain else { return }`, line 334)
so repeatedly hitting "no artwork" doesn't repeatedly re-trigger the
animation either.

---

## 4. The liquid-glass rendering recipe

`Sources/VinylPod/Views/Widget/AdaptiveWidgetGlassBackground.swift` is the
single shared background used by `SmallGlassWidget`, `MediumGlassWidget`,
`RegularGlassWidget`, and `LargeGlassWidget` (each supplies its own
`cornerRadius` / `accentStrength` / `neutralOpacity` / `strokeOpacity`, but
the layer stack is identical). It renders bottom-to-top as a `ZStack`; here
is the numbered recipe with concrete formulas, reproducible by a designer in
any layer-based tool (Figma, Sketch, CSS):

**Precomputed per-frame values** (lines 32-40):
```
chromaBoost            = min(vibrant.chroma * 0.18, 0.14)
isBrightArtwork         = dominant.relativeLuminance > 0.46
isDarkArtwork           = dominant.relativeLuminance < 0.16
strength                = glassTintStrength.multiplier      // 0.72 / 1.0 / 1.28 (§6)
colorMembraneOpacity    = min((accentStrength + 0.13 + chromaBoost) * strength, 0.58)
dominantMembraneOpacity = min((accentStrength + 0.08 + chromaBoost*0.65) * strength, 0.46)
legibilityScrimOpacity  = isBrightArtwork ? 0.22 : (isDarkArtwork ? 0.12 : 0.17)
depthOpacity            = isDarkArtwork ? 0.26 : 0.18
```

| # | Layer | Technique | Formula / stops |
|---|---|---|---|
| **1** | **Blur** | `VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)`, clipped to the shape | Native macOS live backdrop blur — the actual translucency. Everything above is a thin tint on top of this. |
| **2** | **Album color membrane** | `LinearGradient`, normal blend (no `.blendMode`), diagonal top-leading → bottom-trailing | Stops: `vibrant@colorMembraneOpacity` at 0.00, `dominant@dominantMembraneOpacity` at 0.46, `shadow@depthOpacity` at 1.00. **This is the fix for "blue covers must read visibly blue"** — normal blend, not soft-light, because soft-light alone tested too subtle over bright desktop content. |
| **2** | **Light frost** | `LinearGradient`, normal blend, top → bottom | Stops: `white@(neutralOpacity*0.28)` at 0.00, `muted@(neutralOpacity*0.22)` at 0.42, `shadow@(0.12+depthOpacity)` at 1.00. Top-lit, near-clear body, faint bottom shade — replaces an earlier flat white+black fill that read as "milky." |
| **3** | **Legibility vignette** | `LinearGradient`, **`.multiply`** blend, top → bottom | Stops: `black@(scrim*0.20)` at 0.00, `black@(scrim*0.44)` at 0.58, `black@scrim` at 1.00, where `scrim = legibilityScrimOpacity`. Multiply (not an opaque rectangle) so text stays legible without flattening the cover's hue. |
| **3** | **Color bloom** | `RadialGradient`, **`.overlay`** blend, center `(0.18, 0.02)` (upper-left), `startRadius 6 → endRadius 230` | Colors: `vibrant@min((accentStrength*1.70+chromaBoost)*strength, 0.68)` → `dominant@min((accentStrength*0.92+chromaBoost*0.55)*strength, 0.48)` → `.clear`. |
| **4** | **Specular wet edge** | `LinearGradient`, **`.screen`** blend, top → bottom, hit-testing disabled | Stops: `white@(isDarkArtwork ? 0.62 : 0.52)` at 0.00, `vibrant@0.30` at 0.055, `.clear` at 0.22 — a crisp bright sliver hugging the top rim only (replaced an earlier blurry rotated-capsule smudge). |
| **4** | **Corner catch-light** | `RadialGradient`, `.screen` blend, center `(0.10, 0.08)`, `startRadius 0 → endRadius 135` | Colors: `white@(isDarkArtwork ? 0.24 : 0.16)` → `.clear`. |
| **5** | **Bottom shade** (optional, only if `bottomShadeHeight > 0`) | `Rectangle` pinned to bottom, plain fill | Colors: `black@0.04` → `black@(isBrightArtwork ? 0.28 : 0.22)`, top → bottom, height = `bottomShadeHeight`. Used by callers that need extra contrast under a caption strip. |
| **6** | **Rim stroke, primary** | `strokeBorder`, `LinearGradient`, diagonal, `lineWidth 1.0` | Colors: `white@(strokeOpacity + (isDarkArtwork ? 0.42 : 0.34))` → `vibrant@(strokeOpacity+0.24)` → `shadow@(isBrightArtwork ? 0.42 : 0.32)`. Bright top-left highlight fading through a faint accent to a soft dark bottom-right — "the thin liquid edge that lifts the glass off the landscape." |
| **6** | **Rim stroke, secondary shade** | `strokeBorder`, `LinearGradient`, diagonal, `lineWidth 1.6`, `blur(0.35)`, **`.multiply`** blend | Colors: `.clear` → `shadow@(isBrightArtwork ? 0.34 : 0.24)`. A soft duplicate stroke that only darkens the far corner, adding depth without doubling the highlight. |

All of layers 2–6 animate together via `.animation(VPTheme.liquid, value:
settings.albumPalette)` **and** `.animation(VPTheme.liquid, value:
settings.glassTintStrength)` (lines 190-191) — a track change and a user
changing the Liquid Glass strength slider produce the same 1.05s easeInOut
cross-fade, never a hard cut.

**Why the membrane is normal-blended, not soft-light:** the in-code comment
at lines 49-51 states it directly — *"Soft-light was too subtle over bright
desktop content, so a thin normal-blended membrane makes the glass visibly
inherit the cover."* This is the single most load-bearing decision in the
recipe: the difference between glass that merely tints and glass that
unmistakably reads as "this widget is holding the color of the record on it."

### The landscape's own reaction (distinct, much lighter recipe)

`LandscapeBackground.swift` never swaps the photo, but layers three thin
tints on top of it (lines 45-76), always ending in the same fixed dark scrim
for legibility:

1. `LinearGradient` (topTrailing→bottomLeading, **`.overlay`** blend):
   `vibrant@0.24` → `dominant@0.20` → `shadow@0.22`.
2. `RadialGradient` (**`.screen`** blend, center `(0.26, 0.14)`,
   `radius 8→220`): `vibrant@0.24` → `.clear`.
3. Fixed legibility scrim, **no blend mode override** (plain composite):
   `LinearGradient` top→bottom, `black@0.16` → `black@0.28` → `black@0.42` —
   always present regardless of palette, guaranteeing contrast "on ANY
   background" (comment at line 67, citing design_system.md §9).

Also animates via `.animation(VPTheme.liquid, value: settings.albumPalette)`
(line 82) — same 1.05s curve as the glass, so background and widgets always
breathe in sync.

---

## 5. Typography, radii, and motion (`VPTheme`)

All from `Sources/VinylPod/Core/Theme.swift`.

### Radii (`Theme.swift:31-33`)

| Token | Value | Used for |
|---|---:|---|
| `radiusSmall` | `10 pt` | Small controls |
| `radius` | `14 pt` | Standard panel / album-art corner (single cohesion token) |
| `radiusLarge` | `22 pt` | Large containers |

Note actual widget containers often use their own literal radii tuned per
size (Small/Medium = `18`, Regular/Large = `12`, per §7 table) — `VPTheme`'s
radius tokens are the *shared-language* defaults used elsewhere (album art
tiles, menus), not a claim that every widget shell uses exactly `14`.

### Motion (`Theme.swift:36-39`)

| Token | Definition | Intent |
|---|---|---|
| `fade` | `Animation.easeInOut(duration: 0.45)` | Empty ↔ playing transitions, error states, hover reveals — "no spinners." |
| `liquid` | `Animation.easeInOut(duration: 1.05)` | The signature cross-fade for `albumPalette` and `glassTintStrength` changes across glass + landscape + desktop canvas. Long enough to read as "flowing," per the desktop-canvas note: *"applies... so track changes feel like the glass is flowing into the new album mood."* |
| `spring` | `Animation.spring(response: 0.32, dampingFraction: 0.7)` | Snappy interactive motion — button presses, menu open (per `design_system.md`: "Open: scale 0.96→1.0 + opacity 0→1 over `VPTheme.spring`"). |

Bespoke curves layered on top for specific mechanisms (not in `VPTheme` but
following its spirit): Dynamic Island expand/collapse uses
`Animation.spring(response: 0.44, dampingFraction: 0.86, blendDuration:
0.10)` (`DynamicIslandWidget.swift:31`); the desktop vinyl spin is
`Animation.linear(duration: 18.0).repeatForever(autoreverses: false)`
(`DesktopWidgetCanvas.swift:600` — 18s/rev in current source, vs. 11s/rev in
`design_system.md`'s "Desktop animation rules," which has drifted from an
earlier tuning pass); the tonearm drop/lift is `.spring(response: 0.65,
dampingFraction: 0.78)`.

### Fonts (`Theme.swift:42-44`)

```swift
static func title(_ size: CGFloat = 16) -> Font { .system(size: size, weight: .bold) }
static func body(_ size: CGFloat = 12)  -> Font { .system(size: size, weight: .semibold) }
static func caption(_ size: CGFloat = 10) -> Font { .system(size: size, weight: .bold) }
```

All native SF Pro / system sans (`design: .default`), matching
`design_system.md` §3's "Apple standard sans-serif — SF Pro / system font."
Most widget-level title/subtitle text uses inline `.system(size:weight:)`
tuned per widget (§7) rather than these three helpers, which are used more
by menus/settings/status text. The Dynamic Island and its track title/artist
text specifically opt into `design: .rounded`
(`DynamicIslandWidget.swift:203, 335, 343`) — a softer, friendlier register
distinct from the bolder `.default` design used on the floating widgets.

### Color tokens (`Theme.swift:12-27`)

| Token | Value |
|---|---|
| `textPrimary` | `Color.white` |
| `textSecondary` | `white.opacity(0.65)` |
| `textMuted` | `white.opacity(0.40)` |
| `scrim` / `scrimStrong` | `black.opacity(0.35)` / `black.opacity(0.55)` |
| `glassTint` | `white.opacity(0.07)` |
| `glassStroke` | `white.opacity(0.18)` |
| `panel` | `white.opacity(0.08)` |
| `iceAccent` | `Color(red: 0.38, green: 0.78, blue: 0.96)` |
| `accentFallback` | `iceAccent.opacity(0.92)` |

`iceAccent`/`accentFallback` is the color used when adaptive accent is off or
there is no artwork — visually in the same cool-blue family as the
`.iceMountain` palette (§2.2) but defined independently; the two are close
but not numerically identical (`iceAccent` = `#61C7F5`-ish vs
`iceMountain.vibrant` = `#42ADFA`-ish), both intentionally "ice blue."

---

## 6. User-facing style controls

Wired in `Sources/VinylPod/Views/Widget/SettingsMenu.swift` (the "three-dot"
dropdown) and mirrored in `Views/Settings/SettingsWindow.swift`. Backing
state lives in `AppSettings` / `GlassTintStrength` (`Models.swift:119-141`).

### Vinyl Style (radio, `VinylStyle` enum, `Models.swift:111-116`)

| Case | Display name | Effect |
|---|---|---|
| `.vinyl` | "Vinyl" | Large widget renders `VinylDiskView` — a spinning record with the album art on the center label (`LargeGlassWidget.swift:101-104`), spin gated by `isPlaying`. |
| `.image` | "Image" (default) | Flat album-art card, `radius 5`, white `0.10`-opacity stroke, soft drop shadow (`LargeGlassWidget.swift:105-122`). |

SettingsMenu rows: `SettingsMenu.swift:200-206`.

### Liquid Glass strength (radio, `GlassTintStrength` enum,
`Models.swift:119-141`)

| Case | Display name | `multiplier` | Effect |
|---|---|---:|---|
| `.subtle` | "Subtle" | `0.72` | Multiplies `colorMembraneOpacity` / `dominantMembraneOpacity` / bloom opacity in `AdaptiveWidgetGlassBackground` (§4) down — less obvious album tint. |
| `.balanced` | "Balanced" (default) | `1.0` | Baseline recipe as documented in §4. |
| `.vivid` | "Vivid" | `1.28` | Same formulas scaled up — most saturated/obvious glass tint, still clamped by the per-layer `min(..., cap)` ceilings so it can't blow out. |

SettingsMenu rows: `SettingsMenu.swift:212-218`. Every opacity formula in §4
that references `strength` is this multiplier — it is the *only* place
tint strength is applied; it does not touch blur radius, stroke width, or
corner radius.

### Adaptive-accent toggle (`AppSettings.useAdaptiveAccent`,
`Models.swift`/`Core/Services.swift:244-246`)

Not a dropdown radio row directly — surfaced as the **"Appearance"** action
row in the dropdown, whose *title itself* reflects current state
(`SettingsMenu.swift:264-265`):

```swift
private var appearanceRowTitle: String {
    settings.useAdaptiveAccent ? "Appearance — Adaptive" : "Appearance — Custom accent"
}
```

Clicking it opens `SettingsWindowController` rather than toggling inline —
the actual toggle lives in the Settings window. When off, `setAccent(from:)`
and `setAlbumPalette(from:)` both force the ice-blue fallback
(`Core/Services.swift:324-330`, `332-338`) regardless of what the extractor
produced, reverting the whole app to the static `.iceMountain` identity
(§2.2) — the "pure white/translucent-white fallback" promised in
`design_system.md` §2, refined in the shipped build to ice-blue rather than
pure white.

### Now Playing source (informational, not a style control)

The old inert "Music Player Source" radio (Apple Music / Spotify / Safari
Music) in the root `design_system.md`'s dropdown hierarchy has been replaced
by a live, read-only `NowPlayingSourceRow()` plus a "Connect a Browser…"
action (`SettingsMenu.swift:163-174`) — that section of `design_system.md` is
stale; this document supersedes it.

---

## 7. Per-size visual treatment

All five `WindowMode` cases (`Models.swift:55-72`: `.small`, `.normal`
[display name "Medium"], `.regular`, `.large`, `.desktopWidget` [display name
"Desktop"]) share the same glass recipe (§4) and palette (§2.2) but differ in
scale, chrome placement, and content density.

| Mode | Dimensions | Corner radius | Artwork treatment | Controls | Distinctive chrome |
|---|---|---:|---|---|---|
| **Small** | `162×162` | `18 pt` | `98×98`, radius `7`, offset `(11, 7)` | Bottom 42pt glass strip: title (12pt bold) + prev/play/next icons (18–24pt) | In-art close button (top-left, always visible, 15pt); settings ellipsis top-right (18pt, opaque `black@0.82` — the only widget with an opaque, not glass-tinted, trigger). |
| **Medium** (`.normal`) | `344×132` | `18 pt` | `100×100`, radius `7`, leading-aligned | Title (17pt heavy) + artist (13pt semibold) + prev/play/next (23–27pt) + optional `MediumProgressStrip` | Text column fixed at `184pt` wide; progress strip is an isolated leaf reading `position` at 1×/sec (perf pattern, see §3 dedup note analog). |
| **Regular** | `300×360` | `12 pt` | Fills entire card, cropped center — no inset margin | Hover-revealed transport row at `y=151` (25–32pt icons, fades via `VPTheme.fade`) | Bottom 86pt gradient caption panel (title 16pt heavy / artist 13pt bold) that darkens more when `brightCover` is true; `artworkTone` overlay adds an extra top-highlight + bottom-vibrant/shadow wash directly onto the artwork itself. |
| **Large** | `320×432` | `12 pt` | Centered `260×260`, offset `y=31`; radius `5` (Image style) or full `VinylDiskView` (Vinyl style, §6) | Title (17pt heavy) / artist (14pt bold) below artwork, prev/play/next (25–31pt), optional `LargeProgressStrip` | Close + settings buttons dim to `0.42` opacity at rest, fade to `1.0` on hover (only widget where **both** chrome buttons are hover-gated, not just the transport row). |
| **Desktop** (`.desktopWidget`) | Full screen (`GeometryReader`-driven) | n/a (full bleed) | Vinyl deck: cover art tilted `-8°` at `28.5%` of width, spinning record layered on top (`recordRotation`, 18s/rev linear), tonearm (`-8°` paused / `10°` playing, spring) | Giant monospaced timer (138pt heavy) top-left, playback block (32pt title / 16pt artist) bottom-left, `DesktopProgressStrip` (1×/sec leaf) | Distinct background recipe (§7.1 below) instead of `AdaptiveWidgetGlassBackground`; own `desktopPopoverBackground` for timer/display popovers (opaque `white@0.90` base + palette tint, for readability over any wallpaper). |

### 7.1 Desktop's distinct background recipe

`DesktopWidgetCanvas.desktopBackground` (`DesktopWidgetCanvas.swift:77-144`)
does **not** reuse `AdaptiveWidgetGlassBackground` — full-screen ambience
needs a different weighting than a floating card. Its stack, bottom to top:

1. Blurred/scaled idle artwork (only if track is empty; `blur(18)`,
   `scale(1.08)`, `black@0.10` overlay) — otherwise skipped so real album art
   shows through the gradients below undimmed.
2. `LinearGradient` (topTrailing→bottomLeading): `vibrant@0.76` (0.62 idle) →
   `muted@0.60` (0.48 idle) → `shadow@0.82` (0.70 idle) — **far higher
   opacities than the floating-widget membrane** (§4's cap was `0.58`);
   full-screen ambience is allowed to be much more saturated since there's no
   underlying content to preserve.
3. Two `RadialGradient` highlights: white glow at `(0.34, 0.20)` and
   `dominant` glow at `(0.48, 0.18)`.
4. `settings.accentColor@(0.24–0.28)` flat fill, `.overlay` blend.
5. `VisualEffectBlur(.hudWindow)` at low opacity (`0.12`–`0.18`) — blur is
   present but a minor contributor here, unlike the floating widgets where
   it's the foundational layer.
6. Final `LinearGradient` overlay-blended wash (`white@0.10` → `vibrant@0.18`
   → `shadow@0.13`) for extra depth.

Same `.animation(VPTheme.liquid, value: settings.albumPalette)` gate
(line 143) as everywhere else.

---

## 8. Dynamic Island's distinct visual treatment

`Sources/VinylPod/Views/Widget/DynamicIslandWidget.swift`. An independent
top-center `NSPanel` (per `design_system.md`: compact `390×30-ish`/expanded
`430×700-ish` in the original spec; current source uses `compactSize =
326×36`, `expandedSize = 402×594`, `expandedPanelSize = 386×536` with `48pt`
top padding — the island has been retuned since that note was written).

**Why it's visually distinct from the four floating widgets, not just a
smaller copy:**

1. **Two bespoke glass structs instead of `AdaptiveWidgetGlassBackground`:**
   `IslandCapsuleGlass` (compact pill) and `IslandPanelGlass` (expanded
   card). Both open with the same `VisualEffectBlur(.hudWindow,
   .behindWindow)` foundation, but the stack is simpler —
   `IslandCapsuleGlass` is 4 layers (blur, diagonal gradient, radial overlay
   bloom, top/bottom screen sheen) vs. 8+ in `AdaptiveWidgetGlassBackground`.
2. **Shape is a `Capsule`**, not a `RoundedRectangle`, for the compact pill —
   the only fully circular-ended glass shape in the app.
3. **A literal notch "bump"** — `DynamicIslandBump`, a custom `Shape` with
   bezier curves forming a rounded trapezoid tab (lines 731-754), rendered
   above the expanded panel only, filled with a top-white → vibrant →
   shadow gradient — visually welding the panel to the menu-bar notch area.
4. **`.rounded` type design** for track title/artist text specifically
   (§5) — softer than the `.default` design used by the floating widgets.
5. **Perf-driven view splitting is more aggressive here than anywhere else.**
   The island is *always mounted* while `dynamicNotch` is on, so the
   top-level body deliberately does **not** observe `NowPlayingService` at
   all (comment, lines 13-21) — every tick-sensitive read is pushed into a
   leaf (`IslandCompactContent`/`IslandExpandedContent` read only
   `track`/`isPlaying`; `IslandTimeRow` is the *sole* view reading raw
   `position`, and even it coarsens to whole-second `Int`s, mirroring the
   `albumPalette` dedup discipline from §3). `EqualizerBars` caps its
   `TimelineView` at 30fps and **pauses entirely** when not playing
   (lines 702-705).
6. **Settings dropdown readability flip:** per `design_system.md`'s "Dynamic
   island and comparative polish pass" note, the island's settings popover
   deliberately uses a **light** adaptive-glass popover (primary ink
   `black@0.82`, hover `black@0.075`) rather than the dark/white-text style
   used elsewhere — explicitly flagged in-repo: *"Do not use white text
   inside this popover."*
7. **Progress fill glow:** `IslandTimeRow`'s progress capsule is the only
   progress bar in the app with an explicit colored `.shadow(color:
   vibrant.opacity(0.30), radius: 5)` glow baked onto the fill (line 517) —
   a small "this is jewelry, not just a status bar" touch consistent with
   the island being the most decorative surface in the app.
