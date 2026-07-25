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

        # Field bug: when `xcodebuild -create-xcframework` fails partway
        # through (e.g. AEXML's missing-swiftinterface error), it can still
        # have already written a partial bundle skeleton (an Info.plist with
        # no actual framework slice) to @output_path before erroring out.
        # Nothing previously cleaned that up on failure, so it sat in the
        # cache directory looking exactly like a valid entry -- a later run
        # only checks path existence to decide "hit" vs "missed", so it
        # silently treated the corrupted artifact as permanently cached and
        # never retried the build, even after the underlying bug was fixed.
        # Verified empirically: reproduced the leftover Info.plist-only
        # AEXML.xcframework, confirmed removing it let the retry proceed.
        def build
          raise "No framework paths provided" if @framework_paths.empty?

          @output_path ||= File.join(Dir.pwd, "#{@name}.xcframework")
          FileUtils.rm_rf(@output_path)

          cmd = "xcodebuild -create-xcframework"
          @framework_paths.each do |fw_path|
            cmd += " -framework #{fw_path}"
          end
          cmd += " -output #{@output_path}"
          begin
            SPMCache::Core::Sh.run(cmd)
          rescue StandardError
            FileUtils.rm_rf(@output_path)
            raise
          end

          @output_path
        end

        def add_framework_path(path)
          @framework_paths << path
        end
      end
    end
  end
end
