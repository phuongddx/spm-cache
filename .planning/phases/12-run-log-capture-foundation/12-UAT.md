---
status: testing
phase: 12-Run-Log Capture Foundation
source: [12-VERIFICATION.md]
started: 2026-09-01T02:40:00Z
updated: 2026-09-01T02:40:00Z
---

## Current Test

number: 1
name: Real-TTY terminal byte-parity (SC3)
expected: |
  Run `spm-cache use` (or a failing `spm-cache build`) on the reference project with and
  without `--no-run-log`; diff the terminal transcripts and exit codes — identical in both.
awaiting: user response

## Tests

### 1. Real-TTY terminal byte-parity (SC3)
expected: Transcripts and exit codes identical with capture on vs `--no-run-log`. Hermetic StringIO byte-parity and exit-shape specs are green and TeeIO delegates tty?/isatty/sync/flush — a real TTY's buffering/isatty interplay is the one surface no automated spec exercises (12-VALIDATION.md manual-only item).
result: [pending]

### 2. Judgment-tier prohibition — no secrets in run logs
expected: argv-only capture (zero ENV reads in run_log.rb/sh.rb/main.rb), header credential redaction active (WR-02 specs green). Human review of the judgment-tier verdict: SUBSTANTIALLY HONORED with documented residual IN-08 (CREDENTIAL_PATTERN misses literal-`/` passwords and empty-user `:token@` forms — carried Info in 12-REVIEW.md).
result: [pending]

## Summary

total: 2
passed: 0
issues: 0
pending: 2
skipped: 0
blocked: 0

## Gaps

None recorded. (The third human item — CR-02 deviation acceptance — was ACCEPTED in-session 2026-09-01 and is recorded in 12-VERIFICATION.md frontmatter/overrides_applied: 1.)
