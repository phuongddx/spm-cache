# frozen_string_literal: true

module SPMCache
  class Command
    class Use < Command
      include BaseOptions

      self.summary = 'Use cached SPM dependencies (default command)'
      self.description = 'Integrates the proxy package and replaces source dependencies with prebuilt binaries where cache hits are available. Auto-detects changes in the Xcode SPM graph and regenerates the proxy when needed.'

      def self.options
        [['--watch', 'Watch Package.resolved and auto-regenerate on change (background mode)']].concat(super)
      end

      def initialize(argv)
        super
        @watch = argv.flag?('watch', false)
      end

      def run
        require 'spm_cache/installer/use'
        project_path = find_project
        raise 'No .xcodeproj found in current directory' unless project_path

        if @watch
          run_watch(project_path)
        else
          run_once(project_path)
        end
      end

      private

      def find_project
        Dir.glob('*.xcodeproj').first
      end

      def run_once(project_path)
        installer = Installer::Use.new(project: project_path)
        installer.perform_install
        Core::UI.info "Done! Cache integrated into #{project_path}"
      end

      # Watches Package.resolved inside the .xcodeproj bundle and re-runs the
      # integration whenever it changes. Uses a simple polling loop (mtime +
      # size) rather than a native FSEvents binding to avoid a platform-
      # specific gem dependency; the poll interval (2s) is cheap enough for a
      # background dev tool and avoids the fsevent_watch subprocess entirely.
      # Exits cleanly on Ctrl-C (Interrupt).
      def run_watch(project_path)
        require 'spm_cache/installer/use'

        resolved_path = find_package_resolved(project_path)
        unless resolved_path
          Core::UI.warn "No Package.resolved found in #{project_path}; --watch needs an existing resolved graph to monitor."
          return
        end

        Core::UI.info "Watching #{resolved_path} for changes (Ctrl-C to stop)..."

        # Initial run so the proxy is current before watching starts.
        run_once(project_path)

        signature = file_signature(resolved_path)
        loop do
          sleep 2
          current = file_signature(resolved_path)
          next if current == signature

          signature = current
          Core::UI.info "\n[watch] Package.resolved changed, re-integrating..."
          begin
            run_once(project_path)
          rescue StandardError => e
            Core::UI.warn "[watch] integration failed: #{e.message}"
          end
        end
      rescue Interrupt
        Core::UI.info "\n[watch] stopped."
      end

      def find_package_resolved(project_path)
        Dir.glob(File.join(project_path, '**/Package.resolved')).find { |f| File.exist?(f) }
      end

      def file_signature(path)
        return nil unless File.exist?(path)

        stat = File.stat(path)
        [stat.mtime.to_i, stat.size]
      end
    end
  end
end
