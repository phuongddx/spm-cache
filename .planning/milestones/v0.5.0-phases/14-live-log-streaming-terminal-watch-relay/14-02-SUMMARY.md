---
phase: 14-live-log-streaming-terminal-watch-relay
plan: 02
subsystem: installer
tags: [installer, build-lock, d-05, logs-05, tdd, lock-contention, tee]

requires:
  - phase: 12-run-log-capture-foundation plan 01
    provides: the TeeIO swap over $stdout (run_log.rb:428-480) — the mechanism this plan rides with zero new machinery
  - phase: 12-run-log-capture-foundation plan 01
    provides: RunLog::CycleWrapper (run_log.rb:494-563) — the watch-cycle tee the third tee example drives
  - phase: 14-live-log-streaming-terminal-watch-relay research
    provides: Pattern 5 (the three-step insert), the pinned copy from 14-UI-SPEC 'Lock-wait line (D-05)'
provides:
  - "'Waiting for build lock…' announced at BOTH blocking flock sites (Installer::Build#acquire_build_lock, Installer::Use#with_build_lock) exactly when contended, before blocking — the blocked run testifies about itself (CP10)"
  - "the line rides Core::UI.info → $stdout → the Phase 12 tee, so it lands in the blocked run's own JSONL as a T-12-01 body line {ts, stream 'out', text} — the stream (14-01) relays it like any body line and 14-05 renders it verbatim"
  - "the free-lock path is pinned byte-identical to pre-D-05 output (regression pins in spec/installer_lock_notice_spec.rb + the untouched build_lock/installer_build semantics suites)"
affects:
  - 14-01 (the SSE stream relays the notice as an ordinary out body line — no new event type, no lock-state channel)
  - 14-05 (renders the pinned string verbatim in-stream; 14-UI-SPEC lock-wait row)
  - 15 (BLD-02 waiting-state copy consumes the identical string — frozen once landed)

actuals:
  tokens: 4796   # chars/4 over the realized diff (19,182 chars across the 3 commits); plan estimated 20000 at confidence low
  tasks: 2
  commits: 3

tech-stack:
  added: []   # two stdlib calls (flock LOCK_NB, Core::UI.info) inside existing methods; no new runtime surface
  patterns:
    - "Probe → announce → block: a one-shot flock(LOCK_EX | LOCK_NB) whose false RETURN VALUE (never a raise — build_lock_spec.rb:41-45) gates the announce, so the free path evaluates no output at all; the blocking flock afterwards is byte-for-byte the pre-existing call"
    - "Announce-before-block proven structurally, not by timing: the spec's holder thread refuses to release the lock until the notice is visible in the announce buffer — an implementation announcing after acquiring deadlocks into the bounds and fails"

key-files:
  created:
    - spec/installer_lock_notice_spec.rb
    - .planning/phases/14-live-log-streaming-terminal-watch-relay/14-02-SUMMARY.md
  modified:
    - lib/spm_cache/installer/build.rb
    - lib/spm_cache/installer/use.rb

key-decisions:
  - "One-shot LOCK_NB probe with return-value check (no rescue, no polling, no backoff): flock's LOCK_NB returns false under contention and never raises on this platform, so the probe cannot take a skip path and the free path emits nothing — both prohibitions hold by construction"
  - "Same thread-held-flock fixture for contention instead of fork: real OS-level flock on the real Config#build_lock_path under a tmpdir project_dir (doctor_spec project_dir= idiom), with the holder waiting for the notice before releasing — announce-before-block becomes structural and every example stays bounded (web_server_boot join discipline)"
  - "Included-module constants are not lexically reachable from example blocks (Ruby resolves constants via the source cref): the pinned copy is exposed both as LockNoticeHelpers::NOTICE and a notice_text method"
  - "Task 2 committed once (GREEN message), not twice: the plan's RED expectation ('3 new failing examples') is unachievable when the mechanism already holds — Task 1 GREEN + Phase 12 TeeIO make the tee examples green on arrival, the plan prescribes no production edits for Task 2, and two commits over an identical tree are impossible"
  - "Task 1 RED landed with 4 failures, not the plan's literal '6': the two free-path examples are byte-identity regression pins and were green BEFORE D-05 by design — the plan's own truth #3 ('free-lock path byte-identical to today') makes a failing free pin a contradiction"

requirements-completed: [LOGS-05]

coverage:
  - id: LOGS-05-lock-wait-announce
    description: "Both blocking flock sites print 'Waiting for build lock…' to stdout before blocking, exactly once, only when contended (D-05 attribution half)"
    verification:
      - kind: tests
        ref: "spec/installer_lock_notice_spec.rb — 'announces exactly once to stdout before blocking' (Build + Use), 'routes the notice to stdout (Core::UI.info), never stderr', 'triggers the announce from the LOCK_NB trylock RETURN VALUE — raise-free'"
        status: pass
    human_judgment: false
  - id: LOGS-05-tee-landing
    description: "The notice is a T-12-01 body line {ts, stream 'out', text} in the blocked run's own JSONL, via the existing Phase 12 tee (Main.run shape AND watch-cycle shape); holder-run files gain nothing"
    verification:
      - kind: tests
        ref: "spec/installer_lock_notice_spec.rb — tee-landing describe: T-12-01 body-line shape, blocked-run-only landing, RunLog::CycleWrapper cycle, free-lock-with-tee byte-identity pin"
        status: pass
    human_judgment: false
  - id: LOGS-05-free-path-byte-identity
    description: "Free-lock path byte-identical to pre-D-05: no notice, no extra output, no behavior change; pre-existing cross-process lock semantics undisturbed"
    verification:
      - kind: tests
        ref: "spec/installer_lock_notice_spec.rb free-path pins (green pre- and post-D-05) + spec/installer_build_spec.rb, spec/build_lock_spec.rb, spec/installer_spec.rb green in the same verify run"
        status: pass
    human_judgment: false

duration: 25min
completed: 2026-09-01
status: complete
---

# Phase 14 Plan 02: D-05 "Waiting for build lock…" at Both Installer Flock Sites Summary

**Both blocking build-lock sites now announce contention before blocking — a one-shot `flock(LOCK_EX | LOCK_NB)` probe whose false return gates a single `Core::UI.info 'Waiting for build lock…'` (pinned copy: capital W, one ellipsis character, no trailing period), so the blocked run testifies about itself into its own JSONL via the Phase 12 tee with zero new logging machinery, while the free-lock path stays byte-identical (pinned green-before-and-after); full suite 797 examples, 0 failures.**

## Performance

- **Duration:** ~25 min (19:49–19:59 local; precondition suite through wave gate)
- **Tasks:** 2 (probe→announce→block at both sites; tee-landing proof)
- **Files:** 3 (2 production methods edited — 21 inserted lines; 1 new spec file — 10 examples)

## What Shipped vs Plan

### Task 1 — probe → announce → block at both flock sites (3c2bf03 RED → b5181d6 GREEN)
As planned. RED (`test(14-02): failing lock-notice specs for both flock sites (6 examples)`): 6 examples in the fixed Wave 0 file — contended/free × both sites + stream discipline + trylock semantics — with the thread-held flock helper (real OS contention on the real `Config#build_lock_path` under a tmpdir `project_dir`; holder releases only after the notice is visible, bounded joins throughout). **RED evidence: exactly 4 failures — the contended-dependent examples fail on the absent notice ('expected "Building 1 target(s)…" to include "Waiting for build lock…"', `notice_count` 0 vs 1); the 2 free-path examples pass by design** (they pin pre-D-05 output verbatim — a failing free pin would contradict the plan's byte-identity truth; see Deviations). GREEN (`feat(14-02): probe→announce→block at both build-lock sites (D-05)`): the identical three-step insert at `build.rb` `acquire_build_lock` and `use.rb` `with_build_lock` — one-shot LOCK_NB probe → `Core::UI.info 'Waiting for build lock…'` → the pre-existing blocking `flock(LOCK_EX)`; Pitfall-15 design comments preserved; the pinned string appears exactly once per method (grep-verified: 1 occurrence in each file, 2 total under lib/). **GREEN evidence: `bundle exec rspec spec/installer_lock_notice_spec.rb spec/installer_build_spec.rb spec/build_lock_spec.rb` green; acceptance run incl. `spec/installer_spec.rb` → 35 examples, 0 failures.**

### Task 2 — tee-landing proof (5e4e42d)
As planned in content, single commit in shape (see Deviations). Four examples appended (extend, not restructure): (1) direct `TeeIO` install over `$stdout` (Main.run's swap shape) → the run's JSONL gains exactly one body line with keys exactly `ts/stream/text` (no `event` key — T-12-01), `stream 'out'`, `ts` ISO-8601-UTC, and the terminal leg saw the identical string; (2) with holder-run and blocked-run logs concurrently open, the notice lands ONLY in the blocked run's file (parsed per line + raw-bytes negative); (3) through `RunLog.cycle_wrapper(installer, argv: ['watch'], log_dir:)` a watch-triggered cycle testifies identically (one `*-watch.jsonl`, same body-line shape); (4) free-lock-under-tee adds no line (byte-identity pin). All assertions parse `JSON.parse` per line — never raw substring hits on whole files. **Evidence: 13 examples (10 mine + 3 spec_helper's), 0 failures; green on arrival** — Task 1 GREEN + Phase 12 TeeIO already provide the mechanism, so the plan's RED expectation was unachievable; contended paths genuinely ran (holder-wait timing confirms announce→block→release; a dead path would burn the 2 s bounds × 3).

### Wave gate
`bundle exec rspec` → **797 examples, 0 failures** (787 baseline + exactly this plan's 10 examples). No production edits were needed in Phase 12 code — the mechanism held.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] GREEN edit initially dropped the `File.open` line in `acquire_build_lock`**
- **Found during:** Task 1 GREEN verify run
- **Issue:** The first edit replaced the two original lines (`lock = File.open(...)` + `lock.flock(File::LOCK_EX)`) but re-emitted only the flock half → `NameError: undefined local variable or method 'lock'`, caught immediately by 2 failures in `spec/build_lock_spec.rb` (the plan's own regression fence doing its job).
- **Fix:** Restored `lock = File.open(path, File::CREAT | File::RDWR)` before the probe; re-ran the full verify → green. Never reached a commit.
- **Files modified:** lib/spm_cache/installer/build.rb
- **Verification:** 35 examples, 0 failures incl. build_lock_spec
- **Commit:** none (fixed pre-commit inside Task 1; b5181d6 carries the corrected method)

### Clarifications (documented, not behavior deviations)

- **Task 1 RED failed 4/6, not the plan's literal "6 failures":** the two free-path examples are byte-identity regression pins and were green BEFORE D-05 by design — the plan's own must-have truth #3 ("free-lock path byte-identical to today") makes a failing free pin a logical contradiction. All 4 contended-dependent examples failed for the right reason (notice absent).
- **Task 2 committed once (GREEN message `5e4e42d`), not RED-then-GREEN:** the plan's "RED first: 3 new failing examples" is unachievable when Task 1 GREEN already emits via `Core::UI.info → $stdout` and Phase 12's TeeIO already exists — the plan itself prescribes no production edits for Task 2 ("this task proves it, it does not build it"). The examples ran and passed; committing the identical tree twice is impossible.
- **Suite arithmetic:** individual-file runs report +3 examples over the file's own count — `spec/spec_helper.rb` itself defines 3 `SPMCache` version/ROOT examples (repo convention, applies to every spec file).

**Total deviations:** 1 auto-fixed (Rule 1, caught by the verify fence pre-commit). **Impact:** none — committed production diff is exactly the two-method insert the plan specifies.

## Threat Flags

All three register dispositions honored; no surface beyond the plan's threat_model was introduced:

| Flag | File | Description |
|------|------|-------------|
| threat_mitigated: T-14-08 | spec/installer_lock_notice_spec.rb | Free-lock byte-identity pinned twice over (Task 1 pins + Task 2 under-tee pin) and the regression files (installer_build/build_lock/installer) ran green in the same verify commands |
| threat_mitigated: T-14-09 | lib/spm_cache/installer/{build,use}.rb | Raise-free return-value probe (LOCK_NB never raises; the trylock-semantics example pins no error class in output) and bounded contended examples prove the block still completes after release |
| threat_flag: T-14-10 (accepted) | both flock sites | No holder identity anywhere — the pinned copy has no slots; nothing added to leak |

## Known Stubs

None. The production change is the complete D-05 emission; stream relay (14-01) and verbatim rendering (14-05) are downstream plans by design, not stubs of this one.

## Verification

- **Task 1 RED:** `bundle exec rspec spec/installer_lock_notice_spec.rb` → 6 examples, **4 failures** (exactly the contended set), 2 byte-identity pins green
- **Task 1 GREEN:** `bundle exec rspec spec/installer_lock_notice_spec.rb spec/installer_build_spec.rb spec/build_lock_spec.rb spec/installer_spec.rb` → **35 examples, 0 failures**; pinned-string grep: exactly 1 occurrence per edited method, 2 total in lib/
- **Task 2:** `bundle exec rspec spec/installer_lock_notice_spec.rb` → **13 examples, 0 failures** (green on arrival — mechanism pre-proven; see Deviations)
- **Wave gate:** `bundle exec rspec` → **797 examples, 0 failures**
- Task commits: **3c2bf03** (RED), **b5181d6** (GREEN), **5e4e42d** (tee proof)
- Precondition honored before Task 1: `spec/installer_build_spec.rb spec/build_lock_spec.rb spec/installer_spec.rb` → 29 examples, 0 failures

## Self-Check: PASSED

All three key files exist on disk (`lib/spm_cache/installer/build.rb`, `lib/spm_cache/installer/use.rb`, `spec/installer_lock_notice_spec.rb`); all three task commits (3c2bf03, b5181d6, 5e4e42d) present in history on gsd/v0.5.0-web-interface; prohibitions spot-checked green — no polling/backoff/retry around either flock (one-shot probe only), no new event type or holder identity in the line, no web-side lock probing, free-path output identical (pinned), and the blocking `flock(File::LOCK_EX)` call is unchanged inside both inserts.
