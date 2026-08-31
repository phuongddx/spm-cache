# Requirements: spm-cache

**Defined:** 2026-08-31
**Core Value:** Reduce Xcode clean build times by serving prebuilt SPM dependency binaries transparently, with automatic fallback to source compilation on cache miss — so a cache hit never breaks a build.
**Milestone:** v0.5.0 — Web Interface

## v1 Requirements

Requirements for milestone v0.5.0. Each maps to roadmap phases (traceability below).

### Web server

- [ ] **WEB-01**: `spm-cache web` starts a localhost-only server (explicit 127.0.0.1 binding, port probing that skips known-occupied ports including AirPlay 5000/7000) and opens the dashboard in the default browser
- [ ] **WEB-02**: Re-running `spm-cache web` while a server is live is idempotent (marker file with pid-liveness check reuses the running instance), not an error
- [ ] **WEB-03**: Server exits cleanly on SIGTERM/SIGINT — cleanup, exit 0 (watch-style signal contract)
- [ ] **WEB-04**: Mutating endpoints validate Host/Origin plus a per-launch token; all dashboard assets are vendored and load fully offline (no CDN)

### Dashboard panels

- [ ] **DASH-01**: Cache state table shows per-package size, cached/source state, and fidelity status
- [ ] **DASH-02**: Doctor panel runs checks on demand, shows statuses + fix hints, cached with timestamp (data-driven from the check registry, no hard-coded checks)
- [ ] **DASH-03**: Graph panel renders package nodes via a repaired visualization (vendored cytoscape, raw-entries-to-elements transform; edges deferred pending Swift spike)

### Live log streaming

- [ ] **LOGS-01**: Every CLI run (build/use/watch) writes a JSONL run log (header/body/exit lines) under the project run dir, outside the sandbox
- [ ] **LOGS-02**: Browser shows a single live log stream with per-package anchors while a build runs
- [ ] **LOGS-03**: Loading mid-build replays the run from the start; reconnects resume without lost lines (Last-Event-ID; never 204)
- [ ] **LOGS-04**: Terminal- and `watch`-initiated runs stream into the same browser view as UI-triggered runs
- [ ] **LOGS-05**: Each run shows identity — trigger source (UI/terminal/watch), command, status — with external-run detection from the build lock

### Build control

- [ ] **BLD-01**: Build/Rebuild button with scope selection spawns the real CLI subprocess (array argv, pgroup) and streams its output; a second concurrent UI build is rejected (single slot)
- [ ] **BLD-02**: Busy/waiting state derived from the build lock is visible in the UI ("waiting for build lock…")
- [ ] **BLD-03**: Build failures surface with exit status and highlighted errors
- [ ] **BLD-04**: Rollback button restores source mode; rollback acquires the build lock (closes the current lock-free rollback race)

### Package toggles

- [ ] **TOGL-01**: Per-package cache on/off toggles persist to the same config ignore list `spm-cache off` writes — one source of truth, `off` refactored onto shared mutators, atomic save
- [ ] **TOGL-02**: Toggle UI shows saved-vs-applied state with an explicit Apply-now (re-sync) action
- [ ] **TOGL-03**: Non-toggleable packages show WHY (pattern-managed / plugin / binary-target / excluded / fidelity)

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Web interface follow-ups

- **WEB2-01**: Graph edges populated from real dependency data (requires Swift spike: dependency data source — pbxproj analysis vs `swift package dump-package`)
- **WEB2-02**: Cancellation of UI-triggered runs (mechanism arrives with BLD-01's pgroup spawn; cancel stays UI-run-only)
- **WEB2-03**: Cache-state overlay on the graph during runs
- **WEB2-04**: "Rebuild what drifted" prefill from DiffDetector
- **WEB2-05**: Run-history persistence with search

### Carried forward (pre-webUI candidates)

- **CARRY-01**: `~/.spm-cache` partitioning + content-addressed cache keys (v0.5 carry-over, deferred again 2026-08-31)
- **CARRY-02**: RubyGems publication (`gem push`) + GitHub Action viability it unlocks

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Remote access / auth for the web UI | Hard localhost-only constraint (user decision 2026-08-31); would be a new milestone |
| Multi-project server | Per-project ports and state model; single-project dashboard is the v0.5 shape |
| N per-package parallel log panes | Build loop is sequential — N panes would be N empty boxes (research verdict) |
| Cross-process build cancellation | Killing other processes' xcodebuild trees races the flock; UI-triggered runs only (future) |
| General spm-cache.yml editor | Structured toggle controls only; a yml editor invites source-of-truth drift |
| Graph edges in v0.5 | Dependency data source unresearched — spike first (WEB2-01) |
| Run-history DB, notifications, animated graph re-layout | Research anti-features (Dozzle stores nothing; tab title + banner suffice) |
| CocoaPods support / app-target caching / non-macOS | Long-standing project exclusions |
| `~/.spm-cache` partitioning + content-addressed keys | Deferred again this milestone (CARRY-01) |
| RubyGems publication | Deferred by user decision (CARRY-02) |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| WEB-01 | Phase 13 | Pending |
| WEB-02 | Phase 13 | Pending |
| WEB-03 | Phase 13 | Pending |
| WEB-04 | Phase 13 | Pending |
| DASH-01 | Phase 13 | Pending |
| DASH-02 | Phase 13 | Pending |
| DASH-03 | Phase 13 | Pending |
| LOGS-01 | Phase 12 | Pending |
| LOGS-02 | Phase 14 | Pending |
| LOGS-03 | Phase 14 | Pending |
| LOGS-04 | Phase 14 | Pending |
| LOGS-05 | Phase 14 | Pending |
| BLD-01 | Phase 15 | Pending |
| BLD-02 | Phase 15 | Pending |
| BLD-03 | Phase 15 | Pending |
| BLD-04 | Phase 15 | Pending |
| TOGL-01 | Phase 16 | Pending |
| TOGL-02 | Phase 16 | Pending |
| TOGL-03 | Phase 16 | Pending |

**Coverage:**
- v1 requirements: 19 total
- Mapped to phases: 19 ✓
- Unmapped: 0

---
*Requirements defined: 2026-08-31*
*Last updated: 2026-08-31 after v0.5.0 roadmap creation (Phases 12–16, 19/19 mapped)*
