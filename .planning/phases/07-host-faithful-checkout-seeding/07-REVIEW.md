---
phase: 07-host-faithful-checkout-seeding
reviewed: 2026-08-29T14:20:00Z
depth: standard
files_reviewed: 12
files_reviewed_list:
  - lib/spm_cache/core/config.rb
  - lib/spm_cache/installer/build.rb
  - lib/spm_cache/installer/use.rb
  - lib/spm_cache/spm/build.rb
  - lib/spm_cache/spm/build_pipeline.rb
  - lib/spm_cache/spm/resolved_graph.rb
  - spec/build_lock_spec.rb
  - spec/build_pipeline_seeding_spec.rb
  - spec/build_pipeline_spec.rb
  - spec/buildable_spec.rb
  - spec/installer_build_spec.rb
  - spec/resolved_graph_spec.rb
findings:
  critical: 0
  warning: 0
  info: 0
  total: 0
status: clean
---

# Phase 07: Code Review Report (Iteration 3 of 3 — Verification Pass)

**Reviewed:** 2026-08-29T14:20:00Z
**Depth:** standard
**Files Reviewed:** 12
**Status:** clean

## Summary

This is the final verification pass of a review→fix loop. All items from the prior
review that were approved for fixing (CR-01b + WR-01, WR-02, WR-03, WR-04, WR-06)
were verified against the current source at their current line numbers, cross-checked
against the actual commit diffs (`c5d1aaa`, `3a972bb`), and confirmed to close the
originally-described defect without introducing regressions. `bundle exec rspec` was
re-run and confirms 342 examples, 0 failures.

WR-05 and the three Info items (IN-01/02/03) were explicitly out of scope for this
fix iteration (critical+warning only) and were deliberately left untouched; they are
not re-litigated here since no code changed for them and they were not re-approved
for this pass.

### CR-01b — verified closed

`lib/spm_cache/installer/use.rb:16-41`: both the fast path (lines 21-27) and the
non-fast-path (lines 29-39) now wrap their trailing `gen_supporting_files` /
`integrate_proxy_into_project` / `gen_cachemap_viz` calls in `with_build_lock`.
Previously only the non-fast-path was locked, while the fast path's
`gen_cachemap_viz` still wrote into `@config.sandbox_dir` without holding the lock
Installer::Build holds across its entire build — a real race against a concurrent
`recreate_dirs` `rm_rf`.

`spec/build_lock_spec.rb:158-187` replaces the previous (incorrect) assertion that
the fast path "does not acquire the lock" with a timing-based proof
(`gen_supporting_files_called_at - start >= 0.3`) that a forked process holding the
lock for 0.4s genuinely blocks the fast path's trailing calls until release. This is
a real two-process flock contention test, not a mock — confirmed adequate.

### WR-01 — verified closed

`lib/spm_cache/spm/build.rb:144-146`: `build_for_destination` now splats `**opts`
directly into `xcodebuild(dest, derived_data_path: derived_data_path, **opts)`
instead of nesting them under an `opts:` key. Confirmed no caller anywhere in
`lib/` or `spec/` passes a `opts:` keyword expecting the old nested shape — all
call sites either omit extra opts or pass real keys like `live_log:`. Matches the
commit description exactly.

### WR-02 — verified closed

`lib/spm_cache/installer/build.rb:96-102`: `slice_satisfies?`'s `else` branch now
returns `false` instead of `true`. Verified this cannot regress current behavior:
`resolve_destinations` (build.rb:186-188) and `SPM::Package::DEFAULT_DESTINATIONS`
(`pkg/base.rb:17`) only ever produce `"iphonesimulator"`/`"iphoneos"` as
`dest_key` values reaching `slice_satisfies?`, so the changed `else` branch is
presently unreachable in production but correctly fail-safe if a third SDK key is
ever introduced.

### WR-03 — verified closed

`lib/spm_cache/spm/build_pipeline.rb:508-546`: the duplicated swiftinterface-scan
block (framework-wrapped case and bare `.swiftmodule` case) is now a single
`scan_swiftinterfaces` helper called from both sites (lines 522, 526). Diff
confirms the extraction is behavior-preserving (same regex, same `rescue
StandardError` around `File.read`).

### WR-04 — verified closed

Confirmed via `git show 3a972bb` that exactly the three rescues named in the fix
commit message were narrowed:
- `resolve_public_headers` (build_pipeline.rb:468): `StandardError` →
  `SPMCache::Core::GeneralError, JSON::ParserError`
- `resolve_scheme_fallback` (build_pipeline.rb:929-934): bare `rescue ""` →
  `rescue SPMCache::Core::GeneralError`
- `schemes_across_projects` (build_pipeline.rb:283-289): bare `rescue ""` →
  `rescue SPMCache::Core::GeneralError`

The two remaining `rescue StandardError` blocks in `build_pipeline.rb`
(`referenced_module_names` line 515, `scan_swiftinterfaces` line 541) guard
`File.read` calls on already-globbed paths, not shell-outs — a materially
different failure surface (a symlink race, a permissions error, an encoding
error) that the fix commit correctly did not touch. `resolved_graph.rb:77`'s
`rescue StandardError` in `atomic_write` is a cleanup-then-reraise (`tmp&.unlink;
raise`), not an error-swallowing catch, so narrowing it would not change
behavior — also correctly left alone.

### WR-06 — verified closed

`lib/spm_cache/installer/build.rb:185-188`: `resolve_destinations`'s three-branch
`case` (all three branches returned `[sdk]` except the `"all"` branch) is
collapsed into `sdk == "all" ? SPM::Package::DEFAULT_DESTINATIONS : [sdk]`.
Semantically identical to the prior code for every input.

## Verification commands run

```
bundle exec rspec
# => 342 examples, 0 failures
```

All reviewed files meet quality standards for this iteration. No new issues were
introduced by commits `c5d1aaa` or `3a972bb`, and no previously-approved finding
remains open.

---

_Reviewed: 2026-08-29T14:20:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
