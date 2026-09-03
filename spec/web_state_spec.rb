# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'tmpdir'
require 'fileutils'
require 'securerandom'
require 'set'

require_relative 'support/web_server_boot'

# Unit coverage for the /api/state read model (DASH-01): the cache
# table's data derives from the same files the CLI reads -- Cache::
# Inventory for rows, proxy graph.json (via Cache::Cachemap) for the
# state/has_macro join and the summary -- re-read per call, never
# memoized. The cache_root + Config-singleton seams keep every example
# hermetic (no real ~/.spm-cache is ever scanned).
RSpec.describe SPMCache::Web::ReadModels::State do
  let(:project_dir) { Dir.mktmpdir('spm-cache-state-project') }
  let(:cache_root) { Dir.mktmpdir('spm-cache-state-cache') }
  let(:config) { SPMCache::Core::Config.instance }

  around do |example|
    previous = config.project_dir
    SPMCache::Core::Config.configure(project_dir: project_dir)
    config.reset!
    example.run
  ensure
    config.reset!
    SPMCache::Core::Config.configure(project_dir: previous)
    FileUtils.rm_rf(project_dir)
    FileUtils.rm_rf(cache_root)
  end

  def write_graph(entries)
    path = File.join(project_dir, 'spm-cache', 'packages', 'proxy', 'graph.json')
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.generate(entries))
    path
  end

  def write_framework(cfg, name, bytes: 0)
    fw = File.join(cache_root, cfg, "#{name}.xcframework")
    FileUtils.mkdir_p(fw)
    File.write(File.join(fw, 'binary.dat'), 'x' * bytes) if bytes.positive?
    fw
  end

  def write_lockfile(packages, project: 'TestApp.xcodeproj')
    File.write(config.lockfile_path, JSON.generate(project => { 'packages' => packages }))
  end

  def state
    described_class.call(config: config, cache_root: cache_root)
  end

  describe 'the package join' do
    it 'returns one row per cached xcframework with graph status, fidelity, and size joined by module name' do
      write_graph([
                    { 'module' => 'Alamofire', 'status' => 'hit', 'hasMacro' => false },
                    { 'module' => 'Ziph', 'status' => 'missed', 'hasMacro' => true }
                  ])
      fw = write_framework('debug', 'Alamofire', bytes: 120)
      write_framework('debug', 'Ziph')
      write_framework('release', 'Alamofire')
      alamofire_size = File.lstat(fw).size + File.lstat(File.join(fw, 'binary.dat')).size

      expect(state['packages']).to eq(
        [
          { 'name' => 'Alamofire', 'config' => 'debug', 'size_bytes' => alamofire_size,
            'state' => 'hit', 'fidelity' => 'not-graph-pinned', 'has_macro' => false,
            # (16-01) the saved/applied/pending fields land BESIDE the
            # six: empty on-disk ignore list -> saved_cached true;
            # hit/missed -> applied_cached true; nothing pending.
            # (16-03) toggleable/reason land beside those three: no
            # gating fact on either fixture package -> toggleable,
            # no reason.
            'toggleable' => true, 'reason' => nil,
            'saved_cached' => true, 'applied_cached' => true, 'pending' => false },
          { 'name' => 'Ziph', 'config' => 'debug', 'size_bytes' => File.lstat(File.join(cache_root, 'debug', 'Ziph.xcframework')).size,
            'state' => 'missed', 'fidelity' => 'not-graph-pinned', 'has_macro' => true,
            'toggleable' => true, 'reason' => nil,
            'saved_cached' => true, 'applied_cached' => true, 'pending' => false },
          { 'name' => 'Alamofire', 'config' => 'release', 'size_bytes' => File.lstat(File.join(cache_root, 'release', 'Alamofire.xcframework')).size,
            'state' => 'hit', 'fidelity' => 'not-graph-pinned', 'has_macro' => false,
            'toggleable' => true, 'reason' => nil,
            'saved_cached' => true, 'applied_cached' => true, 'pending' => false }
        ]
      )
    end

    it 'gives a cached artifact absent from graph.json state nil and has_macro false (the UI renders the "—" cell)' do
      write_graph([{ 'module' => 'Alamofire', 'status' => 'hit', 'hasMacro' => false }])
      write_framework('debug', 'GhostKit')

      row = state['packages'].find { |p| p['name'] == 'GhostKit' }
      expect(row['state']).to be_nil
      expect(row['has_macro']).to eq(false)
    end

    it 'defaults has_macro to false when the graph entry omits hasMacro' do
      write_graph([{ 'module' => 'Plain', 'status' => 'ignored' }])
      write_framework('debug', 'Plain')

      expect(state['packages'].first['has_macro']).to eq(false)
    end

    it 'carries Inventory fidelity from the provenance sidecar' do
      write_graph([{ 'module' => 'Pinned', 'status' => 'hit', 'hasMacro' => false }])
      write_framework('debug', 'Pinned')
      File.write(File.join(cache_root, 'debug', 'Pinned.xcframework.provenance.json'),
                 JSON.generate(fidelity_status: 'graph-pinned'))

      expect(state['packages'].first['fidelity']).to eq('graph-pinned')
    end
  end

  # (16-03, D-09/TOGL-03) The one server-side derivation: every row
  # answers whether it may be toggled and, when it may not, exactly
  # one of the five words -- resolved by a fixed precedence over facts
  # already on disk (the saved ignore list, the graph status, the
  # provenance fidelity, and the lockfile's binary-backed name set).
  describe 'the reason matrix' do
    it 'is toggleable with no reason for a plainly cached package with no gating fact' do
      write_framework('debug', 'Plain')

      row = state['packages'].first
      expect(row['toggleable']).to eq(true)
      expect(row['reason']).to be_nil
    end

    it 'is not toggleable with the pattern-managed reason when a glob pattern matches but no exact entry exists' do
      write_framework('debug', 'AlamoCore')
      File.write(config.config_path, "ignore:\n  - 'Alamo*'\n")

      row = state['packages'].first
      expect(row['toggleable']).to eq(false)
      expect(row['reason']).to eq('pattern-managed')
    end

    it 'is not toggleable with the plugin reason for a plugin-status package' do
      write_graph([{ 'module' => 'PluginPkg', 'status' => 'plugin' }])
      write_framework('debug', 'PluginPkg')

      row = state['packages'].first
      expect(row['toggleable']).to eq(false)
      expect(row['reason']).to eq('plugin')
    end

    it 'is not toggleable with the excluded reason for an excluded-status package' do
      write_graph([{ 'module' => 'ExcludedPkg', 'status' => 'excluded' }])
      write_framework('debug', 'ExcludedPkg')

      row = state['packages'].first
      expect(row['toggleable']).to eq(false)
      expect(row['reason']).to eq('excluded')
    end

    it 'is not toggleable with the binary-target reason when the lockfile marks the package binary-backed' do
      write_framework('debug', 'BinKit')
      write_lockfile([{ 'name' => 'BinKit', 'binary_target' => true }])

      row = state['packages'].first
      expect(row['toggleable']).to eq(false)
      expect(row['reason']).to eq('binary-target')
    end

    it 'gates on fidelity only for the resolution-incompatible warn status, staying toggleable for not-graph-pinned' do
      write_framework('debug', 'Warned')
      File.write(File.join(cache_root, 'debug', 'Warned.xcframework.provenance.json'),
                 JSON.generate(fidelity_status: 'resolution-incompatible'))
      write_framework('debug', 'Neutral')

      warned = state['packages'].find { |p| p['name'] == 'Warned' }
      neutral = state['packages'].find { |p| p['name'] == 'Neutral' }
      expect(warned['toggleable']).to eq(false)
      expect(warned['reason']).to eq('fidelity')
      expect(neutral['toggleable']).to eq(true)
      expect(neutral['reason']).to be_nil
    end

    it 'resolves precedence deterministically end-to-end: excluded > plugin > binary-target > pattern-managed > fidelity' do
      write_graph([
                    { 'module' => 'ChainExcluded', 'status' => 'excluded' },
                    { 'module' => 'ChainPlugin', 'status' => 'plugin' },
                    { 'module' => 'ChainBinary', 'status' => 'hit' },
                    { 'module' => 'ChainPattern', 'status' => 'hit' }
                  ])
      %w[ChainExcluded ChainPlugin ChainBinary ChainPattern].each do |name|
        write_framework('debug', name)
        File.write(File.join(cache_root, 'debug', "#{name}.xcframework.provenance.json"),
                   JSON.generate(fidelity_status: 'resolution-incompatible'))
      end
      write_lockfile([
                       { 'name' => 'ChainExcluded', 'binary_target' => true },
                       { 'name' => 'ChainPlugin', 'binary_target' => true },
                       { 'name' => 'ChainBinary', 'binary_target' => true }
                     ])
      File.write(config.config_path, "ignore:\n  - 'Chain*'\n")

      reasons = state['packages'].each_with_object({}) { |row, acc| acc[row['name']] = row['reason'] }
      expect(reasons).to eq(
        'ChainExcluded' => 'excluded',
        'ChainPlugin' => 'plugin',
        'ChainBinary' => 'binary-target',
        'ChainPattern' => 'pattern-managed'
      )
    end

    it 'stays toggleable with no reason when the package has an exact ignore entry (the normal off state)' do
      write_framework('debug', 'ToggledOff')
      File.write(config.config_path, "ignore:\n  - ToggledOff\n")

      row = state['packages'].first
      expect(row['toggleable']).to eq(true)
      expect(row['reason']).to be_nil
      expect(row['saved_cached']).to eq(false)
    end

    it 'ignores the macro flag as a reason input' do
      write_graph([{ 'module' => 'MacroPkg', 'status' => 'hit', 'hasMacro' => true }])
      write_framework('debug', 'MacroPkg')

      row = state['packages'].first
      expect(row['has_macro']).to eq(true)
      expect(row['toggleable']).to eq(true)
      expect(row['reason']).to be_nil
    end

    it 'never emits a reason outside the five-word vocabulary' do
      write_graph([
                    { 'module' => 'ExcludedOne', 'status' => 'excluded' },
                    { 'module' => 'PluginOne', 'status' => 'plugin' },
                    { 'module' => 'BinaryOne', 'status' => 'hit' },
                    { 'module' => 'PatternOne', 'status' => 'hit' },
                    { 'module' => 'FidelityOne', 'status' => 'hit' },
                    { 'module' => 'PlainOne', 'status' => 'hit' }
                  ])
      %w[ExcludedOne PluginOne BinaryOne PatternOne FidelityOne PlainOne].each { |n| write_framework('debug', n) }
      write_lockfile([{ 'name' => 'BinaryOne', 'binary_target' => true }])
      File.write(config.config_path, "ignore:\n  - 'Pattern*'\n")
      File.write(File.join(cache_root, 'debug', 'FidelityOne.xcframework.provenance.json'),
                 JSON.generate(fidelity_status: 'resolution-incompatible'))

      reasons = state['packages'].map { |row| row['reason'] }.compact
      expect(reasons.to_set).to eq(%w[excluded plugin binary-target pattern-managed fidelity].to_set)
    end
  end

  describe 'the summary' do
    it 'mirrors Cachemap#stats (string keys) when graph.json exists' do
      write_graph([
                    { 'module' => 'A', 'status' => 'hit' },
                    { 'module' => 'B', 'status' => 'missed' },
                    { 'module' => 'C', 'status' => 'ignored' },
                    { 'module' => 'D', 'status' => 'excluded' },
                    { 'module' => 'E', 'status' => 'plugin' }
                  ])

      expect(state['summary']).to eq(
        'total' => 5, 'hit' => 1, 'missed' => 1, 'ignored' => 1, 'excluded' => 1, 'plugin' => 1
      )
    end

    it 'is all zeros when graph.json is absent (even with cached packages on disk)' do
      write_framework('debug', 'Alamofire', bytes: 10)

      expect(state['summary']).to eq(
        'total' => 0, 'hit' => 0, 'missed' => 0, 'ignored' => 0, 'excluded' => 0, 'plugin' => 0
      )
    end

    it 'is zeros and packages is empty for empty cache dirs (the "No cached packages yet" trigger)' do
      expect(state['packages']).to eq([])
      expect(state['summary']).to eq(
        'total' => 0, 'hit' => 0, 'missed' => 0, 'ignored' => 0, 'excluded' => 0, 'plugin' => 0
      )
    end
  end

  describe 'poll_seconds' do
    it 'defaults to 5' do
      expect(state['poll_seconds']).to eq(5)
    end

    it 'reflects the config override' do
      config.raw['web_poll_seconds'] = 12
      expect(state['poll_seconds']).to eq(12)
    end
  end

  describe 'shape and freshness' do
    it 'answers exactly the packages/summary/poll_seconds keys' do
      expect(state.keys).to eq(%w[packages summary poll_seconds])
    end

    it 'uses String keys throughout so JSON.generate serializes everything' do
      write_graph([{ 'module' => 'A', 'status' => 'hit', 'hasMacro' => true }])
      write_framework('debug', 'A')

      expect(JSON.parse(JSON.generate(state))).to eq(state)
    end

    it 're-reads graph.json on every call: a mutation between two calls changes the answer' do
      write_graph([{ 'module' => 'Alamofire', 'status' => 'hit', 'hasMacro' => false }])
      write_framework('debug', 'Alamofire')

      expect(state['packages'].first['state']).to eq('hit')
      expect(state['summary']['hit']).to eq(1)

      write_graph([{ 'module' => 'Alamofire', 'status' => 'ignored', 'hasMacro' => false }])

      refreshed = state
      expect(refreshed['packages'].first['state']).to eq('ignored')
      expect(refreshed['summary']['hit']).to eq(0)
      expect(refreshed['summary']['ignored']).to eq(1)
    end

    it 're-reads the cache dirs on every call: a newly cached artifact appears without server restart' do
      write_graph([{ 'module' => 'Alamofire', 'status' => 'hit' }])
      write_framework('debug', 'Alamofire')

      expect(state['packages'].size).to eq(1)

      write_framework('debug', 'NewKit')

      expect(state['packages'].map { |p| p['name'] }).to eq(%w[Alamofire NewKit])
    end
  end

  # (16-03, D-06/TOGL-02) Saved and applied are two independently
  # sourced truths; pending is narrowed to rows the UI can actually
  # act on; the read path re-reads on every call and mutates nothing.
  describe 'saved vs applied' do
    it 'saved truth is the exact-entry test regardless of any matching glob pattern' do
      write_framework('debug', 'GlobExact')
      write_framework('debug', 'GlobOnly')
      File.write(config.config_path, "ignore:\n  - 'Glob*'\n  - GlobExact\n")

      exact = state['packages'].find { |p| p['name'] == 'GlobExact' }
      only = state['packages'].find { |p| p['name'] == 'GlobOnly' }
      expect(exact['saved_cached']).to eq(false)
      expect(only['saved_cached']).to eq(true)
      expect(only['reason']).to eq('pattern-managed')
    end

    it 'would_remain_pattern_ignored? is true only when a DIFFERENT pattern would still match once the exact entry is gone (WR-02)' do
      File.write(config.config_path, "ignore:\n  - 'Glob*'\n  - GlobExact\n  - PlainExact\n")

      expect(described_class.would_remain_pattern_ignored?('GlobExact', config)).to eq(true)
      expect(described_class.would_remain_pattern_ignored?('PlainExact', config)).to eq(false)
      expect(described_class.would_remain_pattern_ignored?('NeverListed', config)).to eq(false)
    end

    it 'applied truth is the last-sync graph verdict: ignored means not cached, hit and missed mean cached' do
      write_graph([
                    { 'module' => 'AppliedIgnored', 'status' => 'ignored' },
                    { 'module' => 'AppliedHit', 'status' => 'hit' },
                    { 'module' => 'AppliedMissed', 'status' => 'missed' }
                  ])
      %w[AppliedIgnored AppliedHit AppliedMissed].each { |n| write_framework('debug', n) }

      applied = state['packages'].each_with_object({}) { |row, acc| acc[row['name']] = row['applied_cached'] }
      expect(applied).to eq('AppliedIgnored' => false, 'AppliedHit' => true, 'AppliedMissed' => true)
    end

    it 'has no applied signal and is never pending when the row has no graph entry' do
      write_graph([{ 'module' => 'Known', 'status' => 'hit' }])
      write_framework('debug', 'Known')
      write_framework('debug', 'GhostRow')

      ghost = state['packages'].find { |p| p['name'] == 'GhostRow' }
      expect(ghost['applied_cached']).to be_nil
      expect(ghost['pending']).to eq(false)
    end

    it 'pending is exactly toggleable AND has an applied signal AND the two disagree' do
      write_graph([
                    { 'module' => 'FreshOff', 'status' => 'hit' },
                    { 'module' => 'Converged', 'status' => 'ignored' },
                    { 'module' => 'LockedDivergent', 'status' => 'plugin' }
                  ])
      %w[FreshOff Converged LockedDivergent].each { |n| write_framework('debug', n) }
      File.write(config.config_path, "ignore:\n  - FreshOff\n  - Converged\n  - LockedDivergent\n")

      rows = state['packages'].each_with_object({}) { |row, acc| acc[row['name']] = row }
      expect(rows['FreshOff']['pending']).to eq(true)
      expect(rows['Converged']['pending']).to eq(false)
      expect(rows['LockedDivergent']['toggleable']).to eq(false)
      expect(rows['LockedDivergent']['pending']).to eq(false)
    end

    it 'duplicate rows for a package cached in both configs carry identical toggle fields' do
      write_graph([{ 'module' => 'DualConfig', 'status' => 'plugin' }])
      write_framework('debug', 'DualConfig')
      write_framework('release', 'DualConfig')
      File.write(config.config_path, "ignore:\n  - DualConfig\n")

      rows = state['packages'].select { |p| p['name'] == 'DualConfig' }
      expect(rows.size).to eq(2)
      toggle_fields = rows.map { |r| r.values_at('toggleable', 'reason', 'saved_cached', 'applied_cached', 'pending') }
      expect(toggle_fields.uniq.size).to eq(1)
    end

    it 'CP1: re-reads spm-cache.yml on every call and leaves the Config singleton untouched' do
      write_framework('debug', 'FreshPkg')
      raw_snapshot = config.raw.dup

      expect(state['packages'].first['saved_cached']).to eq(true)

      File.write(config.config_path, "ignore:\n  - FreshPkg\n")

      expect(state['packages'].first['saved_cached']).to eq(false)
      expect(config.raw).to eq(raw_snapshot)
    end
  end

  describe 'the read path stays total' do
    it 'answers honestly with no config file' do
      write_framework('debug', 'NoConfigPkg')

      expect { state }.not_to raise_error
      row = state['packages'].first
      expect(row['saved_cached']).to eq(true)
      expect(row['reason']).to be_nil
    end

    it 'answers honestly when spm-cache.yml is malformed YAML' do
      write_framework('debug', 'BadYamlPkg')
      File.write(config.config_path, "ignore: [Unterminated\n")

      expect { state }.not_to raise_error
      expect(state['packages'].first['saved_cached']).to eq(true)
    end

    it 'answers honestly with no lockfile: no binary-target reason ever fires' do
      write_framework('debug', 'NoLockPkg')

      expect { state }.not_to raise_error
      row = state['packages'].first
      expect(row['reason']).to be_nil
      expect(row['toggleable']).to eq(true)
    end

    it 'answers honestly when spm-cache.lock is corrupted JSON (WR-01: total, not just permission errors)' do
      write_framework('debug', 'CorruptLockPkg')
      File.write(config.lockfile_path, '{"MyApp": {"packages": [')

      expect { state }.not_to raise_error
      row = state['packages'].first
      expect(row['reason']).to be_nil
      expect(row['toggleable']).to eq(true)
    end

    it 'answers honestly with no graph.json: no applied signal, never pending' do
      write_framework('debug', 'NoGraphPkg')

      expect { state }.not_to raise_error
      row = state['packages'].first
      expect(row['applied_cached']).to be_nil
      expect(row['pending']).to eq(false)
    end
  end

  describe 'router mount' do
    it 'token-gates GET /api/state (401 without the launch token)' do
      Dir.mktmpdir do |project|
        WebServerBoot.with_server(project_dir: project) do |handle|
          res = WebServerBoot.http_get(handle, '/api/state')
          expect(res.code).to eq('401')
          body = JSON.parse(res.body)
          expect(body['status']).to eq('error')
        end
      end
    end
  end
end
