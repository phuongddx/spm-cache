# frozen_string_literal: true

require "spm_cache/core/sh"

module SPMCache
  module Swift
    class Sdk
      attr_reader :name, :arch, :vendor, :platform, :version

      def initialize(name:, arch:, vendor:, platform:, version: nil)
        @name = name
        @arch = arch
        @vendor = vendor
        @platform = platform
        @version = version
      end

      def triple
        "#{arch}-#{vendor}-#{platform}#{version_suffix}"
      end

      def simulator?
        platform.include?("simulator")
      end

      def sdk_path
        @sdk_path ||= Sh.capture_output("xcrun --sdk #{name} --show-sdk-path")
      rescue
        nil
      end

      def swiftc_args
        args = ["-sdk", name, "-target", triple]
        args += ["-Xswiftc", "-emit-module-interface"] if library_evolution?
        args
      end

      def library_evolution?
        @library_evolution
      end

      def self.for_iphonesimulator(arch = "arm64")
        new(
          name: "iphonesimulator",
          arch: arch,
          vendor: "apple",
          platform: "ios-simulator",
        )
      end

      def self.for_iphoneos(arch = "arm64")
        new(
          name: "iphoneos",
          arch: arch,
          vendor: "apple",
          platform: "ios",
        )
      end

      def self.for_macos(arch: nil)
        arch ||= `uname -m`.strip
        new(
          name: "macosx",
          arch: arch,
          vendor: "apple",
          platform: "macosx",
        )
      end

      def self.resolve(name, arch = nil)
        case name
        when "iphonesimulator"
          for_iphonesimulator(arch || "arm64")
        when "iphoneos"
          for_iphoneos(arch || "arm64")
        when "macosx", "macos"
          for_macos(arch: arch)
        else
          raise "Unknown SDK: #{name}"
        end
      end

      private

      def version_suffix
        @version ? @version.to_s : ""
      end
    end
  end
end
