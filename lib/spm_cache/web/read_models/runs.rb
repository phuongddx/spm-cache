# frozen_string_literal: true

require 'json'
require 'time'

module SPMCache
  module Web
    module ReadModels
      # D-12/LOGS-05/CP10: the recent-runs listing and the ONE state
      # derivation behind it. Everything derives from the runs dir
      # (run_start headers + run_end lines) and a non-blocking probe of
      # the build lock on EVERY call -- re-read per request, the State
      # shape (state.rb:5-11 posture), never an instance cache: CP10
      # forbids run-state memory in the server, and Doctor's
      # {data, generated_at} Mutex-cache is explicitly the WRONG shape
      # here (14-PATTERNS 'Do NOT copy Doctor's statefulness'). Events'
      # hello consumes the same helpers (derive / lock_state), so the
      # D-06 card and the D-12 dropdown agree by construction -- one
      # derivation, two surfaces, zero drift.
      class Runs
        # The recent-runs dropdown bound ('10 newest entries',
        # 14-UI-SPEC; discretion per 14-CONTEXT).
        LIST_LIMIT = 10

        # CP14, pinned verbatim (14-UI-SPEC status table): a dead header
        # pid with no run_end line. The em dash is part of the contract.
        INTERRUPTED = 'interrupted — exit unknown'

        # The idle lock shape: the probe acquired, so nothing holds it.
        FREE_LOCK = { 'state' => 'free', 'holder' => nil, 'holder_status' => nil }.freeze

        class << self
          # The /api/runs payload: newest-first listing + lock + now,
          # String-keyed at every level (JSON.generate silently drops
          # symbol keys -- state.rb:44-53 lesson).
          def call(config: Core::Config.instance)
            {
              'runs' => list(runs_dir: config.runs_dir),
              'lock' => lock_state(config: config),
              'now' => Time.now.utc.iso8601
            }
          end

          # One run's derived identity + status (the shared derivation
          # Events' hello also consumes): the run_start header plus the
          # run_end exit line, one small-file read (files are bounded by
          # retention -- do not over-engineer). Header parse per the
          # run_start_pid shape (run_log.rb:415-419, rescue-to-nil);
          # nil when the header is unreadable, never a raise into the
          # request.
          def derive(path)
            header = nil
            run_end = nil
            File.open(path, 'rb') do |io|
              io.each_line do |line|
                parsed = begin
                  JSON.parse(line)
                rescue JSON::ParserError
                  nil
                end
                next unless parsed.is_a?(Hash)

                header = parsed if parsed['event'] == 'run_start' && header.nil?
                if parsed['event'] == 'run_end'
                  run_end = parsed
                  break # run_end is the file's last word (run_log.rb:277-291)
                end
              end
            end
            return nil unless header

            {
              'run' => File.basename(path),
              'header' => header,
              'status' => status_for(header: header, run_end: run_end),
              'started_at' => header['started_at'],
              'ended_at' => run_end && run_end['ended_at']
            }
          rescue StandardError
            nil # an unreadable run file degrades to an absent row
          end

          # D-12 listing: glob + sort (filename sort == chronological,
          # run_log.rb:29-31), newest first, at most LIST_LIMIT entries.
          # An absent runs dir is simply no glob hits (graph.rb guard
          # shape) -- never a raise.
          def list(runs_dir:, limit: LIST_LIMIT)
            run_files(runs_dir).reverse.first(limit).filter_map { |path| entry(derive(path)) }
          end

          # D-13 fresh-connect choice (Events.choose_run delegates here,
          # so the tailer spec's pinned seam keeps working): the newest
          # file whose header pid is alive and whose file lacks run_end
          # (the live run); else the newest file overall; nil for an
          # empty runs dir. Derived from disk on every call (CP10).
          def current_path(runs_dir:)
            files = run_files(runs_dir)
            return nil if files.empty?

            running = newest_running(runs_dir)
            return File.join(runs_dir, running['run']) if running

            files.last
          end

          # CP10 lock derivation: probe + attribution. Held + an
          # attributable live run → that run's identity ('running');
          # held + nothing attributable → 'unknown holder' (LOGS-05's
          # external-run detection: a --no-run-log invocation or a
          # pre-Phase-12 process genuinely holds it -- flock releases on
          # process death, so a held lock always means a live holder;
          # the derivation never guesses); free → idle.
          def lock_state(config: Core::Config.instance)
            return FREE_LOCK unless lock_held?(config.build_lock_path)

            running = newest_running(config.runs_dir)
            if running
              { 'state' => 'held', 'holder' => running['run'], 'holder_status' => 'running' }
            else
              { 'state' => 'held', 'holder' => nil, 'holder_status' => 'unknown holder' }
            end
          end

          private

          def run_files(runs_dir)
            Dir.glob(File.join(runs_dir, '*.jsonl')).sort
          end

          # Newest-first scan stopping at the first 'running' derivation
          # -- the D-13 choice and the lock attribution share it.
          def newest_running(runs_dir)
            run_files(runs_dir).reverse_each do |path|
              derived = derive(path)
              return derived if derived && derived['status'] == 'running'
            end
            nil
          end

          # The non-blocking probe (research Pattern 4): try to acquire;
          # acquiring proves nothing held it and the File.open block's
          # exit releases immediately (closing the fd drops the flock)
          # -- the server NEVER holds or lingers on the build lock
          # (milestone stance, CP4's flip side; T-14-14: LOCK_NB never
          # blocks the request thread). ENOENT → free (never taken).
          def lock_held?(path)
            File.open(path, File::RDWR) { |io| !io.flock(File::LOCK_EX | File::LOCK_NB) }
          rescue Errno::ENOENT
            false
          end

          # The D-12 dropdown entry: identity (run id, command, trigger,
          # started_at, ended_at) + derived status.
          def entry(derived)
            return nil unless derived

            {
              'run' => derived['run'],
              'command' => derived['header']['command'],
              'trigger' => derived['header']['trigger'],
              'started_at' => derived['started_at'],
              'ended_at' => derived['ended_at'],
              'status' => derived['status']
            }
          end

          # The status vocabulary (14-UI-SPEC card words): run_end 0 →
          # 'success'; non-zero → 'failed'; alive pid + no run_end →
          # 'running'; dead pid + no run_end → CP14's honest interrupt.
          # The exit line is authoritative for FINISHED runs; pid
          # liveness is authoritative for liveness -- a dead pid is
          # never 'running' (the missing run_end only means the exit
          # status is unknown).
          def status_for(header:, run_end:)
            if run_end
              run_end['status'] == 0 ? 'success' : 'failed'
            elsif pid_alive?(header['pid'])
              'running'
            else
              INTERRUPTED
            end
          end

          # run_log.rb:395-402 semantics (private there): Process.kill(0,
          # pid) probes liveness -- ESRCH means dead; any other error
          # (e.g. EPERM) means the pid exists, so treat as alive.
          def pid_alive?(pid)
            return false unless pid.is_a?(Integer)

            Process.kill(0, pid)
            true
          rescue Errno::ESRCH
            false
          rescue StandardError
            true
          end
        end
      end
    end
  end
end
