# Cache Identity & GC Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace name-keyed cache artifacts with pin-level content-hash-keyed artifacts plus a canonical pointer layer, and add LRU cache hygiene (`cache gc` + opt-in auto-evict).

**Architecture:** Ruby computes a per-dependency 8-hex fingerprint (pins + dep closure + toolchain + build context) and names durable artifacts `{module}-{hash8}.xcframework`. Plain-name symlinks (`{module}.xcframework` + sidecars) preserve the existing lookup contract consumed by Swift `GenProxy` and `Installer::Build#slice_complete?` — the Swift companion is NOT modified. Hygiene lives in a plan/execute-split `Cache::GC` (LRU by sidecar `last_used_at`, Tuist-style 85%→70% watermark, orphan cleanup).

**Tech Stack:** Ruby >= 3.1 gem (CLAide, RSpec), existing `Core::Sh`/`Core::Config` seams. No new runtime deps. No Swift changes.

**Spec:** `docs/superpowers/specs/2026-09-21-cache-identity-gc-design.md`

## Global Constraints

- macOS-only tool; Ruby >= 3.1; `# frozen_string_literal: true` at top of every new `.rb`.
- No new runtime gem dependencies.
- All shell-outs via `Core::Sh` (never backticks/`system`); `Fingerprint.version_line` uses read-only `Open3.capture3` version probes only.
- Fail-open invariant: fingerprint/pointer/eviction failures must never break a build — degrade to source mode or warn.
- Swift companion (`tools/spm-cache-proxy`) unmodified; pointer layer is the only bridge.
- Defaults verbatim: `max_size_gb: 20`, `auto_evict: false`.
- Sidecar `last_used_at` is integer epoch seconds (`Time.now.to_i`).

## Review Focus

Failure modes the spec implies but tasks might miss; each pinned to its owning task's tests:

1. **Fingerprint computation raises mid-run** → build/use still succeed (fail-open). Test: Task 2 (`fail-opens when fingerprinting raises`).
2. **Dangling pointer after eviction** → `use` treats as miss, rebuilds, no crash. Test: Task 3 (`materialize! is a miss when target absent`).
3. **Auto-evict deletes the just-written artifact** → forbidden; current run's hashes protected. Test: Task 7 (protect-set assertion).
4. **Remote sync leaks pointers** → git push strips before add; S3 never follows symlinks. Test: Task 8.
5. **Legacy plain-name artifact silently hits after upgrade** → quarantined to `legacy-{module}.xcframework` (miss) before `gen_proxy`. Test: Task 3 (`quarantine_legacy!`).

---

### Task 1: `Cache::Fingerprint`

**Files:**
- Create: `lib/spm_cache/cache/fingerprint.rb`
- Test: `spec/fingerprint_spec.rb`

**Interfaces:**
- Consumes: `SPMCache::VERSION`; injectable toolchain (no `Core::Config` dependency at this layer).
- Produces (used by Tasks 2, 3, 9):
  - `Fingerprint.for(package:, pin:, dependencies: {}, context:) -> String` — 8 hex chars.
  - `Fingerprint.context(config:, toolchain: nil) -> Hash` — string keys: `sdk, config, destinations, merge_slices, library_evolution, swift_version, xcode_version, spm_cache_version`. `config` responds to `run_sdk/run_config/run_merge_slices/run_library_evolution` (Task 3 adds these to `Core::Config`). `toolchain` = `{swift_version:, xcode_version:}`; nil ⇒ `Fingerprint.toolchain` memoized capture.
  - `Fingerprint.toolchain(swift_version: nil, xcode_version: nil) -> Hash` — memoized; captures `swift --version` / `xcodebuild -version` first lines when args nil.
  - `Fingerprint.pin_data(pin) -> Hash` — normalized `{identity:, version:, branch:, revision:}` from raw Package.resolved pin (tolerant of missing `state`).
  - `Fingerprint.map_for(graph_entries:, pins:, config:, toolchain: nil) -> Hash` — `{"Module" => "hash8"}` bottom-up over `graph_entries` (`[{ "module" => name, "dependencies" => [names] }]`); unknown dep names hash with empty pin.

- [ ] **Step 1: Write failing tests**

```ruby
# spec/fingerprint_spec.rb
# frozen_string_literal: true

require 'spec_helper'
require 'spm_cache/cache/fingerprint'

RSpec.describe SPMCache::Cache::Fingerprint do
  let(:pin) { { 'identity' => 'alamofire', 'state' => { 'version' => '5.9.1', 'revision' => 'abc123' } } }
  let(:toolchain) { { swift_version: '6.0', xcode_version: 'Xcode 16.0' } }
  let(:config_stub) do
    instance_double(SPMCache::Core::Config, run_sdk: 'iphonesimulator', run_config: 'debug',
                                            run_merge_slices: true, run_library_evolution: true)
  end
  let(:context) { described_class.context(config: config_stub, toolchain: toolchain) }

  describe '.for' do
    it 'returns 8 hex chars' do
      expect(described_class.for(package: 'Alamofire', pin: pin, context: context))
        .to match(/\A[0-9a-f]{8}\z/)
    end

    it 'is deterministic across key order' do
      a = described_class.for(package: 'Alamofire', pin: pin, context: context)
      b = described_class.for(package: 'Alamofire', pin: pin, context: context.to_a.to_h)
      expect(a).to eq(b)
    end

    it 'changes when the pin changes' do
      bumped = pin.merge('state' => { 'version' => '5.10.0', 'revision' => 'def456' })
      expect(described_class.for(package: 'Alamofire', pin: bumped, context: context))
        .not_to eq(described_class.for(package: 'Alamofire', pin: pin, context: context))
    end

    it 'changes when swift version changes' do
      other = context.merge('swift_version' => '6.1')
      expect(described_class.for(package: 'Alamofire', pin: pin, context: other))
        .not_to eq(described_class.for(package: 'Alamofire', pin: pin, context: context))
    end

    it 'cascades dependency hash changes upstream' do
      deps = { 'Logging' => '11111111' }
      before = described_class.for(package: 'App', pin: pin, dependencies: deps, context: context)
      after = described_class.for(package: 'App', pin: pin,
                                  dependencies: deps.merge('Logging' => '22222222'), context: context)
      expect(before).not_to eq(after)
    end
  end

  describe '.pin_data' do
    it 'normalizes identity/version/branch/revision tolerantly' do
      expect(described_class.pin_data(pin)).to eq(
        'identity' => 'alamofire', 'version' => '5.9.1', 'branch' => nil, 'revision' => 'abc123'
      )
      expect(described_class.pin_data({ 'identity' => 'x' })).to eq(
        'identity' => 'x', 'version' => nil, 'branch' => nil, 'revision' => nil
      )
    end
  end

  describe '.map_for' do
    it 'hashes bottom-up over graph dependencies' do
      graph = [
        { 'module' => 'Logging', 'dependencies' => [] },
        { 'module' => 'Alamofire', 'dependencies' => ['Logging'] }
      ]
      pins = { 'Logging' => { 'identity' => 'swift-log' }, 'Alamofire' => pin }
      map = described_class.map_for(graph_entries: graph, pins: pins,
                                    config: config_stub, toolchain: toolchain)
      direct = described_class.for(package: 'Logging', pin: pins['Logging'], dependencies: {},
                                   context: context)
      expect(map['Logging']).to eq(direct)
      expect(map['Alamofire']).to match(/\A[0-9a-f]{8}\z/)
    end
  end
end
```

- [ ] **Step 2: Run tests — expect failure**

Run: `bundle exec rspec spec/fingerprint_spec.rb`
Expected: FAIL — uninitialized constant `SPMCache::Cache::Fingerprint`.

- [ ] **Step 3: Implement**

```ruby
# lib/spm_cache/cache/fingerprint.rb
# frozen_string_literal: true

require 'digest/sha2'
require 'json'
require 'open3'

module SPMCache
  module Cache
    # Pin-level content fingerprint for cache identity. Deterministic by
    # construction: canonical JSON (sorted keys), no absolute paths, no
    # mtimes. Toolchain capture is memoized per process unless injected.
    module Fingerprint
      HASH_LENGTH = 8
      @@toolchain_cache = {}

      class << self
        def for(package:, pin:, dependencies: {}, context:)
          payload = {
            'package' => package.to_s,
            'pin' => pin_data(pin),
            'dependencies' => Hash[dependencies.sort],
            'context' => context
          }
          Digest::SHA256.hexdigest(canonical_json(payload))[0, HASH_LENGTH]
        end

        def context(config:, toolchain: nil)
          tc = toolchain || self.toolchain
          {
            'sdk' => config.run_sdk.to_s,
            'config' => config.run_config.to_s,
            'destinations' => destinations_for(config.run_sdk, config.run_merge_slices).sort,
            'merge_slices' => !!config.run_merge_slices,
            'library_evolution' => !!config.run_library_evolution,
            'swift_version' => tc[:swift_version],
            'xcode_version' => tc[:xcode_version],
            'spm_cache_version' => SPMCache::VERSION
          }
        end

        def toolchain(swift_version: nil, xcode_version: nil)
          key = [swift_version, xcode_version]
          @@toolchain_cache[key] ||= {
            swift_version: swift_version || version_line('swift --version'),
            xcode_version: xcode_version || version_line('xcodebuild -version')
          }
        end

        def pin_data(pin)
          pin ||= {}
          state = pin['state'] || {}
          {
            'identity' => pin['identity'] || pin['name'],
            'version' => state['version'] || pin['version'],
            'branch' => state['branch'] || pin['branch'],
            'revision' => state['revision'] || pin['revision']
          }
        end

        # graph_entries: [{ 'module' => name, 'dependencies' => [names] }]
        # pins: { module_name => raw_pin_hash }
        def map_for(graph_entries:, pins:, config:, toolchain: nil)
          ctx = context(config: config, toolchain: toolchain)
          by_name = graph_entries.each_with_object({}) { |e, h| h[e['module']] = e }
          hashes = {}
          resolve = lambda do |name, seen|
            next hashes[name] if hashes[name]
            raise "dependency cycle at #{name}" if seen.include?(name)

            entry = by_name[name]
            dep_map = ((entry && entry['dependencies']) || []).each_with_object({}) do |dep, h|
              h[dep] = resolve.call(dep, seen + [name])
            end
            hashes[name] = for(package: name, pin: pins[name] || {},
                               dependencies: dep_map, context: ctx)
          end
          by_name.each_key { |name| resolve.call(name, []) }
          hashes
        end

        private

        def destinations_for(sdk, merge_slices)
          return %w[iphonesimulator iphoneos] if merge_slices || sdk.to_s == 'all'

          [sdk.to_s]
        end

        # Read-only version probes; same pattern as Core::Diagnostics.
        def version_line(cmd)
          out, = Open3.capture3(cmd)
          out.to_s.lines.first.to_s.strip
        end

        def canonical_json(payload)
          JSON.generate(sort_keys_deep(payload))
        end

        def sort_keys_deep(obj)
          case obj
          when Hash then obj.keys.sort.each_with_object({}) { |k, h| h[k] = sort_keys_deep(obj[k]) }
          when Array then obj.map { |v| sort_keys_deep(v) }
          else obj
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run tests — expect pass**

Run: `bundle exec rspec spec/fingerprint_spec.rb && bundle exec rubocop lib/spm_cache/cache/fingerprint.rb spec/fingerprint_spec.rb`
Expected: PASS / no offenses.

- [ ] **Step 5: Commit**

```bash
git add lib/spm_cache/cache/fingerprint.rb spec/fingerprint_spec.rb
git commit -m "feat(cache): pin-level content fingerprint for cache identity"
```

### Task 2: Hash-named store + provenance sidecar fields

**Files:**
- Modify: `lib/spm_cache/spm/build_pipeline.rb` (`run` signature ~line 58; `write_provenance_sidecar` ~lines 265-281)
- Modify: `lib/spm_cache/installer/build.rb` (build loop in `perform_install`; `build_single_target`)
- Test: `spec/build_pipeline_cache_key_spec.rb`

**Interfaces:**
- Consumes: Task 1 (`Fingerprint.for/map_for/context/pin_data`).
- Produces:
  - `run` new kwargs: `graph_entries: []`, `fingerprint_context: nil`, `pins_override: nil` (test seam; production passes nothing).
  - Stored artifact `{module}-{hash8}.xcframework`; sidecar fields `cache_key`, `cache_key_inputs`, `last_used_at`.
  - `run` return path ends with the hash-suffixed name on success-with-fingerprint; plain name on fail-open.

- [ ] **Step 1: Write failing tests**

```ruby
# spec/build_pipeline_cache_key_spec.rb
# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'
require 'json'
require 'spm_cache/cache/fingerprint'

RSpec.describe SPMCache::SPM::BuildPipeline do
  let(:dir) { Dir.mktmpdir }
  let(:out_dir) { File.join(dir, 'cache') }
  let(:pipeline) { described_class.new }
  let(:pin) { { 'identity' => 'alamofire', 'state' => { 'version' => '5.9.1', 'revision' => 'abc' } } }
  let(:toolchain) { { swift_version: '6.0', xcode_version: 'Xcode 16.0' } }
  let(:config_stub) do
    instance_double(SPMCache::Core::Config, run_sdk: 'iphonesimulator', run_config: 'debug',
                                            run_merge_slices: true, run_library_evolution: true)
  end
  let(:fingerprint_context) do
    SPMCache::Cache::Fingerprint.context(config: config_stub, toolchain: toolchain)
  end

  after { FileUtils.remove_entry(dir) }

  def stub_plain_build(name)
    allow(pipeline).to receive(:perform_build).and_wrap_original do |_m, *_args|
      fw = File.join(out_dir, "#{name}.xcframework")
      FileUtils.mkdir_p(fw)
      fw
    end
  end

  it 'renames the stored artifact and records cache_key inputs' do
    stub_plain_build('Alamofire')
    hash8 = SPMCache::Cache::Fingerprint.for(package: 'Alamofire', pin: pin,
                                             dependencies: {}, context: fingerprint_context)
    result = pipeline.run(name: 'Alamofire', pkg_dir: dir, destinations: ['iphonesimulator'],
                          out_dir: out_dir, config: 'debug',
                          graph_entries: [{ 'module' => 'Alamofire', 'dependencies' => [] }],
                          fingerprint_context: fingerprint_context,
                          pins_override: { 'Alamofire' => pin })
    hashed = File.join(out_dir, "Alamofire-#{hash8}.xcframework")
    expect(File.directory?(hashed)).to be(true)
    expect(result).to eq(hashed)
    sidecar = JSON.parse(File.read("#{hashed}.provenance.json"))
    expect(sidecar['cache_key']).to eq(hash8)
    expect(sidecar['cache_key_inputs']['pin']['version']).to eq('5.9.1')
    expect(sidecar['last_used_at']).to be_a(Integer)
  end

  it 'fail-opens when fingerprinting raises' do
    stub_plain_build('Broken')
    allow(SPMCache::Cache::Fingerprint).to receive(:map_for).and_raise(StandardError.new('boom'))
    result = pipeline.run(name: 'Broken', pkg_dir: dir, destinations: ['iphonesimulator'],
                          out_dir: out_dir, config: 'debug',
                          graph_entries: [], fingerprint_context: fingerprint_context,
                          pins_override: {})
    expect(result).to eq(File.join(out_dir, 'Broken.xcframework'))
    expect(File.directory?(File.join(out_dir, 'Broken.xcframework'))).to be(true)
  end
end
```

- [ ] **Step 2: Run — expect failure**

Run: `bundle exec rspec spec/build_pipeline_cache_key_spec.rb`
Expected: FAIL — unknown keywords `graph_entries/fingerprint_context/pins_override`.

- [ ] **Step 3: Implement (surgical)**

In `run` add the three kwargs. Where the final artifact exists at plain `output_path` (post-assembly, before sidecar writes), insert:

```ruby
# Content-hash rename (spec §2): durable artifact becomes
# {module}-{hash8}.xcframework. Fail-open: fingerprint error keeps the
# plain name (legacy path) and warns — cache must never break a build.
cache_key = nil
cache_key_inputs = nil
begin
  pin_map = pins_override || { name => pin_for_target(resolved_pins_file, name) }
  hashes = Fingerprint.map_for(graph_entries: graph_entries, pins: pin_map,
                               config: fingerprint_config, toolchain: toolchain_from(fingerprint_context))
  cache_key = hashes[name]
  if cache_key
    hash_path = File.join(File.dirname(output_path), "#{name}-#{cache_key}.xcframework")
    FileUtils.rm_rf(hash_path)
    FileUtils.mv(output_path, hash_path)
    output_path = hash_path
    cache_key_inputs = { 'pin' => Fingerprint.pin_data(pin_map[name] || {}),
                         'dependencies' => hashes.reject { |k, _| k == name },
                         'context' => fingerprint_context }
  end
rescue StandardError => e
  Core::UI.warn "  fingerprint failed for #{name}: #{e.message}; storing unhashed"
end
```

Helpers (private, same file): `pin_for_target(resolved_pins_file, name)` reuses the existing pin-map computation already feeding provenance `pins` — extract/reuse it, return the raw pin hash for `name` (or `{}`). `toolchain_from(ctx)` returns `{swift_version: ctx && ctx['swift_version'], xcode_version: ctx && ctx['xcode_version']}` — nil ctx ⇒ nil toolchain ⇒ live capture. `fingerprint_config`: when `fingerprint_context` provided, build a tiny Struct(:run_sdk, :run_config, :run_merge_slices, :run_library_evolution) from its values; otherwise use `Core::Config.instance`.

Extend `write_provenance_sidecar` (line 265) to accept `cache_key: nil, cache_key_inputs: nil` and include them + `last_used_at: Time.now.to_i` in the generated JSON. Thread through all three call sites (~173, ~178, ~197).

In `installer/build.rb`, before `missed.each`:

```ruby
fingerprint_context = Cache::Fingerprint.context(config: @config)
graph_entries = load_graph_entries # graph.json from the prior run; [] when absent
```

`load_graph_entries`: read the exact graph path `gen_cachemap_viz`/`Cachemap` uses (find the constant where viz reads it — likely `@config.proxy_dir/graph.json`); parse JSON array, tolerate absent/malformed → `[]`. Pass both into `build_single_target` → `pipeline.run`.

- [ ] **Step 4: Run — expect pass + regression sweep**

Run: `bundle exec rspec spec/build_pipeline_cache_key_spec.rb spec/build_pipeline_spec.rb spec/build_pipeline_provenance_spec.rb spec/command_build_rebuild_spec.rb`
Expected: new PASS; existing PASS (omitted kwargs keep legacy behavior for `pkg build --out`).

- [ ] **Step 5: Commit**

```bash
git add lib/spm_cache/spm/build_pipeline.rb lib/spm_cache/installer/build.rb spec/build_pipeline_cache_key_spec.rb
git commit -m "feat(cache): store artifacts under content-hash names with cache_key provenance"
```

### Task 3: `Cache::Pointer` + Installer wiring + run-scope config

**Files:**
- Create: `lib/spm_cache/cache/pointer.rb`
- Modify: `lib/spm_cache/core/config.rb` (run-scope accessors + `reset!` hook)
- Modify: `lib/spm_cache/command/base.rb` (set run-scope values from argv)
- Modify: `lib/spm_cache/spm/pkg/proxy.rb` (`prepare`, lines ~29-47)
- Test: `spec/cache_pointer_spec.rb`

**Interfaces:**
- Consumes: Task 1; graph JSON path used by `Cachemap`.
- Produces (used by Tasks 5, 7, 8):
  - `Pointer.refresh_all!(cache_dir:, lockfile_path:, graph_path:, config:, pins_path: nil) -> Hash` (`{module => hash8}` for materialized hits; `{}` on any error — fail-open).
  - `Pointer.materialize!(cache_dir:, module_name:, hash8:) -> bool`.
  - `Pointer.clear_all!(cache_dir) -> Integer` (count of plain-name symlinks removed).
  - `Pointer.quarantine_legacy!(cache_dir) -> Array<String>` (renamed module names).

- [ ] **Step 1: Write failing tests**

```ruby
# spec/cache_pointer_spec.rb
# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'
require 'json'
require 'spm_cache/cache/fingerprint'
require 'spm_cache/cache/pointer'

RSpec.describe SPMCache::Cache::Pointer do
  let(:dir) { Dir.mktmpdir }
  let(:config_stub) do
    instance_double(SPMCache::Core::Config, run_sdk: 'iphonesimulator', run_config: 'debug',
                                            run_merge_slices: true, run_library_evolution: true)
  end
  after { FileUtils.remove_entry(dir) }

  def make_artifact(name, extra_sidecar: {})
    fw = File.join(dir, name)
    FileUtils.mkdir_p(fw)
    File.write("#{fw}.provenance.json", JSON.generate(extra_sidecar))
    fw
  end

  describe '.materialize!' do
    it 'creates plain-name symlinks for artifact and sidecar, touches last_used_at' do
      make_artifact('Alamofire-a1b2c3d4.xcframework')
      expect(described_class.materialize!(cache_dir: dir, module_name: 'Alamofire', hash8: 'a1b2c3d4')).to be(true)
      expect(File.symlink?(File.join(dir, 'Alamofire.xcframework'))).to be(true)
      expect(File.symlink?(File.join(dir, 'Alamofire.xcframework.provenance.json'))).to be(true)
      sidecar = JSON.parse(File.read(File.join(dir, 'Alamofire-a1b2c3d4.xcframework.provenance.json')))
      expect(sidecar['last_used_at']).to be_a(Integer)
    end

    it 'is a miss (false) when the hash target is absent' do
      expect(described_class.materialize!(cache_dir: dir, module_name: 'X', hash8: 'deadbeef')).to be(false)
      expect(File.exist?(File.join(dir, 'X.xcframework'))).to be(false)
    end
  end

  describe '.quarantine_legacy!' do
    it 'renames legacy plain artifacts into misses' do
      make_artifact('Legacy.xcframework')
      expect(described_class.quarantine_legacy!(dir)).to eq(['Legacy'])
      expect(File.directory?(File.join(dir, 'legacy-Legacy.xcframework'))).to be(true)
      expect(File.exist?(File.join(dir, 'legacy-Legacy.xcframework.provenance.json'))).to be(true)
      expect(File.exist?(File.join(dir, 'Legacy.xcframework'))).to be(false)
    end

    it 'leaves hash-suffixed artifacts and pointers alone' do
      make_artifact('Alamofire-a1b2c3d4.xcframework')
      described_class.materialize!(cache_dir: dir, module_name: 'Alamofire', hash8: 'a1b2c3d4')
      expect(described_class.quarantine_legacy!(dir)).to eq([])
      expect(File.symlink?(File.join(dir, 'Alamofire.xcframework'))).to be(true)
    end
  end

  describe '.clear_all!' do
    it 'removes only plain-name symlinks' do
      make_artifact('Alamofire-a1b2c3d4.xcframework')
      described_class.materialize!(cache_dir: dir, module_name: 'Alamofire', hash8: 'a1b2c3d4')
      make_artifact('Keep-99999999.xcframework')
      expect(described_class.clear_all!(dir)).to eq(1)
      expect(File.exist?(File.join(dir, 'Alamofire.xcframework'))).to be(false)
      expect(File.directory?(File.join(dir, 'Alamofire-a1b2c3d4.xcframework'))).to be(true)
      expect(File.directory?(File.join(dir, 'Keep-99999999.xcframework'))).to be(true)
    end
  end

  describe '.refresh_all!' do
    it 'materializes hits and is idempotent' do
      make_artifact('Alamofire-a1b2c3d4.xcframework')
      pins_path = File.join(dir, 'pins.json')
      pin = { 'identity' => 'alamofire', 'state' => { 'version' => '5.9.1', 'revision' => 'abc' } }
      File.write(pins_path, JSON.generate('Alamofire' => pin))
      graph_path = File.join(dir, 'graph.json')
      File.write(graph_path, JSON.generate([{ 'module' => 'Alamofire', 'dependencies' => [] }]))
      toolchain = { swift_version: '6.0', xcode_version: 'Xcode 16.0' }
      expected = SPMCache::Cache::Fingerprint.map_for(
        graph_entries: [{ 'module' => 'Alamofire', 'dependencies' => [] }],
        pins: { 'Alamofire' => pin }, config: config_stub, toolchain: toolchain
      )['Alamofire']
      skip 'fixture/context mismatch guard' unless expected == 'a1b2c3d4'

      result = nil
      Dir.chdir(dir) do
        result = described_class.refresh_all!(cache_dir: dir, lockfile_path: nil,
                                              graph_path: graph_path, config: config_stub,
                                              pins_path: pins_path)
      end
      expect(result).to eq('Alamofire' => 'a1b2c3d4')
      expect(File.symlink?(File.join(dir, 'Alamofire.xcframework'))).to be(true)
      2.times do
        described_class.refresh_all!(cache_dir: dir, lockfile_path: nil, graph_path: graph_path,
                                     config: config_stub, pins_path: pins_path)
      end
      expect(Dir.children(dir).count { |c| c == 'Alamofire.xcframework' }).to eq(1)
    end

    it 'fails open (returns {}) when fingerprinting raises' do
      allow(SPMCache::Cache::Fingerprint).to receive(:map_for).and_raise(StandardError.new('boom'))
      expect(described_class.refresh_all!(cache_dir: dir, lockfile_path: nil, graph_path: nil,
                                          config: config_stub)).to eq({})
    end
  end
end
```

(The `skip unless` guard makes the fixture robust: rename the fixture artifact to the computed `expected` hash before asserting, instead of skipping — implement as `File.rename` setup in the test, then assert the map. Final form: compute `expected` first, create artifact under that hash, then refresh.)

- [ ] **Step 2: Run — expect failure**

Run: `bundle exec rspec spec/cache_pointer_spec.rb`
Expected: FAIL — `SPMCache::Cache::Pointer` undefined.

- [ ] **Step 3: Implement**

```ruby
# lib/spm_cache/cache/pointer.rb
# frozen_string_literal: true

require 'fileutils'
require 'json'

module SPMCache
  module Cache
    # Canonical-name pointer layer: plain-name symlinks over hash-suffixed
    # artifacts, preserving the Swift GenProxy / slice_complete? lookup
    # contract without modifying the companion. Pointers are derived,
    # ephemeral state — never synced, always safe to delete and recreate.
    module Pointer
      HASH_NAME = /\A(.+)-([0-9a-f]{8})\.xcframework\z/.freeze

      class << self
        def refresh_all!(cache_dir:, lockfile_path:, graph_path:, config:, pins_path: nil)
          quarantine_legacy!(cache_dir)
          graph_entries = read_json_array(graph_path)
          pins = read_pins(pins_path) || pins_from_lockfile(lockfile_path)
          hashes = Fingerprint.map_for(graph_entries: graph_entries, pins: pins, config: config)
          hashes.each_with_object({}) do |(mod, hash8), result|
            result[mod] = hash8 if materialize!(cache_dir: cache_dir, module_name: mod, hash8: hash8)
          end
        rescue StandardError => e
          Core::UI.warn "pointer refresh failed (fail-open): #{e.message}"
          {}
        end

        def materialize!(cache_dir:, module_name:, hash8:)
          target = File.join(cache_dir, "#{module_name}-#{hash8}.xcframework")
          return false unless File.directory?(target)

          link_atomic(cache_dir, "#{module_name}.xcframework", "#{module_name}-#{hash8}.xcframework")
          link_atomic(cache_dir, "#{module_name}.xcframework.provenance.json",
                      "#{module_name}-#{hash8}.xcframework.provenance.json", optional: true)
          link_atomic(cache_dir, "#{module_name}.xcframework.shims.json",
                      "#{module_name}-#{hash8}.xcframework.shims.json", optional: true)
          touch_last_used("#{target}.provenance.json")
          true
        end

        # Non-symlink plain-name dirs are pre-upgrade artifacts: quarantine to
        # legacy-* so Swift lookups miss and rebuild once; GC sweeps them.
        def quarantine_legacy!(cache_dir)
          Dir.glob(File.join(cache_dir, '*.xcframework')).filter_map do |path|
            next if File.symlink?(path)

            base = File.basename(path, '.xcframework')
            next if base.start_with?('legacy-') || base.match?(/-[0-9a-f]{8}\z/)

            move_pair(cache_dir, base, "legacy-#{base}")
            base
          end
        end

        def clear_all!(cache_dir)
          Dir.glob(File.join(cache_dir, '*.xcframework')).count do |path|
            next 0 unless File.symlink?(path)

            FileUtils.rm_f(path)
            FileUtils.rm_f("#{path}.provenance.json")
            FileUtils.rm_f("#{path}.shims.json")
            1
          end
        end

        private

        def link_atomic(cache_dir, link_name, target_name, optional: false)
          target = File.join(cache_dir, target_name)
          return if optional && !File.exist?(target)

          link = File.join(cache_dir, link_name)
          tmp = "#{link}.tmp#{Process.pid}"
          FileUtils.rm_f(tmp)
          File.symlink(target_name, tmp)
          File.rename(tmp, link)
        end

        def move_pair(cache_dir, from_base, to_base)
          FileUtils.mv(File.join(cache_dir, "#{from_base}.xcframework"),
                       File.join(cache_dir, "#{to_base}.xcframework"))
          %w[provenance shims].each do |kind|
            from = File.join(cache_dir, "#{from_base}.xcframework.#{kind}.json")
            FileUtils.mv(from, File.join(cache_dir, "#{to_base}.xcframework.#{kind}.json")) if File.exist?(from)
          end
        end

        def touch_last_used(sidecar)
          return unless File.exist?(sidecar)

          data = JSON.parse(File.read(sidecar))
          data['last_used_at'] = Time.now.to_i
          File.write(sidecar, JSON.generate(data))
        rescue JSON::ParserError, SystemCallError
          nil # sidecar tolerance: pointer metadata must never break a hit
        end

        def read_json_array(path)
          return [] unless path && File.exist?(path)

          parsed = JSON.parse(File.read(path))
          parsed.is_a?(Array) ? parsed : []
        rescue JSON::ParserError, SystemCallError
          []
        end

        def read_pins(pins_path)
          return nil unless pins_path && File.exist?(pins_path)

          parsed = JSON.parse(File.read(pins_path))
          parsed.is_a?(Hash) ? parsed : {}
        rescue JSON::ParserError, SystemCallError
          {}
        end

        # Lockfile packages map module-ish names to raw pin hashes when no
        # explicit pins_path is given (best effort; unknown = {}).
        def pins_from_lockfile(lockfile_path)
          return {} unless lockfile_path && File.exist?(lockfile_path)

          data = JSON.parse(File.read(lockfile_path))
          projects = data['projects'] || {}
          projects.values.flat_map { |pkgs| pkgs.map { |p| [p['name'], p] } }.to_h
        rescue JSON::ParserError, SystemCallError
          {}
        end
      end
    end
  end
end
```

Wiring — `spm/pkg/proxy.rb` `prepare`, immediately before the `gen_proxy` call (~line 45):

```ruby
# Refresh canonical pointers BEFORE gen-proxy: the Swift side decides hits
# through plain-name paths, so quarantine + materialize must precede it.
begin
  graph_path = File.join(@root_dir, 'spm-cache', 'graph.json') # use the SAME path gen_cachemap_viz reads
  Cache::Pointer.refresh_all!(cache_dir: cache_dir, lockfile_path: lockfile_path,
                              graph_path: graph_path, config: Core::Config.instance)
rescue StandardError => e
  Core::UI.warn "pointer refresh skipped: #{e.message}"
end
```

IMPORTANT: replace the literal graph path with the exact constant/derivation `installer/integration/viz.rb` uses for the graph JSON — one source of truth, not a second guess.

Run-scope config — `core/config.rb`:

```ruby
attr_accessor :run_sdk, :run_config, :run_merge_slices, :run_library_evolution

# in initialize, after existing assignments:
reset_run_scope!

def reset_run_scope!
  require 'spm_cache/command/base'
  @run_sdk = Command::BaseOptions::SDK
  @run_config = Command::BaseOptions::CONFIG
  @run_merge_slices = Command::BaseOptions::MERGE_SLICES
  @run_library_evolution = Command::BaseOptions::LIBRARY_EVOLUTION
end
```

In `reset!` add `reset_run_scope!`. In `command/base.rb` `initialize(argv)`, after existing option parsing, set the four `Core::Config.instance` values from the parsed options (use `argv.option('sdk', ...)`/`argv.flag?` exactly as the existing global options are parsed — follow `Command.options` declarations at `command.rb`).

- [ ] **Step 4: Run — expect pass + sweep**

Run: `bundle exec rspec spec/cache_pointer_spec.rb spec/fingerprint_spec.rb spec/installer_integrate_proxy_spec.rb spec/gen_proxy_cache_only_spec.rb`
Expected: PASS. If proxy fixtures assert plain-name artifacts, update fixtures to hash-name + pointer (fixture-only change; no assertion weakening).

- [ ] **Step 5: Commit**

```bash
git add lib/spm_cache/cache/pointer.rb lib/spm_cache/core/config.rb lib/spm_cache/command/base.rb lib/spm_cache/spm/pkg/proxy.rb spec/cache_pointer_spec.rb
git commit -m "feat(cache): canonical pointer layer with legacy quarantine and run-scope context"
```

### Task 4: Inventory `hash8` + `last_used`

**Files:**
- Modify: `lib/spm_cache/cache/inventory.rb`
- Test: `spec/cache_inventory_spec.rb`

**Interfaces:**
- Consumes: Task 2 sidecar fields; Task 3 pointers.
- Produces: `Entry` gains `hash8` (String/nil), `last_used` (Integer/nil); scan resolves symlinks to targets for size/fidelity; a plain-name pointer never counts as a separate entry.

- [ ] **Step 1: Write failing tests**

```ruby
# spec/cache_inventory_spec.rb
# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'
require 'json'

RSpec.describe SPMCache::Cache::Inventory do
  let(:root) { Dir.mktmpdir }
  after { FileUtils.remove_entry(root) }

  it 'reports hash8 and last_used, resolves pointers, skips double-count' do
    dir = File.join(root, 'debug')
    FileUtils.mkdir_p(dir)
    fw = File.join(dir, 'Alamofire-a1b2c3d4.xcframework')
    FileUtils.mkdir_p(fw)
    File.write("#{fw}.provenance.json",
               JSON.generate('fidelity_status' => 'host-pinned', 'cache_key' => 'a1b2c3d4',
                             'last_used_at' => 123))
    FileUtils.ln_s('Alamofire-a1b2c3d4.xcframework', File.join(dir, 'Alamofire.xcframework'))
    entries = described_class.scan(cache_root: root)
    entry = entries.find { |e| e.name == 'Alamofire' }
    expect(entry.hash8).to eq('a1b2c3d4')
    expect(entry.last_used).to eq(123)
    expect(entry.fidelity).to eq('host-pinned')
    expect(entries.count).to eq(1)
  end

  it 'keeps legacy artifacts visible with nil hash8' do
    FileUtils.mkdir_p(File.join(root, 'debug', 'legacy-Old.xcframework'))
    entry = described_class.scan(cache_root: root).find { |e| e.name == 'legacy-Old' }
    expect(entry.hash8).to be_nil
  end
end
```

- [ ] **Step 2: Run** — FAIL (`hash8`/`last_used` undefined; count == 2).
- [ ] **Step 3: Implement** — extend `Entry` struct (`hash8:, last_used:`); in `scan`: `path = File.realpath(p) if File.symlink?(p)` then skip the original glob entry when its realpath was already emitted; extract hash8 via basename regex `/-([0-9a-f]{8})\.xcframework\z/`; read `last_used_at` in the same tolerant sidecar parse as `fidelity_status_for` (extend it to return both fields or add a sibling method `sidecar_fields_for`).
- [ ] **Step 4: Run** `bundle exec rspec spec/cache_inventory_spec.rb spec/command_cache_list_spec.rb` — PASS (update list expectations if output gains columns).
- [ ] **Step 5: Commit** `git add lib/spm_cache/cache/inventory.rb spec/cache_inventory_spec.rb && git commit -m "feat(cache): inventory reports hash8 and last_used via pointer resolution"`

### Task 5: `Cache::GC` engine

**Files:**
- Create: `lib/spm_cache/cache/gc.rb`
- Test: `spec/cache_gc_spec.rb`

**Interfaces:**
- Consumes: Task 2/3 sidecar conventions; `Core::Config#build_lock_path`.
- Produces (used by Tasks 6, 7):
  - `GC::Plan = Struct.new(:entries, :reclaimed_bytes, :usage_bytes, keyword_init: true)`; entry `{path:, bytes:, reason:}`; reasons `:over_budget_lru, :legacy, :dangling_pointer, :orphan_sidecar, :missing_sidecar`.
  - `GC.plan(cache_dirs:, max_size_bytes:, protect: []) -> Plan` — ALL cleanup classes (legacy/dangling/orphan/missing-sidecar; plus LRU entries needed to reach 70% when over budget).
  - `GC.watermark_plan(cache_dir:, budget_bytes:, protect: []) -> Plan` — empty when ≤85%; LRU-to-≤70% otherwise.
  - `GC.execute!(plan) -> Integer`.
  - `GC.build_lock_held?(lock_path) -> bool` — non-blocking flock probe.

- [ ] **Step 1: Write failing tests** — fixture builder writes hash-named artifacts with padded files + sidecars (`last_used_at` 1/2/3), one `legacy-Old`, one dangling pointer, one orphan sidecar, one hash artifact without sidecar. Assert: `plan` reasons exactly match classes; LRU eviction order 1→2→3; `watermark_plan` empty at ≤85%; protects skip listed hashes even when oldest; `execute!` removes artifact + provenance + shims sidecars; `build_lock_held?` true while an exclusive flock is held in the test, false after release.
- [ ] **Step 2: Run** — FAIL (module undefined).
- [ ] **Step 3: Implement**

```ruby
# lib/spm_cache/cache/gc.rb
# frozen_string_literal: true

require 'fileutils'
require 'json'

module SPMCache
  module Cache
    module GC
      HIGH_WATERMARK = 0.85
      LOW_WATERMARK = 0.70
      Plan = Struct.new(:entries, :reclaimed_bytes, :usage_bytes, keyword_init: true)

      class << self
        def plan(cache_dirs:, max_size_bytes:, protect: [])
          entries = cache_dirs.flat_map { |dir| structural_entries(dir, protect: protect) }
          usage = cache_dirs.sum { |dir| dir_bytes(dir) }
          over = cache_dirs.flat_map { |dir| lru_entries(dir, protect: protect, budget: max_size_bytes) }
          entries += over
          Plan.new(entries: entries, reclaimed_bytes: entries.sum { |e| e[:bytes] }, usage_bytes: usage)
        end

        def watermark_plan(cache_dir:, budget_bytes:, protect: [])
          usage = dir_bytes(cache_dir)
          empty = Plan.new(entries: [], reclaimed_bytes: 0, usage_bytes: usage)
          return empty if budget_bytes <= 0 || usage <= (budget_bytes * HIGH_WATERMARK).to_i

          target = (budget_bytes * LOW_WATERMARK).to_i
          picked = []
          lru_entries(cache_dir, protect: protect, budget: budget_bytes).each do |cand|
            break if usage - picked.sum { |p| p[:bytes] } <= target

            picked << cand
          end
          Plan.new(entries: picked, reclaimed_bytes: picked.sum { |p| p[:bytes] }, usage_bytes: usage)
        end

        def execute!(plan)
          plan.entries.count do |e|
            FileUtils.rm_rf(e[:path])
            FileUtils.rm_f("#{e[:path]}.provenance.json")
            FileUtils.rm_f("#{e[:path]}.shims.json")
            true
          end
        end

        def build_lock_held?(lock_path)
          return false unless File.exist?(lock_path)

          f = File.open(lock_path, File::RDWR)
          held = !f.flock(File::LOCK_EX | File::LOCK_NB)
          f.flock(File::LOCK_UN) unless held
          f.close
          held
        end

        private

        def structural_entries(dir, protect:)
          return [] unless File.directory?(dir)

          entries = []
          Dir.glob(File.join(dir, '*.xcframework')).each do |path|
            if File.symlink?(path)
              entries << { path: path, bytes: 0, reason: :dangling_pointer } unless File.directory?(path)
            elsif File.basename(path).start_with?('legacy-')
              entries << { path: path, bytes: dir_bytes(path), reason: :legacy }
            elsif hash8(path) && !protect.include?(hash8(path))
              entries << { path: path, bytes: dir_bytes(path),
                           reason: sidecar?(path) ? :over_budget_lru : :missing_sidecar }
            end
          end
          Dir.glob(File.join(dir, '*.xcframework.{provenance,shims}.json')).each do |sc|
            fw = sc.sub(/\.(provenance|shims)\.json\z/, '')
            entries << { path: sc, bytes: File.size(sc), reason: :orphan_sidecar } unless File.exist?(fw)
          end
          entries
        end

        def lru_entries(dir, protect:, budget:)
          usage = dir_bytes(dir)
          return [] if usage <= (budget * HIGH_WATERMARK).to_i

          target = (budget * LOW_WATERMARK).to_i
          picked = []
          Dir.glob(File.join(dir, '*-????????.xcframework'))
              .map { |p| { path: p, bytes: dir_bytes(p), last_used: last_used(p) } }
              .reject { |c| protect.include?(hash8(c[:path])) || !hash8(c[:path]) }
              .sort_by { |c| c[:last_used] }
              .each do |cand|
            break if usage - picked.sum { |p| p[:bytes] } <= target

            picked << cand.merge(reason: :over_budget_lru)
          end
          picked
        end

        def hash8(path)
          File.basename(path)[/-([0-9a-f]{8})\.xcframework\z/, 1]
        end

        def sidecar?(path)
          File.exist?("#{path}.provenance.json")
        end

        def last_used(path)
          JSON.parse(File.read("#{path}.provenance.json"))['last_used_at'] || 0
        rescue JSON::ParserError, SystemCallError
          0 # unreadable sidecar = evicted first
        end

        def dir_bytes(path)
          return 0 unless File.directory?(path)

          Dir.glob(File.join(path, '**', '*')).sum { |e| File.lstat(e).size } + File.lstat(path).size
        rescue SystemCallError
          0
        end
      end
    end
  end
end
```

`Dir.glob('*-????????.xcframework')` is a coarse prefilter only; the `hash8` method's regex is the authority on what counts as hash-suffixed.

- [ ] **Step 4: Run** `bundle exec rspec spec/cache_gc_spec.rb && bundle exec rubocop lib/spm_cache/cache/gc.rb` — PASS.
- [ ] **Step 5: Commit** `git add lib/spm_cache/cache/gc.rb spec/cache_gc_spec.rb && git commit -m "feat(cache): plan/execute GC engine with LRU watermark and orphan cleanup"`

### Task 6: Config keys + `spm-cache cache gc`

**Files:**
- Modify: `lib/spm_cache/core/config.rb` (DEFAULT_CONFIG + readers)
- Create: `lib/spm_cache/command/cache/gc.rb`
- Modify: `lib/spm_cache/command/cache.rb` (require)
- Test: `spec/command_cache_gc_spec.rb`; extend `spec/config_spec.rb`

**Interfaces:**
- Consumes: Task 5 `GC.plan/execute!/build_lock_held?`.
- Produces: `Config#cache_max_size_gb -> Integer` (yml `cache.max_size_gb`, default 20, invalid → 20), `Config#cache_auto_evict? -> bool` (yml `cache.auto_evict`, default false). CLI `spm-cache cache gc [--dry-run] [--max-size N] [--all-configs]` — always covers `debug` + `release` (`--all-configs` = explicit form of the default).

- [ ] **Step 1: Failing tests** — config: defaults 20/false; `write_yml('cache' => { 'max_size_gb' => 3, 'auto_evict' => true })` reads 3/true; `'max_size_gb' => 'x'` → 20. Command: stub `Cache::GC.plan` → Plan with 2 entries; dry-run prints `[dry]` per entry and deletes nothing; real run removes both + prints reclaimed bytes; `Cache::GC.build_lock_held?` → true ⇒ raises `Core::GeneralError` whose message contains `build lock`.
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement** — config:

```ruby
# DEFAULT_CONFIG addition:
'cache' => { 'max_size_gb' => 20, 'auto_evict' => false }

def cache_max_size_gb
  Integer(@raw.dig('cache', 'max_size_gb') || DEFAULT_CONFIG.fetch('cache').fetch('max_size_gb'))
rescue ArgumentError, TypeError
  20
end

def cache_auto_evict?
  @raw.dig('cache', 'auto_evict') == true
end
```

Command mirrors `command/cache/clean.rb` structure (options array, `initialize(argv)` parsing `@dry = argv.flag?('dry-run', argv.flag?('dry', false))`, `@max_size = argv.option('max-size')`, `@all_configs = argv.flag?('all-configs', true)`; `run` checks `GC.build_lock_held?(config.build_lock_path)` first, then `plan` + `execute!` per both config dirs).

- [ ] **Step 4: Run** `bundle exec rspec spec/command_cache_gc_spec.rb spec/config_spec.rb` — PASS.
- [ ] **Step 5: Commit** `git add lib/spm_cache/core/config.rb lib/spm_cache/command/cache.rb lib/spm_cache/command/cache/gc.rb spec/command_cache_gc_spec.rb spec/config_spec.rb && git commit -m "feat(cache): cache gc command with size budget config"`

### Task 7: Opt-in auto-evict after store

**Files:**
- Modify: `lib/spm_cache/installer/build.rb` (after the `missed.each` loop, inside `with_build_lock`)
- Test: `spec/installer_auto_evict_spec.rb`

**Interfaces:**
- Consumes: Task 5 `GC.watermark_plan/execute!`; `Config#cache_auto_evict?/#cache_max_size_gb`; Task 2 hash return values.
- Produces: behavior only. `build_single_target` records `@written_cache_keys ||= {}; @written_cache_keys[name] = hash8` when the pipeline result basename matches `/-([0-9a-f]{8})\.xcframework\z/`.

- [ ] **Step 1: Failing tests** — (a) `auto_evict: false` ⇒ `watermark_plan` never called; (b) true + usage ≤85% ⇒ nothing removed; (c) true + over budget ⇒ LRU evicted, and `watermark_plan` receives `protect:` containing exactly the written hash8s; post-state asserts the just-written artifact still exists while the oldest does not; (d) `watermark_plan` raises ⇒ build succeeds with warn. Stub `Cache::GC.watermark_plan`/`execute!` capturing kwargs; drive `Installer::Build#perform_install` with the existing build spec fixture approach (`spec/installer_build_spec.rb`).
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement** — after the build loop:

```ruby
return unless @config.cache_auto_evict?

begin
  budget = @config.cache_max_size_gb * 1024 * 1024 * 1024
  plan = Cache::GC.watermark_plan(cache_dir: cache_out, budget_bytes: budget,
                                  protect: (@written_cache_keys || {}).values)
  if plan.entries.any?
    Cache::GC.execute!(plan)
    Core::UI.info "Auto-evicted #{plan.entries.size} artifact(s), reclaimed #{plan.reclaimed_bytes} bytes"
  end
rescue StandardError => e
  Core::UI.warn "auto-evict failed (ignored): #{e.message}"
end
```

(Place it before the `ensure` releases the lock; `cache_out` is already in scope at `installer/build.rb:26`.)

- [ ] **Step 4: Run** `bundle exec rspec spec/installer_auto_evict_spec.rb spec/command_build_rebuild_spec.rb` — PASS.
- [ ] **Step 5: Commit** `git add lib/spm_cache/installer/build.rb spec/installer_auto_evict_spec.rb && git commit -m "feat(cache): opt-in LRU auto-eviction after successful store"`

### Task 8: Remote storage pointer hygiene

**Files:**
- Modify: `lib/spm_cache/storage/git.rb`, `lib/spm_cache/storage/s3.rb`
- Test: `spec/storage_pointer_hygiene_spec.rb`

**Interfaces:**
- Consumes: Task 3 `Pointer.clear_all!`.
- Produces: behavior only.

- [ ] **Step 1: Failing tests** — git: instance_double `Core::Git` recording call order; fixture dir with hash artifact + live pointer; after `push`, assert the plain symlink was absent at `git.add(".")` time (record `File.symlink?` state inside the stubbed add) and the hash artifact remains. S3: stub `Core::Sh.run` capturing command strings; assert pull and push commands both include `--no-follow-symlinks`.
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement** — git `push`, after init/ensure_remote, before `git.add(".")`:

```ruby
# Pointers are local derived state: never commit them. Next `use`
# recreates them from lockfile + fingerprints.
removed = Cache::Pointer.clear_all!(@cache_dir)
Core::UI.info("Stripped #{removed} local pointer(s) before push") if removed.positive?
```

git `pull`, after `git.clean(force: true)`: `Core::UI.info('Pointers refresh on next spm-cache use')`. S3 pull/push: append `--no-follow-symlinks` to both `aws s3 sync` command strings.

- [ ] **Step 4: Run** `bundle exec rspec spec/storage_pointer_hygiene_spec.rb` — PASS.
- [ ] **Step 5: Commit** `git add lib/spm_cache/storage/git.rb lib/spm_cache/storage/s3.rb spec/storage_pointer_hygiene_spec.rb && git commit -m "fix(storage): keep canonical pointers out of remote cache sync"`

### Task 9: Doctor check + fast-path regression

**Files:**
- Modify: `lib/spm_cache/core/diagnostics.rb` (new `register('cache_fingerprint', ...)` check)
- Test: `spec/doctor_cache_fingerprint_spec.rb`, `spec/fingerprint_fast_path_regression_spec.rb`

**Interfaces:**
- Consumes: Tasks 1-4.
- Produces: `doctor` check reports (a) `Fingerprint.map_for` computes identically twice for the current lockfile+graph; (b) every non-legacy scanned artifact carries sidecar `cache_key` (warns with names of missing ones).

- [ ] **Step 1: Failing tests** — doctor: inject toolchain stubs + fixture graph/pins; ok-case check passes; a `Plain.xcframework` fixture without `cache_key` produces a warning naming it. Regression: reuse the `fidelity_drift_regression_spec.rb` fixture approach — first `Installer::Use#perform_install` writes hash artifact + pointer; second run with unchanged pins/context invokes `SPM::SPM::BuildPipeline#run` zero times (spy) and still integrates the proxy.
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement** — diagnostics check follows the existing `register('swift_version', ...)` pattern (diagnostics.rb:233): compute the map twice and compare; scan `Cache::Inventory.scan` for `hash8.nil? && !name.start_with?('legacy-')`. Regression spec copies the drift-regression fixture setup and swaps drift assertions for the no-rebuild spy assertion.
- [ ] **Step 4: Run** `bundle exec rspec spec/doctor_cache_fingerprint_spec.rb spec/fingerprint_fast_path_regression_spec.rb && bundle exec rspec` (full suite) — PASS.
- [ ] **Step 5: Commit** `git add lib/spm_cache/core/diagnostics.rb spec/doctor_cache_fingerprint_spec.rb spec/fingerprint_fast_path_regression_spec.rb && git commit -m "feat(doctor): fingerprint determinism check and fast-path no-rebuild regression"`

### Task 10: Fixture-project GitHub Actions validation

**Files:**
- Create: `script/generate-fixture-app.rb` (generates the fixture .xcodeproj via the existing `xcodeproj` gem — never commit the pbxproj)
- Create: `spec/fixtures/fixture-app/` (committed sources: `FixtureApp/` Swift sources, `FixtureKit/` local Swift package, `Package.resolved` with one remote pin `swift-log`)
- Create: `.github/workflows/fixture-cache.yml`
- Test: the workflow run itself (Task 10's test cycle is CI-green + assertions passing)

**Interfaces:**
- Consumes: Tasks 1-9 (hash-named artifacts, pointers, sidecars, `cache gc`, fast path).
- Produces: a repeatable end-to-end environment proving cache identity + hygiene against a real Xcode project on GitHub's macOS runners.

**Fixture shape (KISS):**

```
spec/fixtures/fixture-app/
  FixtureApp/            # tiny iOS app target (one AppDelegate.swift importing FixtureKit + Logging)
  FixtureKit/            # local Swift package (one library target)
  Package.resolved       # one remote pin: swift-log (stable, small)
  README.md              # regenerated by script; do not edit
```

- `generate-fixture-app.rb` builds `FixtureApp.xcodeproj` with the `xcodeproj` gem: app target (iOS deployment target 17.0), local package reference to `FixtureKit`, remote package `swift-log` resolved from the committed `Package.resolved`, framework-embedded app dependency wiring. Deterministic output; safe to re-run.
- Workflow (`.github/workflows/fixture-cache.yml`): `workflow_dispatch` + `pull_request` (paths `lib/**`, `spec/fixtures/fixture-app/**`, `script/**`, `.github/workflows/fixture-cache.yml`); `runs-on: macos-15`; Xcode 16 via `maxim-lobanov/setup-xcode@v1` (mirrors `ci.yml`); steps: checkout → setup-ruby (3.3, bundler-cache) → `make proxy.build` → `bundle exec ruby script/generate-fixture-app.rb` → first `use`/build run → assertions → second-run fast-path assertion → `cache gc --dry-run` → `cache gc`.

**CI assertions (bash in workflow, fail loud):**

```bash
CACHE_DIR="$HOME/.spm-cache/debug"
# 1. exactly one hash-suffixed FixtureKit artifact + swift-log artifacts
ls "$CACHE_DIR" | grep -E '^FixtureKit-[0-9a-f]{8}\.xcframework$'
# 2. plain-name pointer is a symlink to the hash artifact
test -L "$CACHE_DIR/FixtureKit.xcframework"
# 3. sidecar carries cache_key + last_used_at
SIDECAR=$(ls "$CACHE_DIR"/FixtureKit-*.xcframework.provenance.json | head -1)
grep -q '"cache_key"' "$SIDECAR" && grep -q '"last_used_at"' "$SIDECAR"
# 4. second run hits the fast path (no rebuild of built targets)
bundle exec bin/spm-cache build FixtureKit 2>&1 | tee /tmp/second.log
grep -q 'No targets to build' /tmp/second.log
# 5. gc dry-run lists entries; real gc keeps the pinned artifact
bundle exec bin/spm-cache cache gc --dry-run | tee /tmp/gc.log
test -d "$CACHE_DIR/$(ls "$CACHE_DIR" | grep -E '^FixtureKit-[0-9a-f]{8}\.xcframework$')"
```

**Local pre-flight before push:** run `bundle exec ruby script/generate-fixture-app.rb` + the same assertion block on this Mac; CI must never be the first execution.

- [ ] **Step 1: Write failing fixture + workflow** — commit fixture sources, generator script, workflow yaml as above.
- [ ] **Step 2: Local pre-flight** — `bundle exec ruby script/generate-fixture-app.rb && cd spec/fixtures/fixture-app && ../../../../bin/spm-cache build FixtureKit` then run the assertion block; fix fixture until green locally.
- [ ] **Step 3: Push branch + dispatch workflow** — push `cache-identity-gc` branch; `gh workflow run fixture-cache.yml --ref cache-identity-gc`; `gh run watch` until green; attach run URL to the task report.
- [ ] **Step 4: Commit** `git add script/generate-fixture-app.rb spec/fixtures/fixture-app .github/workflows/fixture-cache.yml && git commit -m "ci(fixture): end-to-end cache identity and gc validation on GitHub Actions"`

## Release notes (fold into CHANGELOG/README on release)

- Cache artifacts are now content-hash keyed (`{module}-{hash8}.xcframework`); stale-binary hits for changed pins/toolchain/flags are structurally impossible.
- One-time migration: first `use` after upgrade treats pre-upgrade artifacts as misses and rebuilds; `spm-cache cache gc` removes `legacy-*` leftovers.
- New: `spm-cache cache gc [--dry-run] [--max-size N]`; new `spm-cache.yml` keys `cache.max_size_gb` (default 20), `cache.auto_evict` (default false).
- Remote: pushes are additive under hash names; local pointers never leave the machine.
