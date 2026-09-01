# frozen_string_literal: true

require 'json'
require 'time'

require 'spm_cache/web/middleware'
require 'spm_cache/web/read_models/state'
require 'spm_cache/web/read_models/graph'
require 'spm_cache/web/read_models/runs'
require 'spm_cache/web/read_models/doctor'
require 'spm_cache/web/events'
require 'spm_cache/web/jobs'

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

      def initialize(token:, port:, assets: nil, read_models: {}, events: nil, jobs: nil,
                     config: Core::Config.instance)
        @token = token
        @port = port
        @assets = assets
        @config = config
        # Read models: State/Graph/Runs are stateless callables answering
        # .call(config:) and re-reading disk on every request; doctor
        # is an INSTANCE -- it holds the {data, generated_at} cache
        # (13-02). Per-key overridable for specs.
        @read_models = {
          state: Web::ReadModels::State,
          graph: Web::ReadModels::Graph,
          runs: Web::ReadModels::Runs,
          doctor: Web::ReadModels::Doctor.new(config: config)
        }.merge(read_models)
        # Events: the SSE collaborator (14-01), an INSTANCE like doctor
        # (it holds the tailer thread + client registry). Constructing it
        # starts no thread -- the tailer starts lazily on the first
        # /api/events register -- so every non-streaming boot stays
        # thread-free. Injectable for specs (short poll/heartbeat).
        @events = events || Web::Events.new(config: config)
        # Jobs: the ONE UI-mutation spawner (15-01), defaulted exactly
        # like events -- Command::Web#build_server needs NO edit, and
        # specs inject a fake-bin-backed Jobs through this same seam.
        @jobs = jobs || Web::Jobs.new(config: config)
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

      # Server#shutdown seam (WEB-03): notify the SSE broadcaster BEFORE
      # @http.shutdown -- nil-safe for doubles and events-less routers.
      # Public: the Server holds the router instance and calls this from
      # ITS #shutdown; must stay above the private section.
      def shutdown_events
        @events&.shutdown!
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
        when '/api/state'
          api_read(req, res, supplied, :state)
        when '/api/graph'
          api_read(req, res, supplied, :graph)
        when '/api/runs'
          api_read(req, res, supplied, :runs)
        when '/api/build'
          # CR-01: /api/build's scope is verb-level (build/rebuild
          # only) -- rollback is reachable only via the dedicated
          # /api/rollback route below, never via this one's body.
          api_mutate(req, res, supplied, allowed_scopes: %w[build rebuild])
        when '/api/rollback'
          # D-07: the scope is IMPLIED by the route, never read from
          # the body -- rollback takes no scope, so an empty or absent
          # body is the documented shape.
          api_mutate(req, res, supplied, fixed_scope: 'rollback')
        when '/api/toggle'
          # D-08 (16-01): the instant config-write arm -- never
          # slot-gated (the spawn slot governs Apply-now only).
          api_toggle(req, res, supplied)
        when '/api/doctor'
          api_doctor(req, res, supplied)
        when '/api/events'
          events_stream(req, res, supplied)
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

      # Static assets: no token check (see the class-level matrix note),
      # but names resolve through Web::Assets' validated-basename +
      # containment contract (T-13-04) -- every traversal form 404s.
      def asset(res, name)
        file = @assets&.serve(name)
        return reject(res, 404, 'not found') unless file

        respond(res, 200, file[:content_type], file[:body])
      end

      # Shared shape of every GET-only /api/* read endpoint: token gate
      # first (T-13-09 -- no un-gated route exists), then verb check.
      # Malformed project files (graph.json) surface as the 500 error
      # envelope -- the shape Plan 13-03's error copy consumes.
      def api_read(req, res, supplied, model)
        unless Middleware.valid_token?(token: supplied, expected_token: @token)
          return reject(res, 401, 'missing or invalid token')
        end
        return reject(res, 404, 'not found') unless req.request_method == 'GET'

        begin
          respond_json(res, 200, ok_envelope(@read_models[model].call(config: @config)))
        rescue JSON::JSONError, TypeError => e
          # JSONError covers ParserError AND its sibling GeneratorError:
          # invalid-UTF-8 strings planted in project files parse fine
          # (json keeps the raw bytes) and only explode at
          # JSON.generate inside respond_json. TypeError covers
          # shape-malformed JSON -- e.g. graph.json holding an object,
          # where iteration yields [key, value] pairs and
          # entry['module'] dies with String-into-Integer. Both surface
          # as the 500 envelope; anything else still escapes to
          # WEBrick's handler.
          respond_json(res, 500, error_envelope(e.message))
        end
      end

      # DASH-02: the doctor endpoint. Any truthy ?run= value (the Run
      # Doctor button sends 1) executes the check registry
      # synchronously in-request; without it the cached result (or the
      # honest never-run shape) is served. The envelope's generated_at
      # is the read model's OWN stamp -- nil before the first run --
      # passed through verbatim, never re-stamped, so "Cached —
      # generated at" always labels the run that produced the data.
      def api_doctor(req, res, supplied)
        unless Middleware.valid_token?(token: supplied, expected_token: @token)
          return reject(res, 401, 'missing or invalid token')
        end
        return reject(res, 404, 'not found') unless req.request_method == 'GET'

        result =
          begin
            @read_models[:doctor].call(run: !req.query['run'].nil?)
          rescue StandardError => e
            # The doctor round-trips its payload through JSON.generate
            # inside #call, so hostile strings in check messages raise
            # GeneratorError HERE, before an envelope exists -- same
            # 500-envelope contract as api_read. StandardError (never
            # Interrupt) keeps the serving path total.
            return respond_json(res, 500, error_envelope(e.message))
          end
        respond_json(res, 200,
                     'status' => 'ok',
                     'data' => result[:data],
                     'generated_at' => result[:generated_at])
      end

      # GET /api/events -- the SSE stream (LOGS-03). The ONE route that
      # never calls respond_json: after the shared token/verb gates it
      # answers 200 text/event-stream ALWAYS -- any non-200 permanently
      # fails EventSource reconnect (WHATWG 9.2.3; the milestone's
      # "503 + Retry:" clause is falsified per 14-RESEARCH) -- with
      # keep_alive=false (one-shot stream; the connection thread exits
      # at the chunked terminator instead of parking RequestTimeout) and
      # the body proc as the per-client writer (research Pattern 1).
      # Auth failures (401/403) are deliberately permanent: an
      # auth-dead tab must not ghost-retry. ?run= pins the stream to a
      # validated run name (14-03, D-12): resolve_run_name applies the
      # same regex + containment machinery as the resume id, so a
      # hostile value never reaches File.open -- it silently falls back
      # to current-or-newest.
      def events_stream(req, res, supplied)
        unless Middleware.valid_token?(token: supplied, expected_token: @token)
          return reject(res, 401, 'missing or invalid token')
        end
        return reject(res, 404, 'not found') unless req.request_method == 'GET'

        resume = Events.parse_resume_id(req['last-event-id'], runs_dir: @config.runs_dir)
        pin = Events.resolve_run_name(req.query['run'], runs_dir: @config.runs_dir)
        res.status = 200
        res.content_type = 'text/event-stream'
        res.keep_alive = false
        res.chunked = true
        res.body = proc do |out|
          client = @events.register(out)
          @events.stream(client, resume: resume, pin: pin)
        end
      end

      # The mutation routes (BLD-01/BLD-04, D-04/D-05/D-07): POST
      # /api/build (scope from the JSON body) and POST /api/rollback
      # (scope implied by the route, fixed_scope: -- an empty or
      # absent body is its documented shape). Both share api_read's
      # gate ORDER -- token first (401), then a request-method check
      # that answers the house 404 for anything but POST -- then
      # Jobs::SCOPES' frozen keys, matched EXACTLY -- no case folding,
      # no coercion of non-strings (V5: rejected 400 'bad_scope'
      # BEFORE any spawn attempt, never interpolated into argv). The
      # fixed reason vocabulary (planner decision, Open Question 3):
      # 'bad_body' (400, unparseable JSON), 'bad_scope' (400),
      # 'slot_busy' (409 -- Jobs answered nil for a held slot),
      # 'spawn_failed' (500 -- Jobs raised; the slot was never
      # claimed). Reasons are for programs, never rendered by the
      # frontend (UI-SPEC A9), and error messages are deliberately
      # NOT the dashboard's display copy. A 2xx envelope carries the
      # claimed scope plus a freshly derived lock snapshot (D-06) so
      # the UI's waiting flavor can light up without waiting for the
      # next poll.
      def api_mutate(req, res, supplied, fixed_scope: nil, allowed_scopes: Jobs::SCOPES.keys)
        unless Middleware.valid_token?(token: supplied, expected_token: @token)
          return reject(res, 401, 'missing or invalid token')
        end
        return reject(res, 404, 'not found') unless req.request_method == 'POST'

        raw = req.body.to_s
        body = begin
          # An empty (or whitespace-only) body is the empty object:
          # rollback's documented POST shape (and a scopeless build
          # POST still fails the whitelist below with 'bad_scope',
          # never 'bad_body').
          raw.strip.empty? ? {} : JSON.parse(raw)
        rescue JSON::ParserError
          return respond_json(res, 400, error_envelope('malformed request body', reason: 'bad_body'))
        end
        scope = fixed_scope || (body.is_a?(Hash) ? body['scope'] : nil)
        # CR-01: allowed_scopes narrows the per-route whitelist
        # (/api/build -> build/rebuild only); Jobs::SCOPES.key? alone
        # would also accept 'rollback' here, letting /api/build
        # silently do /api/rollback's job.
        unless allowed_scopes.include?(scope) && Jobs::SCOPES.key?(scope)
          return respond_json(res, 400, error_envelope('scope is not one of the known scopes', reason: 'bad_scope'))
        end

        pid =
          begin
            @jobs.spawn_run(scope: scope)
          rescue StandardError => e
            return respond_json(res, 500, error_envelope(e.message, reason: 'spawn_failed'))
          end
        if pid.nil?
          return respond_json(res, 409,
                              error_envelope('spawn slot busy', reason: 'slot_busy'))
        end

        respond_json(res, 200, ok_envelope('scope' => scope,
                                           'lock' => @read_models[:runs].lock_state(config: @config)))
      end

      # POST /api/toggle (D-08, 16-04: the completed matrix -- 16-01
      # landed the tracer shape this extends): the instant config
      # write through the shared Config mutator. Mirrors api_mutate's
      # gate ORDER -- token first (401), then the house 404 for
      # anything but POST -- then body validation: parseable JSON,
      # `package` a non-empty, non-blank String, `cached` EXACTLY
      # true or false with no truthy coercion (V5) -- then the SAME
      # read model the dashboard renders decides permission,
      # re-derived from disk on EVERY request (the stale-DOM defense:
      # a client-side disabled attribute is never trusted): a package
      # absent from the row set is 404 `unknown_package` (the row set
      # IS the universe -- a typo can never plant a phantom entry);
      # a row the model marks non-toggleable is 400 `not_toggleable`.
      # Only then does the mutator run, its raise rescued into 500
      # `config_write_failed` -- nothing escapes to WEBrick's error
      # log (T-13-03). NEVER references @jobs: the slot governs
      # Apply-now only, so a toggle stays live while a run holds the
      # slot (D-08).
      def api_toggle(req, res, supplied)
        unless Middleware.valid_token?(token: supplied, expected_token: @token)
          return reject(res, 401, 'missing or invalid token')
        end
        return reject(res, 404, 'not found') unless req.request_method == 'POST'

        body = begin
          JSON.parse(req.body.to_s)
        rescue JSON::ParserError
          return respond_json(res, 400, error_envelope('malformed request body', reason: 'bad_body'))
        end
        package = body.is_a?(Hash) ? body['package'] : nil
        unless package.is_a?(String) && !package.strip.empty?
          return respond_json(res, 400, error_envelope('package must be a non-empty string', reason: 'bad_package'))
        end

        cached = body.is_a?(Hash) ? body['cached'] : nil
        unless [true, false].include?(cached)
          return respond_json(res, 400, error_envelope('cached must be true or false', reason: 'bad_cached'))
        end

        row = @read_models[:state].call(config: @config)['packages'].find { |r| r['name'] == package }
        return respond_json(res, 404, error_envelope('unknown package', reason: 'unknown_package')) unless row
        unless row['toggleable']
          return respond_json(res, 400, error_envelope('package is not toggleable', reason: 'not_toggleable'))
        end

        begin
          # cached: true KEEPS the package cached -> ignore entry absent.
          @config.set_ignored(package, !cached)
        rescue StandardError => e
          return respond_json(res, 500, error_envelope(e.message, reason: 'config_write_failed'))
        end
        respond_json(res, 200, ok_envelope('package' => package, 'cached' => cached))
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

      def error_envelope(message, reason: nil)
        data = { 'message' => message }
        data['reason'] = reason if reason
        { 'status' => 'error', 'data' => data,
          'generated_at' => Time.now.utc.iso8601 }
      end
    end
  end
end
