# frozen_string_literal: true

require 'json'

module SPMCache
  module Web
    # Web::Events -- the live-log streaming spine (LOGS-02/03/04). One
    # tailer thread follows the shared runs dir; one broadcaster fans
    # complete JSONL lines out to per-client bounded queues; the
    # /api/events body proc (Router#events_stream) is the per-client
    # writer. The transport is writer-agnostic by construction: terminal,
    # watch-cycle (Phase 12 D-09), and future UI runs are all just files
    # in the runs dir.
    #
    # Truth stays on disk (CP10): every connect re-derives run identity
    # and status from the runs dir; the tailer memoizes ONLY its own read
    # position -- fd + byte offset + partial-line buffer (research
    # Pitfall 7). No coupling to Core::Watcher or Command::Watch exists
    # or is wanted (CP5/CP6 hygiene IS the absence of coupling).
    class Events
      # CP11 constants (research Open Question 3, resolved): heartbeat
      # ~15s, queue cap order 10^3. Injectable per constructor keyword so
      # no spec ever sleeps 15s. The in-stream `retry:` field is the ONLY
      # EventSource reconnect-time control (WHATWG parse rules) -- an HTTP
      # Retry: header plays no role.
      HEARTBEAT_SECONDS = 15
      QUEUE_CAP = 1000
      RETRY_MS = 3000
      POLL_INTERVAL = 0.25

      # Run-file names: '%Y%m%dT%H%M%S%3NZ-<pid>-<verb>' (run_log.rb:31,
      # 117) plus the optional same-millisecond collision suffix '-<n>'
      # (run_log.rb:120-123) and '.jsonl'. Names contain no colons and
      # sort chronologically (EDGE ordering, run_log.rb:29-31).
      RUN_NAME = /\A\d{8}T\d{6}\d{3}Z-\d+-[a-z]+(-\d+)?\.jsonl\z/

      # Composite resume id '<run-filename>:<byte-offset>' -- exactly what
      # a reconnecting EventSource sends as Last-Event-ID. Research-
      # VERBATIM regex (Pitfall 4): the optional (-\d+)? collision group
      # is load-bearing -- dropping it silently demotes collision-suffixed
      # runs to fresh replay (an exact-resume miss, LOGS-03).
      RESUME_ID = /\A(\d{8}T\d{6}\d{3}Z-\d+-[a-z]+(-\d+)?)\.jsonl:(\d+)\z/

      # One complete JSONL line as delivered on the wire. data is the
      # line VERBATIM: it is already JSON, and JSON.generate escaped
      # embedded newlines at write time (run_log.rb:248), so framing is
      # passthrough-safe. The id offset is AFTER the consumed newline, so
      # resuming at an id seeks exactly to the next line (Pitfall 5).
      Entry = Struct.new(:file, :offset, :line, keyword_init: true) do
        def id
          "#{file}:#{offset}"
        end
      end

      # D-04 auto-switch: the followed run changed; the previous run
      # stays reachable via the notice's run id.
      Switch = Struct.new(:run, :previous, keyword_init: true)

      # Server-origin notices (pruned-run fallback). The CP11 drop-oldest
      # notice is synthesized client-side from the per-client drop count.
      Notice = Struct.new(:message, keyword_init: true)

      # WEB-03: WEBrick's accept-loop ensure JOINS every connection thread
      # (webrick server.rb:210) -- a body proc looping forever would hang
      # Server#shutdown and break the TERM/INT exit-0 contract. This
      # sentinel ends every client loop; type identity is the signal.
      ShutdownSentinel = Class.new

      class << self
        # Last-Event-ID is ATTACKER INPUT (Pitfall 4 / T-13-04 posture):
        # the filename must match the run-file regex and the expanded path
        # must stay contained under runs_dir BEFORE any File.open. Any
        # failure is nil -> fresh replay, never an error surface worth
        # probing. `exists:` distinguishes a vanished (pruned) run -- a
        # well-formed name that no longer exists -- from hostile input.
        def parse_resume_id(id, runs_dir:)
          return nil unless id.is_a?(String)

          match = RESUME_ID.match(id)
          return nil unless match

          # Group 1 excludes the '.jsonl' extension -- reattach it for the
          # filesystem path; group 3 is the byte offset.
          name = "#{match[1]}.jsonl"
          path = File.expand_path(name, runs_dir)
          return nil unless contained?(path, runs_dir)

          { name: name, offset: match[3].to_i, path: path, exists: File.file?(path) }
        end

        # ?run= names (14-03 consumes this): a bare run-filename resolves
        # to its absolute path under runs_dir with the same validation
        # posture as parse_resume_id, or nil.
        def resolve_run_name(name, runs_dir:)
          return nil unless name.is_a?(String) && RUN_NAME.match?(name)

          path = File.expand_path(name, runs_dir)
          contained?(path, runs_dir) && File.file?(path) ? path : nil
        end

        def contained?(path, runs_dir)
          root = File.expand_path(runs_dir)
          path == root || path.start_with?("#{root}/")
        end

        # D-13 fresh-connect choice: the newest file whose header pid is
        # alive and whose file lacks run_end (the live run); else the
        # newest file overall; nil for an empty runs dir. Derived from
        # disk on every call (CP10) -- never memoized.
        def choose_run(runs_dir:)
          files = Dir.glob(File.join(runs_dir, '*.jsonl')).sort
          return nil if files.empty?

          files.reverse_each do |path|
            state = run_state(path)
            return path if state && state[:status] == 'running'
          end
          files.last
        end

        # Header + derived status for one run file, in a single pass:
        # 'running' (pid alive, no run_end), 'completed' (run_end
        # present), 'interrupted' (pid dead, no run_end -- CP14 honesty:
        # a dead pid is never 'running'; the missing run_end only means
        # the exit status is unknown). nil when the header is unreadable.
        def run_state(path)
          header = nil
          has_run_end = false
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
                has_run_end = true
                break
              end
            end
          end
          return nil unless header

          status =
            if has_run_end
              'completed'
            elsif pid_alive?(header['pid'])
              'running'
            else
              'interrupted'
            end
          { header: header, status: status }
        rescue StandardError
          nil
        end

        # run_log.rb:395-402 semantics (private there): Process.kill(0,
        # pid) probes liveness -- ESRCH means dead; any other error (e.g.
        # EPERM) means the pid exists, so treat as alive.
        def pid_alive?(pid)
          return false unless pid.is_a?(Integer)

          Process.kill(0, pid)
          true
        rescue Errno::ESRCH
          false
        rescue StandardError
          true
        end

        # Replay/resume read: yields an Entry per complete JSONL line from
        # byte `offset` (default 0) to EOF. Binary mode only ('rb') --
        # text transcodings corrupt byte offsets (Pitfall 5). A trailing
        # partial line (no newline yet) is NOT yielded: its newline has
        # not landed, and the tailer will publish the complete line when
        # it does -- yielding the partial here would double-deliver its
        # bytes (run_log.rb:216-240 buffer-until-newline, inverted).
        def each_entry(path, offset = 0)
          return to_enum(:each_entry, path, offset) unless block_given?

          name = File.basename(path)
          File.open(path, 'rb') do |io|
            io.seek(offset)
            io.each_line do |line|
              break unless line.end_with?("\n")

              offset += line.bytesize
              yield Entry.new(file: name, offset: offset, line: utf8!(line))
            end
          end
          nil
        end

        # Binary reads tag strings ASCII-8BIT; the writer guarantees valid
        # UTF-8 bytes (scrubbed at write, run_log.rb:248), so the tag is
        # corrected WITHOUT transcoding -- byte offsets are untouched
        # either way ('rb' only, Pitfall 5).
        def utf8!(binary_line)
          binary_line.force_encoding(Encoding::UTF_8)
        end

        # One SSE frame = ONE out.write call (one chunk per frame), built
        # first as a whole string so raw-socket assertions are
        # unambiguous against the chunked byte stream. JSONL lines arrive
        # newline-terminated; SSE framing supplies its own line ending,
        # so one trailing newline is stripped from data (the payload is
        # single-line JSON by construction).
        def frame(event:, data:, id: nil, retry_ms: nil)
          parts = []
          parts << "retry: #{retry_ms}" if retry_ms
          parts << "id: #{id}" if id
          parts << "event: #{event}"
          parts << "data: #{data.to_s.sub(/\n\z/, '')}"
          "#{parts.join("\n")}\n\n"
        end
      end

      attr_reader :broadcaster, :tailer

      def initialize(config:, poll_interval: POLL_INTERVAL,
                     heartbeat_seconds: HEARTBEAT_SECONDS, queue_cap: QUEUE_CAP)
        @config = config
        @heartbeat_seconds = heartbeat_seconds
        @broadcaster = Broadcaster.new(queue_cap: queue_cap)
        @tailer = Tailer.new(config: config, broadcaster: @broadcaster,
                             poll_interval: poll_interval)
      end

      # Route body-proc entry (Router#events_stream): create the client,
      # join the registry, and start the tailer on FIRST register -- the
      # construction itself is lazy-threaded so every non-streaming boot
      # (all existing with_server specs) stays thread-free.
      def register(out)
        client = Client.new(out: out, queue_cap: @broadcaster.queue_cap)
        @broadcaster.register(client)
        @tailer.start
        client
      end

      # The per-client loop -- runs INSIDE the WEBrick body proc: the
      # connection thread IS the per-client writer (research Pattern 3).
      # Hello from disk, replay/resume entries, then the queue pop loop
      # with exactly-once suppression and the shutdown sentinel. Dead
      # clients surface as EPIPE/ECONNRESET on write and are handled
      # here; WEBrick already ends the response (httpresponse.rb:243-249).
      def stream(client, resume: nil)
        run = live_resume(resume) || fresh_run
        deliver_hello(client, run)

        last_file = run && run[:name]
        last_offset = run && run[:offset]
        if run
          self.class.each_entry(run[:path], run[:offset]) do |entry|
            client.write(self.class.frame(event: 'entry', data: entry.line, id: entry.id))
            last_file = entry.file
            last_offset = entry.offset
          end
        end
        pop_loop(client, last_file, last_offset)
      rescue Errno::EPIPE, Errno::ECONNRESET, IOError
        nil
      ensure
        @broadcaster.unregister(client)
      end

      # Server#shutdown seam (WEB-03): stop the tailer, then push the
      # sentinel to every client queue so each body proc's pop returns
      # and WEBrick's connection-thread join completes.
      def shutdown!
        @tailer.stop
        @broadcaster.shutdown!
      end

      private

      # A resume whose file vanished between parse and open is not an
      # error surface: fall through to the fresh choice (the pruned-run
      # notice lands with the retention interplay, D-07).
      def live_resume(resume)
        return nil unless resume && resume[:exists]

        state = self.class.run_state(resume[:path])
        return nil unless state

        resume.merge(state: state)
      end

      def fresh_run
        path = self.class.choose_run(runs_dir: @config.runs_dir)
        return nil unless path

        state = self.class.run_state(path)
        return nil unless state

        { name: File.basename(path), path: path, offset: 0, state: state }
      end

      # Hello carries the in-stream retry: field (RETRY_MS), the run
      # name, the parsed run_start header, and the derived status
      # (D-11/D-13). String keys throughout: JSON.generate drops symbol
      # keys (state.rb:44-53 discipline).
      def deliver_hello(client, run)
        data =
          if run
            { 'run' => run[:name], 'header' => run[:state][:header],
              'status' => run[:state][:status] }
          else
            { 'run' => nil, 'header' => nil, 'status' => 'idle' }
          end
        client.write(self.class.frame(event: 'hello', data: JSON.generate(data),
                                      retry_ms: RETRY_MS))
      end

      # Exactly-once replay->queue handoff: registration (T0) starts the
      # tailer feeding the queue while the disk replay drains toward EOF
      # (T1) -- a line appended in (T0, T1] is both on disk AND queued,
      # so queued entries with composite id <= the last delivered id are
      # dropped. Filenames sort chronologically, so the (file, offset)
      # pair compare never suppresses a newer file's entries with an
      # older file's offset.
      def pop_loop(client, last_file, last_offset)
        loop do
          item = client.queue.pop(timeout: @heartbeat_seconds)
          case item
          when ShutdownSentinel
            break
          when nil
            # Pop-timeout IS the heartbeat timer (research alternative
            # table: no dedicated thread): a comment frame the SSE parser
            # ignores, keeping the connection visibly alive -- and
            # probing the writer, so a dead client is discovered here
            # rather than by the next entry.
            client.write(Client::HEARTBEAT_COMMENT)
            # (loop: the timeout is the timer -- no break, keep popping)

          when Entry
            # Array#<=> compares element-wise (filename, then offset);
            # Array has no #<=, so the spaceship result is compared.
            next if last_file && ([item.file, item.offset] <=> [last_file, last_offset]) <= 0

            flush_dropped(client)
            client.write(self.class.frame(event: 'entry', data: item.line, id: item.id))
            last_file = item.file
            last_offset = item.offset
          when Switch
            # No switch notice when the client already views the run
            # (its own replay covered the switch target).
            next if item.run == last_file

            client.write(self.class.frame(
                           event: 'switch',
                           data: JSON.generate('run' => item.run, 'previous' => item.previous)
                         ))
          when Notice
            client.write(self.class.frame(
                           event: 'notice',
                           data: JSON.generate('message' => item.message)
                         ))
          end
        end
      end

      # CP11: the per-client drop count flushes as ONE pinned notice --
      # '{N} lines dropped' -- at the dropped entries' would-be position,
      # immediately before the next delivered frame.
      def flush_dropped(client)
        dropped = client.take_dropped!
        return if dropped.zero?

        client.write(self.class.frame(
                       event: 'notice',
                       data: JSON.generate('message' => "#{dropped} lines dropped")
                     ))
      end

      # One connected SSE client: the bounded queue the tailer feeds and
      # the response writer the body proc owns. One frame = ONE write
      # call = one WEBrick chunk (ChunkedWrapper#write flushes per call,
      # httpresponse.rb:561-572).
      class Client
        # Heartbeat comment frame (CP11 ~15s cadence via pop timeout):
        # the SSE processing model ignores comment lines.
        HEARTBEAT_COMMENT = ": ping\n\n"

        def initialize(out:, queue_cap:)
          @out = out
          @queue = SizedQueue.new(queue_cap)
          @dropped = 0
          @drop_mutex = Mutex.new
        end

        attr_reader :queue

        def write(frame_text)
          @out.write(frame_text)
        end

        # CP11 drop accounting is per-client: entries evicted from this
        # client's queue since the last delivery, flushed as ONE notice.
        def record_drop!
          @drop_mutex.synchronize { @dropped += 1 }
        end

        def take_dropped!
          @drop_mutex.synchronize do
            dropped = @dropped
            @dropped = 0
            dropped
          end
        end
      end

      # Fan-out registry (research Pattern 3 -- NO repo analog exists;
      # built from the research, not from any repo file). ONE Mutex
      # guards the client set with a fixed single lock order (the
      # run_log.rb:189-190 discipline: one lock per concern, never
      # nested acquisition in the reverse order). Enqueues happen under
      # the registry lock but are always non-blocking: a slow client's
      # full queue must never wedge the registry -- drop-oldest handles
      # the pressure (CP11).
      class Broadcaster
        SENTINEL = ShutdownSentinel.new

        def initialize(queue_cap:)
          @queue_cap = queue_cap
          @clients = []
          @mutex = Mutex.new
          @shutdown = false
        end

        attr_reader :queue_cap

        # A register racing the sentinel fan-out (a connect landing while
        # the server shuts down) must not become a sentinel-less
        # straggler: WEBrick's accept-loop join would hang on its body
        # proc (WEB-03). Under the registry lock, a shutdown-state
        # register immediately receives its sentinel.
        def register(client)
          @mutex.synchronize do
            @clients.push(client)
            enqueue_sentinel(client) if @shutdown
          end
          client
        end

        def unregister(client)
          @mutex.synchronize { @clients.delete(client) }
          nil
        end

        def clients
          @mutex.synchronize { @clients.dup }
        end

        def publish_entry(file:, offset:, line:)
          fan_out { Entry.new(file: file, offset: offset, line: line) }
        end

        def publish_switch(run:, previous:)
          fan_out { Switch.new(run: run, previous: previous) }
        end

        def publish_notice(message)
          fan_out { Notice.new(message: message) }
        end

        # WEB-03: push the sentinel to EVERY client queue so each body
        # proc's pop returns and the proc ends before WEBrick's
        # accept-loop ensure joins connection threads (webrick
        # server.rb:210). A sentinel that displaces a queued entry at
        # shutdown loses nothing recoverable: the browser reconnects
        # with Last-Event-ID and the resume is byte-exact. May be called
        # from a Signal.trap context (Server#shutdown <- Command::Web's
        # TERM/INT trap): Mutex#synchronize raises ThreadError there
        # (Ruby >= 3), so the fan-out falls back to a short-lived
        # thread; clients observe the sentinel within one heartbeat
        # period regardless.
        def shutdown!
          fan_out_sentinels
        rescue ThreadError
          Thread.new { fan_out_sentinels }
        end

        private

        def fan_out
          @mutex.synchronize do
            item = yield
            @clients.each { |client| enqueue(client, item) }
          end
          nil
        end

        def fan_out_sentinels
          @mutex.synchronize do
            return if @shutdown # idempotent: exactly one sentinel per client

            @shutdown = true
            @clients.each { |client| enqueue_sentinel(client) }
          end
          nil
        end

        # Drop-oldest under pressure (CP11): discard the OLDEST queued
        # entry to make room. MRI Queue#push/pop are trap-safe, but this
        # path runs on the tailer thread; the client-side accounting and
        # its '{N} lines dropped' notice flush on delivery.
        def enqueue(client, item)
          client.queue.push(item, true)
        rescue ThreadError
          begin
            client.queue.pop(true) # discard the OLDEST (CP11)
            client.record_drop!
          rescue ThreadError
            nil # drained concurrently: nothing was dropped
          end
          client.queue.push(item, true)
        end

        def enqueue_sentinel(client)
          client.queue.push(SENTINEL, true)
        rescue ThreadError
          begin
            client.queue.pop(true) # displace an entry; recoverable via Last-Event-ID
          rescue ThreadError
            nil
          end
          client.queue.push(SENTINEL, true)
        end
      end

      # The single poll thread over the runs dir (research Pattern 2;
      # watcher.rb:57-67 poll + continue-on-error precedent). Follows ONE
      # file at a time and publishes complete lines to the broadcaster.
      # Memoizes ONLY its read position -- fd + byte offset + buffer
      # (CP10 / research Pitfall 7): this thread is never a source of
      # truth for run identity; every connect re-derives from disk.
      # Binary reads only ('rb'): text transcodings corrupt byte offsets
      # (Pitfall 5).
      class Tailer
        BINARY = Encoding::ASCII_8BIT

        def initialize(config:, broadcaster:, poll_interval: Events::POLL_INTERVAL)
          @config = config
          @broadcaster = broadcaster
          @poll_interval = poll_interval
          @start_mutex = Mutex.new
          @started = false
          @stopped = false
          @path = nil
          @io = nil
          @offset = 0
          @buffer = String.new(encoding: BINARY)
        end

        # The followed file's path (nil before the first attach) -- the
        # spec-side seam for observing attach without sleeping.
        attr_reader :path

        # Idempotent start: the FIRST register starts the thread; every
        # boot without an SSE request never calls this (lazy Events).
        def start
          @start_mutex.synchronize do
            return if @started || @stopped

            @started = true
            Thread.new { run_loop }
          end
          nil
        end

        def stop
          @stopped = true
        end

        def running?
          @start_mutex.synchronize { @started && !@stopped }
        end

        private

        def run_loop
          until @stopped
            tick
            sleep(@poll_interval) unless @stopped
          end
        ensure
          close_io
        end

        # Continue-on-error posture (watcher.rb:64-67): a transient
        # stat/read failure never kills the tailer -- the next tick
        # recovers.
        def tick
          poll_once
        rescue StandardError
          nil
        end

        def poll_once
          discover
          read_appended
        end

        # Discovery by glob + sort (lexicographic == chronological per
        # the filename format). Task 1 scope: attach when not yet
        # following; the switch-over notice (D-04) extends this seam.
        def discover
          return if @path

          newest = Dir.glob(File.join(@config.runs_dir, '*.jsonl')).sort.last
          attach(newest, from_byte0: false) if newest
        end

        def attach(path, from_byte0:)
          @path = path
          @offset = from_byte0 ? 0 : last_complete_line_offset(path)
          @buffer = String.new(encoding: BINARY)
          # Held fd: retention's unlink keeps an unlinked file readable
          # through its descriptor (POSIX, D-07 fd survival).
          @io = File.open(path, 'rb')
        end

        def close_io
          @io&.close
          @io = nil
        rescue IOError
          nil
        end

        # Attach offset: the byte just past the LAST complete line, so
        # only lines appended after attach are published (client replays
        # cover history) and a partially-written trailing line is picked
        # up COMPLETE once its newline lands. Reverse chunked scan.
        def last_complete_line_offset(path)
          size = File.size(path)
          pos = size
          window = +''
          while pos.positive?
            step = [512, pos].min
            pos -= step
            window.prepend(File.binread(path, step, pos))
            nl = window.rindex("\n")
            return pos + nl + 1 if nl
          end
          0
        end

        # run_log.rb:216-240's buffer-until-newline, inverted: bytes in,
        # complete \n-terminated lines out, partial tail buffered. The
        # offset advances by line.bytesize only on complete lines, and
        # the published id records the offset AFTER the newline.
        def read_appended
          return unless @io

          # Seek past the buffered partial tail: the offset advances only
          # on complete lines, so the bytes already held in @buffer must
          # not be read (and re-buffered) a second time on the next tick.
          @io.seek(@offset + @buffer.bytesize)
          chunk = @io.read
          return unless chunk && !chunk.empty?

          @buffer << chunk
          while (nl = @buffer.index("\n"))
            line = @buffer.slice!(0..nl)
            @offset += line.bytesize
            @broadcaster.publish_entry(file: File.basename(@path),
                                       offset: @offset,
                                       line: Events.utf8!(line))
          end
        end
      end
    end
  end
end
