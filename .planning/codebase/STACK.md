# Technology Stack

**Analysis Date:** 2026-07-03

## Languages

**Primary:**
- Swift 5.9 (`swift-tools-version:5.9` in `Package.swift`) - Entire native macOS app under `Sources/VinylPod/`
- JavaScript (ES2020, vanilla, no build step) - MV3 browser extension under `BrowserExtension/`

**Secondary:**
- Swift - Safari Web Extension host wrapper under `SafariExtension/VinylPodConnect/` (Xcode project, `SafariWebExtensionHandler.swift`, `AppDelegate.swift`)

## Runtime

**Environment:**
- macOS 13.0+ (`platforms: [.macOS(.v13)]` in `Package.swift`; `LSMinimumSystemVersion 13.0` in `make_app.sh` Info.plist)
- Menu-bar accessory app (`LSUIElement=true`, no Dock icon)
- Browser extension targets Chrome 102+ (`minimum_chrome_version` in `BrowserExtension/manifest.json`), plus Safari via the wrapper

**Package Manager:**
- Swift Package Manager (SPM) — single `Package.swift`, no external package dependencies
- No lockfile with third-party pins (dependency list is empty)
- Browser extension has NO package manager / npm — plain static `.js` files loaded directly

## Frameworks

**Core (all first-party Apple, no third-party):**
- SwiftUI - Primary UI layer (32 files import it) - widgets, settings, views
- AppKit - Menu bar, windowing, `NSImage`, `NSStatusItem` (29 files import it)
- Network (`NWListener` / `NWProtocolWebSocket`) - Loopback WebSocket bridge in `Sources/VinylPod/Bridge/BrowserBridge.swift`
- AVFoundation - Local audio playback + metadata (`Sources/VinylPod/Audio/LocalAudioPlayer.swift`, `MetadataReader.swift`)
- CoreImage / CoreGraphics - Album-artwork color extraction (`Sources/VinylPod/Audio/ArtworkColorExtractor.swift`)
- CryptoKit - MD5 signing of Last.fm API requests (`Sources/VinylPod/Scrobbling/LastFmClient.swift`)
- Combine - Reactive state (`NowPlayingService`, `LastFmScrobbler`)
- Carbon.HIToolbox - Global hotkey registration (`Sources/VinylPod/Hotkeys/HotKeyManager.swift`)
- ServiceManagement - Launch-at-login (`Sources/VinylPod/App/SettingsEffects.swift`)
- UniformTypeIdentifiers - Drag-and-drop / file-type handling

**Private framework (runtime-resolved, NOT linked):**
- MediaRemote (`/System/Library/PrivateFrameworks/MediaRemote.framework`) - resolved via `dlopen`/`dlsym` in `Sources/VinylPod/Capture/NativeMediaRemoteCapture.swift`. Never linked, so the app loads even when symbols are absent or entitlement-gated (macOS 15.4+ returns empty dicts to unsigned apps).

**Testing:**
- XCTest (implied by `Tests/` directory) - See TESTING.md

**Build/Dev:**
- `swift build` (Command Line Tools only — no Xcode, no `xcodebuild`)
- `make_app.sh` - Wraps the bare SPM binary into a runnable `dist/VinylPod.app` bundle (writes `Info.plist`, ad-hoc `codesign --sign -`)

## Key Dependencies

**Critical:**
- NONE. The project has zero third-party Swift or JS dependencies. All capability comes from Apple system frameworks and vanilla JS. This is an intentional design choice (noted throughout source, e.g. BrowserBridge "no dependencies").

**Infrastructure:**
- Apple system frameworks only (see Frameworks above)

## Configuration

**Toolchain Workaround (`@VPState`):**
- Defined in `Sources/VinylPod/Core/Theme.swift`: `typealias VPState = SwiftUI.State`
- Reason: the macOS 26+ SDK declares `@State` as a Swift *macro* whose `SwiftUIMacros` plugin ships only with full Xcode, not Command Line Tools. Aliasing the property-wrapper TYPE dodges the macro of the same name.
- Convention: ALL view-local state uses `@VPState`, never `@State`. Enforced across all `Views/**` files (e.g. `ModeContentView.swift`, `DynamicIslandWidget.swift`, `ShortcutRecorderView.swift`).

**Environment:**
- Last.fm credentials are hardcoded constants (`LASTFM_API_KEY` / `LASTFM_API_SECRET`) in `Sources/VinylPod/Scrobbling/LastFmClient.swift`, empty by default — the whole scrobbling subsystem no-ops until both are filled.
- User preferences persist via `UserDefaults` (`AppSettings` in `Sources/VinylPod/Core/Services.swift`).
- Feature manifests as JSON at repo root (`widget_features.json`, `settings_features.json`, `desktop_widget_features.json`, etc.) and `BrowserExtension/extension_backend_features.json`.

**Build:**
- `Package.swift` - single executable target `VinylPod`, `path: "Sources/VinylPod"`, `.process("Resources")`
- `make_app.sh` - bundling + Info.plist + ad-hoc codesign

## Platform Requirements

**Development:**
- macOS with Command Line Tools (Xcode NOT required for the main app; required only for the `SafariExtension/` Xcode project)
- Swift 5.9+ toolchain

**Production:**
- macOS 13.0+ end-user machine
- Optional: a Chromium/Firefox/Safari browser with the "VinylPod Connect" extension installed for browser-source capture

---

*Stack analysis: 2026-07-03*
