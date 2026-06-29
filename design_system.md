# VinylPod — "Ai Structuer" Design System

> Status: **DRAFT — awaiting founder sign-off**
> Date: 2026-06-28
> Mood: Dark Minimalist · Calm · Static-landscape aesthetic (暗色极简 · 宁静)

---

## Small Size Widget Patch

Reference screenshots: `Screenshot 2026-06-28 at 2.45.02 PM.png`,
`Screenshot 2026-06-28 at 2.44.56 PM.png`, `Screenshot 2026-06-28 at
2.44.48 PM.png`, and `Screenshot 2026-06-28 at 2.45.11 PM.png`.

### Dimensions

| Token | Value |
|---|---:|
| `smallWidgetWidth` | `162 pt` |
| `smallWidgetHeight` | `162 pt` |
| `smallWidgetRadius` | `18 pt` continuous |
| `smallArtworkSize` | `98 pt` |
| `smallArtworkX` | `11 pt` |
| `smallArtworkY` | `7 pt` |
| `smallArtworkRadius` | `7 pt` |
| `innerCloseButton` | `15 pt` circle |
| `innerCloseInset` | `3 pt` from artwork top-left |
| `settingsButton` | `18 pt` circle |
| `settingsTop` | `6 pt` |
| `settingsRight` | `6 pt` |
| `bottomStripHeight` | `42 pt` |

### Colors

| Token | Hex / Opacity | Usage |
|---|---:|---|
| `smallGlassBase` | `#C592AB @ 68%` | main widget tint |
| `smallGlassHotspot` | `#F0A4CF @ 32%` | top-left pink bloom |
| `smallGlassShadow` | `#000000 @ 22%` | soft desktop shadow |
| `smallBottomStrip` | `#362833 @ 46%` | bottom controls strip |
| `smallTextPrimary` | `#FFFFFF @ 92%` | stopped/title text |
| `smallTextSecondary` | `#FFFFFF @ 78%` | subtitle/artist text |
| `smallCloseFill` | `#3E3555 @ 78%` | x button fill |
| `smallCloseStroke` | `#7D86D9 @ 90%` | focused blue close ring |
| `smallDotsFill` | `#111111 @ 82%` | top-right dots circle |

### CSS Equivalent

```css
.small-widget-glass {
  width: 162px;
  height: 162px;
  border-radius: 18px;
  background:
    radial-gradient(circle at 18% 8%, rgba(240,164,207,.32), transparent 42%),
    linear-gradient(135deg, rgba(197,146,171,.72), rgba(151,108,132,.62));
  backdrop-filter: blur(28px) saturate(145%);
  box-shadow: 0 12px 28px rgba(0,0,0,.22), inset 0 1px 1px rgba(255,255,255,.20);
}

.small-widget-art {
  position: absolute;
  left: 11px;
  top: 7px;
  width: 98px;
  height: 98px;
  border-radius: 7px;
}

.small-widget-close {
  position: absolute;
  left: 3px;
  top: 3px;
  width: 15px;
  height: 15px;
}

.small-widget-dots {
  position: absolute;
  right: 6px;
  top: 6px;
  width: 18px;
  height: 18px;
}
```

### Ai Structuer Dropdown Blueprint

Identity:

| Rule | Value |
|---|---|
| Primary Accent Color | `#C592AB` dusty rose |
| Background Mood | Dusty rose glass over warm desktop |
| Typography | SF Pro native sans, 13 pt menu rows, 10 pt muted section labels |

Layout:

| Rule | Value |
|---|---|
| Default Size on Launch | `Small` |
| Panel Shape | Rounded square widget, rounded dropdown page |
| Dropdown Anchor | Top-right, directly below the three-dot icon |
| Dropdown Animation | Smooth page slide down from top edge with opacity |
| Dropdown Z Stack | Outside catcher `zIndex 900`, dropdown `zIndex 2000` |

CSS equivalent:

```css
.settings-dropdown-page {
  width: 230px;
  max-height: 460px;
  border-radius: 14px;
  background: rgba(255,255,255,.72);
  backdrop-filter: blur(30px) saturate(160%);
  box-shadow: 0 18px 32px rgba(0,0,0,.28);
  transform-origin: top right;
  transition: transform .28s cubic-bezier(.16,1,.3,1), opacity .18s ease;
  z-index: 2000;
}

.settings-row:hover {
  background: rgba(255,255,255,.06);
}
```

## 1. Design Philosophy

> **Stunning enough for the visual lover, simple enough for everyone.**
> Quiet by default. The landscape is the soul; the UI is a whisper of glass on top of it.

---

## 2. Color System (色彩系统)

### Background Mood — Dark Minimalist (暗色极简)
- Base mood is **dark**, anchored by a **static high-quality landscape photograph** (default: **ice mountain 冰山**; others e.g. peach blossom 桃花).
- **The background never changes color with the track** — visual stability is a hard rule.

### Accent Color — Adaptive from Album Art (自适应取色 — option B, scoped)
- **Adaptive accent:** A single dominant color is extracted from the **current album art** and applied **only to small accent elements**:
  - Progress bar fill
  - Active / focused buttons
  - Playback highlight
  - Subtle text glow / outline
- **Scope rule (conflict resolution):** The large landscape background **stays static and uncolored**; only the small accents "breathe" with each track. This preserves the calm while giving every song a touch of identity.
- **Fallback:** A **pure white / translucent-white** accent mode is available as a one-tap fallback if adaptive color ever feels too busy.

### Suggested Tokens (to refine in build)
| Token | Value (placeholder) |
|---|---|
| `--bg-overlay` | `rgba(0,0,0,0.35)` scrim over landscape for legibility |
| `--text-primary` | `#FFFFFF` |
| `--text-secondary` | `rgba(255,255,255,0.65)` |
| `--accent` | *dynamic — extracted from album art* |
| `--accent-fallback` | `rgba(255,255,255,0.9)` |

---

## 3. Typography (字体系统)

- **Family:** Apple standard sans-serif — **SF Pro / system font** (Modern Sans-Serif).
- **Rationale:** Maximum legibility over dark + landscape + glass surfaces; native macOS feel.
- **Hierarchy:**
  - Track title — semibold, larger.
  - Artist / album — regular, secondary opacity.
  - Time / metadata — small, tertiary opacity.

---

## 4. Material & Surfaces (材质)

- **Glassmorphism (磨砂玻璃):** Semi-transparent frosted panels (macOS `NSVisualEffectView`-style blur) layered over the landscape to create depth without blocking the view.
- Panels float as light, translucent layers — never opaque solid blocks.

---

## 5. Shape Language (形状)

- **macOS-native rounded rectangles (圆角矩形)** throughout.
- **Consistent corner radius** across all panels and buttons for visual comfort and cohesion. (Single radius token, e.g. `--radius: 12px`, to be finalized.)

---

## 6. Layout & Navigation (布局与导航)

Four shared-language sizes (same shape, different scale & control density):

| Mode | Layout |
|---|---|
| **Small (小)** | Single play/pause button over landscape + blur layer. |
| **Normal (正常)** | Progress bar · track title/artist · play/pause + skip controls. |
| **Large (大)** | Album art · full track metadata · complete control console. |
| **Desktop Widget (桌面部件)** | Fullscreen / desktop-embedded, visual-first. Controls in a **hover-reveal overlay**. Toggle **front / behind all windows**. |

- **Navigation:** Menu bar dropdown (primary) + keyboard shortcuts (secondary). No persistent chrome that clutters the calm.

---

## 7. Motion & States (动效与状态)

| State | Treatment |
|---|---|
| **Empty (空)** | Static landscape only. **No motion, no dynamic elements.** |
| **Loading (载入)** | **Smooth fade-in.** No spinners, no rotation. Preserves immersion. |
| **Mode switch** | Fluid resize/relayout; **never interrupts playback or background visuals**. |
| **Error / Offline (错误)** | Default: silent fade back to landscape. On user click: reveal reason + Retry/Reconnect. |
| **Desktop Widget controls** | Invisible at rest → gently fade/reveal on mouse hover. |

---

## 8. Imagery Rules (背景图规则)

- Ship a default **ice mountain** background.
- All backgrounds: high-quality, calm, static, non-reactive to audio.
- User-uploaded images allowed; apply a consistent dark scrim + blur layer so UI stays legible regardless of uploaded image.

---

## 9. Accessibility & Legibility

- Maintain a dark scrim/overlay between landscape and text to guarantee contrast on any background.
- System font + high-contrast white text ensures readability for the "general listener" persona.

---

*Prepared by your Professional Project Questioner. Pending founder sign-off before any code is written.*

---

# Compact Glass Widget — Extracted from Reference Screenshots (2026-06-28)

## Glassmorphism tokens (native NSVisualEffectView + overlays)
- Material: `.hudWindow` / `.popover`, blendingMode `.behindWindow`, state `.active`.
- Tint over blur: mauve/dark-slate — `rgba(255,255,255,0.06)` lightening + a subtle
  warm-mauve wash `rgba(180,150,170,0.10)` for the player body.
- **Inner 3D border stroke** (the depth cue in the photos): a 1px stroke that is
  brighter at the top (`white @ 0.35`) fading to dark at the bottom (`black @ 0.25`),
  i.e. a top-lit bevel. Implement as an overlay rounded-rect with a linear-gradient stroke.
- Corner radius: container `radiusLarge (22)`; album art `radius (14)`; menus `radius (14)`.
- Drop shadow: `black @ 0.45`, radius ~18, y ~6.

## The 'X' close button (CRITICAL placement)
- Lives INSIDE the album-art square, top-left corner, inset ~8pt.
- Semi-transparent dark circle `black @ 0.45`, ~22pt diameter, `xmark` glyph white @ 0.9.
- Appears on hover over the art (fades in); click opens the Window-behavior popover.

## 'X' → Window-behavior popover (exact items)
```
Window behavior            (header, dimmed)
✓ Above all windows
  Below all windows
  ────────────
  Quit
```
Maps to: DesktopLayer.front (Above) / .back (Below) applied to the live window; Quit = NSApp.terminate.

## Three-dots Settings dropdown (exact hierarchy, top→bottom)
```
You're a Pro               (status row, dimmed)
Music Player Source        (section header)
  Apple Music
  Spotify                  (focus/selected highlight)
✓ Safari Music
  Safari Music Guide
Music Player Size          (section header)
✓ Small
  Medium
  Regular
  Large
  Desktop
  ────────────
✓ Dynamic notch
✓ Show in Menu Bar
Vinyl Style                (section header)
  Vinyl
✓ Image
✓ Show progress
  ────────────
✓ Keep Window in Front
  Launch at Login
✓ Show Artwork in Dock
✓ Hide Dock Icon
  Cover art as wallpaper
  Hide notch in fullscreen
  ────────────
  Keyboard shortcuts
  Appearance
  ────────────
  Rate us
  Share our app            (share glyph)
  About
  ────────────
  Quit
```
Section headers: `VPTheme.caption()` dimmed, uppercased-ish, non-interactive.
Checkable rows: leading checkmark column (✓ when on); hover highlight `white @ 0.06`.
Radio groups: Music Player Source, Music Player Size, Vinyl Style (single selection).
Toggles: Dynamic notch, Show in Menu Bar, Show progress, Keep Window in Front,
Launch at Login, Show Artwork in Dock, Hide Dock Icon, Cover art as wallpaper,
Hide notch in fullscreen.
Actions: Keyboard shortcuts, Appearance, Rate us, Share our app, About, Quit.

## Menu motion (default chosen)
Open: scale 0.96→1.0 + opacity 0→1 over `VPTheme.spring`, anchored to trigger.
Dismiss on outside-click / Esc with a quick `VPTheme.fade`.

---

# Medium Widget Readability Patch (2026-06-28)

## Medium widget dimensions
- Window mode label: `Medium` (code enum remains `normal` for compatibility).
- Default medium size: `344 x 132`.
- Container radius: `18`.
- Album art: `100 x 100`, radius `7`, placed left with 18pt leading padding.
- Top-right settings trigger: 18pt black circular ellipsis, 9pt glyph, inset 9pt from top/right.
- Text area: 184pt wide, strong white title with subtle black shadow for visibility.

## Readable popover menu palette
- Popover panel fill: white/frosted material with an extra white wash `white @ 0.78-0.80`.
- Primary menu text: `black @ 0.86`.
- Secondary menu text: `black @ 0.48`.
- Muted section/header text: `black @ 0.34-0.46`.
- Hover row fill: `black @ 0.07`.
- Divider: `black @ 0.12`.

## Interaction decision
- Three-dot menu uses native SwiftUI `.popover` so it is not clipped by the widget window and remains clickable.
- X/window-behavior menu also uses native SwiftUI `.popover` so the options can appear outside the album-art bounds.

---

# Regular Widget Build (2026-06-28)

## Visual extraction
- Reference scale: `300 x 360` floating card, seen on desktop as a compact tall album widget.
- Card radius: `12 pt`, noticeably less rounded than Small/Medium but still soft.
- X button: `15 pt` dark circle, 7pt inset from the top-left edge, always visible.
- Three-dot settings: `18 pt` black circle, 9pt top/right inset, anchored to the regular settings popover.
- Artwork: fills the entire card, cropped center, with mauve-pink sky and violet lower wash.
- Controls: white previous/play/next icons floating over the artwork around `y = 151`.
- Caption: bottom 86pt gradient panel, centered title/subtitle, strong white text.

## Regular CSS equivalent
```css
.regular-widget {
  width: 300px;
  height: 360px;
  border-radius: 12px;
  overflow: hidden;
  background: rgba(197, 146, 171, .72);
  backdrop-filter: blur(28px) saturate(145%);
  box-shadow:
    0 10px 18px rgba(0,0,0,.22),
    inset 0 1px 1px rgba(255,255,255,.12);
}

.regular-bottom-caption {
  height: 86px;
  background: linear-gradient(
    to bottom,
    transparent,
    rgba(128,64,125,.74),
    rgba(120,61,120,.88)
  );
}
```

---

# Large Widget Build (2026-06-28)

## Visual extraction
- Reference scale: `320 x 432` floating card on a full desktop screenshot.
- Card radius: `12 pt`; same rounded family as Regular, larger vertical body.
- Main artwork: centered `260 x 260`, top offset `31 pt`, radius `5 pt`.
- X button: `15 pt` dark circle, card top-left inset `8 pt`, shown on hover / while interacting.
- Three-dot settings: `18 pt` black circle, card top-right inset `9 pt`.
- Typography: title `17 pt heavy`, subtitle `14 pt bold`, centered and white.
- Playback controls: centered previous/play/next with 28pt spacing.
- Progress: bottom row with 10pt bold time labels and 198pt capsule track.

## Large CSS equivalent
```css
.large-widget {
  width: 320px;
  height: 432px;
  border-radius: 12px;
  background:
    radial-gradient(circle at 72% 6%, rgba(255,171,219,.28), transparent 48%),
    linear-gradient(135deg, rgba(209,143,184,.82), rgba(150,89,145,.88));
  backdrop-filter: blur(28px) saturate(145%);
  box-shadow:
    0 10px 18px rgba(0,0,0,.22),
    inset 0 1px 1px rgba(255,255,255,.12);
}

.large-artwork {
  width: 260px;
  height: 260px;
  margin-top: 31px;
  border-radius: 5px;
}
```

---

# Desktop Widget Build (2026-06-28)

## Visual extraction
- Full-screen surface: mauve/pink glass gradient with darker plum lower-left and soft white bloom.
- Top-left desktop chrome: four small white controls in one row: close, time, display, settings dots.
- Timer: giant white monospaced time at upper-left; countdown mode shows a smaller seconds suffix.
- Timer menu: small white ellipsis near timer top-right, popover rows `Time`, `Countdown`, `Countdown Settings`.
- Countdown editor: white rounded input with large minute number and gray `mins` suffix.
- Music block: bottom-left title/subtitle, white controls, thin progress rail.
- Vinyl composition: tilted album art, large black record with concentric groove rings, tonearm on right.
- Tonearm themes: black and white, toggled by clicking the tonearm.

## Desktop animation rules
- Vinyl record spins only when `isPlaying == true`; the SwiftUI rotation uses a slow linear repeat animation around `11s/rev`.
- Vinyl record stops when playback pauses.
- Tonearm uses a spring rotation: lifted when paused, dropped when playing.
- Timer uses `TimelineView(.periodic(..., by: 1))` for countdown updates.

## Desktop CSS equivalent
```css
.desktop-widget {
  width: 100vw;
  height: 100vh;
  background:
    radial-gradient(circle at 34% 20%, rgba(255,255,255,.25), transparent 45%),
    radial-gradient(circle at 48% 18%, rgba(117,48,120,.42), transparent 40%),
    linear-gradient(135deg, #DB8FC2, #BD6BAD, #8C4587);
}

@keyframes vinyl-spin {
  to { transform: rotate(360deg); }
}

.vinyl-record.is-playing {
  animation: vinyl-spin 11s linear infinite;
}

.tonearm {
  transform-origin: top center;
  transition: transform .65s cubic-bezier(.22, 1, .36, 1);
}

.tonearm.is-playing {
  transform: rotate(7deg);
}

.tonearm.is-paused {
  transform: rotate(-11deg);
}
```

## Desktop widget refinement pass (2026-06-28 evening)
- Desktop mode is a fixed screen canvas, not a draggable card: `isMovable = false`, `isMovableByWindowBackground = false`.
- Desktop mode uses only two layer choices: front status-window level or back desktop-window level.
- Desktop mode no longer uses `canJoinAllSpaces`; it stays on the current screen/Space instead of following every desktop.
- Timer ellipsis is an independent top layer anchored near the top-right edge of the time, not inside the `TimelineView` text row.
- Timer menu must be intrinsically sized with `fixedSize(vertical: true)` so rows do not stretch into a tall broken panel.
- Countdown settings is a focused editor state: while open, the giant timer and timer ellipsis fade out so the white input panel never overlaps the numerals.
- Liquid glass background = mauve vinyl gradient + `hudWindow` blur + album-accent soft-light overlay at roughly 14% opacity.
- Vinyl deck placement: record is balanced with the album cover visible behind it, not cropped into the right edge.
- Vinyl record label is intentionally large so the album art is readable at desktop scale.
- Groove treatment uses two layers: subtle white highlight rings plus darker physical grooves for a real pressed-record texture.

## Floating widget adaptive glass pass
- Difference observed against VinyIpod reference: the old VinylPod widgets used a fixed mauve/purple gradient; VinyIpod uses neutral frosted glass that changes subtly with album artwork.
- New rule: floating widgets start from macOS `hudWindow` blur, then apply `settings.albumPalette` as soft-light album refraction around 22-24% opacity.
- Blue album art should produce blue-gray glass; monochrome album art should produce neutral gray glass; warm album art should produce cream/tan glass.
- Avoid solid color fills: the desktop wallpaper must remain visible through the card.

## Ai Structuer liquid-glass lock (2026-06-29)
- Primary accent color: album-derived vibrant color; fallback `#5CCEF5` ice blue when artwork is missing.
- Background mood: custom `Album-reactive liquid glass` over a calm image base.
- Typography: Sans (modern), native Apple SF Pro-like system sans.
- Default size on launch: keep persisted user choice; default code path remains `Small` unless preferences choose another size.
- Panel shape: rounded glass cards for widgets, pill for dynamic island compact state.
- Where on screen: free placement for normal widgets; top-center for dynamic island.

## Dynamic color engine
- Extractor: `ArtworkColorExtractor.paletteOffMain(from:)` uses CoreImage `CIAreaAverage` for dominant color.
- Vibrant color: CoreImage renders a `52px` sample grid; pixels are saturation-weighted so colorful album regions drive controls/progress.
- Muted color: the same sample grid weights lower-chroma pixels for frosted fill and glass body tone.
- Shadow color: a darkened dominant color creates depth without adding a static black wash.
- Animation: `AppSettings.setAlbumPalette(from:)` applies `VPTheme.liquid = easeInOut(1.05s)` so track changes feel like the glass is flowing into the new album mood.
- SwiftUI application: `AdaptiveWidgetGlassBackground` and `DesktopWidgetCanvas` read `settings.albumPalette`; reusable modifier is `View.liquidAlbumGlass(...)`.
- Visibility rule: album color must be obvious, not theoretical. Blue album art should make glass/background read blue, so the surface includes a normal-blended album color membrane before the frost layer. `softLight` alone is not enough over bright desktop content.

---

## Dynamic island and comparative polish pass
- Dynamic island: independent top-center `NSPanel`, compact size `390x30`, expanded card size `430x700`, anchored to the main screen's top midpoint. The panel is non-draggable and resizes between compact/expanded states so transparent regions do not block clicks.
- Settings menu label is `Dynamic island` and is wired to `settings.dynamicNotch`; toggling it creates/removes the top-center island panel.
- Island visual language: smoky `hudWindow` blur, `Color.black.opacity(0.21-0.30)`, album-accent soft-light tint at roughly `16-18%`, white stroke at `22-24%`, and a top-center notch bump.
- Island typography: native Apple SF Pro-like sans, title `32pt semibold`, artist/status `24pt bold`, compact pill title `16pt semibold`.
- Settings visibility: default ellipsis trigger is now a dark circular control (`black 48-58%`) with white glyph (`92-100%`) so it remains visible on pink, gray, bright, or busy cover art.
- Settings dropdown: width `242`, max height `760`, light adaptive glass for readability over bright desktops. Primary ink `black 82%`, secondary `black 60%`, muted headers `black 42%`, hover fill `black 7.5%`, dividers `black 13%`, checkmarks use album vibrant color. Do not use white text inside this popover.
- Progress placement: large widget title/control/progress cluster is shifted upward by reducing the top spacer from `302` to `292`, title-control gap from `20` to `16`, and control-progress gap from `12` to `6`.
- Idle artwork/background: when no song is playing, use the uploaded file `majestic-ice-mountain-stockcake.jpg` as a packaged SwiftPM resource. Do not recreate it procedurally unless the resource fails to load.
- Liquid glass recommendation implemented: blur first, then neutral dark depth, then album/ice color soft-light refraction, then white specular streak and bottom inner shadow. This should feel like glass absorbing nearby color, not a flat purple overlay.

---

## Keyboard Shortcuts window (from reference screenshot)

Native titled NSWindow ("Keyboard shortcuts", dark), ~546×458. Three grouped
blocks of rows; each row = right-aligned action label (~150pt column, secondary
white) + a gray "Record Shortcut" pill (`white @ 12%` fill, ~12pt text).
Groups: [Play/pause, Next track, Previous track, Open player] · [Toggle notch
open, Toggle menu bar visibility, Toggle popover] · [Widget size, Display in
fullscreen, Window top/bottom]. Recording shows the live combo as ⌃⌥⇧⌘+key; a
trailing ✕ clears. Global firing via Carbon RegisterEventHotKey (no Accessibility
permission). Persisted in UserDefaults key `keyboardShortcuts` (JSON).
