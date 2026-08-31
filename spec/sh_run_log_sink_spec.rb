# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'tmpdir'

# Real-subprocess coverage of Core::Sh's popen3 run-log seams (LOGS-01/SC2):
# per-stream sinks, full-fidelity file capture, and the restored 60-line
# failure_detail on live-mode failures (the discarded-capture gap, sh.rb:20-33
# drops every line today). Real echo/printf through the real Core::Sh is
# established suite precedent (core_spec.rb:6-31). Stream attribution is
# tested with explicit echo-to-stderr redirection, never xcodebuild
# heuristics (Pitfall 4 warning sign). No default-deny guard here by design:
# a real subprocess through the real Sh seam IS the point of this file
# (Pitfall 8).
RSpec.describe SPMCache::Core::Sh do
  let(:runs_dir) { Dir.mktmpdir }
  # A real RunLog in a tmpdir -- the exact sink shape Plan 12-04 threads
  # from the xcodebuild path (StreamSink over the sh.rb live_log contract).
  let(:log) { SPMCache::Core::RunLog.open(runs_dir: runs_dir, command: 'use') }
  let(:out_sink) { SPMCache::Core::RunLog::StreamSink.new(log, 'out') }
  let(:err_sink) { SPMCache::Core::RunLog::StreamSink.new(log, 'err') }

  after do
    SPMCache::Core::RunLog.current = nil
    FileUtils.rm_rf(runs_dir)
  end

  def read_lines(path)
    File.read(path).lines.map { |line| JSON.parse(line) }
  end

  # Body lines never carry an `event` key (by construction, run_log.rb), so
  # this selects exactly the captured subprocess text.
  def bodies(path)
    read_lines(path).reject { |entry| entry.key?('event') }
  end

  describe 'popen3 failure_detail tails (SC2 discarded-capture gap)' do
    # printf assembles the marker at runtime: the command string itself
    # never contains the assertion text, so these examples can only pass
    # when the RAISED MESSAGE carries the streamed line (the popen3 raise
    # embeds the command today, so an `echo marker` shape would match
    # vacuously through the cmd text).
    it 'raises with the streamed stdout line in the message (legacy live_log form)' do
      cmd = "printf 'stdout-%s detail\\n' marker && false"
      expect { described_class.run(cmd, live_log: out_sink) }
        .to raise_error(SPMCache::Core::GeneralError, /stdout-marker detail/)
    end

    it 'raises with the streamed stderr line in the message (legacy live_log form)' do
      cmd = "printf 'stderr-%s detail\\n' marker 1>&2 && false"
      expect { described_class.run(cmd, live_log: out_sink) }
        .to raise_error(SPMCache::Core::GeneralError, /stderr-marker detail/)
    end

    it 'raises with the streamed stdout line when per-stream sinks are passed (core_spec precedent shape)' do
      expect do
        described_class.run("echo 'the real error is here' && false", live_log_out: out_sink, live_log_err: err_sink)
      end
        .to raise_error(SPMCache::Core::GeneralError, /the real error is here/)
    end

    it 'raises with the streamed stderr line when per-stream sinks are passed (core_spec precedent shape)' do
      expect do
        described_class.run("echo 'stderr detail' 1>&2 && false", live_log_out: out_sink, live_log_err: err_sink)
      end
        .to raise_error(SPMCache::Core::GeneralError, /stderr detail/)
    end
  end

  describe 'popen3 per-stream sinks (Pitfall 4)' do
    it 'lands stdout tagged out and stderr tagged err in the run-log file' do
      described_class.run('echo out-line; echo err-line 1>&2', live_log_out: out_sink, live_log_err: err_sink)
      log.finish(0)
      expect(bodies(log.path)).to contain_exactly(
        include('stream' => 'out', 'text' => "out-line\n"),
        include('stream' => 'err', 'text' => "err-line\n")
      )
    end

    it 'writes the FULL stream to the file; the 60-line tail bound never touches it (D-05)' do
      described_class.run('for i in $(seq 1 100); do echo "line $i"; done', live_log_out: out_sink,
                                                                            live_log_err: err_sink)
      log.finish(0)
      body = bodies(log.path)
      expect(body.length).to eq(100)
      expect(body.first['text']).to eq("line 1\n")
      expect(body.last['text']).to eq("line 100\n")
    end

    it 'returns the tailed output/error strings with status 0 (enriched success return)' do
      result = described_class.run('echo ok-line; echo bad-line 1>&2', live_log_out: out_sink, live_log_err: err_sink)
      expect(result).to include(output: "ok-line\n", error: "bad-line\n", status: 0)
    end

    it 'adds zero body lines for a zero-output subprocess and the file stays valid (EDGE empty)' do
      described_class.run('true', live_log_out: out_sink, live_log_err: err_sink)
      log.finish(0)
      lines = File.read(log.path).lines
      expect(lines.length).to eq(2) # header + run_end only
      lines.each { |line| JSON.parse(line) }
    end
  end

  describe 'legacy live_log back-compat' do
    it 'still calls output(line) for every line of BOTH streams on the single object' do
      spy = Class.new do
        def initialize
          @lines = []
        end

        attr_reader :lines

        def output(line)
          @lines << line
        end
      end.new
      described_class.run('echo a-line; echo b-line 1>&2', live_log: spy)
      expect(spy.lines.sort).to eq(%W[a-line\n b-line\n])
    end
  end

  describe '.capture_output sh events (Pitfall 5 / A2)' do
    it 'records one {event: sh, ts, cmd, status} line per completed capture, returned value unchanged' do
      expect(described_class.capture_output('echo hi')).to eq('hi')
      log.finish(0)
      events = read_lines(log.path).select { |entry| entry['event'] == 'sh' }
      expect(events.length).to eq(1)
      expect(events.first).to include('event' => 'sh', 'cmd' => 'echo hi', 'status' => 0)
      expect(events.first['ts']).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/)
    end

    it 'records the real exit status before the raise on a failing capture (EDGE empty: zero output, status recorded)' do
      expect { described_class.capture_output('false') }.to raise_error(SPMCache::Core::GeneralError)
      log.finish(0)
      events = read_lines(log.path).select { |entry| entry['event'] == 'sh' }
      expect(events).to contain_exactly(include('cmd' => 'false', 'status' => 1))
    end

    it 'records nothing when RunLog.current is nil (nil-disables)' do
      expect(SPMCache::Core::RunLog.current).to be_nil
      expect(described_class.capture_output('echo nil-case')).to eq('nil-case')
      expect(Dir.children(runs_dir)).to be_empty
    end
  end
end
