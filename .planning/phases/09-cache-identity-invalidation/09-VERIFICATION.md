---
phase: 09-cache-identity-invalidation
verified: 2026-08-29T13:29:23Z
status: passed
score: 4/5 must-haves verified
behavior_unverified: 1
overrides_applied: 0
human_verification:

  - test: "Follow the reproduction procedure recorded in 09-SC5-VERIFICATION.md against the real reference project (/Users/ddphuong/Projects/next-labs/stress-ai/ios-stress-app/StressMonitor): cold-build, mark one cached package's linked framework content in DerivedData, force a pin-disagreement miss + rebuild that one package, rebuild the app WITHOUT clearing DerivedData, re-check the marker."
    expected: "The app's rebuilt binary reflects the NEW xcframework's content (marker changes) -- Xcode's incremental build noticed the in-place content change on its own, with no manual DerivedData clear required."
    why_human: "Requires the real external reference project, a real Xcode build, and human judgment comparing binary/symbol content across two DerivedData states -- not reproducible by an autonomous agent in this environment (no Xcode GUI, no reference-project repo access)."
behavior_unverified_items:

  - truth: "A rebuild triggered by the new invalidation mechanism does not leave Xcode's DerivedData serving the PREVIOUS build's linked module/resource content once the app is rebuilt without a manual DerivedData clear (SC5, ROADMAP success criterion 5)"
    test: "Run the 5-step procedure in 09-SC5-VERIFICATION.md: cold-build, mark linked framework content, force a pin-disagreement miss + rebuild one package, rebuild app without clearing DerivedData, re-check marker"
    expected: "Post-rebuild marker differs from pre-rebuild marker, proving Xcode relinked the new artifact content without a manual DerivedData purge"
    why_human: "This is a real-Xcode-build state-transition/staleness invariant across two DerivedData states on an external reference project -- grep/presence checks cannot observe linker/build-system behavior, and no automated test in this repo exercises it (by design, per 09-CONTEXT.md's D-11 -- spm-cache does not touch DerivedData, so this can only be proven empirically against real Xcode)"
---

# Phase 9: Cache Identity & Invalidation Verification Report

**Phase Goal:** Users on an existing cache actually receive the fidelity fix — an artifact built against a graph that no longer matches the host's is treated as a miss and rebuilt, and two projects on different versions stop sharing one binary.
**Verified:** 2026-08-29T13:29:23Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

Sourced from ROADMAP.md Phase 9 success criteria (the roadmap contract), cross-referenced against
09-01/09-02/09-03 PLAN.md `must_haves.truths`.

| # | Truth | Status | Evidence |
| --- | --- | --- | --- |
| 1 (SC1) | Upgrading from v0.3.0 without clearing `~/.spm-cache` produces a rebuild — an artifact with no provenance is a miss, not a hit — via BOTH `spm-cache build` and the default `spm-cache`/`spm-cache use` command | ✓ VERIFIED | `Cache.swift:28-48` `hit()` returns `nil` when no sidecar file exists at all (unconditional miss). Unit: `CacheTests.swift` "no sidecar file at all -> miss (D-01/SC1 upgrade scenario)" — passes. Real-binary: `spec/gen_proxy_provenance_spec.rb` "SC1: an xcframework with NO sidecar at all for a lockfile-pinned package is reported missed" — passes against the compiled `spm-cache-proxy` CLI. Default-command closure: `Installer::Use#fast_path?` gained a 4th guard (`current_spm_cache_version?`, `use.rb:79-101`) forcing a full regen after any spm-cache version bump even with an unchanged host graph; `spec/installer_use_fast_path_spec.rb` mismatched/matching-stamp tests both pass. |
| 2 (SC2) | Changing a transitive version in the host `Package.resolved` invalidates only the artifacts whose recorded pins actually disagree; an unrelated bump elsewhere does not empty the cache | ✓ VERIFIED | `Cache.swift:39-46` compares only `pins[identity]` against `currentPin`, intersection-only (absence is never drift). Unit: `CacheTests.swift` "disagreeing pin -> miss (D-02)" / "agreeing pin -> hit" / "absent-identity in non-empty pins -> hit". Real-binary: `spec/gen_proxy_provenance_spec.rb` "SC2: within ONE run, the agreeing package hits and the disagreeing package misses (partial invalidation)" — passes. |
| 3 (SC3) | Two projects resolving the same package at different versions no longer serve each other's artifact | ✓ VERIFIED | Real-binary: `spec/gen_proxy_provenance_spec.rb` "SC3/D-08: two projects sharing one cache dir, pinning the SAME identity at DIFFERENT versions, do not share the artifact" AND "D-07: two projects pinning the SAME version ... continue sharing the one cached artifact" (regression guard for the shared-cache value prop) — both pass against the real compiled binary, one shared cache dir, two separate lockfiles. |
| 4 (SC4) | `cache clean` leaves no orphaned provenance sidecars behind | ✓ VERIFIED | `Command::Cache::Clean#sweep_orphaned_sidecars` (`clean.rb:66-79`) globs `*.{provenance,shims}.json`, strips the `.xcframework.(provenance\|shims).json` suffix, and removes any sidecar with no matching `.xcframework` directory — across debug+release, bare/`--all`/named-target invocations, additive to (never widening) the existing removal branch. `spec/command_cache_clean_spec.rb` (6 examples: orphan removal x2 suffixes, paired-sidecar survival [D-10], `--dry` reporting, named-target same-invocation sweep, both configs) — all pass. |
| 5 (SC5) | A rebuild triggered by a graph change does not reuse DerivedData modules or resource bundles produced against the previous graph | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | `09-SC5-VERIFICATION.md` exists (179 lines), contains a concrete, runnable 5-step reproduction procedure (cold-build, mark linked-framework content, force a pin-disagreement miss + rebuild via Plan 01's real `hit()` mechanism, rebuild host app in Xcode without clearing DerivedData, re-check marker) against the real reference project. Its `## Outcome` section is deliberately unfilled — per this plan's own design (`09-03-PLAN.md`, `human_verify_mode: end-of-phase`), the PASS/FAIL is queued for human execution, not yet run. No automated test in this repo can exercise real Xcode/DerivedData linking behavior — see `behavior_unverified_items`. |

**Score:** 4/5 truths verified (1 present, behavior-unverified — awaiting human execution of the SC5 runbook)

### Required Artifacts

| Artifact | Expected | Status | Details |
| --- | --- | --- | --- |
| `tools/spm-cache-proxy/Sources/Core/Cache.swift` | `hit(module:identity:currentPin:)` provenance-aware decision point | ✓ VERIFIED | Signature changed from `hit(module:) -> URL?` to `hit(module:identity:currentPin:) -> URL?`; reads `<module>.xcframework.provenance.json`, guards `pins` key, fail-closed on any parse anomaly. |
| `tools/spm-cache-proxy/Sources/Core/Lockfile.swift` | `PackageRef.pinValue` raw revision-over-version accessor | ✓ VERIFIED | `pinValue` computed property present (lines ~131+), mirrors `versionRequirement`'s exact precedence shape. 4 `PackageRefPinValueTests` pass. |
| `tools/spm-cache-proxy/Sources/Core/Generator/ProxyGenerator.swift` | Sole `hit()` call site passes `pkg.name`/`pkg.pinValue`, never `product.name` | ✓ VERIFIED | Line ~119: `cache.hit(module: product.name, identity: pkg.name ?? product.name, currentPin: pkg.pinValue)`. Pitfall-3 regression test passes. |
| `tools/spm-cache-proxy/Tests/spm-cache-proxyTests/CacheTests.swift` | Full hit()/miss decision matrix, real fixtures | ✓ VERIFIED | New file, 9 tests, all pass (`swift test`: 36 tests / 7 suites, 0 failures). |
| `lib/spm_cache/spm/build_pipeline.rb` | `report_fidelity`'s unless-seeded branch writes a not-graph-pinned sidecar instead of deleting it | ✓ VERIFIED | `unless seeded` branch (`build_pipeline.rb:103-136`) calls `existing_sidecar_pins` then either preserves prior host-pinned pins (WR-03/CR-01 fix) or writes `not-graph-pinned`/`pins: {}` — never a bare `rm_f` anymore. |
| `spec/gen_proxy_provenance_spec.rb` | Real-binary end-to-end proof of SC1/SC2/SC3 | ✓ VERIFIED | New file, 8 examples (5 scenario + 3 SPMCache smoke), all pass against `tools/spm-cache-proxy/.build/release/spm-cache-proxy` (binary confirmed present on disk, not skipped). |
| `lib/spm_cache/installer/use.rb` | `fast_path?` gains a `spm_cache_version` stamp check | ✓ VERIFIED | `current_spm_cache_version?` reads a throwaway `Core::Lockfile` instance, guards `fast_path?`'s 4th condition. |
| `lib/spm_cache/command/cache/clean.rb` | `sweep_orphaned_sidecars` — new orphan sidecar sweep, runs unconditionally | ✓ VERIFIED | Present, wired into `run`'s per-config loop after the existing removal branch. |
| `spec/command_cache_clean_spec.rb` | CACHE-03 regression coverage (new file) | ✓ VERIFIED | New file, 6 examples, all pass. |
| `.planning/phases/09-cache-identity-invalidation/09-SC5-VERIFICATION.md` | Empirical runbook + recorded outcome for SC5 | ⚠️ PARTIAL | File exists (179 lines, well over `min_lines: 20`), contains a concrete runnable procedure — but per its own design the `## Outcome` PASS/FAIL is deliberately left unfilled, awaiting human execution (not a defect; this is the documented end-of-phase human-check hand-off). |

### Key Link Verification

| From | To | Via | Status | Details |
| --- | --- | --- | --- | --- |
| `ProxyGenerator.swift:119` | `Cache.swift` `hit(module:identity:currentPin:)` | Direct call, passes `pkg.name` (never `product.name`) as identity, `pkg.pinValue` as currentPin | ✓ WIRED | Confirmed by direct source read; regression-guarded by the two-product Pitfall-3 test. |
| `hit()` | `<module>.xcframework.provenance.json` sidecar | `Data(contentsOf:)` + `JSONSerialization` read, `pins[identity]` comparison | ✓ WIRED | Confirmed by source read + 9 passing `CacheTests.swift` cases covering every branch (absent file, malformed JSON, non-Hash root, missing `pins` key, empty pins, agreeing/disagreeing/absent identity). |
| `BuildPipeline.report_fidelity`'s `unless seeded` branch | `write_provenance_sidecar(status: "not-graph-pinned", pins: {})` | Direct call, replacing the old `FileUtils.rm_f` | ✓ WIRED | Confirmed by source read (`build_pipeline.rb:130-136`) + passing `build_pipeline_provenance_spec.rb` rewritten tests. |
| `Installer::Use#fast_path?` | `current_spm_cache_version?` | 4th guard clause, throwaway `Core::Lockfile` read (never mutates `@lockfile`) | ✓ WIRED | Confirmed by source read (`use.rb:79-101`) + passing fast-path spec (mismatched stamp forces regen, matching stamp preserves fast path). |
| `Command::Cache::Clean#run` | `sweep_orphaned_sidecars(cache_dir)` | Called inside the existing `["debug","release"].each` loop, after the removal branch | ✓ WIRED | Confirmed by source read (`clean.rb:37`) + passing `command_cache_clean_spec.rb` (named-target same-invocation sweep test specifically proves the after-branch placement). |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| --- | --- | --- | --- |
| Swift unit suite (Cache/Lockfile/ProxyGenerator) is green | `cd tools/spm-cache-proxy && swift test` | 36 tests in 7 suites, 0 failures | ✓ PASS |
| Full Ruby suite is green | `bundle exec rspec` | 387 examples, 0 failures | ✓ PASS |
| Real-binary provenance scenarios (SC1/SC2/SC3/D-07/Class-E) pass against the compiled CLI, not a stub | `bundle exec rspec spec/gen_proxy_provenance_spec.rb --format documentation` | 8 examples, 0 failures; binary confirmed present at `tools/spm-cache-proxy/.build/release/spm-cache-proxy` | ✓ PASS |
| Fast-path version gate + cache clean orphan sweep specs pass | `bundle exec rspec spec/installer_use_fast_path_spec.rb spec/command_cache_clean_spec.rb spec/build_pipeline_provenance_spec.rb` | 38 examples, 0 failures | ✓ PASS |
| SC5 empirical DerivedData check | (requires real Xcode + external reference project) | N/A | ? SKIP — routed to human verification |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
| --- | --- | --- | --- | --- |
| CACHE-02 | 09-01, 09-02 | A cache hit requires recorded provenance to match the current host graph; missing provenance counts as a miss | ✓ SATISFIED | `Cache.swift` `hit()` provenance-aware end-to-end (Swift), reachable via both `spm-cache build` and the default `spm-cache use` (fast-path version gate). Real-binary + unit coverage passing. |
| CACHE-03 | 09-02 | `cache clean` sweeps provenance sidecars alongside the artifacts they describe | ✓ SATISFIED | `Command::Cache::Clean#sweep_orphaned_sidecars`, 6 passing regression tests, never touches a paired sidecar (D-10). |

No orphaned requirements — REQUIREMENTS.md's traceability table maps only CACHE-02/CACHE-03 to Phase 9, and both are claimed and covered.

Note: `.planning/REQUIREMENTS.md`'s checkboxes for CACHE-02/CACHE-03 and its traceability table
("Pending") have not yet been flipped to reflect this phase's completion — this is expected
end-of-phase bookkeeping (typically done at ship/milestone-complete time), not a functional gap.

### Anti-Patterns Found

None. Scanned all 6 primary modified/created source files
(`Cache.swift`, `Lockfile.swift`, `ProxyGenerator.swift`, `build_pipeline.rb`, `clean.rb`,
`use.rb`) for `TBD|FIXME|XXX|TODO|HACK|PLACEHOLDER` — zero matches. Code review
(`09-REVIEW.md`, deep, 13 files) found 0 critical, 0 warning findings after 3 auto-fix
iterations; 2 info-tier items remain, both explicitly low-severity, fail-closed, and
documented as intentionally out of scope (`IN-01`: fast-path lockfile key has no legacy
stem-match fallback — fails closed to slower regen, not a correctness bug; `IN-02`: orphan
sweep's suffix-strip regex would misclassify a non-`.xcframework.`-segmented sidecar filename,
confirmed unreachable since every current sidecar producer follows that naming convention).

### Human Verification Required

> **Update 2026-08-29T14:24:56Z:** SC5 executed by the operator — **PASS**. Recorded in
> `09-UAT.md` (test 1) and `09-SC5-VERIFICATION.md` `## Outcome`. Status canonicalized to
> `passed` via `/gsd-verify-work 9`.

### 1. SC5 — DerivedData staleness on in-place xcframework rebuild

**Test:** Follow the reproduction procedure in `09-SC5-VERIFICATION.md` against the real reference
project (`/Users/ddphuong/Projects/next-labs/stress-ai/ios-stress-app/StressMonitor`): cold-build via
`spm-cache build`, record a marker (mtime/hash/`otool -L`/`nm` symbol hash) for one cached package's
linked framework inside the app's DerivedData, force a pin-disagreement `missed` for that one
package (via sidecar hand-edit or `Package.resolved` pin bump) and rebuild it through spm-cache,
rebuild the HOST APP in Xcode again WITHOUT clearing DerivedData, and re-check the same marker.
**Expected:** The re-checked marker differs from the original — the app's rebuilt binary reflects
the NEW xcframework's content, proving Xcode's incremental build noticed the in-place content
change on its own, with no manual DerivedData clear required.
**Why human:** Requires the real external reference project, a real Xcode/`xcodebuild` build, and
human judgment comparing binary/symbol content across two DerivedData states — no Xcode GUI or
reference-project repository access exists in this autonomous verification environment. This is
also this phase's own design: `09-03-PLAN.md` deliberately deferred this check to
`human_verify_mode: end-of-phase` rather than a mid-execution checkpoint.

### Gaps Summary

No gaps. All four automatable roadmap success criteria (SC1-SC4) are verified against both unit
coverage (Swift + Ruby) and a real-binary end-to-end integration spec, with zero regressions across
the full test suite (387 Ruby examples, 36 Swift tests) and a clean deep code review (0
critical/warning findings after 3 convergence iterations). The one remaining item, SC5, is not a
gap — it is a documented, correctly-scoped empirical check that requires a human with Xcode and the
real external reference project to execute; the runbook itself is complete, concrete, and ready to
run. Phase 9 cannot be marked fully `passed` until that human check is executed and its outcome
recorded in `09-SC5-VERIFICATION.md`'s `## Outcome` section.

---

*Verified: 2026-08-29T13:29:23Z*
*Verifier: Claude (gsd-verifier)*
