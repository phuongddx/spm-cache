# frozen_string_literal: true

require 'spec_helper'
require 'claide'
require 'json'
require 'time'
require 'tmpdir'
require 'fileutils'
require 'stringio'
require 'socket'

# web_signals_spec (Task 3) own sockets; the prober's own examples below
# bind raw TCPServers only.
class ServerSpy
  attr_reader :kwargs, :start_count, :shutdown_count, :term_handler, :int_handler,
              :callback_fired_during_start

  def initialize(kwargs)
    @kwargs = kwargs
    @start_count = 0
    @shutdown_count = 0
  end

  def callback
    @kwargs[:start_callback]
  end

  def start
    @start_count += 1
    # Read (and reset) the installed traps the way the OS would deliver
    # them later; a real signal fires the proc.
    @term_handler = Signal.trap('TERM', 'DEFAULT')
    @int_handler = Signal.trap('INT', 'DEFAULT')
    @callback_fired_during_start = false
    @kwargs[:start_callback]&.call
    @callback_fired_during_start = true
  end

  def shutdown
    @shutdown_count += 1
  end
end

RSpec.describe SPMCache::Web::Marker do
  let(:tmpdir) { Dir.mktmpdir }
  let(:marker_path) { File.join(tmpdir, 'nested', 'web', 'server.json') }

  after { FileUtils.remove_entry(tmpdir) if File.directory?(tmpdir) }

  describe '.write / .read' do
    it 'creates parent dirs and writes pid/port/token/started_at at mode 0600' do
      described_class.write(path: marker_path, pid: 4242, port: 7915, token: 'a' * 64)

      expect(File.stat(marker_path).mode & 0o777).to eq(0o600)
      entry = described_class.read(path: marker_path)
      expect(entry['pid']).to eq(4242)
      expect(entry['port']).to eq(7915)
      expect(entry['token']).to eq('a' * 64)
      expect(Time.iso8601(entry['started_at'])).to be_a(Time)
    end

    it 'returns nil for an absent marker' do
      expect(described_class.read(path: marker_path)).to be_nil
    end

    it 'returns nil for malformed JSON' do
      FileUtils.mkdir_p(File.dirname(marker_path))
      File.write(marker_path, '{oops')
      expect(described_class.read(path: marker_path)).to be_nil
    end

    it 'returns nil for a pre-planted symlink at the marker path (T-13-05)' do
      FileUtils.mkdir_p(File.dirname(marker_path))
      target = File.join(tmpdir, 'real.json')
      File.write(target, JSON.generate('pid' => 1))
      File.symlink(target, marker_path)
      expect(described_class.read(path: marker_path)).to be_nil
    end

    it 'replaces a planted symlink on write instead of writing through it' do
      FileUtils.mkdir_p(File.dirname(marker_path))
      target = File.join(tmpdir, 'real.json')
      File.write(target, JSON.generate('pid' => 1))
      File.symlink(target, marker_path)

      described_class.write(path: marker_path, pid: 99, port: 80, token: 't')

      expect(File.symlink?(marker_path)).to be(false)
      expect(File.read(target)).not_to include('"pid" => ') # target untouched
      expect(described_class.read(path: marker_path)['pid']).to eq(99)
    end
  end

  describe '.live?' do
    it 'is true only for a parseable, alive pid' do
      expect(described_class.live?({ 'pid' => Process.pid })).to be(true)
    end

    it 'is false for a dead pid (Errno::ESRCH)' do
      expect(described_class.live?({ 'pid' => 2_000_000_000 })).to be(false)
    end

    it 'is false for a non-integer, missing, or nil entry' do
      expect(described_class.live?({ 'pid' => 'abc' })).to be(false)
      expect(described_class.live?({})).to be(false)
      expect(described_class.live?(nil)).to be(false)
    end
  end

  describe '.clear' do
    it 'unlinks a present marker and no-ops on an absent one' do
      described_class.write(path: marker_path, pid: 1, port: 2, token: 'x')
      described_class.clear(path: marker_path)
      expect(File.exist?(marker_path)).to be(false)
      expect { described_class.clear(path: marker_path) }.not_to raise_error
    end

    it 'refuses to clear a marker owned by another pid (review WR-02)' do
      described_class.write(path: marker_path, pid: Process.pid, port: 4242, token: 'x')
      described_class.clear(path: marker_path, pid: Process.pid + 1)
      expect(File.exist?(marker_path)).to be(true)
    end

    it 'clears when the given pid matches or is omitted' do
      described_class.write(path: marker_path, pid: 4242, port: 2, token: 'x')
      described_class.clear(path: marker_path, pid: 4242)
      expect(File.exist?(marker_path)).to be(false)
      described_class.write(path: marker_path, pid: 4242, port: 2, token: 'x')
      described_class.clear(path: marker_path)
      expect(File.exist?(marker_path)).to be(false)
    end
  end
end

RSpec.describe SPMCache::Web::PortProber do
  after do
    @held&.close
  end

  def hold_port(port)
    @held = TCPServer.new('127.0.0.1', port)
  end

  def first_free_port
    probe = TCPServer.new('127.0.0.1', 0)
    port = probe.addr[1]
    probe.close
    port
  end

  it 'skips AirPlay 5000/7000 unconditionally and defaults to 7915 (CP9)' do
    expect(described_class::SKIP_PORTS).to eq([5000, 7000])
    expect(described_class::DEFAULT_START_PORT).to eq(7915)
  end

  it 'never binds 5000: probing from a held 4999 with 2 attempts exhausts' do
    hold_port(4999)
    expect { described_class.pick(start_port: 4999, attempts: 2) }
      .to raise_error(SPMCache::Core::GeneralError, %r{\[4999, 5001\).*5000/7000})
  end

  it 'probes upward past an occupied port' do
    port = first_free_port
    hold_port(port)
    expect(described_class.pick(start_port: port, attempts: 3)).to eq(port + 1)
  end

  it 'raises with the tried range after consecutive failures' do
    port = first_free_port
    hold_port(port)
    second = TCPServer.new('127.0.0.1', port + 1)
    begin
      expect { described_class.pick(start_port: port, attempts: 2) }
        .to raise_error(SPMCache::Core::GeneralError, /\[#{port}, #{port + 2}\)/)
    ensure
      second.close
    end
  end
end

RSpec.describe SPMCache::Command::Web do
  let(:tmpdir) { Dir.mktmpdir }
  let(:marker_path) { File.join(tmpdir, '.spm-cache', 'web', 'server.json') }
  let(:spies) { [] }

  around do |example|
    # Command::Web installs/masks TERM+INT traps; save and restore them
    # so the suite runner keeps its own signal handling.
    saved = %w[TERM INT].to_h { |sig| [sig, Signal.trap(sig, 'DEFAULT')] }
    original_project_dir = SPMCache::Core::Config.instance.project_dir
    SPMCache::Core::Config.configure(project_dir: tmpdir)
    example.run
  ensure
    SPMCache::Core::Config.configure(project_dir: original_project_dir)
    SPMCache::Core::Config.instance.reset!
    saved.each { |sig, handler| Signal.trap(sig, handler) if handler }
    FileUtils.remove_entry(tmpdir) if File.directory?(tmpdir)
  end

  before do
    # Default-deny: any unexpected shell-out (e.g. a browser open the
    # example did not opt into) fails the example loudly.
    allow(SPMCache::Core::Sh).to receive(:run)
      .and_raise(SPMCache::Core::GeneralError.new('unexpected shell-out'))
    allow(SPMCache::Web::Server).to receive(:new) do |**kwargs|
      spy = ServerSpy.new(kwargs)
      spies << spy
      spy
    end
  end

  def record_sh_calls!
    calls = []
    allow(SPMCache::Core::Sh).to receive(:run) { |cmd, *_| calls << cmd }
    calls
  end

  def run_web(*args)
    out = StringIO.new
    original = $stdout
    $stdout = out
    begin
      described_class.new(CLAide::ARGV.new(args)).run
    ensure
      $stdout = original
    end
    out.string
  end

  describe 'idempotent relaunch (WEB-02)' do
    it 'prints the running URL, reuses, and never constructs a server' do
      SPMCache::Web::Marker.write(path: marker_path, pid: Process.pid, port: 4242,
                                  token: 'secrettokenshouldnotprint')
      before_bytes = File.read(marker_path)

      stdout = run_web('--no-open')

      expect(stdout).to include('http://127.0.0.1:4242')
      expect(stdout).to include('already running')
      expect(stdout).not_to include('secrettokenshouldnotprint')
      expect(spies).to be_empty
      expect(File.read(marker_path)).to eq(before_bytes) # marker untouched
    end

    it 'opens the browser on reuse when not suppressed' do
      SPMCache::Web::Marker.write(path: marker_path, pid: Process.pid, port: 4242, token: 't')
      calls = record_sh_calls!

      run_web

      expect(calls).to eq(['open http://127.0.0.1:4242'])
    end
  end

  describe 'stale marker heals into a fresh launch' do
    it 'clears the stale marker, starts a server, writes a fresh marker, clears on exit' do
      SPMCache::Web::Marker.write(path: marker_path, pid: 2_000_000_000, port: 1, token: 'dead')

      run_web('--no-open')

      expect(spies.size).to eq(1)
      expect(spies.first.start_count).to eq(1)
      expect(File.exist?(marker_path)).to be(false) # ensure cleared it
    end

    it 'writes the fresh marker with this pid, the served port, and a 64-hex token' do
      captured = nil
      allow(SPMCache::Web::Marker).to receive(:write).and_wrap_original do |method, **kwargs|
        captured = kwargs
        method.call(**kwargs)
      end

      run_web('--no-open')

      expect(captured[:pid]).to eq(Process.pid)
      expect(captured[:port]).to eq(spies.first.kwargs[:port])
      expect(captured[:port]).to be >= 1024
      expect(captured[:token]).to match(/\A[0-9a-f]{64}\z/)
    end
  end

  describe 'browser open (fresh start)' do
    it 'opens exactly once, fired only by the server-ready callback (CP12)' do
      calls = record_sh_calls!

      run_web

      spy = spies.first
      expect(spy.callback).to be_a(Proc)
      # The only open path is the StartCallback, which fires inside
      # start (i.e. after the server is ready) -- never before it.
      expect(spy.callback_fired_during_start).to be(true)
      expect(calls).to eq(["open http://127.0.0.1:#{spy.kwargs[:port]}"])
    end

    it 'never sends the token to the shell or stdout' do
      calls = record_sh_calls!
      stdout = run_web

      expect(calls.first).not_to include('token')
      expect(stdout).not_to include('token=')
    end

    it 'is suppressed by --no-open' do
      calls = record_sh_calls!

      run_web('--no-open')

      expect(calls).to be_empty
      expect(spies.first.callback).to be_nil
    end

    it 'degrades to a warn when open fails; the server keeps running' do
      err = StringIO.new
      original = $stderr
      $stderr = err
      begin
        run_web
      ensure
        $stderr = original
      end

      expect(spies.first.start_count).to eq(1)
      expect(err.string).to include('could not open browser')
    end
  end

  describe 'boot resilience' do
    it 're-probes when the probed port is squatted between probe and WEBrick bind' do
      server_attempts = 0
      allow(SPMCache::Web::Server).to receive(:new) do |**kwargs|
        server_attempts += 1
        raise Errno::EADDRINUSE, 'bind(2) for 127.0.0.1' if server_attempts == 1

        spy = ServerSpy.new(kwargs)
        spies << spy
        spy
      end
      allow(SPMCache::Web::PortProber).to receive(:pick).and_return(8123)

      run_web('--no-open')

      expect(server_attempts).to eq(2)
      expect(spies.size).to eq(1)
    end
  end

  describe '--port parsing' do
    def picked_start_port
      @picked = nil
      allow(SPMCache::Web::PortProber).to receive(:pick) do |**kwargs|
        @picked = kwargs[:start_port]
        8123
      end
    end

    it 'accepts an explicit port' do
      picked_start_port
      run_web('--port=8123', '--no-open')
      expect(@picked).to eq(8123)
    end

    it 'falls back to 7915 on garbage (yml-is-user-authored posture)' do
      picked_start_port
      run_web('--port=abc', '--no-open')
      expect(@picked).to eq(7915)
    end
  end

  describe 'signal contract wiring (WEB-03, watcher.rb shape)' do
    it 'installs TERM/INT traps that call shutdown, then masks them during cleanup' do
      run_web('--no-open')

      spy = spies.first
      expect(spy.term_handler).to be_a(Proc)
      expect(spy.int_handler).to be_a(Proc)

      spy.term_handler.call
      spy.int_handler.call
      expect(spy.shutdown_count).to eq(2)

      # After run returns, further signals are IGNORE-masked during the
      # cleanup path (watcher.rb:73-86 pattern) and the marker is gone.
      expect(Signal.trap('TERM', 'DEFAULT')).to eq('IGNORE')
      expect(Signal.trap('INT', 'DEFAULT')).to eq('IGNORE')
      expect(File.exist?(marker_path)).to be(false)
    end
  end

  describe 'boot-lock serialization (review WR-02)' do
    let(:lock_path) { File.join(tmpdir, '.spm-cache', 'web', '.boot.lock') }

    it 'holds an exclusive boot lock while the marker check and the server run' do
      observations = {}
      probes = []
      allow(SPMCache::Web::Server).to receive(:new) do |**kwargs|
        spy = ServerSpy.new(kwargs)
        spies << spy
        # While the command is inside boot_and_serve, a blocking
        # exclusive claim on the boot lock from another thread must
        # still be parked (macOS quirk: LOCK_NB from the same process
        # never conflicts, so the probe claims blocking and we check
        # it stays blocked while the boot runs). NOT joined here: the
        # probe can only acquire after the command releases.
        probe = Thread.new do
          File.open(lock_path, File::RDWR) do |fd|
            fd.flock(File::LOCK_EX)
            observations[:acquired] = true
          end
        end
        probes << probe
        probe.join(0.3) # nil while the command holds the lock
        observations[:blocked_during_boot] = probe.alive?
        spy
      end

      run_web('--no-open') # returns after the boot lock is released

      probes.each(&:join) # the parked probe acquires post-release
      expect(observations[:blocked_during_boot]).to be(true)
      expect(observations[:acquired]).to be(true) # released at command exit
    end

    it 'serializes a concurrent launch: the second blocks, then reuses the winner marker' do
      SPMCache::Web::Marker.write(path: marker_path, pid: Process.pid, port: 4242, token: 't')
      FileUtils.mkdir_p(File.dirname(lock_path))
      holder = File.open(lock_path, File::CREAT | File::RDWR, 0o600)
      holder.flock(File::LOCK_EX)

      out = StringIO.new
      worker = Thread.new do
        original = $stdout
        $stdout = out
        begin
          described_class.new(CLAide::ARGV.new(['--no-open'])).run
        ensure
          $stdout = original
          holder.close # unblock the worker if the example failed early
        end
      end

      sleep 0.5
      expect(spies).to be_empty
      expect(out.string).to be_empty # still blocked on the boot lock

      holder.close # release: the blocked launch proceeds to the marker read
      worker.join(5)

      expect(out.string).to include('http://127.0.0.1:4242')
      expect(out.string).to include('already running')
      expect(spies).to be_empty # reused, never constructed a server
      expect(File.exist?(marker_path)).to be(true) # winner marker intact
    end

    it 'never clears a marker a newer server overwrote during our run' do
      marker_path_local = marker_path
      spy = ServerSpy.new({})
      spy.define_singleton_method(:start) do
        super()
        # A newer launch overwrites our marker while we serve (the
        # WR-02 orphan scenario the boot lock prevents for real
        # processes -- the pid-guard is the second line of defense).
        SPMCache::Web::Marker.write(path: marker_path_local,
                                    pid: 2_000_000_000, port: 9999, token: 'newer')
      end
      allow(SPMCache::Web::Server).to receive(:new).and_return(spy)
      spies << spy

      run_web('--no-open')

      # Our pid-guarded ensure must leave the newer record in place.
      expect(SPMCache::Web::Marker.read(path: marker_path)['port']).to eq(9999)
    end
  end
end
