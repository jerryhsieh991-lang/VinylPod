# VinylPod — Core Architecture & State Management

> **Slice:** Core architecture, state ownership, dependency injection, lifecycle.
> **Repo:** `Sources/VinylPod/`
> **Date:** 2026-06-29 (refreshed 2026-07-01 — added the `AppSettings` property table in §4.3, the "Native capture integration point" in §4.2, the "Settings window vs. the three-dot dropdown" writeup in §4.9, and a new row in the §7 Known Risks table, all reflecting tonight's native-capture work)

---

## 1. High-Level Summary

VinylPod is a macOS **accessory (menu-bar) app** — no Dock icon by default, no main window managed by SwiftUI's scene machinery. All persistent on-screen surfaces are either:

1. A `MenuBarExtra` SwiftUI popover (the menu-bar dropdown).
2. An `NSPanel`/`NSWindow` pair owned exclusively by `WindowManager`.

The app has one piece of central mutable state (`NowPlayingService`) and one piece of central persisted settings state (`AppSettings`), both held in a singleton `AppEnvironment.shared`. All playback logic flows through `NowPlayingService`; the UI layers observe it but never own it.

---

## 2. Module / Folder Layout

```
Sources/VinylPod/
├── App/               # Entry point, lifecycle wiring, side effects
│   ├── VinylPodApp.swift          — @main struct, MenuBarExtra scene
│   ├── AppDelegate (in same file) — wiring graph, concrete injection
│   ├── WindowCoordinator.swift    — shared singleton linking AppDelegate → Views
│   └── SettingsEffects.swift      — Combine-driven OS side effects
├── Core/              # Owned state and protocols (zero AppKit UI)
│   ├── Models.swift               — Track, WindowMode, PlaybackSource, enums
│   ├── Services.swift             — NowPlayingService, AppSettings, AppEnvironment
│   ├── Shortcuts.swift            — ShortcutStore, ShortcutAction, KeyCombo
│   └── Theme.swift                — VPTheme constants, AlbumColorPalette
├── Audio/             # Concrete playback implementations (no UI, no services)
│   ├── LocalAudioPlayer.swift     — AVAudioPlayer wrapper, implements AudioPlaying
│   ├── MetadataReader.swift       — AVURLAsset async metadata, implements MetadataReading
│   └── ArtworkColorExtractor.swift — CoreImage palette, implements ArtworkColorExtracting
├── Bridge/            # External now-playing input
│   └── BrowserBridge.swift        — loopback WebSocket server (NWListener, port 8787)
├── Capture/           # OPTIONAL native desktop-app now-playing capture (added post-initial-writeup)
│   └── NativeMediaRemoteCapture.swift — dlopen/dlsym MediaRemote adapter, off by default
├── Scrobbling/        # Last.fm integration (added post-initial-writeup)
│   ├── LastFmScrobbler.swift      — ObservableObject; subscribes to $track, drives now-playing/scrobble
│   └── LastFmClient.swift         — API session + OAuth-style auth handshake (not read in full here)
├── Windowing/         # NSWindow/NSPanel ownership
│   └── WindowManager.swift        — sole owner of NSPanel; content injected via factories
├── MenuBar/           # Menu-bar popover surface
│   └── MenuBarContentView.swift   — dropdown UI, observes settings only (NOT nowPlaying directly)
├── Hotkeys/           # System-wide Carbon hotkeys
│   └── HotKeyManager.swift        — RegisterEventHotKey, no Accessibility permission needed
└── Views/             # SwiftUI rendering only; reads from environment objects
    ├── ModeContentView.swift      — root content view dispatched per WindowMode
    ├── Widget/                    — per-mode glass widgets (Small/Medium/Regular/Large/Desktop)
    │   └── SettingsMenu.swift     — the three-dot dropdown (SettingsMenuButton); see §9.1
    ├── Settings/                  — tabbed Settings window (added post-initial-writeup, see §9.1)
    │   ├── SettingsWindow.swift          — TabView host + SettingsWindowController (owns the NSWindow)
    │   ├── GeneralSettingsSection.swift  — General tab
    │   ├── AppearanceSettingsSection.swift — accent/palette editor (see §9.5 for a wiring gap)
    │   ├── CaptureSettingsSection.swift  — native-capture toggle + live indicator; calls attachNativeCapture
    │   ├── LastFmSettingsSection.swift   — scrobble toggle + Last.fm connect/disconnect flow
    │   └── AboutSettingsSection.swift    — About tab
    ├── LandscapeBackground.swift  — static scenic backdrop
    ├── GlassPanel.swift           — reusable liquid-glass material
    └── ...
```

### Module boundary rules

| Module | Allowed to touch | Prohibited from touching |
|--------|-----------------|--------------------------|
| Core | — | Any UIKit/AppKit, any playback API |
| Audio | Core protocols and models | UI, Services, Bridge |
| Bridge | Core models, NowPlayingService via ref | Audio, Windowing, Views |
| Capture | Core models, NowPlayingService via `attachNativeCapture` | Audio, Bridge, Views |
| Scrobbling | Core models (`Track`), NowPlayingService via `$track` subscription | Audio, Bridge, Windowing, Views |
| Windowing | Core models, AppSettings | Audio, Bridge, NowPlayingService directly |
| Views | EnvironmentObjects (NowPlayingService, AppSettings), WindowCoordinator | Audio internals, Bridge |
| App | Everything — the only "wiring" layer | — |

Capture and Scrobbling are both **feed-in** modules like Bridge, not **consumers**: they push updates into `NowPlayingService`/read `$track` from it, and are never read from by Views directly (Views only ever observe `NowPlayingService`/`AppSettings`, regardless of which upstream module produced the data).

---

## 3. Dependency Graph

```mermaid
graph TD
    subgraph App["App (wiring layer)"]
        AD[AppDelegate<br/>applicationDidFinishLaunching]
        WC[WindowCoordinator.shared]
        SE[SettingsEffects]
    end

    subgraph Core["Core (state)"]
        AE[AppEnvironment.shared<br/>singleton]
        NPS[NowPlayingService<br/>@MainActor ObservableObject]
        AS[AppSettings<br/>@MainActor ObservableObject]
        SS[ShortcutStore<br/>@MainActor ObservableObject]
    end

    subgraph Audio["Audio (drives Core)"]
        LAP[LocalAudioPlayer<br/>AudioPlaying]
        MR[MetadataReader<br/>MetadataReading]
        ACE[ArtworkColorExtractor<br/>ArtworkColorExtracting]
    end

    subgraph Bridge["Bridge (feeds Core)"]
        BB[BrowserBridge<br/>NWListener ws://127.0.0.1:8787]
    end

    subgraph Windowing["Windowing"]
        WM[WindowManager<br/>NSPanel owner]
        DI[DynamicIslandPanel<br/>NSPanel]
    end

    subgraph UI["Views / MenuBar (render)"]
        MBCEV[MenuBarContentView<br/>MenuBarExtra]
        MCV[ModeContentView<br/>hosted in NSPanel]
        Widgets[SmallGlassWidget<br/>MediumGlassWidget<br/>RegularGlassWidget<br/>LargeGlassWidget<br/>DesktopWidgetCanvas]
    end

    AD -->|creates| LAP
    AD -->|creates| MR
    AD -->|creates| ACE
    AD -->|injects player/metadata ref| NPS
    AD -->|wires onTick, onFinish callbacks| LAP
    AD -->|creates and starts| BB
    AD -->|creates| WM
    AD -->|sets| WC
    AD -->|creates| SE

    AE -->|holds| NPS
    AE -->|holds| AS
    AE -->|holds| SS

    LAP -->|onTick callback| NPS
    LAP -->|onFinish callback| NPS
    NPS -->|calls AudioPlaying protocol| LAP
    NPS -->|calls MetadataReading protocol async| MR

    BB -->|updateFromExternal on @MainActor| NPS
    NPS -->|externalControl closure| BB

    NPS -->|onTrackChanged closure| AS
    AS -->|setAlbumPalette| ACE

    WM -->|reads| AS
    WM -->|content factory AnyView| MCV
    WC -->|manager ref| WM

    MBCEV -->|@EnvironmentObject| NPS
    MBCEV -->|@EnvironmentObject| AS
    MBCEV -->|WindowCoordinator.shared| WC

    MCV -->|@EnvironmentObject| NPS
    MCV -->|@EnvironmentObject| AS
    MCV -->|dispatches to| Widgets

    SE -->|Combine sinks on| AS
    SE -->|Combine sinks on| NPS

    HKM[HotKeyManager] -->|onAction| AD
    AD -->|reload from| SS
    SS -->|onChange| HKM
```

---

## 4. Key Types and Responsibilities

### 4.1 `AppEnvironment` — the singleton root

```swift
@MainActor final class AppEnvironment {
    static let shared = AppEnvironment()
    let nowPlaying = NowPlayingService()
    let settings   = AppSettings()
    let shortcuts  = ShortcutStore()
}
```

A plain value-holder singleton. It exists so:
- `VinylPodApp.body` (the SwiftUI scene, outside `AppDelegate`) can inject environment objects into `MenuBarExtra` content at scene construction time.
- Views that need to reach the service without being in a SwiftUI hierarchy (e.g., `ModeContentView.handleDrop`) can call `AppEnvironment.shared.nowPlaying.load(...)` directly.

It owns nothing except three `ObservableObject` instances. There is intentionally no business logic here.

---

### 4.2 `NowPlayingService` — single source of truth

File: `Core/Services.swift`

```swift
@MainActor final class NowPlayingService: ObservableObject {
    @Published private(set) var track:    Track
    @Published private(set) var isPlaying: Bool
    @Published private(set) var position:  TimeInterval
    @Published private(set) var duration:  TimeInterval

    var player:          AudioPlaying?     // injected by AppDelegate
    var metadata:        MetadataReading?  // injected by AppDelegate
    var onTrackChanged:  ((Track) -> Void)?
    var externalControl: ((ExternalControlAction) -> Void)?
}
```

**Two distinct update paths:**

| Path | Entry point | Who calls it |
|------|-------------|--------------|
| Local file | `playCurrent()` → `player?.load`, async `metadata?.read`, `player?.play` | `load(urls:)`, `next()`, `previous()` |
| External (browser/Spotify/Apple Music) | `updateFromExternal(_:isPlaying:position:duration:)` | `BrowserBridge` via `@MainActor` Task hop |

The external path guards against re-firing expensive side effects on every 1 Hz position tick. `track` is only re-assigned when `t != track` (value equality via title/artist/album/url/source). Only a real track change fires `onTrackChanged` → palette extraction. Position is always updated.

**Transport routing:** `playPause()`, `next()`, `previous()`, `seek()` branch on `track.source`:
- `.localFile` → calls `player?.play/pause/seek` directly.
- Any other source → calls `externalControl?(action)` which routes to `BrowserBridge.send(_:)`.

**Queue management:** a simple `[URL]` array with an index. No playlist model layer; add one if shuffle/repeat is needed.

**Native capture integration point.** `NowPlayingService.attachNativeCapture(settings:)` is the wiring method for the optional `Capture/NativeMediaRemoteCapture.swift` adapter (see §2's module tree). It is intentionally *not* a third parallel state-update path alongside "local file" and "external." Instead, when `settings.nativeCaptureEnabled` is true, the adapter's `onUpdate` callback builds a `Track` (tagging `.source` as `.spotify` or `.appleMusic` from the captured bundle identifier) and hands it to the SAME `updateFromExternal(_:isPlaying:position:duration:)` entry point that `BrowserBridge` already calls. That means:
- The `t != track` equality guard and the 1 Hz-safe re-render behavior described above apply unmodified to native-capture updates — no new perf work was needed.
- Native capture only *supplements* the browser bridge: `onUpdate` explicitly no-ops (`if self.track.source == .localFile { return }`) so it can never clobber active local-file playback, and there is no precedence logic needed between "browser" and "native" because both funnel through the same guarded setter.
- `attachNativeCapture` is idempotent and safe to call on every settings change — it lazily creates/starts the adapter when the toggle flips on and tears it down (`stop()` + `nativeCapture = nil`) when it flips off. `CaptureSettingsSection.swift` (see §4.9) calls it whenever the toggle changes.

The key architectural takeaway: adding a new upstream data source did not require adding a new downstream update path. `updateFromExternal` is the one and only "external" ingestion point in `NowPlayingService`; Bridge and Capture are two producers feeding the same consumer.

---

### 4.3 `AppSettings` — persisted user preferences

File: `Core/Services.swift`

All `@Published` properties persist in `UserDefaults.standard` via `didSet` (except where noted below). Reads happen once in `init()`. There is no abstraction layer over UserDefaults (acceptable for this volume of settings; would need a settings-store protocol for testability at scale).

**Important distinction:** `bridgeConnected` is **not** an `AppSettings` property — it is a `@Published private(set)` property on `NowPlayingService` (§4.2), set by `BrowserBridge` on WebSocket connect/disconnect and read by the settings UI for a live status indicator. It is transient connection state, not a user preference, so it is intentionally not persisted and not listed in the table below.

Every `@Published` property on `AppSettings`:

| Property | Type | Default | Persisted key | Purpose |
|----------|------|---------|----------------|---------|
| `windowMode` | `WindowMode` | `.small` | `"windowMode"` | Persisted current widget size (`.small` / `.normal` / `.regular` / `.large` / `.desktopWidget`); restored by `WindowManager` at launch. |
| `desktopLayer` | `DesktopLayer` | `.front` | `"desktopLayer"` | Stacking for the desktop widget (`.front` above all windows, `.back` behind desktop icons). |
| `albumPalette` | `AlbumColorPalette` | `.iceMountain` | *not persisted* | Derived fresh from artwork on every track change via `setAlbumPalette(from:)`. The default is shown until the first track's art arrives. |
| `accentColor` | `Color` | `VPTheme.accentFallback` | *not persisted* | Derived from `albumPalette.vibrant` (when `useAdaptiveAccent` is on); used by controls, source chip, transport buttons. |
| `useAdaptiveAccent` | `Bool` | `true` | `"useAdaptiveAccent"` | Whether `accentColor`/`albumPalette` react to album art at all, vs. staying on the fallback theme color. |
| `customBackgroundURL` | `URL?` | `nil` | `"customBackgroundURL"` | `nil` → procedural built-in "ice mountain" background; non-nil → user-supplied image. |
| `musicSource` | `PlaybackSource` | `.spotify` | `"musicSource"` | The "Music Player Source" selector (dropdown-era; now also shown read-only in the Settings window's Sources tab). |
| `vinylStyle` | `VinylStyle` | `.image` | `"vinylStyle"` | The "Vinyl Style" widget-look selector. |
| `glassTintStrength` | `GlassTintStrength` | `.balanced` | `"glassTintStrength"` | How strongly album colors tint the liquid-glass membranes. Added tonight. |
| `showProgress` | `Bool` | `true` | `"showProgress"` | Shows/hides the playback progress bar in the widget. |
| `keepWindowInFront` | `Bool` | `true` | `"keepWindowInFront"` | Keeps the widget panel floating above other windows. |
| `dynamicNotch` | `Bool` | `true` | `"dynamicNotch"` | Enables the top-center dynamic-island notch; `didSet` also calls `WindowCoordinator.shared.manager?.syncDynamicIsland()`. |
| `showInMenuBar` | `Bool` | `true` | `"showInMenuBar"` | Whether the `MenuBarExtra` icon is shown. |
| `launchAtLogin` | `Bool` | `false` | `"launchAtLogin"` | Drives `SMAppService.mainApp.register/unregister()` via `SettingsEffects`. |
| `showArtworkInDock` | `Bool` | `false` | `"showArtworkInDock"` | Drives `NSApp.applicationIconImage` via `SettingsEffects`. |
| `hideDockIcon` | `Bool` | `true` | `"hideDockIcon"` | Drives `NSApp.setActivationPolicy(.accessory/.regular)` via `SettingsEffects`. |
| `coverArtAsWallpaper` | `Bool` | `false` | `"coverArtAsWallpaper"` | Drives `NSWorkspace.setDesktopImageURL` (reversible capture/restore) via `SettingsEffects`. |
| `hideNotchInFullscreen` | `Bool` | `false` | `"hideNotchInFullscreen"` | Suppresses the dynamic-island notch while another app is fullscreen. |
| `nativeCaptureEnabled` | `Bool` | `false` | `"settings.nativeCaptureEnabled"` | OPTIONAL/EXPERIMENTAL: turns on the private-MediaRemote-framework capture path (see "Native capture integration point" above and `CaptureSettingsSection.swift`). OFF by default; may be a no-op on macOS 15.4+ where MediaRemote is entitlement-gated. Added tonight. |

Two properties (`albumPalette`, `accentColor`) are deliberately excluded from persistence because they are derived, not preferences — persisting a stale palette across launches would show wrong colors until the next track change recomputes them.

`setAlbumPalette(from:)` is the critical hot path — it includes an equality guard (`guard palette != albumPalette else { return }`) to prevent re-triggering the `.animation(value: albumPalette)` modifier on the glass + landscape views when the palette has not actually changed.

---

### 4.4 Dependency-injection protocols (`Core/Services.swift`)

Three protocols define the seams between Core (state) and Audio (behavior):

```swift
@MainActor protocol AudioPlaying: AnyObject {
    func load(_ url: URL); func play(); func pause()
    func stop(); func seek(to seconds: TimeInterval)
    var onTick: ((TimeInterval, TimeInterval) -> Void)? { get set }
    var onFinish: (() -> Void)? { get set }
}

@MainActor protocol MetadataReading {
    func read(_ url: URL) async -> Track
}

@MainActor protocol ArtworkColorExtracting {
    func palette(from image: NSImage) -> AlbumColorPalette?
    func dominantColor(from image: NSImage) -> Color?
}
```

Concrete implementations injected at `applicationDidFinishLaunching`:
- `AudioPlaying` ← `LocalAudioPlayer` (AVAudioPlayer, 10 Hz timer, AVFoundation delegate bridge)
- `MetadataReading` ← `MetadataReader` (async `AVURLAsset.load(.commonMetadata)`)
- `ArtworkColorExtracting` ← `ArtworkColorExtractor` (CoreImage CIAreaAverage + pixel sampling)

`NowPlayingService` never imports AVFoundation. The protocols are all declared on `@MainActor`, so injected concretes are always accessed from the main thread even though `MetadataReader.read` is itself `async`.

---

### 4.5 `WindowManager` and `WindowCoordinator`

`WindowManager` (`Windowing/WindowManager.swift`) is the sole owner of the app's `NSPanel` instances. It:
- Takes `AppSettings` and two content factory closures at `init` (one for mode content, one for the dynamic island).
- Decides when to reuse the existing `NSPanel` vs. rebuild it (the style mask is different between widget and non-widget modes, requiring a new `NSPanel`).
- Resizes the panel around its center (grow/shrink in place), clamps to the visible screen frame, and persists position in `UserDefaults`.
- Manages a second `NSPanel` for the optional top-center dynamic island notch.

`WindowCoordinator` (`App/WindowCoordinator.swift`) is a tiny `@MainActor` singleton that holds a weak reference to the `WindowManager`. It exists to bridge:
- `AppDelegate.keyMonitor` (an `NSEvent` monitor, no SwiftUI context)
- `MenuBarContentView` (a SwiftUI scene, no reference to `AppDelegate`)
- `ModeContentView` (embedded in the hosted `NSPanel`, also no `AppDelegate` reference)

All three can reach the `WindowManager` via `WindowCoordinator.shared.manager?.apply(mode:)` without creating circular references.

---

### 4.6 `BrowserBridge` — external input

File: `Bridge/BrowserBridge.swift`

A loopback WebSocket server using Apple's `NWListener` + `NWProtocolWebSocket` (no third-party dependencies). The browser extension pushes `{type:"nowplaying", payload:{…}}` at ~1 Hz. The bridge:
1. Validates and decodes the JSON frame.
2. Downloads cover art (cached by URL; handles both `http(s)://` and inline `data:` URIs).
3. Hops to `@MainActor` and calls `NowPlayingService.updateFromExternal(...)`.

Transport commands flow back via `NowPlayingService.externalControl → BrowserBridge.send(_:)`.

Security hardening is in place (see §6).

---

### 4.7 `SettingsEffects` — OS side effects

File: `App/SettingsEffects.swift`

Uses Combine subscriptions (not SwiftUI `.onChange`) to react to settings changes and push state into the OS:
- `launchAtLogin` → `SMAppService.mainApp.register/unregister()`
- `hideDockIcon` + `showInMenuBar` → `NSApp.setActivationPolicy(.accessory/.regular)`
- `showArtworkInDock` + track changes → `NSApp.applicationIconImage`
- `coverArtAsWallpaper` + track changes → `NSWorkspace.setDesktopImageURL` (with reversible capture/restore)

The wallpaper feature saves each screen's current wallpaper URL the moment the toggle is enabled, and restores exactly those URLs when the toggle is disabled.

---

### 4.8 `HotKeyManager` — system-wide hotkeys

File: `Hotkeys/HotKeyManager.swift`

Uses Carbon `RegisterEventHotKey` (not `NSEvent.addGlobalMonitorForEvents`). Carbon hotkeys:
- Fire when another app has focus (truly system-wide).
- Do not require Accessibility permission.
- Consume the key event so it does not leak to the focused app.

One shared `EventHandler` fires for all registered hotkeys; it dispatches back to the main actor via `DispatchQueue.main.async` and calls `AppDelegate.perform(_:)`.

---

### 4.9 Settings window vs. the three-dot dropdown

VinylPod has two separate settings surfaces, and the split is deliberate rather than historical debris:

- **`SettingsMenu.swift` (`SettingsMenuButton`, `Views/Widget/`)** — a popover anchored to the three-dot button on the widget itself. This stays reserved for the controls a user reaches for constantly while listening: things like the music-source indicator and other quick, frequent toggles that should be one click away from the now-playing surface, without leaving the widget's context.
- **`SettingsWindow.swift` (`Views/Settings/`)** — a proper tabbed `NSWindow` (General / Appearance / Sources / Shortcuts / About), opened via ⌘, or an explicit "Open Settings…" action, owned by `SettingsWindowController.shared`. This is where the long-tail toggles live — the ones a user sets once and rarely revisits — plus the newer, larger features that don't fit a quick popover: the Capture tab section (native desktop-app capture, via `CaptureSettingsSection.swift`) and Last.fm scrobbling (via `LastFmSettingsSection.swift`), both surfaced under the Sources tab.

The code states its own rationale for keeping the two surfaces cleanly separated at the data layer, not just the UI layer. `SettingsWindow`'s doc comment spells out a hard perf invariant: the window and everything it hosts observes **only** `AppSettings`, and must never observe `NowPlayingService` directly — because `NowPlayingService.position` is rewritten roughly 10×/sec, and binding that into the settings window would repaint the whole tabbed window on every playback tick. Where the Sources tab needs to show the current source, it reads the *configured* `musicSource` preference (read-only) rather than live playback state — consistent with the module boundary rule in §2 that Views only ever observe `NowPlayingService`/`AppSettings`, never reach into Bridge/Capture/Scrobbling internals directly.

In short: the dropdown is optimized for frequency-of-use and proximity to the widget; the Settings window is optimized for discoverability of everything else, and is structurally prevented from becoming a perf liability by only ever binding to `AppSettings`.

---

## 5. App Lifecycle

### Startup sequence (`applicationDidFinishLaunching`)

```
1. NSApp.setActivationPolicy(.accessory)          — hide Dock icon
2. Build LocalAudioPlayer, MetadataReader, ArtworkColorExtractor
3. Inject into NowPlayingService via property assignment
4. Wire player.onTick → NowPlayingService.reportTick
5. Wire player.onFinish → NowPlayingService.reportFinished
6. Wire NowPlayingService.onTrackChanged → Task.detached palette extraction → AppSettings.setAlbumPalette
7. Build WindowManager with content factories (close over AppEnvironment.shared)
8. Set WindowCoordinator.shared.manager = wm
9. wm.show(settings.windowMode)                   — restore last size
10. Build BrowserBridge, start WS server on :8787
11. Wire NowPlayingService.externalControl → BrowserBridge.send
12. Install ⌘1–⌘5 local key monitor
13. Build HotKeyManager, wire onAction → AppDelegate.perform
14. Register Carbon hotkeys from ShortcutStore
15. Build SettingsEffects, call .start()           — apply OS state baseline + subscribe
16. Handle launch-argument audio files (play immediately if any)
```

### Environment object propagation to SwiftUI

Both `NowPlayingService` and `AppSettings` are injected at TWO entry points:

1. **`MenuBarExtra` content** — injected in `VinylPodApp.body` via `.environmentObject(env.nowPlaying)` / `.environmentObject(env.settings)`.
2. **`WindowManager`-hosted content** — injected in the content factory closure captured in `AppDelegate`, passed into `WindowManager.init(content:)`, and applied in `WindowManager.hostContent(for:in:)` via `NSHostingController`.

This dual injection is necessary because SwiftUI scene objects (`MenuBarExtra`) and imperatively-hosted views (`NSHostingController`) have separate environment trees; there is no shared parent view that could inject once.

### Teardown (`applicationWillTerminate`)

Removes the local key event monitor (`NSEvent.removeMonitor`). The `BrowserBridge`'s `NWListener` and connections are torn down when the instance is deallocated (no explicit `stop()` method). Carbon hotkeys are unregistered when `HotKeyManager` deinits via `UnregisterEventHotKey`.

---

## 6. Design Decisions and Tradeoffs

### Global `AppEnvironment.shared` singleton vs. DI container

**Decision:** Simple singleton. **Tradeoff:** Not unit-testable without global mutation. Acceptable for a single-window accessory app where integration tests are impractical and the app has no server-side logic. A DI container would add indirection for no present benefit.

### Protocol seams for Audio

**Decision:** Three `@MainActor` protocols (`AudioPlaying`, `MetadataReading`, `ArtworkColorExtracting`) instead of direct type references from `NowPlayingService`. **Benefit:** Core never imports AVFoundation or CoreImage. The Audio module is entirely swappable (e.g., replacing `LocalAudioPlayer` with an `AVPlayer`-based implementation for streaming, or injecting a mock for UI tests). **Cost:** Protocol declarations live alongside the concrete implementations' call sites, which requires discipline to avoid slippage.

### `@MainActor` throughout

**Decision:** Every service and most UI types are `@MainActor`. **Benefit:** No lock-based data races; Swift 6 isolation checking enforces this at compile time. **Cost:** Metadata reading and color extraction must be bridged off-main (`Task.detached` with a `Data` snapshot, `nonisolated static` methods) — done correctly but the pattern is non-obvious.

### `updateFromExternal` equality guard (performance fix)

The browser extension pushes `nowplaying` at ~1 Hz. Without the `t != track` guard in `updateFromExternal`, `onTrackChanged` fired every second → `ArtworkColorExtractor.paletteOffMain` ran every second → `AppSettings.setAlbumPalette` animated → SwiftUI's `LandscapeBackground` and glass layers re-rendered at 60 fps → 98% CPU at idle. The guard costs one `Track.==` check per second and eliminates the loop entirely.

### Window reuse strategy

`WindowManager` reuses the existing `NSPanel` and swaps `NSHostingController.rootView` when the style class is unchanged (non-widget to non-widget). It only rebuilds the `NSPanel` when crossing the widget/non-widget boundary (which requires a different style mask). This avoids tearing down the hosting layer (and thus the SwiftUI material/blur view hierarchy) on every size change.

### Carbon hotkeys over `NSEvent` global monitor

`NSEvent.addGlobalMonitorForEvents` requires Accessibility permission on macOS 14+. `RegisterEventHotKey` does not. The tradeoff is the Carbon C API (verbose, Unmanaged pointers), but it is the correct choice for a consumer app that should not demand Accessibility access just to pause music.

### `BrowserBridge` SSRF and DoS mitigations

The bridge is an unilateral receiver of attacker-controlled JSON (any page the user visits can push to it via the extension). Hardened:
- Max concurrent connections: 6 (oldest evicted on overflow).
- Max inbound frame size: 256 KB.
- Artwork fetch: HTTP/S only; IP/host blocklist for loopback, link-local, RFC-1918, `.local`, `.localhost`; max response size 8 MB; `data:` URIs decoded from string (never `Data(contentsOf:)`).
- Title length cap: 2048 characters.

---

## 7. Known Risks and Open Items

| Risk | Severity | Notes |
|------|----------|-------|
| `AppEnvironment.shared` is untestable | Low | No unit test suite currently exists. Introduce a per-instance `AppEnvironment` parameter if tests are added. |
| `NowPlayingService.queue` is a plain `[URL]` with an index | Medium | No shuffle, no repeat, no persistent queue. A bad index after queue mutation would crash silently (guarded by `queue.indices.contains(index)`). |
| `MetadataReader` has no cancellation | Low | If a file is replaced before the async `read` finishes, the stale result is applied. A `Task` stored per-load and cancelled on next `load` call would fix this. |
| `BrowserBridge` has no authentication | Low-Medium | Any local process can connect to port 8787 and inject arbitrary track metadata or receive transport commands. Acceptable for a loopback-only bridge; a shared secret would improve it. |
| Wallpaper restoration on crash | Medium | `SettingsEffects` saves the original wallpaper URL in memory. If the app crashes while "Cover art as wallpaper" is enabled, the user's original wallpaper is not restored. Consider persisting the saved wallpaper URLs in `UserDefaults`. |
| `ArtworkColorExtractor.paletteOffMain` creates a new `CIContext` on every call | Low | `CIContext` creation is not free. Caching one per-thread (or sharing a single one behind a lock) would reduce overhead on rapid track changes. |
| `WindowManager` position persistence uses `NSStringFromPoint` | Low | Fragile across locale changes (decimal separator in older macOS). Use `Codable` or separate `x`/`y` keys instead. |
| `NativeMediaRemoteCapture` depends on a private, undocumented Apple framework (MediaRemote, via `dlopen`/`dlsym`) | Medium | There is no public API contract here — Apple can change symbol names, further entitlement-gate the framework (already partially gated on macOS 15.4+, per its own doc comment), or remove it outright in a future macOS release, silently breaking the feature. Mitigated somewhat by the fact the toggle is OFF by default and purely supplemental (§4.2's "Native capture integration point"): a break degrades to "native capture stops updating," not a crash, and the default browser-bridge path is unaffected. Still, this is not something to build additional user-facing promises on top of without a fallback story. |
