# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "spm_cache/core/sh"
require "spm_cache/spm/desc/desc"
require "spm_cache/spm/build"
require "spm_cache/spm/xcframework/xcframework"
require "spm_cache/spm/macro"

module SPMCache
  module SPM
    class Package
      attr_reader :root_dir, :config

      # Default destinations: simulator + device for multi-slice xcframeworks
      DEFAULT_DESTINATIONS = ["iphonesimulator", "iphoneos"].freeze

      def initialize(root_dir:, config: "debug")
        @root_dir = root_dir
        @config = config
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
        destinations = opts[:destinations] || DEFAULT_DESTINATIONS
        library_evolution = opts.fetch(:library_evolution, true)

        buildable = Buildable.new(
          name: target.name,
          module_name: target.module_name,
          pkg_dir: @root_dir,
          config: @config,
          library_evolution: library_evolution,
          scheme: target.name,
        )

        framework_paths = []
        tmpdir = Dir.mktmpdir

        destinations.each do |dest_key|
          UI.info "  Building #{target.name} for #{dest_key}..."
          dd = File.join(@root_dir, "DerivedData_#{dest_key}")
          artifacts = buildable.build_for_destination(dest_key, derived_data_path: dd)
          next unless artifacts[:object_file]

          fw_dir = buildable.create_framework(artifacts, tmpdir)
          # Rename to avoid collision (sim and device have same framework name)
          fw_dest = File.join(tmpdir, "#{dest_key}_#{target.module_name}.framework")
          FileUtils.rm_rf(fw_dest)
          FileUtils.cp_r(fw_dir, fw_dest)
          framework_paths << fw_dest
        end

        if framework_paths.empty?
          raise "Failed to build any slices for #{target.name}"
        end

        output_path = opts[:output_path] || File.join(Dir.pwd, "#{target.module_name}.xcframework")
        xcframework = XCFramework::XCFramework.new(
          name: target.module_name,
          framework_paths: framework_paths,
          output_path: output_path,
        )
        xcframework.build

        FileUtils.rm_rf(tmpdir)
        output_path
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
