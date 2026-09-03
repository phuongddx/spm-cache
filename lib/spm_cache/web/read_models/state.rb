# frozen_string_literal: true

require 'set'

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
        # (16-03, D-09) The five-word reason vocabulary -- the ONLY
        # strings a non-toggleable row may carry, named here ONCE so
        # the route (16-04) and the client (16-05) share this exact
        # source. This list is documentation; #toggle_reason below is
        # the actual pinned precedence, expressed as control flow.
        REASON_EXCLUDED = 'excluded'
        REASON_PLUGIN = 'plugin'
        REASON_BINARY_TARGET = 'binary-target'
        REASON_PATTERN_MANAGED = 'pattern-managed'
        REASON_FIDELITY = 'fidelity'
        REASONS = [REASON_EXCLUDED, REASON_PLUGIN, REASON_BINARY_TARGET, REASON_PATTERN_MANAGED,
                   REASON_FIDELITY].freeze

        # (16-03, A4) The only fidelity value that gates: the warn
        # bucket where a provenance pin can't be verified against the
        # current graph. `not-graph-pinned` (and the ok statuses
        # graph-pinned/host-pinned) stay neutral and toggleable.
        FIDELITY_WARN = 'resolution-incompatible'

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
          # (16-03, TOGL-03) The binary-backed name set, read from the
          # lockfile ONCE per call -- parsed here, membership-tested
          # per row below, never re-parsed per row.
          binary_names = lockfile_binary_names(config)

          {
            'packages' => inventory.map do |entry|
              graph_entry = graph_entries[entry.name]
              graph_status = graph_entry && graph_entry['status']
              # (16-03, D-09/CP10) The ONE server-side derivation: a
              # non-toggleable row carries exactly one of the five
              # words, in the pinned precedence order; a toggleable
              # row carries none.
              reason = toggle_reason(name: entry.name, graph_status: graph_status,
                                     fidelity: entry.fidelity, saved_ignored: saved_ignored,
                                     binary_names: binary_names)
              toggleable = reason.nil?
              # (16-01/16-03, D-06) saved_cached = the exact-entry test
              # (the checkbox's own truth, served pre-inverted so the
              # client does no math); applied_cached = what the LAST
              # SYNC kept cached (graph status: ignored means not
              # cached, and a row with no graph entry has no applied
              # signal at all); pending = TOGGLEABLE and an applied
              # signal exists and the two disagree -- a pattern-managed
              # or otherwise locked row never contributes divergence,
              # because the unsaved-changes bar it would raise could
              # never be cleared by any action the UI offers.
              saved_cached = !saved_ignored.include?(entry.name)
              applied_cached = graph_entry ? graph_status != 'ignored' : nil
              {
                'name' => entry.name,
                'config' => entry.config,
                'size_bytes' => entry.size_bytes,
                # nil when the cached artifact is not in the current
                # graph -- the UI renders its "—" cell for that row.
                'state' => graph_status,
                'fidelity' => entry.fidelity,
                'has_macro' => graph_entry ? (graph_entry['hasMacro'] || false) : false,
                'toggleable' => toggleable,
                'reason' => reason,
                'saved_cached' => saved_cached,
                'applied_cached' => applied_cached,
                'pending' => toggleable && !applied_cached.nil? && saved_cached != applied_cached
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

        # (16-03, TOGL-03) The Set of names a binary-backed package is
        # reachable by (identity ∪ product names ∪ product target
        # names -- Core::Lockfile#binary_backed_names), unioned across
        # every project the lockfile tracks: the web tier has no
        # concept of an xcodeproj basename, so it asks every project
        # key rather than guess one (a project tracks exactly one in
        # practice). Absent lockfile -> no projects -> empty Set;
        # unreadable (permission) AND corrupted (malformed JSON --
        # WR-01: a truncated spm-cache.lock is a real possibility,
        # not contrived, since Lockfile#save is a plain File.write,
        # not the atomic tmp+rename pattern Config#save uses) errors
        # both degrade the same way -- the binary-target reason
        # simply never fires rather than raising.
        def self.lockfile_binary_names(config)
          lockfile = Core::Lockfile.new(config.lockfile_path)
          lockfile.projects.keys.each_with_object(Set.new) do |project_name, names|
            names.merge(lockfile.binary_backed_names(project_name))
          end
        rescue SystemCallError, JSON::ParserError
          Set.new
        end
        private_class_method :lockfile_binary_names

        # (16-03, D-09) toggleable/reason in one place, evaluated in
        # the PINNED precedence order (excluded -> plugin ->
        # binary-target -> pattern-managed -> fidelity) as control
        # flow -- the first hit wins and nothing downstream is even
        # evaluated, so the ordering IS the code rather than a table
        # reconstructed elsewhere. has_macro is never read here (the
        # generator writes it literally false today -- Pitfall 8).
        def self.toggle_reason(name:, graph_status:, fidelity:, saved_ignored:, binary_names:)
          return REASON_EXCLUDED if graph_status == 'excluded'
          return REASON_PLUGIN if graph_status == 'plugin'
          return REASON_BINARY_TARGET if binary_names.include?(name)
          return REASON_PATTERN_MANAGED if pattern_managed?(name, saved_ignored)
          return REASON_FIDELITY if fidelity == FIDELITY_WARN

          nil
        end
        private_class_method :toggle_reason

        # PATTERN truth (a glob match) is a DIFFERENT question from
        # exact-entry truth (Pitfall 5): an exact entry is the normal
        # user-toggled-off state and must stay toggleable, so this
        # predicate only fires when a pattern matches AND no exact
        # entry exists for the same name.
        def self.pattern_managed?(name, saved_ignored)
          !saved_ignored.include?(name) && saved_ignored.any? { |pattern| File.fnmatch(pattern, name) }
        end
        private_class_method :pattern_managed?

        # (WR-02) True when PACKAGE carries its own exact ignore entry
        # AND a DIFFERENT, broader pattern in the SAME on-disk list
        # would still match it once that exact entry is gone -- the
        # toggle-on dead end: without this check, /api/toggle would
        # remove the exact entry, answer 200, and leave the package
        # ignored in reality (Config#should_ignore? still matches the
        # surviving pattern) with nothing telling the user -- Pitfall
        # 5's mirror image. PUBLIC (not private_class_method) --
        # api_toggle calls this directly before running the mutator.
        # Reads the SAME fresh-from-disk ignore list saved_ignore_list
        # already uses (CP1) -- never the config singleton's
        # boot-time @raw, so a config edited after server boot is
        # judged correctly on the very next request.
        def self.would_remain_pattern_ignored?(package, config)
          remaining = saved_ignore_list(config) - [package]
          remaining.any? { |pattern| File.fnmatch(pattern, package) }
        end
      end
    end
  end
end
