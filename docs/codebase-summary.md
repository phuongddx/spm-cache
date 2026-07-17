# Codebase Summary

> **Last Updated:** 2026-07-16 (rev 5)
> **Version:** 0.2.0

## Overview

`spm-cache` is a dual-language tool for caching Swift Package Manager dependencies as `.xcframework` binaries. It consists of a Ruby gem (CLI orchestrator + build pipeline) and a Swift companion tool (SPM manifest generation + dependency graph resolution). **Verified end-to-end on a real iOS project** (ios-stress-app with 8 SPM dependencies, 2.06x build speedup).

## Languages & Sizes

| Component | Language | Files | LOC |
|-----------|----------|-------|-----|
| Ruby gem (`lib/`) | Ruby | 81 | ~3,900 |
| Swift proxy (`tools/spm-cache-proxy/Sources/`) | Swift | 15 | ~800 |
| Templates (`lib/spm_cache/assets/templates/`) | ERB/HTML/PLIST | 8 | — |
| Test suite (`spec/`) | Ruby | 4 | ~150 |
| Agent skills (`skills/`) | Markdown + YAML | 8 | — |
| **Total** | — | **118+** | **~4,576** |

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
- `installer.rb`: Base `Installer` class — `perform_install` orchestrates: verify → recreate_dirs → ensure_config (copy template if missing, then load config) → sync_lockfile → prepare_proxy (gen_umbrella → resolve_umbrella_checkouts → enrich_lockfile_products → gen_proxy) → gen_supporting_files → integrate_proxy_into_project (keeps plugin-only package refs untouched, rewires everything else onto the local proxy) → gen_cachemap_viz
- `use.rb`, `build.rb`, `rollback.rb`: Installer subclasses. `Installer::Build` accepts a `targets:` kwarg (expanding a package identity to all of its real product names via `expand_target_aliases`), filters the cachemap missed set, and invokes `SPM::BuildPipeline` per target to build real xcframeworks into the cache dir. Checkout resolution itself moved to the base `Installer#prepare_proxy` (all flows), no longer duplicated here.
- `integration/`: Mixins — `BuildIntegrationMixin` (build_missed!), `DescsIntegrationMixin` (binary_targets), `SupportingFilesIntegrationMixin` (gen_xcconfigs for macros), `VizIntegrationMixin` (cachemap HTML). **Dead code**: never required/included anywhere.

**`spm/`** — SPM package model (19 files)
- `pkg/base.rb`: `SPM::Package` — describe, resolve, build_target (dispatches to xcframework or macro). `DEFAULT_DESTINATIONS = ["iphonesimulator", "iphoneos"]` for multi-slice builds.
- `pkg/proxy.rb`: `SPM::Package::Proxy` — `prepare` orchestrates gen_umbrella → (caller-supplied materialize+enrich block) → invalidate_cache → gen_proxy → load_graph
- `pkg/proxy_executable.rb`: `ProxyExecutable` — locates/builds the Swift proxy binary, runs subcommands
- `checkout_resolver.rb`: `SPM::CheckoutResolver` — shared module (mixed into `Installer`) for `resolve_umbrella_checkouts`/`fallback_xcode_checkouts`/`checkout_map`/`slug_for`, used by every install flow (previously only `Installer::Build`, and only after Xcode integration)
- `build.rb`: `Buildable` — **uses `xcodebuild build`** (not `swift build`) with configurable destinations (sim + device), `libtool -static` for library creation, framework assembly with library evolution swiftinterface files. Supports `build_for_destination`, `create_static_library`, `create_framework`.
- `build_pipeline.rb`: `SPM::BuildPipeline` — shared xcframework build pipeline (destination loop + framework assembly + xcframework creation). **Resolves Xcode scheme from `swift package describe` product metadata** (filters library-type products by exact name, substring containment, or first available library), with fallback to `xcodebuild -list` heuristic if no match found. Used by both `pkg build` and `Installer::Build`.
- `macro.rb`: `Macro` — builds macro targets as `.macro` binaries
- `xcframework/`: `XCFramework` (merges multiple framework slices via `xcodebuild -create-xcframework`), `Metadata` (checksum, Info.plist parsing)
- `desc/`: `Description` (swift package describe --type json), `Target`, `Product` (`to_h` → `{name:, targets:, type:}`, feeds directly into `spm-cache.lock`'s `products[]`), `Dependency`, `BinaryTarget`, `MacroTarget`

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

### Test Suite (`spec/`)

RSpec tests with 19 examples covering:
- `spec_helper.rb` — test setup and helpers
- `config_spec.rb` — `Core::Config` singleton behavior
- `core_spec.rb` — `Core::Sh` shell execution and `Core::UI` logging
- `lockfile_spec.rb` — lockfile parsing, package resolution, deep merge
- `buildable_spec.rb` — SPM package naming conventions and library evolution defaults

**Not yet covered:** Installer integration, Storage backends, Proxy execution (known limitation)

### Agent Skills (`skills/`)

Two Claude agent skills for end-users and developers:

**`skills/spm-cache/`** — User-facing skill for spm-cache workflows
- `SKILL.md` — skill entry point
- `references/cli-reference.md` — complete command/option table
- `references/remote-cache.md` — Git/S3 remote setup guides
- `references/ci-cd.md` — GitHub Actions patterns (pull→build→use→build→push)
- `references/troubleshooting.md` — 7 common issues and solutions

**`skills/spm-cache-issue/`** — GitHub issue filing skill
- `SKILL.md` — skill entry point
- `scripts/collect_diagnostics.sh` — gathers OS, Ruby, Swift, Xcode, and gem diagnostics
- Includes `agents/openai.yaml` for non-Claude runtime compatibility

### Swift Proxy Tool (`tools/spm-cache-proxy/`)

**Package:** `spm-cache-proxy`, Swift 6.0, macOS 14+
**Dependencies:** `swift-argument-parser`, `Rainbow`

**Entry Point:** `CLI` (AsyncParsableCommand) with subcommands: `gen-umbrella`, `gen-proxy`, `resolve`

**`CLI/`** (3 files)
- `GenUmbrella.swift`: Loads lockfile → merges packages/platforms → `UmbrellaGenerator.generate()`
- `GenProxy.swift`: Loads lockfile → `ProxyGenerator.generate(for:)` → `generateGraphJSON(entries:)`. Accepts `--ignore` CSV glob patterns to exclude modules from caching.
- `Resolve.swift`: `Resolver.resolve()` (stub — metadata generation)

**`Core/`** (9 files)
- `Cache.swift`: `BinariesCache` — hit/binaryPath/cachedModules for `.xcframework` and `.macro`
- `Lockfile.swift`: `Lockfile` struct (Codable) — `PackageRef` now carries `products: [ProductRef]?` (`{name, type, targets}`, enriched by the Ruby side from `swift package describe`); `libraryProducts` expands to every real `library`-type product (falling back to a single synthetic entry derived from the legacy `productName ?? name ?? slug` when `products` is absent), `isPluginOnly` is true when `products` metadata exists with no `library` entry. Also supports `revision`-only pins (emits `revision: "<sha>"` when only revision present, otherwise `from: "<version>"`, precedence `version` > `revision` > fallback), `TargetDeps`, platforms, `load(from:)`
- `Resolver.swift`: `Resolver` — package graph resolution (stub)
- `Env.swift`: `Env.isRunningInsideXcode`, `Env.isCI`
- `Generator/`:
  - `UmbrellaGenerator.swift`: Generates umbrella `Package.swift` from the lockfile — `dependencies:` only, no target/product references (resolve doesn't validate products, so this also makes checkout resolution immune to wrong/plugin product names); skips a package already known to be plugin-only
  - `ProxyGenerator.swift`: Skips plugin-only packages (`plugin`-status `graph.json` entry, no proxy folder, no root-proxy dependency). For every other package, expands `libraryProducts` and generates ONE `.proxies/{slug}_proxy/Package.swift` exporting every real library product (each with its own binary/shim target — one `graph.json` entry per product, independent hit/miss status), plus root proxy, `graph.json`. Honors `ignoredPatterns`/`cacheOnlyPatterns` (fnmatch against any real product name OR package identity, package-level decision); ignored/excluded packages are always source even when a cached binary exists.
  - `GraphGenerator.swift`: Cytoscape-style graph JSON generator — dead code, no callers
  - `MetadataGenerator.swift`: Generates per-package metadata JSON
- `Log/`: `Logger` (Rainbow colored), `LiveLog`
- `Extensions/Core.swift`: `URL` extensions (recreate, mkdir, symlink, touch), `String.c99extidentifier`

## Data Flow

```
User runs `spm-cache`
  → Command::Use.run
    → Installer::Use.perform_install
      → SPM::Package::Proxy.prepare
        → ProxyExecutable.gen_umbrella (calls Swift `gen-umbrella`)
          → UmbrellaGenerator: lockfile → umbrella Package.swift (deps only)
        → resolve_umbrella_checkouts (SPM::CheckoutResolver, mixed into Installer)
          → swift package resolve → real checkouts under .build/checkouts/{slug}
            (falls back to newest matching DerivedData checkouts on failure)
        → enrich_lockfile_products (Installer)
          → swift package describe per checkout → products[] into spm-cache.lock
        → ProxyExecutable.gen_proxy (calls Swift `gen-proxy`)
          → ProxyGenerator: packages → per-pkg proxy (per real product) + root proxy + graph.json
            (plugin-only packages skipped, `plugin` status instead)
        → load_graph (reads graph.json)
      → integrate_proxy_into_project (keeps plugin-only refs, rewires everything else)
      → Cachemap.load(graph.json)
      → gen_cachemap_viz (HTML visualization)
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
