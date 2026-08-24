# frozen_string_literal: true

module SPMCache
  module Core
    # Filesystem-watch loop that auto-regenerates the proxy package when the
    # Xcode project's SPM graph changes. Uses portable mtime+size polling
    # (Ruby stdlib only — no native gem dependency). The poll interval is
    # cheap for a background dev tool and avoids platform-specific bindings.
    #
    # The loop is continue-on-error: a transient regeneration failure is
    # logged with a timestamp and the loop continues. Only fatal conditions
    # (project file deleted/unwatchable) exit non-zero. SIGINT/SIGTERM flush
    # a pending event and exit 0.
    class Watcher
      DEFAULT_DEBOUNCE = 2 # seconds

      attr_reader :project_path, :debounce, :watched_files

      # @param project_path [String] path to the .xcodeproj
      # @param installer_factory [Proc] returns an Installer::Use-like object
      #   responding to #perform_install (injectable for testing)
      # @param debounce [Integer] seconds to wait between detecting a change
      #   and regenerating (collapses burst saves)
      # @param out [IO] output sink for log lines (default $stdout)
      def initialize(project_path:, installer_factory:, debounce: DEFAULT_DEBOUNCE, out: $stdout)
        @project_path = project_path
        @installer_factory = installer_factory
        @debounce = debounce
        @out = out
        @watched_files = resolve_watched_files
      end

      # Run a single sync-and-exit. Returns true if a regeneration ran.
      # Used by `watch --once` (CI/testing) and is fully unit-testable
      # without the poll loop.
      def run_once
        signatures = current_signatures
        return false if signatures.empty?

        regenerate
        @last_signatures = signatures
        true
      end

      # Start the watch loop. Blocks until interrupted or a fatal error.
      def run
        Signal.trap('TERM') { raise Interrupt }
        info "Watching #{watched_files.join(', ')} for changes (Ctrl-C to stop)..."

        # Initial sync so the proxy is current before watching starts.
        @last_signatures = current_signatures
        regenerate
        @last_signatures = current_signatures

        loop do
          sleep debounce
          current = current_signatures
          next if current == @last_signatures

          @last_signatures = current
          info "\n[watch] SPM graph changed, re-integrating..."
          begin
            regenerate
            @last_signatures = current_signatures
          rescue StandardError => e
            # Continue-on-error: log and keep watching. A transient build
            # failure must not kill the watcher.
            warn_msg "[#{Time.now}] [watch] integration failed: #{e.message}"
          end
        end
      rescue Interrupt
        # Mask further signals for the shutdown path: a trap-raise
        # landing inside this handler escapes uncaught (Interrupt is
        # not a StandardError), so a second Ctrl-C/TERM must not abort
        # the flush or break the exit-0 contract.
        Signal.trap('TERM', 'IGNORE')
        Signal.trap('INT', 'IGNORE')
        flush_pending_event
        info "\n[watch] stopped."
      rescue StandardError => e
        # Fatal: project deleted/unwatchable, or installer construction failed.
        warn_msg "[watch] fatal: #{e.message}"
        raise
      end

      private

      def regenerate
        installer = @installer_factory.call(project_path)
        installer.perform_install
      end

      # On interrupt, a change that landed inside the current poll window
      # has not been processed yet — flush it so Ctrl-C never silently
      # drops a pending regeneration. Accepted edge (same trade-off as
      # the post-regenerate re-snapshot): a change already consumed by a
      # regeneration the interrupt aborts mid-flight is abandoned here —
      # the signatures match — and healed by the next run's initial sync.
      def flush_pending_event
        current = current_signatures
        return if current == @last_signatures

        @last_signatures = current
        info "\n[watch] SPM graph changed, flushing pending change..."
        begin
          regenerate
          @last_signatures = current_signatures
        rescue StandardError => e
          warn_msg "[#{Time.now}] [watch] flush failed: #{e.message}"
        end
      end

      # The files that define the SPM graph: Package.resolved (resolved
      # versions) and project.pbxproj (SPM package references). Watching the
      # whole .xcodeproj bundle is too noisy — Xcode rewrites many files
      # constantly. These two are the meaningful signal.
      def resolve_watched_files
        resolved = Dir.glob(File.join(project_path, '**/Package.resolved'))
                      .find { |f| File.exist?(f) }
        pbxproj = Dir.glob(File.join(project_path, '**/project.pbxproj'))
                     .find { |f| File.exist?(f) }
        [resolved, pbxproj].compact
      end

      def current_signatures
        watched_files.map { |f| file_signature(f) }
      end

      def file_signature(path)
        return nil unless path && File.exist?(path)

        stat = File.stat(path)
        [path, stat.mtime.to_i, stat.size]
      end

      def info(msg)
        @out.puts msg
      end

      def warn_msg(msg)
        @out.puts msg
      end
    end
  end
end
