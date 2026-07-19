# v0.2.6 Release: Revision Precedence — The Downstream Drift That Breaks Late

**Date**: 2026-07-19 18:47  
**Severity**: Critical  
**Component**: tools/spm-cache-proxy/Sources/Core/Lockfile.swift (PackageRef.versionRequirement)  
**Status**: Resolved  

## What Happened

Downstream field-testing progressed past Firebase batch and hit "no scheme named FirebaseAnalytics" failures across every Xcode build scheme. Initial diagnosis pointed to Firebase integration; investigation revealed the error was a symptom, not the cause. The real failure: the entire dependency graph resolution was broken because swift-collections (pinned in Package.resolved at exactly commit 3d2dc41a / 1.1.2) was being resolved by spm-cache-proxy to version 1.6.0 (commit a0cb0954), whose manifest declared products not present in 1.1.2. When Xcode re-unified the graph back to 1.1.2 via constraints, it couldn't find those products, and every scheme failed to load.

Root cause: `PackageRef.versionRequirement` in the proxy's Lockfile.swift preferred open-ended lower-bound version pins (`from: "<version>"`) over the exact revision recorded in Package.resolved, even though both were available. The umbrella's isolated `swift package resolve` floated swift-collections from the locked 1.1.2 to the compatible 1.6.0; enrichment recorded the drifted manifest's products as ground truth; the proxy demanded them; the real Xcode graph (unified back at 1.1.2 by convergent constraints) failed with "product not found", killing every scheme.

Fix: flipped the precedence. Revision (exact commit hash) now wins whenever present in the lockfile; `from:` is fallback only for revision-less entries. Two-line change in PackageRef initialization. Both generated manifests (umbrella AND real proxy) now reproduce exactly what Package.resolved settled on, eliminating the drift.

## The Brutal Truth

This is the corrosive aspect of version vs. revision semantics: Package.resolved exists precisely to freeze a resolved graph to exact commits. Yet the code that *uses* the lockfile to generate proxies was silently ignoring the frozen commit and re-floating to a "compatible" newer version. The system's own ground truth was being overridden by a heuristic that seemed safer (broader compatibility) but actually broke it.

The downstream project's own tracking plan *already flagged this exact mechanism* as a reproducibility risk, 24 hours earlier, when a Realm conflict went away because the float happened to *fix* instead of break. Drift that helps today breaks tomorrow. That insight went on record, was never acted on, and the same mechanism immediately proved the warning right in a different package. It's the accumulated frustration of watching a known failure mode propagate because fixing it required one more pull on one more thread.

## Technical Details

**The precedence bug (version preferred, revision ignored):**
```swift
// Before: version takes precedence if both exist
var versionRequirement: VersionRequirement {
  if let versionStr = version {
    return .from(Version(versionStr)!)  // Preferred
  }
  if let revStr = revision {
    return .revision(revStr)  // Fallback
  }
  return .branch("main")
}
```

**The symptom chain (what manifested at the user level):**
1. Umbrella `swift package resolve` with `from: "1.1.2"` floats swift-collections to 1.6.0 (newer, compatible).
2. Product enrichment reads 1.6.0's manifest, records `TrailingElementsModule` as a valid product (doesn't exist in 1.1.2).
3. Proxy generates manifest declaring `TrailingElementsModule` product.
4. Real Xcode graph, constrained by other dependencies, resolves swift-collections back to exactly 1.1.2.
5. Xcode fails: "product 'TrailingElementsModule' ... not found at version 1.1.2", killing scheme resolution globally.
6. User sees Firebase-unrelated "no scheme named FirebaseAnalytics" because every scheme load fails.

**The fix (revision takes precedence):**
```swift
// After: revision takes precedence if both exist
var versionRequirement: VersionRequirement {
  if let revStr = revision {
    return .revision(revStr)  // Exact commit wins
  }
  if let versionStr = version {
    return .from(Version(versionStr)!)  // Fallback only
  }
  return .branch("main")
}
```

**Swift-collections drift verified empirically:**
Real checkout at both revisions confirmed:
- 1.1.2 (commit 3d2dc41a): `TrailingElementsModule` product absent.
- 1.6.0 (commit a0cb0954): `TrailingElementsModule` product present.
- `git describe --tags` on the actual spm-cache checkout: 1.6.0 (drift).
- Package.resolved exact entry: revision 3d2dc41a, version 1.1.2 (correct constraint).

## What We Tried

**Diagnosis:** User reported scheme load failure. Initial instinct: Firebase configuration. Ran xcodebuild -list directly instead of trusting per-target error; saw the real error: "product not found". Traced backwards through proxy generation, then through enrichment, to the version mismatch.

**Investigation:** Compared two fixture package graphs:
1. With revision pins at every topology layer (root → path → path → revision).
2. Without revision pins, relying on version constraints alone.

Both revealed: when a lockfile specifies revision, SwiftPM honors it as an exact override; a version range like `from: "1.1.2"` is subordinate and silent—it doesn't error when the revision says "use 1.1.2" but something else resolved it to 1.6.0, because the revision is authoritative. The proxy must respect that same authority.

**Test coverage:** Rewrote existing test `"version takes precedence over revision when both are set"` to assert the corrected behavior: `"revision takes precedence over version when both are present"`. Added new fixture test exercising the real topology: both-fields entry through actual package binaries, verified it fails against pre-fix binary (demands non-existent product), passes with fix.

## Root Cause Analysis

**Why version preferred revision:** The code assumed version was more readable/user-friendly and revision was fallback. That's correct for *inputs* (users write `from:` more often). But for lockfile entries—which are outputs of `swift package resolve` that *already* captured exact resolved commits—the input semantics were backwards. The lockfile wasn't a user constraint; it was a record of what was already resolved. Revision is the source of truth; version is just annotation.

**Why this drift stayed hidden:** Isolated `swift package resolve` in the umbrella environment will successfully resolve to compatible newer versions if no explicit revision pin exists. If the proxy then uses the drifted version to compute products, it records a fact that's true *in that isolated environment* but false in the *real unified graph* where other constraints pull back to the original revision. The proxy's manifest then makes a claim that fails when actually used.

**Why field-testing surfaced this:** Unit tests of the proxy would exercise both-fields entries, but with synthetic data where version and revision are *consistent* (not drifted). Only the real downstream lockfile, pre-existing, with Package.resolved locking it to 1.1.2 while the umbrella floated to 1.6.0, exposed the inconsistency. The data had to be real and pre-existing to show the failure mode.

## Lessons Learned

1. **Lockfile revision is authoritative; version is secondary.** When both are present, the revision is a historical record of what Package.resolved actually locked. Version is metadata. The proxy must treat them that way.

2. **A drift that helps you today will hurt you tomorrow.** The tracking plan flagged the Realm float-on-version as "a reproducibility risk" without acting on it because the float *fixed* that failure. Same mechanism, different package, same session, reversed outcome. Systems that drift should be forced to fail loudly or fixed explicitly—not left to chance.

3. **Symptom != cause, and the user's diagnostic instinct is worth listening to.** Reported error: "no scheme named FirebaseAnalytics". Real cause: version mismatch in a transitive dependency. The user's decision to bypass trust and run the command directly (xcodebuild -list) surfaced the real error. When the system's error message doesn't match the feature being tested, dig deeper.

4. **Empirical validation with real fixture graphs is non-negotiable for version/revision semantics.** The fix was a two-line reversal, but correctness required building actual multi-layer package topologies, confirming SwiftPM's behavior at each layer, and verifying the proxy aligns with it. Assumptions about "what a lockfile means" needed source code confirmation.

## Next Steps

1. **Released v0.2.6:** Pushed, tagged, GitHub release created, Homebrew tap update workflow verified completed. Release notes applied the template from v0.2.5 (consistent messaging for third release in campaign). Formula at v0.2.6 confirmed via brew.

2. **Test suite:** Ruby 136/136 (baseline 135 + unrelated WIP diff-detector specs), Swift 9/9. Both-fields fixture regression test now in suite, will catch future revision-ignoring bugs.

3. **Downstream validation:** epost-app can now pull v0.2.6; swift-collections will resolve to exact 1.1.2, products will match, every scheme will load. Firebase batch testing can proceed.

4. **Process note:** Tree contained uncommitted WIP (separate diff-detector feature, not related to this fix). Staged only the 9 fixed files via explicit pathspec; WIP remains uncommitted. Prevents polluting the fix commit with unrelated work.

---

**Related artifacts:**
- Commits: (v0.2.6 implementation)
- Tag: v0.2.6
- GitHub release: https://github.com/phuongddx/spm-cache/releases/tag/v0.2.6
- Tap workflow: `.github/workflows/update-tap.yml` (completed successfully)
- Implementation: `tools/spm-cache-proxy/Sources/Core/Lockfile.swift` (PackageRef.versionRequirement)
- Test fixture: `Tests/spm-cache-proxyTests/LockfileTests.swift` (both-fields regression)
- Tracking plan reference: 0716-2300-v013-release-and-three-field-bug-plan.md

Status: DONE  
Summary: Fixed version/revision precedence in proxy lockfile generation. Real cause: PackageRef preferred open-ended version float over exact revision lock, causing drifted manifests that failed when graph re-unified at original constraint. Flipped precedence: revision now wins. User's diagnostic insight (bypass reported error, check real failure) surfaced the root cause. v0.2.6 released same-session through full chain. Fourth fix in downstream campaign; fourth verification that field-testing on real data catches what unit tests miss.
