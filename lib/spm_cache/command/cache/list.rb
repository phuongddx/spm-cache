# frozen_string_literal: true

require 'spm_cache/command/cache'

module SPMCache
  class Command
    class Cache
      class List < Cache
        self.summary = 'List cached packages'

        def run
          config = Core::Config.instance
          # The scan lives in Cache::Inventory -- the same source of
          # truth the web state read model reads (13-02). Printed
          # output is unchanged: headers per existing config dir, rows
          # per cached artifact with its sidecar fidelity.
          entries = SPMCache::Cache::Inventory.scan(config: config)
          %w[debug release].each do |cfg|
            next unless File.directory?(config.cache_dir(cfg))

            puts "\n#{cfg.capitalize}:"
            entries.select { |entry| entry.config == cfg }.each do |entry|
              puts "  #{entry.name} (#{entry.fidelity})"
            end
          end
        end
      end
    end
  end
end
