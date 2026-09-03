# Phase 7 Plan 2: PERF-01 Benchmark -- clones_dir + build lock vs. baseline

**Date:** 2026-08-27
**Reference project:** `/Users/ddphuong/Projects/next-labs/stress-ai/ios-stress-app/StressMonitor`
(the M1-established reference project from `06-M1-MEASUREMENT.md`)
**Methodology:** cold-cache full build via `spm-cache build --config=release`, driven from this
repo's local source (`bundle exec ruby -I<repo>/lib <repo>/bin/spm-cache build --config=release`,
`BUNDLE_GEMFILE` pointed at this repo's `Gemfile` so the reference project's own globally-installed
Homebrew `spm-cache` binary was never exercised) against the SAME live Xcode SPM graph, with
`~/.spm-cache` cleared before each run (release cache AND `derived_data/` scratch -- `derived_data`
is not config-scoped, so a warm `derived_data/SourcePackages/checkouts` from an earlier `debug`
build would silently pre-seed the exact per-package clone cost this benchmark measures, if left in
place).

## Commits measured

| Run | Commit | State |
|-----|--------|-------|
| Before | `a8d5ddb` | Plan 07-01 landed (seeding), no `clones_dir`/lock -- pre-Plan-07-02 |
| After | `bef915e` | This plan's Task 1 (`clones_dir`) + Task 2 (build lock) landed |

`lib/` was swapped between these two states via `git checkout <commit> -- lib/` (working-tree
files only, HEAD never moved) so both runs used the identical live `spm-cache.lock`/project graph,
isolating the variable under test. The Swift companion (`tools/spm-cache-proxy`) is unaffected by
either commit (Ruby-only plan) and was not rebuilt between runs.

## Pre-existing, out-of-scope failure encountered (not fixed, per SCOPE BOUNDARY)

The reference project's live SPM graph includes three Firebase Analytics variant products
(`FirebaseAnalyticsCore`, `FirebaseAnalyticsIdentitySupport`, `FirebaseAnalyticsWithoutAdIdSupport`)
that are all backed by the SAME Class E `.binaryTarget` (`FirebaseAnalytics`) under a differently
named product -- a case `BuildPipeline#copy_prebuilt_binary_target` explicitly does not implement
(see its own doc comment: "renaming a multi-slice prebuilt xcframework correctly would also require
patching the xcframework's own top-level Info.plist ... unneeded machinery for a case neither of
this session's two real products exercises"). This is unrelated to Task 1/2's changes (present
identically on both the before and after commit) and out of this plan's scope to fix. `--config=release`
+ a temporary local `ignore_build_errors: true` (the project's own gitignored `spm-cache.yml`,
restored to its original `false` after both runs -- never committed, never part of the project's
git history) let the benchmark continue past these 3 known failures and reach a real wall-clock/disk
number for the other 26 targets, identically on both runs (3 warned, 26 cached, both before and after).
No source code was changed to work around this; it is logged here as a discovered gap outside this
plan's scope, not fixed.

## Results

| Metric | Before (a8d5ddb) | After (bef915e) | Delta | Regression? |
|--------|-------------------|-------------------|-------|-------------|
| Wall-clock | 18m15s (1095s) | 10m50s (650s) | **-445s (-40.6%)** | No -- faster |
| `~/.spm-cache` total disk | 4.1G | 2.7G | **-1.4G (-34%)** | No -- smaller |
| `~/.spm-cache/release` (cached xcframework output) | 75M | 75M | 0 | No -- identical build artifacts |
| `~/.spm-cache/derived_data` (xcodebuild scratch) | 4.1G | 2.7G | -1.4G | No -- smaller |
| Targets built successfully | 26/29 | 26/29 | 0 | n/a (same pre-existing gap both runs) |

The shared `-clonedSourcePackagesDirPath` (`StressMonitor/spm-cache/packages/clones`, confirmed
present after the "after" run: `artifacts/`, `checkouts/`, `repositories/`, `workspace-state.json`,
326M total) replaces N independent per-package `DerivedData_<dest>/SourcePackages/checkouts` clones
of the whole host dependency graph with ONE shared clone directory reused across every xcodebuild
invocation -- exactly the Pitfall 9 fan-out this plan's Task 1 exists to collapse. The wall-clock
improvement follows directly: less redundant `git clone`/checkout work per package.

## Verdict

```
PASS: wall_clock_delta_s=-445 (<=0, required) AND disk_delta_bytes<=0 (required)
exit 0
```

**No regression on either axis -- both wall-clock and disk usage improved substantially.** PERF-01
is satisfied by measurement, not assumption. No gap-closure / minimal-pin-closure narrowing (D-08)
is needed.

## Reference project state (verified restored)

`StressMonitor.xcodeproj/project.pbxproj` (the one git-tracked file `integrate_proxy_into_project`
rewrites) was confirmed clean (`git status --short`) before both runs and restored via
`git checkout -- StressMonitor.xcodeproj/project.pbxproj` after each. `spm-cache.yml` and
`spm-cache.lock` are both gitignored in the reference project (confirmed via `git check-ignore -v`)
-- their mutation during this benchmark is not a git-tracked change; `spm-cache.yml` was restored
to its original content (`ignore_build_errors: false`) byte-for-byte after the benchmark. The
reference project's branch (`main`, `ea7e7cf9`) and its 3 pre-existing unrelated uncommitted changes
(`../AGENTS.md`, `../CLAUDE.md`, `StressMonitor.xcodeproj/xcshareddata/xcschemes/StressMonitor.xcscheme`)
were never touched and remain exactly as they were before this benchmark began.
