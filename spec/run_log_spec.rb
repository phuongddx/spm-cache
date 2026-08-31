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
