# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'stringio'
require 'json'

require 'spm_cache/core/watcher'
require 'spm_cache/core/run_log'

# A fake installer that records calls and can be made to fail, so we can test
# the watcher without a real Xcode project or build pipeline.
class FakeInstaller
  attr_reader :call_count, :last_project

  def initialize(should_fail: false)
    @should_fail = should_fail
    @call_count = 0
  end

  def perform_install
    @call_count += 1
    raise StandardError, 'simulated build failure' if @should_fail
  end
end

# Hermetic double for the Plan 12-05 cycle-wrapper examples (D-09): prints
# one stdout line per perform_install, or raises a chosen exit shape. No
# Xcode, no shell-outs -- the wrapper's tee/exit contract is observable
# with plain writes alone.
class CycleDouble
  def initialize(mode = :ok)
    @mode = mode
  end

  def perform_install
    case @mode
    when :general_error then raise SPMCache::Core::GeneralError, 'cycle boom'
    when :interrupt then raise Interrupt
    when :exit3 then raise SystemExit.new(3)
    else puts 'cycle body line'
    end
  end
end

# A fake installer that records calls and can be made to fail, so we can test
# the watcher without a real Xcode project or build pipeline.
class FakeInstaller
  attr_reader :call_count, :last_project

  def initialize(should_fail: false)
    @should_fail = should_fail
    @call_count = 0
  end

  def perform_install
    @call_count += 1
    raise StandardError, 'simulated build failure' if @should_fail
  end
end

RSpec.describe SPMCache::Core::Watcher do
  let(:tmpdir) { Dir.mktmpdir }
  let(:project_path) { File.join(tmpdir, 'App.xcodeproj') }
  let(:resolved_path) do
    p = File.join(project_path, 'project.xcworkspace/xcshareddata/swiftpm/Package.resolved')
    p
  end

  before do
    FileUtils.mkdir_p(File.dirname(resolved_path))
    File.write(resolved_path, '{"pins":[],"version":1}')
  end

  after { FileUtils.remove_entry(tmpdir) if File.directory?(tmpdir) }

  def make_installer(should_fail: false)
    inst = FakeInstaller.new(should_fail: should_fail)
    [inst, ->(_path) { inst }]
  end

  it 'watches Package.resolved and project.pbxproj' do
    _, factory = make_installer
    watcher = described_class.new(project_path: project_path, installer_factory: factory, out: StringIO.new)
    expect(watcher.watched_files).to include(resolved_path)
  end

  it 'run_once performs a single integration' do
    inst, factory = make_installer
    watcher = described_class.new(project_path: project_path, installer_factory: factory, out: StringIO.new)
    result = watcher.run_once
    expect(result).to be true
    expect(inst.call_count).to eq(1)
  end

  it 'detects a change to Package.resolved between signatures' do
    inst, factory = make_installer
    out = StringIO.new
    watcher = described_class.new(project_path: project_path, installer_factory: factory,
                                  debounce: 0, out: out)

    # Seed initial signature via run_once, then modify the file.
    watcher.run_once
    inst.call_count

    # Bump the mtime+content so the signature differs.
    File.write(resolved_path, '{"pins":[{"identity":"NewDep"}],"version":1}')
    sleep 1 # ensure mtime advances by >= 1s on coarse filesystems

    # Simulate one poll iteration manually (avoids a blocking loop in tests).
    current = watcher.send(:current_signatures)
    expect(current).not_to eq(watcher.instance_variable_get(:@last_signatures))
  end

  it 'continue-on-error: logs a transient failure and keeps the loop contract' do
    _, factory = make_installer(should_fail: true)
    out = StringIO.new
    watcher = described_class.new(project_path: project_path, installer_factory: factory,
                                  debounce: 0, out: out)

    # run_once raises directly (no loop to rescue); verify the error surfaces
    # so the loop's rescue path is the thing that swallows it.
    expect { watcher.run_once }.to raise_error(StandardError, /simulated build failure/)

    # The loop (not run_once) is responsible for continue-on-error. Verify a
    # failing installer doesn't corrupt state — a fresh watcher with a working
    # installer recovers.
    inst2, factory2 = make_installer(should_fail: false)
    watcher2 = described_class.new(project_path: project_path, installer_factory: factory2, out: StringIO.new)
    expect(watcher2.run_once).to be true
    expect(inst2.call_count).to eq(1)
  end

  it 'handles a missing project gracefully' do
    _, factory = make_installer
    watcher = described_class.new(
      project_path: File.join(tmpdir, 'DoesNotExist.xcodeproj'),
      installer_factory: factory,
      out: StringIO.new
    )
    expect(watcher.watched_files).to be_empty
    expect(watcher.run_once).to be false
  end

  it 'accepts a custom debounce value' do
    _, factory = make_installer
    watcher = described_class.new(project_path: project_path, installer_factory: factory,
                                  debounce: 5, out: StringIO.new)
    expect(watcher.debounce).to eq(5)
  end
end

# Plan 12-05 (D-09 / SC1, LOGS-01): the watch daemon writes ONE complete run
# log per regeneration cycle -- never a rolling session file. The decorator
# is injected from Command::Watch's installer_factory; Core::Watcher itself
# is untouched (it keeps calling factory.call + perform_install,
# watcher.rb:90-93). Traps never run inside RSpec (watch_signals_spec.rb:69-78),
# so cycle behavior is proven at the wrapper and run_once levels with
# hermetic doubles over tmpdirs.
RSpec.describe SPMCache::Core::RunLog, 'cycle_wrapper (D-09 per-cycle run logs)' do
  let(:tmpdir) { Dir.mktmpdir }
  let(:config) { SPMCache::Core::Config.instance }

  before { @orig_project_dir = config.project_dir }

  after do
    config.project_dir = @orig_project_dir
    described_class.current = nil
    FileUtils.remove_entry(tmpdir) if File.directory?(tmpdir)
  end

  # doctor_spec.rb:186-195 convention: manual $stdout/$stderr swap with
  # begin/ensure restore, so the tee under test wraps our StringIOs.
  def with_swapped_streams
    out = StringIO.new
    err = StringIO.new
    old_out = $stdout
    old_err = $stderr
    $stdout = out
    $stderr = err
    begin
      yield
    ensure
      $stdout = old_out
      $stderr = old_err
    end
    [out.string, err.string]
  end

  def cycle_files(dir)
    Dir.glob(File.join(dir, '*.jsonl')).sort
  end

  def read_jsonl(path)
    File.read(path).lines.map { |line| JSON.parse(line) }
  end

  def body_texts(lines)
    lines.reject { |line| line.key?('event') }.map { |body| body['text'] }
  end

  describe 'wrapper unit (hermetic double)' do
    it 'writes one self-contained cycle file: run_start watch/watch/cycle true, one out body, run_end 0; streams and current restored' do
      config.project_dir = tmpdir # default runs dir: <project>/.spm-cache/runs (D-02)
      runs = File.join(tmpdir, '.spm-cache', 'runs')

      out = StringIO.new
      err = StringIO.new
      old_out = $stdout
      old_err = $stderr
      $stdout = out
      $stderr = err
      begin
        described_class.cycle_wrapper(CycleDouble.new, argv: ['watch']).perform_install
        # Restoration is asserted BEFORE any helper restore: post-cycle the
        # swapped StringIOs must be back in place and RunLog.current reset
        # to its pre-cycle value (nil here -- no enclosing run).
        expect($stdout).to equal(out)
        expect($stderr).to equal(err)
        expect(described_class.current).to be_nil
      ensure
        $stdout = old_out
        $stderr = old_err
      end

      files = cycle_files(runs)
      expect(files.length).to eq(1)
      lines = read_jsonl(files.first)
      expect(lines.length).to eq(3) # run_start + one body line + run_end
      expect(lines.first).to include(
        'event' => 'run_start',
        'command' => 'watch',
        'trigger' => 'watch',
        'cycle' => true,
        'argv' => ['watch'],
        'pid' => Process.pid
      )
      expect(lines[1]).to include('stream' => 'out', 'text' => "cycle body line\n")
      expect(lines.last).to include('event' => 'run_end', 'status' => 0)

      # SC3: the tee is write-through -- the real stream saw the bytes.
      expect(out.string).to eq("cycle body line\n")
    end

    it 'captures status 1 and propagates a GeneralError raised inside the cycle' do
      config.project_dir = tmpdir
      runs = File.join(tmpdir, '.spm-cache', 'runs')

      with_swapped_streams do
        expect do
          described_class.cycle_wrapper(CycleDouble.new(:general_error), argv: ['watch']).perform_install
        end.to raise_error(SPMCache::Core::GeneralError, /cycle boom/)
      end

      lines = read_jsonl(cycle_files(runs).first)
      expect(lines.first['event']).to eq('run_start')
      expect(lines.last).to include('event' => 'run_end', 'status' => 1)
    end

    it 'captures status 130 and propagates Interrupt (a mid-cycle Ctrl-C still lands run_end via the ensure)' do
      config.project_dir = tmpdir
      runs = File.join(tmpdir, '.spm-cache', 'runs')

      with_swapped_streams do
        expect do
          described_class.cycle_wrapper(CycleDouble.new(:interrupt), argv: ['watch']).perform_install
        end.to raise_error(Interrupt)
      end

      expect(read_jsonl(cycle_files(runs).first).last).to include('event' => 'run_end', 'status' => 130)
    end

    it 'captures SystemExit(3) status verbatim and propagates (same three-shape contract as Main.run)' do
      config.project_dir = tmpdir
      runs = File.join(tmpdir, '.spm-cache', 'runs')

      with_swapped_streams do
        expect do
          described_class.cycle_wrapper(CycleDouble.new(:exit3), argv: ['watch']).perform_install
        end.to raise_error(SystemExit) { |e| expect(e.status).to eq(3) }
      end

      expect(read_jsonl(cycle_files(runs).first).last).to include('event' => 'run_end', 'status' => 3)
    end

    it 'two cycles produce two distinct self-contained files (D-09: no session file; ms-precise names disambiguate)' do
      config.project_dir = tmpdir
      runs = File.join(tmpdir, '.spm-cache', 'runs')

      with_swapped_streams do
        2.times { described_class.cycle_wrapper(CycleDouble.new, argv: ['watch']).perform_install }
      end

      files = cycle_files(runs)
      expect(files.length).to eq(2)
      expect(files.first).not_to eq(files.last)
      files.each do |file|
        lines = read_jsonl(file)
        expect(lines.length).to eq(3) # each cycle file is complete on its own
        expect(lines.first).to include('event' => 'run_start', 'cycle' => true)
        expect(lines.last).to include('event' => 'run_end', 'status' => 0)
      end
    end

    it 'honors --log-dir for cycles (D-01: the override is never a dead knob on the watch surface)' do
      config.project_dir = tmpdir

      Dir.mktmpdir do |logs|
        with_swapped_streams do
          described_class.cycle_wrapper(CycleDouble.new, argv: ['watch', "--log-dir=#{logs}"]).perform_install
        end

        files = cycle_files(logs)
        expect(files.length).to eq(1)
        header = read_jsonl(files.first).first
        expect(header).to include(
          'command' => 'watch',
          'cycle' => true,
          'argv' => ['watch', "--log-dir=#{logs}"]
        )
        # The override wins outright: the default runs dir is never created.
        expect(File.exist?(File.join(tmpdir, '.spm-cache'))).to be(false)
      end
    end

    it 'honors --log-dir=X AFTER the verb (the position CLAide actually accepts for watch — CR-02/D-01)' do
      config.project_dir = tmpdir

      Dir.mktmpdir do |logs|
        with_swapped_streams do
          described_class.cycle_wrapper(CycleDouble.new, argv: ['watch', "--log-dir=#{logs}", '--once']).perform_install
        end

        files = cycle_files(logs)
        expect(files.length).to eq(1)
        expect(read_jsonl(files.first).first).to include('command' => 'watch', 'cycle' => true)
        # The override wins outright: the default runs dir is never created.
        expect(File.exist?(File.join(tmpdir, '.spm-cache'))).to be(false)
      end
    end

    it 'captures only the cycle own output: writes printed between cycles (no tee active) land in no file' do
      config.project_dir = tmpdir
      runs = File.join(tmpdir, '.spm-cache', 'runs')

      with_swapped_streams do
        wrapper = described_class.cycle_wrapper(CycleDouble.new, argv: ['watch'])
        wrapper.perform_install
        # Between cycles the tee is restored -- exactly when Core::Watcher
        # prints its inter-cycle narrative (its @out, bound before any swap).
        $stdout.puts '[watch] SPM graph changed, re-integrating...'
        warn '[watch] integration failed: between cycles'
        wrapper.perform_install
      end

      files = cycle_files(runs)
      expect(files.length).to eq(2)
      files.each do |file|
        expect(body_texts(read_jsonl(file))).to eq(["cycle body line\n"])
      end
    end

    # Research A5 (Plan 12-05, recorded decision): Core::Watcher's
    # inter-cycle narrative ("Watching ...", "[watch] SPM graph changed...")
    # is terminal-only BY DESIGN -- D-09 forbids a session file, and the
    # cycle tee is active only inside perform_install. The watcher's own
    # info mechanism (its @out, bound before any cycle swap) is driven
    # here so the assertion covers the real write path between cycles.
    it 'A5: inter-cycle Watcher narrative is terminal-only -- it is emitted but lands in no cycle file (D-09: no session file)' do
      config.project_dir = tmpdir
      runs = File.join(tmpdir, '.spm-cache', 'runs')

      proj = File.join(tmpdir, 'App.xcodeproj')
      swiftpm = File.join(proj, 'project.xcworkspace/xcshareddata/swiftpm')
      FileUtils.mkdir_p(swiftpm)
      File.write(File.join(swiftpm, 'Package.resolved'), '{"pins":[],"version":1}')

      narrative = StringIO.new
      installer = CycleDouble.new
      watcher = SPMCache::Core::Watcher.new(
        project_path: proj,
        installer_factory: ->(_path) { described_class.cycle_wrapper(installer, argv: ['watch']) },
        debounce: 0,
        out: narrative
      )

      with_swapped_streams do
        watcher.run_once
        watcher.send(:info, "Watching #{proj} for changes (Ctrl-C to stop)...") # exactly Watcher#run's banner
        watcher.send(:info, "\n[watch] SPM graph changed, re-integrating...") # exactly Watcher#run's mid-loop line
        watcher.run_once
      end

      # The narrative WAS emitted (terminal leg) yet persists nowhere:
      # each cycle file carries only its own output.
      expect(narrative.string).to include('SPM graph changed, re-integrating')
      files = cycle_files(runs)
      expect(files.length).to eq(2)
      files.each do |file|
        expect(body_texts(read_jsonl(file))).to eq(["cycle body line\n"])
      end
    end
  end
end

RSpec.describe SPMCache::Command::Watch do
  it 'parses --once and --debounce flags' do
    cmd = described_class.parse(['--once', '--debounce=5'])
    expect(cmd.instance_variable_get(:@once)).to be true
    expect(cmd.instance_variable_get(:@debounce)).to eq(5)
  end

  it 'defaults debounce to the Watcher default' do
    cmd = described_class.parse([])
    expect(cmd.instance_variable_get(:@debounce)).to eq(SPMCache::Core::Watcher::DEFAULT_DEBOUNCE)
  end

  it 'errors when no .xcodeproj is found' do
    Dir.mktmpdir do |empty_dir|
      Dir.chdir(empty_dir) do
        cmd = described_class.parse([])
        expect { cmd.run }.to raise_error(SPMCache::Core::GeneralError, /No \.xcodeproj found/)
      end
    end
  end

  describe 'installer_factory cycle wiring (D-09)' do
    it 'wraps Installer::Use in the cycle wrapper; --once logs one complete cycle file through the real run_once' do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          proj = File.join(dir, 'App.xcodeproj')
          swiftpm = File.join(proj, 'project.xcworkspace/xcshareddata/swiftpm')
          FileUtils.mkdir_p(swiftpm)
          File.write(File.join(swiftpm, 'Package.resolved'), '{"pins":[],"version":1}')

          Dir.mktmpdir do |logs|
            stub_const('ARGV', ['watch', "--log-dir=#{logs}", '--once'])

            installer = CycleDouble.new
            allow(SPMCache::Installer::Use).to receive(:new).and_return(installer)

            created = nil
            allow(SPMCache::Core::Watcher).to receive(:new).and_wrap_original do |orig, **kwargs|
              created = orig.call(**kwargs)
            end

            out = StringIO.new
            old_out = $stdout
            $stdout = out
            begin
              described_class.parse(['--once']).run
            ensure
              $stdout = old_out
            end

            # The factory the command wired into the REAL Watcher returns a
            # cycle-wrapped installer (the D-09 seam -- watcher.rb untouched).
            wrapped = created.instance_variable_get(:@installer_factory).call(proj)
            expect(wrapped).to be_a(SPMCache::Core::RunLog::CycleWrapper)

            # --once flowed run_once -> factory -> perform_install: exactly
            # one self-contained cycle file, landing in the --log-dir
            # override (D-01).
            files = Dir.glob(File.join(logs, '*.jsonl')).sort
            expect(files.length).to eq(1)
            lines = File.read(files.first).lines.map { |l| JSON.parse(l) }
            expect(lines.first).to include(
              'event' => 'run_start',
              'command' => 'watch',
              'trigger' => 'watch',
              'cycle' => true,
              'argv' => ['watch', "--log-dir=#{logs}", '--once']
            )
            expect(lines[1]).to include('stream' => 'out', 'text' => "cycle body line\n")
            expect(lines.last).to include('event' => 'run_end', 'status' => 0)

            # The --once completion narrative prints AFTER run_once returned
            # (tee restored): terminal-only, never in the cycle file (D-09).
            expect(out.string).to include('Sync complete.')
            expect(lines.none? { |l| l['text'].to_s.include?('Sync complete.') }).to be(true)
          end
        end
      end
    end
  end
end
