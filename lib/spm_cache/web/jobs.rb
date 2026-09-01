# frozen_string_literal: true

require 'spm_cache/web/read_models/runs'

module SPMCache
  module Web
    # Web::Jobs -- the ONE UI-originated mutation spawner (BLD-01, D-02,
    # D-05). Spawns the REAL spm-cache CLI as an array-argv, own-
    # process-group, detached child (research P1-P5): the server never
    # becomes the build's signal parent -- no waitpid, no monitoring
    # thread, no signal call anywhere in this class. A Mutex-guarded
    # single slot enforces exactly one UI-spawned run at a time
    # (build+rollback share it, UI-SPEC A1); release is DERIVED from
    # the run log on the next claim attempt (CP10), never remembered
    # and never learned from waitpid (detach discards exit status).
    class Jobs
      # P8 (machine-probed): resolves from this file's depth to the
      # repo bin in both the dev checkout and RubyGems' installed
      # layout (<gem>/lib/spm_cache/web/ + <gem>/bin/spm-cache).
      # Pinning the interpreter (RbConfig.ruby) removes PATH-ruby
      # ambiguity; Dir.pwd-relative paths would break under any other
      # cwd (research Q1).
      BIN_PATH = File.expand_path('../../../bin/spm-cache', __dir__)

      # Attribution-only marker (D-03, Pitfall 7): the ONLY variable
      # Jobs adds on top of the inherited parent environment. Never
      # read for control flow by anything -- the child's Main.run (15-
      # 02) normalizes it into the run_start header, and that is its
      # entire purpose.
      TRIGGER_ENV = 'SPM_CACHE_TRIGGER'

      # The frozen scope->argv table (V5, Pitfall 5): the request's
      # scope string is looked up here and NEVER interpolated,
      # concatenated, or splatted into the spawned command line.
      # 'build' is the incremental verb; 'rebuild' is the SAME verb
      # plus 15-03's forced flag (A8 -- the argv row self-documents
      # which verb ran); 'rollback' is the rollback verb (D-07), the
      # route-implied scope of POST /api/rollback.
      SCOPES = {
        'build' => ['build'].freeze,
        'rebuild' => ['build', '--rebuild'].freeze,
        'rollback' => ['rollback'].freeze,
        # (16-04, D-07) Apply-now: the bare sync verb -- command/use.rb's
        # default subcommand, watch flag defaulted off. One frozen
        # fragment, looked up by POST /api/apply's route-fixed scope;
        # no second spawn mechanism exists anywhere in this class.
        'use' => ['use'].freeze
      }.freeze

      def initialize(config: Core::Config.instance, bin_path: BIN_PATH)
        @config = config
        @bin_path = bin_path
        @mutex = Mutex.new
        @slot = nil # { pid:, scope: } while claimed; nil while free
      end

      # Atomic check-then-claim-then-record (Pitfall 1: two WEBrick
      # threads racing a double-click POST must not both pass the
      # check) entirely inside one Mutex. Returns the new child pid on
      # a successful claim, nil when the slot is still held by a live
      # run. Process.spawn raising (bad bin, ENOENT, ...) propagates to
      # the caller -- the router maps that to the 500 envelope.
      def spawn_run(scope:)
        @mutex.synchronize do
          return nil if held?

          argv = SCOPES.fetch(scope)
          env = ENV.to_h.merge(TRIGGER_ENV => 'ui')
          pid = Process.spawn(env, RbConfig.ruby, @bin_path, *argv,
                              chdir: @config.project_dir,
                              out: File::NULL, err: File::NULL,
                              pgroup: true)
          Process.detach(pid)
          @slot = { pid: pid, scope: scope }
          pid
        end
      end

      private

      # D-05/CP10 (the honest release): the slot never learns "ended"
      # from waitpid -- detach discards the exit status, and no
      # monitoring thread exists anywhere in this class. Instead:
      #   - a run file whose header pid matches the slot pid exists ->
      #     ReadModels::Runs' own status derivation decides (run_end
      #     line authoritative, pid liveness fallback, CP14
      #     'interrupted' honored as ended, never wedged);
      #   - no such run file exists yet (the pre-header spawn window)
      #     -> the raw pid probe decides.
      # Freeing the slot happens IN PLACE so the next claim proceeds
      # without a second round trip.
      def held?
        return false unless @slot

        pid = @slot[:pid]
        derived = ReadModels::Runs.derive_for_pid(pid, runs_dir: @config.runs_dir)
        alive = derived ? derived['status'] == 'running' : ReadModels::Runs.pid_alive?(pid)
        @slot = nil unless alive
        alive
      end
    end
  end
end
