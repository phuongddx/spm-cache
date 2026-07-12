# frozen_string_literal: true

module SPMCache
  module Core
    module Syntax
      autoload :HashRepresentable, "spm_cache/core/syntax/hash"
      autoload :JSONRepresentable, "spm_cache/core/syntax/json"
      autoload :YAMLRepresentable, "spm_cache/core/syntax/yml"
      autoload :PlistRepresentable, "spm_cache/core/syntax/plist"
    end
  end
end
