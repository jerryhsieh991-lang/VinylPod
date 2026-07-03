# Codebase Concerns

**Analysis Date:** 2026-07-03

*Note (Phase 0 reconciliation, 2026-07-03): the "Test Coverage Gaps" analysis below claims no `*Tests.swift` files exist, which contradicts `TESTING.md` and the tracked `Tests/VinylPodBackendTests/` suite (4 files, landed pre-map in `6a8abd9`); `Package.swift` does still declare no test target. A remap via `/gsd-map-codebase` is recommended to re-derive that section rather than hand-editing the analysis.*

## Tech Debt

**WIP drift — landed (Phase 0):**
- **RESOLVED (Phase 0, 2026-07-03):** The full security/crash-fix WIP landed on `claude/security-crash-fixes` as grouped, reviewable commits — `fb8ab0a` (bridge/extension JS + e2e), `d6f26f2` (core service gating, models, theme + Capture/Scrobbling scaffolds), `7d91ef7` (widget canvas/glass), `7338518` (settings window/menu/effects), plus `bb5d282` (config) and fixes `37a5aa9`/`59342d5`/`e400241`. The real inventory was larger than the 19 files recorded here: 33 code paths including previously-untracked `Sources/VinylPod/Capture/`, `Sources/VinylPod/Scrobbling/`, `Sources/VinylPod/Views/Settings/`, `MusicVisualizerContainerView.swift`, and `e2e/`. Idle CPU re-profiled post-landing at **0.00% mean** (a MenuBarExtra binding loop was caught by the gate and fixed in `e400241`).
- Historical issue (compressed): ~480 insertions of behavioral change sat only in the working tree atop the pre-WIP documentation commit, unreviewable and at risk of loss; landing them as grouped commits was Phase 0 plan 00-01's mandate.

**Untracked Playwright MCP artifact dump:**
- **RESOLVED (Phase 0, 2026-07-03):** The dump was already purged pre-phase in commit `e79c990` ("chore: remove duplicate design doc and transient playwright logs"), and `.playwright-mcp/` is now permanently gitignored (commit `5dfea7f`, plan 00-03) so future dumps can never re-enter `git status`; the stray `.DS_Store` files were also purged in 00-03.
- Historical issue (compressed): ~100+ transient console/page snapshot files from 2026-06-29/30 debugging sessions polluted `git status` and risked accidental commit.

**Empty / stray files:**
- **RESOLVED (Phase 0, 2026-07-03):** `claude.md` and `codex.md` no longer exist anywhere — verified absent from disk, index, and untracked state during plan 00-02 (reappeared NotebookLM exports were losslessly relocated to `~/.claude/notes/`; nothing was committed or deleted in-repo). The stray-file concern is resolved by absence.

## Known Bugs

**Regression risk: the 98%-CPU idle render loop (historical, fixed, fragile):**
- Symptoms: Before the fix, `NowPlayingService.position` (`@Published`, written 10 Hz local / 1 Hz bridge) invalidated always-on parent views observing the full service via `@EnvironmentObject`, driving continuous 60 fps re-renders at idle — traced via `sample`/Instruments to ~98% idle CPU. Documented in `docs/system-design/05-security-performance-build.md` §3 and commits `bed0c39`, `8a4383f`.
- Files: `Sources/VinylPod/Core/Services.swift` (`updateFromExternal`, `setAlbumPalette`), `Sources/VinylPod/Views/Widget/DynamicIslandWidget.swift`, `MenuBarContentView`, `Sources/VinylPod/Windowing/WindowManager.swift`.
- Trigger: Any new code that (a) adds an unconditionally-written `@Published` field, (b) observes `NowPlayingService` in a structurally always-alive parent view, or (c) runs palette extraction off a non-track-change signal.
- Workaround / guard: 6 documented **Performance Invariants** must be preserved (see Fragile Areas below). `Sources/VinylPod/Core/Services.swift` currently carries the change-gating and `NativeMediaRemoteCapture` extrapolates elapsed between slow polls specifically to avoid hammering the update path. The Phase 0 landing (`d6f26f2`) touched exactly this code; all six invariants were statically re-verified during 00-01 (all PASS) and the rebuilt release app re-profiled at 0.00% idle CPU.

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
  - Note: the three `BrowserExtension/*.js` files landed in Phase 0 (`fb8ab0a`); the extension side of this trust boundary should still be re-reviewed alongside the Swift bridge when the residual gaps above are addressed.

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
- Safe modification: Before touching `Services.swift`, `WindowManager.swift`, or any always-on view, re-read §3 and profile with `sample`/Instruments after the change. The `Services.swift` and `WindowManager.swift` edits landed in Phase 0 (`d6f26f2`) fell squarely in this zone and were re-verified against all six invariants during 00-01 (static review PASS; idle re-profiled 0.00%).
- Test coverage: **No automated test target exists** — `Package.swift` has no test target and there are no `*Tests.swift` files. All perf invariants are verified manually. This is the single largest coverage gap.

**Build toolchain fragility — `@VPState` / Command Line Tools, no Xcode:**
- Files: `Sources/VinylPod/Core/Theme.swift:47-51` (`typealias VPState = SwiftUI.State`), `make_app.sh` (root `README.md` was removed in Phase 0; toolchain notes live in `docs/system-design/05-security-performance-build.md`).
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
- **RESOLVED (Phase 0, 2026-07-03):** `PRD.md` now carries a HISTORICAL banner (commit `212ad4a`, plan 00-02) pointing to `docs/system-design/` (canonical spec) and `.planning/` (requirements/roadmap); the stale "DRAFT — awaiting founder sign-off" / "no application code written yet" header is gone.
- Historical issue (compressed): the PRD described a pre-code planning state while ~9,300 LOC of built app existed, misleading any planner loading it.

**Documentation sprawl / overlap:**
- **RESOLVED (Phase 0, 2026-07-03):** `docs/system-design/` is now the declared single canonical spec (canonical statement added to `docs/system-design/README.md`, commit `212ad4a`); `design_system 2.md` was removed pre-phase in `e79c990` (verified gone in 00-02); the seven root `*_features.json` were consolidated into `docs/system-design/07-feature-inventory.md` Appendix A then removed (`51f7cb8`); the superseded root `README.md` was removed (`a01bf3c`). Root `design_system.md` remains, explicitly labeled historical.
- Historical issue (compressed): overlapping root docs (design, product, contracts, seven feature JSONs) had no declared source of truth, producing contradictory guidance.

## Test Coverage Gaps

**No test target anywhere:**
- What's not tested: Everything. `Package.swift` declares no test target; no `*Tests.swift` files exist. The security bridge (`BrowserBridge`), the perf-critical `NowPlayingService` gating, the `data:` URI decoder, and SSRF `isPublicHost()` allowlist — all of which are explicitly security- and regression-sensitive — have zero automated coverage.
- Files: `Sources/VinylPod/Bridge/BrowserBridge.swift`, `Sources/VinylPod/Core/Services.swift`, `Sources/VinylPod/Capture/NativeMediaRemoteCapture.swift`.
- Risk: Perf invariants and bridge threat-model guards can silently regress; the `decodeDataURI` / `isPublicHost` logic is exactly the kind of parsing/allowlist code that benefits most from unit tests.
- Priority: High — start with pure-function tests for `isPublicHost()`, `decodeDataURI()`, and `NowPlayingService.updateFromExternal` change-gating.

---

*Concerns audit: 2026-07-03 · Phase 0 reconciliation: 2026-07-03 (five landed/dispositioned concerns marked RESOLVED; still-open concerns — no test target in `Package.swift`, bridge residual gaps, private MediaRemote, Phase-2 scaffolds — preserved as-is)*
