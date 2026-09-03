---
phase: 15-ui-build-controls
plan: 02
subsystem: cli
tags: [rollback, flock, trigger, run-log]

requires:
  - phase: 15-ui-build-controls
    provides: "15-01 spawn slot; D-03 marker contract"
provides:
  - "Rollback acquires the build lock before the sandbox rm_rf (BLD-04/CP4) with announce + ensure-release"
  - "SPM_CACHE_TRIGGER whitelist normalization → run_start trigger 'ui' (D-03)"
affects: [15-04, 15-05, 16-package-toggles-panel-completion]

actuals:
  tokens: 18000
  tasks: 2
  commits: 4

key-decisions:
  - "Lock wrapper mirrors installer/build.rb's probe→announce→block shape with release-on-raise; free-path byte-identical (regression pin)"
  - "Marker normalization is a whitelist: 'ui' passes through, anything else → 'terminal' — never passthrough; argv stays clean (env, not flag)"

requirements-completed: [BLD-04]

coverage:
  - id: D1
    description: "Rollback lock acquisition (ordering + contention announce + release-on-raise)"
    requirement: BLD-04
    verification:
      - kind: unit
        ref: "spec/installer_rollback_lock_spec.rb (6 examples; ordering + File.exist? release-on-raise)"
        status: pass
    human_judgment: false
  - id: D2
    description: "UI-run attribution — trigger 'ui' in the run_start header"
    requirement: BLD-01
    verification:
      - kind: unit
        ref: "spec/run_log_trigger_spec.rb (5 examples: marker present/absent/foreign + no-behavior-change + vocabulary closure)"
        status: pass
    human_judgment: false

duration: 9min
completed: 2026-09-02
status: complete
---

# Phase 15 / Plan 15-02: CLI-side truth — rollback lock + trigger 'ui'

**Rollback now holds the build lock around the sandbox removal; UI-spawned runs record trigger 'ui' via a whitelisted env marker.**

## Task Commits
1. RED rollback lock — `e989291`; GREEN — `1cde68e`
2. RED trigger marker — `8f96d5f`; GREEN — `83975bf`

## Notes
- Fixture self-fix (SANDBOX_DIR path) caught pre-commit; regression-pin conventions matched the sibling D-05 spec.

## Files
- lib/spm_cache/installer/rollback.rb, lib/spm_cache/main.rb, spec/installer_rollback_lock_spec.rb, spec/run_log_trigger_spec.rb
