---
phase: 08-drift-read-back-fidelity-status-provenance
reviewed: 2026-08-29T00:00:00Z
depth: deep
files_reviewed: 5
files_reviewed_list:
  - lib/spm_cache/command/cache/list.rb
  - lib/spm_cache/installer/build.rb
  - lib/spm_cache/spm/build_pipeline.rb
  - spec/build_pipeline_provenance_spec.rb
  - spec/command_cache_list_spec.rb
findings:
  critical: 1
  warning: 3
  info: 1
  total: 5
status: issues_found
---

# Phase 08: Code Review Report

**Reviewed:** 2026-08-29T00:00:00Z
**Depth:** deep
**Files Reviewed:** 5
**Status:** issues_found

## Summary

Reviewed the drift read-back / fidelity-status / provenance-sidecar feature: the new
`fidelity_status_for` read path in `cache list`, the `config:` threading in
`Installer::Build`, and the new `report_fidelity` / `drifted_identities` /
`pin_value_map` / `write_provenance_sidecar` machinery added to
`SPM::BuildPipeline.run`. The core drift-diff logic (intersection-only scoping,
revision-over-version precedence, nil-safe fallbacks) is correct and well covered by
`spec/build_pipeline_provenance_spec.rb`. Cross-file tracing surfaced one real crash
risk in the new `cache list` read path, and several correctness/robustness gaps in the
new provenance-write code that aren't exercised by the current spec suite (verified by
confirming no test in `build_pipeline_provenance_spec.rb` covers a partial-destination
failure, a `report_fidelity` write failure, or a non-Hash sidecar payload).

## Critical Issues

### CR-01: `cache list` can crash and abort the entire listing on a sidecar read race or malformed sidecar shape

**File:** `lib/spm_cache/command/cache/list.rb:29-35`
**Issue:** `fidelity_status_for` only rescues `JSON::ParserError`:

```ruby
def fidelity_status_for(sidecar_path)
  return "not-graph-pinned" unless File.exist?(sidecar_path)

  JSON.parse(File.read(sidecar_path))["fidelity_status"] || "not-graph-pinned"
rescue JSON::ParserError
  "not-graph-pinned"
end
```

Two realistic failure modes are not handled:

1. **TOCTOU race:** between the `File.exist?` check and `File.read`, a concurrent
   `spm-cache cache clean` (which unconditionally `rm_f`s `.provenance.json`
   alongside the xcframework) or a concurrent build's `report_fidelity`/
   `copy_prebuilt_binary_target` rewrite can delete/replace the file. `File.read`
   then raises `Errno::ENOENT` (or briefly reads a truncated in-flight write from
   the non-atomic `File.write` in `write_provenance_sidecar`), which is **not**
   rescued here.
2. **Valid JSON, non-Hash payload:** if the sidecar ever contains valid JSON that
   isn't an object (e.g. a truncated-but-syntactically-valid array/scalar from a
   partial write, or a foreign/future schema), `JSON.parse(...)["fidelity_status"]`
   raises `NoMethodError`/`TypeError`, not `JSON::ParserError`.

Either raises an uncaught exception out of the `Dir.glob(...).each` loop in `run`,
which aborts the *entire* `cache list` command — every package alphabetically after
the offending one silently never gets printed, not just the affected entry. The spec
suite only exercises the syntax-invalid case (`spec/command_cache_list_spec.rb:52-58`,
`'{"fidelity_status": "host-pinned"'`), so this gap is untested.

**Fix:**
```ruby
def fidelity_status_for(sidecar_path)
  return "not-graph-pinned" unless File.exist?(sidecar_path)

  parsed = JSON.parse(File.read(sidecar_path))
  return "not-graph-pinned" unless parsed.is_a?(Hash)

  parsed["fidelity_status"] || "not-graph-pinned"
rescue JSON::ParserError, SystemCallError
  "not-graph-pinned"
end
```

## Warnings

### WR-01: Provenance sidecar's `destinations` field records requested destinations, not the ones that actually built

**File:** `lib/spm_cache/spm/build_pipeline.rb:49-74, 87-114, 223-249`
**Issue:** `run` threads its own `destinations:` argument straight through to
`report_fidelity` (line 69) and into `write_provenance_sidecar` (line 113), which
writes it verbatim into the sidecar. But `perform_build`'s per-destination loop
(lines 223-231) *rescues and skips* a destination that fails to build:

```ruby
destinations.each do |dest_key|
  ...
  begin
    artifacts = buildable.build_for_destination(dest_key, derived_data_path: dd)
  rescue => e
    Core::UI.warn "#{dest_key} build failed: #{e.message}"
    next
  end
  ...
end
...
raise "No slices were built successfully for #{name}" if framework_paths.empty?
```

Only an *empty* `framework_paths` raises. If, say, `iphoneos` fails but
`iphonesimulator` succeeds, the build "succeeds" with a single-slice xcframework,
yet the provenance sidecar still claims `"destinations": ["iphonesimulator",
"iphoneos"]` — the exact opposite of what this phase is supposed to record (an
honest read-back of what was actually produced). No test in
`build_pipeline_provenance_spec.rb` exercises a partial-destination-failure build,
so this gap is unverified.

**Fix:** Track which `dest_key`s actually produced a framework inside
`perform_build` (e.g. `built_destinations << dest_key` right after the `next unless
artifacts[...]` guard) and thread that list back through `run`/`report_fidelity`
instead of the original `destinations:` argument.

### WR-02: `intended_pin_map` is computed outside the seed/restore exception boundary

**File:** `lib/spm_cache/spm/build_pipeline.rb:55-73`
**Issue:**
```ruby
seed_snapshot, seeded = seed_host_graph(name, pkg_dir, resolved_pins_file)
intended_pin_map = seeded ? pin_value_map(Core::PackageResolved.pins_or_nil(resolved_pins_file)) : nil

success = false
begin
  result = perform_build(...)
  success = true
  report_fidelity(...)
  result
ensure
  ResolvedGraph.restore!(pkg_dir, seed_snapshot) if seeded && !success
end
```
`seed_host_graph` mutates `pkg_dir/Package.resolved` (via `ResolvedGraph.seed!`)
*before* the `begin/ensure` region starts. The `intended_pin_map` line sits between
the seed call and `begin`, so if it were ever to raise, the just-seeded checkout
would never be restored — contradicting the surrounding comment's stated guarantee
("seeded checkout restored on any failure/interrupt"). Today this can't actually
fire, because `Core::PackageResolved.pins_or_nil` and `pin_value_map` are both
designed to swallow parse errors and return `nil` rather than raise — but that
safety is incidental to this call site, not structurally guaranteed by it. This is a
latent landmine for the next person who touches `pin_value_map`/`pins_or_nil` and
assumes (reasonably, from the "always restored on failure" doc comment) that
anything after `seed_host_graph` is covered.

**Fix:** Move the `intended_pin_map` computation inside the `begin` block so the
exception-safety invariant actually covers every statement that can observe/act on
the seeded checkout:
```ruby
success = false
begin
  intended_pin_map = seeded ? pin_value_map(Core::PackageResolved.pins_or_nil(resolved_pins_file)) : nil
  result = perform_build(...)
  ...
```

### WR-03: `write_provenance_sidecar`'s non-atomic `File.write` can raise, contradicting `report_fidelity`'s documented "never raises" invariant

**File:** `lib/spm_cache/spm/build_pipeline.rb:86-114, 158-166`
**Issue:** The doc comment on `report_fidelity` states: "Never raises -- this always
runs on the success path, so `ignore_build_errors?` can never mask the
resolution-incompatible status (Pitfall 2)." But `write_provenance_sidecar` ends in
a plain `File.write`:
```ruby
def write_provenance_sidecar(output_path, status:, pins:, config:, destinations:)
  File.write("#{output_path}.provenance.json", JSON.generate(...))
end
```
This can raise (`Errno::ENOSPC`, `Errno::EACCES`, etc.), unlike
`ResolvedGraph.atomic_write` elsewhere in this same feature, which uses a
tempfile-then-rename specifically to avoid partial/failed writes. If it does raise,
the exception propagates out of `report_fidelity` → `run` → into
`build_single_target`'s `rescue => e` in `lib/spm_cache/installer/build.rb:177-183`,
where it is indistinguishable from a genuine build failure — including engaging
`ignore_build_errors?` handling. A build that already succeeded (the xcframework is
on disk and usable) would then be reported to the user as a failed target purely
because a small metadata write hit a disk error, which is both misleading and
exactly the kind of masking Pitfall 2 was meant to prevent (just via a different
code path than the one the comment anticipated).

**Fix:** Either make the sidecar write atomic (tempfile + rename, mirroring
`ResolvedGraph.atomic_write`) and/or wrap it so a write failure degrades to a
warning instead of raising, e.g.:
```ruby
def write_provenance_sidecar(output_path, status:, pins:, config:, destinations:)
  File.write("#{output_path}.provenance.json", JSON.generate(...))
rescue SystemCallError => e
  Core::UI.warn "  could not write provenance sidecar for #{File.basename(output_path)}: #{e.message}"
end
```

## Info

### IN-01: Redundant `.provenance.json` cleanup in `copy_prebuilt_binary_target`

**File:** `lib/spm_cache/spm/build_pipeline.rb:1007-1010`
**Issue:**
```ruby
# Same rationale as the .shims.json rm_f immediately above: a
# pre-Class-E cache entry may carry a stale provenance sidecar from
# when this product was still built via the normal path.
FileUtils.rm_f("#{output_path}.provenance.json")
```
Unlike the `.shims.json` cleanup on the preceding line (which *is* needed, since
nothing else touches that sidecar for the Class E path), this `.provenance.json`
`rm_f` is dead weight: `perform_build`'s return always flows back into `run`, which
unconditionally calls `report_fidelity` afterward — and `report_fidelity` either
`FileUtils.rm_f`s the same path again (`seeded == false`) or fully overwrites it via
`write_provenance_sidecar` (`seeded == true`, `File.write` truncates). Either way the
final state of `output_path.provenance.json` after `run` returns is entirely
determined by `report_fidelity`'s consolidated insertion point, making this earlier
`rm_f` unreachable-in-effect and the accompanying comment's stated rationale
("Same rationale as the .shims.json rm_f") inaccurate for this specific line — it
gives future readers false confidence that removing it here matters.

**Fix:** Remove the redundant `FileUtils.rm_f("#{output_path}.provenance.json")` at
line 1010 (keep the `.shims.json` one), or add a one-line comment noting it's
belt-and-suspenders only if intentionally kept for defense-in-depth.

---

_Reviewed: 2026-08-29T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep_
