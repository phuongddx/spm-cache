# frozen_string_literal: true

module SPMCache
  module SPM
    autoload :Buildable, "spm_cache/spm/build"
    autoload :Macro, "spm_cache/spm/macro"
    autoload :Package, "spm_cache/spm/pkg/base"
    autoload :PkgMixin, "spm_cache/spm/mixin"
  end
end
