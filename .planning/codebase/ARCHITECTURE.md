---
title: Architecture
focus: arch
mapped_date: 2026-08-23
last_mapped_commit: f55b9b9a7dc73104b490ed76ec38549b242af03e
---
<!-- refreshed: 2026-08-23 -->

# Architecture

**Analysis Date:** 2026-08-23

## System Overview

```text
┌──────────────────────────────────────────────────────────────────────┐
│                        CLI Layer (CLAide)                            │
│              `bin/spm-cache` → `lib/spm_cache/main.rb`               │
├──────┬──────┬───────┬───────┬───────┬──────┬──────┬───────┬──────────┤
│ use  │build │ init  │watch  │doctor │cache │remote│  pkg  │rollback  │
└──┬───┴──┬───┴──┬────┴──┬────┴──┬────┴──┬─────┴──┬───┴──┬────┴──┬─────┘
   │      │      │      │      │      │        │      │      │
   ▼      │      │      ▼      │      │        │      │      │
┌──────────┐│   ┌──────────┐  ┌──────────┐    │   ┌──────────┐
│Installer ││   │   Core   │  │  Core    │    │   │Installer │
│  ::Use   ││   │ Watcher  │  │Diagnostics│   │   │ ::Build  │
└────┬─────┘│   └──────────┘  └──────────┘    │   └──────────┘
     │      │                                   │
     ▼      │                                   ▼
┌──────────────────────────────────────┐   ┌──────────────┐
│          Installer (base)            │   │ BuildPipeline │
│  `lib/spm_cache/installer.rb`        │   │ + xcframework │
│  DiffDetector → Lockfile → Proxy    │   └──────────────┘
│  → integrate into .xcodeproj        │
└──────────┬───────────────────────────┘
           │ delegates to
           ▼
┌──────────────────────────────────────┐
│      SPM::Package::Proxy             │
│  `lib/spm_cache/spm/pkg/proxy.rb`    │
│  → ProxyExecutable (shell-out)      │
└──────────┬───────────────────────────┘
           │ CLI calls
           ▼
┌──────────────────────────────────────┐
│     Swift companion binary           │
│  `tools/spm-cache-proxy/`            │
│  gen-umbrella / gen-proxy            │
│  UmbrellaGenerator / ProxyGenerator  │
└──────────────────────────────────────┘
```

## Component Responsibilities

| Component | Responsibility | File |
|-----------|----------------|------|
| `Main` | Entry point; recursive autoload of all `.rb` files; dispatches to `Command.run` | `lib/spm_cache/main.rb` |
| `Command` (CLAide) | CLI root; defines global options (`--sdk`, `--config`, `--log-dir`, `--merge-slices`, `--no-library-evolution`); default subcommand is `use` | `lib/spm_cache/command.rb` |
| `Command::Use` | Primary command; finds `.xcodeproj`, creates `Installer::Use`, optionally runs inline polling watch loop | `lib/spm_cache/command/use.rb` |
| `Command::Watch` | v0.3.0 — delegates to `Core::Watcher` for `Package.resolved` + `project.pbxproj` polling with configurable debounce | `lib/spm_cache/command/watch.rb` |
| `Command::Init` | v0.3.0 — bootstraps `spm-cache.yml` + seeded `spm-cache.lock`; interactive or flags-driven; idempotent diff-merge | `lib/spm_cache/command/init.rb` |
| `Command::Doctor` | v0.3.0 — runs registered diagnostic checks (`Core::Diagnostics`); human or `--json` output; non-zero exit on failure | `lib/spm_cache/command/doctor.rb` |
| `Command::Build` | Builds specific targets into xcframeworks via `Installer::Build` + `BuildPipeline` | `lib/spm_cache/command/build.rb` |
| `Command::Cache` | Abstract parent for `list` and `clean` subcommands | `lib/spm_cache/command/cache.rb` |
| `Command::Remote` | Abstract parent for `pull`/`push`; creates `Storage::GitStorage` or `Storage::S3Storage` from config | `lib/spm_cache/command/remote.rb` |
| `Command::Pkg` | Abstract parent for `build` subcommand | `lib/spm_cache/command/pkg.rb` |
| `Installer` (base) | Full integration pipeline: diff detect → lockfile sync → proxy prepare → xcodeproj rewrite → cachemap report | `lib/spm_cache/installer.rb` |
| `Installer::Use` | Overrides `perform_install` with fast-path guard (no-op when lockfile matches live graph and proxy exists) | `lib/spm_cache/installer/use.rb` |
| `Installer::Build` | Builds xcframeworks from umbrella checkouts via `BuildPipeline` | `lib/spm_cache/installer/build.rb` |
| `Core::Config` | Singleton; owns `spm-cache.yml` parsing, sandbox/cache/umbrella/proxy dir paths, ignore/cache-only lists | `lib/spm_cache/core/config.rb` |
| `Core::Lockfile` | Reads/writes `spm-cache.lock` JSON; models packages, products, dependencies, platforms per project | `lib/spm_cache/core/lockfile.rb` |
| `Core::DiffDetector` | Compares live Xcode SPM graph (Package.resolved + pbxproj refs) against lockfile snapshot; produces structured `Diff` | `lib/spm_cache/core/diff_detector.rb` |
| `Core::Watcher` | mtime+size polling loop over `Package.resolved` and `project.pbxproj`; configurable debounce; continue-on-error | `lib/spm_cache/core/watcher.rb` |
| `Core::Diagnostics` | Data-driven check registry (Xcode, Swift, toolchain, cache dir, LE compat, remote connectivity, companion binary) | `lib/spm_cache/core/diagnostics.rb` |
| `Core::Sh` | Shell execution via `Open3`; live-log or capture mode; bounded failure detail (last 60 lines) | `lib/spm_cache/core/sh.rb` |
| `SPM::Package::Proxy` | Orchestrates the three-phase proxy flow: gen-umbrella → enrich lockfile → gen-proxy | `lib/spm_cache/spm/pkg/proxy.rb` |
| `SPM::Package::ProxyExecutable` | Locates (env var or built binary) and shell-outs to the Swift companion tool | `lib/spm_cache/spm/pkg/proxy_executable.rb` |
| `SPM::CheckoutResolver` | Mixin; resolves umbrella checkouts via `swift package resolve`, falls back to DerivedData copy | `lib/spm_cache/spm/checkout_resolver.rb` |
| `SPM::BuildPipeline` | Builds per-destination frameworks, assembles xcframeworks, handles binary targets, private Clang shims | `lib/spm_cache/spm/build_pipeline.rb` |
| `SPM::Desc::Description` | Wraps `swift package describe --type json`; models targets, products, dependencies, platform traversal | `lib/spm_cache/spm/desc/desc.rb` |
| `Cache::Cachemap` | Loads `graph.json`; reports cache hit/miss/ignored/excluded/plugin stats per module | `lib/spm_cache/cache/cachemap.rb` |
| `GenUmbrella` (Swift) | ArgumentParser CLI; calls `UmbrellaGenerator` to emit a combined `Package.swift` pinning all deps | `tools/spm-cache-proxy/Sources/CLI/GenUmbrella.swift` |
| `GenProxy` (Swift) | ArgumentParser CLI; calls `ProxyGenerator` to emit per-package proxy `Package.swift` + root proxy + `graph.json` | `tools/spm-cache-proxy/Sources/CLI/GenProxy.swift` |
| `UmbrellaGenerator` (Swift) | Generates umbrella Package.swift from lockfile; skips plugin-only and transitive-only packages | `tools/spm-cache-proxy/Sources/Core/Generator/UmbrellaGenerator.swift` |
| `ProxyGenerator` (Swift) | Generates per-package proxy Package.swift (binary on cache hit, source shim on miss); root proxy aggregating all; `graph.json` | `tools/spm-cache-proxy/Sources/Core/Generator/ProxyGenerator.swift` |
| `BinariesCache` (Swift) | Looks up `~/.spm-cache/<config>/<name>.xcframework` for cache-hit decisions and shim sidecars | `tools/spm-cache-proxy/Sources/Core/Cache.swift` |
| `Lockfile` (Swift) | Decodes `spm-cache.lock` JSON; models packages with enriched product metadata | `tools/spm-cache-proxy/Sources/Core/Lockfile.swift` |

## Pattern Overview

**Overall:** Two-language pipeline with Ruby orchestration shell + Swift code-generation companion.

**Key Characteristics:**
- Ruby gem owns CLI, project introspection (xcodeproj), lockfile management, and xcodeproj integration
- Swift companion binary (`spm-cache-proxy`) owns Package.swift code generation (umbrella + proxy manifests) and cache-hit lookup
- Ruby calls Swift via `Core::Sh.run` (subprocess) through `ProxyExecutable` — the two languages never share memory
- Fast-path optimization: when lockfile matches live graph and proxy exists, `Installer::Use` skips the entire regenerate cycle
- Data-driven diagnostics registry pattern for `doctor` command
- Polling-based file watcher (mtime+size, no native gem dependency)

## Layers

**CLI Layer:**
- Purpose: Parse argv, dispatch to subcommands via CLAide
- Location: `lib/spm_cache/command.rb`, `lib/spm_cache/command/*.rb`
- Contains: One class per CLI verb (`Use`, `Build`, `Watch`, `Init`, `Doctor`, `Cache`, `Remote`, `Pkg`, `Rollback`, `Off`)
- Depends on: `Installer` classes, `Core::Config`, `Core::Watcher`, `Core::Diagnostics`
- Used by: `bin/spm-cache` entry point

**Installer Layer:**
- Purpose: Full integration pipeline — diff detection, lockfile sync, proxy generation, xcodeproj rewriting, cachemap reporting
- Location: `lib/spm_cache/installer.rb` (base), `lib/spm_cache/installer/use.rb`, `lib/spm_cache/installer/build.rb`
- Contains: `Installer` base class (570+ lines), `Installer::Use` (fast-path override), `Installer::Build`
- Depends on: `Core::DiffDetector`, `Core::Lockfile`, `Core::Config`, `SPM::Package::Proxy`, `Cache::Cachemap`, `xcodeproj` gem
- Used by: `Command::Use`, `Command::Build`

**Core Layer:**
- Purpose: Shared infrastructure — config, lockfile, diff detection, shell execution, diagnostics, watching, error types
- Location: `lib/spm_cache/core/*.rb`
- Contains: `Config` (singleton), `Lockfile`, `DiffDetector`, `Watcher`, `Diagnostics`, `Sh`, error hierarchy
- Depends on: Ruby stdlib, `yaml`, `json`, `open3`
- Used by: All other layers

**SPM Layer:**
- Purpose: Swift Package Manager interactions — proxy orchestration, checkout resolution, build pipeline, `swift package describe` parsing, xcframework assembly
- Location: `lib/spm_cache/spm/**/*.rb`
- Contains: `Package::Proxy`, `Package::ProxyExecutable`, `CheckoutResolver` mixin, `BuildPipeline`, `Desc::Description`, xcframework modules
- Depends on: `Core::Sh`, `Core::Config`, `Core::Log`, Swift toolchain CLI
- Used by: `Installer` layer, `Command::Pkg`

**Swift Companion Layer:**
- Purpose: Package.swift code generation and binary cache lookup — the only Swift code in the project
- Location: `tools/spm-cache-proxy/Sources/`
- Contains: `GenUmbrella` CLI, `GenProxy` CLI, `UmbrellaGenerator`, `ProxyGenerator`, `BinariesCache`, `Lockfile` model, `Cache` model
- Depends on: Swift stdlib, `ArgumentParser`, `Foundation`
- Used by: `SPM::Package::ProxyExecutable` (Ruby shell-out)

## Data Flow

### Primary Request Path (`spm-cache use`)

1. **Entry** — `bin/spm-cache` requires `spm_cache`, calls `SPMCache::Main.run(ARGV)` (`bin/spm-cache:4`)
2. **Load all** — `Main.load_all` recursively requires every `.rb` under `lib/spm_cache/` (`lib/spm_cache/main.rb:10`)
3. **Dispatch** — CLAide routes to `Command::Use#run` (default subcommand) (`lib/spm_cache/command/use.rb:18`)
4. **Installer creation** — `Installer::Use.new(project: project_path)` (`lib/spm_cache/installer/use.rb:30`)
5. **Fast-path check** — `detect_diff` compares `spm-cache.lock` vs live Xcode graph; if empty + proxy Package.swift exists → no-op (`lib/spm_cache/installer/use.rb:18-28`)
6. **Lockfile sync** — Generate/update `spm-cache.lock` from `Package.resolved`; record consumed dependencies per target (`lib/spm_cache/installer.rb:127-165`)
7. **Proxy prepare** — `SPM::Package::Proxy#prepare` runs three phases (`lib/spm_cache/spm/pkg/proxy.rb:27-49`):
   - **gen-umbrella** — Shell-out to `spm-cache-proxy gen-umbrella` → umbrella `Package.swift` with all deps pinned (`lib/spm_cache/spm/pkg/proxy.rb:51-52`)
   - **Enrich lockfile** — Caller block runs `enrich_lockfile_products` (runs `swift package describe` on each checkout, writes real product names/types into lockfile) (`lib/spm_cache/installer.rb:233-282`)
   - **gen-proxy** — Shell-out to `spm-cache-proxy gen-proxy` → per-package proxy `Package.swift` + root proxy + `graph.json` (`lib/spm_cache/spm/pkg/proxy.rb:54-58`)
8. **Xcode integration** — `integrate_proxy_into_project` purges orphaned SPM objects, strips original package refs, adds local proxy ref, rewrites product dependencies (`lib/spm_cache/installer.rb:358-452`)
9. **Cachemap report** — Reads `graph.json`, prints hit/miss/ignored counts (`lib/spm_cache/installer.rb:567-573`)

### `spm-cache watch` Flow (v0.3.0)

1. **Entry** — `Command::Watch#run` finds `.xcodeproj`, creates `Core::Watcher` with `Installer::Use` factory (`lib/spm_cache/command/watch.rb:29-34`)
2. **Initial sync** — `watcher.run` performs initial regeneration then enters poll loop (`lib/spm_cache/core/watcher.rb:42-65`)
3. **Poll loop** — Every `debounce` seconds (default 2), compares mtime+size signatures of `Package.resolved` + `project.pbxproj` (`lib/spm_cache/core/watcher.rb:66-80`)
4. **On change** — Calls `Installer::Use#perform_install` (full regeneration); continues on error, exits on fatal (`lib/spm_cache/core/watcher.rb:86-89`)

### `spm-cache init` Flow (v0.3.0)

1. **Entry** — `Command::Init#run` resolves project, platforms, config, remote backend (`lib/spm_cache/command/init.rb:34-49`)
2. **Config write** — Idempotent diff-merge: loads existing `spm-cache.yml`, merges new values over `DEFAULT_CONFIG`, saves (`lib/spm_cache/command/init.rb:130-145`)
3. **Lockfile seed** — Copies `Package.resolved` → `spm-cache.lock` so first `use` can take the fast path (`lib/spm_cache/command/init.rb:147-156`)
4. **Gitignore** — Appends `spm-cache/` entry if missing (`lib/spm_cache/command/init.rb:162-170`)

### `spm-cache doctor` Flow (v0.3.0)

1. **Entry** — `Command::Doctor#run` loads config, calls `Core::Diagnostics.run_all` (`lib/spm_cache/command/doctor.rb:25-28`)
2. **Registry** — Each registered `Check` runs a callable returning `[:ok|:warn|:fail, message]`; errors captured as `:fail` (`lib/spm_cache/core/diagnostics.rb:38-49`)
3. **Output** — Human-readable `✓/!/✗` report or `--json` payload; exits non-zero on any failure (`lib/spm_cache/command/doctor.rb:31-55`)

### Proxy-Package Mechanism

The proxy package is the core architectural pattern that distinguishes spm-cache from alternatives like Scipio:

1. **Umbrella package** — A temporary `Package.swift` declaring every SPM dependency from the lockfile at its resolved version. Its sole purpose is checkout materialization (`swift package resolve` fetches sources). Generated by Swift `UmbrellaGenerator`.

2. **Per-package proxy** — For each real package, a `Package.swift` is emitted under `spm-cache/packages/proxy/<pkg-slug>/`. On cache hit, it declares a `binaryTarget` pointing at `~/.spm-cache/<config>/<name>.xcframework`. On cache miss, it declares a source shim (`@_exported import RealModule`) and a dependency on the real upstream package. Generated by Swift `ProxyGenerator`.

3. **Root proxy** — A single `Package.swift` at `spm-cache/packages/proxy/Package.swift` that aggregates all per-package proxies as local dependencies and re-exports every library product by its real name.

4. **Xcode integration** — The Ruby installer strips all original `XCRemoteSwiftPackageReference` and `XCSwiftPackageProductDependency` objects from the `.xcodeproj`, adds a single `XCLocalSwiftPackageReference` pointing at the root proxy, and re-creates product dependencies pointing at it. Plugin-only packages and never-cached products are exempted.

**State Management:**
- `Core::Config` is a singleton holding all paths and settings
- `spm-cache.lock` (JSON) is the authoritative snapshot of the SPM graph — written after every successful run, read on the next to detect changes
- `spm-cache.yml` (YAML) holds user configuration (ignore/cache-only lists, remote backend, platforms)
- No database; all state is file-based in the project's `spm-cache/` sandbox directory

## Key Abstractions

**DiffDetector:**
- Purpose: Determines whether the live Xcode SPM graph has changed since the last successful run
- Examples: `lib/spm_cache/core/diff_detector.rb`
- Pattern: Structured diff (added/removed/updated) comparing normalized package identities from `Package.resolved` + `project.pbxproj` against `spm-cache.lock`

**Proxy-Package Triangle (Umbrella → Per-Package → Root):**
- Purpose: Replaces source dependencies with cached binaries at the SwiftPM manifest level without modifying any source code
- Examples: `tools/spm-cache-proxy/Sources/Core/Generator/UmbrellaGenerator.swift`, `tools/spm-cache-proxy/Sources/Core/Generator/ProxyGenerator.swift`
- Pattern: Code generation — Swift structs emit `Package.swift` text; cache-hit = binaryTarget, cache-miss = source shim with `@_exported import`

**Diagnostics Registry:**
- Purpose: Pluggable health-check system for `doctor` command
- Examples: `lib/spm_cache/core/diagnostics.rb`
- Pattern: Registry pattern — `register(name, fix_hint:, &block)` appends `Check` structs; `run_all` maps each to a `Result` struct; errors are caught per-check so one failure never aborts the report

**CheckoutResolver (Mixin):**
- Purpose: Materializes real package sources so `swift package describe` and build can inspect them
- Examples: `lib/spm_cache/spm/checkout_resolver.rb`
- Pattern: Module mixin included into `Installer`; handles `swift package resolve` success/failure and DerivedData checkout fallback

## Entry Points

**`bin/spm-cache` (primary CLI):**
- Location: `bin/spm-cache`
- Triggers: User invocation or CI
- Responsibilities: Adds `lib/` to load path, requires `spm_cache`, calls `SPMCache::Main.run(ARGV)`

**`lib/spm_cache/main.rb` (Ruby entry):**
- Location: `lib/spm_cache/main.rb`
- Triggers: Required by `bin/spm-cache`
- Responsibilities: Recursive autoload of all `.rb` files; delegates to `Command.run(argv)`

**`tools/spm-cache-proxy` (Swift companion):**
- Location: `tools/spm-cache-proxy/Sources/CLI/GenUmbrella.swift`, `tools/spm-cache-proxy/Sources/CLI/GenProxy.swift`
- Triggers: Shell-out from `ProxyExecutable`
- Responsibilities: `gen-umbrella` and `gen-proxy` subcommands for Package.swift generation

**`action/action.yml` (GitHub Actions):**
- Location: `action/action.yml`
- Triggers: CI workflow
- Responsibilities: Thin wrapper — installs gem, runs `spm-cache init` + `spm-cache remote pull/push` for CI cache sharing

## Architectural Constraints

- **Threading:** Ruby single-threaded event loop; `parallel` gem used for concurrent xcframework builds in `BuildPipeline`
- **Global state:** `Core::Config` is a module-level singleton (`@@instance`) — one instance per process at `lib/spm_cache/core/config.rb:28`; mutable `@raw` hash shared across all components
- **Circular imports:** `installer.rb` requires `installer/use.rb` and `installer/rollback.rb` at its tail (line 575-577), while `installer/use.rb` requires `installer.rb` — resolved by Ruby's lazy `require` (file already loaded)
- **Two-language boundary:** Ruby ↔ Swift communication is subprocess-only via `Core::Sh.run`; the Swift binary is an opaque CLI tool with no shared memory or FFI
- **Xcode dependency:** `xcodeproj` gem modifies `.pbxproj` files directly; project must be closed in Xcode during modifications

## Anti-Patterns

### Giant Installer Base Class

**What happens:** `Installer` base class at `lib/spm_cache/installer.rb` is 578 lines and contains lockfile enrichment, product fallback parsing, xcodeproj integration, orphan purging, URL normalization, and plugin detection all in one class.
**Why it's wrong:** High cognitive load; hard to test individual concerns in isolation; `Installer::Use` and `Installer::Build` inherit all of it.
**Do this instead:** Extract enrichment into `Core::LockfileEnricher`, integration into `Xcodeproj::Integration`, and orphan purging into `Xcodeproj::OrphanPurger` modules. The base class should orchestrate calls, not implement them.

### Recursive Require-All Loading

**What happens:** `Main.load_all` globs and requires every `.rb` file recursively (`lib/spm_cache/main.rb:10-13`), including test-only code paths and all subcommands regardless of which is invoked.
**Why it's wrong:** Slower startup; potential for load-order side effects; every file is in memory even for `spm-cache doctor` which needs only `Core::Diagnostics`.
**Do this instead:** Use `autoload` per class/module (already used for `Main` and `VERSION` at `lib/spm_cache.rb:5-6`) or lazy `require` inside each command's `run` method.

## Error Handling

**Strategy:** Custom exception hierarchy with `Core::BaseError < StandardError` and `Core::GeneralError < BaseError` carrying an `exit_status` attribute (`lib/spm_cache/core/error.rb`). Shell commands raise `GeneralError` with bounded failure detail (last 60 lines of stdout+stderr) via `Core::Sh` (`lib/spm_cache/core/sh.rb:57-60`). The `Watcher` catches `StandardError` per-iteration to continue-on-error but re-raises on fatal conditions. The `Diagnostics` registry catches per-check errors and converts to `:fail` results.

**Patterns:**
- Raise `GeneralError` for expected failures (command exit non-zero, file not found)
- Raise `"No .xcodeproj found"` (bare string) for validation failures in commands
- `rescue StandardError` in watcher loop for transient regeneration failures
- `rescue StandardError` in diagnostics for individual check robustness

## Cross-Cutting Concerns

**Logging:** `Core::Log` mixin and `Core::UI.section`/`Core::UI.info`/`Core::UI.warn` for user-facing output; `Core::Sh` supports live-log mode via `Open3.popen3` with thread-based streaming to a `LiveLog` instance for build output

**Validation:** CLAide's `validate!` hook in `Command`; manual `raise` for project detection; `Lockfile#verify!` for data integrity

**Authentication:** No auth in the core tool. Remote backends (`Storage::GitStorage`, `Storage::S3Storage`) handle credentials — git uses SSH keys or token in URL; S3 uses a credentials JSON file path

---

*Architecture analysis: 2026-08-23*
