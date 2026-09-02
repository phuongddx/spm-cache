---
phase: 15-ui-build-controls
reviewed: 2026-09-01T20:20:09Z
depth: deep
files_reviewed: 10
files_reviewed_list:
  - lib/spm_cache/web/jobs.rb
  - lib/spm_cache/web/router.rb
  - lib/spm_cache/web/read_models/runs.rb
  - lib/spm_cache/web/assets/app.js
  - lib/spm_cache/web/assets/index.html
  - lib/spm_cache/web/assets/styles.css
  - lib/spm_cache/web/assets/log.js
  - lib/spm_cache/installer/rollback.rb
  - lib/spm_cache/installer/build.rb
  - lib/spm_cache/command/build.rb
  - lib/spm_cache/main.rb
  - README.md
findings:
  critical: 1
  warning: 1
  info: 1
  total: 3
status: resolved
---

# Phase 15: Code Review Report

**Reviewed:** 2026-09-01T20:20:09Z
**Depth:** deep (cross-file trace: router → jobs → read_models/runs; frontend event coupling app.js ↔ log.js)
**Files Reviewed:** 11 source files + README.md
**Status:** resolved (CR-01 fixed, WR-01 fixed, IN-01 documented — see Resolution notes below)

## Summary

Reviewed commit range `9945823..HEAD` (Phase 15, plans 15-01 through 15-06) against the pinned contracts in 15-CONTEXT.md (D-01..D-09), the PROBED spawn shape, the trigger whitelist, the rollback lock, the scope whitelist, and the frontend disciplines.

Verified clean against the pinned contracts:
- **PROBED spawn shape** (`lib/spm_cache/web/jobs.rb`): array argv (`SCOPES` table, never interpolated/splatted from user input), `pgroup: true`, `Process.detach` with no `waitpid`/monitor thread, slot release derived from `ReadModels::Runs.derive_for_pid`/`pid_alive?` on the next claim attempt — matches D-02/D-05/CP10 exactly.
- **Trigger whitelist** (`lib/spm_cache/main.rb:24`): `ENV['SPM_CACHE_TRIGGER'] == 'ui' ? 'ui' : 'terminal'` is a closed two-way map — any other value (unset, empty, garbage) normalizes to `'terminal'`, never passthrough.
- **Rollback lock** (`lib/spm_cache/installer/rollback.rb`): `acquire_build_lock` runs before `remove_proxy`'s `rm_rf`, and `release_build_lock` runs in `perform_install`'s `ensure`, so a raise inside `restore_packages`/`remove_proxy` still releases (matches BLD-04/CP4).
- **WEB-03 exit-0 with in-flight build**: `Web::Server#shutdown` (unmodified this phase) never touches `@jobs`, never waits on the spawned pgroup — confirmed no new coupling was introduced.
- **el()/textContent discipline**: no `innerHTML`/`dangerouslySetInnerHTML` anywhere in the new `app.js` build-controls block (§11) or the untouched-pattern reuse in `log.js`.
- **409 reason machine-readable**: `reason: 'slot_busy'/'bad_scope'/'bad_body'/'spawn_failed'` are never read by the frontend for display copy — `app.js`'s `settle()` reads only `data.message`.
- **No new assets**: diff touches only the four existing asset files.

One contract is violated (Critical, below), and one genuine cross-module race exists in the frontend event coupling (Warning, below).

## Critical Issues

### CR-01: `POST /api/build` accepts `scope: "rollback"`, bypassing the route-implied scope whitelist

**File:** `lib/spm_cache/web/router.rb:112-119` (`dispatch`) and `lib/spm_cache/web/router.rb:250-274` (`api_mutate`)

**Issue:** The pinned contract (D-01, D-07, and the router's own doc comment above `api_mutate`) is that `/api/build`'s scope is verb-level (`build`/`rebuild` only) and `/api/rollback`'s scope is *implied by the route, never read from the body*. The route-to-scope binding is only enforced in one direction:

```ruby
# dispatch
when '/api/build'
  api_mutate(req, res, supplied)                              # scope from body, unrestricted
when '/api/rollback'
  api_mutate(req, res, supplied, fixed_scope: 'rollback')      # scope forced

# api_mutate
scope = fixed_scope || (body.is_a?(Hash) ? body['scope'] : nil)
unless Jobs::SCOPES.key?(scope)
  return respond_json(res, 400, error_envelope(..., reason: 'bad_scope'))
end
```

`Jobs::SCOPES` has three keys: `'build'`, `'rebuild'`, `'rollback'` (`lib/spm_cache/web/jobs.rb:36-40`). Because `/api/build` validates only `Jobs::SCOPES.key?(scope)` — the full three-key table — and never restricts to `%w[build rebuild]`, a POST to `/api/build` with body `{"scope":"rollback"}` passes validation and calls `@jobs.spawn_run(scope: 'rollback')`, spawning the exact same `bin/spm-cache rollback` subprocess as the dedicated `/api/rollback` route. This is reachable by any token-holder without ever hitting `/api/rollback`.

`spec/web_build_routes_spec.rb`'s `bad_scope` matrix (lines 425-444) exercises `'cleanse'`, `7`, `['build']`, `'Build'`, `'BUILD'` against `/api/build` but never `'rollback'` — the gap is real and untested. `spec/web_build_routes_spec.rb:190/223` only assert `scope == 'rollback'` for requests actually posted to `/api/rollback`.

Impact is bounded (a valid token already grants direct access to `/api/rollback`, so this is not a new privilege), but it is a genuine, silent contract violation of the explicitly pinned per-route scope whitelist, defeats any future observability/rate-limiting that assumes "rollback only happens via POST /api/rollback", and ships with zero test coverage protecting it.

**Fix:** Restrict `/api/build`'s accepted scopes explicitly, mirroring the `fixed_scope` pattern already used for rollback:

```ruby
when '/api/build'
  api_mutate(req, res, supplied, allowed_scopes: %w[build rebuild])
when '/api/rollback'
  api_mutate(req, res, supplied, fixed_scope: 'rollback')

def api_mutate(req, res, supplied, fixed_scope: nil, allowed_scopes: Jobs::SCOPES.keys)
  ...
  scope = fixed_scope || (body.is_a?(Hash) ? body['scope'] : nil)
  unless allowed_scopes.include?(scope) && Jobs::SCOPES.key?(scope)
    return respond_json(res, 400, error_envelope('scope is not one of the known scopes', reason: 'bad_scope'))
  end
```

Add a spec row: `post('/api/build', auth, JSON.generate('scope' => 'rollback'))` expects `400`/`bad_scope`.

**Resolution:** Fixed exactly as suggested — `api_mutate` gained an `allowed_scopes:` keyword (default `Jobs::SCOPES.keys`); the `/api/build` dispatch arm now passes `allowed_scopes: %w[build rebuild]`, so `Jobs::SCOPES.key?(scope)` alone is no longer sufficient to reach `spawn_run`. Added the exact suggested spec row (a `'cross-route scope (rollback via /api/build)'` case in the existing `bad_scope` matrix) — RED confirmed pre-fix (`200`, spawned the rollback subprocess), GREEN post-fix (`400`/`bad_scope`, `expect_no_spawn`).
**Commit:** 12fdd51

## Warnings

### WR-01: Build-controls "in-flight" state is derived from whatever run is currently displayed, not the run the click actually started — an unrelated run's `run_end` can prematurely reset the row

**File:** `lib/spm_cache/web/assets/log.js:527-536` (`appendBody`, `onRunEnd` → `emitProgress`) and `lib/spm_cache/web/assets/app.js:392-400` (the `spm-run-progress` listener)

**Issue:** `emitProgress('active'|'waiting')` fires from `appendBody` for every body line of whatever run `log.js` currently has open (`currentRun`), and `emitProgress('ended')` fires from `onRunEnd` for that same currently-displayed run's `run_end` line — live or **replayed**. `app.js`'s listener has no correlation to which run its own POST actually spawned:

```js
document.addEventListener('spm-run-progress', (e) => {
  const phase = e.detail && e.detail.phase;
  if (phase === 'ended') { freeze(false); verb = null; say(''); return; }
  ...
});
```

The design comment ("emission is displayed-run-scoped by construction") assumes the SSE auto-switch (D-04) always lands *before* any other progress event fires for the row. That assumption breaks in a realistic sequence:

1. User opens the recent-runs dropdown and selects an older, already-finished run (`loadRun` → `resetForRun(name, false)` → `pinned = true`, `replaying = true`). The cold-load replay of that file is now streaming from byte 0, including its own recorded `run_end` line.
2. Before that replay finishes, the user clicks **Build**. `app.js` sets `verb = 'build'` and freezes the row.
3. The still-in-flight replay of the *old, unrelated* run reaches its own `run_end` line → `onRunEnd` → `emitProgress('ended')`.
4. The listener has no way to know this `ended` belongs to a different run than the one just spawned — it unconditionally does `freeze(false); verb = null; say('')`, silently returning the controls row to idle while the real UI-spawned build keeps running server-side (the Jobs slot is still held).
5. The user can now click Build again; the second click correctly gets rejected with `409 slot_busy`, so no double-spawn occurs — but the row's state is wrong for however long remains of the real build, and the "busy" message only reappears reactively on the next failed click rather than reflecting the true in-flight state.

This is a real, reachable race (browsing run history and then triggering a build/rollback is an ordinary user action), not a security or data-loss issue, but it is an unhandled edge case in the one "sanctioned coupling" (A10) this phase introduces.

**Fix:** Carry the spawned run's identity (or at minimum the currently-*pinned-at-click-time* run id) and only accept `ended`/`waiting`/`active` events once `log.js`'s `currentRun` matches the run that was actually started — e.g. have the 2xx envelope's lock snapshot include the newly-derived run id (already computed server-side via `lock_state`) and have `app.js` ignore `spm-run-progress` events until `log.js` reports (via the event detail or a small currentRun readout) that the displayed run has switched to it. A simpler mitigation: don't dispatch `spm-run-progress` for events sourced from a `replaying` load (`log.js`'s own `replaying` flag is already tracked) — a purely-historical replay should never emit build-controls milestones.

**Resolution:** Took the "simpler mitigation" but gated on `pinned` rather than `replaying` — `replaying` is not a stable-enough signal (it flips `false` mid-replay the moment the viewport reaches the bottom, per `log.js`'s own D-13 comment, which can happen *before* an unrelated run's `run_end` line is reached for a short historical log, i.e. exactly inside this finding's own narrated race). `pinned` does not have that flicker: `onSwitchEvent` unconditionally clears it the instant ANY run's switch broadcast lands, so by the time `currentRun` genuinely becomes the run a click spawned, `pinned` is guaranteed false again — `emitProgress` now no-ops with `if (pinned) return;` while suppressing zero milestones for the run that was actually started. RED confirmed pre-fix (source-contract pin absent), GREEN post-fix.
**Commit:** 165e88e

## Info

### IN-01: `Jobs#held?` / `ReadModels::Runs.pid_alive?` are subject to a (very low probability) PID-reuse false positive

**File:** `lib/spm_cache/web/jobs.rb:74-82`, `lib/spm_cache/web/read_models/runs.rb` (`pid_alive?`)

**Issue:** Slot release is derived from `Process.kill(0, pid)` liveness when no run file is yet attributable to the pid (the pre-header spawn window). If the spawned child dies in that exact window and the OS reissues its pid to an unrelated process before the next `spawn_run` claim attempt, `held?` would report `alive = true` for a build that has already exited, blocking new UI-originated builds until the false-positive pid also exits. This is an inherent limitation of pid-based liveness probing (the same pattern already existed pre-phase-15 in `run_log.rb`'s private `pid_alive?`, and Phase 15 only reuses/publicizes it) and self-corrects once the borrowed pid exits — it is not data-loss and does not defeat the mutex's correctness, only its liveness under an adversarial-timing coincidence. No fix required; noting for completeness since the review scope explicitly asked about slot-release races.

**Resolution:** Documented, no code change (theoretical, self-correcting per the Issue text above — task scope marks this info-tier finding as documentation-only). The pid-reuse window is inherent to pid-based liveness probing and pre-dates Phase 15 (`run_log.rb`'s private `pid_alive?`); closing it would require a generation-tagged slot token or an OS-level pid-fd, out of proportion to a very-low-probability, self-healing liveness false positive with no data-loss and no correctness impact on the mutex itself.

---

_Reviewed: 2026-09-01T20:20:09Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep_
