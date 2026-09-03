---
title: Testing Patterns
focus: quality
mapped_date: 2026-08-31
last_mapped_commit: fdb3a70abe81852ec9310a3ff410341a4adcfa0c
---

<!-- refreshed: 2026-08-31 -->

# Testing Patterns

**Analysis Date:** 2026-08-31

## Test Framework

**Runner:**
- RSpec ~> 3.12 (dev dependency in both `spm_cache.gemspec` and `Gemfile`)
- Config: none beyond `spec/spec_helper.rb` (default RSpec configuration, no `.rspec`, no custom rspec config)
- Suite size at v0.4.0: **49 spec files, 441 examples, 0 failures**

**Assertion Library:**
- RSpec built-in matchers (`expect`, `eq`, `include`, `match`, `raise_error`, `output(...).to_stdout/.to_stderr`, `all`, `be_nil`, `be_a`)

**Run Commands:**
```bash
bundle exec rspec                        # Run all tests
bundle exec rspec spec/<file>_spec.rb    # Single file
make test                                # Makefile alias for bundle exec rspec
make proxy.build                         # Build tools/spm-cache-proxy (needed before tier-3 specs run non-skipped)
bundle exec rubocop                      # Lint (not tests)
```

**CI:**
- `.github/workflows/ci.yml` — `ruby-tests` job on `macos-15`, Ruby matrix ['3.1', '3.2', '3.3'], Xcode 16, `actions/checkout@v5`
- The Ruby job **builds the proxy first** (`make proxy.build`) before `bundle exec rspec`, so the tier-3 real-binary specs run non-skipped in CI
- Separate `swift-tests` job runs `swift test` for `tools/spm-cache-proxy` in `Tests/spm-cache-proxyTests/`
- Workflow-level `concurrency` group with `cancel-in-progress: true`; `permissions: contents: read`
- `.github/workflows/update-tap.yml` (Homebrew tap publish) is NOT run as a test by CI — it is pinned structurally by `spec/update_tap_workflow_spec.rb`

## Test File Organization

**Location:** All specs in `spec/` at project root (not co-located with source). Shared JSON fixtures in `spec/fixtures/`.

**Naming — four patterns:**
1. **Class-mirroring** (`<subject>_spec.rb`): `spec/package_resolved_spec.rb` → `SPMCache::Core::PackageResolved`, `spec/resolved_graph_spec.rb` → `SPMCache::SPM::ResolvedGraph`, `spec/command_cache_list_spec.rb` → `SPMCache::Command::Cache::List`
2. **Aspect specs** (`<subject>_<aspect>_spec.rb`): `spec/build_pipeline_seeding_spec.rb` (host-graph seeding), `spec/build_pipeline_provenance_spec.rb` (provenance sidecars), `spec/doctor_lock_fidelity_spec.rb` (doctor's lock-fidelity check), `spec/lockfile_reconciliation_spec.rb` (Installer::Use lockfile reconciliation)
3. **Structural YAML specs** (named after the non-Ruby artifact under test): `spec/action_spec.rb` pins `action/action.yml`; `spec/update_tap_workflow_spec.rb` pins `.github/workflows/update-tap.yml`
4. **Behavior umbrella specs** (named after the behavior, not a class): `spec/build_lock_spec.rb` ("process-level build lock"), `spec/fidelity_drift_regression_spec.rb`, `spec/fidelity_bucket_partition_spec.rb`, `spec/fidelity_edge_matrix_spec.rb`

**Structure:**
```
spec/
├── spec_helper.rb                       # Minimal: requires spm_cache/main, 3 sanity examples
├── fixtures/
│   ├── fidelity-kitchen-sink-lockfile.json   # All-classes synthetic lockfile (TEST-02 universe)
│   ├── field-regression-lockfile.json
│   ├── plugin-lockfile.json
│   ├── products-lockfile.json
│   └── ignore-lockfile.json
├── core_spec.rb                         # Core::Sh + Core::UI
├── config_spec.rb                       # Core::Config singleton
├── main_version_spec.rb                 # SPMCache::Main + VERSION wiring
├── action_spec.rb                       # action/action.yml structure + flag cross-reference
├── update_tap_workflow_spec.rb          # .github/workflows/update-tap.yml REL-04..09 invariants
├── watch_spec.rb                        # Watcher unit behavior (run_once, signatures)
├── watch_loop_spec.rb                   # Watcher loop contract (subprocess)
├── watch_signals_spec.rb                # Watcher signal handling (subprocess)
├── build_lock_spec.rb                   # Process-level flock contract
├── init_spec.rb                         # Command::Init
├── doctor_spec.rb                       # Core::Diagnostics + Command::Doctor
├── doctor_lock_fidelity_spec.rb         # Doctor's Package.resolved fidelity check
├── doctor_companion_version_spec.rb     # spm-cache-proxy --version (binary-gated)
├── command_cache_list_spec.rb           # Command::Cache::List
├── command_cache_clean_spec.rb          # Command::Cache::Clean
├── buildable_spec.rb                    # SPM::Buildable
├── build_pipeline_spec.rb               # SPM::BuildPipeline argument assembly
├── build_pipeline_seeding_spec.rb       # Host-graph seeding (Phase 7)
├── build_pipeline_provenance_spec.rb    # Provenance sidecar write/read-back (Phase 8)
├── resolved_graph_spec.rb               # SPM::ResolvedGraph
├── package_resolved_spec.rb             # Core::PackageResolved locator
├── checkout_enrichment_sequencing_spec.rb
├── lockfile_spec.rb                     # Core::Lockfile
├── lockfile_enrichment_spec.rb
├── lockfile_reconciliation_spec.rb      # Installer::Use lockfile reconciliation
├── diff_detector_spec.rb                # Core::DiffDetector
├── cachemap_spec.rb                     # Cache::Cachemap
├── xcframework_spec.rb                  # XCFramework creation
├── desc_target_spec.rb                  # SPM::Desc::Target
├── desc_product_spec.rb                 # SPM::Desc::Product
├── proxy_executable_spec.rb             # SPM::Package::ProxyExecutable
├── installer_spec.rb                    # Installer base
├── installer_build_spec.rb              # Installer::Build target selection
├── installer_use_fast_path_spec.rb      # Installer::Use fast path
├── installer_integrate_proxy_spec.rb    # Proxy integration
├── installer_retry_umbrella_resolve_spec.rb
├── installer_consumed_dependencies_spec.rb
├── gen_proxy_cache_only_spec.rb
├── gen_proxy_ignore_spec.rb
├── gen_proxy_field_regression_spec.rb
├── gen_proxy_products_spec.rb
├── gen_proxy_plugin_spec.rb
├── gen_proxy_root_build_regression_spec.rb
├── gen_proxy_provenance_spec.rb         # Provenance-aware cache identity (real-binary smoke)
└── fidelity_drift_regression_spec.rb    # TEST-01 drift both directions, both injection sources
└── fidelity_bucket_partition_spec.rb    # TEST-02 zero/double-bucket partition over kitchen-sink universe
└── fidelity_edge_matrix_spec.rb         # TEST-03 all 8 v0.2.x edge classes
```

Note: `installer_rollback_spec.rb` no longer exists (removed during v0.4.0; rollback flows are covered inside the installer specs). `watch_spec.rb` was split: unit behavior stays there, while the poll-loop contract and signal handling moved to subprocess-based `watch_loop_spec.rb` and `watch_signals_spec.rb`.

## Test Structure

**Suite organization follows RSpec idioms. Every spec file opens with a header comment block stating the regression contract it pins** — what must hold, which phase/requirement it came from, and which seams are stubbed:

```ruby
# frozen_string_literal: true

require "spec_helper"

# TEST-01 regression contract: an out-of-range transitive pin is detected and
# reported, never silently re-resolved -- pinned in BOTH assertion directions
# (drift MUST warn; agreeing pins MUST NOT warn) and from BOTH drift-injection
# sources ...
RSpec.describe SPMCache::SPM::BuildPipeline, "TEST-01: transitive-version drift regression (read-back + provenance)" do
  let(:tmpdir) { Dir.mktmpdir }
  ...
end
```

**Multi-class specs:** tightly coupled classes share one file (e.g., `spec/core_spec.rb` tests `Core::Sh` and `Core::UI`). Multiple `RSpec.describe` blocks per file are fine — `spec/fidelity_drift_regression_spec.rb` has one block per drift-injection source (tier-1 seam, then tier-3 real binary).

**Nested contexts:** `describe "#method"` / `context "with condition"` as before.

**Parametrized in-spec runners:** specs define helper methods that install a stub and drive the real production path, then reuse them across examples:

```ruby
# spec/fidelity_drift_regression_spec.rb
def run_with_realized_pins(realized)
  fake_buildable = instance_double(SPMCache::SPM::Buildable)
  allow(SPMCache::SPM::Buildable).to receive(:new).and_return(fake_buildable)
  allow(fake_buildable).to receive(:build_for_destination) do |*_args, **_kwargs|
    # writes the realized Package.resolved, or deletes it when realized is nil
    ...
  end
  described_class.run(name: "SomePkg", pkg_dir: pkg_dir, ...)
end
```

## Hermeticity (v0.4.0 Standard)

**All specs are hermetic — no network, no real xcodebuild/swift, ever.** Three mechanisms enforce this:

**1. Default-deny `Core::Sh` guard.** Both `Core::Sh` entry points are stubbed to RAISE on any invocation that survives the object stubs — turning "zero real shell-outs" into an executable assertion:

```ruby
# Armed in `before`; present in the fidelity specs and build_pipeline_provenance_spec.rb
allow(SPMCache::Core::Sh).to receive(:run) do |cmd, *_opts|
  raise "unexpected real invocation: Sh.run(#{cmd.inspect})"
end
allow(SPMCache::Core::Sh).to receive(:capture_output) do |cmd, *_opts|
  raise "unexpected real invocation: Sh.capture_output(#{cmd.inspect})"
end
```

Examples that legitimately need a specific tool (the edge-matrix shim/resource legs' libtool/swiftc) **re-allow exactly those command prefixes on top** of the default-deny guard; everything else still raises.

**2. Tier-3 real-binary specs skip when unbuilt.** Specs that exercise the compiled Swift proxy locate it at `tools/spm-cache-proxy/.build/release/spm-cache-proxy` and skip cleanly:

```ruby
let(:binary) do
  local = SPMCache::ROOT.join("tools", "spm-cache-proxy", ".build", "release", "spm-cache-proxy").to_s
  File.executable?(local) ? local : nil
end
before { skip "spm-cache-proxy binary not built (run make proxy.build)" unless binary }
```

Tier-3 legs invoke the binary via plain `system()` with output to `File::NULL` — never `Core::Sh`, so the guard stays armed (and silent) during those legs.

**3. No-circularity rule.** Every `File.write` in specs writes fixture INPUTS (Package.resolved, lockfiles, sidecars, stub frameworks); expected values are typed contract expectations, never generated from system output.

## Spec Helper

**`spec/spec_helper.rb` is minimal** (unchanged pattern): requires `spm_cache/main`, asserts `SPMCache::VERSION` shape and that `SPMCache::ROOT` resolves to the repo root (checks `lib/spm_cache.rb` and `tools/spm-cache-proxy` exist under it).

**No shared examples, no custom matchers, no shared contexts.** Each spec file is self-contained with its own `require 'spec_helper'`. Cross-file reuse happens by copying the documented stub seam (the fidelity specs explicitly say they stub "exactly as in spec/build_pipeline_provenance_spec.rb").

## Mocking and Stubbing

**Framework:** RSpec built-in (`allow`, `receive`, `instance_double`, `expect`, `and_wrap_original`). No external mocking libraries.

### The Tier-1 Stub Seam (fidelity/provenance specs)

The canonical object-stub seam for driving the REAL `BuildPipeline.run` (including `report_fidelity` and `seed_host_graph`) while keeping everything hermetic:
- `SPMCache::SPM::Desc::Description.new` → `instance_double` with stubbed `fetch`, `products`, `raw`
- `SPMCache::SPM::Buildable.new` → `instance_double` with stubbed `build_for_destination` (returns the artifact hash) and `create_framework` (materializes a stub `.framework` directory)
- `SPMCache::SPM::XCFramework::XCFramework.new` → double with stubbed `build`
- `Core::Sh` → default-deny guard (above)
- **Real:** the filesystem (`Package.resolved`, provenance sidecars), and `BuildPipeline.run` itself

### Drift-Injection Idiom

The stubbed `build_for_destination` **rewrites `pkg_dir/Package.resolved` in place** before returning, modeling a silently re-resolved pin — the proven way to inject drift into the read-back path:

```ruby
allow(fake_buildable).to receive(:build_for_destination) do |*_args, **_kwargs|
  write_resolved(File.join(pkg_dir, "Package.resolved"), "SomePkg", "bbb222")  # seed said aaa111
  { derived_data: "/dd", object_file: "/dd/SomePkg.o", swiftmodule: nil, ... }
end
```

### Plain Shell-Out Stubbing (legacy style, still valid)

```ruby
allow(SPMCache::Core::Sh).to receive(:run) do |cmd, _opts = {}|
  captured_cmds << cmd
  { output: "", status: 0 }
end
```

### Instance-Level Stubbing with `allow_any_instance_of`

Still used for installer tests with deep internal dependencies (`perform_install` wrap to inject `@cachemap`, stub `resolve_umbrella_checkouts`, `checkout_map`, `build_single_target`).

### Factory Injection (Dependency Injection)

The watcher takes an `installer_factory:` Proc — no stubbing needed for the core loop; tests inject `FakeInstaller`-returning factories and an `out: StringIO.new`.

### `instance_double` for Complex Objects

`instance_double(SPMCache::SPM::Desc::Description)` with `allow(fake_desc).to receive(:products).and_return(...)` — as in the tier-1 seam.

### Fake Classes (Test Doubles)

Defined inline (`FakeInstaller`, watcher's `SelfWritingInstaller`/`RecordingInstaller`/`VerifyingInstaller` child installers in `watch_loop_spec.rb`).

### IO Capture

```ruby
expect { described_class.run(...) }
  .to output(/resolution-incompatible/).to_stdout
  .and output(/SomePkg.*aaa111.*bbb222/).to_stderr
```

### Singleton Reset

```ruby
before do
  config.reset!
  config.project_dir = "/tmp/test-project"
end
```

## What to Mock

- **`Core::Sh.run` / `Core::Sh.capture_output`** — default-deny guard raising on unexpected invocation (v0.4.0 style); plain capture stubs remain valid where shell commands are incidental
- **`SPM::Desc::Description`, `SPM::Buildable`, `XCFramework`** — the tier-1 seam trio; stub construction to keep the seam hermetic
- **`Installer#perform_install`** — stub to isolate target-selection logic
- **`Core::Config.instance`** — `reset!` + direct attribute assignment
- **`exit`** — stub on commands that call it

## What NOT to Mock

- **File I/O** — real temp directories and real files; Package.resolved and provenance sidecars are written and read back with `JSON.parse` in tests
- **`Core::UI`** — captured via RSpec `output` matcher or injected `StringIO`
- **`BuildPipeline.run` / `report_fidelity`** — stays real in the fidelity specs; stubbing it would defeat the contract under test
- **`Core::Error` / `GeneralError`** — real error classes, real raise paths

## Temp Directory Pattern

Almost every spec uses temp directories for isolation:

```ruby
let(:tmpdir) { Dir.mktmpdir }
before { FileUtils.mkdir_p(pkg_dir) }
after  { FileUtils.rm_rf(tmpdir) }
```

Block-form `Dir.mktmpdir { |dir| Dir.chdir(dir) { ... } }` for chdir tests.

## Coverage

**No enforced coverage target.** No `simplecov` or similar gem. Coverage discipline is enforced by the fidelity regression specs instead: `fidelity_bucket_partition_spec.rb` asserts completeness (zero-bucket) + disjointness (double-bucket) of fidelity classification over the declared package universe (`spec/fixtures/fidelity-kitchen-sink-lockfile.json` + the tier-1 legs' pin identities), so an unclassified resolution outcome fails the suite.

## Test Types

**Unit Tests:** All class-level specs; argument assembly, target selection, locator precedence, sidecar schema — all shell-outs stubbed.

**Fidelity Regression Specs (v0.4.0):** `spec/fidelity_drift_regression_spec.rb` (TEST-01: drift detected in both assertion directions, injected from both sources — resolution read-back AND provenance-sidecar disagreement), `spec/fidelity_bucket_partition_spec.rb` (TEST-02: hybrid two-surface observation — `report_fidelity` sidecars via the tier-1 seam AND compiled-proxy `graph.json` via tier-3), `spec/fidelity_edge_matrix_spec.rb` (TEST-03: all 8 v0.2.x edge classes — binary target, narrow swift-syntax macro pin, vendored `.xcodeproj`, plugin-only, transitive-only, resource bundle, private Clang shim, product-not-equal-target rename — tier-1 legs under the default-deny guard, tier-3 legs via local proxy). Combined runtime ≈ 0.89s.

**Subprocess Integration Tests:** `spec/watch_loop_spec.rb` and `spec/watch_signals_spec.rb` run the REAL `Core::Watcher#run` in a spawned child Ruby process — never inside the RSpec process (a blocking loop cannot be tested there). Pattern:
- Child script built as a heredoc constant (`LOOP_CHILD_SCRIPT`), written to tmpdir, run via `Process.spawn(RbConfig.ruby, '-I', lib, script, ...)`
- Every child interaction bounded by `Timeout.timeout(15)` with a `Process.kill('KILL')` fallback in `ensure`
- Child communicates via a marker file; parent polls with `wait_for_marker(count)` (10s deadline)
- Modes select child installer behavior (`self_write`, `record`, `verify`) to model self-trigger, burst collapse, mid-watch deletion

**Real-Binary Smoke Tests (tier-3):** `spec/gen_proxy_provenance_spec.rb` (provenance-aware cache identity: no-provenance upgrade miss, partial invalidation, cross-project identity), `spec/doctor_companion_version_spec.rb` (companion `--version`) — run the actual compiled `spm-cache-proxy`; skip if not built.

**Structural YAML Specs:** `spec/action_spec.rb` and `spec/update_tap_workflow_spec.rb` parse composite-action/workflow YAML with strict Psych and pin structure — no execution.

**E2E Tests:** No full end-to-end run of real xcodebuild anywhere in the suite.

## Common Patterns

**Workflow YAML Structural Testing:**
```ruby
let(:workflow) { YAML.safe_load_file('.github/workflows/update-tap.yml', permitted_classes: [], aliases: false) }
let(:triggers) { workflow[true] }   # NOT workflow['on'] — unquoted on: parses as boolean true under Psych
it 'pins the trigger surface' do
  expect(triggers.keys.sort).to eq(%w[release workflow_dispatch])
end
```
Shell-body properties are asserted with **line-anchored regexes over the step text** so a prose comment (`#`-leading line) can never satisfy a structural claim.

**Spec Slicing with Loud Failure:** locate steps/option-blocks by stable markers and `raise` naming the file instead of asserting against nil:

```ruby
def own_option_flags(path)
  start_idx = src.index('def self.options') or
    raise "#{path} defines no own options block — update the cross-reference source list"
  concat_idx = src.index('.concat(super)', start_idx) or
    raise "#{path} composes options without .concat(super) — slice boundary broken"
  src[start_idx...concat_idx].scan(...)
end
```

`spec/action_spec.rb` slices each command file from `def self.options` up to (not including) `.concat(super)` so only the command's OWN flags count, then cross-references them against the GitHub Action inputs — inherited `--config` must stay outside the slice.

**Provenance Sidecar Read-Back:**
```ruby
parsed = JSON.parse(File.read("#{result}.provenance.json"))
expect(parsed["fidelity_status"]).to eq("resolution-incompatible")
expect(parsed["pins"]).to eq("SomePkg" => "bbb222")
```

**Fail-First Discipline (RED-then-GREEN):** New regression specs are proven to fail BEFORE the fix/guard exists — mutation probes (e.g., editing a fixture allowlist, equalizing a drift-injecting line) must make the target example fail "as designed" while the rest of the suite stays green. Phase 10/11 verification records this per headlined invariant; keep the discipline for new regression contracts.

**Error Testing:** unchanged —
```ruby
expect { cmd.run }.to raise_error(SPMCache::Core::GeneralError, /No \.xcodeproj found/)
expect { described_class.run("echo 'the real error is here' && false") }
  .to raise_error(SPMCache::Core::GeneralError, /the real error is here/)
```

**Output Testing:** `output(...).to_stdout` / `.to_stderr` with regexes; drift assertions combine both streams in one expectation (`.and output(...).to_stderr`).

**Registry Testing (Diagnostics):** save/replace `@registry`, register a raising check, assert `:fail` status, restore in `ensure` — unchanged from v0.3.0.

---

*Testing analysis: 2026-08-31*
