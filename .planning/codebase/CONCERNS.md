# Codebase Concerns

**Analysis Date:** 2026-07-03

## Tech Debt

**Uncommitted WIP drift (working tree vs. last commit):**
- Issue: The working tree on branch `claude/security-crash-fixes` has **19 modified files not committed** (`git status` / `git diff --stat`: 480 insertions, 164 deletions). The last commit `f0a4c1c` ("Add master app documentation") predates all of this WIP. Substantial behavioral changes sit only in the working tree — `Sources/VinylPod/Core/Services.swift` (+78), `Sources/VinylPod/Views/Widget/DesktopWidgetCanvas.swift` (+99/-, net large), `Sources/VinylPod/Views/Widget/SettingsMenu.swift` (heavy churn), `Sources/VinylPod/App/SettingsEffects.swift` (+65), plus the entire `BrowserExtension/` JS trio (`cs-common.js`, `mediasession-main.js`, `service-worker.js`).
- Files: all 19 in `git diff --stat`; core risk concentrated in `Sources/VinylPod/Core/Services.swift`, `Sources/VinylPod/Core/Models.swift`, `Sources/VinylPod/Core/Theme.swift`, `Sources/VinylPod/Windowing/WindowManager.swift`, `Sources/VinylPod/Bridge/*` consumers.
- Impact: Any codebase map, PRD, or CONTRACTS reference describes the **committed** state, which no longer matches reality. A `git stash`, checkout, or clean-clone loses uncommitted work. Reviewers cannot see the change as a diffable unit. The branch name implies security + crash fixes are in-flight but unlanded.
- Fix approach: Commit the WIP in logically-grouped commits (bridge JS, perf/service gating, widget canvas, settings) with messages tied to CONTRACTS invariants, or explicitly stash + document. Re-run `/gsd-map-codebase` after landing so docs reflect committed state.

**Untracked Playwright MCP artifact dump:**
- Issue: ~100+ untracked files under `.playwright-mcp/` (console `*.log` + page `*.yml` snapshots from 2026-06-29/30 debugging sessions) pollute `git status` and the repo root.
- Files: `.playwright-mcp/console-*.log`, `.playwright-mcp/page-*.yml`; also stray `.DS_Store`.
- Impact: Noise buries real untracked source; risk of accidental commit of transient debug output.
- Fix approach: Add `.playwright-mcp/` to `.gitignore` (currently ignores `.build/`, `.swiftpm/`, `.DS_Store`, etc. but not this dir) and delete the dump.

**Empty / stray files:**
- Issue: `claude.md` (root) is 0 bytes; a separate lowercase `claude.md` coexists with the CLAUDE.md convention.
- Files: `/Users/jerryjerry/Desktop/VinylPodMac/claude.md`.
- Impact: Confusing no-op file; ambiguous instruction source.
- Fix approach: Remove or populate.

## Known Bugs

**Regression risk: the 98%-CPU idle render loop (historical, fixed, fragile):**
- Symptoms: Before the fix, `NowPlayingService.position` (`@Published`, written 10 Hz local / 1 Hz bridge) invalidated always-on parent views observing the full service via `@EnvironmentObject`, driving continuous 60 fps re-renders at idle — traced via `sample`/Instruments to ~98% idle CPU. Documented in `docs/system-design/05-security-performance-build.md` §3 and commits `bed0c39`, `8a4383f`.
- Files: `Sources/VinylPod/Core/Services.swift` (`updateFromExternal`, `setAlbumPalette`), `Sources/VinylPod/Views/Widget/DynamicIslandWidget.swift`, `MenuBarContentView`, `Sources/VinylPod/Windowing/WindowManager.swift`.
- Trigger: Any new code that (a) adds an unconditionally-written `@Published` field, (b) observes `NowPlayingService` in a structurally always-alive parent view, or (c) runs palette extraction off a non-track-change signal.
- Workaround / guard: 6 documented **Performance Invariants** must be preserved (see Fragile Areas below). `Sources/VinylPod/Core/Services.swift` currently carries the change-gating and `NativeMediaRemoteCapture` extrapolates elapsed between slow polls specifically to avoid hammering the update path. WIP edits to `Services.swift` (+78 lines, uncommitted) touch exactly this code and must be re-verified against the invariants.

## Security Considerations

**Loopback WebSocket bridge — documented threat model, known residual gaps:**
- Risk: `Sources/VinylPod/Bridge/BrowserBridge.swift` runs a local WebSocket server on `ws://127.0.0.1:8787` and is the **single ingestion point for all attacker-influenced input** (the browser extension is treated as untrusted). The app is **unsandboxed** (no App Store entitlement), so this hardening layer is the only barrier between extension payloads and the system.
- Files: `Sources/VinylPod/Bridge/BrowserBridge.swift`; threat model in `docs/system-design/05-security-performance-build.md` §2.
- Current mitigations (verified in code):
  - T1 DoS frame flood — `ws.maximumMessageSize = 256 * 1024` plus re-check `data.count <= 256 * 1024` in `handle()`.
  - T2 Connection exhaustion — `accept()` caps at 6 concurrent connections; evicts oldest.
  - T3 SSRF — `isPublicHost()` blocks loopback, link-local (`169.254.*`), RFC-1918, `.local`/`.localhost`.
  - T4 `file://` read — `loadArtwork()` only proceeds for `http`/`https`.
  - T5 Image memory exhaustion — `URLSession` response capped at `8 * 1024 * 1024` bytes.
  - T6 `data:` URI — `decodeDataURI()` splits the string manually (no `URL`/`Data(contentsOf:)` dereference).
  - T7 Title inflation — `title.count <= 2048` guard.
  - T8 Interface exposure — `params.requiredLocalEndpoint` pins bind to `127.0.0.1`.
  - T9 Hung fetch — `req.timeoutInterval = 10`. T10 cache race — reads/writes serialized on private `queue`.
- Recommendations (documented residual gaps, §2.3 "NOT defended"):
  - **No extension authentication** — any local process that knows port 8787 can push payloads and overwrite the displayed track. A shared secret/nonce is not implemented.
  - **No per-frame rate limiting** beyond the 6-connection cap — one long-lived connection can flood frames at max WebSocket rate.
  - **No Origin header validation** — `NWProtocolWebSocket` does not surface the HTTP `Origin`, so a malicious page in the same browser could in principle open a cross-origin WS connection while VinylPod runs.
  - Note: the three `BrowserExtension/*.js` files are uncommitted WIP; the extension side of this trust boundary should be re-reviewed alongside the Swift bridge before landing.

## Performance Bottlenecks

**Publish-rate amplification through SwiftUI observation:**
- Problem: The core render cost is not compute — it is `@Published` fan-out. `position` writes at 10 Hz (local audio) drive body re-diffs of any observing view; `MenuBarContentView` contains a `Picker/ForEach` whose re-diff is expensive.
- Files: `Sources/VinylPod/Core/Services.swift`, `Sources/VinylPod/Views/Widget/DynamicIslandWidget.swift` (754 LOC — largest file), `Sources/VinylPod/Views/Widget/DesktopWidgetCanvas.swift` (654 LOC).
- Cause: SwiftUI invalidates the full `body` on any `@Published` change on an observed object.
- Improvement path: Keep observation pushed to leaf views (Rule 1); coarsen position to whole seconds at display sites (Rule 3). Do not add new high-frequency `@Published` fields.

## Fragile Areas

**The 6 Performance Invariants (regression-critical):**
- Files: `docs/system-design/05-security-performance-build.md` §3; enforced across `Sources/VinylPod/Core/Services.swift`, `Sources/VinylPod/Windowing/WindowManager.swift`, `DynamicIslandWidget.swift`, `MenuBarContentView`.
- Why fragile: The invariants are convention-enforced, not compiler-enforced — nothing prevents a future edit from re-introducing the CPU loop.
  - Rule 1 — Never observe `NowPlayingService` in an always-on parent view; push observation to leaves.
  - Rule 2 — `position` must remain the ONLY unconditionally-written `@Published` field; all others equality-gated.
  - Rule 3 — Leaf views displaying position must coarsen to whole seconds.
  - Rule 4 — `setAlbumPalette` must be called only on real track changes (`Services.swift:339` guards against `.iceMountain` re-assign).
  - Rule 5 — Size-switch transitions must use `.transition(.opacity)` cross-fades (not full rebuild) — see commit `5b53863`.
  - Rule 6 — `modeTransitionInFlight` guard in `WindowManager.apply(mode:)` must remain to prevent overlapping transitions.
- Safe modification: Before touching `Services.swift`, `WindowManager.swift`, or any always-on view, re-read §3 and profile with `sample`/Instruments after the change. The uncommitted `Services.swift` (+78) and `WindowManager.swift` (+5) edits fall squarely in this zone.
- Test coverage: **No automated test target exists** — `Package.swift` has no test target and there are no `*Tests.swift` files. All perf invariants are verified manually. This is the single largest coverage gap.

**Build toolchain fragility — `@VPState` / Command Line Tools, no Xcode:**
- Files: `Sources/VinylPod/Core/Theme.swift:47-51` (`typealias VPState = SwiftUI.State`), `README.md`, `make_app.sh`.
- Why fragile: The macOS 26+ SDK declares `@State` as a *macro* whose `SwiftUIMacros` plugin ships only with full Xcode. This machine has **Command Line Tools only**, so every view-local state uses the `@VPState` typealias workaround instead of `@State`. The app is built via `swift build` + `make_app.sh` bundling rather than an Xcode project.
- Safe modification: Do not introduce raw `@State` (won't compile under CLT). Any contributor with a different toolchain (full Xcode) may not hit this constraint, creating environment-dependent build behavior.
- Distribution impact: No Xcode project, no signing/entitlements pipeline, unsandboxed — **Mac App Store distribution is blocked** without a real Xcode target, code signing, sandbox entitlements, and removal of the private-framework dependency (see below).

## Scaling Limits

**Browser bridge concurrency:**
- Current capacity: 6 concurrent WebSocket connections (`BrowserBridge.accept()`), single serial `DispatchQueue`.
- Limit: 7th connection evicts the oldest; sufficient for a single browser but not a hard security boundary.
- Scaling path: Not a real concern for a single-user desktop widget; leave as-is.

## Dependencies at Risk

**Apple private `MediaRemote.framework` (native capture):**
- Risk: `Sources/VinylPod/Capture/NativeMediaRemoteCapture.swift` resolves `MRMediaRemoteGetNowPlayingInfo` and friends at runtime via `dlopen`/`dlsym` of `/System/Library/PrivateFrameworks/MediaRemote.framework`. On **macOS 15.4+ ("Sequoia") the API is entitlement-gated** and returns no data to unentitled apps.
- Impact: Native Spotify.app / Music.app capture is a **graceful no-op** on modern macOS (`Services.swift:287`, `NativeMediaRemoteCapture.swift:103` log once then no-op forever). Private-framework use also bars App Store distribution and can break on any macOS update.
- Migration plan: Native capture cannot be relied on going forward; the browser-extension bridge is the durable capture path. A supported alternative (e.g. `MPNowPlayingInfoCenter` / ScriptingBridge to Music.app, or Spotify Web API) would be required for entitlement-free streaming capture.

## Missing Critical Features

**Phase 2 scaffolded but unwired (Spotify / Apple Music / browser capture seams):**
- Problem: `Sources/VinylPod/Core/Models.swift` defines `.spotify` / `.appleMusic` source cases and CONTRACTS defines protocol seams, but the streaming-connect path is not wired end-to-end. `Sources/VinylPod/Scrobbling/LastFmClient.swift` + `LastFmModels.swift:44` note the API key/secret are still **empty-string placeholders**, so the entire scrobbling subsystem no-ops. `Sources/VinylPod/Views/Settings/SettingsWindow.swift:97,140` carry placeholder tabs for the capture/source config.
- Blocks: Apple Music + Spotify "connect" (PRD §3 source #3) and Last.fm scrobbling are non-functional until credentials + wiring land. Native capture (the other candidate for streaming) is entitlement-blocked (above).
- Files: `Sources/VinylPod/Core/Models.swift`, `Sources/VinylPod/Scrobbling/LastFmClient.swift`, `Sources/VinylPod/Scrobbling/LastFmModels.swift`, `Sources/VinylPod/Views/Settings/SettingsWindow.swift`, `Sources/VinylPod/Capture/NativeMediaRemoteCapture.swift`.

## Documentation Concerns

**PRD vs. reality drift:**
- Problem: `PRD.md` header states `Status: DRAFT — awaiting founder sign-off`, `Phase: Thinking & Planning (no application code written yet)` dated 2026-06-28. In reality the app is **substantially built** — ~9,300 LOC across `Sources/VinylPod/` (`find Sources -name '*.swift' | xargs wc -l` → 9297 total), a working browser extension, and a build pipeline. The PRD describes a pre-code planning state that no longer exists.
- Files: `PRD.md`.
- Impact: Any planner/executor loading PRD.md for phase planning will be misled about project maturity and scope status.
- Fix approach: Update PRD status to reflect built state, or supersede it with the `docs/system-design/` set (which does describe the real architecture).

**Documentation sprawl / overlap:**
- Problem: Multiple overlapping and duplicate docs describe the same product/design surface with no single source of truth:
  - Design: `design_system.md` (22 KB) AND `design_system 2.md` (8.8 KB, note the space-in-filename duplicate) AND `docs/system-design/06-design-system.md`.
  - Product: `PRD.md` AND `docs/system-design/00-product-vision.md` AND `README.md`.
  - Contracts: `CONTRACTS.md` AND `docs/system-design/01-core-architecture.md`.
  - Feature inventories: seven root-level `*_features.json` (`widget_features.json`, `small_widget_features.json`, `regular_widget_features.json`, `large_widget_features.json`, `desktop_widget_features.json`, `settings_features.json`, `ui_comparative_features.json`) AND `docs/system-design/07-feature-inventory.md`.
  - Empty `claude.md` at root.
- Files: repo root `*.md` + `*_features.json`, `docs/system-design/**`, `docs/settings-audit.md`, `docs/asset-catalog-migration.md`.
- Impact: Contradictory or stale guidance; unclear which doc is authoritative; the space-in-filename `design_system 2.md` is almost certainly an accidental duplicate.
- Fix approach: Designate `docs/system-design/` as canonical, delete/merge the root duplicates (especially `design_system 2.md`), consolidate the seven `*_features.json` into the single `07-feature-inventory.md`, and either fill or remove `claude.md`.

## Test Coverage Gaps

**No test target anywhere:**
- What's not tested: Everything. `Package.swift` declares no test target; no `*Tests.swift` files exist. The security bridge (`BrowserBridge`), the perf-critical `NowPlayingService` gating, the `data:` URI decoder, and SSRF `isPublicHost()` allowlist — all of which are explicitly security- and regression-sensitive — have zero automated coverage.
- Files: `Sources/VinylPod/Bridge/BrowserBridge.swift`, `Sources/VinylPod/Core/Services.swift`, `Sources/VinylPod/Capture/NativeMediaRemoteCapture.swift`.
- Risk: Perf invariants and bridge threat-model guards can silently regress; the `decodeDataURI` / `isPublicHost` logic is exactly the kind of parsing/allowlist code that benefits most from unit tests.
- Priority: High — start with pure-function tests for `isPublicHost()`, `decodeDataURI()`, and `NowPlayingService.updateFromExternal` change-gating.

---

*Concerns audit: 2026-07-03*
