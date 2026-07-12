# frozen_string_literal: true

require "spm_cache/spm/desc/target"

module SPMCache
  module SPM
    module Desc
      class BinaryTarget < Target
        def binary?
          true
        end

        def url
          raw["url"]
        end

        def checksum
          raw["checksum"]
        end
      end
    end
  end
end
