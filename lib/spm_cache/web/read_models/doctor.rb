# frozen_string_literal: true

require 'time'

module SPMCache
  module Web
    module ReadModels
      # DASH-02: the doctor panel's data. run:true executes the check
      # registry synchronously IN-REQUEST (the Run Doctor button --
      # checks shell out and can take seconds; T-13-12 accepts
      # dev-tool concurrency: the button disables itself while in
      # flight, and only this path ever executes checks) and swaps the
      # in-memory {data, generated_at} cache atomically under a Mutex
      # (T-13-10: WEBrick serves each request in its own thread; data
      # and stamp move as ONE pair so a stale stamp can never label
      # fresh checks). Without run, the cached result is served with
      # its ORIGINAL stamp -- the timestamp of the run, not of the read
      # -- so the UI's "Cached — generated at" stays honest.
      class Doctor
        NEVER_RUN = {
          'has_run' => false,
          'checks' => [],
          'summary' => { 'ok' => 0, 'warnings' => 0, 'failures' => 0 }
        }.freeze

        # One instance per server (it holds the cache state, unlike the
        # stateless State/Graph callables). config: and diagnostics:
        # are injectable seams for specs.
        def initialize(config: Core::Config.instance, diagnostics: Core::Diagnostics)
          @config = config
          @diagnostics = diagnostics
          @mutex = Mutex.new
          @cache = nil
        end

        # Answers {data:, generated_at:}; generated_at is nil before
        # the first run -- the router passes it through to the envelope
        # verbatim instead of stamping now().
        def call(run: false)
          return run_and_cache if run

          @mutex.synchronize { @cache || { data: NEVER_RUN, generated_at: nil } }
        end

        private

        def run_and_cache
          # Tolerant config load (Command::Doctor posture): a project
          # with no spm-cache.yml still runs every check.
          begin
            @config.load
          rescue StandardError
            nil
          end

          # The registry is the single source of check truth (DASH-02):
          # nothing here enumerates checks by name.
          payload = @diagnostics.payload(@diagnostics.run_all(config: @config))
          # Normalize through the serializer the router will use: the
          # cached data hash is defined AS its JSON shape -- String
          # keys at every level, exactly what the envelope serves and
          # the DASH-02 contract pins.
          data = { 'has_run' => true }.merge(JSON.parse(JSON.generate(payload)))
          entry = { data: data, generated_at: Time.now.utc.iso8601 }
          @mutex.synchronize { @cache = entry }
        end
      end
    end
  end
end
