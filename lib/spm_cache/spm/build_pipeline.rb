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
          header_paths = resolve_public_headers(module_name, name, pkg_dir)

          buildable = Buildable.new(
            name: name,
            module_name: module_name,
            pkg_dir: pkg_dir,
            library_evolution: library_evolution,
            scheme: scheme,
            header_paths: header_paths,
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
            fw_dir = rename_framework_to_product(fw_dir, module_name, name)
            framework_paths << fw_dir

            shim_targets.each do |shim|
              fw = build_clang_shim_framework(shim: shim, pkg_dir: pkg_dir, derived_data: dd, output_dir: fw_subdir)
              shim_framework_paths[shim["name"]] << fw if fw
            end

            find_framework_companions(artifacts, module_name, out_dir, fw_subdir: fw_subdir, pkg_dir: pkg_dir).each do |companion_name, companion_fw|
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
          header_paths = resolve_public_headers(name, name, pkg_dir)

          buildable = Buildable.new(
            name: name,
            module_name: name,
            pkg_dir: pkg_dir,
            library_evolution: library_evolution,
            scheme: scheme,
            header_paths: header_paths,
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
            find_framework_companions(artifacts, name, out_dir, fw_subdir: fw_subdir, pkg_dir: pkg_dir).each do |companion_name, companion_fw|
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

        # Public headers for an ObjC (ClangTarget) product, so create_framework
        # can emit a real module. Returns [] for Swift targets, which need no
        # Headers/ or modulemap.
        def resolve_public_headers(module_name, name, pkg_dir)
          desc = Desc::Description.new(name: name, pkg_dir: pkg_dir)
          desc.fetch
          targets = desc.raw["targets"] || []
          target = targets.find { |t| t["name"] == module_name } || targets.find { |t| t["name"] == name }
          return [] unless target && target["module_type"] == "ClangTarget"

          Desc::Target.new(raw: target, pkg_dir: pkg_dir).header_paths
        rescue StandardError
          []
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
        # Accepts either a framework path or a products_dir/module_name pair
        # to support both framework-wrapped and bare .swiftmodule cases.
        def referenced_module_names(main_framework, products_dir = nil, module_name = nil)
          names = Set.new

          # ObjC header scanning (framework-wrapped case)
          Dir.glob(File.join(main_framework, "Headers", "**", "*.h")).each do |header|
            content = begin
              File.read(header)
            rescue StandardError
              ""
            end
            content.scan(%r{#\s*(?:import|include)\s*<([A-Za-z0-9_]+)/}) { |m| names << m[0] }
          end

          # Swift interface scanning: framework-wrapped case
          Dir.glob(File.join(main_framework, "Modules", "*.swiftmodule", "*.swiftinterface")).each do |interface|
            content = begin
              File.read(interface)
            rescue StandardError
              ""
            end
            # Field bug: an umbrella product (e.g. Collections, re-exporting
            # BitCollections/DequeModule/OrderedCollections/...) writes
            # `@_exported import X` rather than a plain `import X` -- the
            # unqualified anchor missed it entirely, so Collections never
            # detected any of its companions as referenced at all.
            content.scan(/^\s*(?:@_exported\s+)?import\s+([A-Za-z0-9_]+)\s*$/) { |m| names << m[0] }
          end

          # Swift interface scanning: bare .swiftmodule case (SPM pure-Swift libs)
          if products_dir && module_name
            Dir.glob(File.join(products_dir, "#{module_name}.swiftmodule", "*.swiftinterface")).each do |interface|
              content = begin
                File.read(interface)
              rescue StandardError
                ""
              end
              # Field bug: an umbrella product (e.g. Collections, re-exporting
            # BitCollections/DequeModule/OrderedCollections/...) writes
            # `@_exported import X` rather than a plain `import X` -- the
            # unqualified anchor missed it entirely, so Collections never
            # detected any of its companions as referenced at all.
            content.scan(/^\s*(?:@_exported\s+)?import\s+([A-Za-z0-9_]+)\s*$/) { |m| names << m[0] }
            end
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
        # Field bug: FirebaseAnalytics' product wraps a target literally named
        # FirebaseAnalyticsTarget, and Xcode stamps every artifact with the
        # TARGET name -- so the cached xcframework held
        # FirebaseAnalyticsTarget.framework and was importable only under a
        # name no consumer writes.
        #
        # Renaming after the fact rather than forcing PRODUCT_MODULE_NAME on
        # the xcodebuild invocation: that override applies to every target in
        # the invocation, and on a multi-target graph several targets then
        # raced to emit the same module ("Multiple commands produce
        # ... .swiftmodule"). Verified failure on Zendesk; do not reintroduce.
        def rename_framework_to_product(fw_dir, module_name, product_name)
          return fw_dir if module_name == product_name

          new_dir = File.join(File.dirname(fw_dir), "#{product_name}.framework")
          FileUtils.rm_rf(new_dir)
          FileUtils.mv(fw_dir, new_dir)

          old_binary = File.join(new_dir, module_name)
          FileUtils.mv(old_binary, File.join(new_dir, product_name)) if File.exist?(old_binary)

          old_swiftmodule = File.join(new_dir, "Modules", "#{module_name}.swiftmodule")
          if File.exist?(old_swiftmodule)
            FileUtils.mv(old_swiftmodule, File.join(new_dir, "Modules", "#{product_name}.swiftmodule"))
          end

          patch_info_plist(new_dir, module_name, product_name)
          rename_objc_module(new_dir, module_name, product_name)

          new_dir
        end

        # Field bug, confirmed live and blocking the entire app build: the renames
        # above never touched the framework's own Info.plist, so CFBundleExecutable
        # and CFBundleName stayed as the pre-rename target name while the binary on
        # disk was renamed to the product name. Xcode's build-plan resolution reads
        # CFBundleExecutable to find the bundle's executable, doesn't find a file by
        # that name, and aborts the whole build before any compilation starts
        # ("could not determine executable path for bundle"). Handles both
        # spm-cache's own compact single-line template (#framework_info_plist) and
        # a real xcodebuild-produced multi-line Info.plist (the use_existing_framework
        # path) since the key and its value can be separated by a newline there.
        def patch_info_plist(fw_dir, module_name, product_name)
          plist_path = File.join(fw_dir, "Info.plist")
          return unless File.exist?(plist_path)

          content = File.read(plist_path)
          %w[CFBundleExecutable CFBundleName].each do |key|
            content = content.sub(
              /(<key>#{key}<\/key>\s*<string>)#{Regexp.escape(module_name)}(<\/string>)/,
              "\\1#{product_name}\\2",
            )
          end
          File.write(plist_path, content)
        end

        # Field gap, same function: create_objc_module (build.rb) writes
        # Modules/module.modulemap declaring `framework module <module_name>` with
        # `umbrella header "<module_name>.h"`, and the actual file is
        # Headers/<module_name>.h. The renames above never touched the modulemap
        # content or the umbrella header filename -- latent today (no current
        # product with product != target also has public headers), but a real gap
        # in the same function. No-op when no ObjC module was assembled (no
        # Headers/<module_name>.h alongside the modulemap), which covers every
        # Swift-only rename exercised so far.
        def rename_objc_module(fw_dir, module_name, product_name)
          modulemap_path = File.join(fw_dir, "Modules", "module.modulemap")
          old_header = File.join(fw_dir, "Headers", "#{module_name}.h")
          return unless File.exist?(modulemap_path) && File.exist?(old_header)

          FileUtils.mv(old_header, File.join(fw_dir, "Headers", "#{product_name}.h"))

          content = File.read(modulemap_path)
          content = content.sub("framework module #{module_name} {", "framework module #{product_name} {")
          content = content.sub(%(umbrella header "#{module_name}.h"), %(umbrella header "#{product_name}.h"))
          File.write(modulemap_path, content)
        end

        def find_framework_companions(artifacts, module_name, out_dir, fw_subdir: nil, pkg_dir: nil)
          products_dir = Dir.glob(File.join(artifacts[:derived_data].to_s, "Build", "Products", "*"))
                            .find { |d| File.directory?(d) }
          return {} unless products_dir

          # Detect main module layout: framework-wrapped (DTFoundation case) or
          # bare .swiftmodule (SPM pure-Swift lib case). Both must be scanned
          # for referenced modules.
          main_framework = File.join(products_dir, "#{module_name}.framework")
          if File.directory?(main_framework)
            # Framework-wrapped case: scan headers and framework's Modules/*.swiftmodule
            referenced = referenced_module_names(main_framework)
          else
            # Bare case: scan only the bare .swiftmodule dir
            referenced = referenced_module_names(main_framework, products_dir, module_name)
          end
          return {} if referenced.empty?

          # Companion collection: framework-wrapped first (existing behavior).
          #
          # Field bug (Class D sibling-skip): an already-cached companion used
          # to be skipped from this hash entirely -- avoiding a wasteful
          # rebuild (see #write_shim_sidecar, which OVERWRITES whatever
          # .xcframework already exists at that name), but that also meant
          # the companion never got wired into a LATER sibling product's own
          # `.library` target list, even though the companion binary is
          # genuinely correct and already cached. Record it with a :cached
          # marker instead of a real framework path, so the caller still
          # notes the name for THIS product's own sidecar while
          # #write_shim_sidecar knows not to rebuild it.
          companions = Dir.glob(File.join(products_dir, "*.framework")).each_with_object({}) do |fw, acc|
            fw_name = File.basename(fw, ".framework")
            next if fw_name == module_name
            next unless referenced.include?(fw_name)

            acc[fw_name] = File.exist?(File.join(out_dir, "#{fw_name}.xcframework")) ? :cached : fw
          end

          # Also check for bare companion modules and synthesize frameworks
          # (SPM pure-Swift library internal dependencies).
          referenced.each do |companion_name|
            # Skip if already found as a framework (real path or :cached above)
            next if companions.key?(companion_name)

            if File.exist?(File.join(out_dir, "#{companion_name}.xcframework"))
              companions[companion_name] = :cached
              next
            end

            # Bare companion shapes needing synthesis: a bare Swift module
            # (.swiftmodule dir, no .framework -- the original SPM
            # pure-Swift-lib case) or a bare Clang/ObjC internal target (no
            # .swiftmodule either, just a raw .o plus real public headers
            # via Package.swift's `publicHeadersPath:` -- e.g. Firebase's
            # FirebaseAuthInternal/FirebaseCoreExtension/etc, pure internal
            # dependencies never vended as their own library product).
            # Neither shape is distinguishable from the referenced name
            # alone, so both are attempted unconditionally here;
            # #build_companion_framework's own #find_object_file check
            # (a cheap glob, no shell-out) is the real gate and returns nil
            # immediately for a referenced name with no object file at all
            # (e.g. plain system frameworks like Foundation/Swift), so this
            # costs nothing for those.
            companion_scratch = fw_subdir ? File.join(fw_subdir, "#{companion_name}-tmp") : File.join(out_dir, "#{companion_name}-tmp")
            FileUtils.mkdir_p(companion_scratch)
            fw = build_companion_framework(
              module_name: companion_name,
              pkg_dir: pkg_dir,
              derived_data: artifacts[:derived_data],
              output_dir: companion_scratch,
            )
            companions[companion_name] = fw if fw
          end

          companions
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

        # Synthesizes a companion framework for a bare module with no existing
        # .framework wrapper -- either a bare Swift module (.swiftmodule dir,
        # SPM pure-Swift library internal dependency, e.g.
        # InternalCollectionsUtilities) or a bare Clang/ObjC internal target
        # (no .swiftmodule either, just a raw .o plus real public headers
        # declared via Package.swift's `publicHeadersPath:`, e.g. Firebase's
        # FirebaseAuthInternal/FirebaseCoreExtension/FirebaseAppCheckInterop/
        # etc). Reuses Buildable to collect artifacts and #create_framework
        # to assemble the binary, so the result has the same layout and
        # metadata as the main module's framework -- #create_framework's own
        # #create_objc_module already emits Headers/ + module.modulemap
        # whenever header_paths is non-empty, and is a correct no-op when
        # empty, so passing #resolve_public_headers's result here is all
        # that's needed to make the Clang/ObjC shape work; no separate
        # synthesis path required.
        #
        # Gated on #find_object_file (a cheap glob, no shell-out) BEFORE
        # calling #resolve_public_headers (which shells out to `swift
        # package describe`) -- #find_framework_companions calls this for
        # every referenced name with no existing .framework/.xcframework,
        # including plain system frameworks (Foundation, Swift, ...) that
        # will never have an object file here at all, so the ordering avoids
        # a wasted `swift package describe` per such name.
        def build_companion_framework(module_name:, pkg_dir:, derived_data:, output_dir:)
          probe = Buildable.new(name: module_name, module_name: module_name, pkg_dir: pkg_dir)
          obj = probe.find_object_file(derived_data)
          return nil unless obj && File.exist?(obj)

          companion = Buildable.new(
            name: module_name,
            module_name: module_name,
            pkg_dir: pkg_dir,
            header_paths: resolve_public_headers(module_name, module_name, pkg_dir),
          )
          artifacts = {
            derived_data: derived_data,
            object_file: obj,
            object_files: companion.find_object_files(derived_data, obj),
            swiftmodule: companion.find_file(derived_data, "#{module_name}.swiftmodule"),
            swiftdoc: companion.find_file(derived_data, "#{module_name}.swiftdoc"),
            swiftsourceinfo: companion.find_file(derived_data, "#{module_name}.swiftsourceinfo"),
            swiftinterface: companion.find_file(derived_data, "#{module_name}.swiftinterface"),
          }
          companion.create_framework(artifacts, output_dir)
        end

        # Builds one companion `<ShimName>.xcframework` per detected shim
        # (skipping any that never produced a slice) alongside the main
        # xcframework in `out_dir`, and records their names in a
        # `<name>.xcframework.shims.json` sidecar so the proxy generator
        # knows to wire each one in as an extra `.binaryTarget` combined
        # into the SAME `.library` product as the main binary.
        #
        # A companion whose paths are all the :cached marker (see
        # #find_framework_companions) is already correct on disk from a
        # previously-processed sibling product -- its name still needs to
        # land in THIS product's sidecar so the proxy wires it in here too,
        # but it must not be rebuilt: XCFramework.build would OVERWRITE the
        # existing, already-correct .xcframework for no benefit.
        def write_shim_sidecar(output_path, shim_framework_paths, out_dir)
          built_shim_names = shim_framework_paths.filter_map do |shim_name, paths|
            next nil if paths.empty?

            real_paths = paths.reject { |p| p == :cached }
            if real_paths.empty?
              shim_name
            else
              shim_output = File.join(out_dir, "#{shim_name}.xcframework")
              FileUtils.rm_rf(shim_output)
              XCFramework::XCFramework.new(name: shim_name, framework_paths: real_paths, output_path: shim_output).build
              shim_name
            end
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
