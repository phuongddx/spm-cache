---
status: testing
phase: 07-host-faithful-checkout-seeding
source: [07-01-SUMMARY.md, 07-02-SUMMARY.md]
started: 2026-08-29T13:15:00Z
updated: 2026-08-29T13:15:00Z
audit_acknowledged:
  milestone: v0.4.0
  at: 2026-08-31
  gap_snapshot: "testing::scenarios=1"
---

## Current Test

<!-- OVERWRITE each test - shows where we are -->

number: 7
name: PERF-01 benchmark holds — no wall-clock or disk regression
expected: |
  Cached-build wall-clock and disk usage on the reference project show no regression
  versus the pre-seeding baseline, or the regression is surfaced as a blocking finding
  rather than shipped silently.
awaiting: user response

## Tests

### 1. Host graph seeded verbatim before first describe call

expected: A package built by spm-cache checks out the same transitive versions the host app resolved (host graph seeded verbatim before the first swift package describe call)
result: pass
source: automated
coverage_id: D1

### 2. Vendored-.xcodeproj packages reported not-graph-pinned

expected: Vendored-.xcodeproj packages are reported as an explicit not-graph-pinned category, never silently folded into pinned
result: pass
source: automated
coverage_id: D2

### 3. Aborted/failed/interrupted build leaves no synthetic Package.resolved behind

expected: An aborted, failed, or interrupted build leaves no checkout carrying a synthetic Package.resolved it did not have before
result: pass
source: automated
coverage_id: D3

### 4. No host graph available -> byte-for-byte v0.3.0 behavior

expected: With no host graph available anywhere, behavior is byte-for-byte identical to v0.3.0
result: pass
source: automated
coverage_id: D4

### 5. Shared clone directory across all xcodebuild invocations

expected: Every xcodebuild invocation shares one spm-cache-owned clone directory instead of each of N package builds cloning the whole host graph independently
result: pass
source: automated
coverage_id: D1

### 6. Watch cannot delete checkouts mid-build

expected: A concurrent watch cycle cannot delete checkouts out from under an in-flight spm-cache build -- it waits instead
result: pass
source: automated
coverage_id: D2

### 7. PERF-01 benchmark holds — no wall-clock or disk regression

expected: Cached-build wall-clock and disk usage on the reference project show no regression versus the pre-seeding baseline, or the regression is surfaced as a blocking finding rather than shipped silently.
result: [pending]

## Summary

total: 7
passed: 6
issues: 0
pending: 1
skipped: 0
blocked: 0

## Gaps

[none yet]
