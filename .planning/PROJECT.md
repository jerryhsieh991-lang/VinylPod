# VinylPod

## What This Is

VinylPod is a **free, native macOS menu-bar (accessory) app** that captures and beautifully displays the currently-playing track — from **any browser tab** (Spotify Web, Apple Music Web, YouTube/YT Music, or any site via the W3C MediaSession API, read by a cross-browser extension over a hardened loopback WebSocket) and from **local audio files** (drag-and-drop, AVFoundation). It renders now-playing as a liquid-glass, adaptive-themed widget in **five selectable sizes plus a Dynamic Island**, with static landscape backdrops. It is built with **Swift Package Manager (SwiftUI + AppKit)**, no third-party dependencies.

It serves two users at once: the **visual lover** who treats it as calm desktop decor, and the **general listener** who wants zero learning curve.

## Core Value

Show what's playing — beautifully, calmly, and reliably — for *browser* playback that every competitor misses, without depending on Apple's private, now-restricted `MediaRemote` hook. If everything else fails, the browser-capture → glass now-playing display must work.

## Business Context

- **Customer**: Individual macOS users (music/visual enthusiasts + general listeners) who want a good-looking, free now-playing widget, especially for browser-based playback.
- **Revenue model**: Free, no paid tiers enforced in code. (Positioning is "the free, App-Store-safe option" vs. mostly-paid competitors.)
- **Success metric**: A shippable, signed/notarized app users can install and trust — ultimately listed on the Mac App Store.
- **Strategy notes**: Competitive survey of 12+ now-playing apps in `docs/system-design/00-product-vision.md`; canonical design/architecture lives in `docs/system-design/`.

## Requirements

### Validated

<!-- Inferred from the existing, building codebase (~9,300 LOC Swift + MV3 extension). These work today. -->

- ✓ Local-file drag-and-drop playback (AVFoundation) with ID3/AVAsset metadata — existing
- ✓ Browser-extension web capture (MV3 content scripts + service worker) → loopback WebSocket → `BrowserBridge` → `NowPlayingService` — existing
- ✓ Single-source-of-truth `NowPlayingService` (@MainActor) unifying local + external inputs — existing
- ✓ Adaptive album-art accent (`ArtworkColorExtractor` → `AlbumColorPalette`) driving liquid-glass surfaces — existing
- ✓ Five window modes (Small / Normal / Large / Desktop Widget) + Dynamic Island, one reused `NSPanel` with opacity cross-fade — existing
- ✓ Menu-bar accessory shell, three-dot dropdown + Settings window, ⌘1–4 size shortcuts, system-wide Carbon hotkeys — existing
- ✓ Empty / loading / error states; procedural + custom-image landscape backgrounds — existing
- ✓ Desktop-widget front/behind layer toggle (above/below desktop icons) — existing
- ✓ Hardened bridge threat model (loopback bind, 256 KB frame cap, 6-connection cap, SSRF guard, `data:` decode, 8 MB image cap) — existing
- ✓ Six documented performance invariants preventing the historical ~98% idle-CPU render loop — existing

### Active

<!-- This cycle: a full re-plan treating docs as spec. Decisions: BLEND UI + PURSUE MAC APP STORE. Hypotheses until shipped & validated. -->

- [ ] Land & reconcile: commit WIP drift, designate `docs/system-design/` canonical, delete duplicate/stale docs, refresh map
- [ ] Test foundation: add an SPM test target; unit-test bridge security (`isPublicHost`, `decodeDataURI`), `updateFromExternal` change-gating, perf invariants
- [ ] Bridge hardening gaps: extension authentication (shared secret/nonce), per-frame rate limiting, Origin validation
- [ ] Wire Phase 2 capture: real Spotify / Apple Music / browser source selection end-to-end; finish source-precedence rules
- [ ] Last.fm scrobbling: real credentials + wiring (currently empty-string placeholders → no-op)
- [ ] UI refinement (BLEND): keep glass architecture/tokens; fold selected improvements from the new "VinyIpod UI" mockups into the five sizes + Dynamic Island
- [ ] Mac App Store readiness: Xcode project/target, code signing + entitlements, App Sandbox, remove/guard private `MediaRemote.framework`, Safari Web Extension packaging, notarization pipeline
- [ ] Housekeeping: `.gitignore` `.playwright-mcp/`, remove empty `claude.md`, consolidate seven `*_features.json`

### Out of Scope

- Full streaming playback control beyond basic transport (queue editing, library browsing) — not core to the now-playing value
- Cloud upload / sync of local files — no backend; privacy-first local design
- Social sharing of now-playing — out of product focus
- Native desktop-app (Spotify.app / Music.app) capture as a *relied-upon* path — Apple entitlement-gated `MediaRemote` on macOS 15.4+; browser bridge is the durable path (native stays experimental/off)
- Paid tiers / monetization features — app is free by positioning
- Reliance on private frameworks in the shipping path — blocks App Store; must be removed/guarded

## Context

- **Maturity vs. docs**: The app is substantially built (~9,300 LOC + working extension + build pipeline), but `PRD.md` still says "no application code written yet." `docs/system-design/` describes the real architecture and should be treated as canonical.
- **Working-tree drift**: On branch `claude/security-crash-fixes`, ~19 modified files are uncommitted (480 insertions / 164 deletions), concentrated in perf/security-critical `Core/Services.swift`, `Windowing/WindowManager.swift`, and the three `BrowserExtension/*.js` files. Must be landed & re-verified against the perf invariants before/at the start of this cycle.
- **Toolchain**: Command Line Tools only (no Xcode). macOS 26 SDK makes SwiftUI `@State` a macro whose plugin ships only with Xcode, so the code uses a `@VPState`/`typealias VPState = SwiftUI.State` workaround. Pursuing the App Store **requires** introducing a real Xcode toolchain/target — a central constraint of this cycle.
- **Capture reality**: MediaSession browser capture is the durable path. Native `MediaRemote` capture is experimental, off by default, and a graceful no-op on macOS 15.4+.
- **Design system**: Liquid-glass adaptive theming, `AlbumColorPalette` four-role color model, per-size visual recipes, `VPTheme` tokens (`Core/Theme.swift`). Documented in `docs/system-design/06-design-system.md`.
- **Codebase map**: Fresh analysis in `.planning/codebase/` (STACK, INTEGRATIONS, ARCHITECTURE, STRUCTURE, CONVENTIONS, TESTING, CONCERNS).
- **UI mockups**: ~40 fresh screenshots in `~/Desktop/VinyIpod UI/` — reference for the BLEND UI-refinement work.

## Constraints

- **Tech stack**: Swift + SwiftUI + AppKit via SwiftPM, no third-party deps — established architecture; keep the frozen `CONTRACTS.md` seams intact.
- **Toolchain**: `@VPState` workaround required under Command Line Tools; introducing Xcode for App Store must not break the `swift build` / `make_app.sh` path used for dev today.
- **Performance**: The six perf invariants are convention-enforced, not compiler-enforced — any change to `Services.swift`/`WindowManager.swift`/always-on views must be re-profiled (target 0.0% idle CPU).
- **Security**: The loopback bridge is the single ingestion point for untrusted (extension) input; App Sandbox must still permit the `127.0.0.1:8787` server binding — a real feasibility question for the App Store path.
- **Distribution**: Mac App Store requires signing, App Sandbox entitlements, and **zero** private-framework dependencies in the shipping path.
- **Compatibility**: macOS target must account for the macOS 15.4+ `MediaRemote` lockdown; hotkeys use Carbon `RegisterEventHotKey` to avoid demanding Accessibility permission.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Full re-plan treating `docs/` as the spec | Docs are richer/more current than the stale PRD; produce one coherent end-to-end roadmap | — Pending |
| Map the live codebase before planning | ~19-file WIP drift; docs describe committed state — plan must reflect reality | ✓ Good (map committed `281e675`) |
| BLEND UI: keep glass architecture, fold in mockup refinements | Preserve proven perf-critical rendering + tokens; selectively adopt new "VinyIpod UI" ideas | — Pending |
| Pursue Mac App Store distribution | Signed/notarized, sandboxed, private-framework-free = a trustworthy, listable free app | — Pending |
| Browser extension over private `MediaRemote` | App-Store-safe, cross-browser, unaffected by the macOS 15.4 lockdown | ✓ Good (already the default path) |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Business Context check — customer, revenue model, success metric still accurate?
4. Audit Out of Scope — reasons still valid?
5. Update Context with current state

---
*Last updated: 2026-07-03 after initialization*
