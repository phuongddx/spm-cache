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
    entries = 2.times.map { events_class.pop_with_timeout(client.queue, 5) }

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
    expect(events_class.pop_with_timeout(client.queue, 0.2)).to be_nil

    append_run(RUN_A, "tial\n")
    entry = events_class.pop_with_timeout(client.queue, 5)
    expect(entry.line).to eq("partial\n")
    expect(entry.id).to eq("#{RUN_A}:#{header.bytesize + 8}")
    expect(events_class.pop_with_timeout(client.queue, 0.2)).to be_nil # exactly one entry, no split halves
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
    entry = events_class.pop_with_timeout(client.queue, 5)
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
    entries = 2.times.map { events_class.pop_with_timeout(client.queue, 5) }

    entries.zip(appended).each do |entry, raw|
      expect(entry.line).to eq(raw) # byte-for-byte, trailing newline included
      expect(JSON.parse(entry.line)).to eq(JSON.parse(raw)) # still valid JSONL
    end
  end

  describe 'discovery, switch, and retention interplay (D-04/D-07)' do
    PRUNED_NOTICE = 'run log pruned while viewing; switching to newest'

    it 'switches to a newer run with a switch event naming run and previous (D-04)' do
      header_a = header_line(command: 'build', trigger: 'terminal')
      write_run(RUN_A, [header_a])

      events = start_events
      client = events.register(StringIO.new)
      wait_until { events.tailer.path }

      header_b = header_line(command: 'use', trigger: 'terminal')
      line_b1 = body_line("new run first\n")
      write_run(RUN_B, [header_b, line_b1]) # sorts after A: chronological

      items = 3.times.map { events_class.pop_with_timeout(client.queue, 5) }
      switch = items.find { |item| item.respond_to?(:run) }
      expect(switch.run).to eq(RUN_B) # the switch event names the new run
      expect(switch.previous).to eq(RUN_A) # ...and the previous one
      # Continues from B's byte 0: the header and first body line arrive as
      # entries carrying B's filename, at B's own offsets.
      entries = items.compact.reject { |item| item.respond_to?(:run) }
      expect(entries.map(&:line)).to eq([header_b, line_b1])
      expect(entries.map(&:file)).to eq([RUN_B, RUN_B])
      expect(entries.first.id).to eq("#{RUN_B}:#{header_b.bytesize}")
    end

    it 'keeps delivering through its open fd after the served file is unlinked (POSIX, D-07)' do
      header = header_line(command: 'build', trigger: 'terminal')
      write_run(RUN_A, [header])

      events = start_events
      client = events.register(StringIO.new)
      wait_until { events.tailer.path }

      writer = File.open(run_path(RUN_A), 'a') # hold an append handle...
      begin
        File.unlink(run_path(RUN_A)) # ...then retention unlinks the path
        line = body_line("post-unlink bytes\n")
        writer.write(line)
        writer.flush

        entry = events_class.pop_with_timeout(client.queue, 5)
        expect(entry.line).to eq(line) # surfaced through the held fd
        expect(entry.file).to eq(RUN_A)
      ensure
        writer.close
      end
    end

    it "notices 'run log pruned while viewing; switching to newest' and replays the newest run on a vanished resume id" do
      write_run(RUN_A, [header_line(command: 'build', trigger: 'terminal', pid: DEAD_PID), run_end_line])
      header_b = header_line(command: 'use', trigger: 'terminal')
      line_b = body_line("newest body\n")
      write_run(RUN_B, [header_b, line_b]) # B is the live newest run

      resume_id = "#{RUN_A}:0"
      File.delete(run_path(RUN_A)) # retention pruned the viewed run mid-session
      resume = events_class.parse_resume_id(resume_id, runs_dir: runs_dir)
      expect(resume[:exists]).to be(false) # well-formed name, vanished file

      out = StringIO.new
      events = start_events
      client = events.register(out)
      thread = Thread.new { events.stream(client, resume: resume) }
      begin
        frames = wait_until(timeout: 5) { out.string.include?(PRUNED_NOTICE) ? out.string : nil }
        # The notice is followed by fresh replay of the newest run (B).
        expect(frames).to include('event: notice')
        expect(frames.index(PRUNED_NOTICE)).to be > frames.index('event: hello')
        expect(frames).to include('event: entry')
        hello = frames.match(/event: hello\ndata: (\{[^\n]*\})\n/)
        expect(JSON.parse(hello[1])['run']).to eq(RUN_B)
      ensure
        events.shutdown!
        thread.join(2)
      end
    end

    it 'survives a transiently absent runs dir: the thread lives and recovers on the next tick' do
      header_a = header_line(command: 'build', trigger: 'terminal')
      write_run(RUN_A, [header_a])

      events = start_events
      client = events.register(StringIO.new)
      wait_until { events.tailer.path }

      FileUtils.rm_rf(runs_dir) # transiently absent (no glob hits, no crash)
      sleep 0.1 # several poll ticks under the failure
      expect(events.tailer.running?).to be(true) # the thread never died

      FileUtils.mkdir_p(runs_dir)
      header_b = header_line(command: 'use', trigger: 'terminal')
      line_b = body_line("recovery line\n")
      write_run(RUN_B, [header_b, line_b])
      items = 3.times.map { events_class.pop_with_timeout(client.queue, 5) } # discovery recovers
      entries = items.compact.reject { |item| item.respond_to?(:run) }
      expect(entries.map(&:line)).to eq([header_b, line_b])
      expect(entries.map(&:file)).to eq([RUN_B, RUN_B])
    end

    it 'never memoizes identity: a new instance picks up a run that appeared after the old one stopped (CP10/Pitfall 7)' do
      write_run(RUN_A, [header_line(command: 'build', trigger: 'terminal')])
      events1 = start_events
      client1 = events1.register(StringIO.new)
      wait_until { events1.tailer.path }
      events1.shutdown! # stop the old instance

      header_b = header_line(command: 'use', trigger: 'terminal')
      line_b1 = body_line("fresh run one\n")
      write_run(RUN_B, [header_b, line_b1]) # appeared AFTER the stop

      # Fresh-connect choice re-derives from disk -- the registry, the
      # hello derivation, and the follow all read the runs dir anew.
      expect(events_class.choose_run(runs_dir: runs_dir)).to eq(run_path(RUN_B))

      events2 = start_events
      client2 = events2.register(StringIO.new)
      wait_until { events2.tailer.path == run_path(RUN_B) }
      line_b2 = body_line("fresh run two\n")
      append_run(RUN_B, line_b2)
      entry = events_class.pop_with_timeout(client2.queue, 5)
      expect(entry.file).to eq(RUN_B)
      expect(entry.line).to eq(line_b2)
    end
  end
end
