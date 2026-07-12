# frozen_string_literal: true

require "json"
require "spm_cache/core/sh"
require "spm_cache/core/syntax/json"

module SPMCache
  module SPM
    module Desc
      autoload :BaseObject, "spm_cache/spm/desc/base"
      autoload :Description, "spm_cache/spm/desc/desc"
      autoload :Product, "spm_cache/spm/desc/product"
      autoload :Target, "spm_cache/spm/desc/target"
      autoload :Dependency, "spm_cache/spm/desc/dep"
    end
  end
end
