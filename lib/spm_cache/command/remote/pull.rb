# frozen_string_literal: true

require "spm_cache/command/remote"

module SPMCache
  class Command
    class Remote
      class Pull < Remote
        self.summary = "Pull cache from remote"

        def self.options
          [["--config=CONFIG", "Build configuration (default: debug)"]].concat(super)
        end

        def initialize(argv)
          @config_name = argv.option("config", "debug")
          super
        end

        def run
          storage = Remote.create_storage(@config_name)
          storage.pull
        end
      end
    end
  end
end
