# frozen_string_literal: true

require "spm_cache/command/cache"

module SPMCache
  class Command
    class Cache
      class List < Cache
        self.summary = "List cached packages"

        def run
          config = Core::Config.instance
          ["debug", "release"].each do |cfg|
            cache_dir = config.cache_dir(cfg)
            next unless File.directory?(cache_dir)

            puts "\n#{cfg.capitalize}:"
            Dir.entries(cache_dir).sort.each do |entry|
              next if entry.start_with?(".")
              puts "  #{entry}"
            end
          end
        end
      end
    end
  end
end
