# frozen_string_literal: true

require "fileutils"
require "spm_cache/core/sh"
require "spm_cache/spm/desc/desc"
require "spm_cache/spm/build"
require "spm_cache/spm/xcframework/xcframework"
require "spm_cache/spm/xcframework/slice"
require "spm_cache/spm/macro"

module SPMCache
  module SPM
    class Package
      attr_reader :root_dir, :config, :sdks

      def initialize(root_dir:, config: "debug", sdks: [])
        @root_dir = root_dir
        @config = config
        @sdks = sdks
        @pkg_desc = nil
      end

      def pkg_desc
        return @pkg_desc if @pkg_desc

        @pkg_desc = Desc::Description.new(name: package_name, pkg_dir: @root_dir)
        @pkg_desc.fetch
        @pkg_desc
      end

      def package_name
        File.basename(@root_dir)
      end

      def get_target(name)
        pkg_desc.get_target(name)
      end

      def validate!
        raise "Package.swift not found in #{@root_dir}" unless File.exist?(File.join(@root_dir, "Package.swift"))
        raise "No targets found in package" if pkg_desc.targets.empty?
        true
      end

      def resolve
        Sh.run("swift package resolve", cwd: @root_dir)
      end

      def build_target(target_name, opts = {})
        target = get_target(target_name)
        raise "Target not found: #{target_name}" unless target

        if target.macro?
          build_macro(target, opts)
        elsif target.binary?
          raise "Cannot build binary target: #{target_name}"
        else
          build_xcframework(target, opts)
        end
      end

      def build(opts = {})
        targets = opts[:targets] || pkg_desc.targets.reject { |t| t.binary? }.map(&:name)
        results = {}
        targets.each do |name|
          results[name] = build_target(name, opts)
        end
        results
      end

      private

      def build_xcframework(target, opts)
        buildable = Buildable.new(
          name: target.name,
          module_name: target.module_name,
          pkg_dir: @root_dir,
          sdks: @sdks,
          config: @config,
          library_evolution: opts.fetch(:library_evolution, true),
        )

        slices = (@sdks.any? ? @sdks : [Swift::Sdk.for_iphonesimulator]).map do |sdk|
          XCFramework::FrameworkSlice.new(target: target, sdk: sdk, buildable: buildable)
        end

        output_path = opts[:output_path] || File.join(Dir.pwd, "#{target.module_name}.xcframework")
        xcframework = XCFramework::XCFramework.new(
          name: target.module_name,
          slices: slices,
          output_path: output_path,
        )
        xcframework.build(merge_slices: opts.fetch(:merge_slices, true))
      end

      def build_macro(target, opts)
        macro = Macro.new(
          target_name: target.name,
          module_name: target.module_name,
          pkg_dir: @root_dir,
          config: @config,
        )
        macro.build(opts[:output_path])
      end
    end
  end
end
