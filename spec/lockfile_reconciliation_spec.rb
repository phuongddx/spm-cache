# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'json'
require 'xcodeproj'
require 'spm_cache/core/diff_detector'
require 'spm_cache/installer/use'

# FID-01 -- the lockfile the umbrella is generated from must describe the host
# project's CURRENT resolved graph. `generate_lockfile_from_resolved` writes
# only when no lock exists, so every package's version/revision stayed frozen
# at first creation and the umbrella pinned an abandoned snapshot forever.
RSpec.describe SPMCache::Installer::Use, '#sync_lockfile reconciliation' do
  let(:tmpdir) { Dir.mktmpdir }
  let(:project_path) { File.join(tmpdir, 'Fake.xcodeproj') }
  let(:lockfile_path) { File.join(tmpdir, 'spm-cache.lock') }
  let(:alpha_url) { 'https://github.com/example/alpha.git' }
  let(:gamma_url) { 'https://github.com/example/gamma.git' }
  let(:delta_url) { 'https://github.com/example/delta.git' }
  let(:alpha_products) { [{ 'name' => 'Alpha', 'type' => 'library', 'targets' => ['Alpha'] }] }

  before do
    SPMCache::Core::Config.instance.reset!
    SPMCache::Core::Config.instance.project_dir = tmpdir
    build_project
  end

  after { FileUtils.rm_rf(tmpdir) }

  def build_project
    project = Xcodeproj::Project.new(project_path)
    project.new_target(:application, 'MyApp', :ios)
    project.save
  end

  def write_resolved(path, version:, revision:)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.generate(
                       'version' => 3,
                       'pins' => [{
                         'identity' => 'alpha',
                         'kind' => 'remoteSourceControl',
                         'location' => alpha_url,
                         'state' => { 'revision' => revision, 'version' => version }
                       }]
                     ))
    path
  end

  def canonical_resolved(version:, revision:)
    write_resolved(File.join(project_path, SPMCache::Core::PackageResolved::CANONICAL_RELATIVE_PATH),
                   version: version, revision: revision)
  end

  # The stale nested bundle copy the legacy glob answered with.
  def nested_resolved(version:, revision:)
    write_resolved(
      File.join(project_path, 'Fake.xcodeproj', SPMCache::Core::PackageResolved::CANONICAL_RELATIVE_PATH),
      version: version, revision: revision
    )
  end

  def write_lockfile(version:, revision:, products: nil)
    pkg = { 'repositoryURL' => alpha_url, 'name' => 'alpha', 'version' => version, 'revision' => revision }
    pkg['products'] = products if products
    File.write(lockfile_path, JSON.pretty_generate(
                                'Fake.xcodeproj' => {
                                  'packages' => [pkg],
                                  'dependencies' => {},
                                  'platforms' => { 'ios' => '16.0' }
                                }
                              ))
  end

  def locked_alpha
    JSON.parse(File.read(lockfile_path))['Fake.xcodeproj']['packages'].first
  end

  def run_sync
    installer = described_class.new(project: project_path)
    installer.detect_diff
    installer.send(:sync_lockfile)
    installer
  end

  def add_local_refs(paths)
    project = Xcodeproj::Project.open(project_path)
    paths.each do |path|
      ref = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
      ref.relative_path = path
      project.root_object.package_references << ref
    end
    project.save
  end

  def pin_entry(spec)
    {
      'identity' => spec[:identity],
      'kind' => 'remoteSourceControl',
      'location' => spec[:url],
      'state' => { 'revision' => spec[:revision], 'version' => spec[:version] }.compact
    }
  end

  def write_canonical_pins(pins)
    path = File.join(project_path, SPMCache::Core::PackageResolved::CANONICAL_RELATIVE_PATH)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.generate('version' => 3, 'pins' => pins.map { |p| pin_entry(p) }))
    path
  end

  def write_canonical_raw(content)
    path = File.join(project_path, SPMCache::Core::PackageResolved::CANONICAL_RELATIVE_PATH)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    path
  end

  def write_lock(packages, project_key: 'Fake.xcodeproj', extra: {})
    File.write(lockfile_path, JSON.pretty_generate(
                                project_key => {
                                  'packages' => packages,
                                  'dependencies' => {},
                                  'platforms' => { 'ios' => '16.0' }
                                }.merge(extra)
                              ))
  end

  def locked_project(project_key = 'Fake.xcodeproj')
    JSON.parse(File.read(lockfile_path))[project_key]
  end

  def locked_packages(project_key = 'Fake.xcodeproj')
    locked_project(project_key)['packages']
  end

  def locked_names(project_key = 'Fake.xcodeproj')
    locked_packages(project_key).map { |pkg| pkg['name'] }
  end

  # Isolates the reconciler from `refresh_consumed_dependencies`, whose own save
  # would rewrite the file and mask a byte-identity assertion. `diff` is injected
  # only where `detect_diff` cannot run at all: DiffDetector's own
  # `live_packages` JSON.parses the host graph unguarded, so a truncated
  # Package.resolved raises there before reconciliation is ever reached.
  def run_reconcile_only(diff: nil)
    installer = described_class.new(project: project_path)
    allow(installer).to receive(:refresh_consumed_dependencies)
    if diff
      installer.instance_variable_set(:@diff, diff)
    else
      installer.detect_diff
    end
    installer.send(:sync_lockfile)
    installer
  end

  def non_empty_diff
    SPMCache::Core::DiffDetector::Diff.new(added: ['injected'], removed: [], updated: [])
  end

  it 'updates version and revision' do
    canonical_resolved(version: '2.0.0', revision: 'rev-new')
    write_lockfile(version: '1.0.0', revision: 'rev-old')

    run_sync

    expect(locked_alpha['version']).to eq('2.0.0')
    expect(locked_alpha['revision']).to eq('rev-new')
  end

  # The nested copy here agrees with the stale lock, so a reconciler reading it
  # would be a no-op AND would still leave DiffDetector reporting empty -- two
  # components agreeing on the wrong file. The version/revision assertions are
  # what make the empty-diff assertion non-vacuous.
  it 'reconciles a single drifted package end to end and leaves DiffDetector reporting an empty diff' do
    canonical_resolved(version: '2.0.0', revision: 'rev-new')
    nested_resolved(version: '1.0.0', revision: 'rev-old')
    write_lockfile(version: '1.0.0', revision: 'rev-old', products: alpha_products)

    installer = run_sync
    expect(installer.diff).not_to be_empty

    expect(locked_alpha['version']).to eq('2.0.0')
    expect(locked_alpha['revision']).to eq('rev-new')
    expect(locked_alpha['products']).to eq(alpha_products)

    fresh = SPMCache::Core::DiffDetector.new(project_path: project_path, lockfile_path: lockfile_path).detect
    expect(fresh).to be_empty
  end

  describe 'membership' do
    it 'drops a package absent from the host graph' do
      write_canonical_pins([{ identity: 'alpha', url: alpha_url, version: '2.0.0', revision: 'rev-new' }])
      write_lock([
                   { 'repositoryURL' => alpha_url, 'name' => 'alpha', 'version' => '1.0.0',
                     'revision' => 'rev-old' },
                   { 'repositoryURL' => gamma_url, 'name' => 'gamma', 'version' => '3.0.0',
                     'revision' => 'rev-gamma' }
                 ])

      run_sync

      expect(locked_names).to eq(['alpha'])
    end

    it 'adds a new package without a products key' do
      write_canonical_pins([
                             { identity: 'alpha', url: alpha_url, version: '1.0.0', revision: 'rev-old' },
                             { identity: 'delta', url: delta_url, version: '4.1.0', revision: 'rev-delta' }
                           ])
      write_lock([{ 'repositoryURL' => alpha_url, 'name' => 'alpha', 'version' => '1.0.0',
                    'revision' => 'rev-old' }])

      run_sync

      delta = locked_packages.find { |pkg| pkg['name'] == 'delta' }
      expect(delta).not_to be_nil
      expect(delta.keys).to eq(%w[repositoryURL name version revision])
      expect(delta['repositoryURL']).to eq(delta_url)
      expect(delta['version']).to eq('4.1.0')
      expect(delta['revision']).to eq('rev-delta')
      # `[]` is truthy, so a present-but-empty products key would make
      # enrich_lockfile_products skip this package forever.
      expect(delta.key?('products')).to be(false)
    end

    it 'keeps a local package absent from Package.resolved' do
      add_local_refs(['LocalPackages/core-utils'])
      write_canonical_pins([{ identity: 'alpha', url: alpha_url, version: '2.0.0', revision: 'rev-new' }])
      write_lock([
                   { 'repositoryURL' => alpha_url, 'name' => 'alpha', 'version' => '1.0.0',
                     'revision' => 'rev-old' },
                   { 'path_from_root' => 'LocalPackages/core-utils', 'name' => 'core-utils' }
                 ])

      run_sync

      local = locked_packages.find { |pkg| pkg['name'] == 'core-utils' }
      expect(local).not_to be_nil
      expect(local['path_from_root']).to eq('LocalPackages/core-utils')
      expect(local).not_to have_key('repositoryURL')
      expect(locked_names).to include('alpha')
    end

    it 'does not resurrect the spm-cache proxy ref as a dependency' do
      add_local_refs([File.join('spm-cache', 'packages', 'proxy')])
      write_canonical_pins([{ identity: 'alpha', url: alpha_url, version: '2.0.0', revision: 'rev-new' }])
      write_lock([{ 'repositoryURL' => alpha_url, 'name' => 'alpha', 'version' => '1.0.0',
                    'revision' => 'rev-old' }])

      run_sync

      expect(locked_names).to eq(['alpha'])
    end

    it 'matches identity across url spelling variants' do
      write_canonical_pins([{ identity: 'repo', url: 'https://github.com/org/Repo', version: '2.0.0',
                              revision: 'rev-new' }])
      write_lock([{ 'repositoryURL' => 'git@github.com:org/Repo.git', 'name' => 'Repo', 'version' => '1.0.0',
                    'revision' => 'rev-old' }])

      run_sync

      expect(locked_packages.length).to eq(1)
      expect(locked_packages.first['repositoryURL']).to eq('git@github.com:org/Repo.git')
      expect(locked_packages.first['version']).to eq('2.0.0')
      expect(locked_packages.first['revision']).to eq('rev-new')
    end
  end
end
