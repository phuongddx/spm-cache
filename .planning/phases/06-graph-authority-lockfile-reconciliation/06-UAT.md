---
status: partial
phase: 06-graph-authority-lockfile-reconciliation
source: [06-01-SUMMARY.md, 06-02-SUMMARY.md, 06-03-SUMMARY.md, 06-04-SUMMARY.md, 06-05-SUMMARY.md]
started: 2026-08-27T14:54:25Z
updated: 2026-08-27T22:58:00Z
---

## Current Test

[testing paused by explicit user override -- 2 items outstanding, not re-diagnosed as gaps]

## Tests

### 1. doctor names lock/graph drift without a build
expected: On a project whose spm-cache.lock disagrees with the host Package.resolved (by
  package set or by version/revision), `spm-cache doctor` reports the lock_graph_fidelity
  check as a warning naming the drifted packages -- with no Xcode build, resolve, or shell-out.
result: pass

### 2. A non-fast-path run reconciles the lock to the canonical graph
expected: Running spm-cache on a project whose Package.resolved changed (including the case
  where a stale duplicate resolved file exists elsewhere in the project) drops packages no
  longer in the host graph, adds new ones, and leaves DiffDetector reporting an empty diff --
  on the FIRST run, and on every project shape (not just the common one).
result: skipped
reason: "User explicitly chose to override remaining UAT and proceed to autonomous 6-11.
  Independently verified pre-override by the orchestrator (grep counts on 06-05's gate
  greps, field replay against the reference project's real inputs); not re-confirmed by the
  user's own words on this test."

### 3. End-to-end use/build against the reference project
expected: Running `spm-cache use` (and a subsequent build) on
  /Users/ddphuong/Projects/next-labs/stress-ai/ios-stress-app/StressMonitor resolves against
  the canonical 17-pin graph, the lock ends up holding those 17 packages (not the old 8), and
  the project still builds -- this is the one criterion (ROADMAP criterion 2) that needs a
  real toolchain run against a real project rather than a hermetic spec.
result: skipped
reason: "User explicitly chose to override remaining UAT and proceed to autonomous 6-11.
  Genuinely unverified -- needs a real Xcode toolchain run the user has not yet performed."

## Summary

total: 3
passed: 1
issues: 0
pending: 0
skipped: 2

## Gaps

[none yet]
