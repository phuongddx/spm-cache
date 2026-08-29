---
phase: 09-cache-identity-invalidation
plan: 02
subsystem: cache
tags: [ruby, cache-invalidation, spm, cli]

requires:
  - phase: 09-cache-identity-invalidation
    plan: 01
    provides: "BinariesCache.hit(module:identity:currentPin:) provenance-aware decision and report_fidelity's not-graph-pinned sidecar write (Swift-side identity check this plan's version-stamp gate feeds into for the default workflow)"
provides:
  - "Installer::Use#fast_path? -- gained a fourth guard: the on-disk lockfile's spm_cache_version stamp must equal SPMCache::VERSION"
  - "Installer::Use#current_spm_cache_version? -- new private method, throwaway Core::Lockfile read, no @lockfile ivar mutation"
  - "Command::Cache::Clean#sweep_orphaned_sidecars -- new orphan sidecar sweep, runs unconditionally after the existing --all/target removal branch"
affects: [10-fidelity-regression-coverage]

actuals:
  tokens: 2800
  tasks: 2
  commits: 2

tech-stack:
  added: []
  patterns:
    - "Version-stamp gate via a throwaway Core::Lockfile read (never populates @lockfile) -- mirrors enrich_lockfile_products/invalidate_stale_products!'s existing products[] staleness pattern, applied here to fast_path? eligibility instead"
    - "Suffix-stripped basename sidecar matching (cache clean's new sweep) -- same convention already used by copy_prebuilt_binary_target's write-time cleanup, now also applied at clean-time"

key-files:
  created:
    - spec/command_cache_clean_spec.rb
  modified:
    - lib/spm_cache/installer/use.rb
    - spec/installer_use_fast_path_spec.rb
    - lib/spm_cache/command/cache/clean.rb

key-decisions:
  - "sweep_orphaned_sidecars runs AFTER the existing if @all / elsif @targets.any? / else branch, not before -- a named-target cache clean <target> invocation's own now-orphaned sidecar (remove_path only rm_rf's the .xcframework path, leaving sidecars behind) is caught in the SAME invocation instead of requiring a second run. For --all, cache_dir is already deleted by the time the sweep runs, so Dir.glob on the missing directory returns [] -- a harmless no-op, not an error."
  - "current_spm_cache_version? reads a throwaway Core::Lockfile.new(@config.lockfile_path) instance, never assigned to @lockfile -- avoids changing what integrate_proxy_into_project's plugin_only_lockfile_urls sees on the fast path (it reads @lockfile&.projects&.each_value and silently no-ops when @lockfile is nil)"

requirements-completed: [CACHE-02, CACHE-03]

coverage:
  - id: D1
    description: "spm-cache use's fast path is not taken when the lockfile's recorded spm_cache_version does not match the running gem version, even with an unchanged host graph -- sync_lockfile/prepare_proxy run instead"
    requirement: "CACHE-02"
    verification:
      - kind: unit
        ref: "spec/installer_use_fast_path_spec.rb#regenerates (does not take the fast path) when the lockfile spm_cache_version stamp does not match the running gem version, even with an unchanged host graph"
        status: pass
    human_judgment: false
  - id: D2
    description: "spm-cache use's fast path IS still taken when the stamp matches and the host graph is unchanged -- no regression to the pre-existing fast-path optimization"
    requirement: "CACHE-02"
    verification:
      - kind: unit
        ref: "spec/installer_use_fast_path_spec.rb#still takes the fast path when the lockfile spm_cache_version stamp matches the running gem version and the host graph is unchanged"
        status: pass
    human_judgment: false
  - id: D3
    description: "cache clean removes every orphaned .provenance.json/.shims.json sidecar (no matching .xcframework), in bare, --all, and named-target invocation shapes, across both debug and release cache dirs, and never touches a paired sidecar"
    requirement: "CACHE-03"
    verification:
      - kind: unit
        ref: "spec/command_cache_clean_spec.rb (6 examples: orphan removal x2 suffixes, paired survival, --dry reporting, named-target same-invocation sweep, both configs)"
        status: pass
    human_judgment: false

duration: ~20min
completed: 2026-08-29
status: complete
---

# Phase 09 Plan 02: Cache Identity & Invalidation -- Fast-Path Version Gate & Orphan Sidecar Sweep Summary

**Closed the one gap that would let CACHE-02's provenance fix silently miss the default `spm-cache`/`spm-cache use` workflow (fast path now re-checks provenance after an upgrade), and implemented CACHE-03's `cache clean` orphan-sidecar sweep so a `.provenance.json`/`.shims.json` sidecar never outlives the `.xcframework` it describes.**

## Performance

- **Duration:** ~20 min
- **Completed:** 2026-08-29
- **Tasks:** 2 / 2
- **Files modified:** 4 (1 created, 3 modified)

## Accomplishments

- `Installer::Use#fast_path?` gained a fourth guard: `current_spm_cache_version?` reads the
  on-disk lockfile's per-project `spm_cache_version` stamp via a throwaway `Core::Lockfile`
  instance (never assigned to `@lockfile`) and requires it to equal `SPMCache::VERSION`. This
  closes RESEARCH.md Pitfall 2 -- a bare `spm-cache`/`spm-cache use` run immediately after
  upgrading, with the host graph otherwise unchanged, now forces one full `gen-proxy` run
  (through `sync_lockfile`/`prepare_proxy`) instead of silently reusing a proxy built by the
  prior spm-cache version. `spm-cache build` was already unaffected (no fast-path short-circuit
  exists on that path); this closes the gap for the README-documented default command.
- `spec/installer_use_fast_path_spec.rb`'s shared `write_lockfile` helper gained an optional
  `version:` keyword (defaults to `SPMCache::VERSION`) so all 4 pre-existing tests kept passing
  unchanged, plus two new examples: a mismatched stamp forces `sync_lockfile`/`prepare_proxy` to
  run even with an empty diff, and a matching stamp still takes the fast path (regression guard).
- `Command::Cache::Clean#sweep_orphaned_sidecars`: new private method, glob-matches
  `*.{provenance,shims}.json` in a cache dir, strips the `.xcframework.(provenance|shims).json`
  suffix to find the candidate module name, and removes the sidecar (or reports it under `--dry`)
  only when no matching `.xcframework` directory exists. Wired into `run`'s existing
  `["debug", "release"].each` loop, called AFTER the existing `if @all / elsif @targets.any? /
  else` branch so a named-target removal's own newly-orphaned sidecar is swept in the same
  invocation.
- `spec/command_cache_clean_spec.rb`: new file, 6 examples covering both sidecar suffixes,
  paired-sidecar survival (D-10), `--dry` reporting without deletion, the named-target
  same-invocation sweep, and coverage across both debug and release cache dirs.

## Task Commits

Each task was committed atomically:

1. **Task 1: `spm-cache use`'s fast path forces a full run after a version bump** - `b79a8af` (feat)
2. **Task 2: `cache clean` sweeps orphaned provenance/shim sidecars (CACHE-03)** - `d68f192` (feat)

_Note: Task 1 was `type="tracer" tdd="true"` and Task 2 was `type="auto" tdd="true"` -- both
implemented and verified in one commit each against the full new test matrix, no separate
RED/GREEN split, matching 09-01's precedent (this plan's frontmatter `type` is `execute`, not a
plan-level `type: tdd` phase, so the strict RED/GREEN gate does not apply)._

## Files Created/Modified

- `lib/spm_cache/installer/use.rb` - `fast_path?` gained a 4th guard; new private
  `current_spm_cache_version?` method
- `spec/installer_use_fast_path_spec.rb` - `write_lockfile` helper gained `version:` kwarg; 2 new
  examples added to the existing describe block
- `lib/spm_cache/command/cache/clean.rb` - new `sweep_orphaned_sidecars` private method, called
  unconditionally at the end of the per-config loop in `run`
- `spec/command_cache_clean_spec.rb` - new file, 6 examples

## Decisions Made

None beyond what RESEARCH.md/09-CONTEXT.md/the plan's own `<context>` already specified --
implementation followed the plan's recommended code shape verbatim (verified against the actual
source read at execution start, matching what the plan's `<action>` blocks described).

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- CACHE-02 is now fully shipped end-to-end: the Swift-side provenance-aware `hit()` (09-01) is
  reachable via BOTH `spm-cache build` (always) and the default `spm-cache`/`spm-cache use`
  (now, via the version-stamp gate) -- no remaining path silently serves a stale pre-Phase-9
  proxy after an upgrade.
- CACHE-03 is fully shipped: `cache clean` never leaves an orphaned sidecar behind, in any
  invocation shape, and never touches a paired sidecar.
- Phase 9 (both plans) complete. Full Ruby suite: `bundle exec rspec` -- 382 examples, 0 failures
  (was 374 after 09-01; +8 from this plan: +2 net in `installer_use_fast_path_spec.rb`, +6 new in
  `command_cache_clean_spec.rb`). No Swift changes in this plan (Swift suite unaffected, still 34
  tests / 0 failures from 09-01).
- No blockers for Phase 10 (Fidelity Regression Coverage).

## Self-Check: PASSED

All created/modified files verified present on disk; both commit hashes (`b79a8af`, `d68f192`)
verified present in `git log --oneline --all`.

---
*Phase: 09-cache-identity-invalidation*
*Completed: 2026-08-29*
