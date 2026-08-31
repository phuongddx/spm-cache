---
phase: 08-drift-read-back-fidelity-status-provenance
measured: 2026-08-29
measurement: M2
status: complete
---

# Phase 8 — M2 Measurement: Resolution-Incompatible Package Count

**Measured:** 2026-08-29
**Reference project:** `/Users/ddphuong/Projects/next-labs/stress-ai/ios-stress-app/StressMonitor`
**Host graph:** canonical `StressMonitor.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`, 17 pins (all Firebase/Google SDK family)

**Blocking gate (ROADMAP.md Phase 8):** "the `resolution-incompatible` count from Phase 7's report-only run gates the policy commitment locked here. Confirm the count before committing; rescope if it is large." M2 was never executed during Phase 7 (confirmed by Phase 7's re-planning research pass and the goal-backward verifier) — this measurement closes that gap before Phase 8 planning begins.

## Method

Phase 7's `resolution-incompatible` concept (ROADMAP success criterion 2: "a package whose declared requirements genuinely cannot satisfy the host graph") means: does any host-pinned package's own `Package.swift` dependency declaration exclude the host's pinned version of another host-pinned package?

Rather than a live `swift package resolve`/build sweep (expensive, and the actual `resolution-incompatible` detection/status machinery is Phase 8's own deliverable — not yet built), this measurement performs **static manifest analysis**, reusing checkouts Xcode itself already produced for the reference project (`DerivedData/StressMonitor-*/SourcePackages/checkouts/`, 17 directories matching the 17 host pins exactly — no fresh clone needed):

1. Parse the host's canonical `Package.resolved` into `{identity: pinned_version}`.
2. For each of the 17 checked-out packages, run `swift package dump-package` (offline, reads the manifest only) and extract its `dependencies[].sourceControl[]` entries.
3. For each declared dependency whose `identity` is itself one of the 17 host-pinned packages, check whether the host's pinned version satisfies the declared requirement (`range`, `exact`, `revision`, or `branch`).
4. Count packages with at least one unsatisfied requirement against another host-pinned package.

This does not need network access or an SDK build; it is genuinely report-only. It is scoped to edges *between* host-pinned packages — a host-pinned package's own test-only dependencies (`ocmock`, `gcdwebserver`, both pinned to exact revisions) are correctly out of scope since they are not part of the app's resolved/cached graph.

Script: ad hoc, not committed to the repo (single-use measurement, mirrors M1's non-committed reproduction scripts).

## Result

**0 of 17 packages report resolution-incompatible.**

| Package | Dependencies checked against host pins | Result |
|---|---|---|
| AppAuth-iOS | (leaf — no host-pinned deps) | OK |
| GTMAppAuth | appauth-ios | OK |
| GoogleAppMeasurement | (checked as a dependent by others) | OK |
| GoogleDataTransport | (leaf) | OK |
| GoogleSignIn-iOS | appauth-ios, app-check, gtmappauth, gtm-session-fetcher, googleutilities | OK |
| GoogleUtilities | (leaf) | OK |
| abseil-cpp-binary | (leaf) | OK |
| app-check | (leaf) | OK |
| firebase-ios-sdk | promises, swift-protobuf, googleappmeasurement, googledatatransport, googleutilities, gtm-session-fetcher, nanopb, abseil-cpp-binary, grpc-binary, leveldb, interop-ios-for-google-sdks, app-check | OK |
| google-ads-on-device-conversion-ios-sdk | (leaf) | OK |
| grpc-binary | (leaf) | OK |
| gtm-session-fetcher | (leaf) | OK |
| interop-ios-for-google-sdks | (leaf) | OK |
| leveldb | (leaf) | OK |
| nanopb | (leaf) | OK |
| promises | (leaf) | OK |
| swift-protobuf | (leaf) | OK |

Spot-checked `firebase-ios-sdk` (the largest dependent, 14 declared dependencies) by hand against the script's output — every range/exact requirement is satisfied by the corresponding host pin (e.g. `googleappmeasurement` pinned `exact: 11.15.0` vs host `11.15.0`; `abseil-cpp-binary` range `[1.2024072200.0, 1.2024072300.0)` vs host `1.2024072200.0`, exactly at the lower bound). No `branch` dependencies exist anywhere in this graph.

## Interpretation

**Not a rescope trigger.** The count is 0, not "large" — ROADMAP's ordering ("Confirm the count before committing; rescope if it is large") resolves to "proceed as scoped." This is consistent with the wider Firebase/Google SDK family's practice of shipping tightly co-versioned releases (each SDK's own dependency ranges are kept wide enough to accommodate sibling releases from the same train), and with M1's independent finding that isolated per-package upward re-resolution was observed **zero times** in the field on this same reference project — both measurements point the same direction: this reference project's dependency graph is unusually well-behaved, not adversarial.

**Caveat — single reference project.** This is the one real-world project available for measurement in this milestone (same one M1/M3 used). A different, less disciplined dependency graph (mixed-vendor packages with narrower or conflicting version ranges) could plausibly produce a nonzero count. Phase 8's `resolution-incompatible` status and source-fallback path (success criterion 2) still need to exist and work correctly for that case — this measurement says the *policy design* doesn't need to be reshaped around a high-incompatibility-rate assumption, not that the feature itself is unnecessary.

## Consumed by

Phase 8 planning proceeds against the ROADMAP's current scope (FID-03, FID-04, CACHE-01, DIAG-02) without a rescope. No policy redesign triggered.
