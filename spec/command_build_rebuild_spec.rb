# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'stringio'
require 'json'

# D-01/A8: the forced-rebuild scope as genuine, terminal-visible CLI surface.
# Installer::Build's `rebuild:` kwarg widens the candidate set into the full
# cachemap `hit` set while the default path, the requested-target filter, and
# the ignore/cache_only warnings stay byte-identical -- the planner-pinned
# spec file named by 15-VALIDATION's A8 row.
RSpec.describe SPMCache::Installer::Build, 'forced-rebuild selection (D-01)' do
  let(:tmpdir) { Dir.mktmpdir }
  let(:project_path) { File.join(tmpdir, 'Fake.xcodeproj') }

  # CachedLib: a genuine complete hit (on-disk xcframework carrying the
  # requested slice) -- skipped by default, rebuilt only when forced.
  # IncompleteLib: a hit whose xcframework is entirely absent from disk (the
  # installer_build_spec "entirely absent from disk" pattern) -- already
  # rebuilt today via the incomplete-slice top-up, so forcing it a second
  # time (via the full hit set below) is exactly the duplication risk
  # `missed.uniq!` must still catch (example 5).
  let(:cachemap) do
    SPMCache::Cache::Cachemap.new(
      graph_data: [
        { 'module' => 'Alamofire', 'status' => 'missed' },
        { 'module' => 'SnapKit', 'status' => 'missed' },
        { 'module' => 'CachedLib', 'status' => 'hit' },
        { 'module' => 'IncompleteLib', 'status' => 'hit' },
        { 'module' => 'VolatileLib', 'status' => 'ignored' },
        { 'module' => 'ExcludedLib', 'status' => 'excluded' }
      ]
    )
  end

  before do
    FileUtils.mkdir_p(project_path)
    FileUtils.mkdir_p(File.join(tmpdir, 'CachedLib.xcframework', 'ios-arm64-simulator'))
    # IncompleteLib intentionally gets no on-disk xcframework at all.

    allow_any_instance_of(SPMCache::Installer).to receive(:perform_install).and_wrap_original do |original, *_args|
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

  def make_installer(targets: [], rebuild: false)
    described_class.new(project: project_path, targets: targets, rebuild: rebuild)
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end

  it 'builds every missed package AND the complete cache hit when forced' do
    output = capture_stdout { make_installer(rebuild: true).perform_install }
    expect(output).to match(/Building 4 target/)
    expect(output).to match(/CachedLib/)
  end

  it 'leaves the default selection unchanged without the flag' do
    output = capture_stdout { make_installer(rebuild: false).perform_install }
    expect(output).to match(/Building 3 target/)
    expect(output).not_to match(/CachedLib/)
  end

  it 'still narrows to the single requested target when forced' do
    output = capture_stdout { make_installer(targets: ['CachedLib'], rebuild: true).perform_install }
    expect(output).to match(/Building 1 target.*: CachedLib/)
  end

  it 'does not pull ignored or excluded packages into the forced build set' do
    expect { make_installer(targets: ['VolatileLib'], rebuild: true).perform_install }
      .to output(/'VolatileLib' is in the ignore list; skipping/).to_stderr
    expect { make_installer(targets: ['ExcludedLib'], rebuild: true).perform_install }
      .to output(/'ExcludedLib' is excluded by cache_only; skipping/).to_stderr
  end

  it 'does not duplicate a package present in both the missed top-up and the forced hit set' do
    output = capture_stdout { make_installer(rebuild: true).perform_install }
    expect(output.scan(/IncompleteLib/).size).to eq(1)
  end
end

# A8: the flag is declared on Command::Build's option table and reaches the
# installer through an explicit constructor pass-through -- no second verb,
# no env-driven behavior (Pitfall 7 keeps the trigger marker
# attribution-only). CLI-level: the installer construction is spied so no
# real build runs.
RSpec.describe SPMCache::Command::Build, '--rebuild CLI surface (A8)' do
  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end

  def with_swapped_streams
    old_out = $stdout
    old_err = $stderr
    $stdout = StringIO.new
    $stderr = StringIO.new
    yield
  ensure
    $stdout = old_out
    $stderr = old_err
  end

  it 'constructs Installer::Build with the forced scope only when the flag is parsed' do
    allow(Dir).to receive(:glob).with('*.xcodeproj').and_return(['Fake.xcodeproj'])
    forced = instance_double(SPMCache::Installer::Build, perform_install: nil)
    plain = instance_double(SPMCache::Installer::Build, perform_install: nil)
    allow(SPMCache::Installer::Build).to receive(:new)
      .with(project: 'Fake.xcodeproj', config: 'debug', targets: [], rebuild: true).and_return(forced)
    allow(SPMCache::Installer::Build).to receive(:new)
      .with(project: 'Fake.xcodeproj', config: 'debug', targets: [], rebuild: false).and_return(plain)

    capture_stdout { SPMCache::Command.parse(['build', '--rebuild']).run }
    capture_stdout { SPMCache::Command.parse(['build']).run }

    expect(SPMCache::Installer::Build).to have_received(:new).with(hash_including(rebuild: true))
    expect(SPMCache::Installer::Build).to have_received(:new).with(hash_including(rebuild: false))
  end

  it 'declares --rebuild in the option table alongside --recursive' do
    option_names = SPMCache::Command::Build.options.map(&:first)
    expect(option_names).to include('--rebuild')
    expect(option_names).to include('--recursive')
  end

  it 'combines with a target argument and the existing recursive flag regardless of argv order' do
    cmd1 = SPMCache::Command.parse(['build', '--rebuild', 'SomeTarget', '--recursive'])
    cmd2 = SPMCache::Command.parse(['build', 'SomeTarget', '--recursive', '--rebuild'])

    [cmd1, cmd2].each do |cmd|
      expect(cmd.instance_variable_get(:@targets)).to eq(['SomeTarget'])
      expect(cmd.instance_variable_get(:@rebuild)).to be(true)
      expect(cmd.instance_variable_get(:@recursive)).to be(true)
    end
  end

  it 'records --rebuild in the run-log header argv (A8 self-documenting argv row)' do
    allow(SPMCache::Command).to receive(:run)
    Dir.mktmpdir do |log_dir|
      argv = ["--log-dir=#{log_dir}", 'build', '--rebuild']
      with_swapped_streams { SPMCache::Main.run(argv) }

      file = Dir.glob(File.join(log_dir, '*.jsonl')).first
      header = JSON.parse(File.readlines(file).first)
      expect(header['argv']).to eq(argv)
    end
  end
end
