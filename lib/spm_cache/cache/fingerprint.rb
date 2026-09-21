# frozen_string_literal: true

require 'digest/sha2'
require 'json'
require 'open3'

module SPMCache
  module Cache
    # Pin-level content fingerprint for cache identity. Deterministic by
    # construction: canonical JSON (sorted keys), no absolute paths, no
    # mtimes. Toolchain capture is memoized per process unless injected.
    module Fingerprint
      HASH_LENGTH = 8

      class << self
        def for(package:, pin:, context:, dependencies: {})
          payload = {
            'package' => package.to_s,
            'pin' => pin_data(pin),
            'dependencies' => Hash[dependencies.sort],
            'context' => context
          }
          Digest::SHA256.hexdigest(canonical_json(payload))[0, HASH_LENGTH]
        end

        def context(config:, toolchain: nil)
          tc = toolchain || self.toolchain
          run_context(config).merge(toolchain_context(tc))
        end

        def toolchain(swift_version: nil, xcode_version: nil)
          key = [swift_version, xcode_version]
          (@toolchain_cache ||= {})[key] ||= {
            swift_version: swift_version || version_line('swift --version'),
            xcode_version: xcode_version || version_line('xcodebuild -version')
          }
        end

        def pin_data(pin)
          pin ||= {}
          state = pin['state'] || {}
          {
            'identity' => pin['identity'] || pin['name'],
            'version' => state['version'] || pin['version'],
            'branch' => state['branch'] || pin['branch'],
            'revision' => state['revision'] || pin['revision']
          }
        end

        # graph_entries: [{ 'module' => name, 'dependencies' => [names] }]
        # pins: { module_name => raw_pin_hash }
        def map_for(graph_entries:, pins:, config:, toolchain: nil)
          ctx = context(config: config, toolchain: toolchain)
          by_name = graph_entries.each_with_object({}) { |entry, hash| hash[entry['module']] = entry }
          hashes = {}
          by_name.each_key { |name| resolve_graph_node(name, by_name, pins, ctx, hashes, []) }
          hashes
        end

        private

        # rubocop:disable Metrics/ParameterLists
        def resolve_graph_node(name, by_name, pins, context, hashes, seen)
          return hashes[name] if hashes[name]
          raise "dependency cycle at #{name}" if seen.include?(name)

          dependencies = graph_dependencies(name, by_name, pins, context, hashes, seen)
          hashes[name] = self.for(package: name, pin: pins[name] || {},
                                  dependencies: dependencies, context: context)
        end

        def graph_dependencies(name, by_name, pins, context, hashes, seen)
          entry = by_name[name]
          dependencies = entry ? entry['dependencies'] : []
          dependencies.each_with_object({}) do |dependency, map|
            map[dependency] = resolve_graph_node(dependency, by_name, pins, context, hashes, seen + [name])
          end
        end
        # rubocop:enable Metrics/ParameterLists

        def run_context(config)
          {
            'sdk' => config.run_sdk.to_s,
            'config' => config.run_config.to_s,
            'destinations' => destinations_for(config.run_sdk, config.run_merge_slices).sort,
            'merge_slices' => config.run_merge_slices ? true : false,
            'library_evolution' => config.run_library_evolution ? true : false
          }
        end

        def toolchain_context(toolchain)
          {
            'swift_version' => toolchain[:swift_version],
            'xcode_version' => toolchain[:xcode_version],
            'spm_cache_version' => SPMCache::VERSION
          }
        end

        def destinations_for(sdk, merge_slices)
          return %w[iphonesimulator iphoneos] if merge_slices || sdk.to_s == 'all'

          [sdk.to_s]
        end

        # Read-only version probes; same pattern as Core::Diagnostics.
        def version_line(cmd)
          out, = Open3.capture3(cmd)
          out.to_s.lines.first.to_s.strip
        end

        def canonical_json(payload)
          JSON.generate(sort_keys_deep(payload))
        end

        def sort_keys_deep(obj)
          case obj
          when Hash then obj.keys.sort.each_with_object({}) { |key, hash| hash[key] = sort_keys_deep(obj[key]) }
          when Array then obj.map { |value| sort_keys_deep(value) }
          else obj
          end
        end
      end
    end
  end
end
