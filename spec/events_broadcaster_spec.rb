# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'tmpdir'
require 'fileutils'
require 'stringio'

# Broadcaster hardening for Web::Events (CP11 / WEB-03): drop-oldest with
# an exact-count notice, pop-timeout heartbeats (no timer thread), the
# shutdown sentinel (bounded return, idempotent, safe at zero clients,
# and delivered even to a client registered during shutdown), dead-client
# discovery through the heartbeat write, and the register/unregister race
# invariant. Real threads, real SizedQueues, bounded joins everywhere;
# injectable heartbeat/cap so nothing sleeps 15s (web_doctor_spec
# concurrency posture).
RSpec.describe 'SPMCache::Web::Events broadcaster' do
  let(:project_dir) { Dir.mktmpdir('spm-cache-events-broadcaster') }
  let(:config) { SPMCache::Core::Config.instance }
  let(:runs_dir) { File.join(project_dir, '.spm-cache', 'runs') }

  around do |example|
    previous = config.project_dir
    SPMCache::Core::Config.configure(project_dir: project_dir)
    config.reset!
    FileUtils.mkdir_p(runs_dir) # empty runs dir: hello is idle, no replay
    example.run
  ensure
    config.reset!
    SPMCache::Core::Config.configure(project_dir: previous)
    FileUtils.rm_rf(project_dir)
  end

  after do
    @events&.shutdown!
  end

  def events_class
    SPMCache::Web::Events
  end

  def start_events(heartbeat_seconds:, queue_cap: 1000)
    @events = events_class.new(config: config, poll_interval: 0.05,
                               heartbeat_seconds: heartbeat_seconds,
                               queue_cap: queue_cap)
  end

  def wait_for_out(out, pattern, timeout: 2)
    deadline = Time.now + timeout
    until out.string.match?(pattern)
      if Time.now > deadline
        raise "expected #{pattern.inspect} in stream output within #{timeout}s (got: #{out.string.inspect})"
      end

      sleep 0.01
    end
    out.string
  end

  it 'drops the OLDEST entries at cap and flushes one exact-count notice (CP11)' do
    start_events(heartbeat_seconds: 0.5, queue_cap: 3)
    out = StringIO.new
    client = @events.register(out)
    5.times { |i| @events.broadcaster.publish_entry(file: 'race.jsonl', offset: i + 1, line: "l#{i}\n") }

    thread = Thread.new { @events.stream(client) }
    begin
      frames = wait_for_out(out, /lines dropped/)
      @events.shutdown!
      expect(thread.join(2)).to be_truthy

      # The notice is pinned verbatim: '{N} lines dropped' with the exact
      # count of evicted entries (2: l0, l1), flushed as ONE notice at the
      # dropped entries' would-be position -- BEFORE the first survivor.
      expect(frames).to include('event: notice')
      expect(frames).to include('"message":"2 lines dropped"')
      expect(frames.index('2 lines dropped')).to be < frames.index('event: entry')
      # The queue held the NEWEST 3 (l2, l3, l4) -- nothing else survives.
      expect(frames.scan('event: entry').length).to eq(3)
      expect(frames).to include('l4')
    ensure
      @events.shutdown!
      thread.join(2)
    end
  end

  it "writes a ': ping' heartbeat comment on pop timeout (pop-timeout IS the timer)" do
    start_events(heartbeat_seconds: 0.05)
    out = StringIO.new
    client = @events.register(out)

    thread = Thread.new { @events.stream(client) }
    begin
      frames = wait_for_out(out, /: ping/, timeout: 1) # bounded: no 15s sleep
      expect(frames).to include(": ping\n\n")          # comment frame, parser-ignored
    ensure
      @events.shutdown!
      thread.join(2)
    end
  end

  it 'ends a blocked client loop via the sentinel, and a client registered during shutdown still gets one' do
    start_events(heartbeat_seconds: 0.05)
    out = StringIO.new
    client = @events.register(out)

    thread = Thread.new { @events.stream(client) }
    wait_for_out(out, /event: hello/) # loop is live: blocked in pop

    t0 = Time.now
    @events.shutdown!
    expect(thread.join(1)).to be_truthy # returns well within the bound
    expect(Time.now - t0).to be < 1

    # A connect racing the shutdown (register AFTER the fan-out) must not
    # become a sentinel-less straggler -- WEBrick's shutdown join (WEB-03)
    # would otherwise hang on its body proc.
    late = StringIO.new
    late_client = @events.register(late)
    late_thread = Thread.new { @events.stream(late_client) }
    expect(late_thread.join(1)).to be_truthy
  end

  it 'is idempotent and safe with zero clients: exactly one sentinel per client' do
    start_events(heartbeat_seconds: 0.05)
    out = StringIO.new
    client = @events.register(out)

    thread = Thread.new { @events.stream(client) }
    wait_for_out(out, /event: hello/)

    @events.shutdown!
    @events.shutdown! # second call must be a no-op, never a duplicate
    expect(thread.join(1)).to be_truthy
    # The stream consumed its sentinel; a duplicate (double fan-out) would
    # still sit in the queue.
    expect(client.queue.pop(timeout: 0.2)).to be_nil

    quiet = events_class.new(config: config, heartbeat_seconds: 0.05)
    expect { quiet.shutdown! }.not_to raise_error
    expect { quiet.shutdown! }.not_to raise_error # zero clients, twice
  end

  it 'discovers a dead writer through the heartbeat write and unregisters the client' do
    start_events(heartbeat_seconds: 0.05)
    # First write (hello) lands; every later write raises EPIPE -- only a
    # periodic write (the heartbeat) can discover the death with no
    # further entries published.
    dying = +''
    count = 0
    writer = Object.new
    writer.define_singleton_method(:write) do |_text|
      count += 1
      count == 1 ? dying << _text : raise(Errno::EPIPE.new('broken pipe'))
    end
    client = @events.register(writer)

    thread = Thread.new { @events.stream(client) }
    expect(thread.join(2)).to be_truthy # rescued via the ping-path EPIPE
    expect(@events.broadcaster.clients).to be_empty # ensure-unregister ran
  end

  it 'keeps the registry invariant under concurrent register/unregister + publish + shutdown' do
    start_events(heartbeat_seconds: 0.05, queue_cap: 50)
    stream_threads = []
    stop_race = false

    racers = 3.times.map do
      Thread.new do
        until stop_race
          client = @events.register(StringIO.new)
          stream_threads << Thread.new { @events.stream(client) }
          @events.broadcaster.publish_entry(file: 'race.jsonl', offset: 1, line: "r\n")
          @events.broadcaster.unregister(client) # races the streams' own ensure-unregister
        end
      end
    end

    begin
      sleep 0.2            # let the race run
      @events.shutdown!    # MID-race: the WEB-03 hazard
      sleep 0.1
      stop_race = true
    ensure
      stop_race = true
    end

    racers.each { |racer| expect(racer.join(3)).to be_truthy }
    # Every stream returned -- including clients registered after the
    # sentinel fan-out (no straggler can hang WEBrick's join).
    stream_threads.each { |t| expect(t.join(2)).to be_truthy }
  end
end
