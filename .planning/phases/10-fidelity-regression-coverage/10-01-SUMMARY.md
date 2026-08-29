---
phase: 10-fidelity-regression-coverage
plan: 01
subsystem: testing
tags: [rspec, regression, provenance, drift, hermetic, spm]

# Dependency graph
requires:
  - phase: 08-drift-readback-fidelity-status-provenance
    provides: BuildPipeline#report_fidelity drift read-back + provenance sidecar write
  - phase: 09-cache-identity-invalidation
    provides: provenance-aware BinariesCache.hit() gen-proxy miss semantics
provides:
  - Named TEST-01 drift regression contract (spec/fidelity_drift_regression_spec.rb)
  - Executable SC4 default-deny hermeticity guard pattern (both Core::Sh entry points)
  - Fail-first mutation proofs for both drift-injection sources
affects: [phase-10-verification, phase-11-release-automation]

# Actuals (#2632) — pairs with the plan's estimate to calibrate future estimates.
actuals:
  tokens: 3400   # chars/4 over the realized spec diff (13604 chars, 314 insertions)
  tasks: 3
  commits: 4      # 3 task commits + 1 docs close-out

# Tech tracking
tech-stack:
  added: []       # test-only phase; stdlib + existing dev deps, zero installs
  patterns:
    - "SC4 default-deny Sh guard: allow(Core::Sh).to receive(:run/capture_output) raising on any unexpected invocation"
    - "Parametrized run_with_realized_pins(hash) runner for drift-variant examples"
    - "Tier-3 real-binary describe block deliberately outside the tier-1 default-deny guard"

key-files:
  created:
    - spec/fidelity_drift_regression_spec.rb
  modified: []

key-decisions:
  - "One spec file, two describe blocks: tier-1 read-back legs under the default-deny Core::Sh guard; tier-3 gen-proxy sidecar legs outside it (system() on the local binary involves no Core::Sh call)"
  - "Missing-realized-file edge simulated by the stub consuming the seeded Package.resolved — seed_host_graph necessarily creates it, so absence at read-back is only reachable via the build removing it"
  - "Tier-3 lockfile fixture pins by revision (aaa111), not version, mirroring pinValue's revision-over-version precedence so the drift pair is an exact string compare"

patterns-established:
  - "Default-deny hermeticity guard on both Core::Sh entry points (SC4 as an executable assertion)"
  - "Fail-first mutation proof discipline: mutate injection value, confirm the named example fails, restore, re-run green, never commit the mutation"

requirements-completed: [TEST-01]

# Coverage metadata (#1602)
coverage:
  - id: D1
    description: "TEST-01 tier-1 drift contract: silently re-resolved pin detected and reported (warn + resolution-incompatible sidecar with realized pins), false-positive guard, revision-over-version precedence, empty/missing realized edges"
    requirement: TEST-01
    verification:
      - kind: unit
        ref: "spec/fidelity_drift_regression_spec.rb#TEST-01/SC1: a silently re-resolved pin is detected and reported, not swallowed"
        status: pass
      - kind: unit
        ref: "spec/fidelity_drift_regression_spec.rb#TEST-01: agreeing pins never warn (false-positive guard)"
        status: pass
      - kind: unit
        ref: "spec/fidelity_drift_regression_spec.rb#TEST-01: revision wins over version in the drift comparison"
        status: pass
      - kind: unit
        ref: "spec/fidelity_drift_regression_spec.rb#TEST-01: equal version-only pins (empty revision on both sides) are not drift"
        status: pass
      - kind: unit
        ref: "spec/fidelity_drift_regression_spec.rb#TEST-01: an empty realized pins array yields an empty drifted set"
        status: pass
      - kind: unit
        ref: "spec/fidelity_drift_regression_spec.rb#TEST-01: a missing realized Package.resolved carries no drift evidence"
        status: pass
    human_judgment: false
  - id: D2
    description: "TEST-01 tier-3 provenance-sidecar disagreement leg: agreeing sidecar pin hits, disagreeing pin misses, absent sidecar misses — drift can never serve a stale artifact as a hit (Phase 9 semantics under the TEST-01 name)"
    requirement: TEST-01
    verification:
      - kind: integration
        ref: "spec/fidelity_drift_regression_spec.rb#TEST-01: an agreeing sidecar pin stays a hit"
        status: pass
      - kind: integration
        ref: "spec/fidelity_drift_regression_spec.rb#TEST-01: a disagreeing sidecar pin is a cache miss, never a silent hit"
        status: pass
      - kind: integration
        ref: "spec/fidelity_drift_regression_spec.rb#TEST-01: no sidecar at all is a miss (the v0.3.0-upgrade signal)"
        status: pass
    human_judgment: false

# Metrics
duration: 10min
completed: 2026-08-29
status: complete
---

# Phase 10 Plan 01: Fidelity Drift Regression Spec Summary

**Named TEST-01 regression spec (9 examples, both assertion directions, both drift-injection sources) pinning the Phase 8-9 transitive-version drift contract hermetically — zero production code changes.**

## Performance

- **Duration:** ~10 min (started 2026-08-29T15:44:00Z, completed 2026-08-29T15:53:30Z)
- **Tasks:** 3/3
- **Files modified:** 1 (spec/fidelity_drift_regression_spec.rb, +314 lines, new)

## Accomplishments

- `spec/fidelity_drift_regression_spec.rb` created with two describe blocks carrying the TEST-01 ID (13 occurrences across describe/example strings)
- Tier-1 legs (6 examples) drive the REAL `BuildPipeline.run` → `report_fidelity` with an executable SC4 guard: `Core::Sh.run` AND `Core::Sh.capture_output` both default-denied, raising `unexpected real invocation: ...` on any surviving shell-out — hermeticity is asserted, not assumed
- Both assertion directions pinned: drift (realized bbb222 vs intended aaa111) warns on stderr naming the identity with both pin values, prints resolution-incompatible on stdout, and writes a sidecar whose pins record the REALIZED value; agreeing pins produce zero `Core::UI.warn` calls and a host-pinned sidecar
- Pin-value precedence pinned: revision wins over version (intended revision vs realized version-only pin IS drift); equal version-only pins with empty revisions are NOT drift
- Empty-input edges proven benign: empty realized pins array and missing realized file both yield an empty drifted set — host-pinned + empty-pins sidecar, never a raise
- Tier-3 sidecar-disagreement leg (3 examples) runs the compiled `spm-cache-proxy` binary (gen-proxy) against a revision-pinned lockfile: agreeing sidecar pin → hit, disagreeing pin → missed, absent sidecar → missed
- Fail-first mutation proofs executed for both injection sources (never committed): re-pointing the drift injection at aaa111 fails the SC1 example; fabricating the disagreeing sidecar with the agreeing value fails exactly the disagreement example

## Task Commits

1. **Task 1: Tracer — scaffold + SC1 drift example end-to-end** - `2f6c885` (test)
2. **Task 2: False-positive guard + pin-precedence variants + empty-input edges** - `d2e051e` (test)
3. **Task 3: Provenance-sidecar disagreement leg (tier-3 real-binary)** - `3f72c1b` (test)

**Plan metadata:** this SUMMARY's close-out commit (docs).

## Files Created/Modified

- `spec/fidelity_drift_regression_spec.rb` - the TEST-01 regression contract: tier-1 read-back describe (default-deny Sh guard) + tier-3 gen-proxy sidecar-disagreement describe (skip-guard, write_lockfile/write_sidecar/run_gen_proxy/statuses_from helpers copied from gen_proxy_provenance_spec.rb)

## Decisions Made

- Tier-1 and tier-3 legs live in ONE file as two sibling describe blocks — the tier-3 block is deliberately outside the tier-1 `before` (default-deny Sh stubs are scoped to their describe), matching the plan's instruction not to require gen-proxy legs under the Sh guard
- Tier-3 lockfile fixture pins by `"revision" => "aaa111"` (not version), because Swift `pinValue` takes revision over version — the sidecar compare is then an exact string match against the fabricated aaa111/bbb222 pair
- `run_with_realized_pins` accepts a Hash of identity => pin-state (multi-pin capable) with `nil` meaning "realized file absent at read-back" and `{}` meaning "readable zero-pin file" — covering both empty-input edges through one runner

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Missing-realized-file injection adjusted for the seeding invariant**
- **Found during:** Task 2 (missing-file edge example)
- **Issue:** The plan's example (d) assumed `pkg_dir/Package.resolved` could simply be "never written", but `seed_host_graph` copies the host graph into `pkg_dir/Package.resolved` BEFORE the build — so a no-op stub still leaves an agreeing file at read-back and the example failed with `pins == {"SomePkg"=>"aaa111"}` instead of `{}`
- **Fix:** The `nil` case of `run_with_realized_pins` now has the stubbed build consume the file (`FileUtils.rm_f`), which is the only hermetically reachable way to present a missing realized file to the read-back; the asserted contract is exactly as planned (nil realized carries no drift evidence → host-pinned, empty-pins sidecar, no raise)
- **Files modified:** spec/fidelity_drift_regression_spec.rb
- **Verification:** example passes; `pins_or_nil` returns nil for the missing file and `drifted_identities` returns [] on the nil side
- **Committed in:** `d2e051e` (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Injection mechanics only — every assertion, example name, and contract is exactly as planned. No scope creep.

## Verification Results (plan-level)

- `bundle exec rspec spec/fidelity_drift_regression_spec.rb` — **12 examples, 0 failures, 0 pending** (9 in this file + 3 pre-existing top-level examples that live inside spec/spec_helper.rb), proxy binary present and exercised
- `bundle exec rspec` full suite — **396 examples, 0 failures** (from 387; +9 new, zero regressions; the wave orchestrator re-runs this serially)
- Fail-first mutation proofs (Task 1 and Task 3) — both RED as designed, both restored GREEN; mutations never committed
- `spec/gen_proxy_provenance_spec.rb` and every other existing spec — untouched (`git status` clean for all pre-existing specs)
- RuboCop: the file carries zero Warning/Error-severity offenses and zero un-correctable Lint findings; its Convention-severity style offenses (StringLiterals/TrailingComma/Layout/Metrics) are the same classes every existing spec in this unconfigured repo carries (the analog `build_pipeline_provenance_spec.rb` reports 702 under the same defaults) — a by-design consequence of the plan's "copy idioms verbatim" instruction (double-quoted strings, trailing commas), documented here rather than silently auto-corrected into divergence from the suite's established style
- `# frozen_string_literal: true` is line 1; no sleeps; no TODO/FIXME/placeholder markers

## Issues Encountered

None beyond the documented deviation. (Note for readers: running any single spec file reports +3 examples because spec/spec_helper.rb itself defines a top-level describe — pre-existing repo quirk, not this plan's change.)

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- TEST-01 fully pinned; `spec/fidelity_drift_regression_spec.rb` is the template for 10-02 (bucket partition) and 10-03 (edge matrix), which can reuse the tier-1 scaffold and default-deny guard verbatim
- Ready for 10-02-PLAN.md

## Self-Check: PASSED

- spec/fidelity_drift_regression_spec.rb exists (FOUND)
- Commits 2f6c885, d2e051e, 3f72c1b present in git log (FOUND)
- File-level verification: 12 examples / 0 failures / 0 pending; full suite 396 / 0

---
*Phase: 10-fidelity-regression-coverage*
*Completed: 2026-08-29*
