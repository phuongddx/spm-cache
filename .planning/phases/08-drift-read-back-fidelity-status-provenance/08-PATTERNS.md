# Phase 8: Drift Read-Back, Fidelity Status & Provenance - Pattern Map

**Mapped:** 2026-08-29
**Files analyzed:** 5 (3 modified, 2 spec extended, 1 new spec)
**Analogs found:** 5 / 5 (all patterns exist verbatim in-repo; no external analogs needed)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|-----------------|---------------|
| `lib/spm_cache/spm/build_pipeline.rb` (drift read-back + provenance sidecar) | service | file-I/O + transform | itself — `write_shim_sidecar`/`copy_prebuilt_binary_target` (same file) | exact |
| `lib/spm_cache/installer/build.rb` (status line in build output) | controller | request-response | itself — `build_single_target` (same file) | exact |
| `lib/spm_cache/command/cache/list.rb` (per-module status column) | controller/CLI command | CRUD (read) | `lib/spm_cache/core/diagnostics.rb`'s `lock_graph_fidelity` (pin-diff logic) + `Cache::Cachemap` (status-bucket pattern) | role-match (list.rb itself has no per-module analog — must be rebuilt from scratch, see Pitfall 4) |
| `spec/build_pipeline_provenance_spec.rb` (new) | test | file-I/O | `spec/build_pipeline_seeding_spec.rb` | exact |
| `spec/command_cache_list_spec.rb` (new) | test | request-response | `spec/cachemap_spec.rb` | role-match |

## Pattern Assignments

### `lib/spm_cache/spm/build_pipeline.rb` — drift read-back + provenance sidecar (service, file-I/O)

**Analog:** same file's existing `write_shim_sidecar` (sidecar write) and `copy_prebuilt_binary_target` (cleanup), plus `Core::PackageResolved.pins_or_nil` (parser) and `Core::Diagnostics#lock_pin_value`/`host_pin_value` (precedence rule).

**Imports pattern** (`lib/spm_cache/spm/build_pipeline.rb:1-15`, unchanged — `json`/`fileutils` already required):
```ruby
require "fileutils"
require "tmpdir"
require "digest"
require "json"
require "set"

require "spm_cache/core/log"
require "spm_cache/core/sh"
require "spm_cache/core/config"
require "spm_cache/spm/build"
require "spm_cache/spm/desc/desc"
require "spm_cache/spm/xcframework/xcframework"
require "spm_cache/spm/resolved_graph"
```
Add `require "spm_cache/core/package_resolved"` and `require "spm_cache/version"` if not already transitively loaded (check before adding — `Core::Config` may already pull `package_resolved`).

**Single insertion point in `run`** (`lib/spm_cache/spm/build_pipeline.rb:43-61`, current exact text):
```ruby
def run(name:, pkg_dir:, destinations:, out_dir:, library_evolution: true, resolved_pins_file: nil,
        clones_dir: nil)
  raise "Target name required" if name.nil? || name.empty?

  FileUtils.mkdir_p(out_dir)

  seed_snapshot, seeded = seed_host_graph(name, pkg_dir, resolved_pins_file)

  success = false
  begin
    result = perform_build(name: name, pkg_dir: pkg_dir, destinations: destinations,
                            out_dir: out_dir, library_evolution: library_evolution,
                            clones_dir: clones_dir)
    success = true
    result
  ensure
    ResolvedGraph.restore!(pkg_dir, seed_snapshot) if seeded && !success
  end
end
```
Drift/status/provenance logic slots in right after `success = true`, before `result` is returned — this is the ONE place all three artifact-producing paths (`perform_build`'s direct xcframework build, `run_with_scheme`, `copy_prebuilt_binary_target`) converge, per RESEARCH.md Pattern 2. Capture "intended pins" from `resolved_pins_file` (via `Core::PackageResolved.pins_or_nil`) BEFORE `perform_build` runs — never re-read `pkg_dir/Package.resolved` for the intended side (Pitfall 1). Capture "realized pins" via `Core::PackageResolved.pins_or_nil(File.join(pkg_dir, ResolvedGraph::RESOLVED_FILENAME))` after `perform_build` returns.

**Sidecar write pattern to mirror exactly** (`lib/spm_cache/spm/build_pipeline.rb:843-860`):
```ruby
def write_shim_sidecar(output_path, shim_framework_paths, out_dir)
  built_shim_names = shim_framework_paths.filter_map do |shim_name, paths|
    next nil if paths.empty?
    real_paths = paths.reject { |p| p == :cached }
    if real_paths.empty?
      shim_name
    else
      shim_output = File.join(out_dir, "#{shim_name}.xcframework")
      FileUtils.rm_rf(shim_output)
      XCFramework::XCFramework.new(name: shim_name, framework_paths: real_paths, output_path: shim_output).build
      shim_name
    end
  end
  return if built_shim_names.empty?

  File.write("#{output_path}.shims.json", JSON.generate(built_shim_names))
end
```
New `write_provenance_sidecar(output_path, realized_pins:, config:, destinations:)` should follow the exact same shape: `File.write("#{output_path}.provenance.json", JSON.generate({ pins: realized_pins, spm_cache_version: SPMCache::VERSION, config: config, destinations: destinations }))`. No conditional early-return needed unless realized_pins is nil (vendored `.xcodeproj` / `not-graph-pinned` case — skip writing a sidecar there, matching `cache list`'s documented fallback).

**Cleanup pattern to mirror exactly** (`lib/spm_cache/spm/build_pipeline.rb:882-905`, the Class E path):
```ruby
def copy_prebuilt_binary_target(target_name, product_name, pkg_dir, out_dir)
  # ...
  output_path = File.join(out_dir, "#{product_name}.xcframework")
  FileUtils.rm_rf(output_path)
  FileUtils.cp_r(source, output_path)

  # A pre-Class-E cache entry for this product may carry a
  # `.shims.json` sidecar from when it was still built (and
  # companion-wired) via the normal Buildable/xcodebuild path.
  FileUtils.rm_f("#{output_path}.shims.json")

  output_path
end
```
Add `FileUtils.rm_f("#{output_path}.provenance.json")` at the same line (902), same rationale, one line below.

**Pin-value precedence to mirror exactly** (`lib/spm_cache/core/diagnostics.rb:155-164`, `Core::Diagnostics`, private methods — do NOT call into `Core::Diagnostics` directly since it's a doctor-only registry; copy the precedence logic into `BuildPipeline` or a small shared helper):
```ruby
def lock_pin_value(pkg)
  revision = pkg['revision']
  revision.to_s.empty? ? pkg['version'] : revision
end

def host_pin_value(pin)
  state = pin['state'] || {}
  revision = state['revision']
  revision.to_s.empty? ? state['version'] : revision
end
```
Note: `Core::PackageResolved.pins_or_nil` returns raw pin hashes with a `state` sub-hash (host-graph shape) — both `lock_pin_value`-equivalent (for the seeded/intended side, same host-graph shape) and `host_pin_value` (for the realized side, same shape) actually both need the `host_pin_value` shape here, since BOTH intended and realized pins come from the same `Package.resolved` format (unlike diagnostics.rb which compares a `spm-cache.lock` shape against a host-graph shape). Use one precedence helper, not two.

**Parser to reuse verbatim, never reimplement** (`lib/spm_cache/core/package_resolved.rb:60-72`):
```ruby
def pins_or_nil(path)
  return nil unless path && File.exist?(path)

  data = JSON.parse(File.read(path))
  return nil unless data.is_a?(Hash)

  value = data['pins'] || []
  return nil unless value.is_a?(Array)

  value.select { |pin| pin.is_a?(Hash) }
rescue JSON::ParserError, TypeError
  nil
end
```

**Drift-as-warning precedent** (`Core::UI.warn`, same posture as `lib/spm_cache/core/diagnostics.rb:150`'s `[:warn, "spm-cache.lock disagrees with the host Package.resolved: ..."]` — but here call `Core::UI.warn` directly, not via the `[:warn, msg]` tuple return shape, since this isn't a doctor check):
```ruby
Core::UI.warn "  #{pkg_name}: drift detected (intended #{intended_version}, realized #{realized_version})"
```

**Vendored-checkout / no-resolution precedent** (`lib/spm_cache/spm/resolved_graph.rb:61-63`):
```ruby
def vendored_xcodeproj?(pkg_dir)
  Dir.glob(File.join(pkg_dir, "*.xcodeproj")).any?
end
```
Already called by `seed_host_graph` (line 70) to skip seeding entirely for vendored packages — this is the existing `not-graph-pinned` case (FID-05 precedent per CONTEXT.md line 60/183).

**Seed/source-of-intended-pins pattern** (`lib/spm_cache/spm/resolved_graph.rb:24-30`, `36-41`):
```ruby
def source_for(umbrella_dir:, host_graph_path:)
  umbrella_resolved = File.join(umbrella_dir, RESOLVED_FILENAME)
  return umbrella_resolved if File.exist?(umbrella_resolved)
  return host_graph_path if host_graph_path && File.exist?(host_graph_path)
  nil
end

def seed!(source_path, pkg_dir)
  destination = File.join(pkg_dir, RESOLVED_FILENAME)
  snapshot = snapshot_for(destination)
  atomic_write(destination, File.binread(source_path))
  snapshot
end
```
`resolved_pins_file` (already a `run` kwarg) IS the intended-pins source — read it directly with `Core::PackageResolved.pins_or_nil(resolved_pins_file)` at/before `seed_host_graph` time, store in a local variable, never re-derive it from `pkg_dir` post-build.

---

### `lib/spm_cache/installer/build.rb` — fidelity status line in build output (controller, request-response)

**Analog:** same file's `build_single_target` (existing "Cached: ..." line).

**Core pattern to extend** (`lib/spm_cache/installer/build.rb:157-183`, exact current text):
```ruby
def build_single_target(target_name, checkouts, destinations, cache_out, resolved_pins_file, clones_dir = nil)
  pkg_dir = checkouts[target_name]
  unless pkg_dir && File.directory?(pkg_dir)
    Core::UI.warn "checkout not found for '#{target_name}'; skipping"
    return
  end

  Core::UI.info "  Building #{target_name}..."
  begin
    result = SPM::BuildPipeline.run(
      name: target_name,
      pkg_dir: pkg_dir,
      destinations: destinations,
      out_dir: cache_out,
      library_evolution: true,
      resolved_pins_file: resolved_pins_file,
      clones_dir: clones_dir,
    )
    Core::UI.info "  Cached: #{result}"
  rescue => e
    if @config.ignore_build_errors?
      Core::UI.warn "  #{target_name} build failed (continuing): #{e.message}"
    else
      raise
    end
  end
end
```
**Critical constraint (Pitfall 2):** the fidelity status must NOT be threaded through the `rescue` block — `ignore_build_errors?` only intercepts exceptions (line 177), so the status line must print on the success path, e.g. right after `Core::UI.info "  Cached: #{result}"`. `BuildPipeline.run` should return a richer value (or the status should be queryable via a small struct/hash return, e.g. `{ output_path:, fidelity_status: }`) rather than just the bare path string it returns today — this changes `BuildPipeline.run`'s return contract, so callers (`spm-cache pkg build`, if any, and this call site) both need updating consistently.

**Error-handling pattern already established** (same block, lines 176-181) — unchanged, reused as-is; `resolution-incompatible` must never route through this `rescue`.

---

### `lib/spm_cache/command/cache/list.rb` — per-module fidelity status column (controller/CLI, CRUD-read)

**Analog:** No direct analog for the per-module loop (must be rebuilt, per Pitfall 4) — borrow the read-a-sidecar-and-report pattern conceptually from `write_shim_sidecar`'s sibling-file naming convention, and the status-bucket vocabulary from `Cache::Cachemap`.

**Current implementation (to be replaced, not extended)** (`lib/spm_cache/command/cache/list.rb:11-23`, full file body):
```ruby
def run
  config = Core::Config.instance
  ["debug", "release"].each do |cfg|
    cache_dir = config.cache_dir(cfg)
    next unless File.directory?(cache_dir)

    puts "\n#{cfg.capitalize}:"
    Dir.entries(cache_dir).sort.each do |entry|
      next if entry.start_with?(".")
      puts "  #{entry}"
    end
  end
end
```
**Required rewrite shape** (per Pitfall 4 — iterate `*.xcframework` directories specifically, not raw `Dir.entries`):
```ruby
def run
  config = Core::Config.instance
  ["debug", "release"].each do |cfg|
    cache_dir = config.cache_dir(cfg)
    next unless File.directory?(cache_dir)

    puts "\n#{cfg.capitalize}:"
    Dir.glob(File.join(cache_dir, "*.xcframework")).sort.each do |fw_path|
      name = File.basename(fw_path, ".xcframework")
      status = fidelity_status_for("#{fw_path}.provenance.json")
      puts "  #{name} (#{status})"
    end
  end
end

private

def fidelity_status_for(sidecar_path)
  return "not-graph-pinned" unless File.exist?(sidecar_path)

  JSON.parse(File.read(sidecar_path))["fidelity_status"] || "not-graph-pinned"
rescue JSON::ParserError
  "not-graph-pinned"
end
```
This is new code, not a mechanical port — no existing `cache list` per-module loop exists to extend from (confirmed by RESEARCH.md's grep). Requires `require "json"` at the top of this file (currently absent).

**Cross-reference for status vocabulary** (`Cache::Cachemap`'s existing bucket pattern, `lib/spm_cache/cache/cachemap.rb`) — orthogonal dimension (hit/missed/ignored/excluded/plugin), not reused directly, but confirms the project's existing convention of small string-enum statuses surfaced via simple accessor methods; the three fidelity values (`host-pinned`/`resolution-incompatible`/`not-graph-pinned`) should be implemented the same lightweight way (plain strings, no new enum class).

---

## Shared Patterns

### Tolerant Package.resolved parsing
**Source:** `lib/spm_cache/core/package_resolved.rb:60-72` (`Core::PackageResolved.pins_or_nil`)
**Apply to:** All intended-pins and realized-pins reads in `BuildPipeline` — never write a second parser.

### Pin-value precedence (revision wins over version)
**Source:** `lib/spm_cache/core/diagnostics.rb:155-164` (`lock_pin_value`/`host_pin_value`)
**Apply to:** The intended-vs-realized diff in `BuildPipeline`; copy this precedence logic (or extract to a small shared helper module) rather than inventing a new rule.

### Sidecar file lifecycle (write + cleanup, sibling naming)
**Source:** `lib/spm_cache/spm/build_pipeline.rb:843-860` (write) and `:882-905` (cleanup)
**Apply to:** The new `.provenance.json` sidecar — same `File.write`/`JSON.generate` shape, same `FileUtils.rm_f` cleanup site in `copy_prebuilt_binary_target`.

### Drift-is-a-warning-never-a-failure posture
**Source:** `lib/spm_cache/core/diagnostics.rb:64-151` (`lock_graph_fidelity` doctor check, a *different* drift class but same posture)
**Apply to:** FID-03's per-package drift report — `Core::UI.warn`, never raise, never block the build.

### `ignore_build_errors?` scope (exceptions only)
**Source:** `lib/spm_cache/installer/build.rb:176-181`
**Apply to:** FID-04's `resolution-incompatible` classification — must be a return value / success-path report, never routed through this `rescue`, or it becomes maskable (forbidden by CONTEXT.md).

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `lib/spm_cache/command/cache/list.rb` per-module loop | controller | CRUD (read) | Current implementation is a bare `Dir.entries` walker with zero per-module concept (confirmed empirically); must be built fresh, following the sibling-sidecar-naming convention established elsewhere rather than any existing per-module code in this file |
| `spec/command_cache_list_spec.rb` | test | request-response | No spec file exists for this command anywhere in the repo today (confirmed via `find spec -iname "*cache*list*"` returning nothing per RESEARCH.md) |

## Metadata

**Analog search scope:** `lib/spm_cache/spm/build_pipeline.rb`, `lib/spm_cache/installer/build.rb`, `lib/spm_cache/command/cache/list.rb`, `lib/spm_cache/spm/resolved_graph.rb`, `lib/spm_cache/core/package_resolved.rb`, `lib/spm_cache/core/diagnostics.rb`, `lib/spm_cache/cache/cachemap.rb`, `spec/build_pipeline_seeding_spec.rb`, `spec/cachemap_spec.rb`
**Files scanned:** 9 (all read directly this session or in RESEARCH.md's prior session, cross-verified with fresh reads for line-number accuracy)
**Pattern extraction date:** 2026-08-29
