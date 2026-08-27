# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'tmpdir'
require 'xcodeproj'
require 'spm_cache/core/diagnostics'

# Two-layer doctor coverage:
# - Registry mechanics and the text/JSON formatters are exercised through the
#   Command; the live-host examples below assert report shape with tolerant
#   verdicts (environment-dependent statuses are never hardcoded).
# - Shell-probing checks are exercised hermetically by injecting stubbed
#   shell-output collectors over the existing Core::Sh seam
#   (allow(SPMCache::Core::Sh).to receive(:capture_output)), asserting exact
#   ok/warn/fail verdict paths and messages without a real Xcode install.
RSpec.describe SPMCache::Core::Diagnostics do
  it 'registers built-in checks' do
    names = described_class.registry.map(&:name)
    expect(names).to include(
      'xcode_version', 'swift_version', 'toolchain_path',
      'cache_dir_health', 'library_evolution_compatibility',
      'remote_backend_connectivity', 'companion_binary'
    )
  end

  it 'every check returns a Result with a valid status' do
    results = described_class.run_all(config: nil)
    expect(results).to all(be_a(SPMCache::Core::Diagnostics::Result))
    results.each do |r|
      expect(%i[ok warn fail]).to include(r.status)
      expect(r.message).to be_a(String)
      expect(r.fix_hint).to be_a(String)
    end
  end

  it 'captures a check that raises as a :fail' do
    saved = described_class.registry.dup
    begin
      described_class.instance_variable_set(:@registry, [])
      described_class.register('boom', fix_hint: 'fix it') { raise 'kaboom' }
      described_class.register('good', fix_hint: '') { [:ok, 'fine'] }

      results = described_class.run_all(config: nil)
      boom = results.find { |r| r.name == 'boom' }
      expect(boom.status).to eq(:fail)
      expect(boom.message).to include('kaboom')
      expect(results.find { |r| r.name == 'good' }.status).to eq(:ok)
    ensure
      described_class.instance_variable_set(:@registry, saved)
    end
  end
end

RSpec.describe SPMCache::Core::Diagnostics, 'hermetic per-check paths (injected shell collectors)' do
  let(:cache_dir) { SPMCache::Core::Config::CACHE_DIR }
  let(:companion_bin) do
    File.expand_path('tools/spm-cache-proxy/.build/release/spm-cache-proxy', SPMCache::ROOT)
  end

  before do
    # Default: every shell probe fails, as on a host with no toolchain. Each
    # example overrides the specific command it exercises; no example here
    # ever shells out to the real host.
    allow(SPMCache::Core::Sh).to receive(:capture_output)
      .and_raise(SPMCache::Core::GeneralError.new('Command failed (exit 1): not installed'))
  end

  def result_for(name, config: nil)
    SPMCache::Core::Diagnostics.run_all(config: config).find { |r| r.name == name }
  end

  it 'xcode_version returns :ok with the first line of xcodebuild output' do
    allow(SPMCache::Core::Sh).to receive(:capture_output).with('xcodebuild -version')
                                                         .and_return("Xcode 16.0\nBuild 16A242d\n")
    result = result_for('xcode_version')
    expect(result.status).to eq(:ok)
    expect(result.message).to eq('Xcode 16.0')
  end

  it 'xcode_version returns :fail when the probe raises' do
    result = result_for('xcode_version')
    expect(result.status).to eq(:fail)
    expect(result.message).to start_with('xcodebuild not found or returned no output')
  end

  it 'swift_version returns :ok with the first line of swift output' do
    allow(SPMCache::Core::Sh).to receive(:capture_output).with('swift --version')
                                                         .and_return("Swift version 6.0.2\nTarget: arm64\n")
    result = result_for('swift_version')
    expect(result.status).to eq(:ok)
    expect(result.message).to eq('Swift version 6.0.2')
  end

  it 'swift_version returns :fail when swift is absent' do
    result = result_for('swift_version')
    expect(result.status).to eq(:fail)
    expect(result.message).to eq('swift not found on PATH')
  end

  it 'toolchain_path returns :ok with the located swift path' do
    allow(SPMCache::Core::Sh).to receive(:capture_output).with('xcrun --find swift 2>/dev/null')
                                                         .and_return('/Applications/Xcode.app/usr/bin/swift')
    result = result_for('toolchain_path')
    expect(result.status).to eq(:ok)
    expect(result.message).to eq('/Applications/Xcode.app/usr/bin/swift')
  end

  it 'toolchain_path returns :fail when xcrun cannot locate swift' do
    result = result_for('toolchain_path')
    expect(result.status).to eq(:fail)
    expect(result.message).to eq('xcrun could not locate swift — Xcode command-line tools not installed?')
  end

  it 'companion_binary returns :ok with the version suffix when the probe answers' do
    allow(File).to receive(:executable?).and_call_original
    allow(File).to receive(:executable?).with(companion_bin).and_return(true)
    allow(SPMCache::Core::Sh).to receive(:capture_output)
      .with("#{companion_bin} --version 2>/dev/null").and_return('0.3.0')
    result = result_for('companion_binary')
    expect(result.status).to eq(:ok)
    expect(result.message).to eq("Companion binary present at #{companion_bin} (0.3.0)")
  end

  it 'companion_binary returns :ok without a suffix when the probe fails' do
    allow(File).to receive(:executable?).and_call_original
    allow(File).to receive(:executable?).with(companion_bin).and_return(true)
    result = result_for('companion_binary')
    expect(result.status).to eq(:ok)
    expect(result.message).to eq("Companion binary present at #{companion_bin}")
  end

  it 'companion_binary returns :warn when the binary is missing' do
    allow(File).to receive(:executable?).and_call_original
    allow(File).to receive(:executable?).with(companion_bin).and_return(false)
    result = result_for('companion_binary')
    expect(result.status).to eq(:warn)
    expect(result.message).to start_with('Companion binary not built')
  end

  it 'cache_dir_health returns :ok with config and file counts when the dir exists' do
    allow(File).to receive(:directory?).and_call_original
    allow(File).to receive(:directory?).with(cache_dir).and_return(true)
    allow(Dir).to receive(:children).and_call_original
    allow(Dir).to receive(:children).with(cache_dir).and_return(%w[config-a config-b])
    allow(Dir).to receive(:glob).and_call_original
    allow(Dir).to receive(:glob).with(a_string_starting_with(cache_dir.to_s)).and_return([])
    result = result_for('cache_dir_health')
    expect(result.status).to eq(:ok)
    expect(result.message).to eq("Cache dir #{cache_dir} (2 config(s), ~0 files)")
  end

  it 'cache_dir_health returns :ok when the cache dir does not exist yet' do
    allow(File).to receive(:directory?).and_call_original
    allow(File).to receive(:directory?).with(cache_dir).and_return(false)
    result = result_for('cache_dir_health')
    expect(result.status).to eq(:ok)
    expect(result.message).to eq("Cache dir #{cache_dir} does not exist yet (no caches built)")
  end

  it 'remote_backend_connectivity returns :ok local-only when no remote is configured' do
    config = instance_double(SPMCache::Core::Config, load: nil, raw: {})
    result = result_for('remote_backend_connectivity', config: config)
    expect(result.status).to eq(:ok)
    expect(result.message).to eq('No remote backend configured (local-only)')
  end

  it 'remote_backend_connectivity returns :ok configured when a remote key exists' do
    config = instance_double(SPMCache::Core::Config, load: nil, raw: { 'remote' => { 'default' => {} } })
    result = result_for('remote_backend_connectivity', config: config)
    expect(result.status).to eq(:ok)
    expect(result.message).to include('Remote backend configured')
    expect(result.message).to include('run `spm-cache remote pull`')
  end

  it 'registers the built-in checks in registration (report) order' do
    expect(SPMCache::Core::Diagnostics.registry.map(&:name)).to eq(
      %w[xcode_version swift_version toolchain_path cache_dir_health
         library_evolution_compatibility remote_backend_connectivity companion_binary
         lock_graph_fidelity]
    )
  end
end

RSpec.describe 'spm-cache doctor with a fully absent toolchain' do
  it 'renders all 8 checks, marks the three toolchain probes failed, and exits 1' do
    require 'spm_cache/command/doctor'
    allow(SPMCache::Core::Sh).to receive(:capture_output)
      .and_raise(SPMCache::Core::GeneralError.new('Command failed (exit 1): not installed'))
    out = StringIO.new
    original_stdout = $stdout
    $stdout = out
    begin
      # exit 1 would abort the spec process; expect it instead (any :fail => 1).
      expect_any_instance_of(SPMCache::Command::Doctor).to receive(:exit).with(1).and_return(nil)
      cmd = SPMCache::Command.parse(['doctor'])
      cmd.run
    ensure
      $stdout = original_stdout
    end
    marker_lines = out.string.lines.map(&:strip).select { |l| l.match?(/\A[✓!✗] /) }
    expect(marker_lines.length).to eq(8) # none dropped, none extra — report completed
    %w[xcode_version swift_version toolchain_path].each do |name|
      expect(marker_lines).to include(a_string_starting_with("✗ #{name}:"))
    end
    expect(out.string).to match(/Summary: \d+ ok, \d+ warnings?, 3 failures/)
  end
end

RSpec.describe 'spm-cache doctor with a drifted lock' do
  # DIAG-01's exit contract: drift is a :warn because the remedy is automatic on
  # the next non-fast-path `use`, so a :fail would redden CI before a first run.
  it 'reports the drift, renders the fix hint, and never reaches the exit branch' do
    require 'spm_cache/command/doctor'
    diagnostics = SPMCache::Core::Diagnostics
    saved = diagnostics.registry.dup
    config = SPMCache::Core::Config.instance
    original_project_dir = config.project_dir
    tmpdir = Dir.mktmpdir
    project_path = File.join(tmpdir, 'Drifted.xcodeproj')
    project = Xcodeproj::Project.new(project_path)
    project.new_target(:application, 'MyApp', :ios)
    project.save
    resolved = File.join(project_path, SPMCache::Core::PackageResolved::CANONICAL_RELATIVE_PATH)
    FileUtils.mkdir_p(File.dirname(resolved))
    File.write(resolved, JSON.generate(
                           'version' => 3,
                           'pins' => [{ 'identity' => 'hosted', 'kind' => 'remoteSourceControl',
                                        'location' => 'https://github.com/example/hosted.git',
                                        'state' => { 'version' => '2.0.0' } }]
                         ))
    File.write(File.join(tmpdir, 'spm-cache.lock'), JSON.generate(
                                                     'Drifted.xcodeproj' => {
                                                       'packages' => [{
                                                         'name' => 'stale',
                                                         'repositoryURL' => 'https://github.com/example/stale.git',
                                                         'version' => '1.0.0'
                                                       }],
                                                       'dependencies' => {}, 'platforms' => {}
                                                     }
                                                   ))
    out = StringIO.new
    original_stdout = $stdout
    $stdout = out
    begin
      diagnostics.instance_variable_set(:@registry, saved.select { |c| c.name == 'lock_graph_fidelity' })
      config.project_dir = tmpdir
      expect_any_instance_of(SPMCache::Command::Doctor).not_to receive(:exit)
      SPMCache::Command.parse(['doctor']).run
    ensure
      $stdout = original_stdout
      diagnostics.instance_variable_set(:@registry, saved)
      config.project_dir = original_project_dir
      FileUtils.rm_rf(tmpdir)
    end
    expect(out.string).to match(/^! lock_graph_fidelity: /)
    expect(out.string).to include('stale')
    expect(out.string).to include('hosted')
    expect(out.string).to include('↳ Run `spm-cache use` to reconcile')
    expect(out.string).to match(/Summary: 0 ok, 1 warning, 0 failures/)
  end
end

RSpec.describe 'spm-cache doctor --json' do
  it 'emits valid JSON with checks and summary' do
    require 'spm_cache/command/doctor'
    out = StringIO.new
    # Capture stdout from the command's puts calls.
    original_stdout = $stdout
    $stdout = out
    begin
      # exit 1 would abort the spec process; stub it.
      allow_any_instance_of(SPMCache::Command::Doctor).to receive(:exit).and_return(nil)
      cmd = SPMCache::Command.parse(['doctor', '--json'])
      cmd.run
    ensure
      $stdout = original_stdout
    end
    parsed = JSON.parse(out.string)
    expect(parsed).to include('checks', 'summary')
    expect(parsed['checks']).to be_an(Array)
    expect(parsed['summary']).to include('ok', 'warnings', 'failures')
  end

  it 'emits valid JSON even when a check raises mid-run' do
    require 'spm_cache/command/doctor'
    allow(SPMCache::Core::Sh).to receive(:capture_output)
      .and_raise(SPMCache::Core::GeneralError.new('Command failed (exit 1): not installed'))
    diagnostics = SPMCache::Core::Diagnostics
    saved = diagnostics.registry.dup
    out = StringIO.new
    original_stdout = $stdout
    $stdout = out
    begin
      diagnostics.register('kaboom_json', fix_hint: 'n/a') { raise 'json boom' }
      allow_any_instance_of(SPMCache::Command::Doctor).to receive(:exit).with(1).and_return(nil)
      cmd = SPMCache::Command.parse(['doctor', '--json'])
      cmd.run
    ensure
      $stdout = original_stdout
      diagnostics.instance_variable_set(:@registry, saved)
    end
    parsed = JSON.parse(out.string)
    names = parsed['checks'].map { |c| c['name'] }
    expect(parsed['checks'].length).to eq(9)
    %w[xcode_version swift_version toolchain_path cache_dir_health
       library_evolution_compatibility remote_backend_connectivity companion_binary].each do |name|
      expect(names).to include(name)
    end
    kaboom = parsed['checks'].find { |c| c['name'] == 'kaboom_json' }
    expect(kaboom['status']).to eq('fail')
    expect(kaboom['message']).to start_with('Check raised an error: json boom')
    expect(parsed['summary']['failures']).to be >= 1
  end
end
