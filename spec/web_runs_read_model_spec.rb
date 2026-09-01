# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'tmpdir'
require 'fileutils'
require 'securerandom'

require_relative 'support/web_server_boot'

# Unit coverage for the /api/runs read model (D-12) and the CP10 state
# derivation it owns: run identity + status derive from the runs dir
# (header pid + run_end lines) and the build lock (a non-blocking
# acquire-and-release probe) on EVERY call -- the State shape, never a
# cache (CP10 forbids run-state memory in the server; Doctor's
# {data, generated_at} instance pattern is explicitly the WRONG shape
# here). CP14 honesty: a dead header pid without a run_end line is
# 'interrupted -- exit unknown', never 'running'; a held lock nothing
# live can own is 'unknown holder' (LOGS-05 external-run detection) --
# the derivation never guesses. Fixtures are hand-authored JSONL in the
# Phase 12 vocabulary (run_log_spec fixture idiom); the thread-held
# flock helper below is this repo's first cross-thread lock fixture
# (built once here per 14-PATTERNS; 14-02's inline helper is
# site-specific to the Installer notice rows).
RSpec.describe 'SPMCache::Web::ReadModels::Runs (CP10 derivation + D-12 listing)' do
  # ESRCH by construction (events_tailer_spec / run_log.rb:395-402
  # posture): Process.kill(0, 999_999_999) means the pid is dead.
  DEAD_PID = 999_999_999

  let(:project_dir) { Dir.mktmpdir('spm-cache-runs-project') }
  let(:config) { SPMCache::Core::Config.instance }
  let(:runs_dir) { File.join(project_dir, '.spm-cache', 'runs') }

  # web_doctor_spec:24-33 idiom: the Config singleton points at the
  # tmpdir project for the example, so build_lock_path and runs_dir are
  # the REAL derived paths under it (config.rb:110-121).
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

  # Resolved INSIDE examples: the RED run reports failing examples,
  # not a load error (the 0-examples trap, events_tailer_spec idiom).
  def runs_model
    SPMCache::Web::ReadModels::Runs
  end

  def payload
    runs_model.call(config: config)
  end

  # -- fixtures (Phase 12 JSONL vocabulary) ------------------------------

  def self.header_line(command:, trigger:, pid:, started_at: '2026-09-01T09:30:00Z')
    JSON.generate(
      'event' => 'run_start', 'ts' => started_at, 'command' => command,
      'argv' => [command, 'Alamofire'], 'redacted' => false, 'pid' => pid,
      'started_at' => started_at, 'spm_cache_version' => '0.5.0',
      'trigger' => trigger, 'cycle' => false
    ) + "\n"
  end

  def self.body_line(text)
    JSON.generate('ts' => '2026-09-01T09:30:01Z', 'stream' => 'out', 'text' => text) + "\n"
  end

  # run_log.rb:283-285 shape: status + ended_at (+ the shared 'ts').
  def self.run_end_line(status, ended_at: '2026-09-01T09:31:00Z')
    JSON.generate('event' => 'run_end', 'ts' => ended_at,
                  'status' => status, 'ended_at' => ended_at) + "\n"
  end

  def header_line(**kwargs)
    self.class.header_line(**kwargs)
  end

  def body_line(text)
    self.class.body_line(text)
  end

  def run_end_line(status, **kwargs)
    self.class.run_end_line(status, **kwargs)
  end

  # Filename chronology (run_log.rb:31,117): '%Y%m%dT%H%M%S%3NZ-<pid>-<verb>'
  # -- lexicographic sort == chronological order.
  def run_name(sec:, pid: 4821, verb: 'build')
    format('20260901T0930%02d000Z-%d-%s.jsonl', sec, pid, verb)
  end

  def write_run(name, lines)
    FileUtils.mkdir_p(runs_dir)
    File.write(File.join(runs_dir, name), lines.join)
  end

  # -- the thread-held flock helper (14-PATTERNS: no repo ancestor) -----
  # A background thread takes LOCK_EX on the REAL Config#build_lock_path
  # under the tmpdir project (never a mock); the block runs only after
  # the lock is genuinely held; release is signalled and the holder is
  # JOINED in ensure, so assertions after the block can never race the
  # unlock. Bounded pops/joins everywhere (web_server_boot discipline):
  # a wedged holder fails the example, never the suite.
  def with_build_lock_held
    path = config.build_lock_path
    FileUtils.mkdir_p(File.dirname(path))
    taken = Queue.new
    release = Queue.new
    holder = Thread.new do
      file = File.open(path, File::CREAT | File::RDWR)
      begin
        file.flock(File::LOCK_EX)
        taken << true
        release.pop(timeout: 10)
      ensure
        file.flock(File::LOCK_UN)
        file.close
      end
    end
    taken.pop(timeout: 5)
    begin
      yield
    ensure
      release << true
      holder.join(5) || holder.kill
    end
  end

  # -- 1. the probe ------------------------------------------------------

  it 'probes the build lock acquire-and-release: thread-held → held; released → free (the server never holds)' do
    with_build_lock_held do
      expect(payload['lock']['state']).to eq('held')
    end
    # The helper JOINED the holder before returning: the unlock has
    # landed. A probe that held the lock would fail right here -- the
    # free-direction assertion IS the never-holds proof (CP4's flip
    # side; the probe acquires and releases atomically inside one
    # File.open block).
    expect(payload['lock']['state']).to eq('free')
  end

  # -- 2/3. attribution (LOGS-05) ---------------------------------------

  it 'attributes a held lock to the attributable live run: holder identity + running' do
    write_run(run_name(sec: 10), [header_line(command: 'build', trigger: 'terminal', pid: DEAD_PID),
                                  body_line("old\n"), run_end_line(0)])
    live = run_name(sec: 20, pid: Process.pid) # header pid = THIS process: alive
    write_run(live, [header_line(command: 'use', trigger: 'watch', pid: Process.pid),
                     body_line("in flight\n")]) # no run_end

    with_build_lock_held do
      lock = payload['lock']
      expect(lock['state']).to eq('held')
      expect(lock['holder']).to eq(live) # held + attributable → that run's identity
      expect(lock['holder_status']).to eq('running')
    end
  end

  it "reports 'unknown holder' when nothing live is attributable — never a guess" do
    write_run(run_name(sec: 10), [header_line(command: 'build', trigger: 'terminal', pid: Process.pid),
                                  body_line("done\n"), run_end_line(0)]) # finished
    write_run(run_name(sec: 20), [header_line(command: 'build', trigger: 'terminal', pid: DEAD_PID),
                                  body_line("crashed\n")]) # interrupted, dead pid

    with_build_lock_held do
      lock = payload['lock']
      expect(lock['state']).to eq('held')
      expect(lock['holder']).to be_nil
      # External-run detection (LOGS-05): a --no-run-log holder or a
      # pre-Phase-12 process genuinely holds the lock; the derivation
      # says so instead of fabricating an identity.
      expect(lock['holder_status']).to eq('unknown holder')
    end
  end

  # -- 4/5. status vocabulary + CP14 honesty -----------------------------

  it "CP14: a dead header pid with no run_end derives 'interrupted — exit unknown', never 'running'" do
    write_run(run_name(sec: 30, pid: DEAD_PID),
              [header_line(command: 'build', trigger: 'terminal', pid: DEAD_PID),
               body_line("killed mid-run\n")]) # pid dead, file lacks run_end

    entry = payload['runs'].first
    expect(entry['status']).to eq('interrupted — exit unknown')
    expect(entry['status']).not_to eq('running') # pid liveness is authoritative
  end

  it 'derives the status vocabulary: success / failed / running, with ended_at surfacing per entry' do
    write_run(run_name(sec: 10), [header_line(command: 'build', trigger: 'terminal', pid: DEAD_PID),
                                  body_line("ok\n"), run_end_line(0)])
    write_run(run_name(sec: 20), [header_line(command: 'use', trigger: 'terminal', pid: DEAD_PID),
                                  body_line("boom\n"), run_end_line(17)])
    write_run(run_name(sec: 30, pid: Process.pid),
              [header_line(command: 'watch', trigger: 'watch', pid: Process.pid),
               body_line("running\n")])

    by_run = payload['runs'].to_h { |entry| [entry['run'], entry] }
    expect(by_run[run_name(sec: 10)]['status']).to eq('success')
    expect(by_run[run_name(sec: 10)]['ended_at']).to eq('2026-09-01T09:31:00Z')
    expect(by_run[run_name(sec: 20)]['status']).to eq('failed') # non-zero exit
    expect(by_run[run_name(sec: 20)]['ended_at']).to eq('2026-09-01T09:31:00Z')
    expect(by_run[run_name(sec: 30)]['status']).to eq('running') # alive pid, no run_end
    expect(by_run[run_name(sec: 30)]['ended_at']).to be_nil
  end

  # -- 6/7/8. the D-12 listing + shapes ---------------------------------

  it 'lists D-12: newest-first, identity + derived status per entry, at most LIST_LIMIT (10)' do
    12.times do |i|
      write_run(run_name(sec: 30 + i),
                [header_line(command: i.even? ? 'build' : 'use', trigger: 'terminal', pid: DEAD_PID),
                 body_line("line #{i}\n"), run_end_line(i % 3)]) # mixed end states
    end

    runs = payload['runs']
    expect(runs.length).to eq(10) # LIST_LIMIT bound (discretion per 14-CONTEXT)
    expected = (30..41).map { |sec| run_name(sec: sec) }.last(10).reverse
    expect(runs.map { |entry| entry['run'] }).to eq(expected) # newest first
    newest = runs.first
    expect(newest).to include('run' => run_name(sec: 41), 'command' => 'use',
                              'trigger' => 'terminal', 'started_at' => '2026-09-01T09:30:00Z')
    expect(newest['status']).to eq('failed') # i=11 → run_end status 2
  end

  it 'answers the empty/absent-runs-dir shape: runs [], derived lock, ISO8601 now — never a raise' do
    result = payload # the runs dir does not exist at all (graph.rb guard shape)
    expect(result['runs']).to eq([])
    expect(result['lock']['state']).to eq('free') # no lock file either → idle
    expect(result['now']).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/)
  end

  it 'is String-keyed at every level: a JSON round-trip preserves everything' do
    write_run(run_name(sec: 30, pid: Process.pid),
              [header_line(command: 'build', trigger: 'terminal', pid: Process.pid),
               body_line("round trip\n")])

    # JSON.generate silently drops symbol keys (state.rb:44-53 lesson).
    expect(JSON.parse(JSON.generate(payload))).to eq(payload)
  end

  # -- 9. the route -------------------------------------------------------

  describe 'router mount (/api/runs)' do
    it 'token-gates GET /api/runs: 401 envelope without the token; the standard ok envelope with it' do
      Dir.mktmpdir('spm-cache-runs-mount') do |project|
        WebServerBoot.with_server(project_dir: project) do |handle|
          unauthorized = WebServerBoot.http_get(handle, '/api/runs')
          expect(unauthorized.code).to eq('401')
          expect(JSON.parse(unauthorized.body)['status']).to eq('error')

          authorized = WebServerBoot.http_get(handle, '/api/runs', 'X-SPM-Token' => handle.token)
          expect(authorized.code).to eq('200')
          body = JSON.parse(authorized.body)
          expect(body.keys).to contain_exactly('status', 'data', 'generated_at')
          expect(body['status']).to eq('ok')
          expect(body['data'].keys).to contain_exactly('runs', 'lock', 'now')
          expect(body['data']['runs']).to eq([]) # fresh project: empty listing
        end
      end
    end
  end
end
