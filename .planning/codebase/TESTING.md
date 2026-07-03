# Testing Patterns

**Analysis Date:** 2026-07-03

VinylPod has three distinct verification layers, none of them a conventional CI test pyramid:
1. **Swift backend unit tests** (XCTest) in `Tests/VinylPodBackendTests/` — the only automated, assertion-based suite.
2. **Native macOS E2E harnesses** in `e2e/` — a JXA (osascript) Accessibility driver and a Node WebSocket stress driver, each emitting a JSON report.
3. **Manual / MCP-driven browser verification** — the browser extension is verified by driving real music sites with Playwright MCP (artifacts in `.playwright-mcp/`).

## Test Framework

**Swift unit tests:**
- Framework: **XCTest** (`import XCTest`, `@testable import VinylPod`).
- No separate test target is declared in `Package.swift` (it declares only the `.executableTarget`). Tests live in `Tests/VinylPodBackendTests/` and are `@testable`-importing the executable target; run via `swift test`.
- All suites are `@MainActor final class …: XCTestCase` (the code under test is `@MainActor`).

**E2E:**
- `e2e/e2e_size_switching.spec.js` — **JavaScript for Automation (JXA)** run with `osascript -l JavaScript`. Drives the *live app* through macOS System Events / Accessibility. NOT Playwright.
- `e2e/bridge_stress_test.js` — **Node.js** (`#!/usr/bin/env node`), stdlib only (`node:net`, `node:crypto`, `node:child_process`, `node:perf_hooks`). Raw WebSocket load generator against the app's local bridge.

**Run commands:**
```bash
swift test                                              # Swift unit suite
osascript -l JavaScript e2e/e2e_size_switching.spec.js  # native size-switching E2E (app must be running)
node e2e/bridge_stress_test.js                          # bridge WebSocket stress (app must be running on :8787)
./make_app.sh release                                   # build + bundle → dist/VinylPod.app (build verification)
./make_app.sh debug                                     # debug build
```

## Test File Organization

- **Location:** separate `Tests/` tree, mirroring the "backend node" decomposition rather than the source directory layout.
- **Naming:** `<Node>Tests.swift`. Each file maps to a named backend node and is headed by a `/// NODE (x) — <Name>.` doc comment:
  - `StateSyncBridgeTests.swift` — NODE (a) State_Sync_Bridge
  - `LocalSettingsDBTests.swift` — NODE (b) Local_Settings_DB
  - `GlobalShortcutOSHookTests.swift` — NODE (c) Global_Shortcut_OS_Hook
  - `MemoryLeakPreventionTests.swift` — NODE (d) Memory_Leak_Prevention
- E2E harnesses live outside `Sources/` and deliberately do not import or mutate core app code (documented in the `e2e_size_switching.spec.js` header).

## Test Structure

Each suite opens with a rich `///` doc comment stating the contract under test and *why the seam is tested the way it is*. Tests are `func test…()` with descriptive assertion messages. `throws` + `try XCTUnwrap` is the standard optional-unwrapping idiom.

```swift
@MainActor
final class GlobalShortcutOSHookTests: XCTestCase {
    override func setUp()   { super.setUp(); /* snapshot UserDefaults */ }
    override func tearDown(){ /* restore UserDefaults */; super.tearDown() }

    func testKeyComboParsesModifiersAndKey() throws {
        let event = try XCTUnwrap(keyDown(keyCode: UInt16(kVK_ANSI_P), chars: "p", flags: [.command, .shift]))
        let combo = try XCTUnwrap(KeyCombo.from(event), "⌘⇧P must parse to a KeyCombo")
        XCTAssertEqual(combo.keyCode, UInt32(kVK_ANSI_P))
    }
}
```

**Patterns:**
- **UserDefaults isolation via snapshot/restore.** Suites that touch `UserDefaults.standard` (`LocalSettingsDBTests`, `GlobalShortcutOSHookTests`) snapshot the exact keys they use in `setUp`, wipe them, and restore in `tearDown` so the developer's real prefs are never polluted. See `LocalSettingsDBTests.swift` (`keys` array + `saved` dict).
- **"Relaunch" simulation** is the dominant idiom for persistence: mutate one instance, construct a *fresh* instance, assert it re-reads the persisted value (`AppSettings` round-trips; `ShortcutStore` round-trips a `KeyCombo`).
- **`autoreleasepool` + `weak var` deinit tracking** for leak tests (`MemoryLeakPreventionTests`).

## What Is Covered

- **State-sync bridge contract** (`StateSyncBridgeTests`): a representative `{type:"nowplaying", payload:{…}}` extension frame decodes and maps onto `NowPlayingService` (`isPlaying`, `duration`, `position`, derived `source`); `mapSource` string→`PlaybackSource` mapping; empty/`null`-payload "gone" frames are rejected (no-clobber guard); dominant-color derivation from artwork via `ArtworkColorExtractor`.
- **Settings persistence** (`LocalSettingsDBTests`): bool/enum/URL settings survive relaunch; code defaults honored on a clean store.
- **Global shortcut OS hook** (`GlobalShortcutOSHookTests`): `KeyCombo.from(NSEvent)` parse + Carbon modifier translation (⌘⇧ bitmask correctness); modifier-less keys rejected; `ShortcutStore` persist + `onChange` firing; `HotKeyManager.reload` reaches the real Carbon `RegisterEventHotKey`/`InstallEventHandler` path without crashing.
- **Memory-leak prevention** (`MemoryLeakPreventionTests`): `BrowserBridge`, `SettingsEffects`, and the weak `externalControl` / `ShortcutStore.onChange` wirings all deallocate — proving no retain cycles in the 24/7 listener/timer/closure graph.
- **Native size-switching E2E** (`e2e_size_switching.spec.js`): launches/detects the app, cycles Small→Medium→Regular→Large→Desktop, and verifies per-mode window constraints (exact sizes for floating modes, min-size + non-floating for desktop widget).
- **Bridge stress** (`bridge_stress_test.js`): connection churn, high-rate text/binary frames, buffered-bytes cap, event-loop delay, and RSS-growth thresholds against `ws://127.0.0.1:8787` — enforces `failOnDropRate` (5%) and `failOnRssGrowthMb` (150 MB) pass/fail gates.

## Mocking / Test Doubles

- **No mocking framework.** Doubles are hand-rolled and minimal.
- Seam protocols (`AudioPlaying`, `MetadataReading`, `ArtworkColorExtracting`) exist to allow injection, but the unit tests mostly exercise the **real** production types (`NowPlayingService`, `ArtworkColorExtractor`, `HotKeyManager`, `ShortcutStore`) on real (isolated) `UserDefaults` and real Carbon/AppKit APIs — integration-leaning unit tests.
- Where production members are `private` (e.g. `BrowserBridge.handle`, `InMessage`/`Payload`, `mapSource`), the test **mirrors the frozen wire format locally** and exercises the reachable public seam (`NowPlayingService.updateFromExternal`). The mirror is kept byte-identical on purpose so the test fails loudly if production diverges (`StateSyncBridgeTests` header + inline `mapSource` copy).
- **Fixtures** are inline: JSON string literals for wire frames, programmatically-drawn `NSImage` for color extraction (`img.lockFocus()` → fill → `unlockFocus()`), synthesized `NSEvent.keyEvent(...)` for key combos. No fixture files.
- Non-default ports (`8798`, `8799`) are used in bridge tests to avoid colliding with a running app on `8787`.

## Build & Verification

- **Build:** `make_app.sh` (repo root) runs `swift build -c release`, locates the bare binary via `swift build --show-bin-path`, and hand-assembles a `.app` bundle (`Contents/MacOS`, generated `Info.plist` with `LSUIElement=true` for a menu-bar agent app), then ad-hoc codesigns (`codesign --force --deep --sign -`). This bundling step exists because the project builds under **Command Line Tools, not Xcode/xcodebuild** — `swift build` yields a bare binary, not an app. See also `docs/system-design/05-security-performance-build.md`.
- **Build is itself a verification gate** (must compile under CLT, which is why `@VPState` exists — see CONVENTIONS.md).
- The E2E JXA spec references a debug build at `/private/tmp/vinylpod-run-build/out/Products/Debug/VinylPod`.

## Manual Verification Practices

- **Browser extension** has no automated JS test suite. It is verified manually by loading `BrowserExtension/` unpacked in Chrome (developer mode, see `BrowserExtension/README.md`) and by driving real Spotify / Apple Music / YouTube / YouTube Music pages with **Playwright MCP** — the large body of captured `console-*.log` and `page-*.yml` snapshot artifacts in `.playwright-mcp/` (repo root, git-ignored region) are the evidence of these interactive verification sessions, not a committed test suite.
- Both E2E harnesses emit a structured JSON `REPORT`/`metrics` object (phases, observations, failures) for manual/automated inspection rather than using an assertion runner.

## Coverage Gaps

- **No coverage tooling / thresholds configured**; `swift test` coverage is not enforced.
- **Browser extension JS is entirely untested by automation** — the adapters (`sites/*.js`), `cs-common.js` poll/diff/clamp logic, and `service-worker.js` aggregation (`recomputeActive`) are verified only manually via Playwright MCP. High-value target for a headless test (e.g. jsdom/vitest) since the wire contract is frozen and clamping is security-relevant.
- **No SwiftUI view tests / snapshot tests** — the entire `Sources/VinylPod/Views/` tree (widgets, settings sections, glass surfaces, visualizers) is unverified except by the native Accessibility E2E for window sizing.
- **E2E harnesses are not wired into CI** and require a live app + macos GUI session; the bridge stress test needs the app listening on `8787`.
- **`make_app.sh` swallows codesign failure** (`|| echo "(codesign skipped)"`) with no verification gate (noted in `docs/system-design/05-security-performance-build.md`).
- Scrobbling (`Sources/VinylPod/Scrobbling/`, Last.fm client) and native capture (`Capture/NativeMediaRemoteCapture.swift`) have no dedicated unit tests.

---

*Testing analysis: 2026-07-03*
