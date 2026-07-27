# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "digest"
require "json"
require "set"

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
          shim_targets = find_private_clang_shims(module_name, name, pkg_dir)

          buildable = Buildable.new(
            name: name,
            module_name: module_name,
            pkg_dir: pkg_dir,
            library_evolution: library_evolution,
            scheme: scheme,
          )

          tmpdir = Dir.mktmpdir
          framework_paths = []
          shim_framework_paths = Hash.new { |h, k| h[k] = [] }

          destinations.each do |dest_key|
            Core::UI.info "  Building #{name} for #{dest_key}..."
            dd = derived_data_dir_for(pkg_dir, dest_key)
            begin
              artifacts = buildable.build_for_destination(dest_key, derived_data_path: dd)
            rescue => e
              Core::UI.warn "#{dest_key} build failed: #{e.message}"
              next
            end
            next unless artifacts[:object_file] || artifacts[:framework]

            fw_subdir = File.join(tmpdir, dest_key)
            FileUtils.mkdir_p(fw_subdir)
            fw_dir = artifacts[:framework] ? buildable.use_existing_framework(artifacts, fw_subdir) :
                     buildable.create_framework(artifacts, fw_subdir)
            framework_paths << fw_dir

            shim_targets.each do |shim|
              fw = build_clang_shim_framework(shim: shim, pkg_dir: pkg_dir, derived_data: dd, output_dir: fw_subdir)
              shim_framework_paths[shim["name"]] << fw if fw
            end

            find_framework_companions(artifacts, module_name, out_dir).each do |companion_name, companion_fw|
              shim_framework_paths[companion_name] << companion_fw
            end
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
          write_shim_sidecar(output_path, shim_framework_paths, out_dir)
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
          companion_framework_paths = Hash.new { |h, k| h[k] = [] }

          destinations.each do |dest_key|
            Core::UI.info "  Building #{name} (scheme #{scheme}) for #{dest_key}..."
            dd = derived_data_dir_for(pkg_dir, dest_key)
            begin
              artifacts = buildable.build_for_destination(dest_key, derived_data_path: dd)
            rescue => e
              Core::UI.warn "#{dest_key} build failed: #{e.message}"
              next
            end
            next unless artifacts[:object_file] || artifacts[:framework]

            fw_subdir = File.join(tmpdir, dest_key)
            FileUtils.mkdir_p(fw_subdir)
            fw_dir = artifacts[:framework] ? buildable.use_existing_framework(artifacts, fw_subdir) :
                     buildable.create_framework(artifacts, fw_subdir)
            framework_paths << fw_dir

            # Cross-package public-header dependencies must travel with the
            # cached binary here too -- this fallback path is the one a
            # vendored-.xcodeproj package like DTCoreText actually takes.
            find_framework_companions(artifacts, name, out_dir).each do |companion_name, companion_fw|
              companion_framework_paths[companion_name] << companion_fw
            end
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
          write_shim_sidecar(output_path, companion_framework_paths, out_dir)
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
          candidate = match&.name

          # Field bug: SVGKit's Package.swift declares an SPM product named
          # exactly "SVGKit", but its checkout carries THREE committed
          # .xcodeproj files (the library + two demo apps) whose real
          # schemes are all prefixed differently (SVGKitFramework-iOS/OSX/
          # tvOS) -- no scheme named "SVGKit" exists ANYWHERE. Plain
          # `xcodebuild -list` (used by resolve_scheme_fallback) fails
          # outright in an ambiguous multi-project checkout ("contains N
          # projects ... Specify the project"), so it was never reached to
          # catch this: the `return match.name if match` above always fired
          # first on the exact product-name match, however wrong. Verify the
          # candidate against schemes scraped directly from EACH candidate
          # project (bypassing plain `-list`'s ambiguity failure) only when
          # 2+ .xcodeproj exist; unambiguous checkouts (0 or 1) are
          # completely unaffected -- verified empirically for CryptoSwift/
          # AppAuth-iOS, whose product-name match already resolves to a
          # real scheme on its own.
          if candidate && ambiguous_project_checkout?(pkg_dir)
            real_schemes = schemes_across_projects(pkg_dir)
            return candidate if real_schemes.any? { |s| s.casecmp(candidate).zero? }

            real_match = best_name_match(candidate, real_schemes)
            return real_match if real_match
          end
          return candidate if candidate

          # Fall back to xcodebuild -list heuristic only if `swift package
          # describe` yielded nothing usable (e.g. binary-only/malformed packages).
          resolve_scheme_fallback(name, pkg_dir) || name
        end

        def ambiguous_project_checkout?(pkg_dir)
          Dir.glob(File.join(pkg_dir, "*.xcodeproj")).length >= 2
        end

        def schemes_across_projects(pkg_dir)
          Dir.glob(File.join(pkg_dir, "*.xcodeproj")).flat_map do |proj|
            list_output = Core::Sh.capture_output("xcodebuild -list -project '#{proj}'") rescue ""
            list_output.split("\n").drop_while { |l| !l.match?(/Schemes:/) }
                       .drop(1)
                       .map(&:strip)
                       .reject(&:empty?)
          end.uniq
        end

        # Same fuzzy-match strategy as the product-name lookup above
        # (exact match, then closest substring match), applied against a
        # plain list of real scheme name strings instead of Product objects.
        def best_name_match(name, candidates)
          candidates.find { |s| s.casecmp(name).zero? } ||
            candidates
              .select { |s| s.downcase.include?(name.downcase) || name.downcase.include?(s.downcase) }
              .min_by { |s| (s.length - name.length).abs }
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

        # Some Swift targets privately depend on an internal Clang ("C shim")
        # target that is never declared as its own library product -- e.g.
        # swift-numerics' RealModule depends on `_NumericsShims` purely for
        # libm wrapper functions. Because RealModule's own source imports it
        # with a plain (non-`@_implementationOnly`) `import`, and those
        # functions are used inside `@_transparent` (cross-module-inlinable)
        # bodies -- verified empirically that marking the import
        # `@_implementationOnly` breaks compilation ("cannot be used in a
        # '@_transparent' function because '_NumericsShims' was imported
        # implementation-only") -- swiftc's emitted `.swiftinterface` embeds
        # `import _NumericsShims` as a real, unavoidable public import. A
        # binary-cached consumer of RealModule.xcframework therefore needs
        # `_NumericsShims`'s Clang module resolvable on its own, but
        # spm-cache never builds/bundles it since it isn't a declared
        # library product -- "no such module '_NumericsShims'" when Xcode
        # reparses the interface under library evolution. Detect any such
        # target-level (not product-level) Clang dependency so a companion
        # xcframework can be assembled alongside the main one.
        def find_private_clang_shims(module_name, name, pkg_dir)
          desc = Desc::Description.new(name: name, pkg_dir: pkg_dir)
          desc.fetch
          product_names = desc.products.map(&:name).to_set
          targets_by_name = (desc.raw["targets"] || []).each_with_object({}) { |t, h| h[t["name"]] = t }
          target = targets_by_name[module_name] || targets_by_name[name]
          return [] unless target

          (target["target_dependencies"] || []).filter_map do |dep_name|
            dep = targets_by_name[dep_name]
            next unless dep && dep["module_type"] == "ClangTarget" && !product_names.include?(dep_name)

            dep
          end
        end

        # Cross-PACKAGE counterpart to #find_private_clang_shims. Where that
        # method handles a private Clang target INSIDE the same package, this
        # one handles a dependency living in a wholly separate package whose
        # headers the cached module's own PUBLIC headers `#import` by
        # framework name.
        #
        # Field bug: DTCoreText's public header DTHTMLAttributedStringBuilder.h
        # does `#import <DTFoundation/DTHTMLParser.h>` -- DTFoundation is a
        # separate SPM package (github.com/Cocoanetics/DTFoundation), consumed
        # via `.product(name: "DTFoundation", package: "DTFoundation")`. The
        # generated proxy replaces DTCoreText with a plain binaryTarget and
        # drops that dependency edge entirely (verified: DTFoundation appears
        # nowhere in the generated proxy Package.swift), so once DTCoreText is
        # a cached xcframework nothing supplies DTFoundation's headers and the
        # app build dies in Clang's dependency scanner ("'DTFoundation/
        # DTHTMLParser.h' file not found" -> "could not build module
        # 'DTCoreText'"). Unlike the _NumericsShims case there is nothing to
        # assemble by hand: xcodebuild already emits a complete, real
        # DTFoundation.framework (binary + Headers/ + module.modulemap) right
        # next to DTCoreText.framework in the same Products dir, because
        # building the main scheme necessarily builds its dependency graph.
        # Pick those siblings up and let the existing companion-shim plumbing
        # (#write_shim_sidecar -> <module>.xcframework.shims.json ->
        # BinariesCache.shims -> extra binaryTarget in the SAME .library
        # product) carry them alongside the main binary.
        #
        # Module names this framework's PUBLIC surface names -- either an ObjC
        # public header's angle-bracket import (`#import <DTFoundation/X.h>`)
        # or a Swift `.swiftinterface` import line
        # (`import InternalCollectionsUtilities`). Both forms make the named
        # module part of the consumer-visible contract, so it must resolve
        # when a consumer compiles against the cached binary. A dependency
        # used only from implementation files appears in neither and needs no
        # companion -- its symbols are already linked into the main binary.
        def referenced_module_names(main_framework)
          names = Set.new

          Dir.glob(File.join(main_framework, "Headers", "**", "*.h")).each do |header|
            content = begin
              File.read(header)
            rescue StandardError
              ""
            end
            content.scan(%r{#\s*(?:import|include)\s*<([A-Za-z0-9_]+)/}) { |m| names << m[0] }
          end

          Dir.glob(File.join(main_framework, "Modules", "*.swiftmodule", "*.swiftinterface")).each do |interface|
            content = begin
              File.read(interface)
            rescue StandardError
              ""
            end
            content.scan(/^\s*import\s+([A-Za-z0-9_]+)\s*$/) { |m| names << m[0] }
          end

          names
        end

        # Deliberately narrow, to avoid bundling a copy of something the app
        # already gets by another route:
        #   * only siblings actually named in a PUBLIC header's angle-bracket
        #     import are taken -- a dependency used solely from .m
        #     implementation files needs no headers at consumer-compile time
        #     (its symbols are already linked into the main binary), so
        #     bundling it would be pure duplication;
        #   * anything independently cached in `out_dir` is skipped, since the
        #     proxy already vends that as its own product and a second copy
        #     inside this one would collide (the same duplicate-GUID/duplicate
        #     -symbol family of failure documented throughout spm-cache.yml).
        def find_framework_companions(artifacts, module_name, out_dir)
          products_dir = Dir.glob(File.join(artifacts[:derived_data].to_s, "Build", "Products", "*"))
                            .find { |d| File.directory?(d) }
          return {} unless products_dir

          main_framework = File.join(products_dir, "#{module_name}.framework")
          referenced = referenced_module_names(main_framework)
          return {} if referenced.empty?

          Dir.glob(File.join(products_dir, "*.framework")).each_with_object({}) do |fw, acc|
            fw_name = File.basename(fw, ".framework")
            next if fw_name == module_name
            next unless referenced.include?(fw_name)
            next if File.exist?(File.join(out_dir, "#{fw_name}.xcframework"))

            acc[fw_name] = fw
          end
        end

        # Assembles a companion `.framework` slice for a private Clang shim
        # target, reusing the `.o` that xcodebuild already produced as a
        # side effect of building the main target in the SAME derived_data
        # tree (no extra build invocation needed -- confirmed empirically
        # that `_NumericsShims.o` sits right there under
        # `Products/<config>/_NumericsShims.o` once `RealModule` finishes
        # building, same layout `find_object_file` already globs). Headers
        # come from the target's own `include/` dir (SwiftPM's default
        # public-headers convention for a Clang target with no explicit
        # `publicHeadersPath`). The framework module is declared as
        # `framework module` under an umbrella header that re-exports every
        # real header -- verified empirically (standalone swiftc repro,
        # outside spm-cache) that this is what makes Clang's `-F`
        # framework-module search resolve `import _NumericsShims` when the
        # resulting framework sits alongside RealModule.framework on the
        # same search path; a plain `module` declaration embedded inside
        # RealModule.framework's OWN Modules/ dir does NOT get found, and
        # neither does re-using the real (non-framework) module.modulemap
        # from the checkout verbatim.
        def build_clang_shim_framework(shim:, pkg_dir:, derived_data:, output_dir:)
          shim_name = shim["name"]
          shim_buildable = Buildable.new(name: shim_name, module_name: shim_name, pkg_dir: pkg_dir)
          object_file = shim_buildable.find_object_file(derived_data)
          return nil unless object_file && File.exist?(object_file)

          header_dir = File.join(pkg_dir, shim["path"], "include")
          headers = Dir.glob(File.join(header_dir, "*.h"))
          return nil if headers.empty?

          fw_dir = File.join(output_dir, "#{shim_name}-shim", "#{shim_name}.framework")
          FileUtils.mkdir_p(fw_dir)

          Core::Sh.run("libtool -static -o '#{File.join(fw_dir, shim_name)}' '#{object_file}'")

          headers_dir = File.join(fw_dir, "Headers")
          FileUtils.mkdir_p(headers_dir)
          headers.each { |h| FileUtils.cp(h, File.join(headers_dir, File.basename(h))) }

          umbrella_name = "#{shim_name}-Umbrella.h"
          File.write(File.join(headers_dir, umbrella_name),
                     headers.map { |h| "#import \"#{File.basename(h)}\"" }.join("\n") + "\n")

          modules_dir = File.join(fw_dir, "Modules")
          FileUtils.mkdir_p(modules_dir)
          File.write(File.join(modules_dir, "module.modulemap"), <<~MODULEMAP)
            framework module #{shim_name} {
              umbrella header "#{umbrella_name}"
              export *
            }
          MODULEMAP

          File.write(File.join(fw_dir, "Info.plist"), <<~PLIST)
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
            <key>CFBundleExecutable</key><string>#{shim_name}</string>
            <key>CFBundleIdentifier</key><string>com.spm-cache.#{shim_name.downcase}</string>
            <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
            <key>CFBundleName</key><string>#{shim_name}</string>
            <key>CFBundlePackageType</key><string>FMWK</string>
            <key>CFBundleShortVersionString</key><string>1.0</string>
            <key>CFBundleVersion</key><string>1</string>
            </dict>
            </plist>
          PLIST

          fw_dir
        end

        # Builds one companion `<ShimName>.xcframework` per detected shim
        # (skipping any that never produced a slice) alongside the main
        # xcframework in `out_dir`, and records their names in a
        # `<name>.xcframework.shims.json` sidecar so the proxy generator
        # knows to wire each one in as an extra `.binaryTarget` combined
        # into the SAME `.library` product as the main binary.
        def write_shim_sidecar(output_path, shim_framework_paths, out_dir)
          built_shim_names = shim_framework_paths.filter_map do |shim_name, paths|
            next nil if paths.empty?

            shim_output = File.join(out_dir, "#{shim_name}.xcframework")
            FileUtils.rm_rf(shim_output)
            XCFramework::XCFramework.new(name: shim_name, framework_paths: paths, output_path: shim_output).build
            shim_name
          end
          return if built_shim_names.empty?

          File.write("#{output_path}.shims.json", JSON.generate(built_shim_names))
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
