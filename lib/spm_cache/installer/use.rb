# frozen_string_literal: true

require 'spm_cache/installer'

module SPMCache
  class Installer
    class Use < Installer
      # Integrate the proxy package. When spm-cache.lock already exists and
      # the live Xcode SPM graph matches it (DiffDetector reports no changes)
      # AND the proxy package is already materialized on disk, the integration
      # is a no-op fast path -- we skip the costly regenerate/resolve/build
      # cycle entirely. Any change (added/removed/updated package) forces a
      # full regeneration so the proxy stays in sync transparently. This is the
      # structural moat vs Scipio, which requires a separate manifest the user
      # must edit by hand on every dependency change.
      def perform_install
        Core::UI.section('spm-cache') do
          verify_projects!
          detect_diff

          if fast_path?
            Core::UI.info 'No changes detected. Proxy package up to date.'
          else
            recreate_dirs
            ensure_config_file
            sync_lockfile
            prepare_proxy
            yield self if block_given?
          end

          gen_supporting_files
          integrate_proxy_into_project
          gen_cachemap_viz
        end
      end

      private

      # The fast path applies only when:
      #   1. A lockfile exists (prior run succeeded), AND
      #   2. DiffDetector reports an empty diff (live == locked), AND
      #   3. The proxy Package.swift is already materialized on disk.
      # Missing any of these, we fall back to a full regeneration so a stale
      # proxy is never silently served as if it were current.
      def fast_path?
        return false unless @diff
        return false unless @diff.empty?
        return false unless File.exist?(@config.lockfile_path)

        File.exist?(File.join(@config.proxy_dir, 'Package.swift'))
      end
    end
  end
end
