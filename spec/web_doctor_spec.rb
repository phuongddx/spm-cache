# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'tmpdir'
require 'fileutils'

require_relative 'support/web_server_boot'

# DASH-02: the doctor read model. run:true executes Core::Diagnostics.
# run_all synchronously in-request (the Run Doctor button -- checks
# shell out and can take seconds) and swaps the {data, generated_at}
# cache under a Mutex; run:false serves the cache -- or the honest
# never-run shape -- with the stamp of the RUN, never of the read.
# The registry is the single source of check truth: the stubbed-extra
# -check example registers a synthetic check and sees it appear with
# zero read-model change. Hermetic posture copied from doctor_spec:
# default-deny Core::Sh with targeted overrides; no example here ever
# shells out to the real host.
RSpec.describe SPMCache::Web::ReadModels::Doctor do
  let(:project_dir) { Dir.mktmpdir('spm-cache-doctor-project') }
  let(:config) { SPMCache::Core::Config.instance }

  around do |example|
    previous = config.project_dir
    SPMCache::Core::Config.configure(project_dir: project_dir)
    config.reset!
    example.run
  ensure
    config.reset!
    SPMCache::Core::Config.configure(project_dir: previous)
    FileUtils.rm_rf(project_dir)
  end

  def read_model
    described_class.new(config: config)
  end

  def deny_sh!
    allow(SPMCache::Core::Sh).to receive(:capture_output)
      .and_raise(SPMCache::Core::GeneralError.new('Command failed (exit 1): not installed'))
  end

  describe 'never-run shape' do
    it 'answers has_run:false with empty checks, a zero summary, and a nil stamp' do
      result = read_model.call

      expect(result[:data]).to eq(
        'has_run' => false, 'checks' => [],
        'summary' => { 'ok' => 0, 'warnings' => 0, 'failures' => 0 }
      )
      expect(result[:generated_at]).to be_nil
    end
  end

  describe 'run semantics' do
    before { deny_sh! }

    it 'run:true executes the registry and caches the payload with has_run:true and an ISO8601 stamp' do
      result = read_model.call(run: true)

      expect(result[:data]['has_run']).to eq(true)
      expect(result[:data]['checks']).to be_an(Array)
      expect(result[:data]['checks']).not_to be_empty
      expect(result[:generated_at]).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/)
    end

    it 'each cached check carries exactly the shared payload keys (name, status, message, fix_hint)' do
      result = read_model.call(run: true)

      result[:data]['checks'].each do |check|
        expect(JSON.parse(JSON.generate(check)).keys).to contain_exactly('name', 'status', 'message', 'fix_hint')
      end
    end

    it 'run:false after a run returns the CACHED payload with the run-time stamp, not a fresh one' do
      model = read_model
      first = model.call(run: true)

      sleep 1.1 # past the ISO8601 stamp's 1s resolution

      second = model.call
      expect(second[:data]).to eq(first[:data])
      expect(second[:generated_at]).to eq(first[:generated_at])
    end

    it 'is data-driven: a stubbed extra check appears in the payload with no read-model change' do
      diagnostics = SPMCache::Core::Diagnostics
      saved = diagnostics.registry.dup
      begin
        diagnostics.register('stub_web_check', fix_hint: 'stub fix') { [:warn, 'synthetic'] }

        result = read_model.call(run: true)
        stub_check = result[:data]['checks'].find { |c| c['name'] == 'stub_web_check' }

        expect(stub_check['status']).to eq('warn')
        expect(stub_check['message']).to eq('synthetic')
        expect(stub_check['fix_hint']).to eq('stub fix')
        expect(result[:data]['summary']['warnings']).to be >= 1
      ensure
        diagnostics.instance_variable_set(:@registry, saved)
      end
    end

    it 'flows hermetic ok and fail verdicts through targeted shell stubs' do
      allow(SPMCache::Core::Sh).to receive(:capture_output).with('xcodebuild -version')
                                                           .and_return("Xcode 16.0\nBuild 16A242d\n")

      result = read_model.call(run: true)
      checks = result[:data]['checks']

      xcode = checks.find { |c| c['name'] == 'xcode_version' }
      expect(xcode['status']).to eq('ok')
      expect(xcode['message']).to eq('Xcode 16.0')

      swift = checks.find { |c| c['name'] == 'swift_version' }
      expect(swift['status']).to eq('fail')
      expect(result[:data]['summary']['failures']).to be >= 1
      expect(result[:data]['summary']['ok']).to be >= 1
    end

    it 'tolerates a project with no spm-cache.yml (config.load rescued, checks still run)' do
      expect(File.exist?(File.join(project_dir, 'spm-cache.yml'))).to be_falsey

      result = read_model.call(run: true)

      expect(result[:data]['has_run']).to eq(true)
      expect(result[:data]['checks']).not_to be_empty
    end
  end

  describe 'concurrency (T-13-10: the {data, generated_at} swap is atomic)' do
    it 'never exposes a torn cache: a thread-B read returns the pair thread A swapped in' do
      deny_sh!
      model = read_model

      from_a = nil
      Thread.new { from_a = model.call(run: true) }.join

      from_b = nil
      Thread.new { from_b = model.call }.join

      expect(from_b[:data]).to eq(from_a[:data])
      expect(from_b[:generated_at]).to eq(from_a[:generated_at])
      expect(from_b[:data]['has_run']).to eq(true)
    end
  end

  describe 'router mount' do
    before { deny_sh! }

    it 'serves GET /api/doctor with the envelope passing the cache stamp through verbatim' do
      Dir.mktmpdir do |project|
        WebServerBoot.with_server(project_dir: project) do |handle|
          fresh = JSON.parse(WebServerBoot.http_get(handle, '/api/doctor', 'X-SPM-Token' => handle.token).body)
          expect(fresh['status']).to eq('ok')
          expect(fresh['data']).to eq(
            'has_run' => false, 'checks' => [],
            'summary' => { 'ok' => 0, 'warnings' => 0, 'failures' => 0 }
          )
          expect(fresh['generated_at']).to be_nil

          run = JSON.parse(WebServerBoot.http_get(handle, '/api/doctor?run=1', 'X-SPM-Token' => handle.token).body)
          expect(run['data']['has_run']).to eq(true)
          expect(run['data']['checks']).not_to be_empty
          expect(run['generated_at']).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/)

          cached = JSON.parse(WebServerBoot.http_get(handle, '/api/doctor', 'X-SPM-Token' => handle.token).body)
          expect(cached['generated_at']).to eq(run['generated_at'])
          expect(cached['data']).to eq(run['data'])
        end
      end
    end

    it 'token-gates GET /api/doctor (401 without the launch token)' do
      Dir.mktmpdir do |project|
        WebServerBoot.with_server(project_dir: project) do |handle|
          res = WebServerBoot.http_get(handle, '/api/doctor')
          expect(res.code).to eq('401')
          expect(JSON.parse(res.body)['status']).to eq('error')
        end
      end
    end
  end
end
