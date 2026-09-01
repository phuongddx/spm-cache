# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'tmpdir'
require 'fileutils'
require 'timeout'
require 'rbconfig'

# WEB-03 against a REAL spawned process (the phase's real-process e2e,
# watch_signals_spec.rb scaffold reused in spirit): a child running the
# actual `spm-cache web --no-open --port=0` in a tmpdir project must
# publish a live marker, and SIGTERM/SIGINT must stop the server, remove
# the marker, and exit 0. SIGKILL leaves an honest stale marker that
# WEB_CHILD_SCRIPT is uniquely named: watch_signals_spec.rb defines a
# top-level CHILD_SCRIPT for its own children, and a same-named constant
# here would silently replace it once both files load -- each spec's
# children would run the other's script.
WEB_CHILD_SCRIPT = <<~'RUBY'
  # frozen_string_literal: true

  require 'spm_cache/main'

  Dir.chdir(ARGV[0])
  SPMCache::Main.run(['web', '--no-open', '--port=0'])
RUBY

RSpec.describe 'spm-cache web signal contract (real subprocess)' do
  let(:tmpdir) { Dir.mktmpdir }
  let(:project_dir) { File.join(tmpdir, 'proj') }
  let(:marker_path) { File.join(project_dir, '.spm-cache', 'web', 'server.json') }
  let(:script_path) { File.join(tmpdir, 'child.rb') }
  let(:stdout_path) { File.join(tmpdir, 'child-stdout.log') }
  let(:stderr_path) { File.join(tmpdir, 'child-stderr.log') }

  before { FileUtils.mkdir_p(project_dir) }

  after { FileUtils.remove_entry(tmpdir) if File.directory?(tmpdir) }

  def with_web_child
    File.write(script_path, WEB_CHILD_SCRIPT)
    pid = Process.spawn(
      RbConfig.ruby, '-I', File.expand_path('lib', SPMCache::ROOT),
      script_path, project_dir,
      out: stdout_path, err: stderr_path
    )
    Timeout.timeout(30) do
      yield pid
      _pid, status = Timeout.timeout(10) { Process.wait2(pid) }
      status
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

  # Bounded wait: the child writes the marker only after the port probe
  # and server construction -- its existence means serving is imminent.
  def wait_for_marker
    deadline = Time.now + 15
    until File.exist?(marker_path)
      raise "child never wrote its marker; stderr: #{File.read(stderr_path)[0, 500]}" if Time.now > deadline

      sleep 0.05
    end
    JSON.parse(File.read(marker_path))
  end

  it 'SIGTERM: exits 0 and removes the marker' do
    status = with_web_child do |pid|
      marker = wait_for_marker
      expect(marker['pid']).to eq(pid)
      expect(marker['port']).to be > 0
      expect(SPMCache::Web::Marker.live?(marker)).to be(true)
      Process.kill('TERM', pid)
    end

    expect(status.exitstatus).to eq(0)
    expect(File.exist?(marker_path)).to be(false)
  end

  it 'SIGINT: exits 0 and removes the marker' do
    status = with_web_child do |pid|
      wait_for_marker
      Process.kill('INT', pid)
    end

    expect(status.exitstatus).to eq(0)
    expect(File.exist?(marker_path)).to be(false)
  end

  it 'SIGKILL: leaves an honest stale marker that reads dead' do
    with_web_child do |pid|
      wait_for_marker
      Process.kill('KILL', pid)
    end

    expect(File.exist?(marker_path)).to be(true)
    expect(SPMCache::Web::Marker.live?(SPMCache::Web::Marker.read(path: marker_path))).to be(false)
  end
end
