---
phase: 10-fidelity-regression-coverage
reviewed: 2026-08-29T16:51:21Z
depth: deep
files_reviewed: 4
files_reviewed_list:
  - spec/fidelity_drift_regression_spec.rb
  - spec/fidelity_bucket_partition_spec.rb
  - spec/fidelity_edge_matrix_spec.rb
  - spec/fixtures/fidelity-kitchen-sink-lockfile.json
findings:
  critical: 0
  warning: 2
  info: 7
  total: 9
status: issues_found
---

# Phase 10: Code Review Report

**Reviewed:** 2026-08-29T16:51:21Z
**Depth:** deep
**Files Reviewed:** 4
**Status:** issues_found

## Summary

Test-only phase (zero production changes confirmed via `git log` — commits adddddbe/85b3a86/d8a5475, ab8a0df/b209c27/1f4dddc, 2f6c885/d2e051e/3f72c1b touch only the four reviewed files). Deep review traced every spec against the production surfaces it drives: `BuildPipeline.run`/`report_fidelity`/`drifted_identities`/`pin_value_map` (lib/spm_cache/spm/build_pipeline.rb), `ResolvedGraph.seed!`/`vendored_xcodeproj?` (lib/spm_cache/spm/resolved_graph.rb), `Core::PackageResolved.pins_or_nil`, `Core::Sh` entry points, `Desc::Product`/`Target`, `FrameworkSlice#copy_resource_bundles` (lib/spm_cache/spm/xcframework/slice.rb), and the Swift companion (`ProxyGenerator.swift`, `Cache.swift` `BinariesCache.hit`, `Lockfile.swift` `pinValue`/`isTransitiveOnly`/`isPluginOnly`, `GenProxy.swift`).

Verification performed (not taken on faith from the SUMMARYs):

- **Executed** `bundle exec rspec` on all three spec files: 32 examples, 0 failures, with the compiled proxy binary present — hermetic, no network, no real xcodebuild/libtool (all tool calls intercepted by stubs).
- **Proved the SC4 guard mechanics empirically**: a default-deny `allow(Sh).to receive(:run) { raise }` followed by a constrained `allow(...).with(/\Alibtool -static -o /)` behaves as an allowlist (constrained stub shadows for matching args, deny fallback otherwise), and `Sh.run!`/`capture_output` route through the stubbed `run` — so both-stubbed entry points genuinely cover all three public entry points in core/sh.rb.
- **Confirmed no false-pass via silent tool failure**: `system(cmd, out: File::NULL, ...)` return values are ignored, but every leg asserts outcomes that fail loudly if the binary dies (missing `graph.json` → ENOENT; partial content → nil status → `eq` failure), and `URL.recreate()` wipes `outputDir` before each gen-proxy run so stale `graph.json` cannot leak across runs.
- **Confirmed the two documented deviations are safe as implemented** (see below).

Both accepted deviations check out against production reality:

1. **10-01 missing-realized-file edge**: `seed_host_graph` unconditionally writes `pkg_dir/Package.resolved` via `ResolvedGraph.seed!` (build_pipeline.rb:56, resolved_graph.rb:36-41), so the only reachable way to present an absent realized file is the stub consuming it (`FileUtils.rm_f`). The asserted contract matches production exactly: `pins_or_nil` returns nil for a missing file, `drifted_identities` returns `[]` on a nil side, and `pins: realized_pin_map || {}` yields `{}` (build_pipeline.rb:139-153, 163-169).
2. **10-03 class 6/8 send-drive**: all three pre-existing FrameworkSlice defects are real — `Desc::Target#resource_paths` is private (`private_method_defined?` → true, so slice.rb:31's `respond_to?` guard is always false), bare `Sh` at slice.rb:64 is a NameError (no `Sh` constant in `FrameworkSlice`/`XCFramework`/`SPM`/`SPMCache`/top-level), and the example never touches the broken assembly path. The `send` calls fail loudly (NoMethodError) if the private methods are renamed, and all assertions land on real parser output and real copied files on disk.

No BLOCKER findings: assertion directions match production output byte-for-byte (warn message format `"<identity>: drift detected (intended X, realized Y)"` on stderr via `Core::UI.warn` → `$stderr`; status line on stdout via `puts`), sidecar `pins` record the REALIZED values, tier-3 statuses (`hit`/`missed`/`ignored`/`excluded`/`plugin`) match the Swift `GraphEntry.Status` enum and the excluded-beats-ignored precedence in ProxyGenerator.swift:121-130, `pinValue` is revision-over-version exactly as the drift legs assume, and the fixture is valid JSON whose `dependencies` consumed-set drives the intended classifications on both the Ruby and Swift sides. The two Warnings are false-assurance risks in spec examples whose titles promise more than their assertions can ever check — not incorrect behavior.

## Critical Issues

_(none)_

## Warnings

### WR-01: The "SC4 hermeticity audit" example is tautological — it cannot fail for any production reason

**File:** `spec/fidelity_edge_matrix_spec.rb:594-601`
**Issue:** The example installs `allow(SPMCache::Core::Sh).to receive(:run) { raise ... }` and then asserts that calling `SPMCache::Core::Sh.run("xcodebuild ...")` raises. `Core::Sh.run` has been fully replaced by the stub before the call, so the example exercises zero production code — the only way it can fail is RSpec itself breaking. It provides no regression signal (delete the guard from every other example and it still passes), yet its name and the 10-03-SUMMARY's "SC4 sweep / hermeticity as an executable assertion" framing present it as assurance that hermeticity is enforced. The real enforcement correctly lives in the per-example guards (verified effective), so this example is pure false assurance.
**Fix:** Either delete the example (the guards speak for themselves in every leg), or anchor it to production: drive a real Ruby path that shells out and expect the raise, e.g.

```ruby
it "SC4: the default-deny guard intercepts a real production shell-out path" do
  allow(SPMCache::Core::Sh).to receive(:run) { |cmd, _| raise "unexpected real invocation: Sh.run(#{cmd.inspect})" }
  # resolve_scheme_fallback legitimately calls Core::Sh.capture_output -> run
  expect { described_class.resolve_scheme_fallback("Foo", pkg_dir) }
    .to raise_error(RuntimeError, /unexpected real invocation/)
end
```

### WR-02: The tier-1 tracer's "exactly one bucket" assertions are self-referential and can never fail

**File:** `spec/fidelity_bucket_partition_spec.rb:301-305`
**Issue:** `collected` is constructed two lines earlier as exactly `[status_read_from_sidecar]` (single `observe_bucket` call with a non-nil value), so `expect(collected.length).to eq(1)` and `expect(collected.first).to eq(status_read_from_sidecar)` are tautologies — true by construction regardless of any production behavior. The example's only real teeth are `parsed.fetch("fidelity_status")` raising when the sidecar omits the key and the `pins` equality. As titled ("a pinned package is observed in exactly one bucket") the partition property is unenforced in this example; the actual enforcement lives entirely in the later SC2 example (which is properly built).
**Fix:** Drop the two self-referential expectations, or replace them with a production-anchored one:

```ruby
status_read_from_sidecar = parsed.fetch("fidelity_status")
expect(status_read_from_sidecar).to be_a(String), "sidecar must record a fidelity_status"
expect(status_read_from_sidecar).not_to be_empty
expect(parsed["pins"]).to eq("Alamofire" => "aaa111")
```

## Info

### IN-01: Tier-1/tier-3 scaffolding duplicated across the three new files

**File:** `spec/fidelity_drift_regression_spec.rb:22-35,200-241`, `spec/fidelity_bucket_partition_spec.rb:41-45,72-91,209-212`, `spec/fidelity_edge_matrix_spec.rb:32-47,400-448`
**Issue:** `binary` let, `write_lockfile`, `write_sidecar`/`seed_cache_hit`, `statuses_from`, `run_gen_proxy`, `stub_desc_products`, and `write_resolved_pins` are copy-pasted (with small divergences — e.g. `stub_desc_products` gained `raw_targets:` in 10-03 only) across the three files and from `gen_proxy_provenance_spec.rb`. Documented as a deliberate flat-spec choice in 10-02-SUMMARY; drift risk grows with each future consumer.
**Fix:** If a fourth fidelity spec lands, extract a `spec/support/fidelity_helpers.rb` (or accept the convention and note it in 10-PATTERNS.md).

### IN-02: Shell-command paths interpolated unescaped into `system(cmd)`

**File:** `spec/fidelity_bucket_partition_spec.rb:202-206,264-265` (also `spec/fidelity_drift_regression_spec.rb:233-235`, `spec/fidelity_edge_matrix_spec.rb:440-442`)
**Issue:** Only `--ignore`/`--cache-only` values are `Shellwords.escape`d; `binary`, `umbrella_dir`, `fixture_lockfile`, `output_dir`, `cache_dir` are interpolated raw into a shell string. Safe today (`Dir.mktmpdir` paths and the repo path contain no whitespace), and it matches the pre-existing `gen_proxy_*` convention — but a repo checkout under a path with spaces makes all tier-3 legs fail spuriously.
**Fix:** Wrap all interpolated path arguments with `Shellwords.escape`, or switch to the array form: `system(binary, "gen-proxy", "--umbrella", umbrella_dir, ..., out: File::NULL, err: File::NULL)`.

### IN-03: Class 8/8 stub artifacts omit `:derived_data`, making a glob CWD-relative

**File:** `spec/fidelity_edge_matrix_spec.rb:286-288`
**Issue:** `build_for_destination` returns `{ object_file: "/dd/..." }` with no `derived_data` key, so `find_framework_companions` computes `Dir.glob(File.join("", "Build", "Products", "*"))` — the relative pattern `Build/Products/*` resolved against whatever directory RSpec runs from. Harmless today (no such directory at repo root; the glob then returns nothing), but the example's hermeticity now depends on the working directory's contents.
**Fix:** Add `derived_data: "/dd"` to the stubbed artifacts hash, matching the sibling legs.

### IN-04: Class 7/8 permits but does not require the libtool invocation

**File:** `spec/fidelity_edge_matrix_spec.rb:250`
**Issue:** `allow(SPMCache::Core::Sh).to receive(:run).with(/\Alibtool -static -o /)` makes the one genuine tool step optional — if production dropped the libtool call (shim binary never produced), every existing assertion still passes (the shim `XCFramework` double fakes `.build`), so the real linkage step is unpinned.
**Fix:** Use `expect(SPMCache::Core::Sh).to receive(:run).with(/\Alibtool -static -o /)` (keep the default-deny `capture_output` stub; no other `Sh.run` call occurs in this leg), or assert the shim binary path exists after the run.

### IN-05: Class 1/8 leaves `actual_destinations_for` narrowing unasserted

**File:** `spec/fidelity_edge_matrix_spec.rb:76-79,118`
**Issue:** The fixture's prebuilt slice directory is `ios-arm64` (device-only) while the run requests `iphonesimulator`, so `actual_destinations_for` correctly narrows the sidecar's `destinations` to `[]` — a real production behavior the example exercises but never asserts. A regression in the narrowing logic would pass unnoticed.
**Fix:** Either add an `ios-arm64-simulator` slice directory and assert `sidecar["destinations"] == ["iphonesimulator"]`, or explicitly pin the current narrowing: `expect(sidecar["destinations"]).to eq([])`.

### IN-06: `write_sidecar`'s `status:` keyword is dead

**File:** `spec/fidelity_drift_regression_spec.rb:225-230`
**Issue:** The `status:` parameter (and the `fidelity_status` key it writes) is never overridden in any call, and `BinariesCache.hit()` reads only `pins` (Cache.swift:28-48) — inert fixture data copied from `gen_proxy_provenance_spec.rb`.
**Fix:** Drop the parameter and the key, or add a leg that varies it if it ever becomes load-bearing.

### IN-07: Meta-spec self-referential probes carry no production regression signal (by design, but worth keeping labeled)

**File:** `spec/fidelity_bucket_partition_spec.rb:379-380,475-480,495-506`
**Issue:** The empty-universe probe (`partition_violations([], {})`), the ordering probe (PkgA/PkgB/PkgC against synthetic store), and `expect(ownership_map.values.count("PrimeKit")).to eq(2)` assert properties of the spec's own helpers/data, not production. They can only fail if the helpers are refactored badly — legitimate for a meta-spec's self-check, but they should not be counted as production coverage when tallying TEST-02.
**Fix:** None required; optionally annotate the describe string (e.g. "SC2 helper mechanics (no production surface)") so coverage reports don't over-credit them.

---

_Reviewed: 2026-08-29T16:51:21Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep_
