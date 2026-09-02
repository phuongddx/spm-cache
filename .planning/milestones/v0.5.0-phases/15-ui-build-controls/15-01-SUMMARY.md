---
phase: 15-ui-build-controls
plan: 01
subsystem: api
tags: [spawn, pgroup, sse, tracer]

requires:
  - phase: 14-live-log-streaming-terminal-watch-relay
    provides: "SSE switch/auto-switch machinery; web server boot; marker; middleware"
provides:
  - "Web::Jobs — mutex-atomic single spawn slot, PROBED spawn shape (array argv, chdir, ENV + SPM_CACHE_TRIGGER, pgroup+detach), run_end-on-disk slot learning"
  - "POST /api/build {scope} behind the structural gate; shutdown-with-in-flight-build integration row (WEB-03 holds)"
affects: [15-04, 15-05, 16-package-toggles-panel-completion]

actuals:
  tokens: 34000
  tasks: 2
  commits: 3

key-decisions:
  - "Slot never waitpids — 'ended' derives from the child's own run_end on disk (CP14-honest); shutdown never touches the process group (P4/P5)"
  - "Fake-bin fixture drives spawn assertions hermetically; a one-time tailer warm-up connect + bounded wait helpers remove the boot races"
  - "Test ordering: 'POST /api/build' nested inside 'live log stream' after its WELD_RUN rows; final shutdown wrapped as the group's true last act"

requirements-completed: [BLD-01]

coverage:
  - id: D1
    description: "TRACER: one UI-triggered build end to end — POST → slot → detached pgroup CLI → run log → SSE → clean shutdown"
    requirement: BLD-01
    verification:
      - kind: integration
        ref: "spec/web_integration_spec.rb POST /api/build rows + shutdown-with-in-flight-build"
        status: pass
      - kind: unit
        ref: "spec/web_jobs_spec.rb spawn/slot/release matrix (9 examples)"
        status: pass
    human_judgment: false

duration: 45min
completed: 2026-09-02
status: complete
---

# Phase 15 / Plan 15-01: TRACER — one UI-triggered build end to end

**POST /api/build spawns the real CLI detached-in-its-own-pgroup; the run streams via the existing SSE machinery; server shutdown leaves it running and exits 0.**

## Task Commits
1. RED end-to-end rows + fake-bin fixture — `0c31738`
2. GREEN jobs.rb + route + lock snapshot — `8293545`
3. Web::Jobs unit matrix — `12a465a`

## Notes
- Rule-1 fixes en route: restored a dropped '/api/events' dispatch arm caught by the suite; fake-bin stdio probe File.stat→io.stat.rdev.
- Test-only hardening: positional body param (Ruby 3 kwarg separation), bounded wait helpers for child-process races, tailer warm-up, dry-run-verified ordering.

## Files
- lib/spm_cache/web/jobs.rb (new), router.rb, read_models/runs.rb, spec/fixtures/fake_spm_cache_bin.rb (new), spec/support/web_server_boot.rb, spec/web_integration_spec.rb, spec/web_jobs_spec.rb (new)
