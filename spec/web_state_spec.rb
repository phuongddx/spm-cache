# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'tmpdir'
require 'fileutils'
require 'securerandom'

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
            'saved_cached' => true, 'applied_cached' => true, 'pending' => false },
          { 'name' => 'Ziph', 'config' => 'debug', 'size_bytes' => File.lstat(File.join(cache_root, 'debug', 'Ziph.xcframework')).size,
            'state' => 'missed', 'fidelity' => 'not-graph-pinned', 'has_macro' => true,
            'saved_cached' => true, 'applied_cached' => true, 'pending' => false },
          { 'name' => 'Alamofire', 'config' => 'release', 'size_bytes' => File.lstat(File.join(cache_root, 'release', 'Alamofire.xcframework')).size,
            'state' => 'hit', 'fidelity' => 'not-graph-pinned', 'has_macro' => false,
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
