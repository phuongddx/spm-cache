---
title: Structure
focus: arch
mapped_date: 2026-08-31
last_mapped_commit: fdb3a70abe81852ec9310a3ff410341a4adcfa0c
---
<!-- refreshed: 2026-08-31 -->

# Codebase Structure

**Analysis Date:** 2026-08-31

## Directory Layout

```
spm-cache/
├── .github/
│   └── workflows/          # CI, tap-update/deploy-key release automation
├── .planning/              # GSD project management (not shipped)
│   ├── codebase/           # Codebase map documents
│   ├── phases/             # Phase plans, summaries, benchmarks
│   └── research/           # Research artifacts
├── action/                 # GitHub Action composite action
├── bin/
│   └── spm-cache           # CLI entry point (Ruby script)
├── docs/                   # Project documentation, journals, superpowers specs
├── lib/
│   └── spm_cache/          # Ruby gem source
│       ├── command/        # CLAide CLI subcommands
│       ├── core/           # Shared infrastructure (incl. package_resolved.rb)
│       │   └── syntax/     # JSON/YAML/Plist representation mixins
│       ├── installer/      # Integration pipeline
│       │   └── integration/ # Supporting-file generation mixins
│       ├── spm/            # SwiftPM interactions (incl. resolved_graph.rb)
│       │   ├── desc/       # swift package describe models
│       │   │   └── target_types/ # Macro and binary target types
│       │   ├── xcframework/ # xcframework model
│       │   └── pkg/        # Proxy package orchestration
│       ├── cache/          # Cachemap model
│       ├── storage/        # Remote backends (git, s3)
│       ├── xcodeproj/      # xcodeproj manipulation helpers
│       ├── swift/          # Swift toolchain helpers (swiftc, sdk)
│       ├── utils/          # Template engine
│       └── assets/templates/ # spm-cache.yml and cachemap.js templates
├── plans/                  # Historical phase plans and reports
├── skills/                 # Claude skills for issue filing and workflow
├── spec/                   # RSpec test suite (48 files)
│   └── fixtures/           # Test lockfile JSON files
├── tools/
│   └── spm-cache-proxy/   # Swift companion binary
│       ├── Sources/
│       │   ├── CLI/        # ArgumentParser entry points (GenUmbrella, GenProxy, Resolve)
│       │   └── Core/       # Generator, Cache, Lockfile, Resolver models
│       └── Tests/          # Swift XCTest suite
├── Gemfile                 # Ruby dependencies
├── Gemfile.lock            # Dependency lock
├── Makefile                # install, format, test, proxy.build, proxy.clean targets
├── spm_cache.gemspec       # Gem specification
├── VERSION                 # Single-line version string (0.4.0)
└── CLAUDE.md               # Coding principles
```

## Directory Purposes

**`lib/spm_cache/`:**
- Purpose: All Ruby source code for the gem
- Contains: CLI commands, core infrastructure, SPM abstractions, installer pipeline, storage backends, xcodeproj helpers
- Key files: `lib/spm_cache/installer.rb` (base installer, 707 lines), `lib/spm_cache/command.rb` (CLAide root), `lib/spm_cache/core/config.rb` (singleton config), `lib/spm_cache/core/package_resolved.rb` (canonical host-graph locator)

**`lib/spm_cache/command/`:**
- Purpose: One file per CLI subcommand verb
- Contains: `use.rb`, `build.rb`, `watch.rb`, `init.rb`, `doctor.rb`, `cache.rb` (abstract parent for `cache/list.rb`, `cache/clean.rb`), `remote.rb` (abstract parent for `remote/push.rb`, `remote/pull.rb`), `pkg.rb` (abstract parent for `pkg/build.rb`), `rollback.rb`, `off.rb`, `base.rb` (shared options module)
- Key files: `lib/spm_cache/command/use.rb` (default subcommand), `lib/spm_cache/command/cache/list.rb` (fidelity-status column), `lib/spm_cache/command/cache/clean.rb` (sidecar orphan sweep)

**`lib/spm_cache/core/`:**
- Purpose: Shared infrastructure used across all layers
- Contains: Config singleton, Lockfile, PackageResolved (canonical locator), DiffDetector, Watcher, Diagnostics, Sh (shell execution), error types, logging, git helpers, hash utilities, parallel execution, system detection
- Key files: `lib/spm_cache/core/package_resolved.rb`, `lib/spm_cache/core/config.rb`, `lib/spm_cache/core/diff_detector.rb`, `lib/spm_cache/core/diagnostics.rb`, `lib/spm_cache/core/watcher.rb`, `lib/spm_cache/core/sh.rb`

**`lib/spm_cache/installer/`:**
- Purpose: The integration pipeline that replaces SPM source deps with cached binaries
- Contains: Base `Installer` class (via `installer.rb` parent), `Installer::Use` (fast path + build lock), `Installer::Build` (flock + fidelity-driven builds), `Installer::Rollback`, integration mixins for supporting files, descs, viz, and build
- Key files: `lib/spm_cache/installer/use.rb`, `lib/spm_cache/installer/build.rb`

**`lib/spm_cache/spm/`:**
- Purpose: Swift Package Manager interactions — host-graph seeding, building, describing, resolving
- Contains: ResolvedGraph (seed/restore), build pipeline (fidelity reporting), checkout resolver, buildable, desc models (target, product, dependency), xcframework model, proxy package orchestration, macro support
- Key files: `lib/spm_cache/spm/build_pipeline.rb` (1,177 lines), `lib/spm_cache/spm/resolved_graph.rb`, `lib/spm_cache/spm/build.rb`, `lib/spm_cache/spm/pkg/proxy.rb`, `lib/spm_cache/spm/checkout_resolver.rb`

**`tools/spm-cache-proxy/`:**
- Purpose: Swift companion binary for Package.swift code generation and cache-hit lookup
- Contains: `Sources/CLI/` (GenUmbrella, GenProxy, Resolve ArgumentParser commands), `Sources/Core/` (UmbrellaGenerator, ProxyGenerator, GraphGenerator, MetadataGenerator, BinariesCache, Lockfile, Resolver, Env), `Tests/spm-cache-proxyTests/` (Swift XCTest suite: UmbrellaGenerator, ProxyGenerator, Cache, Lockfile)
- Key files: `tools/spm-cache-proxy/Sources/CLI/GenProxy.swift`, `tools/spm-cache-proxy/Sources/CLI/GenUmbrella.swift`, `tools/spm-cache-proxy/Sources/Core/Generator/ProxyGenerator.swift`, `tools/spm-cache-proxy/Sources/Core/Generator/UmbrellaGenerator.swift`, `tools/spm-cache-proxy/Sources/Core/Cache.swift` (provenance-aware `hit`)

**`spec/`:**
- Purpose: RSpec test suite for all Ruby code
- Contains: 48 spec files covering installer, diff_detector, package_resolved, resolved_graph, lockfile reconciliation, fidelity regressions (drift/edge-matrix/bucket-partition), build pipeline (seeding/provenance), build lock, doctor (incl. lock-graph fidelity and companion version), cache list/clean, watch (loop/signals), init, action, proxy executable, and command behaviors; `fixtures/` directory with 5 test lockfile JSON files
- Key files: `spec/spec_helper.rb`, `spec/build_pipeline_spec.rb` (54.8KB, largest spec), `spec/build_pipeline_provenance_spec.rb` (921 lines), `spec/fidelity_edge_matrix_spec.rb`, `spec/fidelity_drift_regression_spec.rb`, `spec/fidelity_bucket_partition_spec.rb`, `spec/lockfile_reconciliation_spec.rb`, `spec/package_resolved_spec.rb`, `spec/resolved_graph_spec.rb`, `spec/build_lock_spec.rb`

**`action/`:**
- Purpose: GitHub Actions composite action for CI cache sharing
- Contains: `action.yml` (composite action spec), `README.md`
- Key files: `action/action.yml`

**`.github/workflows/`:**
- Purpose: CI and release automation
- Contains: `ci.yml` (Ruby matrix tests + Swift proxy build/test on macOS), `update-tap.yml` (deploy-key push of the formula to `phuongddx/homebrew-spm-cache` + post-publish install verification)
- Key files: `.github/workflows/ci.yml`, `.github/workflows/update-tap.yml`

## Key File Locations

**Entry Points:**
- `bin/spm-cache`: Ruby CLI entry point; adds `lib/` to load path, calls `SPMCache::Main.run(ARGV)`
- `lib/spm_cache/main.rb`: Recursive autoload of all `.rb` files, `--version` interception, dispatches to `Command.run`
- `lib/spm_cache/command.rb`: CLAide root command with global options; default subcommand is `use`
- `tools/spm-cache-proxy/Sources/CLI/GenUmbrella.swift`: Swift companion entry for umbrella generation
- `tools/spm-cache-proxy/Sources/CLI/GenProxy.swift`: Swift companion entry for proxy generation
- `tools/spm-cache-proxy/Sources/CLI/Resolve.swift`: Swift companion entry for graph resolve + metadata

**Configuration:**
- `lib/spm_cache/core/config.rb`: Singleton config; defines `SANDBOX_DIR`, `CACHE_DIR`, `CONFIG_FILENAME`, `LOCKFILE_FILENAME` constants and all path helpers, including `clones_dir` (`spm-cache/packages/clones`) and `build_lock_path` (`<project_dir>/.spm-cache-build.lock`, outside the sandbox by construction)
- `spm_cache.gemspec`: Gem metadata, runtime dependencies (claide, xcodeproj, parallel, tty-cursor, tty-screen, CFPropertyList)
- `Gemfile`: Dev dependencies (rspec, rubocop)
- `Makefile`: `install`, `format`, `test`, `proxy.build`, `proxy.clean` targets
- `VERSION`: Single-line version string (`0.4.0`); mirrored by `proxyVersion` in `tools/spm-cache-proxy/Sources/CLI.swift`

**Core Logic:**
- `lib/spm_cache/installer.rb`: Base installer — full integration pipeline (diff, lockfile reconcile, proxy, xcodeproj rewrite)
- `lib/spm_cache/core/package_resolved.rb`: Canonical `Package.resolved` locator (4 tiers) + strict/tolerant pin parsing
- `lib/spm_cache/spm/resolved_graph.rb`: Host-graph seed/restore into checkouts (atomic, snapshot-based)
- `lib/spm_cache/spm/build_pipeline.rb`: xcframework build pipeline — per-destination builds, framework assembly, binary target handling, fidelity read-back + `.provenance.json` sidecar write
- `lib/spm_cache/spm/pkg/proxy.rb`: Orchestrates umbrella → enrich → proxy generation sequence
- `tools/spm-cache-proxy/Sources/Core/Generator/ProxyGenerator.swift`: Per-package and root proxy Package.swift generation, graph.json emission
- `tools/spm-cache-proxy/Sources/Core/Generator/UmbrellaGenerator.swift`: Umbrella Package.swift generation from lockfile
- `tools/spm-cache-proxy/Sources/Core/Cache.swift`: Provenance-aware cache-hit decision (`hit(module:identity:currentPin:)`)

**Testing:**
- `spec/spec_helper.rb`: RSpec configuration
- `spec/installer_use_fast_path_spec.rb`: Fast-path guard incl. the `spm_cache_version` stamp condition
- `spec/build_pipeline_spec.rb`: Comprehensive build pipeline tests (54.8KB)
- `spec/build_pipeline_seeding_spec.rb`, `spec/build_pipeline_provenance_spec.rb`: Host-graph seeding and fidelity sidecar behavior
- `spec/lockfile_reconciliation_spec.rb`: Lockfile reconcile-from-host-graph behavior
- `spec/package_resolved_spec.rb`, `spec/resolved_graph_spec.rb`: Locator tiers and seed/restore semantics
- `spec/fidelity_drift_regression_spec.rb`, `spec/fidelity_edge_matrix_spec.rb`, `spec/fidelity_bucket_partition_spec.rb`: Fidelity regression suite
- `spec/build_lock_spec.rb`: Cross-process flock serialization
- `spec/watch_spec.rb`, `spec/watch_loop_spec.rb`, `spec/watch_signals_spec.rb`: Watcher and signal handling
- `spec/doctor_spec.rb`, `spec/doctor_lock_fidelity_spec.rb`, `spec/doctor_companion_version_spec.rb`: Diagnostics
- `spec/command_cache_list_spec.rb`, `spec/command_cache_clean_spec.rb`: Cache subcommands
- `spec/main_version_spec.rb`: `--version` interception
- `tools/spm-cache-proxy/Tests/spm-cache-proxyTests/`: Swift XCTest suite (UmbrellaGenerator, ProxyGenerator, Cache, Lockfile)

## Naming Conventions

**Files:**
- Ruby source files: `snake_case.rb` (e.g., `diff_detector.rb`, `package_resolved.rb`, `resolved_graph.rb`, `build_pipeline.rb`)
- Swift source files: `PascalCase.swift` (e.g., `ProxyGenerator.swift`, `BinariesCache.swift`, `GenProxy.swift`, `Resolve.swift`)
- Spec files: `snake_case_spec.rb` mirroring the source file under test (e.g., `package_resolved_spec.rb`, `watch_spec.rb`)
- Test fixtures: `kebab-case-lockfile.json` (e.g., `fidelity-kitchen-sink-lockfile.json`, `field-regression-lockfile.json`)
- Template files: `name.template` (e.g., `spm-cache.yml.template`, `cachemap.js.template`)
- Cache artifacts: `<Name>.xcframework` with sidecars `<Name>.xcframework.provenance.json` and `<Name>.xcframework.shims.json` (suffix-stripped basename shared with the framework)

**Directories:**
- Ruby modules: `snake_case` (e.g., `spm_cache/`, `core/`, `installer/`)
- Swift package structure: `Sources/Core/Generator/`, `Sources/CLI/`, `Tests/spm-cache-proxyTests/`
- CLI subcommands: single verb in `snake_case` (e.g., `command/watch.rb`, `command/doctor.rb`)
- Nested CLAide subcommand groups: abstract parent in `snake_case` (e.g., `command/cache/`, `command/remote/`, `command/pkg/`)

**Modules/Classes:**
- Ruby: `SPMCache::Core::ClassName`, `SPMCache::SPM::Module::ClassName`, `SPMCache::Command::VerbName`
- Swift: `PascalCase` structs (e.g., `UmbrellaGenerator`, `ProxyGenerator`, `BinariesCache`, `GenProxy`, `Resolver`)

## Where to Add New Code

**New CLI subcommand:**
- Implementation: `lib/spm_cache/command/<verb>.rb` — define `SPMCache::Command::<Verb>` inheriting from `Command`, set `self.summary` and `self.description`, implement `#run`
- For abstract subcommand groups (with children): add a parent `lib/spm_cache/command/<group>.rb` with `self.abstract_command = true` and a directory `lib/spm_cache/command/<group>/` for children
- Tests: `spec/<verb>_spec.rb`

**New diagnostic check (for `doctor`):**
- Implementation: Add a `register('check_name', fix_hint: '...') { |config:| ... }` block at `lib/spm_cache/core/diagnostics.rb` after the existing built-in checks; every input path must return a status instead of raising (a raise is captured as `:fail` and `doctor` exits 1)
- Host-graph comparisons MUST go through `Core::PackageResolved.locate` (see `lock_graph_fidelity` at `lib/spm_cache/core/diagnostics.rb:64`) — never a parallel `Dir.glob`
- Tests: `spec/doctor_spec.rb` (add expectations for the new check name)

**New core infrastructure:**
- Implementation: `lib/spm_cache/core/<module>.rb`
- Tests: `spec/<module>_spec.rb`
- Anything reading the host `Package.resolved` MUST route through `Core::PackageResolved` (`lib/spm_cache/core/package_resolved.rb`) rather than globbing independently

**New SPM interaction (build, describe, resolve, seed):**
- Implementation: `lib/spm_cache/spm/<module>.rb` or subdirectory under `lib/spm_cache/spm/`
- Tests: `spec/<module>_spec.rb`
- New `BuildPipeline.run` parameters default to `nil` and degrade to pre-existing behavior when omitted, so `spm-cache pkg build` (`lib/spm_cache/command/pkg/build.rb`) stays unaffected unless it opts in

**New Swift companion functionality:**
- Implementation: New file under `tools/spm-cache-proxy/Sources/Core/` or new CLI command under `tools/spm-cache-proxy/Sources/CLI/` (register it in the `subcommands` list in `tools/spm-cache-proxy/Sources/CLI.swift`)
- Tests: New file under `tools/spm-cache-proxy/Tests/spm-cache-proxyTests/`
- Ruby bridge: Add method to `lib/spm_cache/spm/pkg/proxy_executable.rb` that calls the new subcommand via `Core::Sh.run`
- Version bump: update `proxyVersion` in `tools/spm-cache-proxy/Sources/CLI.swift` in lockstep with the repo `VERSION` file

**New cache artifact metadata:**
- Sidecar writers must be tempfile-then-rename atomic and never raise post-success (mirror `write_provenance_sidecar` at `lib/spm_cache/spm/build_pipeline.rb:220`)
- Sidecar readers must fail safe to miss/absent (mirror `BinariesCache.hit` at `tools/spm-cache-proxy/Sources/Core/Cache.swift:28` and `fidelity_status_for` at `lib/spm_cache/command/cache/list.rb:29`)
- Orphan sweeping: register new sidecar extensions in `Command::Cache::Clean#sweep_orphaned_sidecars` (`lib/spm_cache/command/cache/clean.rb:66`)

**New storage backend (remote cache):**
- Implementation: `lib/spm_cache/storage/<backend>.rb` inheriting from `Storage::Base`
- Wire in: `lib/spm_cache/command/remote.rb` `create_storage` method
- Tests: `spec/storage_<backend>_spec.rb`

**New GitHub Actions workflow:**
- Implementation: `.github/workflows/<name>.yml`
- Release/tap automation: extend `.github/workflows/update-tap.yml` (deploy-key push + verification)

**New CI integration (composite action):**
- Implementation: `action/action.yml` (modify existing) or new action directory
- Tests: `spec/action_spec.rb`

## Special Directories

**`spm-cache/` (project-local sandbox):**
- Purpose: Generated at runtime inside the user's Xcode project directory; contains the proxy package, umbrella package, clones, metadata, and build artifacts
- Generated: Yes (by `Installer#recreate_dirs`)
- Committed: No (added to `.gitignore` by `init` command)
- Structure: `spm-cache/packages/proxy/` (root proxy + per-package proxies), `spm-cache/packages/umbrella/`, `spm-cache/packages/clones/` (shared `-clonedSourcePackagesDirPath` for all xcodebuild invocations), `spm-cache/metadata/`

**`<project_dir>/.spm-cache-build.lock` (build mutex):**
- Purpose: flock target serializing `Installer::Use` and `Installer::Build` across processes
- Generated: Yes (created by `acquire_build_lock`/`with_build_lock`)
- Committed: No
- Note: lives at project level, deliberately OUTSIDE `spm-cache/`, so `recreate_dirs`' `rm_rf` can never delete a live lock file (`Core::Config#build_lock_path`, `lib/spm_cache/core/config.rb:101`)

**`~/.spm-cache/` (global cache directory):**
- Purpose: Stores built xcframework binaries organized by config name (`~/.spm-cache/debug/`, `~/.spm-cache/release/`), each optionally accompanied by `.provenance.json` (fidelity attestation) and `.shims.json` (companion shims) sidecars
- Generated: Yes (by `BuildPipeline`)
- Committed: No (user-local; travels through remote backends as part of `remote push`/`pull`)

**`tools/spm-cache-proxy/.build/` (Swift build artifacts):**
- Purpose: Compiled Swift companion binary at `.build/release/spm-cache-proxy`
- Generated: Yes (by `make proxy.build` or auto-built on first use by `ProxyExecutable#build_from_source`)
- Committed: No (in `.gitignore`)

**`spec/fixtures/`:**
- Purpose: Static test data — lockfile JSON files used by RSpec tests
- Generated: No
- Committed: Yes

**`lib/spm_cache/assets/templates/`:**
- Purpose: ERB/text templates for `spm-cache.yml` and `cachemap.js` generation
- Generated: No
- Committed: Yes

---
*Structure analysis: 2026-08-31*
