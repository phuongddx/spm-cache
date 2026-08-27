---
phase: 07-host-faithful-checkout-seeding
plan: 02
subsystem: build-fidelity
tags: [swift-package-manager, xcodebuild, flock, performance, ruby]

requires:
  - phase: 07-host-faithful-checkout-seeding
    plan: "01"
    provides: "SPM::ResolvedGraph seeding + BuildPipeline.run's resolved_pins_file: kwarg + Installer::Build threading one host-graph answer per run"
provides:
  - "Config#clones_dir / #build_lock_path"
  - "Buildable#build_command's -clonedSourcePackagesDirPath flag, threaded from both BuildPipeline.run call sites"
  - "Installer::Build / Installer::Use process-level flock (build_lock_path) closing the watch re-entrancy race"
  - "07-BENCHMARK.md: real cold-cache before/after measurement against the reference project, PERF-01 satisfied"
affects: ["08-drift-read-back-fidelity-status-provenance", "09-cache-identity-invalidation", "10-fidelity-regression-coverage"]

actuals:
  tokens: 24000
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "Gate a new xcodebuild flag on presence (clones_dir: nil), never on a separate feature toggle -- byte-identical default output is the regression-safety net, verified as a literal string match in build_pipeline_seeding_spec.rb, unchanged by this plan"
    - "Blocking flock (LOCK_EX), never a trylock-and-retry loop -- 'defer rather than interrupt' is satisfied by the OS's own blocking semantics"
    - "Lock path lives OUTSIDE the directory tree the lock protects against rm_rf, by construction (Config#build_lock_path is a project_dir-level dotfile, sandbox_dir is a project_dir/spm-cache subdirectory)"

key-files:
  created:
    - spec/build_lock_spec.rb
    - .planning/phases/07-host-faithful-checkout-seeding/07-BENCHMARK.md
  modified:
    - lib/spm_cache/core/config.rb
    - lib/spm_cache/spm/build.rb
    - lib/spm_cache/spm/build_pipeline.rb
    - lib/spm_cache/installer/build.rb
    - lib/spm_cache/installer/use.rb
    - spec/buildable_spec.rb
    - spec/build_pipeline_spec.rb
    - .planning/REQUIREMENTS.md
    - .planning/ROADMAP.md

key-decisions:
  - "clones_dir threaded through a plain kwarg default nil at every layer (Config -> Buildable -> BuildPipeline.run -> Installer::Build), matching resolved_pins_file's own Plan 07-01 pattern -- no new abstraction introduced for a single optional path"
  - "Lock acquire/release helper methods (acquire_build_lock/release_build_lock in Build, with_build_lock in Use) duplicated per-file rather than lifted onto the shared Installer base class, since the plan's files_modified scope explicitly excludes lib/spm_cache/installer.rb"
  - "Class E binaryTarget rename gap (FirebaseAnalyticsCore/IdentitySupport/WithoutAdIdSupport all backed by one differently-named FirebaseAnalytics binaryTarget) discovered live during the benchmark is a pre-existing, out-of-scope limitation -- documented in 07-BENCHMARK.md, NOT fixed inline (present identically on both the before and after commit, so it does not bias the PERF-01 comparison)"

requirements-completed: [PERF-01]

coverage:
  - id: D1
    description: "Every xcodebuild invocation shares one spm-cache-owned clone directory instead of each of N package builds cloning the whole host graph independently"
    requirement: PERF-01
    verification:
      - kind: unit
        ref: "spec/buildable_spec.rb#SPMCache::SPM::Buildable#build_command -clonedSourcePackagesDirPath"
        status: pass
      - kind: unit
        ref: "spec/build_pipeline_spec.rb#SPMCache::SPM::BuildPipeline clones_dir threading (D-03)"
        status: pass
      - kind: integration
        ref: "07-BENCHMARK.md -- spm-cache/packages/clones/ confirmed present and shared (326M) after the real reference-project build"
        status: pass
    human_judgment: false
  - id: D2
    description: "A concurrent watch cycle cannot delete checkouts out from under an in-flight spm-cache build -- it waits instead"
    verification:
      - kind: unit
        ref: "spec/build_lock_spec.rb -- real two-process (Process.fork) contention proof, plus Installer::Build/Installer::Use integration tests proving the lock is held across the build loop and the non-fast-path Use branch genuinely blocks (timing-verified) until released"
        status: pass
    human_judgment: false
  - id: D3
    description: "Cached-build wall-clock and disk usage on the reference project show no regression versus the pre-seeding baseline, or the regression is surfaced as a blocking finding rather than shipped silently"
    requirement: PERF-01
    verification:
      - kind: manual
        ref: "07-BENCHMARK.md -- real cold-cache spm-cache build --config=release against StressMonitor, before (a8d5ddb) vs after (bef915e): wall-clock 18m15s -> 10m50s (-40.6%), disk 4.1G -> 2.7G (-34%). Both axes improved; no regression."
        status: pass
    human_judgment: false

duration: "~2h (including ~29min real xcodebuild wall-clock across two full cold-cache reference-project builds)"
completed: 2026-08-27
status: complete
---

# Phase 7 Plan 2: Shared Clone Directory, Process-Level Build Lock & PERF-01 Benchmark Summary

**Every xcodebuild invocation now shares one spm-cache-owned clone directory via `-clonedSourcePackagesDirPath` instead of N independent per-package clones of the whole host graph; `Installer::Build` and `Installer::Use` share a process-level blocking flock so a watch-triggered regenerate defers to an in-flight build instead of racing it; and a real cold-cache benchmark against the reference project proves PERF-01 with a 40.6% wall-clock improvement and 34% disk reduction, not a regression.**

## Performance

- **Duration:** ~2h (includes ~29min of real xcodebuild wall-clock across two full cold-cache builds of the 59-70 package reference project)
- **Completed:** 2026-08-27
- **Tasks:** 3
- **Files modified:** 9 (5 lib, 2 spec, 2 .planning)

## Accomplishments

- `Config#clones_dir` (`sandbox_dir/packages/clones`, a dedicated sibling of `umbrella_dir`/`proxy_dir`, never under `{umbrella}/.build`) and `Config#build_lock_path` (a project_dir-level dotfile, OUTSIDE `sandbox_dir` by construction so `recreate_dirs`' `rm_rf` can never delete it while held)
- `Buildable#build_command` appends a single-quoted `-clonedSourcePackagesDirPath` flag only when `clones_dir` is present -- byte-identical to pre-Plan-07-02 output when nil, verified against `build_pipeline_seeding_spec.rb`'s own recorded literal-string baseline
- `BuildPipeline.run`'s `clones_dir:` kwarg threads into BOTH `Buildable.new` call sites -- the primary path AND `run_with_scheme`'s vendored-`.xcodeproj` fallback (the path packages like CryptoSwift/DTCoreText actually take) -- proven by a real-object test exercising the fallback branch and inspecting its own assembled xcodebuild command
- `Installer::Build#perform_install` acquires an exclusive blocking flock before `super`, holds it across `super` (recreate_dirs + resolve_umbrella_checkouts) and the entire build loop, and always releases it in `ensure` -- including when a build raises
- `Installer::Use#perform_install`'s non-fast-path branch blocks on the identical flock immediately before its own `recreate_dirs` call; the fast path acquires nothing (nothing to protect against there)
- Real two-process contention proof (`Process.fork`, not a single-process mock): a forked child holding the lock provably blocks a concurrent non-blocking trylock until it releases; a separate timing-based integration test proves `Installer::Use`'s non-fast-path `recreate_dirs` genuinely waits (>=300ms) for a concurrently-held lock to release before running
- `07-BENCHMARK.md`: real cold-cache `spm-cache build --config=release` against the StressMonitor reference project, before (`a8d5ddb`, pre-Plan-07-02) vs after (`bef915e`, this plan's Task 1+2): **wall-clock 18m15s -> 10m50s (-40.6%)**, **disk `~/.spm-cache` total 4.1G -> 2.7G (-34%)**, cached xcframework output identical (75M both runs). Both axes improved substantially; no gap-closure narrowing (D-08) needed.

## Task Commits

1. **Task 1: Shared -clonedSourcePackagesDirPath across every xcodebuild invocation** - `07e07ff` (feat)
2. **Task 2: Process-level lock so watch cannot delete checkouts mid-build** - `bef915e` (feat)
3. **Task 3: Benchmark gate -- no wall-clock or disk regression on the reference project** - `1b7b89d` (docs; PERF-01 marked Complete in REQUIREMENTS.md)

_TDD RED was verified genuinely before implementation for both Tasks 1 and 2: `spec/buildable_spec.rb`/`spec/build_pipeline_spec.rb` failed with `ArgumentError: unknown keyword: :clones_dir` before `Buildable#initialize`/`BuildPipeline.run` accepted it; `spec/build_lock_spec.rb`'s `Installer::Build`/`Installer::Use` lock tests failed genuinely (lock not held / recreate_dirs not blocked) before the flock wiring existed._

**Plan metadata commit:** pending (this commit)

## Files Created/Modified

- `lib/spm_cache/core/config.rb` - `clones_dir`, `build_lock_path`
- `lib/spm_cache/spm/build.rb` - `Buildable#initialize(clones_dir:)`, `build_command`'s gated flag
- `lib/spm_cache/spm/build_pipeline.rb` - `clones_dir:` threaded through `run`/`perform_build`/`run_with_scheme`
- `lib/spm_cache/installer/build.rb` - `acquire_build_lock`/`release_build_lock` wrapping `perform_install`; `clones_dir` threaded into `build_single_target`
- `lib/spm_cache/installer/use.rb` - `with_build_lock` wrapping the non-fast-path branch
- `spec/buildable_spec.rb` - `-clonedSourcePackagesDirPath` presence/omission tests
- `spec/build_pipeline_spec.rb` - clones_dir threading tests (primary + fallback)
- `spec/build_lock_spec.rb` - new file: real fork-based contention proof + Build/Use lock integration tests
- `.planning/phases/07-host-faithful-checkout-seeding/07-BENCHMARK.md` - new file: the PERF-01 measurement
- `.planning/REQUIREMENTS.md` - PERF-01 marked Complete
- `.planning/ROADMAP.md` - 07-02-PLAN.md marked done

## Decisions Made

- `clones_dir` threaded through a plain `nil`-default kwarg at every layer, mirroring `resolved_pins_file`'s own Plan 07-01 pattern -- no new abstraction for a single optional path.
- Lock acquire/release helpers duplicated in `Installer::Build` and `Installer::Use` rather than lifted onto the shared `Installer` base class, since the plan's `files_modified` explicitly scoped only those two files (not `lib/spm_cache/installer.rb`).
- The benchmark used `--config=release` (matching the plan's own suggested invocation) partly because it happened to already be a genuinely cold cache on this machine (`~/.spm-cache/release` was empty going in), and cleared the FULL `~/.spm-cache` (including `derived_data/`, not just `release/`) before each run -- `derived_data` is keyed by `pkg_dir`+`dest_key`, not by config, so a warm `derived_data/SourcePackages/checkouts` from an earlier `debug` run would have silently pre-seeded the exact per-package clone cost this benchmark exists to measure.
- A pre-existing, out-of-scope Class E binaryTarget rename gap (3 Firebase Analytics variant products all backed by one differently-named `FirebaseAnalytics` binaryTarget) was discovered live during the "before" run. Per SCOPE BOUNDARY, it was not fixed -- instead the reference project's own gitignored `spm-cache.yml` was temporarily set to `ignore_build_errors: true` (a supported, documented CLI knob, not a workaround) so the benchmark could continue past it and reach a real number for the other 26/29 targets, identically on both runs. Restored to its original `false` after both runs completed.

## Deviations from Plan

- **[Rule 3 - blocking issue, worked around via existing config knob, not fixed]** The reference project's live SPM graph triggers a pre-existing `BuildPipeline#copy_prebuilt_binary_target` gap (Class E binaryTarget name-mismatch, explicitly documented as unimplemented in that method's own comment) on 3 of 29 targets, identically on both the before and after commit. This blocked the benchmark from completing via a fatal, unrescued exception. Worked around by temporarily setting the reference project's own gitignored `ignore_build_errors: true` (its documented "continue past a broken package" flag) rather than fixing the underlying gap inline -- that gap is unrelated to this plan's `clones_dir`/lock changes and out of scope. Logged here, not fixed. Restored to `false` afterward.
- No other deviations -- Tasks 1 and 2 executed exactly as planned, including the explicit exclusions (no gate on `ResolvedGraph.vendored_xcodeproj?` for `clones_dir`, blocking flock not trylock-and-retry, no `watcher.rb` edit).

## Issues Encountered

- The reference project's Firebase Analytics Class E binaryTarget rename gap (see Deviations above) -- logged as a discovered, out-of-scope limitation, not filed as a separate `deferred-items.md` entry since it is fully documented in `07-BENCHMARK.md` and does not affect this plan's own success criteria.
- Reference project's git-tracked `StressMonitor.xcodeproj/project.pbxproj` is rewritten by every `spm-cache build`/`use` run (`integrate_proxy_into_project` always calls `project.save`). Verified clean before the benchmark, restored via `git checkout -- <path>` after each of the two runs, and reconfirmed clean at the end -- the reference project's branch (`main`), HEAD commit, and its 3 pre-existing unrelated uncommitted changes were never touched.

## User Setup Required

None -- no external service configuration required.

## Next Phase Readiness

- ROADMAP Phase 7 criteria 3 (watch cannot delete checkouts mid-build) and 5 (no wall-clock/disk regression, PERF-01) now hold, completing what Plan 07-01 left open (criteria 1, 2, 4).
- PERF-01 is Complete in `REQUIREMENTS.md`. Phase 7 has no remaining open requirements (FID-02, FID-05 from Plan 07-01; PERF-01 from this plan).
- Full suite: 341 examples, 0 failures. Baseline verified via a clean `git archive a8d5ddb` snapshot (the commit immediately before this plan's Task 1): 332 examples, 0 failures -- confirms `07-01-SUMMARY.md`'s own recorded count. Net +9 examples added by this plan. `make proxy.build` clean (Ruby-only plan, Swift companion untouched).
- Phase 8 (Drift Read-Back, Fidelity Status & Provenance) can now proceed: the seeded `Package.resolved` (Plan 07-01) plus the shared clone dir and build lock (this plan) form the complete, safe seeding mechanism Phase 8's read-back compares against.

---
*Phase: 07-host-faithful-checkout-seeding*
*Completed: 2026-08-27*

## Self-Check: PASSED

- FOUND: lib/spm_cache/core/config.rb
- FOUND: lib/spm_cache/spm/build.rb
- FOUND: lib/spm_cache/spm/build_pipeline.rb
- FOUND: lib/spm_cache/installer/build.rb
- FOUND: lib/spm_cache/installer/use.rb
- FOUND: spec/build_lock_spec.rb
- FOUND: .planning/phases/07-host-faithful-checkout-seeding/07-BENCHMARK.md
- FOUND commit: 07e07ff
- FOUND commit: bef915e
- FOUND commit: 1b7b89d
