# frozen_string_literal: true

require 'spm_cache/command'
require 'spm_cache/core/watcher'

module SPMCache
  class Command
    # Watches the Xcode project's SPM graph and re-runs the spm-cache
    # integration automatically when it changes. Use --once for a single sync.
    class Watch < Command
      include BaseOptions

      self.summary = 'Watch the Xcode project and auto-regenerate the cache proxy'
      self.description = 'Monitors Package.resolved and project.pbxproj for changes and re-runs the spm-cache integration automatically. Use --once for a single sync (CI/testing).'

      def self.options
        [
          ['--once', 'Run a single sync and exit (no watch loop)'],
          ['--debounce=SECONDS', 'Seconds between detecting a change and regenerating (default: 2)']
        ].concat(super)
      end

      def initialize(argv)
        super
        @once = argv.flag?('once', false)
        @debounce = (argv.option('debounce') || Core::Watcher::DEFAULT_DEBOUNCE).to_i
      end

      def run
        require 'spm_cache/installer/use'

        project_path = find_project
        raise Core::GeneralError, 'No .xcodeproj found in current directory' unless project_path

        watcher = Core::Watcher.new(
          project_path: project_path,
          # D-09 (SC1/LOGS-01): every regeneration cycle is its own run log.
          # The factory seam wraps Installer::Use in the per-cycle decorator
          # so Core::Watcher itself stays untouched (factory.call +
          # perform_install, watcher.rb:90-93) -- `watch --once` flows
          # through run_once and the same factory, logging identically.
          # Raw ARGV (not parsed flags) threads --log-dir into the wrapper
          # so cycle files honor the override (D-01); the CLAide-parsed
          # @log_dir rides along (CR-02: CLAide accepts --log-dir=X in any
          # position, so the parsed value -- not raw-argv shape -- routes).
          installer_factory: lambda { |path|
            Core::RunLog.cycle_wrapper(Installer::Use.new(project: path), argv: ARGV, log_dir: @log_dir)
          },
          debounce: @debounce
        )

        if @once
          ok = watcher.run_once
          Core::UI.info(ok ? 'Sync complete.' : 'Nothing to sync (no watched files found).')
        else
          watcher.run
        end
      end

      private

      def find_project
        Dir.glob('*.xcodeproj').first
      end
    end
  end
end
