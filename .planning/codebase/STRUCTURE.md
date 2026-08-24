---
title: Structure
focus: arch
mapped_date: 2026-08-23
last_mapped_commit: f55b9b9a7dc73104b490ed76ec38549b242af03e
---
<!-- refreshed: 2026-08-23 -->

# Codebase Structure

**Analysis Date:** 2026-08-23

## Directory Layout

```
spm-cache/
├── .github/
│   └── workflows/          # CI and tap-update GitHub Actions
├── .planning/              # GSD project management (not shipped)
│   ├── codebase/           # Codebase map documents
│   ├── phases/             # Phase plans and summaries
│   └── research/           # Research artifacts
├── action/                 # GitHub Action composite action
├── bin/
│   └── spm-cache           # CLI entry point (Ruby script)
├── docs/                   # Project documentation, journals, superpowers specs
├── lib/
│   └── spm_cache/          # Ruby gem source
│       ├── command/        # CLAide CLI subcommands
│       ├── core/           # Shared infrastructure
│       │   └── syntax/     # JSON/YAML/Plist representation mixins
│       ├── installer/      # Integration pipeline
│       │   └── integration/ # Supporting-file generation mixins
│       ├── spm/            # SwiftPM interactions
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
├── plans/                 # Historical phase plans and reports
├── skills/                # Claude skills for issue filing and workflow
├── spec/                  # RSpec test suite
│   └── fixtures/          # Test lockfile JSON files
├── tools/
│   └── spm-cache-proxy/   # Swift companion binary
│       ├── Sources/
│       │   ├── CLI/        # ArgumentParser entry points
│       │   └── Core/       # Generator, Cache, Lockfile models
│       └── Tests/          # Swift XCTest suite
├── Gemfile                # Ruby dependencies
├── Gemfile.lock           # Dependency lock
├── Makefile               # build, test, format, proxy.build targets
├── spm_cache.gemspec      # Gem specification
├── VERSION                # Single-line version string (0.3.0)
└── CLAUDE.md              # Coding principles
```

## Directory Purposes

**`lib/spm_cache/`:**
- Purpose: All Ruby source code for the gem
- Contains: CLI commands, core infrastructure, SPM abstractions, installer pipeline, storage backends, xcodeproj helpers
- Key files: `lib/spm_cache/installer.rb` (base installer, 578 lines), `lib/spm_cache/command.rb` (CLAide root), `lib/spm_cache/core/config.rb` (singleton config)

**`lib/spm_cache/command/`:**
- Purpose: One file per CLI subcommand verb
- Contains: `use.rb`, `build.rb`, `watch.rb`, `init.rb`, `doctor.rb`, `cache.rb` (abstract parent for `cache/list.rb`, `cache/clean.rb`), `remote.rb` (abstract parent for `remote/push.rb`, `remote/pull.rb`), `pkg.rb`, `rollback.rb`, `off.rb`, `base.rb` (shared options module)
- Key files: `lib/spm_cache/command/use.rb` (default subcommand), `lib/spm_cache/command/watch.rb` (v0.3.0), `lib/spm_cache/command/init.rb` (v0.3.0), `lib/spm_cache/command/doctor.rb` (v0.3.0)

**`lib/spm_cache/core/`:**
- Purpose: Shared infrastructure used across all layers
- Contains: Config singleton, Lockfile, DiffDetector, Watcher, Diagnostics, Sh (shell execution), error types, logging, git helpers, hash utilities, parallel execution, system detection
- Key files: `lib/spm_cache/core/config.rb`, `lib/spm_cache/core/diff_detector.rb`, `lib/spm_cache/core/watcher.rb`, `lib/spm_cache/core/diagnostics.rb`, `lib/spm_cache/core/sh.rb`

**`lib/spm_cache/installer/`:**
- Purpose: The integration pipeline that replaces SPM source deps with cached binaries
- Contains: Base `Installer` class (via `installer.rb` parent), `Installer::Use` (fast-path override), `Installer::Build`, integration mixins for supporting files, descs, viz, and build
- Key files: `lib/spm_cache/installer/use.rb`, `lib/spm_cache/installer/build.rb`

**`lib/spm_cache/spm/`:**
- Purpose: Swift Package Manager interactions — building, describing, resolving
- Contains: Build pipeline, checkout resolver, desc models (target, product, dependency), xcframework model, proxy package orchestration, macro support
- Key files: `lib/spm_cache/spm/build_pipeline.rb` (919 lines), `lib/spm_cache/spm/pkg/proxy.rb`, `lib/spm_cache/spm/checkout_resolver.rb`

**`tools/spm-cache-proxy/`:**
- Purpose: Swift companion binary for Package.swift code generation
- Contains: `Sources/CLI/` (GenUmbrella, GenProxy ArgumentParser commands), `Sources/Core/` (UmbrellaGenerator, ProxyGenerator, BinariesCache, Lockfile model), `Tests/` (Swift XCTest suite)
- Key files: `tools/spm-cache-proxy/Sources/CLI/GenProxy.swift`, `tools/spm-cache-proxy/Sources/CLI/GenUmbrella.swift`, `tools/spm-cache-proxy/Sources/Core/Generator/ProxyGenerator.swift`, `tools/spm-cache-proxy/Sources/Core/Generator/UmbrellaGenerator.swift`

**`spec/`:**
- Purpose: RSpec test suite for all Ruby code
- Contains: 30+ spec files covering installer, diff_detector, lockfile, config, cachemap, watcher, doctor, init, proxy_executable, build pipeline, and command behaviors; `fixtures/` directory with test lockfile JSON files
- Key files: `spec/spec_helper.rb`, `spec/installer_use_fast_path_spec.rb`, `spec/build_pipeline_spec.rb` (50.8KB, largest spec)

**`action/`:**
- Purpose: GitHub Actions composite action for CI cache sharing
- Contains: `action.yml` (composite action spec), `README.md`
- Key files: `action/action.yml`

**`.github/workflows/`:**
- Purpose: CI and automation
- Contains: `ci.yml` (Ruby matrix tests + Swift proxy build/test on macOS 15), `update-tap.yml`
- Key files: `.github/workflows/ci.yml`

## Key File Locations

**Entry Points:**
- `bin/spm-cache`: Ruby CLI entry point; adds `lib/` to load path, calls `SPMCache::Main.run(ARGV)`
- `lib/spm_cache/main.rb`: Recursive autoload of all `.rb` files, dispatches to `Command.run`
- `lib/spm_cache/command.rb`: CLAide root command with global options; default subcommand is `use`
- `tools/spm-cache-proxy/Sources/CLI/GenUmbrella.swift`: Swift companion entry for umbrella generation
- `tools/spm-cache-proxy/Sources/CLI/GenProxy.swift`: Swift companion entry for proxy generation

**Configuration:**
- `lib/spm_cache/core/config.rb`: Singleton config; defines `SANDBOX_DIR`, `CACHE_DIR`, `CONFIG_FILENAME`, `LOCKFILE_FILENAME` constants and all path helpers
- `spm_cache.gemspec`: Gem metadata, runtime dependencies (claide, xcodeproj, parallel, tty-cursor, tty-screen, CFPropertyList)
- `Gemfile`: Dev dependencies (rspec, rubocop)
- `Makefile`: `install`, `format`, `test`, `proxy.build`, `proxy.clean` targets
- `VERSION`: Single-line version string (`0.3.0`)

**Core Logic:**
- `lib/spm_cache/installer.rb`: Base installer — full integration pipeline (diff, lockfile, proxy, xcodeproj rewrite)
- `lib/spm_cache/spm/build_pipeline.rb`: xcframework build pipeline — per-destination builds, framework assembly, binary target handling
- `lib/spm_cache/spm/pkg/proxy.rb`: Orchestrates umbrella → enrich → proxy generation sequence
- `tools/spm-cache-proxy/Sources/Core/Generator/ProxyGenerator.swift`: Per-package and root proxy Package.swift generation, graph.json emission
- `tools/spm-cache-proxy/Sources/Core/Generator/UmbrellaGenerator.swift`: Umbrella Package.swift generation from lockfile

**Testing:**
- `spec/spec_helper.rb`: RSpec configuration
- `spec/installer_use_fast_path_spec.rb`: Tests the fast-path no-op optimization
- `spec/build_pipeline_spec.rb`: Comprehensive build pipeline tests (50.8KB)
- `spec/watch_spec.rb`: v0.3.0 watcher tests
- `spec/doctor_spec.rb`: v0.3.0 diagnostics tests
- `spec/init_spec.rb`: v0.3.0 init command tests
- `tools/spm-cache-proxy/Tests/`: Swift XCTest suite (Lockfile, UmbrellaGenerator, ProxyGenerator)

## Naming Conventions

**Files:**
- Ruby source files: `snake_case.rb` (e.g., `diff_detector.rb`, `proxy_executable.rb`, `build_pipeline.rb`)
- Swift source files: `PascalCase.swift` (e.g., `ProxyGenerator.swift`, `BinariesCache.swift`, `GenProxy.swift`)
- Spec files: `snake_case_spec.rb` mirroring the source file under test (e.g., `diff_detector_spec.rb`, `watch_spec.rb`)
- Test fixtures: `kebab-case-lockfile.json` (e.g., `field-regression-lockfile.json`, `plugin-lockfile.json`)
- Template files: `name.template` (e.g., `spm-cache.yml.template`, `cachemap.js.template`)

**Directories:**
- Ruby modules: `snake_case` (e.g., `spm_cache/`, `build_pipeline.rb`)
- Swift package structure: `Sources/Core/Generator/`, `Tests/spm-cache-proxyTests/`
- CLI subcommands: single verb in `snake_case` (e.g., `command/watch.rb`, `command/doctor.rb`)
- Nested CLAide subcommand groups: abstract parent in `snake_case` (e.g., `command/cache/`, `command/remote/`)

**Modules/Classes:**
- Ruby: `SPMCache::Core::ClassName`, `SPMCache::SPM::Module::ClassName`, `SPMCache::Command::VerbName`
- Swift: `PascalCase` structs (e.g., `UmbrellaGenerator`, `ProxyGenerator`, `BinariesCache`, `GenProxy`)

## Where to Add New Code

**New CLI subcommand:**
- Implementation: `lib/spm_cache/command/<verb>.rb` — define `SPMCache::Command::<Verb>` inheriting from `Command`, set `self.summary` and `self.description`, implement `#run`
- For abstract subcommand groups (with children): add a parent `lib/spm_cache/command/<group>.rb` with `self.abstract_command = true` and a directory `lib/spm_cache/command/<group>/` for children
- Tests: `spec/<verb>_spec.rb`

**New diagnostic check (for `doctor`):**
- Implementation: Add a `register('check_name', fix_hint: '...') { |config:| ... }` block at `lib/spm_cache/core/diagnostics.rb` after the existing built-in checks
- Tests: `spec/doctor_spec.rb` (add expectations for the new check name)

**New core infrastructure:**
- Implementation: `lib/spm_cache/core/<module>.rb`
- Tests: `spec/<module>_spec.rb`

**New SPM interaction (build, describe, resolve):**
- Implementation: `lib/spm_cache/spm/<module>.rb` or subdirectory under `lib/spm_cache/spm/`
- Tests: `spec/<module>_spec.rb`

**New Swift companion functionality:**
- Implementation: New file under `tools/spm-cache-proxy/Sources/Core/` or new CLI command under `tools/spm-cache-proxy/Sources/CLI/`
- Tests: New file under `tools/spm-cache-proxy/Tests/spm-cache-proxyTests/`
- Ruby bridge: Add method to `lib/spm_cache/spm/pkg/proxy_executable.rb` that calls the new subcommand via `Core::Sh.run`

**New storage backend (remote cache):**
- Implementation: `lib/spm_cache/storage/<backend>.rb` inheriting from `Storage::Base`
- Wire in: `lib/spm_cache/command/remote.rb` `create_storage` method
- Tests: `spec/storage_<backend>_spec.rb`

**New GitHub Actions workflow:**
- Implementation: `.github/workflows/<name>.yml`

**New CI integration (composite action):**
- Implementation: `action/action.yml` (modify existing) or new action directory

## Special Directories

**`spm-cache/` (project-local sandbox):**
- Purpose: Generated at runtime inside the user's Xcode project directory; contains the proxy package, umbrella package, metadata, and build artifacts
- Generated: Yes (by `Installer#recreate_dirs`)
- Committed: No (added to `.gitignore` by `init` command)
- Structure: `spm-cache/packages/proxy/` (root proxy + per-package proxies), `spm-cache/packages/umbrella/`, `spm-cache/metadata/`

**`~/.spm-cache/` (global cache directory):**
- Purpose: Stores built xcframework binaries organized by config name (`~/.spm-cache/debug/`, `~/.spm-cache/release/`)
- Generated: Yes (by `BuildPipeline`)
- Committed: No (user-local)

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
*Structure analysis: 2026-08-23*
