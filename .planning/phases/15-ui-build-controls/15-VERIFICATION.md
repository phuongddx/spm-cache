---
phase: 15-ui-build-controls
verified: 2026-09-02T00:00:00Z
status: passed
score: 6/6 must-haves verified
behavior_unverified: 0
overrides_applied: 0
---

# Phase 15: UI Build Controls Verification Report

**Phase Goal:** Users can trigger builds and rollback from the dashboard with the same locking, live output, and failure visibility as the terminal
**Verified:** 2026-09-02T00:00:00Z (HEAD 35ac544)
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth (ROADMAP SC / REQUIREMENTS) | Status | Evidence |
|---|---|---|---|
| 1 | SC1a/BLD-01 — Build/Rebuild with scope selection spawns the real CLI subprocess as array argv in its own process group, output streams live | ✓ VERIFIED | `lib/spm_cache/web/jobs.rb:64-75` — `Process.spawn(env, RbConfig.ruby, @bin_path, *argv, chdir:, out: File::NULL, err: File::NULL, pgroup: true)` then `Process.detach`; argv sourced only from the frozen `SCOPES` table (`build`→`['build']`, `rebuild`→`['build','--rebuild']`). Behavioral proof: `spec/web_jobs_spec.rb` spawn-shape rows (argv fragments, cwd, pgid==pid, null stdio) — 0 failures. Browser-true: 15-06-SUMMARY.md Row 1 (Build → `ui` badge, live stream to `Build complete!`) and Row 4 (Rebuild all → argv `spm-cache build --rebuild`) — both PASS, agent-browser recorded 2026-09-02. |
| 2 | SC1b/BLD-01 — A second concurrent UI build is rejected with a clear busy message (single slot) | ✓ VERIFIED | `lib/spm_cache/web/jobs.rb:60-76` — check-then-claim inside one `Mutex#synchronize`. Behavioral proof (state-transition/race, not just presence): `spec/web_jobs_spec.rb:176-190` spawns 8 real threads racing `spawn_run` and asserts exactly 1 non-nil result — passing. Router surfaces the rejection as HTTP 409 with `data.reason: 'slot_busy'` (`router.rb:296-299`); frontend renders the pinned sentence `CTRL.busy` inline (`app.js:324,368`). Browser-true: 15-06-SUMMARY.md Row 2 (tab B's click during a parked run → 409, inline message, no dialog, no second run file) — PASS. |
| 3 | SC2/BLD-02 — When another process holds the build lock, the UI shows the waiting state derived from the lock, never a silent queue | ✓ VERIFIED | Server: 2xx envelope always carries a freshly derived `lock` snapshot via `ReadModels::Runs.lock_state` (`router.rb:302-303`). Client: `app.js:372` lights `CTRL.wait` ("Waiting for build lock…") from that snapshot as an entry assist, and `log.js:604-609` emits `waiting`/`active` from the run's own byte-matched frozen line via the `spm-run-progress` CustomEvent, consumed at `app.js:411-417`. The frozen string is byte-identical across `installer/rollback.rb:47` (`Core::UI.info 'Waiting for build lock…'`), `log.js:587` (`WAIT_LINE`), and `app.js:325` (`CTRL.wait`). Browser-true: 15-06-SUMMARY.md Row 3 (foreign-held lock → 2xx spawn accepted, row shows the wait message within 600ms from the POST's lock snapshot, identical in-stream announce line, clears on release) — PASS. |
| 4 | SC3/BLD-03 — A failed build surfaces its exit status with highlighted error lines in the UI | ✓ VERIFIED | Inherited Phase-14 banner chain (D-09/D-10, unmodified) renders `Run failed — exit status N` with fail-colored `✗`-prefixed lines and a working jump; Phase 15 adds no new failure-rendering code (by design — UI-SPEC A7: "the banner owns run outcome, the row owns action state"), and the controls row returns to idle on run end (`app.js:413`) so a retry is one click. Browser-true, UI-triggered: 15-06-SUMMARY.md Row 6 (forced `Rebuild all` of a compile-broken package → `Run failed — exit status 1` banner, `Jump to first error`, 82 `✗`-prefixed err lines, card `✗ failed | ui | build`, row idle) — PASS. |
| 5 | SC4a/BLD-04 — The Rollback button restores source mode | ✓ VERIFIED | `lib/spm_cache/installer/rollback.rb:19-26` `perform_install` (`restore_packages` + `remove_proxy`, unmodified this phase) spawned via the same `Web::Jobs` seam (`SCOPES['rollback'] => ['rollback']`) behind the two-step inline confirm bar (`index.html:41-45`, `app.js:385-399` — focus→Cancel, Tab reaches Confirm per the `0962522` DOM-order fix, Confirm POSTs `/api/rollback`). Browser-true: 15-06-SUMMARY.md Row 5 (byte-exact confirm sentence, correct keyboard order after the probe-caught fix, spawned rollback completes, sandbox removed on disk) — PASS. |
| 6 | SC4b/BLD-04/CP4 — Rollback now acquires the build lock; the lock-free rollback race is closed | ✓ VERIFIED | `lib/spm_cache/installer/rollback.rb:19-26` — `acquire_build_lock` runs BEFORE `remove_proxy`'s `rm_rf`, `release_build_lock` runs in `perform_install`'s `ensure`. Behavioral proof (ordering + cleanup invariants, not presence alone): `spec/installer_rollback_lock_spec.rb` — "holds the lock BEFORE touching the project: the sandbox survives while a holder owns the flock, and is gone once it releases" (128), "genuinely holds the flock across the critical section: non-blocking probe fails during, succeeds after" (147), "releases on raise: the raise propagates unchanged and a subsequent acquire succeeds" (160), "emits no notice on the free path (byte-identical to today)" (182) — all passing. Browser-true: 15-06-SUMMARY.md Row 5 (spawned rollback's own stream shows the lock-wait announce under a foreign holder, then takes the lock and completes after release) — PASS. |

**Score:** 6/6 truths verified (0 present-but-behavior-unverified)

### Required Artifacts

| Artifact | Expected | Status | Details |
|---|---|---|---|
| `lib/spm_cache/web/jobs.rb` | Array-argv spawner, frozen scope table, Mutex slot, derive-based liveness | ✓ VERIFIED | Exists, substantive, wired into `Router#initialize` (`router.rb:57`), exercised by `spec/web_jobs_spec.rb` (16 examples, 0 failures). |
| `lib/spm_cache/web/router.rb` | `/api/build` (build/rebuild only) + `/api/rollback` (fixed scope) dispatch, `api_mutate` reason vocabulary | ✓ VERIFIED | `dispatch` (lines 108-118), `api_mutate` (lines 258-306) with `allowed_scopes:` narrowing (CR-01 fix); exercised by `spec/web_build_routes_spec.rb`. |
| `lib/spm_cache/web/read_models/runs.rb` | `derive_for_pid`/`pid_alive?` public, consumed by the slot | ✓ VERIFIED | `jobs.rb:88-89` calls both; public per the diff (IN-01 documents the inherent, self-correcting pid-reuse edge — no code gap). |
| `lib/spm_cache/installer/rollback.rb` | Build-lock acquire/release around `perform_install` | ✓ VERIFIED | Lines 19-58; ensure-released, byte-frozen wait announce. |
| `lib/spm_cache/installer/build.rb` + `lib/spm_cache/command/build.rb` | `--rebuild` flag widening the candidate set to the full cachemap hit set | ✓ VERIFIED | `installer/build.rb:13-40` (`@rebuild` kwarg, `missed.concat(@cachemap.hit) if @rebuild`); `command/build.rb:13-31` (`--rebuild` option, pass-through). |
| `lib/spm_cache/main.rb` | `SPM_CACHE_TRIGGER` whitelist → run header `trigger` | ✓ VERIFIED | Line 34: `ENV['SPM_CACHE_TRIGGER'] == 'ui' ? 'ui' : 'terminal'` — closed two-way map. |
| `lib/spm_cache/web/assets/{index.html,app.js,log.js,styles.css}` | Controls row + confirm bar + state machine + progress coupling | ✓ VERIFIED | Controls row is the first child of `#log-body` (`index.html:29-40`); confirm bar DOM order Cancel-before-Confirm (post `0962522`); `app.js` state machine (`clickBuild`, `settle`, `spm-run-progress` listener); `log.js` `emitProgress`/`WAIT_LINE`/`pinned` guard (WR-01 fix). No new asset files. |
| `README.md` | CLI Reference row for `--rebuild` | ✓ VERIFIED | Line 147: `` `spm-cache build [TARGETS] [--rebuild]` `` \| `--rebuild` also rebuilds cache hits. |
| `spec/web_jobs_spec.rb`, `spec/web_build_routes_spec.rb`, `spec/installer_rollback_lock_spec.rb`, `spec/run_log_trigger_spec.rb`, `spec/command_build_rebuild_spec.rb`, `spec/web_frontend_spec.rb` | New/extended coverage for every truth above | ✓ VERIFIED | Ran directly (see Behavioral Spot-Checks): 50/50 examples pass across the first five files; `web_frontend_spec.rb` included in the 984-example full-suite green run. |

### Key Link Verification

| From | To | Via | Status | Details |
|---|---|---|---|---|
| `Router#initialize` | `Web::Jobs` | `@jobs = jobs \|\| Web::Jobs.new(config: config)` (router.rb:69) | ✓ WIRED | Same seam as `@events`; `Command::Web#build_server` needed no edit. |
| `POST /api/build` \| `/api/rollback` | `Jobs#spawn_run` | `api_mutate` → `@jobs.spawn_run(scope:)` (router.rb:284) | ✓ WIRED | Only reachable path from request to spawn; scope validated against `allowed_scopes` AND `Jobs::SCOPES.key?` before the call. |
| `Web::Jobs` child process | Rollback lock | Spawns `bin/spm-cache rollback` which invokes `Installer::Rollback#perform_install` | ✓ WIRED | Confirmed both by unit specs and the browser probe's stream-visible lock-wait announce (Row 5). |
| `app.js` controls | `/api/build`, `/api/rollback` | `requestPost()` with `X-SPM-Token` header, JSON body | ✓ WIRED | `app.js:337-378`; token via header only, never query param or body field. |
| `log.js` (`appendBody`, `onRunEnd`) | `app.js` (`spm-run-progress` listener) | One DOM `CustomEvent` (A10 coupling), gated by `pinned` (WR-01 fix) | ✓ WIRED | No second `EventSource`, no new polling channel; verified by source-pin specs and the browser probe. |
| `Router` 2xx envelope | `app.js` waiting entry-assist | `data.lock` (`ReadModels::Runs.lock_state`) → `CTRL.wait` | ✓ WIRED | Row 3 of the probe shows the wait rendering within 600ms, before any stream line arrives. |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|---|---|---|---|---|
| 2xx build/rollback envelope | `data.lock` | `ReadModels::Runs.lock_state(config: @config)` — a live re-derivation each request | Yes (re-reads the flock file state on every call) | ✓ FLOWING |
| Row wait/in-flight message | `msg.textContent` | `CTRL.wait` / `CTRL.inflight[verb]` driven by `data.lock.state` or the `spm-run-progress` event's `phase` | Yes (both sources are server/stream-derived, never hardcoded) | ✓ FLOWING |
| Slot liveness (`held?`) | `alive` | `ReadModels::Runs.derive_for_pid` (run_end authoritative) with `pid_alive?` fallback | Yes | ✓ FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|---|---|---|---|
| Phase-15 unit/integration specs are green | `bundle exec rspec spec/web_jobs_spec.rb spec/web_build_routes_spec.rb spec/installer_rollback_lock_spec.rb spec/run_log_trigger_spec.rb spec/command_build_rebuild_spec.rb` | 50 examples, 0 failures | ✓ PASS |
| Full suite green at HEAD (35ac544) | `bundle exec rspec` | 984 examples, 0 failures | ✓ PASS |
| Mutex-atomic race (8 real threads) | `spec/web_jobs_spec.rb:176` (included in the run above) | exactly 1 non-nil spawn among 8 racers | ✓ PASS |
| Rollback lock ordering + release-on-raise | `spec/installer_rollback_lock_spec.rb:128,160` (included in the run above) | sandbox survives while held, gone after release; raise still releases | ✓ PASS |

Browser-interactive behaviors (click→spawn→stream→busy→confirm→ended, focus/keyboard order, cross-tab visibility) are not exercisable by this text-only verification pass; per this run's evidence sources, they route through the already-recorded D-15 agent-browser probe (`15-06-SUMMARY.md`, 2026-09-02): all 7 rows PASS, with one probe-caught keyboard-order defect (confirm-bar Tab order) fixed spec-first (commit `0962522`) and re-verified PASS before the plan closed. This recording constitutes genuine behavioral evidence (real headless-Chromium session against a real server and scratch project, with verbatim observations, not code presence) and is treated as the resolved human-verification pass for this phase's UI truths — no new human-verification items are opened by this report.

### Requirements Coverage

| Requirement | Source Plan(s) | Description | Status | Evidence |
|---|---|---|---|---|
| BLD-01 | 15-01, 15-03, 15-04, 15-05 | Build/Rebuild button with scope selection spawns the real CLI subprocess (array argv, pgroup) and streams output; second concurrent UI build rejected (single slot) | ✓ SATISFIED | Truths 1, 2 above. |
| BLD-02 | 15-01, 15-04, 15-05 | Busy/waiting state derived from the build lock is visible in the UI | ✓ SATISFIED | Truth 3 above. |
| BLD-03 | 15-05 | Build failures surface with exit status and highlighted errors | ✓ SATISFIED | Truth 4 above (inherited Phase-14 banner chain, browser-proven for a UI-triggered run). |
| BLD-04 | 15-02, 15-04, 15-05 | Rollback button restores source mode; rollback acquires the build lock | ✓ SATISFIED | Truths 5, 6 above. |

Note (non-blocking, administrative): `.planning/REQUIREMENTS.md`'s traceability table (lines 97-100) still marks BLD-01..04 `Pending` — a documentation-lifecycle field, not a code gap; the actual implementation and test evidence above satisfy all four requirements.

### Anti-Patterns Found

None. Scanned every file this phase modified (`lib/spm_cache/web/jobs.rb`, `router.rb`, `read_models/runs.rb`, `assets/{app.js,index.html,styles.css,log.js}`, `installer/{rollback.rb,build.rb}`, `command/build.rb`, `main.rb`) for `TODO|FIXME|XXX|TBD|placeholder|not yet implemented|console.log`. The only two hits (`log.js:27,487`) are code comments referring to the legitimate dropdown placeholder *option entries* ("No runs yet", "Loading…"), not debt markers or stubs.

### Code Review Resolution

`15-REVIEW.md` (deep, 11 files) found 1 critical + 1 warning + 1 info:
- **CR-01** (`/api/build` accepted `scope: "rollback"`, bypassing the per-route whitelist) — fixed, commit `12fdd51`; verified in code above (`allowed_scopes: %w[build rebuild]`) and by a dedicated regression row in `spec/web_build_routes_spec.rb`'s `bad_scope` matrix.
- **WR-01** (controls row could reset from an unrelated displayed run's `run_end`) — fixed, commit `165e88e`; verified in code above (`log.js:589` `if (pinned) return;`).
- **IN-01** (pid-reuse liveness false-positive window) — documented, no code change; theoretical, self-correcting, pre-dates Phase 15 (inherited pattern from `run_log.rb`). Not a gap.

`15-REVIEW.md` frontmatter: `status: resolved`.

### Human Verification Required

None. All interactive/browser-dependent behavior was already exercised and recorded via the D-15 agent-browser probe (`15-06-SUMMARY.md`, 7/7 rows PASS, 2026-09-02) — see Behavioral Spot-Checks above.

### Gaps Summary

No gaps. All 6 derived observable truths (covering ROADMAP SC1-4 and REQUIREMENTS BLD-01..04) are verified against actual code, with behavioral evidence (unit tests exercising concurrency/ordering invariants, plus the recorded real-browser probe) rather than presence alone. Full suite is green (984/0) at HEAD `35ac544`. Code review's one critical and one warning finding are fixed and regression-tested; the one info finding is a documented, pre-existing, self-correcting edge case.

---

_Verified: 2026-09-02T00:00:00Z_
_Verifier: Claude (gsd-verifier)_
