---
status: testing
phase: 09-cache-identity-invalidation
source: [09-VERIFICATION.md]
started: 2026-08-29T13:41:00Z
updated: 2026-08-29T13:41:00Z
---

## Current Test

number: 1
name: SC5 -- DerivedData staleness on in-place xcframework rebuild
expected: |
  The app's rebuilt binary reflects the NEW xcframework's content (marker changes) -- Xcode's
  incremental build noticed the in-place content change on its own, with no manual DerivedData
  clear required.
awaiting: user response

## Tests

### 1. SC5 -- DerivedData staleness on in-place xcframework rebuild
expected: The app's rebuilt binary reflects the NEW xcframework's content (marker changes) --
  Xcode's incremental build noticed the in-place content change on its own, with no manual
  DerivedData clear required. Follow the reproduction procedure recorded in
  09-SC5-VERIFICATION.md against the real reference project
  (/Users/ddphuong/Projects/next-labs/stress-ai/ios-stress-app/StressMonitor): cold-build, mark
  one cached package's linked framework content in DerivedData, force a pin-disagreement miss +
  rebuild that one package, rebuild the app WITHOUT clearing DerivedData, re-check the marker.
result: [pending]

## Summary

total: 1
passed: 0
issues: 0
pending: 1
skipped: 0
blocked: 0

## Gaps
