# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'stringio'
require 'tmpdir'

# LOGS-01 tracer slice: every CLI run that reaches Command.run through
# SPMCache::Main.run must leave exactly one JSONL run log under the run dir
# (run_start header / stream-tagged body lines / run_end exit line), while
# terminal bytes and exit codes stay byte-identical (SC3). The --no-run-log /
# --log-dir / verb routing is pre-scanned from raw argv BEFORE CLAide parses
# (Pitfall 1) -- the bare --version intercept in Main.run is the precedent --
# because the tee installs outside Command.run.
RSpec.describe SPMCache::Core::RunLog do
  describe '.pre_scan' do
    it 'treats the first non-flag token as the verb, skipping --log-dir values' do
      scan = described_class.pre_scan(['--log-dir', '/tmp/x', 'use'])
      expect(scan.verb).to eq('use')
    end

    it 'defaults the verb to use (CLAide default_subcommand)' do
      expect(described_class.pre_scan(['--no-merge-slices']).verb).to eq('use')
    end

    it 'flags --no-run-log anywhere in argv as suppressed (D-03)' do
      expect(described_class.pre_scan(['use', '--no-run-log']).suppressed?).to be(true)
      expect(described_class.pre_scan(['--no-run-log', 'use']).suppressed?).to be(true)
      expect(described_class.pre_scan(['use']).suppressed?).to be(false)
    end

    it 'flags the web and watch verbs as main_log_skipped (SC3 / D-09)' do
      expect(described_class.pre_scan(['web']).main_log_skipped?).to be(true)
      expect(described_class.pre_scan(['watch']).main_log_skipped?).to be(true)
      expect(described_class.pre_scan(['--log-dir', '/tmp/x', 'use']).main_log_skipped?).to be(false)
    end

    it 'reads the CLAide-accepted --log-dir=X form in any position; the two-token form routes nothing (D-01/CR-02)' do
      expect(described_class.pre_scan(['--log-dir=/tmp/x', 'use']).log_dir).to eq('/tmp/x')
      expect(described_class.pre_scan(['use', '--log-dir=/tmp/x']).log_dir).to eq('/tmp/x')
      expect(described_class.pre_scan(['use']).log_dir).to be_nil
    end
  end
end

RSpec.describe SPMCache::Main, 'run-log capture (LOGS-01)' do
  let(:tmpdir) { Dir.mktmpdir }
  let(:iso8601_utc) { /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/ }

  before do
    # Hermeticity guard (default-deny, both Core::Sh entry points -- the
    # fidelity_bucket_partition_spec.rb:53-67 pattern): this slice needs ZERO
    # shell-outs; the real-`use` failure example raises at use.rb:25 before
    # ever touching the toolchain.
    allow(SPMCache::Core::Sh).to receive(:run) do |cmd, *_opts|
      raise "unexpected real invocation: Sh.run(#{cmd.inspect})"
    end
    allow(SPMCache::Core::Sh).to receive(:capture_output) do |cmd, *_opts|
      raise "unexpected real invocation: Sh.capture_output(#{cmd.inspect})"
    end
  end

  after { FileUtils.rm_rf(tmpdir) }

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

  def jsonl_files(dir = tmpdir)
    Dir.glob(File.join(dir, '*.jsonl')).sort
  end

  def run_lines(dir = tmpdir)
    files = jsonl_files(dir)
    expect(files.size).to eq(1)
    File.read(files.first).lines.map { |line| JSON.parse(line) }
  end

  describe 'happy path with a stubbed command' do
    it 'writes exactly one JSONL file: run_start header, stream-tagged body, run_end exit line' do
      allow(SPMCache::Command).to receive(:run) do
        puts "stdout \e[32mline\e[0m"
        warn 'stderr line'
      end

      with_swapped_streams { SPMCache::Main.run(["--log-dir=#{tmpdir}", 'use']) }

      files = jsonl_files
      expect(files.size).to eq(1)
      expect(File.basename(files.first)).to match(/\A\d{8}T\d{6}\d{3}Z-\d+-use\.jsonl\z/)

      lines = File.read(files.first).lines
      expect(lines.size).to eq(4) # header + one out line + one err line + exit

      header = JSON.parse(lines[0])
      expect(header).to include(
        'event' => 'run_start',
        'command' => 'use',
        'argv' => ["--log-dir=#{tmpdir}", 'use'],
        'pid' => Process.pid,
        'spm_cache_version' => SPMCache::VERSION,
        'trigger' => 'terminal'
      )
      expect(header['ts']).to match(iso8601_utc)
      expect(header['started_at']).to match(iso8601_utc)

      body_out = JSON.parse(lines[1])
      expect(body_out['stream']).to eq('out')
      expect(body_out['text']).to eq("stdout \e[32mline\e[0m\n") # verbatim, ANSI bytes included
      expect(body_out['ts']).to match(iso8601_utc)

      body_err = JSON.parse(lines[2])
      expect(body_err['stream']).to eq('err')
      expect(body_err['text']).to eq("stderr line\n")

      exit_line = JSON.parse(lines[3])
      expect(exit_line).to include('event' => 'run_end', 'status' => 0)
      expect(exit_line['ended_at']).to match(iso8601_utc)
    end
  end

  describe 'tee invisibility (SC3)' do
    it 'terminal bytes are identical with capture on vs --no-run-log' do
      allow(SPMCache::Command).to receive(:run) do
        puts 'out bytes'
        warn 'err bytes'
      end

      baseline_out, baseline_err =
        with_swapped_streams { SPMCache::Main.run(['--no-run-log', '--log-dir', tmpdir, 'use']) }
      expect(jsonl_files).to be_empty

      captured_out, captured_err =
        with_swapped_streams { SPMCache::Main.run(["--log-dir=#{tmpdir}", 'use']) }

      expect(captured_out).to eq(baseline_out)
      expect(captured_err).to eq(baseline_err)
    end
  end

  describe 'exit-shape capture (every shape re-raises untouched)' do
    it 'records SystemExit status and re-raises it untouched' do
      allow(SPMCache::Command).to receive(:run).and_raise(SystemExit.new(3))
      expect do
        with_swapped_streams { SPMCache::Main.run(["--log-dir=#{tmpdir}", 'use']) }
      end.to raise_error(SystemExit) { |e| expect(e.status).to eq(3) }
      expect(run_lines.last).to include('event' => 'run_end', 'status' => 3)
    end

    it 'records status 130 for Interrupt and re-raises it' do
      allow(SPMCache::Command).to receive(:run).and_raise(Interrupt)
      expect do
        with_swapped_streams { SPMCache::Main.run(["--log-dir=#{tmpdir}", 'use']) }
      end.to raise_error(Interrupt)
      expect(run_lines.last).to include('event' => 'run_end', 'status' => 130)
    end

    it 'records GeneralError exit_status (default 1) and re-raises it' do
      allow(SPMCache::Command).to receive(:run).and_raise(SPMCache::Core::GeneralError.new('boom'))
      expect do
        with_swapped_streams { SPMCache::Main.run(["--log-dir=#{tmpdir}", 'use']) }
      end.to raise_error(SPMCache::Core::GeneralError, 'boom')
      expect(run_lines.last).to include('event' => 'run_end', 'status' => 1)
    end

    it 'records status 1 for a plain RuntimeError and re-raises it' do
      allow(SPMCache::Command).to receive(:run).and_raise(RuntimeError, 'kaboom')
      expect do
        with_swapped_streams { SPMCache::Main.run(["--log-dir=#{tmpdir}", 'use']) }
      end.to raise_error(RuntimeError, 'kaboom')
      expect(run_lines.last).to include('event' => 'run_end', 'status' => 1)
    end
  end

  describe 'real failure path (EDGE empty)' do
    it 'raises exactly as today and leaves a valid two-line run log' do
      empty_dir = File.join(tmpdir, 'empty')
      FileUtils.mkdir_p(empty_dir)
      Dir.chdir(empty_dir) do
        # The = form: CLAide rejects the space-separated '--log-dir X' form
        # outright (Unknown option), which would surface a Help-driven
        # SystemExit instead of the raw RuntimeError under test.
        expect do
          with_swapped_streams { SPMCache::Main.run(["--log-dir=#{tmpdir}", 'use']) }
        end.to raise_error(StandardError, /No \.xcodeproj found/)
      end

      files = jsonl_files
      expect(files.size).to eq(1)
      lines = File.read(files.first).lines
      expect(lines.size).to eq(2) # zero-output run: run_start + run_end only
      parsed = lines.map { |line| JSON.parse(line) } # every line parses as JSON
      expect(parsed.first['event']).to eq('run_start')
      expect(parsed.last).to include('event' => 'run_end', 'status' => 1)
    end
  end

  describe 'exclusions' do
    it 'writes no run log when --no-run-log appears anywhere in argv (D-03)' do
      allow(SPMCache::Command).to receive(:run)
      with_swapped_streams { SPMCache::Main.run(['use', '--no-run-log']) }
      expect(jsonl_files).to be_empty
    end

    it 'never logs the web verb (SC3)' do
      allow(SPMCache::Command).to receive(:run)
      with_swapped_streams { SPMCache::Main.run(['--log-dir', tmpdir, 'web']) }
      expect(jsonl_files).to be_empty
    end

    it 'opens no Main-level run log for the watch verb (D-09: per-cycle files are Plan 05)' do
      allow(SPMCache::Command).to receive(:run)
      with_swapped_streams { SPMCache::Main.run(['--log-dir', tmpdir, 'watch']) }
      expect(jsonl_files).to be_empty
    end
  end

  describe '--log-dir override forms (D-01)' do
    it 'lands the run file in the given dir for --log-dir=X before and after the verb' do
      allow(SPMCache::Command).to receive(:run)
      dir_a = File.join(tmpdir, 'a')
      dir_b = File.join(tmpdir, 'b')

      with_swapped_streams { SPMCache::Main.run(["--log-dir=#{dir_a}", 'use']) }
      with_swapped_streams { SPMCache::Main.run(['use', "--log-dir=#{dir_b}"]) }

      expect(jsonl_files(dir_a).size).to eq(1)
      expect(jsonl_files(dir_b).size).to eq(1)
      expect(jsonl_files(tmpdir).size).to eq(0) # nothing at the parent level
    end
  end
end
