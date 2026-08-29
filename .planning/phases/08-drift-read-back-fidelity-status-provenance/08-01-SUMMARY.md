---
phase: 08-drift-read-back-fidelity-status-provenance
plan: 01
subsystem: build-pipeline
tags: [ruby, swiftpm, xcodebuild, package-resolved, provenance, drift-detection]

requires:
  - phase: 07-host-faithful-checkout-seeding
    provides: "SPM::ResolvedGraph.seed!/restore!, the seeded pkg_dir/Package.resolved left in place on success specifically for this phase's diff, and the vendored-.xcodeproj not-graph-pinned classification"
provides:
  - "BuildPipeline.run drift read-back: intended (resolved_pins_file) vs realized (post-build pkg_dir/Package.resolved) pin diff, intersection-only scoping"
  - "host-pinned / resolution-incompatible fidelity status classification, printed inline in spm-cache build output, never maskable by ignore_build_errors?"
  - "<name>.xcframework.provenance.json sidecar (fidelity_status, pins, spm_cache_version, config, destinations) written/cleaned-up alongside every cached xcframework, including the Class E direct-copy path"
  - "Installer::Build#build_single_target threads config: @config_name into every SPM::BuildPipeline.run call"
affects: ["cache list DIAG-02 column (deferred, not this plan's scope)", "Phase 9 cache identity/invalidation (may consume the provenance sidecar)"]

actuals:
  tokens: 7624
  tasks: 3
  commits: 5

tech-stack:
  added: []
  patterns:
    - "Single consolidated insertion point in BuildPipeline.run (after perform_build succeeds, before result is returned) covers all three artifact-producing paths (direct xcframework build, run_with_scheme, copy_prebuilt_binary_target) uniformly -- no per-call-site duplication"
    - "Sidecar write/cleanup mirrors write_shim_sidecar's exact File.write/JSON.generate shape and copy_prebuilt_binary_target's existing FileUtils.rm_f cleanup pattern"
    - "Pin-value precedence (revision wins over version) copied from Core::Diagnostics#host_pin_value rather than reinventing a second rule"

key-files:
  created:
    - spec/build_pipeline_provenance_spec.rb
  modified:
    - lib/spm_cache/spm/build_pipeline.rb
    - lib/spm_cache/installer/build.rb

key-decisions:
  - "Drift/status/sidecar logic lives once in BuildPipeline.run, not duplicated at each of perform_build's three internal return paths (RESEARCH.md Pattern 2) -- this is what gives Class E a correct sidecar with zero special-casing"
  - "Class E (copy_prebuilt_binary_target) defaults to host-pinned by construction: it never touches Package.resolved, so realized always equals whatever seed_host_graph wrote as intended"
  - "Intended pins captured from resolved_pins_file immediately after seed_host_graph returns, before perform_build runs -- never re-derived from pkg_dir/Package.resolved after the build (Pitfall 1 guard)"
  - "resolution-incompatible classification lives entirely on run's success path (Core::UI calls before result is returned), never via raise -- structurally unmaskable by Installer::Build's ignore_build_errors? rescue (Pitfall 2 guard, verified by a dedicated regression spec)"
  - "command/pkg/build.rb deliberately left untouched -- it never passes resolved_pins_file, so seeded is always false there and no sidecar is ever written regardless of the new config: kwarg's default nil"

patterns-established:
  - "Fidelity status sidecar cleanup extends to every path that overwrites/replaces an xcframework (not-seeded branch's rm_f generalizes what was previously only Class E's .shims.json cleanup)"

requirements-completed: [FID-03, FID-04, CACHE-01, DIAG-02]

coverage:
  - id: D1
    description: "Drift between intended (host-seeded) and realized (post-build) pins is detected per package and reported via Core::UI.warn, naming the package and both pin values"
    requirement: FID-03
    verification:
      - kind: unit
        ref: "spec/build_pipeline_provenance_spec.rb#reports drift, resolution-incompatible status, and writes a provenance sidecar with exactly five keys"
        status: pass
      - kind: unit
        ref: "spec/build_pipeline_provenance_spec.rb#compares revision values when present on both sides, ignoring version"
        status: pass
    human_judgment: false
  - id: D2
    description: "A package whose realized pins diverge from intent is classified resolution-incompatible, still builds and caches successfully, and the status is never masked by ignore_build_errors?"
    requirement: FID-04
    verification:
      - kind: unit
        ref: "spec/build_pipeline_provenance_spec.rb#reports drift, resolution-incompatible status, and writes a provenance sidecar with exactly five keys"
        status: pass
      - kind: unit
        ref: "spec/build_pipeline_provenance_spec.rb#never queries ignore_build_errors? when BuildPipeline.run succeeds and reports resolution-incompatible on its own success path"
        status: pass
    human_judgment: false
  - id: D3
    description: "Every host-graph-aware cached xcframework (including the Class E direct-copy path) carries a .xcframework.provenance.json sidecar with exactly the five specified fields; every path that overwrites/replaces an xcframework without a fresh sidecar removes any stale one; vendored-.xcodeproj and no-host-graph (pkg build) paths write nothing"
    requirement: CACHE-01
    verification:
      - kind: unit
        ref: "spec/build_pipeline_provenance_spec.rb#writes a host-pinned provenance sidecar for a Class E direct-copy build, with no special-casing"
        status: pass
      - kind: unit
        ref: "spec/build_pipeline_provenance_spec.rb#vendored .xcodeproj checkout: writes no sidecar and removes a pre-existing stale one"
        status: pass
      - kind: unit
        ref: "spec/build_pipeline_provenance_spec.rb#nil resolved_pins_file (no host graph anywhere): writes no sidecar, prints no fidelity status line, removes a pre-existing stale one"
        status: pass
    human_judgment: false
  - id: D4
    description: "spm-cache build output names each built package's fidelity status inline (host-pinned / resolution-incompatible), using neutral (never alarming) wording, without a separate command"
    requirement: DIAG-02
    verification:
      - kind: unit
        ref: "spec/build_pipeline_provenance_spec.rb#reports host-pinned status with no drift warning when intended and realized pins agree"
        status: pass
    human_judgment: false

duration: ~40min
completed: 2026-08-29
status: complete
---

# Phase 08 Plan 01: Drift Read-Back, Fidelity Status & Provenance Summary

**BuildPipeline.run now diffs intended vs. realized pins after every build, reports host-pinned/resolution-incompatible status inline, and writes a `.xcframework.provenance.json` sidecar (realized pins, spm-cache version, config, destinations) via one consolidated insertion point that covers the main build path, the scheme-fallback path, and the Class E direct-copy path uniformly.**

## Performance

- **Duration:** ~40 min
- **Tasks:** 3
- **Files modified:** 2 (+1 new spec file)
- **Commits:** 5

## Accomplishments
- Realized dependency versions are read back after every seeded build and compared against the intended host pins; drift is reported via `Core::UI.warn`, naming the package identity and both pin values (FID-03)
- Packages whose realized graph diverges from intent are classified `resolution-incompatible`, still build and cache successfully from source, and the classification is structurally unmaskable by `ignore_build_errors?` since it is assigned and reported entirely on `run`'s success path, never via `raise` (FID-04)
- Every host-graph-aware cached xcframework -- including the Class E (`copy_prebuilt_binary_target`) direct-copy path, with zero special-casing -- carries a `<name>.xcframework.provenance.json` sidecar with exactly the five specified fields (`fidelity_status`, `pins`, `spm_cache_version`, `config`, `destinations`); every path that overwrites/replaces an xcframework without writing a fresh sidecar (vendored `.xcodeproj`, no host graph at all) removes any stale one instead (CACHE-01)
- `spm-cache build` output prints one status line per built package (`host-pinned` / `resolution-incompatible (built from source)`) inline, in the existing build output stream, with no separate command needed (DIAG-02's build-output half)
- `Installer::Build#build_single_target` now threads `config: @config_name` into every `SPM::BuildPipeline.run` call; `command/pkg/build.rb`'s own call site is deliberately untouched

## Task Commits

Each task was committed atomically (all three tasks are `tdd="true"`, so each followed a RED-then-GREEN cycle):

1. **Task 1: End-to-end drift detected -> resolution-incompatible reported -> provenance sidecar written (one path only)**
   - `85538f2` (test) - failing spec for drift read-back, status line, and sidecar
   - `af356de` (feat) - implemented `pin_value_map`/`host_pin_value`, the single consolidated insertion point in `run`, and `write_provenance_sidecar`
2. **Task 2: host-pinned / not-graph-pinned / Class E coverage + config threading**
   - `89c8135` (test) - coverage for host-pinned, vendored `.xcodeproj`, nil `resolved_pins_file`, Class E, and config threading (host-pinned + Class E already passed against Task 1's code; the other three failed as expected)
   - `b9b2d7e` (feat) - not-seeded cleanup branch, Class E's `rm_f`, and `Installer::Build`'s `config:` threading
3. **Task 3: diff-scoping edge cases + ignore_build_errors? cannot mask resolution-incompatible**
   - `abaa718` (test) - intersection-only scoping, malformed-JSON tolerance, revision/version precedence, and the `ignore_build_errors?` masking regression guard; all 15 examples passed immediately against Task 1/2's implementation with no further production code changes needed

**Plan metadata:** commit for this SUMMARY.md is separate, per the plan's instruction to leave STATE.md/ROADMAP.md to the orchestrator.

## Files Created/Modified
- `lib/spm_cache/spm/build_pipeline.rb` - `pin_value_map`/`host_pin_value` precedence helper, `report_fidelity`/`drifted_identities`/`write_provenance_sidecar` private methods, single insertion point in `run` after `perform_build` succeeds, `rm_f` cleanup added to `copy_prebuilt_binary_target` and to the not-seeded branch, new optional `config:` kwarg on `run`
- `lib/spm_cache/installer/build.rb` - `build_single_target` now passes `config: @config_name` into `SPM::BuildPipeline.run`
- `spec/build_pipeline_provenance_spec.rb` - new file, 15 examples covering FID-03/FID-04/CACHE-01/DIAG-02

## Decisions Made
- Single consolidated insertion point in `BuildPipeline.run` (RESEARCH.md Open Question 2, resolved in the plan) rather than duplicating drift/sidecar logic at each of `perform_build`'s three internal return paths -- simpler, DRYer, and what makes Class E get a correct sidecar automatically
- Class E gets `host-pinned` by construction rather than a distinct status: it never invokes `xcodebuild`/re-resolves, so its realized `Package.resolved` always equals whatever `seed_host_graph` wrote as intended (Assumption A1 from RESEARCH.md accepted as-is; the earlier `swift package describe` probe was not found to trigger any re-resolution in practice, consistent with this design)
- `pin_value_map`/`host_pin_value` copy `Core::Diagnostics`'s existing revision-over-version precedence verbatim rather than defining a second, possibly-disagreeing rule
- Diff scope is strictly the intersection of intended and realized pin identities (`intended.keys & realized.keys`) -- an identity on only one side carries no evidence of drift, matching the plan's context section on `seed!`'s verbatim-copy-then-narrow semantics

## Deviations from Plan

None - plan executed exactly as written. All 5 `must_haves.truths` verified true against the resulting code (see Coverage section above and the full verification run below).

## Issues Encountered
None.

## User Setup Required

None - no external service configuration required.

## Verification

```
bundle exec rspec spec/build_pipeline_provenance_spec.rb                        # 15 examples, 0 failures
bundle exec rspec spec/build_pipeline_seeding_spec.rb spec/build_pipeline_spec.rb # 46 examples, 0 failures
bundle exec rspec                                                                 # 354 examples, 0 failures (baseline 342 + 12 new)
```

## Next Phase Readiness

FID-03, FID-04, CACHE-01, and DIAG-02's build-output half are complete. `cache list`'s per-module status column (DIAG-02's other half, per RESEARCH.md's Pitfall 4 -- `cache list` currently has no per-module concept at all) was not part of this plan's `files_modified` scope and remains open; the provenance sidecar this plan writes is exactly what a future `cache list` implementation would read. Phase 9 (Cache Identity & Invalidation) can consume the provenance sidecar's `fidelity_status`/`pins` fields as-is; no schema changes anticipated.

---
*Phase: 08-drift-read-back-fidelity-status-provenance*
*Completed: 2026-08-29*
