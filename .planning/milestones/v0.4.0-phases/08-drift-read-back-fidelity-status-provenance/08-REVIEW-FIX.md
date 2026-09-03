---
phase: 08-drift-read-back-fidelity-status-provenance
fixed_at: 2026-08-29T16:49:00Z
review_path: .planning/phases/08-drift-read-back-fidelity-status-provenance/08-REVIEW.md
iteration: 2
findings_in_scope: 1
fixed: 1
skipped: 0
status: all_fixed
---

# Phase 08: Code Review Fix Report

**Fixed at:** 2026-08-29T16:49:00Z
**Source review:** .planning/phases/08-drift-read-back-fidelity-status-provenance/08-REVIEW.md
**Iteration:** 2

**Summary:**
- Findings in scope: 1 (WR-04; IN-01 excluded -- `fix_scope: critical_warning`; 0 critical findings this iteration)
- Fixed: 1
- Skipped: 0

**Verification:** `workflow.use_worktrees` is `false` in `.planning/config.json`, so editing and the commit happened directly in the main checkout -- no isolated worktree was created, per the documented opt-out. `ruby -c` syntax checks, the targeted spec run (`bundle exec rspec spec/build_pipeline_provenance_spec.rb`), and the full suite (`bundle exec rspec`) all ran in that same main checkout, so the numbers below are reproducible from the tree as it stands now.

## Fixed Issues

### WR-04: Class E (`copy_prebuilt_binary_target`) provenance sidecar still recorded requested destinations, not the copied artifact's actual slices

**Files modified:** `lib/spm_cache/spm/build_pipeline.rb`, `spec/build_pipeline_provenance_spec.rb`
**Commit:** `386305b`
**Applied fix:** `perform_build`'s Class E short-circuit no longer returns the bare requested `destinations` argument alongside the copied artifact's path. It now calls a new private helper, `actual_destinations_for(xcframework_path, requested)`, which lists the copied xcframework's own top-level slice directories and narrows `requested` down to the ones a slice actually satisfies -- mirroring `Installer::Build#slice_satisfies?`'s existing cache-hit-detection logic exactly (`"iphonesimulator"` requires a slice directory name containing `"simulator"`; `"iphoneos"` requires one starting with `"ios"` that does *not* contain `"simulator"`). This closes the same "requested != actually-produced" gap WR-01 (iteration 1) already closed for the two build-loop paths (`perform_build`'s main loop and `run_with_scheme`), for the third artifact-producing path (a vendor's prebuilt binaryTarget xcframework instead of a failed `xcodebuild` invocation).

Added a new regression test in the existing "Class E ... gets a provenance sidecar" describe block: a prebuilt xcframework fixture with only an `ios-arm64` slice (no simulator slice, reusing the existing fixture's device-only shape) is requested with `destinations: ["iphonesimulator", "iphoneos"]`, and the test asserts the written sidecar's `destinations` field is narrowed to `["iphoneos"]` -- exercising the actual production code path (`BuildPipeline.run` -> `perform_build` -> `copy_prebuilt_binary_target` + `actual_destinations_for` -> `report_fidelity` -> `write_provenance_sidecar`), not a stub of the helper itself. Ran `bundle exec rspec spec/build_pipeline_provenance_spec.rb` (20 examples, 0 failures, including this new one and the pre-existing Class E test unaffected) and the full suite `bundle exec rspec` (368 examples, 0 failures).

---

_Fixed: 2026-08-29T16:49:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 2_
