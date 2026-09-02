---
phase: 12-run-log-capture-foundation
plan: 02
subsystem: infra
tags: [subprocess-capture, popen3, run-log, jsonl, stream-attribution, shell-seam]

requires:
  - phase: 12-run-log-capture-foundation (plan 12-01)
    provides: Core::RunLog JSONL writer, RunLog.current process-wide seam, RunLog::StreamSink per-stream adapter, mutex-serialized safe_append degradation
provides:
  - Core::Sh.run opts live_log_out:/live_log_err: (per-stream sinks, legacy live_log: fallback, nil-disables)
  - popen3 failure_detail tails — failing live-mode commands raise the capture3-identical 60-line detail message (discarded-capture gap closed)
  - Enriched popen3 success return {output, error, status: 0} from the tail joins
  - Core::Sh capture3 calls recorded as structured {event: "sh", ts, cmd, status} lines via RunLog.current (nil-safe)
  - spec/sh_run_log_sink_spec.rb (12 examples, real echo/printf through the real Sh)
affects: [12-run-log-capture-foundation (12-04 sink forwarding), 14-live-log-streaming (reconstruction), 13-server-skeleton]

actuals:
  tokens: 2766   # chars/4 over the realized diff (lib+spec, 11063 added chars); plan estimated 30000 at confidence low
  tasks: 2
  commits: 4

tech-stack:
  added: []   # stdlib only (Open3/thread primitives already in use) — no new gems, per project constraint
  patterns:
    - "Per-stream sink opts with legacy single-object fallback (out = live_log_out || live_log) — nil-disables everywhere, no caller signature changes"
    - "Bounded tail ring inside the reader thread (<< + shift over the shared FAILURE_DETAIL_LINES constant) — bounds only the raised message, never the file (D-05)"
    - "Nil-safe structured event at the Sh boundary: RunLog.current&.event('sh', cmd:, status:) recorded before any raise, safe_append as the only degradation guard"

key-files:
  created:
    - spec/sh_run_log_sink_spec.rb
  modified:
    - lib/spm_cache/core/sh.rb

key-decisions:
  - "Raise-message assertions use printf-runtime markers ('printf \"stdout-%s detail\" marker'): the assertion text exists only in the STREAMED line — today's popen3 raise embeds the command, so an `echo marker` shape would match vacuously through the cmd text"
  - "The 60-line tail bound applies only to the raised error message and the return hash; the run-log file receives the full stream verbatim (D-05)"
  - "sh events carry cmd (verbatim, JSON-escaped) + numeric status only — never output text (A2: value-returning captures are not terminal-visible today; numeric-only status + escaping keep a subprocess from forging an event line, T-12-01)"
  - "Dead output_lines local removed — it sat inside the restructured popen3 range and was never read (rubocop's own useless-assignment warning confirmed)"

patterns-established:
  - "live_log_out:/live_log_err: is the exact opt pair Plan 12-04 forwards from Buildable#xcodebuild (build.rb:80-87) to activate the sink from the build path"
  - "Spec-side: force lazy let(:log) open BEFORE asserting RunLog.current — expect(actual) evaluates actual before matcher args, so equal(log) alone opens the seam too late"

requirements-completed: []   # LOGS-01 stays open until 12-05 (SC4 retention = 03, build-path wiring = 04, watch cycles = 05); this plan closes the SC2 subprocess halves

coverage:
  - id: D1
    description: "Core::Sh popen3 per-stream sinks + restored failure_detail — subprocess lines reach the run log with correct out/err tags, failing live-mode commands raise with the streamed 60-line detail (discarded-capture gap closed), full stream to the file, enriched success return, legacy live_log back-compat"
    requirement: LOGS-01
    verification:
      - kind: unit
        ref: "spec/sh_run_log_sink_spec.rb#raises with the streamed stdout line in the message (legacy live_log form)"
        status: pass
      - kind: unit
        ref: "spec/sh_run_log_sink_spec.rb#raises with the streamed stderr line in the message (legacy live_log form)"
        status: pass
      - kind: unit
        ref: "spec/sh_run_log_sink_spec.rb#raises with the streamed stdout line when per-stream sinks are passed (core_spec precedent shape)"
        status: pass
      - kind: unit
        ref: "spec/sh_run_log_sink_spec.rb#raises with the streamed stderr line when per-stream sinks are passed (core_spec precedent shape)"
        status: pass
      - kind: unit
        ref: "spec/sh_run_log_sink_spec.rb#lands stdout tagged out and stderr tagged err in the run-log file"
        status: pass
      - kind: unit
        ref: "spec/sh_run_log_sink_spec.rb#writes the FULL stream to the file; the 60-line tail bound never touches it (D-05)"
        status: pass
      - kind: unit
        ref: "spec/sh_run_log_sink_spec.rb#returns the tailed output/error strings with status 0 (enriched success return)"
        status: pass
      - kind: unit
        ref: "spec/sh_run_log_sink_spec.rb#adds zero body lines for a zero-output subprocess and the file stays valid (EDGE empty)"
        status: pass
      - kind: unit
        ref: "spec/sh_run_log_sink_spec.rb#still calls output(line) for every line of BOTH streams on the single object"
        status: pass
    human_judgment: false
  - id: D2
    description: "Every completed capture3 call recorded as one structured {event: sh, ts, cmd, status} line when a run log is active — success and failure (real exit status before the raise), returned values and raise semantics byte-identical, nil-safe when RunLog.current is unset"
    requirement: LOGS-01
    verification:
      - kind: unit
        ref: "spec/sh_run_log_sink_spec.rb#records one {event: sh, ts, cmd, status} line per completed capture, returned value unchanged"
        status: pass
      - kind: unit
        ref: "spec/sh_run_log_sink_spec.rb#records the real exit status before the raise on a failing capture"
        status: pass
      - kind: unit
        ref: "spec/sh_run_log_sink_spec.rb#records nothing when RunLog.current is nil (nil-disables)"
        status: pass
    human_judgment: false

duration: 15min
completed: 2026-08-31
status: complete
---

# Phase 12 Plan 02: Core::Sh run-log sink + failure_detail restoration Summary

**Core::Sh popen3 branch gained per-stream run-log sinks (live_log_out/live_log_err, legacy live_log back-compat) plus bounded 60-line failure_detail tails that close the discarded-capture gap, and every capture3 call now lands as a structured {event: "sh", ts, cmd, status} line via RunLog.current — terminal bytes, exit codes, and all caller signatures unchanged, full suite 480 examples green**

## Performance

- **Duration:** 15 min
- **Started:** 2026-08-31T16:44:28Z
- **Completed:** 2026-08-31T16:59:14Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Subprocess output reaches the run log with correct stream attribution (Pitfall 4): each popen3 reader thread drives its own sink resolved per stream (`live_log_out || live_log`), so stdout lines land tagged `out` and stderr lines tagged `err` — proven with explicit echo-to-stderr through the real Core::Sh, never xcodebuild heuristics
- Failing live-mode commands now raise the same detailed message the capture3 path has always had: "Command failed (exit N): cmd" plus the last 60 lines per stream — the milestone-flagged gap where sh.rb:20-33 dropped every captured line is closed; the file still receives the FULL stream (D-05), only the raised message is bounded
- Every completed capture3 call records one structured `sh` event ({event, ts, cmd, status}) through the nil-safe `RunLog.current&.event` seam (Pitfall 5 / A2): swift-package-describe / xcodebuild -list become visible in offline reconstruction without output spam
- Nil-disables holds everywhere: no sink opts → identical code path to today (468 pre-existing examples green); RunLog.current nil → zero recording, zero filesystem impact; enriched success return is unobservable (no caller reads it — build.rb:81,86 ignore it)

## Task Commits

Each task was committed atomically (TDD: RED before GREEN on both):

1. **Task 1 RED: failing sink specs** - `0bb2c5b` (test)
2. **Task 1 GREEN: popen3 per-stream sinks + 60-line failure_detail tails** - `95456a6` (feat)
3. **Task 2 RED: failing sh-event specs** - `d5ee722` (test)
4. **Task 2 GREEN: capture3 calls recorded as structured sh events** - `337ef90` (feat)

**Plan metadata:** docs commit (this commit: SUMMARY + STATE + ROADMAP)

## Files Created/Modified
- `lib/spm_cache/core/sh.rb` - popen3 branch: per-stream sink opts + tail rings + detailed raise + enriched return; capture3 branch: single `RunLog.current&.event('sh', cmd:, status:)` call site before the raise; dead `output_lines` local removed
- `spec/sh_run_log_sink_spec.rb` - 12 examples (real echo/printf through the real Sh over real RunLogs in tmpdirs): 4 failure-detail (printf-runtime markers), 4 sink/file behaviors (tagging, 100-line full fidelity, enriched return, zero-output EDGE empty), 1 legacy back-compat spy, 3 sh-event (success, failing status, nil-current)

## Decisions Made
- printf-runtime markers (`printf 'stdout-%s detail\n' marker`) make the raise-message assertions non-vacuous: the popen3 raise embeds the command text today, so an `echo marker` shape would satisfy the regex through the cmd, not the streamed line
- Tail rings reuse the existing `FAILURE_DETAIL_LINES` constant (no duplicate); each ring is touched only by its own reader thread, so no new synchronization is needed — the RunLog mutex already serializes the file writes from both threads (EDGE adjacency)
- sh events record cmd exactly as passed plus the numeric exit status, nothing else (T-12-01: JSON-escaped cmd + numeric status cannot be forged by subprocess output; T-12-05: today's flag surface carries no secrets, verified command.rb:16-24)
- Recording sits AFTER the capture3 wait and BEFORE the raise, on success and failure alike; RunLog's safe_append degradation is the only guard — no second layer (per plan)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Event specs' lazy seam setup never installed RunLog.current at capture time**
- **Found during:** Task 2 (GREEN verification — first run still red)
- **Issue:** `let(:log)` is lazy; in the two event-recording examples `log` was first referenced after `capture_output` ran, so `RunLog.current` was nil during the capture. The first fix attempt (`expect(RunLog.current).to equal(log)`) still failed: `expect(actual)` evaluates actual before matcher args, so the open happened too late even there
- **Fix:** Force the lazy open in a separate statement first (`expect(log).to be_a(SPMCache::Core::RunLog)`), then assert `RunLog.current` identity, then run the capture — with a comment explaining the evaluation-order trap
- **Files modified:** spec/sh_run_log_sink_spec.rb
- **Verification:** `bundle exec rspec spec/sh_run_log_sink_spec.rb spec/core_spec.rb` → 22 examples, 0 failures
- **Committed in:** 337ef90 (part of Task 2 GREEN commit)

---

**Total deviations:** 1 auto-fixed (1 × Rule 1 spec-harness correction; zero production-code deviations — the implementation passed both RED spec sets on first write)
**Impact on plan:** None on scope or design; the RED signal itself was valid (no events recorded), only the harness ordering was wrong.

## Issues Encountered
- The editor's rubocop daemon again auto-corrected style file-wide on save of touched files (require-quote conversion in sh.rb, `%W[]` array + line re-wrap in the spec) — behavior-identical Ruby aligned with the project's own `make format`, same phenomenon 12-01 documented; accepted rather than fought
- Full-suite example count: 468 → 480, exactly +12 (the new file's 12 examples; the spec_helper's 3 embedded examples count once per process, matching 12-01's accounting). core_spec and every terminal-parity example unchanged — the nil-disables regression net held

## User Setup Required
None - no external service configuration required.

## Known Stubs
None — every surface is wired to real behavior; no placeholders, TODOs, or mock data paths were found in the stub scan.

## Threat Flags

None — no security-relevant surface beyond the plan's threat_model. T-12-01 (log-forging) mitigated as planned: subprocess text lands only in body lines via JSON.generate, `sh` events carry escaped cmd + numeric status; T-12-04 (disk-fill) remains deliberately deferred to Plan 12-03's retention, with only the raised message bounded here (D-05 honored by the 100-line full-fidelity example).

## Next Phase Readiness
- `live_log_out:`/`live_log_err:` are exactly the opts Plan 12-04 forwards from `Buildable#xcodebuild` (build.rb:80-87 forwards `opts[:live_log]` today — the same pass-through site gains the pair) to activate sink capture from the real build path
- The `RunLog.current&.event` seam usage is the precedent Plans 12-04 (phase/package markers) and 12-05 (watch cycles) extend
- LOGS-01 remains open: SC4 retention (12-03), build-path sink + markers (12-04), watch per-cycle files (12-05)

## TDD Gate Compliance

Both tasks followed RED → GREEN with the required commits (validated in git log):
- Task 1: `test(12-02)` RED (0bb2c5b, 4 failing) before `feat(12-02)` GREEN (95456a6)
- Task 2: `test(12-02)` RED (d5ee722, 2 failing) before `feat(12-02)` GREEN (337ef90)
- RED discipline held: each RED run demonstrated the exact new-behavior failures; regression pins passing in RED state were the expected legacy/nil paths

---
*Phase: 12-run-log-capture-foundation*
*Completed: 2026-08-31*

## Self-Check: PASSED

All created files exist on disk (spec/sh_run_log_sink_spec.rb, 12-02-SUMMARY.md); all four task commits (0bb2c5b, 95456a6, d5ee722, 337ef90) present in history; acceptance tokens verified in sh.rb (live_log_out/live_log_err opts, per-stream sink resolution in reader threads, failure_detail(out_tail, err_tail) stdout-first, single `RunLog.current&.event('sh'` call site with cmd+status); full suite 480 examples, 0 failures.
