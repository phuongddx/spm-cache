# frozen_string_literal: true

require "spm_cache/installer"

module SPMCache
  class Installer
    class Build < Installer
      def perform_install
        super do |installer|
          build_missed!
        end
      end
    end
  end
end
