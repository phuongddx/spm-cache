# Implementation Plan: spm-cache

> **Status:** pending
> **Brainstorm:** [docs/brainstorm-spm-cache.md](brainstorm-spm-cache.md)
> **Objective:** Build spm-cache, a Ruby gem + Swift proxy tool that caches SPM dependencies as xcframeworks

---

## Phase 1: Core Foundation (Ruby Gem Scaffold + Core Utilities)

**Goal:** Create the gem skeleton, CLI framework, and all foundational utility modules.

### 1.1 Gem scaffold
- [ ] Create `spm_cache.gemspec` with dependencies: claide, xcodeproj (>= 1.26.0), parallel, tty-cursor, tty-screen
- [ ] Create `Gemfile` with dev deps: bundler, rspec, rubocop
- [ ] Create `VERSION` file (0.1.0)
- [ ] Create `bin/spm-cache` executable entry point
- [ ] Create `lib/spm_cache.rb` module root with ROOT/LIBEXEC constants
- [ ] Create `lib/spm_cache/main.rb` with auto-require + pathname

### 1.2 CLAide CLI framework
- [ ] Create `lib/spm_cache/command.rb` - CLAide::Command subclass, abstract, default subcommand "use", install/build options parsing
- [ ] Create `lib/spm_cache/command/base.rb` - Command::Options constants (SDK, CONFIG, LOG_DIR, MERGE_SLICES, LIBRARY_EVOLUTION)

### 1.3 Core utilities
- [ ] Create `lib/spm_cache/core.rb` auto-require
- [ ] Create `lib/spm_cache/core/error.rb` - BaseError, GeneralError
- [ ] Create `lib/spm_cache/core/log.rb` - UI module with Mixin (section, message, info, warn, error, error!)
- [ ] Create `lib/spm_cache/core/sh.rb` - Sh.run (Open3 popen3), capture_output, handles live_log
- [ ] Create `lib/spm_cache/core/git.rb` - Git wrapper (init, checkout, fetch, push, clean, add, commit, remote, etc.)
- [ ] Create `lib/spm_cache/core/live_log.rb` - LiveLog (tty-cursor based terminal output, sticky lines, capture)
- [ ] Create `lib/spm_cache/core/parallel.rb` - Array#parallel_map extension
- [ ] Create `lib/spm_cache/core/hash.rb` - Hash#deep_merge with uniq_block and sort_block
- [ ] Create `lib/spm_cache/core/system.rb` - String#c99extidentifier, File.which, Dir.prepare/create_tmpdir/git?, Pathname#symlink_to/copy/checksum

### 1.4 Syntax (serialization layer)
- [ ] Create `lib/spm_cache/core/syntax/hash.rb` - HashRepresentable base (path, raw, load, save, [], []=)
- [ ] Create `lib/spm_cache/core/syntax/json.rb` - JSONRepresentable
- [ ] Create `lib/spm_cache/core/syntax/yml.rb` - YAMLRepresentable
- [ ] Create `lib/spm_cache/core/syntax/plist.rb` - PlistRepresentable (CFPropertyList)

### 1.5 Config + Lockfile
- [ ] Create `lib/spm_cache/core/config.rb` - Config singleton (Mixin, sandbox paths, remote config, ignore lists)
- [ ] Create `lib/spm_cache/core/lockfile.rb` - Lockfile (JSONRepresentable, Pkg class, deep_merge, verify!)

### 1.6 Cacheable + Template
- [ ] Create `lib/spm_cache/core/cacheable.rb` - Cacheable mixin (prepend-module memoization)
- [ ] Create `lib/spm_cache/utils/template.rb` - Template (ERB rendering from assets/templates/)

### 1.7 Verification
- [ ] `bundle install` succeeds
- [ ] `bundle exec spm-cache --help` shows help (even if subcommands are stubs)
- [ ] Config loads from spm-cache.yml, Lockfile parses JSON

---

## Phase 2: SPM Build Pipeline (Source -> xcframework)

**Goal:** Build the complete pipeline that compiles a Swift package target into an xcframework.

### 2.1 Swift SDK support
- [ ] Create `lib/spm_cache/swift/sdk.rb` - Swift::Sdk (name, arch, vendor, platform, triple, sdk_path, swiftc_args, simulator?)
- [ ] Create `lib/spm_cache/swift/swiftc.rb` - Swift::Swiftc.version detection

### 2.2 Buildable base
- [ ] Create `lib/spm_cache/spm/build.rb` - SPM::Buildable (name, module_name, pkg_dir, sdks, config, swift_build with library evolution flags, sh wrapper)

### 2.3 Framework slice creation
- [ ] Create `lib/spm_cache/spm/xcframework/slice.rb` - FrameworkSlice (swift_build -> create_framework)
  - create_framework_binary (libtool -static from .o files)
  - create_info_plist (template)
  - create_headers (Swift + ObjC, umbrella header, angle-bracket import correction)
  - create_modules (modulemap template, swiftmodules, swiftinterfaces copy)
  - copy_resource_bundles (with resource symlink resolution)
  - override_resource_bundle_accessor (Swift + ObjC templates compiled via swiftc/clang)

### 2.4 XCFramework assembly
- [ ] Create `lib/spm_cache/spm/xcframework/xcframework.rb` - XCFramework (slices, build with merge_slices support, create_xcframework via xcodebuild)

### 2.5 XCFramework metadata
- [ ] Create `lib/spm_cache/spm/xcframework/metadata.rb` - Metadata (PlistRepresentable, available_libraries, triples)

### 2.6 Macro builder
- [ ] Create `lib/spm_cache/spm/macro.rb` - SPM::Macro (build associated .target to get tool binary, copy -tool binary)

### 2.7 SPM Package base + Description parsing
- [ ] Create `lib/spm_cache/spm/desc/base.rb` - BaseObject (JSONRepresentable, name, full_name, fetch, pkg_desc_of)
- [ ] Create `lib/spm_cache/spm/desc/desc.rb` - Description (platforms, dependencies, products, targets, traverse graph, combine_descs)
- [ ] Create `lib/spm_cache/spm/desc/product.rb` - Product (target_names, targets, recursive_targets)
- [ ] Create `lib/spm_cache/spm/desc/target.rb` - Target (type, downcast, header_paths, resource_paths, recursive_targets, direct_dependencies)
- [ ] Create `lib/spm_cache/spm/desc/target/binary.rb` - BinaryTarget
- [ ] Create `lib/spm_cache/spm/desc/target/macro.rb` - MacroTarget
- [ ] Create `lib/spm_cache/spm/desc/dep.rb` - Dependency (local?, slug, path, pkg_desc)

### 2.8 SPM Package (build orchestration)
- [ ] Create `lib/spm_cache/spm/pkg/base.rb` - SPM::Package (root_dir, build, build_target, resolve, pkg_desc, get_target, validate!)
- [ ] Create `lib/spm_cache/spm.rb` auto-require
- [ ] Create `lib/spm_cache/spm/mixin.rb` - PkgMixin (umbrella_pkg, proxy_pkg accessors)

### 2.9 Templates for build pipeline
- [ ] Create `lib/spm_cache/assets/templates/framework.info.plist.template`
- [ ] Create `lib/spm_cache/assets/templates/framework.modulemap.template`
- [ ] Create `lib/spm_cache/assets/templates/resource_bundle_accessor.swift.template`
- [ ] Create `lib/spm_cache/assets/templates/resource_bundle_accessor.m.template`

### 2.10 Verification
- [ ] `spm-cache pkg build Alamofire --sdk=iphonesimulator` produces a valid .xcframework
- [ ] Framework contains binary, Info.plist, Headers/, Modules/, Resources/ (if applicable)
- [ ] Macro build produces a .macro binary

---

## Phase 3: Proxy Architecture (Swift Tool + Ruby Integration)

**Goal:** Build the Swift proxy tool and integrate it with the Ruby gem.

### 3.1 Swift proxy tool scaffold
- [ ] Create `tools/spm-cache-proxy/Package.swift` (depends on swift-package-manager release/6.2, swift-argument-parser, Rainbow)
- [ ] Create `Sources/CLI/CLI.swift` - AsyncParsableCommand with subcommands: GenUmbrella, GenProxy, Resolve
- [ ] Create `Sources/CLI/Base.swift` - CommandRunning protocol, projectRootDir, defaultSandboxDir

### 3.2 Swift Core: Lockfile + Env + Cache
- [ ] Create `Sources/Core/Lockfile.swift` - Lockfile struct (packages, dependencies, platforms)
- [ ] Create `Sources/Core/Env.swift` - Env (isRunningInsideXcode)
- [ ] Create `Sources/Core/Cache.swift` - BinariesCache (dir, update modules/artifacts, hit, binaryPath)

### 3.3 Swift Core: Extensions
- [ ] Create `Sources/Core/Extensions/Core.swift` - AbsolutePath extensions (pwd, recreate, mkdir, symlink, touch, subPaths, exists), URL.subPaths
- [ ] Create `Sources/Core/Extensions/SwiftPM.swift` - Manifest extensions (slug, hasMacro, create, withChanges, write), ModulesGraph extensions (recursiveModulesFromRoot, etc.), ResolvedPackage extensions (localDependency, slug)

### 3.4 Swift Core: Logger
- [ ] Create `Sources/Core/Log/Logger.swift` - Logger (debug/info/warning/error, OSLogHandler, ConsoleLogHandler)
- [ ] Create `Sources/Core/Log/Logger+Live.swift` - LiveLog (cursor control, liveSection, liveOutput)

### 3.5 Swift Core: Generators
- [ ] Create `Sources/Core/Generator/UmbrellaGenerator.swift` - Lockfile -> umbrella Package.swift with {Name}.spm_cache targets
- [ ] Create `Sources/Core/Generator/MetadataGenerator.swift` - Graph -> per-package manifest JSON metadata
- [ ] Create `Sources/Core/Generator/ProxyGenerator.swift` - Graph + cache -> per-dependency proxy packages + root proxy
- [ ] Create `Sources/Core/Generator/GraphGenerator.swift` - Graph -> graph.json (deps, cache status, macros)

### 3.6 Swift Core: Proxy packages
- [ ] Create `Sources/Core/Proxy/ProxyPackageProtocol.swift` - Shared logic (reachableProducts, recursiveDependencies, buildSettings, macroBuildSettings, headerSearchPathSettings)
- [ ] Create `Sources/Core/Proxy/ProxyPackage.swift` - Per-dependency proxy (generate, convert products/targets, symlink sources)
- [ ] Create `Sources/Core/Proxy/RootProxyPackage.swift` - Root proxy (exposeHeaders symlink tree, convert targets)

### 3.7 Swift Core: Resolver
- [ ] Create `Sources/Core/Resolver.swift` - Workspace.loadPackageGraph + MetadataGenerator

### 3.8 Swift CLI subcommands
- [ ] Create `Sources/CLI/GenUmbrella.swift` - gen-umbrella command (lockfile -> umbrella dir)
- [ ] Create `Sources/CLI/GenProxy.swift` - gen-proxy command (umbrella -> proxy dir + binaries dir)
- [ ] Create `Sources/CLI/Resolve.swift` - resolve command (pkg dir -> metadata dir)

### 3.9 Ruby: Proxy package + executable manager
- [ ] Create `lib/spm_cache/spm/pkg/proxy_executable.rb` - Executable (lookup local/download/build_from_source, run commands)
- [ ] Create `lib/spm_cache/spm/pkg/proxy.rb` - SPM::Package::Proxy (prepare: gen-umbrella + resolve + invalidate_cache + gen_proxy, graph accessor)

### 3.10 Ruby: Cachemap
- [ ] Create `lib/spm_cache/cache/cachemap.rb` - Cache::Cachemap (depgraph_data, cache_data, missed?, stats, update_from_graph, print_stats)

### 3.11 Verification
- [ ] Swift tool builds: `cd tools/spm-cache-proxy && swift build -c release`
- [ ] gen-umbrella produces valid umbrella Package.swift from a lockfile
- [ ] resolve produces per-package metadata JSON
- [ ] gen-proxy produces proxy packages with correct binaryTarget/source switching
- [ ] graph.json contains cache status (hit/missed/ignored) and dependency edges

---

## Phase 4: Installer Orchestration

**Goal:** Wire together the complete installation pipeline (use/build/rollback).

### 4.1 Installer base (Template Method)
- [ ] Create `lib/spm_cache/installer.rb` - Installer (perform_install pipeline: verify, recreate_dirs, migrate, sync_lockfile, proxy_pkg.prepare, yield hook, gen_supporting_files, add_refs, inject_xcconfig, gen_cachemap_viz)
- [ ] Create `lib/spm_cache/installer/integration.rb` - IntegrationMixin (includes all integration modules)

### 4.2 Integration mixins
- [ ] Create `lib/spm_cache/installer/integration/build.rb` - BuildIntegrationMixin (targets_to_build from cachemap missed)
- [ ] Create `lib/spm_cache/installer/integration/descs.rb` - DescsIntegrationMixin (xccache_desc, targets_of_products, binary_targets)
- [ ] Create `lib/spm_cache/installer/integration/supporting_files.rb` - SupportingFilesIntegrationMixin (gen_xcconfigs for macro support)
- [ ] Create `lib/spm_cache/installer/integration/viz.rb` - VizIntegrationMixin (gen_cachemap_viz HTML/JS/CSS)

### 4.3 Installer subclasses
- [ ] Create `lib/spm_cache/installer/build.rb` - Installer::Build (perform_install + build + gen_proxy)
- [ ] Create `lib/spm_cache/installer/use.rb` - Installer::Use (replace_binaries_for_project)
- [ ] Create `lib/spm_cache/installer/rollback.rb` - Installer::Rollback (restore packages + product deps, remove proxy)

### 4.4 Cachemap visualization templates
- [ ] Create `lib/spm_cache/assets/templates/cachemap.html.template`
- [ ] Create `lib/spm_cache/assets/templates/cachemap.js.template`
- [ ] Create `lib/spm_cache/assets/templates/cachemap.style.css.template`

### 4.5 Config template
- [ ] Create `lib/spm_cache/assets/templates/spm-cache.yml.template`

### 4.6 Verification
- [ ] Installer::Use runs perform_install end-to-end (with mock proxy)
- [ ] Installer::Build builds missed targets then regenerates proxy
- [ ] Installer::Rollback restores original project state

---

## Phase 5: Project Integration (xcodeproj Extensions)

**Goal:** Extend the xcodeproj gem to manipulate .xcodeproj files for spm-cache integration.

### 5.1 Project extensions
- [ ] Create `lib/spm_cache/xcodeproj.rb` auto-require
- [ ] Create `lib/spm_cache/xcodeproj/project.rb` - Project extensions (display_name, pkgs, xccache_pkg, add_pkg, add_xccache_pkg, remove_pkgs, get_target, get_pkg, xccache_config_group)

### 5.2 Target extensions
- [ ] Create `lib/spm_cache/xcodeproj/target.rb` - PBXNativeTarget extensions (pkg_product_dependencies, add/remove product deps, xccache product dependency)

### 5.3 Package reference extensions
- [ ] Create `lib/spm_cache/xcodeproj/pkg.rb` - PkgRefMixin (id, slug, local?, xccache_pkg?, to_h), XCRemoteSwiftPackageReference, XCLocalSwiftPackageReference extensions

### 5.4 Product dependency extensions
- [ ] Create `lib/spm_cache/xcodeproj/pkg_product_dependency.rb` - XCSwiftPackageProductDependency (full_name, pkg, remove_alongside_related)

### 5.5 Group + Build config extensions
- [ ] Create `lib/spm_cache/xcodeproj/group.rb` - PBXGroup (synced_groups, ensure_synced_group, new_synced_group)
- [ ] Create `lib/spm_cache/xcodeproj/build_configuration.rb` - XCBuildConfiguration (base_configuration_xcconfig, path resolution)
- [ ] Create `lib/spm_cache/xcodeproj/config.rb` - Xcodeproj::Config (path accessor)
- [ ] Create `lib/spm_cache/xcodeproj/file_system_synchronized_root_group.rb` - PBXFileSystemSynchronizedRootGroup (name attribute, display_name)

### 5.6 Verification
- [ ] Opening a test .xcodeproj, adding proxy package ref, saving, reopening - refs preserved
- [ ] Adding/removing product dependencies works correctly
- [ ] xcconfig injection into existing base configurations works
- [ ] Synced groups (local-packages, xcconfigs) created correctly

---

## Phase 6: Storage Backends + Remote Commands

**Goal:** Implement Git and S3 remote cache backends and wire up remote commands.

### 6.1 Storage layer
- [ ] Create `lib/spm_cache/storage.rb` auto-require
- [ ] Create `lib/spm_cache/storage/base.rb` - Storage (no-op base with warnings)
- [ ] Create `lib/spm_cache/storage/git.rb` - GitStorage (pull: fetch+checkout+clean, push: add+commit+push, ensure_remote)
- [ ] Create `lib/spm_cache/storage/s3.rb` - S3Storage (pull/push via aws s3 sync, validate awscli, creds handling)

### 6.2 Remote commands
- [ ] Create `lib/spm_cache/command/remote.rb` - Remote abstract command (create_storage factory from config)
- [ ] Create `lib/spm_cache/command/remote/pull.rb` - Pull (storage.pull)
- [ ] Create `lib/spm_cache/command/remote/push.rb` - Push (storage.push)

### 6.3 Verification
- [ ] `spm-cache remote pull` with git config fetches cache correctly
- [ ] `spm-cache remote push` with git config pushes cache correctly
- [ ] `spm-cache remote pull` with no config shows helpful warning
- [ ] S3 storage validates awscli presence and creds file

---

## Phase 7: Remaining Commands

**Goal:** Implement all remaining CLI commands.

### 7.1 Use command
- [ ] Create `lib/spm_cache/command/use.rb` - Use (default subcommand, runs Installer::Use)

### 7.2 Build command
- [ ] Create `lib/spm_cache/command/build.rb` - Build (accepts TARGET args, runs Installer::Build, --recursive flag)

### 7.3 Off command
- [ ] Create `lib/spm_cache/command/off.rb` - Off (force source mode for specific targets via ignore_list)

### 7.4 Rollback command
- [ ] Create `lib/spm_cache/command/rollback.rb` - Rollback (runs Installer::Rollback)

### 7.5 Cache commands
- [ ] Create `lib/spm_cache/command/cache.rb` - Cache abstract command
- [ ] Create `lib/spm_cache/command/cache/list.rb` - List (list cached packages grouped by target)
- [ ] Create `lib/spm_cache/command/cache/clean.rb` - Clean (remove specific/all cache, --dry flag)

### 7.6 Pkg commands
- [ ] Create `lib/spm_cache/command/pkg.rb` - Pkg abstract command
- [ ] Create `lib/spm_cache/command/pkg/build.rb` - Pkg::Build (build single package, --out, --checksum flags)

### 7.7 Verification
- [ ] `spm-cache` (no args) defaults to `use`
- [ ] `spm-cache build Alamofire --recursive` builds missed recursive targets
- [ ] `spm-cache off DebugKit` forces source mode
- [ ] `spm-cache cache list` shows cached packages
- [ ] `spm-cache cache clean --all` purges cache
- [ ] `spm-cache pkg build Alamofire --out=./out` produces xcframework

---

## Phase 8: Documentation, Examples, and Polish

**Goal:** Complete documentation, examples, and final polish.

### 8.1 Documentation
- [ ] Create `README.md` (overview, installation, getting started, links)
- [ ] Create `docs/README.md` (knowledge base index)
- [ ] Create `docs/how-to-install.md`
- [ ] Create `docs/getting-started.md`
- [ ] Create `docs/overview.md` (cache model, validation, fallback)
- [ ] Create `docs/configuration.md` (all spm-cache.yml options)
- [ ] Create `docs/troubleshooting.md` (unknown product dependencies)
- [ ] Create `docs/features-roadmap.md`
- [ ] Create `docs/under-the-hood/proxy-packages.md`
- [ ] Create `docs/under-the-hood/packaging-as-xcframework.md`
- [ ] Create `docs/under-the-hood/ensuring-bundle-module.md`
- [ ] Create `docs/under-the-hood/macro-as-binary.md`
- [ ] Create `docs/contributing-guidelines.md`

### 8.2 Examples
- [ ] Create `examples/` with test Xcode project (EX.xcodeproj)
- [ ] Create `examples/spm-cache.yml`
- [ ] Create `examples/spm-cache.lock`
- [ ] Create `examples/LocalPackages/` with test packages (core-utils, wizard/macro)
- [ ] Create `examples/Makefile`

### 8.3 Build infrastructure
- [ ] Create `Makefile` (install, format, test, proxy.build targets)
- [ ] Create `.pre-commit-config.yaml` (rubocop)
- [ ] Create `LICENSE.txt` (MIT)
- [ ] Create `.gitignore`

### 8.4 Final verification
- [ ] End-to-end: `spm-cache` in examples project produces proxy, cachemap, lockfile
- [ ] End-to-end: `spm-cache build` + `spm-cache` uses cache correctly
- [ ] End-to-end: `spm-cache rollback` restores project
- [ ] End-to-end: macro package builds and works when cached
- [ ] End-to-end: resource bundle accessible via Bundle.module in cached framework
- [ ] `bundle exec rspec` passes (if tests added)
- [ ] `bundle exec rubocop` passes

---

## Build Order Summary

| Phase | Focus | Depends On | Est. Complexity |
|-------|-------|------------|-----------------|
| 1 | Core Foundation | - | Medium |
| 2 | SPM Build Pipeline | Phase 1 | High |
| 3 | Proxy Architecture (Swift + Ruby) | Phase 1, 2 | High |
| 4 | Installer Orchestration | Phase 1-3 | Medium |
| 5 | Project Integration (xcodeproj) | Phase 1, 4 | Medium |
| 6 | Storage Backends | Phase 1 | Low |
| 7 | Remaining Commands | Phase 1-6 | Low |
| 8 | Documentation + Polish | All | Low |

**Note:** Phases 2 and 3 can be partially parallelized (Swift proxy tool is decoupled from Ruby build pipeline). Phase 5 can be developed alongside Phase 4.
