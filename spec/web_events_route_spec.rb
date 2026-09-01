# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'tmpdir'
require 'fileutils'
require 'securerandom'
require 'stringio'

require_relative 'support/web_server_boot'

# GET /api/events -- the SSE route (LOGS-03). Raw loopback sockets via the
# WebServerBoot SSE helpers (Net::HTTP would block forever on the endless
# stream). Pinned per 14-01: 200 text/event-stream ALWAYS once authed (any
# non-200 permanently kills EventSource reconnect, WHATWG 9.2.3 -- the
# milestone 503 clause is falsified), hello carrying retry + parsed header
# + derived status, replay-from-byte-0, live delivery, exact Last-Event-ID
# resume (regex-validated incl. the collision suffix; hostile ids fall
# back to fresh replay and are NEVER opened), Connection: close, and the
# exactly-once replay->queue handoff. Short poll/heartbeat injected for
# bounded reads.
RSpec.describe 'SPMCache::Web /api/events SSE route' do
  TRIGGER = 'watch-cycle-7' # D-11: passes through verbatim, no allowlist
  RUN_NAME = "20260901T093000123Z-#{Process.pid}-build.jsonl"
  COLLISION_NAME = "20260901T093000123Z-#{Process.pid}-build-1.jsonl" # run_log.rb:120-123
  BIG_RUN_NAME = "20260901T093500999Z-#{Process.pid}-build.jsonl"

  let(:project_dir) { Dir.mktmpdir('spm-cache-events-route') }
  let(:runs_dir) { File.join(project_dir, '.spm-cache', 'runs') }

  def events_class
    SPMCache::Web::Events
  end

  def self.header_line(command:, trigger:, pid: Process.pid)
    JSON.generate(
      'event' => 'run_start', 'ts' => '2026-09-01T09:30:00Z', 'command' => command,
      'argv' => [command, 'Alamofire'], 'redacted' => false, 'pid' => pid,
      'started_at' => '2026-09-01T09:30:00Z', 'spm_cache_version' => '0.5.0',
      'trigger' => trigger, 'cycle' => false
    ) + "\n"
  end

  def self.body_line(text)
    JSON.generate('ts' => '2026-09-01T09:30:01Z', 'stream' => 'out', 'text' => text) + "\n"
  end

  # Instance delegates so examples can build ad-hoc lines.
  def header_line(**kwargs)
    self.class.header_line(**kwargs)
  end

  def body_line(text)
    self.class.body_line(text)
  end

  def run_path(name)
    File.join(runs_dir, name)
  end

  def append_run(name, text)
    File.open(run_path(name), 'a') { |f| f.write(text) }
  end

  HEADER = header_line(command: 'build', trigger: TRIGGER).freeze
  LINE1 = body_line("replay one\n").freeze
  LINE2 = body_line("replay two\n").freeze
  LINE1_TEXT = 'replay one'
  LINE2_TEXT = 'replay two'

  def write_main_fixture
    FileUtils.mkdir_p(runs_dir)
    File.write(run_path(RUN_NAME), [HEADER, LINE1, LINE2].join)
  end

  def with_events_server(&block)
    write_main_fixture
    events = events_class.new(config: SPMCache::Core::Config.instance,
                              poll_interval: 0.05, heartbeat_seconds: 0.25)
    WebServerBoot.with_server(project_dir: project_dir, events: events, &block)
  end

  def stream_open(handle, last_event_id: nil)
    headers = {}
    headers['Last-Event-ID'] = last_event_id if last_event_id
    WebServerBoot.raw_stream_open(handle, "/api/events?token=#{handle.token}", headers)
  end

  def read_until(sock, pattern, timeout: 5)
    WebServerBoot.raw_read_until(sock, pattern, timeout: timeout)
  end

  # Frame data payload for the first `event: <name>` frame in raw bytes
  # (one frame = one WEBrick chunk, so frame bytes are contiguous).
  def frame_data(bytes, event_name)
    match = bytes.match(/event: #{event_name}\ndata: (\{[^\n]*\})\n/)
    match && JSON.parse(match[1])
  end

  # All entry data payloads in order of appearance.
  def entry_payloads(bytes)
    bytes.scan(/event: entry\ndata: (\{[^\n]*\})\n/).map { |(raw)| JSON.parse(raw) }
  end

  it 'answers 200 text/event-stream with security headers and a hello carrying retry, header, and status' do
    with_events_server do |handle|
      sock = stream_open(handle)
      begin
        # One bounded read to the hello frame (raw_read_until over-reads
        # past its pattern, so a follow-up per-region read would lose the
        # over-read bytes); split the stream at the header terminator.
        bytes = read_until(sock, 'event: hello')
        head, _terminator, body = bytes.partition("\r\n\r\n")
        status_line, *header_lines = head.split("\r\n")
        expect(status_line).to start_with('HTTP/1.1 200') # ALWAYS 200 once authed (Pitfall 1)
        headers = header_lines.map { |l| l.split(':', 2) }.to_h { |k, v| [k.strip, v.strip] }
        expect(headers['Content-Type']).to eq('text/event-stream')
        expect(headers['Cache-Control']).to eq('no-store')
        expect(headers['X-Frame-Options']).to eq('DENY')

        # The first chunk is the hello frame, led by the in-stream retry
        # field (the ONLY reconnect-time control, WHATWG parse rules).
        expect(body).to match(/\A[0-9a-f]+\r\nretry: 3000\nevent: hello\ndata: \{/)

        hello = frame_data(body, 'hello')
        expect(hello['run']).to eq(RUN_NAME)
        expect(hello['status']).to eq('running') # live pid (this process), no run_end
        expect(hello['header']['command']).to eq('build')
        expect(hello['header']['argv']).to eq(%w[build Alamofire])
        expect(hello['header']['trigger']).to eq(TRIGGER) # D-11 verbatim
        expect(hello['header']['started_at']).to eq('2026-09-01T09:30:00Z')
        expect(hello['header']['redacted']).to be(false)
      ensure
        WebServerBoot.raw_close(sock)
      end
    end
  end

  it 'replays the run from byte 0: existing body lines arrive as id-carrying entry frames in order' do
    with_events_server do |handle|
      sock = stream_open(handle)
      begin
        bytes = read_until(sock, LINE2_TEXT)
        id1 = "#{RUN_NAME}:#{HEADER.bytesize + LINE1.bytesize}"
        id2 = "#{RUN_NAME}:#{HEADER.bytesize + LINE1.bytesize + LINE2.bytesize}"
        expect(bytes.index("id: #{id1}\n")).to be < bytes.index("id: #{id2}\n")
        expect(bytes).to include("id: #{id1}\nevent: entry\ndata: #{LINE1.chomp}\n")
        expect(bytes).to include("id: #{id2}\nevent: entry\ndata: #{LINE2.chomp}\n")
        payloads = entry_payloads(bytes)
        expect(payloads.length).to eq(2) # nothing between hello and the replay
        expect(payloads.map { |p| p['text'] }).to eq(["replay one\n", "replay two\n"])
      ensure
        WebServerBoot.raw_close(sock)
      end
    end
  end

  it 'delivers a line appended after connect within the poll bound (LIVE tracer row)' do
    with_events_server do |handle|
      sock = stream_open(handle)
      begin
        read_until(sock, LINE2_TEXT) # replay drained
        live = body_line("LIVE-APPEND-#{SecureRandom.hex(4)}\n")
        append_run(RUN_NAME, live)
        bytes = read_until(sock, 'LIVE-APPEND', timeout: 2) # poll 0.05s; 2s bound
        expect(bytes).to include('event: entry')
        expect(bytes).to include("id: #{RUN_NAME}:")
      ensure
        WebServerBoot.raw_close(sock)
      end
    end
  end

  it 'gates like every route: 401 envelope without token, 403 foreign Origin, 404 non-GET' do
    with_events_server do |handle|
      unauthorized = WebServerBoot.http_get(handle, '/api/events')
      expect(unauthorized.code).to eq('401')
      expect(JSON.parse(unauthorized.body)['status']).to eq('error') # standard envelope

      forbidden = WebServerBoot.http_get(handle, "/api/events?token=#{handle.token}", 'Origin' => 'http://evil.com')
      expect(forbidden.code).to eq('403')
      expect(JSON.parse(forbidden.body)['status']).to eq('error')

      not_found = WebServerBoot.http_post(handle, "/api/events?token=#{handle.token}")
      expect(not_found.code).to eq('404')
      expect(JSON.parse(not_found.body)['status']).to eq('error')
    end
  end

  it 'resumes exactly on Last-Event-ID (incl. collision-suffixed names); hostile ids fall back to fresh replay and are never opened' do
    with_events_server do |handle|
      # -- round-trip: capture the live line's id, append a successor line,
      #    reconnect -> the first entry after hello is EXACTLY the next line.
      sock = stream_open(handle)
      live1 = body_line("RESUME-ANCHOR-#{SecureRandom.hex(4)}\n")
      append_run(RUN_NAME, live1)
      bytes0 = read_until(sock, 'RESUME-ANCHOR')
      live_id = bytes0.scan(/id: ([^\n]*)\n/).last
      expect(live_id).to start_with("#{RUN_NAME}:")
      next_line = body_line("AFTER-ANCHOR-#{SecureRandom.hex(4)}\n")
      append_run(RUN_NAME, next_line)
      WebServerBoot.raw_close(sock)

      sock = stream_open(handle, last_event_id: live_id)
      bytes = read_until(sock, 'AFTER-ANCHOR')
      payloads = entry_payloads(bytes)
      expect(payloads.length).to eq(1) # no re-delivery of the anchor line
      expect(payloads.first['text']).to eq(JSON.parse(next_line)['text'])
      WebServerBoot.raw_close(sock)

      # -- same-millisecond collision-suffixed run name (run_log.rb:120-123):
      #    the regex's optional (-\d+)? group is load-bearing -- without it
      #    this id silently falls back to fresh replay of the NEWEST run.
      c_header = header_line(name: COLLISION_NAME, command: 'use', trigger: 'terminal', pid: 999_999_999)
      c_line1 = body_line("collision one\n")
      c_line2 = body_line("collision two\n")
      File.write(run_path(COLLISION_NAME), [c_header, c_line1, c_line2].join)
      collision_id = "#{COLLISION_NAME}:#{c_header.bytesize + c_line1.bytesize}"
      sock = stream_open(handle, last_event_id: collision_id)
      bytes = read_until(sock, 'collision two')
      expect(entry_payloads(bytes).map { |p| p['text'] }).to eq(["collision two\n"])
      WebServerBoot.raw_close(sock)

      # -- hostile ids (Pitfall 4 / T-13-04): regex or containment failure
      #    -> fresh replay from byte 0; the named files are NEVER opened.
      canary = "CANARY-#{SecureRandom.hex(8)}"
      File.write(File.join(project_dir, 'spm-cache.yml'), canary) # target of ../../spm-cache.yml:0
      outside = "OUTSIDE-#{SecureRandom.hex(8)}"
      outside_name = '20260101T000000001Z-1-build.jsonl' # outside runs_dir, one level up
      File.write(File.join(project_dir, '.spm-cache', outside_name), outside)
      hostile_ids = [
        '../../spm-cache.yml:0',
        '/etc/passwd:0',
        'not-a-run-file:5',
        '20260101T000000000Z-424242-build.jsonl:0', # well-formed, nonexistent
        "../#{outside_name}:0" # well-formed name, exists OUTSIDE runs_dir
      ]
      hostile_ids.each do |bad|
        sock = stream_open(handle, last_event_id: bad)
        bytes = read_until(sock, LINE1_TEXT) # fresh replay reaches line 1 again
        expect(frame_data(bytes, 'hello')['run']).to eq(RUN_NAME)
        expect(bytes).not_to include(canary)    # traversal target never opened
        expect(bytes).not_to include(outside)   # outside-run file never opened
        WebServerBoot.raw_close(sock)
      end
    end
  end

  it 'carries Connection: close (keep_alive=false: one-shot stream, verified mechanic)' do
    with_events_server do |handle|
      sock = stream_open(handle)
      begin
        head = read_until(sock, "\r\n\r\n")
        expect(head).to match(/^Connection: close\r$/i)
      ensure
        WebServerBoot.raw_close(sock)
      end
    end
  end

  it 'delivers each line exactly once across the replay->queue handoff (double-delivery window opened live)' do
    FileUtils.mkdir_p(runs_dir)
    big_header = header_line(command: 'build', trigger: 'terminal')
    big_lines = 2000.times.map { |i| body_line("filler #{i}\n") }
    File.write(run_path(BIG_RUN_NAME), big_header + big_lines.join)
    base_offset = big_header.bytesize + big_lines.sum(&:bytesize)

    events = events_class.new(config: SPMCache::Core::Config.instance,
                              poll_interval: 0.05, heartbeat_seconds: 0.25)
    WebServerBoot.with_server(project_dir: project_dir, events: events) do |handle|
      sock = stream_open(handle)
      marker = body_line("MARKER-#{SecureRandom.hex(6)}\n")
      append_run(BIG_RUN_NAME, marker) # immediately after the GET: lands in (T0, T1]
      # Quiescence: the first heartbeat comment proves the queue drained
      # (a pop timed out) with no further appends pending.
      bytes = read_until(sock, ': ping', timeout: 10)

      marker_id = "#{BIG_RUN_NAME}:#{base_offset + marker.bytesize}"
      # EXACTLY ONCE: never once from the disk replay and again from the
      # tailer queue (id-based suppression through the handoff window).
      expect(bytes.scan(marker_id).length).to eq(1)
      expect(bytes.scan('MARKER-').length).to eq(1)
      WebServerBoot.raw_close(sock)
    end
  end
end
