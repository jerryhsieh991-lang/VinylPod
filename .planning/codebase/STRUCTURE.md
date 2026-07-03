# Codebase Structure

**Analysis Date:** 2026-07-03

## Directory Layout

```
VinylPodMac/
├── Package.swift              # SPM manifest (single executableTarget, macOS .v13)
├── make_app.sh               # bundles release binary → dist/VinylPod.app
├── CONTRACTS.md              # FROZEN module contracts (exact public names)
├── design_system.md          # liquid-glass design language spec
├── PRD.md / README.md        # product docs
├── *_features.json           # per-surface feature inventories (widget/settings/etc.)
├── Sources/VinylPod/         # all Swift source (see below)
├── Tests/                    # test target (minimal)
├── e2e/                      # Playwright/node E2E + bridge stress test
├── docs/system-design/       # 00–07 architecture slice docs (authoritative)
├── BrowserExtension/         # Chrome/universal WebExtension (not part of SPM)
├── SafariExtension/          # Safari App Extension Xcode project (not part of SPM)
└── dist/                     # generated .app bundles; gitignored
```

```
Sources/VinylPod/
├── App/                      # Entry point, lifecycle wiring, OS side effects
│   ├── VinylPodApp.swift          — @main App + AppDelegate wiring graph; ⌘1–⌘5 monitor
│   ├── WindowCoordinator.swift    — @MainActor singleton → WindowManager
│   └── SettingsEffects.swift      — Combine-driven OS side effects
├── Core/                     # Owned state + DI protocols (zero AppKit UI)
│   ├── Models.swift               — Track, WindowMode, PlaybackSource, DesktopLayer enums
│   ├── Services.swift             — NowPlayingService, AppSettings, AppEnvironment, protocols
│   ├── Shortcuts.swift            — ShortcutStore, ShortcutAction, KeyCombo
│   └── Theme.swift                — VPTheme tokens, AlbumColorPalette
├── Audio/                    # Concrete Core-protocol implementations (no UI)
│   ├── LocalAudioPlayer.swift     — AVAudioPlayer; AudioPlaying
│   ├── MetadataReader.swift       — async AVURLAsset; MetadataReading
│   └── ArtworkColorExtractor.swift— CoreImage palette; ArtworkColorExtracting
├── Bridge/                   # External now-playing input
│   └── BrowserBridge.swift        — loopback WebSocket server (NWListener, :8787)
├── Capture/                  # OPTIONAL native desktop-app capture (off by default)
│   └── NativeMediaRemoteCapture.swift — dlopen/dlsym MediaRemote adapter
├── Scrobbling/               # Last.fm integration
│   ├── LastFmScrobbler.swift      — ObservableObject; subscribes to $track
│   ├── LastFmClient.swift         — API session + auth handshake
│   └── LastFmModels.swift         — DTOs
├── Windowing/                # NSWindow/NSPanel ownership
│   └── WindowManager.swift        — sole NSPanel owner; mode/size/layer transitions
├── MenuBar/                  # Menu-bar popover surface
│   └── MenuBarContentView.swift   — dropdown UI (observes AppSettings only)
├── Hotkeys/                  # System-wide Carbon hotkeys
│   └── HotKeyManager.swift        — RegisterEventHotKey (no Accessibility perm)
├── Resources/                # Bundled assets (.process rule)
│   └── majestic-ice-mountain-stockcake.jpg
└── Views/                    # SwiftUI rendering only (reads environment objects)
    ├── ModeContentView.swift      — root content dispatched per WindowMode
    ├── LandscapeBackground.swift  — static scenic backdrop (never reacts to track)
    ├── GlassPanel.swift           — reusable liquid-glass material
    ├── VisualEffectBlur.swift     — NSVisualEffectView wrapper
    ├── ProgressBarView.swift      — playback progress bar
    ├── TransportControls.swift    — prev/play/next tinted with accentColor
    ├── Widget/                    — per-mode glass widgets (see modes below)
    │   ├── SmallGlassWidget.swift
    │   ├── RegularGlassWidget.swift
    │   ├── LargeGlassWidget.swift
    │   ├── DesktopWidgetCanvas.swift
    │   ├── DynamicIslandWidget.swift
    │   ├── AdaptiveWidgetGlassBackground.swift — 6-layer glass primitive
    │   ├── MusicVisualizerContainerView.swift
    │   ├── VinylDiskView.swift
    │   ├── AlbumArtCloseButton.swift
    │   ├── SettingsMenu.swift              — three-dot popover (SettingsMenuButton)
    │   ├── ShortcutRecorderView.swift
    │   └── KeyboardShortcutsWindow.swift
    └── Settings/                  — tabbed Settings NSWindow (observes AppSettings only)
        ├── SettingsWindow.swift            — TabView host + SettingsWindowController
        ├── GeneralSettingsSection.swift
        ├── AppearanceSettingsSection.swift
        ├── CaptureSettingsSection.swift    — native-capture toggle
        ├── LastFmSettingsSection.swift     — scrobble toggle + connect flow
        └── AboutSettingsSection.swift
```

## Directory Purposes

**`Sources/VinylPod/Core/`:**
- Purpose: single-source-of-truth state + DI protocol seams; imports no AppKit/AVFoundation.
- Key files: `Services.swift` (all three services + protocols), `Theme.swift` (`VPTheme`, `AlbumColorPalette`), `Models.swift` (all enums).

**`Sources/VinylPod/Views/Widget/`:**
- Purpose: one file per window-mode glass widget plus shared glass primitives.
- Key files: `AdaptiveWidgetGlassBackground.swift` (used by Small/Medium/Regular/Large), `DesktopWidgetCanvas.swift`, `DynamicIslandWidget.swift`.

**`Sources/VinylPod/Views/Settings/`:**
- Purpose: the long-tail tabbed Settings window (General/Appearance/Sources/Shortcuts/About). Structurally forbidden from observing `NowPlayingService`.

**`docs/system-design/`:**
- Purpose: authoritative architecture slices (00 vision, 01 core-arch, 02 windowing/UI, 03 capture/bridge, 04 audio/media, 05 security/perf/build, 06 design-system, 07 feature-inventory). Read these before touching the matching module.

## Key File Locations

**Entry Points:**
- `Sources/VinylPod/App/VinylPodApp.swift`: `@main` App + AppDelegate wiring graph.
- `Sources/VinylPod/App/WindowCoordinator.swift`: SwiftUI ↔ WindowManager bridge.

**Configuration:**
- `Package.swift`: SPM manifest — single `executableTarget`, `macOS(.v13)`, `.process("Resources")`, no external deps.
- `make_app.sh`: build → `.app` bundle → ad-hoc codesign (`Info.plist` with `LSUIElement=true`, id `com.vinylpod.widget`).
- `CONTRACTS.md`: frozen public-name contract; Core and `Package.swift` are read-only.

**Core Logic:**
- `Sources/VinylPod/Core/Services.swift`: `NowPlayingService`, `AppSettings`, `AppEnvironment`, DI protocols.
- `Sources/VinylPod/Windowing/WindowManager.swift`: NSPanel ownership + transitions.
- `Sources/VinylPod/Bridge/BrowserBridge.swift`: external ingestion + security hardening.

**Testing:**
- `Tests/`: SPM test target (minimal).
- `e2e/e2e_size_switching.spec.js`, `e2e/bridge_stress_test.js`: integration/stress harnesses.

## Naming Conventions

**Files:**
- One primary type per file, filename == type name (`WindowManager.swift`, `SmallGlassWidget.swift`).
- Settings tab sections suffixed `SettingsSection.swift`; widget views suffixed `Widget.swift`/`Canvas.swift`/`View.swift`.

**Directories:**
- PascalCase, named by architectural role (`Core`, `Audio`, `Bridge`, `Windowing`, `Views/Widget`, `Views/Settings`).

**Types:**
- Design tokens namespaced under `VPTheme`; `@VPState` typealias for `SwiftUI.State` (CLT build, avoids `@State` macro plugin).
- Carbon hotkey signature OSType `0x56504B59` ("VPKY").

## Window Modes

Five modes in `WindowMode` (`Sources/VinylPod/Core/Models.swift`), shortcuts ⌘1–⌘5:

| Mode | `displayName` | `defaultSize` | Widget file | Style class |
|------|--------------|---------------|-------------|-------------|
| `.small` | Small | 162 × 162 | `SmallGlassWidget.swift` | Non-widget (shadow, `.floating`, movable) |
| `.normal` | Medium | 344 × 132 | `MediumGlassWidget` (in Widget/) | Non-widget |
| `.regular` | Regular | 300 × 360 | `RegularGlassWidget.swift` | Non-widget |
| `.large` | Large | 320 × 432 | `LargeGlassWidget.swift` | Non-widget |
| `.desktopWidget` | Desktop | screen frame | `DesktopWidgetCanvas.swift` | Widget (no shadow, stationary, layer per `DesktopLayer`) |

Plus a **Dynamic Island** (`DynamicIslandWidget.swift`) — an *optional* separate `NSPanel` at `kCGStatusWindowLevel`, not a `WindowMode`. Collapsed pill 390 × 30, expanded 430 × 700; gated by `settings.dynamicNotch`.

Crossing the **widget ↔ non-widget** style-class boundary forces a new `NSPanel` (different style mask); all other transitions reuse the panel and swap `rootView` with an opacity cross-fade.

## Where to Add New Code

**New window/widget mode:**
- Add case to `WindowMode` (`Core/Models.swift`) with `displayName`/`defaultSize`/`shortcutKey`.
- Add widget view under `Views/Widget/`; dispatch it in `ModeContentView.swift`.

**New now-playing producer (like Bridge/Capture):**
- Add a folder + file at `Sources/VinylPod/<Producer>/`; push into `NowPlayingService.updateFromExternal(...)`. Do NOT add a new consumer path or let Views read it.

**New Core protocol implementation:**
- Implement the seam protocol in `Sources/VinylPod/Audio/` (or a new behavior module); inject at `applicationDidFinishLaunching` in `App/VinylPodApp.swift`. Never reference the concrete from Core.

**New setting:**
- Add `@Published` property to `AppSettings` (`Core/Services.swift`) with a `didSet` UserDefaults persist; surface it in `Views/Settings/<Tab>SettingsSection.swift` and/or `Views/Widget/SettingsMenu.swift`. Any OS side effect goes in `App/SettingsEffects.swift`.

**Shared SwiftUI helpers:**
- Reusable materials/controls at `Sources/VinylPod/Views/` root (`GlassPanel.swift`, `VisualEffectBlur.swift`, `TransportControls.swift`).

## Special Directories

**`dist/`:**
- Purpose: generated `.app` bundles from `make_app.sh`. Generated: Yes. Committed: No (gitignored).

**`BrowserExtension/` & `SafariExtension/`:**
- Purpose: the browser-side WebExtension that feeds `BrowserBridge`. Generated: No. Committed: Yes. NOT part of the SPM target — built separately (Safari via its own `.xcodeproj`).

**`Sources/VinylPod/Resources/`:**
- Purpose: bundled assets copied via `.process("Resources")`. Contains the fallback `majestic-ice-mountain-stockcake.jpg` landscape.

**`.ui_backup_*/`:**
- Purpose: dated UI backup snapshots. Generated: Yes. Committed: incidental — not a source directory.

---

*Structure analysis: 2026-07-03*
