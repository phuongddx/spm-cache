---
phase: 09-cache-identity-invalidation
reviewed: 2026-08-29T12:50:13Z
depth: deep
files_reviewed: 12
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
  critical: 1
  warning: 4
  info: 2
  total: 7
status: issues_found
---

# Phase 09: Code Review Report

**Reviewed:** 2026-08-29T12:50:13Z
**Depth:** deep
**Files Reviewed:** 12
**Status:** issues_found

## Summary

Reviewed the phase 09 diff (`git diff a5d1383a3ffe18ff9702cc7acce64d241b7f5d45^..HEAD`) at deep
depth: the `spm-cache use` fast-path version-stamp gate, the `cache clean` orphaned-sidecar sweep,
`report_fidelity`'s new "not-graph-pinned" explicit-sidecar write, and `BinariesCache.hit`'s
provenance-aware (identity+pin) cache-hit decision, plus their accompanying specs.

The core CACHE-02/CACHE-03 logic itself (drift comparison, intersection-only pin semantics,
sidecar read/write, orphan sweep) is solid and well covered by the new tests — I traced every test
against its corresponding implementation branch and found the two agree. The most serious issue is
not in the new code itself but in what this phase's fast-path fix now makes *routinely reachable*:
tracing `Installer::Use#perform_install`'s fast path into `Installer#integrate_proxy_into_project`
(a method this phase does not touch, but that the fast path unconditionally calls) shows that
plugin-only SPM package references get silently stripped from the Xcode project on every fast-path
run, because the fast path never populates `@lockfile`. This is a pre-existing, previously-dormant
gap that this phase's own plan documentation (`09-02-PLAN.md`) explicitly flags as a known,
deliberately-untouched interaction — but this phase's version-stamp gate is precisely what makes the
fast path the *reliable, default-taken* branch for every unchanged run going forward, so the
practical blast radius of that gap grows substantially as a direct consequence of this phase's
change. It is reported here as a BLOCKER because it is a real, provable behavior defect exercised by
code this phase modifies, not because the phase introduced the root cause.

The remaining findings are narrower edge cases in the new provenance/pin logic (a `nil` current-pin
silently bypassing the new drift check, an `ensure`-block ordering gap that can leave a seeded
checkout unrestored) and small code-quality nits.

## Critical Issues

### CR-01: Fast path silently strips plugin-only package references from the Xcode project

**File:** `lib/spm_cache/installer/use.rb:21-27` (fast path), `lib/spm_cache/installer.rb:493-653`
(call chain: `integrate_proxy_into_project` → `plugin_only_lockfile_urls`)

**Issue:** `Installer::Use#perform_install`'s fast-path branch calls only
`gen_supporting_files` / `integrate_proxy_into_project` / `gen_cachemap_viz` — it never calls
`sync_lockfile`, which is the *only* place that assigns `@lockfile`:

```ruby
# lib/spm_cache/installer/use.rb
if fast_path?
  Core::UI.info 'No changes detected. Proxy package up to date.'
  with_build_lock do
    gen_supporting_files
    integrate_proxy_into_project
    gen_cachemap_viz
  end
else
  with_build_lock do
    recreate_dirs
    ensure_config_file
    sync_lockfile          # <-- only place @lockfile is ever set
    prepare_proxy
    ...
```

`integrate_proxy_into_project` (unchanged by this phase, but directly invoked by the code this
phase modifies) decides which existing Xcode package references to *keep* rather than purge via
`plugin_only_lockfile_urls`:

```ruby
# lib/spm_cache/installer.rb
def plugin_only_lockfile_urls
  urls = []
  @lockfile&.projects&.each_value do |proj_data|   # @lockfile is nil on the fast path -> no-op, urls == []
    ...
  end
  urls
end
```

With `plugin_urls == []`, `plugin_ref?` never matches anything, so `plugin_kept_refs == []`. Later:

```ruby
project.root_object.package_references.to_a.each do |ref|
  next if kept_refs.include?(ref)     # kept_refs == never_cached_refs only (plugin refs never included)
  ref.remove_from_project
end
```

Any package reference for a build-tool-plugin package (e.g. a SwiftGenPlugin-style dependency,
which has no `library` product and is therefore never referenced by `never_cached_refs`) is removed
from the project on every fast-path run, and its corresponding product dependency is stripped too
(`dep_exempted?` only spares it if the product name happens to be prefixed `"plugin:"` — an
Xcode-internal convention that does not cover every plugin dependency shape). The net effect: a
project with a build-tool-plugin SPM dependency silently loses that dependency's Xcode wiring the
second time `spm-cache`/`spm-cache use` runs with no host-graph changes.

This exact interaction is already known and explicitly called out as intentionally left alone in
`.planning/phases/09-cache-identity-invalidation/09-02-PLAN.md`:
> "Setting the `@lockfile` ivar as a side effect of the check would change what
> `integrate_proxy_into_project`'s `plugin_only_lockfile_urls` sees on the fast path (it currently
> reads `@lockfile&.projects&.each_value` and silently no-ops when `@lockfile` is `nil`) -- an
> unrelated behavior change this plan must not introduce."

That framing treats the *status quo* as the safe choice, but the status quo is the bug: before this
phase, `fast_path?` had no version-stamp gate, so it's plausible the fast path was taken rarely
enough in practice that this gap went unnoticed. This phase's `current_spm_cache_version?` addition
is exactly what makes the fast path reliably taken on every unchanged run from now on — so a
previously narrow exposure window becomes the routine case for any project carrying a plugin-only
package.

**Fix:** Populate `@lockfile` (read-only, no save) on the fast path before calling
`integrate_proxy_into_project`, e.g.:

```ruby
if fast_path?
  Core::UI.info 'No changes detected. Proxy package up to date.'
  with_build_lock do
    @lockfile = Core::Lockfile.new(@config.lockfile_path)
    gen_supporting_files
    integrate_proxy_into_project
    gen_cachemap_viz
  end
```

and add a regression spec asserting a plugin-only package's `XCRemoteSwiftPackageReference` /
`XCSwiftPackageProductDependency` survive a fast-path run.

## Warnings

### WR-01: `BuildPipeline.run`'s success flag is set before the code its own doc comment says must restore-on-failure

**File:** `lib/spm_cache/spm/build_pipeline.rb:58-79`

**Issue:**

```ruby
success = false
begin
  intended_pin_map = seeded ? pin_value_map(...) : nil
  result, built_destinations = perform_build(...)
  success = true
  report_fidelity(...)   # <-- runs AFTER success is already true
  result
ensure
  ResolvedGraph.restore!(pkg_dir, seed_snapshot) if seeded && !success
end
```

`report_fidelity` does non-trivial work after `success = true` is set: JSON generation, a rename,
and (on the seeded branch) reading and diffing pin maps from a second `Package.resolved`. If any of
that raises something other than `SystemCallError` — the only class `write_provenance_sidecar`
rescues — e.g. `JSON::GeneratorError`/`Encoding::UndefinedConversionError` from non-UTF8 identity
strings, or a `NoMethodError` from a malformed pin entry reaching `drifted_identities`/
`pin_value_map`/`host_pin_value` — the exception propagates out of `run` to the caller, but the
`ensure` block's restore guard (`seeded && !success`) is already false, so the seeded
`Package.resolved` is left in place. This contradicts the method's own doc comment: "seeded checkout
restored on any failure/interrupt, left in place on success — Phase 8's future read-back source."
`success` here really means "the build itself succeeded," not "the whole `run` call is returning
normally," and the `ensure` guard conflates the two.

**Fix:** Move `report_fidelity`'s call (or at minimum, treat any exception from it as still needing
restoration) outside the "success" window, e.g. wrap it in its own begin/rescue that logs and
swallows *any* `StandardError` (matching the "never raises" invariant the surrounding comments
already claim), not just `SystemCallError`:

```ruby
rescue SystemCallError => e
  tmp&.unlink
  Core::UI.warn "  could not write provenance sidecar for #{File.basename(output_path)}: #{e.message}"
rescue StandardError => e
  tmp&.unlink
  Core::UI.warn "  could not write provenance sidecar for #{File.basename(output_path)}: #{e.message}"
end
```

### WR-02: `BinariesCache.hit` silently skips the drift check when the lockfile's current pin is `nil`

**File:** `tools/spm-cache-proxy/Sources/Core/Cache.swift:28-43`

**Issue:**

```swift
if let recorded = pins[identity], let current = currentPin, recorded != current {
    return nil // miss: pin disagreement
}
return xcframework
```

When `currentPin` is `nil` (i.e. `Lockfile.PackageRef.pinValue` returns `nil`, which happens
whenever a lockfile entry has neither `version` nor `revision` recorded — a malformed/legacy/
partially-reconciled entry), the `if let current = currentPin` binding fails regardless of whether
`pins[identity]` is present and would have disagreed, so the whole condition is skipped and a hit is
always granted. This silently falls back to pre-CACHE-02 (fileExists-only) semantics for exactly
the package identities whose lockfile data is least trustworthy, which is the opposite of the
fail-safe posture the rest of `hit()` establishes (absent/malformed sidecar → miss). No test in
`CacheTests.swift` exercises `currentPin: nil` together with a disagreeing `pins[identity]` entry.

**Fix:** Treat a `nil` current pin as inconclusive-but-cautious rather than "no evidence of drift,"
or at minimum add a `CacheTests.swift` case documenting the intended behavior explicitly (currently
unstated and not covered):

```swift
@Test("currentPin nil with a disagreeing recorded pin -- decide and test this explicitly")
func nilCurrentPinWithDisagreeingRecordedPin() throws { ... }
```

### WR-03: `spm-cache pkg build` can silently downgrade a host-pinned cache entry to permanently-hit

**File:** `lib/spm_cache/spm/build_pipeline.rb:92-107`, `lib/spm_cache/command/pkg/build.rb:43-49`

**Issue:** `Command::Pkg::Build` never passes `resolved_pins_file` to `BuildPipeline.run` (by
design — its doc comment says `nil` "disables seeding entirely"). Since this phase changed the
`unless seeded` branch of `report_fidelity` from deleting the sidecar to *writing* an explicit
`"not-graph-pinned"`/`pins: {}` sidecar, any `spm-cache pkg build <name> --out <dir>` invocation
that happens to target the same cache directory `spm-cache use`/`build` write to will overwrite a
previously host-pinned (drift-protected, non-empty `pins`) sidecar with an empty-`pins` one. Per
`hit()`'s intersection-only rule, empty `pins` means "no evidence of drift" against *any* future
`currentPin`, so that cache entry becomes permanently hit — the exact identity-collision failure
mode CACHE-02 exists to prevent — until someone notices and runs `cache clean` on it. This requires
non-default `--out` usage (the default is the current working directory, not the shared cache), so
it's a real but lower-probability footgun; worth a one-line doc/warning rather than a design change.

**Fix:** Either warn in `Command::Pkg::Build` when `--out` resolves inside a configured cache
directory, or have `report_fidelity`'s `unless seeded` branch preserve an existing sidecar's
non-empty `pins` instead of unconditionally overwriting with `{}` when no host graph is available
this run.

### WR-04: `Command::Cache::Clean#remove_path`'s `cfg` parameter is unused

**File:** `lib/spm_cache/command/cache/clean.rb:43-52`

**Issue:**

```ruby
def remove_path(path, cfg)
  return unless File.exist?(path)
  ...
```

`cfg` is passed by both call sites (`remove_path(cache_dir, cfg)` and
`remove_path(File.join(cache_dir, t), cfg)`) but never referenced inside the method body. Dead
parameter — harmless, but noise that obscures the method's real contract.

**Fix:** Drop the parameter: `def remove_path(path)` and update both call sites.

## Info

### IN-01: Redundant `provenance.json` cleanup in `copy_prebuilt_binary_target`

**File:** `lib/spm_cache/spm/build_pipeline.rb:1043-1051`

**Issue:** `copy_prebuilt_binary_target` explicitly does
`FileUtils.rm_f("#{output_path}.provenance.json")` before returning. This was necessary
pre-this-phase, when `report_fidelity`'s `unless seeded` branch only ever *deleted* the sidecar (so
Class E builds with `seeded == false` needed their own explicit cleanup to avoid a stale leftover).
Now that `report_fidelity` *always* writes a fresh sidecar via `write_provenance_sidecar` (which
renames a tempfile over the destination, clobbering whatever is there) on both the seeded and
unseeded branches, this explicit `rm_f` is redundant — harmless, but leftover from before this
phase's refactor and worth removing for clarity. (The neighboring `.shims.json` `rm_f` immediately
above it is still required and should stay.)

**Fix:** Remove the now-redundant `FileUtils.rm_f("#{output_path}.provenance.json")` line; keep the
`.shims.json` one.

### IN-02: Fast-path lockfile version read has no fallback for a hand-written/legacy project key

**File:** `lib/spm_cache/installer/use.rb:91-95`

**Issue:** `current_spm_cache_version?` looks up
`disk_lockfile.projects[File.basename(@project_path)]` with an exact-basename match only, whereas
`Installer#lock_project_data` (used elsewhere for the same lockfile) also falls back to a
stem-match ignoring a missing `.xcodeproj` suffix for hand-written/workspace-era locks. This is
fail-closed (a mismatch just forces a full regeneration rather than corrupting anything), so it's
not a correctness bug, but it's an inconsistency between two lookups of the same data that could
cause silent, hard-to-diagnose "fast path never engages" behavior for such a project's lockfile.

**Fix:** Factor the stem-fallback lookup out of `lock_project_data` into a shared helper both call,
or note in a comment why `current_spm_cache_version?` intentionally uses the stricter match.

---

_Reviewed: 2026-08-29T12:50:13Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep_
