---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: unknown
stopped_at: Completed 00-03-PLAN.md (SUMMARY written, FND-03 marked complete)
last_updated: "2026-07-03T18:56:21.819Z"
progress:
  total_phases: 7
  completed_phases: 0
  total_plans: 4
  completed_plans: 3
  percent: 0
---

# Project State: VinylPod

## Project Reference

See: `.planning/PROJECT.md` (updated 2026-07-03)

**Core value:** Show what's playing — beautifully, calmly, reliably — for *browser* playback every competitor misses, without depending on Apple's private, restricted `MediaRemote` hook.
**Current focus:** Phase 00 — land-wip-reconcile

## Milestone

**Milestone:** Full re-plan → Mac App Store (BLEND UI + PURSUE MAC APP STORE)
**Roadmap:** `.planning/ROADMAP.md` — 7 phases (0–6), 28 plans, 39 v1 requirements
**Critical path:** Phase 0 → 2 → 3 → 4 → 6, with Phase 1 and Phase 5 branching off Phase 0 in parallel (Phase 5 gated on Phase 1 perf guards).

## Phase Status

| Phase | Name | Status | Plans | Research? |
|-------|------|--------|-------|-----------|
| 0 | Land WIP & Reconcile | ◐ In Progress (3/4 plans) | 4 | skip |
| 1 | Test Foundation | ○ Pending | 4 | skip |
| 2 | Sandbox/Loopback + Signing Spike | ○ Pending | 2 | ⚠ warranted (`--research-phase`) |
| 3 | MAS Scaffold + Private-Framework Removal | ○ Pending | 5 | ⚠ warranted (`--research-phase`) |
| 4 | Phase 2 Capture (Precedence → Scrobbling) | ○ Pending | 5 | skip |
| 5 | UI Blend | ○ Pending | 4 | skip (design pass; UI hint: yes) |
| 6 | Store Submission | ○ Pending | 4 | ⚠ warranted (`--research-phase`) |

Progress: ░░░░░░░░░░ 0% (0/7 phases)

## Next Action

Execute plan 00-04 (map refresh / phase gate): `/gsd-execute-phase 0` continues

## Session

**Last session:** 2026-07-03T18:56:21.810Z
**Stopped at:** Completed 00-03-PLAN.md (SUMMARY written, FND-03 marked complete)
**Resume file:** None

## Key Context (carry into planning)

- **Brownfield, working app** (~9,300 LOC Swift + MV3 extension). All work is additive over a frozen architecture; route through the single `updateFromExternal` seam. Preserve `CONTRACTS.md` and the 6 perf invariants.
- **Phase 0 is a hard prerequisite** — ~19 uncommitted WIP files on branch `claude/security-crash-fixes` (perf/security-critical) must be landed and re-verified before anything builds on them.
- **#1 risk resolved FEASIBLE:** sandboxed loopback WebSocket server works with `network.server` + `network.client` entitlements. Phase 2 is a cheap spike to prove it on a real signed build before the Xcode migration.
- **Load-bearing gates:** compile-exclude private `MediaRemote` (Phase 3, symbol-grep gate); ≈0.0% idle-CPU re-profile on any ingestion/UI change (Phases 0/4/5); Safari uses native messaging, not `ws://localhost` (Phase 3/4).
- **Toolchain shift:** install Xcode 26; refactor into `VinylPodKit` library + thin `.xcodeproj` app target; keep `Package.swift` + `make_app.sh` dev loop intact.

## Recent Activity

- 2026-07-03 — Codebase mapped (`.planning/codebase/`, commit `281e675`)
- 2026-07-03 — PROJECT.md initialized (`8ff20bb`); config set YOLO/Standard/Adaptive (`9d310ea`)
- 2026-07-03 — Deep research: STACK/FEATURES/ARCHITECTURE/PITFALLS + SUMMARY (`b65b2f8`)
- 2026-07-03 — REQUIREMENTS.md defined, 39 v1 (`2159c78`)
- 2026-07-03 — ROADMAP.md created, 7 phases / 28 plans, traceability finalized (`211a841`)
- 2026-07-03 — 00-01 executed: WIP landed as grouped commits (`fb8ab0a`..`7338518` + external `bb5d282`), 3 deviation fixes (`37a5aa9`, `59342d5`, `e400241` — killed a ~100% idle-CPU MenuBarExtra loop), idle CPU re-profiled 0.00%, FND-01 complete
- 2026-07-03 — 00-02 executed: docs canonicalized (`51f7cb8`, `212ad4a`, `a01bf3c`) — feature JSONs consolidated into 07-inventory Appendix A, PRD marked HISTORICAL, docs audits landed, README removed; reappeared claude.md/codex.md (NotebookLM exports) relocated to ~/.claude/notes/ via checkpoint disposition; FND-02 complete
- 2026-07-03 — 00-03 executed: repo root de-noised (`5dfea7f`) — .playwright-mcp/, VinylPod-Complete-Documentation.md, and .planning/research/.cache/ gitignored; 4 stray .DS_Store purged; first fully-clean `git status --porcelain` of the phase; FND-03 complete

---
*Last updated: 2026-07-03 after initialization*

## Performance Metrics

| Phase | Plan | Duration | Notes |
|-------|------|----------|-------|
| Phase 00 P01 | 35m | 3 tasks | 35 files |
| Phase 00 P02 | 25m | 3 tasks | 12 files |
| Phase 00 P03 | 4min | 2 tasks | 5 files |

## Decisions

- [Phase ?]: MenuBarExtra(isInserted:) must use compare-before-assign Binding — raw @Published binding self-sustains a ~100%-CPU render loop
- [Phase ?]: .build lives outside iCloud via symlink to ~/Library/Caches/VinylPodMac.build — iCloud xattrs break codesign and swiftbuild db
- [Phase ?]: make_app.sh must bundle VinylPod_VinylPod.bundle — Bundle.module fatals at launch without it
- [Phase 00]: docs/system-design/ is the single canonical spec; PRD.md and design_system.md are historical; CONTRACTS.md stays authoritative for frozen API names
- [Phase 00]: Reappeared root claude.md/codex.md (NotebookLM exports) relocated to ~/.claude/notes/ rather than committed or deleted (T-00-05 disposition)
- [Phase 00]: .planning/research/.cache/ gitignored (regenerable research cache, not committed); VinylPod-Complete-Documentation.md ignored in place, never deleted
