# frozen_string_literal: true

require 'open3'
require 'fileutils'

module SPMCache
  module Core
    module Sh
      class << self
        def run(cmd, opts = {})
          live_log = opts[:live_log]
          # Per-stream sinks (Pitfall 4): a single live_log object cannot
          # attribute stdout vs stderr -- each reader thread gets its own
          # sink, falling back to the legacy single object for both streams.
          out_sink = opts[:live_log_out] || live_log
          err_sink = opts[:live_log_err] || live_log
          cwd = opts[:cwd]
          env = opts[:env] || {}

          spawn_opts = {}
          spawn_opts[:chdir] = cwd if cwd

          if out_sink || err_sink
            # Bounded per-stream tails restore failure_detail on THIS path --
            # the capture3 branch below has always had them, but the popen3
            # branch raised detail-free, discarding every captured line (SC2
            # discarded-capture gap). The sink still receives the FULL stream
            # (D-05: only the raised message is bounded to the last
            # FAILURE_DETAIL_LINES per stream, never the run-log file).
            out_tail = []
            err_tail = []
            Open3.popen3(env, cmd, **spawn_opts) do |stdin, stdout, stderr, wait_thr|
              stdin.close
              threads = [
                Thread.new do
                  stdout.each_line do |l|
                    out_sink&.output(l)
                    out_tail << l
                    out_tail.shift if out_tail.size > FAILURE_DETAIL_LINES
                  end
                end,
                Thread.new do
                  stderr.each_line do |l|
                    err_sink&.output(l)
                    err_tail << l
                    err_tail.shift if err_tail.size > FAILURE_DETAIL_LINES
                  end
                end
              ]
              threads.each(&:join)
              status = wait_thr.value
              unless status.success?
                msg = "Command failed (exit #{status.exitstatus}): #{cmd}\n#{failure_detail(out_tail.join,
                                                                                            err_tail.join)}"
                raise GeneralError.new(msg)
              end
            end
            { output: out_tail.join, error: err_tail.join, status: 0 }
          else
            stdout_str, stderr_str, status = Open3.capture3(env, cmd, **spawn_opts)
            # Structured sh event per completed capture3 call (Pitfall 5 /
            # LOGS-01, A2): value-returning captures are consumed as values
            # and never printed today -- cmd + status (never output text)
            # makes swift-package-describe / xcodebuild -list visible in
            # offline reconstruction without spamming. Recorded on success
            # AND failure, before the raise; RunLog's safe_append
            # degradation already guarantees a logging failure can never
            # mask the capture's own result (no second guard layer here).
            RunLog.current&.event('sh', cmd: cmd, status: status.exitstatus)
            unless status.success?
              msg = "Command failed (exit #{status.exitstatus}): #{cmd}\n#{failure_detail(stdout_str, stderr_str)}"
              raise GeneralError.new(msg)
            end
            { output: stdout_str, error: stderr_str, status: status.exitstatus }
          end
        end

        def capture_output(cmd, opts = {})
          result = run(cmd, opts)
          result[:output].to_s.strip
        end

        def run!(cmd, opts = {})
          run(cmd, opts)
        end

        private

        # Tools like xcodebuild write their actual failure reason (compiler
        # errors, linker errors) to STDOUT, not STDERR -- a plain `stderr_str`
        # in the raised error hid the real cause behind an uninformative
        # "Command failed (exit N): <cmd>" for every such failure. Bounded to
        # the last FAILURE_DETAIL_LINES of each stream (not the full log,
        # which can be thousands of lines for a full Xcode build) since the
        # actual error line is almost always near the end, right before the
        # tool's own final failure summary.
        FAILURE_DETAIL_LINES = 60

        def failure_detail(stdout_str, stderr_str)
          [tail_lines(stdout_str), tail_lines(stderr_str)].reject(&:empty?).join("\n")
        end

        def tail_lines(str)
          str.to_s.lines.last(FAILURE_DETAIL_LINES).join.strip
        end
      end
    end
  end
end
