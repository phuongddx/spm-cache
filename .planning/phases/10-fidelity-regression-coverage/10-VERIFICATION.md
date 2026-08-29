---
phase: 10-fidelity-regression-coverage
verified: 2026-08-29T17:12:43Z
status: human_needed
score: 23/23 must-haves verified
behavior_unverified: 0
overrides_applied: 0
human_verification:
  - test: "Confirm the 10-03 FLAGGED ASSUMPTION on the resource-bundle edge-class shape (operator intent confirmation — plan-mandated, 'never auto-resolved')"
    expected: "Operator confirms (or re-points) the assumed meaning: TEST-03 class 6/8 = a describe-JSON target whose `resources` array parses to real paths and whose *.bundle is delivered into the assembled framework by the real copy_resource_bundles semantics (current-production-behavior baseline per RESEARCH A2). If a different v0.2.x incident shape was intended, the single class 6/8 example in spec/fidelity_edge_matrix_spec.rb is re-pointed (one-example edit by design)."
    why_human: "The plan's must_haves carry one probe category the deterministic classifier could not classify; the assumption is about operator intent for the v0.2.x incident shape, which no code inspection can resolve. Verifier safety judgment: SAFE to accept — the assumed meaning is the only reading consistent with TEST-03's requirement text ('resource bundle' listed as a class, matrix 'does not regress' = current-behavior baseline), RESEARCH A2 derived it explicitly, and the example asserts real parser + real copy semantics rather than a stub. All other 22 truths and every automated gate pass; nothing else awaits human action."
---

# Phase 10: Fidelity Regression Coverage Verification Report

**Phase Goal:** The fidelity contract is pinned by hermetic specs, so transitive-version drift cannot silently return in a later release — the v0.3.0 lesson ("an implemented feature is not a done phase") applied as executable coverage.
**Verified:** 2026-08-29T17:12:43Z
**Status:** human_needed
**Re-verification:** No — initial verification (no previous VERIFICATION.md existed)

## Goal Achievement

Test-only phase. Deliverables are four new files — `spec/fidelity_drift_regression_spec.rb` (314 lines), `spec/fidelity_bucket_partition_spec.rb` (547 lines), `spec/fidelity_edge_matrix_spec.rb` (623 lines), `spec/fixtures/fidelity-kitchen-sink-lockfile.json` (69 lines, 7 package entries) — with **zero production changes** (git range `2f6c885~1..HEAD` touches only these four files plus `.planning/` docs; `lib/` and `tools/` untouched).

All SUMMARY claims were re-derived from the codebase and re-executed, not trusted:

- Three spec files: **32 examples, 0 failures, 0 pending** (0.98s; compiled proxy binary present and exercised — no skip-guard fired).
- Full suite: **416 examples, 0 failures** (42.25s) — matches the claimed post-fix state exactly.
- **Fail-first sensitivity re-proven by this verifier with controlled, self-cleaning mutation probes** (temp copies, deleted after; `git status spec/` clean):
  - SC1: equalizing the drift injection (`bbb222` → `aaa111`) made `TEST-01/SC1` FAIL on the empty stderr match — the drift spec cannot pass a silently re-resolved pin.
  - SC2 double-bucket arm: dropping Alamofire from the `--cache-only` allowlist made the partition FAIL with `TEST-02 double-bucket members: Alamofire (observed ["host-pinned", "excluded"])` — byte-identical to the documented WR-02 mutation-3 output. The partition is not tautological.

### Observable Truths

Roadmap SC1–SC4 are the contract; plan must_haves add detail (8 + 9 + 6 = 23 truths). All verified; SC mappings noted.

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| SC1 | A regression spec fails if an out-of-range pin is silently re-resolved instead of being detected and reported | ✓ VERIFIED | `fidelity_drift_regression_spec.rb:61-98` — drift warns on stderr naming identity + both pins, stdout `resolution-incompatible`, sidecar pins record REALIZED value; passes green AND fails under this verifier's equalized-injection mutation probe; inverse (agreeing-pins) example proves the false-positive guard |
| SC2 | A coverage assertion fails if any package lands in zero or >1 bucket | ✓ VERIFIED | `fidelity_bucket_partition_spec.rb:430-510` — both arms in one example over the declared universe (fixture packages incl. local/path + pin identities); this verifier's allowlist mutation probe failed the double-bucket arm as designed; zero-bucket arm fail-first documented (PhantomKit run) and mechanically identical lookup |
| SC3 | The v0.2.x edge-class fixture matrix passes unchanged (all 8 classes) | ✓ VERIFIED | `fidelity_edge_matrix_spec.rb` — exactly one `it "TEST-03 class N/8…"` per class for all 1/8…8/8 (grep count == 1 each); all pass; existing scattered specs untouched (git range touches no pre-existing spec) |
| SC4 | Suite runs hermetically on Core::Sh/Desc/Buildable seams, green on Ruby 3.1–3.3 CI matrix | ✓ VERIFIED | Default-deny guards on BOTH `Core::Sh` entry points in all three spec files (`unexpected real invocation` ×2/×2/×9); SC4 audit example (post-WR-01) drives two REAL production shell-out seams (`Desc::Description#fetch`, `resolve_scheme_fallback`) and requires interception; tier-3 legs use `system()` on the local binary only; `.github/workflows/ci.yml` builds the proxy (`make proxy.build`) before RSpec on every 3.1/3.2/3.3 leg; local Ruby 3.2.3 green; syntax uses no construct newer than Ruby 3.0 |
| 10-01 drift direction (warn + stdout + sidecar realized pins) | ✓ VERIFIED | Spec lines 61-98, passing; output matchers + `File.read` of sidecar JSON |
| 10-01 false-positive guard | ✓ VERIFIED | Lines 136-144: `not_to receive(:warn)` + host-pinned sidecar, pins preserved |
| 10-01 pin-value precedence (revision > version; equal version-only ≠ drift) | ✓ VERIFIED | Lines 146-169, two passing examples |
| 10-01 sidecar-disagreement leg (disagree = miss, never silent hit; agree = hit; absent = miss) | ✓ VERIFIED | Lines 200-314, tier-3 real-binary, 3 passing examples via `statuses_from` on graph.json |
| 10-01 SC4 zero shell-outs on tier-1 | ✓ VERIFIED | Lines 51-56 default-deny stubs; examples pass (a surviving shell-out would raise) |
| 10-01 edge adjacency (equal pins merge, never false drift) | ✓ VERIFIED | Agreeing-pins example (136-144) |
| 10-01 edge empty (empty/missing realized → empty drifted set, host-pinned, never raises) | ✓ VERIFIED | Lines 171-189 (both `{}` and missing-file cases; documented rm_f deviation judged safe — asserted contract identical) |
| 10-01 edge ordering (per-identity assertions; no multi-warn ordering dependence) | ✓ VERIFIED | Single-identity examples; identity-keyed sidecar expectations |
| 10-02 completeness (every universe member in ≥1 bucket) | ✓ VERIFIED | SC2 example zero-bucket arm empty |
| 10-02 disjointness (no member in 2 buckets; per-package aggregation) | ✓ VERIFIED | Double-bucket arm + ownership-map aggregation (PrimeKit multi-product collapses to one) — mutation-proven by this verifier |
| 10-02 bucket derivation from observed output only | ✓ VERIFIED | Canary-derived availability filter (lines 250-274); `excluded_bucket_value`/`transitive_bucket_value` reuse observed values; no bracket literal contains ≥2 of the six bucket names (grep-proven) |
| 10-02 local/path entry lands in excluded bucket | ✓ VERIFIED | Fixture `"repositoryURL": ""` (exactly 1); SC2 input-side rule (lines 485-486); graph absence `be_nil` (line 400) |
| 10-02 transitive-only classified input-side; graph absence asserted explicitly | ✓ VERIFIED | Lines 378-389 (`be_nil`) + consumer-sidecar pin attestation (line 446) |
| 10-02 SC4 (tier-1 zero shell-outs; graph legs local binary only) | ✓ VERIFIED | Lines 62-67 guard; Shellwords-escaped `--ignore`/`--cache-only`; `system()` legs |
| 10-02 edge adjacency (multi-product merges by identity) | ✓ VERIFIED | Lines 403-420 |
| 10-02 edge empty (empty universe partitions; empty-pins → empty drifted set) | ✓ VERIFIED | Lines 514-532 |
| 10-02 edge ordering (identity-keyed lookups) | ✓ VERIFIED | Lines 534-545 probe + Hash-keyed code |
| 10-03 matrix (8 classes, one passing example each) | ✓ VERIFIED | grep `it "TEST-03 class N/8"` == 1 for all N; all green |
| 10-03 additive (no existing spec modified) | ✓ VERIFIED | Git: phase commits touch only the 4 new files |
| 10-03 macro class (swift-syntax narrow pin drift + agreeing directions) | ✓ VERIFIED | Lines 349-390, both directions in one example |
| 10-03 resource-bundle class (parser resolves resources array; real copy delivers bundle) | ✓ VERIFIED | Lines 512-587: real `Desc::Target` parser + real `copy_resource_bundles`; unless-exists stale semantics pinned. Driven via `send` against public `framework_path` — documented deviation for unwired dead code (3 pre-existing defects, logged in deferred-items.md); assertions land on real parser output and real copied files on disk |
| 10-03 Ruby 3.1 compatibility | ✓ VERIFIED | Local 3.2.3 green; full-file read shows no construct newer than Ruby 3.0; CI 3.1 leg builds proxy first |
| 10-03 FLAGGED ASSUMPTION (probe unclassified — surfaced for verify-time confirmation) | ✓ VERIFIED (as flagged-and-grounded; confirmation routed to Human Verification) | Assumption documented in plan + SUMMARY + spec header; fixture asserts exactly the assumed meaning; RESEARCH A2 provenance; single-example re-point if operator intends otherwise |

**Score:** 23/23 truths verified (0 present-but-behavior-unverified — every behavior-dependent truth has a passing behavioral test, and the two headline invariants were mutation-proven fail-first by this verifier)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `spec/fidelity_drift_regression_spec.rb` | TEST-01 named drift regression contract | ✓ VERIFIED | 314 lines, two describes (tier-1 + tier-3), 9 own examples green, `contains: TEST-01` satisfied (13 occurrences) |
| `spec/fidelity_bucket_partition_spec.rb` | TEST-02 partition meta-spec | ✓ VERIFIED | 547 lines, hybrid two-surface route, SC2 both arms, 11 own examples green |
| `spec/fidelity_edge_matrix_spec.rb` | TEST-03 eight-class matrix | ✓ VERIFIED | 623 lines, all 8 classes exactly once, SC4 audit, 9 own examples green |
| `spec/fixtures/fidelity-kitchen-sink-lockfile.json` | 7-class kitchen-sink fixture | ✓ VERIFIED | Valid JSON, 7 entries, exactly 1 empty `repositoryURL`, `FixtureApp.xcodeproj` key, fake URLs only |

All artifacts exist, are substantive, and are wired to production surfaces (Level 3): the specs ARE the wiring — they drive `BuildPipeline.run`/`report_fidelity`, the compiled `spm-cache-proxy` binary, `Desc::Target`, and `FrameworkSlice#copy_resource_bundles`.

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|----|--------|---------|
| fidelity_drift_regression_spec.rb | lib/spm_cache/spm/build_pipeline.rb | `BuildPipeline.run` → real `report_fidelity`; stdout/stderr + sidecar on disk; pattern `resolution-incompatible` | ✓ WIRED | `described_class.run(...)` at lines 85/130/…; sidecar `File.read("#{result}.provenance.json")` |
| fidelity_drift_regression_spec.rb | tools/spm-cache-proxy | compiled binary `gen-proxy` + graph.json statuses | ✓ WIRED | `run_gen_proxy` system() + `statuses_from` (lines 232-241); binary exercised (0 skips) |
| fidelity_bucket_partition_spec.rb | lib/spm_cache/spm/build_pipeline.rb | tier-1 legs read `fidelity_status` from sidecars | ✓ WIRED | `run_tier1_leg` → `SPMCache::SPM::BuildPipeline.run`; `fetch("fidelity_status")` |
| fidelity_bucket_partition_spec.rb | tools/spm-cache-proxy | gen-proxy `--ignore`/`--cache-only` + graph.json | ✓ WIRED | Shellwords-escaped flags; `package_statuses_from(output_dir)` |
| fidelity_edge_matrix_spec.rb | lib/spm_cache/spm/build_pipeline.rb | classes 1/2/3/7/8 on tier-1 seam | ✓ WIRED | `described_class.run` throughout; sidecar/shims/rename assertions on disk |
| fidelity_edge_matrix_spec.rb | lib/spm_cache/spm/xcframework/slice.rb | real `copy_resource_bundles` over a fabricated bundle | ✓ WIRED | `fresh_slice.send(:copy_resource_bundles)`; bundle lands inside framework path, contents intact |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|--------------|--------|--------------------|--------|
| drift spec | sidecar JSON | `write_provenance_sidecar` via real `report_fidelity` | Yes — parsed from disk, values asserted | ✓ FLOWING |
| drift spec | graph statuses | compiled proxy binary output `graph.json` | Yes — read from output dir | ✓ FLOWING |
| partition spec | bucket values | sidecar `fidelity_status` + graph.json statuses + canary observation | Yes — every recorded value read from production output | ✓ FLOWING |
| edge matrix | sidecar/shims/rename outcomes | real `BuildPipeline.run` paths | Yes — files read from disk | ✓ FLOWING |
| edge matrix | resource paths / copied bundle | real `Desc::Target` + real `copy_resource_bundles` | Yes — parser output + copied file bytes asserted | ✓ FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Three fidelity specs green, binary exercised | `bundle exec rspec spec/fidelity_{drift_regression,bucket_partition,edge_matrix}_spec.rb` | 32 examples, 0 failures, no pending | ✓ PASS |
| Full suite regression | `bundle exec rspec` | 416 examples, 0 failures | ✓ PASS |
| SC1 fail-first (mutation probe, self-cleaning) | sed-injection equalized on temp copy, run `--example "silently re-resolved"` | 1 example, 1 failure (empty stderr match); temp removed | ✓ PASS (fails as designed) |
| SC2 double-bucket fail-first (mutation probe, self-cleaning) | allowlist drops Alamofire on temp copy, run SC2 example | 1 failure: `double-bucket members: Alamofire (observed ["host-pinned", "excluded"])`; temp removed | ✓ PASS (fails as designed) |
| Fixture validity + local-entry uniqueness | `ruby -rjson` parse + `grep -c '"repositoryURL": ""'` | valid; exactly 1 | ✓ PASS |

### Probe Execution

No `scripts/*/tests/probe-*.sh` exist or are declared. The plans' "(probe)" truths are spec-embedded edge examples (adjacency/empty/ordering) — all executed green in the targeted run above; not shell probes.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| TEST-01 | 10-01 | Regression spec proves out-of-range pin detected and reported, not silently re-resolved | ✓ SATISFIED | Both directions, both injection sources, mutation-proven fail-first |
| TEST-02 | 10-02 | Coverage assertion: every Package.resolved package in exactly one bucket, none silently absent | ✓ SATISFIED | SC2 partition both arms over declared universe incl. local/path; double-bucket arm mutation-proven |
| TEST-03 | 10-03 | v0.2.x edge-class matrix does not regress (8 classes) | ✓ SATISFIED | All 8 classes green, additive, untouched existing specs; resource-bundle intent pending operator confirmation (see Human Verification) |

Orphan check: REQUIREMENTS.md maps exactly TEST-01/02/03 to Phase 10 — all three claimed by plans. No orphans.

### Prohibition Disposition (must_haves.prohibitions — negative checks)

All 7 prohibitions across the three plans verified as NOT-violated, with enforcement evidence gathered at verify time (git + code read; not merely asserted):

| Prohibition (abridged) | Evidence | Disposition |
|------------------------|----------|-------------|
| 10-01: no existing spec modified | git range `2f6c885~1..HEAD` touches only the 4 new files | VERIFIED (held) |
| 10-01: no drift assertions on double internals | assertions bind to output matchers + sidecar/graph JSON on disk | VERIFIED (held) |
| 10-02: no hand-typed bucket enumeration | no bracket literal with ≥2 bucket names; canary-derived vocabulary; observed values reused | VERIFIED (held) |
| 10-02: universe not derived from classifier output | universe = fixture packages + seed pin identities (line 495) | VERIFIED (held) |
| 10-02: no Ruby reimplementation of Swift classification | tier-3 legs run the compiled binary; statuses read from graph.json | VERIFIED (held) |
| 10-03: no modify/migrate existing edge specs | git evidence, byte-identical | VERIFIED (held) |
| 10-03: no networked/real-xcodebuild leg | default-deny guards armed in all three describes; SC4 audit drives real seams and requires interception | VERIFIED (held) |

### Test Quality Audit

| Test File | Linked Req | Active | Skipped | Circular | Assertion Level | Verdict |
|-----------|-----------|--------|---------|----------|-----------------|---------|
| fidelity_drift_regression_spec.rb | TEST-01 | 9 | 0 | 0 | Value/Behavioral (output matchers + parsed sidecar JSON + graph statuses) | OK |
| fidelity_bucket_partition_spec.rb | TEST-02 | 11 | 0 | 0 | Value/Behavioral (partition arms + observed vocabulary) | OK |
| fidelity_edge_matrix_spec.rb | TEST-03 | 9 | 0 | 0 | Value/Behavioral (file bytes, shims.json, hash_including, statuses) | OK |

- Disabled tests on requirements: 0 (the only `skip` literals are the documented binary-not-built guards; none fired — 0 pending in all runs).
- Circular patterns: 0 — every `File.write` in the specs writes fixture INPUTS (Package.resolved, lockfiles, cache sidecars, stub framework files); expected values are typed contract expectations, never generated from system output. Provenance: VALID (contract authored from the Phase 8/9 design, fail-first sensitivity proven by mutation).
- Assertion strength: value-level throughout; the drift/partition invariants additionally carry behavioral (multi-channel) assertions.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| fidelity_edge_matrix_spec.rb | 546-585 | `send` drives private `resource_paths`/`copy_resource_bundles` (FrameworkSlice is unwired dead code with 3 pre-existing defects) | ℹ️ Info | Documented deviation; semantics pinned for real; defects logged in deferred-items.md as out-of-scope product decision |
| fidelity_bucket_partition_spec.rb | 363-375 | tier-3 leg assertions type individual status literals (`eq("ignored")` etc.) | ℹ️ Info | Per-leg value expectations per plan Task 2; the PARTITION vocabulary itself is 100% observed (prohibition target) |
| all three files | — | helper scaffolding duplication (review IN-01), unescaped tier-3 path interpolation (IN-02), optional libtool (IN-04) | ℹ️ Info | Code-review info findings left out of scope by design; match pre-existing suite conventions; no teeth lost on SC1-SC4 |

Debt-marker gate: clean — no TBD/FIXME/XXX/TODO/HACK/PLACEHOLDER in any deliverable; no sleeps; no empty implementations.

### Decision Coverage

Machine gate: `check.decision-coverage-verify` → skipped ("no trackable decisions" — CONTEXT decisions are prose-form). Manual check: all four CONTEXT decision areas are honored in the shipped artifacts — hermetic Sh-stub harness + untouched Phase 9 real-binary coverage; both assertion directions + both injection sources; dedicated named spec files; kitchen-sink fixture + observed-only bucket vocabulary; local/path in excluded bucket; 8-class matrix alongside untouched scattered specs; executable default-deny guards (SC4 as assertion, not convention); version-agnostic syntax; TEST-01/02/03 IDs in describe strings (grep counts 13/17/16).

### Review Convergence

10-REVIEW.md (deep): 0 Critical / 2 Warning / 7 Info. Both warnings fixed (WR-01 → commit `ebb757a`, SC4 audit re-anchored to two real production seams; WR-02 → commit `5b54277`, tracer bucket membership derived from independent sources) with documented mutation proofs; fixes verified present in the current files and behaviorally re-proven by this verifier's SC2 probe. Post-fix full suite 416/0 — reproduced.

### Human Verification Required

### 1. Confirm the 10-03 FLAGGED ASSUMPTION (resource-bundle edge-class intent)

**Test:** Confirm (or re-point) the assumed meaning of the one probe category the deterministic classifier could not classify: TEST-03 class 6/8.
**Expected:** Operator accepts that class 6/8 pins the CURRENT production behavior — a describe-JSON `resources` array that parses to real paths, with the built `*.bundle` delivered into the assembled framework by the real `copy_resource_bundles` semantics — as the non-regression baseline (RESEARCH A2). If a different v0.2.x incident shape was intended, re-point the single class 6/8 example in `spec/fidelity_edge_matrix_spec.rb` (one-example edit by design).
**Why human:** The assumption concerns operator intent about a historical incident shape; no code inspection can resolve it. The plan mandates verify-time surfacing ("never auto-resolved"). Verifier safety judgment: SAFE — it is the only reading consistent with TEST-03's requirement text and the "does not regress = current-behavior baseline" semantics; the example asserts real parser and real copy behavior, not a stub.

(No other human items: this is a test-only infrastructure phase with no user-facing elements; every behavior-dependent truth carries behavioral evidence — passing specs plus this verifier's mutation probes — so `behavior_unverified` is 0.)

### Gaps Summary

None. All 23 must-have truths verified with behavioral evidence; all four artifacts exist, are substantive, and are wired to the production seams they pin; all key links wired with real data flowing; all three requirements satisfied; all 7 prohibitions held with evidence; no blockers, no debt markers, no disabled or circular tests; full suite green at 416/0; both headline invariants independently mutation-proven fail-first by this verifier. The single open item is the plan-mandated operator confirmation of the 10-03 flagged assumption, which routes to this checkpoint by design — hence `human_needed`, not `gaps_found`.

---

_Verified: 2026-08-29T17:12:43Z_
_Verifier: Claude (gsd-verifier)_
