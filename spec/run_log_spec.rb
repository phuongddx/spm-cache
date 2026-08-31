# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'stringio'
require 'tmpdir'

# Unit coverage for the Core::RunLog writer (LOGS-01): tee mechanics, header
# atomicity, verbatim JSON escaping, partial-line buffering, concurrency
# (EDGE adjacency), and safety degradation. Hermetic: tmpdir + StringIO/spy
# doubles only, zero shell-outs (default-deny Sh guard below, per the
# fidelity_bucket_partition_spec.rb:53-67 pattern -- spec_helper installs
# NONE).
RSpec.describe SPMCache::Core::RunLog do
  let(:runs_dir) { Dir.mktmpdir }

  before do
    allow(SPMCache::Core::Sh).to receive(:run) do |cmd, *_opts|
      raise "unexpected real invocation: Sh.run(#{cmd.inspect})"
    end
    allow(SPMCache::Core::Sh).to receive(:capture_output) do |cmd, *_opts|
      raise "unexpected real invocation: Sh.capture_output(#{cmd.inspect})"
    end
  end

  after do
    described_class.current = nil
    FileUtils.rm_rf(runs_dir)
  end

  def open_log(**kwargs)
    described_class.open(runs_dir: runs_dir, command: 'use', **kwargs)
  end

  describe 'header atomicity' do
    it 'publishes a complete parseable run_start at open with no *.tmp residue' do
      log = open_log
      expect(File.exist?(log.path)).to be(true)
      lines = File.read(log.path).lines
      expect(lines.length).to eq(1) # header only, fully published
      expect(JSON.parse(lines.first)).to include(
        'event' => 'run_start',
        'command' => 'use',
        'pid' => Process.pid,
        'trigger' => 'terminal'
      )
      expect(File.basename(log.path)).to match(/\A\d{8}T\d{6}\d{3}Z-\d+-use\.jsonl\z/)
      expect(Dir.glob(File.join(runs_dir, '*.tmp'))).to be_empty # Tempfile cleaned up by rename
      log.finish(0)
    end
  end

  describe 'verbatim capture and JSON escaping' do
    it 'round-trips quotes, backslashes, embedded newlines and ANSI bytes, one JSON document per physical line' do
      log = open_log
      text = "quote\" back\\slash embedded\nnewline and \e[31mANSI\e[0m bytes\n"
      log.record_text(text, 'out')
      log.finish(0)

      lines = File.read(log.path).lines
      expect(lines.length).to eq(3) # header + ONE body line + run_end
      lines.each { |line| JSON.parse(line) } # raises if any physical line is not a JSON document
      expect(JSON.parse(lines[1])['text']).to eq(text)
    end
  end

  # CR-01 (LOGS-01): xcodebuild/compiler output carries arbitrary bytes. One
  # invalid-UTF-8 sequence used to raise JSON::GeneratorError OUT of the
  # writer, killing the Sh reader thread mid-stream and failing the wrapped
  # build. Capture must never mask, fail, or alter the operation: invalid
  # bytes degrade to U+FFFD replacements (the file stays a valid JSONL
  # document) and the run continues.
  describe 'invalid UTF-8 degradation (CR-01)' do
    it 'scrubs invalid bytes in body lines instead of raising; the run continues' do
      log = open_log
      expect { log.record_text("bad \xFF\xFE bytes\n", 'out') }.not_to raise_error
      log.record_text("after the bad line\n", 'out')
      log.finish(0)

      parsed = File.read(log.path).lines.map { |line| JSON.parse(line) } # every line valid JSON
      texts = parsed.select { |entry| entry.key?('text') }.map { |entry| entry['text'] }
      expect(texts.first).to include("bad \uFFFD\uFFFD bytes\n")
      expect(texts).to include("after the bad line\n") # capture kept streaming
    end

    it 'scrubs invalid bytes in event string fields and keeps non-string fields typed' do
      log = open_log
      expect { log.event('sh', cmd: "xcodebuild \xFF build\n", status: 65) }.not_to raise_error
      log.finish(0)

      events = File.read(log.path).lines.map { |line| JSON.parse(line) }.select { |entry| entry['event'] == 'sh' }
      expect(events.first['cmd']).to eq("xcodebuild \uFFFD build\n")
      expect(events.first['status']).to eq(65) # the JSON schema keeps numeric types
    end
  end

  describe 'partial-line buffering' do
    it 'emits ONE body line for record_line("par") followed by record_line("tial\n")' do
      log = open_log
      log.record_line('par', 'out')
      log.record_line("tial\n", 'out')
      log.finish(0)
      lines = File.read(log.path).lines
      expect(lines.length).to eq(3)
      expect(JSON.parse(lines[1])['text']).to eq("partial\n")
    end

    it 'flushes a trailing partial line (no newline) at finish so it is not dropped (SC2)' do
      log = open_log
      log.record_line('dangling', 'err')
      log.finish(0)
      lines = File.read(log.path).lines
      expect(lines.length).to eq(3)
      expect(JSON.parse(lines[1])['text']).to eq('dangling')
    end
  end

  describe 'finish' do
    it 'is idempotent: double finish writes exactly one run_end and restores RunLog.current' do
      expect(described_class.current).to be_nil
      log = open_log
      expect(described_class.current).to equal(log)
      log.record_text("body\n", 'out')
      log.finish(0)
      log.finish(0)

      lines = File.read(log.path).lines
      expect(lines.length).to eq(3)
      expect(lines.count { |line| JSON.parse(line)['event'] == 'run_end' }).to eq(1)
      expect(JSON.parse(lines.last)).to include('event' => 'run_end', 'status' => 0)
      expect(described_class.current).to be_nil
    end
  end

  describe 'concurrency (EDGE adjacency)' do
    it 'opens two distinct files in the same runs dir (ms-timestamp + pid disambiguation)' do
      log1 = open_log
      log2 = open_log # same millisecond, same pid: exercises the -1 collision suffix
      expect(log1.path).not_to eq(log2.path)

      log2.finish(0) # nested save/restore: inner finishes first
      log1.finish(0)

      expect(File.exist?(log1.path)).to be(true)
      expect(File.exist?(log2.path)).to be(true)
      expect(described_class.current).to be_nil
    end

    it 'serializes concurrent appends: 200 interleaved lines, every physical line valid JSON' do
      log = open_log
      threads = [1, 2].map do |t|
        Thread.new { 100.times { |i| log.record_text("thread-#{t} line #{i}\n", 'out') } }
      end
      threads.each(&:join)
      log.finish(0)

      lines = File.read(log.path).lines
      expect(lines.length).to eq(202) # header + 200 body lines + run_end
      parsed = lines.map { |line| JSON.parse(line) } # raises on any interleaved/corrupt line
      texts = parsed[1..-2].map { |body| body['text'] }
      expect(texts.length).to eq(200) # all 200 appends landed, none lost
      expected = [1, 2].flat_map { |t| (0...100).map { |i| "thread-#{t} line #{i}\n" } }
      expect(texts.sort).to eq(expected.sort)
    end
  end

  describe 'safety degradation' do
    it 'returns nil with a single warning when the runs dir is unwritable (command proceeds unlogged)' do
      FileUtils.chmod(0o000, runs_dir)
      begin
        log = nil
        expect { log = open_log }.to output(/run log disabled/).to_stderr
        expect(log).to be_nil
      ensure
        FileUtils.chmod(0o700, runs_dir)
      end
    end

    it 'never raises into the caller when an append fails, warning at most once and disabling the log' do
      log = open_log
      log.record_text("logged before failure\n", 'out')
      log.instance_variable_get(:@file).close # force the append failure

      expect { log.record_text('first append fails', 'out') }.to output(/run log disabled/).to_stderr
      expect { log.record_text('second append is silent', 'out') }.not_to output.to_stderr
      expect { log.finish(0) }.not_to raise_error

      lines = File.read(log.path).lines
      expect(lines.length).to eq(2) # header + the one pre-failure body; nothing appended after disable
      expect(described_class.current).to be_nil # finish still restores the seam
    end
  end

  # Retention (SC4): count + size hybrid (D-06) applied at run start, after
  # the new header lands (D-07). Budgets come from Config (Singleton --
  # reset! around every example). Fabricated prior-run files carry a real
  # run_start line whose pid controls liveness (Pitfall 6) and optional
  # padding bytes for the size budget; their 2020… names sort strictly
  # BEFORE the just-opened run's 2026… file name, so lexicographic ==
  # chronological holds (EDGE ordering).
  describe 'retention (SC4: D-06/D-07 — count + size hybrid at run start)' do
    let(:config) { SPMCache::Core::Config.instance }

    def fabricate_old_run(name, pid: 2_000_000, bytes: 0)
      path = File.join(runs_dir, name)
      File.write(path, "#{JSON.generate('event' => 'run_start', 'pid' => pid)}\n")
      File.open(path, 'a') { |f| f.write('x' * bytes) } if bytes.positive?
      path
    end

    before do
      config.reset!
      config.raw['runs_keep'] = 50
      config.raw['runs_max_mb'] = 500
    end

    after { config.reset! }

    it 'keeps the newest runs_keep prior runs plus the just-opened one (count bound)' do
      config.raw['runs_keep'] = 2
      4.times { |i| fabricate_old_run("20200101T00000000#{i}Z-1-use.jsonl") }
      log = open_log
      log.finish(0)

      expect(Dir.children(runs_dir).sort).to eq(
        ['20200101T000000002Z-1-use.jsonl', '20200101T000000003Z-1-use.jsonl', File.basename(log.path)]
      )
    end

    it 'prunes oldest-first lexicographic until the size budget fits; newest fabricated survives (size bound + EDGE ordering)' do
      config.raw['runs_max_mb'] = 1 # 1 MiB budget; fabricated total is 1_800_000 bytes
      %w[0 1 2].each { |i| fabricate_old_run("20200101T00000000#{i}Z-1-use.jsonl", bytes: 600_000) }
      log = open_log
      log.finish(0)

      expect(File.exist?(File.join(runs_dir, '20200101T000000000Z-1-use.jsonl'))).to be(false) # oldest died first
      expect(File.exist?(File.join(runs_dir, '20200101T000000001Z-1-use.jsonl'))).to be(false)
      expect(File.exist?(File.join(runs_dir, '20200101T000000002Z-1-use.jsonl'))).to be(true) # newest fabricated survives
      expect(Dir.children(runs_dir).sort).to eq(['20200101T000000002Z-1-use.jsonl', File.basename(log.path)])
    end

    it 'never deletes the just-opened run even at zero budgets (current-run immunity; the current file exists during prune — D-07)' do
      config.raw['runs_keep'] = 0
      config.raw['runs_max_mb'] = 0
      fabricate_old_run('20200101T000000000Z-1-use.jsonl')
      log = open_log
      log.finish(0)

      expect(Dir.children(runs_dir)).to eq([File.basename(log.path)])
      expect(File.read(log.path).lines.length).to eq(2) # header + run_end: the run itself was unaffected
    end

    it 'never prunes a live-pid run even over budget; a dead-pid run is pruned (Pitfall 6 / CP14 at birth)' do
      config.raw['runs_keep'] = 0
      config.raw['runs_max_mb'] = 0
      live = fabricate_old_run('20200101T000000000Z-1-use.jsonl', pid: Process.pid) # alive, no run_end line
      dead = fabricate_old_run('20200101T000000001Z-2-use.jsonl', pid: 2_000_000) # ESRCH: out-of-range pid
      log = open_log
      log.finish(0)

      expect(File.exist?(live)).to be(true)
      expect(File.exist?(dead)).to be(false)
      expect(File.exist?(log.path)).to be(true)
    end

    # CR-03 / T-12-04: every prior cycle of a RUNNING watch session carries
    # the watch process's own (alive) pid. Liveness protection exists for
    # CONCURRENT runs (Pitfall 6) -- a same-pid prior cycle is by
    # construction finished (its run_end landed in finish) -- so exempting
    # it left intra-session growth unbounded until process exit.
    it 'prunes a finished prior cycle of the SAME process; the third cycle of a watch session bounds the first (CR-03)' do
      config.raw['runs_keep'] = 1
      config.raw['runs_max_mb'] = 500
      first = fabricate_old_run('20200101T000000000Z-1-watch.jsonl', pid: Process.pid)
      second = fabricate_old_run('20200101T000000001Z-1-watch.jsonl', pid: Process.pid)
      log = open_log # third cycle of the same process
      log.finish(0)

      expect(File.exist?(first)).to be(false)  # oldest same-pid cycle pruned
      expect(File.exist?(second)).to be(true)  # within keep budget
      expect(Dir.children(runs_dir).sort).to eq([File.basename(second), File.basename(log.path)])
    end

    it 'deletes nothing when the runs dir is under both budgets (EDGE empty)' do
      2.times { |i| fabricate_old_run("20200101T00000000#{i}Z-1-use.jsonl") }
      log = open_log
      log.finish(0)

      expect(Dir.children(runs_dir).length).to eq(3) # 2 prior runs + current, all retained
    end

    it 'skips a candidate it cannot delete and never raises into the run (degradation)' do
      config.raw['runs_keep'] = 0
      config.raw['runs_max_mb'] = 0
      # A directory matching *.jsonl can never be unlinked by File.delete --
      # the same per-candidate failure as a file that vanished mid-walk
      # (concurrent prune): skip, never raise.
      unprunable = File.join(runs_dir, '20200101T000000000Z-1-use.jsonl')
      Dir.mkdir(unprunable)
      log = nil
      expect { log = open_log }.not_to raise_error
      expect(File.exist?(unprunable)).to be(true) # skipped, left alone
      log.finish(0)
      expect(File.read(log.path).lines.length).to eq(2) # the run proceeded normally
    end
  end

  # D-08 (Plan 12-05): ALL verbs log via the Main.run tee -- exactly two
  # verb exclusions (web by SC3, watch by D-09 per-cycle files) plus the
  # --no-run-log flag. This truth table asserts the exclusion decision is
  # verb-SET based, structurally NOT an allowlist: the future-verb row
  # below (['frobnicate']) logs with no code change -- an implementation
  # enumerating allowed verbs would fail it.
  describe '.pre_scan truth table (D-08: no allowlist)' do
    it 'every real verb logs: use/build/doctor/cache/rollback/remote/pkg/init' do
      {
        ['use'] => 'use',
        %w[build Alamofire] => 'build',
        ['doctor'] => 'doctor',
        %w[cache list] => 'cache',
        ['rollback'] => 'rollback',
        %w[remote push] => 'remote',
        %w[pkg build X] => 'pkg',
        ['init'] => 'init'
      }.each do |argv, verb|
        scan = described_class.pre_scan(argv)
        expect(scan.verb).to eq(verb)
        expect(scan.main_log_skipped?).to be(false)
        expect(scan.suppressed?).to be(false)
      end
    end

    it 'a future verb logs with no code change -- the exclusion set is {web, watch}, not a membership list' do
      scan = described_class.pre_scan(['frobnicate'])
      expect(scan.verb).to eq('frobnicate')
      expect(scan.main_log_skipped?).to be(false)
      expect(scan.suppressed?).to be(false)
    end

    it 'excludes exactly web and watch at Main level (SC3 / D-09)' do
      expect(described_class.pre_scan(['web']).main_log_skipped?).to be(true)
      expect(described_class.pre_scan(['watch']).main_log_skipped?).to be(true)
    end

    it 'suppresses on --no-run-log wherever it appears (D-03)' do
      expect(described_class.pre_scan(['--no-run-log', 'use']).suppressed?).to be(true)
      expect(described_class.pre_scan(['use', '--no-run-log']).suppressed?).to be(true)
    end

    it "legacy 'use --watch' logs as ONE session-level use run at Main level" \
      ' (A6 / Open Question 1: D-09 per-cycle mandate targets the watch daemon;' \
      ' the legacy loop is CLI-only per CP5)' do
      scan = described_class.pre_scan(['use', '--watch'])
      expect(scan.verb).to eq('use')
      expect(scan.main_log_skipped?).to be(false)
    end

    # CR-02: the scan must cover the WHOLE argv. CLAide accepts --log-dir=X
    # in any position (validated live: parse + validate! pass pre- and
    # post-verb), so a scan that stops at the verb silently misroutes every
    # post-verb override -- and `watch` is always post-verb, so its override
    # was entirely dead. D-01 contract: the override works wherever CLAide
    # accepts it.
    it 'routes --log-dir=X in ANY position, pre-verb and post-verb (D-01/CR-02)' do
      scan = described_class.pre_scan(['use', '--log-dir=/tmp/x'])
      expect(scan.log_dir).to eq('/tmp/x')
      expect(scan.verb).to eq('use')

      scan = described_class.pre_scan(['build', 'Alamofire', '--config=release', '--log-dir=/tmp/x'])
      expect(scan.log_dir).to eq('/tmp/x')
      expect(scan.verb).to eq('build')
    end

    it 'consumes but never routes the CLAide-rejected two-token --log-dir X form (CR-02: CLAide parity)' do
      scan = described_class.pre_scan(['--log-dir', '/tmp/x', 'build'])
      expect(scan.verb).to eq('build') # the value never masquerades as the verb
      expect(scan.log_dir).to be_nil   # and no override is routed for a form CLAide rejects

      scan = described_class.pre_scan(['watch', '--log-dir', '/tmp/x', '--once'])
      expect(scan.verb).to eq('watch')
      expect(scan.log_dir).to be_nil
    end

    it 'watch + --log-dir: the = form routes, the two-token form routes nowhere (D-01)' do
      scan = described_class.pre_scan(['watch', '--log-dir=/tmp/x'])
      expect(scan.main_log_skipped?).to be(true)
      expect(scan.log_dir).to eq('/tmp/x')

      scan = described_class.pre_scan(['--log-dir', '/tmp/x', 'watch'])
      expect(scan.main_log_skipped?).to be(true)
      expect(scan.log_dir).to be_nil # CLAide rejects this form; the scan agrees
    end
  end
end

RSpec.describe SPMCache::Core::RunLog::TeeIO do
  it 'delegates tty?, isatty, sync, sync=, flush to the real IO and returns its write byte count' do
    runs_dir = Dir.mktmpdir
    begin
      log = SPMCache::Core::RunLog.open(runs_dir: runs_dir, command: 'use')
      real = StringIO.new
      allow(real).to receive(:tty?).and_return(true)
      allow(real).to receive(:isatty).and_return(false)
      allow(real).to receive(:sync).and_return(:sync_state)
      allow(real).to receive(:sync=)
      allow(real).to receive(:flush).and_return(:flush_return)
      tee = described_class.new(real, log, 'out')

      expect(tee.write('hello')).to eq(5)
      expect(real.string).to eq('hello') # terminal leg FIRST, write-through
      expect(tee.puts('line')).to be_nil
      expect(real.string).to eq("helloline\n")
      expect(tee.print('x')).to be_nil
      expect(real.string).to eq("helloline\nx")
      expect(tee << 'y').to be(tee) # IO#<< returns self
      expect(real.string).to eq("helloline\nxy")

      expect(tee.tty?).to be(true)
      expect(tee.isatty).to be(false)
      expect(tee.sync).to eq(:sync_state)
      tee.sync = false
      expect(real).to have_received(:sync=).with(false)
      expect(tee.flush).to eq(:flush_return)

      log.finish(0)
    ensure
      SPMCache::Core::RunLog.current = nil
      FileUtils.rm_rf(runs_dir)
    end
  end
end

RSpec.describe SPMCache::Core::RunLog::StreamSink do
  it 'routes output(line) to a per-stream record_text (Core::Sh live_log contract, sh.rb:24-25)' do
    runs_dir = Dir.mktmpdir
    begin
      log = SPMCache::Core::RunLog.open(runs_dir: runs_dir, command: 'use')
      described_class.new(log, 'err').output("subprocess stderr\n") # lines arrive WITH trailing newline
      described_class.new(log, 'out').output("subprocess stdout\n")
      log.finish(0)

      lines = File.read(log.path).lines
      expect(lines.length).to eq(4) # header + err + out + run_end
      expect(JSON.parse(lines[1])).to include('stream' => 'err', 'text' => "subprocess stderr\n")
      expect(JSON.parse(lines[2])).to include('stream' => 'out', 'text' => "subprocess stdout\n")
    ensure
      SPMCache::Core::RunLog.current = nil
      FileUtils.rm_rf(runs_dir)
    end
  end
end
