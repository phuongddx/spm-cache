---
status: complete
phase: 11-Homebrew Release Automation
source: [11-VERIFICATION.md]
started: 2026-08-31T00:00:00Z
updated: 2026-08-31T04:00:00Z
---

## Current Test
[testing complete]
## Tests

### 1. First real publish observation (commit+push path live)
expected: On the first real release (v0.4.0) — or a scratch-tag drill — the update-tap job's commit+push executes and lands in the tap repo; no auth/push failure. WR-01..03 commits (ec51795/c6df1a4/a505521) landed after live run 3: spec-pinned but not yet live-proven — this same observation covers them (optional pre-release re-dispatch also acceptable).
result: skipped
reason: "Deferred follow-up: to v0.4.0 release cut (operator choice 2026-08-31). Static preconditions verified today: tap main unprotected (404), no rulesets, deploy key read_only=false verified=true, same SSH credential live-proven for checkout in run 33322506805. Remaining: literal commit+push execution + live proof of WR-01..03 — both fold into the real release, where the push is the desired outcome."

### 2. Tap-side formula boot fix (operator, before v0.4.0's first green verify)
expected: phuongddx/homebrew-spm-cache formula wrapper fixed so the CLI boots under Homebrew Ruby >= 3.4 (kconv/nkf LoadError, logged in deferred-items.md) — edit wrapper to exec keg-only ruby@3.3. Operator-side edit in the tap repo; until then verify-publish stays red on the boot step, not the version assertion.
result: pass

### 3. Release-time asset attachment (WR-02 operator recommendation)
expected: From v0.4.0 on, attach spm-cache-<ver>.tar.gz to each release (git archive / tar --owner=0 --group=0 + gh release upload) so the workflow hashes stable attached bytes instead of the loudly-warned auto-generated archive fallback.
result: pass

## Summary

total: 3
passed: 2
issues: 0
pending: 0
skipped: 1
blocked: 0

## Deferred Follow-Ups

- test: 1
  idea: "Prove update-tap commit+push live at the v0.4.0 release cut (also live-proves WR-01..03); confirm the run lands green end-to-end"
  deferred_at: 2026-08-31

### Addendum 2026-08-31 (post-deferral evidence)

Test 1's commit+push leg was live-proven the same day during Test 3 verification: run
33354678763 executed a REAL formula-changing edit, commit `ee27cc7`, and deploy-key push to
the unprotected tap main — update-tap job green throughout. The remaining deferral to v0.4.0
covers only the full-green observation (verify-publish green requires the post-intercept
tarball, i.e. the v0.4.0 release itself).

## Gaps
