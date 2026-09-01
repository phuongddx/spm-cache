# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'tmpdir'
require 'fileutils'
require 'securerandom'
require 'uri'
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
  # Pinned-replay fixtures (14-03): OLDER sorts before RUN_NAME (the
  # ?run= pin target), EVEN_NEWER sorts after everything written before
  # it (the discovery/switch trigger), PRUNED is well-formed but never
  # existed (the graceful-degrade row).
  OLDER_RUN = '20260901T092000456Z-5302-use.jsonl'
  EVEN_NEWER_RUN = '20260901T094500999Z-6100-build.jsonl'
  PRUNED_RUN = '20260101T000000000Z-424242-build.jsonl'
  DEAD_PID = 999_999_999 # ESRCH by construction (events_tailer_spec idiom)

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

  def self.run_end_line(status = 0)
    JSON.generate('event' => 'run_end', 'ts' => '2026-09-01T09:30:02Z',
                  'status' => status, 'ended_at' => '2026-09-01T09:30:02Z') + "\n"
  end

  def run_end_line(status = 0)
    self.class.run_end_line(status)
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

  def stream_open(handle, last_event_id: nil, run: nil)
    headers = {}
    headers['Last-Event-ID'] = last_event_id if last_event_id
    # ?run= rides the same URL as the token; the value is ATTACKER
    # INPUT and is percent-encoded here only so the fixture values
    # (slashes, spaces) survive the request line verbatim.
    path = "/api/events?token=#{handle.token}"
    path += "&run=#{URI.encode_www_form_component(run)}" unless run.nil?
    WebServerBoot.raw_stream_open(handle, path, headers)
  end

  def read_until(sock, pattern, timeout: 5)
    WebServerBoot.raw_read_until(sock, pattern, timeout: timeout)
  end

  # Greedy bounded drain (spec-side quiescence for the exactly-once row
  # until heartbeat comments land): read everything arriving within
  # `seconds` of socket silence into one buffer.
  def drain_for(sock, seconds)
    bytes = +''
    deadline = Time.now + seconds
    while Time.now < deadline
      readable = IO.select([sock], nil, nil, 0.05)
      next unless readable

      loop do
        bytes << sock.read_nonblock(65_536)
      rescue IO::WaitReadable
        break
      rescue EOFError
        return bytes
      end
    end
    bytes
  end

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
        expect(payloads.length).to eq(3) # full-file replay: header + both body lines
        expect(payloads.map { |p| p['text'] }).to eq(
          [nil, "replay one\n", "replay two\n"] # header carries no text field
        )
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

      not_found = WebServerBoot.http_post(handle, '/api/events', 'X-SPM-Token' => handle.token)
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
      live_id = bytes0.scan(/id: ([^\n]*)\n/).flatten.last
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
      c_header = header_line(command: 'use', trigger: 'terminal', pid: 999_999_999)
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
      bytes = read_until(sock, 'MARKER-', timeout: 10)
      # Quiescence: everything arriving within a further 1s of silence is
      # captured -- a duplicate delivery through the handoff window would
      # land in that window (the queue drains within milliseconds).
      bytes << drain_for(sock, 1.0)
      marker_id = "#{BIG_RUN_NAME}:#{base_offset + marker.bytesize}"
      # tailer queue (id-based suppression through the handoff window).
      expect(bytes.scan(marker_id).length).to eq(1)
      expect(bytes.scan('MARKER-').length).to eq(1)
      WebServerBoot.raw_close(sock)
    end
  end

  # -- 14-03: hello consumes the shared derivation; ?run= pins older-run
  #    replay (D-12 reachability in place, no reload). Pinned semantics:
  #    ENTRY delivery is scoped to the named run; switch/notice
  #    broadcasts still arrive (the client drops the pin and reconnects
  #    unpinned -- 14-05's D-04 job); the server NEVER re-points a
  #    pinned stream.
  it 'hello carries the full shared derivation: header + status + lock + now, agreeing with /api/runs' do
    with_events_server do |handle|
      sock = stream_open(handle)
      begin
        bytes = read_until(sock, LINE2_TEXT)
        hello = frame_data(bytes, 'hello')
        expect(hello['run']).to eq(RUN_NAME)
        expect(hello['status']).to eq('running')
        # D-06/D-11: the parsed run_start header VERBATIM (all Phase 12
        # identity keys), trigger through with no allowlist.
        expect(hello['header']).to eq(JSON.parse(HEADER.chomp))
        # The lock field + the server now (14-03): the lock is
        # server-internal -- the client renders nothing for it
        # (14-UI-SPEC external-run row) -- but it is the SAME derivation
        # /api/runs serves.
        expect(hello['lock']).to eq('state' => 'free', 'holder' => nil, 'holder_status' => nil)

        # Zero drift (key_link): the listing, fetched alongside the open
        # stream, derives the same run + status + lock shape through the
        # SAME read model -- one derivation, two surfaces.
        listing = JSON.parse(WebServerBoot.http_get(handle, '/api/runs', 'X-SPM-Token' => handle.token).body)
        expect(listing['status']).to eq('ok')
        entry = listing['data']['runs'].first
        expect(entry['run']).to eq(hello['run'])
        expect(entry['status']).to eq(hello['status'])
        expect(listing['data']['lock']).to eq(hello['lock'])
      ensure
        WebServerBoot.raw_close(sock)
      end
    end
  end

  it '?run= pins an older completed run: byte-0 replay of the NAMED run, follow of its growth, no entry switch, switch broadcast still delivered' do
    with_events_server do |handle|
      File.write(run_path(OLDER_RUN),
                 [header_line(command: 'use', trigger: 'terminal', pid: DEAD_PID),
                  body_line("older one\n"), body_line("older two\n"), run_end_line(0)].join)

      sock = stream_open(handle, run: OLDER_RUN)
      begin
        bytes = read_until(sock, '"run_end"') # the replay's LAST line
        hello = frame_data(bytes, 'hello')
        expect(hello['run']).to eq(OLDER_RUN) # pinned identity, not current-or-newest
        expect(hello['status']).to eq('success') # the Task-1 vocabulary through the pin path
        # Replay is the NAMED run from byte 0 (header + 2 body + run_end)
        # and every entry id carries the NAMED run's filename.
        expect(entry_payloads(bytes).length).to eq(4)
        ids = bytes.scan(/^id: ([^\n]*)\n/).flatten
        expect(ids).not_to be_empty
        expect(ids).to all(start_with("#{OLDER_RUN}:"))

        # Follow of the pinned file: an append reaches the pinned stream.
        pinned_line = body_line("PINNED-APPEND-#{SecureRandom.hex(4)}\n")
        append_run(OLDER_RUN, pinned_line)
        bytes2 = read_until(sock, 'PINNED-APPEND', timeout: 2)
        expect(bytes2).to include("id: #{OLDER_RUN}:")

        # An even-newer run appears: the switch broadcast ARRIVES on this
        # pinned connection (broadcasts are not filtered)...
        File.write(run_path(EVEN_NEWER_RUN),
                   [header_line(command: 'build', trigger: 'terminal', pid: DEAD_PID),
                    body_line("newest body\n")].join)
        bytes3 = read_until(sock, 'event: switch', timeout: 2)
        switch = frame_data(bytes3, 'switch')
        expect(switch['run']).to eq(EVEN_NEWER_RUN)
        expect(switch['previous']).to eq(RUN_NAME) # the tailer was following the live newest

        # ...but the ENTRY stream never re-points: another append to the
        # pinned run still arrives under the NAMED filename, and the
        # newer run's entries NEVER appear as pinned entries.
        still_pinned = body_line("STILL-PINNED-#{SecureRandom.hex(4)}\n")
        append_run(OLDER_RUN, still_pinned)
        bytes4 = read_until(sock, 'STILL-PINNED', timeout: 2)
        expect(bytes4).to include("id: #{OLDER_RUN}:")
        expect((bytes3 + bytes4).scan("id: #{EVEN_NEWER_RUN}:")).to be_empty
      ensure
        WebServerBoot.raw_close(sock)
      end
    end
  end

  it '?run= on a live run pins with follow engaged (the dropdown live-selection contract)' do
    with_events_server do |handle|
      sock = stream_open(handle, run: RUN_NAME)
      begin
        bytes = read_until(sock, LINE2_TEXT)
        expect(frame_data(bytes, 'hello')).to include('run' => RUN_NAME, 'status' => 'running')

        live = body_line("LIVE-PINNED-#{SecureRandom.hex(4)}\n")
        append_run(RUN_NAME, live)
        expect(read_until(sock, 'LIVE-PINNED', timeout: 2)).to include("id: #{RUN_NAME}:")

        # The pin holds even as a NEWER run appears: entries stay on the
        # pinned run while the switch broadcast still arrives.
        File.write(run_path(EVEN_NEWER_RUN),
                   [header_line(command: 'build', trigger: 'terminal', pid: DEAD_PID),
                    body_line("newest body\n")].join)
        switch_bytes = read_until(sock, 'event: switch', timeout: 2)
        expect(frame_data(switch_bytes, 'switch')['run']).to eq(EVEN_NEWER_RUN)

        follow_line = body_line("PIN-HOLDS-#{SecureRandom.hex(4)}\n")
        append_run(RUN_NAME, follow_line)
        follow_bytes = read_until(sock, 'PIN-HOLDS', timeout: 2)
        expect(follow_bytes).to include("id: #{RUN_NAME}:")
        expect((switch_bytes + follow_bytes).scan("id: #{EVEN_NEWER_RUN}:")).to be_empty
      ensure
        WebServerBoot.raw_close(sock)
      end
    end
  end

  it '?run= hostile values fall back to current-or-newest exactly like omitting the param; the traversal canary is never opened' do
    with_events_server do |handle|
      canary = "CANARY-#{SecureRandom.hex(8)}"
      File.write(File.join(project_dir, 'spm-cache.yml'), canary) # target of ../../spm-cache.yml

      # Every hostile shape resolves to nil and the stream is
      # behavior-identical to no param: same hello run, same byte-0
      # replay -- and never an error surface worth probing (T-13-04).
      ['../../spm-cache.yml', '/etc/hosts', 'not a run file', ''].each do |hostile|
        sock = stream_open(handle, run: hostile)
        begin
          bytes = read_until(sock, LINE2_TEXT) # the replay's final line
          expect(frame_data(bytes, 'hello')['run']).to eq(RUN_NAME)
          expect(entry_payloads(bytes).length).to eq(3) # full fresh replay, header included
          expect(bytes).not_to include(canary) # the named target was never opened
        ensure
          WebServerBoot.raw_close(sock)
        end
      end
    end
  end

  it '?run= valid shape but pruned/nonexistent → the pinned notice + fresh replay of the newest run' do
    with_events_server do |handle|
      sock = stream_open(handle, run: PRUNED_RUN)
      begin
        bytes = read_until(sock, LINE2_TEXT)
        hello = frame_data(bytes, 'hello')
        expect(hello['run']).to eq(RUN_NAME) # graceful degrade to current-or-newest
        expect(hello['status']).to eq('running')
        notice = frame_data(bytes, 'notice')
        expect(notice['message']).to eq('run log pruned while viewing; switching to newest')
        expect(bytes.index('run log pruned')).to be > bytes.index('event: hello') # notice AFTER hello
        expect(entry_payloads(bytes).length).to eq(3) # then the fresh replay, header included
      ensure
        WebServerBoot.raw_close(sock)
      end
    end
  end
end
