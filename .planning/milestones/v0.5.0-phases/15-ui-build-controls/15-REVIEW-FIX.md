---
phase: 15-ui-build-controls
fixed_at: 2026-09-01T20:29:35Z
review_path: .planning/phases/15-ui-build-controls/15-REVIEW.md
iteration: 1
findings_in_scope: 3
fixed: 2
skipped: 0
status: partial
---

# Phase 15: Code Review Fix Report

**Fixed at:** 2026-09-01T20:29:35Z (post-fix full suite: 984 examples, 0 failures — baseline 983 + 1 new regression spec)
**Source review:** .planning/phases/15-ui-build-controls/15-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 3 (critical: 1, warning: 1, info: 1 — task scope required CR-01 and WR-01 code fixes, IN-01 documentation only)
- Fixed: 2
- Documented (no code change, by task scope): 1

## Fixed Issues

### CR-01: `POST /api/build` accepted `scope: "rollback"`, bypassing the route-implied scope whitelist

**Files modified:** `lib/spm_cache/web/router.rb`, `spec/web_build_routes_spec.rb`
**Commit:** 12fdd51
**Applied fix:** `api_mutate` gained an `allowed_scopes:` keyword (default `Jobs::SCOPES.keys`); the `/api/build` dispatch arm now passes `allowed_scopes: %w[build rebuild]`, and the scope check became `allowed_scopes.include?(scope) && Jobs::SCOPES.key?(scope)`. `/api/rollback` is unaffected (`fixed_scope: 'rollback'` already forced its scope, ignoring the body). Applied exactly as the review's Fix section suggested, plus its suggested spec row.
**RED→GREEN:** Added a `'cross-route scope (rollback via /api/build)'` case to the existing `bad_scope` matrix in `spec/web_build_routes_spec.rb`. Pre-fix: `200` (the route spawned the rollback subprocess) — confirmed failing. Post-fix: `400`/`bad_scope`, `expect_no_spawn` holds.

### WR-01: Build-controls "in-flight" state derived from whatever run is displayed, not the run the click actually started

**Files modified:** `lib/spm_cache/web/assets/log.js`, `spec/web_frontend_spec.rb`
**Commit:** 165e88e
**Applied fix:** `emitProgress` now no-ops with `if (pinned) return;` before dispatching the `spm-run-progress` CustomEvent. Chose `pinned` over the review's literal "simpler mitigation" (`replaying`) because `replaying` is not stable across the exact race the finding narrates — `log.js`'s own D-13 logic flips `replaying` to `false` mid-replay the instant the viewport reaches the bottom, which can happen for a short historical log *before* its `run_end` line is even reached, silently defeating a `!replaying` gate in precisely the scenario described. `pinned` has no such flicker: `onSwitchEvent` unconditionally clears it the moment ANY run's switch broadcast lands, so by the time `currentRun` genuinely becomes the run a click spawned, `pinned` is guaranteed false again — the gate never withholds a milestone for the run actually started, only for whichever unrelated/historical run the viewer happens to be pinned to.
**RED→GREEN:** This repo runs no JS execution harness (`web_frontend_spec.rb`'s own header: "This repo runs no JavaScript in CI: every contract is a byte-level pin"); added a source-contract spec pinning `if (pinned) return;` inside `emitProgress`'s body, matching the file's existing convention (see the `emission points` / `listener mapping` specs in the same describe block). Pre-fix: failed (guard text absent). Post-fix: passes.

## Documented, No Code Change

### IN-01: `Jobs#held?` / `ReadModels::Runs.pid_alive?` PID-reuse false positive

**File:** `lib/spm_cache/web/jobs.rb:74-82`, `lib/spm_cache/web/read_models/runs.rb`
**Disposition:** Documentation only, per task scope — theoretical and self-correcting (the review's own Issue text: "not data-loss and does not defeat the mutex's correctness, only its liveness under an adversarial-timing coincidence"). Recorded a **Resolution** note in `15-REVIEW.md` explaining the pre-existing (pre-Phase-15) nature of the limitation and why a real fix (generation-tagged slot token or OS pid-fd) is out of proportion to the risk. No commit — no source changed.

## Verification

- Full suite: `bundle exec rspec` — **984 examples, 0 failures** (baseline 983 + 1 new example; CR-01's regression is a new row inside an existing `it` block, so it added zero new examples — only WR-01 added a new `it`).
- Both fixes proven RED before the code change and GREEN after, via the specific spec files touched (`spec/web_build_routes_spec.rb`, `spec/web_frontend_spec.rb`) before running the full suite once at the end, per task constraints.
- Ran directly in the main checkout (no worktree — `--no-worktree` per task constraints), on branch `gsd/v0.5.0-web-interface`.
- `.planning/phases/15-ui-build-controls/15-REVIEW.md` updated in place with **Resolution**/**Commit** lines for all three findings and frontmatter `status: issues_found` → `resolved`.

---

_Fixed: 2026-09-01_
_Fixer: Claude (gsd-code-fixer, FixReview15)_
_Iteration: 1_
