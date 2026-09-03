# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'json'

# Unit-tests Installer::Build target-selection logic with a stubbed Cachemap.
# No real xcodebuild is invoked; the build pipeline is not exercised here.
RSpec.describe SPMCache::Installer::Build do
  let(:tmpdir) { Dir.mktmpdir }
  let(:project_path) { File.join(tmpdir, 'Fake.xcodeproj') }

  before do
    FileUtils.mkdir_p(project_path)
    # CachedLib is "hit" per the cachemap below; give it a real on-disk
    # xcframework with a simulator slice so it is a genuine complete cache
    # hit, not a hit-by-metadata-only miss (slice_complete? forces a rebuild
    # when the framework directory is absent from disk, #CR-02).
    FileUtils.mkdir_p(File.join(tmpdir, 'CachedLib.xcframework', 'ios-arm64-simulator'))
    # Stub out the heavy Installer#perform_install steps so we can isolate
    # the selection logic added in Phase 2.
    allow_any_instance_of(SPMCache::Installer).to receive(:perform_install).and_wrap_original do |original, *args, &block|
      me = original.receiver
      me.instance_variable_set(:@cachemap, cachemap) if me.respond_to?(:cachemap)
      nil
    end
    allow_any_instance_of(SPMCache::Installer::Build).to receive(:resolve_umbrella_checkouts).and_return(nil)
    allow_any_instance_of(SPMCache::Installer::Build).to receive(:checkout_map).and_return({})
    allow_any_instance_of(SPMCache::Installer::Build).to receive(:build_single_target).and_return(nil)
    allow(SPMCache::Core::Config.instance).to receive(:ignore_build_errors?).and_return(false)
    allow(SPMCache::Core::Config.instance).to receive(:default_sdk).and_return('iphonesimulator')
    allow(SPMCache::Core::Config.instance).to receive(:cache_dir).and_return(tmpdir)
  end

  after { FileUtils.rm_rf(tmpdir) }

  let(:cachemap) do
    SPMCache::Cache::Cachemap.new(
      graph_data: [
        { 'module' => 'Alamofire', 'status' => 'missed' },
        { 'module' => 'SnapKit', 'status' => 'missed' },
        { 'module' => 'CachedLib', 'status' => 'hit' },
        { 'module' => 'VolatileLib', 'status' => 'ignored' },
        { 'module' => 'ExcludedLib', 'status' => 'excluded' }
      ]
    )
  end

  def make_installer(targets: [])
    described_class.new(project: project_path, targets: targets)
  end

  it 'builds all missed targets when no TARGETS given' do
    inst = make_installer(targets: [])
    expect { inst.perform_install }.to output(/Building 2 target.*Alamofire.*SnapKit/m).to_stdout
  end

  it 'filters to only requested missed targets' do
    inst = make_installer(targets: ['Alamofire'])
    expect { inst.perform_install }.to output(/Building 1 target.*: Alamofire/).to_stdout
  end

  it 'warns on unknown target' do
    inst = make_installer(targets: ['Nonexistent'])
    expect do
      expect { inst.perform_install }.to output(/No targets to build/).to_stdout
    end.to output(/unknown target 'Nonexistent'/).to_stderr
  end

  it 'warns when requested target is ignored' do
    inst = make_installer(targets: ['VolatileLib'])
    expect { inst.perform_install }.to output(/'VolatileLib' is in the ignore list; skipping/).to_stderr
  end

  it 'warns when requested target is excluded by cache_only, not mislabeled unknown' do
    inst = make_installer(targets: ['ExcludedLib'])
    expect { inst.perform_install }.to output(/'ExcludedLib' is excluded by cache_only; skipping/).to_stderr
    expect { inst.perform_install }.not_to output(/unknown target 'ExcludedLib'/).to_stderr
  end

  it 'does not build already-hit targets' do
    inst = make_installer(targets: ['CachedLib'])
    expect { inst.perform_install }.to output(/unknown target 'CachedLib'|No targets to build/).to_stdout
  end

  # D-04/LOGS-01: the build phase marker + run_log threading from
  # Installer::Build#perform_install. With RunLog.current nil (every other
  # example here) the marker call and the threaded run_log are no-ops.
  describe 'run-log phase markers (D-04)' do
    let(:marker_runs_dir) { File.join(tmpdir, 'runs') }

    def with_current_run_log
      log = SPMCache::Core::RunLog.open(runs_dir: marker_runs_dir, command: 'build')
      yield log
    ensure
      log&.finish(0)
    end

    def events_in(log)
      File.read(log.path).lines.map { |line| JSON.parse(line) }.select { |line| line.key?('event') }
    end

    it 'emits the build phase marker before the missed.each loop' do
      with_current_run_log do |log|
        inst = make_installer(targets: [])
        expect { inst.perform_install }.to output(/Building 2 target/).to_stdout
        phases = events_in(log).select { |e| e['event'] == 'phase' }.map { |e| e['name'] }
        expect(phases).to eq(['build'])
      end
    end

    it 'emits the build marker on an empty missed set with zero package events (EDGE empty zero-pins)' do
      hit_only = SPMCache::Cache::Cachemap.new(
        graph_data: [
          { 'module' => 'CachedLib', 'status' => 'hit' },
          { 'module' => 'ExcludedLib', 'status' => 'excluded' }
        ]
      )
      allow_any_instance_of(SPMCache::Installer).to receive(:perform_install).and_wrap_original do |original, *args, &block|
        me = original.receiver
        me.instance_variable_set(:@cachemap, hit_only) if me.respond_to?(:cachemap)
        nil
      end

      with_current_run_log do |log|
        expect(SPMCache::SPM::BuildPipeline).not_to receive(:run)
        inst = make_installer(targets: [])
        expect { inst.perform_install }.to output(/No targets to build/).to_stdout

        events = events_in(log)
        expect(events.select { |e| e['event'] == 'phase' }.map { |e| e['name'] }).to eq(['build'])
        expect(events.none? { |e| %w[package_start package_end].include?(e['event']) }).to be(true)
      end
    end

    it 'threads Core::RunLog.current into every BuildPipeline.run call (Task 12-04-01 call site)' do
      alamofire_dir = File.join(tmpdir, 'checkouts', 'Alamofire')
      snapkit_dir = File.join(tmpdir, 'checkouts', 'SnapKit')
      FileUtils.mkdir_p(alamofire_dir)
      FileUtils.mkdir_p(snapkit_dir)
      allow_any_instance_of(SPMCache::Installer::Build).to receive(:checkout_map)
        .and_return('Alamofire' => alamofire_dir, 'SnapKit' => snapkit_dir)
      allow_any_instance_of(SPMCache::Installer::Build).to receive(:build_single_target).and_call_original
      allow(SPMCache::SPM::BuildPipeline).to receive(:run).and_return(File.join(tmpdir, 'fake.xcframework'))

      with_current_run_log do |log|
        inst = make_installer(targets: [])
        inst.perform_install

        expect(SPMCache::SPM::BuildPipeline).to have_received(:run)
          .with(hash_including(run_log: log)).twice
      end
    end
  end
end

# Regression coverage for the per-product CLI/graph granularity change: a
# package identity (the pre-Phase-2 target name) must still work as an alias
# that expands to all of that package's real product names.
RSpec.describe SPMCache::Installer::Build, 'package-identity alias expansion' do
  let(:tmpdir) { Dir.mktmpdir }
  let(:project_path) { File.join(tmpdir, 'Fake.xcodeproj') }

  let(:cachemap) do
    SPMCache::Cache::Cachemap.new(
      graph_data: [
        { 'module' => 'Realm', 'status' => 'missed' },
        { 'module' => 'RealmSwift', 'status' => 'missed' }
      ]
    )
  end

  let(:lockfile_data) do
    {
      'Fake.xcodeproj' => {
        'packages' => [
          {
            'repositoryURL' => 'https://github.com/realm/realm-swift.git',
            'name' => 'realm-swift',
            'products' => [
              { 'name' => 'Realm', 'type' => 'library', 'targets' => ['Realm'] },
              { 'name' => 'RealmSwift', 'type' => 'library', 'targets' => ['RealmSwift'] }
            ]
          }
        ],
        'dependencies' => {},
        'platforms' => { 'ios' => '16.0' }
      }
    }
  end

  before do
    FileUtils.mkdir_p(project_path)
    lockfile_path = File.join(tmpdir, 'spm-cache.lock')
    File.write(lockfile_path, JSON.generate(lockfile_data))
    lockfile = SPMCache::Core::Lockfile.new(lockfile_path)

    allow_any_instance_of(SPMCache::Installer).to receive(:perform_install).and_wrap_original do |original, *args, &block|
      me = original.receiver
      if me.respond_to?(:cachemap)
        me.instance_variable_set(:@cachemap, cachemap)
        me.instance_variable_set(:@lockfile, lockfile)
      end
      nil
    end
    allow_any_instance_of(SPMCache::Installer::Build).to receive(:resolve_umbrella_checkouts).and_return(nil)
    allow_any_instance_of(SPMCache::Installer::Build).to receive(:checkout_map).and_return({})
    allow_any_instance_of(SPMCache::Installer::Build).to receive(:build_single_target).and_return(nil)
    allow(SPMCache::Core::Config.instance).to receive(:ignore_build_errors?).and_return(false)
    allow(SPMCache::Core::Config.instance).to receive(:default_sdk).and_return('iphonesimulator')
    allow(SPMCache::Core::Config.instance).to receive(:cache_dir).and_return(tmpdir)
  end

  after { FileUtils.rm_rf(tmpdir) }

  it 'expands a requested package identity to all of its real product names' do
    inst = described_class.new(project: project_path, targets: ['realm-swift'])
    expect { inst.perform_install }.to output(/Building 2 target.*Realm.*RealmSwift/m).to_stdout
  end

  it 'still accepts a real product name directly' do
    inst = described_class.new(project: project_path, targets: ['RealmSwift'])
    expect { inst.perform_install }.to output(/Building 1 target.*: RealmSwift/).to_stdout
  end
end

# Regression coverage: a mixed library+plugin package's identity must expand
# to ONLY its library product (the plugin product never reaches graph.json),
# not silently produce a spurious "unknown target" warning for the plugin
# product name.
RSpec.describe SPMCache::Installer::Build, 'package-identity alias expansion (mixed library+plugin package)' do
  let(:tmpdir) { Dir.mktmpdir }
  let(:project_path) { File.join(tmpdir, 'Fake.xcodeproj') }

  let(:cachemap) do
    SPMCache::Cache::Cachemap.new(graph_data: [{ 'module' => 'MixedLib', 'status' => 'missed' }])
  end

  let(:lockfile_data) do
    {
      'Fake.xcodeproj' => {
        'packages' => [
          {
            'repositoryURL' => 'https://github.com/example/mixed-package.git',
            'name' => 'mixed-package',
            'products' => [
              { 'name' => 'MixedLib', 'type' => 'library', 'targets' => ['MixedLib'] },
              { 'name' => 'MixedPlugin', 'type' => 'plugin', 'targets' => ['MixedPlugin'] }
            ]
          }
        ],
        'dependencies' => {},
        'platforms' => { 'ios' => '16.0' }
      }
    }
  end

  before do
    FileUtils.mkdir_p(project_path)
    lockfile_path = File.join(tmpdir, 'spm-cache.lock')
    File.write(lockfile_path, JSON.generate(lockfile_data))
    lockfile = SPMCache::Core::Lockfile.new(lockfile_path)

    allow_any_instance_of(SPMCache::Installer).to receive(:perform_install).and_wrap_original do |original, *args, &block|
      me = original.receiver
      if me.respond_to?(:cachemap)
        me.instance_variable_set(:@cachemap, cachemap)
        me.instance_variable_set(:@lockfile, lockfile)
      end
      nil
    end
    allow_any_instance_of(SPMCache::Installer::Build).to receive(:resolve_umbrella_checkouts).and_return(nil)
    allow_any_instance_of(SPMCache::Installer::Build).to receive(:checkout_map).and_return({})
    allow_any_instance_of(SPMCache::Installer::Build).to receive(:build_single_target).and_return(nil)
    allow(SPMCache::Core::Config.instance).to receive(:ignore_build_errors?).and_return(false)
    allow(SPMCache::Core::Config.instance).to receive(:default_sdk).and_return('iphonesimulator')
    allow(SPMCache::Core::Config.instance).to receive(:cache_dir).and_return(tmpdir)
  end

  after { FileUtils.rm_rf(tmpdir) }

  it 'expands the package identity to only its library product, not the plugin product' do
    inst = described_class.new(project: project_path, targets: ['mixed-package'])
    expect { inst.perform_install }.to output(/Building 1 target.*: MixedLib/).to_stdout
    expect { inst.perform_install }.not_to output(/unknown target 'MixedPlugin'/).to_stderr
  end
end

# Exercises the umbrella resolve fallback (issue #3) with a fresh top-level
# describe so it does NOT inherit the outer spec's
# `resolve_umbrella_checkouts` stub - the whole point here is to drive the
# real rescue/fallback path.
RSpec.describe SPMCache::Installer::Build, 'umbrella resolve fallback (issue #3)' do
  let(:project_tmpdir) { Dir.mktmpdir }
  let(:project_path) { File.join(project_tmpdir, 'Fake.xcodeproj') }
  let(:fake_home) { Dir.mktmpdir }
  let(:derived_data_dir) { File.join(fake_home, 'Library', 'Developer', 'Xcode', 'DerivedData') }

  before do
    FileUtils.mkdir_p(project_path)
    FileUtils.mkdir_p(derived_data_dir)
    @original_home = ENV['HOME']
    ENV['HOME'] = fake_home
    allow(SPMCache::Core::Sh).to receive(:run).and_raise(SPMCache::Core::GeneralError.new('resolve boom'))
  end

  after do
    ENV['HOME'] = @original_home
    FileUtils.rm_rf(project_tmpdir)
    FileUtils.rm_rf(fake_home)
  end

  def make_installer
    described_class.new(project: project_path)
  end

  def umbrella_checkouts_dir(installer)
    File.join(installer.config.umbrella_dir, '.build', 'checkouts')
  end

  def write_derived_data_checkout(derived_data_dir_name, marker_content, mtime:)
    dd_dir = File.join(derived_data_dir, derived_data_dir_name)
    checkout_dir = File.join(dd_dir, 'SourcePackages', 'checkouts', 'Alamofire')
    FileUtils.mkdir_p(checkout_dir)
    File.write(File.join(checkout_dir, 'marker.txt'), marker_content)
    File.utime(mtime, mtime, dd_dir)
    dd_dir
  end

  it 'copies checkouts from the newest matching DerivedData dir, not the first glob match' do
    write_derived_data_checkout('Fake-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'stale', mtime: Time.now - 3600)
    write_derived_data_checkout('Fake-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', 'fresh', mtime: Time.now)

    inst = make_installer
    expect { inst.send(:resolve_umbrella_checkouts) }.to output(/Umbrella resolve failed/).to_stderr

    copied_marker = File.join(umbrella_checkouts_dir(inst), 'Alamofire', 'marker.txt')
    expect(File.read(copied_marker)).to eq('fresh')
  end

  it 'escalates the warning when no DerivedData checkouts match the project' do
    inst = make_installer

    expect { inst.send(:resolve_umbrella_checkouts) }.to output(
      /Umbrella resolve failed and no DerivedData checkouts found; all targets will be skipped/
    ).to_stderr
    expect(Dir.glob(File.join(umbrella_checkouts_dir(inst), '*'))).to be_empty
  end

  it 'does not escalate the warning when the fallback finds checkouts' do
    write_derived_data_checkout('Fake-cccccccccccccccccccccccccccccccc', 'ok', mtime: Time.now)

    inst = make_installer

    expect { inst.send(:resolve_umbrella_checkouts) }.not_to output(
      /no DerivedData checkouts found/
    ).to_stderr
  end
end

# Regression: a cached xcframework missing a slice for a requested destination
# (e.g. sim-only under --sdk=all) must be rebuilt, not skipped as a "hit".
RSpec.describe SPMCache::Installer::Build, 'slice-aware rebuild of incomplete hits' do
  let(:tmpdir) { Dir.mktmpdir }
  let(:project_path) { File.join(tmpdir, 'Fake.xcodeproj') }

  let(:cachemap) do
    SPMCache::Cache::Cachemap.new(
      graph_data: [
        { 'module' => 'SimOnlyLib', 'status' => 'hit' },
        { 'module' => 'CompleteLib', 'status' => 'hit' }
      ]
    )
  end

  before do
    FileUtils.mkdir_p(project_path)
    FileUtils.mkdir_p(File.join(tmpdir, 'SimOnlyLib.xcframework', 'ios-arm64-simulator'))
    FileUtils.mkdir_p(File.join(tmpdir, 'CompleteLib.xcframework', 'ios-arm64-simulator'))
    FileUtils.mkdir_p(File.join(tmpdir, 'CompleteLib.xcframework', 'ios-arm64'))

    allow_any_instance_of(SPMCache::Installer).to receive(:perform_install).and_wrap_original do |original, *args|
      me = original.receiver
      me.instance_variable_set(:@cachemap, cachemap) if me.respond_to?(:cachemap)
      nil
    end
    allow_any_instance_of(SPMCache::Installer::Build).to receive(:resolve_umbrella_checkouts).and_return(nil)
    allow_any_instance_of(SPMCache::Installer::Build).to receive(:checkout_map).and_return({})
    allow_any_instance_of(SPMCache::Installer::Build).to receive(:build_single_target).and_return(nil)
    allow(SPMCache::Core::Config.instance).to receive(:ignore_build_errors?).and_return(false)
    allow(SPMCache::Core::Config.instance).to receive(:default_sdk).and_return('all')
    allow(SPMCache::Core::Config.instance).to receive(:cache_dir).and_return(tmpdir)
  end

  after { FileUtils.rm_rf(tmpdir) }

  it 'rebuilds a hit package missing the device slice, but skips a complete one' do
    inst = described_class.new(project: project_path)
    expect { inst.perform_install }.to output(/Building 1 target.*: SimOnlyLib/).to_stdout
  end

  it 'rebuilds a hit package whose xcframework directory is entirely absent from disk' do
    FileUtils.rm_rf(File.join(tmpdir, 'CompleteLib.xcframework'))
    inst = described_class.new(project: project_path)
    expect { inst.perform_install }.to output(/Building 2 target.*SimOnlyLib.*CompleteLib/m).to_stdout
  end
end

# D-07: with no umbrella Package.resolved AND no host graph findable anywhere,
# SPM::ResolvedGraph.source_for returns nil, and that nil must thread through
# to every SPM::BuildPipeline.run call for the run -- the exact
# "seeding disabled (default)" case.
RSpec.describe SPMCache::Installer::Build, 'no host graph found threads resolved_pins_file: nil' do
  let(:tmpdir) { Dir.mktmpdir }
  let(:project_path) { File.join(tmpdir, 'Fake.xcodeproj') }

  let(:cachemap) do
    SPMCache::Cache::Cachemap.new(graph_data: [{ 'module' => 'Alamofire', 'status' => 'missed' }])
  end

  before do
    FileUtils.mkdir_p(project_path)
    alamofire_dir = File.join(tmpdir, 'checkouts', 'Alamofire')
    FileUtils.mkdir_p(alamofire_dir)
    allow_any_instance_of(SPMCache::Installer).to receive(:perform_install).and_wrap_original do |original, *_args|
      me = original.receiver
      me.instance_variable_set(:@cachemap, cachemap) if me.respond_to?(:cachemap)
      nil
    end
    allow_any_instance_of(SPMCache::Installer::Build).to receive(:resolve_umbrella_checkouts).and_return(nil)
    allow_any_instance_of(SPMCache::Installer::Build).to receive(:checkout_map).and_return('Alamofire' => alamofire_dir)
    allow(SPMCache::Core::Config.instance).to receive(:ignore_build_errors?).and_return(false)
    allow(SPMCache::Core::Config.instance).to receive(:default_sdk).and_return('iphonesimulator')
    allow(SPMCache::Core::Config.instance).to receive(:cache_dir).and_return(tmpdir)
    allow(SPMCache::Core::Config.instance).to receive(:umbrella_dir).and_return(File.join(tmpdir, 'umbrella'))
  end

  after { FileUtils.rm_rf(tmpdir) }

  it 'threads resolved_pins_file: nil into BuildPipeline.run when source_for finds nothing' do
    allow(SPMCache::SPM::ResolvedGraph).to receive(:source_for).and_return(nil)
    allow(SPMCache::SPM::BuildPipeline).to receive(:run).and_return('/out/fake.xcframework')

    described_class.new(project: project_path, targets: []).perform_install

    expect(SPMCache::SPM::BuildPipeline).to have_received(:run).with(hash_including(resolved_pins_file: nil))
  end
end
