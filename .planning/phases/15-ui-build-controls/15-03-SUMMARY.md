---
phase: 15-ui-build-controls
plan: 03
subsystem: cli
tags: [rebuild, flag, readme]

requires:
  - phase: 15-ui-build-controls
    provides: "D-01 verb-level scope decision"
provides:
  - "--rebuild flag on Command::Build → Installer::Build includes the cachemap hit set (forced-rebuild scope); README CLI row"
affects: [15-04, 15-05]

actuals:
  tokens: 14000
  tasks: 2
  commits: 4

key-decisions:
  - "`missed.concat(@cachemap.hit) if @rebuild` lands after the incomplete-slice top-up and before narrowing/uniq — the uniq! collapses the overlap (no duplicate builds)"
  - "Flag mirrors --recursive's parse shape; argv-fidelity row pins the run-log header carrying the flag"

requirements-completed: [BLD-01]

coverage:
  - id: D1
    description: "Forced-rebuild selection + CLI surface"
    requirement: BLD-01
    verification:
      - kind: unit
        ref: "spec/command_build_rebuild_spec.rb (9 examples incl. no-duplication overlap fixture + argv fidelity)"
        status: pass
    human_judgment: false

duration: 8min
completed: 2026-09-02
status: complete
---

# Phase 15 / Plan 15-03: --rebuild on the build verb

**`spm-cache build --rebuild` widens the build set to every cached target; terminal surface + README row; the identity card's argv row is the user-visible proof.**

## Task Commits
1. RED forced-rebuild selection — `166b2ed`; GREEN — `df1a98c`
2. RED CLI surface — `4a80eb4`; GREEN — `c694ef2`

## Notes
- Fixture extended with an incomplete-slice hit so the no-duplication example exercises a real overlap (vacuous otherwise) — documented deviation.

## Files
- lib/spm_cache/installer/build.rb, lib/spm_cache/command/build.rb, spec/command_build_rebuild_spec.rb, README.md
