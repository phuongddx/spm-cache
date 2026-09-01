# frozen_string_literal: true

require 'securerandom'
require 'fileutils'

require 'spm_cache/command'
require 'spm_cache/web/assets'
require 'spm_cache/web/marker'
require 'spm_cache/web/port_prober'
require 'spm_cache/web/router'
require 'spm_cache/web/server'

module SPMCache
  class Command
    # `spm-cache web` — serves the read-only dashboard on the loopback.
    # Watch-like mental model: foreground process, Ctrl-C to stop
    # (13-CONTEXT "Launch & Port Behavior"). CLAide auto-registers the
    # verb from the class name; command.rb stays untouched.
    class Web < Command
      BOOT_RETRIES = 2
      DEFAULT_PORT = 7915

      self.summary = 'Serve the read-only cache dashboard on localhost'
      self.description = 'Starts a hardened localhost-only web server showing cache state, doctor health, and the dependency graph. Read-only. Re-running while a server is live reuses it; SIGTERM/SIGINT stops it cleanly.'

      def self.options
        [
          ['--port=PORT',
           'Port to serve on (default: 7915; probes upward on collision, always skipping AirPlay 5000/7000)'],
          ['--no-open', 'Do not open the dashboard in the browser']
        ].concat(super)
      end

      def initialize(argv)
        @port = parse_port(argv.option('port'))
        @open = argv.flag?('open', true)
        super
      end

      def run
        config = Core::Config.instance
        begin
          config.load
        rescue StandardError
          nil
        end

        # WEB-02 mutual exclusion (review WR-02): the marker read ->
        # live? -> probe -> write sequence must be atomic across
        # processes. The flock boot lock (installer/build.rb precedent)
        # is held from before the marker check until the server stops:
        # a concurrent `spm-cache web` blocks here, then reuses the
        # winner's marker instead of racing a second server -- and a
        # last-write-wins clear -- into existence. Process death
        # releases the lock for free.
        FileUtils.mkdir_p(config.web_dir)
        File.open(File.join(config.web_dir, '.boot.lock'),
                  File::CREAT | File::RDWR, 0o600) do |lock|
          lock.flock(File::LOCK_EX)
          boot_and_serve
        end
      end

      # The serialized launch body (caller holds the boot lock).
      def boot_and_serve
        marker = ::SPMCache::Web::Marker.read
        if marker && ::SPMCache::Web::Marker.live?(marker)
          url = "http://127.0.0.1:#{marker['port']}"
          Core::UI.info "spm-cache web is already running at #{url}"
          open_browser(url) if @open
          return
        end
        ::SPMCache::Web::Marker.clear if marker # stale (dead pid / unreadable): heal

        token = SecureRandom.hex(32) # per launch, rotated every launch
        port, server = boot_with_retry(token)

        ::SPMCache::Web::Marker.write(pid: Process.pid, port: port, token: token)

        # WEB-03, watcher.rb:73-86 shape: traps stop the server; further
        # traps are IGNORE-masked during cleanup so a second Ctrl-C/TERM
        # can never abort the marker clear or break the exit-0 contract.
        %w[TERM INT].each { |sig| Signal.trap(sig) { server.shutdown } }

        begin
          server.start # blocks in the WEBrick run loop until shutdown
        ensure
          Signal.trap('TERM', 'IGNORE')
          Signal.trap('INT', 'IGNORE')
          # pid-guarded (review WR-02): clear only OUR record -- never
          # one a newer server overwrote while we served.
          ::SPMCache::Web::Marker.clear(pid: Process.pid)
        end
      end

      private

      # Probe + construct, retrying past the rare ephemeral-reuse race:
      # between PortProber's bind-and-close and WEBrick's bind, another
      # process can squat the port. Re-probing moves past the squatter
      # (pick rescues EADDRINUSE per candidate) instead of dying at boot.
      def boot_with_retry(token)
        attempts = 0
        begin
          port = ::SPMCache::Web::PortProber.pick(start_port: @port)
          [port, build_server(port: port, token: token)]
        rescue Errno::EADDRINUSE
          attempts += 1
          retry if attempts <= BOOT_RETRIES
          raise
        end
      end

      # Overridable seam (installer_factory precedent, watch.rb): specs
      # inject a double at the ::SPMCache::Web::Server.new boundary inside.
      def build_server(port:, token:)
        router = ::SPMCache::Web::Router.new(token: token, port: port,
                                             assets: ::SPMCache::Web::Assets.new)
        ::SPMCache::Web::Server.new(
          port: port,
          token: token,
          router: router,
          # CP12 health-before-open: StartCallback fires inside #start
          # after the listener sockets are bound -- the browser opens
          # only once the server can actually answer.
          start_callback: @open ? -> { open_browser("http://127.0.0.1:#{port}") } : nil
        )
      end

      # macOS-only project; a failure here must never kill the server.
      def open_browser(url)
        Core::Sh.run("open #{url}")
      rescue Core::GeneralError => e
        Core::UI.warn "could not open browser: #{e.message}"
      end

      # Integer()-coerced with rescue-to-default: the --port value is
      # user-authored CLI input (same posture as the retention readers,
      # config.rb) -- `--port=abc` falls back to the default, never a
      # crash mid-verb. A numerically valid but unbindable value is a
      # deliberate user choice, so it fails loudly as a GeneralError
      # (the PortProber-exhaustion posture) instead of a raw errno
      # dump from deep inside the boot (review WR-04).
      def parse_port(raw)
        port = Integer(raw || DEFAULT_PORT)
        unless (1..65_535).cover?(port)
          raise Core::GeneralError,
                "--port must be between 1 and 65535 (got #{port})"
        end
        port
      rescue ArgumentError, TypeError
        DEFAULT_PORT
      end
    end
  end
end
