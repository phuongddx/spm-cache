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
| 15-01-T2 | 15-01 | 1 | BLD-01 | T-15-02, T-15-05 | Spawn shape: ARRAY argv `[RbConfig.ruby, BIN, verb…]` (never a shell string), `chdir` = config.project_dir, env carries `SPM_CACHE_TRIGGER=ui`, `pgroup: true` + `Process.detach`, `out:/err: → File::NULL` — asserted via an injectable FAKE-BIN script's side effects | unit (fake-bin fixture) | `bundle exec rspec spec/web_jobs_spec.rb` | ❌ Wave 0 | ⬜ pending |
| 15-01-T2 | 15-01 | 1 | BLD-01 / D-05 | T-15-03 | Single slot: Mutex-atomic check-then-claim (concurrent-thread POST race cannot double-spawn); release derives from run_end/pid (CP14-honest); second POST → 409 envelope with machine-readable reason; build+rollback SHARE the slot (UI-SPEC A1) | unit | `bundle exec rspec spec/web_jobs_spec.rb` | ❌ Wave 0 | ⬜ pending |
| 15-04-T1, 15-04-T2 | 15-04 | 2 | BLD-01 / D-04 | CP13, V5, T-15-16..T-15-21 | Route matrix: POST-only (404 on GET), token gate 401 rows, Host/Origin inherited from the structural gate, `scope` whitelist `{"build","rebuild"}` → 400 on anything else, malformed JSON body → 400, 2xx envelope carries `lock:` snapshot, 409 reason never leaks into display copy | unit | `bundle exec rspec spec/web_build_routes_spec.rb` | ❌ Wave 0 | ⬜ pending |
| 15-02-T1 | 15-02 | 1 | BLD-04 / CP4 | T-15-08, T-15-09 | Rollback lock: acquires the build flock BEFORE the sandbox `rm_rf` (ordering asserted), releases on raise (ensure shape, build.rb:97-102), announces `Waiting for build lock…` byte-exact exactly once under thread-held flock, free-lock path byte-identical | unit (`$stdout`-swap + thread-held flock — installer_lock_notice_spec conventions) | `bundle exec rspec spec/installer_rollback_lock_spec.rb` | ❌ Wave 0 | ⬜ pending |
| 15-02-T2 | 15-02 | 1 | D-03 / LOGS-05 | T-15-10, T-15-11 | Trigger marker: `SPM_CACHE_TRIGGER=ui` → run_start header `trigger:'ui'`; unset/other value → `'terminal'` (whitelist normalization, never passthrough); the marker never alters CLI behavior | unit | `bundle exec rspec spec/run_log_trigger_spec.rb` | ❌ Wave 0 | ⬜ pending |
| 15-01-T1 (tracer) | 15-01 | 1 | BLD-01 + WEB-03 | T-15-01, T-15-04 | THE integration row (extends `web_integration_spec.rb` / `WebServerBoot`): POST spawns a fake-bin build → its run log appears via /api/events (switch + hello trigger 'ui') → `server.shutdown` with the build IN FLIGHT completes within bound (probed P5: exit 0 in 18 ms — the detached child is neither joined nor killed) | integration (port 0, loopback) | `bundle exec rspec spec/web_integration_spec.rb` | extend Wave 0 | ⬜ pending |
| 15-03-T1, 15-03-T2 (+ 15-04-T1 for the scope→argv mapping) | 15-03 | 1 | D-01 (A8) | T-15-13, T-15-15 | Rebuild mechanism — planner pinned `build --rebuild` (a flag on the existing verb, not a new verb): argv maps scope `rebuild` → the forced-rebuild CLI surface; the `@cachemap.hit` set is rebuilt, not skipped | unit | `bundle exec rspec spec/command_build_rebuild_spec.rb` | ❌ Wave 0 | ⬜ pending |
| 15-05-T1, 15-05-T2, 15-05-T3 | 15-05 | 3 | BLD-01 / BLD-02 / BLD-03 | T-15-22..T-15-27 | Controls surface pins (added by the planner; no research mapping is remapped): served DOM order + byte-exact copy, POST helper returning status (409 branchable), state machine transitions with a message in every disabled state, confirm-bar swap + focus semantics, the three `spm-run-progress` emission points, and the 14-UI-REVIEW polish folds (W1/W3/W4/W5/M1) | unit (byte/source pins — no JS runtime in CI; the browser net is the manual table) | `bundle exec rspec spec/web_frontend_spec.rb` | exists (extend) | ⬜ pending |

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
| ✅ Build click → run appears with `ui` badge and streams (2026-09-02, agent-browser) | BLD-01, D-03, D-09 | Real EventSource + real spawn | PASS — instant disable ×3 + `Building…`; auto-switch delivered run 83196 with verbatim `ui` badge in card + dropdown; streamed to `Build complete!`; row idle. Evidence: 15-06-SUMMARY.md Row 1 |
| ✅ Second UI build rejected inline (409) (2026-09-02, agent-browser) | BLD-01 / D-05 | Cross-request UI state | PASS — tab B's click during the parked run: 409, pinned busy sentence inline, no dialog, no second run file. Evidence: Row 2 |
| ✅ Terminal-held lock → visible queue, buttons stay enabled (2026-09-02, agent-browser) | BLD-02 / D-06, A3 | Cross-process contention | PASS — POST 2xx under foreign-held lock; row wait message from the POST lock snapshot (<600ms) + identical in-stream announce line; released → proceeded, cleared, ✓. Evidence: Row 3 |
| ✅ Rebuild all → distinct verb + argv proof (2026-09-02, agent-browser) | BLD-01 / D-01 (A8) | Visual + spawn identity | PASS — `Rebuilding all…`; argv row `spm-cache build --rebuild`; real rebuild with package chips; completed ✓. Evidence: Row 4 |
| ✅ Rollback confirm bar (D-08 + A6) (2026-09-02, agent-browser; after spec-first fix 0962522) | BLD-04 | Focus/keyboard semantics | PASS — byte-exact sentence, focus→Cancel, Tab→Confirm (after the DOM-order fix), Cancel→focus back to Rollback; Confirm→spawned rollback's stream showed the lock wait then `Rollback complete!`; sandbox removed on disk. Evidence: Row 5 |
| ✅ Failing build → banner chain (BLD-03) (2026-09-02, agent-browser) | BLD-03 / D-09 | Visual judgment vs 14 contract | PASS — forced rebuild of a compile-broken package: `Run failed — exit status 1` banner + working jump, 82 ✗-prefixed err lines, ✗ card, row idle for one-click retry. Evidence: Row 6 |
| ✅ Cross-tab slot visibility (D-05 / A1) (2026-09-02, agent-browser) | D-05 / A1 | Two-tab state | PASS — tab B saw the parked run unaided; its Build attempt got the inline 409 busy message. Evidence: Row 7 |

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
