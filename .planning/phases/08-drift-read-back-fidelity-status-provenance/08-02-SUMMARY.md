---
phase: 08-drift-read-back-fidelity-status-provenance
plan: 02
subsystem: cache
tags: [ruby, cli, provenance, fidelity-status]

requires:
  - phase: 08-drift-read-back-fidelity-status-provenance
    provides: "08-01's <name>.xcframework.provenance.json sidecar schema ({fidelity_status, pins, spm_cache_version, config, destinations}), written sibling to every cached xcframework"
provides:
  - "Command::Cache::List#run rebuilt around *.xcframework entries specifically, with a private fidelity_status_for(sidecar_path) reading the provenance sidecar's fidelity_status field"
  - "Fix for the pre-existing bug where a .shims.json/.provenance.json sidecar printed as its own spurious package line in cache list output"
affects: ["Phase 9 cache identity/invalidation (may reuse the *.xcframework-only glob convention this plan establishes)"]

actuals:
  tokens: 1500
  tasks: 2
  commits: 2

tech-stack:
  added: []
  patterns:
    - "cache list iterates Dir.glob(cache_dir, '*.xcframework').sort exclusively, never raw Dir.entries -- sidecar files (.shims.json, .provenance.json) can never surface as their own listed entry"
    - "fidelity_status_for's tolerant fallback (missing file, malformed JSON, missing key -> not-graph-pinned) mirrors 08-01's own defensive JSON.parse discipline rather than inventing a stricter contract"

key-files:
  created:
    - spec/command_cache_list_spec.rb
  modified:
    - lib/spm_cache/command/cache/list.rb

key-decisions:
  - "One RED spec file covering both Task 1's single-package happy path and Task 2's fallback/malformed/multi-config/empty-cache edge cases, rather than two separate spec-writing passes -- all edge cases exercise the same single fidelity_status_for method, so splitting the RED commit in two would have meant writing (and immediately invalidating) an incomplete first assertion set"
  - "Test invocation uses SPMCache::Command.parse([\"cache\", \"list\"]) rather than Command::Cache::List.new([]).run -- CLAide::Command#initialize calls argv.option(...)/argv.flag?(...), which a raw Array doesn't support; Command.parse is the same construction spec/doctor_spec.rb already establishes for CLAide-based command specs"
  - "Task 2 required zero production code changes -- all 6 of its new assertions (no-sidecar fallback, malformed-JSON rescue, missing-key fallback, multi-config sort, sidecar-not-listed, empty-cache header) passed immediately against Task 1's fidelity_status_for/Dir.glob rewrite, exactly as the plan itself predicted (\"Only change list.rb if one of the new assertions actually fails\")"

patterns-established:
  - "Dir.glob(cache_dir, '*.xcframework').sort as the canonical per-module enumeration for cache-scoped commands, superseding the old Dir.entries(cache_dir).sort walk"

requirements-completed: [DIAG-02]

coverage:
  - id: D1
    description: "cache list prints each cached package's fidelity status (host-pinned / resolution-incompatible / not-graph-pinned), read from its .provenance.json sidecar, without needing to inspect the sidecar by hand"
    requirement: DIAG-02
    verification:
      - kind: unit
        ref: "spec/command_cache_list_spec.rb#prints a cached package's fidelity status read from its provenance sidecar"
        status: pass
      - kind: unit
        ref: "spec/command_cache_list_spec.rb#lists multiple cached modules across both debug and release configs, sorted alphabetically per config"
        status: pass
    human_judgment: false
  - id: D2
    description: "A package with no recorded provenance (no sidecar, malformed sidecar, or a sidecar missing the fidelity_status key) is reported not-graph-pinned, never silently omitted or crashed on"
    requirement: DIAG-02
    verification:
      - kind: unit
        ref: "spec/command_cache_list_spec.rb#reports not-graph-pinned for a cached package with no sidecar at all"
        status: pass
      - kind: unit
        ref: "spec/command_cache_list_spec.rb#reports not-graph-pinned for a malformed (truncated) sidecar without raising"
        status: pass
      - kind: unit
        ref: "spec/command_cache_list_spec.rb#reports not-graph-pinned when the sidecar is valid JSON but missing fidelity_status"
        status: pass
    human_judgment: false
  - id: D3
    description: "The sidecar files themselves (.provenance.json, .shims.json) never appear in cache list's output as if they were their own cached package -- the pre-existing spurious-entry bug is fixed"
    requirement: DIAG-02
    verification:
      - kind: unit
        ref: "spec/command_cache_list_spec.rb#never prints a sidecar file as its own spurious package entry"
        status: pass
    human_judgment: false
  - id: D4
    description: "The pre-existing header-always (empty cache_dir still prints the config header) and alphabetical-sort-within-config behaviors are preserved by the rewrite"
    requirement: DIAG-02
    verification:
      - kind: unit
        ref: "spec/command_cache_list_spec.rb#still prints the config header with no rows when a cache_dir has zero cached xcframeworks"
        status: pass
    human_judgment: false

duration: ~15min
completed: 2026-08-29
status: complete
---

# Phase 08 Plan 02: Drift Read-Back, Fidelity Status & Provenance -- Cache List Summary

**`spm-cache cache list` now names each cached package's fidelity status (`host-pinned` / `resolution-incompatible` / `not-graph-pinned`) read from its `.provenance.json` sidecar, fixing the pre-existing bug where sidecar files printed as their own spurious package entries.**

## Performance

- **Duration:** ~15 min
- **Tasks:** 2
- **Files modified:** 2 (1 new spec file, 1 rewritten command)
- **Commits:** 2

## Accomplishments
- `Command::Cache::List#run` rebuilt to iterate `Dir.glob(cache_dir, "*.xcframework").sort` instead of the old bare `Dir.entries(cache_dir).sort` walk, closing the pre-existing bug where a `.shims.json`/`.provenance.json` sidecar printed as its own spurious "package" line
- New private `fidelity_status_for(sidecar_path)` reads the sidecar's `fidelity_status` field, tolerantly falling back to `not-graph-pinned` when the sidecar is absent, malformed JSON, or valid JSON missing the key -- never raises, never prints `nil`
- Pre-existing `["debug", "release"].each { puts "\n#{cfg.capitalize}:" }` header-always structure and alphabetical sort preserved unchanged
- `spec/command_cache_list_spec.rb` created (no test existed for this command before) -- 10 examples covering the single-package happy path, three fallback shapes, sidecar-not-listed, multi-config sort, and empty-cache header preservation

## Task Commits

1. **Task 1: End-to-end -- cache list shows fidelity status for one cached package**
   - `57e07ea` (test) - failing spec, 10 examples covering both Task 1's happy path and Task 2's full edge-case set (see Decisions Made)
   - `9f0d5a4` (feat) - `Dir.glob`-based rewrite + `fidelity_status_for`; all 10 examples pass, no further changes needed for Task 2

2. **Task 2: fallback / malformed / multi-config / empty-cache coverage**
   - No separate commit -- Task 2's 6 assertions were already written into `57e07ea`'s spec file and already passed against `9f0d5a4`'s implementation with zero additional production-code changes, exactly as the plan's own action text predicted. See Deviations below.

**Plan metadata:** commit for this SUMMARY.md is separate, per the plan's instruction to leave STATE.md/ROADMAP.md to the orchestrator.

## Files Created/Modified
- `lib/spm_cache/command/cache/list.rb` - rewritten `#run` (glob-based iteration) + new private `fidelity_status_for`
- `spec/command_cache_list_spec.rb` - new file, 10 examples covering DIAG-02's `cache list` half

## Decisions Made
- One RED spec file covering both tasks' behaviors in a single pass, rather than writing Task 1's single assertion first and returning to add Task 2's five more later -- all edge cases exercise the same `fidelity_status_for` method and `Dir.glob` loop, so there was no natural seam to split the RED commit across two separate spec-authoring passes without artificially truncating the first
- Test invocation uses `SPMCache::Command.parse(["cache", "list"])` rather than the plan's suggested `Command::Cache::List.new([]).run` -- `CLAide::Command#initialize` calls `argv.option(...)`/`argv.flag?(...)`, which a raw `Array` doesn't support (confirmed via a `NoMethodError` on the first RED run); `Command.parse` is the same construction `spec/doctor_spec.rb` already establishes for CLAide-based command specs, so no new test convention was introduced

## Deviations from Plan

**1. [Rule 3 - Blocking] `Command::Cache::List.new([])` doesn't work -- switched to `Command.parse`**
- **Found during:** Task 1, first RED run
- **Issue:** The plan's literal test invocation (`Command::Cache::List.new([]).run`) raised `NoMethodError: undefined method 'option' for []:Array` -- `CLAide::Command#initialize` requires a `CLAide::ARGV`-like object, not a raw Array
- **Fix:** Used `SPMCache::Command.parse(["cache", "list"]).run`, matching the existing convention in `spec/doctor_spec.rb`
- **Files modified:** spec/command_cache_list_spec.rb
- **Verification:** All 10 examples pass with this invocation
- **Committed in:** 57e07ea (Task 1 test commit)

**2. Task 2's edge cases folded into Task 1's single spec/implementation pass (no separate commit)**
- **Found during:** Task 1 authoring
- **Issue:** The plan splits the RED-then-GREEN cycle across two tasks, but Task 2's own action text says "Only change list.rb if one of the new assertions actually fails" -- anticipating that Task 1's implementation would already satisfy Task 2's cases
- **Outcome:** Wrote all 10 examples (Task 1's happy path + Task 2's 6 edge cases) into one spec file, confirmed RED (6 of 10 failing against the unmodified `Dir.entries` implementation), then made GREEN with one implementation commit. Task 2 required zero additional production-code changes, exactly as its own action text predicted.
- **Files modified:** spec/command_cache_list_spec.rb (all in 57e07ea), lib/spm_cache/command/cache/list.rb (all in 9f0d5a4)
- **Verification:** `bundle exec rspec spec/command_cache_list_spec.rb` -- 10 examples, 0 failures; `bundle exec rspec` -- 361 examples, 0 failures (baseline 354 + 7 net new, one spec_helper self-test unaffected)

---

**Total deviations:** 2 (1 blocking test-invocation fix, 1 documented task-boundary consolidation)
**Impact on plan:** No scope creep. The test-invocation fix was required for the spec to run at all. The task consolidation changes commit structure, not behavior -- every must_have truth and every task's stated acceptance criteria are met by the resulting code.

## Issues Encountered
None beyond the deviations above.

## User Setup Required

None - no external service configuration required.

## Verification

```
bundle exec rspec spec/command_cache_list_spec.rb   # 10 examples, 0 failures
bundle exec rspec                                    # 361 examples, 0 failures (baseline 354 + 7 new)
```

## Next Phase Readiness

DIAG-02 is now fully complete (build-output half shipped in 08-01, `cache list` half shipped here). Phase 8's full scope (FID-03, FID-04, CACHE-01, DIAG-02) is done. Phase 9 (Cache Identity & Invalidation) can proceed; its `cache list`-adjacent work, if any, would extend the same `*.xcframework`-only glob convention this plan establishes rather than reintroducing the old `Dir.entries` walk.

## Self-Check: PASSED

All created/modified files exist on disk (`lib/spm_cache/command/cache/list.rb`,
`spec/command_cache_list_spec.rb`, this SUMMARY.md). Both commits (`57e07ea`, `9f0d5a4`)
verified present via `git log --oneline --all`.

---
*Phase: 08-drift-read-back-fidelity-status-provenance*
*Completed: 2026-08-29*
