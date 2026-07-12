# frozen_string_literal: true

require "spm_cache/installer"

module SPMCache
  class Installer
    class Use < Installer
      def perform_install
        super do |installer|
          replace_binaries_for_project
        end
      end

      def replace_binaries_for_project
        Logger.info "Replacing source dependencies with cached binaries..."
      end
    end
  end
end
