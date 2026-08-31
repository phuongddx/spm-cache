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

  describe 'preservation and safe degradation' do
    it 'preserves products' do
      write_canonical_pins([{ identity: 'alpha', url: alpha_url, version: '2.0.0', revision: 'rev-new' }])
      write_lock([{ 'repositoryURL' => alpha_url, 'name' => 'alpha', 'version' => '1.0.0',
                    'revision' => 'rev-old', 'products' => alpha_products }])

      run_sync

      expect(locked_packages.first['products']).to eq(alpha_products)
      expect(locked_packages.first['version']).to eq('2.0.0')
    end

    it 'leaves dependencies platforms and version stamp untouched' do
      write_canonical_pins([{ identity: 'alpha', url: alpha_url, version: '2.0.0', revision: 'rev-new' }])
      write_lock([{ 'repositoryURL' => alpha_url, 'name' => 'alpha', 'version' => '1.0.0',
                    'revision' => 'rev-old', 'branch' => 'main' }],
                 extra: { 'dependencies' => { 'MyApp' => ['Alpha'] }, 'spm_cache_version' => '0.0.1-frozen' })

      run_reconcile_only

      proj = locked_project
      expect(proj['dependencies']).to eq({ 'MyApp' => ['Alpha'] })
      expect(proj['platforms']).to eq({ 'ios' => '16.0' })
      expect(proj['spm_cache_version']).to eq('0.0.1-frozen')
      expect(proj['packages'].first['branch']).to eq('main')
      expect(proj['packages'].first['version']).to eq('2.0.0')
    end

    it 'leaves the lock untouched when Package.resolved is unreadable' do
      write_canonical_raw('{"version": 3, "pins": [')
      write_lock([{ 'repositoryURL' => alpha_url, 'name' => 'alpha', 'version' => '1.0.0',
                    'revision' => 'rev-old' }])
      before_bytes = File.binread(lockfile_path)

      expect(SPMCache::Core::UI).to receive(:warn).once
      run_reconcile_only(diff: non_empty_diff)

      expect(File.binread(lockfile_path)).to eq(before_bytes)
    end

    it 'leaves the lock untouched when Package.resolved is missing' do
      write_lock([{ 'repositoryURL' => alpha_url, 'name' => 'alpha', 'version' => '1.0.0',
                    'revision' => 'rev-old' }])
      before_bytes = File.binread(lockfile_path)

      expect(SPMCache::Core::UI).to receive(:warn).once
      run_reconcile_only

      expect(File.binread(lockfile_path)).to eq(before_bytes)
    end

    it 'does not clear an existing revision when the host pin has none' do
      write_canonical_pins([{ identity: 'alpha', url: alpha_url, version: '2.0.0' }])
      write_lock([{ 'repositoryURL' => alpha_url, 'name' => 'alpha', 'version' => '1.0.0',
                    'revision' => 'rev-old' }])

      run_sync

      expect(locked_packages.first['version']).to eq('2.0.0')
      expect(locked_packages.first['revision']).to eq('rev-old')
    end

    it 'does not write when the diff is empty' do
      write_canonical_pins([{ identity: 'alpha', url: alpha_url, version: '1.0.0', revision: 'rev-old' }])
      write_lock([{ 'repositoryURL' => alpha_url, 'name' => 'alpha', 'version' => '1.0.0',
                    'revision' => 'rev-old' }])
      before_bytes = File.binread(lockfile_path)
      before_mtime = File.mtime(lockfile_path)

      installer = run_reconcile_only

      expect(installer.diff).to be_empty
      expect(File.binread(lockfile_path)).to eq(before_bytes)
      expect(File.mtime(lockfile_path)).to eq(before_mtime)
    end

    it 'reconciles a project whose lock key differs from the project basename' do
      write_canonical_pins([{ identity: 'alpha', url: alpha_url, version: '2.0.0', revision: 'rev-new' }])
      write_lock([{ 'repositoryURL' => alpha_url, 'name' => 'alpha', 'version' => '1.0.0',
                    'revision' => 'rev-old' }],
                 project_key: 'Fake')

      run_sync

      expect(locked_packages('Fake').first['version']).to eq('2.0.0')
      expect(locked_packages('Fake').first['revision']).to eq('rev-new')
    end

    it 'skips the drop pass when the host graph has zero pins but the lock has remote entries' do
      write_canonical_raw(JSON.generate('object' => { 'pins' => [{ 'package' => 'Alpha' }] }))
      write_lock([
                   { 'repositoryURL' => alpha_url, 'name' => 'alpha', 'version' => '1.0.0',
                     'revision' => 'rev-old' },
                   { 'repositoryURL' => gamma_url, 'name' => 'gamma', 'version' => '3.0.0',
                     'revision' => 'rev-gamma' }
                 ])

      expect(SPMCache::Core::UI).to receive(:warn).once
      run_reconcile_only

      expect(locked_names).to contain_exactly('alpha', 'gamma')
    end
  end

  # A SwiftPM-rooted directory with a generated Xcode project keeps its resolved
  # file beside the `.xcodeproj`, so tiers 1-3 all miss and only the locator's
  # parent-directory tier answers. DiffDetector reached that tier while the
  # installer did not, so the detector reported drift the reconciler declined to
  # close -- permanently, on every subsequent run.
  describe 'parent-directory tier project shape' do
    def parent_tier_resolved(version:, revision:)
      write_resolved(File.join(tmpdir, 'Package.resolved'), version: version, revision: revision)
    end

    def parent_tier_raw(content)
      path = File.join(tmpdir, 'Package.resolved')
      File.write(path, content)
      path
    end

    def fresh_diff
      SPMCache::Core::DiffDetector.new(project_path: project_path, lockfile_path: lockfile_path).detect
    end

    it 'reconciles a project whose host graph is reachable only through the parent-directory tier' do
      parent_tier_resolved(version: '2.0.0', revision: 'rev-new')
      write_lock([{ 'repositoryURL' => alpha_url, 'name' => 'alpha', 'version' => '1.0.0',
                    'revision' => 'rev-old' }])

      expect(SPMCache::Core::UI).not_to receive(:warn)
      run_sync

      expect(locked_packages.first['version']).to eq('2.0.0')
      expect(locked_packages.first['revision']).to eq('rev-new')
      expect(fresh_diff).to be_empty
    end

    # The structural non-recurrence guard: this fails the moment any consumer
    # looks the host graph up independently, which is what makes the two sides
    # unable to diverge again rather than merely agreeing today.
    it 'resolves the host graph exactly once per run' do
      write_canonical_pins([{ identity: 'alpha', url: alpha_url, version: '2.0.0', revision: 'rev-new' }])
      write_lock([{ 'repositoryURL' => alpha_url, 'name' => 'alpha', 'version' => '1.0.0',
                    'revision' => 'rev-old' }])

      expect(SPMCache::Core::PackageResolved).to receive(:locate).once.and_call_original

      installer = described_class.new(project: project_path)
      installer.detect_diff
      installer.send(:sync_lockfile)

      expect(locked_packages.first['version']).to eq('2.0.0')
    end

    # A first run IS a non-fast-path run, so criterion 1 covers the no-lock-yet
    # half of this shape too: the seeding path used to find nothing and return,
    # after which the reconciler had no project entry to reconcile.
    it 'seeds a first-run lock from a host graph reachable only through the parent-directory tier' do
      parent_tier_resolved(version: '2.0.0', revision: 'rev-new')

      run_sync

      expect(File.exist?(lockfile_path)).to be(true)
      expect(locked_packages.length).to eq(1)
      expect(locked_packages.first['name']).to eq('alpha')
      expect(locked_packages.first['version']).to eq('2.0.0')
      expect(locked_packages.first['revision']).to eq('rev-new')
      expect(fresh_diff).to be_empty
    end

    # The posture pin: widening this site's REACH must not widen its TOLERANCE.
    # Degrading here would seed a lock claiming the project has no packages.
    it 'raises rather than seeding an empty lock when a parent-tier host graph is malformed' do
      parent_tier_raw('{"version": 3, "pins": [')

      expect { run_reconcile_only(diff: non_empty_diff) }.to raise_error(JSON::ParserError)
    end
  end
end
