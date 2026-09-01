---
gsd_state_version: 1.0
milestone: v0.5.0
milestone_name: Web Interface
current_phase: 15 — UI Build Controls
current_phase_name: UI Build Controls
status: planning
stopped_at: Phase 15 context gathered
last_updated: "2026-09-01T16:53:57.634Z"
last_activity: 2026-09-01
last_activity_desc: Phase 14 complete, transitioned to Phase 15
state_head: 842b7381dca3a4ff73541f0f8a57848b78e38bb4
progress:
  total_phases: 5
  completed_phases: 3
  total_plans: 15
  completed_plans: 15
  percent: 60
---

# Project State: spm-cache

**Initialized:** 2026-08-10
**Current Phase:** 15 — UI Build Controls
**Project Mode:** Horizontal Layers
**Direction:** v0.5.0 Web Interface — localhost dashboard, live log streaming, per-package toggles

## Project Reference

See: .planning/PROJECT.md (updated 2026-09-01)

**Core value:** Reduce Xcode clean build times by serving prebuilt SPM dependency binaries transparently, with automatic fallback to source on cache miss — so a cache hit never breaks a build.
**Current focus:** Phase 14 — Live Log Streaming + Terminal/Watch Relay

v0.4.0 shipped and released 2026-08-31 (first fully-green tap publish in project history). Full milestone history: `.planning/MILESTONES.md`.

## Current Position

Phase: 14 (Live Log Streaming + Terminal/Watch Relay) — PLANNED, ready to execute
Plan: Not started
Status: Ready to plan
Last activity: 2026-09-01 — Phase 14 complete, transitioned to Phase 15

Progress: [████░░░░░░] 40%

## v0.5.0 Phase Status

| Phase | Name | Status | Branch |
|-------|------|--------|--------|
| 12 | Run-Log Capture Foundation | Complete (2026-09-01) | gsd/v0.5.0-web-interface |
| 13 | Server Skeleton + Read-Only Dashboard | Complete (2026-09-01) | gsd/v0.5.0-web-interface |
| 14 | Live Log Streaming + Terminal/Watch Relay | Planned — 5 plans, ready to execute | gsd/v0.5.0-web-interface |
| 15 | UI Build Controls | Not started | — |
| 16 | Package Toggles + Panel Completion | Not started | — |

Hard chain: 12 → 13 → 14 → 15 → 16.

Research flags: **Phase 14 — SATISFIED 2026-09-01** (`14-RESEARCH.md`, HIGH confidence: webrick 1.9.2 gem source read at file:line + three transport behaviors machine-probed live; CP5/CP6/CP10/CP11/CP12 all addressed). Two milestone-research corrections came out of it: the "503 + `Retry:`, never 204" SSE clause is FALSIFIED (any non-200 permanently kills EventSource — always answer 200 and hold), and WEBrick's accept loop joins connection threads on shutdown, so an SSE body proc needs a shutdown sentinel or `server.shutdown` hangs and breaks WEB-03's exit-0 contract. Phases 12/13/15/16 reuse established code-anchored patterns.

## v0.5.0 Planning Context

- Research: `.planning/research/SUMMARY.md` (HIGH confidence). Key verdicts baked into the roadmap:
  - **webrick is the ONLY new runtime dependency**; its gemspec declaration is load-bearing (`require` fails without it on all target rubies — machine-probed).
  - **File-tail JSONL run logs** as the relay transport (overrides STACK.md's UDS; UDS = documented fallback). Confirm during Phase 12 planning.
  - **graph.json has NO edges** — ARCHITECTURE.md's cytoscape-edges claim was falsified against source (dead `GraphGenerator.swift`, zero callers). v0.5 ships graph **nodes** only; edges need a Swift spike first (v2: WEB2-01).
  - **localhost is not a trust boundary** — Host/Origin + per-launch-token middleware ships with the Phase 13 skeleton, before any mutating endpoint exists.
- Open planning decisions: default port (7915 vs 7960, must skip AirPlay 5000/7000 — Phase 13); `--log-dir` stub repurpose-as-run-log-dir vs remove (Phase 12); mutation token depth (Phase 13); toggle yml-rewrite comment-loss surfaced in undo copy (Phase 16).
- Constraint: server is a stateless file reader + run-log tailer + CLI-subprocess spawner — never a second source of truth; the build flock stays the only mutex.

## Performance Metrics

Historical velocity (v0.3.0–v0.4.0, plans completed: 31):

| Plan | Duration | Plan | Duration |
|------|----------|------|----------|
| Phase 06 P01–P05 | ~83m total | Phase 10 P01–P03 | ~29m total |
| Phase 07 P01–P02 | ~2h55m (incl. 29m real xcodebuild) | Phase 11 P01–P03 | ~55m total |
| Phase 08 P01–P02 | sequential autonomous | Phase 09 P01–P03 | sequential autonomous |

Trend: stable (typical plan 10–35 min; outliers involve real xcodebuild runs).
**Per-Plan Metrics:**

| Plan | Duration | Tasks | Files |
|------|----------|-------|-------|
| Phase 12 P01 | 31m | 2 tasks | 7 files |
| Phase 12 P02 | 15min | 2 tasks | 2 files |
| Phase 12 P03 | 14min | 3 tasks | 7 files |
| Phase 12 P04 | 11min | 2 tasks | 8 files |
| Phase 12 P05 | 10min | 2 tasks | 4 files |
| Phase 13 P02 | 13min | 3 tasks | 15 files |
| Phase 13 P03 | 25min | 3 tasks | 6 files |
| Phase 13 P04 | 11min | 2 tasks | 2 files |

## Decisions

Full log: PROJECT.md Key Decisions table. Roadmap decisions (2026-08-31):

- v0.5.0 numbered Phases 12–16 — continues v0.4.0 (6–11); phase numbering never restarts.
- Run-log capture is Phase 12 alone (no server): the capture sink is the keystone every streaming feature consumes; hermetic and independently verifiable before any web layer exists.
- WEB-04 (Host/Origin + token middleware, offline assets) mapped to Phase 13 — the middleware must exist before the first mutating endpoint ships (Phase 15), not alongside it.
- Toggle phase (16) lands last: the only state-writing surface, reusing Phase 15's job machinery for "Apply now".
- [Phase 12]: Run-log run_start/run_end JSONL vocabulary + RunLog.current seam landed (Plan 12-01); body lines carry only ts/stream/text, never an event key (T-12-01 log-forging mitigation)
- [Phase 12]: Run-file naming %Y%m%dT%H%M%S%3NZ-<pid>-<verb>.jsonl (ms precision, deliberate deviation from RESEARCH Pattern 6 for same-second watch cycles)
- [Phase 12]: CLAide 1.1.0 rejects the space-separated --log-dir X form (Unknown option -> Help SystemExit 1); only --log-dir=X is valid CLI syntax — pre_scan still honors both forms so rejected invocations get logged
- [Phase 12]: [Phase 12]: Core::Sh popen3 branch gained live_log_out:/live_log_err: per-stream sinks (legacy live_log fallback) + 60-line failure_detail tails — the discarded-capture gap (detail-free live-mode raises) is closed; the run-log file still gets the full stream (D-05), only the raised message is bounded (Plan 12-02)
- [Phase 12]: [Phase 12]: every completed capture3 call records one structured {event: sh, ts, cmd, status} line via RunLog.current&.event (nil-safe, before any raise) — cmd+status only, never output text (Pitfall 5 / A2 / T-12-01 log-forging) (Plan 12-02)
- [Phase 12]: [Phase 12]: Run-log retention landed (Plan 12-03) — count+size hybrid (runs_keep 50 / runs_max_mb 500, Integer-coercing Config readers) pruned oldest-first at every RunLog.open after the header lands (D-06/D-07); budgets govern prior runs, current + live-pid runs are immune (Process.kill(0,pid) probe, CP14 at birth); T-12-04 disk-fill disposed
- [Phase 12]: [Phase 12]: Command::Init .gitignore now carries both 'spm-cache/' and '.spm-cache/' (one append-once entry per concern, D-02) — run logs stay out of VCS (T-12-05)
- [Phase 12]: D-04 event vocabulary frozen for Phase 14: package_start/package_end + phase markers (detect/integrate/build/fidelity) emitted from the pipeline's single choke point and the installers' existing boundaries (Plan 12-04)
- [Phase 12]: Build marker emits BEFORE the missed.empty? early return so a zero-pins run still records the phase (plan action text placed it after the 'Building N' line, unreachable on empty missed — resolved for behavior bullet + EDGE truth) (Plan 12-04)
- [Phase 12]: Buildable#xcodebuild activates Plan 12-02's sinks: per-stream live_log_out/live_log_err StreamSinks forwarded on both Sh.run calls when run_log is threaded; nil forwards no sink keys at all (byte-identical) (Plan 12-04)
- [Phase 12]: [Phase 12]: Watch cycles log via RunLog.cycle_wrapper at Command::Watch's factory seam — Core::Watcher untouched; each cycle is its own file (command watch / trigger watch / cycle true) with runs_dir resolved per cycle from pre_scan(argv).log_dir || Config#runs_dir (D-01 live at the watch surface) (Plan 12-05)
- [Phase 12]: [Phase 12]: D-08 no-allowlist spec-proven — exclusion set is exactly {web, watch} + --no-run-log (future-verb row mutation-proven); A6 legacy 'use --watch' = session-level 'use' run; A5 inter-cycle narrative terminal-only (D-09) (Plan 12-05)
- [Phase 13 — Server Skeleton + Read-Only Dashboard]: 13-03: offline frontend shipped as 4 static assets — vendored cytoscape v3.34.2 structurally pinned (version comment, >300KB, gemspec membership), first-party assets byte-gated for scheme URLs
- [Phase 13 — Server Skeleton + Read-Only Dashboard]: 13-03: app.js stored-XSS defense by construction — zero innerHTML, all dynamic text via textContent; stamps derive from server timestamps only (no Date.now())
- [Phase 13 — Server Skeleton + Read-Only Dashboard]: 13-04: exhaustive 25-cell route x auth matrix + CP13 drive-by shapes proven from ONE port-0 boot with zero production edits — middleware as shipped held every cell; packaging pins make the four-asset gem ship and webrick >= 1.8 < 2 un-regressible
- [Phase 13 — Server Skeleton + Read-Only Dashboard]: 13-05 (G-13-1 gap closure): index.html asset refs are RELATIVE `assets/…` (absolute `/assets/` would violate the locked relative-only offline negative pins); integration spec resolves every scanned ref with browser semantics (URI.join against the document origin) — test-side `/assets/#{ref}` re-prefixing is forbidden, that rewrite hid a ship-blocking 404 from 119 green examples (first real-browser exercise caught it)
- [Phase 13 — Server Skeleton + Read-Only Dashboard]: User acceptances 2026-09-01: WR-02 second-launch UX = block-then-replace (second launch blocks on boot flock, then boots fresh; 'already running' print only manifests in the synthetic lock-free scenario); default-browser auto-open accepted on StartCallback-after-bind spec evidence; true-offline UAT accepted on same-origin evidence (loopback never traverses NIC)

## Deferred Items

Items acknowledged and deferred at milestone close, most recent first:

| Category | Item | Status | Deferred At | Milestone |
|----------|------|--------|-------------|-----------|
| uat_gaps | 11/11-UAT.md | complete (test 1 satisfied by run 33377121583 evidence) | 2026-08-31 | v0.4.0 |
| uat_gaps | 06/06-UAT.md | partial (0 pending; remainder skipped by 2026-08-27 override) | 2026-08-31 | v0.4.0 |
| uat_gaps | 07/07-UAT.md | testing (1 pending; superseded by canonical verification 5/5) | 2026-08-31 | v0.4.0 |
| deferred_items | 11/deferred-items.md: tap formula Ruby ≥3.4 boot crash | RESOLVED same day (tap@5fd0f0d, live-proven run 33350215267) — acknowledged to quiet the scanner | 2026-08-31 | v0.4.0 |

## Session Continuity

Last session: 2026-09-01T16:53:56.640Z
Stopped at: Phase 15 context gathered
Resume file: .planning/phases/15-ui-build-controls/15-CONTEXT.md
