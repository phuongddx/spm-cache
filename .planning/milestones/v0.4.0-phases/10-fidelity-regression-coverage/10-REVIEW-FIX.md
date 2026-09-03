---
phase: 10-fidelity-regression-coverage
fixed_at: 2026-08-29T17:04:20Z
review_path: .planning/phases/10-fidelity-regression-coverage/10-REVIEW.md
iteration: 1
findings_in_scope: 2
fixed: 2
remaining: 7 info findings (IN-01..IN-07, out of scope for this pass)
skipped: 0
status: all_fixed
---

# Phase 10: Code Review Fix Report

**Fixed at:** 2026-08-29T17:04:20Z
**Source review:** `.planning/phases/10-fidelity-regression-coverage/10-REVIEW.md`
**Scope:** `critical_warning` — the 2 WARNING findings (WR-01, WR-02). The 7 INFO findings are out of scope and left untouched, per the fix instruction.
**Verification location:** main checkout (`workflow.use_worktrees: false` in `.planning/config.json`) — every number below is reproducible from the main working tree.

**Summary:**
- Findings in scope: 2
- Fixed: 2 (commits `ebb757a`, `5b54277`)
- Skipped: 0
- Full suite after both fixes: **416 examples, 0 failures** (`bundle exec rspec`, 43.06s)
- Production code: **zero changes** — both commits touch only the two spec files (TEST-ONLY phase honored; all mutation edits below were temporary and reverted, never committed)

## Fixed Issues

### WR-01: The "SC4 hermeticity audit" example was tautological — zero production coupling

**File:** `spec/fidelity_edge_matrix_spec.rb` (SC4 audit describe at end of file)
**Commit:** `ebb757a` — `fix(10): WR-01 anchor SC4 hermeticity audit to real production shell-out paths`
**Original problem:** The example installed `allow(Core::Sh).to receive(:run) { raise }` and then asserted that calling `Core::Sh.run("xcodebuild ...")` raises — exercising zero production code (the stub echoes its own raise). It could only fail if RSpec itself broke.

**Applied fix:** Restructured so the hermeticity claim rests on observable production behavior. The audit now drives two REAL production shell-out seams — the exact calls the matrix legs' object stubs intercept — and requires the default-deny guard to intercept them:

1. **Seam 1 (Sh.run):** `SPMCache::SPM::Desc::Description.new(name:, pkg_dir:).fetch` → `Desc::BaseObject.describe` (lib/spm_cache/spm/desc/base.rb:52) genuinely calls `Core::Sh.run("swift package describe --type json", cwd:)`. Nothing else is stubbed, so production code must really route through `Core::Sh` for the guard's raise to fire.
2. **Seam 2 (capture_output → run):** `SPMCache::SPM::BuildPipeline.send(:resolve_scheme_fallback, "Foo", pkg_dir)` (lib/spm_cache/spm/build_pipeline.rb:1138-1149) calls `Core::Sh.capture_output("xcodebuild -list", cwd:)`. `capture_output` is deliberately NOT stubbed: it must route through the stubbed `Sh.run` for the interception to occur, proving the second public entry point is covered by the same guard.

Both seams rescue only `GeneralError`, so the guard's `RuntimeError` propagates (verified against the production source). If production ever bypassed `Core::Sh` (backticks, `system`, raw `Open3`) or stopped routing an entry point through `Sh.run`, no raise occurs and the example FAILS — teeth against production, not RSpec.

**Mutation proofs (temporary, reverted, never committed):**

| # | Temporary mutation | Observed result |
|---|---|---|
| 1 | `lib/spm_cache/spm/desc/base.rb`: `describe` rescues `RuntimeError` alongside `GeneralError` (simulates the guard's raise no longer propagating / an unguarded shell-out path) | Audit FAILED: `expected RuntimeError with message matching /unexpected real invocation: Sh\.run\("swift package describe/ but nothing was raised`. Reverted → 1 example, 0 failures. |
| 2 | `lib/spm_cache/core/sh.rb`: `capture_output` body replaced with `""` (no longer routes through `run`) | Audit FAILED on seam 2: `expected RuntimeError ... Sh\.run\("xcodebuild -list/ but nothing was raised`. Reverted → 1 example, 0 failures. |

**File check after fix:** `bundle exec rspec spec/fidelity_edge_matrix_spec.rb` → 12 examples, 0 failures.

### WR-02: The tier-1 tracer's "exactly one bucket" assertions were self-referential tautologies

**File:** `spec/fidelity_bucket_partition_spec.rb:288-308` (tier-1 fidelity legs tracer)
**Commit:** `5b54277` — `fix(10): WR-02 derive tier-1 tracer bucket membership from an independent source`
**Original problem:** `collected` was constructed as exactly `[status_read_from_sidecar]` by `observe_bucket` two lines earlier, so `expect(collected.length).to eq(1)` and `expect(collected.first).to eq(status_read_from_sidecar)` were true by construction regardless of any production behavior. The example's only real teeth were the `fetch("fidelity_status")` raise and the `pins` equality; the titled partition property was unenforced.

**Applied fix:** The bucket-membership assertion now derives from INDEPENDENT sources, and both partition arms are checked through the real classifier:

1. **Independent universe anchor:** the leg's identity (`"Alamofire"`) is asserted to be a member of the DECLARED input universe — the kitchen-sink fixture's package list read from disk (`fixture_packages_by_name.keys`) — never from the leg's own output. A fixture edit or leg rename orphaning the tracer from the declared universe fails before any bucket is counted.
2. **Sidecar teeth kept and strengthened:** `fetch("fidelity_status")` (raises on a dropped classification), plus new `be_a(String)` / `not_to be_empty` checks, plus the existing `pins` equality.
3. **Cross-surface partition with real teeth:** the identity's bucket set is collected from BOTH production surfaces that classify it — the sidecar status plus the compiled proxy's graph.json (aggregated through the ownership map, with the canary-observed cache-availability statuses filtered out — the same semantics as the SC2 partition). The graph surface is REQUIRED to classify the identity (`not_to be_empty`), then `partition_violations([identity], observations)` asserts BOTH arms (zero-bucket and double-bucket) with the file's established failure-message format. A double bucket is only detectable cross-surface, so the graph observation is what makes the double-bucket arm real: a production change emitting a second, non-availability status for this consumed, allowlisted package now fails the example.

Note: the cross-surface check needs the compiled `spm-cache-proxy` binary; the example mid-way `skip`s with the file's standard message when it is absent (the tier-1 assertions still execute first — same posture as the tier-3 legs and the SC2 example).

**Mutation proofs (temporary, reverted, never committed):**

| # | Temporary mutation | Observed result |
|---|---|---|
| 1 (dropped sidecar classification) | `lib/spm_cache/spm/build_pipeline.rb`: `write_provenance_sidecar` omits `fidelity_status` from the generated JSON | Tracer FAILED: `KeyError: key not found: "fidelity_status"`. Reverted → green. |
| 2 (dropped from declared universe) | `spec/fixtures/fidelity-kitchen-sink-lockfile.json`: package `"name": "Alamofire"` renamed to `"AlamofireRenamed"` | Tracer FAILED at the anchor: `expected ["AlamofireRenamed", ...] to include "Alamofire"`. Reverted → green. |
| 3 (double-bucket, cross-surface) | `--cache-only` allowlist input drops Alamofire (simulates a production allowlist/classification regression: the generator emits a second, non-availability status for the consumed package) | Tracer FAILED on the double-bucket arm: `TEST-02 double-bucket members: Alamofire (observed ["host-pinned", "excluded"])`. Reverted → green. |

**File check after fix:** `bundle exec rspec spec/fidelity_bucket_partition_spec.rb` → 14 examples, 0 failures.

## Verification Summary

- Targeted gates after each fix: `spec/fidelity_edge_matrix_spec.rb` 12/0; `spec/fidelity_bucket_partition_spec.rb` 14/0.
- Both files together: 23 examples, 0 failures.
- **Full suite (run once, after both fixes): 416 examples, 0 failures** — no regressions.
- Every inverse mutation was proven to fail the fixed example and then restored to green before commit; `git status` over `lib/` and `spec/` was clean of mutation residue at each commit.
- Process note: during the WR-02 mutation proofs, the mutation-3 revert (`git checkout --` on the spec file) also reverted the then-uncommitted WR-02 edit; the fix was re-applied byte-identically, mutation 3 was re-proven against the re-applied code with a targeted (non-git) revert, and only then committed.

## Remaining (out of scope)

The 7 INFO findings (IN-01 scaffolding duplication, IN-02 unescaped shell paths, IN-03 missing `:derived_data`, IN-04 optional libtool, IN-05 unasserted destination narrowing, IN-06 dead `status:` keyword, IN-07 meta-spec self-referential probes) are out of scope for this `critical_warning` pass and were deliberately left untouched.

---

_Fixed: 2026-08-29T17:04:20Z_
_Fixer: ZCode (gsd-code-fixer)_
_Iteration: 1_
