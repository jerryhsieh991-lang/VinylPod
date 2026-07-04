---
phase: 00-land-wip-reconcile
plan: 01
subsystem: foundation
tags: [wip-landing, perf-invariants, cpu-profile, git-hygiene]
requires: []
provides:
  - "Full security/crash-fix WIP committed on claude/security-crash-fixes as reviewable, logically-grouped commits"
  - "Capture/, Scrobbling/, Views/Settings/ source dirs in git history (clean clones compile)"
  - "Release dist/VinylPod.app rebuilt from the landed tree with 0.0% idle CPU"
affects: [00-02, 00-03, 00-04, phase-1, phase-4, phase-5]
tech-stack:
  added: []
  patterns:
    - "Equality-guarded Binding for MenuBarExtra(isInserted:) — invariant Rule 2 applied at the scene boundary"
    - ".build symlinked out of iCloud-synced repo to ~/Library/Caches/VinylPodMac.build"
key-files:
  created:
    - Sources/VinylPod/Capture/NativeMediaRemoteCapture.swift
    - Sources/VinylPod/Scrobbling/LastFmClient.swift
    - Sources/VinylPod/Scrobbling/LastFmModels.swift
    - Sources/VinylPod/Scrobbling/LastFmScrobbler.swift
    - Sources/VinylPod/Views/Settings/ (6 files)
    - Sources/VinylPod/Views/Widget/MusicVisualizerContainerView.swift
    - e2e/bridge_stress_test.js
    - e2e/e2e_size_switching.spec.js
  modified:
    - Sources/VinylPod/Core/Services.swift
    - Sources/VinylPod/App/VinylPodApp.swift
    - Sources/VinylPod/Windowing/WindowManager.swift
    - Sources/VinylPod/Views/Widget/ (7 files)
    - BrowserExtension/ (3 files)
    - make_app.sh
    - .gitignore
decisions:
  - "MenuBarExtra(isInserted:) must use a compare-before-assign Binding — raw $settings.showInMenuBar self-sustains a ~100%-CPU render loop"
  - ".build lives outside iCloud (symlink to ~/Library/Caches/VinylPodMac.build) — iCloud fileprovider xattrs break codesign and the swiftbuild database"
  - "make_app.sh must bundle VinylPod_VinylPod.bundle — Bundle.module access fatals at launch without it"
  - "Steady-playback CPU verdict DEFERRED to end-of-phase human check — scripted local-file profile measures designed 30fps animation cost, not the loop regression"
metrics:
  duration: "~35 min active execution (across 2 sessions; first was cut by a session limit before any commit)"
  completed: "2026-07-03"
  tasks: 3
  files: 35
status: complete
---

# Phase 00 Plan 01: Land WIP & Re-verify Performance Invariants Summary

**One-liner:** Landed the entire 480+-insertion security/crash-fix WIP (33 paths incl. Capture/Scrobbling/Settings scaffolds) as four grouped feat commits + externally-committed config, then caught and fixed a real ~100%-idle-CPU MenuBarExtra binding loop during the mandated re-profile — final idle CPU 0.00%.

## Commits (FND-01 evidence — plan 00-04 cites these)

| # | SHA | Subject | Group |
|---|-----|---------|-------|
| 1 | `fb8ab0a` | feat(00-01): land bridge/extension JS hardening + e2e scripts | Group 1 (3 BrowserExtension JS + 2 e2e) |
| 2 | `d6f26f2` | feat(00-01): land core service gating, models, theme + capture/scrobbling scaffolds | Group 2 (7 core/audio/app/windowing + Capture/ + Scrobbling/) |
| 3 | `7d91ef7` | feat(00-01): land desktop widget canvas + glass widget refinements | Group 3 (7 widget views + MusicVisualizerContainerView) |
| 4 | `7338518` | feat(00-01): land settings window sections, menu, and OS effects | Group 4 (SettingsMenu, SettingsEffects + Views/Settings/) |
| 5 | `bb5d282` | chore: update workflow settings (per-phase branching, intel, research-qs) | Group 5 (.planning/config.json — committed EXTERNALLY by the orchestrator mid-run; see Deviations) |
| 6 | `37a5aa9` | fix(00-01): ignore .build as symlink (relocated out of iCloud) | Deviation fix |
| 7 | `59342d5` | fix(00-01): bundle SPM resources into dist/VinylPod.app | Deviation fix |
| 8 | `e400241` | fix(00-01): equality-guard MenuBarExtra(isInserted:) binding — kills ~100% idle-CPU loop | Deviation fix (Rule 1) |

Branch throughout: `claude/security-crash-fixes` (no branch created/switched; no destructive git command used; every commit used explicit path lists).

Post-landing tree state: `git status --porcelain` shows NO entries under `Sources/`, `BrowserExtension/`, or `e2e/`. Remaining (by design, for plans 00-02/00-03): ` D README.md`, `?? docs/settings-audit.md`, `?? docs/asset-catalog-migration.md`, `?? VinylPod-Complete-Documentation.md`. `git ls-files` counts: Scrobbling/ = 3, Views/Settings/ = 6.

## Task 1 — Preflight & static invariant review

**WIP inventory captured (git status --porcelain before landing):** 20 tracked modifications (BrowserExtension ×3, Core ×3, Audio ×2, App ×2, Widget views ×8, Windowing ×1, .planning/config.json) + unstaged ` D README.md` (left for 00-02) + untracked `Sources/VinylPod/Capture/` (1 file), `Sources/VinylPod/Scrobbling/` (3 files), `Sources/VinylPod/Views/Settings/` (6 files), `Sources/VinylPod/Views/Widget/MusicVisualizerContainerView.swift`, `e2e/` (2 files), docs leftovers. All named critical paths present.

**Pre-landing build:** `swift build` exit 0, "Build complete! (63.39 sec)" — after the .build/iCloud environment fix (see Deviations).

**Static review verdict — all six render-loop invariants:**

| Rule | Verdict | Evidence |
|------|---------|----------|
| 1 — no NowPlayingService observation in always-on parents | PASS | New views' only observation wrappers: `@ObservedObject var settings: AppSettings` ×5, `@ObservedObject scrobbler = LastFmScrobbler.shared` ×1. CaptureSettingsSection touches `AppEnvironment.shared.nowPlaying` imperatively only (toggle action + manual `refreshIndicator()`), never observes it. MusicVisualizerContainerView: zero NowPlayingService references. |
| 2 — `position` only unconditional @Published write in updateFromExternal | PASS | Diff does not touch `updateFromExternal`; body verified: `track`/`isPlaying`/`duration` all inequality-guarded, `position = pos` remains the sole unconditional write, `onTrackChanged` fires only on `trackChanged`. New native-capture callback routes through the same seam at ≤1 Hz. |
| 3 — position reads coarsened to whole seconds | PASS | Exactly one added widget-diff code line reads position (DesktopWidgetCanvas.swift): `let elapsed = isEmpty ? 0 : Int(max(0, nowPlaying.position))` — Int-coarsened. The other two grep hits are comment lines documenting that same fix. |
| 4 — setAlbumPalette only on real track changes | PASS | Zero call sites in Services.swift (definition only). Both call sites live in VinylPodApp.swift inside `env.nowPlaying.onTrackChanged` (fires only on `trackChanged`); the VinylPodApp diff adds only the ⌘, shortcut handler, untouched palette path. |
| 5 — cross-fade, no `.id(mode)` pinning | PASS | `grep -c 'transition(.opacity)' ModeContentView.swift` = 3 (file not in diff); added `.id(mode` lines in Views diff = 0. |
| 6 — modeTransitionInFlight guard survives | PASS | 4 occurrences in WindowManager.swift; the diff only adjusts island panel host sizes (402×594 / 326×36), guard untouched. |

## Task 2 — Landing

Five groups planned; four committed by this executor (`fb8ab0a`, `d6f26f2`, `7d91ef7`, `7338518`), group 5's content committed externally as `bb5d282` (see Deviations). `git show --stat` on each commit confirmed no unexpected path swept in; no file deletions in any commit. Landed tree: `swift build` → "Build complete!".

## Task 3 — Release rebuild & CPU re-profile

**Build:** `./make_app.sh release` → "✓ Built dist/VinylPod.app" (after two blocking fixes below).

**IDLE profile (primary regression gate) — PASS:**

```
12 samples, 2 s apart (ps -o %cpu=):
0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0
mean = 0.00  (gate: < 1.0)   max = 0.00  (gate: every sample < 5.0)
```

`sample VinylPod 5` excerpt (healthy — main thread 100% parked, no render-loop hot path):

```
Call graph:
    4339 Thread_654280   DispatchQueue_1: com.apple.main-thread  (serial)
    + 4339 start (dyld) → main (VinylPod) → App.main() → NSApplicationMain
    +   → -[NSApplication run] → nextEventMatchingMask:…
    +     → _DPSBlockUntilNextEventMatchingListInMode
    +       → __CFRunLoopServiceMachPort → mach_msg2_trap   [all 4339 samples]
```

**IMPORTANT — this idle result is AFTER fixing a real regression the profile caught.** The first idle profile of the landed tree measured **mean 99.77% / max 100.0%** — the historical loop signature exactly (`AppDelegate.makeMainMenu → AppKitMainMenuItem.updateMainMenu → MainMenuItemHost.requestUpdate → GraphHost.updatePreferences`, 1743/2275 samples), with `AppSettings.showInMenuBar.setter` firing inside the loop. Root cause: `MenuBarExtra(isInserted: $settings.showInMenuBar)` — MenuBarExtra re-writes the binding during scene updates, `@Published` fires `objectWillChange` on every assignment (no equality check), the observed App body re-invalidates, MenuBarExtra writes again. Pre-existing on the branch (introduced in `2f8463e`, not by the landed groups) but a hard FND-01 gate failure. Fixed in `e400241` with a compare-before-assign Binding; idle fell from ~100% to 0.00%.

**STEADY-PLAYBACK profile — thresholds exceeded, NO loop regression; verdict DEFERRED to end-of-phase human check:**

- Playback engaged: `lsof` shows `test.aiff` open by VinylPod (count = 1) — measurement is valid, not skipped.
- `12 samples: 17.2 15.6 16.8 15.4 15.6 15.6 15.2 16.8 16.2 17.0 17.7 16.4 → mean 16.29 (gate < 2.0), max 17.7 (gate < 10.0)` — numeric gates FAIL.
- `sample VinylPod 5` during playback shows the failure mode is ABSENT: 1329/2297 main-thread samples parked in `mach_msg`; the remainder diffuses across *designed* 30 fps `TimelineView` animation work (`EqualizerBars` — DynamicIslandWidget.swift:705/707, `paused: !active`, active during playback by design per the invariants' own corollary; vinyl-disc spin; `MediumProgressStrip`), all as scattered 1-sample frames. No `makeMainMenu`/`requestUpdate`/`updatePreferences` loop signature anywhere in the trace.
- Interpretation: the plan's ~0.0% expectation models bridge-path 1 Hz ingestion with animation surfaces mostly quiescent; the scripted local-file profile instead drives 10 Hz `reportTick` plus two visible animated surfaces (dynamic island equalizer + spinning disc, `dynamicNotch=1` on this machine). ~16% of one core is the cost of the permitted animations while audibly playing, not an invariant violation.
- Per the plan's own guidance that idle is the primary regression gate and its end-of-phase `<human-check>` covers the real bridge path: **playback verdict recorded as DEFERRED to the end-of-phase human check** (play music via the extension ~1 min, confirm Activity Monitor ~0.0%). If the human check also shows sustained high CPU on the bridge path, start from the EqualizerBars `active` gating.

**Cleanup:** app quit (`pgrep -x VinylPod` → no process), `/tmp/vinylpod-profile` removed.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Relocated `.build` out of iCloud; widened .gitignore pattern**
- **Found during:** Task 1 (pre-landing `swift build` gate)
- **Issue:** Repo lives on iCloud-synced Desktop. iCloud fileprovider stamped xattrs onto build products → codesign failed ("resource fork, Finder information, or similar detritus not allowed") and the swiftbuild database hit sqlite "disk I/O error"; `swift build` exited 1.
- **Fix:** `.build` → symlink to `~/Library/Caches/VinylPodMac.build` (matches documented project constraint "keep .build out of iCloud"); `.gitignore` `.build/` → `.build` (dir pattern doesn't match a symlink).
- **Files modified:** .gitignore (local env symlink is untracked)
- **Commit:** `37a5aa9`

**2. [Rule 3 - Blocking] make_app.sh never bundled the SPM resource bundle → launch fatal**
- **Found during:** Task 3 (app died instantly on `open`)
- **Issue:** Landed WIP loads default artwork via `Bundle.module` (SmallGlassWidget.swift `DefaultArtworkAsset`); without `VinylPod_VinylPod.bundle` in Contents/Resources the app fatals at `resource_bundle_accessor.swift:44`.
- **Fix:** make_app.sh copies the bundle into Contents/Resources and exits 1 loudly if missing.
- **Files modified:** make_app.sh
- **Commit:** `59342d5`

**3. [Rule 1 - Bug] MenuBarExtra(isInserted:) unguarded @Published binding → ~100% idle-CPU self-sustaining loop**
- **Found during:** Task 3 idle profile (mean 99.77% — hard gate failure)
- **Issue/Fix/Evidence:** See Task 3 section above. Compare-before-assign Binding; idle 0.00% after fix.
- **Files modified:** Sources/VinylPod/App/VinylPodApp.swift
- **Commit:** `e400241`

### Other Deviations

**4. Group 5 (.planning/config.json) committed externally mid-run.** The orchestrator committed the config WIP as `bb5d282` ("chore: update workflow settings…") between my group-2 and group-3 commits, leaving nothing to commit for the planned `chore(00-01)` subject. The config change IS in history on the branch; only the commit subject/authorship differs from plan. No empty commit was fabricated. Consequently the literal acceptance check "`git log --oneline -5 | grep -c '(00-01)'` = 5" is satisfied in spirit (4 executor feat commits + external config commit + 3 fix commits), not literally.

**5. Steady-playback numeric gates exceeded → DEFERRED verdict** (documented in Task 3 above; not silently passed).

## Known Stubs

| Stub | File | Reason |
|------|------|--------|
| Native MediaRemote capture is best-effort scaffold, OFF by default | Sources/VinylPod/Capture/NativeMediaRemoteCapture.swift | Entitlement-gated on macOS 15.4+; Phase 3 compile-excludes private MediaRemote for MAS; Phase 4 owns capture precedence |
| Last.fm scrobbling scaffold landed but integration completes later | Sources/VinylPod/Scrobbling/* | Phase 4 (Precedence → Scrobbling) wires and verifies it |
| `INTEGRATION POINT` comment for settings sections composition | Sources/VinylPod/Views/Settings/SettingsWindow.swift:171 | Sections exist and are wired; comment marks the composition seam for later phases |

## Threat Flags

| Flag | File | Description |
|------|------|-------------|
| threat_flag: network-egress | Sources/VinylPod/Scrobbling/LastFmClient.swift | New outbound HTTPS surface (Last.fm API) not in this plan's threat model — landed as WIP scaffold; review when Phase 4 activates scrobbling |
| threat_flag: private-framework | Sources/VinylPod/Capture/NativeMediaRemoteCapture.swift | Private MediaRemote access (OFF by default); Phase 3 must compile-exclude for MAS (symbol-grep gate) |

## Verification vs success criteria

- Full code WIP (33 paths) committed in logically-grouped, reviewable commits; no destructive git operation used — DONE (see Deviations #4 for group 5).
- Landed tree compiles (`Build complete!`); rebuilt release app measures **0.00% idle CPU** — DONE (after fixing a genuine loop regression the gate existed to catch).
- Evidence (samples, means, `sample` excerpts) recorded above — DONE. Steady-playback bridge-path measurement deferred to the plan's end-of-phase human check.

## Self-Check: PASSED

All 8 commit SHAs present on claude/security-crash-fixes; all created files exist on disk; SUMMARY.md written.
