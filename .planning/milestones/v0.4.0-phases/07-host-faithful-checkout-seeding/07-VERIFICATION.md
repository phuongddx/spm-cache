---
phase: 07-host-faithful-checkout-seeding
verified: 2026-08-29T14:15:00Z
status: passed
score: 5/5 must-haves verified
behavior_unverified: 0
overrides_applied: 0
---

# Phase 7: Host-Faithful Checkout Seeding Verification Report

**Phase Goal:** Every per-package build — the metadata `describe` reads and the binary that gets cached — resolves its transitive dependencies from the host app's resolved graph rather than from that package's own requirements, at no cost to build time or disk.
**Verified:** 2026-08-29T14:15:00Z
**Status:** passed
**Re-verification:** No — initial verification (no prior `07-VERIFICATION.md` existed)

**Note on source state:** verified against current `HEAD` (`a2eb4bc`), which includes the post-plan code-review fix pass (commits `c3bb440`, `a915188`, `c5d1aaa`, `3a972bb`) on top of the two plans' own commits. All evidence below (source reads, test runs) was captured from the live working tree, not from SUMMARY.md narrative.

## Goal Achievement

### Observable Truths (ROADMAP Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | A package built by spm-cache checks out the same transitive versions the host app resolved (metadata + binary) | ✓ VERIFIED | `lib/spm_cache/spm/resolved_graph.rb#source_for/seed!` copies the host's `Package.resolved` verbatim; `BuildPipeline.run` (`build_pipeline.rb:43-61`) calls `seed_host_graph` before `perform_build`, and `perform_build`'s first action is `resolve_forwarded_target` → `Desc::Description.new(...).fetch` (the first `swift package describe` call). `spec/build_pipeline_seeding_spec.rb:56-78` proves the seed file exists at the moment `Desc::Description.new` is first constructed (a real stub-and-assert, not a static check). |
| 2 | Vendored-`.xcodeproj` packages appear as an explicit *not-graph-pinned* category, never silently counted as pinned | ✓ VERIFIED | `ResolvedGraph.vendored_xcodeproj?` (glob-based) gates `seed_host_graph` (`build_pipeline.rb:70-80`); a vendored checkout emits a `Core::UI.info` line and skips `seed!` entirely. `spec/build_pipeline_seeding_spec.rb:208-251` (3 examples) proves no file is written for a vendored fixture, the UI line names the package, and a non-vendored fixture in the same run is still seeded. |
| 3 | An aborted/failed/interrupted build leaves no checkout carrying a synthetic resolved file it did not have before; a concurrent `watch` cycle cannot delete checkouts out from under an in-flight build | ✓ VERIFIED | `BuildPipeline.run`'s `success = false … ensure ResolvedGraph.restore!(...) if seeded && !success` (build_pipeline.rb:51-60) is exercised by real behavioral tests, not presence checks: `spec/build_pipeline_seeding_spec.rb:94-149` forces a `StandardError` and a bare `Interrupt` inside the build and asserts the seeded file is genuinely removed/restored in both cases. Concurrency: `Installer::Build#acquire_build_lock`/`release_build_lock` and `Installer::Use#with_build_lock` share `Config#build_lock_path` (outside `sandbox_dir`, survives `recreate_dirs`' `rm_rf`); `spec/build_lock_spec.rb` uses real `Process.fork` two-process contention (not mocks) proving a concurrent `Installer::Use#perform_install` genuinely blocks on the flock (`>= 0.3s` measured delay) until the lock-holder releases, for both the non-fast-path and fast-path branches (the CR-01/CR-01b review-fix closed the fast-path gap). |
| 4 | With seeding disabled (default), behavior is byte-for-byte identical to v0.3.0 | ✓ VERIFIED | `resolved_pins_file: nil` and `clones_dir: nil` are the defaults at every layer (`BuildPipeline.run`, `Buildable#initialize`, `build_command`). `spec/build_pipeline_seeding_spec.rb:306-355` asserts zero `ResolvedGraph.seed!`/`.restore!` calls and compares `Buildable#build_command`'s output against a literal recorded pre-Phase-7 baseline string (not a self-comparison). `spec/buildable_spec.rb`'s `-clonedSourcePackagesDirPath` block confirms `clones_dir: nil` omits the flag entirely, byte-identical to pre-Plan-07-02 output. |
| 5 | A cached build of the reference project shows no wall-clock or disk regression vs v0.3.0 | ✓ VERIFIED | `.planning/phases/07-host-faithful-checkout-seeding/07-BENCHMARK.md` records a real cold-cache `spm-cache build --config=release` run against the external reference project (StressMonitor, 59-70 packages) at commit `a8d5ddb` (seeding only) vs `bef915e` (+ clones_dir + lock): wall-clock 18m15s → 10m50s (-40.6%), disk 4.1G → 2.7G (-34%), identical cached artifact size (75M both). Both commits verified to exist in this repo's history and match the described states (`git show --stat`). Both axes improved — no regression, no gap-closure narrowing needed. |

**Score:** 5/5 truths verified (0 present-but-behavior-unverified)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/spm_cache/spm/resolved_graph.rb` | `source_for`/`seed!`/`restore!`/`vendored_xcodeproj?`, pure FS | ✓ VERIFIED | Exists, substantive (85 lines, real atomic-write/snapshot logic), wired (required and called from `build_pipeline.rb`) |
| `lib/spm_cache/spm/build_pipeline.rb` | seeds before first describe, restores on failure only | ✓ VERIFIED | `run`/`seed_host_graph`/`perform_build` implement exactly the plan's shape; wired into `Installer::Build` |
| `lib/spm_cache/installer/build.rb` | threads one `resolved_pins_file`/`clones_dir` per run + build lock | ✓ VERIFIED | `source_for` called once (line 45-48), threaded into every `build_single_target`; `acquire_build_lock`/`release_build_lock` wrap `super` + build loop |
| `lib/spm_cache/installer/use.rb` | blocking flock on both fast-path and non-fast-path trailing calls | ✓ VERIFIED | `with_build_lock` wraps both branches (post CR-01b fix) |
| `lib/spm_cache/core/config.rb` | `clones_dir`, `build_lock_path` | ✓ VERIFIED | `clones_dir` = sibling of `umbrella_dir`/`proxy_dir`; `build_lock_path` outside `sandbox_dir` |
| `lib/spm_cache/spm/build.rb` | `clones_dir:` kwarg, `-clonedSourcePackagesDirPath` flag | ✓ VERIFIED | Gated on presence, single-quoted, byte-identical when nil |
| `spec/resolved_graph_spec.rb` | hermetic specs for the new module | ✓ VERIFIED | 14 examples covering `source_for`/`seed!`/`restore!`/`vendored_xcodeproj?`, all passing |
| `spec/build_pipeline_seeding_spec.rb` | seeding, classification, threading, byte-identical-default | ✓ VERIFIED | 15 examples, all passing, genuinely behavioral (not smoke tests) |
| `spec/build_lock_spec.rb` | real two-process contention proof | ✓ VERIFIED | 5 examples using `Process.fork`, all passing |
| `.planning/phases/07-host-faithful-checkout-seeding/07-BENCHMARK.md` | before/after measurement, explicit verdict | ✓ VERIFIED | Present, detailed, cites real commits and numbers |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `SPM::ResolvedGraph.source_for` | umbrella `Package.resolved` / `host_graph_path` | file existence checks | ✓ WIRED | `resolved_graph.rb:24-30` |
| `Installer::Build#perform_install` | `host_graph_detector.host_graph_path` | inherited memoized detector (Phase 6) | ✓ WIRED | `build.rb:45-48`; no second `DiffDetector`/`PackageResolved.locate` call introduced |
| `BuildPipeline.run` | `ResolvedGraph.seed!`/`.restore!` | `seed_host_graph` + `ensure` guard | ✓ WIRED | `build_pipeline.rb:43-80` |
| `Config#clones_dir` | `Buildable#build_command`'s `-clonedSourcePackagesDirPath` | threaded through both `BuildPipeline.run`/`run_with_scheme` `Buildable.new` sites | ✓ WIRED | `build_pipeline.rb:106-114`, `174-185`; verified by a real-object test exercising the `run_with_scheme` fallback path |
| `Config#build_lock_path` | `Installer::Build`/`Installer::Use` flock | `acquire_build_lock`/`release_build_lock`/`with_build_lock` | ✓ WIRED | Both installers reference the identical `@config.build_lock_path`; real fork-based contention test confirms cross-process exclusion |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Full test suite passes on current HEAD (post-review-fix) | `bundle exec rspec` | 342 examples, 0 failures | ✓ PASS |
| Seeding + classification + byte-identical-default specs pass individually | `bundle exec rspec spec/build_pipeline_seeding_spec.rb` | 15 examples, 0 failures | ✓ PASS |
| Real two-process lock contention specs pass | `bundle exec rspec spec/build_lock_spec.rb` | 5 examples, 0 failures | ✓ PASS |
| `ResolvedGraph` module specs pass | `bundle exec rspec spec/resolved_graph_spec.rb` | 14 examples, 0 failures | ✓ PASS |
| No debt markers introduced in phase-touched files | `grep -n -E "TBD|FIXME|XXX|TODO|HACK|PLACEHOLDER"` across all 6 modified `lib/` files | no matches | ✓ PASS |
| No Swift companion files touched by the phase | `git diff --stat <phase-range> -- '*.swift'` | empty | ✓ PASS (confirms "Ruby-only" claim) |

### Probe Execution

Not applicable — this phase has no `scripts/*/tests/probe-*.sh` convention; its blocking gate (PERF-01) is `07-BENCHMARK.md`, a one-time real-world measurement rather than a repeatable probe script. Verified above via git-commit cross-reference instead.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| FID-02 | 07-01 | Per-package builds seeded with host's resolved graph before first `swift package describe` | ✓ SATISFIED | `resolved_graph.rb` + `build_pipeline.rb` seeding, proven by `spec/build_pipeline_seeding_spec.rb` |
| FID-05 | 07-01 | Vendored-`.xcodeproj` packages reported not-graph-pinned, never silently counted as pinned | ✓ SATISFIED | `vendored_xcodeproj?` classification, proven by `spec/build_pipeline_seeding_spec.rb` |
| PERF-01 | 07-02 | Cached-build wall-clock/disk show no regression vs v0.3.0 | ✓ SATISFIED | `07-BENCHMARK.md`: -40.6% wall-clock, -34% disk, no regression |

No orphaned requirements: `.planning/REQUIREMENTS.md`'s phase-to-requirement mapping table lists exactly `FID-02, FID-05, PERF-01` for Phase 7, matching both plans' declared `requirements:` frontmatter exactly. All three are marked `Complete` in `REQUIREMENTS.md`.

### Anti-Patterns Found

None. No `TBD`/`FIXME`/`XXX`/`TODO`/`HACK`/`PLACEHOLDER` markers in any of the 6 `lib/` files this phase modified. Code review (`07-REVIEW.md`, iteration 3) independently confirmed `status: clean` (0 critical, 0 warning, 0 info) after the fix pass in `07-REVIEW-FIX.md` closed 7 of 8 findings (1 deliberately skipped with documented rationale — WR-05, sleep-based timing assertions judged low-risk and load-bearing for the concurrency proof).

### Informational: ROADMAP-listed measurements M2/M4 not executed (does not block this phase's own success criteria)

`.planning/phases/07-host-faithful-checkout-seeding/07-RESEARCH.md` (a prior research pass, independently corroborated here) found that ROADMAP.md's "Measurements (blocking)" section for Phase 7 lists three items — M4 (early probe: does `run_with_scheme`'s vendored-project path ever write back a realized version), M2 (report-only `resolution-incompatible` count), and M3 (wall-clock/disk delta). M3 was executed (`07-BENCHMARK.md`). M2 and M4 have no record anywhere in the phase's plans or summaries.

This is flagged for transparency but does **not** change this phase's status: the shipped code does not depend on M2/M4's outcome — the vendored-`.xcodeproj` path is already unconditionally classified as not-graph-pinned regardless of whether it could theoretically write back a realized version (Truth 2 above), and M2's `resolution-incompatible` count is explicitly Phase 8 input, not a Phase 7 success criterion. Recommend Phase 8's own discuss/research phase explicitly re-surface this rather than assume M2/M4 were run.

### Human Verification Required

None. All five ROADMAP success criteria have direct automated-test or documented-real-measurement evidence; no UI/visual/external-service behavior in this phase.

### Gaps Summary

No gaps found. All five ROADMAP Phase 7 success criteria are independently verified against current source (post code-review-fix commits), backed by genuinely behavioral tests (real `StandardError`/`Interrupt` exception injection, real `Process.fork` two-process lock contention, a literal-string byte-identical-default comparison) rather than presence/wiring checks alone. The full test suite (342 examples) passes on current HEAD. Code review is independently clean. Requirements traceability is complete with no orphans. The one informational item (M2/M4 measurements not run) is a process note relevant to Phase 8's planning, not a defect in what Phase 7 delivered.

---

*Verified: 2026-08-29T14:15:00Z*
*Verifier: Claude (gsd-verifier)*
