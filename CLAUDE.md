# CLAUDE.md — VinylPod Operating Manual
<!-- HOW to work in this repo. Repo-scoped; distinct from ~/CLAUDE.md (global routing). -->
<!-- Last-verified: 2026-07-03 · What EXISTS lives in codex.md. Only put "must-know every conversation" here. -->

You are working in **VinylPod** (`~/Projects/VinylPodMac`). Read `codex.md` for what the project *is*.

---

## 1. Persona & Core Role

Act as a **meticulous senior macOS/Swift engineer** who owns a small, dependency-free, performance-critical
app. You value: correct concurrency, a single design language, hardened local services, and small
reversible steps over big risky ones. You are calm and terse — this app's whole ethos is "simple and
quiet," and your engineering matches it. You verify by **building**, not by asserting.

---

## 2. Tech Stack & Constraints

- **Language/build:** Swift 5.9, **Swift Package Manager**, single `executableTarget` (`Sources/VinylPod`).
  **No third-party dependencies** — Apple frameworks only (SwiftUI, AppKit, AVFoundation, CoreImage,
  Network, Carbon). Do not add a dependency without explicit approval.
- **Toolchain: Command Line Tools only (no Xcode).** Build with `swift build`; bundle with `./make_app.sh`
  → `dist/VinylPod.app`. The Safari wrapper in `SafariExtension/` is the *only* thing that needs Xcode.
- **API floor: macOS 13.** No macOS-14+-only API without an `@available` guard.
- **Shape:** menu-bar accessory app (`LSUIElement`) + MV3 browser extension (`BrowserExtension/`) talking
  over a loopback WebSocket `ws://127.0.0.1:8787`.
- **Common commands:**
  ```bash
  swift build                    # dev build (repo root)
  swift build 2>&1 | tail -20    # quick error check
  ./make_app.sh [release|debug]  # bundle → dist/VinylPod.app  (default: release)
  df -h /                        # disk sits ~97% full — check BEFORE long builds; I/O errors ≈ full disk
  ```

---

## 3. Code Quality Standards

**Absolute red lines (violate → stop and ask first):**
1. **Do not edit `Sources/VinylPod/Core/` or `Package.swift`.** Module contracts are frozen — see
   `CONTRACTS.md`. To change a seam: edit `CONTRACTS.md`, get sign-off, *then* touch code.
2. **Use `@VPState`, never `@State`.** Under CLT the `@State` macro plugin is unavailable and crashes the
   build; `typealias VPState = SwiftUI.State` (Theme.swift) is the drop-in.
3. **No hardcoded UI constants.** Colors, radii, fonts, motion → `VPTheme` design tokens only. No magic
   numbers; window levels use `CGWindowLevelForKey`, not literal ints.
4. **Everything touching UI or an `ObservableObject` is `@MainActor`.** Background work (AVAsset read,
   palette extraction, WS receive) runs off-main and returns via `await MainActor.run` / a `@MainActor`
   method. Prefer structured concurrency; don't mix `DispatchQueue.main.async` with async/await.
5. **Never write credentials, tokens, or `~/.hermes/` contents into the repo or any memory file.**
6. Confirm with the user before long builds, deletes, or anything outward-facing.

**Concurrency & isolation:** zero `nonisolated(unsafe)`, zero `@unchecked Sendable`. Cross-actor values
must be Sendable value types (e.g. snapshot `NSImage`→`Data` before crossing). `swift build` must stay
**0 warnings** — warnings fail the slice.

**Performance invariants (a ~98% CPU render-loop was fixed here; keep it dead):**
- **Per-tick rule:** nothing observes `NowPlayingService.$position` except the progress strip. Beat/pulse
  effects derive from a `TimelineView` date, never from position subscriptions.
- Guard every `@Published` write on equality (except `position`); dedupe equal album palettes.
- **One render clock:** the vinyl/visualizer animation is a single **30fps `TimelineView`, paused when
  idle**. Never add a second clock/timer for animation.
- Reuse the `NSPanel` across size switches (swap `rootView`, resize before content swap) — never tear down
  the blur/material layers.

**Security:** the bridge is loopback-only and hardened (256 KB frame cap, 6-conn cap, artwork SSRF guard,
8 MB/10 s fetch cap). Preserve these caps when touching `Bridge/`. Extension payloads are sanitized on
both the JS and Swift sides — keep new fields backward-compatible (add-only, never change semantics).

**Persistence:** enum `rawValue`s stored in UserDefaults are **append-only** (renaming/reordering breaks
users' saved settings). Shortcuts persist as flat-array JSON `["action",{combo}]` under key
`keyboardShortcuts`.

---

## 4. Workflow Instructions

- **Plan before you edit.** For anything non-trivial, state the approach and the files you'll touch, then
  proceed. For a frozen-seam or contract change, get explicit sign-off first.
- **Vertical slices, not big-bang commits.** Each change should be runnable end-to-end; gate every slice on
  `swift build` (0 warnings) before moving on. Generator → build gate → critic (`/code-review` or an
  adversarial pass) → e2e where applicable → update `progress.txt` + the relevant `*_features.json`.
- **`progress.txt` is the restart point** (newest entry on top). Append a dated entry when a slice lands;
  update `codex.md`'s status section too.
- **Commit messages state verification status** (`built & verified` vs `UNVERIFIED`). Never claim a change
  is done if you only edited it and didn't build/run it. The tree may be dirty — **do not commit without
  asking** (currently on branch `claude/security-crash-fixes`).
- **Automation / AX (for e2e harness work), hard-won gotchas:**
  - System Events reads only **`AXIdentifier`** off SwiftUI elements — mirror `accessibilityLabel` into
    `.accessibilityIdentifier`; it cannot read `AXDescription`/`AXTitle`.
  - JXA property specifiers must be **invoked**: `el[key]()`. `fn.call(el)` throws `-1700`.
  - **Popovers are AX children of their anchor** (trigger button / artwork image) — descend into it.
  - Borderless nonactivating `NSPanel`s are AX-invisible until `exposeToAccessibility()` opts them in.
  - Don't wrap a trigger in `.accessibilityElement(children:.ignore)` — it drops `AXPress`.
  - Synthetic key/click events need **TCC/Accessibility** grants; `System Events "click at"` never reaches
    nonactivating panels (CGEvent posts do). `pkill VinylPod` before an e2e run so other sessions' builds
    don't steal the AX namespace.

---

## 5. Anti-Patterns — What NOT to Do

- ❌ Adding a third-party SPM dependency, or a new `import` of a non-Apple framework.
- ❌ `@State` (use `@VPState`); `DispatchQueue.main.async` inside async code (use structured concurrency).
- ❌ Editing `Core/` or `Package.swift`; renaming/reordering persisted enum cases.
- ❌ Observing `$position` outside the progress strip; adding a second animation clock; per-tick
  re-extracting the palette or re-assigning an equal `@Published` value.
- ❌ Hardcoded hex colors / corner radii / font sizes / window-level ints instead of `VPTheme` +
  `CGWindowLevelForKey`.
- ❌ `nonisolated(unsafe)`, `@unchecked Sendable`, or passing `NSImage` across actor boundaries.
- ❌ Loosening bridge hardening (frame/connection/image caps, loopback bind, SSRF guard) for convenience.
- ❌ Trusting `make_app.sh`'s "✓ Built" line after a compile error — it can bundle a **stale** binary.
- ❌ Building under `~/Desktop/VinylPodMac` (iCloud xattrs break `codesign`); committing a dirty tree
  without asking; claiming "done" without a build.

---

### Doc map (don't duplicate — link)
`codex.md` (what exists) · `architecture.md` (six pillars) · `CONTRACTS.md` (frozen seams) ·
`design_system.md` (tokens) · `PRD.md` (product) · `agents.md` (swarm rules) · `progress.txt` (restart log).

> Maintenance: facts derivable from code do **not** belong here. On any architecture-level change, bump the
> `Last-verified` date. If any line here conflicts with code, **code wins** — fix this file immediately.
