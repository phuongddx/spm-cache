---
phase: 09-cache-identity-invalidation
reviewed: 2026-08-29T20:45:00Z
depth: deep
files_reviewed: 13
files_reviewed_list:
  - lib/spm_cache/command/cache/clean.rb
  - lib/spm_cache/installer/use.rb
  - lib/spm_cache/spm/build_pipeline.rb
  - spec/build_pipeline_provenance_spec.rb
  - spec/command_cache_clean_spec.rb
  - spec/gen_proxy_provenance_spec.rb
  - spec/installer_use_fast_path_spec.rb
  - tools/spm-cache-proxy/Sources/Core/Cache.swift
  - tools/spm-cache-proxy/Sources/Core/Generator/ProxyGenerator.swift
  - tools/spm-cache-proxy/Sources/Core/Lockfile.swift
  - tools/spm-cache-proxy/Tests/spm-cache-proxyTests/CacheTests.swift
  - tools/spm-cache-proxy/Tests/spm-cache-proxyTests/LockfileTests.swift
  - tools/spm-cache-proxy/Tests/spm-cache-proxyTests/ProxyGeneratorTests.swift
findings:
  critical: 0
  warning: 0
  info: 2
  total: 2
status: clean
---

# Phase 09: Code Review Report (Final convergence check)

**Reviewed:** 2026-08-29T20:45:00Z
**Depth:** deep
**Files Reviewed:** 13
**Status:** clean (auto-fix budget exhausted; two pre-existing info-tier items carried forward as known, unfixed)

## Summary

This is the final convergence pass for this phase. The auto-fix loop has hit its 3-pass cap; this
review's job was (1) confirm the iteration-3 CR-01 fix (`f83ee3b`, dropping the pre-emptive
`FileUtils.rm_f("#{output_path}.provenance.json")` from `copy_prebuilt_binary_target`) is genuinely
correct and complete, and (2) trace further for anything the prior three iterations missed.

**CR-01 fix verified genuinely correct and complete.** Traced the full call chain end to end:

- `BuildPipeline.run` → `perform_build` → (Class E short-circuit) → `copy_prebuilt_binary_target`
  now only deletes `"#{output_path}.shims.json"`; the `.provenance.json` `rm_f` line is gone
  (confirmed via `git show f83ee3b` — a clean, minimal diff that removes exactly the four lines the
  prior review's fix suggestion specified, plus updates the doc comment on the remaining
  `.shims.json` cleanup to explain why no equivalent removal exists for `.provenance.json`).
- Back in `run`, `report_fidelity` now runs against an **intact** old sidecar. Its `unless seeded`
  branch (`build_pipeline.rb:102-136`) calls `existing_sidecar_pins(output_path)`, which reads
  `"#{output_path}.provenance.json"` successfully (no longer `ENOENT`), finds the previously
  recorded non-empty `pins`, and takes the preserve-and-merge branch (`status: "host-pinned"`,
  `pins: preserved_pins`, but `config`/`destinations` refreshed to *this* build's values per
  WR-05) — instead of falling through to the `not-graph-pinned`/`pins: {}` branch that would
  produce a false cache hit against any host pin.
- The regression test added alongside the fix
  (`spec/build_pipeline_provenance_spec.rb:673-712`, "preserves a prior host-pinned sidecar's
  non-empty pins on an unseeded Class E rebuild (CR-01)") exercises the real production path —
  `BuildPipeline.run` with `resolved_pins_file: nil`, a real prebuilt `.xcframework` on disk, a
  pre-seeded `host-pinned` sidecar with non-empty pins at the Class E product's `output_path` — and
  asserts both `fidelity_status` and `pins` survive an unseeded rebuild unchanged. I independently
  confirmed this is non-tautological by inspecting `git show f83ee3b`'s diff directly (rather than
  re-reverting and re-running, since the diff itself is small and unambiguous): the removed lines
  are exactly the ones that, if restored, would re-run `FileUtils.rm_f` before `report_fidelity`
  reads the file back, reproducing the exact `ENOENT`/fail-through path CR-01 describes.
- Ran both full test suites myself from this checkout: `bundle exec rspec` → **387 examples, 0
  failures**; `swift test` (`tools/spm-cache-proxy/`) → **36 tests in 7 suites, all passed**. Also
  ran the four specifically-relevant spec files in isolation
  (`build_pipeline_provenance_spec.rb`, `command_cache_clean_spec.rb`,
  `installer_use_fast_path_spec.rb`, `gen_proxy_provenance_spec.rb`) → **43 examples, 0 failures**.
  All files listed in this review's scope are committed (clean `git status`), so what I read is
  exactly what ships.

No other code path in `build_pipeline.rb` deletes or otherwise mutates
`"#{output_path}.provenance.json"` before `report_fidelity` runs — `perform_build`'s and
`run_with_scheme`'s `FileUtils.rm_rf(output_path)` calls only remove the `.xcframework` directory
itself (a distinct path from its `.provenance.json`/`.shims.json` sidecars), so this specific class
of "sidecar deleted before the read-back that depends on it" bug does not recur elsewhere in this
file.

Two info-tier items are carried forward, unchanged, from prior iterations — both already
documented, both explicitly out of scope for the exhausted `critical_warning` fix budget, neither
newly discovered by this pass.

## Info

### IN-01 (carried over, unfixed): Fast-path lockfile version read has no fallback for a hand-written/legacy project key

**File:** `lib/spm_cache/installer/use.rb:97-101`

`current_spm_cache_version?` does an exact-basename lookup
(`disk_lockfile.projects[File.basename(@project_path)]`), while other lockfile readers elsewhere in
the codebase (e.g. `Installer#lock_project_data`) fall back to a stem-match ignoring a missing
`.xcodeproj` suffix. A hand-written/legacy lockfile key that doesn't exactly match
`File.basename(@project_path)` makes `fast_path?` return `false` unconditionally (via
`proj_data && ...` short-circuiting on `nil`), forcing a full regeneration. Fail-closed — worst case
is a slower run, not a correctness bug — so this is a reader-consistency nit, not a defect. No fix
suggested for this pass; flagged only for continuity across reviews.

### IN-02 (new observation, very low severity, not a regression): `cache clean`'s orphan-sidecar glob would misclassify a sidecar filename that doesn't end in `.xcframework.{provenance,shims}.json`

**File:** `lib/spm_cache/command/cache/clean.rb:67-68`

```ruby
Dir.glob(File.join(cache_dir, "*.{provenance,shims}.json")).each do |sidecar|
  basename = File.basename(sidecar).sub(/\.xcframework\.(provenance|shims)\.json\z/, "")
```

The glob matches any file ending in `.provenance.json` or `.shims.json`, not specifically
`<name>.xcframework.provenance.json`. If a file existed named e.g. `Foo.provenance.json` (no
`.xcframework.` segment), the anchored `.sub` would be a no-op, `basename` would stay
`"Foo.provenance.json"`, `fw_path` would become `".../Foo.provenance.json.xcframework"` (which
never exists), and the sidecar would be treated as orphaned and deleted. Confirmed via `grep` that
no code in this repo currently writes such a file — every producer of `.provenance.json`/
`.shims.json` derives its path from `output_path = File.join(out_dir, "#{name}.xcframework")`, so
the filename always contains `.xcframework.` — so this is unreachable in practice, not a live bug.
Noting it only because a future sidecar producer that doesn't follow that convention would silently
hit this. No fix needed now.

---

_Reviewed: 2026-08-29T20:45:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep_
