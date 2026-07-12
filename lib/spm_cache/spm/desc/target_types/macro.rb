# frozen_string_literal: true

require "spm_cache/spm/desc/target"

module SPMCache
  module SPM
    module Desc
      class MacroTarget < Target
        def macro?
          true
        end

        def plugin_capability
          raw["pluginCapability"]
        end
      end
    end
  end
end
