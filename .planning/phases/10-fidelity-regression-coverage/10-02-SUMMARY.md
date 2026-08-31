---
phase: 10-fidelity-regression-coverage
plan: 02
subsystem: testing
tags: [rspec, fidelity, partition, regression-coverage, hermetic]
requires:
  - "Phase 8 report_fidelity (build_pipeline.rb)"
  - "Phase 9 provenance-aware BinariesCache.hit (ProxyGenerator.swift)"
  - "compiled spm-cache-proxy binary (make proxy.build)"
provides:
  - "spec/fidelity_bucket_partition_spec.rb — TEST-02 bucket-partition meta-spec (completeness + disjointness)"
  - "spec/fixtures/fidelity-kitchen-sink-lockfile.json — 7-class kitchen-sink lockfile fixture"
affects: []
tech-stack:
  added: []
  patterns:
    - "hybrid two-surface observation (tier-1 sidecars + tier-3 compiled-proxy graph.json)"
    - "canary-derived cache-availability filter (observed, never typed)"
    - "fixture-authored product->package ownership map for per-package identity aggregation"
key-files:
  created:
    - spec/fidelity_bucket_partition_spec.rb
    - spec/fixtures/fidelity-kitchen-sink-lockfile.json
  modified: []
decisions:
  - "Bucket vocabulary is 100% observed: cache-availability statuses (hit/missed) excluded via a canary package observed against empty and populated caches — no status name typed in the spec"
  - "Local/path entry joins the observed excluded bucket (six-bucket partition, no seventh bucket); transitive-only entry joins its consumer's observed pinned bucket, attested by the consumer's sidecar pins"
  - "Partition is per-package identity through an ownership map; the mixed hit+missed downgrade keeps multi-product packages at one bucket"
metrics:
  duration: 831s
  completed: 2026-08-29
actuals:
  tokens: 6491   # chars/4 over the two files actually created (estimate: 48000)
  tasks: 3
  commits: 3
status: complete
requirements_completed: [TEST-02]
---

# Phase 10 Plan 02: TEST-02 Bucket-Partition Coverage Meta-Spec Summary

One-liner: A hermetic meta-spec proving every package in a kitchen-sink universe lands in exactly ONE of the six fidelity buckets — sidecar statuses observed through the tier-1 BuildPipeline seam, graph statuses through the compiled proxy binary, both partition arms proven fail-first.

## What Was Built

**spec/fidelity_bucket_partition_spec.rb** (14 examples: 3 spec_helper + 11 own) in one outer `TEST-02` describe with nested groups sharing one flat helper set:

- **tier-1 fidelity legs** — `BuildPipeline.run` + real `report_fidelity` on the proven instance-double seam, under the default-deny `Core::Sh` guard (both entry points raise `unexpected real invocation`). Tracer records the pinned package's bucket from the sidecar's `fidelity_status` value at runtime.
- **tier-3 graph legs** — the compiled `spm-cache-proxy` binary over the kitchen-sink fixture with Shellwords-escaped `--ignore "Noise*"` / `--cache-only "Alamofire,NoiseInjector,PrimeKit"`: ignored / excluded / plugin each asserted from real graph.json output; transitive-only and local/path entries asserted absent (`be_nil`); the multi-product package's hit+downgraded-excluded statuses collapse under one identity.
- **the SC2 partition** — universe = fixture lockfile packages (local/path entry included) ∪ tier-1 resolved pin identities; classifier COLLECTS all matching buckets per member; both arms asserted in one example (`zero_bucket` empty AND `double_bucket` empty, failure messages naming identities and their observed buckets); observed vocabulary asserted ≥ 6 distinct values, all read from production output.
- **edge probes** — empty universe partitions without raising; empty-pins resolved file yields an empty drifted set and a single bucket; violation computation is identity-keyed (universe order changes nothing, both arms' mechanics proven on a synthetic store).

**spec/fixtures/fidelity-kitchen-sink-lockfile.json** — 7 entries under `FixtureApp.xcodeproj`: plain library (Alamofire), plugin-only (SwiftGenPlugin), ignore target (NoiseInjector), cache-only exclusion target (SideCartKit), multi-product (PrimeKit: PrimeCore + PrimeExtras), transitive-only (TransitiveCore), and the local/path entry (`"repositoryURL": ""` + `path_from_root`, exactly one such entry). Fake URLs/revisions only. The `dependencies` block is the consumed-set input: it deliberately excludes TransitiveCore, LocalDesignKit, and PrimeExtras.

### The two-surface observation route (RESEARCH Pitfall 1 correction, honored)

`report_fidelity` emits only host-pinned / resolution-incompatible / not-graph-pinned into sidecars; ignored / excluded / plugin exist only in ProxyGenerator's graph.json. The spec observes each bucket from its real producing surface. DriftyKit (drift leg) and CryptoSwift (vendored `.xcodeproj` leg) enter the universe via their tier-1 pin identities — they are not fixture entries, so no graph surface ever re-classifies them.

### How hit/missed stay out of the bucket vocabulary without typing names

A config-unconstrained canary package (no patterns, library product) is run against an empty cache and then against its own cached artifact with an agreeing sidecar pin; the two statuses it yields are observed to be the cache-availability statuses and are filtered from bucket collection. Every other graph status is decided by config or type and IS a bucket. No status string is typed anywhere in the spec; cache-sidecar seeding writes `pins`-only documents (the only key `BinariesCache.hit()` reads).

## Fail-First Mutation Proofs (Task 3, temporary, removed before commit)

1. **Zero-bucket arm (mutation a):** appended a phantom `PhantomKit` to the universe → run FAILED with `TEST-02 zero-bucket members (silently absent): PhantomKit (observed [])`. Mutation removed, run restored green.
2. **Double-bucket arm (mutation b):** artificially observed the excluded value onto NoiseInjector (already `ignored`) → run FAILED with `TEST-02 double-bucket members: NoiseInjector (observed ["ignored", "excluded"])`. Mutation removed, run restored green.

Final state: `bundle exec rspec spec/fidelity_bucket_partition_spec.rb` → **14 examples, 0 failures, 0 pending** (binary executed; skip-guard never triggered).

## Verification Results

- Targeted gate per task: `bundle exec rspec spec/fidelity_bucket_partition_spec.rb` green at every commit (Task 1: 4 examples → Task 2: 10 → Task 3: 14).
- Fixture: parses as JSON; `grep -c '"repositoryURL": ""'` == 1; 7 package entries.
- Source gates: `unexpected real invocation` ×2; `Shellwords` ×2; `to be_nil` ×2; both partition arms as two expectations in one example; universe built from `packages_by_name.keys + pinned_seed.keys + drifted_seed.keys + vendored_seed.keys`; local rule keyed on `repositoryURL.to_s.empty?`; **zero** lines matching two or more bucket names inside a bracket-style literal.
- `spec/fidelity_drift_regression_spec.rb` (10-01) untouched — `git diff` over it is empty.
- RuboCop: no project config exists; offense-class profile identical to the committed 10-01 sibling (default-config Style/Layout/Metrics noise only — same double-quote/trailing-comma/brace-block style). No new offense classes.
- Runtime: 10-02 alone ~0.35s (14 examples); **10-01 + 10-02 combined: 23 examples, ~1.27s** — within the 2–3s target with 10-03 still to come (its SUMMARY records the final combined figure).
- Full suite: intentionally NOT run in-task (plan note) — the serial wave-completion check belongs to the orchestrator after all Wave 1 plans merge.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `described_class` evaluated to nil inside `run_tier1_leg`**
- **Found during:** Task 3 verification (first partition run)
- **Issue:** Task 3 restructured the file into one string-described outer group (so the partition example can reach both surfaces' helpers); `run_tier1_leg` is defined on the outer group where `described_class` is nil → `NoMethodError: undefined method 'run' for nil`.
- **Fix:** replaced with the explicit `SPMCache::SPM::BuildPipeline.run` in the helper.
- **Files modified:** spec/fidelity_bucket_partition_spec.rb
- **Commit:** 1f4dddc

### Documented Deviations (no rule number — structural, planned in-action)

- **Task 3 restructured Tasks 1–2's two top-level describes into one outer describe with nested groups.** The partition example needs BOTH surfaces' helpers; RSpec methods don't cross sibling describes, and a helper-module file would violate the flat-spec convention. All committed example bodies are preserved verbatim; only nesting/indentation changed.
- **`write_sidecar` realized as `seed_cache_hit`** (pins-only cache-sidecar writer): `BinariesCache.hit()` reads only `pins`, and omitting the inert `fidelity_status` key keeps zero bucket-name literals in the spec. `write_lockfile` gained an optional `dependencies:` keyword for the canary's consumed set.
- **`state.update-progress` errored** ("Progress field not found in STATE.md") — frontmatter counts (completed_plans 13→14, percent 93) updated manually. A probe call to `state.record-metric` with mismatched flag meanings appended one malformed metrics row; removed immediately (the correct `Phase 10 P02 | 831s | 3 tasks | 2 files` row came from the first, properly-flagged call).

## Decisions Made

1. **Canary-derived cache-availability filter** — which graph statuses are not buckets is itself observed (canary vs empty/populated cache) instead of typed, honoring the CONTEXT lock that a hand-maintained vocabulary drifts. This is also what lets the pinned-leg package stay consumed-and-allowlisted in the graph run (its `missed` is filtered, so it never false-double-buckets against its sidecar status).
2. **Local/path = the observed excluded bucket** — no seventh bucket name; the rule reuses the status value the `--cache-only` inversion actually produced. Transitive-only = the consumer's observed pinned bucket value, with the consumer's sidecar `pins` asserted to carry the transitive pin (`include("TransitiveCore" => "ttt111")`).
3. **Drift/vendored legs enter the universe via pin identities, not fixture entries** — keeps their only observation surface the sidecar one (a fixture entry would also be graph-classified and force pattern choreography to avoid legitimate-looking doubles).

## Known Stubs

None — no production code was touched; every observed value comes from a real production code path (BuildPipeline.run/report_fidelity or the compiled ProxyGenerator).

## Threat Flags

None — no security-relevant surface beyond the plan's threat model. T-10-02 (no credentials in fixtures) and T-10-03 (Shellwords-escaped patterns, tmpdir/ROOT-derived paths) are mitigated as planned.

## TDD Gate Compliance

N/A — plan type is `execute` (not `tdd`); the fail-first mutation proofs above serve the equivalent gate for the partition assertion (red proven for both arms, committed green only).

## Self-Check: PASSED

- spec/fidelity_bucket_partition_spec.rb — FOUND
- spec/fixtures/fidelity-kitchen-sink-lockfile.json — FOUND
- ab8a0df / b209c27 / 1f4dddc — FOUND in git log
- spec/fidelity_drift_regression_spec.rb unmodified — VERIFIED (empty diff)
