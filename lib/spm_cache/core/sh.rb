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
            # Full per-stream accumulation restores failure_detail on THIS
            # path -- the capture3 branch below has always had it, but the
            # popen3 branch used to raise detail-free, discarding every
            # captured line (SC2 discarded-capture gap). The sink still
            # receives the FULL stream (D-05); only the raised message is
            # bounded to the last FAILURE_DETAIL_LINES per stream, never the
            # run-log file. The return value honors the capture3 contract
            # (WR-03): full streams + the real exitstatus -- never a tailed
            # preview masquerading as output, never a literal status.
            out_buf = +''
            err_buf = +''
            exit_status = 0
            Open3.popen3(env, cmd, **spawn_opts) do |stdin, stdout, stderr, wait_thr|
              stdin.close
              threads = [
                Thread.new do
                  stdout.each_line do |l|
                    out_sink&.output(l)
                    out_buf << l
                  end
                end,
                Thread.new do
                  stderr.each_line do |l|
                    err_sink&.output(l)
                    err_buf << l
                  end
                end
              ]
              threads.each(&:join)
              exit_status = wait_thr.value.exitstatus
              unless wait_thr.value.success?
                error = GeneralError.new("Command failed (exit #{exit_status}): #{cmd}\n#{failure_detail(out_buf,
                                                                                                         err_buf)}")
                # WR-04: the message is tail-bounded for display; recovery
                # callers match the complete streamed content instead.
                error.full_output = out_buf + err_buf
                raise error
              end
            end
            { output: out_buf, error: err_buf, status: exit_status }
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
              error = GeneralError.new("Command failed (exit #{status.exitstatus}): #{cmd}\n#{failure_detail(
                stdout_str, stderr_str
              )}")
              # WR-04 parity with the popen3 branch: full streams stay
              # matchable even though the message carries only the tail.
              error.full_output = stdout_str + stderr_str
              raise error
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
