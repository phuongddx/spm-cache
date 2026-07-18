# Codebase Summary

> **Last Updated:** 2026-07-18 (rev 6)
> **Version:** 0.2.2

## Overview

`spm-cache` is a dual-language tool for caching Swift Package Manager dependencies as `.xcframework` binaries. It consists of a Ruby gem (CLI orchestrator + build pipeline) and a Swift companion tool (SPM manifest generation + dependency graph resolution). **Verified end-to-end on a real iOS project** (ios-stress-app with 8 SPM dependencies, 2.06x build speedup).

## Languages & Sizes

| Component | Language | Files | LOC |
|-----------|----------|-------|-----|
| Ruby gem (`lib/`) | Ruby | 81 | 4,319 |
| Swift proxy (`tools/spm-cache-proxy/Sources/`) | Swift | 15 | 962 |
| Swift proxy tests (`tools/spm-cache-proxy/Tests/`) | Swift | 1 | 234 |
| Templates (`lib/spm_cache/assets/templates/`) | ERB/HTML/PLIST | 8 | — |
| Test suite (`spec/`) | Ruby | 21 | 2,076 |
| Agent skills (`skills/`) | Markdown + YAML | 9 | — |
| **Total** | — | **135+** | **7,591** |

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
- `installer.rb`: Base `Installer` class — `perform_install` orchestrates: verify → recreate_dirs → ensure_config (copy template if missing, then load config) → sync_lockfile → refresh_consumed_dependencies (Xcode project scan → target's directly-linked products into lockfile.dependencies) → prepare_proxy (gen_umbrella with isTransitiveOnly skip → resolve_umbrella_checkouts → enrich_lockfile_products from package describe → conditional retry_umbrella_resolve_after_enrichment if first resolve hit DerivedData fallback → gen_proxy with transitive-only skip in both umbrella and real proxy) → gen_supporting_files → integrate_proxy_into_project (keeps plugin-only package refs untouched, rewires everything else onto the local proxy) → gen_cachemap_viz
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

RSpec test suite with 21 files (~2,076 LOC) covering core utilities, enrichment pipelines, installer flows, and proxy generation:

**Core & Config** — 4 files
- `spec_helper.rb` — test setup and helpers
- `config_spec.rb` — `Core::Config` singleton behavior
- `core_spec.rb` — `Core::Sh` shell execution and `Core::UI` logging
- `buildable_spec.rb` — SPM package naming conventions and library evolution defaults

**Lockfile & Product Enrichment** — 2 files
- `lockfile_spec.rb` — lockfile parsing, package resolution, deep merge
- `checkout_enrichment_sequencing_spec.rb` — checkout resolution ordering and product enrichment

**Installer & Dependency Tracking** — 4 files
- `installer_spec.rb` — full install pipeline integration
- `installer_build_spec.rb` — build-specific installer behavior
- `installer_consumed_dependencies_spec.rb` — tracking directly-linked products per target
- `installer_integrate_proxy_spec.rb` — Xcode project integration step
- `installer_retry_umbrella_resolve_spec.rb` — retry-after-enrichment umbrella resolution

**Gen-Proxy Variants** — 6 files
- `gen_proxy_cache_only_spec.rb` — cache-only products
- `gen_proxy_ignore_spec.rb` — ignored/excluded patterns
- `gen_proxy_plugin_spec.rb` — plugin-only package handling
- `gen_proxy_products_spec.rb` — product expansion and naming
- `gen_proxy_field_regression_spec.rb` — real 59-package field project regression
- `gen_proxy_root_build_regression_spec.rb` — root proxy resolution stability

**Pipeline & Supporting** — 5 files
- `build_pipeline_spec.rb` — xcframework build orchestration
- `cachemap_spec.rb` — cachemap graph structure and visualization
- `desc_product_spec.rb` — product metadata extraction
- `lockfile_enrichment_spec.rb` — products array enrichment from package describes
- `proxy_executable_spec.rb` — Swift proxy binary execution and lifecycle

**Swift Proxy Tests** — `tools/spm-cache-proxy/Tests/LockfileTests.swift` (234 LOC)
- `PackageRef.versionRequirement` and pin serialization (revision-only vs. version pins)
- `isTransitiveOnly` behavior for both UmbrellaGenerator and ProxyGenerator
- Plugin-only product detection

### Agent Skills (`skills/`)

Two Claude agent skills for end-users and developers:

**`skills/spm-cache/`** — User-facing skill for spm-cache workflows
- `SKILL.md` — skill entry point
- `references/cli-reference.md` — complete command/option table
- `references/remote-cache.md` — Git/S3 remote setup guides
- `references/ci-cd.md` — install options (gem/Homebrew), GitHub Actions patterns (pull→build→use→build→push), CI exclusion strategy (cache_only/off), scheduled cache maintenance
- `references/troubleshooting.md` — common issues and solutions, including transitive-only version conflicts and an escalation pointer to `skills/spm-cache-issue`

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
- `Lockfile.swift`: `Lockfile` struct (Codable) — `PackageRef` carries `products: [ProductRef]?` (`{name, type, targets}`, enriched from `swift package describe`), `dependencies: {target => [product_names]}` (recorded by Ruby's `refresh_consumed_dependencies`), and `isTransitiveOnly` helper (checks if a package's products never appear in any target's dependencies). `libraryProducts` expands to every real `library`-type product (fallback: legacy `productName ?? name ?? slug`), `isPluginOnly` is true when `products` exists with no `library` entry. Also supports `revision`-only pins (emits `revision: "<sha>"` when only revision present, otherwise `from: "<version>"`, precedence `version` > `revision` > fallback), `TargetDeps`, platforms, `load(from:)`
- `Resolver.swift`: `Resolver` — package graph resolution (stub)
- `Env.swift`: `Env.isRunningInsideXcode`, `Env.isCI`
- `Generator/`:
  - `UmbrellaGenerator.swift`: Generates umbrella `Package.swift` from the lockfile — `dependencies:` only, no target/product references (immune to wrong/plugin product names). Skips packages that are plugin-only (no library products) AND transitive-only (no products appear in any target's dependencies, per `PackageRef.isTransitiveOnly(consumedProducts:)` helper).
  - `ProxyGenerator.swift`: Skips plugin-only packages (`plugin`-status `graph.json` entry, no proxy folder, no root-proxy dependency) AND transitive-only packages (same helper). For every other package, expands `libraryProducts` and generates ONE `.proxies/{slug}_proxy/Package.swift` exporting every real library product (each with its own binary/shim target — one `graph.json` entry per product, independent hit/miss status), plus root proxy, `graph.json`. Honors `ignoredPatterns`/`cacheOnlyPatterns` (fnmatch against any real product name OR package identity, package-level decision); ignored/excluded packages are always source even when a cached binary exists.
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
        → refresh_consumed_dependencies (Installer)
          → Xcode project analysis → records target's directly-linked product names
            → lockfile.dependencies = {target => [product_names]}
        → ProxyExecutable.gen_umbrella (calls Swift `gen-umbrella`)
          → UmbrellaGenerator: lockfile → umbrella Package.swift (skips transitive-only packages)
        → resolve_umbrella_checkouts (SPM::CheckoutResolver, mixed into Installer)
          → swift package resolve → real checkouts under .build/checkouts/{slug}
            (if fails, falls back to DerivedData; triggers retry_umbrella_resolve_after_enrichment)
        → enrich_lockfile_products (Installer)
          → swift package describe per checkout → products[] into spm-cache.lock
        → retry_umbrella_resolve_after_enrichment (if first resolve fell back to DerivedData)
          → regenerate umbrella with products[] now available
          → re-resolve umbrella (transitive-only skip now applies correctly)
        → ProxyExecutable.gen_proxy (calls Swift `gen-proxy`)
          → ProxyGenerator: packages → per-pkg proxy (per real product) + root proxy + graph.json
            (skips transitive-only and plugin-only packages; both use shared isTransitiveOnly helper)
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
