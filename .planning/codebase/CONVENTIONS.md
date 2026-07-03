# Coding Conventions

**Analysis Date:** 2026-07-03

VinylPod is a two-language codebase: native macOS Swift (SwiftUI + AppKit) in `Sources/VinylPod/`, and a Manifest V3 browser extension (plain JS, no build step) in `BrowserExtension/`. Conventions differ per language; both are documented below.

## Naming Patterns

**Swift files:**
- One primary type per file, filename matches the type: `NowPlayingService.swift` → `NowPlayingService`, `BrowserBridge.swift` → `BrowserBridge`.
- Files grouped by module directory, not by type-kind: `Sources/VinylPod/Core/`, `Audio/`, `Bridge/`, `Capture/`, `Views/`, `Views/Widget/`, `Views/Settings/`, `Scrobbling/`, `Hotkeys/`, `Windowing/`, `MenuBar/`, `App/`.
- Design-system type is namespaced `VPTheme` / `VPState` with the `VP` prefix; most other types are unprefixed (`Track`, `AppSettings`, `HotKeyManager`).

**Swift types:** UpperCamelCase. Enums for closed sets with `String, Codable, CaseIterable` conformances (`PlaybackSource`, `WindowMode`, `DesktopLayer`, `VinylStyle` in `Sources/VinylPod/Core/Models.swift`). Value types (`struct`) for immutable snapshots (`Track`, `RGBColorToken`); reference types (`final class`) for services/state owners.

**Swift functions / vars:** lowerCamelCase. Enum cases lowerCamelCase (`.localFile`, `.appleMusic`, `.desktopWidget`).

**JS files:** kebab-case (`cs-common.js`, `service-worker.js`, `universal-relay.js`, `mediasession-main.js`); per-site adapters live in `BrowserExtension/sites/` (`spotify.js`, `apple-music.js`, `youtube.js`, `youtube-music.js`). JS functions/vars are lowerCamelCase; module-level constants are SCREAMING_SNAKE (`POLL_MS`, `MAX_TEXT`, `MAX_URL`, `WS_URL`).

## The `@VPState` / `VPState` typealias pattern (CRITICAL)

**Rule:** In SwiftUI views, view-local state uses `@VPState`, NEVER `@State`. `@ObservedObject` / `@StateObject` / `@Published` / `@Binding` are used normally.

**Definition:** `Sources/VinylPod/Core/Theme.swift:51`
```swift
typealias VPState = SwiftUI.State
```

**Why it exists (documented at `Theme.swift:47-50`):** The macOS 26+ SDK declares `@State` as a *macro* whose `SwiftUIMacros` plugin ships only with full Xcode — NOT with the Command Line Tools toolchain this project builds under (`swift build`, see `make_app.sh`). Referencing `@State` therefore fails to compile under CLT. Aliasing the underlying property-wrapper *type* (`SwiftUI.State`) sidesteps the same-named macro, giving identical runtime behavior with a name the macro expansion never touches.

**When writing new views:** declare `@VPState private var hovering = false` (see `Sources/VinylPod/Views/TransportControls.swift:73`, `ProgressBarView.swift:16`, `Views/Widget/DynamicIslandWidget.swift:24`). Many view files carry an inline reminder comment, e.g. `Views/Widget/AlbumArtCloseButton.swift:32` ("View-local state (CLT workaround: @VPState, never @State).").

## `@Published` equality-guard discipline (PERFORMANCE INVARIANT — CRITICAL)

**Rule:** Never re-assign an `@Published` property (or fire a change callback) unless the value actually changed. Every setter that runs at tick frequency MUST guard with an equality check.

**Why:** The browser bridge and native capture push state ~1×/sec. Blindly re-assigning `track` / firing `onTrackChanged` each tick re-ran dominant-color extraction and re-triggered the 60fps liquid-glass/landscape animation, producing a self-sustaining ~98% CPU render loop. This is documented in-code and is a hard invariant.

**Canonical example** — `NowPlayingService.updateFromExternal` in `Sources/VinylPod/Core/Services.swift`:
```swift
let trackChanged = (t != track)
if trackChanged { track = t }
if isPlaying != playing { isPlaying = playing }
position = pos                       // the ONE field that legitimately changes each tick
if duration != dur { duration = dur }
if trackChanged { onTrackChanged?(t) }   // expensive color/animation work — gated
```
Same pattern in `setBridgeConnected` (`if bridgeConnected != connected { … }`). New push-path code must follow it. `Track.==` (`Models.swift`) is a custom equality over identity fields (title/artist/album/url/source) — artwork is deliberately excluded so image loads don't count as "changed".

**Mirror guard on the JS side:** `BrowserExtension/cs-common.js` diffs serialized state (`lastSerialized`) and only reports on change, and clamps untrusted DOM strings (`MAX_TEXT = 512`, `MAX_URL = 2048`) before they cross the messaging boundary.

## MVVM / Service Patterns

- **Single source of truth:** `NowPlayingService` (`Sources/VinylPod/Core/Services.swift`) is a `@MainActor final class … : ObservableObject` holding `@Published private(set)` state (`track`, `isPlaying`, `position`, `duration`, `bridgeConnected`). Views observe it; the Audio module drives it; menu bar and shortcuts command it. Writes are internal-only (`private(set)`).
- **Seam protocols for injection:** Core defines `@MainActor` protocols (`AudioPlaying`, `MetadataReading`, `ArtworkColorExtracting` in `Services.swift`) implemented by the Audio module (`LocalAudioPlayer`, `MetadataReader`, `ArtworkColorExtractor`). Dependencies are injected as `var player: AudioPlaying?` etc., which keeps Core decoupled and makes the seams unit-testable.
- **Concurrency:** UI/state classes are annotated `@MainActor`. Background numeric work uses `Sendable` value tokens (`RGBColorToken: Equatable, Sendable`) so only plain numbers cross actors; SwiftUI `Color`/`NSImage` stay on the main actor.
- **Settings as observable store:** `AppSettings` (`@MainActor ObservableObject`) persists each property to `UserDefaults` via `didSet` and re-reads in `init()`. Side effects of settings changes live in a separate `SettingsEffects` (`Sources/VinylPod/App/SettingsEffects.swift`) that subscribes with Combine sinks — settings state and OS side effects are kept separate.

## Memory-Management Discipline (enforced by tests)

- **Weak captures in long-lived closures are mandatory.** Anything wired for a 24/7 session captures `[weak self]` / `[weak bridge]` / `[weak manager]`:
  - `svc.externalControl = { [weak bridge] action in bridge?.send(action) }`
  - `store.onChange = { [weak manager] in manager?.reload(from: store) }`
  - `NWConnection`/listener handlers in `BrowserBridge` and Combine sinks in `SettingsEffects` all capture weakly.
- These are asserted via deinit/weak-ref tracking in `Tests/VinylPodBackendTests/MemoryLeakPreventionTests.swift`. New listener/timer/closure owners must be cycle-free and should get a matching leak test.

## Error / Empty / Loading State Handling

- **No spinners.** State transitions (empty ↔ playing ↔ error) are smooth fades via design tokens: `VPTheme.fade = Animation.easeInOut(duration: 0.45)` (`Theme.swift`).
- **Empty state is a first-class value:** `Track.empty` / `Track.isEmpty` (`Models.swift`); `PlaybackSource.none` renders as "VinylPod" with the `opticaldisc` SF Symbol.
- **Defensive early-returns / guards** rather than throwing across boundaries: bridge ingest drops frames with empty title (`guard let title = p.title, !title.isEmpty`), `SettingsEffects` guards `NSApp != nil` before OS calls and wraps OS calls in `try?`.
- **Optional-not-error for missing data:** color extraction returns `Color?` / `AlbumColorPalette?` (nil = unavailable), consumers fall back to `VPTheme.accentFallback`.

## Design Tokens / Glassmorphism Usage

- **All visual constants come from `VPTheme` (`Sources/VinylPod/Core/Theme.swift`) — never hard-code colors, radii, fonts, or animations in views.** Tokens: text (`textPrimary/Secondary/Muted`), glass surfaces (`scrim`, `scrimStrong`, `glassTint`, `glassStroke`, `panel`), accent fallback (`iceAccent`, `accentFallback`), shape (`radius` 14 / `radiusSmall` 10 / `radiusLarge` 22), motion (`fade`, `liquid`, `spring`), fonts (`VPTheme.title/body/caption(_:)` using `.system(design: .default)`).
- **Album-reactive liquid glass** is the core mood: current artwork drives the palette (`ArtworkColorExtractor` → `RGBColorToken`/`AlbumColorPalette` → `AppSettings.albumPalette`). Reusable glass surfaces live in `Sources/VinylPod/Views/GlassPanel.swift`, `VisualEffectBlur.swift`, and `Views/Widget/AdaptiveWidgetGlassBackground.swift`. See `design_system.md` (repo root) and `docs/system-design/06-design-system.md` for the full spec.

## Browser-Extension JS Conventions

- **`"use strict";` at the top of every file**; content-script bodies wrapped in an IIFE `(function () { "use strict"; … })()`.
- **Manifest V3 hard rules:** no `eval`, no remote code. The service worker (`service-worker.js`) is an event worker that tolerates teardown/restart; durable state goes in `chrome.storage.session`, live per-tab records in an in-memory `Map`.
- **Adapter pattern for sites:** each `sites/*.js` defines an adapter `{ source, readState(), controls:{playpause,next,prev,seek} }` and calls the shared `window.VinylPodRun(adapter)` in `cs-common.js`, which owns the poll loop (`POLL_MS = 1000`), change-diffing, reporting, and control listener. Keep site adapters tiny; put shared behavior in `cs-common.js`.
- **Isolated vs MAIN world:** DOM-scraping adapters run in the isolated world; `navigator.mediaSession` access runs in the MAIN world (`mediasession-main.js`, declared `"world": "MAIN"` + `web_accessible_resources`). `universal-relay.js` bridges them for unsupported sites.
- **Untrusted-input clamping** at the capture boundary (`clampText`, `clampURL`, finite/non-negative numeric coercion in `normalize`) — a malicious/broken page must never push unbounded or NaN/Infinity values downstream.
- **Frozen wire contract:** the WS payload shape `{ source,title,artist,album,artwork,isPlaying,currentTime,duration }` pushed to `ws://127.0.0.1:8787` is frozen and documented in `BrowserExtension/data_flow.md` and `CONTRACTS.md`; the Swift bridge decodes the identical shape. Changing it requires updating both sides and the mirroring test.

## Comments

- Swift types and non-trivial methods carry `///` doc comments explaining *intent and invariants*, not mechanics — heavily used to record the "why" behind perf guards and the CLT workaround. `// MARK: -` separates sections within files.
- JS files open with a block-comment header describing the file's responsibility, MV3 compliance notes, and the adapter/message contract.

---

*Convention analysis: 2026-07-03*
