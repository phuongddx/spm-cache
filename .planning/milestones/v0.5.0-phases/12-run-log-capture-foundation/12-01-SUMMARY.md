---
phase: 12-run-log-capture-foundation
plan: 01
subsystem: infra
tags: [jsonl, run-log, tee, io-wrappers, claide, logging]

requires:
  - phase: 11-v0.4.0-release
    provides: green 441-example hermetic suite, Core::Sh output(line) seam, CLAide command tree
provides:
  - Core::RunLog JSONL writer (atomic run_start header, verbatim body lines, structured events, idempotent run_end)
  - RunLog.pre_scan raw-argv routing (--no-run-log, --log-dir both forms, verb, web/watch exclusions)
  - RunLog.current process-wide seam (save/restore nested at open/finish) consumed by Plans 02/04/05
  - RunLog::TeeIO write-through $stdout/$stderr wrappers and RunLog::StreamSink (Core::Sh live_log contract)
  - Main.run tee install + three-shape exit capture (SystemExit/Interrupt/StandardError, bare-raise everywhere)
  - Config#runs_dir at <project>/.spm-cache/runs (outside the sandbox, D-02)
  - --no-run-log CLI flag (CLAide declaration + Options::RUN_LOG + run_log? reader, D-03)
affects: [12-run-log-capture-foundation, 13-server-skeleton, 14-live-log-streaming]

actuals:
  tokens: 10126   # chars/4 over the realized diff (lib+spec, 40507 added chars); plan estimated 45000 at confidence low
  tasks: 2
  commits: 3

tech-stack:
  added: []   # stdlib only (json/tempfile/fileutils) — no new gems, per project constraint
  patterns:
    - "Global tee via $stdout/$stderr swap (write-through TeeIO), never IO monkey-patching"
    - "Atomic header publish via same-dir Tempfile + File.rename (provenance-sidecar pattern)"
    - "Raw-argv pre-scan before CLAide parse (--version intercept precedent)"
    - "Bare-raise observation in rescue/ensure — status captured, exception untouched (Pitfall 2)"
    - "Mutex-serialized single-write JSONL appends with warn-once degradation"

key-files:
  created:
    - lib/spm_cache/core/run_log.rb
    - spec/main_run_log_spec.rb
    - spec/run_log_spec.rb
  modified:
    - lib/spm_cache/main.rb
    - lib/spm_cache/core/config.rb
    - lib/spm_cache/command.rb
    - lib/spm_cache/command/base.rb

key-decisions:
  - "Body lines carry only ts/stream/text and never an `event` key — structured events stay distinguishable from logged subprocess text by construction (T-12-01 log-forging mitigation)"
  - "File naming %Y%m%dT%H%M%S%3NZ-<pid>-<verb>.jsonl — ms precision (deliberate deviation from RESEARCH Pattern 6) so same-second watch cycles cannot collide; lexicographic == chronological"
  - "flush_partial_buffers at finish: a trailing no-newline `print` is emitted as a final body line instead of dropped (SC2)"
  - "CLAide 1.1.0 rejects the space-separated `--log-dir X` form outright (Unknown option -> Help -> SystemExit 1); only --log-dir=X is valid CLI syntax. pre_scan still honors both forms so even the rejected invocation is logged (header + run_end status 1)"

patterns-established:
  - "RunLog.current accessor is the sink seam — Plans 02 (capture3 sh events), 04 (phase/package markers), 05 (watch cycles) attach through it; shape change requires re-checking those plans"
  - "StreamSink(run_log, 'out'|'err') adapts Core::Sh's single-object live_log contract to per-stream attribution (Pitfall 4)"

requirements-completed: []   # LOGS-01 completes with Plans 12-02..12-05 (SC2 Sh sink = 02, SC4 retention = 03, watch cycles = 05); SC1/SC3 slice proven here

coverage:
  - id: D1
    description: "Core::RunLog JSONL writer — atomic run_start header, verbatim body lines via JSON.generate, structured event(), idempotent finish(), mutex-serialized appends, warn-once degradation"
    requirement: LOGS-01
    verification:
      - kind: unit
        ref: "spec/run_log_spec.rb#header atomicity publishes a complete parseable run_start at open with no *.tmp residue"
        status: pass
      - kind: unit
        ref: "spec/run_log_spec.rb#verbatim capture and JSON escaping round-trips quotes, backslashes, embedded newlines and ANSI bytes"
        status: pass
      - kind: unit
        ref: "spec/run_log_spec.rb#finish is idempotent: double finish writes exactly one run_end and restores RunLog.current"
        status: pass
      - kind: unit
        ref: "spec/run_log_spec.rb#concurrency (EDGE adjacency) serializes concurrent appends: 200 interleaved lines, every physical line valid JSON"
        status: pass
      - kind: unit
        ref: "spec/run_log_spec.rb#safety degradation never raises into the caller when an append fails, warning at most once and disabling the log"
        status: pass
    human_judgment: false
  - id: D2
    description: "Main.run tee wiring — exactly one JSONL file per run with run_start/body/run_end, byte-parity vs --no-run-log, all four exit shapes captured and re-raised untouched, web/watch/--no-run-log exclusions, --log-dir both forms"
    requirement: LOGS-01
    verification:
      - kind: integration
        ref: "spec/main_run_log_spec.rb#happy path with a stubbed command writes exactly one JSONL file: run_start header, stream-tagged body, run_end exit line"
        status: pass
      - kind: integration
        ref: "spec/main_run_log_spec.rb#tee invisibility (SC3) terminal bytes are identical with capture on vs --no-run-log"
        status: pass
      - kind: integration
        ref: "spec/main_run_log_spec.rb#exit-shape capture (every shape re-raises untouched)"
        status: pass
      - kind: integration
        ref: "spec/main_run_log_spec.rb#real failure path (EDGE empty) raises exactly as today and leaves a valid two-line run log"
        status: pass
      - kind: integration
        ref: "spec/main_run_log_spec.rb#exclusions + --log-dir override forms (D-01)"
        status: pass
    human_judgment: false
  - id: D3
    description: "TeeIO delegation surface and StreamSink per-stream adapter (Core::Sh live_log contract, sh.rb:24-25)"
    requirement: LOGS-01
    verification:
      - kind: unit
        ref: "spec/run_log_spec.rb#SPMCache::Core::RunLog::TeeIO delegates tty?, isatty, sync, sync=, flush to the real IO and returns its write byte count"
        status: pass
      - kind: unit
        ref: "spec/run_log_spec.rb#SPMCache::Core::RunLog::StreamSink routes output(line) to a per-stream record_text"
        status: pass
    human_judgment: false

duration: 31min
completed: 2026-08-31
status: complete
---

# Phase 12 Plan 01: Tracer — end-to-end run-log slice Summary

**Core::RunLog JSONL writer (atomic run_start header, verbatim stream-tagged body, idempotent run_end) + Main.run write-through tee with three-shape exit capture, --no-run-log/--log-dir pre-scan, and Config#runs_dir — terminal bytes and exit codes byte-identical**

## Performance

- **Duration:** 31 min
- **Started:** 2026-08-31T16:04:16Z
- **Completed:** 2026-08-31T16:36:00Z
- **Tasks:** 2
- **Files modified:** 7

## Accomplishments
- Every CLI verb routed through Main.run now leaves exactly one JSONL run log under the run dir: run_start header (command/argv/pid/started_at/spm_cache_version/trigger/cycle), verbatim stream-tagged body lines (ANSI bytes included), run_end exit line with numeric status
- Tee is invisible (SC3): byte-parity with --no-run-log proven; SystemExit→e.status, Interrupt→130, StandardError→exit_status||1 all captured and re-raised untouched via bare raise
- Exclusions exactly as designed: `--no-run-log` anywhere in argv, verb `web` (SC3), verb `watch` (D-09 per-cycle files are Plan 05); everything else logs (no allowlist, D-08)
- Writer hardened hermetically: header atomicity (no *.tmp residue), partial-line buffering, 200-line concurrency without interleaving, degradation that never raises into the wrapped run
- Full suite green: 468 examples, 0 failures (441 pre-existing — the terminal-parity regression net — plus 27 new)

## Task Commits

Each task was committed atomically:

1. **Task 1 RED: failing e2e specs** - `2768599` (test)
2. **Task 1 GREEN: Core::RunLog + Main.run tee/exit wiring** - `005c1b0` (feat)
3. **Task 2: writer unit specs — tee, atomicity, escaping, concurrency, degradation** - `ab1d25f` (test)

**Plan metadata:** docs commit (this commit: SUMMARY + STATE + ROADMAP)

_Note: Task 1 is a TDD tracer — RED spec commit precedes the GREEN implementation commit._

## Files Created/Modified
- `lib/spm_cache/core/run_log.rb` - Core::RunLog, pre_scan, RunLog.current seam, TeeIO, StreamSink, safe_append degradation
- `lib/spm_cache/main.rb` - tee install + SystemExit/Interrupt/StandardError exit capture around Command.run, streams restored before finish
- `lib/spm_cache/core/config.rb` - Config#runs_dir at project_dir/.spm-cache/runs (outside sandbox_dir, D-02/Pitfall 7)
- `lib/spm_cache/command.rb` - --no-run-log CLAide declaration + argv.flag?('run-log', true) parse (D-03)
- `lib/spm_cache/command/base.rb` - Options::RUN_LOG + run_log? reader
- `spec/main_run_log_spec.rb` - e2e wiring specs (16 examples): happy path, byte-parity, exit shapes, real-failure EDGE empty, exclusions, --log-dir forms
- `spec/run_log_spec.rb` - writer unit specs (11 examples): delegation, escaping, buffering, atomicity, idempotency, concurrency, degradation

## Decisions Made
- Body lines never carry an `event` key (T-12-01): renderers key on `event` only — logged subprocess text cannot forge structured events
- Millisecond file-name timestamps: same-second watch cycles (D-09) cannot collide on identical pid+verb; fixed-width %3N preserves lexicographic ordering for retention (Plan 12-03)
- Trailing partial lines are flushed at finish (a terminal `print` without newline is not silently dropped — SC2)
- Space-separated `--log-dir X` turns out to be invalid argv for CLAide 1.1.0 (argv.rb: `--log-dir` without `=` parses as a flag → "Unknown option" Help → SystemExit 1); pre_scan honors both forms anyway so the rejected invocation still gets a logged run_start + run_end(1)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Real-failure spec used CLAide-invalid argv form**
- **Found during:** Task 1 (GREEN verification)
- **Issue:** Plan's real-failure behavior bullet implied `['--log-dir', <dir>, 'use']` reaches `Use#run`; empirically CLAide 1.1.0 rejects the space-separated form outright ("Unknown option: `--log-dir`" → Help → SystemExit 1, claide argv.rb has no `--opt VALUE` parsing), so the example saw SystemExit instead of the raw RuntimeError
- **Fix:** Example uses `["--log-dir=#{tmpdir}", 'use']` (the valid form) with a comment explaining why; pre_scan keeps both forms per plan (the rejected space-form invocation is still logged, header + run_end status 1 — verified by probe)
- **Files modified:** spec/main_run_log_spec.rb
- **Verification:** `bundle exec rspec spec/main_run_log_spec.rb spec/main_version_spec.rb` → 21 examples, 0 failures
- **Committed in:** 005c1b0 (part of Task 1 GREEN commit)

**2. [Rule 1 - Bug] Concurrency spec line-count arithmetic**
- **Found during:** Task 2 (first run)
- **Issue:** Expected 201 physical lines; header + 200 body + run_end = 202 — the writer was correct, the expectation was not
- **Fix:** eq(202) plus an explicit 200-bodies assertion
- **Files modified:** spec/run_log_spec.rb
- **Verification:** `bundle exec rspec spec/run_log_spec.rb spec/main_run_log_spec.rb` → 30 examples, 0 failures
- **Committed in:** ab1d25f (part of Task 2 commit)

---

**Total deviations:** 2 auto-fixed (2 × Rule 1 spec corrections; zero production-code deviations — Task 1's implementation passed all Task 2 hardening behaviors unchanged)
**Impact on plan:** None on scope or design; both were expectation-side corrections grounded against claide 1.1.0 gem source and actual file contents.

## Issues Encountered
- The editor's rubocop daemon auto-corrected quote style file-wide on every save of touched files (single quotes, no trailing commas). Behavior-identical Ruby, aligned with rubocop defaults and the project's own `pre-commit`/`make format` (`rubocop --auto-correct`) — accepted rather than fought; it slightly inflates the diff on untouched lines of command.rb/base.rb/config.rb/main.rb.
- Full-suite example counts vs per-file runs differ by design in this repo (spec_helper embeds 3 examples; solo runs re-register them per process): baseline 441 → final 468, exactly 441 + 27 new examples (+16 spec/main_run_log_spec.rb, +11 spec/run_log_spec.rb). A per-file documentation diff against the pristine tree confirmed zero pre-existing examples changed.

## User Setup Required
None - no external service configuration required.

## Known Stubs
None — every surface is wired to real behavior; no placeholders, TODOs, or mock data paths were found in the stub scan.

## Next Phase Readiness
- `RunLog.current` seam + `StreamSink` are exactly the shape Plans 12-02 (Sh popen3/capture3 sinks + failure_detail tails) and 12-04 (phase/package markers) consume
- Lexicographic-chronological file naming is ready for Plan 12-03's retention prune (runs_keep/runs_max_mb keys land there, plus the `.spm-cache/` gitignore entry D-02 assigns to this phase's later plan)
- LOGS-01 stays open until 12-05: SC2 subprocess output (02), SC4 retention (03), watch per-cycle files (05)

---
*Phase: 12-run-log-capture-foundation*
*Completed: 2026-08-31*

## Self-Check: PASSED

All created files exist on disk; all three task commits (2768599, 005c1b0, ab1d25f) present in history; structural greps confirmed (class RunLog, def runs_dir, --no-run-log row); full suite 468 examples, 0 failures.
