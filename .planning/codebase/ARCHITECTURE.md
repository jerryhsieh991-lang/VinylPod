<!-- refreshed: 2026-07-03 -->
# Architecture

**Analysis Date:** 2026-07-03

## System Overview

VinylPod is a macOS **accessory (menu-bar) app** (no Dock icon by default, `LSUIElement=true`). It has exactly one piece of central mutable playback state (`NowPlayingService`) and one piece of persisted settings state (`AppSettings`), both held in the `AppEnvironment.shared` singleton. Multiple upstream producers feed the service; the UI only ever observes it.

```text
┌─────────────────────────────────────────────────────────────────────┐
│                     Producers (feed Core, never read by Views)       │
├──────────────────┬──────────────────────┬──────────────────────────┤
│ LocalAudioPlayer │  BrowserBridge        │  NativeMediaRemoteCapture │
│ `Audio/Local…`   │  `Bridge/Browser…`    │  `Capture/NativeMedia…`   │
│ AVFoundation     │  WS ws://127.0.0.1:8787│  private MediaRemote      │
│  (local path)    │  (external path)      │  (external path, opt-in)  │
└────────┬─────────┴──────────┬────────────┴───────────┬──────────────┘
         │ onTick/onFinish    │ updateFromExternal(…)   │ updateFromExternal(…)
         ▼                    ▼                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│                 Core — single source of truth                        │
│  `AppEnvironment.shared`  (`Core/Services.swift`)                    │
│   ├─ NowPlayingService  @MainActor ObservableObject                  │
│   │    @Published: track, isPlaying, position, duration              │
│   ├─ AppSettings        @MainActor ObservableObject (UserDefaults)   │
│   └─ ShortcutStore      @MainActor ObservableObject                  │
│  onTrackChanged ─► ArtworkColorExtractor ─► AppSettings.albumPalette │
│  externalControl ─► BrowserBridge.send(_:)   (transport relay back)  │
└──────────┬─────────────────────────────────────────┬────────────────┘
           │ @EnvironmentObject (observe only)        │ reads AppSettings
           ▼                                          ▼
┌───────────────────────────────┐   ┌───────────────────────────────────┐
│ Views / MenuBar (SwiftUI)     │   │ Windowing                         │
│ `Views/`, `MenuBar/`          │   │ `Windowing/WindowManager.swift`   │
│ ModeContentView → per-mode    │   │ sole owner of NSPanel(s);         │
│ glass widgets; MenuBarExtra   │   │ reuse + opacity cross-fade        │
└───────────────────────────────┘   └───────────────────────────────────┘
```

## Component Responsibilities

| Component | Responsibility | File |
|-----------|----------------|------|
| `AppEnvironment` | Singleton root holding the three services; no business logic | `Sources/VinylPod/Core/Services.swift` |
| `NowPlayingService` | Single source of truth for playback state; two update paths | `Sources/VinylPod/Core/Services.swift` |
| `AppSettings` | Persisted user prefs (UserDefaults) + derived `albumPalette`/`accentColor` | `Sources/VinylPod/Core/Services.swift` |
| `ShortcutStore` | `[ShortcutAction: KeyCombo]` persistence, drives hotkeys | `Sources/VinylPod/Core/Shortcuts.swift` |
| `LocalAudioPlayer` | AVFoundation playback; `AudioPlaying` concrete; onTick/onFinish | `Sources/VinylPod/Audio/LocalAudioPlayer.swift` |
| `MetadataReader` | Async `AVURLAsset` metadata → `Track`; `MetadataReading` | `Sources/VinylPod/Audio/MetadataReader.swift` |
| `ArtworkColorExtractor` | CoreImage palette → `AlbumColorPalette`; `ArtworkColorExtracting` | `Sources/VinylPod/Audio/ArtworkColorExtractor.swift` |
| `BrowserBridge` | Loopback WebSocket server; external now-playing ingestion + transport | `Sources/VinylPod/Bridge/BrowserBridge.swift` |
| `NativeMediaRemoteCapture` | Optional dlopen/dlsym MediaRemote adapter (off by default) | `Sources/VinylPod/Capture/NativeMediaRemoteCapture.swift` |
| `LastFmScrobbler` | Subscribes to `$track`, drives now-playing/scrobble | `Sources/VinylPod/Scrobbling/LastFmScrobbler.swift` |
| `WindowManager` | Sole owner of `NSPanel`(s); size/mode/layer transitions | `Sources/VinylPod/Windowing/WindowManager.swift` |
| `WindowCoordinator` | `@MainActor` singleton bridging SwiftUI ↔ WindowManager | `Sources/VinylPod/App/WindowCoordinator.swift` |
| `VinylPodApp` / AppDelegate | `@main` scene + wiring graph, concrete injection | `Sources/VinylPod/App/VinylPodApp.swift` |
| `SettingsEffects` | Combine-driven OS side effects (login item, wallpaper, dock) | `Sources/VinylPod/App/SettingsEffects.swift` |
| `HotKeyManager` | Carbon system-wide hotkeys (`RegisterEventHotKey`) | `Sources/VinylPod/Hotkeys/HotKeyManager.swift` |
| `ModeContentView` | Root content view dispatched per `WindowMode` | `Sources/VinylPod/Views/ModeContentView.swift` |
| `MenuBarContentView` | Menu-bar dropdown; observes `AppSettings` only | `Sources/VinylPod/MenuBar/MenuBarContentView.swift` |

## Pattern Overview

**Overall:** Single-source-of-truth reactive state with protocol-seamed dependency injection. One observable service (`NowPlayingService`) is fed by multiple producers through a single guarded ingestion method; SwiftUI views observe via `@EnvironmentObject` and never own state.

**Key Characteristics:**
- **Producer/consumer split.** `Bridge`, `Capture`, `Scrobbling` are feed-in producers; `Views`/`MenuBar` are consumers. They never touch each other — everything funnels through Core.
- **Protocol seams isolate Core from AppKit/AVFoundation.** `AudioPlaying`, `MetadataReading`, `ArtworkColorExtracting` let Core avoid importing AVFoundation/CoreImage; the whole Audio module is swappable/mockable.
- **`@MainActor` throughout.** Compile-time data-race safety (Swift 6 isolation); off-main work is explicitly bridged with `Task.detached` + `nonisolated`.
- **One reusable `NSPanel`.** `WindowManager` swaps `NSHostingController.rootView` rather than rebuilding, preserving the expensive glass/blur layer tree.

## Layers

**Core (state):**
- Purpose: owns all mutable/persisted state and the DI protocols; zero AppKit UI.
- Location: `Sources/VinylPod/Core/`
- Contains: `NowPlayingService`, `AppSettings`, `AppEnvironment`, `ShortcutStore`, `VPTheme`, `AlbumColorPalette`, `Track`/`WindowMode`/`PlaybackSource` enums, DI protocols.
- Depends on: nothing (no UIKit/AppKit, no playback API).
- Used by: everything.

**Audio (behavior, drives Core):**
- Purpose: concrete AVFoundation/CoreImage implementations of Core protocols.
- Location: `Sources/VinylPod/Audio/`
- Depends on: Core protocols and models only.
- Prohibited: UI, Services internals, Bridge.

**Producers (feed Core):**
- `Bridge/` (WebSocket external input), `Capture/` (optional native), `Scrobbling/` (Last.fm; reads `$track`).
- All push into / read from `NowPlayingService`; never read by Views.

**Windowing (NSPanel ownership):**
- Location: `Sources/VinylPod/Windowing/`
- Depends on: Core models + `AppSettings`. Prohibited from touching `NowPlayingService` directly.

**Views / MenuBar (render only):**
- Location: `Sources/VinylPod/Views/`, `Sources/VinylPod/MenuBar/`
- Observe `NowPlayingService`/`AppSettings` via `@EnvironmentObject`; reach `WindowManager` via `WindowCoordinator.shared`.

**App (wiring — the only layer allowed to touch everything):**
- Location: `Sources/VinylPod/App/` + `MenuBar/`
- `VinylPodApp.swift` (`@main`, MenuBarExtra scene, AppDelegate wiring graph), `WindowCoordinator.swift`, `SettingsEffects.swift`.

## Data Flow

### Local-File Playback Path

1. User drops files → `ModeContentView` `.onDrop` → `AppEnvironment.shared.nowPlaying.load(urls:)` (`Views/ModeContentView.swift`).
2. `NowPlayingService.playCurrent()` → `player?.load` + async `metadata?.read` → `player?.play` (`Core/Services.swift`).
3. `LocalAudioPlayer` fires `onTick` (~10 Hz) → `reportTick(position:duration:)`; `onFinish` → `reportFinished()` (`Audio/LocalAudioPlayer.swift`).
4. Real track change → `onTrackChanged` → `Task.detached` palette extraction → `AppSettings.setAlbumPalette(from:)` (`Core/Services.swift`).

### External (Browser / Spotify / Apple Music) Path

1. Extension pushes `{type:"nowplaying", payload:{…}}` over `ws://127.0.0.1:8787` (~1 Hz).
2. `BrowserBridge` validates/decodes, fetches+caches artwork, hops to `@MainActor` → `NowPlayingService.updateFromExternal(_:isPlaying:position:duration:)` (`Bridge/BrowserBridge.swift`).
3. `updateFromExternal` **change-gates** every field except `position`: `track` is re-assigned only when `t != track`; only a real change fires `onTrackChanged` → palette extraction (`Core/Services.swift`).
4. Transport commands route back: `NowPlayingService` branches on `track.source` — non-`.localFile` → `externalControl?(action)` → `BrowserBridge.send(_:)`.
5. `NativeMediaRemoteCapture` (opt-in) funnels through the **same** `updateFromExternal` entry point (tagged `.spotify`/`.appleMusic`); no third parallel path exists.

**State Management:**
- `NowPlayingService` is the only mutable playback state; all `@Published` fields are `private(set)`. Adding a new producer does not add a new consumer path — `updateFromExternal` is the one external ingestion point.

## Key Abstractions

**DI protocol seams (`Core/Services.swift`):**
- `AudioPlaying` ← `LocalAudioPlayer`; `MetadataReading` ← `MetadataReader`; `ArtworkColorExtracting` ← `ArtworkColorExtractor`. All `@MainActor`. Core never imports AVFoundation/CoreImage.

**`updateFromExternal` (single external ingestion):**
- `NowPlayingService.updateFromExternal(_:isPlaying:position:duration:)`. Guarded setter shared by `BrowserBridge` and `NativeMediaRemoteCapture`. `attachNativeCapture(settings:)` no-ops when `track.source == .localFile` so native capture never clobbers active local playback.

**`externalControl` relay:**
- `NowPlayingService.externalControl: ((ExternalControlAction) -> Void)?` wired to `BrowserBridge.send`. Transport controls for non-local sources flow back out through this closure.

**`AlbumColorPalette` (`Core/Theme.swift`):**
- Derived from artwork by `ArtworkColorExtractor.paletteOffMain(from:)` (dominant/vibrant/muted/shadow). Drives `LandscapeBackground`, `AdaptiveWidgetGlassBackground` (6-layer glass), `DesktopWidgetCanvas`, and the settings dropdown tint. `.iceMountain` is the pre-artwork fallback.

## Entry Points

**`VinylPodApp` (`Sources/VinylPod/App/VinylPodApp.swift`):**
- `@main struct VinylPodApp: App`; provides the `MenuBarExtra` scene and installs the ⌘1–⌘5 local `NSEvent` monitor (`installModeShortcuts()`). Its embedded AppDelegate runs `applicationDidFinishLaunching` — the wiring graph.

**Startup sequence (`applicationDidFinishLaunching`):** hide Dock icon → build Audio concretes → inject into `NowPlayingService` → wire onTick/onFinish/onTrackChanged → build `WindowManager` with content factories → set `WindowCoordinator.shared.manager` → `wm.show(settings.windowMode)` → start `BrowserBridge` on :8787 → wire `externalControl` → install ⌘1–⌘5 monitor → build `HotKeyManager` + register Carbon hotkeys → start `SettingsEffects` → handle launch-arg audio files.

**`WindowCoordinator` (`Sources/VinylPod/App/WindowCoordinator.swift`):**
- `@MainActor` singleton holding a weak `WindowManager` ref. Lets `AppDelegate.keyMonitor`, `MenuBarContentView`, and `ModeContentView` reach the manager without circular references.

**`MenuBarContentView` (`Sources/VinylPod/MenuBar/MenuBarContentView.swift`):**
- The menu-bar dropdown surface. Observes `AppSettings` only (NOT `NowPlayingService` directly — see Performance Invariants).

## Architectural Constraints

- **Threading:** Every service and most UI types are `@MainActor`. Metadata reading and color extraction bridge off-main via `Task.detached` + `nonisolated static` methods operating on a `Data`/`NSImage` snapshot.
- **Global state:** One intentional singleton `AppEnvironment.shared` (holds `nowPlaying`, `settings`, `shortcuts`) plus `WindowCoordinator.shared`. Both are `@MainActor`. `AppEnvironment` has no business logic.
- **Module boundaries (enforced by discipline, per CONTRACTS.md §2):** Core touches no AppKit/playback API; Audio touches only Core; Bridge/Capture/Scrobbling feed Core and never touch Views; Windowing never touches `NowPlayingService`; Views observe only environment objects.
- **Frozen contracts:** `CONTRACTS.md` freezes exact public names — `NowPlayingService` published/injected members, `AudioPlaying`/`MetadataReading`/`ArtworkColorExtracting` signatures, `WindowManager.init/show/apply`, `ModeContentView(mode:)`. Core and `Package.swift` are read-only per the contract header.

## Anti-Patterns

### Observing `NowPlayingService` in an always-on parent view

**What happens:** A structurally-alive view (menu-bar root, dynamic-island root, hosting-controller root) holds `@EnvironmentObject var nowPlaying: NowPlayingService`.
**Why it's wrong:** `position` is `@Published` and rewritten ~10 Hz (local) / ~1 Hz (bridge). Any such body re-runs on every tick → a self-sustaining 98% idle-CPU loop (traced to `MainMenuItemHost.requestUpdate`/`GraphHost.updatePreferences`).
**Do this instead:** Parent shells observe only `AppSettings`; push `nowPlaying` observation down to leaf views (`NowPlayingMenuSection`, `IslandTimeRow`) that actually display playback data. See `docs/system-design/05-security-performance-build.md` §3.

### Writing extra fields unconditionally on every tick

**What happens:** A new `@Published` field is assigned every `updateFromExternal`/`reportTick` call.
**Why it's wrong:** Every unconditional assignment invalidates observers, defeating the change-gate.
**Do this instead:** Only `position` is written unconditionally; all other fields are equality-guarded before assignment (`Core/Services.swift`). Display sites coarsen to whole seconds (`Int(position)`).

### `.id(mode)` pinning for size switches

**What happens:** Assigning a per-mode `.id` to the mode content forces SwiftUI to destroy/recreate the landscape + glass `NSVisualEffectView` subtree.
**Why it's wrong:** Recreation renders the outgoing layout at the incoming window size → visible stretch/blank flash.
**Do this instead:** Keep the single stable `.id("vinylpod.content")` on the shell and cross-fade only the inner `content` with `.transition(.opacity)` + `.animation(VPTheme.fade, value: mode)` (`Views/ModeContentView.swift`).

## Performance Invariants (render-loop rules — mandatory)

From `docs/system-design/05-security-performance-build.md` §3. Violating these historically caused a 98% idle-CPU loop.

1. **Never observe `NowPlayingService` in an always-on parent view.** Push observation to leaf views.
2. **`position` must remain the only unconditionally-written field** on `NowPlayingService`; all other fields equality-guarded before assignment.
3. **Leaf views displaying position must coarsen to whole seconds** (`Int(position)`), never render raw `TimeInterval`.
4. **`setAlbumPalette` must be called only on real track changes** (`onTrackChanged` fires only when `trackChanged`), plus its own `palette != albumPalette` guard.
5. **Size-switch transitions must use `.transition(.opacity)` cross-fades, not `.id(mode)` pinning.**
6. **The `modeTransitionInFlight` guard in `WindowManager.apply(mode:)` must stay** — drops duplicate in-flight transitions from rapid taps.

Corollaries realized in the UI: `IslandTimeRow` is the only view reading `position` in the dynamic island; `EqualizerBars` uses `TimelineView(minimumInterval: 1/30, paused: !active)`; `SettingsWindow` binds only to `AppSettings`, never `NowPlayingService`.

## Error Handling

**Strategy:** Defensive guards + graceful degradation rather than throwing propagation. The app has no server-side logic and no unit test suite.

**Patterns:**
- Queue index bounds guarded with `queue.indices.contains(index)` (silent no-op rather than crash).
- `BrowserBridge` validates/drops malformed frames; SSRF/DoS mitigations reject bad artwork URLs and oversized frames silently (see §"Cross-Cutting").
- Hotkey registration conflicts are silently skipped; unknown persisted shortcut keys are dropped (forward-compat).
- Native capture breakage degrades to "stops updating," never a crash; browser-bridge path is unaffected.

## Cross-Cutting Concerns

**Logging:** No structured logging framework observed; diagnosis is via `Instruments`/`sample` for the render-loop invariants.
**Validation / security (`BrowserBridge`):** Loopback-only bind (`127.0.0.1:8787`), 6-connection cap, 256 KB max frame, HTTP/S-only artwork with loopback/link-local/RFC-1918/`.local` blocklist, 8 MB response cap, manual `data:` URI decode, 2048-char title cap. The bridge is the single ingestion point for attacker-influenced input; the app is unsandboxed so this is the only confinement layer.
**Authentication:** None between extension and bridge — any local process knowing port 8787 can inject. Accepted for a loopback bridge.
**OS side effects:** Centralized in `SettingsEffects` (Combine sinks on `AppSettings`/`NowPlayingService`) — login item, activation policy, dock artwork, wallpaper (reversible capture/restore).

---

*Architecture analysis: 2026-07-03*
