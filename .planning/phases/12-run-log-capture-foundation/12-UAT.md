---
status: complete
phase: 12-Run-Log Capture Foundation
source: [12-VERIFICATION.md]
started: 2026-09-01T02:40:00Z
updated: 2026-09-01T03:05:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Real-TTY terminal byte-parity (SC3)
expected: Transcripts and exit codes identical with capture on vs `--no-run-log`. Hermetic StringIO byte-parity and exit-shape specs are green and TeeIO delegates tty?/isatty/sync/flush — a real TTY's buffering/isatty interplay is the one surface no automated spec exercises (12-VALIDATION.md manual-only item).
result: pass
evidence: Orchestrator-gathered empirical evidence (user-confirmed, not self-certified) — matched full-regen pair (lockfile deleted to force non-fast path, `recreate_dirs` wipes sandbox for identical pre-state), real TTY via `script`, real `Core::Sh` `swift package resolve`/`describe` subprocess streaming, on the reference project (`stress-ai/ios-stress-app/StressMonitor`). Capture-on vs `--no-run-log` transcripts byte-identical (md5 match), exit 0/0. Run-log `.jsonl` written only for capture-on. Also confirmed byte-identical on the `use` fast path with real ANSI enabled. Reference project left clean (lockfile restored).

### 2. Judgment-tier prohibition — no secrets in run logs
expected: argv-only capture (zero ENV reads in run_log.rb/sh.rb/main.rb), header credential redaction active (WR-02 specs green). Human review of the judgment-tier verdict: SUBSTANTIALLY HONORED with documented residual IN-08 (CREDENTIAL_PATTERN misses literal-`/` passwords and empty-user `:token@` forms — carried Info in 12-REVIEW.md).
result: pass
evidence: User-accepted after orchestrator live probe of the production seam (RunLog.redact_credentials at run_log.rb:125, not a reimplementation): normal and flag-embedded user:pass forms redact to [REDACTED]@; zero ENV[ reads across run_log.rb/sh.rb/main.rb confirms D-04 argv-only capture. IN-08 residual reproduced live (empty-user :token@ and literal-/ password forms leak verbatim into the header) and body-never-scrubbed noted as by-design D-05 — both accepted as documented residual per 12-REVIEW.md Info, not new gaps.

## Summary

total: 2
passed: 2
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps

None recorded. (The third human item — CR-02 deviation acceptance — was ACCEPTED in-session 2026-09-01 and is recorded in 12-VERIFICATION.md frontmatter/overrides_applied: 1.)
