# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'timeout'
require 'rbconfig'

require 'spm_cache/core/watcher'

# Self-contained child: builds the fixture project (mirroring
# spec/watch_spec.rb:30-44, plus the also-watched project.pbxproj),
# wires an inline FakeInstaller that appends one marker line per
# perform_install, and runs the REAL Core::Watcher#run.
CHILD_SCRIPT = <<~'RUBY'
  # frozen_string_literal: true

  require 'fileutils'
  require 'spm_cache/core/watcher'

  project_dir = ARGV[0]
  marker_path = ARGV[1]
  debounce = Float(ARGV[2])
  mode = ARGV[3] # 'ok' | 'fail' | 'slow' | 'fail_flush'

  proj = File.join(project_dir, 'App.xcodeproj')
  swiftpm = File.join(proj, 'project.xcworkspace/xcshareddata/swiftpm')
  FileUtils.mkdir_p(swiftpm)
  File.write(File.join(swiftpm, 'Package.resolved'), '{"pins":[],"version":1}')
  File.write(File.join(proj, 'project.pbxproj'), "// !$*UTF8*$!\n")

  class FakeInstaller
    def initialize(marker_path, mode)
      @marker_path = marker_path
      @mode = mode
    end

    def perform_install
      raise StandardError, 'simulated build failure' if @mode == 'fail'

      if @mode == 'fail_flush' && marker_count >= 1
        raise StandardError, 'simulated flush-time build failure'
      end

      sleep 3 if @mode == 'slow'
      File.open(@marker_path, 'a') { |f| f.puts 'install' }
    end

    private

    # Failure is keyed off the marker file (persisted state), not
    # instance state — mirrors how each real regeneration observes
    # on-disk state rather than memory of prior runs.
    def marker_count
      return 0 unless File.exist?(@marker_path)

      File.readlines(@marker_path).count { |l| !l.strip.empty? }
    end
  end

  installer = FakeInstaller.new(marker_path, mode)
  SPMCache::Core::Watcher.new(
    project_path: proj,
    installer_factory: ->(_path) { installer },
    debounce: debounce
  ).run
RUBY

# Subprocess harness for signal-testing the real Watcher#run loop.
#
# Watcher#run must NEVER be invoked inside the RSpec process: Signal.trap
# (installed by #run) would leak into the runner and interfere with the
# suite's own INT handling (Phase 5 RESEARCH, Pitfall 5). Each example
# writes the child script to a tmpdir, spawns it with the repo's lib/ on
# the load path, synchronizes on a marker file, sends a signal, and
# asserts the child's exit status + captured stdout. Every child
# interaction is bounded by Timeout.timeout(15) with a KILL fallback, so
# a watcher bug fails the example instead of hanging the suite.
RSpec.describe 'SPMCache::Core::Watcher signal handling (subprocess)' do
  let(:tmpdir) { Dir.mktmpdir }
  let(:project_dir) { File.join(tmpdir, 'proj') }
  let(:marker_path) { File.join(tmpdir, 'marker.log') }
  let(:stdout_path) { File.join(tmpdir, 'child-stdout.log') }
  let(:script_path) { File.join(tmpdir, 'child.rb') }
  let(:resolved_path) do
    File.join(project_dir, 'App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved')
  end

  before { FileUtils.mkdir_p(project_dir) }

  after { FileUtils.remove_entry(tmpdir) if File.directory?(tmpdir) }

  def marker_lines
    return [] unless File.exist?(marker_path)

    File.readlines(marker_path).map(&:strip).reject(&:empty?)
  end

  # Bounded wait for the child's initial install marker. The marker only
  # appears once the initial regenerate runs, and the pre-regenerate
  # signature snapshot precedes it — so waiting for line 1 also proves the
  # snapshot is in place.
  def wait_for_marker(count)
    deadline = Time.now + 10
    until marker_lines.size >= count
      raise "child never wrote #{count} marker line(s); saw #{marker_lines.size}" if Time.now > deadline

      sleep 0.05
    end
  end

  # Spawn the child running the real Watcher#run; yield the pid; return
  # [exitstatus, stdout]. The ensure block KILLs and reaps the child so no
  # example can hang the suite.
  def with_watcher_child(debounce, mode: 'ok')
    File.write(script_path, CHILD_SCRIPT)
    pid = Process.spawn(
      RbConfig.ruby, '-I', File.expand_path('lib', SPMCache::ROOT),
      script_path, project_dir, marker_path, debounce.to_s, mode,
      out: stdout_path, err: File::NULL
    )
    Timeout.timeout(15) do
      yield pid
      _pid, status = Process.wait2(pid)
      [status.exitstatus, File.read(stdout_path)]
    end
  ensure
    if pid
      begin
        Process.kill('KILL', pid)
        Process.wait(pid)
      rescue Errno::ESRCH, Errno::ECHILD
        # Already exited and reaped.
      end
    end
  end

  it 'exits 0 with "[watch] stopped." on SIGTERM' do
    exitstatus, stdout = with_watcher_child(5) do |pid|
      wait_for_marker(1)
      Process.kill('TERM', pid)
    end

    expect(exitstatus).to eq(0)
    expect(stdout).to include('[watch] stopped.')
  end

  it 'exits 0 with "[watch] stopped." on SIGINT' do
    exitstatus, stdout = with_watcher_child(5) do |pid|
      wait_for_marker(1)
      Process.kill('INT', pid)
    end

    expect(exitstatus).to eq(0)
    expect(stdout).to include('[watch] stopped.')
  end

  it 'flushes a pending change on interrupt before exiting 0' do
    exitstatus, stdout = with_watcher_child(5) do |pid|
      wait_for_marker(1)

      # Different-size content: the [path, mtime.to_i, size] signature
      # differs on size alone — no mtime sleep needed.
      File.write(resolved_path, '{"pins":[{"identity":"FlushedDep"}],"version":1}')

      # Well inside the 5s debounce window: the change is pending, not yet
      # polled, when the interrupt lands.
      Process.kill('INT', pid)
    end

    expect(exitstatus).to eq(0)
    expect(stdout).to include('[watch] stopped.')
    # Initial install + the flushed pending change — never silently dropped.
    expect(marker_lines).to eq(%w[install install])
  end


  it 'completes the flush and exits 0 when a second signal lands mid-flush' do
    exitstatus, stdout = with_watcher_child(5, mode: 'slow') do |pid|
      wait_for_marker(1)

      # Different-size content: the [path, mtime.to_i, size] signature
      # differs on size alone — no mtime sleep needed.
      File.write(resolved_path, '{"pins":[{"identity":"FlushedDep"}],"version":1}')

      # Interrupt: the flush's slow (3s) regenerate is now in flight.
      Process.kill('INT', pid)
      sleep 0.5
      # Second signals mid-flush must not abort the flush or kill the
      # child (classic double-Ctrl-C, or Ctrl-C then supervisor TERM).
      Process.kill('TERM', pid)
      Process.kill('INT', pid)
    end

    expect(exitstatus).to eq(0)
    expect(stdout).to include('[watch] stopped.')
    # Initial install + the flushed pending change — the flush completed
    # despite the second signal.
    expect(marker_lines).to eq(%w[install install])
  end

  it 'logs a failing flush and still exits 0' do
    exitstatus, stdout = with_watcher_child(5, mode: 'fail_flush') do |pid|
      wait_for_marker(1)

      # Pending change; the flush-time install raises (marker already
      # has the initial line), pinning the flush-failure branch of
      # flush_pending_event.
      File.write(resolved_path, '{"pins":[{"identity":"FlushedDep"}],"version":1}')
      Process.kill('INT', pid)
    end

    expect(exitstatus).to eq(0)
    expect(stdout).to include('[watch] flush failed')
    expect(stdout).to include('[watch] stopped.')
    expect(marker_lines).to eq(%w[install])
  end

  it 'exits 1 with "[watch] fatal:" when the initial install fails' do
    exitstatus, stdout = with_watcher_child(5, mode: 'fail') do |pid|
      # No marker to wait for: the initial regenerate raises before any
      # install is recorded.
    end

    expect(exitstatus).to eq(1)
    expect(stdout).to include('[watch] fatal:')
  end
end
