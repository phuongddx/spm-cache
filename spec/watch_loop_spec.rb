# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'timeout'
require 'rbconfig'

require 'spm_cache/core/watcher'

# Self-contained child for loop-contract examples: builds the fixture
# project (mirroring spec/watch_spec.rb:30-44, plus the also-watched
# project.pbxproj) and runs the REAL Core::Watcher#run with one of three
# installers selected by mode:
#   self_write — appends a marker line AND one byte to the watched
#     project.pbxproj, faithfully modeling the unconditional project.save
#     at installer.rb:468 rewriting the watched file on every regeneration.
#   record — records the byte size of Package.resolved at install time.
#   verify — appends a marker line, then raises unless the watched
#     Package.resolved still exists (models verify_projects! failing
#     after a mid-watch deletion).
LOOP_CHILD_SCRIPT = <<~'RUBY'
  # frozen_string_literal: true

  require 'fileutils'
  require 'spm_cache/core/watcher'

  project_dir = ARGV[0]
  marker_path = ARGV[1]
  debounce = Float(ARGV[2])
  mode = ARGV[3]

  proj = File.join(project_dir, 'App.xcodeproj')
  swiftpm = File.join(proj, 'project.xcworkspace/xcshareddata/swiftpm')
  FileUtils.mkdir_p(swiftpm)
  resolved = File.join(swiftpm, 'Package.resolved')
  pbxproj = File.join(proj, 'project.pbxproj')
  File.write(resolved, '{"pins":[],"version":1}')
  File.write(pbxproj, "// !$*UTF8*$!\n")

  class SelfWritingInstaller
    def initialize(marker_path, pbxproj)
      @marker_path = marker_path
      @pbxproj = pbxproj
    end

    def perform_install
      File.open(@marker_path, 'a') { |f| f.puts 'install' }
      File.open(@pbxproj, 'a') { |f| f.write ' ' }
    end
  end

  class RecordingInstaller
    def initialize(marker_path, resolved)
      @marker_path = marker_path
      @resolved = resolved
    end

    def perform_install
      File.open(@marker_path, 'a') { |f| f.puts "install:#{File.binread(@resolved).bytesize}" }
    end
  end

  class VerifyingInstaller
    def initialize(marker_path, resolved)
      @marker_path = marker_path
      @resolved = resolved
    end

    def perform_install
      File.open(@marker_path, 'a') { |f| f.puts 'install' }
      raise StandardError, 'project gone' unless File.exist?(@resolved)
    end
  end

  installer = {
    'self_write' => SelfWritingInstaller.new(marker_path, pbxproj),
    'record' => RecordingInstaller.new(marker_path, resolved),
    'verify' => VerifyingInstaller.new(marker_path, resolved)
  }.fetch(mode)

  SPMCache::Core::Watcher.new(
    project_path: proj,
    installer_factory: ->(_path) { installer },
    debounce: debounce
  ).run
RUBY

# Subprocess loop-contract specs for the real Watcher#run (self-trigger
# guard, burst collapse, mid-watch deletion). Same harness rules as
# spec/watch_signals_spec.rb: the loop is never run inside the RSpec
# process; every child interaction is bounded by Timeout.timeout(15) with
# a KILL fallback.
RSpec.describe 'SPMCache::Core::Watcher loop contract (subprocess)' do
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

  def wait_for_marker(count)
    deadline = Time.now + 10
    until marker_lines.size >= count
      raise "child never wrote #{count} marker line(s); saw #{marker_lines.size}" if Time.now > deadline

      sleep 0.05
    end
  end

  def with_watcher_child(debounce, mode)
    File.write(script_path, LOOP_CHILD_SCRIPT)
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

  it 'never re-triggers on its own regeneration writes (self-trigger guard)' do
    exitstatus, = with_watcher_child(0.3, 'self_write') do |pid|
      # Initial regenerate + snapshot complete.
      wait_for_marker(1)

      # >= 6 poll windows with no external edits. Pre-fix, the installer's
      # own pbxproj write looks like a change every window (the snapshot
      # precedes regenerate), so the marker grows ~1 per window.
      sleep 2.5

      Process.kill('TERM', pid)
    end

    expect(exitstatus).to eq(0)
    expect(marker_lines).to eq(['install'])
  end

  it 'collapses a burst of saves within one poll window into one regeneration using the final state' do
    exitstatus, = with_watcher_child(0.5, 'record') do |pid|
      wait_for_marker(1)

      # Three rapid writes of increasing size inside one 0.5s window. Size
      # varies, so the coarse mtime component is irrelevant.
      %w[x xx xxx].each do |pad|
        File.write(resolved_path, "{\"pins\":[],\"pad\":\"#{pad}\",\"version\":1}")
      end

      # >= 3 poll windows for the change to be seen (and to prove no
      # further regeneration follows).
      sleep 2

      Process.kill('TERM', pid)
    end

    expect(exitstatus).to eq(0)
    # One regeneration for the burst, using the FINAL file state — the
    # last event of a burst is never dropped.
    expect(marker_lines.size).to eq(2)
    expect(marker_lines.last).to eq("install:#{File.binread(resolved_path).bytesize}")
  end

  it 'logs a mid-watch deletion once as transient and idles without busy-looping' do
    exitstatus, stdout = with_watcher_child(0.3, 'verify') do |pid|
      wait_for_marker(1)

      File.delete(resolved_path)

      # >= 4 poll windows: exactly one deletion-triggered attempt is
      # expected, then the loop idles (nil signatures compare equal).
      sleep 1.5

      Process.kill('TERM', pid)
    end

    expect(exitstatus).to eq(0)
    expect(marker_lines.size).to eq(2)
    expect(stdout).to include('[watch] integration failed')
  end
end
