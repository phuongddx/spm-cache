# frozen_string_literal: true

module SPMCache
  class Command
    class Pkg < Command
      self.abstract_command = true
      def self.default_subcommand; nil; end
      self.summary = "Package commands"
      self.description = "Build or inspect individual SPM packages."
    end
  end
end

require "spm_cache/command/pkg/build"
