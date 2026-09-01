# frozen_string_literal: true

# spec/fixtures/fake_spm_cache_bin.rb -- injectable stand-in for
# bin/spm-cache, run as [RbConfig.ruby, THIS_FILE, *argv] through
# Web::Jobs' bin_path: seam (15-01). Pure stdlib (json/fileutils/
# tempfile/time): it stands in for the CLI's process-boundary shape
# (argv/cwd/env/pgroup/stdio + a real run log), never exercises the
# gem. Lives under fixtures/, never a _spec file, so RSpec never loads
# it as a suite member.
#
# Contract (15-01-PLAN.md Task 1 behavior bullet):
#   - When ENV['FAKE_BIN_PROBE'] names a file path, appends one JSON
#     object recording exactly what THIS process actually received:
#     argv, cwd, the trigger env value, its own pid, its own pgid, and
#     whether stdout/stderr resolve to the null device (Web::Jobs' P7
#     null-stdio claim, verified from the child's own side -- proof
#     the parent's real stdout was never inherited).
#   - Writes a REAL run log into <cwd>/.spm-cache/runs, filename and
#     header shape matching Core::RunLog (run_log.rb:31,114-146) via
#     the same same-dir-Tempfile + File.rename publish so
#     Web::ReadModels::Runs / the tailer treat it exactly like any
#     other run -- never observing a run file before its header lands.
#   - Honors ENV['FAKE_BIN_SLEEP'] (seconds) as a pause between the
#     header and the run_end line -- the in-flight window the
#     integration rows assert against.

require 'json'
require 'fileutils'
require 'tempfile'
require 'time'

TIMESTAMP_FORMAT = '%Y-%m-%dT%H:%M:%SZ'
FILE_TIMESTAMP_FORMAT = '%Y%m%dT%H%M%S%3NZ'

command = ARGV.first || 'build'

if ENV['FAKE_BIN_PROBE']
  null_rdev = File.stat(File::NULL).rdev
  stdio_at_null = lambda do |io|
    io.stat.rdev == null_rdev
  rescue StandardError
    false
  end
  probe = {
    'argv' => ARGV,
    'pwd' => Dir.pwd,
    'trigger_env' => ENV['SPM_CACHE_TRIGGER'],
    'pid' => Process.pid,
    'pgid' => Process.getpgid(Process.pid),
    'stdout_null' => stdio_at_null.call($stdout),
    'stderr_null' => stdio_at_null.call($stderr)
  }
  File.open(ENV['FAKE_BIN_PROBE'], 'a') { |f| f.puts(JSON.generate(probe)) }
end

runs_dir = File.join(Dir.pwd, '.spm-cache', 'runs')
FileUtils.mkdir_p(runs_dir)

ts = Time.now.utc.strftime(TIMESTAMP_FORMAT)
base = "#{Time.now.utc.strftime(FILE_TIMESTAMP_FORMAT)}-#{Process.pid}-#{command}"
path = File.join(runs_dir, "#{base}.jsonl")
n = 0
while File.exist?(path)
  n += 1
  path = File.join(runs_dir, "#{base}-#{n}.jsonl")
end

# UI-origin normalization mirrors the seam 15-02 lands for real
# (main.rb:26): a whitelist, never a passthrough.
trigger = ENV['SPM_CACHE_TRIGGER'] == 'ui' ? 'ui' : 'terminal'

tmp = Tempfile.new(['run_start', '.tmp'], runs_dir)
tmp.write("#{JSON.generate(
  'event' => 'run_start', 'ts' => ts, 'command' => command, 'argv' => ARGV,
  'redacted' => false, 'pid' => Process.pid, 'started_at' => ts,
  'spm_cache_version' => 'fake', 'trigger' => trigger, 'cycle' => false
)}\n")
tmp.close
File.rename(tmp.path, path)

file = File.open(path, 'a')
file.sync = true

sleep_for = ENV['FAKE_BIN_SLEEP'].to_f
sleep(sleep_for) if sleep_for.positive?

file.puts(JSON.generate(
            'event' => 'run_end', 'ts' => Time.now.utc.strftime(TIMESTAMP_FORMAT),
            'status' => 0, 'ended_at' => Time.now.utc.strftime(TIMESTAMP_FORMAT)
          ))
file.close
