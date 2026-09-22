# frozen_string_literal: true

require 'spm_cache/command/cache'

module SPMCache
  class Command
    class Cache
      # Remove GC-eligible artifacts and enforce the LRU size budget.
      class GC < Cache
        self.summary = 'Remove garbage and evict LRU cache artifacts'

        def self.options
          [
            ['--dry-run', 'Show what would be removed'],
            ['--dry', 'Alias for --dry-run'],
            ['--max-size=GB', 'Budget per config directory (default: 20)'],
          ].concat(super)
        end

        def initialize(argv)
          @dry = argv.flag?('dry-run', argv.flag?('dry', false))
          @max_size = argv.option('max-size')
          super
        end

        def run
          config = Core::Config.instance
          if ::SPMCache::Cache::GC.build_lock_held?(config.build_lock_path)
            raise Core::GeneralError, 'Refusing to GC: build lock is held'
          end

          %w[debug release].each do |cfg|
            cache_dir = config.cache_dir(cfg)
            next unless File.directory?(cache_dir)

            run_gc(config, cache_dir)
          end
        end

        private

        def build_plan(config, cache_dir)
          ::SPMCache::Cache::GC.plan(
            cache_dirs: [cache_dir],
            max_size_bytes: max_size_bytes(config),
            protect: []
          )
        end

        def run_gc(config, cache_dir)
          plan = build_plan(config, cache_dir)
          if @dry
            print_dry_plan(plan)
          else
            ::SPMCache::Cache::GC.execute!(plan)
            puts "#{cache_dir}: Reclaimed: #{plan.reclaimed_bytes} bytes"
          end
        end

        def max_size_bytes(config)
          Integer(@max_size || config.cache_max_size_gb) * 1024**3
        end

        def print_dry_plan(plan)
          plan.entries.each do |entry|
            puts "[dry] #{entry[:path]} (#{entry[:bytes]} bytes)"
          end
        end
      end
    end
  end
end
