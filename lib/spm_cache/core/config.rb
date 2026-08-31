# frozen_string_literal: true

require 'singleton'
require 'fileutils'
require 'yaml'

require 'spm_cache/core/syntax/yml'

module SPMCache
  module Core
    class Config
      include Singleton
      include Syntax::YAMLRepresentable

      DEFAULT_CONFIG = {
        'ignore' => [],
        'cache_only' => [],
        'ignore_local' => false,
        'ignore_build_errors' => false,
        'keep_pkgs_in_project' => false,
        'default_sdk' => 'iphonesimulator',
        # Run-log retention budgets (D-06): keep the newest `runs_keep`
        # run logs, then prune oldest until the total is under
        # `runs_max_mb` MB. Fidelity is absolute (D-05) -- growth is
        # bounded only by whole-file retention pruning (Plan 12-03).
        'runs_keep' => 50,
        'runs_max_mb' => 500
      }.freeze

      SANDBOX_DIR = 'spm-cache'
      CACHE_DIR = File.expand_path('~/.spm-cache')
      CONFIG_FILENAME = 'spm-cache.yml'
      LOCKFILE_FILENAME = 'spm-cache.lock'

      attr_accessor :project_dir, :config_path

      def initialize
        @project_dir = Dir.pwd
        @config_path = File.join(@project_dir, CONFIG_FILENAME)
        @raw = DEFAULT_CONFIG.dup
      end

      def self.instance
        @@instance ||= super
      end

      def self.configure(project_dir: nil, config_path: nil)
        inst = instance
        inst.project_dir = project_dir if project_dir
        inst.config_path = config_path if config_path
        inst
      end

      def load(path = nil)
        @config_path = path if path
        if @config_path && File.exist?(@config_path)
          @raw = DEFAULT_CONFIG.merge(YAML.safe_load(File.read(@config_path)) || {})
        end
        @raw
      end

      def save(path = nil)
        @config_path = path || @config_path
        return unless @config_path

        FileUtils.mkdir_p(File.dirname(@config_path))
        File.write(@config_path, YAML.dump(@raw))
      end

      def sandbox_dir
        File.join(project_dir, SANDBOX_DIR)
      end

      def cache_dir(config = nil)
        config ? File.join(CACHE_DIR, config) : CACHE_DIR
      end

      def umbrella_dir
        File.join(sandbox_dir, 'packages', 'umbrella')
      end

      def proxy_dir
        File.join(sandbox_dir, 'packages', 'proxy')
      end

      def metadata_dir
        File.join(sandbox_dir, 'metadata')
      end

      def binaries_dir
        File.join(sandbox_dir, 'packages', 'proxy', '.build', 'artifacts')
      end

      # A dedicated sibling of umbrella_dir/proxy_dir -- never a path under
      # umbrella_dir or its .build, which #locate_prebuilt_xcframework reads
      # Class-E binaryTarget artifacts from (BuildPipeline). Shared across
      # every xcodebuild invocation via -clonedSourcePackagesDirPath so N
      # per-package builds don't each independently clone the whole host
      # graph (Pitfall 9).
      def clones_dir
        File.join(sandbox_dir, 'packages', 'clones')
      end

      # Stable, OUTSIDE sandbox_dir by construction (a project_dir-level
      # dotfile) so recreate_dirs' rm_rf(sandbox_dir) can never delete the
      # path a live flock is held on (Pitfall 15).
      def build_lock_path
        File.join(project_dir, '.spm-cache-build.lock')
      end

      # Run logs live under a project_dir-level dot-directory, OUTSIDE
      # sandbox_dir (D-02): recreate_dirs rm_rf's sandbox_dir only
      # (installer/use.rb), so a runs dir inside it would delete the
      # current run's log mid-run (Pitfall 7). Same placement rationale
      # as build_lock_path above.
      def runs_dir
        File.join(project_dir, '.spm-cache', 'runs')
      end

      def local_packages_dir
        File.join(sandbox_dir, 'local-packages')
      end

      def xcconfigs_dir
        File.join(sandbox_dir, 'xcconfigs')
      end

      def lockfile_path
        File.join(project_dir, LOCKFILE_FILENAME)
      end

      def remote_config(config)
        remote = raw['remote'] || {}
        remote[config] || remote[config.to_s]
      end

      def ignore_list
        raw['ignore'] || []
      end

      def cache_only_list
        raw['cache_only'] || []
      end

      def ignore_local?
        raw['ignore_local']
      end

      def ignore_build_errors?
        raw['ignore_build_errors']
      end

      def keep_pkgs_in_project?
        raw['keep_pkgs_in_project']
      end

      def default_sdk
        raw['default_sdk'] || 'iphonesimulator'
      end

      # Retention budgets (D-06). Integer()-coerced with rescue-to-default:
      # spm-cache.yml is user-authored, not adversarial (research V5) -- a
      # typo like `runs_keep: many` falls back to the default instead of
      # raising into a run.
      def runs_keep
        Integer(raw['runs_keep'] || DEFAULT_CONFIG['runs_keep'])
      rescue ArgumentError, TypeError
        DEFAULT_CONFIG['runs_keep']
      end

      def runs_max_mb
        Integer(raw['runs_max_mb'] || DEFAULT_CONFIG['runs_max_mb'])
      rescue ArgumentError, TypeError
        DEFAULT_CONFIG['runs_max_mb']
      end

      def should_ignore?(package_name)
        ignore_list.any? { |pattern| File.fnmatch(pattern, package_name) }
      end

      def reset!
        @raw = DEFAULT_CONFIG.dup
      end
    end
  end
end
