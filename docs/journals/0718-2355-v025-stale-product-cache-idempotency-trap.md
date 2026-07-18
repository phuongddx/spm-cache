# v0.2.5 Release: Correct Code, Stale Cache — The Idempotency Trap

**Date**: 2026-07-18 23:55  
**Severity**: High  
**Component**: lib/spm_cache/installer.rb (enrich_lockfile_products)  
**Status**: Resolved  

## What Happened

Re-testing v0.2.4 in the real downstream project revealed that the `abcd` fabricated product—supposedly fixed in v0.2.3—still appeared in `spm-cache.lock`. The product should have been gone; the fix was correct; the code was committed and released. Yet the lockfile persisted the old, wrong data unchanged. Root cause: `enrich_lockfile_products` has an idempotency guard (`next if pkg_data["products"]`) that skips re-deriving product metadata for any package that already has a `products` array in the lockfile. This is a correct optimization to avoid redundant `swift package describe` calls. But it means a package whose `products` was written by a BUGGY older version of spm-cache keeps that wrong data forever—the v0.2.3 fix corrected the code path, but had no way to reach data already baked into an existing lockfile.

Fix: added `invalidate_stale_products!` with a version-aware self-healing mechanism. New field: `spm_cache_version` nested (deliberately not top-level) inside each project's existing lockfile hash, tracking the version that last wrote the project's data. On every run, if the stamp doesn't match `SPMCache::VERSION` or is absent, every package's `products[]` is cleared once so they re-derive fresh that run, then the project gets re-stamped. Self-heals not just this bug but any future correctness fix to the same enrichment code path. Nested-field design avoided breaking the Swift-side proxy tool's `Lockfile.load(from:)` parser (which treats every top-level JSON key as its own project; a new top-level key would have created a spurious empty "project").

4 tests added/updated in `spec/lockfile_enrichment_spec.rb` (one existing test premise—"idempotent means never re-describing"—was itself incomplete once version-awareness was introduced). Validated non-tautologically via revert-and-confirm: stashed the fix, confirmed test suite failed with stale product symptoms, restored fix, all passed. Full suite: 115 → 118 examples, 0 failures; Swift suite unaffected (9/9).

## The Brutal Truth

This is the punishing aspect of persisted state: a correct fix can be architecturally inert if the system has cached bad data from before the fix. The v0.2.3 fix was right; the v0.2.4 fix was right; but neither touched the stale `products[]` already written to disk. Real-world retest in the downstream project immediately exposed this, but no amount of unit tests for the "new code" path would have caught it—because the unit tests don't exercise "what if this package's lockfile entry pre-dates the fix?" That scenario required field-testing against an actual, pre-existing downstream lockfile.

The frustration isn't about the bug itself; it's about the category of bug. Wrong-derivation bugs (v0.2.3, v0.2.4) are visible in tests and code review. Stale-cache bugs are invisible until you retest production data. They're a different species entirely.

## Technical Details

**The idempotency guard (correct optimization, broken assumption):**
```ruby
def enrich_lockfile_products
  @lock["projects"].each do |proj_name, proj_data|
    proj_data["packages"].each do |pkg_name, pkg_data|
      next if pkg_data["products"]  # Skip if already cached
      # ... derive products via swift package describe ...
      pkg_data["products"] = derived_products
    end
  end
end
```

**The problem:** If a package's `products` was written by v0.2.2 (buggy, fabricates `abcd`), it stays in the lockfile forever. Every run skips re-deriving it. v0.2.3's fix prevents *new* bugs but can't heal old data.

**The fix:**
```ruby
def invalidate_stale_products!
  return if @lock.dig("projects", proj_name, "spm_cache_version") == SPMCache::VERSION

  # Version mismatch or missing: clear all products, let them re-derive
  @lock["projects"].each do |_, proj_data|
    proj_data["packages"].each do |_, pkg_data|
      pkg_data.delete("products")
    end
  end

  # Stamp the project so next run skips invalidation
  @lock["projects"][proj_name]["spm_cache_version"] = SPMCache::VERSION
end
```

**Why nested, not top-level:** The Swift proxy tool's `Lockfile.load(from:)` parser explicitly reads specific keys at the top level. A new top-level `spm_cache_version` would be silently ignored by Swift, but a new `{ "project": {} }` top-level key (even empty) would create a spurious project entry. Nesting inside the existing per-project hash is safe; Swift already ignores unknown nested keys.

**Test coverage added:**
Three updated/new specs in `spec/lockfile_enrichment_spec.rb`:
- "respects version stamp, skips invalidation when versions match"
- "invalidates stale products when version mismatches"
- "invalidates products when version field is absent (legacy lockfile)"

## What We Tried

**Investigation:** Re-ran `spm-cache install` on the real downstream project's `spm-cache.lock` (which was created under v0.2.2 before any of today's fixes). Ran against v0.2.4 code. Expected: fresh derivation, clean products. Actual: `spm-cache.lock` still contained the fabricated `abcd` product in the `eh_xcframework` entry. Read the actual lockfile JSON directly: confirmed `products` array present and unchanged, exactly as written by v0.2.2.

**Root cause confirmation:** Traced through `enrich_lockfile_products` logic. The guard `next if pkg_data["products"]` matched; re-derivation was skipped. Realized the fix in v0.2.3 was correct for the derivation code path but had no lever to fix stale data already in the lockfile.

**Solution design:** Version-aware invalidation. Chose nested `spm_cache_version` field (inside per-project hash, not top-level) to preserve Swift parser compatibility. Confirmed via code inspection that Swift's `Lockfile.load(from:)` uses explicit `dict["key"]` lookups, ignoring unknown nested keys.

**Validation:** Reverted only the v0.2.5 fix, re-ran specs—confirmed they failed (stale products persisted). Restored fix, all passed (118 examples, 0 failures). Spot-checked downstream project workflow: `spm-cache install` now correctly invalidates and re-derives products.

## Root Cause Analysis

**Why persisted state broke the fix:** Bug fixes are usually applied to code—next run uses fixed code. But if an earlier run cached bad state before the fix, the cache outlives the code that wrote it. The idempotency guard was designed to avoid re-doing expensive work; it's a correct optimization. But it encoded an implicit assumption: "if the data exists, it's correct." That assumption was fine until a bug in the data-writing code violated it. Once violated, the guard became a blocker preventing recovery.

**Why this wasn't caught by tests:** Existing specs exercise the "fresh lockfile" path (empty `projects`, all packages re-derive) and the "re-run on existing lockfile" path (data exists, guard skips re-derivation, correctness of derived data is assumed). None of them exercise "data exists AND the data is stale/incorrect from a prior version." That scenario required field-testing against a real lockfile with old, buggy data.

**Why field-testing caught it:** The downstream project's actual `spm-cache.lock` was created under v0.2.2 and persisted through v0.2.3 and v0.2.4 releases. Only when re-testing v0.2.4 against that real file did the stale data become visible. Unit tests cannot predict which prior version might have written bad state; only production data captures that history.

## Lessons Learned

1. **A correct code fix does not heal stale cached state.** Fixing the code path that writes data is necessary but not sufficient if earlier runs cached incorrect data. Systems with persistent state need invalidation triggers (version stamps, checksums, time-based expiry) to recover from pre-fix corruption. The idempotency guard was right; the missing piece was version-awareness.

2. **Persisted state creates a new species of bug.** Wrong-derivation bugs (incorrect logic) are caught by tests and code review. Stale-cache bugs (correct logic, old data) only surface in field-testing against production history. Both matter; both need different detection strategies.

3. **Test coverage of "re-run on existing data" is not the same as "re-run on stale data from an old version."** The existing specs passed; they exercise the re-run path. But they use synthetic data created *by the current version* of the code. To catch stale-data bugs, tests need to simulate old data or use real historical lockfiles. This is harder than typical regression testing.

4. **Field-testing after a fix release is not optional for fixes in cached/persisted systems.** Deploying a fix and moving on is enough for stateless systems. For systems that cache or persist state, field-testing the fix against real, pre-existing data (if possible) is the only way to confirm the fix actually heals the downstream impact.

## Next Steps

1. **Released.** v0.2.5 pushed, tagged, released via GitHub (release notes matching v0.2.3/v0.2.4 format), Homebrew tap update verified (`gh api` confirmed). Full release chain completed immediately, applying the v0.2.3 lesson for the third time today.

2. **Downstream verification.** epost-app project can now run `brew upgrade spm-cache` and the `eh_xcframework` lockfile will auto-heal: stale products invalidated on first run, fresh products derived, correct data written with v0.2.5 stamp.

3. **No further rework.** Test suite clean (118 examples, 0 failures). Nested version-field design required zero Swift-side changes. Next layer (CLI integration + real-world lockfile lifecycle) confirmed working via downstream project workflow.

---

**Related artifacts**:
- Commits: (v0.2.5 implementation)
- Tag: v0.2.5
- GitHub release: https://github.com/phuongddx/spm-cache/releases/tag/v0.2.5
- Tap workflow: `.github/workflows/update-tap.yml` (completed successfully)
- Implementation: `lib/spm_cache/installer.rb` (Installer#invalidate_stale_products!)
- Spec changes: `spec/lockfile_enrichment_spec.rb` (4 updated/new examples)

Status: DONE  
Summary: Fixed stale product cache in lockfile: v0.2.3 fix was correct but couldn't heal pre-existing buggy data due to idempotency guard. Added version-aware self-healing invalidation. Revealed a new bug class: persisted state prevents code fixes from reaching production. Field-testing on real downstream lockfile caught what unit tests missed. v0.2.5 released through full chain immediately.
