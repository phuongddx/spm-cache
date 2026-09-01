---
phase: "15"
slug: "ui-build-controls"
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
# audit-milestone §5.5 distinguishes NOT-VALIDATED (draft) from PARTIAL (validated + nyquist_compliant: false) (#2117)
status: draft
nyquist_compliant: false
wave_0_complete: false
created: "2026-09-02"
---

# Phase 15 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Source: `15-RESEARCH.md` § Validation Architecture (all seams anchored at file:line; spawn/pgroup/WEB-03 semantics machine-probed 2026-09-02 — probes P1-P8).

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | RSpec ~> 3.12 (dev dep; hermetic suite per CP7) |
| **Config file** | none beyond `.rspec` defaults (per `.planning/codebase/TESTING.md`) |
| **Quick run command** | `bundle exec rspec spec/web_jobs_spec.rb spec/web_build_routes_spec.rb spec/installer_rollback_lock_spec.rb spec/run_log_trigger_spec.rb` |
| **Full suite command** | `bundle exec rspec` (Makefile `make test`) |
| **Estimated runtime** | new specs are hermetic units (fake-bin + tmpdir, no real xcodebuild); integration row extends the ONE port-0 boot |

---

## Sampling Rate

- **After every task commit:** the new spec files for the task's module (fast, hermetic)
- **After every plan wave:** `bundle exec rspec` (full suite; hermetic posture intact — CP7)
- **Before `/gsd-verify-work`:** full suite green AND the manual/agent-browser probe table executed
- **Max feedback latency:** 60 s

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| (planner) | — | 0 | BLD-01 | — | Spawn shape: ARRAY argv `[RbConfig.ruby, BIN, verb…]` (never a shell string), `chdir` = config.project_dir, env carries `SPM_CACHE_TRIGGER=ui`, `pgroup: true` + `Process.detach`, `out:/err: → File::NULL` — asserted via an injectable FAKE-BIN script's side effects | unit (fake-bin fixture) | `bundle exec rspec spec/web_jobs_spec.rb` | ❌ Wave 0 | ⬜ pending |
| (planner) | — | 0 | BLD-01 / D-05 | — | Single slot: Mutex-atomic check-then-claim (concurrent-thread POST race cannot double-spawn); release derives from run_end/pid (CP14-honest); second POST → 409 envelope with machine-readable reason; build+rollback SHARE the slot (UI-SPEC A1) | unit | `bundle exec rspec spec/web_jobs_spec.rb` | ❌ Wave 0 | ⬜ pending |
| (planner) | — | 0 | BLD-01 / D-04 | CP13, V5 | Route matrix: POST-only (404 on GET), token gate 401 rows, Host/Origin inherited from the structural gate, `scope` whitelist `{"build","rebuild"}` → 400 on anything else, malformed JSON body → 400, 2xx envelope carries `lock:` snapshot, 409 reason never leaks into display copy | unit | `bundle exec rspec spec/web_build_routes_spec.rb` | ❌ Wave 0 | ⬜ pending |
| (planner) | — | 0 | BLD-04 / CP4 | — | Rollback lock: acquires the build flock BEFORE the sandbox `rm_rf` (ordering asserted), releases on raise (ensure shape, build.rb:97-102), announces `Waiting for build lock…` byte-exact exactly once under thread-held flock, free-lock path byte-identical | unit (`$stdout`-swap + thread-held flock — installer_lock_notice_spec conventions) | `bundle exec rspec spec/installer_rollback_lock_spec.rb` | ❌ Wave 0 | ⬜ pending |
| (planner) | — | 0 | D-03 / LOGS-05 | — | Trigger marker: `SPM_CACHE_TRIGGER=ui` → run_start header `trigger:'ui'`; unset/other value → `'terminal'` (whitelist normalization, never passthrough); the marker never alters CLI behavior | unit | `bundle exec rspec spec/run_log_trigger_spec.rb` | ❌ Wave 0 | ⬜ pending |
| (planner) | — | 1 | BLD-01 + WEB-03 | — | THE integration row (extends `web_integration_spec.rb` / `WebServerBoot`): POST spawns a fake-bin build → its run log appears via /api/events (switch + hello trigger 'ui') → `server.shutdown` with the build IN FLIGHT completes within bound (probed P5: exit 0 in 18 ms — the detached child is neither joined nor killed) | integration (port 0, loopback) | `bundle exec rspec spec/web_integration_spec.rb` | extend Wave 0 | ⬜ pending |
| (planner) | — | 1 | D-01 (A8) | — | Rebuild mechanism (whatever the planner pins, e.g. `build --rebuild`): argv maps scope `rebuild` → the forced-rebuild CLI surface; the `@cachemap.hit` set is rebuilt, not skipped | unit | per planner's CLI-surface spec file | ❌ Wave 0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*
*(Task IDs filled by the planner; the requirement → spec-file mapping above is fixed by research and must be preserved.)*

---

## Wave 0 Requirements

- [ ] `spec/web_jobs_spec.rb` — spawn shape (argv/cwd/env/pgroup/detach/null-stdio via fake-bin side effects), slot atomicity, derive-based release, 409
- [ ] Fake-bin fixture script (writes a run log with header+run_end; `sleep` mode for in-flight integration row)
- [ ] `spec/web_build_routes_spec.rb` — token/verb/body/409/lock-snapshot matrix (13-04 posture)
- [ ] `spec/installer_rollback_lock_spec.rb` — order-before-rm_rf, release-on-raise, byte-exact announce
- [ ] `spec/run_log_trigger_spec.rb` — env normalization → header trigger
- [ ] Extend `spec/web_integration_spec.rb` (+ `spec/support/web_server_boot.rb` as needed) — POST row + shutdown-with-in-flight-build exit-0 assertion

---

## Manual-Only Verifications

> The repo has no JS runtime; the controls' client behavior is verified by an **agent-driven real browser** — the D-14 probe-net pattern (14's net caught G-13-1 that 119 green examples missed). Reference project + scratch project as in 14-05.

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| ⬜ Build click → run appears with `ui` badge and streams | BLD-01, D-03, D-09 | Real EventSource + real spawn | Open dashboard (token URL) in headless Chromium against a scratch project; click `Build`; assert: buttons disable instantly, `Building…` inline message, run arrives via auto-switch with verbatim `ui` badge in card + dropdown, lines stream live |
| ⬜ Second UI build rejected inline (409) | BLD-01 / D-05 | Cross-request UI state | During the in-flight run, force a second click (re-enable via devtools if needed or second tab): 409 busy message renders INLINE in the message slot (exact pinned copy), never alert(), buttons re-enable per spec |
| ⬜ Terminal-held lock → visible queue, buttons stay enabled | BLD-02 / D-06, A3 | Cross-process contention | Hold `.spm-cache-build.lock` from a terminal thread/ruby one-liner; click `Build`: buttons NOT disabled-by-lock, POST 2xx, row shows `Waiting for build lock…` (from POST lock snapshot or announce line), identical line renders in-stream; release the lock → run proceeds, message clears on the run's next line |
| ⬜ Rebuild all → distinct verb + argv proof | BLD-01 / D-01 (A8) | Visual + spawn identity | Click `Rebuild all`; in-flight message `Rebuilding all…`; identity card argv row shows the forced-rebuild argv; run completes |
| ⬜ Rollback confirm bar (D-08 + A6) | BLD-04 | Focus/keyboard semantics | Click `Rollback` → confirm bar swaps in with exact copy, focus lands on `Cancel`; `Tab` reaches `Confirm`; Cancel → back to row, focus restored to `Rollback`; Confirm → buttons disable, POST, row in-flight `Restoring source mode…`; verify the spawned rollback acquires the lock (its stream shows the flock path) |
| ⬜ Failing build → banner chain (BLD-03) | BLD-03 / D-09 | Visual judgment vs 14 contract | Spawn a build that fails (e.g. corrupt scratch project): sticky `Run failed — exit status N` banner, err lines `✗`-prefixed in fail color, jump-to-first-error works; row returns to idle (buttons re-enabled for one-click retry) |
| ⬜ Cross-tab slot visibility | D-05 / A1 | Two-tab state | Tab A spawns; Tab B (opened before) attempts a build → 409 busy message; both tabs see the run via switch event |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60 s
- [ ] `nyquist_compliant: true` set in frontmatter
- [ ] Manual-only table executed and recorded (7 rows above, D-14 pattern)

**Approval:** pending
