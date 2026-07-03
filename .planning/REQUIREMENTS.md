# Requirements: VinylPod

**Defined:** 2026-07-03
**Core Value:** Show what's playing — beautifully, calmly, reliably — for *browser* playback every competitor misses, without depending on Apple's private, restricted `MediaRemote` hook.

Milestone decisions (locked): **BLEND UI** (keep the liquid-glass architecture/tokens/perf invariants; fold in mockup refinements) · **PURSUE MAC APP STORE** distribution. All changes are additive over the frozen architecture and route through the existing `updateFromExternal` seam.

## v1 Requirements

### Foundation (FND)

- [x] **FND-01**: Uncommitted WIP (~19 files) landed in logically-grouped commits and re-verified against the 6 performance invariants (idle + playback ≈ 0.0% CPU)
- [x] **FND-02**: `docs/system-design/` designated the canonical spec; stale/duplicate docs removed (`design_system 2.md`, outdated `PRD.md` status, empty `claude.md`); seven root `*_features.json` consolidated into `07-feature-inventory.md`
- [x] **FND-03**: `.playwright-mcp/` added to `.gitignore` and transient artifacts removed; repo root de-noised
- [x] **FND-04**: Codebase map (`.planning/codebase/`) refreshed after WIP lands so docs reflect committed state

### Testing (TST)

- [ ] **TST-01**: SPM test target (Swift Testing) exists and runs via `swift test`
- [ ] **TST-02**: Unit tests cover `BrowserBridge.isPublicHost()` SSRF allowlist (loopback/link-local/RFC-1918/`.local` blocked)
- [ ] **TST-03**: Unit tests cover `decodeDataURI()` parsing (no `URL`/`Data(contentsOf:)` dereference)
- [ ] **TST-04**: Unit tests cover `NowPlayingService.updateFromExternal` change-gating (equality guards fire correctly)
- [ ] **TST-05**: XCTest idle-CPU / perf regression assertion guards the render-loop invariants (fails on high-frequency re-render)

### Mac App Store Readiness (MAS)

- [ ] **MAS-01**: Signed + sandboxed throwaway shell binds `127.0.0.1:8787` (NWListener) and fetches artwork successfully on a *real sandboxed build* (spike proof; verified via Console `sandboxd`, not "it launched")
- [ ] **MAS-02**: The shell passes App Store Connect upload — full MAS signing pipeline (Apple Distribution cert + MAS provisioning profile + app-sandbox) validated end-to-end
- [ ] **MAS-03**: Logic refactored into a `VinylPodKit` SPM library; `Package.swift` retained as source of truth; `swift build` + `make_app.sh` dev loop still work
- [ ] **MAS-04**: Thin native `.xcodeproj` app target consumes `VinylPodKit` and owns `Info.plist` (`LSUIElement`), entitlements, signing, and the App Store archive
- [ ] **MAS-05**: Entitlements finalized: `app-sandbox` + `com.apple.security.network.server` + `com.apple.security.network.client` + user-selected-file read (drag-drop)
- [ ] **MAS-06**: Private `MediaRemote` compile-excluded (`#if`) with a no-op stub on the same seam; pre-submit `strings`/`nm`/`otool -L` grep gate fails the build on any `MediaRemote` symbol
- [ ] **MAS-07**: Xcode 26 toolchain adopted; real `@State` compiles (`@VPState` demoted to an optional CLT compatibility shim, not removed)
- [ ] **MAS-08**: Safari Web Extension appex target scaffolded via `xcrun safari-web-extension-converter`, embedded in the `.app`

### Capture & Sources (CAP)

- [ ] **CAP-01**: Multi-source precedence layer ("last-active-playing wins") sits in front of `updateFromExternal` with graceful hand-off when a source pauses (no new ingestion path / no new `@Published` field)
- [ ] **CAP-02**: Manual source-override picker (Auto / Browser / Spotify / Apple Music) as an escape hatch
- [ ] **CAP-03**: Source-provenance badge driven by existing `Track.source`
- [ ] **CAP-04**: Safari native-messaging producer (`SafariWebExtensionHandler`) funnels into the same `updateFromExternal` seam (Safari cannot use `ws://localhost`)
- [ ] **CAP-05**: Source-precedence rules finalized and documented (resolves the PRD SPEC-phase open question)

### Bridge Security (SEC)

- [ ] **SEC-01**: Extension authentication — shared secret / nonce handshake on the loopback bridge (closes the "any local process can push payloads" gap; also strengthens the App Review narrative)
- [ ] **SEC-02**: Per-frame rate limiting beyond the 6-connection cap
- [ ] **SEC-03**: Origin validation (or a documented, justified mitigation) against cross-origin WS connections

### Scrobbling (SCR)

- [ ] **SCR-01**: Real Last.fm API key/secret wired; desktop auth flow surfaced in Settings; session key stored in Keychain only
- [ ] **SCR-02**: `track.updateNowPlaying` sent on play start, with no retry on failure
- [ ] **SCR-03**: Spec-correct scrobble threshold — at `min(duration/2, 240s)` for tracks ≥30s, via an independent elapsed-listen state machine keyed on stable track identity (not naive `position` math against the 1 Hz extrapolated clock)
- [ ] **SCR-04**: Persistent offline scrobble queue — survives restart, chronological order, batch ≤50, ≥30s spacing, error-29 backoff
- [ ] **SCR-05**: `api_sig` computed as MD5 of alphabetically-sorted `name+value` params + secret
- [ ] **SCR-06**: Scrobble-state indicator implemented as a dedicated leaf view (perf-safe)

### UI Blend (UIB)

- [ ] **UIB-01**: Selected refinements from the ~40 "VinyIpod UI" mockups folded into the five sizes + Dynamic Island, preserving glass tokens and the frozen `CONTRACTS.md` seams
- [ ] **UIB-02**: Track-change micro-interactions bound to `onTrackChanged` (real changes only) — never the position tick
- [ ] **UIB-03**: Reduce-Transparency-aware solid-glass fallback; now-playing text stays legible over glass (contrast never sacrificed for translucency)
- [ ] **UIB-04**: Every UI change batch re-profiled to ≈0.0% idle CPU before the phase is marked done

### Store Submission (SUB)

- [ ] **SUB-01**: App Store archive built and submitted for review; metadata scrubbed (no competitor browser names, emoji, donation asks, or "beta" language)
- [ ] **SUB-02**: Every capture source tested *inside Safari* (MV3→appex fidelity is only ~70–80% out of the converter)
- [ ] **SUB-03**: App Review narrative documents the bridge hardening + shared-secret/nonce handshake to justify the bundled local server + broad browser capture
- [ ] **SUB-04**: Chrome / Firefox store listings submitted (decoupled, trailing — do not block the MAS submission)

## v2 Requirements

Deferred to a future milestone. Tracked, not in this roadmap.

### Enhancements

- **ENH-01**: Cross-fade source-switching polish
- **ENH-02**: `track.love` (Last.fm loving)
- **ENH-03**: Per-source scrobble toggle (add if junk-scrobble complaints appear)
- **ENH-04**: Direct-download Developer-ID notarized `.dmg` hedge — only then is `notarytool` in scope (it is NOT part of the MAS submission). Decide up front whether wanted.

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Simultaneous multi-source display | Breaks the single-source-of-truth `NowPlayingService` model |
| Native `MediaRemote` as default precedence winner | Blocks Mac App Store (private API) and is a no-op on macOS 15.4+ |
| Manual scrobble editing | Junk-data surface; not core to now-playing value |
| Scrobbling short clips / ads (<30s) | Violates Last.fm spec; pollutes history |
| "Glass everywhere" maximalism | Legibility is the product; translucency must never win over contrast |
| Full streaming control (queue editing, library browsing) | Beyond basic transport; not core to the now-playing display |
| Cloud upload / sync of local files | No backend; privacy-first local design |
| Social sharing of now-playing | Out of product focus |
| Paid tiers / monetization | App is free by positioning |
| Reliance on any private framework in the shipping path | Blocks App Store; must be compile-excluded |

## Traceability

Final mapping (each v1 requirement → exactly one phase; roadmapper-finalized during ROADMAP creation).

| Requirement | Phase | Status |
|-------------|-------|--------|
| FND-01 | Phase 0 — Land WIP & Reconcile | Complete |
| FND-02 | Phase 0 — Land WIP & Reconcile | Complete |
| FND-03 | Phase 0 — Land WIP & Reconcile | Complete |
| FND-04 | Phase 0 — Land WIP & Reconcile | Complete |
| TST-01 | Phase 1 — Test Foundation | Pending |
| TST-02 | Phase 1 — Test Foundation | Pending |
| TST-03 | Phase 1 — Test Foundation | Pending |
| TST-04 | Phase 1 — Test Foundation | Pending |
| TST-05 | Phase 1 — Test Foundation | Pending |
| MAS-01 | Phase 2 — Sandbox/Loopback + Signing Spike | Pending |
| MAS-02 | Phase 2 — Sandbox/Loopback + Signing Spike | Pending |
| MAS-03 | Phase 3 — MAS Scaffold + Private-Framework Removal | Pending |
| MAS-04 | Phase 3 — MAS Scaffold + Private-Framework Removal | Pending |
| MAS-05 | Phase 3 — MAS Scaffold + Private-Framework Removal | Pending |
| MAS-06 | Phase 3 — MAS Scaffold + Private-Framework Removal | Pending |
| MAS-07 | Phase 3 — MAS Scaffold + Private-Framework Removal | Pending |
| MAS-08 | Phase 3 — MAS Scaffold + Private-Framework Removal | Pending |
| CAP-01 | Phase 4 — Phase 2 Capture (Precedence, then Scrobbling) | Pending |
| CAP-02 | Phase 4 — Phase 2 Capture (Precedence, then Scrobbling) | Pending |
| CAP-03 | Phase 4 — Phase 2 Capture (Precedence, then Scrobbling) | Pending |
| CAP-04 | Phase 4 — Phase 2 Capture (Precedence, then Scrobbling) | Pending |
| CAP-05 | Phase 4 — Phase 2 Capture (Precedence, then Scrobbling) | Pending |
| SEC-01 | Phase 4 — Phase 2 Capture (Precedence, then Scrobbling) | Pending |
| SEC-02 | Phase 4 — Phase 2 Capture (Precedence, then Scrobbling) | Pending |
| SEC-03 | Phase 4 — Phase 2 Capture (Precedence, then Scrobbling) | Pending |
| SCR-01 | Phase 4 — Phase 2 Capture (Precedence, then Scrobbling) | Pending |
| SCR-02 | Phase 4 — Phase 2 Capture (Precedence, then Scrobbling) | Pending |
| SCR-03 | Phase 4 — Phase 2 Capture (Precedence, then Scrobbling) | Pending |
| SCR-04 | Phase 4 — Phase 2 Capture (Precedence, then Scrobbling) | Pending |
| SCR-05 | Phase 4 — Phase 2 Capture (Precedence, then Scrobbling) | Pending |
| SCR-06 | Phase 4 — Phase 2 Capture (Precedence, then Scrobbling) | Pending |
| UIB-01 | Phase 5 — UI Blend | Pending |
| UIB-02 | Phase 5 — UI Blend | Pending |
| UIB-03 | Phase 5 — UI Blend | Pending |
| UIB-04 | Phase 5 — UI Blend | Pending |
| SUB-01 | Phase 6 — Store Submission | Pending |
| SUB-02 | Phase 6 — Store Submission | Pending |
| SUB-03 | Phase 6 — Store Submission | Pending |
| SUB-04 | Phase 6 — Store Submission | Pending |

**Coverage:**

- v1 requirements: 39 total (FND 4 · TST 5 · MAS 8 · CAP 5 · SEC 3 · SCR 6 · UIB 4 · SUB 4)
- Mapped to phases: 39
- Unmapped: 0 ✓
- Duplicates (requirement in >1 phase): 0 ✓

---
*Requirements defined: 2026-07-03*
*Last updated: 2026-07-03 — traceability finalized during ROADMAP creation*
