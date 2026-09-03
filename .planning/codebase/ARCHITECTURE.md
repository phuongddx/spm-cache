---
title: Architecture
focus: arch
mapped_date: 2026-08-31
last_mapped_commit: fdb3a70abe81852ec9310a3ff410341a4adcfa0c
---
<!-- refreshed: 2026-08-31 -->

# Architecture

**Analysis Date:** 2026-08-31

## System Overview

```text
┌────────────────────────────────────────────────────────────────────────┐
│                          CLI Layer (CLAide)                             │
│         `bin/spm-cache` → `lib/spm_cache/main.rb` (--version            │
│         intercepted before CLAide routing)                              │
├──────┬──────┬───────┬───────┬───────┬──────┬──────┬───────┬───────────┤
│ use  │build │ init  │watch  │doctor │cache │remote│  pkg  │rollback   │
└──┬───┴──┬───┴──┬────┴──┬────┴──┬────┴──┬───┴──┬───┴──┬────┴──┬────────┘
   │      │      │       │       │       │      │      │       │
   ▼      │      ▼       ▼       ▼       │      │      ▼       ▼
┌──────────┐ ┌──────────┐ ┌──────────┐     │   ┌──────────┐ ┌──────────┐
│Installer │ │  Core    │ │  Core    │     │   │   Core   │ │Installer │
│  ::Use   │ │ Watcher  │ │Diagnostics│    │   │  Init/   │ │::Rollback│
└────┬─────┘ └──────────┘ └──────────┘     │   │Locator   │ └──────────┘
     │        │              │            │   └──────────┘
     ▼        │              │            ▼
┌──────────────────────────────────────┐  ┌──────────────┐
│   Canonical Host-Graph Locator       │  │  Installer   │
│ `lib/spm_cache/core/                 │  │   (base)     │
│   package_resolved.rb`               │  │  lockfile    │
│  4-tier locate + strict/tolerant     │◄─┤  reconcile,  │
│  pins parsing                        │  │  xcodeproj   │
└──────────────────────────────────────┘  │  rewrite     │
         │                                └──────┬───────┘
         ▼                                       │ delegates to
┌─────────────────────────────────────────────────▼────────────┐
│                  Build Fidelity Pipeline                     │
│  `lib/spm_cache/spm/resolved_graph.rb` (seed host graph into │
│   checkout → build → read back realized pins → write         │
│   `.provenance.json` sidecar)                                │
│  `lib/spm_cache/spm/build_pipeline.rb` + xcframework         │
│  Shared flock: `<project>/.spm-cache-build.lock`             │
└──────────────────────────┬───────────────────────────────────┘
                           │
                           ▼
┌──────────────────────────────────────────────────────────────┐
│              SPM::Package::Proxy (3-phase flow)              │
│  `lib/spm_cache/spm/pkg/proxy.rb` → ProxyExecutable          │
│  (gen-umbrella → enrich lockfile → gen-proxy)                │
└──────────────────────────┬───────────────────────────────────┘
                           │ CLI calls (Core::Sh)
                           ▼
┌──────────────────────────────────────────────────────────────┐
│                Swift companion binary                        │
│  `tools/spm-cache-proxy/Sources/`                            │
│  gen-umbrella / gen-proxy / resolve                          │
│  BinariesCache.hit() = provenance-aware (sidecar pin vs      │
│  lockfile pin, intersection-only)                            │
└──────────────────────────────────────────────────────────────┘
```

## Component Responsibilities

| Component | Responsibility | File |
|-----------|----------------|------|
| `Main` | Entry point; recursive sorted autoload of all `.rb` files; intercepts `--version` before CLAide routing; dispatches to `Command.run` | `lib/spm_cache/main.rb` |
| `Command` (CLAide) | CLI root; defines global options (`--sdk`, `--config`, `--log-dir`, `--merge-slices`, `--no-library-evolution`); default subcommand is `use` | `lib/spm_cache/command.rb` |
| `Command::Use` | Primary command; finds `.xcodeproj`, creates `Installer::Use`, optionally runs inline polling watch loop | `lib/spm_cache/command/use.rb` |
| `Command::Watch` | Delegates to `Core::Watcher` for `Package.resolved` + `project.pbxproj` polling with configurable debounce | `lib/spm_cache/command/watch.rb` |
| `Command::Init` | Bootstraps `spm-cache.yml` + seeded `spm-cache.lock`; interactive or flags-driven; idempotent diff-merge; writes the canonical lockfile shape from the canonical `Package.resolved` | `lib/spm_cache/command/init.rb` |
| `Command::Doctor` | Runs registered diagnostic checks (`Core::Diagnostics`), including `lock_graph_fidelity`; text or `--json` output; non-zero exit on failure | `lib/spm_cache/command/doctor.rb` |
| `Command::Build` | Builds specific targets into xcframeworks via `Installer::Build` + `BuildPipeline` | `lib/spm_cache/command/build.rb` |
| `Command::Cache` | Abstract parent for `list` (per-package fidelity-status column) and `clean` (sidecar orphan sweep) | `lib/spm_cache/command/cache.rb` |
| `Command::Remote` | Abstract parent for `pull`/`push`; creates `Storage::GitStorage` or `Storage::S3Storage` from config | `lib/spm_cache/command/remote.rb` |
| `Command::Pkg` | Abstract parent for `build` subcommand (standalone single-package xcframework build; never seeds the host graph) | `lib/spm_cache/command/pkg.rb` |
| `Installer` (base) | Full integration pipeline: host-graph locate → diff detect → lockfile reconcile → proxy prepare → xcodeproj rewrite → cachemap report | `lib/spm_cache/installer.rb` |
| `Installer::Use` | Fast-path guard (empty diff + proxy exists + version stamp matches) and shared build-lock flock around both branches | `lib/spm_cache/installer/use.rb` |
| `Installer::Build` | Holds the blocking build-lock flock across regenerate + build loop; verifies per-destination slice completeness; seeds host graph into each checkout | `lib/spm_cache/installer/build.rb` |
| `Core::PackageResolved` | Single canonical locator + parser for the host `Package.resolved` (4-tier locate, strict/tolerant pin parsing); every host-graph consumer reads through it | `lib/spm_cache/core/package_resolved.rb` |
| `Core::Config` | Singleton; owns `spm-cache.yml` parsing, sandbox/cache/umbrella/proxy/clones dir paths, build-lock path, ignore/cache-only lists | `lib/spm_cache/core/config.rb` |
| `Core::Lockfile` | Reads/writes `spm-cache.lock` JSON; models packages, products, dependencies, platforms per project | `lib/spm_cache/core/lockfile.rb` |
| `Core::DiffDetector` | Compares live Xcode SPM graph (via `Core::PackageResolved` + pbxproj refs) against lockfile snapshot; produces structured `Diff`; memoizes the run's one `host_graph_path` | `lib/spm_cache/core/diff_detector.rb` |
| `Core::Watcher` | mtime+size polling loop; TERM trap → `Interrupt`; flushes a pending change on shutdown; continue-on-error | `lib/spm_cache/core/watcher.rb` |
| `Core::Diagnostics` | Data-driven check registry (Xcode, Swift, toolchain, cache dir, LE compat, remote connectivity, companion binary + version, `lock_graph_fidelity`) | `lib/spm_cache/core/diagnostics.rb` |
| `Core::Sh` | Shell execution via `Open3`; live-log or capture mode; bounded failure detail (last 60 lines) | `lib/spm_cache/core/sh.rb` |
| `SPM::ResolvedGraph` | Seeds a checkout with the host's resolved graph before build/describe; atomic seed with snapshot + restore; vendored-`.xcodeproj` classification | `lib/spm_cache/spm/resolved_graph.rb` |
| `SPM::BuildPipeline` | Seeds host graph, builds per-destination frameworks, assembles xcframeworks, reads back realized pins, writes `.provenance.json` fidelity sidecars | `lib/spm_cache/spm/build_pipeline.rb` |
| `SPM::Package::Proxy` | Orchestrates the three-phase proxy flow: gen-umbrella → enrich lockfile → gen-proxy | `lib/spm_cache/spm/pkg/proxy.rb` |
| `SPM::Package::ProxyExecutable` | Locates (env var or built binary) and shell-outs to the Swift companion tool | `lib/spm_cache/spm/pkg/proxy_executable.rb` |
| `SPM::CheckoutResolver` | Mixin; resolves umbrella checkouts via `swift package resolve`, falls back to DerivedData copy | `lib/spm_cache/spm/checkout_resolver.rb` |
| `SPM::Buildable` | Single xcodebuild invocation wrapper; forwards `-clonedSourcePackagesDirPath` (shared clone dir) and per-scheme destinations | `lib/spm_cache/spm/build.rb` |
| `SPM::Desc::Description` | Wraps `swift package describe --type json`; models targets, products, dependencies, platform traversal | `lib/spm_cache/spm/desc/desc.rb` |
| `Cache::Cachemap` | Loads `graph.json`; reports cache hit/miss/ignored/excluded/plugin stats per module | `lib/spm_cache/cache/cachemap.rb` |
| `GenUmbrella` (Swift) | ArgumentParser CLI; calls `UmbrellaGenerator` to emit a combined `Package.swift` pinning all deps | `tools/spm-cache-proxy/Sources/CLI/GenUmbrella.swift` |
| `GenProxy` (Swift) | ArgumentParser CLI; calls `ProxyGenerator` to emit per-package proxy `Package.swift` + root proxy + `graph.json` | `tools/spm-cache-proxy/Sources/CLI/GenProxy.swift` |
| `Resolve` (Swift) | ArgumentParser CLI; `Resolver` resolves a package graph and emits per-package metadata JSON | `tools/spm-cache-proxy/Sources/CLI/Resolve.swift` |
| `UmbrellaGenerator` (Swift) | Generates umbrella Package.swift from lockfile; skips plugin-only and transitive-only packages | `tools/spm-cache-proxy/Sources/Core/Generator/UmbrellaGenerator.swift` |
| `ProxyGenerator` (Swift) | Generates per-package proxy Package.swift (binary on provenance-aware cache hit, source shim on miss); root proxy; hands entries to `GraphGenerator`/`MetadataGenerator` | `tools/spm-cache-proxy/Sources/Core/Generator/ProxyGenerator.swift` |
| `BinariesCache` (Swift) | Provenance-aware cache-hit decision: sidecar `pins[identity]` must match the lockfile pin; absent/unparsable sidecar = miss; intersection-only | `tools/spm-cache-proxy/Sources/Core/Cache.swift` |
| `Lockfile` (Swift) | Decodes `spm-cache.lock` JSON; `pinValue` (revision-over-version) feeds the cache-hit comparison | `tools/spm-cache-proxy/Sources/Core/Lockfile.swift` |

## Pattern Overview

**Overall:** Two-language pipeline with Ruby orchestration shell + Swift code-generation companion, unified on a single canonical host-graph source.

**Key Characteristics:**
- Ruby gem owns CLI, project introspection (xcodeproj), lockfile management, and xcodeproj integration
- Swift companion binary (`spm-cache-proxy`) owns Package.swift code generation (umbrella + proxy manifests) and the cache-hit lookup
- Ruby calls Swift via `Core::Sh.run` (subprocess) through `ProxyExecutable` — the two languages never share memory
- **Single canonical locator:** every component that needs the host `Package.resolved` (DiffDetector, lockfile reconciliation, watch signatures, init seeding, doctor) resolves it through `Core::PackageResolved.locate`, so the pin source and the change detector cannot answer with different files
- **Fidelity pipeline:** builds seed the host graph into each checkout, then read back the realized pins and write a `.provenance.json` sidecar recording `host-pinned` / `resolution-incompatible` / `not-graph-pinned`
- **Provenance-aware cache identity:** a cache hit requires the sidecar's recorded pin for that identity to match the current lockfile pin — artifact presence alone is no longer a hit
- **Cross-process mutual exclusion:** `Installer::Use` and `Installer::Build` serialize on one blocking flock at `<project_dir>/.spm-cache-build.lock`
- Fast-path optimization: empty diff + materialized proxy + matching `spm_cache_version` stamp → skip regeneration entirely
- Data-driven diagnostics registry pattern for `doctor`; polling-based file watcher (mtime+size, no native gem dependency)

## Layers

**CLI Layer:**
- Purpose: Parse argv, dispatch to subcommands via CLAide
- Location: `lib/spm_cache/command.rb`, `lib/spm_cache/command/*.rb`
- Contains: One class per CLI verb (`Use`, `Build`, `Watch`, `Init`, `Doctor`, `Cache`, `Remote`, `Pkg`, `Rollback`, `Off`)
- Depends on: `Installer` classes, `Core::Config`, `Core::Watcher`, `Core::Diagnostics`, `Core::PackageResolved`
- Used by: `bin/spm-cache` entry point

**Installer Layer:**
- Purpose: Full integration pipeline — host-graph detection, lockfile reconciliation, proxy generation, xcodeproj rewriting, cachemap reporting, and the flock-serialized build loop
- Location: `lib/spm_cache/installer.rb` (base, 707 lines), `lib/spm_cache/installer/use.rb`, `lib/spm_cache/installer/build.rb`, `lib/spm_cache/installer/rollback.rb`
- Contains: `Installer` base, `Installer::Use` (fast path + `with_build_lock`), `Installer::Build` (flock + slice-completeness + seeding), `Installer::Rollback`
- Depends on: `Core::DiffDetector`, `Core::PackageResolved`, `Core::Lockfile`, `Core::Config`, `SPM::ResolvedGraph`, `SPM::Package::Proxy`, `Cache::Cachemap`, `xcodeproj` gem
- Used by: `Command::Use`, `Command::Build`

**Core Layer:**
- Purpose: Shared infrastructure — config, lockfile, canonical Package.resolved locator, diff detection, shell execution, diagnostics, watching, error types
- Location: `lib/spm_cache/core/*.rb`
- Contains: `Config` (singleton), `Lockfile`, `PackageResolved`, `DiffDetector`, `Watcher`, `Diagnostics`, `Sh`, error hierarchy
- Depends on: Ruby stdlib, `yaml`, `json`, `open3`
- Used by: All other layers

**SPM Layer:**
- Purpose: Swift Package Manager interactions — host-graph seeding, proxy orchestration, checkout resolution, build pipeline, `swift package describe` parsing, xcframework assembly
- Location: `lib/spm_cache/spm/**/*.rb`
- Contains: `ResolvedGraph`, `BuildPipeline`, `Package::Proxy`, `Package::ProxyExecutable`, `CheckoutResolver` mixin, `Buildable`, `Desc::Description`, xcframework modules
- Depends on: `Core::Sh`, `Core::Config`, `Core::PackageResolved`, `Core::Log`, Swift toolchain CLI
- Used by: `Installer` layer, `Command::Pkg`

**Swift Companion Layer:**
- Purpose: Package.swift code generation, metadata resolution, and provenance-aware binary cache lookup
- Location: `tools/spm-cache-proxy/Sources/`
- Contains: `GenUmbrella`, `GenProxy`, `Resolve` CLIs; `UmbrellaGenerator`, `ProxyGenerator`, `GraphGenerator`, `MetadataGenerator`, `BinariesCache`, `Lockfile`, `Resolver`, `Env`
- Depends on: Swift stdlib, `ArgumentParser`, `Foundation`
- Used by: `SPM::Package::ProxyExecutable` (Ruby shell-out)

## Data Flow

### Primary Request Path (`spm-cache use`)

1. **Entry** — `bin/spm-cache` requires `spm_cache`, calls `SPMCache::Main.run(ARGV)`; `--version` is intercepted before CLAide routing (`lib/spm_cache/main.rb:11`)
2. **Dispatch** — CLAide routes to `Command::Use#run` (default subcommand) (`lib/spm_cache/command/use.rb:22`)
3. **Locate host graph** — `Command::Use` and the installer resolve the host `Package.resolved` through the 4-tier canonical locator (`lib/spm_cache/core/package_resolved.rb:19`): tier 1 exact `<project>/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` → tier 2 workspace candidates → tier 3 filtered recursive under the project (`.xcodeproj` components and the `spm-cache` sandbox excluded) → tier 4 parent-directory recursive, taken only by `DiffDetector`
4. **Installer creation** — `Installer::Use.new(project: project_path)`; a single memoized `DiffDetector` (`Installer#host_graph_detector`, `lib/spm_cache/installer.rb:71`) owns the located path for the whole run
5. **Fast-path check** — `detect_diff` compares `spm-cache.lock` vs live graph; `fast_path?` (`lib/spm_cache/installer/use.rb:80`) requires empty diff AND materialized proxy `Package.swift` AND `spm_cache_version` stamp matching the running gem (`current_spm_cache_version?`, `lib/spm_cache/installer/use.rb:97`) — a spm-cache upgrade with an unchanged graph still forces one regeneration
6. **Build lock** — BOTH branches wrap their work in `with_build_lock` (`lib/spm_cache/installer/use.rb:60`): a blocking exclusive flock on `<project_dir>/.spm-cache-build.lock` (`Core::Config#build_lock_path`, `lib/spm_cache/core/config.rb:101`), deferring to any in-flight `Installer::Build`
7. **Lockfile sync + reconcile** (slow path) — `sync_lockfile` (`lib/spm_cache/installer.rb:138`) generates the lockfile from the canonical `Package.resolved` when absent, then `reconcile_lockfile_from_host_graph` (`lib/spm_cache/installer.rb:204`) refreshes `version`/`revision` in place, drops packages absent from the live set (pins UNION pbxproj refs), and appends new ones — self-gated on a non-empty diff and skipped entirely when the host file parses to zero pins while the lock holds remote packages (schema-mismatch guard)
8. **Proxy prepare** — `SPM::Package::Proxy#prepare` runs three phases (`lib/spm_cache/spm/pkg/proxy.rb:26`):
   - **gen-umbrella** — Shell-out to `spm-cache-proxy gen-umbrella` → umbrella `Package.swift` with deps pinned (transitive-only packages pinned only when a revision is held)
   - **Enrich lockfile** — Caller block runs `enrich_lockfile_products` (`swift package describe` per checkout writes real product names/types into the lockfile), with `invalidate_stale_products!` clearing stale `products[]` whenever `spm_cache_version` changed
   - **gen-proxy** — Shell-out to `spm-cache-proxy gen-proxy` → per-package proxy `Package.swift` + root proxy + `graph.json`; cache hits are decided here by `BinariesCache.hit(module:identity:currentPin:)` (`tools/spm-cache-proxy/Sources/Core/Cache.swift:28`)
9. **Xcode integration** — `integrate_proxy_into_project` (`lib/spm_cache/installer.rb:493`) purges orphaned SPM objects by explicit reachability, strips non-exempt package refs, adds the local proxy ref, rewrites product dependencies (plugin-only and never-cached products exempted)
10. **Cachemap report** — `gen_cachemap_viz` (`lib/spm_cache/installer.rb:695`) reads `graph.json`, prints hit/miss counts

### Build + Fidelity Flow (`spm-cache build`)

1. **Acquire build lock** — `Installer::Build#perform_install` (`lib/spm_cache/installer/build.rb:18`) opens a blocking exclusive flock on `<project_dir>/.spm-cache-build.lock` held across `super` (regenerate + checkout resolution) AND the entire build loop (`acquire_build_lock`, `lib/spm_cache/installer/build.rb:68`); released unconditionally in `ensure`
2. **Miss computation** — Cachemap misses are extended with cached-but-slice-incomplete modules (`slice_complete?` verifies the xcframework carries a slice for every requested destination); requested target names are expanded from package identities to their library products
3. **Pin source resolution** — `SPM::ResolvedGraph.source_for` (`lib/spm_cache/spm/resolved_graph.rb:24`) picks the run's single seed source: the umbrella's own already-resolved `Package.resolved` (what the checkouts were materialized from) wins over `host_graph_detector.host_graph_path`; nil means seed nothing (byte-identical to pre-seeding behavior)
4. **Per-target build** — `build_single_target` (`lib/spm_cache/installer/build.rb:157`) passes `resolved_pins_file`, `clones_dir` (`spm-cache/packages/clones`, shared `-clonedSourcePackagesDirPath` so N builds don't each clone the whole graph — measured -40.6% wall-clock / -34% disk in `.planning/phases/07/07-BENCHMARK.md`), and `config` into `SPM::BuildPipeline.run`
5. **Seed** — `BuildPipeline.run` calls `seed_host_graph` (`lib/spm_cache/spm/build_pipeline.rb:244`): vendored-`.xcodeproj` checkouts are classified `not-graph-pinned` and never seeded (xcodebuild ignores their `Package.resolved`); otherwise `ResolvedGraph.seed!` atomically copies the host graph into the checkout and snapshots what was there. The intended pin map is captured from the seed source immediately, never re-read after the build
6. **Build** — `perform_build` runs the per-destination xcodebuild loop (direct xcframework build, scheme build, or prebuilt binaryTarget copy)
7. **Fidelity read-back** — `report_fidelity` (`lib/spm_cache/spm/build_pipeline.rb:102`) reads the checkout's realized `Package.resolved` after the build and diffs it against the intended pin map (intersection-only: identities on one side carry no drift evidence). Empty drift → `host-pinned`; any drift → `resolution-incompatible` (built from source). Unseeded builds preserve an existing sidecar's non-empty pins rather than erasing them
8. **Sidecar write** — `write_provenance_sidecar` (`lib/spm_cache/spm/build_pipeline.rb:220`) writes `<name>.xcframework.provenance.json` (tempfile-then-rename) with exactly `fidelity_status`, `pins`, `spm_cache_version`, `config`, `destinations` — no absolute paths or hostnames, so the sidecar can travel through remote cache backends
9. **Restore guard** — On any failure before success, `ResolvedGraph.restore!` (`lib/spm_cache/spm/resolved_graph.rb:45`) puts the checkout's pre-seed `Package.resolved` back (or removes it if none existed); on success the realized state is left in place for the read-back

### Cache Hit/Miss at Proxy-Generation Time

1. `gen-proxy` runs for each library product; ignored/excluded products are always source
2. `BinariesCache.hit(module:identity:currentPin:)` (`tools/spm-cache-proxy/Sources/Core/Cache.swift:28`) requires: xcframework present AND sidecar present and parsable AND `pins[identity] == currentPin` (revision-over-version via `Lockfile.Package.pinValue`)
3. Identity absent from the sidecar's pins (including empty pins) is NOT drift — it still hits (intersection-only)
4. Absent/unparsable sidecar, or unreadable currentPin while a pin is recorded → miss (fail-safe)
5. Hit → `binaryTarget` proxy declaration; miss → `@_exported import` source shim with a dependency on the real upstream package

### `spm-cache watch` Flow

1. **Entry** — `Command::Watch#run` finds `.xcodeproj`, creates `Core::Watcher` with an `Installer::Use` factory (`lib/spm_cache/command/watch.rb:29`)
2. **Initial sync** — `watcher.run` (`lib/spm_cache/core/watcher.rb:48`) installs a TERM trap (raises `Interrupt`), performs initial regeneration, then re-snapshots signatures so the regenerated files themselves don't trigger a spurious second run
3. **Poll loop** — Every `debounce` seconds (default 2), compares mtime+size signatures of the canonical `Package.resolved` (via `Core::PackageResolved.locate`) + `project.pbxproj`
4. **On change** — Calls `Installer::Use#perform_install` (which blocks on the build lock if a build is in flight); errors are logged and the loop continues
5. **Shutdown** — `Interrupt` masks further signals and calls `flush_pending_event` (`lib/spm_cache/core/watcher.rb:101`) so a change landing inside the final poll window is regenerated before exit 0

### `spm-cache init` Flow

1. **Entry** — `Command::Init#run` resolves project, platforms, config, remote backend (`lib/spm_cache/command/init.rb:39`)
2. **Config write** — Idempotent diff-merge of `spm-cache.yml` over `DEFAULT_CONFIG`
3. **Lockfile seed** — Locates the host graph via the canonical locator, parses pins tolerantly (malformed file → warn + empty skeleton, never abort), and writes the canonical lockfile shape (`packages`/`dependencies`/`platforms`, mirroring `generate_lockfile_from_resolved` field-for-field) (`lib/spm_cache/command/init.rb:145`)
4. **Gitignore** — Appends `spm-cache/` entry if missing

### `spm-cache doctor` Flow

1. **Entry** — `Command::Doctor#run` loads config, calls `Core::Diagnostics.run_all` (`lib/spm_cache/command/doctor.rb:25`)
2. **Registry** — Each registered `Check` returns `[:ok|:warn|:fail, message]`; errors captured per-check as `:fail`; the `companion_binary` check reports the Swift tool's self-reported version (drift made visible, never gated on)
3. **`lock_graph_fidelity` check** — `lib/spm_cache/core/diagnostics.rb:64`: locates the host graph with the SAME locator the reconciler uses, compares lock entries against host pins by identity key and revision-over-version value, and warns on presence or value drift (a zero-pin host parse alongside a populated lock is reported as suspected schema mismatch, not drift)
4. **Output** — Text report with fix hints or `--json`; exits non-zero on any failure

### Proxy-Package Mechanism

The proxy package is the core architectural pattern that distinguishes spm-cache from alternatives like Scipio:

1. **Umbrella package** — A temporary `Package.swift` declaring every SPM dependency from the lockfile at its resolved version. Its sole purpose is checkout materialization (`swift package resolve` fetches sources). Generated by Swift `UmbrellaGenerator`; transitive-only packages are declared only when their exact revision is held by the reconciled lock, so the isolated resolve can't float them into conflict.
2. **Per-package proxy** — For each real package, a `Package.swift` is emitted under `spm-cache/packages/proxy/<pkg-slug>/`. On provenance-aware cache hit, it declares a `binaryTarget` pointing at `~/.spm-cache/<config>/<name>.xcframework`. On cache miss, it declares a source shim (`@_exported import RealModule`) and a dependency on the real upstream package. Generated by Swift `ProxyGenerator`.
3. **Root proxy** — A single `Package.swift` at `spm-cache/packages/proxy/Package.swift` that aggregates all per-package proxies as local dependencies and re-exports every library product by its real name.
4. **Xcode integration** — The Ruby installer purges orphaned SPM objects, strips all non-exempt `XCRemoteSwiftPackageReference`/`XCSwiftPackageProductDependency` objects from the `.xcodeproj`, adds a single `XCLocalSwiftPackageReference` pointing at the root proxy, and re-creates product dependencies pointing at it. Plugin-only packages and never-cached products are exempted by product name.

**State Management:**
- `Core::Config` is a singleton holding all paths and settings
- `spm-cache.lock` (JSON) is the authoritative snapshot of the SPM graph — reconciled from the canonical host graph on every slow-path run, stamped with `spm_cache_version` per project
- `spm-cache.yml` (YAML) holds user configuration (ignore/cache-only lists, remote backend, platforms)
- `<name>.xcframework.provenance.json` sidecars in the cache dir attest to how each binary was produced (fidelity status + pins + version + config + destinations)
- `<project_dir>/.spm-cache-build.lock` is the cross-process build mutex (deliberately outside the sandbox so `recreate_dirs`' `rm_rf` can never delete a live flock target)
- No database; all state is file-based

## Key Abstractions

**Core::PackageResolved (Canonical Locator):**
- Purpose: The one answer to "where is the host's `Package.resolved` and what does it say" — the pin source and every change detector must agree on the same file
- Examples: `lib/spm_cache/core/package_resolved.rb`
- Pattern: Tiered locator (canonical path → workspace → filtered recursive → filtered parent, DiffDetector-only) with strict `pins` (raises on malformed) vs tolerant `pins_or_nil` (nil = absent/unreadable, `[]` = genuinely empty — conflating them would erase the lock); mtime only ever breaks ties within a tier

**DiffDetector:**
- Purpose: Determines whether the live Xcode SPM graph has changed since the last successful run
- Examples: `lib/spm_cache/core/diff_detector.rb`
- Pattern: Structured diff (added/removed/updated) comparing normalized identity keys (`DiffDetector.identity_key` — scheme-agnostic, `.git`-stripping, `local:`/`name:` fallbacks) from the canonical `Package.resolved` + pbxproj union against `spm-cache.lock`; the located path is memoized once per run so the reconciler reads the same answer

**Proxy-Package Triangle (Umbrella → Per-Package → Root):**
- Purpose: Replaces source dependencies with cached binaries at the SwiftPM manifest level without modifying any source code
- Examples: `tools/spm-cache-proxy/Sources/Core/Generator/UmbrellaGenerator.swift`, `tools/spm-cache-proxy/Sources/Core/Generator/ProxyGenerator.swift`
- Pattern: Code generation — Swift structs emit `Package.swift` text; cache-hit = binaryTarget, cache-miss = source shim with `@_exported import`

**Provenance Sidecar (Fidelity Attestation):**
- Purpose: Records how each cached xcframework was produced so cache identity is pin-aware end to end
- Examples: `lib/spm_cache/spm/build_pipeline.rb` (`report_fidelity`, `write_provenance_sidecar`), consumer `tools/spm-cache-proxy/Sources/Core/Cache.swift` (`hit`)
- Pattern: Fixed five-field JSON (`fidelity_status`, `pins`, `spm_cache_version`, `config`, `destinations`) written atomically next to the artifact; read back by the Swift cache-hit decision and `cache list`; swept by `cache clean` so a sidecar never outlives its xcframework

**SPM::ResolvedGraph (Seed/Restore):**
- Purpose: Makes per-package builds resolve the same transitive versions the host app resolved, instead of fresh unbounded ranges from the package's own manifest
- Examples: `lib/spm_cache/spm/resolved_graph.rb`
- Pattern: Verbatim atomic copy with snapshot; exact restore on failure; vendored-`.xcodeproj` checkouts are classified rather than seeded

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
- Responsibilities: Recursive sorted autoload of all `.rb` files; intercepts `--version` (prints `SPMCache::VERSION`, bypassing CLAide); delegates to `Command.run(argv)`

**`tools/spm-cache-proxy` (Swift companion):**
- Location: `tools/spm-cache-proxy/Sources/CLI/GenUmbrella.swift`, `tools/spm-cache-proxy/Sources/CLI/GenProxy.swift`, `tools/spm-cache-proxy/Sources/CLI/Resolve.swift`
- Triggers: Shell-out from `ProxyExecutable`
- Responsibilities: `gen-umbrella` and `gen-proxy` subcommands for Package.swift generation; `resolve` for graph metadata; `--version` self-reports `proxyVersion` (kept in lockstep with the repo `VERSION` file at release)

**`.github/workflows/update-tap.yml` (release automation):**
- Location: `.github/workflows/update-tap.yml`
- Triggers: Release tag push
- Responsibilities: Rewrites the Homebrew formula in `phuongddx/homebrew-spm-cache` via a write-access deploy key (repo secret `TAP_DEPLOY_KEY`), then a verification job installs the published formula and checks the version

**`action/action.yml` (GitHub Actions):**
- Location: `action/action.yml`
- Triggers: CI workflow
- Responsibilities: Thin wrapper — installs gem, runs `spm-cache init` + `spm-cache remote pull/push` for CI cache sharing

## Architectural Constraints

- **Threading:** Ruby single-threaded event loop; `parallel` gem used for concurrent xcframework builds in `BuildPipeline`
- **Global state:** `Core::Config` is a module-level singleton (`@@instance`) — one instance per process at `lib/spm_cache/core/config.rb:38`; mutable `@raw` hash shared across all components
- **Cross-process serialization:** `Installer::Use` and `Installer::Build` mutually exclude on one blocking exclusive flock at `Config#build_lock_path` (`<project_dir>/.spm-cache-build.lock`, deliberately outside `sandbox_dir` so `recreate_dirs` cannot delete a live lock file); the fast path takes the lock too because it still touches the sandbox via `gen_cachemap_viz`
- **Single-locator invariant:** every host-graph consumer reads the path answered by `Core::PackageResolved.locate`; a second independent lookup (e.g. in the doctor check or the build loop) must go through the memoized `DiffDetector#host_graph_path` or the same class method, never a fresh `Dir.glob`
- **Atomic writes:** sidecar writes and seed writes are tempfile-then-rename (`ResolvedGraph.atomic_write`, `write_provenance_sidecar`), so a crash never leaves truncated JSON for readers
- **Circular imports:** `installer.rb` requires `installer/build.rb`, `installer/use.rb`, and `installer/rollback.rb` at its tail (lines 704-706), while `installer/use.rb` requires `installer.rb` — resolved by Ruby's lazy `require` (file already loaded)
- **Two-language boundary:** Ruby ↔ Swift communication is subprocess-only via `Core::Sh.run`; the Swift binary is an opaque CLI tool with no shared memory or FFI
- **Xcode dependency:** `xcodeproj` gem modifies `.pbxproj` files directly; project must be closed in Xcode during modifications

## Anti-Patterns

### Giant Installer Base Class

**What happens:** `Installer` base class at `lib/spm_cache/installer.rb` is 707 lines and contains lockfile generation/reconciliation, product enrichment with fallback parsing, xcodeproj integration, orphan purging, URL normalization, and plugin detection all in one class.
**Why it's wrong:** High cognitive load; hard to test individual concerns in isolation; `Installer::Use`, `Installer::Build`, and `Installer::Rollback` inherit all of it.
**Do this instead:** Extract reconciliation into a dedicated reconciler object, enrichment into `Core::LockfileEnricher`, integration into `Xcodeproj::Integration`, and orphan purging into `Xcodeproj::OrphanPurger` modules. The base class should orchestrate calls, not implement them.

### Recursive Require-All Loading

**What happens:** `Main.load_all` globs and requires every `.rb` file recursively, sorted (`lib/spm_cache/main.rb:16-21`), including all subcommands regardless of which is invoked.
**Why it's wrong:** Slower startup; potential for load-order side effects; every file is in memory even for `spm-cache doctor` which needs only `Core::Diagnostics`.
**Do this instead:** Use `autoload` per class/module (already used for `Main` and `VERSION` at `lib/spm_cache.rb:5-6`) or lazy `require` inside each command's `run` method (several commands already do this, e.g. `lib/spm_cache/command/use.rb:23`).

## Error Handling

**Strategy:** Custom exception hierarchy with `Core::BaseError < StandardError` and `Core::GeneralError < BaseError` carrying an `exit_status` attribute (`lib/spm_cache/core/error.rb`). Shell commands raise `GeneralError` with bounded failure detail (last 60 lines of stdout+stderr) via `Core::Sh` (`lib/spm_cache/core/sh.rb`). The `Watcher` catches `StandardError` per-iteration to continue-on-error, converts TERM to `Interrupt`, and flushes a pending change during shutdown. The `Diagnostics` registry catches per-check errors and converts to `:fail` results.

**Patterns:**
- Raise `GeneralError` for expected failures (command exit non-zero, file not found)
- Raise `"No .xcodeproj found"` (bare string) for validation failures in commands
- Fail-safe tolerance at metadata boundaries: `pins_or_nil`/`existing_sidecar_pins`/`fidelity_status_for` return nil/sentinel on unreadable input instead of raising, while `Core::PackageResolved.pins` stays strict where silence would seed a wrong lock (`generate_lockfile_from_resolved`)
- Post-success bookkeeping never masks the success: `report_fidelity`/`write_provenance_sidecar` rescue to warnings because the xcframework already built — a metadata failure must not be mistaken for a build failure by `ignore_build_errors?` handling
- `ensure`-guarded restore: a seeded checkout is restored on any build failure or interrupt, left realized on success

## Cross-Cutting Concerns

**Logging:** `Core::Log` mixin and `Core::UI.section`/`Core::UI.info`/`Core::UI.warn` for user-facing output; `Core::Sh` supports live-log mode via `Open3.popen3` with thread-based streaming to a `LiveLog` instance for build output

**Validation:** CLAide's `validate!` hook in `Command`; manual `raise` for project detection; `Lockfile#verify!` for data integrity; doctor's `lock_graph_fidelity` cross-checks lock vs host graph with fix hints

**Authentication:** No auth in the core tool. Remote backends (`Storage::GitStorage`, `Storage::S3Storage`) handle credentials — git uses SSH keys or token in URL; S3 uses a credentials JSON file path. The tap-update workflow authenticates to the formula repository with the `TAP_DEPLOY_KEY` deploy-key secret

---

*Architecture analysis: 2026-08-31*
