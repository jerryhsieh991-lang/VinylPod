---
status: testing
phase: 00-land-wip-reconcile
source: [00-VERIFICATION.md]
started: 2026-07-03T19:30:31Z
updated: 2026-07-03T19:30:31Z
---

## Current Test

number: 1
name: Steady-playback + idle CPU on the real bridge path
expected: |
  Launch dist/VinylPod.app, idle ~1 min, then play music in a browser tab via the
  extension ~1 min with the widget visible. Track shows in widget; Activity Monitor
  reads ~0.0% CPU at idle and during steady playback.
awaiting: user response

## Tests

### 1. Steady-playback + idle CPU on the real bridge path
expected: Launch `dist/VinylPod.app`, idle ~1 min, then play music in a browser tab via the extension ~1 min with the widget visible. Track shows in widget; Activity Monitor reads ~0.0% CPU at idle and during steady playback. If high, start debugging from `EqualizerBars` `active` gating (DynamicIslandWidget.swift ~705).
result: [pending]

## Summary

total: 1
passed: 0
issues: 0
pending: 1
skipped: 0
blocked: 0

## Gaps
