# frozen_string_literal: true

module SPMCache
  module Web
    # WEBrick adapter (WEB-01). The ONLY place in the codebase that
    # requires 'webrick' -- lazily, at construction: Main.load_all loads
    # every lib file on every CLI invocation, and a machine without the
    # gem must still run `spm-cache use` (research CP8).
    class Server
      # Never a hostname ('localhost' resolves ::1 first on macOS) and
      # never 0.0.0.0 (off-loopback exposure) -- explicit loopback only
      # (research CP9).
      BIND_ADDRESS = '127.0.0.1'

      attr_reader :port, :token, :bind_address

      def initialize(port:, token:, router:, logger: nil, start_callback: nil)
        require_webrick
        @token = token
        # Resolve port 0 up front so WEBrick receives a CONCRETE port and
        # #port stays the single source of truth (allowlists, printed
        # URL, marker file).
        @port = resolve_port(port)
        router.port = @port
        @bind_address = BIND_ADDRESS
        @http = WEBrick::HTTPServer.new(
          BindAddress: @bind_address,
          Port: @port,
          # T-13-03: WEBrick's DEFAULT access log writes full request
          # URLs -- including ?token=<launch token> -- to $stderr
          # (httpserver.rb builds it when :AccessLog is unset). Disabled
          # outright: the token must never reach any log.
          AccessLog: [],
          # Startup/stop chatter stays out of the terminal the CLI owns.
          Logger: logger || WEBrick::Log.new($stderr, WEBrick::Log::ERROR),
          DoNotReverseLookup: true,
          # CP12 health-before-open: fires inside #start after the
          # listener sockets are bound and before the accept loop begins
          # (verified against webrick 1.9.2 server.rb) -- Command::Web
          # opens the browser here, never before.
          StartCallback: start_callback
        )
        # Exactly ONE servlet at '/': the middleware gate is structural,
        # no route can exist outside it (T-13-01).
        @http.mount('/', catch_all_servlet(router))
      end

      # Blocks in the WEBrick run loop until #shutdown.
      def start
        @http.start
      end

      # Thread-safe and callable from a Signal.trap context: writes the
      # shutdown pipe and closes the listeners (verified against webrick
      # 1.9.2 server.rb -- stop + alarm_shutdown_pipe, no mutex).
      def shutdown
        @http.shutdown
      end

      private

      def require_webrick
        require 'webrick'
      rescue LoadError
        raise Core::GeneralError,
              'the webrick gem is required for spm-cache web — install with: gem install webrick'
      end

      # For port 0: bind, read the assigned port, close, then hand WEBrick
      # the concrete number (accepted ephemeral-port dev-tool race).
      def resolve_port(port)
        return port unless port.zero?

        probe = TCPServer.new(BIND_ADDRESS, 0)
        probe.addr[1]
      ensure
        probe&.close
      end

      # Runtime-built adapter (the class cannot exist at file load: it
      # subclasses a WEBrick constant, and this file must load without
      # the gem). Overrides AbstractServlet#service so EVERY HTTP method
      # funnels into the router -- the built-in ProcHandler covers only
      # GET/POST/PUT, and the gate must not depend on the verb (Phase
      # 15's POSTs inherit it).
      def catch_all_servlet(router)
        Class.new(WEBrick::HTTPServlet::AbstractServlet) do
          define_method(:service) { |req, res| router.service(req, res) }
        end
      end
    end
  end
end
