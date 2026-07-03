# Project State: VinylPod

## Project Reference

See: `.planning/PROJECT.md` (updated 2026-07-03)

**Core value:** Show what's playing — beautifully, calmly, reliably — for *browser* playback every competitor misses, without depending on Apple's private, restricted `MediaRemote` hook.
**Current focus:** Phase 0 — Land WIP & Reconcile (not started)

## Milestone

**Milestone:** Full re-plan → Mac App Store (BLEND UI + PURSUE MAC APP STORE)
**Roadmap:** `.planning/ROADMAP.md` — 7 phases (0–6), 28 plans, 39 v1 requirements
**Critical path:** Phase 0 → 2 → 3 → 4 → 6, with Phase 1 and Phase 5 branching off Phase 0 in parallel (Phase 5 gated on Phase 1 perf guards).

## Phase Status

| Phase | Name | Status | Plans | Research? |
|-------|------|--------|-------|-----------|
| 0 | Land WIP & Reconcile | ○ Pending | 4 | skip |
| 1 | Test Foundation | ○ Pending | 4 | skip |
| 2 | Sandbox/Loopback + Signing Spike | ○ Pending | 2 | ⚠ warranted (`--research-phase`) |
| 3 | MAS Scaffold + Private-Framework Removal | ○ Pending | 5 | ⚠ warranted (`--research-phase`) |
| 4 | Phase 2 Capture (Precedence → Scrobbling) | ○ Pending | 5 | skip |
| 5 | UI Blend | ○ Pending | 4 | skip (design pass; UI hint: yes) |
| 6 | Store Submission | ○ Pending | 4 | ⚠ warranted (`--research-phase`) |

Progress: ░░░░░░░░░░ 0% (0/7 phases)

## Next Action

Plan Phase 0: `/gsd-plan-phase 0`

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

---
*Last updated: 2026-07-03 after initialization*
