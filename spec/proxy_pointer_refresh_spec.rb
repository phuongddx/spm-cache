# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'
require 'json'
require 'spm_cache/cache/fingerprint'
require 'spm_cache/cache/pointer'
require 'spm_cache/spm/pkg/proxy'

# rubocop:disable Metrics/BlockLength
RSpec.describe SPMCache::SPM::Package::Proxy, '#prepare pointer refresh' do
  let(:project_dir) { Dir.mktmpdir }
  let(:cache_dir) { File.join(project_dir, 'cache') }
  let(:lockfile_path) { File.join(project_dir, 'spm-cache.lock') }
  let(:config) { SPMCache::Core::Config.instance }
  let(:executable) { instance_double(SPMCache::SPM::Package::ProxyExecutable) }
  let(:toolchain) { { swift_version: '6.0', xcode_version: 'Xcode 16.0' } }
  let(:pin) do
    {
      'identity' => 'alamofire',
      'version' => '5.9.1',
      'revision' => 'abc',
      'products' => [{ 'name' => 'Alamofire', 'type' => 'library', 'targets' => ['Alamofire'] }]
    }
  end

  before do
    config.reset!
    config.project_dir = project_dir
    allow(config).to receive(:cache_dir).and_return(cache_dir)
    allow(SPMCache::SPM::Package::ProxyExecutable).to receive(:new).and_return(executable)
    allow(executable).to receive(:gen_umbrella)
    allow(executable).to receive(:gen_proxy)
    allow(SPMCache::Cache::Fingerprint).to receive(:toolchain).and_return(toolchain)
    FileUtils.mkdir_p(cache_dir)
  end

  after do
    FileUtils.remove_entry(project_dir)
    config.reset!
  end

  def write_lockfile
    File.write(lockfile_path, JSON.generate('App.xcodeproj' => { 'packages' => [pin] }))
  end

  def write_graph(path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.generate([{ 'module' => 'Alamofire', 'status' => 'hit', 'dependencies' => [] }]))
  end

  def make_artifact(hash8)
    path = File.join(cache_dir, "Alamofire-#{hash8}.xcframework")
    FileUtils.mkdir_p(path)
    File.write("#{path}.provenance.json", '{}')
  end

  def expected_hash
    SPMCache::Cache::Fingerprint.map_for(
      graph_entries: [{ 'module' => 'Alamofire', 'dependencies' => [] }],
      pins: { 'Alamofire' => { 'identity' => 'alamofire',
                               'state' => { 'version' => '5.9.1', 'revision' => 'abc', 'branch' => nil } } },
      config: config, toolchain: toolchain
    )['Alamofire']
  end

  it 'materializes a pointer from the preserved graph when a hash artifact exists' do
    write_lockfile
    graph_path = File.join(project_dir, 'spm-cache', 'packages', 'proxy', 'graph.json')
    write_graph(graph_path)
    make_artifact(expected_hash)

    proxy = described_class.new(root_dir: project_dir)
    proxy.prepare

    snapshot_path = "#{graph_path}.last"
    expect(File.exist?(snapshot_path)).to be(true)
    expect(File.exist?(graph_path)).to be(false)
    expect(File.symlink?(File.join(cache_dir, 'Alamofire.xcframework'))).to be(true)
  end

  it 'creates no pointer on the first run when no graph exists' do
    write_lockfile
    make_artifact('a1b2c3d4')

    proxy = described_class.new(root_dir: project_dir)
    proxy.prepare

    graph_path = File.join(project_dir, 'spm-cache', 'packages', 'proxy', 'graph.json')
    expect(File.exist?("#{graph_path}.last")).to be(false)
    expect(File.symlink?(File.join(cache_dir, 'Alamofire.xcframework'))).to be(false)
  end
end
# rubocop:enable Metrics/BlockLength
