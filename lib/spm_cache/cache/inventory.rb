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
      # entry.name / entry.fidelity, never positional arrays. hash8 and
      # last_used stay nil for pre-identity artifacts.
      Entry = Struct.new(
        :name, :config, :size_bytes, :fidelity, :hash8, :last_used,
        keyword_init: true
      )

      CONFIGS = %w[debug release].freeze

      # cache_root is the injectable seam that keeps specs off the real
      # ~/.spm-cache; production callers never pass it and per-config
      # dirs come from the config's cache_dir. Deterministically sorted
      # (config, then name).
      def self.scan(config: Core::Config.instance, cache_root: nil)
        CONFIGS.flat_map do |cfg|
          dir = config_dir(config, cfg, cache_root)
          next [] unless File.directory?(dir)

          unique_framework_paths(dir).map { |path| entry_for(path, cfg) }
        end
      end

      def self.config_dir(config, cfg, cache_root)
        cache_root ? File.join(cache_root, cfg) : config.cache_dir(cfg)
      end
      private_class_method :config_dir

      # A hash-named artifact and its plain-name pointer are the same
      # cache entry; prefer the pointer path so callers see plain names.
      def self.unique_framework_paths(dir)
        paths_by_realpath = Dir.glob(File.join(dir, '*.xcframework')).sort
                               .each_with_object({}) do |path, map|
          realpath = File.realpath(path)
          map[realpath] = path if File.symlink?(path)
          map[realpath] ||= path
        end
        paths_by_realpath.values.sort
      end
      private_class_method :unique_framework_paths

      def self.entry_for(link_path, cfg)
        fw_path = File.symlink?(link_path) ? File.realpath(link_path) : link_path
        fields = sidecar_fields_for("#{fw_path}.provenance.json")
        Entry.new(
          name: File.basename(link_path, '.xcframework'), config: cfg, size_bytes: dir_size(fw_path),
          fidelity: fields['fidelity_status'] || 'not-graph-pinned', hash8: hash8_for(fw_path),
          last_used: fields['last_used_at'].is_a?(Integer) ? fields['last_used_at'] : nil
        )
      end
      private_class_method :entry_for

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
        sidecar_fields_for(sidecar_path)['fidelity_status'] || 'not-graph-pinned'
      end
      private_class_method :fidelity_status_for

      # Sidecar tolerance, moved verbatim from command/cache/list.rb:
      # absent, malformed, non-Hash, or keyless sidecars read as empty
      # rather than raising into a listing.
      def self.sidecar_fields_for(sidecar_path)
        return {} unless File.exist?(sidecar_path)

        parsed = JSON.parse(File.read(sidecar_path))
        return {} unless parsed.is_a?(Hash)

        parsed
      rescue JSON::ParserError, SystemCallError
        {}
      end
      private_class_method :sidecar_fields_for

      def self.hash8_for(fw_path)
        File.basename(fw_path).match(/-([0-9a-f]{8})\.xcframework\z/)&.[](1)
      end
      private_class_method :hash8_for
    end
  end
end
