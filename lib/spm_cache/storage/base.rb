# frozen_string_literal: true

require "spm_cache/core/log"

module SPMCache
  module Storage
    class Base
      include SPMCache::Core::Log

      def pull
        print_warning("pull")
      end

      def push
        print_warning("push")
      end

      def configured?
        false
      end

      private

      def print_warning(action)
        Logger.warn("No remote cache configured. Skipping #{action}.")
        Logger.warn("Configure remote cache in spm-cache.yml to enable.")
      end
    end
  end
end
