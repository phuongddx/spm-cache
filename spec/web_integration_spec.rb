# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'time'
require 'tmpdir'
require 'fileutils'
require 'securerandom'
require 'uri'

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
    router = SPMCache::Web::Router.new(token: @token, port: 0,
                                       assets: SPMCache::Web::Assets.new)
    @server = SPMCache::Web::Server.new(port: 0, token: @token, router: router)
    @thread = Thread.new { @server.start }
    WebServerBoot.wait_accepting(@server.port)
  end

  after(:all) do
    WebServerBoot.shutdown(@server)
    @thread&.join(10)
    SPMCache::Core::Config.configure(project_dir: @previous_project_dir)
    FileUtils.remove_entry(@project_dir)
  end

  def handle
    WebServerBoot::Handle.new(port: @server.port, token: @token, server: @server)
  end

  def get(path, headers = {})
    WebServerBoot.http_get(handle, path, headers)
  end

  def post(path, headers = {})
    WebServerBoot.http_post(handle, path, headers)
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
        'assets/app.js' => 'application/javascript'
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
end
