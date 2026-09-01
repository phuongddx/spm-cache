# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'time'
require 'tmpdir'
require 'fileutils'

require_relative 'support/web_server_boot'

# The 13-01 tracer's inline graph reader, formalized as
# Web::ReadModels::Graph (DASH-03): present? via File.exist?, nodes via
# Cache::Cachemap#depgraph_for_viz, generated stamp from the file mtime.
# Malformed JSON raises JSON::ParserError so the router's 500 error
# envelope carries the parser's own message (the UI's
# "Couldn't load Dependency Graph: {message}" copy depends on it).
RSpec.describe SPMCache::Web::ReadModels::Graph do
  let(:project_dir) { Dir.mktmpdir('spm-cache-graph-project') }
  let(:config) { SPMCache::Core::Config.instance }

  around do |example|
    previous = config.project_dir
    SPMCache::Core::Config.configure(project_dir: project_dir)
    example.run
  ensure
    SPMCache::Core::Config.configure(project_dir: previous)
    FileUtils.rm_rf(project_dir)
  end

  def graph_path
    File.join(project_dir, 'spm-cache', 'packages', 'proxy', 'graph.json')
  end

  def write_graph(text)
    FileUtils.mkdir_p(File.dirname(graph_path))
    File.write(graph_path, text)
    graph_path
  end

  def call_graph
    described_class.call(config: config)
  end

  describe 'unit contract' do
    it 'reports present:false with empty nodes and a nil stamp when graph.json is absent' do
      expect(call_graph).to eq('present' => false, 'nodes' => [], 'graph_generated_at' => nil)
    end

    it 'reports present:true with depgraph_for_viz nodes for a populated graph.json' do
      write_graph(JSON.generate([
                                  { 'module' => 'A', 'status' => 'hit', 'hasMacro' => false },
                                  { 'module' => 'B', 'status' => 'missed', 'hasMacro' => true }
                                ]))

      data = call_graph
      expect(data['present']).to eq(true)
      expect(JSON.generate(data['nodes'])).to eq(JSON.generate([
                                                                 { data: { id: 'A', module: 'A', status: 'hit',
                                                                           hasMacro: false } },
                                                                 { data: { id: 'B', module: 'B', status: 'missed',
                                                                           hasMacro: true } }
                                                               ]))
    end

    it 'returns an empty nodes array for a zero-entry graph.json (present stays true)' do
      write_graph('[]')

      expect(call_graph).to eq('present' => true, 'nodes' => [],
                               'graph_generated_at' => File.mtime(graph_path).utc.iso8601)
    end

    it 'stamps graph_generated_at from the file mtime (explicit File.utime fixture)' do
      write_graph(JSON.generate([{ 'module' => 'A', 'status' => 'hit' }]))
      stamp = Time.utc(2019, 1, 2, 3, 4, 5)
      File.utime(stamp, stamp, graph_path)

      expect(call_graph['graph_generated_at']).to eq('2019-01-02T03:04:05Z')
    end

    it 'propagates JSON::ParserError for malformed graph.json instead of swallowing it' do
      write_graph('{not json')

      expect { call_graph }.to raise_error(JSON::ParserError)
    end
  end

  describe 'serve-through-router envelope (13-01 boot helper)' do
    it 'serves the 200 ok envelope with the graph data when the token is supplied' do
      Dir.mktmpdir do |project|
        path = File.join(project, 'spm-cache', 'packages', 'proxy', 'graph.json')
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, JSON.generate([{ 'module' => 'A', 'status' => 'hit', 'hasMacro' => false }]))

        WebServerBoot.with_server(project_dir: project) do |handle|
          res = WebServerBoot.http_get(handle, '/api/graph', 'X-SPM-Token' => handle.token)
          expect(res.code).to eq('200')
          body = JSON.parse(res.body)
          expect(body.keys).to contain_exactly('status', 'data', 'generated_at')
          expect(body['status']).to eq('ok')
          expect(body['data']).to eq(
            'present' => true,
            'nodes' => [{ 'data' => { 'id' => 'A', 'module' => 'A', 'status' => 'hit', 'hasMacro' => false } }],
            'graph_generated_at' => File.mtime(path).utc.iso8601
          )
        end
      end
    end

    it 'token-gates GET /api/graph (401 without the launch token)' do
      Dir.mktmpdir do |project|
        WebServerBoot.with_server(project_dir: project) do |handle|
          res = WebServerBoot.http_get(handle, '/api/graph')
          expect(res.code).to eq('401')
          expect(JSON.parse(res.body)['status']).to eq('error')
        end
      end
    end
  end
end
