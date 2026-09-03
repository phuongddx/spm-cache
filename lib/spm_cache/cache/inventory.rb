# frozen_string_literal: true

require 'json'

module SPMCache
  module Cache
    # Shared cache-dir scan (13-02): ONE source of truth for
    # `spm-cache cache list` and the web state read model. Walks the
    # debug/release cache dirs for *.xcframework bundles, sizes each
    # recursively, and reads each .provenance.json sidecar's
    # fidelity_status with the same tolerance the CLI always had.
    class Inventory
      # One cached artifact. keyword_init so callers read
      # entry.name / entry.fidelity, never positional arrays.
      Entry = Struct.new(:name, :config, :size_bytes, :fidelity, keyword_init: true)

      CONFIGS = %w[debug release].freeze

      # cache_root is the injectable seam that keeps specs off the real
      # ~/.spm-cache; production callers never pass it and per-config
      # dirs come from the config's cache_dir. Deterministically sorted
      # (config, then name).
      def self.scan(config: Core::Config.instance, cache_root: nil)
        CONFIGS.flat_map do |cfg|
          dir = cache_root ? File.join(cache_root, cfg) : config.cache_dir(cfg)
          next [] unless File.directory?(dir)

          Dir.glob(File.join(dir, '*.xcframework')).sort.map do |fw_path|
            Entry.new(
              name: File.basename(fw_path, '.xcframework'),
              config: cfg,
              size_bytes: dir_size(fw_path),
              fidelity: fidelity_status_for("#{fw_path}.provenance.json")
            )
          end
        end
      end

      # Recursive lstat sum: symlinked entries count at their link size
      # and are never followed (cache dirs may contain symlinked
      # slices).
      def self.dir_size(path)
        File.lstat(path).size + Dir.glob(File.join(path, '**', '*')).sum { |entry| File.lstat(entry).size }
      end
      private_class_method :dir_size

      # Sidecar tolerance, moved verbatim from command/cache/list.rb:
      # absent, malformed, non-Hash, or keyless sidecars all read as
      # not-graph-pinned rather than raising into a listing.
      def self.fidelity_status_for(sidecar_path)
        return 'not-graph-pinned' unless File.exist?(sidecar_path)

        parsed = JSON.parse(File.read(sidecar_path))
        return 'not-graph-pinned' unless parsed.is_a?(Hash)

        parsed['fidelity_status'] || 'not-graph-pinned'
      rescue JSON::ParserError, SystemCallError
        'not-graph-pinned'
      end
      private_class_method :fidelity_status_for
    end
  end
end
