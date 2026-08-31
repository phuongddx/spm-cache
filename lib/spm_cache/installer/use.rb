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

          # D-04/LOGS-01: detect phase marker immediately after diff
          # detection. Nil-guarded via the process-wide seam -- every
          # caller/spec path without an active run log is a no-op.
          Core::RunLog.current&.event('phase', name: 'detect')

          # D-04/LOGS-01: integrate phase marker emitted ONCE, immediately
          # before the branch -- both the fast and full paths integrate, so
          # a single site here records exactly one marker per run.
          Core::RunLog.current&.event('phase', name: 'integrate')

          if fast_path?
            Core::UI.info 'No changes detected. Proxy package up to date.'
            with_build_lock do
              # sync_lockfile is skipped on this branch, so it never assigns
              # @lockfile -- populate it here (read-only, no save) so
              # integrate_proxy_into_project's plugin_only_lockfile_urls sees
              # the real lockfile instead of nil, which would otherwise strip
              # every plugin-only package reference on each fast-path run.
              @lockfile = Core::Lockfile.new(@config.lockfile_path)
              gen_supporting_files
              integrate_proxy_into_project
              gen_cachemap_viz
            end
          else
            with_build_lock do
              recreate_dirs
              ensure_config_file
              sync_lockfile
              prepare_proxy
              yield self if block_given?
              gen_supporting_files
              integrate_proxy_into_project
              gen_cachemap_viz
            end
          end
        end
      end

      private

      # D-06: blocks on the SAME exclusive flock Installer::Build holds
      # across its whole build (Config#build_lock_path). Wraps BOTH branches'
      # trailing gen_supporting_files/integrate_proxy_into_project/
      # gen_cachemap_viz -- including the fast path, which touches
      # @config.sandbox_dir (via gen_cachemap_viz) even though it never calls
      # recreate_dirs itself -- so a watch-triggered regenerate on either path
      # defers to an in-flight build instead of racing its rm_rf/writes
      # (Pitfall 15). A BLOCKING flock, not a trylock-and-retry -- the OS's
      # own blocking semantics are the whole mechanism, no polling needed.
      def with_build_lock
        path = @config.build_lock_path
        FileUtils.mkdir_p(File.dirname(path))
        lock = File.open(path, File::CREAT | File::RDWR)
        begin
          lock.flock(File::LOCK_EX)
          yield
        ensure
          lock.flock(File::LOCK_UN)
          lock.close
        end
      end

      # The fast path applies only when:
      #   1. A lockfile exists (prior run succeeded), AND
      #   2. DiffDetector reports an empty diff (live == locked), AND
      #   3. The proxy Package.swift is already materialized on disk, AND
      #   4. The lockfile's recorded spm_cache_version matches the running gem.
      # Missing any of these, we fall back to a full regeneration so a stale
      # proxy is never silently served as if it were current.
      def fast_path?
        return false unless @diff
        return false unless @diff.empty?
        return false unless File.exist?(@config.lockfile_path)
        return false unless File.exist?(File.join(@config.proxy_dir, 'Package.swift'))

        current_spm_cache_version?
      end

      # Reads the on-disk lockfile directly via a throwaway Core::Lockfile
      # instance -- never assigned to @lockfile, which sync_lockfile (skipped
      # on this branch) is what normally populates. Guards the same upgrade
      # gap enrich_lockfile_products/invalidate_stale_products! already close
      # for products[] staleness: a spm-cache upgrade with an otherwise
      # unchanged host graph must still force one full gen-proxy run so the
      # cache-identity fix (CACHE-02) actually reaches the default,
      # no-args `spm-cache`/`spm-cache use` workflow, not only `spm-cache build`.
      def current_spm_cache_version?
        disk_lockfile = Core::Lockfile.new(@config.lockfile_path)
        proj_data = disk_lockfile.projects[File.basename(@project_path)]
        proj_data && proj_data['spm_cache_version'] == SPMCache::VERSION
      end
    end
  end
end
