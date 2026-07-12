# frozen_string_literal: true

require_relative "lib/spm_cache/version"

Gem::Specification.new do |spec|
  spec.name          = "spm-cache"
  spec.version       = SPMCache::VERSION
  spec.summary       = "Cache SPM dependencies as xcframeworks"
  spec.description   = "spm-cache prebuilds Swift Package Manager dependencies into .xcframework binaries and swaps them at the manifest level via proxy packages."
  spec.authors       = ["spm-cache"]
  spec.email         = ["dev@spm-cache.dev"]
  spec.homepage      = "https://github.com/your-org/spm-cache"
  spec.license       = "MIT"

  spec.files = Dir[
    "{lib,bin,assets,tools}/**/*",
    "Gemfile",
    "LICENSE.txt",
    "README.md",
    "VERSION",
    "Makefile",
    "*.gemspec"
  ].reject { |f| File.directory?(f) }
  spec.executables   = ["spm-cache"]
  spec.require_paths = ["lib"]

  spec.required_ruby_version = ">= 3.0.0"

  spec.add_runtime_dependency "claide", "~> 1.1"
  spec.add_runtime_dependency "xcodeproj", ">= 1.26.0"
  spec.add_runtime_dependency "parallel", "~> 1.23"
  spec.add_runtime_dependency "tty-cursor", "~> 0.7"
  spec.add_runtime_dependency "tty-screen", "~> 0.8"
  spec.add_runtime_dependency "CFPropertyList", "~> 3.0"

  spec.add_development_dependency "bundler", ">= 2.0"
  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "rubocop", "~> 1.50"
end
