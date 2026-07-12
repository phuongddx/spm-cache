# frozen_string_literal: true

module SPMCache
  class Command
    class Use < Command
      include BaseOptions

      self.summary = "Use cached SPM dependencies (default command)"
      self.description = "Integrates the proxy package and replaces source dependencies with prebuilt binaries where cache hits are available."

      def run
        require "spm_cache/installer/use"
        project_path = find_project
        raise "No .xcodeproj found in current directory" unless project_path

        require "xcodeproj"
        project = Xcodeproj::Project.open(project_path)
        installer = Installer::Use.new(project: project_path)
        installer.perform_install
        Logger.info "Done! Cache integrated into #{project_path}"
      end

      private

      def find_project
        Dir.glob("*.xcodeproj").first
      end
    end
  end
end
