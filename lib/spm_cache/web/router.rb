# frozen_string_literal: true

require 'json'
require 'time'

require 'spm_cache/web/middleware'

module SPMCache
  module Web
    # Single catch-all request dispatcher (WEB-04). Mounted as the
    # server's ONLY servlet (Web::Server), so uniformity is structural:
    # every byte served -- any verb, any path -- passes the Host/Origin
    # gate before dispatch, and every /api/* route additionally requires
    # the per-launch token. Expected rejections set status + body
    # directly instead of raising WEBrick status errors: the generic
    # handler logs raises at ERROR level, and the terminal must stay
    # quiet (T-13-03).
    #
    # Route/auth matrix (pinned for the phase; 13-04 proves it
    # exhaustively once all routes exist):
    #   Host allowlist + Origin-if-present allowlist -> ALL routes (403)
    #   token (X-SPM-Token header or ?token param)  -> ALL /api/* (401)
    #   GET / without ?token -> 302 bootstrap redirect (the ONLY token
    #   delivery path); GET /?token= and /assets/* serve without a token
    #   check -- assets ship inside the gem and <script>/<link> tags
    #   cannot send custom headers; they carry zero project data
    #   (13-CONTEXT "Token & Security Middleware").
    class Router
      TOKEN_HEADER = 'x-spm-token'
      TOKEN_PARAM = 'token'

      # The middleware allowlists derive from the bound port; Web::Server
      # syncs this after ephemeral-port (port: 0) resolution.
      attr_accessor :port

      def initialize(token:, port:, assets: nil, read_models: {})
        @token = token
        @port = port
        @assets = assets
        # Plan 13-02 replaces the inline graph reader with read-model
        # objects behind this same callable interface.
        @read_models = { graph: default_graph_reader }.merge(read_models)
      end

      def service(req, res)
        apply_security_headers(res)

        host = req['host']
        origin = req['origin']
        supplied = req[TOKEN_HEADER] || req.query[TOKEN_PARAM]

        # Gate order is Host, then Origin, then per-route token: a
        # rejected request never reaches dispatch, for any verb.
        return reject(res, 403, 'forbidden host') unless Middleware.allowed_host?(host: host, port: @port)
        return reject(res, 403, 'forbidden origin') unless Middleware.allowed_origin?(origin: origin, port: @port)

        dispatch(req, res, supplied)
      end

      private

      def dispatch(req, res, supplied)
        case req.path
        when '/', ''
          root(req, res)
        when %r{\A/assets/}
          # WEBrick hands us the percent-DECODED path (verified against
          # the gem source); the decoded name goes straight into
          # validation -- decode-then-validate, never the reverse.
          asset(res, req.path.sub(%r{\A/assets/}, ''))
        when '/api/graph'
          api_graph(req, res, supplied)
        else
          reject(res, 404, 'not found')
        end
      end

      def root(req, res)
        return reject(res, 404, 'not found') unless req.request_method == 'GET'

        # Token bootstrap (locked, 13-CONTEXT): first GET / is redirected
        # to /?token=<t>; the page then moves the token to sessionStorage
        # and cleans the URL before first render (13-UI-SPEC). The token
        # is never printed anywhere else.
        return bootstrap_redirect(res) if req.query[TOKEN_PARAM].nil?

        file = @assets&.serve('index.html')
        return reject(res, 404, 'not found') unless file

        respond(res, 200, file[:content_type], file[:body])
      end

      def asset(res, name)
        file = @assets&.serve(name)
        return reject(res, 404, 'not found') unless file

        respond(res, 200, file[:content_type], file[:body])
      end

      def api_graph(req, res, supplied)
        unless Middleware.valid_token?(token: supplied, expected_token: @token)
          return reject(res, 401, 'missing or invalid token')
        end
        return reject(res, 404, 'not found') unless req.request_method == 'GET'

        # Malformed graph.json surfaces as a 500 error envelope -- the
        # shape Plan 13-03's error copy consumes.
        begin
          respond_json(res, 200, ok_envelope(@read_models[:graph].call))
        rescue JSON::ParserError => e
          respond_json(res, 500, error_envelope(e.message))
        end
      end

      # -- helpers ---------------------------------------------------------

      # Every response, rejection or payload alike: clickjacking (T-13-07)
      # and token-in-URL hygiene (T-13-03) -- nothing may be cached.
      def apply_security_headers(res)
        res['X-Frame-Options'] = 'DENY'
        res['Cache-Control'] = 'no-store'
      end

      def bootstrap_redirect(res)
        res.status = 302
        res['Location'] = "/?token=#{@token}"
      end

      def reject(res, status, message)
        respond_json(res, status, error_envelope(message))
      end

      def respond_json(res, status, envelope)
        respond(res, status, 'application/json', JSON.generate(envelope))
      end

      def respond(res, status, content_type, body)
        res.status = status
        res['Content-Type'] = content_type
        res.body = body
      end

      def ok_envelope(data)
        { 'status' => 'ok', 'data' => data,
          'generated_at' => Time.now.utc.iso8601 }
      end

      def error_envelope(message)
        { 'status' => 'error', 'data' => { 'message' => message },
          'generated_at' => Time.now.utc.iso8601 }
      end

      # Tracer read model (DASH-03, server side): the graph panel's data
      # derives from the CLI's own graph.json via Cache::Cachemap -- the
      # server is a stateless file reader, never a second source of truth.
      def default_graph_reader
        lambda do
          graph_path = File.join(Core::Config.instance.proxy_dir, 'graph.json')
          return { 'present' => false, 'nodes' => [], 'graph_generated_at' => nil } unless File.exist?(graph_path)

          {
            'present' => true,
            'nodes' => Cache::Cachemap.load(graph_path).depgraph_for_viz,
            'graph_generated_at' => File.mtime(graph_path).utc.iso8601
          }
        end
      end
    end
  end
end
