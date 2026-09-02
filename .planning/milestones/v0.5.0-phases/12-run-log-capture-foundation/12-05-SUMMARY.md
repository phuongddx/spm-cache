---
phase: 12-run-log-capture-foundation
plan: "05"
subsystem: infra
tags: [run-log, watch, per-cycle, d-09, d-08, cycle-wrapper, decorator, installer-factory]
requires:
  - phase: 12-run-log-capture-foundation (plan 12-01)
    provides: Core::RunLog open/tee/finish/current save-restore, pre_scan raw-argv routing, ms-precise file naming
  - phase: 12-run-log-capture-foundation (plan 12-03)
    provides: RunLog#prune at every open (D-07) — cycle opens prune identically
  - phase: 12-run-log-capture-foundation (plan 12-04)
    provides: phase/package markers via RunLog.current — land in the cycle file for free once current is set
provides:
  - Core::RunLog.cycle_wrapper(installer, argv:) + RunLog::CycleWrapper — per-cycle decorator (fresh cycle RunLog with command "watch"/trigger "watch"/cycle true, tee swap, three-shape exit capture, streams + current restored in ensure)
  - D-01 at the watch surface: each cycle resolves runs_dir via RunLog.pre_scan(argv).log_dir || Config#runs_dir — `watch --log-dir X` never silently writes cycles to the default dir
  - Command::Watch cycle-wrapped installer_factory — `watch --once` logs identically through run_once + the same factory; Core::Watcher untouched (0-line diff)
  - D-08 no-allowlist proof as specs — exclusion decision is verb-set based {web, watch} + --no-run-log, structurally not an allowlist (future-verb row, mutation-proven)
  - A6 (legacy `use --watch` = ONE session-level 'use' run at Main level) and A5 (inter-cycle Watcher narrative terminal-only, D-09 forbids a session file) recorded as asserted specs with research citations
affects: [14-live-log-streaming (Phase 14 relays each regeneration as its own run — cycle files are the per-run unit), 13-server-skeleton]
actuals:
  tokens: 5525   # chars/4 over the realized diff (22101 diff chars); plan estimated 30000 at confidence low
  tasks: 2
  commits: 3
tech-stack:
  added: []   # stdlib only — no new gems, per project constraint
  patterns:
    - "Decorator at the injected-factory seam: the wrapper responds to exactly perform_install (the only method Core::Watcher calls), so the daemon is oblivious by construction"
    - "Same three-shape rescue/ensure contract duplicated from Main.run at cycle granularity — SystemExit/Interrupt/StandardError status captured, bare raise, streams restored before finish"
    - "Mutation-proven no-allowlist spec (Phase 10 fail-first precedent): flipping pre_scan to an enumerated-verb allowlist fails exactly the future-verb row"
key-files:
  created: []
  modified:
    - lib/spm_cache/core/run_log.rb
    - lib/spm_cache/command/watch.rb
    - spec/watch_spec.rb
    - spec/run_log_spec.rb
key-decisions:
  - "CycleWrapper resolves runs_dir per cycle from RunLog.pre_scan(argv) — argv is threaded into the wrapper raw (ARGV at the watch surface), so D-01 is honored below parsing exactly like Main.run honors it above parsing"
  - "The wrapper follows the plan's explicit action and opens the cycle log unconditionally (nil-safe only on open degrade): --no-run-log stays a Main-level escape hatch, not a per-cycle one — no suppressed check inside the wrapper"
  - "A mid-cycle Interrupt lands the cycle's run_end (status 130) from the wrapper's ensure BEFORE Core::Watcher's rescue Interrupt proceeds — the ordering the SC3 truth requires, proven with a raising double"
  - "Restoration asserted pre-helper: the spec captures the swapped StringIOs and asserts identity immediately after perform_install returns, so a leaked tee fails visibly (a begin/ensure helper alone would mask it)"
  - "The inter-cycle narrative proof drives the watcher's own private info path (send(:info, ...)) between two run_once cycles — the real write path, with the StringIO sink proving the narrative was emitted yet persisted nowhere"
requirements-completed: [LOGS-01]
coverage:
  - id: D1
    description: "RunLog.cycle_wrapper + CycleWrapper — per-cycle open (run_start command watch / trigger watch / cycle true / own argv+pid), tee swap, exit shapes 0/1/130/3 with propagation, two-cycles-two-files, --log-dir cycle override, stream + current restoration, inter-cycle writes excluded"
    requirement: LOGS-01
    verification:
      - kind: unit
        ref: "spec/watch_spec.rb#cycle_wrapper writes one self-contained cycle file: run_start watch/watch/cycle true, one out body, run_end 0; streams and current restored"
        status: pass
      - kind: unit
        ref: "spec/watch_spec.rb#captures status 1 and propagates a GeneralError raised inside the cycle"
        status: pass
      - kind: unit
        ref: "spec/watch_spec.rb#captures status 130 and propagates Interrupt (a mid-cycle Ctrl-C still lands run_end via the ensure)"
        status: pass
      - kind: unit
        ref: "spec/watch_spec.rb#captures SystemExit(3) status verbatim and propagates (same three-shape contract as Main.run)"
        status: pass
      - kind: unit
        ref: "spec/watch_spec.rb#two cycles produce two distinct self-contained files (D-09: no session file; ms-precise names disambiguate)"
        status: pass
      - kind: unit
        ref: "spec/watch_spec.rb#honors --log-dir for cycles (D-01: the override is never a dead knob on the watch surface)"
        status: pass
      - kind: unit
        ref: "spec/watch_spec.rb#captures only the cycle own output: writes printed between cycles (no tee active) land in no file"
        status: pass
      - kind: integration
        ref: "spec/watch_spec.rb#Command::Watch wraps Installer::Use in the cycle wrapper; --once logs one complete cycle file through the real run_once"
        status: pass
      - kind: unit
        ref: "spec/watch_spec.rb#A5: inter-cycle Watcher narrative is terminal-only — it is emitted but lands in no cycle file (D-09: no session file)"
        status: pass
    human_judgment: false
  - id: D2
    description: "D-08 no-allowlist proof — exclusion set is exactly {web, watch} + --no-run-log; every real verb and any future verb log; A6 session-level row; both --log-dir forms; watch + --log-dir row"
    requirement: LOGS-01
    verification:
      - kind: unit
        ref: "spec/run_log_spec.rb#.pre_scan truth table: every real verb logs: use/build/doctor/cache/rollback/remote/pkg/init"
        status: pass
      - kind: unit
        ref: "spec/run_log_spec.rb#.pre_scan truth table: a future verb logs with no code change — the exclusion set is {web, watch}, not a membership list"
        status: pass
      - kind: unit
        ref: "spec/run_log_spec.rb#.pre_scan truth table: excludes exactly web and watch at Main level (SC3 / D-09)"
        status: pass
      - kind: unit
        ref: "spec/run_log_spec.rb#.pre_scan truth table: suppresses on --no-run-log wherever it appears (D-03)"
        status: pass
      - kind: unit
        ref: "spec/run_log_spec.rb#.pre_scan truth table: legacy 'use --watch' logs as ONE session-level use run at Main level (A6 / Open Question 1, CP5)"
        status: pass
      - kind: unit
        ref: "spec/run_log_spec.rb#.pre_scan truth table: reads both --log-dir forms for any logging verb (D-01)"
        status: pass
      - kind: unit
        ref: "spec/run_log_spec.rb#.pre_scan truth table: watch + --log-dir: no Main session file, and the override still routes cycle files (D-01 consumed by RunLog.cycle_wrapper)"
        status: pass
    human_judgment: false
duration: 10min
completed: 2026-08-31
status: complete
---

# Phase 12 Plan 05: Watch per-cycle run logs + D-08 coverage proof Summary

**Every watch regeneration cycle is now its own complete JSONL run log — `RunLog.cycle_wrapper` decorates the installer at Command::Watch's injected factory seam (Core::Watcher untouched, 0-line diff), each cycle opening with command "watch"/trigger "watch"/cycle true, teeing the streams, capturing all three exit shapes, and resolving `--log-dir` per cycle so the override is live at the watch surface (D-01); D-08's no-allowlist property is spec-proven with a mutation-tested future-verb row, and A6/A5 are recorded as asserted specs — full suite 519 examples green, LOGS-01 complete**

## Performance

- **Duration:** 10 min
- **Started:** 2026-08-31T17:48:41Z
- **Completed:** 2026-08-31T17:58:00Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- SC1/D-09 closed: the watch daemon writes one timestamped run log per regeneration cycle — own run_start (command "watch", trigger "watch", cycle true, the invocation's argv, own pid/started_at), stream-tagged body lines for everything the cycle printed, own run_end — never a session file. Two cycles → two distinct self-contained files (ms-precise naming; same-ms collisions still disambiguate via the open-path `-N` suffix)
- SC3 preserved: the cycle tee is write-through (terminal bytes asserted), streams and RunLog.current are restored before finish, and every failure shape re-raises untouched — a mid-cycle Interrupt lands the cycle's run_end(130) from the wrapper's ensure before Core::Watcher's rescue Interrupt proceeds exactly as before
- Setting RunLog.current per cycle means Plan 12-04's detect/integrate markers and Plan 12-02's sh events now land in the CYCLE file for free — verified through the run_once-level integration example
- D-01 at the watch surface: `watch --log-dir X` routes cycle files into X (runs_dir = RunLog.pre_scan(argv).log_dir || Config#runs_dir); without it, cycles land in Config#runs_dir; cycle opens prune too (D-07 — a long watch session stays bounded, disposing T-12-04)
- D-08 proven: the pre_scan truth table asserts the exclusion decision is verb-set based — every real verb logs, `['frobnicate']` logs with no code change (mutation-proven: flipping pre_scan to an enumerated allowlist fails exactly that row), and the watch + --log-dir row shows no Main session file while the override still routes cycle files
- A6/A5 recorded as asserted examples citing research IDs: legacy `use --watch` logs as ONE session-level 'use' run (per-cycle mandate targets the watch daemon; the legacy loop is CLI-only per CP5); inter-cycle Watcher narrative is terminal-only by design (D-09 forbids a session file)
- Full suite green: 519 examples, 0 failures — 503 pre-existing (the terminal-parity regression net) + exactly 16 new (8 cycle/wiring + 7 truth table + 1 A5)

## Task Commits

Each task was committed atomically (TDD: RED before GREEN on Task 1):

1. **Task 1 RED: failing cycle-wrapper + factory wiring specs** - `ec08497` (test)
2. **Task 1 GREEN: RunLog.cycle_wrapper + Command::Watch per-cycle wiring** - `bb92c91` (feat)
3. **Task 2: D-08 no-allowlist proof + A6/A5 recorded decisions** - `cfea674` (test; single commit per the plan's own action — no production changes were needed, RED demonstrated by mutation, see TDD Gate Compliance)

**Plan metadata:** docs commit (this commit: SUMMARY + STATE + ROADMAP)

## Files Created/Modified
- `lib/spm_cache/core/run_log.rb` - `.cycle_wrapper(installer, argv:)` + `RunLog::CycleWrapper` (sibling of TeeIO/StreamSink): per-cycle open with runs_dir from pre_scan(argv).log_dir || Config#runs_dir, tee swap, SystemExit/Interrupt/StandardError status capture with bare raise, ensure restores streams before finish; nil-safe degrade when open fails
- `lib/spm_cache/command/watch.rb` - installer_factory wraps Installer::Use in the cycle wrapper (raw ARGV threads --log-dir into the wrapper); lazy require site unchanged; `--once` flows through run_once + the same factory
- `spec/watch_spec.rb` - +9 examples: 7 cycle-wrapper unit (shapes 0/1/130/3, restoration, two-cycles, --log-dir, inter-cycle exclusion), 1 run_once-level factory wiring, 1 A5 narrative example
- `spec/run_log_spec.rb` - +7 truth-table examples under `.pre_scan truth table (D-08: no allowlist)` (main RunLog describe, sibling of retention)

## Decisions Made
- CycleWrapper carries argv raw (ARGV at the watch surface) and resolves the runs dir per cycle — --log-dir is consumed below parsing exactly as Main.run consumes it above parsing, so the knob can never be dead on the watch surface
- Per the plan's explicit action, the wrapper opens the cycle log unconditionally (nil-safe only on open degrade): --no-run-log remains a Main-level escape hatch, not a per-cycle one
- The factory wiring example captures the REAL Watcher via and_wrap_original and asserts the factory it was built with returns a CycleWrapper — then drives `watch --once` end-to-end (stubbed Installer::Use, real run_once, real wrapper) so the wiring proof is production code, not a re-description
- Restoration is asserted before any helper's ensure runs (swapped StringIO identity + current nil immediately after perform_install) — a begin/ensure swap helper alone would restore the streams itself and mask a tee leak
- The A5 example drives the watcher's own private `info` path between two run_once cycles (its @out sink proves the narrative was emitted) and asserts each cycle file carries only its cycle's output

## Deviations from Plan

None - plan executed exactly as written.

Notes on process (not scope): the plan's Task 2 action prescribes a single `test(...)` commit with "no production-code changes expected" — the RED signal was demonstrated by mutation instead of a committed failing spec (details below). An initial edit misplaced CycleWrapper inside StreamSink (wrong nesting); caught by `ruby -c` + constant-resolution probe before any commit and repaired — no commit contains broken structure.

## Issues Encountered
- The editor's line-anchored patch flow needed two repair rounds on whitespace/nesting (CycleWrapper initially nested under StreamSink; truth-table block initially inside the retention group); every repair was verified with `ruby -c` and constant-resolution probes before proceeding — the RED→GREEN signal and commit history were never affected
- Task 2's truth table passed on first run against the committed pre_scan (it is already verb-set based, exactly what D-08 demanded of Plan 12-01) — the fail-first evidence is the mutation run, not a committed RED

## User Setup Required
None - no external service configuration required.

## Known Stubs
None — every surface is wired to real behavior; no placeholders, TODOs, or mock data paths were found in the stub scan.

## Threat Flags

None — no security-relevant surface beyond the plan's threat_model. T-12-04 (disk-fill via N cycle files, high) mitigated as planned: every cycle open runs Plan 12-03's prune (D-07 at every open) — the wrapper routes through RunLog.open unchanged. T-12-05: cycle argv is the watch invocation's own secret-free flags, recorded verbatim per the verified flag surface. T-12-01/T-12-02/T-12-03: unchanged dispositions — cycle files use the identical writer and runs-dir resolution as terminal runs.

## Next Phase Readiness
- LOGS-01 is COMPLETE: all four ROADMAP success criteria now trace across the five plans (SC1: 12-01+12-05; SC2: 12-02+12-04; SC3: 12-01+12-05; SC4: 12-03)
- Phase 14's relay consumes exactly these per-cycle files: each regeneration is its own run with header/body/events/exit, relaying by tailing the runs dir (ms-chronological names, retention-bounded)
- The remaining phase gate item is the manual real-CLI smoke from 12-VALIDATION.md before /gsd-verify-work (fixture project → build/use/watch --once leave parseable JSONL; failing run byte-identical stderr)

## TDD Gate Compliance

- Task 1 followed RED → GREEN with the required commits (validated in git log): `test(12-05)` RED (ec08497, 8 failing — `undefined method 'cycle_wrapper'` / `CycleWrapper` uninitialized, the exact pre-implementation signal; all 20 pre-existing watch examples green) before `feat(12-05)` GREEN (bb92c91, 29 examples across the three watch files)
- Task 2 (tdd="true" in the plan) prescribed exactly ONE commit with "no production-code changes expected" — a committed failing RED spec was impossible without deliberately breaking pre_scan first. The RED signal was demonstrated by mutation instead (the repo's Phase 10 fail-first precedent): pre_scan's exclusion was temporarily flipped to an enumerated-verb allowlist (`!%w[use build doctor cache rollback remote pkg init].include?(verb)`), the new truth-table run failed EXACTLY the future-verb row (7 examples, 1 failure), the mutation was reverted byte-identical (`git diff` clean), and the suite re-ran green before the single commit cfea674 — the proof has teeth without shipping a knowingly-broken implementation
- RED discipline held on Task 1: the RED run demonstrated exactly the new-behavior failures; no regression pin was needed

## Self-Check: PASSED

All modified files exist on disk (run_log.rb, watch.rb, watch_spec.rb, run_log_spec.rb, 12-05-SUMMARY.md); all three task commits (ec08497, bb92c91, cfea674) present in history; structural greps confirmed (`def self.cycle_wrapper` + `class CycleWrapper` at RunLog level, cycle-wrapper lambda in watch.rb with `argv: ARGV`, zero diff on core/watcher.rb); full suite 519 examples, 0 failures.

---
*Phase: 12-run-log-capture-foundation*
*Completed: 2026-08-31*
