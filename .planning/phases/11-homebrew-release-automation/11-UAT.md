---
status: testing
phase: 11-Homebrew Release Automation
source: [11-VERIFICATION.md]
started: 2026-08-31T00:00:00Z
updated: 2026-08-31T00:00:00Z
---

## Current Test

number: 1
name: First real publish observation — formula-changing commit+push has never executed live
expected: |
  The update-tap job's git commit + push path (the only step never exercised by the three
  dry-runs, which all ended idempotently or pre-edit) completes on a real formula-changing
  event, and the tap repo accepts the deploy-key push (branch protection / bot policy on
  phuongddx/homebrew-spm-cache is invisible to static checks). Either cut the v0.4.0
  release and observe, or run a scratch-tag drill first. (IN-04 promoted by verifier.)
awaiting: user response

## Tests

### 1. First real publish observation (commit+push path live)
expected: On the first real release (v0.4.0) — or a scratch-tag drill — the update-tap job's commit+push executes and lands in the tap repo; no auth/push failure. WR-01..03 commits (ec51795/c6df1a4/a505521) landed after live run 3: spec-pinned but not yet live-proven — this same observation covers them (optional pre-release re-dispatch also acceptable).
result: [pending]

### 2. Tap-side formula boot fix (operator, before v0.4.0's first green verify)
expected: phuongddx/homebrew-spm-cache formula wrapper fixed so the CLI boots under Homebrew Ruby >= 3.4 (kconv/nkf LoadError, logged in deferred-items.md) — edit wrapper to exec keg-only ruby@3.3. Operator-side edit in the tap repo; until then verify-publish stays red on the boot step, not the version assertion.
result: [pending]

### 3. Release-time asset attachment (WR-02 operator recommendation)
expected: From v0.4.0 on, attach spm-cache-<ver>.tar.gz to each release (git archive / tar --owner=0 --group=0 + gh release upload) so the workflow hashes stable attached bytes instead of the loudly-warned auto-generated archive fallback.
result: [pending]

## Summary

total: 3
passed: 0
issues: 0
pending: 3
skipped: 0
blocked: 0

## Gaps
