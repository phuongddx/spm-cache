---
phase: 09-cache-identity-invalidation
plan: 03
subsystem: docs
tags: [verification-runbook, derived-data, xcodebuild, provenance]

requires:
  - phase: 09-cache-identity-invalidation
    provides: "Plan 01's provenance-aware BinariesCache.hit() -- this plan's procedure forces a genuine 'missed' via that mechanism, there is nothing real to invalidate without it"
provides:
  - "09-SC5-VERIFICATION.md -- a concrete, runnable, step-by-step reproduction procedure for RESEARCH.md's Assumption A1 (DerivedData staleness on in-place xcframework rebuild), with an empty ## Outcome section queued for human execution"
affects: []

actuals:
  tokens: 3200
  tasks: 1
  commits: 1

tech-stack:
  added: []
  patterns:
    - "Documentation-only plan producing a runbook whose <human-check> is harvested into 09-UAT.md at end-of-phase, per workflow.human_verify_mode: end-of-phase -- no standalone checkpoint task"

key-files:
  created:
    - .planning/phases/09-cache-identity-invalidation/09-SC5-VERIFICATION.md
  modified: []

key-decisions:
  - "Runbook offers two alternative ways to force the pin disagreement (hand-edit the .provenance.json sidecar directly, or bump the host Package.resolved's pin) rather than mandating one -- the sidecar edit is faster/less disruptive, the Package.resolved edit is the more realistic end-to-end reproduction; the human running the procedure picks based on convenience."
  - "Marker choice (mtime, shasum, otool -L, or nm symbol-set hash) left as a menu rather than a single mandated command -- all four are valid evidence of content change, and mtime is fastest for a first pass while nm's symbol hash is the strongest positive proof if the mtime check is ambiguous."

requirements-completed: [CACHE-02]

coverage:
  - id: SC5
    description: "A concrete, runnable reproduction procedure for RESEARCH.md's Assumption A1 (does Xcode's incremental build reliably notice an in-place-overwritten local path:-declared binaryTarget's content change without spm-cache touching DerivedData) exists and is queued for human execution against the real reference project"
    requirement: "CACHE-02"
    verification:
      - kind: manual
        ref: ".planning/phases/09-cache-identity-invalidation/09-SC5-VERIFICATION.md -- 5-step runbook (cold-build, mark linked framework, force a pin-disagreement miss + rebuild one package, rebuild app without clearing DerivedData, re-check marker), empty ## Outcome section"
        status: pending
    human_judgment: true

duration: ~12min
completed: 2026-08-29
status: complete
---

# Phase 09 Plan 03: SC5 DerivedData Verification Runbook Summary

**Wrote a concrete, runnable 5-step reproduction procedure (`09-SC5-VERIFICATION.md`) that empirically tests whether Xcode's incremental build notices an in-place xcframework rebuild without a manual DerivedData clear -- closing RESEARCH.md's open Assumption A1 with a real test instead of circumstantial reasoning, queued for human execution at end-of-phase.**

## Performance

- **Duration:** ~12 min
- **Completed:** 2026-08-29
- **Tasks:** 1 / 1
- **Files modified:** 1 (created)

## Accomplishments

- Read Plan 01's summary (the `hit()` provenance mechanism this runbook exercises), RESEARCH.md's
  full Assumption A1 writeup (its evidence, residual unverified scope, and the exact recommended
  checkpoint shape), and `xcframework.rb`'s `FileUtils.rm_rf(@output_path)` overwrite-in-place
  precedent it cites.
- Confirmed the plan's `<precondition>` is met: the reference project directory
  (`/Users/ddphuong/Projects/next-labs/stress-ai/ios-stress-app/StressMonitor`) exists on disk.
- Wrote `09-SC5-VERIFICATION.md`: a concrete, copy-pasteable 5-step procedure (cold-build via
  `spm-cache build`, mark one linked framework's content in the app's DerivedData, force a
  pin-disagreement `missed` for that ONE package via provenance-sidecar or `Package.resolved` edit
  and rebuild it, rebuild the HOST APP without clearing DerivedData, re-check the same marker) plus
  a cleanup section restoring any edited files, and an empty `## Outcome` section (PASS/FAIL
  checkboxes + notes) for the human to fill in.
- Confirmed the plan's own automated verification (`test -f ... && grep -q "## Outcome" ...`)
  passes; the file is 179 lines, well over the plan's `min_lines: 20` artifact requirement.

## Task Commits

Each task was committed atomically:

1. **Task 1: SC5 empirical reproduction runbook -- DerivedData staleness on in-place xcframework rebuild** - `f7e60a8` (docs)

## Files Created/Modified

- `.planning/phases/09-cache-identity-invalidation/09-SC5-VERIFICATION.md` - new file, empirical
  reproduction runbook for SC5/D-11/D-12, empty `## Outcome` section awaiting human PASS/FAIL.

## Decisions Made

- Offered two alternative pin-disagreement mechanisms (direct sidecar edit vs. host
  `Package.resolved` pin bump) rather than mandating one -- both are faithful ways to trigger
  Plan 01's `hit()` miss path; the choice affects convenience, not correctness of the test.
- Left the "distinguishing marker" choice as a menu (mtime, shasum, `otool -L`, `nm` symbol-set
  hash) since the plan's `<action>` explicitly names all four as acceptable evidence, and the
  strongest/fastest check depends on what's convenient for the human running it.

## Deviations from Plan

None - plan executed exactly as written. This is a documentation-only plan; no code changes, no
auto-fix triggers applicable.

## Issues Encountered

None.

## User Setup Required

**Yes -- this plan's whole output is a runbook queued for human execution.** The `<human-check>`
in `09-03-PLAN.md`'s Task 1 `<verify>` block will be harvested into `09-UAT.md` at end-of-phase
(per `workflow.human_verify_mode: end-of-phase`). A human with Xcode and access to the reference
project must run the 5-step procedure in `09-SC5-VERIFICATION.md` and record PASS/FAIL in its
`## Outcome` section before Phase 9 can be considered fully verified against SC5.

## Next Phase Readiness

- Plan 03 is complete: the runbook artifact exists, is concrete and runnable, and is not
  pre-filled.
- Phase 9's remaining open item is the human execution of this runbook (SC5) plus whatever else
  end-of-phase UAT harvesting surfaces from Plans 01/02.
- No blockers for any subsequent phase from this plan's changes (documentation-only, zero code
  touched).

## Self-Check: PASSED

`09-SC5-VERIFICATION.md` verified present on disk at
`.planning/phases/09-cache-identity-invalidation/09-SC5-VERIFICATION.md` (179 lines, contains
`## Outcome`). Commit hash `f7e60a8` verified present in `git log --oneline --all`.

---
*Phase: 09-cache-identity-invalidation*
*Completed: 2026-08-29*
