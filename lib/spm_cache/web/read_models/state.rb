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

          {
            'packages' => inventory.map do |entry|
              graph_entry = graph_entries[entry.name]
              {
                'name' => entry.name,
                'config' => entry.config,
                'size_bytes' => entry.size_bytes,
                # nil when the cached artifact is not in the current
                # graph -- the UI renders its "—" cell for that row.
                'state' => graph_entry && graph_entry['status'],
                'fidelity' => entry.fidelity,
                'has_macro' => graph_entry ? (graph_entry['hasMacro'] || false) : false
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
      end
    end
  end
end
