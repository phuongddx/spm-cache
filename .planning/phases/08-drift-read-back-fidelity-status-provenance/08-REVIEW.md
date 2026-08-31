---
phase: 08-drift-read-back-fidelity-status-provenance
reviewed: 2026-08-29T16:54:00Z
depth: deep
files_reviewed: 5
files_reviewed_list:
  - lib/spm_cache/command/cache/list.rb
  - lib/spm_cache/installer/build.rb
  - lib/spm_cache/spm/build_pipeline.rb
  - spec/build_pipeline_provenance_spec.rb
  - spec/command_cache_list_spec.rb
findings:
  critical: 0
  warning: 0
  info: 2
  total: 2
status: issues_found
---

# Phase 08: Code Review Report (Third Re-Review — Final Auto-Fix Iteration)

**Reviewed:** 2026-08-29T16:54:00Z
**Depth:** deep
**Files Reviewed:** 5
**Status:** issues_found

## Summary

Third and final auto-fix-iteration re-review. Scope for this pass: (1) confirm the
iteration-2 fix for WR-04 (`08-REVIEW-FIX.md`, commit `386305b`) is genuinely correct
and complete, not just plausible-looking; (2) surface anything new across the same
5 in-scope files at deep depth.

**WR-04 fix verification (confirmed correct and complete):** Read the actual diff
(`git show 386305b`) and the current source, not just the fix report's prose.
`perform_build`'s Class E short-circuit (`build_pipeline.rb:221-231`) now calls a new
private helper `actual_destinations_for(output_path, destinations)`
(`build_pipeline.rb:1054-1057`) instead of returning the bare requested `destinations`
tuple. `actual_destinations_for` lists the copied xcframework's own top-level slice
directories via `Dir.children` + `File.directory?` and narrows `requested` down to the
ones a slice actually satisfies via a new `slice_satisfies?` (`build_pipeline.rb:1059-1065`)
— logic byte-identical to `Installer::Build#slice_satisfies?` (`installer/build.rb:96-102`):
`"iphonesimulator"` requires a slice name containing `"simulator"`; `"iphoneos"` requires
one starting with `"ios"` that does *not* contain `"simulator"`.

Traced this against the actual destination values ever passed into `BuildPipeline.run`
in production: `Installer::Build#resolve_destinations` (`installer/build.rb:186-189`)
yields only `SPM::Package::DEFAULT_DESTINATIONS` (`["iphonesimulator", "iphoneos"]`) or
`[@config.default_sdk]` (default `"iphonesimulator"`), and `Command::Pkg::Build#resolve_destinations`
(`command/pkg/build.rb:62-73`) normalizes its `ios_simulator`/`ios_device` CLI aliases to
`"iphonesimulator"`/`"iphoneos"` *before* calling `BuildPipeline.run` — so the two-branch
`case` in `slice_satisfies?` covers every real destination string that reaches it; the
`else false` branch is unreachable in practice, not a hidden data-loss path.

Verified both new regression tests in `build_pipeline_provenance_spec.rb:445-517`
exercise real production code end-to-end (real `mkdir_p`'d checkout/artifacts directory
tree, no stubbing of `copy_prebuilt_binary_target` or `actual_destinations_for`
themselves) rather than mirroring the implementation. Ran the targeted specs
(`spec/build_pipeline_provenance_spec.rb` + `spec/command_cache_list_spec.rb`: 29
examples, 0 failures) and the full suite (368 examples, 0 failures) myself — matches the
counts claimed in `08-REVIEW-FIX.md`.

**Conclusion: WR-04 is genuinely fixed.** No residual "requested ≠ actually-produced"
gap remains in any of the three artifact-producing paths (`perform_build`'s main loop,
`run_with_scheme`, `copy_prebuilt_binary_target`).

IN-01 was correctly left unfixed again this iteration, per the documented
`fix_scope: critical_warning` cut carried across all three iterations — confirmed still
present and still not a correctness bug.

One new item surfaced by this pass, `IN-02` below: the WR-04 fix itself introduced a
second, independent copy of the slice/destination-satisfaction predicate rather than
extracting a shared helper. Classified Info per this workflow's own taxonomy (code
duplication is an Info-tier example, not Warning), but worth naming explicitly since a
future destination-key addition (e.g. macCatalyst) landing in only one of the two copies
would silently desync cache-hit detection from provenance-sidecar honesty — the exact
kind of drift this whole feature exists to prevent, just at the meta level.

No new Critical or Warning findings. Zero critical findings across all three iterations
of this phase's review (CR-01 was the only Critical, fixed in iteration 1).

## Info

### IN-01 (carried over, deliberately unfixed): Redundant `.provenance.json` cleanup in `copy_prebuilt_binary_target`

**File:** `lib/spm_cache/spm/build_pipeline.rb:1044-1046`
**Status:** Confirmed still present, unchanged from the original review. Per
`08-REVIEW-FIX.md` (both iterations), this was explicitly excluded from the fix pass's
scope (`fix_scope: critical_warning`). No new concerns. Restating the fix suggestion for
completeness: remove the redundant `FileUtils.rm_f` (the consolidated `report_fidelity`
insertion point in `run` already handles sidecar cleanup for every path), or add a
one-line note if intentionally kept as defense-in-depth.

### IN-02 (new): `slice_satisfies?` is now duplicated verbatim across `build_pipeline.rb` and `installer/build.rb`

**File:** `lib/spm_cache/spm/build_pipeline.rb:1059-1065`, `lib/spm_cache/installer/build.rb:96-102`
**Issue:** The WR-04 fix added a second, independently-maintained copy of the exact same
destination/slice-satisfaction predicate:

```ruby
# build_pipeline.rb:1059-1065 (new, from commit 386305b)
def slice_satisfies?(slices, dest_key)
  case dest_key
  when "iphonesimulator" then slices.any? { |s| s.include?("simulator") }
  when "iphoneos" then slices.any? { |s| s.start_with?("ios") && !s.include?("simulator") }
  else false
  end
end
```

```ruby
# installer/build.rb:96-102 (pre-existing)
def slice_satisfies?(slices, dest_key)
  case dest_key
  when "iphonesimulator" then slices.any? { |s| s.include?("simulator") }
  when "iphoneos" then slices.any? { |s| s.start_with?("ios") && !s.include?("simulator") }
  else false
  end
end
```

The fix's own comment (`build_pipeline.rb:1050`, `:228`) explicitly acknowledges this is
a mirror of `Installer::Build#slice_satisfies?` rather than a shared call — a conscious
copy-paste, not an oversight, but it means two independent authoritative definitions of
"does this slice directory name satisfy this destination" now exist in two different
classes (`SPM::BuildPipeline`, a module-level singleton method, vs.
`Installer::Build`, a private instance method), with no shared source of truth. If a
future destination key (e.g. macCatalyst, watchOS) is added to one copy and not the
other, `Installer::Build#slice_complete?`'s cache-hit-completeness check and
`BuildPipeline#actual_destinations_for`'s provenance-sidecar narrowing would silently
disagree about which slices count — one could report a hit/complete artifact the other
would consider incomplete, or vice versa, without any test catching the divergence since
each copy is tested only against its own call site.

**Fix:** Extract a single shared helper (e.g. a `SPM::DestinationSlice` module method or
a method on `SPM::Package`/`Buildable::DESTINATIONS`) that both `Installer::Build` and
`SPM::BuildPipeline` call, e.g.:

```ruby
module SPMCache
  module SPM
    module DestinationSlice
      def self.satisfies?(slices, dest_key)
        case dest_key
        when "iphonesimulator" then slices.any? { |s| s.include?("simulator") }
        when "iphoneos" then slices.any? { |s| s.start_with?("ios") && !s.include?("simulator") }
        else false
        end
      end
    end
  end
end
```

Not urgent enough to block shipping this phase (both copies are currently identical and
both are test-covered independently), but worth a follow-up cleanup pass before a third
destination key is ever added.

---

_Reviewed: 2026-08-29T16:54:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep_
