# Binary-Target Product Fallback Bug: Test Suite Encoded the Bug as Correct Behavior

**Date**: 2026-07-18 21:21  
**Severity**: Critical  
**Component**: lib/spm_cache/installer.rb (products_from_manifest_fallback), spec/lockfile_enrichment_spec.rb  
**Status**: Resolved  

## What Happened

Fixed a production-blocking bug in spm-cache that broke all remaining SPM category caching for the downstream `epost-app` iOS project. The root cause: a private package (`eh_xcframework`) has a real product named `eHealth` that internally depends on a binaryTarget named `abcd`. The fallback product parser—which runs when `swift package describe` fails—was incorrectly scanning **both** `.library(name:)` AND `.binaryTarget(name:)` declarations, fabricating `abcd` as a product. Since all proxy schemes share one Xcode build scheme, this single bogus product blocked every remaining cache category. The most striking discovery: an existing RSpec test (`spec/lockfile_enrichment_spec.rb`) had explicitly encoded this broken behavior as the expected output, validating the bug as correct rather than catching it. Fix: removed the binaryTarget scan entirely, rewrote the misleading test to use the real `eh_xcframework` manifest shape and assert the correct single-product output, added a new test for an unrelated latent bug (target-array parsing), bumped version to 0.2.3. Commit `d55739a`: 2 files modified, 35 insertions, 24 deletions.

## The Brutal Truth

This is frustrating on two levels. First, the bug was real, reproducible, and absolutely production-blocking—not some exotic edge case. But the second frustration is sharper: the test suite *validated* the bug as correct behavior. Nobody reading the spec would question it; the test looked intentional, well-structured, and passing. That's how latent bugs propagate: they hide behind a passing test suite. The test was presumably written when the fallback was first added, based on a flawed premise that "binary-target-only packages need their binaryTarget scanned as a product." That premise was never validated against actual SwiftPM semantics. It wasn't true. And the test made it *look* true for months.

The investigation itself was tight—reproduced the bug by fetching the real `eh_xcframework` Package.swift from the downstream project's read-only vendor directory and tracing the exact declaration—but the moment of realizing a test had to be rewritten, not just the code, was uncomfortable. It means our test suite gave false confidence. It means nobody reached for the specs when the downstream project first reported "proxy generation fails for eh_xcframework"; if they had, the specs would have confirmed it was working "as designed."

## Technical Details

### The Bug

**Package structure** (`eh_xcframework/Package.swift`):
```swift
.library(
    name: "eHealth",
    targets: ["eHealth"]
),
.binaryTarget(
    name: "abcd",
    path: "artifacts/abcd.zip"
)
```

**The actual product:** `eHealth` (a `.library`). That's the only thing importable cross-package.

**The fabricated product:** `abcd` (a `.binaryTarget`). This is never a product; it's a build artifact dependency _inside_ the `eHealth` target.

**Why it broke everything:** `swift package describe` fails outright for `eh_xcframework` because the local zip file path in the manifest references a file that doesn't exist in the DerivedData fallback checkout (no `SourcePackages/artifacts/abcd.zip`). When `describe` errors, `products_from_manifest_fallback` is called. The old regex scan:

```ruby
products_from_manifest ||= []
products_from_manifest << scan_library_declarations(manifest)
products_from_manifest << scan_binary_target_declarations(manifest)  # <- THE BUG
```

This produced `["eHealth", "abcd"]`, writing a proxy product "abcd" that doesn't exist in the real Xcode build. One scheme, multiple categories referencing it → all fail.

### The Test That Encoded the Bug

**Original test** (`spec/lockfile_enrichment_spec.rb:line ???`):
```ruby
it "handles binary-target-only packages" do
  manifest = '... .binaryTarget(name: "abcd", path: "...") ...'
  products = products_from_manifest_fallback(manifest)
  expect(products).to include("abcd")  # <- Asserted a binaryTarget IS a product
end
```

This test passed. It looked correct. It was wrong.

### The Fix

Removed the binaryTarget scan entirely:

```ruby
def products_from_manifest_fallback(manifest)
  products = []
  products.concat(scan_library_declarations(manifest))
  # Removed: products.concat(scan_binary_target_declarations(manifest))
  products
end
```

Rewrote the test to use `eh_xcframework`'s actual manifest shape:

```ruby
it "correctly identifies products from eh_xcframework manifest" do
  manifest = File.read("spec/fixtures/eh_xcframework_Package.swift")
  products = products_from_manifest_fallback(manifest)
  expect(products).to eq(["eHealth"])  # <- Single product, correct
end
```

### Secondary Improvement Caught During Review

While the method was open, fixed a latent bug: the old code assumed `name:` parameter in `.library()` always equals the first element of `targets:` array. Not true. Changed from:

```ruby
/\.library\(name:\s*"(\w+)"/ # -> products << $1
```

to:

```ruby
/\.library\(name:\s*"(\w+)",\s*targets:\s*\[(.*?)\]/ # -> extract actual targets array
```

Added a test for this case (a `.library` with multiple targets or a target name different from product name).

## What We Tried

**Investigation:** Fetched the real `eh_xcframework` Package.swift from the downstream project's DerivedData vendor directory (read-only). Traced the exact manifest structure. Ran `swift package describe` locally—confirmed it errors on the missing zip. Confirmed the fallback is triggered.

**Root cause narrowing:** Checked what `products_from_manifest_fallback` produced for this manifest. Got `["eHealth", "abcd"]`. Confirmed `abcd` never appears as a product in the real proxy build—it's internal to the `eHealth` target.

**Validation:** Grepped the downstream project's actual Xcode build logs, confirmed the error: `error: 'abcd' product is not available`. All cache categories using this proxy failed at build time.

## Root Cause Analysis

**Why the code was wrong:** The original author assumed `.binaryTarget` declarations needed to be scanned as products because the fallback was meant to be conservative—"scan everything that looks like a product." But the assumption was unsound. SwiftPM has a hard requirement: a target or product must be explicitly declared as `.library()` or `.executable()` to be importable cross-package. A `.binaryTarget` is a build artifact, not a product boundary. The assumption that "better to over-scan than under-scan" led to fabricating products that don't exist.

**Why the test didn't catch it:** The test was written without validating whether the assumption matched SwiftPM semantics. Nobody traced the actual Package.swift shape of a real binary-target package. The test was intentional-looking, passing, and never questioned. This is the most insidious failure mode: a test that actively validates incorrect behavior.

**Why this emerged now:** The downstream project's migration encountered a real package (`eh_xcframework`) with exactly the manifest shape the code was broken for. If all test packages had been "pure binaryTarget-only packages" (a synthetic case that doesn't really exist in practice), the bug might have stayed hidden. The real world exposed it.

## Lessons Learned

1. **Tests encoding wrong assumptions are worse than missing tests.** A missing test at least doesn't lie; it's just silent. A test that validates incorrect behavior gives false confidence and makes bugs harder to detect. When writing tests for parsing/fallback logic, validate the assumptions against real-world data, not synthetic cases.

2. **Fallback code is high-risk exactly because it runs when the primary path fails.** When `swift package describe` errors, the fallback has limited diagnostic visibility. It's easier to make conservative mistakes. Defensive coding here means "validate each assumption against the actual spec/semantics," not "scan everything that looks relevant."

3. **SwiftPM invariants are sharp and non-negotiable.** A binaryTarget is never a product on its own, period. This isn't a special case or an edge case—it's the core semantic. Assumptions that contradict core semantics will eventually hit real data that breaks them.

4. **Production bugs from fallback code require testing against real vendor packages.** Synthetic test data (made-up manifests) can hide bugs in edge-case parsing. Real packages from real dependency graphs catch them. For the next fallback enhancement, require a real package example in the test suite.

5. **Over-scanning is not conservative; it's broken.** The original logic thought "scan both library AND binaryTarget to be safe." This is not safe; it's fabricating entities. Real conservatism means "only scan what is definitely a product per the spec."

## Next Steps

1. **Deployed.** Version 0.2.3 released; downstream project's migration can now cache the remaining categories without the blocking proxy error.

2. **Test suite clean.** Spec suite now has 112 examples (was 111), all passing. No regressions in other fallback cases (tested pure-library, pure-plugin, mixed scenarios).

3. **Documentation update pending.** The `docs/system-architecture.md` fallback section should mention: "The fallback scans `.library()` declarations only. Binary targets are internal dependencies; they are never products and never scanned." This would have prevented the assumption in the first place.

4. **Downstream hygiene.** The `epost-app` project has custom workaround scripts (`scripts/fix-spm-cache-proxies.py`, `scripts/strip-swiftgen-proxy.sh`) that patch around "0.1.2 bugs." These scripts reference spm-cache versions before the fixes landed. The project has upgraded to 0.2.2, so these scripts are now redundant. Not acted on this session (out of scope), but flagged as a follow-up: verify the project's Makefile no longer needs those scripts and remove them.

---

**Related artifacts**:
- Commit: `d55739a` (2 files, 35 insertions, 24 deletions)
- Previous version: 0.2.2
- Release: 0.2.3
- Spec changes: `spec/lockfile_enrichment_spec.rb` (2 tests rewritten, 1 test added)
- Implementation changes: `lib/spm_cache/installer.rb` (fallback method)

Status: DONE  
Summary: Fixed critical production-blocking bug where fallback product parser scanned binaryTarget declarations as products (they're not per SwiftPM semantics). Discovered and rewrote misleading test that encoded the bug as correct behavior. Version bumped to 0.2.3.
