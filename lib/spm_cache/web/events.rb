# frozen_string_literal: true

require 'json'
require 'time'
require 'timeout'

require 'spm_cache/web/read_models/runs'

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

      # D-07/Pitfall 3, pinned verbatim -- the frontend renders it as-is.
      PRUNED_NOTICE = 'run log pruned while viewing; switching to newest'
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

        # ?run= names (14-03): parse_resume_id's exact posture and SHAPE
        # -- the filename regex + expand_path containment BEFORE any
        # File.open, hostile input → nil (silent current-or-newest
        # fallback, never an error surface worth probing), while a
        # well-formed name whose file vanished is a first-class honest
        # pruned case (exists: false → the pinned notice + fresh
        # replay, D-07).
        def resolve_run_name(name, runs_dir:)
          return nil unless name.is_a?(String) && RUN_NAME.match?(name)

          path = File.expand_path(name, runs_dir)
          return nil unless contained?(path, runs_dir)

          { name: name, path: path, exists: File.file?(path) }
        end

        def contained?(path, runs_dir)
          root = File.expand_path(runs_dir)
          path == root || path.start_with?("#{root}/")
        end

        # D-13 fresh-connect choice: the newest file whose header pid is
        # alive and whose file lacks run_end (the live run); else the
        # newest file overall; nil for an empty runs dir. Derived from
        # disk on every call (CP10) -- never memoized. The derivation
        # itself lives in ReadModels::Runs (14-03): the stream, hello,
        # and /api/runs share ONE status/choice path -- zero drift.
        def choose_run(runs_dir:)
          ReadModels::Runs.current_path(runs_dir: runs_dir)
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

        # The appended-bytes read shared by the tailer thread and the
        # per-client pinned follows (14-03): seek past the buffered
        # partial tail, read to EOF, split complete \n-terminated lines
        # out of the buffer, advance the offset by line.bytesize per
        # line (run_log.rb:216-240's buffer-until-newline, inverted) --
        # ONE line-splitting implementation, two drivers. Binary reads
        # only ('rb', Pitfall 5); returns nil when nothing was
        # appended, else [entries, new_offset].
        def drain_appended(io, file:, offset:, buffer:)
          io.seek(offset + buffer.bytesize)
          chunk = io.read
          return unless chunk && !chunk.empty?

          entries = []
          buffer << chunk
          while (nl = buffer.index("\n"))
            line = buffer.slice!(0..nl)
            offset += line.bytesize
            entries << Entry.new(file: file, offset: offset, line: utf8!(line))
          end
          [entries, offset]
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

        # CR-01: SizedQueue#pop only gained a `timeout:` keyword on Ruby
        # 3.2 -- on 3.1 (the gem's own declared minimum, and a CI-tested
        # leg) the C implementation absorbs the Hash as the legacy
        # positional `non_block` argument, so `pop(timeout: N)` silently
        # degenerates into a NON-blocking `pop(true)` that raises
        # ThreadError on an empty queue instead of blocking. This
        # Timeout-based wrapper blocks on a plain `queue.pop` (portable
        # across 3.1-3.3) and bounds the wait from the outside, so it
        # behaves identically to `pop(timeout:)` on every supported
        # Ruby.
        def pop_with_timeout(queue, timeout)
          Timeout.timeout(timeout) { queue.pop }
        rescue Timeout::Error
          nil
        end
      end

      attr_reader :broadcaster, :tailer

      def initialize(config:, poll_interval: POLL_INTERVAL,
                     heartbeat_seconds: HEARTBEAT_SECONDS, queue_cap: QUEUE_CAP)
        @config = config
        @heartbeat_seconds = heartbeat_seconds
        # The pinned follows poll at this granularity too (14-03), so
        # specs bound them with the same keyword.
        @poll_interval = poll_interval
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
      # Hello from the shared derivation (identity + status + lock +
      # now), replay/resume entries, then the queue pop loop with
      # exactly-once suppression, the pinned per-connection follow, and
      # the shutdown sentinel. Dead clients surface as EPIPE/ECONNRESET
      # on write and are handled here; WEBrick already ends the response
      # (httpresponse.rb:243-249).
      def stream(client, resume: nil, pin: nil)
        pruned = resume && !resume[:exists] # well-formed name, vanished file
        follow = nil
        run = nil

        if pin
          if pin[:exists]
            derived = ReadModels::Runs.derive(pin[:path])
            if derived
              begin
                follow = PinnedFollow.new(pin[:path])
                run = { name: pin[:name], path: pin[:path], offset: 0, derived: derived }
              rescue Errno::ENOENT
                pruned = true # vanished between resolve and open (D-07)
              end
            else
              pruned = true # unreadable or vanished between resolve and derive
            end
          else
            pruned = true # ?run= named a well-formed run that is gone
          end
        end

        run ||= (!pruned && live_resume(resume)) || fresh_run
        deliver_hello(client, run)
        deliver_notice(client, PRUNED_NOTICE) if pruned # D-07: honest fallback

        last_file = run && run[:name]
        last_offset = run && run[:offset]
        if run
          begin
            self.class.each_entry(run[:path], run[:offset]) do |entry|
              client.write(self.class.frame(event: 'entry', data: entry.line, id: entry.id))
              last_file = entry.file
              last_offset = entry.offset
            end
          rescue Errno::ENOENT
            # Pruned between parse and open mid-flight: same honest notice,
            # then the fresh fallback (D-07 / research Pattern 2 sketch).
            deliver_notice(client, PRUNED_NOTICE)
            follow = nil # the pinned file is gone: the fallback is unpinned
            fresh = fresh_run
            if fresh
              last_file = fresh[:name]
              last_offset = fresh[:offset]
              self.class.each_entry(fresh[:path], fresh[:offset]) do |entry|
                client.write(self.class.frame(event: 'entry', data: entry.line, id: entry.id))
                last_file = entry.file
                last_offset = entry.offset
              end
            end
          end
        end
        # The pinned follow picks up exactly where its replay ended.
        follow&.seek(last_offset)
        pop_loop(client, last_file, last_offset, follow: follow)
      rescue Errno::EPIPE, Errno::ECONNRESET, IOError
        nil
      ensure
        follow&.close
        @broadcaster.unregister(client)
      end

      def deliver_notice(client, message)
        client.write(self.class.frame(
                       event: 'notice',
                       data: JSON.generate('message' => message)
                     ))
      end

      # Server#shutdown seam (WEB-03): stop the tailer, then push the
      def shutdown!
        @tailer.stop
        @broadcaster.shutdown!
      end

      private

      # A resume whose target still exists: identity + status derive
      # through Runs -- the ONE derivation (hello and /api/runs agree
      # by construction, 14-03). A vanished target is not an error
      # surface: the pruned notice lands with the retention interplay
      # (D-07).
      def live_resume(resume)
        return nil unless resume && resume[:exists]

        derived = ReadModels::Runs.derive(resume[:path])
        return nil unless derived

        { name: resume[:name], path: resume[:path], offset: resume[:offset], derived: derived }
      end

      def fresh_run
        path = self.class.choose_run(runs_dir: @config.runs_dir)
        return nil unless path

        derived = ReadModels::Runs.derive(path)
        return nil unless derived

        { name: File.basename(path), path: path, offset: 0, derived: derived }
      end

      # Hello carries the in-stream retry: field (RETRY_MS), the run
      # name, the parsed run_start header, the derived status, the lock
      # state, and the server 'now' stamp (D-06/D-11/D-12; 14-03). The
      # status and lock are Runs' derivation -- the SAME read model
      # /api/runs serves, so the card's data and the dropdown's entries
      # agree by construction. The lock field is server-internal: the
      # client renders nothing for it (14-UI-SPEC external-run row).
      # String keys throughout: JSON.generate drops symbol keys
      # (state.rb:44-53 discipline).
      def deliver_hello(client, run)
        lock = ReadModels::Runs.lock_state(config: @config)
        data =
          if run
            { 'run' => run[:derived]['run'], 'header' => run[:derived]['header'],
              'status' => run[:derived]['status'], 'lock' => lock,
              'now' => Time.now.utc.iso8601 }
          else
            { 'run' => nil, 'header' => nil, 'status' => 'idle', 'lock' => lock,
              'now' => Time.now.utc.iso8601 }
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
      #
      # Pinned connections (follow, 14-03): ENTRY delivery is scoped to
      # the named run -- the per-connection follow is the SOLE entry
      # source, so the shared tailer's entries (possibly for a newer
      # run) are dropped and the stream is never re-pointed, while the
      # pop timeout shortens to the poll interval so the follow ticks
      # at poll granularity and the heartbeat still fires only at
      # heartbeat cadence. Switch/notice broadcasts are NOT filtered: a
      # pinned client stays broadcaster-registered like every client;
      # acting on a switch is the CLIENT's job (drop the pin, close,
      # reconnect unpinned -- 14-05's D-04 handler).
      def pop_loop(client, last_file, last_offset, follow: nil)
        timeout = follow ? [@heartbeat_seconds, @poll_interval].min : @heartbeat_seconds
        last_ping = Time.now
        loop do
          item = self.class.pop_with_timeout(client.queue, timeout)
          case item
          when ShutdownSentinel
            break
          when nil
            if follow
              follow.each_new_entry do |entry|
                flush_dropped(client)
                client.write(self.class.frame(event: 'entry', data: entry.line, id: entry.id))
                last_file = entry.file
                last_offset = entry.offset
              end
              if Time.now - last_ping >= @heartbeat_seconds
                client.write(Client::HEARTBEAT_COMMENT)
                last_ping = Time.now
              end
            else
              # Pop-timeout IS the heartbeat timer (research alternative
              # table: no dedicated thread): a comment frame the SSE parser
              # ignores, keeping the connection visibly alive -- and
              # probing the writer, so a dead client is discovered here
              # rather than by the next entry.
              client.write(Client::HEARTBEAT_COMMENT)
              # (loop: the timeout is the timer -- no break, keep popping)
            end

          when Entry
            # Pinned: the follow is the sole entry source (see above).
            next if follow

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

      # A per-connection follow of ONE pinned run (?run=, 14-03): the
      # client's disk replay covered the named run from byte 0; this
      # reader then delivers ONLY that file's growth through the shared
      # drain machinery (Events.drain_appended). The held fd keeps an
      # unlinked file readable (POSIX, D-07), so a retention prune
      # never breaks a live pinned view. Discovery of newer runs is the
      # BROADCASTER's business (the switch broadcast reaches pinned
      # clients like every client) -- this stream is never re-pointed.
      class PinnedFollow
        def initialize(path)
          @name = File.basename(path)
          @io = File.open(path, 'rb')
          @offset = 0
          @buffer = String.new(encoding: Events::Tailer::BINARY)
        end

        attr_reader :name

        # After the replay: continue from exactly where it ended.
        def seek(offset)
          @offset = offset
          @buffer.clear
        end

        def each_new_entry(&block)
          return unless @io

          result = Events.drain_appended(@io, file: @name, offset: @offset, buffer: @buffer)
          return unless result

          entries, @offset = result
          entries.each(&block)
        end

        def close
          @io&.close
          @io = nil
        rescue IOError
          nil
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
          @prune_notified = false # D-07: one pruned notice per episode
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

        # Discovery each tick (glob + sort; lexicographic == chronological
        # per the filename format). FORWARD-ONLY switching: a newer run
        # starting mid-view switches the follow to its byte 0 with a
        # switch event (D-04). A file that merely VANISHED from the
        # listing (retention pruned the served run) keeps its held fd --
        # POSIX keeps an unlinked file readable (D-07) -- and an absent
        # runs dir (transient) is simply no glob hits.
        #
        # CR-02: the very-first attach (@path.nil? -- server boot before
        # any run exists, or the switch_to rescue's Errno::ENOENT
        # recovery resetting @path to nil) is symmetric with switch_to:
        # replay from byte 0 AND publish a Switch(previous: nil). A
        # client already parked in pop_loop's idle hello (run: nil) has
        # no replay of its own to cover the new run -- it depends
        # entirely on the tailer to deliver identity + content. This is
        # safe unconditionally: pop_loop's exactly-once dedup (id <=
        # last delivered, and `next if item.run == last_file`) already
        # suppresses these now-published entries/switch for any client
        # whose own connect-time replay already covered the range, so
        # only the previously-idle client newly receives what it was
        # missing.
        def discover
          newest = Dir.glob(File.join(@config.runs_dir, '*.jsonl')).sort.last
          return unless newest

          if @path.nil?
            attach(newest, from_byte0: true)
            @broadcaster.publish_switch(run: File.basename(newest), previous: nil)
          elsif newest > @path
            switch_to(newest)
          end
        end

        def switch_to(path)
          previous = File.basename(@path)
          attach(path, from_byte0: true) # D-04: the new run replays from byte 0
          @broadcaster.publish_switch(run: File.basename(path), previous: previous)
        rescue Errno::ENOENT
          # Candidate vanished between glob and open (retention race):
          # pin the honest notice once per episode and re-discover on the
          # next tick (D-07).
          publish_pruned_notice
          close_io
          @path = nil
        end

        def publish_pruned_notice
          return if @prune_notified

          @prune_notified = true
          @broadcaster.publish_notice(Events::PRUNED_NOTICE)
        end

        def attach(path, from_byte0:)
          @path = path
          @prune_notified = false # a successful attach re-arms the notice
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
        # line-splitting itself lives in Events.drain_appended (shared
        # with the per-client pinned follows, 14-03). The offset
        # advances by line.bytesize only on complete lines, and the
        # published id records the offset AFTER the newline.
        def read_appended
          return unless @io

          # Seek past the buffered partial tail: the offset advances only
          # on complete lines, so the bytes already held in @buffer must
          # not be read (and re-buffered) a second time on the next tick.
          result = Events.drain_appended(@io, file: File.basename(@path),
                                              offset: @offset, buffer: @buffer)
          return unless result

          entries, @offset = result
          entries.each do |entry|
            @broadcaster.publish_entry(file: entry.file, offset: entry.offset,
                                       line: entry.line)
          end
        end
      end
    end
  end
end
