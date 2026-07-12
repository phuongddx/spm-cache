# frozen_string_literal: true

module SPMCache
  class Installer
    module BuildIntegrationMixin
      def targets_to_build
        return [] unless @cachemap

        @cachemap.missed
      end

      def build_missed!
        targets = targets_to_build
        return if targets.empty?

        Logger.info "Building #{targets.size} missed targets..."
        targets.each do |target_name|
          Logger.info "  Building #{target_name}..."
          @proxy_pkg.build_target(target_name)
        end
        @proxy_pkg.prepare
      end
    end
  end
end
