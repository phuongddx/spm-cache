# frozen_string_literal: true

require "spm_cache/command/remote"

module SPMCache
  class Command
    class Remote
      class Push < Remote
        self.summary = "Push cache to remote"

        def self.options
          [["--config=CONFIG", "Build configuration (default: debug)"]].concat(super)
        end

        def initialize(argv)
          @config_name = argv.option("config", "debug")
          super
        end

        def run
          storage = Remote.create_storage(@config_name)
          storage.push
        end
      end
    end
  end
end
