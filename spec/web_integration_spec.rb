# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'time'
require 'tmpdir'
require 'fileutils'
require 'securerandom'
require 'tempfile'
require 'yaml'

require_relative 'support/web_server_boot'

# Phase 13's cross-plan weld (WEB-04, Plans 13-01..13-04): ONE real
# server boot (before(:all), port 0, research CP7's single sanctioned
# cross-route integration spec) proves the exhaustive route x auth
# matrix -- every route (/, the served stylesheet, all three /api/*
# endpoints) against every attack shape from the research (CP13:
# localhost is not trusted): foreign Origin (drive-by), spoofed Host
# (DNS rebinding), Origin "null" (sandboxed iframe), absent-Origin
# tokenless form POST, and the passing-gate 404s. The browser
# page-load sequence then walks bootstrap -> index -> the three
# assets AS PARSED FROM THE SERVED HTML -> the three API payloads,
# so the real 13-03 assets and the real 13-02 read models are what
# answers. Expectations are the 13-01/13-02 contracts verbatim: a
# failing row means a bug in the owning module, never here.
RSpec.describe 'SPMCache::Web one-boot integration matrix', order: :defined do
  GRAPH_FIXTURE = [
    { 'module' => 'Alamofire', 'status' => 'hit', 'hasMacro' => false },
    { 'module' => 'SnapKit', 'status' => 'missed', 'hasMacro' => true }
  ].freeze

  # Phase 14 weld fixture: a runs-dir run whose header pid is THIS
  # spec process (genuinely alive → 'running'), two body lines, no
  # run_end — the SSE rows below replay and follow it.
  WELD_RUN = "20260901T093000123Z-#{Process.pid}-build.jsonl"
  WELD_HEADER = JSON.generate(
    'event' => 'run_start', 'ts' => '2026-09-01T09:30:00Z', 'command' => 'build',
    'argv' => %w[build Alamofire], 'redacted' => false, 'pid' => Process.pid,
    'started_at' => '2026-09-01T09:30:00Z', 'spm_cache_version' => '0.5.0',
    'trigger' => 'terminal', 'cycle' => false
  ) + "\n"
  WELD_LINE1 = JSON.generate('ts' => '2026-09-01T09:30:01Z', 'stream' => 'out',
                             'text' => "weld replay one\n") + "\n"
  WELD_LINE2 = JSON.generate('ts' => '2026-09-01T09:30:02Z', 'stream' => 'out',
                             'text' => "weld replay two\n") + "\n"

  # 15-01: the injectable fake-bin fixture (Web::Jobs' bin_path: seam)
  # -- pure stdlib, never the gem (spec/fixtures/fake_spm_cache_bin.rb).
  FAKE_BIN = File.expand_path('fixtures/fake_spm_cache_bin.rb', __dir__)

  before(:all) do
    @boot_started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    @previous_project_dir = SPMCache::Core::Config.instance.project_dir
    @project_dir = Dir.mktmpdir('spm-cache-integration')
    graph_path = File.join(@project_dir, 'spm-cache', 'packages', 'proxy', 'graph.json')
    FileUtils.mkdir_p(File.dirname(graph_path))
    File.write(graph_path, JSON.generate(GRAPH_FIXTURE))

    @token = SecureRandom.hex(32)
    # The REAL wiring: default read models (State/Graph callables +
    # the Doctor instance) and the default assets root, so the
    # served dashboard is the one the gem ships (13-03).
    SPMCache::Core::Config.configure(project_dir: @project_dir)

    # 16-01 tracer: this boot's /api/state rows must be deterministic
    # AND hermetic -- Cache::Inventory otherwise scans the developer's
    # real ~/.spm-cache (CACHE_DIR is machine-global and independent
    # of project_dir), so whether an Alamofire row exists would depend
    # on this machine's cache. Redirected through the state read
    # model's OWN documented seam (cache_root:, state.rb "hermetic
    # specs" comment) via the router's read_models: injection point:
    # the production State.call derivation still answers every row --
    # only the Inventory scan root moves, into a fixture inside the
    # tmp project. Still exactly ONE boot (CP7).
    cache_root = File.join(@project_dir, 'fixture-cache')
    %w[Alamofire SnapKit].each do |name|
      FileUtils.mkdir_p(File.join(cache_root, 'debug', "#{name}.xcframework"))
    end
    state_model = lambda do |config:|
      SPMCache::Web::ReadModels::State.call(config: config, cache_root: cache_root)
    end

    # Phase 14 weld: the runs fixture + a REAL Events instance at
    # spec speed (the boot constructs the Router, so the short
    # poll/heartbeat is injected here) — every SSE row rides the
    # production code path (research § Code Examples boot-harness
    # anchor). Still exactly ONE boot (CP7).
    runs_dir = SPMCache::Core::Config.instance.runs_dir
    FileUtils.mkdir_p(runs_dir)
    File.write(File.join(runs_dir, WELD_RUN), [WELD_HEADER, WELD_LINE1, WELD_LINE2].join)
    weld_events = SPMCache::Web::Events.new(config: SPMCache::Core::Config.instance,
                                            poll_interval: 0.05, heartbeat_seconds: 0.25)

    # 15-01: the fake-bin-backed Jobs collaborator, injected through
    # the SAME seam as events (router.rb jobs: kwarg) -- still exactly
    # ONE boot (CP7). ENV['FAKE_BIN_PROBE'] rides the REAL process ENV
    # since Jobs merges ENV.to_h into the spawned child's env.
    @previous_fake_bin_probe = ENV.fetch('FAKE_BIN_PROBE', nil)
    probe_tmp = Tempfile.new(['fake-bin-probe', '.jsonl'])
    probe_tmp.close
    @probe_file = probe_tmp.path
    ENV['FAKE_BIN_PROBE'] = @probe_file
    @jobs = SPMCache::Web::Jobs.new(config: SPMCache::Core::Config.instance, bin_path: FAKE_BIN)

    router = SPMCache::Web::Router.new(token: @token, port: 0,
                                       assets: SPMCache::Web::Assets.new,
                                       read_models: { state: state_model },
                                       events: weld_events, jobs: @jobs)
    @server = SPMCache::Web::Server.new(port: 0, token: @token, router: router)
    @thread = Thread.new { @server.start }
    WebServerBoot.wait_accepting(@server.port)

    # Prime the events tailer (LOGS-03): it starts lazily on the
    # FIRST /api/events register and its own first discover() tick
    # publishes a Switch(previous: nil) for whatever is newest at
    # that moment. Without this warm-up, the FIRST real test to
    # connect would race that startup switch against its own spawn.
    warm_handle = WebServerBoot::Handle.new(port: @server.port, token: @token, server: @server)
    warm_sock = WebServerBoot.raw_stream_open(warm_handle, "/api/events?token=#{@token}")
    WebServerBoot.raw_read_until(warm_sock, 'event: hello', timeout: 5)
    WebServerBoot.raw_close(warm_sock)
  end

  after(:all) do
    WebServerBoot.shutdown(@server)
    @thread&.join(10)
    SPMCache::Core::Config.configure(project_dir: @previous_project_dir)
    FileUtils.remove_entry(@project_dir)
    if @previous_fake_bin_probe
      ENV['FAKE_BIN_PROBE'] = @previous_fake_bin_probe
    else
      ENV.delete('FAKE_BIN_PROBE')
    end
    File.delete(@probe_file) if @probe_file && File.exist?(@probe_file)
  end

  def handle
    WebServerBoot::Handle.new(port: @server.port, token: @token, server: @server)
  end

  def get(path, headers = {})
    WebServerBoot.http_get(handle, path, headers)
  end

  def post(path, headers = {}, body = nil)
    WebServerBoot.http_post(handle, path, headers, body)
  end

  # 15-01: the fake bin's recorded side effects, newest-last.
  def probe_entries
    return [] unless File.exist?(@probe_file)

    File.readlines(@probe_file).map { |line| JSON.parse(line) }
  end

  # Bounded reap: never an unbounded wait, never leaked past an
  # example (the same posture the shutdown-sentinel row below uses).
  def wait_for_pid_exit(pid, timeout: 5)
    return unless pid

    deadline = Time.now + timeout
    loop do
      Process.kill(0, pid)
      break if Time.now > deadline

      sleep 0.05
    rescue Errno::ESRCH
      break
    end
  end

  # Bounded poll for the probe entry at `index` to appear -- spawn_run
  # returns to the HTTP caller the instant Process.detach is called,
  # well before the child has actually booted far enough to write its
  # probe line, so reading probe_entries immediately after a POST is
  # inherently racy. Every row that needs "the entry this POST just
  # produced" goes through this instead of a bare probe_entries.last.
  def wait_for_probe_entry(index, timeout: 2)
    deadline = Time.now + timeout
    loop do
      entry = probe_entries[index]
      return entry if entry
      return nil if Time.now > deadline

      sleep 0.02
    end
  end

  describe 'route x auth matrix (25 cells, WEB-04)' do
    # kind scopes the token contract: only /api/* requires the launch
    # token (401); / bootstraps (302) and /assets/* serve without one
    # (13-01's locked matrix: assets cannot send headers and carry
    # zero project data). The no_token / wrong_token cells on the
    # non-API routes PIN that scope -- the gate is /api/*-only.
    ROUTES = [
      { path: '/', kind: :page },
      { path: '/assets/styles.css', kind: :asset },
      { path: '/api/state', kind: :api },
      { path: '/api/doctor', kind: :api },
      { path: '/api/graph', kind: :api }
    ].freeze

    EXPECTED = {
      page: { happy: '200', foreign_origin: '403', spoofed_host: '403', no_token: '302', wrong_token: '200' },
      asset: { happy: '200', foreign_origin: '403', spoofed_host: '403', no_token: '200', wrong_token: '200' },
      api: { happy: '200', foreign_origin: '403', spoofed_host: '403', no_token: '401', wrong_token: '401' }
    }.freeze

    def matrix_response(route, case_name)
      path = route[:path]
      headers = {}
      case case_name
      when :happy
        # The route's documented token delivery: ?token= for /,
        # X-SPM-Token for /api/*, nothing for /assets/*.
        path = "/?token=#{@token}" if route[:kind] == :page
        headers['X-SPM-Token'] = @token if route[:kind] == :api
      when :foreign_origin
        # Valid token included on /api/* rows: the Origin gate fires
        # even with a legitimate token (gate order Host -> Origin ->
        # token).
        headers['Origin'] = 'http://evil.com'
        headers['X-SPM-Token'] = @token if route[:kind] == :api
      when :spoofed_host
        headers['Host'] = "evil.com:#{@server.port}"
        headers['X-SPM-Token'] = @token if route[:kind] == :api
      when :no_token
        # Bare request: no token anywhere.
        nil
      when :wrong_token
        path = '/?token=definitely-not-the-launch-token' if route[:kind] == :page
        headers['X-SPM-Token'] = 'e' * 64 if route[:kind] == :api
      end
      get(path, headers)
    end

    ROUTES.product(%i[happy foreign_origin spoofed_host no_token wrong_token]).each do |route, case_name|
      it "GET #{route[:path]} (#{route[:kind]}) #{case_name} -> #{EXPECTED[route[:kind]][case_name]}" do
        res = matrix_response(route, case_name)
        expect(res.code).to eq(EXPECTED[route[:kind]][case_name])
      end
    end
  end

  describe 'drive-by simulation (CP13: every shape a browser page can produce)' do
    API_PATHS = ['/api/state', '/api/doctor', '/api/graph'].freeze

    API_PATHS.each do |path|
      it "POST #{path} with a foreign Origin is 403 even with a valid token" do
        res = post(path, 'Origin' => 'http://evil.com', 'X-SPM-Token' => @token)
        expect(res.code).to eq('403')
      end

      it "POST #{path} same-Host, no-Origin, tokenless (form shape) is 401" do
        expect(post(path).code).to eq('401')
      end

      it "GET #{path} with Origin \"null\" (sandboxed iframe) is 403" do
        res = get(path, 'Origin' => 'null', 'X-SPM-Token' => @token)
        expect(res.code).to eq('403')
      end
    end

    it '404s a passing-gate unknown method (no non-GET handler exists)' do
      put = Net::HTTP::Put.new('/api/state')
      res = WebServerBoot.request(handle, put, 'X-SPM-Token' => @token)
      expect(res.code).to eq('404')
      expect(JSON.parse(res.body)['status']).to eq('error')
    end

    it '404s passing-gate unknown paths' do
      expect(get('/nope').code).to eq('404')
      expect(get('/api/unknown', 'X-SPM-Token' => @token).code).to eq('404')
    end
  end
  describe 'full browser page-load sequence (one boot end-to-end)' do
    it 'bootstraps the token: GET / 302s to the exact launch-token Location, which serves the index' do
      bootstrap = get('/')
      expect(bootstrap.code).to eq('302')
      # WEBrick absolutizes the relative Location (13-01 deviation):
      # same-origin absolute URL carrying the EXACT launch token.
      expect(bootstrap['Location']).to eq("http://127.0.0.1:#{@server.port}/?token=#{@token}")

      page = get("/?token=#{@token}")
      expect(page.code).to eq('200')
      expect(page['Content-Type']).to eq('text/html')
      expect(page.body).to include('Cache State')
      expect(page.body).to include('Doctor')
      expect(page.body).to include('Dependency Graph')
    end

    it 'serves every asset referenced by the served HTML with the right content types' do
      html = get("/?token=#{@token}").body
      refs = html.scan(/(?:href|src)="([^"]+)"/).flatten
      expect(refs).to include('assets/styles.css', 'assets/cytoscape.min.js', 'assets/app.js')

      content_types = {
        'assets/styles.css' => 'text/css',
        'assets/cytoscape.min.js' => 'application/javascript',
        'assets/app.js' => 'application/javascript',
        'assets/log.js' => 'application/javascript'
      }
      refs.each do |ref|
        # Browser resolution: each scanned ref resolved via URI.join
        # against the document's own origin root (the page sits at
        # http://127.0.0.1:<port>/, base path '/'). No test-side
        # /assets/ rewriting -- a ref the router cannot serve as
        # resolved must 404 here (G-13-1 regression net).
        resolved = URI.join("http://127.0.0.1:#{@server.port}/", ref)
        res = get(resolved.request_uri)
        expect(res.code).to eq('200')
        expect(res['Content-Type']).to eq(content_types.fetch(ref))
      end
    end

    it 'answers the three API payloads with the 13-02 envelope and payload keys' do
      state = JSON.parse(get('/api/state', 'X-SPM-Token' => @token).body)
      expect(state.keys).to contain_exactly('status', 'data', 'generated_at')
      expect(state['status']).to eq('ok')
      expect(state['data'].keys).to contain_exactly('packages', 'summary', 'poll_seconds')
      expect(state['data']['packages']).to be_an(Array)
      expect(state['data']['poll_seconds']).to be_an(Integer)

      doctor = JSON.parse(get('/api/doctor', 'X-SPM-Token' => @token).body)
      expect(doctor.keys).to contain_exactly('status', 'data', 'generated_at')
      expect(doctor['status']).to eq('ok')
      expect(doctor['data'].keys).to contain_exactly('has_run', 'checks', 'summary')
      expect(doctor['data']['has_run']).to eq(false)
      # The doctor stamp is the RUN's stamp, never re-stamped: nil
      # before the first run (DASH-02).
      expect(doctor['generated_at']).to be_nil

      graph = JSON.parse(get('/api/graph', 'X-SPM-Token' => @token).body)
      expect(graph.keys).to contain_exactly('status', 'data', 'generated_at')
      expect(graph['status']).to eq('ok')
      expect(graph['data'].keys).to contain_exactly('present', 'nodes', 'graph_generated_at')
      expect(graph['data']['present']).to eq(true)
      expect(graph['data']['nodes']).to include(
        'data' => { 'id' => 'Alamofire', 'module' => 'Alamofire',
                    'status' => 'hit', 'hasMacro' => false }
      )
    end
  end

  describe 'security header sweep over the sequence responses' do
    it 'carries X-Frame-Options: DENY on every HTML/API response and no-store on / and /api/*' do
      bootstrap = get('/')
      index = get("/?token=#{@token}")
      api_responses = [
        get('/api/state', 'X-SPM-Token' => @token),
        get('/api/doctor', 'X-SPM-Token' => @token),
        get('/api/graph', 'X-SPM-Token' => @token)
      ]

      [bootstrap, index, *api_responses].each do |res|
        expect(res['X-Frame-Options']).to eq('DENY')
        expect(res['Cache-Control']).to eq('no-store')
      end
    end
  end

  describe 'Host allowlist second entry' do
    it 'accepts a valid localhost:{port} Host (the second allowlist entry)' do
      res = get('/api/state', 'Host' => "localhost:#{@server.port}", 'X-SPM-Token' => @token)
      expect(res.code).to eq('200')
      expect(JSON.parse(res.body)['status']).to eq('ok')
    end
  end

  describe 'runtime bound (CP7 / T-13-20)' do
    it 'runs the entire matrix from the single boot in under 15 seconds' do
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - @boot_started
      expect(elapsed).to be < 15.0
    end
  end

  # The Phase 14 weld (LOGS-03 + WEB-03, plan 14-03): the phase's
  # transport claims proven from the ONE real boot above — replay,
  # liveness, exact resume, and the shutdown-with-open-stream sentinel
  # proof. Defined AFTER the runtime-bound example (order: :defined)
  # so the 15s bound still measures the pre-SSE matrix; every read
  # here is bounded (≤ 2s) and the shutdown row is the FILE's final
  # example, so closing the server harms nothing after it.
  describe 'live log stream (Phase 14 weld)' do
    before(:all) { @weld_started = Process.clock_gettime(Process::CLOCK_MONOTONIC) }

    def raw_stream(last_event_id: nil)
      headers = {}
      headers['Last-Event-ID'] = last_event_id if last_event_id
      WebServerBoot.raw_stream_open(handle, "/api/events?token=#{@token}", headers)
    end

    def read_until(sock, pattern, timeout: 2)
      WebServerBoot.raw_read_until(sock, pattern, timeout: timeout)
    end

    def append_weld(text)
      File.open(File.join(SPMCache::Core::Config.instance.runs_dir, WELD_RUN), 'a') { |f| f.write(text) }
    end

    def body_line(text)
      JSON.generate('ts' => '2026-09-01T09:30:05Z', 'stream' => 'out', 'text' => text) + "\n"
    end

    it 'answers 200 text/event-stream with no-store, X-Frame-Options DENY, and Connection close' do
      sock = raw_stream
      begin
        bytes = read_until(sock, 'event: hello')
        head, _terminator, = bytes.partition("\r\n\r\n")
        status_line, *header_lines = head.split("\r\n")
        expect(status_line).to start_with('HTTP/1.1 200') # ALWAYS 200 once authed
        headers = header_lines.map { |l| l.split(':', 2) }.to_h { |k, v| [k.strip, v.strip] }
        expect(headers['Content-Type']).to eq('text/event-stream')
        expect(headers['Cache-Control']).to eq('no-store')
        expect(headers['X-Frame-Options']).to eq('DENY')
        expect(headers['Connection'].downcase).to eq('close') # keep_alive=false, one-shot
      ensure
        WebServerBoot.raw_close(sock)
      end
    end

    it 'replays from byte 0: hello (running + lock + now) then both fixture lines with byte-offset ids' do
      sock = raw_stream
      begin
        bytes = read_until(sock, 'weld replay two')
        hello = bytes.match(/event: hello\ndata: (\{[^\n]*\})\n/)
        data = JSON.parse(hello[1])
        expect(data['run']).to eq(WELD_RUN)
        expect(data['status']).to eq('running') # header pid = this spec process, no run_end
        expect(data['header']['command']).to eq('build')
        expect(data['lock']['state']).to eq('free')
        expect(data['now']).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/)
        id1 = "#{WELD_RUN}:#{WELD_HEADER.bytesize + WELD_LINE1.bytesize}"
        id2 = "#{WELD_RUN}:#{WELD_HEADER.bytesize + WELD_LINE1.bytesize + WELD_LINE2.bytesize}"
        expect(bytes).to include("id: #{id1}\nevent: entry\ndata: #{WELD_LINE1.chomp}\n")
        expect(bytes).to include("id: #{id2}\nevent: entry\ndata: #{WELD_LINE2.chomp}\n")
      ensure
        WebServerBoot.raw_close(sock)
      end
    end

    it 'delivers a line appended after connect within the poll bound (LIVE)' do
      sock = raw_stream
      begin
        read_until(sock, 'weld replay two') # replay drained
        append_weld(body_line("weld live\n"))
        bytes = read_until(sock, 'weld live') # poll 0.05s; 2s bound
        expect(bytes).to include('event: entry')
        expect(bytes).to include("id: #{WELD_RUN}:")
      ensure
        WebServerBoot.raw_close(sock)
      end
    end

    it 'resumes exactly on Last-Event-ID across a reconnect: neither loss nor duplication' do
      sock = raw_stream
      begin
        append_weld(body_line("resume anchor\n"))
        bytes = read_until(sock, 'resume anchor')
        resume_id = bytes.scan(/id: ([^\n]*)\n/).flatten.last
        expect(resume_id).to start_with("#{WELD_RUN}:")
      ensure
        WebServerBoot.raw_close(sock)
      end

      append_weld(body_line("after anchor A\n"))
      append_weld(body_line("after anchor B\n"))
      sock = raw_stream(last_event_id: resume_id)
      begin
        bytes = read_until(sock, 'after anchor B')
        payloads = bytes.scan(/event: entry\ndata: (\{[^\n]*\})\n/).map { |(raw)| JSON.parse(raw) }
        expect(payloads.map { |p| p['text'] }).to eq(["after anchor A\n", "after anchor B\n"])
        expect(bytes.scan('id: ').length).to eq(2) # exactly two entry frames, no duplicates
      ensure
        WebServerBoot.raw_close(sock)
      end
    end

    it 'keeps the SSE phase bounded (each read ≤ 2s; the phase stays well inside the file budget)' do
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - @weld_started
      expect(elapsed).to be < 10.0 # CP7: whole file under ~25s, SSE share a fraction of it
    end

    # 15-01: the TRACER slice (BLD-01, D-02/D-04/D-05/D-09), nested
    # HERE deliberately: the shared tailer (LOGS-03) follows exactly
    # one file at a time and only ever moves FORWARD chronologically,
    # so spawning real builds earlier in the file would push it past
    # WELD_RUN before the weld rows above finish asserting live growth
    # on it. Running after those rows (and before the file's real
    # final shutdown, still below) costs nothing: this slice needs a
    # live server, not WELD_RUN's continued growth.
    describe 'POST /api/build (BLD-01 tracer)' do
      def build_body(scope = 'build')
        JSON.generate('scope' => scope)
      end

      it 'answers 200 with the standard envelope, the claimed scope, and a freshly derived lock snapshot' do
        before_count = probe_entries.length
        res = post('/api/build', { 'X-SPM-Token' => @token }, build_body)
        expect(res.code).to eq('200')
        envelope = JSON.parse(res.body)
        expect(envelope['status']).to eq('ok')
        expect(envelope['data']['scope']).to eq('build')
        expect(%w[free held]).to include(envelope['data']['lock']['state'])
      ensure
        wait_for_pid_exit(wait_for_probe_entry(before_count)&.fetch('pid', nil))
      end

      it 'spawns the probed shape: array argv, project cwd, ui trigger env, group-leader pgid, null stdio' do
        before_count = probe_entries.length
        res = post('/api/build', { 'X-SPM-Token' => @token }, build_body)
        expect(res.code).to eq('200')

        entry = wait_for_probe_entry(before_count)
        expect(entry).not_to be_nil
        expect(entry['argv']).to eq(['build'])
        expect(File.realpath(entry['pwd'])).to eq(File.realpath(@project_dir))
        expect(entry['trigger_env']).to eq('ui')
        expect(entry['pgid']).to eq(entry['pid']) # own process-group leader (P1)
        expect(entry['stdout_null']).to eq(true)
        expect(entry['stderr_null']).to eq(true)
      ensure
        wait_for_pid_exit(entry && entry['pid'])
      end

      it 'delivers the spawned run to a live /api/events subscriber, whose header records trigger ui' do
        sock = WebServerBoot.raw_stream_open(handle, "/api/events?token=#{@token}")
        pid = nil
        begin
          WebServerBoot.raw_read_until(sock, 'event: hello', timeout: 2)
          before_count = probe_entries.length
          res = post('/api/build', { 'X-SPM-Token' => @token }, build_body)
          expect(res.code).to eq('200')

          entry = wait_for_probe_entry(before_count)
          expect(entry).not_to be_nil
          pid = entry['pid']

          # The tailer is a single shared follower (LOGS-03): the FIRST
          # 'event: switch' this client observes may still be catching
          # up to an EARLIER sibling row's spawn, not this one -- wait
          # for OUR OWN pid-tagged run name to actually appear in the
          # stream (inside the matching switch's data), not just any
          # switch.
          bytes = WebServerBoot.raw_read_until(sock, "-#{pid}-build.jsonl", timeout: 5)
          run_name = bytes[/\d{8}T\d{6}\d{3}Z-#{pid}-build(?:-\d+)?\.jsonl/]
          run_path = File.join(SPMCache::Core::Config.instance.runs_dir, run_name)
          header = JSON.parse(File.readlines(run_path).first)
          expect(header['trigger']).to eq('ui')
        ensure
          WebServerBoot.raw_close(sock)
          wait_for_pid_exit(pid)
        end
      end

      it 'answers 409 with a machine-readable slot_busy reason while a build is in flight, and spawns nothing new' do
        before_count = probe_entries.length
        first_pid = nil
        ENV['FAKE_BIN_SLEEP'] = '1'
        first = post('/api/build', { 'X-SPM-Token' => @token }, build_body)
        expect(first.code).to eq('200')
        first_entry = wait_for_probe_entry(before_count)
        expect(first_entry).not_to be_nil
        first_pid = first_entry['pid']
        count_before = probe_entries.length

        second = post('/api/build', { 'X-SPM-Token' => @token }, build_body)
        expect(second.code).to eq('409')
        envelope = JSON.parse(second.body)
        expect(envelope['status']).to eq('error')
        expect(envelope['data']['reason']).to eq('slot_busy')
        expect(probe_entries.length).to eq(count_before)
      ensure
        ENV.delete('FAKE_BIN_SLEEP')
        wait_for_pid_exit(first_pid)
      end
    end

    # 16-01: the TRACER slice (D-03/D-04/D-06/D-08) -- the phase's
    # unproven WRITE path proven end to end on one package: an
    # authenticated POST /api/toggle goes through the shared Config
    # mutator (sidecar flock + in-lock re-read + atomic rename
    # replace) onto the booted project's spm-cache.yml, and the very
    # next GET /api/state serves the row saved-not-cached while its
    # applied graph status still says cached. Nested beside the
    # POST /api/build tracer for the same ordering reason: after the
    # WELD_RUN rows, before the file's shutdown acts.
    describe 'POST /api/toggle (16-01 tracer)' do
      def toggle_body(package, cached)
        JSON.generate('package' => package, 'cached' => cached)
      end

      # The booted project's ON-DISK ignore list, parsed from the
      # file the mutator writes -- never asserted against the source
      # text of config.rb.
      def disk_ignore
        path = File.join(@project_dir, 'spm-cache.yml')
        return [] unless File.exist?(path)

        parsed = YAML.safe_load(File.read(path))
        parsed.is_a?(Hash) ? parsed['ignore'] : nil
      end

      def state_row(name)
        payload = JSON.parse(get('/api/state', 'X-SPM-Token' => @token).body)
        expect(payload['status']).to eq('ok')
        payload['data']['packages'].find { |row| row['name'] == name }
      end

      it 'answers 200 with the standard envelope carrying the package and its new cached state' do
        res = post('/api/toggle', { 'X-SPM-Token' => @token }, toggle_body('Alamofire', false))
        expect(res.code).to eq('200')
        envelope = JSON.parse(res.body)
        expect(envelope.keys).to contain_exactly('status', 'data', 'generated_at')
        expect(envelope['status']).to eq('ok')
        expect(envelope['data']['package']).to eq('Alamofire')
        expect(envelope['data']['cached']).to eq(false)
      end

      it 'reached disk THROUGH the shared path: the booted project yml parses with exactly the entry and the full default key set (PROBED P2 shape)' do
        path = File.join(@project_dir, 'spm-cache.yml')
        expect(File.exist?(path)).to be true
        parsed = YAML.safe_load(File.read(path))
        expect(parsed['ignore']).to eq(['Alamofire'])
        expect(parsed.keys).to contain_exactly(*SPMCache::Core::Config::DEFAULT_CONFIG.keys)
      end

      it 'shows on /api/state immediately: saved-not-cached while applied still says cached, and the row is pending' do
        row = state_row('Alamofire')
        expect(row).not_to be_nil
        # (16-03) toggleable/reason land beside the existing nine
        # (neither fixture package carries a gating fact).
        expect(row.keys).to contain_exactly(
          'name', 'config', 'size_bytes', 'state', 'fidelity', 'has_macro',
          'toggleable', 'reason', 'saved_cached', 'applied_cached', 'pending'
        )
        expect(row['saved_cached']).to eq(false)  # the checkbox's own truth: the SAVED config no longer caches it
        expect(row['applied_cached']).to eq(true) # the LAST SYNC still did (graph fixture: hit)
        expect(row['state']).to eq('hit')         # the applied signal itself is untouched
        expect(row['pending']).to eq(true)

        # A package that is neither ignored nor graph-ignored is not
        # pending (graph fixture: SnapKit missed).
        snap = state_row('SnapKit')
        expect(snap['saved_cached']).to eq(true)
        expect(snap['applied_cached']).to eq(true)
        expect(snap['pending']).to eq(false)
      end

      it 'toggling back to cached removes exactly that entry: ignore empty again, saved-cached, no longer pending' do
        res = post('/api/toggle', { 'X-SPM-Token' => @token }, toggle_body('Alamofire', true))
        expect(res.code).to eq('200')
        expect(JSON.parse(res.body)['data']['cached']).to eq(true)

        expect(disk_ignore).to eq([])
        row = state_row('Alamofire')
        expect(row['saved_cached']).to eq(true)
        expect(row['applied_cached']).to eq(true)
        expect(row['pending']).to eq(false)
      end

      it 'never consults the spawn slot: with the Jobs slot deliberately held, a toggle still answers 200 and writes (D-08)' do
        before_count = probe_entries.length
        first_pid = nil
        ENV['FAKE_BIN_SLEEP'] = '2'
        first = post('/api/build', { 'X-SPM-Token' => @token }, JSON.generate('scope' => 'build'))
        expect(first.code).to eq('200')
        first_entry = wait_for_probe_entry(before_count)
        expect(first_entry).not_to be_nil
        first_pid = first_entry['pid']

        # The slot is GENUINELY held right now (a second build
        # harvests the 409) -- the toggle must not (D-08: no 409 from
        # this route, ever; the slot governs Apply-now only).
        busy = post('/api/build', { 'X-SPM-Token' => @token }, JSON.generate('scope' => 'build'))
        expect(busy.code).to eq('409')

        res = post('/api/toggle', { 'X-SPM-Token' => @token }, toggle_body('SnapKit', false))
        expect(res.code).to eq('200')
        expect(disk_ignore).to eq(['SnapKit'])
      ensure
        ENV.delete('FAKE_BIN_SLEEP')
        wait_for_pid_exit(first_pid)
      end
    end

    # 16-04: the phase's whole server-side claim as ONE story --
    # change the config from the browser, see it diverge on
    # /api/state, run the REAL re-sync through the one slot, and
    # watch convergence on a FRESH /api/state read once the run has
    # ended -- never asserted from the POST's own answer (A7/A13).
    # Nested beside the toggle/build tracers for the same ordering
    # reason: after WELD_RUN, before the file's real shutdown acts.
    describe 'POST /api/apply -> converge (16-04)' do
      def toggle_body(package, cached)
        JSON.generate('package' => package, 'cached' => cached)
      end

      def disk_ignore
        path = File.join(@project_dir, 'spm-cache.yml')
        return [] unless File.exist?(path)

        parsed = YAML.safe_load(File.read(path))
        parsed.is_a?(Hash) ? parsed['ignore'] : nil
      end

      def state_row(name)
        payload = JSON.parse(get('/api/state', 'X-SPM-Token' => @token).body)
        expect(payload['status']).to eq('ok')
        payload['data']['packages'].find { |row| row['name'] == name }
      end

      def update_graph(entries)
        path = File.join(@project_dir, 'spm-cache', 'packages', 'proxy', 'graph.json')
        File.write(path, JSON.generate(entries))
      end

      it 'toggling Alamofire off diverges it: saved-not-cached, still applied-cached, pending' do
        res = post('/api/toggle', { 'X-SPM-Token' => @token }, toggle_body('Alamofire', false))
        expect(res.code).to eq('200')

        row = state_row('Alamofire')
        expect(row['saved_cached']).to eq(false)
        expect(row['applied_cached']).to eq(true)
        expect(row['pending']).to eq(true)
      end

      it 'POST /api/apply spawns the bare sync verb through the slot (ui trigger, project dir) -- and a toggle during the run stays live (D-08)' do
        before_count = probe_entries.length
        apply_pid = nil
        begin
          ENV['FAKE_BIN_SLEEP'] = '1'
          res = post('/api/apply', 'X-SPM-Token' => @token)
          expect(res.code).to eq('200')
          envelope = JSON.parse(res.body)
          expect(envelope['data']['scope']).to eq('use')

          entry = wait_for_probe_entry(before_count)
          expect(entry).not_to be_nil
          expect(entry['argv']).to eq(['use'])
          expect(entry['trigger_env']).to eq('ui')
          expect(File.realpath(entry['pwd'])).to eq(File.realpath(@project_dir))
          apply_pid = entry['pid']

          # The slot is GENUINELY held right now (a build harvests the
          # 409) -- yet toggling the OTHER fixture package is never
          # slot-gated and still writes (D-08).
          busy = post('/api/build', { 'X-SPM-Token' => @token }, JSON.generate('scope' => 'build'))
          expect(busy.code).to eq('409')

          toggle_res = post('/api/toggle', { 'X-SPM-Token' => @token }, toggle_body('SnapKit', true))
          expect(toggle_res.code).to eq('200')
          expect(disk_ignore).to eq(['Alamofire'])
        ensure
          ENV.delete('FAKE_BIN_SLEEP')
          wait_for_pid_exit(apply_pid)
        end
      end

      it 'converges once the run has ended and the applied truth catches up: a fresh /api/state shows Alamofire no longer pending' do
        update_graph([
                       { 'module' => 'Alamofire', 'status' => 'ignored', 'hasMacro' => false },
                       { 'module' => 'SnapKit', 'status' => 'missed', 'hasMacro' => true }
                     ])

        row = state_row('Alamofire')
        expect(row['state']).to eq('ignored')
        expect(row['saved_cached']).to eq(false)
        expect(row['applied_cached']).to eq(false)
        expect(row['pending']).to eq(false)

        snap = state_row('SnapKit')
        expect(snap['saved_cached']).to eq(true)
        expect(snap['applied_cached']).to eq(true)
        expect(snap['pending']).to eq(false)
      end
    end

    # Wrapped in its own describe (not a direct it): RSpec always runs
    # a group's direct examples before its nested groups, regardless
    # of source interleaving -- nesting this is what keeps it running
    # AFTER the POST /api/build describe above, as the file's true
    # final act on @server.
    describe 'shutdown with an open stream (the sentinel proof, WEB-03)' do
      it 'shuts down within bound WITH an open stream' do
        sock = raw_stream
        read_until(sock, 'event: hello') # the stream is genuinely open and parked in its pop
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        WebServerBoot.shutdown(@server) # Server#shutdown: broadcaster sentinel BEFORE @http.shutdown
        joined = @thread.join(10) # WEBrick's accept loop joins the stream's connection thread
        expect(joined).to be_truthy # webrick server.rb:210 did NOT hang on the open body proc
        expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 10.0
        WebServerBoot.raw_close(sock)
      end
    end
  end

  # 15-01: the shutdown-with-in-flight-build sentinel (WEB-03 + D-02
  # in one row, P5 as a spec). The file's LAST describe: it spawns
  # via the SAME @jobs collaborator constructed in the ONE boot above
  # (CP7 -- no second listener, no second Jobs instance) so the claim
  # holds regardless of whatever state the SSE-shutdown example above
  # already left @server in.
  describe 'shutdown with an in-flight UI build (D-02/WEB-03, P5 as a spec)' do
    it 'returns bounded, and the detached child is still alive immediately afterwards' do
      pid = nil
      ENV['FAKE_BIN_SLEEP'] = '2'
      pid = @jobs.spawn_run(scope: 'build')
      expect(pid).not_to be_nil

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      WebServerBoot.shutdown(@server) # neither waits on, reaps, nor kills the child
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      expect(elapsed).to be < 5.0

      expect { Process.kill(0, pid) }.not_to raise_error
    ensure
      ENV.delete('FAKE_BIN_SLEEP')
      # The example reaps the child itself (D-02: no server code ever
      # does) -- TERM the process GROUP, then the bounded liveness
      # poll every other row uses, so no example leaks a process.
      begin
        Process.kill('-TERM', pid) if pid
      rescue Errno::ESRCH, Errno::EPERM
        nil
      end
      wait_for_pid_exit(pid)
    end

    it 'shutdown with an in-flight Apply-now spawn returns bounded and leaves the child alive (16-04, the new spawn verb)' do
      pid = nil
      ENV['FAKE_BIN_SLEEP'] = '2'
      pid = @jobs.spawn_run(scope: 'use')
      expect(pid).not_to be_nil

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      WebServerBoot.shutdown(@server) # neither waits on, reaps, nor kills the child
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      expect(elapsed).to be < 5.0

      expect { Process.kill(0, pid) }.not_to raise_error
    ensure
      ENV.delete('FAKE_BIN_SLEEP')
      begin
        Process.kill('-TERM', pid) if pid
      rescue Errno::ESRCH, Errno::EPERM
        nil
      end
      wait_for_pid_exit(pid)
    end
  end
end
