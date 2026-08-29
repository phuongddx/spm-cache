# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'json'
require 'xcodeproj'
require 'spm_cache/core/diff_detector'
require 'spm_cache/installer/use'

# Auto-sync fast path: Installer::Use must skip the costly regenerate/resolve
# cycle when the live Xcode SPM graph matches spm-cache.lock (empty diff) AND
# the proxy package is already materialized. Any change (added/removed/updated)
# forces a full regeneration so the proxy stays in sync transparently.
RSpec.describe SPMCache::Installer::Use, '#perform_install fast path' do
  let(:tmpdir) { Dir.mktmpdir }
  let(:project_path) { File.join(tmpdir, 'Fake.xcodeproj') }
  let(:lockfile_path) { File.join(tmpdir, 'spm-cache.lock') }

  before do
    SPMCache::Core::Config.instance.reset!
    SPMCache::Core::Config.instance.project_dir = tmpdir
  end
  after { FileUtils.rm_rf(tmpdir) }

  def build_project
    project = Xcodeproj::Project.new(project_path)
    project.new_target(:application, 'MyApp', :ios)
    project.save
  end

  def write_lockfile(packages, version: SPMCache::VERSION)
    File.write(lockfile_path, JSON.generate(
                                'Fake.xcodeproj' => {
                                  'packages' => packages,
                                  'dependencies' => {},
                                  'platforms' => { 'ios' => '16.0' },
                                  'spm_cache_version' => version
                                }
                              ))
  end

  def materialize_proxy
    proxy_dir = File.join(tmpdir, 'spm-cache', 'packages', 'proxy')
    FileUtils.mkdir_p(proxy_dir)
    File.write(File.join(proxy_dir, 'Package.swift'), "// proxy placeholder\n")
  end

  def write_package_resolved(pins)
    resolved_path = File.join(project_path, 'project.xcworkspace', 'xcshareddata', 'swiftpm', 'Package.resolved')
    FileUtils.mkdir_p(File.dirname(resolved_path))
    File.write(resolved_path, JSON.generate(
                                'version' => 3,
                                'pins' => pins.map do |p|
                                  {
                                    'identity' => p[:identity],
                                    'kind' => 'remoteSourceControl',
                                    'location' => p[:url],
                                    'state' => { 'revision' => p[:revision] || 'rev', 'version' => p[:version] }
                                  }
                                end
                              ))
  end

  it 'takes the fast path (no regeneration) when diff is empty and proxy exists' do
    build_project
    write_lockfile([
                     { 'repositoryURL' => 'https://github.com/Alamofire/Alamofire.git', 'name' => 'Alamofire', 'version' => '5.0.0' }
                   ])
    write_package_resolved([
                             { identity: 'Alamofire', url: 'https://github.com/Alamofire/Alamofire.git', version: '5.0.0' }
                           ])
    materialize_proxy

    installer = described_class.new(project: project_path)
    # Stub the heavy methods that should NOT run on the fast path
    expect(installer).not_to receive(:recreate_dirs)
    expect(installer).not_to receive(:sync_lockfile)
    expect(installer).not_to receive(:prepare_proxy)

    installer.perform_install

    expect(installer.diff).to be_empty
  end

  it 'regenerates (does not take the fast path) when the lockfile spm_cache_version stamp does not match the running gem version, even with an unchanged host graph' do
    build_project
    write_lockfile([
                     { 'repositoryURL' => 'https://github.com/Alamofire/Alamofire.git', 'name' => 'Alamofire', 'version' => '5.0.0' }
                   ], version: 'v0.3.0-stub')
    write_package_resolved([
                             { identity: 'Alamofire', url: 'https://github.com/Alamofire/Alamofire.git', version: '5.0.0' }
                           ])
    materialize_proxy

    installer = described_class.new(project: project_path)
    allow(installer).to receive(:recreate_dirs)
    allow(installer).to receive(:ensure_config_file)
    allow(installer).to receive(:sync_lockfile)
    allow(installer).to receive(:prepare_proxy)
    allow(installer).to receive(:gen_supporting_files)
    allow(installer).to receive(:integrate_proxy_into_project)
    allow(installer).to receive(:gen_cachemap_viz)

    installer.perform_install

    expect(installer.diff).to be_empty
    expect(installer).to have_received(:sync_lockfile)
    expect(installer).to have_received(:prepare_proxy)
  end

  it 'still takes the fast path when the lockfile spm_cache_version stamp matches the running gem version and the host graph is unchanged' do
    build_project
    write_lockfile([
                     { 'repositoryURL' => 'https://github.com/Alamofire/Alamofire.git', 'name' => 'Alamofire', 'version' => '5.0.0' }
                   ])
    write_package_resolved([
                             { identity: 'Alamofire', url: 'https://github.com/Alamofire/Alamofire.git', version: '5.0.0' }
                           ])
    materialize_proxy

    installer = described_class.new(project: project_path)
    expect(installer).not_to receive(:sync_lockfile)
    expect(installer).not_to receive(:prepare_proxy)

    installer.perform_install

    expect(installer.diff).to be_empty
  end

  it 'regenerates when the diff is non-empty (package added)' do
    build_project
    write_lockfile([
                     { 'repositoryURL' => 'https://github.com/Alamofire/Alamofire.git', 'name' => 'Alamofire', 'version' => '5.0.0' }
                   ])
    # Live state has an extra package
    write_package_resolved([
                             { identity: 'Alamofire', url: 'https://github.com/Alamofire/Alamofire.git',
                               version: '5.0.0' },
                             { identity: 'SnapKit', url: 'https://github.com/SnapKit/SnapKit.git', version: '5.6.0' }
                           ])
    materialize_proxy

    installer = described_class.new(project: project_path)
    # On the regeneration path these must run -- stub them to no-ops so the
    # test doesn't shell out to swift package resolve.
    allow(installer).to receive(:recreate_dirs)
    allow(installer).to receive(:ensure_config_file)
    allow(installer).to receive(:sync_lockfile)
    allow(installer).to receive(:prepare_proxy)
    allow(installer).to receive(:gen_supporting_files)
    allow(installer).to receive(:integrate_proxy_into_project)
    allow(installer).to receive(:gen_cachemap_viz)

    installer.perform_install

    expect(installer.diff).not_to be_empty
    expect(installer.diff.added).to eq(['SnapKit'])
  end

  it 'regenerates when lockfile is missing (first run)' do
    build_project
    write_package_resolved([
                             { identity: 'Alamofire', url: 'https://github.com/Alamofire/Alamofire.git', version: '5.0.0' }
                           ])
    # No lockfile, no proxy -> must regenerate

    installer = described_class.new(project: project_path)
    allow(installer).to receive(:recreate_dirs)
    allow(installer).to receive(:ensure_config_file)
    allow(installer).to receive(:sync_lockfile)
    allow(installer).to receive(:prepare_proxy)
    allow(installer).to receive(:gen_supporting_files)
    allow(installer).to receive(:integrate_proxy_into_project)
    allow(installer).to receive(:gen_cachemap_viz)

    installer.perform_install

    expect(installer.diff).not_to be_empty
    expect(installer.diff.added).to include('Alamofire')
  end

  # ROADMAP success criterion 1, proven the way it is written: after a real
  # non-fast-path run, a freshly constructed DiffDetector reports nothing to do.
  # `sync_lockfile` is deliberately NOT stubbed -- reconciliation lives inside it.
  it 'leaves DiffDetector reporting an empty diff' do
    drifted_url = 'https://github.com/example/Drifted.git'
    removed_url = 'https://github.com/example/Removed.git'
    enriched_url = 'https://github.com/example/Enriched.git'
    newcomer_url = 'https://github.com/example/Newcomer.git'
    enriched_products = [{ 'name' => 'Enriched', 'type' => 'library', 'targets' => ['Enriched'] }]

    build_project
    write_lockfile([
                     { 'repositoryURL' => drifted_url, 'name' => 'Drifted', 'version' => '1.0.0',
                       'revision' => 'rev-old' },
                     { 'repositoryURL' => removed_url, 'name' => 'Removed', 'version' => '9.0.0',
                       'revision' => 'rev-removed' },
                     { 'repositoryURL' => enriched_url, 'name' => 'Enriched', 'version' => '2.0.0',
                       'revision' => 'rev-enriched', 'products' => enriched_products }
                   ])
    write_package_resolved([
                             { identity: 'Drifted', url: drifted_url, version: '3.0.0', revision: 'rev-new' },
                             { identity: 'Enriched', url: enriched_url, version: '2.0.0',
                               revision: 'rev-enriched' },
                             { identity: 'Newcomer', url: newcomer_url, version: '0.5.0',
                               revision: 'rev-newcomer' }
                           ])
    materialize_proxy

    installer = described_class.new(project: project_path)
    allow(installer).to receive(:recreate_dirs)
    allow(installer).to receive(:ensure_config_file)
    allow(installer).to receive(:prepare_proxy)
    allow(installer).to receive(:gen_supporting_files)
    allow(installer).to receive(:integrate_proxy_into_project)
    allow(installer).to receive(:gen_cachemap_viz)

    installer.perform_install

    expect(installer.diff).not_to be_empty

    fresh = SPMCache::Core::DiffDetector.new(project_path: project_path,
                                             lockfile_path: lockfile_path).detect
    expect(fresh).to be_empty

    packages = JSON.parse(File.read(lockfile_path))['Fake.xcodeproj']['packages']
    expect(packages.map { |pkg| pkg['name'] }).to contain_exactly('Drifted', 'Enriched', 'Newcomer')
    drifted = packages.find { |pkg| pkg['name'] == 'Drifted' }
    expect(drifted['version']).to eq('3.0.0')
    expect(drifted['revision']).to eq('rev-new')
    expect(packages.find { |pkg| pkg['name'] == 'Enriched' }['products']).to eq(enriched_products)
  end
end
