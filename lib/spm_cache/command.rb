# frozen_string_literal: true

require "claide"

module SPMCache
  class Command < CLAide::Command
    self.abstract_command = true
    self.command = "spm-cache"
    self.version = SPMCache::VERSION
    self.description = "Cache SPM dependencies as xcframeworks."

    def self.default_subcommand
      "use"
    end

    def self.options
      [
        ["--sdk=SDK", "SDK to build for (default: iphonesimulator)"],
        ["--config=CONFIG", "Build configuration (default: debug)"],
        ["--log-dir=DIR", "Directory for log files"],
        ["--no-merge-slices", "Disable merging framework slices"],
        ["--no-library-evolution", "Disable Swift library evolution flags"],
      ].concat(super)
    end

    def initialize(argv)
      @sdk = argv.option("sdk")
      @config = argv.option("config")
      @log_dir = argv.option("log-dir")
      @merge_slices = argv.flag?("merge-slices", true)
      @library_evolution = argv.flag?("library-evolution", true)
      super
    end

    def validate!
      super
    end

    def run
      help!
    end
  end
end
