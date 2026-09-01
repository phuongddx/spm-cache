# frozen_string_literal: true

module SPMCache
  module Web
    module ReadModels
      # DASH-01: the cache-state table's data. Everything derives from
      # the same files the CLI reads -- rows from Cache::Inventory (the
      # shared scan behind `spm-cache cache list`), state/has_macro and
      # the summary from the proxy graph.json via Cache::Cachemap --
      # re-read on EVERY call: the server holds no derived state
      # (milestone stance: never a second source of truth).
      class State
        # cache_root is the Inventory seam for hermetic specs; the
        # router never passes it.
        def self.call(config: Core::Config.instance, cache_root: nil)
          inventory = Cache::Inventory.scan(config: config, cache_root: cache_root)
          cachemap = Cache::Cachemap.load(File.join(config.proxy_dir, 'graph.json'))
          graph_entries = cachemap.graph_data.each_with_object({}) do |entry, index|
            index[entry['module']] = entry
          end
          # (16-01, D-06) The SAVED truth, read from disk for THIS
          # call -- a local parse, never config.load on the singleton
          # and never its @raw (the web singleton is a boot-time
          # snapshot; trusting it is exactly CP1).
          saved_ignored = saved_ignore_list(config)

          {
            'packages' => inventory.map do |entry|
              graph_entry = graph_entries[entry.name]
              # (16-01, D-06) saved_cached = the exact-entry test (the
              # checkbox's own truth, served pre-inverted so the client
              # does no math); applied_cached = what the LAST SYNC kept
              # cached (graph status: ignored means not cached, and a
              # row with no graph entry has no applied signal at all);
              # pending = an applied signal exists and the two
              # disagree. The reason + toggleable derivation and the
              # toggleable-only narrowing are 16-03's.
              saved_cached = !saved_ignored.include?(entry.name)
              applied_cached = graph_entry ? graph_entry['status'] != 'ignored' : nil
              {
                'name' => entry.name,
                'config' => entry.config,
                'size_bytes' => entry.size_bytes,
                # nil when the cached artifact is not in the current
                # graph -- the UI renders its "—" cell for that row.
                'state' => graph_entry && graph_entry['status'],
                'fidelity' => entry.fidelity,
                'has_macro' => graph_entry ? (graph_entry['hasMacro'] || false) : false,
                'saved_cached' => saved_cached,
                'applied_cached' => applied_cached,
                'pending' => !applied_cached.nil? && saved_cached != applied_cached
              }
            end,
            'summary' => stringified_summary(cachemap.stats),
            'poll_seconds' => config.web_poll_seconds
          }
        end

        # JSON.generate silently drops symbol keys; the payload is
        # String-keyed throughout. Cachemap#stats answers symbols.
        def self.stringified_summary(stats)
          {
            'total' => stats[:total],
            'hit' => stats[:hit],
            'missed' => stats[:missed],
            'ignored' => stats[:ignored],
            'excluded' => stats[:excluded],
            'plugin' => stats[:plugin]
          }
        end
        private_class_method :stringified_summary

        # (16-01) The ignore list as it exists on DISK right now.
        # Missing, malformed, or shape-broken files read as an empty
        # list: spm-cache.yml is user-authored, not adversarial
        # (research V5) -- a Psych error must not escape api_read's
        # rescue set into WEBrick's error log from a GET.
        def self.saved_ignore_list(config)
          path = config.config_path || File.join(config.project_dir, Core::Config::CONFIG_FILENAME)
          return [] unless File.exist?(path)

          parsed = begin
            YAML.safe_load(File.read(path))
          rescue Psych::Exception
            return []
          end
          return [] unless parsed.is_a?(Hash)

          parsed['ignore'].is_a?(Array) ? parsed['ignore'] : []
        end
        private_class_method :saved_ignore_list
      end
    end
  end
end
