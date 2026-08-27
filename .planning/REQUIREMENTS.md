# Requirements: spm-cache v0.4.0 — Build Fidelity & Release Automation

**Defined:** 2026-08-27
**Core Value:** Reduce Xcode clean build times by serving prebuilt SPM dependency binaries transparently, with automatic fallback to source compilation on cache miss — so a cache hit never breaks a build.

## v0.4.0 Requirements

### Graph Fidelity

- [x] **FID-01**: `spm-cache.lock` package `version`/`revision` reconcile from the host project's `Package.resolved` on every non-fast-path run, preserving enriched `products[]`
- [x] **FID-02**: Per-package builds are seeded with the host's resolved graph before the first `swift package describe`, so both metadata and binaries come from the host graph
- [ ] **FID-03**: Realized dependency versions are read back after resolution and compared against the intended pins; any drift is reported
- [ ] **FID-04**: A package whose declared requirements genuinely cannot satisfy the host graph falls back to source compilation with a distinct `resolution-incompatible` status — never a hard failure, and never masked by `ignore_build_errors`
- [x] **FID-05**: Packages that cannot be graph-pinned (vendored `.xcodeproj` packages, which ignore `Package.resolved` entirely) are reported as an explicit *not-graph-pinned* category rather than counted as successfully pinned
- [x] **FID-06**: The host `Package.resolved` locator resolves the *canonical* `project.xcworkspace/xcshareddata/swiftpm/Package.resolved` rather than whichever path `Dir.glob` yields first, so a stale nested copy cannot shadow the real host graph — added 2026-08-27 after Phase 6 research proved the current locator reads a stale nested file on the reference project, making FID-01 a no-op there

### Cache Identity

- [ ] **CACHE-01**: Each cached `.xcframework` records the graph provenance it was built against (realized pins, spm-cache version, config, destination set)
- [ ] **CACHE-02**: A cache hit requires recorded provenance to match the current host graph; **missing provenance counts as a miss**, producing a one-time rebuild that delivers the fix to existing users
- [ ] **CACHE-03**: `cache clean` sweeps provenance sidecars alongside the artifacts they describe

### Diagnostics

- [x] **DIAG-01**: A `doctor` check compares `spm-cache.lock` against the host `Package.resolved` statically, requiring no build
- [ ] **DIAG-02**: Per-package fidelity status (`host-pinned` / `resolution-incompatible` / `not-graph-pinned`) is surfaced in build output and `cache list`

### Regression Coverage

- [ ] **TEST-01**: A regression spec proves an out-of-range pin is detected and reported rather than silently re-resolved
- [ ] **TEST-02**: A coverage assertion proves every package in `Package.resolved` lands in exactly one bucket (pinned / ignored / excluded / plugin-only / resolution-incompatible / not-graph-pinned), with none silently absent
- [ ] **TEST-03**: The v0.2.x edge-class fixture matrix does not regress — binary target (Class E), macro with narrow `swift-syntax`, vendored `.xcodeproj`, plugin-only, transitive-only, resource bundle, private Clang shim, product≠target rename

### Performance

- [x] **PERF-01**: Cached-build wall-clock and disk usage show no regression versus v0.3.0 on the reference project — pin fan-out is a known risk and a regression is a milestone blocker, not a follow-up

### Release Automation

- [ ] **REL-04**: The tap workflow authenticates without a human-owned expiring credential
- [ ] **REL-05**: A tarball download failure fails the workflow loudly instead of hashing an error page into the formula
- [ ] **REL-06**: A commit or push failure fails the workflow loudly — the `|| exit 0` silent-success path is removed
- [ ] **REL-07**: Formula edits are anchored and post-condition-checked, so a zero-match or over-broad substitution cannot pass silently
- [ ] **REL-08**: Post-publish verification installs the published formula and asserts `spm-cache --version` matches the released tag
- [ ] **REL-09**: `workflow_dispatch` with a `tag` input allows retrying a transient failure without re-publishing a release

## Future Requirements

Deferred beyond v0.4.0. Tracked but not in this roadmap.

### Cache

- **CACHE-F1**: Content-addressed cache keys (Merkle over resolved versions) — v0.5
- **CACHE-F2**: Per-graph partitioning of `~/.spm-cache` — v0.5; detection via provenance is the v0.4.0 floor
- **CACHE-F3**: Move hit/miss adjudication into the Swift `BinariesCache` so `gen-proxy` cannot serve a stale binary for one cycle — v0.5

### Visualization

- **VIZ-F1**: Real dependency edges in the cachemap (every `GraphEntry` is constructed `dependencies: []` today — nodes render, no edges)

### Performance

- **PERF-F1**: Parallelize the build loop — currently a correctness-class data race over shared checkouts

## Out of Scope

Explicitly excluded from v0.4.0. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| RubyGems publication (`gem push`) | User decision 2026-08-27; Homebrew builds from the GitHub release tarball and needs no gem on RubyGems |
| `gem install spm-cache` verification | Depends on RubyGems publication; deferred with it |
| GitHub Action + its own-repo smoke CI | The action's `gem install spm-cache` step cannot succeed while the gem is unpublished; broken-window #2 waived, not closed |
| `-onlyUsePackageVersionsFromResolvedFile` as default | Hard-fails on missing pins, and the umbrella systematically omits packages' test-only dependencies — would break every package with an external test dep. Kept as opt-in strict mode only |
| Building through the umbrella workspace | Destroys three field-proven invariants (per-checkout DerivedData isolation, per-invocation library-evolution flags, vendored-`.xcodeproj` handling); re-litigates ~12 documented field bugs |
| Hard-failing on a fidelity violation | Contradicts Core Value; all four comparable tools degrade to source |
| SwiftPM mirrors / `--replace-scm-with-registry` | URL→URL only; carry no version information |
| Re-minting a classic PAT for the tap | Restores the status quo including the one-year auto-deletion that caused the outage |
| CocoaPods support | spm-cache is SPM-only |
| App-target caching | Only SPM dependencies are cached |
| Selective/partial caching, mergeable libraries | Deferred parity features; unrelated to this cycle's correctness focus |
| Non-macOS platforms | Relies on the macOS/Xcode toolchain |

## Decisions Recorded

| Decision | Rationale | Date |
|----------|-----------|------|
| Fidelity violation → warn + source fallback, never hard-fail | Derived from Core Value; corroborated by all four comparable tools | 2026-08-27 |
| Missing provenance ⇒ cache miss (one-time full rebuild) | The only option that actually delivers the fix to existing users; grandfathering keeps serving artifacts built against unverified graphs | 2026-08-27 |
| `-onlyUsePackageVersionsFromResolvedFile` not enabled by default | Missing-pin hard failure is structural and broad (test-only deps); detection moves to post-resolve read-back instead | 2026-08-27 |
| `~/.spm-cache` partitioning stays v0.5 | Consistent with content-addressing deferral; provenance detection is the v0.4.0 floor | 2026-08-27 |
| Local packages' own remote dependencies get host-pinned by the same rule | No known local-package workflow depends on independent resolution | 2026-08-27 |
| Canonical-path preference added to Phase 6 as FID-06 | Phase 6 research proved `Dir.glob(...).find` returns a stale nested `Package.resolved` on the reference project (nested `S…` sorts before canonical `p…`), so reconciliation alone would pass criterion 1 vacuously — both sides agreeing on the wrong file | 2026-08-27 |
| Reconciler drop-rule keyed on DiffDetector's union, not resolved pins alone | `Package.resolved` never lists local/path packages, so a pins-only drop rule would delete every `path_from_root` package (`diff_detector.rb:145` union is resolved ∪ pbxproj refs) | 2026-08-27 |
| Macro-package pinning exclusion deferred to measurement | Contingent on the blast-radius count; decide with data, not in advance | 2026-08-27 |

## Open Measurements

These block design decisions inside phases and must be measured, not assumed.

| # | Measurement | Runs in | Blocks |
|---|-------------|---------|--------|
| M1 | Reproduce the stale-transitive release build on the real 59–70 package project; attribute relative contribution of the lockfile chain vs isolated re-resolution | Phase 6 (first work) | Phase 7 design lock |
| M2 | Report-only pinning run: count packages reporting `resolution-incompatible` | Phase 7 (produced) | Phase 8 policy commitment; rescope trigger if high |
| M3 | Wall-clock and disk delta from pin-list fan-out (verbatim superset vs minimal closure) | Phase 7 | PERF-01; verbatim-vs-closure narrowing decision |
| M4 | Does xcodebuild write back realized versions on the `run_with_scheme` / vendored-`.xcodeproj` path? | Phase 7 (early probe) | Sole falsifier of the no-flag design |

## Traceability

Which phases cover which requirements. Populated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| FID-01 | Phase 6 | Complete |
| FID-02 | Phase 7 | Complete |
| FID-03 | Phase 8 | Pending |
| FID-04 | Phase 8 | Pending |
| FID-05 | Phase 7 | Complete |
| FID-06 | Phase 6 | Complete |
| CACHE-01 | Phase 8 | Pending |
| CACHE-02 | Phase 9 | Pending |
| CACHE-03 | Phase 9 | Pending |
| DIAG-01 | Phase 6 | Complete |
| DIAG-02 | Phase 8 | Pending |
| TEST-01 | Phase 10 | Pending |
| TEST-02 | Phase 10 | Pending |
| TEST-03 | Phase 10 | Pending |
| PERF-01 | Phase 7 | Complete |
| REL-04 | Phase 11 | Pending |
| REL-05 | Phase 11 | Pending |
| REL-06 | Phase 11 | Pending |
| REL-07 | Phase 11 | Pending |
| REL-08 | Phase 11 | Pending |
| REL-09 | Phase 11 | Pending |

**Coverage:**

- v0.4.0 requirements: 21 total
- Mapped to phases: 21 ✓
- Unmapped: 0 — every requirement maps to exactly one phase (no orphans, no duplicates)

| Phase | Requirements | Count |
|-------|--------------|-------|
| Phase 6 — Graph Authority: Lockfile Reconciliation | FID-01, DIAG-01 | 2 |
| Phase 7 — Host-Faithful Checkout Seeding | FID-02, FID-05, PERF-01 | 3 |
| Phase 8 — Drift Read-Back, Fidelity Status & Provenance | FID-03, FID-04, CACHE-01, DIAG-02 | 4 |
| Phase 9 — Cache Identity & Invalidation | CACHE-02, CACHE-03 | 2 |
| Phase 10 — Fidelity Regression Coverage | TEST-01, TEST-02, TEST-03 | 3 |
| Phase 11 — Homebrew Release Automation | REL-04..REL-09 | 6 |

---
*Requirements defined: 2026-08-27*
*Last updated: 2026-08-27 after roadmap creation (Phases 6–11)*
