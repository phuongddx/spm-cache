# frozen_string_literal: true

module SPMCache
  class Command
    module Options
      SDK = "iphonesimulator"
      CONFIG = "debug"
      LOG_DIR = nil
      MERGE_SLICES = true
      LIBRARY_EVOLUTION = true
    end

    module BaseOptions
      def sdk
        @sdk || Options::SDK
      end

      def config
        @config || Options::CONFIG
      end

      def log_dir
        @log_dir || Options::LOG_DIR
      end

      def merge_slices?
        @merge_slices.nil? ? Options::MERGE_SLICES : @merge_slices
      end

      def library_evolution?
        @library_evolution.nil? ? Options::LIBRARY_EVOLUTION : @library_evolution
      end
    end

    # Base is kept for potential abstract subcommand groups (cache, pkg, remote)
    class Base < Command
      self.abstract_command = true
      include BaseOptions
    end
  end
end
