# agents.md — Swarm operating rules (VinylPod ecosystem)
<!-- Last-verified: 2026-07-03 · Ground truth verified by building. WindowMode = 5 (small/normal/regular/large/desktopWidget), ⌘1–5. -->

Commander model: one orchestrator (main context) instantiates roles as needed;
roles are RESPONSIBILITY LANES, not necessarily separate processes. A lane is
spun into a real subagent only when its work is parallel-safe and context-heavy
(adversarial review, broad QA sweeps). Everything else executes in-lane to keep
one coherent architectural memory.

## Ground truth (do not re-derive; verify by building)
- Repo: `~/Projects/VinylPodMac` — SPM macOS app (target macOS 13) + Chrome/Safari
  extension in `BrowserExtension/`. `swift build` must stay **0 warnings**.
- Bridge: extension → loopback WebSocket `ws://127.0.0.1:8787` → `BrowserBridge`
  → `NowPlayingService` (@MainActor). Flood-guarded (see commit 630f629).
- Palette: `ArtworkColorExtractor.paletteOffMain` (nonisolated, CoreImage) →
  Sendable `AlbumColorPalette{dominant,vibrant,muted,shadow}` → liquid glass
  tint via `GlassTintStrength`.
- Visualizer: `MusicVisualizerContainerView` switching `VinylStyle`
  {vinyl,image,cassette,liquidDisc} — exhaustive switch, no `default`.

## Role lanes
 1. Lead Architect        — data-flow changes touching Bridge/NowPlayingService.
 2. AI Structure Designer — liquid-glass identity: palette → membrane math.
 3. Frontend Engineer     — widget bodies (Small/Regular/Large/Desktop).
 4. Animation Specialist  — VinylDiskView/tonearm/menu motion. 30fps TimelineView,
                            paused when idle. NEVER add a second render clock.
 5. Chrome Backend Scout  — MediaSession + DOM scraping (`BrowserExtension/`).
 6. Systems Window Spec.  — WindowManager levels/stacking; desktop widget rules.
 7. Shortcut Engine Arch. — Carbon hotkeys + ShortcutStore (UserDefaults JSON).
 8. QA Evaluator          — destructive tests: e2e/*.js (bridge flood, size
                            switching), `swift build` gate, contrast checks.
 9. Optimization & Memory Guard — context compaction: progress.txt is the
                            restart point; features JSONs are the task graph.
10. Documentation Scribe  — features JSONs (7 files, per-surface) + progress.txt.

## Hard invariants (Critic MUST reject violations)
- **Per-tick invariant**: no view/service may observe `NowPlayingService.$position`
  except the progress strip. Beat/pulse effects derive from `TimelineView` date,
  never from position subscriptions.
- **Isolation**: zero `nonisolated(unsafe)`, zero `@unchecked Sendable`. Cross-
  actor values must be Sendable value types (region isolation).
- **CLT toolchain**: `@VPState` instead of `@State` (macro plugin unavailable).
- **API floor**: macOS 13. No macOS-14-only API without availability guards.
- **Persistence**: enum rawValues stored in UserDefaults are append-only.
- **Windows**: desktop-widget stacking uses CGWindowLevelForKey, not magic ints.

## Generator-Critic loop
1. Generator implements a vertical slice (runnable end-to-end, not UI-only).
2. `swift build` gate: 0 warnings or the slice is rejected.
3. Critic pass (subagent or /code-review): correctness, invariants above,
   contrast ≥ WCAG-ish readability on glass, perf (no new render clocks).
4. QA destructive pass where applicable (e2e scripts).
5. Scribe updates features JSON + progress.txt. Only then move on.
