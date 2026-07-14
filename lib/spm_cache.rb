# frozen_string_literal: true

require "pathname"

module SPMCache
  ROOT = Pathname.new(File.expand_path("..", __dir__))
  LIBEXEC = ROOT.join("lib", "spm_cache")

  autoload :Main, "spm_cache/main"
  autoload :VERSION, "spm_cache/version"
end
