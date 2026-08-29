---
phase: 07-host-faithful-checkout-seeding
reviewed: 2026-08-29T06:34:01Z
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
  critical: 2
  warning: 6
  info: 3
  total: 11
status: issues_found
---

# Phase 07: Code Review Report

**Reviewed:** 2026-08-29T06:34:01Z
**Depth:** standard
**Files Reviewed:** 12
**Status:** issues_found

## Summary

Reviewed the host-faithful checkout seeding feature (`ResolvedGraph`), the process-level build lock (`Installer::Build`/`Installer::Use`), and the surrounding `BuildPipeline`/`Buildable` code that threads `resolved_pins_file`/`clones_dir` through the build. The seeding mechanism itself (`resolved_graph.rb`) is small, well-isolated, and its seed/restore/atomic-write logic checks out correctly against its own spec and against `BuildPipeline.run`'s success/failure paths.

Two defects rise to blocker level: (1) `Installer::Use#perform_install` only holds the build lock around its `recreate_dirs`/`prepare_proxy` phase, not around the trailing `gen_supporting_files`/`integrate_proxy_into_project`/`gen_cachemap_viz` calls that `Installer::Build`'s lock *does* cover (via `super`) — this reopens, in the reverse direction, exactly the "rm_rf checkouts out from under a concurrent operation" race the lock was introduced to close. (2) `Installer::Build#slice_complete?` treats a `"hit"` module whose xcframework directory is missing entirely from disk as "complete" (`return true unless File.directory?(fw)`), which is the wrong default — it should force a rebuild, not skip one, when the cache and the filesystem disagree.

Additional warnings cover a broken (dormant) options-forwarding bug in `Buildable#build_for_destination`, an SDK-completeness check that silently no-ops for any destination other than `iphonesimulator`/`iphoneos`, duplicated regex-scanning code, overly broad rescues, and timing-based (`sleep`) concurrency specs that are inherently flake-prone. Info-level items note dead/redundant branches and a couple of minor defensive-coding gaps.

## Critical Issues

### CR-01: Installer::Use's build lock does not cover the same sequence Installer::Build's lock covers, reopening the Pitfall-15 race in the other direction

**File:** `lib/spm_cache/installer/use.rb:16-37`
**Issue:**
`Installer::Build#perform_install` acquires the lock and then calls `super`, which runs the *entire* base `Installer#perform_install` sequence — including `gen_supporting_files`, `integrate_proxy_into_project`, and `gen_cachemap_viz` — all while the lock is held, plus the build loop afterward.

`Installer::Use#perform_install` does not call `super`; it reimplements the sequence itself, and only wraps `recreate_dirs`/`ensure_config_file`/`sync_lockfile`/`prepare_proxy`/`yield` in `with_build_lock`. The trailing `gen_supporting_files`, `integrate_proxy_into_project`, and `gen_cachemap_viz` calls (lines 33-35) run **after** the lock has already been released:

```ruby
else
  with_build_lock do
    recreate_dirs
    ensure_config_file
    sync_lockfile
    prepare_proxy
    yield self if block_given?
  end
end

gen_supporting_files
integrate_proxy_into_project
gen_cachemap_viz
```

If a concurrently-triggered `Installer::Build` run acquires the lock immediately after `Use` releases it, `Build`'s own `recreate_dirs` (run under its lock, via `super`) can `rm_rf`/recreate `sandbox_dir` (proxy dir, xcconfigs, metadata) while `Use`'s unprotected `gen_supporting_files`/`integrate_proxy_into_project` are still reading from or writing into those same directories. This is precisely the class of bug D-06 (the process-level lock) was introduced to prevent — it is just unprotected in the other direction. The existing lock specs (`spec/build_lock_spec.rb`) only assert that `recreate_dirs` blocks on a concurrently-held lock; they never exercise or assert anything about the three trailing calls, so this gap is untested.

**Fix:** Either call `super` in `Use` and layer `Use`-specific behavior around it (fast-path short-circuit before calling super), or extend `with_build_lock`'s block (or add a second lock acquisition) to also cover `gen_supporting_files`, `integrate_proxy_into_project`, and `gen_cachemap_viz`, matching the coverage `Build` gets via `super`.

### CR-02: `slice_complete?` treats a missing cached xcframework as "complete", so a stale/deleted cache entry is silently never rebuilt

**File:** `lib/spm_cache/installer/build.rb:89-94`
**Issue:**
```ruby
def slice_complete?(cache_dir, module_name, destinations)
  fw = File.join(cache_dir, "#{module_name}.xcframework")
  return true unless File.directory?(fw)
  slices = Dir.children(fw).select { |s| File.directory?(File.join(fw, s)) }
  destinations.all? { |d| slice_satisfies?(slices, d) }
end
```
This is only called for modules already classified `"hit"` by the cachemap:
```ruby
missed.concat(@cachemap.hit.select { |m| !slice_complete?(cache_out, m, destinations) })
```
The method's own doc comment states the purpose is "must be rebuilt instead of skipped" for incomplete slices — but when the xcframework directory doesn't exist *at all* (e.g. it was removed by a concurrent `cache clean`, an interrupted prior run, or any cachemap/filesystem drift), the guard returns `true` ("complete"), so the module is **not** added to `missed` and is never rebuilt. The net effect is a `"hit"` whose artifact is entirely absent from disk gets silently skipped rather than rebuilt, leaving the final app without that binary. The intent was almost certainly to avoid `Dir.children` raising on a nonexistent path, but the chosen fallback value inverts the safe default.

**Fix:**
```ruby
def slice_complete?(cache_dir, module_name, destinations)
  fw = File.join(cache_dir, "#{module_name}.xcframework")
  return false unless File.directory?(fw)
  slices = Dir.children(fw).select { |s| File.directory?(File.join(fw, s)) }
  destinations.all? { |d| slice_satisfies?(slices, d) }
end
```

## Warnings

### WR-01: `Buildable#build_for_destination` passes `opts` as a nested hash instead of splatting it, silently dropping `live_log`/`extra_args`

**File:** `lib/spm_cache/spm/build.rb:144-146`
**Issue:**
```ruby
def build_for_destination(destination_key, derived_data_path: nil, **opts)
  dest = DESTINATIONS[destination_key] || destination_key
  dd = xcodebuild(dest, derived_data_path: derived_data_path, opts: opts)
```
`opts: opts` passes the whole captured-kwargs hash as the value of a single keyword named `opts`, rather than splatting it (`**opts`). Inside `xcodebuild(destination, derived_data_path: nil, **opts)`, the local `opts` therefore becomes `{ opts: { live_log: ..., extra_args: ... } }` — a one-key hash wrapping the real options. `opts[:live_log]` (used for `Core::Sh.run(cmd, cwd: @pkg_dir, live_log: opts[:live_log])`) and `opts[:extra_args]` (used in `build_command`) both silently evaluate to `nil`, regardless of what the caller passed. Every current call site (`build_pipeline.rb:124,195`, `pkg/base.rb:94`) happens to call `build_for_destination` with no extra opts today, so this is currently dormant, but it is a genuine break in the method's contract and will silently no-op the first time a caller tries to pass `live_log:`/`extra_args:` through this path.

**Fix:**
```ruby
dd = xcodebuild(dest, derived_data_path: derived_data_path, **opts)
```

### WR-02: `slice_satisfies?`'s catch-all branch bypasses slice verification for any SDK other than iphonesimulator/iphoneos

**File:** `lib/spm_cache/installer/build.rb:96-102`
**Issue:**
```ruby
def slice_satisfies?(slices, dest_key)
  case dest_key
  when "iphonesimulator" then slices.any? { |s| s.include?("simulator") }
  when "iphoneos" then slices.any? { |s| s.start_with?("ios") && !s.include?("simulator") }
  else true
  end
end
```
`Config#default_sdk` is a free-form string from `spm-cache.yml` and `resolve_destinations` (build.rb:185-195) passes it straight through for any value other than `"all"`. For any destination key other than the two handled cases (e.g. a mistyped SDK, or any future/alternate SDK value), this returns `true` unconditionally — meaning a "hit" that has *no* matching slice at all for that destination is still reported "complete" and never rebuilt. This silently defeats the multi-slice completeness check this method exists to provide.

**Fix:** Either validate `default_sdk` against a known set and reject/warn on unrecognized values, or make the `else` branch conservative (`false`) so unrecognized destinations force a rebuild rather than silently pass.

### WR-03: Duplicated Swift-interface scanning block in `referenced_module_names`

**File:** `lib/spm_cache/spm/build_pipeline.rb:517-547`
**Issue:** The `@_exported import` regex scan (with its identical explanatory comment) is duplicated verbatim between the "framework-wrapped" scan (lines 518-530) and the "bare `.swiftmodule`" scan (lines 533-547):
```ruby
Dir.glob(File.join(main_framework, "Modules", "*.swiftmodule", "*.swiftinterface")).each do |interface|
  ...
  content.scan(/^\s*(?:@_exported\s+)?import\s+([A-Za-z0-9_]+)\s*$/) { |m| names << m[0] }
end
...
if products_dir && module_name
  Dir.glob(File.join(products_dir, "#{module_name}.swiftmodule", "*.swiftinterface")).each do |interface|
    ...
    content.scan(/^\s*(?:@_exported\s+)?import\s+([A-Za-z0-9_]+)\s*$/) { |m| names << m[0] }
  end
end
```
**Fix:** Extract a small private helper, e.g. `scan_swiftinterfaces(glob_pattern, names)`, and call it from both branches with the two different glob patterns.

### WR-04: Overly broad rescues silently swallow real errors

**File:** `lib/spm_cache/spm/build_pipeline.rb:456-466` (`resolve_public_headers`), `933-940` (`resolve_scheme_fallback`), `283-291` (`schemes_across_projects`)
**Issue:**
```ruby
def resolve_public_headers(module_name, name, pkg_dir)
  ...
  Desc::Target.new(raw: target, pkg_dir: pkg_dir).header_paths
rescue StandardError
  []
end
```
and
```ruby
list_output = Core::Sh.capture_output("xcodebuild -list", cwd: pkg_dir) rescue ""
```
These rescue *any* `StandardError` (including programming errors such as `NoMethodError`/`ArgumentError` from an unexpected `raw` shape) and silently return an empty result with no logging. This can mask a real defect as "no public headers found" / "no schemes found" rather than surfacing it, making failures much harder to diagnose in the field.
**Fix:** Narrow the rescued class to the specific expected failure (e.g. `SPMCache::Core::GeneralError` for shell-outs, or a specific parsing error for `Desc::Target`), and log a debug/warn line before swallowing.

### WR-05: Timing-based (`sleep`) concurrency specs are inherently flake-prone

**File:** `spec/build_lock_spec.rb:22-48, 130-156`
**Issue:** These specs rely on wall-clock `sleep 0.3`/`sleep 0.4` in a forked child plus an assertion like `expect(recreate_called_at - start).to be >= 0.3`. Under CI load, scheduling jitter, or a slow/contended CI runner, the parent process could plausibly observe the elapsed time as slightly under the threshold even though the lock behaved correctly, producing an intermittent false failure (or, conversely, a false pass if the child is scheduled late and the lock check happens to still show `false` afterward for unrelated reasons). This directly affects test reliability, which is in scope even though other test-only nits are not.
**Fix:** Use a rendezvous signal (e.g. a second pipe write right in the *release* path) rather than a fixed sleep duration plus a wall-clock elapsed-time assertion, so the test doesn't depend on timing margins.

### WR-06: Asymmetric SDK-string handling has redundant branch masking a real gap

**File:** `lib/spm_cache/installer/build.rb:185-195`
**Issue:**
```ruby
def resolve_destinations
  sdk = @config.default_sdk
  case sdk
  when "all"
    SPM::Package::DEFAULT_DESTINATIONS
  when "iphonesimulator", "iphoneos"
    [sdk]
  else
    [sdk]
  end
end
```
The `"iphonesimulator", "iphoneos"` branch and the `else` branch produce byte-identical results (`[sdk]`), so the middle branch is dead weight — a leftover from a refactor that no longer discriminates. This isn't just a stylistic nit: it is the same code path that feeds WR-02's `slice_satisfies?` gap, so any non-`"all"`/non-recognized SDK value flows straight through with no validation at all.
**Fix:** Either collapse to `sdk == "all" ? SPM::Package::DEFAULT_DESTINATIONS : [sdk]`, or (better, alongside WR-02) validate `sdk` against the known set and raise/warn on anything else.

## Info

### IN-01: `Config::DEFAULT_CONFIG.dup` is a shallow copy

**File:** `lib/spm_cache/core/config.rb:31-35, 150-152`
**Issue:** `@raw = DEFAULT_CONFIG.dup` (in `initialize` and `reset!`) shallow-copies the frozen `DEFAULT_CONFIG` hash; the `"ignore" => []` / `"cache_only" => []` array values are still the *same* frozen-hash-owned array objects shared across every `Config` instance/reset. Today's only mutator (`command/off.rb:21`, `config.raw["ignore"] = ignore.uniq`) reassigns rather than mutates in place, so this is not currently exploited, but any future code that does `config.raw["ignore"] << x` would corrupt `DEFAULT_CONFIG`'s array for the lifetime of the process.
**Fix:** Use a deep copy (e.g. `Marshal.load(Marshal.dump(DEFAULT_CONFIG))`) or construct fresh array literals per key in `initialize`/`reset!`.

### IN-02: `Config#load` omits `aliases: true`, unlike the sibling `YAMLRepresentable#load`

**File:** `lib/spm_cache/core/config.rb:48-54`
**Issue:** `Config#load` calls `YAML.safe_load(File.read(@config_path))` with no `aliases:` option, while `Syntax::YAMLRepresentable#load` (included in this same class, though overridden here) explicitly passes `aliases: true`. If a user's `spm-cache.yml` uses YAML anchors/aliases, `Config#load` will raise `Psych::BadAlias` where the module's own loader would have succeeded. Minor inconsistency, likely harmless for typical flat config files.
**Fix:** Pass `aliases: true` for consistency, or document that config YAML must not use anchors.

### IN-03: `Buildable#destination_arch`'s `"Simulator"` check is redundant given the `"Sim"` check

**File:** `lib/spm_cache/spm/build.rb:374-381`
**Issue:**
```ruby
if dd.include?("Simulator") || dd.include?("sim") || dd.include?("Sim")
```
Any string containing `"Simulator"` necessarily contains `"Sim"`, so the first condition is dead weight (harmless, but confusing to a future reader).
**Fix:** Simplify to `dd.include?("Sim") || dd.include?("sim")` (or, better, match case-insensitively once: `dd.downcase.include?("sim")`).

---

_Reviewed: 2026-08-29T06:34:01Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
