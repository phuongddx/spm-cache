---
phase: 09-cache-identity-invalidation
plan: 01
subsystem: cache
tags: [swift, ruby, provenance, cache-invalidation, spm]

requires:
  - phase: 08-drift-read-back-fidelity-status-provenance
    provides: "BuildPipeline#report_fidelity, write_provenance_sidecar, and the <module>.xcframework.provenance.json sidecar schema (fidelity_status/pins/spm_cache_version/config/destinations) this plan reads and (for the not-graph-pinned case) rewrites"
provides:
  - "BinariesCache.hit(module:identity:currentPin:) -- provenance-aware cache-hit decision (was a bare fileExists check)"
  - "Lockfile.PackageRef.pinValue -- raw revision-over-version pin accessor shared with versionRequirement's existing precedence"
  - "BuildPipeline#report_fidelity's unless-seeded branch writes an explicit not-graph-pinned/empty-pins sidecar instead of deleting it"
  - "Real-binary end-to-end proof (spec/gen_proxy_provenance_spec.rb) of SC1/SC2/SC3/D-07"
affects: [09-02-cache-clean-orphan-sweep, 10-fidelity-regression-coverage]

actuals:
  tokens: 8300
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "Intersection-only pin comparison in hit() -- an identity absent from a sidecar's pins is never evidence of drift, only a present-and-disagreeing entry invalidates"
    - "Sidecar reads fail closed (fail-safe): any parse anomaly (missing file, malformed JSON, non-Hash root, missing pins key) is treated as a miss, never a trusted hit"

key-files:
  created:
    - tools/spm-cache-proxy/Tests/spm-cache-proxyTests/CacheTests.swift
    - spec/gen_proxy_provenance_spec.rb
  modified:
    - tools/spm-cache-proxy/Sources/Core/Cache.swift
    - tools/spm-cache-proxy/Sources/Core/Lockfile.swift
    - tools/spm-cache-proxy/Sources/Core/Generator/ProxyGenerator.swift
    - tools/spm-cache-proxy/Tests/spm-cache-proxyTests/LockfileTests.swift
    - tools/spm-cache-proxy/Tests/spm-cache-proxyTests/ProxyGeneratorTests.swift
    - lib/spm_cache/spm/build_pipeline.rb
    - spec/build_pipeline_provenance_spec.rb

key-decisions:
  - "Task 1's Pitfall-3 regression test (two-product package, wrong lookup key) was redesigned from the plan's literal text: the plan described swapping the sidecar's key to a product name as making both products report missed because the sidecar 'no longer contains ANY entry for the real identity' -- but that contradicts the intersection-only rule this same plan's must_haves establish (identity absent from pins = hit, never miss). Implemented instead as a disagreement-based regression guard: pins carries an AGREEING entry for the real identity (pkg.name) plus DISAGREEING entries for each product name, so a correct pkg.name lookup hits and a buggy product.name lookup would miss -- this actually distinguishes the two implementations, which the plan's literal text would not have."
  - "Left copy_prebuilt_binary_target's own separate rm_f(...provenance.json) untouched, per the plan's own <context> verification that report_fidelity always runs immediately after and supersedes it"

requirements-completed: [CACHE-02]

coverage:
  - id: D1
    description: "BinariesCache.hit(module:identity:currentPin:) is provenance-aware: absent/corrupt/malformed sidecar -> miss; disagreeing pin -> miss; agreeing pin, empty pins, or absent-identity -> hit"
    requirement: "CACHE-02"
    verification:
      - kind: unit
        ref: "tools/spm-cache-proxy/Tests/spm-cache-proxyTests/CacheTests.swift#BinariesCache.hit provenance-aware decision (9 tests)"
        status: pass
    human_judgment: false
  - id: D2
    description: "ProxyGenerator's sole hit() call site passes the package identity (pkg.name), never the product name, as the pins lookup key -- multi-product packages (e.g. realm-swift -> Realm + RealmSwift) cache correctly"
    requirement: "CACHE-02"
    verification:
      - kind: unit
        ref: "tools/spm-cache-proxy/Tests/spm-cache-proxyTests/ProxyGeneratorTests.swift#hitLooksUpByPackageIdentityNotProductName"
        status: pass
    human_judgment: false
  - id: D3
    description: "report_fidelity's unless-seeded branch writes an explicit not-graph-pinned sidecar with empty pins instead of deleting it, so Class E (vendored .xcodeproj) packages are never permanently defeated by the miss-on-no-provenance rule"
    requirement: "CACHE-02"
    verification:
      - kind: unit
        ref: "spec/build_pipeline_provenance_spec.rb#not-graph-pinned paths write an explicit sidecar with empty pins (3 tests)"
        status: pass
    human_judgment: false
  - id: D4
    description: "SC1 (no-provenance miss), SC2 (partial invalidation), SC3/D-08 (cross-project non-sharing on disagreeing pins), and D-07 (cross-project sharing on agreeing pins) all proven against the real compiled spm-cache-proxy binary"
    requirement: "CACHE-02"
    verification:
      - kind: integration
        ref: "spec/gen_proxy_provenance_spec.rb (5 tests)"
        status: pass
    human_judgment: false

duration: ~50min
completed: 2026-08-29
status: complete
---

# Phase 09 Plan 01: Cache Identity Invalidation Summary

**`BinariesCache.hit()` now requires a provenance sidecar's recorded pin to agree with the host's current pin before serving a cached xcframework, closing the gap where Phases 6-8's fidelity fix never reached existing users because the actual cache-hit decision was still a bare `fileExists` check.**

## Performance

- **Duration:** ~50 min
- **Completed:** 2026-08-29
- **Tasks:** 3 / 3
- **Files modified:** 9 (2 created, 7 modified)

## Accomplishments

- `BinariesCache.hit(module:)` (Swift) became `hit(module:identity:currentPin:)`: reads the
  `<module>.xcframework.provenance.json` sidecar and compares `pins[identity]` against the
  host's current pin, intersection-only (absence is never evidence of drift). Any parse
  anomaly (absent file, malformed JSON, non-Hash root, missing `pins` key) fails closed to a
  miss.
- Added `Lockfile.PackageRef.pinValue: String?` (revision-over-version raw accessor), factored
  from the same precedence rule `versionRequirement` already implements, and wired it plus
  `pkg.name` (never `product.name`) into `ProxyGenerator.swift`'s sole `hit()` call site.
- Fixed the Class E (vendored `.xcodeproj`) cache-defeat hazard flagged in RESEARCH.md: `report_fidelity`'s
  `unless seeded` branch now WRITES an explicit `not-graph-pinned` sidecar with empty `pins`
  instead of deleting it, so a totally-absent sidecar stays an unambiguous v0.3.0-upgrade
  signal without permanently miss-ing every vendored-project package.
  `copy_prebuilt_binary_target`'s own separate `rm_f` was deliberately left untouched (always
  superseded moments later by `report_fidelity`'s write; verified in the plan's own `<context>`).
- Proved SC1 (no-provenance upgrade miss), SC2 (partial invalidation within one run), SC3/D-08
  (cross-project non-sharing on disagreeing pins), and D-07 (cross-project sharing preserved
  on agreeing pins) end-to-end through the real compiled `spm-cache-proxy` binary
  (`spec/gen_proxy_provenance_spec.rb`), not a Ruby-side simulation.

## Task Commits

Each task was committed atomically:

1. **Task 1: End-to-end "cache identity" decision -- one Swift path only** - `8be8c72` (feat)
2. **Task 2: `report_fidelity`'s not-graph-pinned branch writes instead of deletes** - `cb286c5` (fix)
3. **Task 3: Real-binary end-to-end proof -- SC1, SC2, SC3 via the compiled spm-cache-proxy CLI** - `9cc0597` (test)

_Note: Task 1 was `type="tracer" tdd="true"` — implemented and verified in one commit against the full new test matrix, no separate RED/GREEN split, matching this plan's own task-type declaration (not a plan-level `type: tdd` phase)._

## Files Created/Modified

- `tools/spm-cache-proxy/Sources/Core/Cache.swift` - `hit()` signature change + provenance sidecar read/compare
- `tools/spm-cache-proxy/Sources/Core/Lockfile.swift` - new `PackageRef.pinValue` computed property
- `tools/spm-cache-proxy/Sources/Core/Generator/ProxyGenerator.swift` - updated `hit()` call site (`pkg.name`, `pkg.pinValue`)
- `tools/spm-cache-proxy/Tests/spm-cache-proxyTests/CacheTests.swift` - new file, full `hit()` decision matrix (9 tests)
- `tools/spm-cache-proxy/Tests/spm-cache-proxyTests/LockfileTests.swift` - new `PackageRefPinValueTests` suite (4 tests)
- `tools/spm-cache-proxy/Tests/spm-cache-proxyTests/ProxyGeneratorTests.swift` - Pitfall-3 regression test + provenance sidecars added to 3 pre-existing hit-path fixtures (zero-regression requirement)
- `lib/spm_cache/spm/build_pipeline.rb` - `report_fidelity`'s `unless seeded` branch writes instead of deletes
- `spec/build_pipeline_provenance_spec.rb` - rewrote the 2 not-graph-pinned-paths specs, added a `pins` shape assertion
- `spec/gen_proxy_provenance_spec.rb` - new file, real-binary SC1/SC2/SC3/D-07 integration coverage (5 tests)

## Decisions Made

- Redesigned the Task 1 Pitfall-3 regression test (see `key-decisions` in frontmatter): the
  plan's literal `<behavior>` text described a "missed" outcome from an absent-identity sidecar
  that contradicts the plan's own intersection-only `must_haves` (absence is never drift).
  Implemented the test with disagreement-based entries instead, which actually distinguishes a
  correct `pkg.name` lookup from a buggy `product.name` lookup — verified by running it against
  the real implementation (passes) and confirming the intersection-only invariant elsewhere
  (`CacheTests.swift`'s `absentIdentityInNonEmptyPinsIsHit`).
- Added provenance sidecars to 3 pre-existing `ProxyGeneratorTests.swift` fixtures
  (AppAuthCore, RealModule, Alamofire) that previously relied on bare file-existence hits — a
  necessary, in-scope fix since CACHE-02's own acceptance criteria requires the pre-existing
  Swift suite to stay green with zero regressions.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug in plan's own test spec] Corrected the Pitfall-3 regression test's expected outcome**
- **Found during:** Task 1
- **Issue:** The plan's `<behavior>` section for the two-product package Pitfall-3 guard specified
  that swapping the sidecar key to a product name would make both products report `missed`
  "because the sidecar no longer contains ANY entry for the real identity" — but per this same
  plan's must_haves and RESEARCH.md Pattern 1, an identity absent from `pins` is intersection-only
  safe and always a HIT, never a miss. A literal implementation of the plan's text would have
  asserted an invariant contrary to the very design being implemented.
- **Fix:** Rewrote the test to use disagreement (an agreeing entry under `pkg.name`, disagreeing
  entries under each product name) so it actually distinguishes a correct `pkg.name`-keyed lookup
  (hits) from a buggy `product.name`-keyed lookup (would miss) — preserving the test's real
  purpose (Pitfall 3 regression guard) without asserting a false invariant.
- **Files modified:** `tools/spm-cache-proxy/Tests/spm-cache-proxyTests/ProxyGeneratorTests.swift`
- **Verification:** `swift test` — 34/34 pass
- **Committed in:** `8be8c72` (Task 1 commit)

**2. [Rule 1 - Bug] Added provenance sidecars to 3 pre-existing hit-path test fixtures**
- **Found during:** Task 1 (post-implementation `swift test` run)
- **Issue:** `ProxyGeneratorTests.swift`'s pre-existing hit-path fixtures (AppAuthCore,
  RealModule, Alamofire) created only an xcframework directory with no provenance sidecar. Under
  the new provenance-aware `hit()`, these correctly began reporting `missed` instead of `hit`,
  breaking 3 pre-existing tests — a real regression against this plan's own zero-regression
  acceptance criterion, not a false positive.
- **Fix:** Added an empty-`pins` provenance sidecar (`fidelity_status`-agnostic, matches the
  not-graph-pinned steady state) next to each fixture's xcframework directory, restoring the
  intended hit outcome those tests assert.
- **Files modified:** `tools/spm-cache-proxy/Tests/spm-cache-proxyTests/ProxyGeneratorTests.swift`
- **Verification:** `swift test` — 34/34 pass (0 regressions)
- **Committed in:** `8be8c72` (Task 1 commit)

---

**Total deviations:** 2 auto-fixed (both Rule 1 — bug fixes required for correctness of the plan's own test coverage)
**Impact on plan:** No scope creep; both fixes were necessary to make the plan's own acceptance criteria (correct regression guard, zero pre-existing-suite regressions) actually hold.

## Issues Encountered

None beyond the deviations above.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- CACHE-02 is fully shipped: `hit()` is provenance-aware end-to-end, Class E caching is preserved,
  and cross-project identity isolation is proven against the real binary.
- Plan 02 (cache clean orphan sweep, CACHE-03) can proceed independently — no blockers from this
  plan's changes.
- Full suite state: Ruby `bundle exec rspec` — 374 examples, 0 failures (was 368 before this
  plan; +6 from `build_pipeline_provenance_spec.rb`'s +1 net and `gen_proxy_provenance_spec.rb`'s
  +5). Swift `swift test` (from `tools/spm-cache-proxy/`) — 34 tests in 7 suites, 0 failures (was
  ~20 before this plan; +14 new: 9 CacheTests, 4 LockfileTests PackageRefPinValueTests, 1
  ProxyGeneratorTests Pitfall-3 guard).

## Self-Check: PASSED

All created/modified files verified present on disk; all 4 commit hashes
(`8be8c72`, `cb286c5`, `9cc0597`, `823cb1e`) verified present in `git log --oneline --all`.

---
*Phase: 09-cache-identity-invalidation*
*Completed: 2026-08-29*
