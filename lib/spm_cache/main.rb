# frozen_string_literal: true

require "pathname"
require "spm_cache"

module SPMCache
  module Main
    def self.run(argv)
      # Ensure all lib files are loaded
      SPMCache::Main.load_all
      Command.run(argv)
    end

    def self.load_all
      lib_dir = File.expand_path(__dir__)
      # Load all .rb files recursively (sorted for deterministic order)
      Dir.glob("#{lib_dir}/**/*.rb").sort.each do |f|
        require f
      end
    end
  end
end

# Auto-require on load
SPMCache::Main.load_all
