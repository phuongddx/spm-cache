# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'tmpdir'
require 'fileutils'
require 'rbconfig'

# Unit coverage for Web::Jobs (BLD-01, D-02/D-04/D-05, CP10): the spawn
# shape (array argv/cwd/env/pgroup/detach/null-stdio -- research P1-P8),
# the Mutex-atomic single slot (build+rollback share it, UI-SPEC A1),
# and the derive-based release (run_end authoritative, raw pid-liveness
# fallback for the pre-header window, never waitpid, never a monitoring
# thread). Hermetic: the 15-01 fake-bin fixture stands in for the real
# CLI (spec/fixtures/fake_spm_cache_bin.rb) -- no sockets, no real
# xcodebuild. Every claimed child is reaped in an ensure so no example
# leaks a process past the suite.
RSpec.describe SPMCache::Web::Jobs do
  FAKE_BIN_PATH = File.expand_path('fixtures/fake_spm_cache_bin.rb', __dir__)
  # A pid that is ESRCH by construction (events_tailer_spec.rb idiom,
  # run_log.rb:395-402's own probe posture).
  DEAD_PID = 999_999_999

  let(:project_dir) { Dir.mktmpdir('spm-cache-jobs') }
  let(:config) { SPMCache::Core::Config.instance }
  let(:runs_dir) { File.join(project_dir, '.spm-cache', 'runs') }
  let(:probe_file) { File.join(project_dir, 'probe.jsonl') }

  around do |example|
    previous_project_dir = config.project_dir
    previous_probe = ENV.fetch('FAKE_BIN_PROBE', nil)
    SPMCache::Core::Config.configure(project_dir: project_dir)
    config.reset!
    ENV['FAKE_BIN_PROBE'] = probe_file
    example.run
  ensure
    ENV.delete('FAKE_BIN_SLEEP')
    if previous_probe
      ENV['FAKE_BIN_PROBE'] = previous_probe
    else
      ENV.delete('FAKE_BIN_PROBE')
    end
    config.reset!
    SPMCache::Core::Config.configure(project_dir: previous_project_dir)
    FileUtils.rm_rf(project_dir)
  end

  def jobs(bin_path: FAKE_BIN_PATH)
    described_class.new(config: config, bin_path: bin_path)
  end

  def probe_entries
    return [] unless File.exist?(probe_file)

    File.readlines(probe_file).map { |line| JSON.parse(line) }
  end

  # spawn_run returns to the caller the instant Process.detach is
  # called, well before the child has booted far enough to write its
  # probe line -- bounded poll for the entry AT index (captured BEFORE
  # the spawn) rather than reading probe_entries.last immediately.
  def wait_for_probe_entry(index, timeout: 5)
    deadline = Time.now + timeout
    loop do
      entry = probe_entries[index]
      return entry if entry
      return nil if Time.now > deadline

      sleep 0.02
    end
  end

  # Bounded reap: never an unbounded wait, never leaked past an example.
  def wait_for_pid_exit(pid, timeout: 5)
    return unless pid

    deadline = Time.now + timeout
    loop do
      Process.kill(0, pid)
      break if Time.now > deadline

      sleep 0.02
    rescue Errno::ESRCH
      break
    end
  end

  # A hand-authored run file (run_log.rb filename + line-shape
  # convention) for the derive-based release rows -- deterministic,
  # no dependency on real process timing.
  def write_run(pid:, command: 'build', trigger: 'ui', run_end: nil)
    FileUtils.mkdir_p(runs_dir)
    ts = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
    name = "#{Time.now.utc.strftime('%Y%m%dT%H%M%S%3NZ')}-#{pid}-#{command}.jsonl"
    path = File.join(runs_dir, name)
    lines = [JSON.generate('event' => 'run_start', 'ts' => ts, 'command' => command,
                           'argv' => [command], 'redacted' => false, 'pid' => pid,
                           'started_at' => ts, 'spm_cache_version' => 'test',
                           'trigger' => trigger, 'cycle' => false)]
    lines << JSON.generate('event' => 'run_end', 'ts' => ts, 'status' => run_end, 'ended_at' => ts) if run_end
    File.write(path, lines.map { |l| "#{l}\n" }.join)
    path
  end

  it 'records exactly [ruby interpreter, bin_path, "build"] -- the frozen table fragments, nothing from the request' do
    pid = nil
    captured = nil
    allow(Process).to receive(:spawn).and_wrap_original do |original, env, *rest, **kwargs|
      captured = rest
      original.call(env, *rest, **kwargs)
    end
    pid = jobs.spawn_run(scope: 'build')
    expect(pid).not_to be_nil
    expect(captured).to eq([RbConfig.ruby, FAKE_BIN_PATH, 'build'])
  ensure
    wait_for_pid_exit(pid)
  end

  it 'merges SPM_CACHE_TRIGGER=ui onto the inherited parent env, and adds no token-shaped variable' do
    pid = nil
    ENV['SPM_CACHE_JOBS_SPEC_SENTINEL'] = 'present'
    captured_env = nil
    allow(Process).to receive(:spawn).and_wrap_original do |original, env, *rest, **kwargs|
      captured_env = env
      original.call(env, *rest, **kwargs)
    end
    pid = jobs.spawn_run(scope: 'build')
    expect(pid).not_to be_nil
    expect(captured_env['SPM_CACHE_TRIGGER']).to eq('ui')
    expect(captured_env['SPM_CACHE_JOBS_SPEC_SENTINEL']).to eq('present')
    expect(captured_env.keys.grep(/token/i)).to be_empty
  ensure
    ENV.delete('SPM_CACHE_JOBS_SPEC_SENTINEL')
    wait_for_pid_exit(pid)
  end

  it 'spawns with cwd = the configured project_dir, not the spec process cwd' do
    pid = nil
    before_count = probe_entries.length
    pid = jobs.spawn_run(scope: 'build')
    expect(pid).not_to be_nil
    entry = wait_for_probe_entry(before_count)
    expect(entry).not_to be_nil
    expect(File.realpath(entry['pwd'])).to eq(File.realpath(project_dir))
    expect(File.realpath(entry['pwd'])).not_to eq(File.realpath(Dir.pwd))
  ensure
    wait_for_pid_exit(pid)
  end

  it 'spawns as its own process-group leader (pgid == own pid, P1)' do
    pid = nil
    before_count = probe_entries.length
    pid = jobs.spawn_run(scope: 'build')
    expect(pid).not_to be_nil
    entry = wait_for_probe_entry(before_count)
    expect(entry).not_to be_nil
    expect(entry['pid']).to eq(pid)
    expect(entry['pgid']).to eq(pid)
  ensure
    wait_for_pid_exit(pid)
  end

  it 'redirects stdout/stderr to the null device (P7) -- confirmed from the child\'s own side' do
    pid = nil
    before_count = probe_entries.length
    pid = jobs.spawn_run(scope: 'build')
    expect(pid).not_to be_nil
    entry = wait_for_probe_entry(before_count)
    expect(entry).not_to be_nil
    expect(entry['stdout_null']).to eq(true)
    expect(entry['stderr_null']).to eq(true)
  ensure
    wait_for_pid_exit(pid)
  end

  it 'is Mutex-atomic under real thread contention: 8 concurrent claims produce exactly one spawn (Pitfall 1)' do
    non_nil = []
    ENV['FAKE_BIN_SLEEP'] = '2' # held open for the whole race window
    j = jobs
    results = Array.new(8)
    threads = Array.new(8) { |i| Thread.new { results[i] = j.spawn_run(scope: 'build') } }
    threads.each(&:join)
    non_nil = results.compact
    expect(non_nil.length).to eq(1)
    expect(results.count(&:nil?)).to eq(7)
    wait_for_probe_entry(0)
    expect(probe_entries.length).to eq(1)
  ensure
    ENV.delete('FAKE_BIN_SLEEP')
    wait_for_pid_exit(non_nil.first)
  end

  it 'is verb-agnostic: a claim for any other scope in the table is refused the same way while the slot is held (UI-SPEC A1)' do
    stub_const('SPMCache::Web::Jobs::SCOPES', { 'build' => ['build'], 'rollback' => ['rollback'] }.freeze)
    first_pid = nil
    ENV['FAKE_BIN_SLEEP'] = '2'
    j = jobs
    first_pid = j.spawn_run(scope: 'build')
    expect(first_pid).not_to be_nil
    second = j.spawn_run(scope: 'rollback')
    expect(second).to be_nil
  ensure
    ENV.delete('FAKE_BIN_SLEEP')
    wait_for_pid_exit(first_pid)
  end

  it 'frees the slot on the next claim once the run log carries run_end -- derived, never remembered, never waitpid' do
    first_pid = nil
    second_pid = nil
    ENV['FAKE_BIN_SLEEP'] = '5' # still genuinely alive when we probe
    j = jobs
    before_count = probe_entries.length
    first_pid = j.spawn_run(scope: 'build')
    expect(first_pid).not_to be_nil
    wait_for_probe_entry(before_count)
    run_path = Dir.glob(File.join(runs_dir, "*-#{first_pid}-build.jsonl")).first
    expect(run_path).not_to be_nil

    # Hand-append run_end while the process is still genuinely alive
    # (sleeping) -- the NEXT claim must be decided by the log, not by
    # Process.kill(0, pid).
    File.open(run_path, 'a') do |f|
      f.puts(JSON.generate('event' => 'run_end', 'ts' => Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'),
                           'status' => 0, 'ended_at' => Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')))
    end
    expect { Process.kill(0, first_pid) }.not_to raise_error # sanity: really still alive

    second_pid = j.spawn_run(scope: 'build')
    expect(second_pid).not_to be_nil
    expect(second_pid).not_to eq(first_pid)
  ensure
    ENV.delete('FAKE_BIN_SLEEP')
    # first_pid is still sleeping and no longer under any slot -- TERM
    # its group directly so it never leaks past the example.
    begin
      Process.kill('-TERM', first_pid) if first_pid
    rescue Errno::ESRCH, Errno::EPERM
      nil
    end
    wait_for_pid_exit(first_pid)
    wait_for_pid_exit(second_pid)
  end

  it 'frees a claim via the raw pid probe before any run file exists for it, and never wedges on a header-mismatched file' do
    pid = nil
    second_pid = nil
    j = jobs

    # Case a: the slot references a dead pid with NO run file at all
    # yet (the pre-header spawn window's fallback) -- the raw probe
    # frees it immediately.
    j.instance_variable_set(:@slot, { pid: DEAD_PID, scope: 'build' })
    pid = j.spawn_run(scope: 'build')
    expect(pid).not_to be_nil
    wait_for_pid_exit(pid)

    # Case b: a run file exists in the runs dir, but its header pid
    # never matches the claimed (dead) pid -- derive_for_pid correctly
    # finds nothing attributable, and the raw-probe fallback still
    # frees the slot instead of wedging forever.
    write_run(pid: pid, command: 'build', trigger: 'ui', run_end: 0)
    j.instance_variable_set(:@slot, { pid: DEAD_PID, scope: 'build' })
    second_pid = j.spawn_run(scope: 'build')
    expect(second_pid).not_to be_nil
  ensure
    wait_for_pid_exit(pid)
    wait_for_pid_exit(second_pid)
  end
end
