# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'
require 'json'
require 'xcodeproj'
require 'spm_cache/cache/fingerprint'
require 'spm_cache/cache/pointer'
require 'spm_cache/installer/build'
require 'spm_cache/installer/use'

# rubocop:disable Metrics/BlockLength
# Cache identity must not turn a stable pins/context run back into a build.
# The first write is the hash-store fixture; the second unchanged `use` is the
# fast path and must integrate without BuildPipeline ever running.
RSpec.describe 'fingerprint fast-path regression' do
  let(:tmpdir) { Dir.mktmpdir }
  let(:project_path) { File.join(tmpdir, 'Fake.xcodeproj') }
  let(:lockfile_path) { File.join(tmpdir, 'spm-cache.lock') }
  let(:cache_dir) { File.join(tmpdir, 'cache') }
  let(:toolchain) { { swift_version: '6.0', xcode_version: 'Xcode 16.0' } }
  let(:pipeline_runs) { [] }
  let(:package) do
    {
      'repositoryURL' => 'https://github.com/Alamofire/Alamofire.git',
      'name' => 'Alamofire',
      'version' => '5.9.1',
      'products' => [{ 'name' => 'Alamofire', 'type' => 'library' }]
    }
  end

  before do
    SPMCache::Core::Config.instance.reset!
    SPMCache::Core::Config.instance.project_dir = tmpdir
    allow(SPMCache::Core::Config.instance).to receive(:cache_dir).and_return(cache_dir)
    allow(SPMCache::Cache::Fingerprint).to receive(:toolchain).and_return(toolchain)

    build_project
    write_lockfile
    write_package_resolved
    materialize_proxy_and_graph
  end

  after do
    FileUtils.rm_rf(tmpdir)
    SPMCache::Core::Config.instance.reset!
  end

  it 'integrates a stable cache without rebuilding' do
    build_hashed_artifact_and_pointer

    first = SPMCache::Installer::Use.new(project: project_path)
    allow(first).to receive(:recreate_dirs)
    allow(first).to receive(:ensure_config_file)
    allow(first).to receive(:sync_lockfile)
    allow(first).to receive(:prepare_proxy)
    first.perform_install

    expect(File.symlink?(File.join(cache_dir, 'Alamofire.xcframework'))).to be(true)
    expect { SPMCache::Installer::Use.new(project: project_path).perform_install }
      .not_to(change { proxy_reference_project.root_object.package_references.size })
    expect(pipeline_runs.size).to eq(1)
  end

  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
  def build_hashed_artifact_and_pointer
    pkg_dir = File.join(tmpdir, 'checkouts', 'Alamofire')
    FileUtils.mkdir_p(pkg_dir)
    cachemap = SPMCache::Cache::Cachemap.new(
      graph_data: [{ 'module' => 'Alamofire', 'status' => 'missed' }]
    )
    allow_any_instance_of(SPMCache::Installer).to receive(:perform_install).and_wrap_original do |original, *_args|
      receiver = original.receiver
      receiver.instance_variable_set(:@cachemap, cachemap)
      receiver.instance_variable_set(:@lockfile, SPMCache::Core::Lockfile.new(lockfile_path))
      nil
    end
    allow_any_instance_of(SPMCache::Installer::Build).to receive(:resolve_umbrella_checkouts).and_return(nil)
    allow_any_instance_of(SPMCache::Installer::Build).to receive(:checkout_map).and_return('Alamofire' => pkg_dir)
    allow(SPMCache::SPM::ResolvedGraph).to receive(:source_for).and_return(nil)
    allow(SPMCache::SPM::BuildPipeline).to receive(:run) do |**kwargs|
      pipeline_runs << kwargs
      name = kwargs.fetch(:name)
      hash8 = SPMCache::Cache::Fingerprint.map_for(
        graph_entries: kwargs.fetch(:graph_entries),
        pins: kwargs.fetch(:pins_override),
        config: SPMCache::Core::Config.instance,
        toolchain: toolchain
      ).fetch(name)
      path = File.join(cache_dir, "#{name}-#{hash8}.xcframework")
      FileUtils.mkdir_p(path)
      sidecar = { 'cache_key' => hash8, 'cache_key_inputs' => {}, 'last_used_at' => Time.now.to_i }
      File.write("#{path}.provenance.json", JSON.generate(sidecar))
      path
    end

    SPMCache::Installer::Build.new(project: project_path).perform_install
    hash8 = Dir.children(cache_dir).grep(/\AAlamofire-[0-9a-f]{8}\.xcframework\z/).first
    suffix = hash8[/\AAlamofire-([0-9a-f]{8})\.xcframework\z/, 1]
    expect(SPMCache::Cache::Pointer.materialize!(cache_dir: cache_dir, module_name: 'Alamofire',
                                                 hash8: suffix)).to be(true)
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

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
    proxy_dir = File.join(tmpdir, 'spm-cache', 'packages', 'proxy')
    FileUtils.mkdir_p(proxy_dir)
    File.write(File.join(proxy_dir, 'Package.swift'), '// proxy fixture')
    graph = [{ 'module' => 'Alamofire', 'status' => 'hit', 'dependencies' => [], 'hasMacro' => false }]
    File.write(File.join(proxy_dir, 'graph.json'), JSON.generate(graph))
  end

  def proxy_reference_project
    Xcodeproj::Project.open(project_path)
  end
end
# rubocop:enable Metrics/BlockLength
