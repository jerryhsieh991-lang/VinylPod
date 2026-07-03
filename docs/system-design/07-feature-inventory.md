# 07 — Feature & Settings Inventory

A complete, current census of every user-facing control in VinylPod: the
three-dot dropdown, the tabbed Settings window (⌘,), and all keyboard
shortcuts — cross-referenced against `AppSettings` (`Sources/VinylPod/Core/Services.swift`)
and the OS-effect audit in `Sources/VinylPod/App/SettingsEffects.swift`.

Status tags used throughout:
- **[WORKING]** — has a real, verifiable OS/UI effect.
- **[EXPERIMENTAL]** — real effect, but explicitly best-effort / may no-op (documented in source).
- **[INERT — reason]** — no effect; cited to source comment or code inspection.
- **[PLACEHOLDER]** — UI exists but wiring is stubbed/unreachable.

---

## 1. Three-dot dropdown (`SettingsMenuButton`, `Sources/VinylPod/Views/Widget/SettingsMenu.swift`)

Rows in exact top-to-bottom order as rendered by `menuContent`:

| # | Row | Effect | `AppSettings` property | Status |
|---|-----|--------|------------------------|--------|
| 1 | **"You're a Pro"** | Static label, `.allowsHitTesting(false)` | none | **[PLACEHOLDER]** — no purchase/entitlement system exists anywhere in the codebase; this is a hardcoded, non-interactive claim. |
| 2 | **Now Playing From** (section header + `NowPlayingSourceRow`) | Live leaf view reading `NowPlayingService.track` / `.bridgeConnected` (never `.position`, by design comment). Shows one of three real states: playing (source icon + name + artist), connected-but-idle, or not-connected. | Reads `NowPlayingService`, not `AppSettings` | **[WORKING]** — genuinely reflects live capture state; replaced an old static source radio that changed nothing (see code comment at line 163). |
| 3 | **Connect a Browser…** | Opens `https://vinylpod.app/connect` via `NSWorkspace` | none (external link) | **[WORKING]** as a link-opener, contingent on that URL being live (unverifiable from source). |
| 4 | **Music Player Size** (5 radio rows) | Sets `settings.windowMode`, closes menu, calls `onSelectSize(mode)` after a 40 ms delay | `windowMode: WindowMode` | **[WORKING]** — drives `WindowCoordinator`/`WindowManager` resize; persisted to `UserDefaults`. The 5 modes are **Small, Medium ("normal"), Regular, Large, Desktop** (`WindowMode.small/.normal/.regular/.large/.desktopWidget`) — note the task description says "5 modes," matching. |
| 5 | **Dynamic Island** toggle | Toggles `settings.dynamicNotch`; setter calls `WindowCoordinator.shared.manager?.syncDynamicIsland()` | `dynamicNotch: Bool` | **[WORKING]** — owned by `WindowManager`, per `SettingsEffects.swift`'s own audit comment (line 110). |
| 6 | **Show in Menu Bar** toggle | Toggles `settings.showInMenuBar`, bound directly to `MenuBarExtra(isInserted:)` in `VinylPodApp.swift` | `showInMenuBar: Bool` | **[WORKING]** — also feeds `SettingsEffects.applyDockPolicy()` (Dock icon only hidden when *both* this is on and `hideDockIcon` is on, guaranteeing one entry point always survives). |
| 7 | **Vinyl Style** — Vinyl / Image (2 radio rows) | Sets `settings.vinylStyle` | `vinylStyle: VinylStyle` | **[WORKING]** — consumed by the widget rendering layer (spinning vinyl vs. flat art card). |
| 8 | **Show progress** toggle | Toggles `settings.showProgress` | `showProgress: Bool` | **[WORKING]** — persisted; gates the progress bar in the widget UI (not traced line-by-line here, but the property is read downstream per its naming and persistence wiring). |
| 9 | **Liquid Glass** — Subtle / Balanced / Vivid (3 radio rows) | Sets `settings.glassTintStrength` | `glassTintStrength: GlassTintStrength` | **[WORKING]** — `GlassTintStrength.multiplier` (0.72 / 1.0 / 1.28) scales the album-color tint intensity on the glass surfaces. |
| 10 | **"Appearance — Adaptive" / "Appearance — Custom accent"** (dynamic label) | Opens the full Settings window via `SettingsWindowController.shared.show()` | Reads `settings.useAdaptiveAccent` for its label only | **[WORKING]** as a navigation row; the label itself is a nice touch (reflects live state) but the row does not let you toggle adaptive accent directly — you land on the Settings window's Appearance tab equivalent, which currently only shows a **placeholder** (see §2.2). |
| 11 | **Open Settings…** | Opens the same Settings window | none directly | **[WORKING]** navigation, but duplicates row 10's destination — two rows go to the same place. Minor UX redundancy, not a bug. |
| 12 | **Rate us** | Opens `VinylPodLinks.appStoreURL` (`https://apps.apple.com/app/vinylpod`) | none | **[PLACEHOLDER]** — the URL constant's own doc comment says "Replace the bundle id / slug with the real one at submission time," i.e. this is a known-fake placeholder URL, not a real App Store listing. |
| 13 | **Share our app** | Copies `VinylPodLinks.websiteURL` (`https://vinylpod.app`) to the pasteboard | none | **[WORKING]** as a clipboard action (no visible confirmation toast, but the copy itself succeeds); site's liveness is unverifiable from source. |
| 14 | **Quit** | Closes menu, calls `onQuit()` → `NSApp.terminate(nil)` | none | **[WORKING]**. |

Rows explicitly **removed** from this dropdown and relocated to the Settings
window (per the comment block at lines 220–227): Launch at Login, Show
Artwork in Dock, Hide Dock Icon, Cover art as wallpaper, Hide notch in
fullscreen, Keep Window in Front, About, Keyboard shortcuts. This was a
deliberate declutter, not a regression.

---

## 2. Settings window (⌘,) — `SettingsWindow.swift` + section files

The window is a 520×460 `TabView` with 5 tabs: **General, Appearance,
Sources, Shortcuts, About** (`SettingsTab` enum). This is the single most
important finding of this audit — **the tab-content wiring does not match
the section files that exist on disk.**

### Critical finding: two tabs render inline placeholders instead of the real section views

`SettingsWindow.swift` defines its own **private** `AppearanceSettingsTab`
and `SourcesSettingsTab` structs (lines 87–189) with explicit code comments
reading:

> `// INTEGRATION POINT: AppearanceSettingsSection(settings: settings)`
> `// Another agent delivers the accent-color / adaptive-accent editor.`
> `// Do NOT reference the type here — it does not exist yet.`

and

> `// INTEGRATION POINT: CaptureSettingsSection(settings:) + LastFmSettingsSection() + BrowserOnboardingView(nowPlaying:)`
> `// Other agents deliver capture configuration, Last.fm scrobbling,`
> `// and the browser-onboarding flow. Do NOT reference those types`
> `// here — they do not exist yet.`

**This is stale.** All three referenced types — `AppearanceSettingsSection.swift`,
`CaptureSettingsSection.swift`, and `LastFmSettingsSection.swift` — **do
exist** on disk, fully implemented, in the same directory
(`Sources/VinylPod/Views/Settings/`). They were built by "another agent" as
the comments anticipated, but `SettingsWindow.swift` was never updated to
actually reference them. The result: three complete, working settings
sections are compiled into the app binary but are **unreachable from any
UI path** — dead code that looks alive.

Only 2 of 5 section files are actually wired into the tab switch:
`GeneralSettingsSection` (General tab) and `AboutSettingsSection` (About
tab). The other 3 are orphaned.

### 2.1 General tab — `GeneralSettingsSection.swift` — **WIRED, [WORKING]**

| Control | `AppSettings` property | Status |
|---|---|---|
| "Show in Menu Bar" toggle | `showInMenuBar` | [WORKING] — same property as dropdown row 6. |
| "Hide Dock icon" toggle | `hideDockIcon` | [WORKING] — drives `SettingsEffects.applyDockPolicy()`; explanatory caption about always keeping one entry point. |
| "Keep window in front" toggle | `keepWindowInFront` | [WORKING] — `.onChange` calls `WindowCoordinator.shared.manager?.applyStacking(...)` directly (native `NSWindowLevel`, not z-index). |
| "Dynamic Island notch" toggle | `dynamicNotch` | [WORKING] — same property/effect as dropdown row 5. |
| "Launch at Login" toggle | `launchAtLogin` | [WORKING] — `SettingsEffects.applyLaunchAtLogin()` calls `SMAppService.mainApp.register()/.unregister()`. |

### 2.2 Appearance tab — inline placeholder — **[PLACEHOLDER]**, real section orphaned

What actually renders (`AppearanceSettingsTab`, inline in `SettingsWindow.swift`):
- A static "Accent & Palette" text block reading "Accent-color controls
  appear here." — **[PLACEHOLDER]**, no controls at all.
- "Widget Look" group: Vinyl style segmented picker (`vinylStyle`) and
  Liquid Glass segmented picker (`glassTintStrength`) — **[WORKING]**,
  duplicates dropdown rows 7 and 9 exactly.
- "Artwork" group: 3 toggles — `showArtworkInDock`, `coverArtAsWallpaper`,
  `hideNotchInFullscreen` — see §4 for per-toggle effect status; these are
  real properties correctly bound, just not exposed anywhere else in the UI.

What is **never shown** because `AppearanceSettingsSection.swift` is
orphaned: a fully-built adaptive-accent toggle (`useAdaptiveAccent`), a
`ColorPicker` bound to `accentColor` with 6 preset swatches, and a custom
background image chooser (`customBackgroundURL`) with an `NSOpenPanel` and
a "Clear" action. All of this is dead, unreachable code.

### 2.3 Sources tab — inline placeholder — **[PLACEHOLDER]**, real sections orphaned

What actually renders (`SourcesSettingsTab`, inline): a read-only
"Configured Source" card showing `settings.musicSource` (icon + display
name + "Read-only" label) and a "Connect a Browser…" button (same
destination as dropdown row 3) — **[WORKING]** as a read-only display, but
note `musicSource` itself is a stale, uncorrelated property (see §4 —
BrowserBridge ignores it as a capture filter per the dropdown's own code
comment). Below that: a static placeholder block reading "Capture
configuration, Last.fm scrobbling, and browser onboarding appear here."

What is **never shown**: `CaptureSettingsSection.swift`'s full native
desktop-app capture UI (toggle for `nativeCaptureEnabled` with a 1 Hz-polled
live status indicator distinguishing "off" / "on, no data yet" / "on,
receiving data" — carefully decoupled from the playback tick) and
`LastFmSettingsSection.swift`'s complete Last.fm OAuth-style connect flow
(enable toggle bound to `LastFmScrobbler.shared.enabled`, a 3-phase
connect/authorize/complete handshake against `LastFmClient.shared`, and a
disconnect action). Both are fully implemented, both are unreachable.

### 2.4 Shortcuts tab — `KeyboardShortcutsView` — **[WORKING]**

Embeds the existing (unchanged, pre-dropdown-declutter)
`KeyboardShortcutsView`, bound to `AppEnvironment.shared.shortcuts`
(`ShortcutStore`). This is the editor for the 10 global `ShortcutAction`
bindings — see §3.2. Not read in full per the task's read list, but its
wiring point is confirmed live.

### 2.5 About tab — `AboutSettingsSection.swift` — **WIRED, [WORKING]**

App icon, name/version (from `Bundle.main` Info.plist keys), "Rate us" and
"Share our app" buttons (same two actions/URLs as dropdown rows 12–13,
duplicated), and static credit text. Fully self-contained, stateless, no
`AppSettings` dependency. **[WORKING]**, modulo the same fake App-Store URL
caveat noted in row 12.

---

## 3. Keyboard shortcuts

### 3.1 Local ⌘-digit monitor (`VinylPodApp.swift`, `installModeShortcuts()`)

A **local** (in-app-focus-only) `NSEvent` key-down monitor, not a system
hotkey — requires exactly the Command modifier alone:

| Shortcut | Action | Status |
|---|---|---|
| ⌘1 | `WindowMode.small` ("Small") | [WORKING] |
| ⌘2 | `WindowMode.normal` ("Medium") | [WORKING] |
| ⌘3 | `WindowMode.regular` ("Regular") | [WORKING] |
| ⌘4 | `WindowMode.large` ("Large") | [WORKING] |
| ⌘5 | `WindowMode.desktopWidget` ("Desktop") | [WORKING] |
| ⌘, | Opens `SettingsWindowController.shared.show(...)` | [WORKING] — standard macOS convention, correctly implemented. |

Each digit is matched against `WindowMode.shortcutKey`; all 5 modes map
1:1 to ⌘1–⌘5 confirming the task's "5 modes" premise.

### 3.2 Global hotkeys (`HotKeyManager.swift` + `Shortcuts.swift`)

A **separate, system-wide** layer using Carbon `RegisterEventHotKey` —
fires even when another app has focus, without requiring Accessibility
permission (per the file's own doc comment). User-recorded and rebindable
via the Shortcuts tab's `KeyboardShortcutsView`, persisted through
`ShortcutStore` (UserDefaults JSON), no default combos hardcoded — each
must be recorded by the user first. `HotKeyManager.reload(from:)` silently
skips any combo the OS/another app has already claimed.

10 bindable `ShortcutAction` cases (grouped in 3 UI blocks per
`ShortcutAction.groups`), routed through `AppDelegate.perform(_:)`:

| Action | Title | Effect when fired | Status |
|---|---|---|---|
| `playPause` | Play/pause | `nowPlaying.playPause()` | [WORKING] |
| `nextTrack` | Next track | `nowPlaying.next()` | [WORKING] |
| `previousTrack` | Previous track | `nowPlaying.previous()` | [WORKING] |
| `openPlayer` | Open player | Shows window at current mode + activates app | [WORKING] |
| `toggleNotch` | Toggle notch open | `settings.dynamicNotch.toggle()` | [WORKING] — same property as dropdown row 5. |
| `toggleMenuBar` | Toggle menu bar visibility | `settings.showInMenuBar.toggle()` | [WORKING] — same property as dropdown row 6. |
| `togglePopover` | Toggle popover | `switch` case is `break` — literally no-op | **[INERT — code says so directly]**: `case .togglePopover: break  // the menu-bar popover is system-managed` (`VinylPodApp.swift` line 211). Bindable and will consume the key combo, but pressing it does nothing. |
| `widgetSize` | Widget size | Cycles to the next `WindowMode` in `allCases` order | [WORKING] |
| `displayFullscreen` | Display in fullscreen | `wm?.apply(mode: .desktopWidget)` | [WORKING] |
| `windowTopBottom` | Window top/bottom | Flips `settings.desktopLayer` between `.front`/`.back`, calls `applyStacking(...)` | [WORKING] |

---

## 4. `AppSettings` cross-reference — every `@Published` property

All properties from `Sources/VinylPod/Core/Services.swift`'s `AppSettings`
class, matched against UI controls found above:

| Property | UI control(s) | Status |
|---|---|---|
| `windowMode` | Dropdown "Music Player Size" rows; ⌘1–⌘5; `widgetSize` global hotkey | [WORKING] |
| `desktopLayer` | `windowTopBottom` global hotkey only (no direct UI row/toggle anywhere) | [WORKING] but **no discoverable UI** — only reachable via a hotkey the user must first bind themselves. Borderline-orphaned: functional but effectively hidden. |
| `albumPalette` | Not user-facing; internal derived state from `setAlbumPalette(from:)` | N/A — not a setting, a computed/cached value. |
| `accentColor` | `AppearanceSettingsSection`'s `ColorPicker` + 6 preset swatches | **Orphaned UI** — the control exists in source but `AppearanceSettingsSection` is never rendered (§2.2). Effectively **[PLACEHOLDER]** from the user's vantage point despite being "wired" internally. |
| `useAdaptiveAccent` | Toggle inside orphaned `AppearanceSettingsSection`; also read (not written) by the dropdown's "Appearance — Adaptive/Custom" label | Same as above — **effectively unreachable to toggle**, only its current value leaks into a label. |
| `customBackgroundURL` | `NSOpenPanel` chooser inside orphaned `AppearanceSettingsSection` | **Orphaned UI** — same as `accentColor`. |
| `musicSource` | Dropdown once had a radio for this (removed); now only shown read-only in the inline `SourcesSettingsTab` placeholder | **[INERT as a capture filter]** — the dropdown's own code comment states plainly: "the BrowserBridge ignores `musicSource` as a capture filter, so that radio changed nothing." It persists and displays, but doesn't affect what's actually captured. |
| `vinylStyle` | Dropdown "Vinyl Style" rows; duplicated in Appearance tab's inline picker | [WORKING] |
| `glassTintStrength` | Dropdown "Liquid Glass" rows; duplicated in Appearance tab's inline picker | [WORKING] |
| `showProgress` | Dropdown "Show progress" toggle | [WORKING] |
| `keepWindowInFront` | General tab toggle | [WORKING] |
| `dynamicNotch` | Dropdown toggle; General tab toggle (duplicate); `toggleNotch` hotkey (duplicate) | [WORKING] — bound in 3 places. |
| `showInMenuBar` | Dropdown toggle; General tab toggle (duplicate); `toggleMenuBar` hotkey (duplicate); also the literal `MenuBarExtra(isInserted:)` binding | [WORKING] — bound in 4 places. |
| `launchAtLogin` | General tab toggle only | [WORKING] |
| `showArtworkInDock` | Appearance tab's inline "Artwork" group toggle | **[WORKING]** — `SettingsEffects`'s own audit comment confirms: sets `NSApp.applicationIconImage` to current artwork; "No change recommended." |
| `hideDockIcon` | General tab toggle only | [WORKING] |
| `coverArtAsWallpaper` | Appearance tab's inline "Artwork" group toggle | **[WORKING, with a confirmation gate]** — `SettingsEffects` audit comment confirms this is a real, working (if invasive) feature: shows an `NSAlert` confirmation on first enable per session ("VinylPod will replace your desktop wallpaper..."), captures each screen's original wallpaper, restores it automatically on disable. Declining the alert auto-reverts the toggle. |
| `hideNotchInFullscreen` | Appearance tab's inline "Artwork" group toggle | **[INERT — explicitly documented]**. `SettingsEffects.swift`'s own audit comment (lines 113–123) states: "intentionally NOT observed. The app has no fullscreen-detection path to hook into — there is no will/didEnterFullScreen observer anywhere in the codebase... Until that exists this toggle is inert. RECOMMEND REMOVAL." |
| `nativeCaptureEnabled` | `CaptureSettingsSection` toggle | **Orphaned UI** — the section itself is fully built (toggle + live 1 Hz status indicator distinguishing off/no-data/receiving-data) but unreachable since `SourcesSettingsTab` never renders it (§2.3). Also self-documented **[EXPERIMENTAL]**: "may be a no-op on macOS 15.4+ where MediaRemote is entitlement-gated." |

**Summary of orphaned/unreachable properties:** `accentColor`,
`useAdaptiveAccent`, `customBackgroundURL`, and `nativeCaptureEnabled` all
have fully-built, correctly-wired-to-the-property UI controls that are
never actually shown to the user, because the parent tab
(`AppearanceSettingsTab` / `SourcesSettingsTab`) renders a hardcoded
placeholder instead of the real section view. `desktopLayer` is
technically reachable but has no direct control, only an unbound hotkey.

---

## 5. Honest summary

Rough tallies across every row/toggle/control inventoried above (counting
duplicates once per unique property, plus dedicated placeholder/inert
items): of roughly **30 distinct settings surfaces**, about **21 are
genuinely [WORKING]**, **2 are [EXPERIMENTAL]** (`nativeCaptureEnabled`,
and `coverArtAsWallpaper`'s invasive-but-working wallpaper takeover sits
close to this line too), **3 are [INERT]** with the reason cited directly
in source (`hideNotchInFullscreen`, `musicSource` as a capture filter,
`togglePopover`), and **4 properties are effectively [PLACEHOLDER]** from
the user's perspective — not because the code is missing, but because
fully-implemented section views (`AppearanceSettingsSection`,
`CaptureSettingsSection`, `LastFmSettingsSection`) were built and left on
disk, uncompiled-in-spirit, while `SettingsWindow.swift` still contains
literal "do not reference — does not exist yet" comments about types that
now do exist. **The single highest-value fix is a five-line change**: in
`SettingsWindow.swift`, delete the inline `AppearanceSettingsTab` /
`SourcesSettingsTab` placeholder structs and have `SettingsWindow.tabContent`
call `AppearanceSettingsSection(settings: settings)` and a small container
combining `CaptureSettingsSection(settings: settings)` +
`LastFmSettingsSection()` directly. This would immediately surface three
already-working features (adaptive-accent/custom-background editing,
native desktop-app capture, and Last.fm scrobbling) with no new logic
required — pure re-wiring of code that already compiles and already works,
it's simply never rendered.

---

## Appendix A — Historical build-spec digests (consolidated from root *_features.json, 2026-07-03)

The seven root-level `*_features.json` files were June-28 screenshot-rebuild
task specs (schema_version 1/2, per-node "done" flags) that predate this
census. Their durable facts are digested below; **the original JSON files
were removed from the repo root in Phase 0 (2026-07-03) and remain fully
retrievable from git history** (they lived at the repo root until the
`docs(00-02)` consolidation commit). `BrowserExtension/extension_backend_features.json`
is a separate, still-live file and was not part of this consolidation.

### widget_features.json

Small/medium widget three-dot dropdown rebuild (schema_version 2,
target native-swiftui). All 6 nodes done. Durable facts:

- **Primary accent:** `#C592AB` (dusty rose glass over warm desktop); SF Pro
  rounded-feeling native sans.
- **Small mode default:** **162 x 162** compact glass widget, dusty rose
  gradient, bottom playback strip; default size on launch = Small.
- **Medium mode:** 344 x 132 horizontal compact widget — stronger white text,
  visible controls, in-art X, top-right ellipsis.
- **Dropdown:** anchored top-right under an 18 pt black ellipsis trigger;
  native SwiftUI popover (avoids window clipping, keeps rows clickable);
  Small/Medium/Large/Desktop rows call `onSelectSize(mode)`.
- **Contrast rule:** three-dot and X popovers use dark ink over bright
  frosted material.

### small_widget_features.json

Small widget rebuild from four 2026-06-28 reference screenshots
(schema_version 1). All 4 nodes done. Durable facts:

- **Target size:** **162 x 162**.
- **Geometry:** rounded glass square, dusty pink tint, 18 pt continuous
  corners; **98 x 98 album artwork** near top-left with the close X *inside*
  the art bounds at its top-left; three-dot settings trigger pinned top-right;
  bottom dark translucent strip with stopped/playing text + prev/play/next.
- **States:** stopped shows "Music is stopped." + "Please play music on
  Spotify..." copy; playing shows title, artist, optional progress, transport.

### regular_widget_features.json

Regular size widget recreation from the 2026-06-28 reference screenshots
(schema_version 1, target native-swiftui). All 5 nodes done. Durable facts:

- **Primary accent:** `#C592AB` (mauve album glass); bold white SF Pro
  title/subtitle.
- **Default regular size:** **300 x 360** tall rounded artwork card, mauve
  overlays, soft shadow.
- **Geometry:** X button inside top-left at 7 pt inset (15 pt
  `AlbumArtCloseButton`, always visible); settings ellipsis inside top-right
  at 9 pt inset (shared 18 pt black popover trigger); playback controls
  centered over artwork around y=151 (white, subtle shadow); caption in a
  bottom 86 pt gradient panel; artwork fills the full card.

### large_widget_features.json

Large size widget recreation from the 2026-06-28 4:20 PM reference
screenshots (schema_version 1, target native-swiftui). All 5 nodes done.
Durable facts:

- **Primary accent:** `#D18FB8` (large mauve glass card); heavy centered
  white SF Pro hierarchy.
- **Default large size:** **320 x 432** rounded vertical card.
- **Geometry:** **260 x 260 artwork centered at 31 pt top offset**; X at card
  top-left 8 pt inset (hover-revealed, no duplicate artwork draw); settings
  ellipsis top-right 9 pt inset; controls centered below the subtitle;
  bottom progress row with left/right time labels.

### desktop_widget_features.json

Desktop widget full-screen recreation — timer ecosystem, display picker,
animated vinyl deck, playback controls (schema_version 1, target
native-swiftui). All 9 nodes done. Durable facts:

- **Primary accent:** `#BD6BAD` (full-screen mauve vinyl desktop); oversized
  white monospaced timer + SF Pro controls.
- **Surface:** full screen; mauve gradient canvas with radial blooms.
- **Chrome:** top-left X, clock/timer toggle, display picker, settings dots at
  20 pt/18 pt; timer upper-left (countdown/time modes, top-right timer dots,
  editable countdown minutes — numerals hide while editing); vinyl deck
  upper-right (slow spin when playing, layered dark/light groove rings,
  larger center artwork, spring-animated tonearm drop/lift, tonearm color
  toggles on click); playback block bottom-left (title, subtitle, controls,
  progress); native frosted popovers with intrinsic row height.
- **Window policy:** pinned to one screen/Space, **not draggable**; front/back
  are the only desktop-layer options (Sticky_Window_Engine); does not join
  all Spaces. Display picker listed Built-in Retina Display and SB220Q.
- **Glass:** album-derived accent used as a subtle soft-light tint
  (Dynamic_Color_Extraction_Glass).

### settings_features.json

Advanced widget settings: keyboard-shortcut recorder + global Carbon
hotkeys, conditional progress bar, native always-on-top. All 7 nodes done.
Durable facts:

- **Locked decision — `hotkeyScope`: global (Carbon `RegisterEventHotKey`,
  no Accessibility permission).** This is the origin of the §3.2 hotkey
  architecture.
- **Node → file mapping:** `Shortcut_Model_Store` → `Core/Shortcuts.swift`
  (KeyCombo Codable, ShortcutAction enum of 10 actions, ShortcutStore as
  UserDefaults JSON + @Published); `Carbon_HotKey_Engine` →
  `Hotkeys/HotKeyManager.swift` (RegisterEventHotKey per bound combo,
  InstallEventHandler dispatch → onAction, reload on store change);
  `Shortcut_Recorder_UI` → `Views/Widget/ShortcutRecorderView.swift`
  ("Record Shortcut" pill, local NSEvent monitor, ⌘⇧P-style display, clear
  button); `Keyboard_Shortcuts_Window` →
  `Views/Widget/KeyboardShortcutsWindow.swift` (NSWindow, all actions in 3
  groups with recorder pills).
- **Progress bar:** `settings.showProgress` gates the bar in ALL sizes
  including Medium/Regular with clean reflow.
- **Always-on-top:** "Keep Window in Front" →
  `WindowManager.applyStacking(.front/.back)` (native `NSWindowLevel`),
  persisted. Wiring: app creates ShortcutStore + HotKeyManager and maps
  actions; SettingsMenu opens the window and wires keep-in-front.

### ui_comparative_features.json

Comparative polish pass against a right-side reference app: dynamic island
first, then typography, progress placement, menu visibility, album-aware
liquid glass. All 8 nodes done. Durable facts:

- **Accent:** dynamic from album artwork via `ArtworkColorExtractor` (no
  fixed hex); smoky adaptive liquid glass over the desktop wallpaper; SF
  Pro / SF Pro Rounded-style native sans replacing prior typography.
- **Dynamic Island:** independent compact/expanded panel anchored top-center
  at the menu bar/notch line, with visible settings trigger and animated
  equalizer bars.
- **Layout polish:** large-widget progress/control cluster moved upward
  (reduced title/control spacers); settings popover widened and max height
  increased (fixes cut-off look); settings trigger defaults to a dark
  high-contrast capsule with white-ink menu text.
- **Idle art:** the uploaded ice-mountain image is packaged as a SwiftPM
  resource and shown wherever no current track artwork exists, with a cool
  blue fallback accent.
- **Glass depth:** blur + darker inner depth + album/ice edge refraction +
  soft white specular streak + stronger bottom shade on the shared widget
  glass.
