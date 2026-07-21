# frozen_string_literal: true

require "open3"
require "fileutils"

module SPMCache
  module Core
    module Sh
      class << self
        def run(cmd, opts = {})
          live_log = opts[:live_log]
          cwd = opts[:cwd]
          env = opts[:env] || {}

          output_lines = []

          spawn_opts = {}
          spawn_opts[:chdir] = cwd if cwd

          if live_log
            Open3.popen3(env, cmd, **spawn_opts) do |stdin, stdout, stderr, wait_thr|
              stdin.close
              threads = [
                Thread.new { stdout.each_line { |l| live_log.output(l) } },
                Thread.new { stderr.each_line { |l| live_log.output(l) } },
              ]
              threads.each(&:join)
              status = wait_thr.value
              unless status.success?
                raise GeneralError.new("Command failed (exit #{status.exitstatus}): #{cmd}")
              end
            end
            { output: "", status: 0 }
          else
            stdout_str, stderr_str, status = Open3.capture3(env, cmd, **spawn_opts)
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
