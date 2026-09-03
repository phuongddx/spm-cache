---
phase: 12-run-log-capture-foundation
plan: 03
subsystem: infra
tags: [retention, run-log, config, gitignore, disk-fill, prune]

requires:
  - phase: 12-run-log-capture-foundation (plan 12-01)
    provides: Core::RunLog open/header/finish structure, lexicographic-chronological file naming, Config#runs_dir
provides:
  - Config#runs_keep / #runs_max_mb (DEFAULT_CONFIG flat keys 50/500, Integer()-coercing readers with rescue-to-default) + commented yml-template documentation
  - Core::RunLog#prune(keep:, max_bytes:) — count+size hybrid, oldest-first, invoked from RunLog.open after the header lands (D-07); disposes T-12-04 (the phase's only high-severity threat)
  - Live-pid prune immunity (Process.kill(0, pid) probe; EPERM = alive) — Pitfall 6 / CP14 applied at birth
  - Command::Init .gitignore entry '.spm-cache/' (independent append-once per entry, D-02 / T-12-05)
affects: [12-run-log-capture-foundation (12-04/12-05: every RunLog.open now prunes), 14-live-log-streaming (retention bounds the tailer's file set)]

actuals:
  tokens: 3604   # chars/4 over the realized diff (14417 added chars); plan estimated 35000 at confidence low
  tasks: 3
  commits: 5

tech-stack:
  added: []   # stdlib only (Dir/File/Process/JSON already in use) — no new gems, per project constraint
  patterns:
    - "Rotation-time retention at open, after the atomic header lands — the current file exists and is excluded by path identity before the walk (D-07)"
    - "Liveness probe via Process.kill(0, pid): Errno::ESRCH = dead, any other error (EPERM) = alive, unparseable/absent pid = dead"
    - "Per-candidate rescue-skip (vanished/undeletable) inside a whole-walk rescue-to-warn — prune can never raise into a run"
    - "Per-entry append-once gitignore helper called twice — one concern per entry, independent early-return idempotency per entry"

key-files:
  created: []
  modified:
    - lib/spm_cache/core/config.rb
    - lib/spm_cache/core/run_log.rb
    - lib/spm_cache/command/init.rb
    - lib/spm_cache/assets/templates/spm-cache.yml.template
    - spec/config_spec.rb
    - spec/run_log_spec.rb
    - spec/init_spec.rb

key-decisions:
  - "Retention budgets govern the retained PRIOR runs: the just-opened run is subtracted from the candidate list before the count/size walk, so runs_keep: N keeps the N newest prior runs plus the live one — exactly the plan's count-bound truth (newest runs_keep + just-opened survive) and user-sensible ('50 runs of history')"
  - "Same-process sequential opens never prune each other (all share Process.pid → live-pid immunity); cross-process cleanup lands once the owning process dies — deliberate CP14-at-birth conservatism, and the reason the specs fabricate dead-pid files with 2020-prefixed timestamp names"
  - "A candidate with an unparseable/absent run_start pid is treated as dead (prunable) so retention still bounds junk *.jsonl files; only a parseable integer pid that answers Process.kill(0) is protected"
  - "The size budget is asserted with an exact survivor set at 1 MiB granularity (runs_max_mb is Integer-only); fabricated 600_000-byte files make the boundary unambiguous"
  - "ensure_gitignore was refactored to a two-call append_gitignore_entry helper — still two independent append-once checks (per-entry early return), per the pattern note's 'one entry per concern'"
  - "Idempotency spec asserts per-line anchored regex counts (/\\A\\.spm-cache\\/\\z/) — '.spm-cache/' contains 'spm-cache/' as a substring, so the old scan('spm-cache/') form would double-count"

patterns-established:
  - "Retention specs fabricate prior runs as real run_start headers with controllable pids + padding bytes — the fixture shape Plans 12-05 (watch cycles) and Phase 14 (tailer) can reuse for age/cleanup tests"
  - "Config budget readers: Integer(raw[k] || DEFAULT_CONFIG[k]) with ArgumentError/TypeError rescue-to-default — the research-V5 coercion shape for any future user-authored numeric knob"

requirements-completed: []  # LOGS-01 completes with 12-05; this plan closes SC4 (retention) and the D-02 gitignore half

coverage:
  - id: D1
    description: "Config#runs_keep / #runs_max_mb — DEFAULT_CONFIG keys 50/500, yml override, Integer() coercion rescue-to-default, template documentation"
    requirement: LOGS-01
    verification:
      - kind: unit
        ref: "spec/config_spec.rb#runs_keep and #runs_max_mb default to 50 runs / 500 MB with no yml keys"
        status: pass
      - kind: unit
        ref: "spec/config_spec.rb#read overrides from a written spm-cache.yml (3/12)"
        status: pass
      - kind: unit
        ref: "spec/config_spec.rb#coerces a non-integer runs_keep back to 50 / a nil runs_max_mb back to 500 (research V5)"
        status: pass
      - kind: unit
        ref: "spec/config_spec.rb#spm-cache.yml template documents the retention keys as commented defaults"
        status: pass
    human_judgment: false
  - id: D2
    description: "RunLog#prune — count+size hybrid at run start after the header lands (D-07), oldest-first lexicographic with exact survivor sets, current-run immunity at zero budgets, live-pid immunity + dead-pid pruning (Pitfall 6), under-budget no-op (EDGE empty), degradation on an undeletable candidate"
    requirement: LOGS-01
    verification:
      - kind: unit
        ref: "spec/run_log_spec.rb#retention keeps the newest runs_keep prior runs plus the just-opened one (count bound)"
        status: pass
      - kind: unit
        ref: "spec/run_log_spec.rb#retention prunes oldest-first lexicographic until the size budget fits; newest fabricated survives (size bound + EDGE ordering)"
        status: pass
      - kind: unit
        ref: "spec/run_log_spec.rb#retention never deletes the just-opened run even at zero budgets (current-run immunity — the current file exists during prune, D-07)"
        status: pass
      - kind: unit
        ref: "spec/run_log_spec.rb#retention never prunes a live-pid run even over budget; a dead-pid run is pruned (Pitfall 6 / CP14 at birth)"
        status: pass
      - kind: unit
        ref: "spec/run_log_spec.rb#retention deletes nothing when the runs dir is under both budgets (EDGE empty)"
        status: pass
      - kind: unit
        ref: "spec/run_log_spec.rb#retention skips a candidate it cannot delete and never raises into the run (degradation)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Command::Init .gitignore '.spm-cache/' entry — both entries under own labeled comments after fresh init, exactly-once after re-init, exact append shape against an existing .gitignore (D-02)"
    requirement: LOGS-01
    verification:
      - kind: unit
        ref: "spec/init_spec.rb#generates spm-cache.yml + seeded lockfile + .gitignore entry (both entries + comments asserted)"
        status: pass
      - kind: unit
        ref: "spec/init_spec.rb#is idempotent — per-entry anchored-regex exactly-once counts for spm-cache/ and .spm-cache/"
        status: pass
      - kind: unit
        ref: "spec/init_spec.rb#appends .spm-cache/ to an existing .gitignore after a blank line with its own comment (exact line array)"
        status: pass
    human_judgment: false

duration: 14min
completed: 2026-08-31
status: complete
---

# Phase 12 Plan 03: Retention, config keys, and the .gitignore entry Summary

**Count+size hybrid retention (runs_keep 50 / runs_max_mb 500, oldest-first, live-pid and current-run immunity) wired into RunLog.open after the header lands, Integer-coercing Config keys documented in the yml template, and init's .gitignore gains the '.spm-cache/' run-logs entry — full suite 492 examples green, T-12-04 disposed**

## Performance

- **Duration:** 14 min
- **Started:** 2026-08-31T17:03:38Z
- **Completed:** 2026-08-31T17:17:00Z
- **Tasks:** 3
- **Files modified:** 7

## Accomplishments
- SC4 closed: every `RunLog.open` now prunes after the atomic header rename (D-07 rotation-time cleanup) — prior runs are deleted oldest-first (timestamp-prefixed names: lexicographic == chronological) while count > runs_keep OR total bytes > runs_max_mb; only whole files are ever deleted (D-05 fidelity untouched), disposing the phase's only high-severity threat T-12-04 (disk-fill)
- The just-opened run is never a prune candidate (excluded by path identity before the walk), and neither is any candidate whose run_start pid is alive — `Process.kill(0, pid)` probe with ESRCH=dead / EPERM-etc.=alive (Pitfall 6 / CP14 applied at birth, machine-probed before implementation)
- Prune degradation is two-layered: a vanished/undeletable candidate is skipped (per-candidate rescue — proven with a directory matching *.jsonl that File.delete can never unlink), and the whole walk rescues to a single warn_once; prune can never raise into a run
- Config surface: DEFAULT_CONFIG gains flat snake_case `runs_keep` (50) / `runs_max_mb` (500) with D-06 citation; readers Integer()-coerce with ArgumentError/TypeError rescue-to-default (yml is user-authored — research V5); the yml template documents both keys as commented lines in the `# cache_only:` style with a one-line hybrid-retention explanation; existing ymls keep working untouched (load merges over DEFAULT_CONFIG)
- D-02 landed: `Command::Init#ensure_gitignore` appends `.spm-cache/` under its own `# spm-cache run logs` comment alongside the untouched `spm-cache/` entry — two independent append-once checks, idempotent per entry (T-12-05: run logs stay out of VCS)
- Full suite green: 492 examples, 0 failures (480 post-12-02 + exactly 12 new: 5 config, 6 retention, 1 init-append)

## Task Commits

Each task was committed atomically (TDD: RED before GREEN on Tasks 1–2):

1. **Task 1 RED: failing config-key specs** - `1fd0caa` (test)
2. **Task 1 GREEN: runs_keep/runs_max_mb keys + template docs** - `c816ffb` (feat)
3. **Task 2 RED: failing retention specs** - `0386e69` (test)
4. **Task 2 GREEN: RunLog#prune wired into open** - `b32c17d` (feat)
5. **Task 3: .spm-cache/ gitignore entry (auto — spec+impl together)** - `b83decb` (feat)

**Plan metadata:** docs commit (this commit: SUMMARY + STATE + ROADMAP)

## Files Created/Modified
- `lib/spm_cache/core/config.rb` - DEFAULT_CONFIG retention keys + Integer-coercing readers (D-06, research V5)
- `lib/spm_cache/core/run_log.rb` - `prune(keep:, max_bytes:)` + private `file_size`/`live_pid?`/`run_start_pid` helpers; `.open` calls prune after the header rename with Config-derived budgets
- `lib/spm_cache/command/init.rb` - `ensure_gitignore` → two-call `append_gitignore_entry` helper ('spm-cache/' sandbox + '.spm-cache/' run logs, one concern per entry)
- `lib/spm_cache/assets/templates/spm-cache.yml.template` - commented `# runs_keep: 50` / `# runs_max_mb: 500` with hybrid-retention explanation
- `spec/config_spec.rb` - +5 examples: defaults, yml override, two coercion cases, template docs (Singleton reset! per precedent)
- `spec/run_log_spec.rb` - +6 retention examples under a sibling `retention` group (fabricated prior runs with controllable pids/sizes)
- `spec/init_spec.rb` - both-entries assertions, anchored-regex exactly-once idempotency counts, exact-shape existing-gitignore append example

## Decisions Made
- Budgets govern the retained PRIOR runs (the current run is outside both count and size): the plan's count-bound truth ("newest runs_keep files plus the just-opened one remain") forces this on the count side; the same semantics were extended to size for consistency — "runs_keep: 50" reads as "50 runs of history"
- Same-process sequential opens never prune each other (shared Process.pid → live-pid immunity); cleanup of a dead process's logs lands on the next run from any other process — deliberately conservative (a live run's log is never a prune candidate, even over budget)
- Unparseable/absent run_start pid → treated as dead so retention still bounds junk `*.jsonl` files; only a parseable integer pid that answers `Process.kill(0)` is protected (T-12-01: prune parses only its candidates' own first-line headers, never body content)
- Degradation spec uses a directory matching `*.jsonl` as the undeletable candidate — a deterministic real-FS stand-in for a file vanishing mid-walk (concurrent prune), forcing the per-candidate rescue without stubs

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- The editor's rubocop daemon again auto-corrected style file-wide on save of touched files (quote conversion + re-indentation in config_spec.rb / init_spec.rb / run_log_spec.rb) — behavior-identical Ruby aligned with the project's own `make format`, same phenomenon 12-01/12-02 documented; accepted rather than fought
- Editor paste misfires during implementation (a spec group briefly nested in the wrong describe, a method body briefly split) were caught by syntax checks / re-reads and repaired before any commit — no commit contains broken structure; RED→GREEN signal was never affected

## User Setup Required
None - no external service configuration required.

## Known Stubs
None — every surface is wired to real behavior; no placeholders, TODOs, or mock data paths were found in the stub scan.

## Threat Flags

None — no security-relevant surface beyond the plan's threat_model. T-12-04 (disk-fill, high) is DISPOSED here as planned: count+size hybrid retention at every run start, spec-proven with exact survivor sets. T-12-03 (symlink swap, accepted): prune unlinks individual `*.jsonl` candidate names only — no rm_rf, no directory replacement. T-12-05 (run logs in VCS) mitigated by the `.spm-cache/` gitignore entry. T-12-02 values additionally Integer-coerced with rescue-to-default.

## Next Phase Readiness
- SC4 is closed; every `RunLog.open` from Plans 12-04 (build-path wiring) and 12-05 (watch cycles) now exercises prune implicitly — their tmpdir-based specs are unaffected (defaults 50/500 prune nothing in fresh dirs, verified: main_run_log_spec 48 examples green alongside retention)
- The retention spec's fabricated-prior-run fixture (real run_start header + controllable pid/padding) is the reusable shape for Phase 14 tailer tests that need aged run sets
- LOGS-01 remains open: build-path sink + phase/package markers (12-04), watch per-cycle files (12-05)

## TDD Gate Compliance

Both tdd tasks followed RED → GREEN with the required commits (validated in git log):
- Task 1: `test(12-03)` RED (1fd0caa, 5 failing: readers undefined + template lines missing) before `feat(12-03)` GREEN (c816ffb)
- Task 2: `test(12-03)` RED (0386e69, 4 failing: prune not called) before `feat(12-03)` GREEN (b32c17d)
- Task 3 was `type="auto"` (spec + implementation in one commit, per plan)
- RED discipline held: each RED run demonstrated exactly the new-behavior failures; the trivially-green examples (EDGE empty pin, degradation pin) were regression anchors, matching 12-02's pattern

---
*Phase: 12-run-log-capture-foundation*
*Completed: 2026-08-31*

## Self-Check: PASSED

All created/modified files exist on disk (config.rb, run_log.rb, init.rb, yml template, three spec files, 12-03-SUMMARY.md); all five task commits (1fd0caa, c816ffb, 0386e69, b32c17d, b83decb) present in history; structural greps confirmed (def prune in run_log.rb, DEFAULT_CONFIG runs_keep 50 / runs_max_mb 500, template commented key lines, .spm-cache/ append in init.rb:207); full suite 492 examples, 0 failures.
