# frozen_string_literal: true

module SPMCache
  class Command
    class Rollback < Command
      include BaseOptions

      self.summary = "Restore original project state"
      self.description = "Removes spm-cache integration and restores original package dependencies."

      def run
        require "spm_cache/installer/rollback"
        project_path = find_project
        raise "No .xcodeproj found" unless project_path

        installer = Installer::Rollback.new(project: project_path)
        installer.perform_install
        puts "Rollback complete!"
      end

      private

      def find_project
        Dir.glob("*.xcodeproj").first
      end
    end
  end
end
