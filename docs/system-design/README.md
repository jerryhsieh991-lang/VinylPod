# VinylPod — System Design

VinylPod is a **free, macOS menu-bar (accessory) app** that shows what's playing —
from the **browser** (Spotify Web, Apple Music Web, YouTube, YouTube Music, or
*any* site via the MediaSession API) and from **local audio files** — as a
liquid-glass now-playing widget in five selectable sizes, plus an optional
macOS-style Dynamic Island. Built with **Swift Package Manager** (SwiftUI +
AppKit), no third-party dependencies.

This folder documents the architecture across five slices. Start here, then dive
into the section you care about.

| # | Doc | Covers |
|---|-----|--------|
| 01 | [Core architecture](01-core-architecture.md) | Module layout, DI seams, `NowPlayingService` state core, app lifecycle |
| 02 | [Windowing & UI](02-windowing-and-ui.md) | `NSPanel`/`NSHostingController` hosting, the 5 window modes, liquid-glass design system, Dynamic Island |
| 03 | [Capture & bridge](03-capture-and-bridge.md) | Browser-extension capture pipeline, WebSocket wire protocol, reconnect logic |
| 04 | [Audio & media](04-audio-and-media.md) | Local playback (AVFoundation), metadata, off-main CoreImage color extraction |
| 05 | [Security, performance & build](05-security-performance-build.md) | Bridge threat model, render-loop invariants, hotkeys, persistence, build pipeline |

## System overview

```mermaid
flowchart TB
  subgraph Browser["Browser — any tab"]
    MS["navigator.mediaSession / DOM"]
    CS["content scripts:\nnamed scrapers + universal MediaSession reader"]
    SW["MV3 service worker:\nper-tab aggregate · active-tab pick · reconnect"]
    MS --> CS --> SW
  end

  SW -- "ws://127.0.0.1:8787\n{type:nowplaying, payload}" --> BB

  subgraph App["VinylPod.app — macOS menu-bar accessory"]
    BB["BrowserBridge\nNWProtocolWebSocket server (loopback)"]
    AUD["LocalAudioPlayer · MetadataReader\n(AVFoundation)"]
    NP["NowPlayingService\n@MainActor · single source of truth\n@Published track/isPlaying/position/duration"]
    ACE["ArtworkColorExtractor\nCoreImage off-main → AlbumColorPalette"]
    AS["AppSettings\npersisted @Published (UserDefaults)"]
    WM["WindowManager\nNSPanel + NSHostingController"]
    UI["SwiftUI views\nModeContentView · glass widgets · Dynamic Island · Settings"]

    BB -- "updateFromExternal()" --> NP
    AUD -- "onTick / onFinish" --> NP
    NP -- "onTrackChanged" --> ACE --> AS
    NP -- "@EnvironmentObject" --> UI
    AS -- "@EnvironmentObject" --> UI
    WM -- "hosts AnyView" --> UI
    NP -- "externalControl (transport)" --> BB
  end
```

**One-paragraph data flow:** A browser tab's now-playing state is read by a
content script (named-site scraper or the universal MediaSession reader),
aggregated per-tab in the MV3 service worker, and streamed over a loopback
WebSocket to `BrowserBridge`, which validates/hardens it and calls
`NowPlayingService.updateFromExternal(...)` on the main actor. Local files take a
parallel path through `LocalAudioPlayer`. `NowPlayingService` is the single
source of truth; a real track change triggers off-main CoreImage color extraction
into an `AlbumColorPalette` that drives the liquid-glass surfaces. SwiftUI views
observe the service and settings via `@EnvironmentObject`; `WindowManager` hosts
them in a reusable `NSPanel`. Transport commands flow back out through the same
WebSocket to control the web player.

## Key design decisions

- **Browser extension over a private API.** Competitors capture now-playing via
  Apple's private `MediaRemote.framework` — which Apple restricted in macOS 15.4
  and which blocks Mac App Store distribution. VinylPod's extension + localhost
  WebSocket is App-Store-safe, cross-browser, and unaffected by that lockdown.
  Trade-off: an extension install is required, and only *browser* playback is
  seen (not the native Spotify/Apple Music desktop apps).
- **One state core, two input paths.** `NowPlayingService` unifies local-file and
  external/browser sources behind `track.source`; transport routes to the local
  player or the `externalControl` relay accordingly.
- **Reuse the window, swap the content.** A single `NSPanel` + `NSHostingController`
  is reused across size switches (only widget⇄non-widget recreates it); the
  visual change is an opacity cross-fade under a stable `.id` so the expensive
  `NSVisualEffectView` blur layers are never torn down.
- **Loopback-only, hardened bridge.** 127.0.0.1 bind, 256 KB frame cap, 6-connection
  cap, SSRF guard + `data:`-string decode on artwork, 8 MB image cap, serial-queue
  state confinement. See doc 05 for the full threat model.

## Performance invariants (must-keep rules)

These come from the ~85% CPU render-loop incident (fixed; verified idle **and**
during playback at **0.0% CPU**). Future code must preserve them:

1. **Never observe `NowPlayingService` wholesale in an always-on parent view.**
   `position` is `@Published` and rewritten every tick — observing it high in the
   tree re-renders everything (incl. the `WindowMode` `ForEach`) every tick.
2. **Read `position` only in dedicated leaf views, coarsened to whole seconds.**
3. **Guard every `@Published` write on equality** (except `position`) before
   assigning, so unchanged data doesn't fire `objectWillChange`.
4. **Never re-extract / re-assign the album palette from a tick** — dedupe equal
   palettes (`palette != albumPalette`).
5. **Size switches use an opacity cross-fade under a stable `.id`,** not a
   per-mode `.id(mode)` (which tears down and rebuilds the glass layers).

## Competitive context & roadmap signals

From a survey of 12+ now-playing apps (Sleeve, Tuneful, NepTunes, Vinyls, Silicio,
Jukebox, and the notch tier — NotchNook, DynamicLake, Alcove, BoringNotch,
MediaMate):

- **Differentiation:** free, App-Store-safe browser/MediaSession capture, 5
  selectable widget sizes, liquid-glass + adaptive palette. No competitor combines
  these.
- **Biggest feature gap:** **Last.fm scrobbling** — present in Sleeve, Tuneful,
  NepTunes, and Silicio; absent here. Highest-value addition for this audience.
- **Second gap:** **native desktop-app capture.** Everyone else sees the native
  Spotify/Apple Music apps (via MediaRemote/AppleScript); VinylPod only sees the
  browser. A future optional MediaRemote-adapter path (à la `ungive/mediaremote-adapter`,
  the macOS-15.4 workaround the notch apps use) would close this — at the cost of
  a private-API helper.
- **Crowded arena:** the Dynamic Island feature competes with mature, feature-rich
  notch apps (File Tray, calendar, HUD). VinylPod's island is now-playing-only —
  fine as a complement, not a differentiator.
