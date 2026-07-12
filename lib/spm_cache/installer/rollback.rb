# frozen_string_literal: true

require "fileutils"
require "spm_cache/installer"

module SPMCache
  class Installer
    class Rollback < Installer
      def perform_install
        restore_packages
        remove_proxy
      end

      def restore_packages
        Logger.info "Restoring original package references..."
      end

      def remove_proxy
        sandbox = @config.sandbox_dir
        FileUtils.rm_rf(sandbox) if File.directory?(sandbox)
        Logger.info "Removed spm-cache sandbox"
      end
    end
  end
end
