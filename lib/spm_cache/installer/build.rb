# frozen_string_literal: true

require "spm_cache/installer"

module SPMCache
  class Installer
    class Build < Installer
      def perform_install
        super
        # After integration, build missed targets
        if @cachemap && @cachemap.missed?
          Core::UI.info "Building #{@cachemap.missed.size} missed targets..."
          @cachemap.missed.each do |target_name|
            Core::UI.info "  Building #{target_name}..."
          end
        end
      end
    end
  end
end
