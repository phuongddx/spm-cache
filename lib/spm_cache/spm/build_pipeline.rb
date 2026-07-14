# frozen_string_literal: true

require "fileutils"
require "tmpdir"

require "spm_cache/core/log"
require "spm_cache/core/sh"
require "spm_cache/spm/build"
require "spm_cache/spm/xcframework/xcframework"

module SPMCache
  module SPM
    # Shared xcframework build pipeline used by both `spm-cache pkg build` and
    # `Installer::Build`. Encapsulates the per-destination build loop, framework
    # assembly, and xcframework creation.
    module BuildPipeline
      class << self
        include Core::Log

        # Build `name` from `pkg_dir` into a multi-slice xcframework located at
        # `out_dir/<name>.xcframework`. Returns the output path on success.
        #
        # @param name [String] scheme / product name to build
        # @param pkg_dir [String] package checkout directory containing Package.swift
        # @param destinations [Array<String>] destination keys (see Buildable::DESTINATIONS)
        # @param out_dir [String] directory to write the xcframework into
        # @param library_evolution [Boolean] emit library-evolution Swift flags
        def run(name:, pkg_dir:, destinations:, out_dir:, library_evolution: true)
          raise "Target name required" if name.nil? || name.empty?

          FileUtils.mkdir_p(out_dir)

          buildable = Buildable.new(
            name: name,
            module_name: name,
            pkg_dir: pkg_dir,
            library_evolution: library_evolution,
            scheme: name,
          )

          tmpdir = Dir.mktmpdir
          framework_paths = []

          destinations.each do |dest_key|
            Core::UI.info "  Building #{name} for #{dest_key}..."
            dd = File.join(pkg_dir, "DerivedData_#{dest_key}")
            begin
              artifacts = buildable.build_for_destination(dest_key, derived_data_path: dd)
            rescue => e
              Core::UI.warn "#{dest_key} build failed: #{e.message}"
              next
            end
            next unless artifacts[:object_file]

            fw_subdir = File.join(tmpdir, dest_key)
            FileUtils.mkdir_p(fw_subdir)
            fw_dir = buildable.create_framework(artifacts, fw_subdir)
            framework_paths << fw_dir
          end

          if framework_paths.empty?
            # Scheme-name fallback: try listing schemes and retry once.
            alt = resolve_scheme_fallback(name, pkg_dir)
            if alt && alt != name
              Core::UI.info "  Retrying with scheme '#{alt}'..."
              return run_with_scheme(name: name, scheme: alt, pkg_dir: pkg_dir,
                                     destinations: destinations, out_dir: out_dir,
                                     library_evolution: library_evolution)
            end
            raise "No slices were built successfully for #{name}"
          end

          output_path = File.join(out_dir, "#{name}.xcframework")
          FileUtils.rm_rf(output_path)

          xcframework = XCFramework::XCFramework.new(
            name: name,
            framework_paths: framework_paths,
            output_path: output_path,
          )
          result = xcframework.build
          FileUtils.rm_rf(tmpdir)
          result
        end

        private

        def run_with_scheme(name:, scheme:, pkg_dir:, destinations:, out_dir:, library_evolution:)
          buildable = Buildable.new(
            name: name,
            module_name: name,
            pkg_dir: pkg_dir,
            library_evolution: library_evolution,
            scheme: scheme,
          )

          tmpdir = Dir.mktmpdir
          framework_paths = []

          destinations.each do |dest_key|
            Core::UI.info "  Building #{name} (scheme #{scheme}) for #{dest_key}..."
            dd = File.join(pkg_dir, "DerivedData_#{dest_key}")
            begin
              artifacts = buildable.build_for_destination(dest_key, derived_data_path: dd)
            rescue => e
              Core::UI.warn "#{dest_key} build failed: #{e.message}"
              next
            end
            next unless artifacts[:object_file]

            fw_subdir = File.join(tmpdir, dest_key)
            FileUtils.mkdir_p(fw_subdir)
            fw_dir = buildable.create_framework(artifacts, fw_subdir)
            framework_paths << fw_dir
          end

          raise "No slices were built successfully for #{name}" if framework_paths.empty?

          output_path = File.join(out_dir, "#{name}.xcframework")
          FileUtils.rm_rf(output_path)

          xcframework = XCFramework::XCFramework.new(
            name: name,
            framework_paths: framework_paths,
            output_path: output_path,
          )
          result = xcframework.build
          FileUtils.rm_rf(tmpdir)
          result
        end

        def resolve_scheme_fallback(name, pkg_dir)
          list_output = Core::Sh.capture_output("xcodebuild -list", cwd: pkg_dir) rescue ""
          schemes = list_output.split("\n").drop_while { |l| !l.match?(/Schemes:/) }
                                 .drop(1)
                                 .map(&:strip)
                                 .reject(&:empty?)
          schemes.find { |s| s.casecmp(name).zero? } || schemes.first
        end
      end
    end
  end
end
