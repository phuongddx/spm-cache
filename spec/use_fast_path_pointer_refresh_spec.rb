# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'
require 'json'
require 'xcodeproj'
require 'spm_cache/cache/fingerprint'
require 'spm_cache/cache/pointer'
require 'spm_cache/installer/use'

# rubocop:disable Metrics/BlockLength
# A fast-path `use` must still repair canonical pointers when the durable hash
# store was populated by a prior build or remote pull.
RSpec.describe 'Installer::Use fast-path pointer refresh' do
  let(:tmpdir) { Dir.mktmpdir }
  let(:project_path) { File.join(tmpdir, 'Fake.xcodeproj') }
  let(:lockfile_path) { File.join(tmpdir, 'spm-cache.lock') }
  let(:cache_dir) { File.join(tmpdir, 'cache') }
  let(:proxy_dir) { File.join(tmpdir, 'spm-cache', 'packages', 'proxy') }
  let(:config) { SPMCache::Core::Config.instance }
  let(:toolchain) { { swift_version: '6.0', xcode_version: 'Xcode 16.0' } }
  let(:package) do
    {
      'repositoryURL' => 'https://github.com/Alamofire/Alamofire.git',
      'name' => 'Alamofire',
      'version' => '5.9.1',
      'products' => [{ 'name' => 'Alamofire', 'type' => 'library' }]
    }
  end

  before do
    config.reset!
    config.project_dir = tmpdir
    allow(config).to receive(:cache_dir).and_return(cache_dir)
    allow(SPMCache::Cache::Fingerprint).to receive(:toolchain).and_return(toolchain)

    build_project
    write_lockfile
    write_package_resolved
    materialize_proxy_and_graph
    make_hashed_artifact
  end

  after do
    FileUtils.remove_entry(tmpdir)
    config.reset!
  end

  it 'materializes a pointer without leaving the fast path' do
    use = SPMCache::Installer::Use.new(project: project_path)
    allow(SPMCache::Core::UI).to receive(:info).and_call_original
    expect(SPMCache::Core::UI).to receive(:info)
      .with('No changes detected. Proxy package up to date.')
    expect(use).not_to receive(:prepare_proxy)

    use.perform_install

    pointer = File.join(cache_dir, 'Alamofire.xcframework')
    expect(File.symlink?(pointer)).to be(true)
    expect(File.readlink(pointer)).to eq("Alamofire-#{expected_hash}.xcframework")
  end

  def expected_hash
    pin = {
      'identity' => 'Alamofire',
      'state' => { 'version' => '5.9.1', 'revision' => nil, 'branch' => nil }
    }
    SPMCache::Cache::Fingerprint.map_for(
      graph_entries: [{ 'module' => 'Alamofire', 'dependencies' => [] }],
      pins: { 'Alamofire' => pin },
      config: config,
      toolchain: toolchain
    ).fetch('Alamofire')
  end

  # rubocop:disable Metrics/AbcSize
  def build_project
    project = Xcodeproj::Project.new(project_path)
    target = project.new_target(:application, 'MyApp', :ios)
    ref = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
    ref.repositoryURL = package.fetch('repositoryURL')
    project.root_object.package_references << ref
    dependency = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
    dependency.product_name = 'Alamofire'
    dependency.package = ref
    target.package_product_dependencies << dependency
    project.save
  end
  # rubocop:enable Metrics/AbcSize

  def write_lockfile
    File.write(lockfile_path, JSON.generate(
                                'Fake.xcodeproj' => {
                                  'packages' => [package],
                                  'dependencies' => {},
                                  'platforms' => { 'ios' => '16.0' },
                                  'spm_cache_version' => SPMCache::VERSION
                                }
                              ))
  end

  # rubocop:disable Metrics/MethodLength
  def write_package_resolved
    resolved_path = File.join(
      project_path, 'project.xcworkspace', 'xcshareddata', 'swiftpm', 'Package.resolved'
    )
    FileUtils.mkdir_p(File.dirname(resolved_path))
    File.write(resolved_path, JSON.generate(
                                'version' => 3,
                                'pins' => [{
                                  'identity' => 'alamofire',
                                  'kind' => 'remoteSourceControl',
                                  'location' => package.fetch('repositoryURL'),
                                  'state' => { 'version' => package.fetch('version') }
                                }]
                              ))
  end
  # rubocop:enable Metrics/MethodLength

  def materialize_proxy_and_graph
    FileUtils.mkdir_p(proxy_dir)
    File.write(File.join(proxy_dir, 'Package.swift'), '// proxy fixture')
    graph = [{ 'module' => 'Alamofire', 'status' => 'hit', 'dependencies' => [], 'hasMacro' => false }]
    File.write(File.join(proxy_dir, 'graph.json'), JSON.generate(graph))
  end

  def make_hashed_artifact
    path = File.join(cache_dir, "Alamofire-#{expected_hash}.xcframework")
    FileUtils.mkdir_p(path)
    File.write("#{path}.provenance.json", JSON.generate({}))
  end
end
# rubocop:enable Metrics/BlockLength
