# frozen_string_literal: true

module SPMCache
  class Command
    class Build < Command
      include BaseOptions

      self.summary = "Build SPM targets into xcframeworks"
      self.description = "Builds specified targets into xcframeworks and stores them in the cache."

      def self.options
        [["--recursive", "Build recursive dependencies"]].concat(super)
      end

      def initialize(argv)
        @targets = argv.arguments!
        @recursive = argv.flag?("recursive", false)
        super
      end

      def run
        require "spm_cache/installer/build"
        project_path = find_project
        raise "No .xcodeproj found" unless project_path

        require "xcodeproj"
        installer = Installer::Build.new(project: project_path)
        installer.perform_install
        puts "Build complete!"
      end

      private

      def find_project
        Dir.glob("*.xcodeproj").first
      end
    end
  end
end
