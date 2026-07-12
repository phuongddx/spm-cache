# frozen_string_literal: true

require "xcodeproj"

module SPMCache
  module XcodeprojExt
    autoload :ProjectExt, "spm_cache/xcodeproj/project"
    autoload :TargetExt, "spm_cache/xcodeproj/target"
    autoload :PkgRefExt, "spm_cache/xcodeproj/pkg"
    autoload :PkgProductDepExt, "spm_cache/xcodeproj/pkg_product_dependency"
    autoload :GroupExt, "spm_cache/xcodeproj/group"
    autoload :BuildConfigExt, "spm_cache/xcodeproj/build_configuration"
  end
end

# Apply extensions
require "spm_cache/xcodeproj/project"
require "spm_cache/xcodeproj/target"
require "spm_cache/xcodeproj/pkg"
require "spm_cache/xcodeproj/pkg_product_dependency"
require "spm_cache/xcodeproj/group"
require "spm_cache/xcodeproj/build_configuration"
