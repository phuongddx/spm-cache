---
phase: 15-ui-build-controls
plan: 04
subsystem: api
tags: [routes, mutation, 409, matrix]

requires:
  - phase: 15-ui-build-controls
    provides: "15-01 jobs+route; 15-02 rollback CLI; 15-03 --rebuild"
provides:
  - "Complete mutation surface: rebuild scope + POST /api/rollback on the shared slot; full route/auth/body/409/lock-snapshot/500 matrix"
affects: [15-05, 16-package-toggles-panel-completion]

actuals:
  tokens: 22000
  tasks: 2
  commits: 4

key-decisions:
  - "409 reason 'spawn slot busy' (A9: never a substring of display copy); malformed body/scope → 400; 2xx carries the lock snapshot"
  - "Spawn-failure row uses a NUL-byte bin path (machine-probed: the interpreter argv[0] raises ArgumentError) — real failure, no stubbing"
  - "Per-route scope whitelist hardened in review (CR-01, 12fdd51): /api/build accepts only {build,rebuild}"

requirements-completed: [BLD-01, BLD-02, BLD-04]

coverage:
  - id: D1
    description: "Mutation route matrix (POST-only, token, scope whitelist incl. cross-route, 409, lock snapshot, spawn failure)"
    requirement: BLD-01
    verification:
      - kind: unit
        ref: "spec/web_build_routes_spec.rb (21 examples incl. the CR-01 cross-route row)"
        status: pass
    human_judgment: false

duration: 19min
completed: 2026-09-02
status: complete
---

# Phase 15 / Plan 15-04: The mutation surface complete

**Both POST routes on the shared spawn slot with an exhaustive validation/rejection matrix; rollback spawns only (D-07 tested prohibition); CR-01's cross-route scope leak fixed in review.**

## Task Commits
1. RED rebuild scope + rollback route — `1ffdd8f`; GREEN — `2496420`
2. RED matrix — `a2470cf`; GREEN — `16fcd26`
3. Review fix CR-01 — `12fdd51` (with `165e88e` WR-01 companion)

## Files
- lib/spm_cache/web/jobs.rb, router.rb, spec/web_build_routes_spec.rb
