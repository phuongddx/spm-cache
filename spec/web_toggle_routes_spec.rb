# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'tmpdir'
require 'fileutils'
require 'yaml'

require_relative 'support/web_server_boot'

# The full toggle/revert/apply matrix (16-04, 16-VALIDATION Wave-2
# route row): POST /api/toggle's complete validation -- auth, verb,
# body, package, cached, unknown, not-toggleable, write failure,
# success, slot independence (D-08) -- plus POST /api/revert's batched
# restore and POST /api/apply's route-fixed sync scope (added by
# Task 2). Hermetic per example (the web_build_routes_spec idiom): a
# tmpdir project AND a tmpdir cache root (the web_state_spec idiom), a
# real WEBrick on port 0, the state read model's cache_root: seam
# injected through read_models: so the package universe is
# deterministic, and the 15-01 fake-bin-backed Jobs injected through
# the router's jobs: seam for the slot-independence and apply rows.
# Spawn identity is asserted from the fake bin's own recorded probe
# entries; every spawned child is reaped in an ensure so no example
# leaks a process past the suite.
RSpec.describe 'SPMCache::Web mutation routes (/api/toggle, /api/revert, /api/apply)' do
  # Named uniquely (not FAKE_BIN/FAKE_BIN_PATH): describe-block
  # constants land on Object under RSpec's class_exec, so a shared
  # name would redefinition-warn whenever sibling web specs co-load.
  TOGGLE_FAKE_BIN = File.expand_path('fixtures/fake_spm_cache_bin.rb', __dir__)

  around do |example|
    Dir.mktmpdir('spm-cache-toggle-project') do |project_dir|
      Dir.mktmpdir('spm-cache-toggle-cache') do |cache_root|
        @project_dir = project_dir
        @cache_root = cache_root
        @probe_file = File.join(project_dir, 'probe.jsonl')
        previous_probe = ENV.fetch('FAKE_BIN_PROBE', nil)
        ENV['FAKE_BIN_PROBE'] = @probe_file
        SPMCache::Core::Config.instance.reset!
        begin
          example.run
        ensure
          SPMCache::Core::Config.instance.reset!
          ENV.delete('FAKE_BIN_SLEEP')
          if previous_probe
            ENV['FAKE_BIN_PROBE'] = previous_probe
          else
            ENV.delete('FAKE_BIN_PROBE')
          end
        end
      end
    end
  end

  def auth
    { 'X-SPM-Token' => @handle.token }
  end

  def post(path, headers = {}, body = nil)
    WebServerBoot.http_post(@handle, path, headers, body)
  end

  def get(path, headers = {})
    WebServerBoot.http_get(@handle, path, headers)
  end

  # Non-GET/POST verbs: WebServerBoot ships only get/post helpers, so
  # PUT/DELETE/HEAD ride a local one-shot request builder over the
  # same loopback Net::HTTP discipline (web_build_routes_spec idiom).
  def request_with(request_class, path, headers = {})
    Net::HTTP.start('127.0.0.1', @handle.port) do |http|
      req = request_class.new(path)
      headers.each { |name, value| req[name] = value }
      http.request(req)
    end
  end

  def state_model
    lambda do |config:|
      SPMCache::Web::ReadModels::State.call(config: config, cache_root: @cache_root)
    end
  end

  def default_jobs
    SPMCache::Web::Jobs.new(config: SPMCache::Core::Config.instance, bin_path: TOGGLE_FAKE_BIN)
  end

  def with_server(jobs: default_jobs, &block)
    WebServerBoot.with_server(project_dir: @project_dir, jobs: jobs,
                              read_models: { state: state_model }) do |handle|
      @handle = handle
      block.call
    end
  end

  def probe_entries
    return [] unless File.exist?(@probe_file)

    File.readlines(@probe_file).map { |line| JSON.parse(line) }
  end

  def wait_for_probe_entry(index, timeout: 5)
    deadline = Time.now + timeout
    loop do
      entry = probe_entries[index]
      return entry if entry
      return nil if Time.now > deadline

      sleep 0.02
    end
  end

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

  def expect_no_spawn(from_index)
    expect(probe_entries.length).to eq(from_index)
  end

  # -- fixtures ------------------------------------------------------

  def write_framework(cfg, name, bytes: 0)
    fw = File.join(@cache_root, cfg, "#{name}.xcframework")
    FileUtils.mkdir_p(fw)
    File.write(File.join(fw, 'binary.dat'), 'x' * bytes) if bytes.positive?
    fw
  end

  def write_graph(entries)
    path = File.join(@project_dir, 'spm-cache', 'packages', 'proxy', 'graph.json')
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.generate(entries))
  end

  def config_path
    File.join(@project_dir, 'spm-cache.yml')
  end

  def write_config_yaml(body)
    File.write(config_path, body)
  end

  def disk_ignore
    return [] unless File.exist?(config_path)

    parsed = YAML.safe_load(File.read(config_path))
    parsed.is_a?(Hash) ? (parsed['ignore'] || []) : []
  end

  def toggle_body(package, cached)
    JSON.generate('package' => package, 'cached' => cached)
  end

  describe 'the gate matrix (D-04 -- inherited, not re-implemented)' do
    it 'answers 401 with the error envelope and writes nothing for a tokenless POST' do
      with_server do
        res = post('/api/toggle', {}, toggle_body('Plain', false))
        expect(res.code).to eq('401')
        expect(JSON.parse(res.body)['status']).to eq('error')
        expect(disk_ignore).to eq([])
      end
    end

    it 'answers 401 with the error envelope and writes nothing for a wrong-token POST' do
      with_server do
        res = post('/api/toggle', { 'X-SPM-Token' => 'f' * 64 }, toggle_body('Plain', false))
        expect(res.code).to eq('401')
        expect(disk_ignore).to eq([])
      end
    end

    it 'accepts the correct token in the header' do
      write_framework('debug', 'Plain')
      with_server do
        res = post('/api/toggle', auth, toggle_body('Plain', false))
        expect(res.code).to eq('200')
      end
    end

    it 'answers 403 before dispatch for a foreign Origin and writes nothing' do
      with_server do
        res = post('/api/toggle', auth.merge('Origin' => 'http://evil.com'), toggle_body('Plain', false))
        expect(res.code).to eq('403')
        expect(disk_ignore).to eq([])
      end
    end

    it 'answers the house 404 for every non-POST verb (GET, PUT, DELETE, HEAD) and writes nothing' do
      with_server do
        [Net::HTTP::Get, Net::HTTP::Put, Net::HTTP::Delete, Net::HTTP::Head].each do |verb|
          res = request_with(verb, '/api/toggle', auth)
          expect(res.code).to eq('404')
          next if verb == Net::HTTP::Head

          envelope = JSON.parse(res.body)
          expect(envelope['status']).to eq('error')
          expect(envelope['data']['message']).to eq('not found')
        end
        expect(disk_ignore).to eq([])
      end
    end
  end

  describe 'body validation (V5 -- every rejection precedes any write)' do
    it 'answers 400 bad_body for unparseable JSON and writes nothing' do
      with_server do
        res = post('/api/toggle', auth, '{nope')
        expect(res.code).to eq('400')
        expect(JSON.parse(res.body)['data']['reason']).to eq('bad_body')
        expect(disk_ignore).to eq([])
      end
    end

    it 'answers 400 bad_package for absent, empty, whitespace-only, and non-String package values' do
      with_server do
        [
          JSON.generate('cached' => false),
          JSON.generate('package' => '', 'cached' => false),
          JSON.generate('package' => '   ', 'cached' => false),
          JSON.generate('package' => 7, 'cached' => false),
          JSON.generate('package' => nil, 'cached' => false),
          JSON.generate(%w[Plain]),
          JSON.generate('Plain')
        ].each do |raw|
          res = post('/api/toggle', auth, raw)
          expect(res.code).to eq('400'), raw
          expect(JSON.parse(res.body)['data']['reason']).to eq('bad_package'), raw
        end
        expect(disk_ignore).to eq([])
      end
    end

    it 'answers 400 bad_cached for a string, numbers, null, or an absent key -- no truthy coercion' do
      write_framework('debug', 'Plain')
      with_server do
        [
          JSON.generate('package' => 'Plain', 'cached' => 'true'),
          JSON.generate('package' => 'Plain', 'cached' => 1),
          JSON.generate('package' => 'Plain', 'cached' => 0),
          JSON.generate('package' => 'Plain', 'cached' => nil),
          JSON.generate('package' => 'Plain')
        ].each do |raw|
          res = post('/api/toggle', auth, raw)
          expect(res.code).to eq('400'), raw
          expect(JSON.parse(res.body)['data']['reason']).to eq('bad_cached'), raw
        end
        expect(disk_ignore).to eq([])
      end
    end
  end

  describe 'unknown package (the row set IS the universe)' do
    it 'answers 404 unknown_package for a package the dashboard does not serve, and writes nothing' do
      write_framework('debug', 'Plain')
      with_server do
        res = post('/api/toggle', auth, toggle_body('Ghost', false))
        expect(res.code).to eq('404')
        expect(JSON.parse(res.body)['data']['reason']).to eq('unknown_package')
        expect(disk_ignore).to eq([])
      end
    end
  end

  describe 'not toggleable (the stale-DOM defense, permission re-derived from disk)' do
    it 'answers 400 not_toggleable for a glob-pattern-managed package and writes nothing' do
      write_framework('debug', 'LockedPkg')
      write_config_yaml("ignore:\n  - 'Locked*'\n")
      with_server do
        res = post('/api/toggle', auth, toggle_body('LockedPkg', false))
        expect(res.code).to eq('400')
        expect(JSON.parse(res.body)['data']['reason']).to eq('not_toggleable')
        expect(disk_ignore).to eq(['Locked*'])
      end
    end
  end

  describe 'write failure (T-13-03 -- an envelope, never a raise into the terminal)' do
    it 'answers 500 config_write_failed when the mutator raises, and nothing is printed' do
      write_framework('debug', 'Plain')
      restricted = false
      with_server do
        FileUtils.chmod(0o500, @project_dir) # tempfile/lock creation inside the dir now fails
        restricted = true
        res = post('/api/toggle', auth, toggle_body('Plain', false))
        expect(res.code).to eq('500')
        envelope = JSON.parse(res.body)
        expect(envelope['status']).to eq('error')
        expect(envelope['data']['reason']).to eq('config_write_failed')
        expect(envelope['data']['message']).to be_a(String)
        expect(envelope['data']['message']).not_to be_empty
      end
    ensure
      FileUtils.chmod(0o700, @project_dir) if restricted
    end
  end

  describe 'success (the standard envelope, idempotent in both directions)' do
    it 'answers 200 with the package and its new cached state, and the config on disk matches' do
      write_framework('debug', 'Plain')
      with_server do
        res = post('/api/toggle', auth, toggle_body('Plain', false))
        expect(res.code).to eq('200')
        envelope = JSON.parse(res.body)
        expect(envelope['status']).to eq('ok')
        expect(envelope['data']).to eq('package' => 'Plain', 'cached' => false)
        expect(disk_ignore).to eq(['Plain'])
      end
    end

    it 'is idempotent toggling off twice and back to cached twice' do
      write_framework('debug', 'Plain')
      with_server do
        post('/api/toggle', auth, toggle_body('Plain', false))
        second_off = post('/api/toggle', auth, toggle_body('Plain', false))
        expect(second_off.code).to eq('200')
        expect(disk_ignore).to eq(['Plain'])

        post('/api/toggle', auth, toggle_body('Plain', true))
        second_on = post('/api/toggle', auth, toggle_body('Plain', true))
        expect(second_on.code).to eq('200')
        expect(disk_ignore).to eq([])
      end
    end
  end

  describe 'slot independence (D-08 -- never gated by the spawn slot)' do
    it 'answers 200 and still writes while the slot is held by a live run; never a 409' do
      write_framework('debug', 'Plain')
      with_server do
        build_pid = nil
        begin
          ENV['FAKE_BIN_SLEEP'] = '2'
          build_res = post('/api/build', auth, JSON.generate('scope' => 'build'))
          expect(build_res.code).to eq('200')
          build_entry = wait_for_probe_entry(0)
          expect(build_entry).not_to be_nil
          build_pid = build_entry['pid']

          busy = post('/api/build', auth, JSON.generate('scope' => 'build'))
          expect(busy.code).to eq('409') # proof the slot IS genuinely held right now

          res = post('/api/toggle', auth, toggle_body('Plain', false))
          expect(res.code).to eq('200')
          expect(res.code).not_to eq('409')
          expect(disk_ignore).to eq(['Plain'])
        ensure
          ENV.delete('FAKE_BIN_SLEEP')
          wait_for_pid_exit(build_pid)
        end
      end
    end
  end
end
