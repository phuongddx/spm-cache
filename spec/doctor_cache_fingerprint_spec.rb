# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'
require 'json'
require 'spm_cache/cache/fingerprint'
require 'spm_cache/cache/inventory'
require 'spm_cache/core/diagnostics'

# rubocop:disable Metrics/BlockLength
RSpec.describe SPMCache::Core::Diagnostics, 'cache_fingerprint' do
  let(:tmpdir) { Dir.mktmpdir }
  let(:cache_dir) { File.join(tmpdir, 'cache', 'debug') }
  let(:lockfile_path) { File.join(tmpdir, 'spm-cache.lock') }
  let(:graph_path) { File.join(tmpdir, 'spm-cache', 'packages', 'proxy', 'graph.json') }
  let(:toolchain) { { swift_version: '6.0', xcode_version: 'Xcode 16.0' } }
  let(:config) do
    instance_double(
      SPMCache::Core::Config,
      project_dir: tmpdir,
      lockfile_path: lockfile_path,
      proxy_graph_path: graph_path,
      run_sdk: 'iphonesimulator',
      run_config: 'debug',
      run_merge_slices: true,
      run_library_evolution: true,
      cache_dir: cache_dir
    )
  end

  before do
    FileUtils.mkdir_p(cache_dir)
    allow(SPMCache::Cache::Fingerprint).to receive(:toolchain).and_return(toolchain)
    allow(SPMCache::Core::Sh).to receive(:run) do |cmd, *_opts|
      raise "unexpected real invocation: Sh.run(#{cmd.inspect})"
    end
    allow(SPMCache::Core::Sh).to receive(:capture_output) do |cmd, *_opts|
      raise "unexpected real invocation: Sh.capture_output(#{cmd.inspect})"
    end
  end

  after { FileUtils.rm_rf(tmpdir) }

  # rubocop:disable Metrics/MethodLength
  def write_fixture
    File.write(lockfile_path, JSON.generate(
                                'Fake.xcodeproj' => {
                                  'packages' => [{
                                    'name' => 'Alamofire',
                                    'identity' => 'alamofire',
                                    'version' => '5.9.1',
                                    'products' => [{ 'name' => 'Alamofire', 'type' => 'library' }]
                                  }]
                                }
                              ))
    FileUtils.mkdir_p(File.dirname(graph_path))
    File.write(graph_path, JSON.generate(
                             [{ 'module' => 'Alamofire', 'status' => 'hit', 'dependencies' => [] }]
                           ))
  end
  # rubocop:enable Metrics/MethodLength

  def make_artifact(name, sidecar: {})
    path = File.join(cache_dir, "#{name}.xcframework")
    FileUtils.mkdir_p(path)
    File.write("#{path}.provenance.json", JSON.generate(sidecar))
  end

  def result
    saved = described_class.registry.dup
    begin
      described_class.instance_variable_set(:@registry, saved.select { |check| check.name == 'cache_fingerprint' })
      described_class.run_all(config: config).first
    ensure
      described_class.instance_variable_set(:@registry, saved)
    end
  end

  def only_result(config_for_check)
    saved = described_class.registry.dup
    begin
      described_class.instance_variable_set(:@registry, saved.select { |check| check.name == 'cache_fingerprint' })
      described_class.run_all(config: config_for_check).first
    ensure
      described_class.instance_variable_set(:@registry, saved)
    end
  end

  it 'is ok when the fingerprint map is deterministic and scanned artifacts have cache keys' do
    write_fixture
    make_artifact('Alamofire-a1b2c3d4', sidecar: { 'cache_key' => 'a1b2c3d4' })

    expect(result).to have_attributes(status: :ok, message: include('deterministic'))
  end

  it 'warns and names a non-legacy artifact whose sidecar has no cache_key' do
    write_fixture
    make_artifact('Plain')

    expect(result).to have_attributes(status: :warn, message: include('Plain'))
  end

  it 'fails when two computations of the same graph and pins differ' do
    write_fixture
    make_artifact('Alamofire-a1b2c3d4', sidecar: { 'cache_key' => 'a1b2c3d4' })
    allow(SPMCache::Cache::Fingerprint).to receive(:map_for).and_return(
      { 'Alamofire' => 'aaaa1111' }, { 'Alamofire' => 'bbbb2222' }
    )

    expect(result).to have_attributes(status: :fail, message: include('changed between computations'))
  end

  it 'is ok without project context or graph state' do
    minimal = instance_double(SPMCache::Core::Config, cache_dir: cache_dir)

    expect(only_result(minimal)).to have_attributes(status: :ok)
  end
end
# rubocop:enable Metrics/BlockLength
