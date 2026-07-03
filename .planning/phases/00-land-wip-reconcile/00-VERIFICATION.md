---
phase: 00-land-wip-reconcile
verified: 2026-07-03T21:30:00Z
status: human_needed
score: 5/6 must-haves verified
behavior_unverified: 1 # SC1's CPU-invariant truth: code present + wired, all six invariants statically re-verified by this verifier; runtime idle/playback CPU not re-exercised (requires launching the app)
overrides_applied: 0
behavior_unverified_items:
  - truth: "The rebuilt release app idles at ~0.0% CPU and stays ~0.0% during steady playback (the six perf invariants hold at runtime)"
    test: "Launch dist/VinylPod.app; observe Activity Monitor idle ~1 min; then play music in a browser tab through the extension for ~1 min"
    expected: "Track shows in the widget; VinylPod reads ~0.0% CPU at idle AND during steady bridge-path playback (no sustained high-CPU loop)"
    why_human: "Runtime CPU behavior cannot be proven by grep/presence checks, and re-profiling requires launching a GUI service (out of verifier scope). Executor recorded idle 0.00% (12 samples + sample trace) AFTER fixing a real ~100%-CPU MenuBarExtra loop (e400241); the scripted playback profile measured ~16.3% attributed to by-design 30fps TimelineView animations (no loop signature) and was DEFERRED by the plan's own end-of-phase human check."
human_verification:
  - test: "Launch dist/VinylPod.app, let it idle ~1 min with Activity Monitor open, then play music in a browser tab through the extension for ~1 min with the widget visible"
    expected: "Track appears in the widget; Activity Monitor shows VinylPod at ~0.0% CPU at idle and during steady playback (no sustained high-CPU render loop)"
    why_human: "Bridge-path 1 Hz ingestion + real animation quiescence can only be observed at runtime; the scripted local-file profile drives 10 Hz reportTick + two always-animated surfaces and cannot approximate the bridge path. If steady playback shows sustained high CPU, start investigating from EqualizerBars `active` gating (DynamicIslandWidget.swift ~705)."
---

# Phase 0: Land WIP & Reconcile — Verification Report

**Phase Goal:** The ~19-file working-tree WIP is committed and re-verified against the six perf invariants, `docs/system-design/` is the canonical spec, the repo root is de-noised, and the codebase map reflects committed state.
**Verified:** 2026-07-03T21:30:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

Merged from ROADMAP Success Criteria 1–4 + the four plans' `must_haves.truths` (dedup: plan truths restate SC wording where they overlap).

| # | Truth | Status | Evidence |
| --- | ----- | ------ | -------- |
| 1 | Clean working tree; WIP landed as logically-grouped, reviewable commits (SC1 structural / FND-01) | ✓ VERIFIED | `git status --porcelain` empty. Branch-scoped log shows all landing commits: `fb8ab0a` (bridge JS + e2e), `d6f26f2` (core gating + Capture/Scrobbling), `7d91ef7` (widget canvas), `7338518` (settings), `bb5d282` (config, committed externally by orchestrator — intent met, documented deviation), plus fixes `37a5aa9`/`59342d5`/`e400241`. All 14 claimed SHAs resolve via `git cat-file -t`. No destructive-op scars: `git show --stat` per commit matches planned path groups exactly. |
| 2 | Committed state compiles, including previously-untracked Capture/, Scrobbling/, Views/Settings/ (plan 00-01 truth) | ✓ VERIFIED | Verifier ran `swift build` on the clean tree (= committed content): "Build complete!". `git ls-files` counts: Capture/ = 1, Scrobbling/ = 3, Views/Settings/ = 6, e2e/ = 2, MusicVisualizerContainerView.swift tracked. |
| 3 | Rebuilt app idles at ~0.0% CPU and stays ~0.0% during steady playback — six perf invariants hold at runtime (SC1 behavioral) | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | All six invariants independently re-verified statically by this verifier in the COMMITTED code (see table below). Executor-recorded idle profile: 12×0.0 samples, mean 0.00%, healthy `sample` trace — after catching and fixing a genuine ~100%-idle-CPU MenuBarExtra binding loop (`e400241`, compare-before-assign Binding confirmed present at VinylPodApp.swift:32-42). Steady-playback verdict DEFERRED by the plan itself (scripted profile ≈16.3% = by-design 30fps TimelineView animations, no loop signature in trace). Runtime behavior not re-exercised by this verifier (requires launching the app) → routes to human check per Step 3/8. |
| 4 | docs/system-design/ is the single canonical spec; no doc claims the app is unbuilt; `design_system 2.md`/claude.md/codex.md/stale PRD status gone; seven root feature JSONs consolidated (SC2 / FND-02) | ✓ VERIFIED | `docs/system-design/README.md`: canonical statement present (`canonical`=1, `CONTRACTS.md`=1, not demoted). PRD.md header reads "Status: **HISTORICAL — founding PRD…**", points to docs/system-design/ + .planning/; zero hits for "no application code written yet"/"awaiting founder sign-off". Absent on disk AND index: `design_system 2.md`, claude.md, codex.md, README.md (reappeared claude.md/codex.md were relocated to ~/.claude/notes/ per drift-gate STOP — verified absent now). Appendix A in 07-feature-inventory.md contains all seven original filenames + accent hexes (#C592AB/#D18FB8/#BD6BAD) + dimensions (162, 300 x 360, 320 x 432); consolidation and `git rm` atomic in `51f7cb8` (+142/−319). `git ls-files '*_features.json'` = only BrowserExtension/extension_backend_features.json; `design_system.md` (non-duplicate) retained. Both docs/ audits tracked. |
| 5 | Repo root de-noised: .playwright-mcp/ gitignored + absent, zero .DS_Store, stitch-file ignored in place (SC3 / FND-03) | ✓ VERIFIED | `git check-ignore` binds: `.playwright-mcp/`, `VinylPod-Complete-Documentation.md`, `.DS_Store`, `.planning/research/.cache/` (drift disposition). `.playwright-mcp/` absent (e79c990 pre-purge held). `find` .DS_Store count = 0 (outside .git/.build). Stitch-file still on disk (ignored, NOT deleted). `5dfea7f` touches .gitignore alone (+5). Existing ignore entries preserved. |
| 6 | .planning/codebase/ map reflects committed state — RESOLVED markers with landing SHAs, zero pre-WIP references (SC4 / FND-04) | ✓ VERIFIED | `grep -c 'RESOLVED (Phase 0' CONCERNS.md` = 5. Zero `f0a4c1c` hits anywhere under .planning/codebase/; zero "uncommitted/not committed" staleness hits. CONCERNS.md cites 11 real landing SHAs (all verified to exist). Still-true concern "No test target anywhere" preserved (=1). File-inventory spot-check: 10 tracked files across Settings/Scrobbling/Capture. Note: SC4's word "regenerated" was satisfied as a scoped refresh — the map was generated 2026-07-03 from the same tree content that landed, so inventories already match committed state; deeper derived-analysis drift ("Test Coverage Gaps" contradicts tracked Tests/) is explicitly flagged in-doc with a `/gsd-map-codebase` remap recommendation per the plan's no-hand-rewrite discipline. See Warnings. |

**Score:** 5/6 truths verified (1 present, behavior-unverified)

### Six-Invariant Static Re-verification (verifier-independent, committed code)

| Rule | Check | Result |
| ---- | ----- | ------ |
| 1 — no NowPlayingService observation in always-on parents | grep of observation wrappers across Views/Settings/ + MusicVisualizerContainerView | PASS — zero `@EnvironmentObject/@ObservedObject/@StateObject` of NowPlayingService; only doc comments referencing the invariant |
| 2 — `position` sole unconditional @Published write in updateFromExternal | Services.swift:100-113 read directly | PASS — `track`/`isPlaying`/`duration` all inequality-guarded; `position = pos` only unconditional write; `onTrackChanged` fires only on `trackChanged` |
| 3 — position reads coarsened to whole seconds | DesktopWidgetCanvas.swift:620 | PASS — `Int(max(0, nowPlaying.position))` |
| 4 — setAlbumPalette only on real track change | All call sites grepped | PASS — both call sites (VinylPodApp.swift:109,115) inside `env.nowPlaying.onTrackChanged` closure |
| 5 — cross-fade, no `.id(mode)` pinning | ModeContentView.swift + Views tree | PASS — `transition(.opacity)` × 3; zero `.id(mode` in Sources/VinylPod/Views/ |
| 6 — modeTransitionInFlight guard | WindowManager.swift | PASS — 4 occurrences |
| (fix e400241) — equality-guarded MenuBarExtra binding | VinylPodApp.swift:32-42 | PASS — compare-before-assign `menuBarInserted` Binding present and wired into `MenuBarExtra(isInserted: menuBarInserted)` at line 48 |

### Required Artifacts

| Artifact | Expected | Status | Details |
| -------- | -------- | ------ | ------- |
| Landing commits on phase branch | 5 grouped 00-01 commits | ✓ VERIFIED | 4 executor feat commits + `bb5d282` external config commit + 3 fix commits; all SHAs resolve |
| `dist/VinylPod.app` | Rebuilt release from landed tree | ✓ VERIFIED | Binary + `VinylPod_VinylPod.bundle` present, mtime Jul 3 11:33 (built from fixed tree immediately before `e400241` was committed at 11:33:52 — legitimate fix→rebuild→profile→commit sequence) |
| 00-01-SUMMARY.md with CPU evidence | Recorded samples | ✓ VERIFIED | Raw 12-sample idle series (all 0.0), `sample` call-graph excerpt, playback series + DEFERRED rationale |
| 07-feature-inventory.md Appendix A | Seven-JSON consolidation | ✓ VERIFIED | Exact heading present; all seven subsections; hexes + dimensions preserved |
| docs/system-design/README.md canonical statement | Explicit, CONTRACTS.md kept authoritative | ✓ VERIFIED | Both greps ≥ 1 |
| PRD.md HISTORICAL banner | Replaces stale pre-code header | ✓ VERIFIED | Banner read directly; stale strings zero |
| Three docs(00-02) commits | `51f7cb8`, `212ad4a`, `a01bf3c` | ✓ VERIFIED | All exist; stats match claimed scope |
| .gitignore new entries + chore(00-03) commit | `.playwright-mcp/`, stitch-file (+ cache dir) | ✓ VERIFIED | `5dfea7f` = .gitignore alone, +5 lines; all patterns bind |
| CONCERNS.md five reconciled sections + docs(00-04) commit | RESOLVED markers + SHAs | ✓ VERIFIED | `81170ca` = CONCERNS.md alone; 5 markers; SHAs real |

### Key Link Verification

| From | To | Via | Status | Details |
| ---- | -- | --- | ------ | ------- |
| Untracked source dirs | Landing commits | Services.swift references their types | ✓ WIRED | 10 files tracked; verifier's `swift build` on committed content passes |
| CPU re-profile | Post-landing binary | Built AFTER all landing content | ✓ WIRED | Binary built from fixed working tree (11:33:17) then committed (`e400241`, 11:33:52); recorded profile is of the fixed code |
| JSON consolidation | `git rm` of the seven JSONs | Same atomic commit | ✓ WIRED | `51f7cb8` shows +142 appendix lines AND the seven removals together |
| claude.md/codex.md drift | Explicit disposition (never assumed) | Plan drift-gate STOP | ✓ WIRED | Execution STOPPED on populated reappearance; files relocated to ~/.claude/notes/ by orchestrator; absence re-verified now (disk + index) |
| gitignore first | Delete second | Ordering | ✓ WIRED | `5dfea7f` (ignore) precedes the .DS_Store purge; `.playwright-mcp/` binds despite directory absence |
| Map file inventories | Committed files | ls-files spot-check | ✓ WIRED | 10/10 tracked files match ARCHITECTURE.md component inventory |

### Data-Flow Trace (Level 4)

Not applicable — phase produces commits, docs, and repo hygiene, not dynamic-data-rendering artifacts. The one code-behavior artifact (perf invariants) is covered by the static re-verification table and the human check.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| -------- | ------- | ------ | ------ |
| Committed tree compiles | `swift build` | "Build complete! (1.05 sec)" | ✓ PASS |
| Clean tree | `git status --porcelain` | empty | ✓ PASS |
| All 14 claimed SHAs exist | `git cat-file -t` per SHA | all `commit` | ✓ PASS |
| Ignore patterns bind | `git check-ignore` ×4 | all bind | ✓ PASS |
| Idle/playback CPU ~0.0% | (not run — requires launching the app) | — | ? SKIP → human |

### Probe Execution

No `scripts/*/tests/probe-*.sh` exist and no plan declares probes — SKIPPED.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
| ----------- | ----------- | ----------- | ------ | -------- |
| FND-01 | 00-01 | WIP landed in grouped commits, re-verified against 6 invariants | ? NEEDS HUMAN (runtime CPU only) | Structural + static halves VERIFIED (truths 1-2, invariant table); runtime idle/playback CPU is the owed human check |
| FND-02 | 00-02 | docs/system-design canonical; stale/duplicate docs removed; JSONs consolidated | ✓ SATISFIED | Truth 4 evidence |
| FND-03 | 00-03 | .playwright-mcp gitignored; transients removed; root de-noised | ✓ SATISFIED | Truth 5 evidence |
| FND-04 | 00-04 | Codebase map refreshed to committed state | ✓ SATISFIED | Truth 6 evidence |

No orphaned requirements: REQUIREMENTS.md maps exactly FND-01..04 to Phase 0 and every ID is claimed by exactly one plan.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| ---- | ---- | ------- | -------- | ------ |
| (none) | — | — | — | Zero TBD/FIXME/XXX, zero TODO/HACK/PLACEHOLDER, zero stub-language hits across all 32 phase-modified source files |

Known scaffolds (declared, not hidden): NativeMediaRemoteCapture (OFF by default, Phase 3/4 scope), Last.fm scrobbling (Phase 4 wires it), SettingsWindow "INTEGRATION POINT" seam comment — all documented in 00-01-SUMMARY Known Stubs with phase ownership; none carries a debt marker.

### Warnings (non-blocking)

1. **CONCERNS.md "Test Coverage Gaps" derived-analysis drift** — claims no `*Tests.swift` exist while `Tests/VinylPodBackendTests/` has 4 tracked XCTest files. Correctly flagged in-doc (line 5 italic note) with a `/gsd-map-codebase` remap recommendation; Phase 1 planners directed to trust TESTING.md. Handled per plan discipline; surface to the developer as a pending remap decision, not a Phase 0 gap.
2. **ROADMAP.md Wave 4 checkbox** — `- [ ] 00-04` remains unchecked while "Plans: 4/4 plans complete" and all four plan checkboxes are `[x]`. Cosmetic metadata inconsistency; orchestrator should tick it when closing the phase.
3. **iCloud duplicate git ref files** (deferred-items.md #1) and **make_app.sh no-abort-on-build-failure** (#2) — logged out-of-scope discoveries, correctly deferred, not phase gaps.

### Human Verification Required

#### 1. Steady-playback (and idle) CPU on the real bridge path

**Test:** Launch `dist/VinylPod.app` with Activity Monitor open. Observe idle for ~1 minute. Then play music in a browser tab through the extension for ~1 minute with the widget visible.
**Expected:** Track appears in the widget; VinylPod reads ~0.0% CPU at idle AND during steady playback — no sustained high-CPU loop.
**Why human:** Runtime CPU behavior is unobservable via grep; the scripted local-file profile drives 10 Hz reportTick + two by-design 30fps animated surfaces (measured ~16.3%, no loop signature) and cannot approximate the extension's 1 Hz bridge ingestion. This is the plans' own end-of-phase `<human-check>` (00-01 Task 3 + 00-04 Task 2, deduplicated). If playback shows sustained high CPU, start from `EqualizerBars` `active` gating (DynamicIslandWidget.swift ~705).

### Gaps Summary

No gaps. Every structural, documentary, and hygiene must-have is verified directly against the codebase; all claimed commit SHAs are real and their contents match the claimed scope; the six perf invariants were independently re-verified statically by this verifier in the committed code (including the compare-before-assign fix for the genuine ~100%-CPU loop the executor caught). The single outstanding item is the runtime CPU confirmation on the real bridge path — a behavior-dependent truth the phase itself explicitly deferred to a human check, which must close before Phase 0 sign-off.

---

_Verified: 2026-07-03T21:30:00Z_
_Verifier: Claude (gsd-verifier)_
