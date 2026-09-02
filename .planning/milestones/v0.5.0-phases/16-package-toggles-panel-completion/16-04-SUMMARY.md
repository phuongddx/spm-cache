---
phase: 16-package-toggles-panel-completion
plan: 04
subsystem: api
tags: [router, jobs, toggle, revert, apply, mutation-surface, ruby]

requires:
  - phase: 16-package-toggles-panel-completion
    provides: "Config#set_ignored/#set_ignored_all shared mutator (16-01); Web::Jobs slot + SCOPES table + fake-bin fixture (15-01); State.call's per-row toggleable/reason/saved_cached/applied_cached/pending derivation (16-03)"
provides:
  - "POST /api/toggle -- the completed validation matrix: token -> verb-404 -> bad_body/bad_package(non-empty, non-blank)/bad_cached(exact boolean) -> the state read model's OWN row set decides unknown_package (404) and not_toggleable (400), re-derived from disk every request -> the mutator's raise rescued into 500 config_write_failed -> the 2xx {package, cached} envelope. Never references @jobs (D-08)"
  - "POST /api/revert -- selects every `pending` row (already narrowed to toggleable-only by 16-03) and hands the whole mapping to Config#set_ignored_all in ONE call; a zero-pending selection skips the mutator entirely and answers an empty reverted set; same gate/body posture as toggle; never slot-gated"
  - "POST /api/apply -- api_mutate(fixed_scope: 'use'), the identical existing helper rollback uses; Jobs::SCOPES gains 'use' => ['use'] (command/use.rb's default bare verb); inherits 409 slot_busy / 500 spawn_failed / the 2xx lock snapshot verbatim, no new spawn code"
  - "spec/web_toggle_routes_spec.rb (new) -- the full toggle/revert/apply matrix, hermetic per example via the state model's cache_root: seam and the 15-01 fake-bin-backed Jobs"
  - "web_jobs_spec.rb + web_integration_spec.rb extended: the sync scope's spawn shape, slot-sharing with build, and the end-to-end toggle-diverge-apply-converge story with a same-run toggle proving D-08 and a dedicated apply-in-flight shutdown row"
affects: [16-05, 16-06]

actuals:
  tokens: 8824   # chars/4 over the realized lib+spec diff (35,297 bytes, 0597612~1..ee6e014)
  tasks: 3
  commits: 6

tech-stack:
  added: []
  patterns:
    - "Route-level permission re-derivation: api_toggle/api_revert ask the SAME injected read model the dashboard renders (@read_models[:state]) rather than a second inventory scan, so the API and the UI can never disagree about what exists or what may change"
    - "Batch-mutator selection as a single each_with_object pass over pending rows, feeding Config#set_ignored_all in ONE call regardless of N -- mirrors 16-01's set_ignored/set_ignored_all convenience split"
    - "Route-fixed scope reuse (api_mutate fixed_scope:) for apply, identical to rollback's precedent -- zero bespoke spawn handling for the third slot-sharing verb"

key-files:
  created:
    - spec/web_toggle_routes_spec.rb
  modified:
    - lib/spm_cache/web/router.rb
    - lib/spm_cache/web/jobs.rb
    - spec/web_jobs_spec.rb
    - spec/web_integration_spec.rb

key-decisions:
  - "Revert skips calling the mutator entirely when the pending selection is empty (rather than always invoking set_ignored_all({})) -- a true no-op does zero disk I/O, and the single-call assertion (one lock acquisition, not N) still holds trivially at N=0"
  - "The not_toggleable rejection carries only the machine reason 'not_toggleable', not the row's own five-word gating reason -- the must_haves/UI-SPEC pin the machine-reason contract, not a secondary payload field; kept minimal per V5 precedent"
  - "package validation upgraded from `!package.empty?` to `!package.strip.empty?` -- closes a real gap the 16-01 tracer left open (a whitespace-only package string passed the old check and would have reached the unknown-package/mutator path with a blank name)"
  - "Task 3 was born-green: Tasks 1-2 already landed the full toggle/apply/revert implementation this integration story exercises. RED was proven by temporarily swapping router.rb/jobs.rb for their pre-16-04 (0f9f6c0) versions and re-running the new rows -- 2/2 selected examples failed (404 route-not-found; KeyError: key not found \"use\") -- then restored byte-identical and re-run GREEN (16-01 Task 3 precedent)"
  - "The integration story's D-08 same-run toggle and the apply-in-flight shutdown row were folded into the SAME describe block / the existing final shutdown describe respectively, rather than new top-level describes -- keeps the file's `order: :defined` real-shutdown-must-run-last invariant intact (the story needs the live server; the two real @server.shutdown calls the file makes must stay the last two acts)"

requirements-completed: []

coverage:
  - id: D1
    description: "POST /api/toggle's full validation matrix: auth, verb, body, package, cached (exact boolean), unknown_package (404, the row set IS the universe), not_toggleable (400, server-re-derived), config_write_failed (500), the 2xx envelope, idempotence in both directions"
    requirement: TOGL-01
    verification:
      - kind: integration
        ref: "spec/web_toggle_routes_spec.rb 'the gate matrix' / 'body validation' / 'unknown package' / 'not toggleable' / 'write failure' / 'success' (12 examples)"
        status: pass
    human_judgment: false
  - id: D2
    description: "D-08: /api/toggle and /api/revert never consult Jobs -- both answer 2xx and write with the spawn slot held by a live run; a 409 from either route is a contract violation"
    requirement: TOGL-01
    verification:
      - kind: integration
        ref: "spec/web_toggle_routes_spec.rb 'slot independence' + the revert 'not slot-gated' row; spec/web_integration_spec.rb 'toggle during the apply run stays live' row"
        status: pass
    human_judgment: false
  - id: D3
    description: "POST /api/revert restores saved-to-applied for every diverging TOGGLEABLE row in ONE lock acquisition (not N), leaves non-diverging and non-toggleable rows untouched, and is a successful no-op with nothing pending"
    requirement: TOGL-02
    verification:
      - kind: integration
        ref: "spec/web_toggle_routes_spec.rb 'POST /api/revert' (6 examples, incl. the single-call mock expectation and the pattern-managed untouched-entry pin)"
        status: pass
    human_judgment: false
  - id: D4
    description: "POST /api/apply is the existing mutation helper with the scope fixed by the route; Jobs::SCOPES gains 'use'; inherits 409/500/2xx verbatim; reads no scope from the body; shares the ONE slot with build/rebuild/rollback"
    requirement: TOGL-02
    verification:
      - kind: unit
        ref: "spec/web_jobs_spec.rb 'the frozen scope table carries the sync verb' + the two slot-sharing rows"
        status: pass
      - kind: integration
        ref: "spec/web_toggle_routes_spec.rb 'POST /api/apply' (5 examples)"
        status: pass
    human_judgment: false
  - id: D5
    description: "The full loop closes end to end: toggle diverges a row, apply spawns the real sync verb through the slot, and once the run has ended and applied truth catches up, a fresh /api/state shows the row converged"
    requirement: TOGL-02
    verification:
      - kind: integration
        ref: "spec/web_integration_spec.rb 'POST /api/apply -> converge (16-04)' (3 examples) + 'shutdown with an in-flight Apply-now spawn' "
        status: pass
    human_judgment: false

duration: 55min
completed: 2026-09-02
status: complete
---

# Phase 16 / Plan 16-04: The mutation surface — the toggle matrix, batched revert, and Apply-now through the one slot

**POST /api/toggle now validates every field of its body and re-derives permission from the same read model the dashboard renders before touching the config; POST /api/revert restores every diverging row in one locked transaction; POST /api/apply spawns the real `spm-cache use` through the single slot Phase 15 already governs — with the whole loop proven end to end by one integration story.**

## Task Commits

1. **Task 1: The toggle matrix** — `0597612` (test), `7881f12` (feat)
2. **Task 2: Batched revert + Apply-now** — `d07c823` (test), `ab50c4a` (feat)
3. **Task 3: The end-to-end story** — `492c27b` (test), `ee6e014` (feat, born-green — see key-decisions)

**Example progression (RED → GREEN):**
- `0597612` added `spec/web_toggle_routes_spec.rb` (17 examples) — 4 failures confirmed before implementation: whitespace-only package accepted (a real 16-01 gap), unknown_package/not_toggleable/config_write_failed all fell through to the tracer's bare 200 path.
- `7881f12` completed `api_toggle` (state-model lookup for unknown/not-toggleable, mutator rescue, `strip.empty?`) — 35 examples green (`web_toggle_routes_spec.rb` + `web_build_routes_spec.rb` regression).
- `d07c823` added 11 revert/apply examples to `web_toggle_routes_spec.rb` and 3 sync-scope examples to `web_jobs_spec.rb` — 13 failures confirmed (routes 404'd; `Jobs::SCOPES` had no `'use'` key).
- `ab50c4a` added the `api_revert` handler, the `/api/apply`/`/api/revert` dispatch arms, and the `'use'` scope table entry — 58 examples green (`web_toggle_routes_spec.rb` + `web_jobs_spec.rb` + `web_build_routes_spec.rb` regression).
- `492c27b` added the toggle→apply→converge story (3 examples) plus a dedicated apply-in-flight shutdown row to `web_integration_spec.rb` — proven discriminative by temporarily restoring the pre-16-04 `router.rb`/`jobs.rb` (commit `0f9f6c0`) and re-running just the new rows: 2/2 failed (404 route-not-found; `KeyError: key not found "use"`).
- `ee6e014` restored the real `router.rb`/`jobs.rb` byte-identical and re-ran GREEN — zero production delta, an empty commit recording the gate (16-01 Task 3 precedent).

## Files Created/Modified
- `lib/spm_cache/web/router.rb` — `api_toggle` completed with the unknown/not-toggleable/write-failure checks; the new `api_revert` handler; `/api/apply` and `/api/revert` dispatch arms
- `lib/spm_cache/web/jobs.rb` — `SCOPES` gains `'use' => ['use'].freeze`
- `spec/web_toggle_routes_spec.rb` (new) — the full toggle/revert/apply matrix, 28 examples
- `spec/web_jobs_spec.rb` — 3 new examples (sync-scope argv shape, bidirectional slot sharing with build)
- `spec/web_integration_spec.rb` — 4 new examples (the converge story's 3 rows + the apply-in-flight shutdown row)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Whitespace-only package strings passed the 16-01 tracer's `bad_package` check**
- **Found during:** Task 1's own RED spec (`answers 400 bad_package for absent, empty, whitespace-only, and non-String package values`)
- **Issue:** The tracer's `package.is_a?(String) && !package.empty?` accepted a string of only whitespace (e.g. `"   "`), which would have reached the unknown-package/mutator path carrying a blank name.
- **Fix:** Changed the emptiness check to `!package.strip.empty?`.
- **Files modified:** `lib/spm_cache/web/router.rb`
- **Verification:** `spec/web_toggle_routes_spec.rb` 'body validation' row, part of the Task 1 GREEN commit `7881f12`.

---

**Total deviations:** 1 auto-fixed (1 bug — a real validation gap the plan's own matrix was designed to catch).
**Impact on plan:** In scope by construction — Task 1's `<behavior>` explicitly specifies "whitespace-only... package values are each 400 with the bad-package reason"; fixing it is the task, not a deviation from it, but recorded here since the defect predates this plan (16-01's tracer).

## Issues Encountered
None beyond the deviation above.

## User Setup Required
None — no external service configuration required.

## Verification

Scoped verify commands (all specified by the plan), run in this order:
- `bundle exec rspec spec/web_toggle_routes_spec.rb spec/web_build_routes_spec.rb` — 35 examples, 0 failures (Task 1 gate)
- `bundle exec rspec spec/web_toggle_routes_spec.rb spec/web_jobs_spec.rb spec/web_build_routes_spec.rb` — 58 examples, 0 failures (Task 2 gate)
- `bundle exec rspec spec/web_integration_spec.rb` — 65 examples, 0 failures (Task 3 gate)
- `bundle exec rspec spec/web_toggle_routes_spec.rb spec/web_jobs_spec.rb spec/web_integration_spec.rb spec/web_build_routes_spec.rb` — 120 examples, 0 failures (the plan's full `<verification>` block)
- `bundle exec rspec` (full suite, run ONCE at the end per the wave-3 merge gate) — **1068 examples, 0 failures**

## Next Phase Readiness
- 16-05's client now has a frozen, fully-validated contract for all three endpoints: `POST /api/toggle` (`unknown_package`/`not_toggleable`/`config_write_failed` machine reasons), `POST /api/revert` (`{reverted: [names]}`), `POST /api/apply` (the shared `{scope, lock}` 2xx shape and the shared 409/500 reasons) — every status code and envelope shape this plan commits is load-bearing for 16-05's button wiring.
- The A4 app-wide busy-string amendment (`CTRL.busy` naming all three verbs) is explicitly 16-05's — this plan touched no frontend asset.
- 16-06's panel proof still needs a live-browser walkthrough of the checkbox/bar/Apply-now/Revert-all surface — nothing in this plan claims that.
- `requirements-completed` intentionally left empty: TOGL-01's core (shared mutator, atomic save) was already claimed by 16-01; TOGL-02/TOGL-03 span through 16-05 (UI) and 16-06 (browser proof), matching the convention 16-02/16-03's SUMMARYs recorded.

## Self-Check: PASSED
- `lib/spm_cache/web/router.rb` — FOUND
- `lib/spm_cache/web/jobs.rb` — FOUND
- `spec/web_toggle_routes_spec.rb` — FOUND
- `spec/web_jobs_spec.rb` — FOUND
- `spec/web_integration_spec.rb` — FOUND
- `0597612` — FOUND in git log
- `7881f12` — FOUND in git log
- `d07c823` — FOUND in git log
- `ab50c4a` — FOUND in git log
- `492c27b` — FOUND in git log
- `ee6e014` — FOUND in git log

---
*Phase: 16-package-toggles-panel-completion*
*Completed: 2026-09-02*
