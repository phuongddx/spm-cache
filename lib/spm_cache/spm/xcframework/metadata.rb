# frozen_string_literal: true

require "json"
require "digest"
require "spm_cache/core/syntax/plist"

module SPMCache
  module SPM
    module XCFramework
      class Metadata
        include SPMCache::Core::Syntax::PlistRepresentable

        attr_reader :xcframework_path

        def initialize(xcframework_path:)
          @xcframework_path = xcframework_path
          @path = File.join(xcframework_path, "Info.xcframework")
          @raw = {}
          load(@path) if File.exist?(@path)
        end

        def available_libraries
          (raw["AvailableLibraries"] || []).map do |lib|
            {
              name: lib["LibraryIdentifier"],
              path: lib["LibraryPath"],
              architectures: lib["SupportedArchitectures"] || [],
              platform: lib["SupportedPlatform"],
              variant: lib["SupportedPlatformVariant"],
            }
          end
        end

        def triples
          available_libraries.map do |lib|
            arch = lib[:architectures].first || "arm64"
            platform = lib[:platform] || "ios"
            variant = lib[:variant]
            suffix = variant ? "-#{variant}" : ""
            "#{arch}-apple-#{platform}#{suffix}"
          end
        end

        def checksum
          return nil unless File.exist?(@xcframework_path)

          entries = Dir.glob(File.join(@xcframework_path, "**/*")).select { |f| File.file?(f) }.sort
          combined = entries.map { |f| Digest::SHA256.file(f).hexdigest }.join
          Digest::SHA256.hexdigest(combined)
        end

        def checksum_short
          checksum&.[](0..7)
        end
      end
    end
  end
end
