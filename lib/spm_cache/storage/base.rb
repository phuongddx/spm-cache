# frozen_string_literal: true

require "spm_cache/core/log"

module SPMCache
  module Storage
    class Base
      def pull
        print_warning("pull")
      end

      def push
        print_warning("push")
      end

      def configured?
        false
      end

      private

      HASHED_ARTIFACT = /\A.+-[0-9a-f]{8}\.xcframework\z/.freeze

      # Remote caches are append-only content stores: plain-name pointers and
      # temporary symlinks are local derived state, while legacy artifacts are
      # intentionally quarantined misses and must not be re-published.
      def canonical_sync_paths(cache_dir)
        artifacts = Dir.children(cache_dir).select do |path|
          full_path = File.join(cache_dir, path)
          File.directory?(full_path) && !File.symlink?(full_path) &&
            path.match?(HASHED_ARTIFACT)
        end
        sidecars = artifacts.flat_map do |path|
          %w[provenance shims].map { |kind| File.join(cache_dir, "#{path}.#{kind}.json") }
        end
        artifacts.map! { |path| File.join(cache_dir, path) }
        (artifacts + sidecars).select { |path| File.exist?(path) }
      end

      def print_warning(action)
        Core::UI.warn("No remote cache configured. Skipping #{action}.")
        Core::UI.warn("Configure remote cache in spm-cache.yml to enable.")
      end
    end
  end
end
