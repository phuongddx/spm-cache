# frozen_string_literal: true

require 'json'
require 'tempfile'
require 'time'
require 'fileutils'

module SPMCache
  module Web
    # Single-instance marker at <project>/.spm-cache/web/server.json
    # (WEB-02): {pid, port, token, started_at}. Written 0600 -- it carries
    # the per-launch token (T-13-03) -- and atomically, so a concurrent
    # `spm-cache web` never observes a half-written marker.
    class Marker
      FILENAME = 'server.json'

      class << self
        def default_path
          File.join(Core::Config.instance.web_dir, FILENAME)
        end

        # Absent, unreadable, malformed, or symlinked-at markers read as
        # nil. The lstat symlink check (T-13-05) defends against a
        # pre-planted symlink a hostile local user swapped in: reading
        # through it would trust THEIR content.
        def read(path: default_path)
          stat = File.lstat(path)
          return nil if stat.symlink?

          JSON.parse(File.read(path))
        rescue JSON::ParserError, SystemCallError
          nil
        end

        def write(pid:, port:, token:, path: default_path)
          dir = File.dirname(path)
          FileUtils.mkdir_p(dir)
          # Tempfile in the marker dir + File.rename: rename replaces the
          # directory entry itself, never writing through a pre-planted
          # symlink (T-13-05; provenance-sidecar pattern, build_pipeline).
          # chmod lands on the tempfile BEFORE the rename so the file is
          # never observable world-readable at the final path.
          tmp = Tempfile.new(['server', '.json'], dir)
          begin
            tmp.write(JSON.generate(
                        'pid' => pid,
                        'port' => port,
                        'token' => token,
                        'started_at' => Time.now.utc.iso8601
                      ))
            tmp.close
            File.chmod(0o600, tmp.path)
            File.rename(tmp.path, path)
          ensure
            tmp.close unless tmp.closed?
            File.unlink(tmp.path) if File.exist?(tmp.path)
          end
          path
        end

        def clear(path: default_path)
          File.unlink(path) if File.exist?(path)
          nil
        end

        # True only when the pid parses and Process.kill(0, pid) succeeds
        # -- Errno::ESRCH means dead, any other error (e.g. EPERM) means
        # the pid exists (run_log.rb:391-399 precedent, cited per plan).
        # An unparseable pid protects nothing, same posture as
        # RunLog#protected_run?.
        def live?(entry)
          return false unless entry.is_a?(Hash)

          pid = entry['pid']
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
