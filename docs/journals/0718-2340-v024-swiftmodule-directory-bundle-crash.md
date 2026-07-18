# v0.2.4 Release: Swiftmodule as Directory Bundle Unblocks the Next Bug

**Date**: 2026-07-18 23:40  
**Severity**: High  
**Component**: lib/spm_cache/spm/build.rb (Buildable#create_framework, Buildable#find_file)  
**Status**: Resolved  

## What Happened

Fixed a second crash in the same code path that emerged when re-testing `eh_xcframework` after the v0.2.3 release. Once the fabricated `abcd` product was removed and `swift package resolve` succeeded, the build progressed to `Buildable#create_framework` and hit: `Errno::EISDIR: Is a directory - read` at line 103, inside a `FileUtils.cp` call. Root cause: `Buildable#find_file` globs for paths ending in `ModuleName.swiftmodule` under Xcode's DerivedData without distinguishing between flat files and directories. For most packages, this resolves to a compiled `.swiftmodule` file. But for multi-arch / library-evolution builds (specifically binaryTarget-wrapping vendor packages like `eh_xcframework`), Xcode emits `ModuleName.swiftmodule` as a DIRECTORY bundle containing per-arch `.swiftmodule`, `.swiftdoc`, and `.swiftsourceinfo` files. `FileUtils.cp` cannot copy a directory; it crashes. Fix: extracted a `copy_module_artifact` helper that branches on `File.directory?`: uses `FileUtils.cp_r(Dir.glob(source/*), destination)` for directories (correctly merging into an existing destination directory), and plain `FileUtils.cp` for flat files. Added 3 regression tests to `spec/buildable_spec.rb` (this method had ZERO direct test coverage before; all existing specs fully stubbed `create_framework`). Validated non-tautologically: reverted only the fix via `git stash`, confirmed the new directory-shape tests reproduced the exact `Errno::EISDIR` from the field report, restored the fix, all passed. Full suite: 112 → 115 examples, 0 failures.

## The Brutal Truth

This is the expected rhythm of blockage-removal: fix one layer, immediately hit the next one in the same code path. It's not a failure of the first fix; it's the whole stack tree coming into focus. What's maddening is that the `find_file` method was never tested directly—three years of specs fully mocked it—so this entire failure mode was invisible until a real build tried to copy a real swiftmodule directory. The moment the proxy resolution worked, the lack of test coverage in the build layer became impossible to ignore.

The upside: once the first bug unblocked downstream progress, the second bug had no hiding place. Real-world retest immediately exposed it.

## Technical Details

**The on-disk shape difference:**
- Flat build (typical): `DerivedData/eh_xcframework/Build/Intermediates.noindex/eh_xcframework.build/Release-iphoneos/eHealth.build/Objects-normal/arm64/eHealth.swiftmodule` (flat file, ~2 MB)
- Multi-arch / library-evolution (eh_xcframework): `DerivedData/eh_xcframework/Build/Intermediates.noindex/eh_xcframework.build/Release-iphoneos/eHealth.build/Objects-normal/eHealth.swiftmodule/` (DIRECTORY containing arm64.swiftmodule, arm64e.swiftmodule, etc.)

**The crash:**
```ruby
# Old code, no type check
source = find_file("#{module_name}.swiftmodule", artifact_dir)
FileUtils.cp(source, destination)  # CRASH: source is a directory
# => Errno::EISDIR: Is a directory - read (Errno::EISDIR) @ io_read - <directory>
```

**The fix:**
```ruby
def copy_module_artifact(source, destination)
  if File.directory?(source)
    # Directory bundle: merge contents into destination
    FileUtils.cp_r(Dir.glob("#{source}/*"), destination)
  else
    # Flat file
    FileUtils.cp(source, destination)
  end
end
```

**Test coverage added:**
Three new specs in `spec/buildable_spec.rb` under `#create_framework` describe block:
- "handles flat swiftmodule files" (typical case)
- "handles swiftmodule directories (multi-arch builds)" (eh_xcframework case)
- "correctly merges swiftmodule directory into existing artifact directory" (correctness check for the merge behavior)

## What We Tried

**Investigation:** Re-ran the `eh_xcframework` integration flow after v0.2.3 release. Proxy generation succeeded (first bug fixed), but `spm-cache build` crashed on swiftmodule copy. Examined actual DerivedData directory structure for eh_xcframework under multi-arch build configuration. Confirmed swiftmodule exists as a directory, not a flat file.

**Validation:** Confirmed `Dir.glob("#{dir}/*")` + `FileUtils.cp_r` correctly merges directory contents into an existing destination (this was critical because the method creates the destination directory a few lines earlier when handling swiftinterface artifacts).

**Regression prevention:** Wrote specs that exercise the real `create_framework` implementation (no mocks), parameterized for flat-file and directory shapes. Verified revert-and-test cycle: removed only the fix, specs failed with exact field crash; restored, all passed.

## Root Cause Analysis

**Why the code was fragile:** `find_file` assumed the result would always be a flat file because the method's callers only ever saw flat files (all test data was synthetic flat files, all production data up until `eh_xcframework` was similarly simple). The method never checked the result type. It was defensive about path globbing but naive about the disk shape that could result from that glob. This is a variant of the same pattern as the `abcd` bug: SPM/Xcode's on-disk output shape varies more than the tool originally assumed, especially for binaryTarget-wrapping vendor packages.

**Why this wasn't caught by existing tests:** All specs that touched `Buildable` and `BuildPipeline` fully stubbed `create_framework` rather than exercising the real implementation. The method had zero direct test coverage. An indirect test would not have surfaced this; only exercising the real code path with real-enough mock data (flat files vs. directories) would catch it.

## Lessons Learned

1. **A fix that unblocks one layer immediately reveals the next bug in the same call stack.** This is not a failure of the first fix; it's the natural consequence of removing a blocker. The lesson is to test multiple layers in sequence, not just the fix itself.

2. **SPM/Xcode's on-disk representation is more variable than assumed.** Products, targets, swiftmodule files, build artifacts—none of these have a single canonical shape. Multi-arch builds, library evolution, binaryTarget wrapping, and other real-world configurations produce different directory structures. Code that touches the filesystem must account for this variability; synthetic test data hides it.

3. **Zero test coverage for a method is worse than a passing test because there's no false confidence.** The previous entry's lesson (tests encoding wrong assumptions are dangerous) implied that having *some* test coverage is worse than none if it validates incorrect behavior. This entry's lesson is the inverse: when a method has NO coverage, it's invisible to regression detection. Either extreme is bad. Real coverage means exercising multiple on-disk shapes with actual File I/O, not stubbed globbing or mocked FileUtils.

## Next Steps

1. **Released.** v0.2.4 tagged, released via GitHub (release notes matching v0.2.0-v0.2.3 format), Homebrew tap updated successfully (verified via `gh api`). This time the full release chain executed immediately after commit + tag, applying the v0.2.3 release-mechanics lesson—no "committed but not pushed" gap.

2. **Downstream blocker unblocked.** epost-app project's `eh_xcframework` migration can now complete: proxy generation works, build copy works, cache categories complete successfully.

3. **Code reviewer finding flagged (optional).** Reviewer noted that `Dir.glob` silently skips dotfiles without `FNM_DOTMATCH` flag. Harmless today (real Xcode module bundles don't contain dotfiles), undocumented. User explicitly chose "approve as-is" rather than fixing (a legitimate scope call, distinct from the `abcd` session's equivalent finding which was fixed). Documented as-is.

4. **No further action.** Test suite clean (115 examples, 0 failures). Buildable layer now has direct test coverage. Next layer up (CLI integration) tested via downstream project's real workflow.

---

**Related artifacts**:
- Commit: `bc3d2ba` (2 files modified, ~40 insertions)
- Previous version: 0.2.3
- Release: 0.2.4
- Spec changes: `spec/buildable_spec.rb` (new `#create_framework` describe block, 3 examples)
- Implementation changes: `lib/spm_cache/spm/build.rb` (Buildable#copy_module_artifact helper)

Status: DONE  
Summary: Fixed second crash in eh_xcframework build flow: swiftmodule-as-directory in multi-arch builds crashed FileUtils.cp. Added type check + cp_r for directories. Added first-ever direct test coverage for Buildable#create_framework. v0.2.4 released with full release chain (push, tag, GitHub release, tap update) completed immediately—applying v0.2.3 release-mechanics lesson without delay.
