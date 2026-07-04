# Project Research Summary

**Project:** VinylPod
**Domain:** Native macOS menu-bar now-playing widget (SwiftUI + AppKit / SwiftPM) → Mac App Store distribution
**Researched:** 2026-07-03
**Confidence:** MEDIUM-HIGH

## Executive Summary

VinylPod is a mature (~9,300 LOC), already-working free macOS menu-bar now-playing app whose durable moat is capturing *any* browser tab's playback (via a cross-browser MediaSession extension over a hardened `127.0.0.1:8787` loopback WebSocket) plus local files — displayed as a liquid-glass, adaptive-themed widget in five sizes plus a Dynamic Island. This milestone is a full re-plan treating `docs/system-design/` as the canonical spec, with two locked product decisions: **BLEND UI** (keep the proven liquid-glass architecture/tokens/perf invariants, fold in selected refinements from ~40 fresh mockups) and **PURSUE MAC APP STORE** distribution. The frozen architecture (single-source-of-truth `NowPlayingService` @MainActor, single `updateFromExternal` ingestion seam, one reused `NSPanel`, six perf invariants, `CONTRACTS.md` names) is not redesigned — every change this cycle is additive and routes through existing seams.

The research resolves the milestone's #1 open risk in favor of proceeding: **a sandboxed MAS app CAN run the loopback WebSocket server** with `com.apple.security.network.server` (listen) + `com.apple.security.network.client` (outbound artwork/Last.fm) entitlements (confirmed HIGH by two independent research dimensions). The real transport constraint moves to the *browser* side: Chrome/Firefox extensions keep the WebSocket path unchanged, but **Safari Web Extensions cannot open `ws://localhost`** and must use native messaging via `SafariWebExtensionHandler` — a distinct transport feeding the *same* `updateFromExternal` seam. Distribution requires a real toolchain shift: install **Xcode 26** (resolves the `@State`-as-macro / `@VPState` workaround via the bundled `SwiftUIMacros` plugin), keep `Package.swift` as source-of-truth by refactoring logic into a **VinylPodKit library** consumed by a **thin `.xcodeproj` app target** that owns Info.plist, entitlements, signing, and the embedded Safari appex. Note `swift package generate-xcodeproj` is removed; do not use it.

The load-bearing risks are all preventable and mostly upstream: (1) private `MediaRemote` must be **compile-excluded** (`#if` + no-op stub), not merely runtime-gated, because App Review does static binary analysis — add a pre-submit `strings`/`nm` symbol-grep gate; (2) **MAS signing** (Apple Distribution cert + MAS provisioning profile + app-sandbox, uploaded to App Store Connect) is a *different* path from **Developer-ID notarization** (`notarytool`) — do not conflate them; (3) the BLEND UI refresh must not resurrect the historical ~98% idle-CPU render loop — bind micro-interactions to `onTrackChanged` (real changes only), never the position tick, and add a Reduce-Transparency fallback; (4) the biggest correctness gap is a **persistent offline Last.fm scrobble queue** (survives restart, chronological, batch ≤50, scrobble at `min(duration/2, 240s)` for ≥30s tracks, `api_sig` = MD5 of alphabetized params + secret). Ordering is load-bearing: land WIP → lock a test foundation → cheap sandbox/loopback + signing spike → MAS scaffold + private-framework removal → Phase 2 capture (precedence first, then scrobbling on top) → UI blend → submit.

## Key Findings

### Recommended Stack

This is a subsequent-milestone stack *delta* — the existing zero-dependency stack (Swift, SwiftUI/AppKit, `Network`, AVFoundation, CryptoKit, Carbon, MV3 extension, loopback bridge) is not re-litigated. The delta is entirely about going from a CLT-only `swift build` to a Mac-App-Store-distributable, signed, sandboxed app. See `.planning/research/STACK.md`.

**Core technologies:**
- **Xcode 26 (macOS 26 Tahoe SDK)**: build toolchain, signing, App Store archive/upload — mandatory for MAS; ships the `SwiftUIMacros` plugin that fixes `@State`, making `@VPState` an unneeded-but-harmless shim.
- **SwiftPM (keep `Package.swift`) + VinylPodKit library**: source of truth for code + tests — refactor the executable target into a library so `swift build` / `make_app.sh` dev loop and `swift test` keep working; the Xcode app target is *additive*.
- **Thin native `.xcodeproj` app target**: owns Info.plist (`LSUIElement`), entitlements (app-sandbox + network.server + network.client), signing, the Safari appex, App Store archive — SPM alone cannot produce a signed sandboxed `.app`. (XcodeGen only if `.pbxproj` merges bite; Tuist reserved for future growth.)
- **App Sandbox + `network.server` + `network.client`**: the loopback WebSocket server survives sandboxing with these two entitlements (the #1 feasibility answer).
- **Safari Web Extension appex** (`xcrun safari-web-extension-converter`): the only browser-extension form the MAS hosts, bundled inside the `.app`; Chrome/Firefox ship via their own stores. Converter covers only ~70–80%; expect hand reconciliation.
- **Swift Testing** (bundled) for pure-function unit tests; keep **XCTest** for perf/`measure` (idle-CPU) assertions.

### Expected Features

This milestone adds/refines exactly three feature areas (shipping features are not re-catalogued). See `.planning/research/FEATURES.md`.

**Must have (table stakes):**
- **Multi-source precedence** — "last-active-playing wins" auto-detect with graceful hand-off when a source pauses; a *selection policy in front of* `updateFromExternal`, not a new ingestion path.
- **Manual source override picker** (Auto / Browser / Spotify / Apple Music) — escape hatch when auto guesses wrong.
- **Last.fm done right** — real API key/secret, desktop auth flow surfaced in Settings, `track.updateNowPlaying` on play start (no retry), spec-correct scrobble at `min(duration/2, 240s)` for ≥30s tracks, and a **persistent offline scrobble queue** (restart-safe, chronological, batch ≤50) — the single highest-value correctness gap.
- **Legible now-playing text over glass** — never sacrifice contrast for translucency.

**Should have (competitive):**
- Unified browser + desktop + local precedence in one widget (the moat).
- Source provenance badge (reads existing `Track.source`).
- Liquid-Glass track-change micro-interactions — bound to `onTrackChanged` only.
- Reduce-Transparency-aware solid glass fallback — turns Liquid Glass's #1 accessibility criticism into a selling point.
- Scrobble-state indicator as a leaf view.

**Defer (v2+):**
- Cross-fade source-switching polish; `track.love`; per-source scrobble toggle (add if junk-scrobble complaints appear).
- **Anti-features to reject:** simultaneous multi-source display (breaks single-source-of-truth); native `MediaRemote` as the default precedence winner (blocks MAS); manual scrobble editing; scrobbling short clips/ads; "glass everywhere" maximalism.

### Architecture Approach

Additive-only deltas over a frozen architecture. The single `updateFromExternal` ingestion seam is preserved: every new producer routes through it, adding no new consumer path or `@Published` field. See `.planning/research/ARCHITECTURE.md`.

**Major components (net-new / changed this cycle):**
1. **`SafariWebExtensionHandler`** — new native-messaging producer for Safari (Safari cannot use `ws://localhost`); funnels into the same `updateFromExternal` as the Chrome/Firefox WebSocket path.
2. **`NativeMediaRemoteCapture` → `#if`-stubbed** — conditionally compiled out of the MAS build (no-op stub on the same seam) so private symbols never enter the shipping binary.
3. **Xcode app target** — wraps the SPM `VinylPodKit` library; owns entitlements/signing/appex/archive while `swift build` + `make_app.sh` stay intact.
4. **Entitlements** — `app-sandbox` + `network.server` + `network.client` (+ user-selected file access for drag-drop).
5. **SPM test target** — locks `isPublicHost`, `decodeDataURI`, `updateFromExternal` change-gating, and the perf invariants.
6. **Multi-source precedence layer** — per-source `(isPlaying, lastUpdatedAt)` selection sitting in front of `updateFromExternal`.

### Critical Pitfalls

Top items from `.planning/research/PITFALLS.md` (upstream gates first):

1. **Loopback bridge under sandbox + Safari transport mismatch** — add BOTH network entitlements and prove bind+outbound on a real signed sandboxed build (Console `sandboxd` denials, not "it launched"); design Safari around native messaging from the start.
2. **Private `MediaRemote` strings tripping static analysis** — compile-exclude (not runtime-guard) and add a pre-submit `strings`/`nm`/`otool -L` grep gate that fails the build on any `MediaRemote` hit.
3. **Entitlement / provisioning / hardened-runtime mismatch** — stand up a trivial signed+sandboxed "hello" shell through the *full* MAS pipeline (App Store Connect round-trip) before wiring features; keep entitlements minimal and exact; never reuse the Developer-ID/notarization setup for MAS.
4. **Re-introducing the ~98% idle-CPU loop during BLEND** — keep observation at leaf views, drive animation via gated `TimelineView` (never a new high-freq `@Published` field), render `Int(position)`, use `.transition(.opacity)` not `.id(mode)`; gate the phase "done" on a `sample`/`powermetrics` ~0.0% idle-CPU check.
5. **Last.fm threshold/dedup/auth done wrong** — independent elapsed-listen state machine keyed on stable track identity; `api_sig` = MD5 of alphabetically-sorted `name+value` params + secret; store only the session key in Keychain; batch ≤50, ≥30s spacing, back off on error 29.
6. **Safari review metadata rejections** — scrub competitor browser names, emoji, donation asks, and "beta" language; hand-audit MV3 APIs (`webRequest` unsupported, fails silently) and test every capture source *inside Safari*.

## Implications for Roadmap

Based on combined research, the suggested phase structure (dependency-ordered):

### Phase 0: Land WIP & Reconcile
**Rationale:** ~19 uncommitted files sit in perf/security-critical `Services.swift`, `WindowManager.swift`, and the three extension JS files — everything downstream must build on committed, invariant-verified code. Hard prerequisite (blocks all).
**Delivers:** committed WIP re-verified against perf invariants; `docs/system-design/` designated canonical; stale docs deleted; codebase map refreshed; housekeeping (`.gitignore`, empty files, consolidated `*_features.json`).
**Avoids:** planning on drifted code.

### Phase 1: Test Foundation
**Rationale:** No dependency on other work; de-risks every later refactor that touches ingestion/perf. Must come first so invariants are locked before UI/capture churn them.
**Delivers:** SPM test target (Swift Testing) unit-testing `isPublicHost`, `decodeDataURI`, `updateFromExternal` change-gating; XCTest idle-CPU regression check; the bridge threat model locked.
**Uses:** Swift Testing + XCTest (STACK.md).
**Avoids:** silent perf-invariant and bridge-guard regressions (Pitfall 4).

### Phase 2: Sandbox/Loopback + Signing Spike
**Rationale:** The feasibility gate. Although research resolves it FEASIBLE (HIGH), prove it on a signed throwaway build *before* the full Xcode migration — a negative result would force a native-messaging-only architecture and reorder everything. Cheap insurance (~1 day). Bundles a trivial signed+sandboxed shell through the full MAS pipeline (Pitfall 3).
**Delivers:** signed sandboxed shell that binds `127.0.0.1:8787`, fetches artwork, passes App Store Connect upload; entitlement triad validated.
**Uses:** Xcode 26, app-sandbox + network.server + network.client.
**Avoids:** Pitfalls 1 & 3.

### Phase 3: MAS Scaffold + Private-Framework Removal
**Rationale:** Depends on the spike. Establishes the durable build structure and strips the private API before any feature wiring.
**Delivers:** VinylPodKit library + thin `.xcodeproj` app target; `#if`-strip of `MediaRemote` with a `strings`/`nm` grep gate; Safari Web Extension target scaffolded; entitlements finalized. `swift build` / `make_app.sh` preserved.
**Uses:** Xcode-wraps-SPM pattern; `safari-web-extension-converter`.
**Avoids:** Pitfall 2 (private-symbol rejection).

### Phase 4: Phase 2 Capture (Precedence, then Scrobbling)
**Rationale:** Precedence must land FIRST because accurate scrobble timing needs clean play-start/track-change/stop signals; wire scrobbling on top. Safari native-messaging producer depends on the Phase-3 Safari target.
**Delivers:** multi-source "last-active-playing" precedence + manual override + source badge; Safari native-messaging producer into `updateFromExternal`; Last.fm real keys + auth UI + spec-correct scrobbling + persistent offline queue.
**Implements:** precedence selection layer, `SafariWebExtensionHandler`, durable scrobble queue.
**Avoids:** Pitfall 5 (scrobble correctness), Pitfall 1 (Safari transport).

### Phase 5: UI BLEND
**Rationale:** Independent of MAS internals (touches `Views/`/`Widget/` only); can run parallel to Phases 3–4 but gated on the Phase-1 perf guards. Fold mockup refinements into the five sizes + Dynamic Island.
**Delivers:** blended glass refinements, source/scrobble indicators, Reduce-Transparency fallback, `onTrackChanged`-bound micro-interactions.
**Avoids:** Pitfall 4 — idle-CPU re-profile after each change batch.

### Phase 6: Store Submission
**Rationale:** Terminal. Chrome/Firefox store submissions are fully decoupled (separate review pipelines) and do not block the MAS submission.
**Delivers:** App Store archive + review submission; metadata scrub; Chrome/FF listings as a trailing independent task.
**Avoids:** Pitfall 6 (Safari review metadata).

### Phase Ordering Rationale
- **Critical path:** `Phase0 → Phase2 → Phase3 → Phase4 → Phase6`, with `Phase1` and `Phase5` hanging off `Phase0` in parallel. The only true serialization is the sandbox gate before the Xcode migration, and the Safari target before the Safari capture producer.
- Precedence before scrobbling (scrobble timing depends on clean per-source play signals).
- Private-framework strip and signing pipeline are upstream gates — they can invalidate the transport architecture, so they precede feature/UI work.

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 2/3 (Safari appex conversion):** MV3→Safari has rough edges (service-worker model, icons, versioning, silently-unsupported APIs) — budget a dedicated pass; do not assume a clean one-shot convert. `/gsd-plan-phase --research-phase` warranted.
- **Phase 6 (App Review reception):** whether a bundled local server + broad browser capture draws review scrutiny is policy-dependent; strengthen the review narrative with the shared-secret/nonce handshake and documented hardening.

Phases with standard patterns (skip research-phase):
- **Phase 1 (tests):** Swift Testing / XCTest are well-documented.
- **Phase 4 Last.fm:** the API spec is HIGH-confidence and precise (thresholds, `api_sig`, batching).
- **Phase 5 UI BLEND:** existing tokens/invariants + mockups; a design pass, not a research one.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | MEDIUM-HIGH | Core Apple-toolchain facts verified against Apple docs, TN3147, Swift Forums; exact Xcode 26 minor + MAS review guidance re-verify at submission time. |
| Features | HIGH (Last.fm) / MEDIUM (precedence, glass UX) | Last.fm spec is authoritative; multi-source precedence and Liquid-Glass patterns are consensus-level. |
| Architecture | HIGH | Sandbox loopback feasibility, Safari `ws://localhost` limitation, and Xcode-wraps-SPM all confirmed against Apple docs/forums. |
| Pitfalls | MEDIUM | Apple docs + web cross-checked, but MAS/Safari review behavior is opaque and version-sensitive — treat exact rejection wording as indicative. |

**Overall confidence:** MEDIUM-HIGH

### Gaps to Address
- **App Review reception of a bundled loopback server + broad browser capture:** policy-dependent; mitigate with documented hardening + shared-secret/nonce handshake in review notes.
- **MV3 → Safari appex fidelity:** ~70–80% converter coverage; test every capture source inside Safari, not just Chrome, before submission.
- **Sandboxed-build runtime behavior:** validate loopback bind, artwork fetch, and file-drop under a real signed sandboxed build (Console `sandboxd` denials), not the unsandboxed dev build.
- **Direct-download hedge:** decide up front whether a parallel Developer-ID notarized `.dmg` is wanted; only then is `notarytool` in scope (it is NOT part of the MAS submission).

## Sources

### Primary (HIGH confidence)
- Apple Developer Documentation — App Sandbox, `com.apple.security.network.server`/`.client` entitlements, "Messaging a Web Extension's Native App", "Adding package dependencies", TN3147 (notarization) — sandbox/loopback/Safari/toolchain facts.
- Last.fm Scrobbling 2.0 API — thresholds, no-retry now-playing, batch ≤50, persistent chronological cache, `api_sig` construction.
- Swift Forums / swift-package-manager issues — `generate-xcodeproj` removal; `@State` external-macro plugin behavior.

### Secondary (MEDIUM confidence)
- Apple Developer Forums (loopback = firewall/code-signing not sandbox; Safari WebSocket block; static-analysis private-API detection).
- Competitor survey (NepTunes, SpotMenu, Sleeve); TidBITS Liquid-Glass legibility; macOS Tahoe 26 review; `safari-web-extension-converter` write-ups (~70–80% coverage).

### Tertiary (LOW confidence)
- Exact App Review reception of bundled local server / broad browser capture — validate at submission time.

---
*Research completed: 2026-07-03*
*Ready for roadmap: yes*
