# frozen_string_literal: true

require 'singleton'
require 'fileutils'
require 'tempfile'
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
        'runs_max_mb' => 500,
        # Dashboard state-table auto-poll interval in seconds
        # (13-UI-SPEC "server-configurable" auto-refresh, default 5s).
        'web_poll_seconds' => 5
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

      # Re-derives config_path from the new project_dir whenever an
      # explicit config_path is not supplied (16-01 hermeticity,
      # T-16-06): a caller pointing the singleton at another project
      # must never keep writing to the boot cwd's spm-cache.yml.
      # An explicit config_path still wins.
      def self.configure(project_dir: nil, config_path: nil)
        inst = instance
        if project_dir
          inst.project_dir = project_dir
          inst.config_path = config_path || File.join(project_dir, CONFIG_FILENAME)
        elsif config_path
          inst.config_path = config_path
        end
        inst
      end

      def load(path = nil)
        @config_path = path if path
        if @config_path && File.exist?(@config_path)
          @raw = DEFAULT_CONFIG.merge(YAML.safe_load(File.read(@config_path)) || {})
        end
        @raw
      end

      # Atomic replace (D-04, 16-01): same-dir Tempfile + File.rename
      # over the config path (marker.rb / run_log.rb header precedent)
      # -- a concurrent reader observes either the whole old file or
      # the whole new one, never a truncated write. The rendered bytes
      # stay byte-identical to the former
      # `File.write(@config_path, YAML.dump(@raw))` -- only the
      # delivery mechanism changes. chmod lands on the tempfile
      # BEFORE the rename (marker.rb ordering) so the file is never
      # observable at the final path with the tempfile's 0600: an
      # existing file's mode is preserved, a new one gets the house
      # default for a non-secret project file.
      def save(path = nil)
        @config_path = path || @config_path
        return unless @config_path

        FileUtils.mkdir_p(File.dirname(@config_path))
        mode = File.exist?(@config_path) ? (File.stat(@config_path).mode & 0o777) : 0o644
        tmp = Tempfile.new(['spm-cache', '.yml'], File.dirname(@config_path))
        begin
          tmp.write(YAML.dump(@raw))
          tmp.close
          File.chmod(mode, tmp.path)
          File.rename(tmp.path, @config_path)
        ensure
          tmp.close unless tmp.closed?
          File.unlink(tmp.path) if File.exist?(tmp.path)
        end
      end

      # The SIDECAR the shared mutator flocks (D-04, 16-01). NEVER
      # the yml inode itself: #save replaces the file by rename, and
      # a rename orphans any lock held on the replaced inode
      # (16-RESEARCH PROBED P5) while the sidecar is inode-stable
      # across rewrites (P6). Sibling of the config, like the build
      # lock is a sibling of the sandbox.
      def config_lock_path
        "#{config_path}.lock"
      end

      # The shared config mutator (D-03/D-04, 16-01): BOTH writers --
      # `spm-cache off` in its own process and POST /api/toggle in
      # the server process -- go through this one method, so both
      # inherit the sidecar lock, the fresh in-lock re-read and the
      # atomic replace by construction; there is no second write path
      # to keep in sync.
      #
      # Nothing here prints, warns or logs: a web request has no
      # stream and the terminal running `spm-cache web` stays quiet
      # (T-13-03). The BLOCKING flock defers contended writers at
      # click granularity (build.rb idiom, minus the announce);
      # LOCK_NB's verdict is truthiness -- Ruby returns false under
      # contention and never raises (PROBED P4).
      def set_ignored_all(changes)
        FileUtils.mkdir_p(File.dirname(config_path))
        lock = File.open(config_lock_path, File::CREAT | File::RDWR)
        lock.flock(File::LOCK_EX)
        begin
          # The fresh in-lock re-read (CP1/Pitfall 2): destroys any
          # boot-time snapshot before merging. reset! first so a
          # config that vanished mid-flight reads as defaults rather
          # than resurrecting the snapshot (load alone keeps @raw
          # when the file is absent).
          @raw = DEFAULT_CONFIG.dup
          load
          current = ignore_list
          changes.each do |package, ignored|
            current = ignored ? (current + [package]).uniq : current - [package]
          end
          # ASSIGN a new array -- never `<<`/push/delete in place:
          # DEFAULT_CONFIG's inner arrays are shared by dup and the
          # frozen hash does not protect them (Pitfall 3).
          raw['ignore'] = current
          save
        ensure
          lock.flock(File::LOCK_UN)
          lock.close
        end
        ignore_list
      end

      # Single-package convenience over the batch mutator: a revert
      # of N rows still costs one lock acquisition (set_ignored_all).
      def set_ignored(package, ignored)
        set_ignored_all(package => ignored)
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

      # Web-server runtime state (the WEB-02 marker file) lives here,
      # OUTSIDE sandbox_dir for the same reason as runs_dir above:
      # recreate_dirs rm_rf's sandbox_dir only (installer/use.rb), and it
      # must never delete a live server's marker mid-run. Sibling of
      # runs_dir (13-CONTEXT "Launch & Port Behavior"); recreate_dirs
      # never touches it.
      def web_dir
        File.join(project_dir, '.spm-cache', 'web')
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

      # Dashboard state-table auto-poll interval (13-UI-SPEC
      # "server-configurable"). Integer()-coerced with rescue-to-default,
      # runs_keep posture: spm-cache.yml is user-authored, not adversarial
      # (research V5) -- a typo falls back to the default instead of
      # raising into a poll loop.
      def web_poll_seconds
        Integer(raw['web_poll_seconds'] || DEFAULT_CONFIG['web_poll_seconds'])
      rescue ArgumentError, TypeError
        DEFAULT_CONFIG['web_poll_seconds']
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
