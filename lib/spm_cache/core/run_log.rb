# frozen_string_literal: true

require 'json'
require 'tempfile'
require 'fileutils'

module SPMCache
  module Core
    # RunLog: the JSONL run-log sink (LOGS-01). One file per run:
    #
    #   {"event":"run_start","ts":...,"command":...,"argv":[...],"pid":...,
    #    "started_at":...,"spm_cache_version":...,"trigger":...,"cycle":false}
    #   {"ts":...,"stream":"out"|"err","text":"..."}   terminal-parity body
    #   {"event":<name>,...}                           structured events (D-04)
    #   {"event":"run_end","ts":...,"status":N,"ended_at":...}
    #
    # Fidelity is absolute (D-05): nothing is ever truncated or rewritten --
    # growth is bounded by whole-file retention pruning (Plan 12-03), never by
    # mangling this file. Body lines carry only ts/stream/text and never an
    # `event` key, so structured events stay distinguishable from logged
    # subprocess text by construction (T-12-01 log-forging: Phase 14 renderers
    # must key on the `event` field, never interpret `text`).
    class RunLog
      # Event/body timestamps (ISO-8601 UTC, second precision).
      TIMESTAMP_FORMAT = '%Y-%m-%dT%H:%M:%SZ'
      # File-name timestamps: millisecond precision is a deliberate deviation
      # from RESEARCH Pattern 6's second precision -- watch cycles can
      # complete within one second and would otherwise collide on identical
      # pid+verb names (D-09). Fixed-width %3N keeps lexicographic ==
      # chronological ordering, which retention (Plan 12-03) relies on.
      FILE_TIMESTAMP_FORMAT = '%Y%m%dT%H%M%S%3NZ'

      # Process-wide seam consumed by Plans 02 (capture3 sh events), 04
      # (phase/package markers) and 05 (watch cycles). Single-threaded,
      # save/restore nested at open/finish -- do not change this shape
      # without re-checking those plans.
      class << self
        attr_reader :current
      end

      class << self
        attr_writer :current
      end

      # Result of RunLog.pre_scan -- the raw-argv routing facts Main.run
      # decides on BEFORE CLAide parses (Pitfall 1).
      Scan = Struct.new(:verb, :log_dir, :suppressed, :main_log_skipped, keyword_init: true) do
        def suppressed?
          suppressed
        end

        def main_log_skipped?
          main_log_skipped
        end
      end

      # Pure scan of raw argv (no CLAide involved). The tee installs before
      # Command.run parses, so --no-run-log / --log-dir / the verb must be
      # read here -- the exact situation of the --version intercept in
      # Main.run. After the two-token "--log-dir X" form matches, the value
      # token X is consumed so ['--log-dir', '/tmp/x', 'use'] yields verb
      # "use": a value-as-verb misdetection would corrupt the <verb>.jsonl
      # filename with path separators and the header command field.
      def self.pre_scan(argv)
        verb = nil
        log_dir = nil
        tokens = argv.to_a
        i = 0
        while i < tokens.size
          token = tokens[i].to_s
          if token == '--log-dir'
            log_dir = tokens[i + 1]
            i += 2
          elsif token.start_with?('--log-dir=')
            log_dir = token.sub(/\A--log-dir=/, '')
            i += 1
          elsif token.start_with?('-')
            i += 1
          else
            verb = tokens[i]
            break
          end
        end
        verb ||= 'use' # CLAide default_subcommand (D-08: every verb logs)
        Scan.new(
          verb: verb,
          log_dir: log_dir,
          suppressed: tokens.include?('--no-run-log'),
          # SC3 (web never logs) + D-09 (watch writes per-cycle files, Plan 12-05)
          main_log_skipped: %w[web watch].include?(verb)
        )
      end

      # Opens a new run log: mkdir_p the runs dir, publish the run_start
      # header via same-dir Tempfile + File.rename (the provenance-sidecar
      # pattern, build_pipeline.rb:220-237) so a tailer never observes a run
      # file without its identity header, then keep an append handle with
      # sync = true. Installs itself as RunLog.current. A run-log open
      # failure degrades to nil + a single warning -- it must never raise
      # into the wrapped command.
      def self.open(runs_dir:, command:, argv: [], trigger: 'terminal', cycle: false)
        FileUtils.mkdir_p(runs_dir)
        ts = Time.now.utc.strftime(TIMESTAMP_FORMAT)
        base = "#{Time.now.utc.strftime(FILE_TIMESTAMP_FORMAT)}-#{Process.pid}-#{command}"
        path = File.join(runs_dir, "#{base}.jsonl")
        n = 0
        while File.exist?(path)
          n += 1 # pathological same-ms collision: append -1, -2 before .jsonl
          path = File.join(runs_dir, "#{base}-#{n}.jsonl")
        end

        tmp = Tempfile.new(['run_start', '.tmp'], runs_dir)
        begin
          tmp.write("#{JSON.generate(
            'event' => 'run_start',
            'ts' => ts,
            'command' => command,
            'argv' => argv.to_a,
            'pid' => Process.pid,
            'started_at' => ts,
            'spm_cache_version' => SPMCache::VERSION,
            'trigger' => trigger,
            'cycle' => cycle
          )}\n")
          tmp.close
          File.rename(tmp.path, path)
        rescue StandardError
          tmp.close
          tmp.unlink
          raise
        end

        file = File.open(path, 'a')
        # Every line hits disk at once: a Ctrl-C'd run keeps everything
        # written up to the interrupt (SC2) without any at_exit machinery.
        file.sync = true
        log = new(path: path, file: file, previous_current: current)
        self.current = log
        log
      rescue StandardError => e
        Core::UI.warn "run log disabled: could not open run log in #{runs_dir}: #{e.message}"
        nil
      end

      def initialize(path:, file:, previous_current:)
        @path = path
        @file = file
        @previous_current = previous_current
        @mutex = Mutex.new
        @buffers = {}
        @finished = false
        @disabled = false
        @warned = false
      end

      # The complete file path (header published atomically at open).
      attr_reader :path

      # Tee entry point: writes may arrive in partial chunks, so buffer per
      # stream until a newline arrives -- record_line("par") followed by
      # record_line("tial\n") must land as ONE body line "partial\n".
      def record_line(str, stream)
        buffer = (@buffers[stream] ||= +'')
        buffer << str
        while (nl = buffer.index("\n"))
          record_text(buffer.slice!(0..nl), stream)
        end
      end

      # Emits one body line. `text` is recorded verbatim (D-05) -- trailing
      # newline and ANSI bytes included -- via JSON.generate only: hand-rolled
      # escaping corrupts tailers (RESEARCH "Don't Hand-Roll").
      def record_text(text, stream)
        safe_append(JSON.generate('ts' => Time.now.utc.strftime(TIMESTAMP_FORMAT),
                                  'stream' => stream, 'text' => text))
      end

      # Core::Sh's live_log duck contract (its reader threads hand lines
      # WITH a trailing newline, sh.rb:24-25). StreamSink carries the
      # per-stream tag for callers that need attribution (Pitfall 4).
      def output(line)
        record_text(line, 'out')
      end

      # Emits a structured event line (D-04 vocabulary: run_end, phase,
      # package_start/package_end, ...).
      def event(name, **fields)
        safe_append(JSON.generate({ 'event' => name,
                                    'ts' => Time.now.utc.strftime(TIMESTAMP_FORMAT) }.merge(fields)))
      end

      def tee_out(real_io)
        TeeIO.new(real_io, self, 'out')
      end

      def tee_err(real_io)
        TeeIO.new(real_io, self, 'err')
      end

      # Idempotent exit line. Main.run restores $stdout/$stderr BEFORE calling
      # this (its ensure order) so the exit line is the file's last word.
      # Restores RunLog.current to the value saved at open.
      def finish(status)
        unless @finished
          flush_partial_buffers
          event('run_end',
                'status' => status.to_i,
                'ended_at' => Time.now.utc.strftime(TIMESTAMP_FORMAT))
          @finished = true
        end
        close
        RunLog.current = @previous_current
        nil
      end

      def close
        return if @file.closed?

        @file.flush
        @file.close
      end

      private

      # Emit any trailing partial line (a `print` without newline) before the
      # exit line so a zero-newline tail is not silently dropped (SC2).
      def flush_partial_buffers
        @buffers.each_key do |stream|
          buffer = @buffers[stream]
          next if buffer.empty?

          @buffers[stream] = +''
          record_text(buffer, stream)
        end
      end

      # All append paths route through here: a write failure (ENOSPC,
      # EACCES, closed handle, ...) degrades to unlogged-with-a-single-
      # warning and NEVER raises into the caller -- the wrapped command must
      # not fail or change behavior because logging did (LOGS-01).
      def safe_append(json_line)
        @mutex.synchronize do
          return if @disabled

          @file.write("#{json_line}\n")
        end
      rescue StandardError => e
        @disabled = true
        warn_once("run log disabled (#{File.basename(@path)}): #{e.message}")
        nil
      end

      def warn_once(message)
        return if @warned

        @warned = true
        Core::UI.warn message
      end

      # Write-through wrapper swapped onto $stdout/$stderr by Main.run. The
      # terminal leg is FIRST and never buffered (SC3: interleaving of
      # stdout/stderr must not change); the log leg follows. CLAide reads
      # the STDOUT constant for ANSI decisions (claide command.rb:129), so
      # the global swap is inherently invisible to it -- the delegation
      # below is defense-in-depth for future tty?-probing callers (Pitfall 3).
      class TeeIO
        def initialize(real_io, run_log, stream_tag)
          @real_io = real_io
          @run_log = run_log
          @stream_tag = stream_tag
        end

        # Returns the real IO's byte count, like IO#write.
        def write(str)
          bytes = @real_io.write(str)
          @run_log.record_line(str, @stream_tag)
          bytes
        end

        def puts(*args)
          args = ["\n"] if args.empty?
          args.flatten.each do |arg|
            line = arg.to_s
            write(line.end_with?("\n") ? line : "#{line}\n")
          end
          nil
        end

        def print(*args)
          write(args.join)
          nil
        end

        def <<(str)
          write(str)
          self
        end

        def tty?
          @real_io.tty?
        end

        def isatty
          @real_io.isatty
        end

        def sync
          @real_io.sync
        end

        def sync=(value)
          @real_io.sync = value
        end

        def flush
          @real_io.flush
        end
      end

      # Per-stream adapter satisfying Core::Sh's live_log contract: the
      # single-object form cannot attribute stdout vs stderr (Pitfall 4),
      # so each reader thread gets one of these with its own tag. Responds
      # to output(line) and nothing else.
      class StreamSink
        def initialize(run_log, stream_tag)
          @run_log = run_log
          @stream_tag = stream_tag
        end

        def output(line)
          @run_log.record_text(line, @stream_tag)
        end
      end
    end
  end
end
