# VinylPod (macOS)

A native macOS menu-bar music companion — dark-minimalist, static landscape
backdrop, glassmorphism, five window sizes. Captures & beautifully displays the
now-playing track. See [`codex.md`](codex.md) for current state; [`PRD.md`](PRD.md)
and [`design_system.md`](design_system.md) for product intent & design.

## Build & run

This machine has **Command Line Tools only (no Xcode)**, so the app is a Swift
Package built with `swift build` and bundled into a `.app` by a script:

```bash
./make_app.sh release      # builds + bundles → dist/VinylPod.app
open dist/VinylPod.app      # look for the ⊙ disc icon in the menu bar
```

The menu-bar icon opens a popover to switch size (Small / Medium / Regular /
Large / Desktop), toggle the desktop-widget layer (In Front / Behind), and quit.
⌘1–⌘5 switch sizes. Drag an audio file onto the window to play it.

## Architecture (`Sources/VinylPod/`)

| Module | What it owns |
|---|---|
| `Core/` | Design tokens (`Theme`), models (`Track`, `WindowMode`…), shared services (`NowPlayingService`, `AppSettings`) + protocol seams. **The frozen contract** — see [`CONTRACTS.md`](CONTRACTS.md). |
| `Audio/` | `LocalAudioPlayer` (AVFoundation), `MetadataReader` (ID3/AVAsset), `ArtworkColorExtractor` (adaptive accent). |
| `Windowing/` | `WindowManager` — 5 window modes, resize-in-place, desktop-widget front/behind levels. |
| `Views/` | Procedural ice-mountain background, glass panels, progress bar, transport controls, the 5 mode layouts, empty/loading/error states, drag-and-drop. |
| `Lyrics/` | Synced `.lrc` lyrics — `LRCParser`, `LRCLibLyricsProvider` (LRCLIB.net), off-main `LyricsEngine` actor, `LiveLyricsScrollView`. |
| `App/` + `MenuBar/` | App shell (accessory/menu-bar), startup wiring, mode picker, ⌘1–5 shortcuts. |

## Status

- ✅ **Done & verified**: compiles, launches, renders. Local-file drag-drop
  playback, adaptive album-art accent, 5 window modes + Dynamic Island, menu bar
  + ⌘1–⌘5 shortcuts, empty/loading/error states, procedural + custom-image
  backgrounds. **Browser-extension MediaSession capture** via the loopback bridge
  (`ws://127.0.0.1:8787`, flood-optimized). GroovePulse beat-simulation visualizer, and **synced lyrics**
  (LRCLIB.net, free/keyless).
- 🚧 **Scaffolded**: native Spotify / Apple Music *streaming connect* (needs OAuth /
  entitlements) and native `MediaRemote` capture (opt-in, OS-gated on macOS 15.4+).
  Last.fm scrobbling is wired but keyless (placeholder API keys).

> Live feature state is tracked in [`codex.md`](codex.md); this list is a summary.

> Toolchain note: the macOS 26+ SDK makes SwiftUI `@State` a macro whose plugin
> ships only with Xcode. We use `typealias VPState = SwiftUI.State` + `@VPState`
> to build under Command Line Tools. Install Xcode to use `@State` directly.
