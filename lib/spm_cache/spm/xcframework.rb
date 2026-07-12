# frozen_string_literal: true

module SPMCache
  module SPM
    module XCFramework
      autoload :FrameworkSlice, "spm_cache/spm/xcframework/slice"
      autoload :XCFramework, "spm_cache/spm/xcframework/xcframework"
      autoload :Metadata, "spm_cache/spm/xcframework/metadata"
    end
  end
end
