# frozen_string_literal: true

require "spm_cache/command/pkg"
require "spm_cache/spm/build_pipeline"
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

          result = SPM::BuildPipeline.run(
            name: @target_name,
            pkg_dir: pkg_dir,
            destinations: destinations,
            out_dir: @out,
            library_evolution: library_evo,
          )

          puts "Built: #{result}"

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
