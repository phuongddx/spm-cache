# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'tmpdir'
require 'fileutils'
require 'stringio'

# Unit coverage for the Web::Events tailer + run-choice/resume derivation
# (LOGS-03/LOGS-04): byte-offset entry ids, partial-line buffering, exact
# resume across multi-byte content, the D-13 fresh-connect choice, and the
# writer-agnostic watch-cycle shape. Hermetic: tmpdir runs-dir fixtures in
# the Phase 12 JSONL vocabulary, real file appends, zero shell-outs (the
# default-deny Sh guard below), bounded queue pops everywhere.
RSpec.describe 'SPMCache::Web::Events tailer' do
  RUN_A = '20260901T093000123Z-4821-build.jsonl'
  RUN_B = '20260901T094500456Z-5302-use.jsonl'
  WATCH_RUN = '20260901T093500789Z-6100-watch.jsonl'
  # A pid that is dead by construction (retention's own probe posture,
  # run_log.rb:395-402): Process.kill(0, 999_999_999) raises ESRCH.
  DEAD_PID = 999_999_999

  let(:project_dir) { Dir.mktmpdir('spm-cache-events-project') }
  let(:config) { SPMCache::Core::Config.instance }
  let(:runs_dir) { File.join(project_dir, '.spm-cache', 'runs') }

  around do |example|
    previous = config.project_dir
    SPMCache::Core::Config.configure(project_dir: project_dir)
    config.reset!
    FileUtils.mkdir_p(runs_dir)
    example.run
  ensure
    @events&.shutdown!
    config.reset!
    SPMCache::Core::Config.configure(project_dir: previous)
    FileUtils.rm_rf(project_dir)
  end

  before do
    # Default-deny Sh guard (run_log_spec.rb idiom): the tailer is a pure
    # file reader -- any shell-out is a bug this suite must catch.
    allow(SPMCache::Core::Sh).to receive(:run) do |cmd, *_opts|
      raise "unexpected real invocation: Sh.run(#{cmd.inspect})"
    end
    allow(SPMCache::Core::Sh).to receive(:capture_output) do |cmd, *_opts|
      raise "unexpected real invocation: Sh.capture_output(#{cmd.inspect})"
    end
  end

  # The class under test is resolved INSIDE examples: the RED run must
  # report failing examples, not a load error (SPMCache::Web::Events is
  # undefined until the GREEN implementation lands).
  def events_class
    SPMCache::Web::Events
  end

  def start_events(poll_interval: 0.02)
    @events = events_class.new(config: config, poll_interval: poll_interval)
  end

  def header_line(command:, trigger:, pid: Process.pid)
    JSON.generate(
      'event' => 'run_start', 'ts' => '2026-09-01T09:30:00Z', 'command' => command,
      'argv' => [command], 'redacted' => false, 'pid' => pid,
      'started_at' => '2026-09-01T09:30:00Z', 'spm_cache_version' => '0.5.0',
      'trigger' => trigger, 'cycle' => false
    ) + "\n"
  end

  def body_line(text)
    JSON.generate('ts' => '2026-09-01T09:30:01Z', 'stream' => 'out', 'text' => text) + "\n"
  end

  def run_end_line(status = 0)
    JSON.generate('event' => 'run_end', 'ts' => '2026-09-01T09:31:00Z',
                  'status' => status, 'ended_at' => '2026-09-01T09:31:00Z') + "\n"
  end

  def run_path(name)
    File.join(runs_dir, name)
  end

  def write_run(name, lines)
    File.write(run_path(name), lines.join)
  end

  def append_run(name, text)
    File.open(run_path(name), 'a') { |f| f.write(text) }
  end

  def wait_until(timeout: 5)
    deadline = Time.now + timeout
    loop do
      result = yield
      return result if result

      raise 'condition not met within bound' if Time.now > deadline

      sleep 0.01
    end
  end

  it 'follows a run file: entry ids are <basename>:<byte-offset>, monotonic, advancing by each line bytesize' do
    header = header_line(command: 'build', trigger: 'terminal')
    line1 = body_line("line one\n")
    write_run(RUN_A, [header, line1])

    events = start_events
    client = events.register(StringIO.new)
    wait_until { events.tailer.path }

    line2 = body_line("second\n")
    line3 = body_line("third\n")
    append_run(RUN_A, line2)
    append_run(RUN_A, line3)
    entries = 2.times.map { client.queue.pop(timeout: 5) }

    # The id offset is recorded AFTER the consumed newline (Pitfall 5), so
    # resuming at an id seeks exactly to the next line.
    first_offset = header.bytesize + line1.bytesize + line2.bytesize
    expect(entries.map(&:id)).to eq(
      ["#{RUN_A}:#{first_offset}", "#{RUN_A}:#{first_offset + line3.bytesize}"]
    )
    expect(entries.map(&:file)).to eq([RUN_A, RUN_A])
  end

  it 'buffers a partial trailing write: no entry until the newline lands, then exactly one' do
    header = header_line(command: 'build', trigger: 'terminal')
    write_run(RUN_A, [header])

    events = start_events
    client = events.register(StringIO.new)
    wait_until { events.tailer.path }

    append_run(RUN_A, 'par')
    sleep 0.1 # several poll ticks with the partial line outstanding
    expect(client.queue.pop(timeout: 0.2)).to be_nil

    append_run(RUN_A, "tial\n")
    entry = client.queue.pop(timeout: 5)
    expect(entry.line).to eq("partial\n")
    expect(entry.id).to eq("#{RUN_A}:#{header.bytesize + 8}")
    expect(client.queue.pop(timeout: 0.2)).to be_nil # exactly one entry, no split halves
  end

  it 'resume-at-id yields exactly the NEXT line for multi-byte UTF-8 content' do
    header = header_line(command: 'use', trigger: 'terminal')
    line1 = body_line("first\n")
    cjk = body_line("Building Alamofire 依赖图 with emoji 🚀 and ünïcödé\n")
    line3 = body_line("after cjk\n")
    write_run(RUN_A, [header, line1, cjk, line3])

    # The id recorded for the CJK line: byte offset AFTER its newline --
    # byte math over multi-byte content is the whole point (Pitfall 5).
    resume_offset = header.bytesize + line1.bytesize + cjk.bytesize
    entries = events_class.each_entry(run_path(RUN_A), resume_offset).to_a

    expect(entries.length).to eq(1) # no duplicated boundary line, none lost
    expect(entries.first.line).to eq(line3)
    expect(entries.first.id).to eq("#{RUN_A}:#{resume_offset + line3.bytesize}")

    # From byte 0 the same reader yields the file verbatim, in order.
    expect(events_class.each_entry(run_path(RUN_A), 0).map(&:line)).to eq([header, line1, cjk, line3])
  end

  it 'D-13: a live-pid run without run_end is chosen over older completed runs and replays from byte 0' do
    write_run(RUN_A,
              [header_line(command: 'build', trigger: 'terminal', pid: DEAD_PID), body_line("old\n"), run_end_line])
    header_b = header_line(command: 'use', trigger: 'terminal')
    line_b = body_line("newest live\n")
    write_run(RUN_B, [header_b, line_b]) # newest, live pid, no run_end

    chosen = events_class.choose_run(runs_dir: runs_dir)
    expect(chosen).to eq(run_path(RUN_B))
    # Replay from byte 0: the very first replayed entry is B's header line.
    expect(events_class.each_entry(chosen, 0).first.line).to eq(header_b)
  end

  it 'D-13: with no live run, the newest file overall is chosen' do
    write_run(RUN_A, [header_line(command: 'build', trigger: 'terminal', pid: DEAD_PID), run_end_line])
    write_run(RUN_B, [header_line(command: 'use', trigger: 'terminal', pid: DEAD_PID), run_end_line])

    expect(events_class.choose_run(runs_dir: runs_dir)).to eq(run_path(RUN_B))
  end

  it 'D-13: an empty runs dir yields no run' do
    expect(events_class.choose_run(runs_dir: runs_dir)).to be_nil
  end

  it 'tails a watch-cycle file identically (writer-agnostic transport, LOGS-04)' do
    header = header_line(command: 'watch', trigger: 'watch')
    write_run(WATCH_RUN, [header])

    events = start_events
    client = events.register(StringIO.new)
    wait_until { events.tailer.path }

    line = body_line("cycle output\n")
    append_run(WATCH_RUN, line)
    entry = client.queue.pop(timeout: 5)
    expect(entry.line).to eq(line)
    expect(entry.id).to eq("#{WATCH_RUN}:#{header.bytesize + line.bytesize}")
  end

  it 'carries the JSONL line verbatim (JSON round-trip equality)' do
    header = header_line(command: 'build', trigger: 'terminal')
    write_run(RUN_A, [header])

    events = start_events
    client = events.register(StringIO.new)
    wait_until { events.tailer.path }

    appended = [body_line("verbatim one\n"), body_line("verbatim two\n")]
    append_run(RUN_A, appended.join)
    entries = 2.times.map { client.queue.pop(timeout: 5) }

    entries.zip(appended).each do |entry, raw|
      expect(entry.line).to eq(raw) # byte-for-byte, trailing newline included
      expect(JSON.parse(entry.line)).to eq(JSON.parse(raw)) # still valid JSONL
    end
  end
end
