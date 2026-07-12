# frozen_string_literal: true

require "spm_cache/command/pkg"
require "spm_cache/spm/pkg/base"
require "spm_cache/core/log"

module SPMCache
  class Command
    class Pkg
      class Build < Pkg
        include Core::Log
        include BaseOptions

        self.summary = "Build a single package into a multi-slice xcframework"

        def self.options
          [
            ["--out=PATH", "Output directory for xcframework (default: current dir)"],
            ["--checksum", "Compute and display checksum"],
            ["--sdk=SDK", "SDK to build for: iphonesimulator, iphoneos, or all (default: all)"],
            ["--no-library-evolution", "Disable Swift library evolution flags"],
          ].concat(super.reject { |opt| opt[0] =~ /^--sdk/ })
        end

        def initialize(argv)
          @target_name = argv.arguments!.first
          @out = argv.option("out", ".")
          @checksum = argv.flag?("checksum", false)
          @sdk_name = argv.option("sdk", "all")
          @no_lib_evo = argv.flag?("library-evolution", true)
          super
        end

        def run
          raise "Target name required" unless @target_name

          pkg_dir = Dir.pwd
          destinations = resolve_destinations(@sdk_name)
          puts "Building #{@target_name} for #{destinations.join(', ')}..."

          library_evo = @no_lib_evo

          # Build directly using Buildable (bypasses swift package describe)
          buildable = SPM::Buildable.new(
            name: @target_name,
            module_name: @target_name,
            pkg_dir: pkg_dir,
            library_evolution: library_evo,
            scheme: @target_name,
          )

          require "tmpdir"
          tmpdir = Dir.mktmpdir
          framework_paths = []

          destinations.each do |dest_key|
            puts "  Building for #{dest_key}..."
            dd = File.join(pkg_dir, "DerivedData_#{dest_key}")
            begin
              artifacts = buildable.build_for_destination(dest_key, derived_data_path: dd)
            rescue => e
              puts "  WARNING: #{dest_key} build failed: #{e.message}"
              next
            end
            next unless artifacts[:object_file]

            # Create framework with correct module name inside temp dir
            fw_subdir = File.join(tmpdir, dest_key)
            FileUtils.mkdir_p(fw_subdir)
            fw_dir = buildable.create_framework(artifacts, fw_subdir)
            framework_paths << fw_dir
            puts "  #{dest_key} framework built"
          end

          if framework_paths.empty?
            puts "ERROR: No slices were built successfully"
            return
          end

          output_path = File.join(@out, "#{@target_name}.xcframework")
          require "fileutils"
          FileUtils.rm_rf(output_path)

          xcframework = SPM::XCFramework::XCFramework.new(
            name: @target_name,
            framework_paths: framework_paths,
            output_path: output_path,
          )
          result = xcframework.build

          puts "Built: #{result}"
          FileUtils.rm_rf(tmpdir)

          if result && File.exist?(result)
            slices = Dir.entries(result).reject { |e| e.start_with?(".") || e == "Info.plist" }
            puts "Slices: #{slices.join(', ')}"
            puts "Size: #{`du -sh #{result}`.split.first}"
          end
        end

        private

        def resolve_destinations(sdk_name)
          case sdk_name
          when "all"
            SPM::Package::DEFAULT_DESTINATIONS
          when "iphonesimulator", "ios_simulator"
            ["iphonesimulator"]
          when "iphoneos", "ios_device"
            ["iphoneos"]
          else
            [sdk_name]
          end
        end
      end
    end
  end
end
