# VinylPod (macOS)

A native macOS menu-bar music companion — dark-minimalist, static landscape
backdrop, glassmorphism, four window sizes. Captures & beautifully displays the
now-playing track. See [`PRD.md`](PRD.md) and [`design_system.md`](design_system.md).

## Build & run

This machine has **Command Line Tools only (no Xcode)**, so the app is a Swift
Package built with `swift build` and bundled into a `.app` by a script:

```bash
./make_app.sh release      # builds + bundles → dist/VinylPod.app
open dist/VinylPod.app      # look for the ⊙ disc icon in the menu bar
```

The menu-bar icon opens a popover to switch size (Small / Normal / Large /
Desktop Widget), toggle the desktop-widget layer (In Front / Behind), and quit.
⌘1–⌘4 switch sizes. Drag an audio file onto the window to play it.

## Architecture (`Sources/VinylPod/`)

| Module | What it owns |
|---|---|
| `Core/` | Design tokens (`Theme`), models (`Track`, `WindowMode`…), shared services (`NowPlayingService`, `AppSettings`) + protocol seams. **The frozen contract** — see [`CONTRACTS.md`](CONTRACTS.md). |
| `Audio/` | `LocalAudioPlayer` (AVFoundation), `MetadataReader` (ID3/AVAsset), `ArtworkColorExtractor` (adaptive accent). |
| `Windowing/` | `WindowManager` — 4 window modes, resize-in-place, desktop-widget front/behind levels. |
| `Views/` | Procedural ice-mountain background, glass panels, progress bar, transport controls, the 4 mode layouts, empty/loading/error states, drag-and-drop. |
| `App/` + `MenuBar/` | App shell (accessory/menu-bar), startup wiring, mode picker, ⌘1–4 shortcuts. |

## Status

- ✅ **Done & verified**: compiles, launches, renders. Local-file drag-drop
  playback, adaptive album-art accent, 4 window modes, menu bar + shortcuts,
  empty/loading/error states, procedural + custom-image backgrounds.
- 🚧 **Scaffolded (Phase 2)**: Spotify / Apple Music connect and browser-extension
  capture. The seams exist (`PlaybackSource`, `NowPlayingService.updateFromExternal`),
  but real wiring needs OAuth / app entitlements / Xcode.

> Toolchain note: the macOS 26+ SDK makes SwiftUI `@State` a macro whose plugin
> ships only with Xcode. We use `typealias VPState = SwiftUI.State` + `@VPState`
> to build under Command Line Tools. Install Xcode to use `@State` directly.
