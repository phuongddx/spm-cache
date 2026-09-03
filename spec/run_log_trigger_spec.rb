# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'stringio'
require 'tmpdir'
require 'fileutils'

# D-03/LOGS-05: 15-01's spawned child carries SPM_CACHE_TRIGGER=ui in its
# env; Main.run normalizes that marker into the run_start header's `trigger`
# field. A CLOSED whitelist -- exactly the UI value becomes 'ui', everything
# else (unset, empty, foreign, wrong-case) becomes 'terminal' -- never
# passthrough, and the marker is attribution-only (Pitfall 7): it never
# alters what runs or how it exits. RunLog.pre_scan and the watch
# CycleWrapper's own 'watch' trigger are untouched -- the seam is the single
# hard-coded kwarg at main.rb's whole-run RunLog.open call.
#
# A hermetic double for the vocabulary-closure example, local to this file
# (not spec/watch_spec.rb's CycleDouble, which is not required by this
# plan's verify command) so the example runs standalone.
class TriggerCycleDouble
  def perform_install
    puts 'cycle body line'
  end
end

RSpec.describe SPMCache::Main, 'UI-run trigger attribution (D-03)' do
  let(:tmpdir) { Dir.mktmpdir }
  let(:iso8601_utc) { /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/ }

  before do
    # Default-deny Sh guard (main_run_log_spec.rb:50-61 pattern): this
    # slice needs zero shell-outs.
    allow(SPMCache::Core::Sh).to receive(:run) do |cmd, *_opts|
      raise "unexpected real invocation: Sh.run(#{cmd.inspect})"
    end
    allow(SPMCache::Core::Sh).to receive(:capture_output) do |cmd, *_opts|
      raise "unexpected real invocation: Sh.capture_output(#{cmd.inspect})"
    end
  end

  after { FileUtils.rm_rf(tmpdir) }

  # doctor_spec.rb:186-195 / main_run_log_spec.rb:65-81 convention: manual
  # $stdout/$stderr swap with begin/ensure restore.
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

  # Sets/restores SPM_CACHE_TRIGGER in an ensure so no example leaks
  # environment state into the rest of the suite. `value: nil` deletes the
  # variable (the unset case).
  def with_trigger_env(value)
    had_original = ENV.key?('SPM_CACHE_TRIGGER')
    original = ENV['SPM_CACHE_TRIGGER']
    if value.nil?
      ENV.delete('SPM_CACHE_TRIGGER')
    else
      ENV['SPM_CACHE_TRIGGER'] = value
    end
    yield
  ensure
    if had_original
      ENV['SPM_CACHE_TRIGGER'] = original
    else
      ENV.delete('SPM_CACHE_TRIGGER')
    end
  end

  def jsonl_files(dir)
    Dir.glob(File.join(dir, '*.jsonl')).sort
  end

  def header_for(dir)
    files = jsonl_files(dir)
    expect(files.size).to eq(1)
    JSON.parse(File.read(files.first).lines.first)
  end

  def run_end_status_for(dir)
    files = jsonl_files(dir)
    lines = File.read(files.first).lines.map { |l| JSON.parse(l) }
    lines.find { |l| l['event'] == 'run_end' }['status']
  end

  describe 'marker present' do
    it 'records trigger "ui" and leaves every other header field unchanged' do
      allow(SPMCache::Command).to receive(:run) { puts 'stdout line' }

      with_trigger_env('ui') do
        with_swapped_streams { SPMCache::Main.run(["--log-dir=#{tmpdir}", 'use']) }
      end

      header = header_for(tmpdir)
      expect(header).to include(
        'event' => 'run_start',
        'command' => 'use',
        'argv' => ["--log-dir=#{tmpdir}", 'use'],
        'pid' => Process.pid,
        'spm_cache_version' => SPMCache::VERSION,
        'trigger' => 'ui',
        'cycle' => false
      )
      expect(header['ts']).to match(iso8601_utc)
      expect(header['started_at']).to match(iso8601_utc)
    end
  end

  describe 'marker absent' do
    it 'records trigger "terminal" (today\'s behavior, pinned as a regression)' do
      allow(SPMCache::Command).to receive(:run) { puts 'stdout line' }

      with_trigger_env(nil) do
        with_swapped_streams { SPMCache::Main.run(["--log-dir=#{tmpdir}", 'use']) }
      end

      expect(header_for(tmpdir)['trigger']).to eq('terminal')
    end
  end

  describe 'marker with any other value' do
    it 'normalizes an arbitrary string, an empty string, and a case variant all to "terminal" (closed whitelist, never passthrough)' do
      allow(SPMCache::Command).to receive(:run) { puts 'stdout line' }

      { 'arbitrary' => 'some-other-value', 'empty' => '', 'case-variant' => 'UI' }.each do |label, value|
        dir = File.join(tmpdir, label)
        FileUtils.mkdir_p(dir)

        with_trigger_env(value) do
          with_swapped_streams { SPMCache::Main.run(["--log-dir=#{dir}", 'use']) }
        end

        expect(header_for(dir)['trigger']).to eq('terminal'), "expected #{value.inspect} to normalize to 'terminal'"
      end
    end
  end

  describe 'no behavior change (Pitfall 7: attribution only)' do
    it 'runs the stubbed command with identical terminal bytes and exit status whether or not the marker is set' do
      allow(SPMCache::Command).to receive(:run) do
        puts 'stdout line'
        warn 'stderr line'
      end

      baseline_dir = File.join(tmpdir, 'baseline')
      ui_dir = File.join(tmpdir, 'ui')
      FileUtils.mkdir_p(baseline_dir)
      FileUtils.mkdir_p(ui_dir)

      baseline_out, baseline_err = with_trigger_env(nil) do
        with_swapped_streams { SPMCache::Main.run(["--log-dir=#{baseline_dir}", 'use']) }
      end

      ui_out, ui_err = with_trigger_env('ui') do
        with_swapped_streams { SPMCache::Main.run(["--log-dir=#{ui_dir}", 'use']) }
      end

      expect(ui_out).to eq(baseline_out)
      expect(ui_err).to eq(baseline_err)
      expect(run_end_status_for(ui_dir)).to eq(run_end_status_for(baseline_dir))
      expect(SPMCache::Command).to have_received(:run).twice
    end
  end

  describe 'vocabulary closure' do
    it 'leaves the watch CycleWrapper trigger at "watch" even with the UI marker set' do
      config = SPMCache::Core::Config.instance
      original_project_dir = config.project_dir
      config.project_dir = tmpdir

      with_trigger_env('ui') do
        with_swapped_streams do
          SPMCache::Core::RunLog.cycle_wrapper(TriggerCycleDouble.new, argv: ['watch']).perform_install
        end
      end

      header = header_for(File.join(tmpdir, '.spm-cache', 'runs'))
      expect(header).to include('command' => 'watch', 'trigger' => 'watch', 'cycle' => true)
    ensure
      config.project_dir = original_project_dir
    end
  end
end
