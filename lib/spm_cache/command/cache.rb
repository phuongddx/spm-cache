# frozen_string_literal: true

module SPMCache
  class Command
    class Cache < Command
      self.abstract_command = true
      def self.default_subcommand; nil; end
      self.summary = "Cache management commands"
      self.description = "List or clean cached SPM packages."
    end
  end
end

require "spm_cache/command/cache/list"
require "spm_cache/command/cache/clean"
