---
phase: 07-host-faithful-checkout-seeding
plan: 01
subsystem: build-fidelity
tags: [swift-package-manager, xcodebuild, resolved-graph, ruby]

requires:
  - phase: 06-graph-authority-lockfile-reconciliation
    provides: "Core::PackageResolved canonical locator + DiffDetector's single memoized host_graph_detector (one host-graph answer per run)"
provides:
  - "SPM::ResolvedGraph module (source_for/seed!/restore!/vendored_xcodeproj?) -- pure filesystem, zero shell-out, zero JSON parsing of seeded content"
  - "BuildPipeline.run's resolved_pins_file: kwarg -- seeds the host's Package.resolved into pkg_dir before the first swift package describe call, atomically, with restore-on-failure/interrupt"
  - "Vendored-.xcodeproj classification gating seed/skip, reported as an explicit not-graph-pinned UI line"
  - "Installer::Build threading one resolved_pins_file per run into every BuildPipeline.run call"
affects: ["08-drift-read-back-fidelity-status-provenance", "10-fidelity-regression-coverage"]

actuals:
  tokens: 8065
  tasks: 3
  commits: 2

tech-stack:
  added: []
  patterns:
    - "success = false ... ensure restore! unless success -- guards a checkout mutation against StandardError AND Interrupt/SignalException, never fires on success"
    - "Classify before mutate: vendored_xcodeproj? gates the seed call itself, not a downstream report"

key-files:
  created:
    - lib/spm_cache/spm/resolved_graph.rb
    - spec/resolved_graph_spec.rb
    - spec/build_pipeline_seeding_spec.rb
  modified:
    - lib/spm_cache/spm/build_pipeline.rb
    - lib/spm_cache/installer/build.rb
    - spec/installer_build_spec.rb

key-decisions:
  - "run's body was extracted into a private perform_build so run itself is just: mkdir_p, classify+seed, then a single success-flag + ensure region around perform_build -- matches the plan's required shape without duplicating the multi-return-statement body under a manual success flag at every return site"
  - "Installer::Build resolves resolved_pins_file exactly once via the inherited, already-memoized host_graph_detector -- no second Core::DiffDetector/Core::PackageResolved.locate call anywhere in this file, preserving Phase 6 Plan 05's single-per-run-answer invariant"
  - "-onlyUsePackageVersionsFromResolvedFile deliberately NOT added (D-02) -- xcodebuild silently upgrades a seeded pin below a package's manifest floor rather than hard-failing; detecting that drift is Phase 8's read-back job"

patterns-established:
  - "Atomic write via Tempfile in the same directory + File.rename, with an ensure-unlink on any write failure -- reused verbatim for both seed! and restore!"

requirements-completed: [FID-02, FID-05]

coverage:
  - id: D1
    description: "A package built by spm-cache checks out the same transitive versions the host app resolved (host graph seeded verbatim before the first swift package describe call)"
    requirement: FID-02
    verification:
      - kind: unit
        ref: "spec/build_pipeline_seeding_spec.rb#SPMCache::SPM::BuildPipeline host graph seeding"
        status: pass
      - kind: unit
        ref: "spec/resolved_graph_spec.rb#SPMCache::SPM::ResolvedGraph"
        status: pass
    human_judgment: false
  - id: D2
    description: "Vendored-.xcodeproj packages are reported as an explicit not-graph-pinned category, never silently folded into pinned"
    requirement: FID-05
    verification:
      - kind: unit
        ref: "spec/build_pipeline_seeding_spec.rb#SPMCache::SPM::BuildPipeline vendored .xcodeproj classification"
        status: pass
    human_judgment: false
  - id: D3
    description: "An aborted, failed, or interrupted build leaves no checkout carrying a synthetic Package.resolved it did not have before"
    verification:
      - kind: unit
        ref: "spec/build_pipeline_seeding_spec.rb#SPMCache::SPM::BuildPipeline host graph seeding (StandardError + Interrupt restore examples)"
        status: pass
    human_judgment: false
  - id: D4
    description: "With no host graph available anywhere, behavior is byte-for-byte identical to v0.3.0"
    requirement: PERF-01
    verification:
      - kind: unit
        ref: "spec/build_pipeline_seeding_spec.rb#SPMCache::SPM::BuildPipeline default (no host graph) path is byte-identical to v0.3.0"
        status: pass
      - kind: unit
        ref: "spec/installer_build_spec.rb#SPMCache::Installer::Build no host graph found threads resolved_pins_file: nil"
        status: pass
    human_judgment: false

duration: ~55min
completed: 2026-08-27
status: complete
---

# Phase 7 Plan 1: Host-Faithful Checkout Seeding Summary

**Every per-package build now seeds the host app's own `Package.resolved` verbatim into the checkout before the first `swift package describe` call, atomically and with restore-on-failure; vendored-`.xcodeproj` packages are classified before seeding and reported not-graph-pinned instead of silently pinned; the no-host-graph-found default path is byte-identical to v0.3.0.**

## Performance

- **Duration:** ~55 min
- **Started:** 2026-08-27T15:26:00Z (approx, from prior git log gap)
- **Completed:** 2026-08-27T16:21:53Z
- **Tasks:** 3
- **Files modified:** 6 (3 lib, 3 spec)

## Accomplishments

- New `SPM::ResolvedGraph` module: `source_for` (umbrella-resolved-first, host-graph-path fallback, nil when neither exists), `seed!`/`restore!` (atomic temp-file+rename, snapshot-based restore distinguishing "nothing existed" from "something did"), `vendored_xcodeproj?` (mirrors `Buildable#ambiguous_project_checkout?`'s glob shape, `.any?` instead of `.length >= 2`)
- `BuildPipeline.run` gained `resolved_pins_file:` (default `nil`), seeds strictly before the first `Desc::Description.new` construction inside the former `run` body (now `perform_build`), and restores exactly on failure/interrupt via a `success = false ... ensure ... unless success` region wrapping the whole build
- Vendored-`.xcodeproj` checkouts are classified before any seed call, never written to, and reported via a `Core::UI.info` line naming the package and stating it is not graph-pinned
- `Installer::Build#perform_install` resolves the run's single pin source once (`SPM::ResolvedGraph.source_for` reading the already-memoized `host_graph_detector.host_graph_path`) and threads the identical value into every `SPM::BuildPipeline.run` call for the run's missed targets
- Proved the default (no host graph found) path is byte-identical to v0.3.0: zero `ResolvedGraph.seed!`/`.restore!` calls, and a real (unstubbed) `Buildable#build_command` output matching a literal recorded pre-Phase-7 baseline string

## Task Commits

1. **Task 1 + Task 2 combined: Seed the host graph before the first describe call, and classify vendored-.xcodeproj checkouts as not-graph-pinned** - `7ebe14a` (feat)
2. **Task 3: Prove the default (no host graph found) path is byte-identical to v0.3.0** - `c1b2d83` (test)

_TDD RED was verified genuinely before implementation: `spec/resolved_graph_spec.rb` and `spec/build_pipeline_seeding_spec.rb` failed with `NameError: uninitialized constant SPMCache::SPM::ResolvedGraph` before `lib/spm_cache/spm/resolved_graph.rb` existed._

**Plan metadata commit:** pending (this commit)

## Files Created/Modified

- `lib/spm_cache/spm/resolved_graph.rb` - `SPM::ResolvedGraph.source_for/seed!/restore!/vendored_xcodeproj?`
- `lib/spm_cache/spm/build_pipeline.rb` - `run` now seeds/classifies before delegating to a new private `perform_build` (the former body), wrapped in a success-flag+ensure restore region
- `lib/spm_cache/installer/build.rb` - resolves `resolved_pins_file` once via `host_graph_detector.host_graph_path`, threads it into every `build_single_target`/`BuildPipeline.run` call
- `spec/resolved_graph_spec.rb` - hermetic specs for the new module (12 examples)
- `spec/build_pipeline_seeding_spec.rb` - new file: BuildPipeline seeding, vendored classification, Installer::Build threading, and the byte-identical-default describe blocks (13 examples)
- `spec/installer_build_spec.rb` - one new example for D-07 (additions only, zero pre-existing lines touched)

## Decisions Made

- Combined Tasks 1 and 2 into a single commit (`7ebe14a`): both were implemented together since the vendored-classification branch sits directly inside the same seed/skip decision point the tracer task introduced, and splitting them into two commits would have required an artificial intermediate state where seeding exists but classification does not (never a real, independently-shippable state). Task 3 was committed separately (`c1b2d83`) since it adds pure regression coverage with no production-code change.
- `run`'s original body (multiple early `return` statements) was extracted into a private `perform_build` method rather than threading a manual `success = true` flag before each return site — functionally identical to the plan's literal "wrap the rest of run's body" instruction (the whole `perform_build` call is one atomic unit inside `run`'s `begin/ensure`), simpler to read, and does not touch any of `perform_build`'s internal control flow (mirrors the plan's own "Claude's discretion" latitude on module/method organization).

## Deviations from Plan

None - plan executed exactly as written, including the explicit exclusions (no `-onlyUsePackageVersionsFromResolvedFile`, no `-clonedSourcePackagesDirPath` wiring, no pins/drift parsing method on `ResolvedGraph`).

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- FID-02 and FID-05 are Complete in `REQUIREMENTS.md`; PERF-01 remains Pending and is 07-02's scope (shared `-clonedSourcePackagesDirPath`, process-level `watch`/build lock, benchmark gate) per ROADMAP's own phase-to-requirement mapping.
- The seeded `<pkg_dir>/Package.resolved` is left in place after a successful build specifically so Phase 8's drift read-back can compare xcodebuild's realized output against it — no rework needed there.
- Full suite: 332 examples, 0 failures (baseline was 307; +25 new examples net across this plan's 3 tasks). `make proxy.build` clean (Ruby-only change, Swift companion untouched).
- `git diff --stat` for `spec/build_pipeline_spec.rb` and `spec/buildable_spec.rb` shows zero changes (both untouched); `spec/installer_build_spec.rb` shows additions only (41 insertions, 0 deletions).

---
*Phase: 07-host-faithful-checkout-seeding*
*Completed: 2026-08-27*

## Self-Check: PASSED

- FOUND: lib/spm_cache/spm/resolved_graph.rb
- FOUND: spec/resolved_graph_spec.rb
- FOUND: spec/build_pipeline_seeding_spec.rb
- FOUND: .planning/phases/07-host-faithful-checkout-seeding/07-01-SUMMARY.md
- FOUND commit: 7ebe14a
- FOUND commit: c1b2d83
