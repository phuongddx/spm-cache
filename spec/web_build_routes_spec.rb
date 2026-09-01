# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'tmpdir'
require 'fileutils'

require_relative 'support/web_server_boot'

# The mutation route matrix over BOTH server-mutating endpoints (15-04,
# 15-VALIDATION row 3): POST /api/build (scopes build/rebuild) and POST
# /api/rollback (route-implied scope, empty-body verb). These rows
# cover the three dashboard verbs and the ONE shared spawn slot
# (UI-SPEC A1); the appended matrix covers auth, verb, body, busy, the
# 2xx lock snapshot (D-06), and spawn failure. Hermetic per-example
# boot (the web_events_route_spec idiom): a tmpdir project, a real
# WEBrick on port 0, and the 15-01 fake-bin-backed Jobs injected
# through the router's jobs: seam -- no real CLI, no xcodebuild. Spawn
# identity is asserted from the fake bin's own recorded probe entries;
# every spawned child is reaped in an ensure so no example leaks a
# process past the suite.
RSpec.describe 'SPMCache::Web mutation routes (/api/build, /api/rollback)' do
  # Named uniquely (not FAKE_BIN/FAKE_BIN_PATH): describe-block
  # constants land on Object under RSpec's class_exec, so a shared
  # name would redefinition-warn whenever sibling web specs co-load.
  MUTATE_FAKE_BIN = File.expand_path('fixtures/fake_spm_cache_bin.rb', __dir__)

  around do |example|
    Dir.mktmpdir('spm-cache-mutate') do |project_dir|
      @project_dir = project_dir
      @probe_file = File.join(project_dir, 'probe.jsonl')
      previous_probe = ENV.fetch('FAKE_BIN_PROBE', nil)
      # Rides the REAL process ENV: Jobs merges ENV.to_h into the
      # spawned child's environment (the integration-spec precedent).
      ENV['FAKE_BIN_PROBE'] = @probe_file
      begin
        example.run
      ensure
        ENV.delete('FAKE_BIN_SLEEP')
        if previous_probe
          ENV['FAKE_BIN_PROBE'] = previous_probe
        else
          ENV.delete('FAKE_BIN_PROBE')
        end
      end
    end
  end

  def auth
    { 'X-SPM-Token' => @handle.token }
  end

  def build_body(scope = 'build')
    JSON.generate('scope' => scope)
  end

  def post(path, headers = {}, body = nil)
    WebServerBoot.http_post(@handle, path, headers, body)
  end

  # Non-GET/POST verbs (the Task-2 verb rows): WebServerBoot ships
  # only get/post helpers, so PUT/DELETE/HEAD ride a local one-shot
  # request builder over the same loopback Net::HTTP discipline.
  def request_with(request_class, path, headers = {})
    Net::HTTP.start('127.0.0.1', @handle.port) do |http|
      req = request_class.new(path)
      headers.each { |name, value| req[name] = value }
      http.request(req)
    end
  end

  def default_jobs
    SPMCache::Web::Jobs.new(config: SPMCache::Core::Config.instance, bin_path: MUTATE_FAKE_BIN)
  end

  def with_server(jobs: default_jobs, &block)
    WebServerBoot.with_server(project_dir: @project_dir, jobs: jobs) do |handle|
      @handle = handle
      block.call
    end
  end

  def probe_entries
    return [] unless File.exist?(@probe_file)

    File.readlines(@probe_file).map { |line| JSON.parse(line) }
  end

  # Bounded poll for the probe entry at `index` (captured BEFORE the
  # POST): spawn_run returns the instant Process.detach is called,
  # well before the child boots far enough to write its probe line.
  def wait_for_probe_entry(index, timeout: 5)
    deadline = Time.now + timeout
    loop do
      entry = probe_entries[index]
      return entry if entry
      return nil if Time.now > deadline

      sleep 0.02
    end
  end

  # Asserts spawn NON-occurrence: rejection paths must never claim a
  # child (V5 -- every rejection precedes any spawn attempt).
  def expect_no_spawn(from_index)
    expect(probe_entries.length).to eq(from_index)
  end

  # Bounded reap: never an unbounded wait, never leaked past an example.
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

  describe 'the three dashboard verbs (D-01/D-07)' do
    it 'POST /api/build {scope:build} spawns exactly the incremental fragment -- the fake bin records argv [build]' do
      with_server do
        before = probe_entries.length
        pid = nil
        begin
          res = post('/api/build', auth, build_body('build'))
          expect(res.code).to eq('200')
          entry = wait_for_probe_entry(before)
          expect(entry).not_to be_nil
          expect(entry['argv']).to eq(['build'])
          pid = entry['pid']
        ensure
          wait_for_pid_exit(pid)
        end
      end
    end

    it 'POST /api/build {scope:rebuild} spawns the SAME verb plus --rebuild (15-03), nothing else differing' do
      with_server do
        plain_pid = nil
        forced_pid = nil
        begin
          plain = nil
          forced = nil
          before_plain = probe_entries.length
          first = post('/api/build', auth, build_body('build'))
          expect(first.code).to eq('200')
          plain = wait_for_probe_entry(before_plain)
          expect(plain).not_to be_nil
          plain_pid = plain['pid']
          wait_for_pid_exit(plain_pid) # slot release derives from run_end on the next claim

          before_forced = probe_entries.length
          second = post('/api/build', auth, build_body('rebuild'))
          expect(second.code).to eq('200')
          forced = wait_for_probe_entry(before_forced)
          expect(forced).not_to be_nil
          forced_pid = forced['pid']

          expect(forced['argv']).to eq(['build', '--rebuild'])
          # Nothing else differs: same cwd, same marker, same stdio,
          # same group leadership (the spawn shape is verb-invariant).
          expect(forced['pwd']).to eq(plain['pwd'])
          expect(forced['trigger_env']).to eq(plain['trigger_env'])
          expect(forced['trigger_env']).to eq('ui')
          expect(forced['pgid']).to eq(forced['pid'])
          expect(forced['stdout_null']).to eq(plain['stdout_null'])
          expect(forced['stderr_null']).to eq(plain['stderr_null'])
        ensure
          wait_for_pid_exit(plain_pid)
          wait_for_pid_exit(forced_pid)
        end
      end
    end

    it 'POST /api/rollback spawns the rollback verb with the identical spawn shape; the 2xx envelope names the scope' do
      with_server do
        before = probe_entries.length
        pid = nil
        begin
          res = post('/api/rollback', auth) # empty body -- rollback takes none
          expect(res.code).to eq('200')
          envelope = JSON.parse(res.body)
          expect(envelope['status']).to eq('ok')
          expect(envelope['data']['scope']).to eq('rollback')

          entry = wait_for_probe_entry(before)
          expect(entry).not_to be_nil
          expect(entry['argv']).to eq(['rollback'])
          expect(entry['trigger_env']).to eq('ui')
          expect(File.realpath(entry['pwd'])).to eq(File.realpath(@project_dir))
          expect(entry['pgid']).to eq(entry['pid']) # own process-group leader
          expect(entry['stdout_null']).to eq(true)
          expect(entry['stderr_null']).to eq(true)
          pid = entry['pid']
        ensure
          wait_for_pid_exit(pid)
        end
      end
    end

    it 'rollback accepts a genuinely empty body and an empty JSON object identically' do
      with_server do
        first_pid = nil
        second_pid = nil
        begin
          first = post('/api/rollback', auth) # no body at all
          expect(first.code).to eq('200')
          first_entry = wait_for_probe_entry(0)
          expect(first_entry).not_to be_nil
          first_pid = first_entry['pid']
          wait_for_pid_exit(first_pid)

          second = post('/api/rollback', auth, '{}')
          expect(second.code).to eq('200')
          second_envelope = JSON.parse(second.body)
          expect(second_envelope['status']).to eq('ok')
          expect(second_envelope['data']['scope']).to eq('rollback')
          second_entry = wait_for_probe_entry(1)
          expect(second_entry).not_to be_nil
          second_pid = second_entry['pid']

          expect(second_entry['argv']).to eq(first_entry['argv'])
        ensure
          wait_for_pid_exit(first_pid)
          wait_for_pid_exit(second_pid)
        end
      end
    end
  end

  describe 'the ONE shared slot (UI-SPEC A1)' do
    it 'refuses a rollback POST with 409 slot_busy while a UI build is in flight, and spawns nothing' do
      with_server do
        build_pid = nil
        begin
          ENV['FAKE_BIN_SLEEP'] = '2'
          before = probe_entries.length
          first = post('/api/build', auth, build_body('build'))
          expect(first.code).to eq('200')
          build_entry = wait_for_probe_entry(before)
          expect(build_entry).not_to be_nil
          build_pid = build_entry['pid']
          count_before = probe_entries.length

          second = post('/api/rollback', auth)
          expect(second.code).to eq('409')
          envelope = JSON.parse(second.body)
          expect(envelope['status']).to eq('error')
          expect(envelope['data']['reason']).to eq('slot_busy')
          expect_no_spawn(count_before)
        ensure
          ENV.delete('FAKE_BIN_SLEEP')
          wait_for_pid_exit(build_pid)
        end
      end
    end

    it 'refuses a build POST with the identical 409 while a UI rollback is in flight -- one slot, not one per verb' do
      with_server do
        rollback_pid = nil
        begin
          ENV['FAKE_BIN_SLEEP'] = '2'
          before = probe_entries.length
          first = post('/api/rollback', auth)
          expect(first.code).to eq('200')
          rollback_entry = wait_for_probe_entry(before)
          expect(rollback_entry).not_to be_nil
          rollback_pid = rollback_entry['pid']
          count_before = probe_entries.length

          second = post('/api/build', auth, build_body('build'))
          expect(second.code).to eq('409')
          envelope = JSON.parse(second.body)
          expect(envelope['status']).to eq('error')
          expect(envelope['data']['reason']).to eq('slot_busy')
          expect_no_spawn(count_before)
        ensure
          ENV.delete('FAKE_BIN_SLEEP')
          wait_for_pid_exit(rollback_pid)
        end
      end
    end
  end
end
