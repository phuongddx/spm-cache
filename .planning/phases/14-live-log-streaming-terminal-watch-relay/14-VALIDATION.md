---
phase: "14"
slug: "live-log-streaming-terminal-watch-relay"
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
# audit-milestone §5.5 distinguishes NOT-VALIDATED (draft) from PARTIAL (validated + nyquist_compliant: false) (#2117)
status: draft
nyquist_compliant: false
wave_0_complete: false
created: "2026-09-01"
---

# Phase 14 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Source: `14-RESEARCH.md` § Validation Architecture (all seams anchored at file:line; transport behaviors machine-probed 2026-09-01).

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | RSpec ~> 3.12 (dev dep; hermetic suite — 787 examples at Phase 13 close) |
| **Config file** | none beyond `.rspec` defaults (per `.planning/codebase/TESTING.md`) |
| **Quick run command** | `bundle exec rspec spec/events_tailer_spec.rb spec/events_broadcaster_spec.rb` |
| **Full suite command** | `bundle exec rspec` (Makefile `make test`) |
| **Estimated runtime** | ~60–75 s full suite (Phase 13 measured 55.4 s; the SSE integration row adds a bounded-shutdown example) |

---

## Sampling Rate

- **After every task commit:** the new spec files for the task's module (fast, hermetic; no sockets except the single integration example)
- **After every plan wave:** `bundle exec rspec` (full suite; hermetic posture intact — CP7)
- **Before `/gsd-verify-work`:** full suite green AND the recorded D-14 agent-browser probe executed
- **Max feedback latency:** 60 s

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 14-01-T1 | 14-01 | 1 | LOGS-03 | — | Byte-offset ids monotonic; resume-at-id yields exact next line (incl. multi-byte UTF-8); partial trailing line buffered until newline | unit (tmpdir) | `bundle exec rspec spec/events_tailer_spec.rb` | ❌ Wave 0 | ⬜ pending |
| 14-01-T3 | 14-01 | 1 | LOGS-02 / D-04 | — | Discovery: new run file → switch notice + follow; retention prune of served file → fd survives; fresh connect to pruned file → notice + newest fallback | unit (tmpdir, real unlink) | `bundle exec rspec spec/events_tailer_spec.rb` | ❌ Wave 0 | ⬜ pending |
| 14-01-T2 | 14-01 | 1 | LOGS-02 / CP11 | — | Broadcaster: queue cap → drop-oldest + "N lines dropped" notice; shutdown sentinel ends every client loop; heartbeat on pop timeout | unit | `bundle exec rspec spec/events_broadcaster_spec.rb` | ❌ Wave 0 | ⬜ pending |
| 14-01-T1 | 14-01 | 1 | LOGS-03 / CP13 | T-13-04 | Route always 200 + `text/event-stream` + `no-store` (NEVER 204/503 — amended CP11); token gate 401 rows; Host/Origin rows extend the 13-04 matrix; `Last-Event-ID` regex + containment (traversal fixtures → fresh replay, file never opened) — extended by 14-03-T2 (hello derivation + `?run=`) | unit + integration row | `bundle exec rspec spec/web_events_route_spec.rb` | ❌ Wave 0 | ⬜ pending |
| 14-03-T1 | 14-03 | 2 | LOGS-05 / CP10 | — | State derivation: thread-held flock → probe reports held; header-pid alive + no run_end → running; dead pid + no exit line → "interrupted — exit unknown" (CP14); free lock → idle; held + unattributable → unknown holder | unit (thread-held flock, tmpdir) | `bundle exec rspec spec/web_runs_read_model_spec.rb` | ❌ Wave 0 | ⬜ pending |
| 14-03-T1 | 14-03 | 2 | D-12 | — | `/api/runs`: newest-first listing with identity + status per entry, zero storage | unit | `bundle exec rspec spec/web_runs_read_model_spec.rb` | ❌ Wave 0 | ⬜ pending |
| 14-02-T1 | 14-02 | 1 | D-05 | — | Both flock sites announce "Waiting for build lock…" exactly when a thread holds the lock, then block; free-lock path byte-identical to today — tee-landing proof in 14-02-T2 | unit (`$stdout`-swap, doctor_spec convention) | `bundle exec rspec spec/installer_lock_notice_spec.rb` | ❌ Wave 0 | ⬜ pending |
| 14-03-T3 | 14-03 | 2 | LOGS-03 + WEB-03 | — | THE one port-0 integration boot: raw TCPSocket GET `/api/events` → headers + hello + replayed fixture lines; reconnect with `Last-Event-ID` resumes exactly; **`server.shutdown` with an open stream joins within bound** (sentinel proof — WEBrick joins connection threads, server.rb:210) | integration (port 0, loopback) | `bundle exec rspec spec/web_integration_spec.rb` | extend Wave 0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*
*(Task IDs filled by the planner; the requirement → spec-file mapping above is fixed by research and must be preserved.)*

---

## Wave 0 Requirements

- [ ] `spec/events_tailer_spec.rb` — offsets, replay, discovery, retention interplay
- [ ] `spec/events_broadcaster_spec.rb` — bounds, drops, shutdown sentinel, heartbeat
- [ ] `spec/web_events_route_spec.rb` — SSE route rows + `Last-Event-ID` validation matrix
- [ ] `spec/web_runs_read_model_spec.rb` — CP10 derivation + D-12 listing
- [ ] `spec/installer_lock_notice_spec.rb` — D-05 at both flock sites
- [ ] extend `spec/web_integration_spec.rb` + `spec/support/web_server_boot.rb` — SSE integration row incl. shutdown-within-bound assertion
- [ ] Fixtures: tmpdir runs-dirs with hand-authored JSONL (header/body/exit shapes per Phase 12 vocabulary); thread-held flock helper

---

## Manual-Only Verifications

> The repo has no JS runtime; SSE client behavior, live rendering, and reconnect semantics are verified by an **agent-driven real browser** (locked as D-14 — this net caught Phase 13's ship-blocking G-13-1 that 119 green examples missed).

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Live render of a terminal-started run | LOGS-02, LOGS-04 | Requires a real EventSource client + real CLI run | Boot `spm-cache web --no-open --port=0` against a real project; read port/token from `.spm-cache/web/server.json`; open the dashboard in a real (headless) browser; start `spm-cache use`/`build` in a terminal; assert the stream renders live with identity card, anchor rail, and follow-tail |
| Mid-run replay in a second tab | LOGS-03 | Browser-side EventSource + replay-from-0 | With a run in flight, open a second dashboard tab; assert it replays the run from the first line, then follows |
| Reconnect without loss or duplication | LOGS-03 | Real network drop semantics | Mid-run: `kill -9` the server, restart it, reopen/resume the tab; assert `Last-Event-ID` resume yields no lost and no duplicated lines |
| Failure surfacing | LOGS-05, D-03 | Visual judgment vs UI contract | Force a failing run; assert sticky banner with exit status, jump-to-first-error anchor, and identity-card status dot flipping to ✗ |
| Filter/banner interaction | D-09, D-10 | Interaction semantics | Filter to package X; force a failure in package Y; assert the banner appears anyway and its jump clears the filter |
| Watch-cycle relay + auto-switch | LOGS-04, D-04 | Two-source live behavior | With `spm-cache watch` running, trigger a cycle while viewing an older run; assert auto-switch with the "switched to new run — previous: <run-id>" notice |
| Lock-wait attribution | D-05, CP10 | Cross-process contention | Hold the build lock from a terminal run; start a second run; assert the blocked run shows "waiting for build lock…" inline |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60 s
- [ ] `nyquist_compliant: true` set in frontmatter
- [ ] Manual-only table executed and recorded (7 items above, incl. the D-14 agent-browser probe)

**Approval:** pending
