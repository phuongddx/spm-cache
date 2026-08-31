# Phase 10: Fidelity Regression Coverage - Context

**Gathered:** 2026-08-29
**Status:** Ready for planning

<domain>
## Phase Boundary

The fidelity contract is pinned by hermetic specs, so transitive-version drift cannot silently
return in a later release — the v0.3.0 lesson ("an implemented feature is not a done phase")
applied as executable coverage. Delivers TEST-01 (drift regression), TEST-02 (bucket-partition
coverage assertion), and TEST-03 (v0.2.x edge-class fixture matrix), all hermetic on the existing
`Core::Sh` / `Desc` / `Buildable` seams — no network, no real `xcodebuild`, green on the
Ruby 3.1–3.3 CI matrix.

</domain>

<decisions>
## Implementation Decisions

### Drift-Regression Spec (TEST-01 / SC1)
- Hermetic `Core::Sh`-stub harness — no network, no real `xcodebuild` (SC4). The real-binary
  SC1–SC3 coverage shipped in Phase 9's `gen_proxy_provenance_spec.rb` stays as-is, untouched.
- Both assertion directions: drift (realized ≠ pinned) MUST warn via `report_fidelity`, and
  agreeing pins must NOT warn (false-positive guard).
- Two drift-injection sources: provenance-sidecar disagreement (Phase 9 hit/miss semantics) and
  resolution read-back drift (Phase 8 `report_fidelity` semantics).
- New dedicated file: `spec/fidelity_drift_regression_spec.rb` — the regression contract gets
  its own named spec (the v0.3.0 lesson).

### Bucket-Partition Coverage Assertion (TEST-02 / SC2)
- Dedicated meta-spec: one synthetic all-classes project driven through the seams; assert every
  `Package.resolved` package lands in exactly ONE bucket — zero-bucket AND double-bucket both fail.
- Bucket enumeration drives the production classifier (single source of truth: Phase 8's
  `report_fidelity` classification); assert completeness + disjointness. No hand-maintained
  bucket list (it would drift).
- One kitchen-sink hermetic fixture containing all edge classes.
- Local/path packages (no `repositoryURL`) land in the excluded/local bucket — never silently
  absent. Extends the DIAG-01 precedent: excluded from the drift *comparison*, but still
  partitioned (SC2's zero-bucket arm demands it).

### Edge-Class Fixture Matrix (TEST-03 / SC3)
- New table-driven matrix spec enumerating all 8 classes: binary target (Class E), macro with a
  narrow `swift-syntax` pin, vendored `.xcodeproj`, plugin-only, transitive-only, resource
  bundle, private Clang shim, product≠target rename.
- Existing scattered edge-class specs stay untouched — SC3 says the matrix "passes unchanged";
  no churn, no migration.
- Inline builders via the proven Sh-stub pattern; JSON fixture files only for lockfile-shaped
  data (current convention: `spec/fixtures/*-lockfile.json`).
- Ruby-side only — the Swift companion keeps its own suite (36 tests); macro `swift-syntax`
  pinning is lockfile-driven and hermetically coverable from Ruby.
- Named `spec/fidelity_edge_matrix_spec.rb`.

### Hermeticity & CI (SC4)
- Explicit guard: the new specs' Sh stub allowlists commands and fails on unexpected real
  invocations — SC4 becomes an executable assertion, not a convention.
- Ruby 3.1–3.3 coverage relies on the existing `ci.yml` matrix; new specs use version-agnostic
  syntax (no 3.3-only constructs).
- Memoized shared kitchen-sink fixture via `let`; target ~2–3s total runtime for the new specs.
- Explicit TEST-01/02/03 IDs in `describe` strings for 1:1 verifier traceability.

### Claude's Discretion
None outstanding — all four areas accepted as recommended by the operator on 2026-08-29.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- Proven hermetic seam specs: `build_pipeline_spec.rb`, `build_pipeline_seeding_spec.rb`,
  `build_pipeline_provenance_spec.rb`, `resolved_graph_spec.rb`, `installer_use_fast_path_spec.rb`
- `gen_proxy_*` spec family + `spec/fixtures/*-lockfile.json` for lockfile-shaped fixture data
- Phase 8's `report_fidelity` classification (pinned / ignored / excluded / plugin-only /
  resolution-incompatible / not-graph-pinned) is the production classifier to drive
- Phase 9's `spec/gen_proxy_provenance_spec.rb` (real-binary SC1–SC3) — untouched reference

### Established Patterns
- Flat `spec/` naming: `<subject>_spec.rb`; `spec_helper.rb` requires `spm_cache/main`
- `Core::Sh` stubbing for swift/xcodebuild/etc.; RSpec built-in matchers only; no
  `spec/support/` directory today
- CI: `bundle exec rspec` on macos-15, Ruby matrix 3.1/3.2/3.3 (`.github/workflows/ci.yml`)

### Integration Points
- `SPM::BuildPipeline#report_fidelity` (`lib/spm_cache/spm/build_pipeline.rb`) — drift read-back
  + bucket classification
- `SPMCache::Core::Sh` — the seam every new spec stubs
- `Core::PackageResolved` / `SPM::ResolvedGraph` — host-graph pin sources

</code_context>

<specifics>
## Specific Ideas

No specific requirements beyond the accepted grey-area answers — open to standard approaches
consistent with the above.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>
