# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "spm_cache/core/sh"
require "spm_cache/swift/sdk"
require "spm_cache/swift/swiftc"

module SPMCache
  module SPM
    class Buildable
      attr_reader :name, :module_name, :pkg_dir, :config
      attr_accessor :library_evolution, :scheme

      # Destinations supported for multi-slice builds
      DESTINATIONS = {
        "iphonesimulator" => "platform=iOS Simulator,name=iPhone 17",
        "iphoneos" => "generic/platform=iOS",
        "ios_simulator" => "platform=iOS Simulator,name=iPhone 17",
        "ios_device" => "generic/platform=iOS",
      }.freeze

      # Field bug: some vendored checkouts (AppAuth-iOS, FSPagerView -- both
      # carrying their own committed .xcodeproj, same shape as CryptoSwift)
      # hardcode an ancient IPHONEOS_DEPLOYMENT_TARGET (8.0 in both cases).
      # This surfaces as two DIFFERENT symptoms depending on the toolchain
      # path taken, but the same single root cause:
      #   1. AppAuth-iOS: linker error -- modern Xcode dropped the
      #      `libarclite` static libraries needed below ~iOS 11 ("SDK does
      #      not contain 'libarclite' ... try increasing the minimum
      #      deployment target").
      #   2. FSPagerView: Swift availability-check error on real API usage
      #      the source never guarded with @available/#available, because
      #      the project's own too-low target makes the compiler treat it
      #      as genuinely unavailable (e.g. "'layoutSublayers(of:)' is only
      #      available in iOS 10.0 or newer").
      # Verified empirically for both that appending
      # IPHONEOS_DEPLOYMENT_TARGET=13.0 on retry (overriding the project's
      # own setting) fixes it standalone. Well past both symptoms' cutoffs
      # and low enough to not restrict any realistic consumer, so safe as a
      # narrow, error-triggered retry rather than a blanket floor applied to
      # every build (which could silently lower an already-correct higher
      # deployment target for packages that build fine as-is).
      LOW_DEPLOYMENT_TARGET_RETRY_VALUE = "13.0"
      LOW_DEPLOYMENT_TARGET_ERROR_PATTERN = /SDK does not contain 'libarclite'|is only available in iOS \d+\.\d+ or newer/.freeze

      def initialize(name:, module_name: nil, pkg_dir:, config: "debug", library_evolution: true, scheme: nil)
        @name = name
        @module_name = module_name || name
        @pkg_dir = pkg_dir
        @config = config
        @library_evolution = library_evolution
        @scheme = scheme || name
      end

      def xcodebuild(destination, derived_data_path: nil, **opts)
        dd = derived_data_path || File.join(@pkg_dir, "DerivedData")
        cmd = build_command(destination, dd, opts)

        begin
          SPMCache::Core::Sh.run(cmd, cwd: @pkg_dir, live_log: opts[:live_log])
        rescue SPMCache::Core::GeneralError => e
          raise unless e.message.match?(LOW_DEPLOYMENT_TARGET_ERROR_PATTERN)

          retry_cmd = "#{cmd} IPHONEOS_DEPLOYMENT_TARGET=#{LOW_DEPLOYMENT_TARGET_RETRY_VALUE}"
          SPMCache::Core::Sh.run(retry_cmd, cwd: @pkg_dir, live_log: opts[:live_log])
        end
        dd
      end

      # Field bug: SkeletonView's checkout has real schemes named "SkeletonView
      # iOS"/"SkeletonView tvOS" -- containing a literal space. The unquoted
      # `-scheme #{@scheme}` interpolation split on the shell's word
      # boundary, so xcodebuild saw `-scheme SkeletonView iOS` as 3 separate
      # arguments and misread the trailing "iOS" as an unknown build action
      # ("xcodebuild: error: Unknown build action 'iOS'"). Every other
      # dynamic value in this command was already quoted (-destination,
      # -project); the scheme was the one place that wasn't.
      def build_command(destination, dd, opts = {})
        cmd = "xcodebuild build"
        cmd += project_disambiguation_flag
        cmd += " -scheme '#{@scheme}'"
        cmd += " -destination '#{destination}'"
        cmd += " -derivedDataPath #{dd}"
        cmd += " CODE_SIGNING_ALLOWED=NO"
        cmd += library_evolution_flags if @library_evolution
        cmd += " #{opts[:extra_args]}" if opts[:extra_args]
        cmd
      end

      # Field bug: SVGKit's checkout carries THREE committed .xcodeproj
      # files at its root (the library itself plus two demo apps) alongside
      # Package.swift -- xcodebuild refuses to guess which one to use
      # ("contains 3 projects, including multiple projects with the current
      # extension (.xcodeproj). Specify the project to use with the
      # -project option") and fails before even attempting to resolve a
      # scheme. Same root shape as CryptoSwift/AppAuth-iOS (a vendored
      # .xcodeproj alongside Package.swift), but those checkouts only ever
      # had exactly one, which Xcode's own implicit single-project
      # detection already resolves correctly on its own -- verified
      # empirically, unaffected by this method (0 or 1 candidates: returns
      # "" immediately, matching prior behavior exactly).
      def project_disambiguation_flag
        candidates = Dir.glob(File.join(@pkg_dir, "*.xcodeproj"))
        return "" if candidates.length < 2

        match = candidates.find { |proj| project_has_scheme?(proj, @scheme) }
        match ? " -project '#{match}'" : ""
      end

      def project_has_scheme?(project_path, scheme_name)
        list_output = Core::Sh.capture_output("xcodebuild -list -project '#{project_path}'")
        schemes = list_output.split("\n").drop_while { |l| !l.match?(/Schemes:/) }
                              .drop(1)
                              .map(&:strip)
                              .reject(&:empty?)
        schemes.any? { |s| s.casecmp(scheme_name).zero? }
      rescue SPMCache::Core::GeneralError
        false
      end

      def build_for_destination(destination_key, derived_data_path: nil, **opts)
        dest = DESTINATIONS[destination_key] || destination_key
        dd = xcodebuild(dest, derived_data_path: derived_data_path, opts: opts)

        # Find .o file in build products
        obj = find_object_file(dd)
        {
          derived_data: dd,
          object_file: obj,
          # Only look for a pre-built .framework when no raw .o was produced
          # -- see #find_framework for why, and avoid the wasted glob in the
          # common case where the .o lookup already succeeded.
          framework: obj ? nil : find_framework(dd),
          swiftmodule: find_file(dd, "#{@module_name}.swiftmodule"),
          swiftdoc: find_file(dd, "#{@module_name}.swiftdoc"),
          swiftsourceinfo: find_file(dd, "#{@module_name}.swiftsourceinfo"),
          swiftinterface: find_file(dd, "#{@module_name}.swiftinterface"),
        }
      end

      def find_object_file(derived_data)
        Dir.glob(File.join(derived_data, "**", "Products", "**", "#{@module_name}.o")).first ||
          Dir.glob(File.join(derived_data, "**", "#{@module_name}.o")).first
      end

      # Field bug: CryptoSwift's checkout carries its own committed
      # .xcodeproj (Xcode "Framework" target type) alongside its
      # Package.swift, so `swift package describe`/resolve_scheme correctly
      # resolves scheme "CryptoSwift" -- but xcodebuild links a genuine
      # `CryptoSwift.framework` bundle directly (verified: no `.o` exists
      # anywhere under DerivedData for this target), unlike a plain SPM
      # library product where spm-cache's own `create_framework` assembles
      # one from a raw `.o`. #find_object_file's glob then finds nothing and
      # the build was silently reported as failed even though it succeeded.
      # Only reached when no `.o` was found, so packages that DO build via
      # the normal SPM/object-file path are unaffected.
      def find_framework(derived_data)
        Dir.glob(File.join(derived_data, "**", "Products", "**", "#{@module_name}.framework")).first
      end

      def find_file(derived_data, basename)
        Dir.glob(File.join(derived_data, "**", "Objects-normal", "arm64", basename)).first ||
          Dir.glob(File.join(derived_data, "**", basename)).first
      end

      def create_static_library(object_file, output_path = nil)
        output_path ||= File.join(Dir.mktmpdir, @module_name)
        SPMCache::Core::Sh.run("libtool -static -o #{output_path} #{object_file}")
        output_path
      end

      def create_framework(artifacts, output_dir)
        fw_dir = File.join(output_dir, "#{@module_name}.framework")
        FileUtils.mkdir_p(fw_dir)

        # 1. Static library binary
        if artifacts[:object_file] && File.exist?(artifacts[:object_file])
          lib = create_static_library(artifacts[:object_file])
          FileUtils.cp(lib, File.join(fw_dir, @module_name))
        end

        # 2. Info.plist
        File.write(File.join(fw_dir, "Info.plist"), framework_info_plist)

        # 3. Modules
        modules_dir = File.join(fw_dir, "Modules")
        FileUtils.mkdir_p(modules_dir)

        # Swiftmodule directory with swiftinterface
        if artifacts[:swiftinterface]
          arch = destination_arch(artifacts)
          sm_dir = File.join(modules_dir, "#{@module_name}.swiftmodule")
          FileUtils.mkdir_p(sm_dir)
          FileUtils.cp(artifacts[:swiftinterface], File.join(sm_dir, arch))
        end

        copy_module_artifact(artifacts[:swiftmodule], modules_dir)
        copy_module_artifact(artifacts[:swiftdoc], modules_dir)
        copy_module_artifact(artifacts[:swiftsourceinfo], modules_dir)

        fw_dir
      end

      # Counterpart to #create_framework for the case where xcodebuild
      # already produced a real `.framework` bundle directly (see
      # #find_framework) -- copies it as-is instead of assembling one from a
      # raw `.o`, since there isn't one to assemble from.
      def use_existing_framework(artifacts, output_dir)
        fw_dir = File.join(output_dir, "#{@module_name}.framework")
        FileUtils.cp_r(artifacts[:framework], fw_dir)
        fw_dir
      end

      private

      # Some build configurations (multi-arch / library-evolution builds,
      # seen with binaryTarget-wrapping packages like eh_xcframework) emit
      # `ModuleName.swiftmodule` as a DIRECTORY bundle -- containing one set
      # of per-arch .swiftmodule/.swiftdoc/.swiftsourceinfo files -- instead
      # of `find_file`'s expected flat single-file form under
      # Objects-normal/<arch>/. `find_file`'s glob doesn't distinguish the
      # two shapes (`Dir.glob` matches directories too), so `FileUtils.cp`
      # crashed with Errno::EISDIR when it landed on the directory form.
      # `cp_r`'s contents merge into `destination` rather than replacing it,
      # so this is safe even when `sm_dir` was already created above from
      # `artifacts[:swiftinterface]` for the same module name.
      def copy_module_artifact(source, modules_dir)
        return unless source && File.exist?(source)

        destination = File.join(modules_dir, File.basename(source))
        if File.directory?(source)
          FileUtils.mkdir_p(destination)
          FileUtils.cp_r(Dir.glob(File.join(source, "*")), destination)
        else
          FileUtils.cp(source, destination)
        end
      end

      def destination_arch(artifacts)
        dd = artifacts[:derived_data] || ""
        if dd.include?("Simulator") || dd.include?("sim") || dd.include?("Sim")
          "arm64-apple-ios-simulator.swiftinterface"
        else
          "arm64-apple-ios.swiftinterface"
        end
      end

      def framework_info_plist
        %(<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
<key>CFBundleExecutable</key><string>#{@module_name}</string>
<key>CFBundleIdentifier</key><string>com.spm-cache.#{@module_name.downcase}</string>
<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
<key>CFBundleName</key><string>#{@module_name}</string>
<key>CFBundlePackageType</key><string>FMWK</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
</dict>
</plist>)
      end

      def library_evolution_flags
        " OTHER_SWIFT_FLAGS='-enable-library-evolution -emit-module-interface -no-verify-emitted-module-interface'"
      end
    end
  end
end
