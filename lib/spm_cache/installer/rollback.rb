# frozen_string_literal: true

require 'fileutils'
require 'spm_cache/installer'

module SPMCache
  class Installer
    class Rollback < Installer
      # BLD-04/CP4/D-07: rollback previously ran lock-free -- a build could
      # be rewriting the sandbox (Installer::Build/Use, both flock-guarded)
      # while a concurrent rollback rm_rf'd it out from under that build.
      # Joining the SAME build flock here, in the installer rather than
      # Command::Rollback or the web layer, means every caller of the
      # installer (terminal, and 15-01's UI-spawned subprocess) inherits
      # the fix for free -- the web layer never re-implements rollback.
      # The wait line is frozen across terminal and browser (BLD-02): it
      # must stay byte-identical to the copies in build.rb and use.rb.
      def perform_install
        lock = acquire_build_lock
        begin
          restore_packages
          remove_proxy
        ensure
          release_build_lock(lock)
        end
      end

      def restore_packages
        Core::UI.info 'Restoring original package references...'
      end

      def remove_proxy
        sandbox = @config.sandbox_dir
        FileUtils.rm_rf(sandbox) if File.directory?(sandbox)
        Core::UI.info 'Removed spm-cache sandbox'
      end

      private

      # Deliberately parallel to Installer::Build#acquire_build_lock
      # (build.rb:76-92) and Installer::Use#with_build_lock (use.rb:70-90)
      # -- NOT extracted into a shared helper across the three files, since
      # that refactor was not asked for and would collide with Plan
      # 15-03's edits to build.rb. Probe -> announce -> block: LOCK_NB
      # returns false under contention (never raises), so only a genuinely
      # contended rollback announces -- the free path stays byte-identical
      # to the pre-BLD-04 code.
      def acquire_build_lock
        path = @config.build_lock_path
        FileUtils.mkdir_p(File.dirname(path))
        lock = File.open(path, File::CREAT | File::RDWR)
        unless lock.flock(File::LOCK_EX | File::LOCK_NB)
          Core::UI.info 'Waiting for build lock…'
          lock.flock(File::LOCK_EX)
        end
        lock
      end

      # Always releases, including when restore_packages/remove_proxy
      # raises -- perform_install's ensure calls this unconditionally, so
      # a failed rollback never wedges the lock for every future
      # build/use/rollback (Pitfall 6).
      def release_build_lock(lock)
        return unless lock

        lock.flock(File::LOCK_UN)
        lock.close
      end
    end
  end
end
