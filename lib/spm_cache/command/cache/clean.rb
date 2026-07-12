# frozen_string_literal: true

require "fileutils"
require "spm_cache/command/cache"

module SPMCache
  class Command
    class Cache
      class Clean < Cache
        self.summary = "Clean cached packages"

        def self.options
          [["--all", "Remove all cached packages"], ["--dry", "Dry run (show what would be removed)"]].concat(super)
        end

        def initialize(argv)
          @targets = argv.arguments!
          @all = argv.flag?("all", false)
          @dry = argv.flag?("dry", false)
          super
        end

        def run
          config = Core::Config.instance
          ["debug", "release"].each do |cfg|
            cache_dir = config.cache_dir(cfg)
            next unless File.directory?(cache_dir)

            if @all
              remove_path(cache_dir, cfg)
            elsif @targets.any?
              @targets.each { |t| remove_path(File.join(cache_dir, t), cfg) }
            else
              puts "Specify --all or target names to clean"
            end
          end
        end

        private

        def remove_path(path, cfg)
          return unless File.exist?(path)

          if @dry
            puts "[dry] Would remove: #{path}"
          else
            FileUtils.rm_rf(path)
            puts "Removed: #{path}"
          end
        end
      end
    end
  end
end
