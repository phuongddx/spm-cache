# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'time'
require 'tmpdir'
require 'fileutils'
require 'stringio'

require_relative 'support/web_server_boot'

# Live-server behavior matrix for the hardened /api/graph tracer slice:
# a real WEBrick boot on an ephemeral loopback port (WEB-01), the
# bootstrap redirect + token gate (WEB-04), and the {status, data,
# generated_at} envelope over <project>/spm-cache/packages/proxy/graph.json
# (DASH-03). Config singleton hygiene: the boot helper points the
# singleton at a tmpdir project and restores it in ensure.
RSpec.describe 'SPMCache::Web::Server request matrix' do
  def http_get(handle, path, headers = {})
    WebServerBoot.http_get(handle, path, headers)
  end

  def http_post(handle, path, headers = {})
    WebServerBoot.http_post(handle, path, headers)
  end

  def with_server(project_dir, **kwargs, &block)
    WebServerBoot.with_server(project_dir: project_dir, **kwargs, &block)
  end

  describe 'binding' do
    it 'binds explicitly to 127.0.0.1 on an ephemeral port and exposes #port' do
      Dir.mktmpdir do |project_dir|
        with_server(project_dir) do |handle|
          expect(handle.server.bind_address).to eq('127.0.0.1')
          expect(handle.port).to be > 0
          # The server actually answers on that port via the loopback.
          res = http_get(handle, "/?token=#{handle.token}")
          expect(res.code).to eq('404') # tracer gap: index.html lands in Plan 13-03
        end
      end
    end
  end

  describe 'bootstrap redirect (WEB-04)' do
    it 'redirects GET / without a token to /?token=<the launch token>' do
      Dir.mktmpdir do |project_dir|
        with_server(project_dir) do |handle|
          res = http_get(handle, '/')
          expect(res.code).to eq('302')
          expect(res['Location']).to eq("/?token=#{handle.token}")
        end
      end
    end

    it 'serves /?token=... as the index only when the asset exists (404 until Plan 13-03)' do
      Dir.mktmpdir do |project_dir|
        with_server(project_dir) do |handle|
          res = http_get(handle, '/?token=anything')
          expect(res.code).to eq('404')
        end
      end
    end
  end

  describe '/api/graph envelope (DASH-03)' do
    let(:graph_fixture) do
      [
        { 'module' => 'A', 'status' => 'hit', 'hasMacro' => false },
        { 'module' => 'B', 'status' => 'missed', 'hasMacro' => true }
      ]
    end
    let(:expected_nodes) do
      graph_fixture.map do |e|
        { 'data' => { 'id' => e['module'], 'module' => e['module'],
                      'status' => e['status'], 'hasMacro' => e['hasMacro'] } }
      end
    end

    def write_graph(project_dir, text)
      path = File.join(project_dir, 'spm-cache', 'packages', 'proxy', 'graph.json')
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, text)
      path
    end

    it 'returns the ok envelope with depgraph_for_viz nodes and the graph mtime' do
      Dir.mktmpdir do |project_dir|
        path = write_graph(project_dir, JSON.generate(graph_fixture))
        with_server(project_dir) do |handle|
          res = http_get(handle, '/api/graph', 'X-SPM-Token' => handle.token)
          expect(res.code).to eq('200')
          body = JSON.parse(res.body)
          expect(body.keys).to contain_exactly('status', 'data', 'generated_at')
          expect(body['status']).to eq('ok')
          expect(body['generated_at']).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/)
          expect(body['data']).to eq(
            'present' => true,
            'nodes' => expected_nodes,
            'graph_generated_at' => File.mtime(path).utc.iso8601
          )
        end
      end
    end

    it 'returns present:false with empty nodes when graph.json is absent' do
      Dir.mktmpdir do |project_dir|
        with_server(project_dir) do |handle|
          res = http_get(handle, '/api/graph', 'X-SPM-Token' => handle.token)
          expect(res.code).to eq('200')
          body = JSON.parse(res.body)
          expect(body['status']).to eq('ok')
          expect(body['data']).to eq(
            'present' => false,
            'nodes' => [],
            'graph_generated_at' => nil
          )
        end
      end
    end

    it 'returns a 500 error envelope carrying the parse message for malformed graph.json' do
      Dir.mktmpdir do |project_dir|
        write_graph(project_dir, '{not json')
        with_server(project_dir) do |handle|
          res = http_get(handle, '/api/graph', 'X-SPM-Token' => handle.token)
          expect(res.code).to eq('500')
          body = JSON.parse(res.body)
          expect(body['status']).to eq('error')
          expect(body['data'].keys).to eq(['message'])
          expect(body['data']['message']).to be_a(String).and(include('not json'))
          expect(body['generated_at']).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/)
        end
      end
    end

    it 'accepts the token as a ?token= query parameter (header-equivalent)' do
      Dir.mktmpdir do |project_dir|
        with_server(project_dir) do |handle|
          res = http_get(handle, "/api/graph?token=#{handle.token}")
          expect(res.code).to eq('200')
          expect(JSON.parse(res.body)['status']).to eq('ok')
        end
      end
    end
  end

  describe 'reject matrix (WEB-04)' do
    it '403s /api/graph on a mismatched Origin' do
      Dir.mktmpdir do |project_dir|
        with_server(project_dir) do |handle|
          res = http_get(handle, '/api/graph',
                         'Origin' => 'http://evil.com', 'X-SPM-Token' => handle.token)
          expect(res.code).to eq('403')
        end
      end
    end

    it '403s /api/graph on a spoofed Host (DNS rebinding, T-13-02)' do
      Dir.mktmpdir do |project_dir|
        with_server(project_dir) do |handle|
          res = http_get(handle, '/api/graph',
                         'Host' => "evil.com:#{handle.port}", 'X-SPM-Token' => handle.token)
          expect(res.code).to eq('403')
        end
      end
    end

    it '401s /api/graph with no token and with a wrong token' do
      Dir.mktmpdir do |project_dir|
        with_server(project_dir) do |handle|
          expect(http_get(handle, '/api/graph').code).to eq('401')
          res = http_get(handle, '/api/graph', 'X-SPM-Token' => 'f' * 64)
          expect(res.code).to eq('401')
        end
      end
    end

    it 'enforces Host and Origin on non-API routes too (GET /)' do
      Dir.mktmpdir do |project_dir|
        with_server(project_dir) do |handle|
          res = http_get(handle, '/', 'Host' => "evil.com:#{handle.port}")
          expect(res.code).to eq('403')
          res = http_get(handle, '/', 'Origin' => 'http://evil.com')
          expect(res.code).to eq('403')
        end
      end
    end

    it 'enforces Host and Origin on asset routes too' do
      Dir.mktmpdir do |project_dir|
        with_server(project_dir) do |handle|
          res = http_get(handle, '/assets/whatever', 'Host' => "evil.com:#{handle.port}")
          expect(res.code).to eq('403')
          res = http_get(handle, '/assets/whatever', 'Origin' => 'https://127.0.0.1:7915')
          expect(res.code).to eq('403')
        end
      end
    end

    it '403s a POST with a bad Origin (method-agnostic gate for Phase 15 POSTs)' do
      Dir.mktmpdir do |project_dir|
        with_server(project_dir) do |handle|
          res = http_post(handle, '/api/graph',
                          'Origin' => 'http://evil.com', 'X-SPM-Token' => handle.token)
          expect(res.code).to eq('403')
        end
      end
    end

    it '404s a passing-gate POST (no POST handler) after the gate' do
      Dir.mktmpdir do |project_dir|
        with_server(project_dir) do |handle|
          res = http_post(handle, '/api/graph', 'X-SPM-Token' => handle.token)
          expect(res.code).to eq('404')
          expect(JSON.parse(res.body)['status']).to eq('error')
        end
      end
    end

    it '404s unknown paths' do
      Dir.mktmpdir do |project_dir|
        with_server(project_dir) do |handle|
          expect(http_get(handle, '/nope').code).to eq('404')
        end
      end
    end
  end

  describe 'response hygiene' do
    it 'carries X-Frame-Options: DENY and Cache-Control: no-store on every response' do
      Dir.mktmpdir do |project_dir|
        with_server(project_dir) do |handle|
          [http_get(handle, '/'),
           http_get(handle, '/?token=x'),
           http_get(handle, '/api/graph', 'X-SPM-Token' => handle.token),
           http_get(handle, '/api/graph'),
           http_get(handle, '/nope')].each do |res|
            expect(res['X-Frame-Options']).to eq('DENY')
            expect(res['Cache-Control']).to eq('no-store')
          end
        end
      end
    end

    it 'emits no WEBrick access log and never logs the token (T-13-03)' do
      captured = StringIO.new
      original_stderr = $stderr
      token = nil
      $stderr = captured
      begin
        Dir.mktmpdir do |project_dir|
          with_server(project_dir) do |handle|
            token = handle.token
            http_get(handle, "/?token=#{handle.token}")
            http_get(handle, '/')
            http_get(handle, '/api/graph', 'X-SPM-Token' => handle.token)
            http_get(handle, '/api/graph')
            http_get(handle, '/nope')
          end
        end
      ensure
        $stderr = original_stderr
      end
      expect(captured.string).to be_empty
      expect(captured.string).not_to include(token)
    end
  end
end
