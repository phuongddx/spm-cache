---
title: Testing Patterns
focus: quality
mapped_date: 2026-08-23
last_mapped_commit: f55b9b9a7dc73104b490ed76ec38549b242af03e
---

# Testing Patterns

**Analysis Date:** 2026-08-23

## Test Framework

**Runner:**
- RSpec ~> 3.12
- Config: none (default RSpec configuration, no `spec/spec_helper.rb` beyond the basic file)
- Dev dependency in `Gemfile` and `spm_cache.gemspec`

**Assertion Library:**
- RSpec built-in matchers (`expect`, `be true`, `eq`, `include`, `match`, `raise_error`, `output(...).to_stdout`, `all`) 

**Run Commands:**
```bash
bundle exec rspec              # Run all Ruby tests
make test                      # Same (Makefile alias)
bundle exec rubocop            # Lint (not tests)
```

**CI:**
- `.github/workflows/ci.yml` — runs `bundle exec rspec` on `macos-15` with Ruby matrix [3.1, 3.2, 3.3]
- Also runs Swift tests for `tools/spm-cache-proxy` in a separate job
- Uses `actions/checkout@v5`

## Test File Organization

**Location:** All specs in `spec/` directory at project root (not co-located with source)

**Naming:** `<subject>_spec.rb` — matches the class or module under test
- `spec/core_spec.rb` → `SPMCache::Core::Sh`, `SPMCache::Core::UI`
- `spec/config_spec.rb` → `SPMCache::Core::Config`
- `spec/watch_spec.rb` → `SPMCache::Core::Watcher`, `SPMCache::Command::Watch`
- `spec/buildable_spec.rb` → `SPMCache::SPM::Buildable`
- `spec/build_pipeline_spec.rb` → `SPMCache::SPM::BuildPipeline`
- `spec/init_spec.rb` → `SPMCache::Command::Init`
- `spec/doctor_spec.rb` → `SPMCache::Core::Diagnostics`, `SPMCache::Command::Doctor`

**Structure:**
```
spec/
├── spec_helper.rb              # Shared setup (requires spm_cache/main)
├── core_spec.rb                # Core::Sh + Core::UI
├── config_spec.rb              # Core::Config singleton
├── watch_spec.rb               # Core::Watcher + Command::Watch
├── init_spec.rb                # Command::Init
├── doctor_spec.rb              # Core::Diagnostics + Command::Doctor
├── buildable_spec.rb           # SPM::Buildable (framework creation)
├── build_pipeline_spec.rb      # SPM::BuildPipeline (argument assembly)
├── installer_build_spec.rb     # Installer::Build (target selection)
├── installer_integrate_proxy_spec.rb  # Installer proxy integration
├── installer_use_fast_path_spec.rb    # Installer::Use fast-path logic
├── installer_spec.rb           # Installer base
├── installer_retry_umbrella_resolve_spec.rb
├── installer_consumed_dependencies_spec.rb
├── gen_proxy_cache_only_spec.rb
├── gen_proxy_ignore_spec.rb
├── gen_proxy_field_regression_spec.rb
├── gen_proxy_products_spec.rb
├── gen_proxy_plugin_spec.rb
├── gen_proxy_root_build_regression_spec.rb
├── desc_target_spec.rb         # SPM::Desc::Target
├── desc_product_spec.rb        # SPM::Desc::Product
├── xcframework_spec.rb         # XCFramework creation
├── diff_detector_spec.rb       # Core::DiffDetector
├── lockfile_spec.rb            # Core::Lockfile
├── lockfile_enrichment_spec.rb
├── checkout_enrichment_sequencing_spec.rb
├── cachemap_spec.rb            # Cache::Cachemap
├── proxy_executable_spec.rb    # SPM::Package::ProxyExecutable
└── installer_rollback_spec.rb
```

## Test Structure

**Suite organization follows RSpec idioms:**

```ruby
RSpec.describe SPMCache::Core::Watcher do
  let(:tmpdir) { Dir.mktmpdir }        # Shared mutable state
  let(:project_path) { ... }

  before do                            # Setup
    FileUtils.mkdir_p(...)
    File.write(...)
  end

  after { FileUtils.remove_entry(tmpdir) }  # Teardown

  # Helper methods for test-specific object creation
  def make_installer(should_fail: false)
    inst = FakeInstaller.new(should_fail: should_fail)
    [inst, ->(_path) { inst }]
  end

  it 'describes the expected behavior' do
    # Arrange + Act + Assert in one block
  end

  it 'continue-on-error: logs a transient failure and keeps the loop contract' do
    # Descriptive names with context
  end
end
```

**Multi-class specs:** Some spec files test multiple related classes (e.g., `spec/watch_spec.rb` has `RSpec.describe SPMCache::Core::Watcher` and `RSpec.describe SPMCache::Command::Watch`). The secondary class spec goes in the same file when the classes are tightly coupled.

**Nested contexts:**
```ruby
describe "#should_ignore?" do
  context "with empty ignore list" do
    before { config.raw["ignore"] = [] }
    it "ignores nothing" do ...
  end
end
```

## Spec Helper

**`spec/spec_helper.rb` is minimal:**
```ruby
require "spm_cache/main"

RSpec.describe SPMCache do
  it "has a version" do
    expect(SPMCache::VERSION).to match(/\d+\.\d+\.\d+/)
  end
  # ... basic sanity checks
end
```

**No shared examples, no custom matchers, no shared contexts.** Each spec file is self-contained with its own `require 'spec_helper'`.

## Mocking and Stubbing

**Framework:** RSpec built-in (`allow`, `receive`, `instance_double`, `expect`). No external mocking libraries.

### Shell-Out Stubbing

The primary concern is preventing `Core::Sh` from running real commands (xcodebuild, swift, etc.):

```ruby
# Stub Core::Sh.run entirely
allow(SPMCache::Core::Sh).to receive(:run) do |cmd, _opts = {}|
  captured_cmds << cmd
  { output: "", status: 0 }
end
```

### Instance-Level Stubbing with `allow_any_instance_of`

Used for installer tests where the class under test has deep internal dependencies:

```ruby
allow_any_instance_of(SPMCache::Installer).to receive(:perform_install).and_wrap_original do |original, *args, &block|
  me = original.receiver
  me.instance_variable_set(:@cachemap, cachemap)
  nil
end
allow_any_instance_of(SPMCache::Installer::Build).to receive(:resolve_umbrella_checkouts).and_return(nil)
allow_any_instance_of(SPMCache::Installer::Build).to receive(:checkout_map).and_return({})
allow_any_instance_of(SPMCache::Installer::Build).to receive(:build_single_target).and_return(nil)
```

### Factory Injection (Dependency Injection)

The watcher uses constructor injection for testability — no stubbing needed for the core loop:

```ruby
# Production
watcher = Core::Watcher.new(
  project_path: project_path,
  installer_factory: ->(path) { Installer::Use.new(project: path) },
  out: $stdout
)

# Test
def make_installer(should_fail: false)
  inst = FakeInstaller.new(should_fail: should_fail)
  [inst, ->(_path) { inst }]
end
watcher = described_class.new(project_path: project_path, installer_factory: factory, out: StringIO.new)
```

### `instance_double` for Complex Objects

```ruby
fake_desc = instance_double(SPMCache::SPM::Desc::Description)
allow(SPMCache::SPM::Desc::Description).to receive(:new).and_return(fake_desc)
allow(fake_desc).to receive(:products).and_return(...)
```

### Fake Classes (Test Doubles)

Defined inline in spec files when a simple interface needs to be faked:

```ruby
class FakeInstaller
  attr_reader :call_count, :last_project
  def initialize(should_fail: false)
    @should_fail = should_fail
    @call_count = 0
  end
  def perform_install
    @call_count += 1
    raise StandardError, 'simulated build failure' if @should_fail
  end
end
```

### IO Capture

```ruby
# Capture stdout for commands that call puts directly
out = StringIO.new
original_stdout = $stdout
$stdout = out
begin
  cmd.run
ensure
  $stdout = original_stdout
end
parsed = out.string

# Or use RSpec's output matcher
expect { described_class.info("test") }.to output("test\n").to_stdout
expect { described_class.warn("danger") }.to output("[warn] danger\n").to_stderr
```

### Singleton Reset

The `Core::Config` singleton must be reset between tests:

```ruby
before do
  config.reset!
  config.project_dir = "/tmp/test-project"
end
```

## What to Mock

- **`Core::Sh.run` / `Core::Sh.capture_output`** — never run real shell commands in tests
- **`SPM::Buildable.new`** — stub construction to prevent xcodebuild invocation
- **`SPM::Desc::Description.new`** — stub to avoid `swift package describe` shell-out
- **`Installer#perform_install`** — stub to isolate target-selection logic from the full pipeline
- **`Core::Config.instance`** — use `reset!` + direct attribute assignment, not full mock
- **`exit`** — stub `exit` on commands that call it (e.g., `allow_any_instance_of(Command::Doctor).to receive(:exit).and_return(nil)`)

## What NOT to Mock

- **File I/O** — tests use real temp directories (`Dir.mktmpdir`) and real file operations. This is deliberate: the config, lockfile, diff detector, and watcher all work with real files on disk in tests.
- **`Core::UI`** — output is captured via `$stdout`/`$stderr` redirection or `StringIO` injection, not mocked
- **`Core::Error` / `GeneralError`** — real error classes are used; `expect { ... }.to raise_error(SPMCache::Core::GeneralError)` tests real error flow

## Temp Directory Pattern

Almost every spec uses temp directories for isolation:

```ruby
let(:tmpdir) { Dir.mktmpdir }
before { FileUtils.mkdir_p(File.join(tmpdir, 'App.xcodeproj')) }
after { FileUtils.remove_entry(tmpdir) if File.directory?(tmpdir) }
```

For `Dir.chdir` tests, use the block form to auto-restore:

```ruby
Dir.mktmpdir do |empty_dir|
  Dir.chdir(empty_dir) do
    expect { cmd.run }.to raise_error(...)
  end
end
```

## Coverage

**No enforced coverage target.** No `simplecov` or similar gem in the gemspec or Gemfile.

## Test Types

**Unit Tests:**
- All Ruby specs are unit tests. They test individual classes/methods in isolation.
- Build pipeline tests stub all shell-outs and test argument assembly only
- No real xcodebuild, swift, or Xcode operations in any spec

**Integration Tests:**
- Not present. The `build_pipeline_spec.rb` explicitly states: "Correctness beyond argument assembly is only covered by the manual end-to-end check."

**E2E Tests:**
- Not present for Ruby code. The Swift companion (`tools/spm-cache-proxy`) has its own RSpec-free Swift test suite in `Tests/spm-cache-proxyTests/`, run via `swift test` in CI.

## Common Patterns

**Async/Long-Running Testing:**
```ruby
# The watcher's poll loop is tested by:
# 1. Testing run_once directly (synchronous)
# 2. Testing signature detection without the loop
# 3. Testing error recovery by verifying a fresh watcher recovers
#
# The actual loop (Watch#run) is NOT tested in a blocking loop.
current = watcher.send(:current_signatures)
expect(current).not_to eq(watcher.instance_variable_get(:@last_signatures))
```

**Error Testing:**
```ruby
# Expected error
expect { described_class.run("false") }.to raise_error(SPMCache::Core::GeneralError)

# Error with message content
expect { cmd.run }.to raise_error(SPMCache::Core::GeneralError, /No \.xcodeproj found/)

# Error with stdout content match
expect { described_class.run("echo 'the real error is here' && false") }
  .to raise_error(SPMCache::Core::GeneralError, /the real error is here/)

# Continue-on-error verification
expect { watcher.run_once }.to raise_error(StandardError, /simulated build failure/)
```

**Output Testing:**
```ruby
expect { cmd.perform_install }.to output(%r{Building 2 target.*Alamofire.*SnapKit}m).to_stdout
expect { ... }.to output(/unknown target 'Nonexistent'/).to_stderr
```

**Registry Testing (Diagnostics):**
```ruby
it 'registers built-in checks' do
  names = described_class.registry.map(&:name)
  expect(names).to include('xcode_version', 'swift_version', ...)
end

it 'captures a check that raises as a :fail' do
  saved = described_class.registry.dup
  begin
    described_class.instance_variable_set(:@registry, [])
    described_class.register('boom', fix_hint: 'fix it') { raise 'kaboom' }
    results = described_class.run_all(config: nil)
    expect(results.find { |r| r.name == 'boom' }.status).to eq(:fail)
  ensure
    described_class.instance_variable_set(:@registry, saved)
  end
end
```

---

*Testing analysis: 2026-08-23*
