# VinylPod — Frozen Module Contracts

All modules code against these EXACT names. Core already exists and compiles.
Do **not** edit Core or Package.swift. Add files only in your own folder.

## Core (already built — read-only)
- `enum VPTheme` — design tokens: `textPrimary/Secondary/Muted`, `scrim`, `glassTint`,
  `glassStroke`, `panel`, `accentFallback`, `radius`/`radiusSmall`/`radiusLarge`,
  `fade`, `spring`, `title()/body()/caption()`.
- `struct Track { title, artist, album, artwork: NSImage?, duration, source, url; .empty; isEmpty }`
- `enum PlaybackSource { localFile, browser, spotify, appleMusic, none; displayName; sfSymbol }`
- `enum WindowMode { small, normal, large, desktopWidget; displayName; defaultSize; shortcutKey }`
- `enum DesktopLayer { front, back; displayName }`
- `@MainActor final class NowPlayingService: ObservableObject`
  - published: `track`, `isPlaying`, `position`, `duration`
  - inject: `player: AudioPlaying?`, `metadata: MetadataReading?`, `onTrackChanged: ((Track)->Void)?`
  - methods: `load(urls:)`, `playPause()`, `next()`, `previous()`, `seek(to:)`,
    `reportTick(position:duration:)`, `reportFinished()`, `updateFromExternal(...)`
- `@MainActor final class AppSettings: ObservableObject`
  - published: `windowMode`, `desktopLayer`, `accentColor`, `useAdaptiveAccent`, `customBackgroundURL`
  - method: `setAccent(from: Color?)`
- `@MainActor final class AppEnvironment { static let shared; nowPlaying; settings }`
- Protocols: `AudioPlaying`, `MetadataReading`, `ArtworkColorExtracting` (see Services.swift).

## Audio module (Agent A) — folder `Sources/VinylPod/Audio/`
Produce exactly these public types with `init()`:
- `final class LocalAudioPlayer: AudioPlaying` — AVFoundation playback; drives `onTick`/`onFinish`.
- `final class MetadataReader: MetadataReading` — `func read(_:) async -> Track` from AVAsset/ID3.
- `final class ArtworkColorExtractor: ArtworkColorExtracting` — `dominantColor(from:) -> Color?`.

## Windowing module (Agent B) — folder `Sources/VinylPod/Windowing/`
- `@MainActor final class WindowManager`
  - `init(settings: AppSettings, content: @escaping (WindowMode) -> AnyView)`
  - `func show(_ mode: WindowMode)` — create/show window for mode, host content.
  - `func apply(mode: WindowMode)` — resize/relayout WITHOUT recreating playback.
  - `func apply(desktopLayer: DesktopLayer)` — front = above all; back = below desktop icons.

## Views module (Agent C) — folder `Sources/VinylPod/Views/`
- `struct ModeContentView: View { init(mode: WindowMode) }`
  - reads `@EnvironmentObject nowPlaying: NowPlayingService`, `@EnvironmentObject settings: AppSettings`
  - renders the correct layout per mode, includes empty/loading/error states,
    and attaches `.onDrop` that calls `AppEnvironment.shared.nowPlaying.load(urls:)`.
- Supporting views (your choice of files): landscape background (procedural ice
  mountain + `settings.customBackgroundURL` image), glass panel, progress bar,
  transport controls tinted with `settings.accentColor`.

## App module (Agent D) — folder `Sources/VinylPod/App/` + `MenuBar/`
- `VinylPodApp.swift` with `@main struct VinylPodApp: App` — REPLACES `_TempMain.swift` (delete it).
- Wires Audio into NowPlayingService, builds `WindowManager` with a content factory that
  injects environment objects into `ModeContentView`, provides MenuBarExtra (mode picker +
  desktop front/behind toggle + quit) and ⌘1–⌘4 shortcuts.
