---
phase: 00-land-wip-reconcile
plan: 02
subsystem: docs
tags: [documentation, consolidation, canonical-spec, fnd-02]
requires:
  - phase: 00-land-wip-reconcile
    plan: 01
    provides: "All WIP source landed through d9e5e32"
provides:
  - "docs/system-design/ declared the single canonical product + architecture spec"
  - "07-feature-inventory.md Appendix A preserving all seven root feature-JSON digests"
  - "PRD.md marked HISTORICAL (no doc claims the app is unbuilt)"
  - "docs/settings-audit.md and docs/asset-catalog-migration.md tracked"
  - "README.md deletion landed (superseded by docs/system-design/05)"
affects: [00-03, 00-04, all-future-planners]
tech-stack:
  added: []
  patterns: ["consolidate-before-delete: durable content folded into canonical doc before git rm"]
key-files:
  created:
    - docs/settings-audit.md
    - docs/asset-catalog-migration.md
  modified:
    - docs/system-design/07-feature-inventory.md
    - docs/system-design/README.md
    - PRD.md
  deleted:
    - widget_features.json
    - small_widget_features.json
    - regular_widget_features.json
    - large_widget_features.json
    - desktop_widget_features.json
    - settings_features.json
    - ui_comparative_features.json
    - README.md
decisions:
  - "Reappeared claude.md/codex.md (NotebookLM exports) dispositioned by lossless relocation to ~/.claude/notes/, not commit or delete"
  - "design_system.md (no space) stays as historical; only the ' 2' duplicate was mandated gone"
metrics:
  duration: "~25 min (incl. checkpoint pause)"
  completed: "2026-07-03"
status: complete
---

# Phase 00 Plan 02: Docs Canonical & Feature-JSON Consolidation Summary

**One-liner:** docs/system-design/ declared single canonical spec; seven root feature JSONs digested into 07-feature-inventory Appendix A then git-rm'd; PRD marked HISTORICAL; docs audits landed and superseded README removed.

## Commits

| Task | Commit | Subject |
|------|--------|---------|
| 1 | `51f7cb8` | docs(00-02): consolidate root feature JSONs into 07-feature-inventory appendix |
| 2 | `212ad4a` | docs(00-02): designate docs/system-design canonical; mark PRD historical |
| 3 | `a01bf3c` | docs(00-02): land docs audits and remove superseded README |

All on branch `gsd/phase-00-land-wip-reconcile`.

## What was done

- **Task 1:** Appended `## Appendix A — Historical build-spec digests (consolidated from root *_features.json, 2026-07-03)` to `docs/system-design/07-feature-inventory.md` with one subsection per JSON, preserving target dimensions (162x162 small, 344x132 medium, 300 x 360 regular, 320 x 432 large, desktop full-screen), accent hexes (#C592AB, #D18FB8, #BD6BAD), layout geometry, the `hotkeyScope: global (Carbon RegisterEventHotKey, no Accessibility permission)` decision, node→file mappings, and done-flag summaries. Only after the appendix was committed-ready were the seven JSONs removed via `git rm` (history preserves originals). `BrowserExtension/extension_backend_features.json` untouched.
- **Task 2:** PRD.md's stale header ("DRAFT — awaiting founder sign-off" / "no application code written yet") replaced with a HISTORICAL banner pointing to `docs/system-design/` (canonical) and `.planning/` (requirements/roadmap); body preserved. `docs/system-design/README.md` gained a canonical-spec notice that keeps `CONTRACTS.md` authoritative for frozen API names and labels root `PRD.md`/`design_system.md` historical.
- **Task 3:** claude.md/codex.md absence asserted (see reconciliation below); `docs/settings-audit.md` + `docs/asset-catalog-migration.md` landed as tracked docs; the WIP `README.md` deletion committed (content in history; toolchain notes superseded by `docs/system-design/05-security-performance-build.md`). `VinylPod-Complete-Documentation.md` deliberately NOT added (plan 00-03 gitignores it).

## Working-tree reconciliation (FND-02 stray-file resolution)

- **`design_system 2.md`:** verified gone from disk and index — removed pre-phase in commit `e79c990` ("chore: remove duplicate design doc and transient playwright logs"). Verify-only gate passed; no fallback removal needed. Root `design_system.md` (22 KB) retained and labeled historical via the README canonical notice.
- **`claude.md` / `codex.md`:** the 2026-07-03 replan had verified both absent everywhere, but they REAPPEARED at repo root at execution time (untracked, populated: 1,053 / 1,088 bytes, created 2026-07-03 11:36 — Chinese-language NotebookLM-style agent-instruction exports with citation markers). Per the plan's drift gate, execution STOPPED at Task 3 for explicit disposition (T-00-05: no commit of unreviewed content, no deletion of a potential only-copy). **Disposition (option 2, by the orchestrator/user):** both files losslessly relocated out of the repo to `~/.claude/notes/vinylpod-notebooklm-claude-instructions.md` and `~/.claude/notes/vinylpod-notebooklm-codex-agents.md` (byte-for-byte, original mtimes). Absence gate then re-asserted and passed; the stray-file half of FND-02 is closed by absence.

## Deviations from Plan

### Checkpoint drift stop (plan-mandated, not a rule violation)

**1. [Drift gate] claude.md/codex.md reappeared populated at execution time**
- **Found during:** Pre-execution status check; gate enforced at Task 3
- **Issue:** Plan's absence assumption was stale — new NotebookLM exports materialized at repo root the morning of execution
- **Fix:** STOP per plan's explicit drift handling; orchestrator relocated both files to `~/.claude/notes/`; Task 3 resumed after absence gate passed
- **Files modified:** none in-repo (relocation happened outside the repo)
- **Commit:** n/a (deliberately nothing committed or deleted in-repo)

No other deviations — Tasks 1 and 2 executed exactly as written.

## Residual working-tree state (for plan 00-03's clean-tree gate)

`git status --porcelain` after Task 3 lists:
- `?? VinylPod-Complete-Documentation.md` — expected; dispositioned by plan 00-03
- `?? .planning/research/.cache/*.json` (6 files) — orchestrator research cache, declared out of scope for this plan; **surfaced here as drift** since the plan's acceptance criteria expected only the Complete-Documentation line. 00-03's clean-tree gate should account for (gitignore or otherwise disposition) these cache files.

## Verification

- `git log --oneline -3` shows the three `docs(00-02)` subjects (`a01bf3c`, `212ad4a`, `51f7cb8`)
- Root has no `*_features.json` (only `BrowserExtension/extension_backend_features.json` tracked), no `design_system 2.md`, no `claude.md`/`codex.md`, no `README.md`
- PRD.md carries the HISTORICAL banner; no "no application code written yet" / "awaiting founder sign-off" strings remain
- `docs/system-design/README.md` contains the canonical statement and retains `CONTRACTS.md` authority
- Appendix A greps confirm `162`, `300 x 360`, `320 x 432`, `#C592AB`, `#D18FB8`, `#BD6BAD` and all seven original filenames

## Known Stubs

None — documentation-only plan; no code paths touched.

## Self-Check: PASSED

- FOUND: docs/settings-audit.md (tracked)
- FOUND: docs/asset-catalog-migration.md (tracked)
- FOUND: Appendix A in docs/system-design/07-feature-inventory.md
- FOUND: commits 51f7cb8, 212ad4a, a01bf3c on gsd/phase-00-land-wip-reconcile
- CONFIRMED ABSENT: README.md, claude.md, codex.md, design_system 2.md, seven root *_features.json
