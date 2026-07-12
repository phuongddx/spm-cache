# frozen_string_literal: true

require "fileutils"
require "spm_cache/core/sh"

module SPMCache
  module SPM
    module XCFramework
      class XCFramework
        attr_reader :name, :framework_paths, :output_path

        def initialize(name:, framework_paths: [], output_path: nil)
          @name = name
          @framework_paths = framework_paths
          @output_path = output_path
        end

        def build
          raise "No framework paths provided" if @framework_paths.empty?

          @output_path ||= File.join(Dir.pwd, "#{@name}.xcframework")
          FileUtils.rm_rf(@output_path)

          cmd = "xcodebuild -create-xcframework"
          @framework_paths.each do |fw_path|
            cmd += " -framework #{fw_path}"
          end
          cmd += " -output #{@output_path}"
          SPMCache::Core::Sh.run(cmd)

          @output_path
        end

        def add_framework_path(path)
          @framework_paths << path
        end
      end
    end
  end
end
