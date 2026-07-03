# Roadmap: VinylPod

## Overview

This is a subsequent milestone on a mature (~9,300 LOC + MV3 extension), already-working free macOS menu-bar now-playing app. The journey takes VinylPod from a drifted, CLT-only `swift build` state to a signed, sandboxed, private-framework-free app submitted to the Mac App Store — without redesigning the frozen architecture (single-source-of-truth `NowPlayingService`, one `updateFromExternal` ingestion seam, one reused `NSPanel`, six perf invariants, `CONTRACTS.md` names). Two product decisions are locked: **BLEND UI** (keep the liquid-glass architecture/tokens/invariants, fold in selected mockup refinements) and **PURSUE MAC APP STORE**. Every change is additive and routes through existing seams. Ordering is load-bearing: land WIP → lock a test foundation → prove sandbox/loopback + signing cheaply → scaffold the MAS build and strip the private framework → wire Phase-2 capture (precedence first, then scrobbling) → blend the UI → submit. The only true serializations are the sandbox/signing spike before the Xcode migration, and the Safari appex target before the Safari capture producer.

## Phases

**Phase Numbering:**

- Integer phases (0, 1, 2, …): Planned milestone work (Phase 0 is a hard prerequisite that blocks all)
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

**Critical path:** Phase 0 → Phase 2 → Phase 3 → Phase 4 → Phase 6, with Phase 1 and Phase 5 hanging off Phase 0 in parallel (Phase 5 gated on the Phase 1 perf guards).

- [x] **Phase 0: Land WIP & Reconcile** - Commit the ~19-file WIP re-verified against the perf invariants, designate docs canonical, de-noise the repo, refresh the map (completed 2026-07-03)
- [ ] **Phase 1: Test Foundation** - Add an SPM test target locking bridge security, ingestion change-gating, and the render-loop perf invariants
- [ ] **Phase 2: Sandbox/Loopback + Signing Spike** - Prove a signed+sandboxed shell binds the loopback server and clears App Store Connect upload before the Xcode migration
- [ ] **Phase 3: MAS Scaffold + Private-Framework Removal** - Stand up VinylPodKit + a thin .xcodeproj, strip MediaRemote with a symbol-grep gate, scaffold the Safari appex
- [ ] **Phase 4: Phase 2 Capture (Precedence, then Scrobbling)** - Multi-source precedence + override + Safari producer + bridge hardening + spec-correct Last.fm with an offline queue
- [ ] **Phase 5: UI Blend** - Fold mockup refinements into the five sizes + Dynamic Island with a Reduce-Transparency fallback, re-profiled to ≈0.0% idle CPU
- [ ] **Phase 6: Store Submission** - Submit the App Store archive with scrubbed metadata + review narrative, verified in Safari, with Chrome/FF trailing

## Phase Details

### Phase 0: Land WIP & Reconcile

**Goal**: The ~19-file working-tree WIP is committed and re-verified against the six perf invariants, `docs/system-design/` is the canonical spec, the repo root is de-noised, and the codebase map reflects committed state.
**Depends on**: Nothing (first phase — HARD PREREQUISITE, blocks all downstream work)
**Requirements**: FND-01, FND-02, FND-03, FND-04
**Success Criteria** (what must be TRUE):

  1. `git status` shows a clean working tree; the WIP has landed as logically-grouped, reviewable commits (bridge JS, perf/service gating, widget canvas, settings) and `sample`/`powermetrics` confirms ≈0.0% idle CPU and ≈0.0% steady-playback CPU (the six invariants still hold)
  2. `docs/system-design/` is the single canonical spec; `design_system 2.md`, the empty root `claude.md`, and the stale `PRD.md` status are removed; the seven root `*_features.json` are consolidated into `07-feature-inventory.md`
  3. The repo root is de-noised — `.playwright-mcp/` is gitignored and its transient artifacts (plus stray `.DS_Store`) are removed
  4. The `.planning/codebase/` map is regenerated after the WIP lands and reflects committed state (not the pre-WIP `f0a4c1c`)

**Plans**: 4/4 plans complete
**Research**: skip (pure land/reconcile/housekeeping; no external unknowns)

Plans:

- [x] 00-01-PLAN.md
- [x] 00-02-PLAN.md
- [x] 00-03-PLAN.md
- [x] 00-04-PLAN.md

**Wave 1**

- [x] 00-01: Land WIP in logically-grouped commits and re-profile idle + playback CPU to ≈0.0% against the six invariants (FND-01)

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 00-02: Designate `docs/system-design/` canonical; delete `design_system 2.md`/empty `claude.md`/stale PRD status; consolidate seven `*_features.json` → `07-feature-inventory.md` (FND-02)

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 00-03: De-noise the repo — add `.playwright-mcp/` to `.gitignore`, remove transient artifacts and stray `.DS_Store` (FND-03)

**Wave 4** *(blocked on Wave 3 completion)*

- [ ] 00-04: Refresh the `.planning/codebase/` map after WIP lands so docs reflect committed state (FND-04)

### Phase 1: Test Foundation

**Goal**: `swift test` runs a real SPM test target that locks the bridge security guards, `updateFromExternal` change-gating, and the render-loop perf invariants before any capture/UI churn.
**Depends on**: Phase 0 (needs committed, invariant-verified code) — runs in parallel with the Phase 2→3→4 critical path
**Requirements**: TST-01, TST-02, TST-03, TST-04, TST-05
**Success Criteria** (what must be TRUE):

  1. `swift test` runs green from a real SPM test target (Swift Testing) and the `swift build` + `make_app.sh` dev loop is unaffected
  2. The bridge threat model is covered — tests fail if `isPublicHost()` allows loopback/link-local/RFC-1918/`.local`, or if `decodeDataURI()` dereferences `URL`/`Data(contentsOf:)`
  3. `updateFromExternal` change-gating is covered — tests fail if any field except `position` is written unconditionally (equality guards fire correctly)
  4. An XCTest idle-CPU / render-loop perf regression assertion fails the suite when a high-frequency re-render is introduced

**Plans**: 4 plans
**Research**: skip (Swift Testing / XCTest are well-documented — standard patterns)

Plans:

- [ ] 01-01: Add an SPM test target (Swift Testing) to `Package.swift`; `swift test` green; `swift build` + `make_app.sh` intact (TST-01)
- [ ] 01-02: Unit-test bridge security — `isPublicHost()` SSRF allowlist and `decodeDataURI()` parsing (TST-02, TST-03)
- [ ] 01-03: Unit-test `NowPlayingService.updateFromExternal` change-gating (only `position` unconditional; others equality-guarded) (TST-04)
- [ ] 01-04: XCTest idle-CPU / render-loop regression assertion guarding the invariants (TST-05)

### Phase 2: Sandbox/Loopback + Signing Spike

**Goal**: A throwaway signed + sandboxed shell proves the loopback WebSocket server binds and artwork fetches under App Sandbox and clears an App Store Connect upload — a cheap feasibility gate before the full Xcode migration (a negative result reorders everything toward native-messaging-only).
**Depends on**: Phase 0 (feasibility gate that must precede the Phase 3 Xcode migration)
**Requirements**: MAS-01, MAS-02
**Success Criteria** (what must be TRUE):

  1. On a *real signed + sandboxed build* the shell binds `127.0.0.1:8787` (NWListener) and completes an outbound artwork fetch with zero `sandboxd` denials in Console (verified via Console, not "it launched")
  2. The entitlement triad (`app-sandbox` + `com.apple.security.network.server` + `com.apple.security.network.client`) is validated as sufficient — both the bind and the outbound fetch succeed under sandbox
  3. The shell passes App Store Connect upload through the full MAS signing pipeline (Apple Distribution cert + MAS provisioning profile + app-sandbox), proving the pipeline end-to-end before any feature work
  4. A go/no-go is recorded — FEASIBLE confirms the planned Phase 3→4 order; a negative result forces a native-messaging-only architecture and reorders downstream phases

**Plans**: 2 plans
**Research**: WARRANTED — `/gsd-plan-phase --research-phase` (signing/sandbox/App-Store-Connect behavior is version-sensitive and opaque; Safari transport constraint informs the shell design)

Plans:

- [ ] 02-01: Signed + sandboxed Xcode 26 shell binds `127.0.0.1:8787` and fetches artwork; verify via Console `sandboxd` (no denials) (MAS-01)
- [ ] 02-02: Validate the full MAS signing pipeline end-to-end — Distribution cert + MAS profile + app-sandbox — via an App Store Connect upload round-trip (MAS-02)

### Phase 3: MAS Scaffold + Private-Framework Removal

**Goal**: The durable MAS build structure exists — a `VinylPodKit` SPM library consumed by a thin `.xcodeproj` app target — with the private `MediaRemote` framework compile-excluded behind a symbol-grep gate and the Safari appex scaffolded, all while `swift build` / `make_app.sh` / `swift test` still work.
**Depends on**: Phase 2 (the sandbox/signing spike must be green before committing to the Xcode migration)
**Requirements**: MAS-03, MAS-04, MAS-05, MAS-06, MAS-07, MAS-08
**Success Criteria** (what must be TRUE):

  1. Logic is refactored into a `VinylPodKit` SPM library (Package.swift retained as source of truth) consumed by a thin `.xcodeproj` app target that owns `Info.plist` (`LSUIElement`), entitlements, signing, and the archive; `swift build`, `make_app.sh`, and `swift test` all still pass
  2. Xcode 26 is adopted and real `@State` compiles (the `@VPState` workaround is demoted to an optional CLT compatibility shim, not removed)
  3. The pre-submit `strings`/`nm`/`otool -L` symbol-grep gate fails the build on any `MediaRemote` symbol; `MediaRemote` is `#if`-excluded with a no-op stub on the same capture seam so private symbols never enter the shipping binary
  4. Entitlements are finalized to the minimal exact set (`app-sandbox` + `network.server` + `network.client` + user-selected-file read), and the Safari Web Extension appex is scaffolded via `xcrun safari-web-extension-converter` and embedded in the `.app`

**Plans**: 5 plans
**Research**: WARRANTED — `/gsd-plan-phase --research-phase` (MV3→Safari appex conversion has rough edges: service-worker model, icons, versioning, silently-unsupported APIs; ~70–80% converter coverage — budget a dedicated pass)

Plans:

- [ ] 03-01: Refactor logic into a `VinylPodKit` SPM library; keep `Package.swift` as source of truth; `swift build` + `make_app.sh` + `swift test` still green (MAS-03)
- [ ] 03-02: Thin native `.xcodeproj` app target consuming VinylPodKit; owns Info.plist/signing/archive; adopt Xcode 26 (real `@State`; `@VPState` → optional shim) (MAS-04, MAS-07)
- [ ] 03-03: Finalize entitlements — `app-sandbox` + `network.server` + `network.client` + user-selected-file read (MAS-05)
- [ ] 03-04: `#if`-strip `MediaRemote` to a no-op stub + pre-submit `strings`/`nm`/`otool -L` grep gate that fails on any `MediaRemote` symbol (MAS-06)
- [ ] 03-05: Scaffold the Safari Web Extension appex via `safari-web-extension-converter`, embedded in the `.app` (MAS-08)

### Phase 4: Phase 2 Capture (Precedence, then Scrobbling)

**Goal**: Multi-source precedence, a manual override picker, the Safari native-messaging producer, hardened bridge auth, and spec-correct Last.fm scrobbling with a persistent offline queue all work end-to-end through the single `updateFromExternal` seam — precedence landing first so scrobble timing gets clean play/track-change/stop signals.
**Depends on**: Phase 3 (needs the Safari appex target + finalized entitlements + VinylPodKit); relies on the Phase 1 perf/bridge test guards
**Requirements**: CAP-01, CAP-02, CAP-03, CAP-04, CAP-05, SEC-01, SEC-02, SEC-03, SCR-01, SCR-02, SCR-03, SCR-04, SCR-05, SCR-06
**Success Criteria** (what must be TRUE):

  1. With two browser tabs playing, a "last-active-playing wins" precedence layer in front of `updateFromExternal` auto-selects the right source and hands off gracefully when one pauses — adding no new ingestion path or `@Published` field; the precedence rules are finalized and documented (resolves the SPEC-phase open question)
  2. The user can force a source via an Auto / Browser / Spotify / Apple Music picker, and a provenance badge shows the active `Track.source`
  3. A track played in Safari appears in the widget via the `SafariWebExtensionHandler` native-messaging producer, funneling into the same `updateFromExternal` seam
  4. The loopback bridge rejects unauthenticated payloads via a shared-secret/nonce handshake, rate-limits per-frame floods beyond the 6-connection cap, and validates (or documents a justified mitigation for) cross-origin WS connections
  5. Last.fm scrobbles at `min(duration/2, 240s)` for tracks ≥30s via an independent elapsed-listen state machine keyed on stable track identity, computes `api_sig` as MD5 of alphabetized `name+value` params + secret, sends no-retry `track.updateNowPlaying` on play start, and a restart-safe offline queue (chronological, batch ≤50, ≥30s spacing, error-29 backoff) survives an app restart; only the session key is stored in Keychain; the scrobble-state indicator is a dedicated leaf view
  6. Idle + steady-playback CPU is re-profiled to ≈0.0% after the ingestion/scrobble changes (the six perf invariants still hold)

**Plans**: 5 plans
**Research**: skip (Last.fm API spec is HIGH-confidence and precise; precedence is consensus-level; Safari appex groundwork done in Phase 3)

Plans:

- [ ] 04-01: Multi-source "last-active-playing" precedence layer in front of `updateFromExternal` with graceful pause hand-off; finalize + document precedence rules (CAP-01, CAP-05)
- [ ] 04-02: Manual source-override picker (Auto/Browser/Spotify/Apple Music) + source-provenance badge from `Track.source` (CAP-02, CAP-03)
- [ ] 04-03: Safari native-messaging producer (`SafariWebExtensionHandler`) funneling into the same `updateFromExternal` seam (CAP-04)
- [ ] 04-04: Bridge hardening — shared-secret/nonce handshake, per-frame rate limiting, Origin validation/mitigation (SEC-01, SEC-02, SEC-03)
- [ ] 04-05: Last.fm end-to-end — real keys + desktop auth + Keychain session key, no-retry now-playing, spec threshold state machine, `api_sig`, persistent offline queue, leaf-view indicator (SCR-01..06)

### Phase 5: UI Blend

**Goal**: Selected refinements from the ~40 "VinyIpod UI" mockups are folded into the five sizes + Dynamic Island — preserving glass tokens and the frozen `CONTRACTS.md` seams — with real-change-only micro-interactions and a Reduce-Transparency fallback, every batch re-profiled to ≈0.0% idle CPU.
**Depends on**: Phase 0 (touches `Views/`/`Widget/` only); parallelizable with Phases 3–4 but **gated on the Phase 1 perf guards**
**Requirements**: UIB-01, UIB-02, UIB-03, UIB-04
**Success Criteria** (what must be TRUE):

  1. The five sizes + Dynamic Island show the blended mockup refinements while glass tokens and the frozen `CONTRACTS.md` seams remain intact
  2. Track-change micro-interactions fire only on real `onTrackChanged` events — never on the 1 Hz/10 Hz position tick
  3. With Reduce Transparency enabled, a solid-glass fallback renders and now-playing text stays legible (contrast is never sacrificed for translucency)
  4. `sample`/`powermetrics` confirms ≈0.0% idle CPU after each UI change batch before the phase is marked done (the six perf invariants still hold)

**Plans**: 4 plans
**Research**: skip (existing tokens/invariants + mockups — a design pass, not a research one)
**UI hint**: yes

Plans:

- [ ] 05-01: Fold selected "VinyIpod UI" mockup refinements into the five sizes + Dynamic Island, preserving glass tokens + frozen seams (UIB-01)
- [ ] 05-02: Bind track-change micro-interactions to `onTrackChanged` only (never the position tick) (UIB-02)
- [ ] 05-03: Reduce-Transparency-aware solid-glass fallback; keep now-playing text legible over glass (UIB-03)
- [ ] 05-04: Re-profile every UI change batch to ≈0.0% idle CPU before marking the phase done (UIB-04)

### Phase 6: Store Submission

**Goal**: The App Store archive is built and submitted for review with scrubbed metadata and a documented review narrative, every capture source verified inside Safari, with Chrome/Firefox listings submitted on their own trailing pipelines.
**Depends on**: Phase 4 (capture must work end-to-end) and Phase 5 (UI blend done); builds on the Phase 3 archive/signing — terminal phase
**Requirements**: SUB-01, SUB-02, SUB-03, SUB-04
**Success Criteria** (what must be TRUE):

  1. An App Store archive is built and submitted for review with metadata scrubbed of competitor browser names, emoji, donation asks, and "beta" language
  2. Every capture source is verified working *inside Safari* (MV3→appex fidelity hand-reconciled past the ~70–80% converter baseline)
  3. The App Review notes document the bridge hardening + shared-secret/nonce handshake to justify the bundled loopback server and broad browser capture
  4. Chrome and Firefox store listings are submitted on their own pipelines, decoupled and trailing — they do not block the MAS submission

**Plans**: 4 plans
**Research**: WARRANTED — `/gsd-plan-phase --research-phase` (App Review reception of a bundled local server + broad browser capture is policy-dependent and opaque; strengthen the review narrative and re-verify guidance at submission time)

Plans:

- [ ] 06-01: Build + submit the App Store archive; scrub metadata (no competitor names, emoji, donation asks, "beta") (SUB-01)
- [ ] 06-02: Test every capture source inside Safari; hand-reconcile appex fidelity past the converter baseline (SUB-02)
- [ ] 06-03: Author the App Review narrative documenting bridge hardening + shared-secret/nonce handshake (SUB-03)
- [ ] 06-04: Submit Chrome / Firefox store listings — decoupled/trailing, must not block MAS (SUB-04)

## Progress

**Execution Order:**
Critical path executes Phase 0 → 2 → 3 → 4 → 6; Phase 1 and Phase 5 run in parallel off Phase 0 (Phase 5 gated on Phase 1 perf guards).

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 0. Land WIP & Reconcile | 4/4 | Complete   | 2026-07-03 |
| 1. Test Foundation | 0/4 | Not started | - |
| 2. Sandbox/Loopback + Signing Spike | 0/2 | Not started | - |
| 3. MAS Scaffold + Private-Framework Removal | 0/5 | Not started | - |
| 4. Phase 2 Capture (Precedence, then Scrobbling) | 0/5 | Not started | - |
| 5. UI Blend | 0/4 | Not started | - |
| 6. Store Submission | 0/4 | Not started | - |
