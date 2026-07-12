# frozen_string_literal: true

require "spm_cache/installer"

module SPMCache
  class Installer
    class Use < Installer
      def perform_install
        super
        Core::UI.info "spm-cache integration complete."
      end
    end
  end
end
