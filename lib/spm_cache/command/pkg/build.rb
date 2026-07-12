# frozen_string_literal: true

require "spm_cache/command/pkg"
require "spm_cache/spm/pkg/base"
require "spm_cache/swift/sdk"

module SPMCache
  class Command
    class Pkg
      class Build < Pkg
        self.summary = "Build a single package into an xcframework"

        def self.options
          [
            ["--out=PATH", "Output directory for xcframework"],
            ["--checksum", "Compute and display checksum"],
            ["--sdk=SDK", "SDK to build for (default: iphonesimulator)"],
          ].concat(super)
        end

        def initialize(argv)
          @target_name = argv.arguments!.first
          @out = argv.option("out", ".")
          @checksum = argv.flag?("checksum", false)
          @sdk_name = argv.option("sdk", "iphonesimulator")
          super
        end

        def run
          raise "Target name required" unless @target_name

          pkg_dir = Dir.pwd
          sdk = Swift::Sdk.resolve(@sdk_name)
          package = SPM::Package.new(root_dir: pkg_dir, sdks: [sdk])

          output_path = File.join(@out, "#{@target_name}.xcframework")
          result = package.build_target(@target_name, output_path: output_path)
          puts "Built: #{result}"

          if @checksum && result && File.exist?(result)
            metadata = SPM::XCFramework::Metadata.new(xcframework_path: result)
            puts "Checksum: #{metadata.checksum}"
          end
        end
      end
    end
  end
end
