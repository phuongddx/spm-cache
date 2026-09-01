# frozen_string_literal: true

require_relative "lib/spm_cache/version"

Gem::Specification.new do |spec|
  spec.name          = "spm-cache"
  spec.version       = SPMCache::VERSION
  spec.summary       = "Cache SPM dependencies as xcframeworks"
  spec.description   = "spm-cache prebuilds Swift Package Manager dependencies into .xcframework binaries and swaps them at the manifest level via proxy packages."
  spec.authors       = ["spm-cache"]
  spec.email         = ["dev@spm-cache.dev"]
  spec.homepage      = "https://github.com/phuongddx/spm-cache"
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

  spec.required_ruby_version = ">= 3.1.0"

  spec.add_runtime_dependency "claide", "~> 1.1"
  spec.add_runtime_dependency "xcodeproj", ">= 1.26.0"
  spec.add_runtime_dependency "parallel", "~> 1.23"
  spec.add_runtime_dependency "tty-cursor", "~> 0.7"
  spec.add_runtime_dependency "tty-screen", "~> 0.8"
  spec.add_runtime_dependency "CFPropertyList", "~> 3.0"
  # The web dashboard server (Phase 13). Load-bearing runtime declaration:
  # webrick is no longer a default gem (removed in Ruby 4.0; bundled only
  # through 3.4), and `require` fails on every target ruby without it
  # (research CP8, machine-probed). Pinned >= 1.8, < 2 per the research
  # verdict — the milestone's single sanctioned new runtime dependency.
  spec.add_runtime_dependency "webrick", ">= 1.8", "< 2"

  spec.add_development_dependency "bundler", ">= 2.0"
  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "rubocop", "~> 1.50"
end
