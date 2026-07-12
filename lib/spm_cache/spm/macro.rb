# frozen_string_literal: true

require "fileutils"
require "spm_cache/core/sh"
require "spm_cache/spm/build"

module SPMCache
  module SPM
    class Macro
      attr_reader :target_name, :module_name, :pkg_dir, :config

      def initialize(target_name:, module_name: nil, pkg_dir:, config: "debug")
        @target_name = target_name
        @module_name = module_name || target_name
        @pkg_dir = pkg_dir
        @config = config
      end

      def build(output_dir = nil)
        cmd = "swift build -c #{@config} --target #{@target_name}"
        Sh.run(cmd, cwd: @pkg_dir)

        tool_binary = find_tool_binary
        raise "Macro tool binary not found for #{@target_name}" unless tool_binary

        output_dir ||= File.join(@pkg_dir, ".build", @config)
        FileUtils.mkdir_p(output_dir)
        dest = File.join(output_dir, "#{@module_name}.macro")
        FileUtils.cp(tool_binary, dest)
        dest
      end

      private

      def find_tool_binary
        build_dir = File.join(@pkg_dir, ".build", @config)
        return nil unless File.directory?(build_dir)

        binary = File.join(build_dir, @target_name)
        return binary if File.executable?(binary)

        Dir.glob(File.join(build_dir, "**", @target_name)).find { |f| File.executable?(f) }
      end
    end
  end
end
