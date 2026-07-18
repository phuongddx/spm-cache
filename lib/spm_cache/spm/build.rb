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
        cmd = "xcodebuild build"
        cmd += " -scheme #{@scheme}"
        cmd += " -destination '#{destination}'"
        cmd += " -derivedDataPath #{dd}"
        cmd += " CODE_SIGNING_ALLOWED=NO"
        cmd += library_evolution_flags if @library_evolution
        cmd += " #{opts[:extra_args]}" if opts[:extra_args]

        SPMCache::Core::Sh.run(cmd, cwd: @pkg_dir, live_log: opts[:live_log])
        dd
      end

      def build_for_destination(destination_key, derived_data_path: nil, **opts)
        dest = DESTINATIONS[destination_key] || destination_key
        dd = xcodebuild(dest, derived_data_path: derived_data_path, opts: opts)

        # Find .o file in build products
        obj = find_object_file(dd)
        {
          derived_data: dd,
          object_file: obj,
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
