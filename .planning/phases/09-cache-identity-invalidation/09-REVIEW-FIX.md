---
phase: 09-cache-identity-invalidation
fixed_at: 2026-08-29T20:22:00Z
review_path: .planning/phases/09-cache-identity-invalidation/09-REVIEW.md
iteration: 3
findings_in_scope: 1
fixed: 1
skipped: 0
status: all_fixed
---

# Phase 09: Code Review Fix Report

**Fixed at:** 2026-08-29T20:22:00Z
**Source review:** .planning/phases/09-cache-identity-invalidation/09-REVIEW.md
**Iteration:** 3 (final auto-fix pass, cap reached)

**Summary:**
- Findings in scope: 1 (critical_warning scope — 0 warning findings this iteration; IN-01/IN-02 are info-tier and out of scope)
- Fixed: 1
- Skipped: 0

## Fixed Issues

### CR-01: `copy_prebuilt_binary_target`'s own provenance-sidecar cleanup ran *before* `report_fidelity`, silently reopening the CACHE-02 identity-collision blind spot for Class E products

**Files modified:** `lib/spm_cache/spm/build_pipeline.rb`, `spec/build_pipeline_provenance_spec.rb`
**Commit:** `f83ee3b`
**Applied fix:** Removed the pre-emptive `FileUtils.rm_f("#{output_path}.provenance.json")` from
`copy_prebuilt_binary_target` (the `.shims.json` `rm_f` immediately above it stays — nothing else
cleans that sidecar up for Class E). `report_fidelity`'s `unless seeded` branch (WR-03/WR-05,
`build_pipeline.rb:102-136`) already unconditionally rewrites the provenance sidecar on every
path, seeded or not — so the pre-emptive delete was redundant on the happy path (IN-01's original
framing) and was actively harmful on the one path that reads the *old* sidecar back first
(`existing_sidecar_pins`, called from the `unless seeded` branch) to decide whether to preserve a
previously-recorded host-pinned identity. Deleting the file before that read-back guaranteed the
guard always saw "no sidecar" for any unseeded Class E rebuild, silently discarding a real pin and
falling through to a fresh `not-graph-pinned`/`pins: {}` sidecar — which `Cache.swift`'s `hit()`
treats as "no evidence of drift", producing a false cache hit against any host pin.

Also updated the doc comment on the remaining `.shims.json` cleanup to explicitly record *why*
there is no equivalent `.provenance.json` removal, so a future reader doesn't reintroduce the
same bug by "restoring" the deleted line as a symmetry fix.

**Regression test added:** `spec/build_pipeline_provenance_spec.rb`, in the existing "Class E
(copy_prebuilt_binary_target) gets a provenance sidecar via the same consolidated insertion
point" describe block — `"preserves a prior host-pinned sidecar's non-empty pins on an unseeded
Class E rebuild (CR-01) instead of copy_prebuilt_binary_target deleting it before report_fidelity
can read it back"`. The test exercises the real production path end-to-end
(`BuildPipeline.run` with `resolved_pins_file: nil`, real `Buildable`/xcodebuild bypassed via the
Class E short-circuit, real filesystem for the prebuilt xcframework and sidecar): it pre-seeds a
`host-pinned` sidecar with a non-empty `pins` entry at the Class E product's `output_path`, runs
an unseeded rebuild, and asserts the pins and `fidelity_status` survive unchanged.

Verified this is a genuine (non-tautological) regression test by temporarily reverting the
production fix and re-running just this test: it fails against the pre-fix code with
`expected: "host-pinned", got: "not-graph-pinned"` — reproducing exactly the failure mode CR-01
describes — and passes once the fix is restored.

## Verification

Both full test suites were run after the fix, from the environment's main checkout
(`workflow.use_worktrees` is `false` in `.planning/config.json`, so this fix was made directly on
branch `gsd/v0.4.0-build-fidelity-release-automation` — no isolated worktree was created; these
results are reproducible from this same checkout):

- `bundle exec rspec` (project root): **387 examples, 0 failures**
- `swift test` (`tools/spm-cache-proxy/`): **36 tests in 7 suites, all passed**

## Skipped Issues

None — the one in-scope finding (CR-01) was fixed and verified.

**Out of scope for this pass (documented, not silently unaddressed):**

- **IN-01** (`lib/spm_cache/spm/build_pipeline.rb:1094`): superseded by and resolved via CR-01
  above — no separate action needed.
- **IN-02** (`lib/spm_cache/installer/use.rb:97-101`): info-tier, explicitly out of scope for
  `critical_warning` fix scope. Carried over unfixed across all three review iterations: the
  fast-path lockfile version read (`current_spm_cache_version?`) does an exact-basename lookup
  with no fallback for a hand-written/legacy project key, unlike `Installer#lock_project_data`'s
  stem-match against the same lockfile. Fail-closed (worst case: fast path never engages, forcing
  a full regen) — not a correctness bug, just a reader inconsistency. Left for a future pass since
  this auto-fix loop's cap (3 iterations) is reached and this finding was never in scope for
  `critical_warning`.

---

_Fixed: 2026-08-29T20:22:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 3 (final)_
