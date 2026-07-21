# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "digest"

require "spm_cache/core/log"
require "spm_cache/core/sh"
require "spm_cache/core/config"
require "spm_cache/spm/build"
require "spm_cache/spm/desc/desc"
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

          scheme = resolve_scheme(name, pkg_dir)
          module_name = resolve_module_name(name, pkg_dir)

          buildable = Buildable.new(
            name: name,
            module_name: module_name,
            pkg_dir: pkg_dir,
            library_evolution: library_evolution,
            scheme: scheme,
          )

          tmpdir = Dir.mktmpdir
          framework_paths = []

          destinations.each do |dest_key|
            Core::UI.info "  Building #{name} for #{dest_key}..."
            dd = derived_data_dir_for(pkg_dir, dest_key)
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
            if alt && alt != scheme
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
            dd = derived_data_dir_for(pkg_dir, dest_key)
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

        # Resolve the Xcode scheme to build for `name` (package identity) BEFORE
        # attempting any build. SPM-native package schemes in Xcode are
        # auto-generated 1:1 from *product* names (not target names, not the
        # package identity), so `swift package describe` product metadata is
        # the authoritative source here — no wasted build attempt needed just
        # to discover the right scheme.
        def resolve_scheme(name, pkg_dir)
          desc = Desc::Description.new(name: name, pkg_dir: pkg_dir)
          desc.fetch
          library_products = desc.products.select { |p| p.type == "library" }
          match = library_products.find { |p| p.name.casecmp(name).zero? } ||
                  library_products
                    .select { |p| p.name.downcase.include?(name.downcase) || name.downcase.include?(p.name.downcase) }
                    .min_by { |p| (p.name.length - name.length).abs } ||
                  library_products.first
          return match.name if match

          # Fall back to xcodebuild -list heuristic only if `swift package
          # describe` yielded nothing usable (e.g. binary-only/malformed packages).
          resolve_scheme_fallback(name, pkg_dir) || name
        end

        # Resolve the *build-product's own target name* to search for when
        # locating the linked `.o` file after a successful build. For most
        # packages this equals the product name (`resolve_scheme`'s `name`),
        # but some multi-target product wrappers declare a product whose sole
        # target is suffixed differently -- e.g. firebase-ios-sdk's Analytics
        # variant family declares product `FirebaseAnalyticsWithoutAdIdSupport`
        # backed by a single target named
        # `FirebaseAnalyticsWithoutAdIdSupportTarget` (confirmed via `swift
        # package describe`; same shape for `FirebaseAnalytics` and
        # `FirebaseAnalyticsOnDeviceConversion` -- `<Product>Target`). Xcode
        # links the object file under the TARGET's name, not the product's, so
        # `find_object_file`'s exact-name glob silently finds nothing and the
        # build is reported as failed even though it actually succeeded.
        # Falls back to `name` itself when there's exactly one target sharing
        # the product's own name (the common case, e.g. FirebaseCore) or when
        # product metadata isn't available at all.
        def resolve_module_name(name, pkg_dir)
          desc = Desc::Description.new(name: name, pkg_dir: pkg_dir)
          desc.fetch
          product = desc.products.find { |p| p.name == name }
          target_names = product&.target_names || []
          return name if target_names.empty? || target_names.include?(name)

          target_names.first
        end

        def resolve_scheme_fallback(name, pkg_dir)
          list_output = Core::Sh.capture_output("xcodebuild -list", cwd: pkg_dir) rescue ""
          schemes = list_output.split("\n").drop_while { |l| !l.match?(/Schemes:/) }
                                 .drop(1)
                                 .map(&:strip)
                                 .reject(&:empty?)
          schemes.find { |s| s.casecmp(name).zero? } || schemes.first
        end

        # DerivedData MUST live outside `pkg_dir` (a SwiftPM checkout under
        # umbrella/.build/checkouts/<pkg>) -- nesting it inside conflicts with
        # SwiftPM's own managed state for some package/target topologies.
        # Field bug: reproduced on firebase-ios-sdk's FirebaseAnalytics variant
        # targets (FirebaseAnalyticsWithoutAdIdSupport, OnDeviceConversion, and
        # base FirebaseAnalytics) with a bare `xcodebuild` invocation -- no Ruby
        # involved. Identical command succeeds with `-derivedDataPath` outside
        # the checkout (e.g. /tmp); fails with `-derivedDataPath
        # ./DerivedData_iphonesimulator` (relative to the checkout) every time:
        # dozens of `could not delete old scheme: ... process disallows saving`
        # warnings followed by `does not contain a scheme named "<name>"`. Other
        # Firebase products (FirebaseCore, FirebaseAuth, FirebaseInstallations,
        # etc.) tolerated the nested path fine, so this only reproduces for
        # certain topologies -- moving DerivedData out entirely sidesteps it
        # rather than special-casing the affected products.
        # Keyed by pkg_dir's absolute path (not a fresh Dir.mktmpdir) so it
        # stays stable and is reused across different targets built from the
        # same checkout, preserving incremental-build speed.
        def derived_data_dir_for(pkg_dir, dest_key)
          key = Digest::SHA256.hexdigest(File.expand_path(pkg_dir))[0, 16]
          File.join(Core::Config::CACHE_DIR, "derived_data", "#{File.basename(pkg_dir)}-#{key}",
                    "DerivedData_#{dest_key}")
        end
      end
    end
  end
end
