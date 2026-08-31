# Roadmap: spm-cache

## Milestones

- ✅ **v0.3.0 Mixed Cycle** — Phases 1–5 (shipped 2026-08-24)
- ✅ **v0.4.0 Build Fidelity & Release Automation** — Phases 6–11 (shipped 2026-08-31)
- 🚧 **v0.5.0 Web Interface** — Phases 12–16 (in progress)

## Overview

v0.5.0 gives spm-cache a local web dashboard. `spm-cache web` starts a localhost-only server for the current project and opens it in the browser: live-streaming build logs (from UI-triggered builds AND from terminal/`watch`-initiated runs relayed into the same view), Build/Rebuild/Rollback controls that spawn the real CLI, per-package cache toggles persisted through the same config path `spm-cache off` uses, a cache-state table with sizes and fidelity status, an embedded dependency-graph view, and a doctor health panel.

The architecture stance (research, HIGH confidence): the server is a stateless file reader + run-log tailer + CLI-subprocess spawner — **never a second source of truth**. Every dashboard mutation spawns the ordinary `spm-cache` verb (inheriting the existing build flock and all code paths); every read re-derives state from the same files the CLI reads (config, sidecars, graph.json, run logs); the build flock stays the only mutex. Exactly one new runtime dependency (`webrick`), fully vendored offline assets, hard 127.0.0.1 binding with Host/Origin + per-launch-token middleware — localhost is not a trust boundary.

Phase numbering continues from v0.4.0 (which ended at Phase 11) — v0.5.0 phases are 12–16.

<details>
<summary>✅ v0.3.0 Mixed Cycle (Phases 1–5) — SHIPPED 2026-08-24</summary>

- [x] Phase 1: Test CI Foundation (2/2 plans) — completed 2026-08-24
- [x] Phase 2: Diagnostics Command (2 plans) — completed 2026-08-24 (verification refreshed same day)
- [x] Phase 3: Project Bootstrap (2 plans) — completed 2026-08-24
- [x] Phase 4: CI GitHub Action (2 plans) — completed 2026-08-24
- [x] Phase 5: Auto-Sync Watcher (2 plans) — completed 2026-08-24

Full phase detail: `milestones/v0.3.0-ROADMAP.md` · Audit: `milestones/v0.3.0-MILESTONE-AUDIT.md`

</details>

<details>
<summary>✅ v0.4.0 Build Fidelity & Release Automation (Phases 6–11) — SHIPPED 2026-08-31</summary>

- [x] Phase 6: Graph Authority — Lockfile Reconciliation (5 plans) — completed 2026-08-27 (verified via documented override + gap closure)
- [x] Phase 7: Host-Faithful Checkout Seeding (2 plans) — completed 2026-08-29
- [x] Phase 8: Drift Read-Back, Fidelity Status & Provenance (2 plans) — completed 2026-08-29
- [x] Phase 9: Cache Identity & Invalidation (3 plans) — completed 2026-08-29
- [x] Phase 10: Fidelity Regression Coverage (3 plans) — completed 2026-08-30
- [x] Phase 11: Homebrew Release Automation (3 plans) — completed 2026-08-31

Full phase detail: `milestones/v0.4.0-ROADMAP.md` · Audit: `v0.4.0-MILESTONE-AUDIT.md`

</details>

## Phases — v0.5.0 Web Interface

- [ ] **Phase 12: Run-Log Capture Foundation** - Every CLI run writes a queryable JSONL run log outside the sandbox, terminal behavior unchanged — the keystone all streaming consumes
- [ ] **Phase 13: Server Skeleton + Read-Only Dashboard** - `spm-cache web`: hardened localhost server serving the cache-state, doctor, and graph panels, fully offline
- [ ] **Phase 14: Live Log Streaming + Terminal/Watch Relay** - One SSE stream of the shared run log — UI-triggered, terminal, and `watch` builds all appear live in the browser
- [ ] **Phase 15: UI Build Controls** - Build/Rebuild/Rollback buttons that spawn the real CLI with lock-derived busy state and failure surfacing
- [ ] **Phase 16: Package Toggles + Panel Completion** - Per-package cache on/off toggles through the shared config mutators, with saved-vs-applied semantics and WHY-not reasons

## Phase Details — v0.5.0 Web Interface

### Phase 12: Run-Log Capture Foundation

**Goal**: Every CLI run (build/use/watch) leaves a complete, queryable run log on disk — the keystone every streaming feature consumes — without changing terminal behavior
**Depends on**: Nothing (first phase of v0.5.0; builds on the existing `Core::UI`/`Core::Sh` seams)
**Requirements**: LOGS-01
**Success Criteria** (what must be TRUE):

  1. Running `spm-cache build`, `use`, or `watch` leaves a JSONL run log under the project's run dir (outside the sandbox, which is destroyed mid-run) containing a header line (command, argv, pid, started_at), timestamped body lines tagged by stream, and an exit line
  2. The log body captures what the terminal showed — including a failing build's error lines and output from spawned xcodebuild/swift subprocesses — so the full run can be reconstructed offline
  3. Terminal output and exit codes are unchanged by the capture (tee is invisible), and `spm-cache web` itself never writes a run log
  4. Repeated runs accumulate logs without unbounded growth (retention policy caps old runs)

**Plans**: 3/5 plans executed

Plans:
**Wave 1**

- [x] 12-01-PLAN.md — Tracer: Core::RunLog + Main.run end-to-end run-log slice (tee, header/body/exit, --no-run-log, --log-dir, exit-shape parity)

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 12-02-PLAN.md — Core::Sh popen3 per-stream sink + failure_detail restoration + capture3 sh events (SC2 subprocess capture)
- [x] 12-03-PLAN.md — Retention (runs_keep/runs_max_mb count+size hybrid at run start), config keys, yml template, .spm-cache/ gitignore entry (SC4)

**Wave 3** *(blocked on Wave 2 completion)*

- [ ] 12-04-PLAN.md — Structured event vocabulary: package_start/package_end, phase markers (detect/integrate/build/fidelity), xcodebuild sink activation (D-04)

**Wave 4** *(blocked on Wave 3 completion)*

- [ ] 12-05-PLAN.md — Watch per-cycle run logs via the installer_factory wrapper + D-08 no-allowlist proof (D-09)

### Phase 13: Server Skeleton + Read-Only Dashboard

**Goal**: `spm-cache web` serves a localhost-only, fully-offline dashboard showing cache state, doctor health, and the dependency graph — read-only, and hardened against localhost drive-by requests before any mutating endpoint exists
**Depends on**: Phase 12 (runs/web config dirs; web-excluded tee)
**Requirements**: WEB-01, WEB-02, WEB-03, WEB-04, DASH-01, DASH-02, DASH-03
**Success Criteria** (what must be TRUE):

  1. `spm-cache web` starts a server bound explicitly to 127.0.0.1 (probing past occupied ports, skipping AirPlay's 5000/7000) and opens the dashboard in the default browser
  2. Re-running `spm-cache web` while a server is live reuses the running instance (marker file with pid-liveness — no error, no second server); SIGTERM/SIGINT exits cleanly with cleanup and exit 0
  3. The dashboard loads fully offline (all assets vendored, zero CDN requests); a request to a mutating endpoint with an invalid Host/Origin or a missing per-launch token is rejected
  4. The cache-state table shows per-package size, cached/source state, and fidelity status, re-derived from the same files the CLI reads
  5. The doctor panel runs checks on demand from the check registry (statuses + fix hints, data-driven — no hard-coded checks; results cached with a timestamp), and the graph panel renders package nodes via a repaired vendored-cytoscape visualization, with an affordance when graph.json hasn't been generated yet

**Plans**: TBD
**UI hint**: yes

### Phase 14: Live Log Streaming + Terminal/Watch Relay

**Goal**: Any build — UI-triggered, terminal-started, or `watch`-initiated — streams live into one browser view with mid-build replay, reconnect-without-loss, and visible run identity
**Depends on**: Phase 12 (run logs), Phase 13 (server)
**Requirements**: LOGS-02, LOGS-03, LOGS-04, LOGS-05
**Success Criteria** (what must be TRUE):

  1. While a build runs, the browser shows a single live log stream with per-package anchors, following the tail with scroll lock
  2. Opening the dashboard mid-build replays the run from the start; after a dropped connection the stream reconnects and resumes without lost lines (Last-Event-ID; failed connects retry — never a terminal 204)
  3. A build started in a terminal (or by `watch`) appears in the same browser stream as a UI-triggered build — including runs that started before the server launched
  4. Each visible run shows its identity: trigger source (UI/terminal/watch), command, and running/success/failure status; a run held by another process's build lock is detected and attributed from the lock, and pid-dead runs without an exit line are handled honestly

**Plans**: TBD
**UI hint**: yes

### Phase 15: UI Build Controls

**Goal**: Users can trigger builds and rollback from the dashboard with the same locking, live output, and failure visibility as the terminal
**Depends on**: Phase 13 (security middleware), Phase 14 (live stream)
**Requirements**: BLD-01, BLD-02, BLD-03, BLD-04
**Success Criteria** (what must be TRUE):

  1. Build/Rebuild with scope selection spawns the real CLI subprocess (array argv, own process group) and its output streams live into the log view; a second concurrent UI build is rejected with a clear busy message (single slot)
  2. When another process holds the build lock, the UI shows the waiting state ("waiting for build lock…") derived from the lock — never a silent queue
  3. A failed build surfaces its exit status with highlighted error lines in the UI
  4. The Rollback button restores source mode, and rollback now acquires the build lock — the current lock-free rollback race is closed

**Plans**: TBD
**UI hint**: yes

### Phase 16: Package Toggles + Panel Completion

**Goal**: Users can flip per-package caching from the browser through the same config code path `spm-cache off` uses, with honest saved-vs-applied semantics and visible reasons where toggling isn't allowed
**Depends on**: Phase 13 (read models), Phase 15 (job machinery for the Apply-now action)
**Requirements**: TOGL-01, TOGL-02, TOGL-03
**Success Criteria** (what must be TRUE):

  1. Toggling a package persists to the same config ignore list `spm-cache off` writes — one source of truth (`off` refactored onto the shared mutators), with an atomic save that cannot clobber concurrent CLI edits
  2. The toggle UI distinguishes saved vs applied state and offers an explicit Apply-now (re-sync) action that runs the real sync
  3. Packages that cannot be toggled show WHY (pattern-managed / plugin / binary-target / excluded / fidelity)

**Plans**: TBD
**UI hint**: yes

## Phase Ordering Rationale

Ordering is dependency-driven (from research), not layer-arbitrary:

- **Nothing can stream without run logs.** Phase 12 builds the output-capture sink at the `Core::UI`/`Core::Sh` boundary (research pitfall CP3 — today visible output lives in three disconnected channels). It is pipeline-adjacent (Core only, no server), hermetic, and independently verifiable, so it lands alone first as the keystone.
- **No SSE and no jobs without a server.** Phase 13 establishes the HTTP adapter, the security middleware (Host/Origin + per-launch token — CP13 lands here, *before* any mutating endpoint ships), and the read-models the later panels reuse. Read-only by design: the risk order inside the new web layer is reads → streams → mutations.
- **Build controls ride the stream.** Phase 15's UI builds must show live output the moment they're triggered, so it needs Phase 14's stream plus Phase 13's middleware (its endpoints are the first destructive mutations — array-argv spawns, parameter validation).
- **Toggles land last** because they are the only phase that writes user state (config), and their Apply-now action reuses Phase 15's job machinery (a spawned `spm-cache use`). Config-integrity pitfalls (CP1/CP2: stale-singleton writeback, non-atomic save) are exactly this phase's scope.
- **Terminal/`watch` relay is not a separate feature.** Because the Phase 14 transport is the shared run-log file (file-tail, chosen over UDS in research adjudication), relay falls out of the same mechanism as UI-run streaming.

Pitfall-to-phase mapping (full set in `research/PITFALLS.md`): CP3 → P12; CP7/CP8/CP9/CP13 → P13; CP5/CP6/CP10/CP11/CP12 → P14; CP4/CP14 → P15; CP1/CP2 → P16.

**Research flags:** Phase 14 warrants `--research-phase` during planning (heaviest integration surface: SSE lifecycle/backpressure plus watcher interplay). Phases 12, 13, 15, 16 follow established, code-anchored patterns — skip research-phase.

## Progress

**Execution Order:** Phases 12 → 13 → 14 → 15 → 16 (hard chain)

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 12. Run-Log Capture Foundation | v0.5.0 | 3/5 | In Progress|  |
| 13. Server Skeleton + Read-Only Dashboard | v0.5.0 | 0/? | Not started | - |
| 14. Live Log Streaming + Terminal/Watch Relay | v0.5.0 | 0/? | Not started | - |
| 15. UI Build Controls | v0.5.0 | 0/? | Not started | - |
| 16. Package Toggles + Panel Completion | v0.5.0 | 0/? | Not started | - |

## Coverage

19/19 v0.5.0 requirements mapped — no orphans, no double-mapping.

| Phase | Requirements |
|-------|--------------|
| 12 | LOGS-01 |
| 13 | WEB-01, WEB-02, WEB-03, WEB-04, DASH-01, DASH-02, DASH-03 |
| 14 | LOGS-02, LOGS-03, LOGS-04, LOGS-05 |
| 15 | BLD-01, BLD-02, BLD-03, BLD-04 |
| 16 | TOGL-01, TOGL-02, TOGL-03 |

Traceability per requirement: `.planning/REQUIREMENTS.md`.
