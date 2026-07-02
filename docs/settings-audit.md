# Settings toggle audit — appearance / system effects

Audit of the four "suspect" `AppSettings` toggles that apply OS-level side
effects. Effects live in `Sources/VinylPod/App/SettingsEffects.swift` (wired at
`Sources/VinylPod/App/VinylPodApp.swift:154`). The toggles are surfaced in two
UIs: `Sources/VinylPod/Views/Settings/SettingsWindow.swift` and
`Sources/VinylPod/Views/Widget/SettingsMenu.swift`.

## Summary table

| Toggle | Field | Status | Rationale |
| --- | --- | --- | --- |
| Hide Dock icon | `hideDockIcon` | **Working** | Drives `NSApp.setActivationPolicy(.accessory/.regular)` in `applyDockPolicy()`. Real, correct, kept. |
| Show artwork in Dock | `showArtworkInDock` | **Working** | Sets `NSApp.applicationIconImage` to current album art in `applyDockArtwork()`, gated on `dockIconVisible`. Subscribes to `$track` only (never `$position`). Kept. |
| Cover art as wallpaper | `coverArtAsWallpaper` | **Implemented-now (confirmation-gated)** | Was applying `NSWorkspace.setDesktopImageURL` the instant the box was checked. Now gated behind a one-time `NSAlert` confirmation per enable session; restore stays automatic. Kept, but see note. |
| Hide notch in fullscreen | `hideNotchInFullscreen` | **Recommend-remove** | No fullscreen-detection path exists anywhere to hook into. Inert. |

## Details

### `showArtworkInDock` — Working
Real effect in `applyDockArtwork()`. Painted only when the toggle is on **and**
the Dock icon is actually visible (`dockIconVisible`); otherwise the default icon
is restored. Refreshed on `nowPlaying.$track` (never `$position`, so the per-tick
perf invariant holds) and on Dock policy changes. No action needed.

### `coverArtAsWallpaper` — Implemented now (confirmation-gated)
Overwriting the desktop wallpaper is a system-wide side effect: it touches every
screen and every Space, not just this app's window. Previous behavior silently
took over the desktop the moment the checkbox flipped.

Change made in `SettingsEffects.swift`:
- First takeover of an enable session now requires an explicit `NSAlert`
  confirmation (`confirmWallpaperTakeoverIfNeeded()`). Decline reverts the toggle.
- Confirmation is remembered for the session (`wallpaperConfirmed`) so track
  changes don't re-prompt.
- The restore path stays fully automatic — undoing an unwanted change never
  prompts. Original wallpapers are captured per-screen on enable and restored on
  disable.

This is the safest correct behavior. If product later decides the intrusion isn't
worth it, this toggle can be removed cleanly — see removal recipe below.

### `hideNotchInFullscreen` — Recommend removal
There is **no fullscreen-detection path** in the codebase for this to hook into:
- No `will/didEnterFullScreen` observers, no `toggleFullScreen`, no
  `safeAreaInsets`/notch geometry handling anywhere in `Sources`.
- The dynamic-island panel's visibility is driven solely by the `dynamicNotch`
  toggle via `WindowManager.syncDynamicIsland()`.
- The only `.fullScreenAuxiliary` usages (`WindowManager.swift:331`,
  `SettingsMenu.swift:301`) are `NSWindow` collection behaviors that let panels
  float *over other apps'* fullscreen Spaces — not a hook for "this app entered
  fullscreen."

Implementing a real effect would require adding a fullscreen observer inside
`WindowManager` (owned by another agent). Until that exists the toggle is inert
and misleading. Recommend removal.

## Removal recipe (for central cleanup — do NOT let the effects agent edit these files)

### `hideNotchInFullscreen` (recommended)
- `Sources/VinylPod/Core/Services.swift`
  - Delete the `@Published var hideNotchInFullscreen ...` declaration (line ~226).
  - Delete the `hideNotchInFullscreen = Self.bool(...)` line in `init()` (line ~256).
- `Sources/VinylPod/Views/Settings/SettingsWindow.swift`
  - Delete the `Toggle("Hide notch in fullscreen", isOn: $settings.hideNotchInFullscreen)` row (line ~127).
- `Sources/VinylPod/Views/Widget/SettingsMenu.swift`
  - Delete the `checkRow(title: "Hide notch in fullscreen", ...)` block that
    toggles `settings.hideNotchInFullscreen` (lines ~240–242).
- `SettingsEffects.swift` already contains no live reference (only an `// AUDIT:`
  comment), so no code deletion is required there.

### `coverArtAsWallpaper` (only if product declines the feature)
- `Sources/VinylPod/Core/Services.swift`: delete the `coverArtAsWallpaper`
  declaration (line ~225) and its `init()` load line (line ~255).
- `SettingsWindow.swift`: delete the `Toggle("Cover art as wallpaper", ...)` row (line ~126).
- `SettingsMenu.swift`: delete the `checkRow(title: "Cover art as wallpaper", ...)` block (lines ~237–239).
- `SettingsEffects.swift` (effects-agent owned): remove `applyWallpaper` and its
  helpers (`captureWallpapersIfNeeded`, `applyArtworkToWallpaper`,
  `restoreWallpapers`, `writeArtworkPNG`, `confirmWallpaperTakeoverIfNeeded`,
  `savedWallpapers`, `wallpaperConfirmed`) plus the `$coverArtAsWallpaper` sink and
  the `applyWallpaper()` calls in `applyAll()` and the `$track` sink.
