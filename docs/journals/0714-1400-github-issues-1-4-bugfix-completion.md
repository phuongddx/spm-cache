# GitHub Issues #1-#4 Bugfix Completion: Four Parallel Fixes + One Phantom Test Suite

**Date**: 2026-07-14 14:00
**Severity**: High (issues #2-#4 block real builds; #1 prevents user config from ever applying)
**Component**: spm-cache core (installer.rb, build.rb, build_pipeline.rb, swift proxy tool)
**Status**: Resolved / Uncommitted (awaiting user commit decision)

## What Happened

Four independent GitHub issues were triaged (commit 1952b3c), all verified as real regressions, and fixed in parallel using isolated git worktrees with disjoint file ownership. All tests passed. Upon code review, a critical phantom-passing test suite bug was discovered, fixed, and re-verified against real data before closing.

**Issues fixed**:
- **#1**: spm-cache.yml config file was parsed but never loaded during build/use commands
- **#2**: revision-only package pins in Swift proxy tool silently dropped the `revision` field
- **#3**: no fallback when `swift package resolve` failed, skipping entire targets
- **4**: Xcode scheme selection heuristic was broken (~47 of 62 targets picked wrong scheme)

## The Brutal Truth

We shipped tests that were passing but worthless. Issue #4's test suite was green with stubs that did not match reality. The stubs had `Product#type` as a bare string (`"library"`) when real `swift package describe --type json` emits it as a Hash (`{"library"=>["automatic"]}`). The code comparing `p.type == "library"` was therefore always false, making the entire scheme-resolution fix a silent no-op that fell through to the broken old heuristic.

**The worst part**: tests passed. The CI would not have caught this. Only an independent code reviewer running real `swift package describe` against real local packages found it. This is a painful example of why "test coverage is passing" does not mean "the fix works."

## Technical Details

### Issue #1: Config Never Loaded
**File**: `lib/spm_cache/installer.rb`
**Root cause**: `ensure_config_file` parsed the YAML but forgot to call `@config.load(config_path)`.
**Fix**: One line added. Trivial once identified.
**Impact**: User's `ignore_build_errors`, `ignore`, `default_sdk` settings were silently ignored every time the command ran.

### Issue #2: PackageRef Silently Drops `revision`
**File**: `tools/spm-cache-proxy/Sources/PackageRef.swift`
**Root cause**: JSON deserialization mapped `revision` field correctly, but `versionRequirement` computed property emitted bare string (`"<hash>"` not `revision: "<hash>"`).
**Evidence**: `lib/spm_cache/core/lockfile.rb` (Ruby side) round-tripped revision fine; the bug was isolated to the Swift proxy's output.
**Fix**: Added explicit `.revision(hash)` case to `versionRequirement`, with proper labeling.
**Bonus**: Added the repo's **first Swift Testing target** (`tools/spm-cache-proxy/Tests/`). Four test cases, all passing. This is the right tool for this job (fast `swift test`, no simulator, pure branch logic on a `Codable` struct).

### Issue #3: No Fallback, All Targets Skipped
**File**: `lib/spm_cache/installer/build.rb`
**Root cause**: If `swift package resolve` failed (often because of issue #2), entire build was skipped with no recovery.
**Fix**: Added `fallback_xcode_checkouts` method that searches DerivedData when umbrella resolve fails.
**Critical bug found during implementation**: When glob-matching DerivedData dirs with pattern `#{project_name}-*`, two stale candidate dirs existed on the real dev machine (from old checkouts). The original suggested code (`Dir.glob(...).first`) does not guarantee the newest. 
**Real fix applied**: Sort matches by `File.mtime` and use `max_by(:mtime)`. Verified correct against `luz_epost_ios` project on developer machine.
**Warning escalation**: If neither umbrella resolve nor DerivedData fallback succeeds, now emits explicit warning (not silent skip).

### Issue #4: Scheme Selection Heuristic Completely Broken + PHANTOM TEST SUITE BUG

**Files**: `lib/spm_cache/spm/build_pipeline.rb`, `lib/spm_cache/spm/desc/desc.rb`

**Root cause of scheme bug**: The code tried to select the "right" Xcode scheme by string heuristics (substring matching) instead of asking SPM for the authoritative product type.

**Planned fix**: Use existing `swift package describe --type json` data (already in the codebase, already used in `lib/spm_cache/spm/pkg/base.rb`) to resolve product type (library vs executable) and exact SPM scheme names.

**Implementation**: Added `resolve_scheme` method wiring up `Desc::Product#type` checks before falling back to xcodebuild heuristic.

---

### THE PHANTOM-PASSING TEST BUG (CRITICAL)

**Discovery point**: First code-review pass of #4 implementation.

**The bug**: 
```ruby
# What the test stubbed:
{
  "type" => "library"  # ← bare string
}

# What real swift package describe emits:
{
  "type" => {"library" => ["automatic"]}  # ← Hash with product name as key
}
```

**Impact**: 
- `Product#type` method returned `raw["type"]` verbatim
- Code path checked `p.type == "library"` → always false on real data
- Scheme resolution fell through to old broken `schemes.first` heuristic
- **Entire fix silently didn't work**
- Tests passed because they never saw real data

**Why tests passed**:
- `spec/build_pipeline_spec.rb` stubbed responses with unrealistic bare-string shape
- The stubbed shape made the code path work (fake data → correct result)
- Real data would have failed (correct branch → no-op → fallback to broken heuristic)
- CI never caught it because we test against stubs, not real packages

**Fix applied**:
1. Normalized `Product#type` to handle both shapes: `t.is_a?(Hash) ? t.keys.first : t`
2. Added direct regression spec (`spec/desc_product_spec.rb`) with three test cases proving the real Hash shape
3. Updated `spec/build_pipeline_spec.rb` stubs to realistic Hash shape
4. Tightened substring-fallback tie-break (`find` → `select.min_by(length delta)`) per Medium-priority review note
5. **Second independent code-review pass**: ran real `swift package describe` against 3 local SwiftPM packages, manually verified scheme resolution correct, confirmed no regressions

## What We Tried

1. **Initial parallel implementation**: All 4 phases in isolated worktrees (no merge conflicts, disjoint files)
2. **First test run**: `bundle exec rspec` → 58 examples, 0 failures ✓
3. **First code review**: Caught the `Product#type` shape mismatch and phantom-pass bug
4. **Fix + spec**: Normalize the type handling, add regression test with real shape
5. **Second code review**: Independent verification against real `swift package describe` output
6. **Final state**: All 4 issues closed, test suite green, fixes verified against real packages

## Root Cause Analysis

### Issue #1
Simple oversight in the initial implementation of `ensure_config_file`. The method existed, did its job, but missed the final load step.

### Issue #2
The Swift Codable initialization worked, but the computed property that emits the version requirement didn't have an explicit case for the revision field. The field was read but never used.

### Issue #3
The umbrella resolve was treated as binary (all-or-nothing). When external failures happened (like issue #2), no recovery path existed. The DerivedData fallback was in the issue report but not implemented.

### Issue #4 + Phantom Test Bug
Two separate root causes:

**The scheme bug itself**: The repo chose string heuristics instead of using the authoritative `swift package describe` data it already had. Classic case of not using existing infrastructure.

**The phantom test bug**: We stubbed test data with a simplified shape instead of capturing the real JSON structure from `swift package describe`. When the test passed, we assumed the implementation was correct, but only because the stub was unrealistic. The test passed the stub but would fail on real data.

**Why this is brutal**: The gap between "test passes" and "code actually works" was hidden. We didn't discover it by looking at test coverage or code path analysis. We found it by a reviewer independently running the real command and comparing. This is a humbling reminder that **stubs can hide failures**.

## Lessons Learned

1. **Always compare stubs against real data, not the other way around.** If you're testing against stubs of external tools (like `swift package describe`), periodically run the real tool and check that your stubs match. Otherwise you're testing an implementation that works in a fantasy world.

2. **Passing tests do not mean the implementation works.** "Green test suite" should trigger skepticism if the test data came from stubs. Pair test-driven verification with real-world spot checks, especially for integration points with external tools.

3. **Use existing infrastructure before inventing heuristics.** Issue #4's string-matching heuristic was fragile (false positives on package names like `FSPagerView` vs `fspagerview`). The codebase already had `swift package describe` plumbed in elsewhere; reusing it would have been clearer and more reliable.

4. **DerivedData state is not guaranteed clean.** The assumption that the first glob match is the "right" one is wrong. Sort by mtime or be explicit about which old state you're ok with. A real dev machine had two stale dirs; CI environments may be cleaner but never assume it.

5. **Small, focused phases with disjoint ownership integrate cleanly.** All 4 phases touched separate files (installer.rb, build.rb, build_pipeline.rb, swift proxy) with no merge conflicts. This is how parallel work should look.

6. **Second-pair code review of schema-dependent code is non-negotiable.** The `Product#type` shape mismatch was invisible in the test suite but obvious the moment someone ran the real command. For any code that parses JSON from external tools, code review should include a real example or the stubs should be auto-generated from real outputs.

## Next Steps

1. **User decision**: Decide whether to commit these changes. All test suites are green, all fixes verified against real data.
2. **Optional follow-up**: Address the pre-existing `Gemfile.lock` drift (`spm-cache 0.1.0` locked vs `VERSION` file `0.1.1`). This is a separate one-line `bundle lock` fix, not part of these issues.
3. **Consider adding real-output-capture to Swift proxy tests**: The Swift Testing target in phase 2 could grow a smoke test that runs `swift test` and compares against real `swift package describe` output from a fixture package, preventing future stubs from diverging.
4. **Audit other stubs in the codebase**: Search `spec/` for any other JSON stubs that might have the same shape-mismatch risk.

---

**Working tree state**: Changes uncommitted. No Gemfile.lock changes (reverted each time).
