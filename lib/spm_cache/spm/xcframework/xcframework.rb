# frozen_string_literal: true

require "fileutils"
require "spm_cache/core/sh"
require "spm_cache/spm/xcframework/slice"

module SPMCache
  module SPM
    module XCFramework
      class XCFramework
        attr_reader :name, :slices, :output_path

        def initialize(name:, slices: [], output_path: nil)
          @name = name
          @slices = slices
          @output_path = output_path
        end

        def build(merge_slices: true)
          framework_paths = @slices.map do |slice|
            slice.create_framework
          end

          @output_path ||= File.join(Dir.pwd, "#{@name}.xcframework")
          FileUtils.rm_rf(@output_path)

          if merge_slices && framework_paths.size > 1
            create_xcframework(framework_paths)
          else
            create_xcframework(framework_paths)
          end

          @output_path
        end

        def add_slice(slice)
          @slices << slice
        end

        private

        def create_xcframework(framework_paths)
          cmd = "xcodebuild -create-xcframework"
          framework_paths.each do |fw_path|
            cmd += " -framework #{fw_path}"
          end
          cmd += " -output #{@output_path}"
          Sh.run(cmd)
        end
      end
    end
  end
end
