---
phase: 14-live-log-streaming-terminal-watch-relay
verified: 2026-09-01T14:55:00Z
status: passed
score: 8/8 must-haves verified
behavior_unverified: 0
overrides_applied: 0
re_verification:
  previous_status: none
  previous_score: n/a
  gaps_closed: []
  gaps_remaining: []
  regressions: []
deferred:
  - truth: "SC3's comparison clause — 'in the same browser stream as a UI-triggered build' — names a run class that does not exist until Phase 15 builds UI-triggering (BLD-01)"
    addressed_in: "Phase 15"
    evidence: "Phase 15 SC1: 'Build/Rebuild with scope selection spawns the real CLI subprocess… and its output streams live into the log view'; ROADMAP architecture note: 'Phase 15's UI builds must show live output the moment they're triggered, so it needs Phase 14's stream'. Phase 14 delivers the writer-agnostic mechanism (verified) and the reserved UI badge path (D-11: trigger renders verbatim, no allowlist — spec/web_frontend_spec.rb 'trigger renders verbatim — a class map only, never a value allowlist')."
---

# Phase 14: Live Log Streaming + Terminal/Watch Relay Verification Report

**Phase Goal:** Any build — UI-triggered, terminal-started, or `watch`-initiated — streams live into one browser view with mid-build replay, reconnect-without-loss, and visible run identity
**Verified:** 2026-09-01T14:55:00Z (HEAD `82b64d6`, branch `gsd/v0.5.0-web-interface`)
**Status:** passed
**Re-verification:** No — initial verification (no previous `*-VERIFICATION.md`)

## Verification Method

Goal-backward from ROADMAP Phase 14 SC1–SC4 (the contract) + REQUIREMENTS LOGS-02/03/04/05. Evidence base per truth: (a) production code read at HEAD (existence + substance + wiring + data flow), (b) named spec rows — the phase's seven spec files re-run this session: **222 examples, 0 failures** (4.51 s), (c) full suite at HEAD: **898 examples, 0 failures** (independently confirmed in the phase context), and (d) for browser-dependent truths, the **D-14 recorded agent-browser probe** in `14-05-SUMMARY.md` § D-14 Probe Recording (commit `fa1e758`, ancestor of HEAD) — all 7 manual rows PASS with commands/timestamps/observed outcomes; two probe-caught defects fixed spec-first (`207133d` doubled-"ago", `3d2481a` statusKey CP14 phrase), both browser-re-verified. Per D-14 (the locked verification net that caught G-13-1 in Phase 13), the recorded probe IS the evidence base for browser truths.

Scope note on the phase's commit surface: `git log bb35be4^..HEAD` omits 14-02's three commits (`3c2bf03`/`b5181d6`/`5e4e42d`) because they landed *before* bb35be4's parent (worktree merge order) — they are ancestors of HEAD on this branch, and the D-05 notice code is present at HEAD (`build.rb:87-90`, `use.rb:81-84`).

## Goal Achievement

### Observable Truths

| # | Truth (SC / requirement) | Status | Evidence |
|---|---|---|---|
| 1 | **SC1/LOGS-02**: While a build runs, the browser shows a single live log stream with per-package anchors, following the tail with scroll lock | ✓ VERIFIED | Transport: tailer→broadcaster→`/api/events` (events.rb Tailer/Broadcaster/Client + `drain_appended`). Specs: `web_events_route_spec.rb` LIVE tracer + exactly-once rows; `web_integration_spec.rb:351` "delivers a line appended after connect within the poll bound (LIVE)". Frontend: log.js `connect()` (802–813) + follow machine; `web_frontend_spec.rb:641/648/657` (follow pins instantly, pill, replay gate), `:721/735/744` (chips + jump). Browser: D-14 Row 1 — terminal `use` run streamed live (dividers, lock-wait park, ✓ flip on run_end 0, rows 10→14 live, follow pinned at tail); Row 5 — chips + dim interaction |
| 2 | **SC2a/LOGS-03**: Opening the dashboard mid-build replays the run from the start | ✓ VERIFIED | `web_events_route_spec.rb:181` "replays the run from byte 0"; `web_integration_spec.rb:331` (weld replay + byte-offset ids); `web_frontend_spec.rb:509/515` (cold-load branches). Browser: D-14 Row 2 — second tab mid-run replayed from the run's first line, same identity card, follow engaged, correctly no switch notice |
| 3 | **SC2b/LOGS-03**: After a dropped connection the stream reconnects and resumes without lost lines (Last-Event-ID) | ✓ VERIFIED | `parse_resume_id` regex+containment before any File.open (events.rb:71–84); exactly-once suppression in `pop_loop`. Specs: `events_tailer_spec.rb:165` (multi-byte exact-next-line), `web_events_route_spec.rb:231` (resume round-trip + collision suffix + hostile matrix, canary never opened), `:301` (exactly-once handoff, live 2000-line fixture), `web_integration_spec.rb:364` (reconnect: neither loss nor duplication). Wire+browser: D-14 Row 3 — `curl` reconnect 0 dupes / exact tail; fresh reopen DOM == renderable disk entries 10/10, zero loss/duplication |
| 4 | **SC2c/LOGS-03**: Failed connects retry — never a terminal 204 | ✓ VERIFIED | `router.rb#events_stream`: after token gate, ALWAYS `200 text/event-stream` (never 204/503; 401/403 pre-auth deliberately permanent per WHATWG §9.2.3 finding); `retry: 3000` in hello (`RETRY_MS`); EventSource auto-reconnect. Specs: `web_events_route_spec.rb:147` (200+headers+hello), `:289` (Connection: close); `web_integration_spec.rb:314`. Browser: D-14 Row 3 — '↻ reconnecting…' observed live; rotated-token 401 → CLOSED → A6 locked page (correct terminal posture) |
| 5 | **SC3/LOGS-04**: A terminal- or `watch`-started run appears in the same browser stream — including runs that started before the server launched | ✓ VERIFIED | Writer-agnostic by construction (the shared run-log file is the only contract — events.rb header; zero Core::Watcher/Command::Watch coupling, grep-clean). Specs: `events_tailer_spec.rb:185` (pre-existing live run chosen + replayed from byte 0), `:247` (newer-run switch, D-04), `:374` (CR-02 idle-client first-run delivery), `web_events_route_spec.rb:365/414` (?run= pin). Browser: D-14 Row 1 (terminal run live), Row 6 (watch cycles + auto-switch from a pinned run, strict {run-id} divergence case), Row 3 (server restarted AFTER the run started → fresh reopen replayed the pre-server run byte-exact). *The "as a UI-triggered build" comparison clause is deferred to Phase 15 (see Deferred Items) — the mechanism (any file in the runs dir) and the reserved verbatim-trigger badge path are in place* |
| 6 | **SC4a/LOGS-05**: Each visible run shows identity — trigger source (UI/terminal/watch), command, running/success/failure status | ✓ VERIFIED | One derivation, two surfaces: `read_models/runs.rb#derive` (header verbatim + `status_for` vocabulary success/failed/running) feeds hello AND `/api/runs`. Specs: `web_runs_read_model_spec.rb:194` (vocabulary), `web_events_route_spec.rb:333` (hello == /api/runs, same run/status/lock), `web_frontend_spec.rb:556/564/570` (card rows; trigger verbatim, class map only — UI badge reserved). Browser: D-14 Rows 1 (`● running \| terminal \| use` → `✓ success`), 4 (`✗ failed \| terminal \| use`), 6 (watch badge in dropdown + card) |
| 7 | **SC4b/LOGS-05**: A run held by another process's build lock is detected and attributed from the lock | ✓ VERIFIED | `runs.rb#lock_state`: non-blocking flock probe (acquire-and-release in one File.open, never holds) + attribution — held→attributable live run ('running' + holder identity) / held→unattributable ('unknown holder', never a guess) / free→idle. D-05: probe→announce→block at BOTH flock sites (`build.rb:87-90`, `use.rb:81-84`), lands as a T-12-01 body line in the blocked run's own JSONL. Specs: `web_runs_read_model_spec.rb:136/150/165`; `installer_lock_notice_spec.rb` 13/13 (announce-before-block structural, both sites, blocked-run-only landing, free-path byte-identity). Browser: D-14 Row 7 (hello `lock.state=held` while another process held the lock; "Waiting for build lock…" rendered verbatim, no special-casing — 0 occurrences in log.js) + Row 1 (parked at the line, released, completed) |
| 8 | **SC4c/LOGS-05/CP14**: pid-dead runs without an exit line are handled honestly | ✓ VERIFIED | `runs.rb#status_for`: dead pid + no run_end → `'interrupted — exit unknown'` (INTERRUPTED, em dash pinned), never 'running'; pid liveness authoritative for liveness. Frontend `statusKey` maps the FULL CP14 phrase (probe catch #2, `3d2481a`). Specs: `web_runs_read_model_spec.rb:184`, `web_frontend_spec.rb:570/671/577`. Browser: probe catch #2 re-verified live — pinned reaped run 64142 rendered card `! interrupted — exit unknown` + banner "Run interrupted — exit unknown." + jump |

**Score:** 8/8 truths verified (0 present, behavior-unverified)

### Deferred Items

| # | Item | Addressed In | Evidence |
|---|------|-------------|----------|
| 1 | SC3's "same browser stream **as a UI-triggered build**" comparison clause — UI-triggered builds are created by Phase 15 | Phase 15 | Phase 15 SC1 "spawns the real CLI subprocess… output streams live into the log view"; BLD-01. Phase 14 ships the writer-agnostic transport and the reserved UI badge (trigger verbatim, no allowlist — spec-pinned) |

Informational only — not a gap. Terminal/watch/pre-server-start halves of SC3 are fully verified in this phase.

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/spm_cache/web/events.rb` | Tailer + Broadcaster + Client + PinnedFollow + ShutdownSentinel + Events facade (857 lines) | ✓ VERIFIED | Substantive; wired via Router#events_stream; CR-01 `pop_with_timeout`, CR-02 symmetric first-attach, W-01 doubly-pruned rescue all present in code |
| `lib/spm_cache/web/read_models/runs.rb` | Stateless CP10 derivation + D-12 listing (201 lines) | ✓ VERIFIED | No instance state; consumed by BOTH `/api/runs` and hello |
| `lib/spm_cache/web/router.rb` | `/api/events` + `/api/runs` rows, ?run= pin, 200-always SSE | ✓ VERIFIED | dispatch rows at router.rb:120-130; events_stream sets 200 text/event-stream after token/verb gates |
| `lib/spm_cache/web/server.rb` | shutdown seam BEFORE @http.shutdown | ✓ VERIFIED | `@router&.shutdown_events` then `@http.shutdown` (server.rb:63-66) |
| `lib/spm_cache/web/assets/log.js` | Stream module: card, follow/ring, banners, anchors/filter, switch/notice, dropdown (828 lines) | ✓ VERIFIED | EventSource on /api/events?token= with hello/entry/switch/notice listeners (802-813); textContent-only; no client clock/timers |
| `lib/spm_cache/web/assets/index.html` | Run Log panel FIRST + a11y skeleton + relative `assets/log.js` module tag | ✓ VERIFIED | Module tag line 102; all asset refs relative (G-13-1 lesson); role=log/alert/live present |
| `lib/spm_cache/web/assets/styles.css` | Log-section rules on existing tokens | ✓ VERIFIED | Referenced by index.html; zero-new-tokens pin green in spec run |
| `lib/spm_cache/core/run_log.rb` | WR-01 thread-keyed partial buffers | ✓ VERIFIED | `@buffers` keyed `[thread, stream]` (run_log.rb:197-233); wired via record_line tee |
| `lib/spm_cache/installer/build.rb` + `use.rb` | D-05 probe→announce→block at both flock sites | ✓ VERIFIED | build.rb:87-90, use.rb:81-84; one-shot LOCK_NB probe, return-value gated |
| 7 spec files (`events_tailer`, `events_broadcaster`, `web_events_route`, `web_runs_read_model`, `installer_lock_notice`, `web_frontend`, `web_integration`) | Phase 14 verification surface | ✓ VERIFIED | Re-run this session: 222 examples, 0 failures |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|----|--------|---------|
| Router | Events | `events_stream` → `@events.register(out)` + `@events.stream(client, resume:, pin:)` | ✓ WIRED | router.rb:216-229 |
| Events | ReadModels::Runs | `deliver_hello`/`live_resume`/`fresh_run` → `Runs.derive` / `Runs.lock_state` | ✓ WIRED | one derivation, two surfaces (zero drift asserted by spec) |
| log.js | /api/events | `new EventSource('/api/events?token=…')` + 4 named listeners | ✓ WIRED | log.js:801-813 |
| log.js | /api/runs | dropdown `fetch('/api/runs', { headers: { 'X-SPM-Token' … } })` on every open | ✓ WIRED | log.js:710, 788-793 |
| index.html | log.js | `<script type="module" src="assets/log.js">` after app.js | ✓ WIRED | served + content-type row green |
| Server | Events (shutdown) | `shutdown` → `@router.shutdown_events` → `Events#shutdown!` sentinel fan-out | ✓ WIRED | sentinel-before-join proven by weld row "shuts down within bound WITH an open stream" |
| Installer notice | run JSONL → stream | `Core::UI.info` → $stdout → Phase 12 TeeIO → body line → relayed as ordinary entry | ✓ WIRED | tee-landing specs + D-14 Rows 1/7 live render |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| runs.rb `call`/`derive` | runs listing, header, status | runs dir glob + JSONL parse per call | Yes (no cache, no memo) | ✓ FLOWING |
| runs.rb `lock_state` | lock hash | real flock probe of build_lock_path | Yes | ✓ FLOWING |
| events.rb `stream` | hello/entries | disk replay + tailer appends | Yes | ✓ FLOWING |
| log.js card/dropdown | header/status/runs | hello payload + /api/runs fetch | Yes | ✓ FLOWING |

No static returns, no hardcoded empty data, no mock fallbacks on any rendered path.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Phase 14 spec surface (7 files: tailer, broadcaster, route, runs read model, lock notice, frontend source-contract, one-boot integration weld incl. real-server LIVE/replay/resume/shutdown rows) | `bundle exec rspec spec/events_tailer_spec.rb spec/events_broadcaster_spec.rb spec/web_events_route_spec.rb spec/web_runs_read_model_spec.rb spec/installer_lock_notice_spec.rb spec/web_frontend_spec.rb spec/web_integration_spec.rb` | 222 examples, 0 failures (4.51 s) | ✓ PASS |
| Full suite at HEAD | per phase context (this session, pre-verification) | 898 examples, 0 failures | ✓ PASS |
| log.js syntax (mechanical floor) | `node --check` (per 14-04 SUMMARY verification) | clean | ✓ PASS |

### Probe Execution

| Probe | Command | Result | Status |
|-------|---------|--------|--------|
| D-14 recorded agent-browser streaming probe (the phase-declared probe — no `scripts/*/tests/probe-*.sh` exists in this repo; discovery run, zero hits) | 7 rows against real servers (`spm-cache web --no-open --port=0`/`--port=62800`), real CLI runs (`use`, `build`, `watch`), real headless-Chromium tabs + curl wire checks; recorded verbatim in 14-05-SUMMARY.md § D-14 (commit `fa1e758`, ancestor of HEAD) | 7/7 rows PASS with timestamps/commands/outcomes; 14-VALIDATION.md manual table ticked 2026-09-01 with per-row evidence pointers; two probe-caught defects fixed spec-first (`207133d`, `3d2481a`) and browser-re-verified | ✓ PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|---------------------|----------|
| LOGS-02 | 14-01/04/05 | Single live log stream with per-package anchors | ✓ SATISFIED | Truth 1 |
| LOGS-03 | 14-01/03/04 | Mid-build replay; reconnect resume without loss (Last-Event-ID; never 204) | ✓ SATISFIED | Truths 2-4 |
| LOGS-04 | 14-01/05 | Terminal- and watch-initiated runs stream into the same browser view | ✓ SATISFIED | Truth 5 (UI-triggered comparison clause deferred to Phase 15 by design) |
| LOGS-05 | 14-02/03/05 | Run identity — trigger source, command, status — with external-run detection from the build lock | ✓ SATISFIED | Truths 6-8 |

Orphaned requirements: none — REQUIREMENTS.md maps exactly LOGS-02/03/04/05 to Phase 14; all four claimed by plans and verified.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| (none) | — | Zero `TBD`/`FIXME`/`XXX`/`TODO`/`HACK`/placeholder markers across all 10 phase production files; zero lock-wait special-casing in log.js; zero markup-writing APIs / client-clock / timers (spec-gated) | — | — |
| `runs.rb:181` vs `run_log.rb` | — | IN-02: `pid_alive?` duplicated verbatim across two files (cross-referenced comments) | ℹ️ Info | Documented in 14-REVIEW.md, explicitly optional ("not required for this phase") — accepted, not a gap |

### Review Findings Closure (14-REVIEW.md, deep pass)

All 5 findings carry recorded Resolution + Commit lines, verified against code and history at HEAD:

- **CR-01** (Ruby 3.1 `pop(timeout:)` silent breakage) — FIXED: `Events.pop_with_timeout` (events.rb:186-196) used by `pop_loop` and specs; commit `1127924` ✓
- **CR-02** (first-attach skipped existing content; idle clients never saw first run) — FIXED: symmetric `attach(newest, from_byte0: true)` + `publish_switch(previous: nil)` in `discover`; RED spec `1127924`-adjacent commits `e5c45e5`/`47ff8ff`; the spec row "delivers switch + replay to an already-parked idle client when the first run appears (CR-02)" ran green this session ✓
- **W-01** (doubly-pruned fallback replay ENOENT escape) — FIXED: inner `rescue Errno::ENOENT; nil` in `Events#stream`; commit `e59a158` ✓
- **IN-01** (`resetForRun` inconsistent follow-arg shapes) — FIXED: plain booleans at all call sites (log.js:618 etc.); commit `3fd9097` ✓
- **IN-02** (pid_alive? duplication) — documented, intentionally not fixed (optional) ✓

### Gaps Summary

None. All 8 must-have truths verified with code + spec + (for browser truths) recorded-probe evidence; all artifacts present, substantive, wired, and data-flowing; all key links wired; requirements LOGS-02/03/04/05 satisfied; no unresolved review findings; no debt markers; suites green (222/0 phase surface re-run this session; 898/0 full suite at HEAD). One informational deferral (SC3's UI-triggered comparison clause → Phase 15) and one accepted info-level duplication (IN-02).

---

_Verified: 2026-09-01T14:55:00Z_
_Verifier: Claude (gsd-verifier)_
