# Codebase Summary

> **Last Updated:** 2026-07-12 (rev 3)
> **Version:** 0.1.0

## Overview

`spm-cache` is a dual-language tool for caching Swift Package Manager dependencies as `.xcframework` binaries. It consists of a Ruby gem (CLI orchestrator + build pipeline) and a Swift companion tool (SPM manifest generation + dependency graph resolution). **Verified end-to-end on a real iOS project** (ios-stress-app with 8 SPM dependencies, 2.06x build speedup).

## Languages & Sizes

| Component | Language | Files | LOC |
|-----------|----------|-------|-----|
| Ruby gem (`lib/`) | Ruby | 79 | ~3,604 |
| Swift proxy (`tools/spm-cache-proxy/Sources/`) | Swift | 19 | ~822 |
| Templates (`lib/spm_cache/assets/templates/`) | ERB/HTML/PLIST | 8 | — |
| **Total** | — | **106+** | **~4,426** |

## Component Breakdown

### Ruby Gem (`lib/spm_cache/`)

**Entry Point:** `bin/spm-cache` → `SPMCache::Main.run(ARGV)` → auto-loads all `*.rb` files → `Command.run`

**`command/`** — CLAide-based CLI (13 files)
- `command.rb`: Abstract `Command < CLAide::Command`, default subcommand `use`
- `base.rb`: `BaseOptions` mixin (sdk, config, log_dir, merge_slices, library_evolution)
- `use.rb`, `build.rb`, `off.rb`, `rollback.rb`: Top-level commands
- `cache/`: `list`, `clean` subcommands
- `pkg/`: `build` subcommand (single package to xcframework)
- `remote/`: `pull`, `push` subcommands

**`core/`** — Foundational utilities (16 files)
- `config.rb`: `Config` singleton — paths, sandbox, cache dirs, remote config, ignore list
- `lockfile.rb`: `Lockfile` — JSON lockfile with `Pkg` class, deep_merge, dependency verification
- `sh.rb`: `Sh.run` — Open3-based command execution with live_log support
- `git.rb`: `Git` wrapper — init, checkout, fetch, push, clean, add, commit, remote
- `log.rb`: `UI`/`Log` module — section, info, warn, error, error!
- `live_log.rb`: `LiveLog` — tty-cursor based sticky terminal output
- `error.rb`: `BaseError`, `GeneralError`
- `cacheable.rb`: `Cacheable` mixin — method memoization
- `parallel.rb`: `Array#parallel_map` refinement (uses `parallel` gem)
- `hash.rb`: `Hash#deep_merge` refinement
- `system.rb`: `String#c99extidentifier`, `Pathname` extensions, `which`
- `syntax/`: Serialization mixins — `HashRepresentable`, `JSONRepresentable`, `YAMLRepresentable`, `PlistRepresentable`

**`installer/`** — Install pipeline (8 files)
- `installer.rb`: Base `Installer` class — `perform_install` orchestrates: verify → recreate_dirs → migrate → ensure_config → sync_lockfile → proxy_pkg.prepare → gen_supporting_files → add_refs → inject_xcconfig → gen_cachemap_viz
- `use.rb`, `build.rb`, `rollback.rb`: Installer subclasses
- `integration/`: Mixins — `BuildIntegrationMixin` (build_missed!), `DescsIntegrationMixin` (binary_targets), `SupportingFilesIntegrationMixin` (gen_xcconfigs for macros), `VizIntegrationMixin` (cachemap HTML)

**`spm/`** — SPM package model (18 files)
- `pkg/base.rb`: `SPM::Package` — describe, resolve, build_target (dispatches to xcframework or macro). `DEFAULT_DESTINATIONS = ["iphonesimulator", "iphoneos"]` for multi-slice builds.
- `pkg/proxy.rb`: `SPM::Package::Proxy` — orchestrates umbrella gen → resolve → proxy gen → graph load
- `pkg/proxy_executable.rb`: `ProxyExecutable` — locates/builds the Swift proxy binary, runs subcommands
- `build.rb`: `Buildable` — **uses `xcodebuild build`** (not `swift build`) with configurable destinations (sim + device), `libtool -static` for library creation, framework assembly with library evolution swiftinterface files. Supports `build_for_destination`, `create_static_library`, `create_framework`.
- `macro.rb`: `Macro` — builds macro targets as `.macro` binaries
- `xcframework/`: `XCFramework` (merges multiple framework slices via `xcodebuild -create-xcframework`), `Metadata` (checksum, Info.plist parsing)
- `desc/`: `Description` (swift package describe --type json), `Target`, `Product`, `Dependency`, `BinaryTarget`, `MacroTarget`

**`storage/`** — Remote cache backends (3 files)
- `base.rb`: `Storage::Base` — no-op fallback
- `git.rb`: `GitStorage` — shallow clone, fetch, commit, push
- `s3.rb`: `S3Storage` — aws s3 sync with credentials

**`xcodeproj/`** — Xcodeproj gem extensions (6 files)
- Monkey-patches `Xcodeproj::Project` objects: `ProjectExt`, `TargetExt`, `PkgRefMixin`, `PkgProductDepExt`, `GroupExt`, `BuildConfigExt`
- Adds `spmcache_pkgs`, `spmcache_proxy_pkg`, `add_pkg`, `add_product_dependency`

**`swift/`** — Swift toolchain (2 files)
- `sdk.rb`: `Swift::Sdk` — name, arch, triple, sdk_path, simulator?
- `swiftc.rb`: `Swift::Swiftc` — version detection

**`utils/`** — Utilities (1 file)
- `template.rb`: `Utils::Template` — ERB rendering from `assets/templates/`

### Swift Proxy Tool (`tools/spm-cache-proxy/`)

**Package:** `spm-cache-proxy`, Swift 6.0, macOS 14+
**Dependencies:** `swift-argument-parser`, `Rainbow`

**Entry Point:** `CLI` (AsyncParsableCommand) with subcommands: `gen-umbrella`, `gen-proxy`, `resolve`

**`CLI/`** (3 files)
- `GenUmbrella.swift`: Loads lockfile → merges packages/platforms → `UmbrellaGenerator.generate()`
- `GenProxy.swift`: Loads lockfile → `ProxyGenerator.generate(for:)` → `generateGraphJSON(entries:)`
- `Resolve.swift`: `Resolver.resolve()` (stub — metadata generation)

**`Core/`** (10 files)
- `Cache.swift`: `BinariesCache` — hit/binaryPath/cachedModules for `.xcframework` and `.macro`
- `Lockfile.swift`: `Lockfile` struct (Codable) — `PackageRef`, `TargetDeps`, platforms, `load(from:)`
- `Resolver.swift`: `Resolver` — package graph resolution (stub)
- `Env.swift`: `Env.isRunningInsideXcode`, `Env.isCI`
- `Generator/`:
  - `UmbrellaGenerator.swift`: Generates umbrella `Package.swift` from lockfile (deps + targets + platforms)
  - `ProxyGenerator.swift`: Generates per-package proxy `Package.swift` (binary or source), root proxy, `graph.json`
  - `GraphGenerator.swift`: Generates cytoscape-style graph JSON for visualization
  - `MetadataGenerator.swift`: Generates per-package metadata JSON
- `Proxy/`:
  - `ProxyPackageProtocol.swift`: Protocol with buildSettings, macroBuildSettings, headerSearchPathSettings
  - `ProxyPackage.swift`: Single proxy package manifest generation
  - `RootProxyPackage.swift`: Root proxy that aggregates all per-package proxies
- `Log/`: `Logger` (Rainbow colored), `LiveLog`
- `Extensions/Core.swift`: `URL` extensions (recreate, mkdir, symlink, touch), `String.c99extidentifier`

## Data Flow

```
User runs `spm-cache`
  → Command::Use.run
    → Installer::Use.perform_install
      → SPM::Package::Proxy.prepare
        → ProxyExecutable.gen_umbrella (calls Swift `gen-umbrella`)
          → UmbrellaGenerator: lockfile → umbrella Package.swift
        → ProxyExecutable.resolve (calls Swift `resolve`)
          → Resolver: package graph → metadata
        → ProxyExecutable.gen_proxy (calls Swift `gen-proxy`)
          → ProxyGenerator: packages → per-pkg proxy + root proxy + graph.json
        → load_graph (reads graph.json)
      → Cachemap.load(graph.json)
      → gen_cachemap_viz (HTML visualization)
    → replace_binaries_for_project
```

## Verified In Practice

End-to-end tested on `ios-stress-app` (NextGen-Limited):
- 8 SPM dependencies, 576 dependency source files vs 292 project source files
- Baseline clean build: 87.3s average (3 runs)
- With spm-cache (4/8 deps cached): 60.6s (2.06x speedup, 51% reduction)
- Multi-slice xcframeworks (simulator + device) built successfully via `spm-cache pkg build`
- Proxy integrated into `.xcodeproj` via `XCLocalSwiftPackageReference`
- Both simulator and device builds succeed

| File | Purpose |
|------|---------|
| `lib/spm_cache/command.rb` | CLI entry, CLAide command tree root |
| `lib/spm_cache/core/config.rb` | Singleton config with all paths |
| `lib/spm_cache/installer.rb` | Install pipeline orchestrator |
| `lib/spm_cache/spm/pkg/proxy.rb` | Proxy package orchestrator |
| `lib/spm_cache/spm/pkg/proxy_executable.rb` | Swift binary bridge |
| `tools/spm-cache-proxy/Sources/Core/Generator/ProxyGenerator.swift` | Proxy manifest generation core |
| `tools/spm-cache-proxy/Sources/Core/Generator/UmbrellaGenerator.swift` | Umbrella manifest generation |
| `tools/spm-cache-proxy/Sources/Core/Cache.swift` | Binary cache lookup |
