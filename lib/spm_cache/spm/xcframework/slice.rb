# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "spm_cache/core/sh"
require "spm_cache/spm/build"
require "spm_cache/utils/template"

module SPMCache
  module SPM
    module XCFramework
      class FrameworkSlice
        attr_reader :target, :sdk, :buildable, :framework_path

        def initialize(target:, sdk:, buildable:)
          @target = target
          @sdk = sdk
          @buildable = buildable
          @framework_path = nil
        end

        def create_framework(output_dir = nil)
          @buildable.swift_build(@sdk)
          @framework_path = File.join(output_dir || Dir.mktmpdir, "#{@target.module_name}.framework")
          FileUtils.mkdir_p(@framework_path)

          create_framework_binary
          create_info_plist
          create_headers if @target.respond_to?(:header_paths) && @target.header_paths.any?
          create_modules
          copy_resource_bundles if @target.respond_to?(:resource_paths) && @target.resource_paths.any?
          override_resource_bundle_accessor if @target.respond_to?(:resource_paths) && @target.resource_paths.any?

          @framework_path
        end

        def triple
          @sdk.triple
        end

        def simulator?
          @sdk.simulator?
        end

        private

        def build_products_dir
          @buildable.build_products_dir(@sdk)
        end

        def object_files
          @buildable.object_files(@sdk)
        end

        def create_framework_binary
          binary_path = File.join(@framework_path, @target.module_name)
          objs = object_files
          raise "No object files found for #{@target.name}" if objs.empty?

          filelist = Tempfile.new(["objs", ".txt"])
          filelist.write(objs.join("\n"))
          filelist.close

          Sh.run("libtool -static -o #{binary_path} -filelist #{filelist.path}")
          filelist.unlink
        end

        def create_info_plist
          Utils::Template.render_to("framework.info.plist", File.join(@framework_path, "Info.plist"), {
            module_name: @target.module_name,
            bundle_identifier: "com.spm-cache.#{@target.module_name.downcase}",
          })
        end

        def create_headers
          headers_dir = File.join(@framework_path, "Headers")
          FileUtils.mkdir_p(headers_dir)

          umbrella_header = File.join(headers_dir, "#{@target.module_name}.h")
          File.write(umbrella_header, umbrella_header_content)

          @target.header_paths.each do |header_path|
            next unless File.exist?(header_path)
            dest = File.join(headers_dir, File.basename(header_path))
            content = File.read(header_path)
            content = fix_angle_bracket_imports(content) if content.include?("#import <")
            File.write(dest, content)
          end
        end

        def create_modules
          modules_dir = File.join(@framework_path, "Modules")
          FileUtils.mkdir_p(modules_dir)

          modulemap_path = File.join(modules_dir, "module.modulemap")
          Utils::Template.render_to("framework.modulemap", modulemap_path, {
            module_name: @target.module_name,
            umbrella_header: "#{@target.module_name}.h",
          })

          copy_swiftmodule_and_interface(modules_dir)
        end

        def copy_swiftmodule_and_interface(modules_dir)
          build_dir = build_products_dir
          modules_build = File.join(@pkg_dir || @buildable.pkg_dir, ".build", @sdk.triple, @config || @buildable.config, "Modules")
          return unless File.directory?(modules_build)

          Dir.glob(File.join(modules_build, "*.swiftinterface")).each do |f|
            FileUtils.cp(f, File.join(modules_dir, File.basename(f)))
          end

          Dir.glob(File.join(modules_build, "*.swiftmodule")).each do |f|
            FileUtils.cp(f, File.join(modules_dir, File.basename(f)))
          end

          Dir.glob(File.join(modules_build, "*.swiftdoc")).each do |f|
            FileUtils.cp(f, File.join(modules_dir, File.basename(f)))
          end
        end

        def copy_resource_bundles
          build_dir = build_products_dir
          Dir.glob(File.join(build_dir, "*.bundle")).each do |bundle|
            dest = File.join(@framework_path, File.basename(bundle))
            FileUtils.cp_r(bundle, dest) unless File.exist?(dest)
          end
        end

        def override_resource_bundle_accessor
          swift_dir = build_products_dir
          bundles = Dir.glob(File.join(swift_dir, "*.bundle")).map { |b| File.basename(b, ".bundle") }
          return if bundles.empty?

          bundles.each do |bundle_name|
            accessor_swift = Utils::Template.render("resource_bundle_accessor.swift", {
              module_name: @target.module_name,
              bundle_name: bundle_name,
            })
            compile_and_replace_accessor(swift_dir, accessor_swift, bundle_name)
          end
        end

        def compile_and_replace_accessor(build_dir, source, bundle_name)
          temp_file = Tempfile.new(["accessor", ".swift"])
          temp_file.write(source)
          temp_file.close

          begin
            output_path = File.join(build_dir, "#{bundle_name}.bundle", "ResourceBundleAccessor.o")
            Sh.run("swiftc -parse-as-library -emit-object -o #{output_path} #{temp_file.path}")
          rescue
          end

          temp_file.unlink
        end

        def umbrella_header_content
          headers = (@target.respond_to?(:header_paths) ? @target.header_paths : []).map do |h|
            "#import <#{File.basename(h)}>"
          end
          <<~H
            #import <Foundation/Foundation.h>
            #{headers.join("\n")}
            //! Project version number for #{@target.module_name}.
            FOUNDATION_EXPORT double #{@target.module_name}VersionNumber;
            //! Project version string for #{@target.module_name}.
            FOUNDATION_EXPORT const unsigned char #{@target.module_name}VersionString[];
          H
        end

        def fix_angle_bracket_imports(content)
          content.gsub(/#import <([^\/>]+\.h)>/) do
            "#import \"#{$1}\""
          end
        end
      end
    end
  end
end
