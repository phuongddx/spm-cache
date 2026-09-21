# frozen_string_literal: true

require 'fileutils'
require 'json'

module SPMCache
  module Cache
    # Canonical-name pointers over durable hash-suffixed artifacts. The Swift
    # proxy keeps using plain paths, while the cache layer keeps a single
    # content-addressed artifact per identity.
    # rubocop:disable Metrics/ModuleLength, Metrics/ClassLength
    module Pointer
      class << self
        def refresh_all!(cache_dir:, lockfile_path:, graph_path:, config:, pins_path: nil)
          quarantine_legacy!(cache_dir)
          graph_entries = read_json_array(graph_path)
          pins = read_pins(pins_path) || pins_from_lockfile(lockfile_path)
          hashes = Fingerprint.map_for(graph_entries: graph_entries, pins: pins, config: config)
          materialize_hashes(hashes, cache_dir: cache_dir)
        rescue StandardError => e
          Core::UI.warn "pointer refresh failed (fail-open): #{e.message}"
          {}
        end

        def materialize!(cache_dir:, module_name:, hash8:)
          target = File.join(cache_dir, "#{module_name}-#{hash8}.xcframework")
          return false unless File.directory?(target)

          link_atomic(cache_dir, "#{module_name}.xcframework", "#{module_name}-#{hash8}.xcframework")
          link_sidecars(cache_dir, module_name, hash8)
          touch_last_used("#{target}.provenance.json")
          true
        end

        # Pre-upgrade plain artifacts cannot be mistaken for a hash hit, so
        # move them aside and let the normal miss path rebuild them.
        def quarantine_legacy!(cache_dir)
          Dir.glob(File.join(cache_dir, '*.xcframework')).filter_map do |path|
            next if File.symlink?(path)

            base = File.basename(path, '.xcframework')
            next if base.start_with?('legacy-') || base.match?(/-[0-9a-f]{8}\z/)

            move_pair(cache_dir, base, "legacy-#{base}")
            base
          end
        end

        def clear_all!(cache_dir)
          Dir.glob(File.join(cache_dir, '*.xcframework')).sum do |path|
            next 0 unless File.symlink?(path)

            FileUtils.rm_f(path)
            FileUtils.rm_f("#{path}.provenance.json")
            FileUtils.rm_f("#{path}.shims.json")
            1
          end
        end

        private

        def materialize_hashes(hashes, cache_dir:)
          hashes.each_with_object({}) do |(module_name, hash8), materialized|
            materialized[module_name] = hash8 if materialize!(
              cache_dir: cache_dir, module_name: module_name, hash8: hash8
            )
          end
        end

        def link_sidecars(cache_dir, module_name, hash8)
          %w[provenance shims].each do |kind|
            target_name = "#{module_name}-#{hash8}.xcframework.#{kind}.json"
            next unless File.exist?(File.join(cache_dir, target_name))

            link_atomic(cache_dir, "#{module_name}.xcframework.#{kind}.json", target_name)
          end
        end

        def link_atomic(cache_dir, link_name, target_name)
          link = File.join(cache_dir, link_name)
          temporary = "#{link}.tmp#{Process.pid}"
          FileUtils.rm_f(temporary)
          File.symlink(target_name, temporary)
          File.rename(temporary, link)
        end

        def move_pair(cache_dir, from_base, to_base)
          FileUtils.mv(File.join(cache_dir, "#{from_base}.xcframework"),
                       File.join(cache_dir, "#{to_base}.xcframework"))
          %w[provenance shims].each do |kind|
            from = File.join(cache_dir, "#{from_base}.xcframework.#{kind}.json")
            FileUtils.mv(from, File.join(cache_dir, "#{to_base}.xcframework.#{kind}.json")) if File.exist?(from)
          end
        end

        def touch_last_used(sidecar)
          return unless File.exist?(sidecar)

          data = JSON.parse(File.read(sidecar))
          data['last_used_at'] = Time.now.to_i
          File.write(sidecar, JSON.generate(data))
        rescue JSON::ParserError, SystemCallError
          nil
        end

        def read_json_array(path)
          return [] unless path && File.exist?(path)

          parsed = JSON.parse(File.read(path))
          parsed.is_a?(Array) ? parsed : []
        rescue JSON::ParserError, SystemCallError
          []
        end

        def read_pins(pins_path)
          return nil unless pins_path && File.exist?(pins_path)

          parsed = JSON.parse(File.read(pins_path))
          parsed.is_a?(Hash) ? parsed : {}
        rescue JSON::ParserError, SystemCallError
          {}
        end

        # Index by package identity and each library product, matching the
        # product/module names emitted in graph.json.
        def pins_from_lockfile(lockfile_path)
          return {} unless lockfile_path && File.exist?(lockfile_path)

          data = JSON.parse(File.read(lockfile_path))
          data.fetch('projects', {}).each_value.flat_map { |project| project_pins(project) }.to_h
        rescue JSON::ParserError, SystemCallError
          {}
        end

        def project_pins(project)
          project.fetch('packages', []).flat_map do |package|
            pin = pin_for_package(package)
            names = [package['identity'], package['name']]
            names.concat(package.fetch('products', []).map { |product| product['name'] if product.is_a?(Hash) })
            names.compact.uniq.map { |name| [name, pin] }
          end
        end

        def pin_for_package(package)
          state = package.slice('version', 'revision', 'branch')
          { 'identity' => package['identity'] || package['name'], 'state' => state }
        end
      end
    end
    # rubocop:enable Metrics/ModuleLength, Metrics/ClassLength
  end
end
