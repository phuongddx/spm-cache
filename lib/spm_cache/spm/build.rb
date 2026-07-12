# frozen_string_literal: true

require "fileutils"
require "spm_cache/core/sh"
require "spm_cache/swift/sdk"
require "spm_cache/swift/swiftc"

module SPMCache
  module SPM
    class Buildable
      attr_reader :name, :module_name, :pkg_dir, :sdks, :config
      attr_accessor :library_evolution

      def initialize(name:, module_name: nil, pkg_dir:, sdks: [], config: "debug", library_evolution: true)
        @name = name
        @module_name = module_name || name
        @pkg_dir = pkg_dir
        @sdks = sdks
        @config = config
        @library_evolution = library_evolution
      end

      def swift_build(sdk, opts = {})
        build_dir = opts[:build_dir] || File.join(@pkg_dir, ".build")
        cmd = "swift build"
        cmd += " -c #{@config}"
        cmd += " --target #{@name}"
        cmd += " --sdk #{sdk.name}" if sdk.name
        cmd += " -Xswiftc -target -Xswiftc #{sdk.triple}" if sdk.triple
        cmd += library_evolution_flags if @library_evolution
        cmd += " --build-path #{build_dir}"
        cmd += " #{opts[:extra_args]}" if opts[:extra_args]

        Sh.run(cmd, cwd: @pkg_dir, live_log: opts[:live_log])
        build_dir
      end

      def build_products_dir(sdk)
        File.join(@pkg_dir, ".build", sdk.triple, @config)
      end

      def object_files(sdk)
        build_dir = File.join(@pkg_dir, ".build", sdk.triple, @config, "#{@name}.build")
        return [] unless File.directory?(build_dir)

        Dir.glob(File.join(build_dir, "**", "*.o"))
      end

      def swiftmodule_path(sdk)
        build_dir = build_products_dir(sdk)
        base = File.join(build_dir, "Modules", @module_name)
        swiftinterface = "#{base}.swiftinterface"
        swiftmodule = "#{base}.swiftmodule"
        File.exist?(swiftinterface) ? swiftinterface : swiftmodule
      end

      private

      def library_evolution_flags
        return "" unless @library_evolution

        " -Xswiftc -enable-library-evolution" \
        " -Xswiftc -emit-module-interface" \
        " -Xswiftc -no-verify-emitted-module-interface"
      end
    end
  end
end
