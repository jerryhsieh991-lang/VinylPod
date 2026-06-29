# VinylPod — Liquid Glass Design System

> Extracted 1:1 from the 19 reference screenshots in `ui foldoer/`.
> Target: **SwiftUI · macOS 26 (Tahoe) · native Liquid Glass** (`.glassEffect`), with
> `.ultraThinMaterial` fallback for `< macOS 26`.
> Palette is **adaptive** — tinted from the current album artwork; the values below are
> the lavender/magenta *fallback* identity seen in the screenshots (pink‑tree cover).

---

## 1. Color & Background Mood

### 1.1 Wallpaper (artwork‑derived backdrop)
The whole window sits on the **blurred, edge‑stretched album cover** ("Cover art as wallpaper").
For the reference cover it reads as a top‑left→bottom‑right lavender→magenta wash:

| Token | Hex | Use |
|---|---|---|
| `wallpaperTop` | `#C7A4D0` | top‑left of backdrop |
| `wallpaperMid` | `#B07CA0` | center mass |
| `wallpaperBottom` | `#8F5E80` | bottom‑right, dusty rose |
| `wallpaperStoppedTop` | `#B98FB0` | flat fallback when music stopped (top) |
| `wallpaperStoppedBottom` | `#8A5F7C` | flat fallback when stopped (bottom) |

Backdrop = artwork scaled to fill → `.blur(radius: 60)` → 1.15× zoom → dim overlay `black @ 8%`.

### 1.2 Liquid Glass panel
Regular Liquid Glass over the wallpaper. Approximated tokens for the fallback path:

| Token | Value | Use |
|---|---|---|
| `glassTint` | `white @ 14%` | panel fill base |
| `glassTopHighlight` | `white @ 28% → 0%` (top→40%) | specular top sheen |
| `glassRim` | `white @ 22%` | 0.75 pt inner stroke |
| `glassShadow` | `black @ 28%`, radius 30, y 14 | floating drop shadow |
| `glassControlTint` | `white @ 18%` | circular button glass |

Implementation: `.glassEffect(.regular, in: .rect(cornerRadius: r))` (macOS 26+);
fallback `.background(.ultraThinMaterial)` + tint + rim + highlight.

### 1.3 Text
| Token | Hex / Opacity | Use |
|---|---|---|
| `textPrimary` | `#FFFFFF` | titles, glyphs, clock numerals |
| `textSecondary` | `#FFFFFF @ 70%` | subtitle "Please play music on…" |
| `textTimestamp` | `#FFFFFF @ 80%` | `00:00` / `-00:00` |
| `textOnLight` | `#1C1C1E` | numerals inside white countdown picker |
| `textMutedOnLight` | `#8E8E93` | "mins" label in picker |

### 1.4 Vinyl
| Token | Hex | Use |
|---|---|---|
| `vinylBlack` | `#0C0C0E` | record body |
| `vinylGroove` | `#1A1A1D` | concentric groove rings (1 pt @ 35%) |
| `vinylSheen` | `white @ 6%` | rotating angular highlight |
| `tonearmWhite` | `#F4F4F6` | white tonearm + pivot |
| `tonearmBlack` | `#141416` | black tonearm variant |
| `tonearmShadow` | `black @ 30%` | arm cast shadow |

---

## 2. Typography

System font (SF Pro). No serif (the old gold theme used serif — the new lavender theme is **all SF Pro**, matching the screenshots).

| Style | Spec | Used for |
|---|---|---|
| `clockDisplay` | SF Pro **Bold**, size 120–160, `.rounded` not used — flat SF, tight tracking | giant `14:11` / `10:00` |
| `cardTitle` | SF Pro **Bold** 22 | "Music is stopped." |
| `cardTitleWide` | SF Pro **Bold** 20 | wide‑layout title |
| `cardSubtitle` | SF Pro **Regular** 14 | "Please play music on Spotify or Music" |
| `sourceTag` | SF Pro **Semibold** 9, tracking 0.8, uppercased | source chip |
| `timestamp` | SF Pro **Medium** 11, `.monospacedDigit` | scrubber times |
| `pickerNumber` | SF Pro **Semibold** 64 | "10" in countdown picker |
| `pickerUnit` | SF Pro **Semibold** 40, secondary | "mins" |
| `menuRow` | SF Pro **Regular** 13 | settings menu items |
| `menuSectionHeader` | SF Pro **Semibold** 11, secondary | "Music Player Source" etc. |

---

## 3. Layout, Dimensions & Shapes

### 3.1 Player card sizes (the "Size" menu: Small / Medium / Regular / Large)
| Size | Card W × H (vertical) | Art | Corner |
|---|---|---|---|
| Small | 220 × 270 | 188 sq | 18 |
| Medium | 260 × 320 | 224 sq | 20 |
| **Regular** (default) | 300 × 380 | 260 sq | 22 |
| Large | 360 × 450 | 312 sq | 24 |
| Wide | 420 × 180 | 120 sq (left) | 22 |

- **Card padding:** 18 (Small) → 22 (Regular) → 26 (Large), uniform inset.
- **Continuous** corners everywhere (`.rect(cornerRadius:, style: .continuous)`).
- **Vertical layout:** art (top) → gap 16 → title → gap 4 → subtitle → gap 18 → transport → gap 14 → scrubber.
- **Wide layout:** art (left) → 18 gap → right column {title, subtitle, transport, scrubber} right‑aligned.

### 3.2 Top chrome
- Close `✕` (top‑left) and overflow `•••` (top‑right): **28 pt** clear‑glass circles, inset 12 from card edges, glyph 11 pt `white @ 80%`. Appear on hover.

### 3.3 Transport row
- Prev / Play / Next, centered, spacing **22**.
- Play = filled glass circle **56 pt** (Regular), glyph 20. Prev/Next = clear, glyph 18.
- Glyphs: `backward.fill` / `play.fill`|`pause.fill` / `forward.fill`, white.

### 3.4 Scrubber
- Track height **3 pt**, full‑round. Filled portion `white @ 90%`, remainder `white @ 25%`.
- Leading dot/thumb 7 pt (grows to 11 on drag).
- `00:00` left, `-00:00` right, 8 pt below, timestamp style.

### 3.5 Vinyl desktop mode
- Disc diameter = min(window) − 80. Center label (artwork circle) = 38% of disc.
- Spindle hole 8 pt at center.
- Tonearm: pivot puck top‑right (≈64 pt), arm length ≈ 0.62× disc, head at ≈ 7–8 o'clock when playing, lifted ≈ 30° when paused.

### 3.6 Clock / Countdown
- Clock numerals fill ~70% of window height, centered, `white`.
- Countdown timer screen: numerals centered, **reset** (`arrow.counterclockwise`) + **play** (`play.fill`) as 34 pt clear‑glass circles below, spacing 28.
- Countdown picker card: **white** rounded‑28 panel, "Countdown time" label top‑left (white, on lavender), big number left + unit right, close `✕` top‑right.

### 3.7 Dynamic Notch
- Collapsed: pill **≈180 × 32** hugging the top‑center notch, `black @ 88%` (not glass — reads as the hardware notch), art thumbnail 22 + scrolling title.
- Expanded (hover/track change): **≈340 × 110**, art 78 + title/artist + mini transport. Spring `response 0.4, damping 0.8`.

---

## 4. Controls & States

| Control | Rest | Hover | Pressed |
|---|---|---|---|
| Glass circle button | clear glass, glyph @ 80% | brighten tint +6%, scale 1.08, glyph 100% | scale 0.94 |
| Play (filled) | `glassControlTint`+accent rim | glow ring (accent @ 40%), scale 1.06 | scale 0.95 |
| Menu row | transparent | `white @ 8%` fill, full‑width | — |
| Scrubber thumb | 7 pt | — | 11 pt on drag |
| Close / overflow | hidden | fade in over 0.18s | scale 0.9 |
| Vinyl | spinning when playing | — | eases to stop on pause (0.8s) |

**Spring vocabulary:** buttons `spring(response: 0.28, damping: 0.65)`; mode/notch transitions `spring(response: 0.4, damping: 0.82)`; cross‑fades `easeInOut(0.35)`.

---

## 5. Motion

| Animation | Spec |
|---|---|
| Vinyl spin | continuous 360° / 1.8s linear while `isPlaying`; decelerate to rest on pause |
| Tonearm | swing onto disc on play / lift on pause, `spring(0.5, 0.8)` |
| Notch | collapse↔expand spring `0.4 / 0.82` |
| Theme re‑tint | accent + wallpaper cross‑fade `easeInOut 0.5` on track change |
| Art change | cross‑fade `easeInOut 0.35` + subtle scale 1.03→1.0 |
| Play/Pause glyph | `.contentTransition(.symbolEffect(.replace))` |

---

## 6. Window / Scene behavior

- **Floating player:** borderless, `.level = .floating` when "Keep Window in Front", draggable by background, transparent titlebar, shadowless system chrome (glass provides shadow).
- **Remember last used** mode + size via `@AppStorage` (`lastMode`, `windowSize`); first run → Floating · Regular.
- **Menu‑bar item:** `opticaldisc` symbol + optional "• Music is stopped." title; popover mini‑player.
- **Automation:** auto‑collapse to notch on idle; expand on play; auto re‑tint on track change; Focus/Pomodoro auto‑pause; auto‑hide when cursor away / another app fullscreen.

---

## 7. Component inventory (files to build under `VinylPod/Views/`)

1. `DesignSystem.swift` — lavender/glass tokens, `GlassBackground`, `LiquidGlass` modifier, `GlassCircleButton`, `ArtworkBackdrop`.
2. `PlayerCardView.swift` — vertical + wide glass card, all sizes, stopped/playing states.
3. `PlayerControls.swift` — transport row + scrubber.
4. `VinylDiskView.swift` — record + grooves + spin + tonearm.
5. `ClockView.swift` / `CountdownView.swift` — clock, timer, picker.
6. `DynamicNotchView.swift` — collapsed/expanded notch.
7. `SettingsMenuView.swift` — the dropdown menu contents.
8. `ProPaywallView.swift` — Pro upsell.
9. `ContentView.swift` — mode host/switcher.
10. `Windows.swift` — `PlayerWindow`, `FloatingPlayerWindow`, `PaywallWindow`.
11. `AppSettings.swift` (App/) — extended settings model.
12. `VinylPodApp.swift` (App/) — scene, MenuBarExtra, remember‑last‑used, automation hooks.
