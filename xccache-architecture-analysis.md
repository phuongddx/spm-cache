# xccache — Deep Architecture Analysis

> **Repository:** [trinhngocthuyen/xccache](https://github.com/trinhngocthuyen/xccache)  
> **Version:** 1.0.5 · **License:** MIT · **Language:** Ruby 99.6% + Makefile 0.4%  
> **Author:** Thuyen Trinh (Chris) · **Stars:** 71 · **Forks:** 10 · **Commits:** 190  
> **Analysis Date:** 2026-07-11

---

## Executive Summary

**xccache** is a Ruby gem CLI tool that caches Swift Package Manager (SPM) dependencies in Xcode projects by prebuilding them into `.xcframework` binaries. It fills a critical gap in the iOS build caching ecosystem — all major caching tools (cocoapods-binary-cache, Rugby, XCRemoteCache) lack SPM support. The tool uses an innovative **proxy package architecture** that swaps between source code and prebuilt binaries at the SPM manifest level, with automatic cache-fallback on miss. It supports local cache, remote cache (Git + S3), Swift macros, per-configuration caching, and includes a Cytoscape.js-based dependency graph visualization.

---

## 1. Architecture Overview

### 1.1 High-Level Component Diagram

```
┌──────────────────────────────────────────────────────────────────────┐
│                          Xcode Project                                │
│  ┌──────────┐    ┌──────────────────────────────────────────────┐    │
│  │ .xcodeproj│───▶│  xccache Proxy Package (xccache/packages/    │    │
│  │  (targets)│    │  proxy/Package.swift)                        │    │
│  └──────────┘    │    ├── .proxies/  ←── symlinked source        │    │
│                  │    │   ├── Alamofire/Package.swift (binaryTarget) │ │
│                  │    │   └── SwiftyBeaver/Package.swift         │    │
│                  │    └── .build/artifacts/ ←── xcframeworks     │    │
│                  └──────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────────┘
         ▲                              ▲
         │ xcodeproj gem                │ xccache-proxy (Swift binary)
         │                              │
┌────────┴──────────────────────────────┴──────────────────────────────┐
│                        xccache Ruby Gem                               │
│                                                                       │
│  ┌─────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌─────────┐ │
│  │ Command │  │Installer │  │   SPM    │  │  Storage │  │  Cache  │ │
│  │  (CLI)  │  │(orch.)   │  │(builder) │  │(remote)  │  │(cachemap)│ │
│  └────┬────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬────┘ │
│       │            │             │             │             │       │
│  ┌────┴────────────┴─────────────┴─────────────┴─────────────┴────┐  │
│  │                         Core Layer                              │  │
│  │  Config │ Lockfile │ Cacheable │ Git │ Sh(shell) │ LiveLog      │  │
│  │  Syntax(JSON/YAML) │ Hash │ Parallel │ Error │ System           │  │
│  └─────────────────────────────────────────────────────────────────┘  │
│                                                                       │
│  Dependencies: claide · xcodeproj · parallel · tty-cursor · tty-screen│
└───────────────────────────────────────────────────────────────────────┘
         │                              │
         ▼                              ▼
   ┌──────────┐              ┌──────────────────┐
   │ Git Repo │              │   S3 Bucket      │
   │ (remote  │              │ (remote cache)   │
   │  cache)  │              └──────────────────┘
   └──────────┘
```

### 1.2 Directory Structure

```
xccache/
├── bin/xccache                          # CLI entry point (3 lines)
├── lib/
│   ├── xccache.rb                       # Module root (ROOT, LIBEXEC)
│   └── xccache/
│       ├── main.rb                      # Auto-loader: requires all sibling .rb
│       ├── command.rb                   # Base CLI (CLAide) + option parsing
│       ├── command/                     # Subcommands (CLAide pattern)
│       │   ├── base.rb                  # Shared options: --sdk, --config, --verbose
│       │   ├── build.rb                 # xccache build [TARGETS]
│       │   ├── use.rb                   # xccache use (default)
│       │   ├── off.rb                   # xccache off (disable cache)
│       │   ├── rollback.rb              # xccache rollback
│       │   ├── cache.rb                 # xccache cache [list|clean]
│       │   ├── pkg.rb                   # xccache pkg [build|checksum|...]
│       │   └── remote.rb                # xccache remote [push|pull]
│       ├── core.rb                      # Auto-loader
│       ├── core/
│       │   ├── config.rb                # Singleton config (xccache.yml → ~/.xccache/)
│       │   ├── cacheable.rb             # @_cache memoization mixin
│       │   ├── lockfile.rb              # xccache.lock (JSON): pkgs, deps, platforms
│       │   ├── git.rb                   # Git wrapper
│       │   ├── sh.rb                    # Shell execution with live_log
│       │   ├── live_log.rb              # TTY-aware live log display
│       │   ├── hash.rb                  # Deep hash utilities
│       │   ├── parallel.rb              # Parallel execution wrapper
│       │   ├── log.rb                   # Logging utilities
│       │   ├── system.rb                # System info (tmpdir, etc.)
│       │   ├── error.rb                 # Custom error types
│       │   └── syntax/                  # YAML/JSON representable base classes
│       ├── installer.rb                 # Base installer (orchestrates install pipeline)
│       ├── installer/
│       │   ├── build.rb                 # Build workflow (swift build → xcframework)
│       │   ├── use.rb                   # Use workflow (swap source→binary)
│       │   ├── rollback.rb              # Rollback workflow (binary→source)
│       │   └── integration.rb           # Xcode project integration mixin
│       ├── spm.rb                       # Auto-loader
│       ├── spm/
│       │   ├── build.rb                 # Buildable base (swift build wrapper)
│       │   ├── desc.rb                  # Package description loader
│       │   ├── desc/                    # SPM manifest parsing
│       │   │   ├── base.rb, desc.rb     # Package.swift descriptor
│       │   │   ├── target.rb            # Target descriptor
│       │   │   ├── product.rb           # Product descriptor
│       │   │   └── dep.rb               # Dependency descriptor
│       │   ├── pkg.rb                   # Package model loader
│       │   ├── pkg/                     # Package implementations
│       │   │   ├── base.rb              # Base Pkg (umbrella, proxy)
│       │   │   ├── proxy.rb             # Proxy Pkg (rewrites manifests)
│       │   │   └── proxy_executable.rb  # Calls xccache-proxy Swift binary
│       │   ├── xcframework.rb           # Auto-loader
│       │   ├── xcframework/             # xcframework builder
│       │   │   ├── xcframework.rb       # xcodebuild -create-xcframework
│       │   │   ├── slice.rb             # Framework slice (swift build → .framework)
│       │   │   └── metadata.rb          # Cache metadata (checksums, SDK triples)
│       │   ├── macro.rb                 # Swift macro support
│       │   └── mixin.rb                 # PkgMixin shared across Installer
│       ├── storage.rb                   # Auto-loader
│       ├── storage/
│       │   ├── base.rb                  # Abstract Storage (no-op warnings)
│       │   ├── git.rb                   # GitStorage: push/pull to git repo
│       │   └── s3.rb                    # S3Storage: push/pull via aws s3 sync
│       ├── cache/
│       │   └── cachemap.rb              # Dependency graph → JSON (Cytoscape.js)
│       ├── swift/
│       │   └── sdk.rb                   # SDK triple resolution (platform→triple)
│       ├── utils/                       # Utility modules
│       ├── xcodeproj/                   # Xcodeproj gem extensions
│       └── assets/templates/            # Template files (xccache.yml)
├── tools/xccache-proxy/                 # Git submodule: Swift binary
├── docs/                                # Extensive documentation
│   ├── overview.md, getting-started.md
│   ├── under-the-hood/
│   │   ├── packaging-as-xcframework.md
│   │   ├── ensuring-bundle-module.md
│   │   ├── macro-as-binary.md
│   │   └── proxy-packages.md
│   ├── case-study-kickstarter.md
│   └── troubleshooting.md
├── examples/                            # Example projects
├── xccache.gemspec                      # Gem specification
├── Gemfile, Gemfile.lock                # Ruby dependencies
├── Makefile                             # Build: install, format, test, proxy.build
└── VERSION                              # 1.0.5
```

---

## 2. Core Architecture Patterns

### 2.1 Proxy Package Architecture (The Key Innovation)

The central design pattern is **proxy packages** — a mechanism that allows seamless switching between source and prebuilt binaries without modifying original SPM packages.

```
Project Dependency Tree (original):
  MyApp
  └── Moya (source)
       └── Alamofire (source: git remote)

Project Dependency Tree (with xccache):
  MyApp
  └── xccache-proxy (Package.swift injected into project)
       └── .proxies/
            ├── Moya/Package.swift      → .binaryTarget(path: "...xcframework")
            │   └── src → symlink to checkout
            └── Alamofire/Package.swift  → .binaryTarget(path: "...xcframework")
                └── src → symlink to checkout
```

**How it works:**

1. **Umbrella Package** (`xccache/packages/umbrella/`): A special SPM package that resolves ALL dependencies from source, creating a `.build/checkouts/` with full source trees.

2. **Proxy Package** (`xccache/packages/proxy/`): For each dependency, a proxy `Package.swift` is generated that:
   - Replaces remote git dependencies with local `path:` references to sibling proxy packages
   - Replaces source `targets` with `.binaryTarget(path: "...xcframework")` when cache exists
   - Symlinks `src/` to the umbrella's checkouts for source fallback

3. **Cache Hit/Miss Logic:**
   - Cache hit: proxy manifest uses `binaryTarget` → Xcode uses prebuilt `.xcframework`
   - Cache miss: proxy manifest uses source targets (symlinked) → Xcode compiles from source
   - **Automatic fallback** — no manual intervention needed

### 2.2 Installer Pipeline (Orchestrator Pattern)

The `Installer` base class orchestrates the full installation pipeline:

```
perform_install()
  ├── verify_projects!()              # Ensure .xcodeproj exists
  ├── recreate_config_dirs()          # Clean & recreate sandbox dirs
  ├── migrate_umbrella_to_proxy()     # One-time migration from v1→v2
  ├── ensure_file!(xccache.yml)       # Generate config if missing
  ├── sync_lockfile()                 # Scan project → update xccache.lock
  │   ├── Scan all targets' SPM deps
  │   ├── Merge into lockfile JSON
  │   └── verify!() unknown deps
  ├── proxy_pkg.prepare()             # Resolve dependencies via umbrella
  │
  ├── [Subclass hook: build() or replace_binaries()]
  │
  ├── gen_supporting_files()          # Generate xcconfigs, metadata
  ├── add_xccache_refs_to_project()   # Add proxy Package.swift to .xcodeproj
  ├── inject_xcconfig_to_project()    # Inject xcconfig for macro support
  └── gen_cachemap_viz()              # Generate dependency graph JSON
```

### 2.3 CLI Architecture (CLAide-based)

The CLI uses [CLAide](https://github.com/CocoaPods/CLAide) — the same framework used by CocoaPods:

```
xccache (abstract)
├── use (default)     → Installer::Use    → replace_binaries_for_project()
├── build [TARGETS]   → Installer::Build  → build(targets) + gen_proxy()
├── off               → Disable cache     → remove proxy from project
├── rollback          → Installer::Rollback → binary→source
├── cache (abstract)
│   ├── list          → List cached packages
│   └── clean         → Clean cache
├── pkg (abstract)
│   ├── build         → Build single package to xcframework
│   ├── checksum      → Compute checksum
│   └── ...
└── remote (abstract)
    ├── push          → Storage::GitStorage or S3Storage
    └── pull          → Pull from remote
```

### 2.4 Cacheable Mixin (Memoization)

A Ruby metaprogramming pattern for transparent memoization:

```ruby
module Cacheable
  def cacheable(*method_names)
    method_names.each do |method_name|
      # Creates a prepended module that intercepts calls
      # Caches results by method_name + args hash
      @_cache[method_name][args.hash | kwargs.hash] ||= super_method.call(...)
    end
  end
end
```

Used throughout the codebase (e.g., `Lockfile#pkgs`, `Config#projects`) to avoid repeated expensive operations like file I/O and SPM resolution.

### 2.5 Lockfile System

`xccache.lock` is a JSON file analogous to `Podfile.lock` or `Package.resolved`:

```json
{
  "MyApp.xcodeproj": {
    "packages": [
      { "repositoryURL": "https://github.com/Alamofire/Alamofire.git" },
      { "path_from_root": "LocalPackages/core-utils" }
    ],
    "dependencies": {
      "MyApp": ["Alamofire/Alamofire", "core-utils/DebugKit"]
    },
    "platforms": { "ios": "15.0" }
  }
}
```

- Tracks every package + its product dependencies per target
- Detects unknown product dependencies (packages not properly added to project)
- Used for cache validation and proxy package generation

---

## 3. Build Pipeline (Source → xcframework)

### 3.1 Framework Slice Creation

```
swift build --target Alamofire --sdk iphonesimulator
  → .build/debug/Alamofire.build/*.o
  → .build/debug/Modules/Alamofire.swiftmodule/

libtool -static -o Alamofire.framework/Alamofire *.o
  → Static library binary

Copy:
  .build/debug/Alamofire.build/*.swiftinterface → Modules/
  .build/debug/Modules/*.swiftmodule            → Modules/
  Headers                                       → Headers/
  Resources (*.bundle)                          → framework root
  module.modulemap (generated)                  → Modules/
```

### 3.2 xcframework Assembly

```bash
xcodebuild -create-xcframework   -framework arm64-apple-ios-simulator/Alamofire.framework   -framework arm64-apple-ios/Alamofire.framework   -output Alamofire.xcframework
```

### 3.3 Library Evolution Support

For Swift library evolution (stable ABI across compiler versions):

```
-Xswiftc -enable-library-evolution
-Xswiftc -alias-module-names-in-module-interface
-Xswiftc -emit-module-interface
-Xswiftc -no-verify-emitted-module-interface
```

This is a workaround for [swift#64669](https://github.com/swiftlang/swift/issues/64669).

### 3.4 Swift Macro Support

Macros require special handling because they're compiler plugins:
- Built as separate macro targets
- Stored with `.macro` extension alongside `.xcframework`
- Injected via `.xcconfig` files into Xcode build settings

---

## 4. Storage Backends

### 4.1 Local Cache

Default location: `~/.xccache/{debug|release}/`

```
~/.xccache/debug/
├── Alamofire.xcframework/
├── SwiftyBeaver.xcframework/
├── Alamofire.macro/           # Swift macros
└── metadata/
    └── Alamofire.json         # Checksum + SDK info
```

### 4.2 Git Storage

- Uses a dedicated git repository as remote cache
- `push`: `git add . && git commit && git push`
- `pull`: `git fetch --depth 1 && git checkout FETCH_HEAD`
- Handles remote URL changes gracefully (add vs set-url)
- Shallow clone for efficiency

### 4.3 S3 Storage

- Uses `aws s3 sync` with `--exact-timestamps --delete`
- Credentials via `~/.xccache/s3.creds.json`:
  ```json
  { "access_key_id": "...", "secret_access_key": "..." }
  ```
- Validates `awscli` installation at runtime
- Syncs only `.xcframework` and `.macro` files

### 4.4 Storage Polymorphism

```ruby
# Base class — no-op with warning
class Storage
  def pull; print_warnings; end
  def push; print_warnings; end
end

# GitStorage and S3Storage override pull/push
```

Configured in `xccache.yml`:
```yaml
remote:
  debug:
    type: git
    remote: git@github.com:team/ios-cache.git
    branch: main
  release:
    type: s3
    uri: s3://my-bucket/ios-cache/
```

---

## 5. Cache Validation Model

### 5.1 Checksum-Based

Each cached xcframework is associated with metadata containing:

```
metadata/Alamofire.json:
{
  "checksum": "sha256:abc123...",
  "sdk_triples": ["arm64-apple-ios", "arm64-apple-ios-simulator"],
  "config": "debug"
}
```

On cache use:
1. Compute current checksum of the package source
2. Compare with stored checksum
3. Mismatch → cache miss → fallback to source

### 5.2 Per-Configuration Caching

Separate cache directories for Debug vs Release:
- `~/.xccache/debug/` — Debug builds (faster compilation, no optimization)
- `~/.xccache/release/` — Release builds (optimized)

### 5.3 Ignore Lists

`xccache.yml` supports:
- `ignore: ["PackageName*"]` — glob patterns for packages to never cache
- `ignore_local: true` — skip all local packages
- `ignore_build_errors: true` — continue even if some packages fail to build

---

## 6. Dependency Graph & Relationships

### 6.1 Internal Dependencies (Ruby Gems)

| Gem | Purpose | Criticality |
|-----|---------|-------------|
| `claide` | CLI framework (commands, options, help) | 🔴 Hard — CLI won't work without it |
| `xcodeproj` (≥1.26.0) | Read/write `.xcodeproj` files | 🔴 Hard — project integration |
| `parallel` | Parallel build execution | 🟡 Soft — performance only |
| `tty-cursor` | Terminal cursor control | 🟡 Soft — cosmetic |
| `tty-screen` | Terminal size detection | 🟡 Soft — cosmetic |

### 6.2 External Dependencies

| Dependency | Purpose |
|------------|---------|
| `xccache-proxy` (Swift submodule) | Swift binary that generates proxy Package.swift manifests |
| `swift` toolchain | `swift build` for compilation |
| `xcodebuild` | `-create-xcframework` for final assembly |
| `libtool` | Static library creation from .o files |
| `awscli` (optional) | S3 remote cache sync |
| `git` | Remote cache via git repo |
| `Cytoscape.js` | Cachemap visualization (HTML/JS) |

### 6.3 Data Flow

```
User runs: xccache use
          │
          ▼
    ┌──────────┐    reads     ┌──────────────┐
    │ xccache  │─────────────▶│ xccache.yml  │ (config)
    │  .lock   │◀─────────────│              │
    └────┬─────┘    writes    └──────────────┘
         │
         │ reads project
         ▼
    ┌──────────┐
    │*.xcodeproj│──▶ targets, SPM deps, platforms
    └──────────┘
         │
         ▼
    ┌──────────────┐    swift build    ┌────────────────┐
    │ umbrella pkg │──────────────────▶│ .build/checkouts│
    │ (resolve)    │                   │  (source code)  │
    └──────┬───────┘                   └────────┬───────┘
           │                                    │
           │ xccache-proxy (Swift)              │ symlink
           ▼                                    ▼
    ┌──────────────┐                   ┌────────────────┐
    │ proxy pkg    │◀──────────────────│ .proxies/      │
    │ (Package.swift)                  │  (manifests)   │
    └──────┬───────┘                   └────────────────┘
           │
           │ binaryTarget or source
           ▼
    ┌──────────────┐
    │ Xcode builds │
    │ the project  │
    └──────────────┘
```

---

## 7. Design Patterns & Code Organization

### 7.1 Patterns Identified

| Pattern | Where | Purpose |
|---------|-------|---------|
| **Proxy** | `spm/pkg/proxy.rb` | Swap source↔binary transparently |
| **Strategy** | `storage/{base,git,s3}.rb` | Pluggable remote cache backends |
| **Template Method** | `installer.rb` → `perform_install` | Subclasses (Build, Use, Rollback) implement hook |
| **Singleton** | `Config.instance` | Global config access |
| **Mixin** | `Cacheable`, `PkgMixin`, `IntegrationMixin` | Shared behavior via Ruby modules |
| **Command** | `command/*.rb` (CLAide) | CLI subcommand dispatch |
| **Auto-loader** | `Dir["*.rb"].each { require }` | Convention over configuration |

### 7.2 Convention over Configuration

The codebase heavily uses Ruby's `Dir[]` glob auto-loading:

```ruby
# lib/xccache/main.rb
Dir["#{__dir__}/*.rb"].sort.each { |f| require f unless f == __FILE__ }

# lib/xccache/core.rb
Dir["#{__dir__}/#{File.basename(__FILE__, '.rb')}/*.rb"].sort.each { |f| require f }
```

This means adding a new file to a directory automatically loads it — no manual `require` statements. The convention is:
- `lib/xccache/command/*.rb` → all subcommands
- `lib/xccache/spm/desc/*.rb` → all descriptor types
- `lib/xccache/spm/pkg/*.rb` → all package types

---

## 8. Strengths & Weaknesses

### 🟢 Strengths

| Aspect | Detail |
|--------|--------|
| **Unique niche** | Only tool with first-class SPM caching support |
| **Proxy architecture** | Elegant: no fork/modify of original packages, uses native SPM binaryTarget |
| **Automatic fallback** | Cache miss → seamless source fallback, no manual intervention |
| **Multiple backends** | Local, Git, S3 — pluggable via Strategy pattern |
| **Swift macro support** | Handles the tricky macro-as-binary case |
| **Good documentation** | Overview, under-the-hood, case study, troubleshooting |
| **Real-world validation** | Tested on Kickstarter iOS (real large project) |
| **Per-configuration** | Separate Debug/Release caches |
| **Clean codebase** | Consistent patterns, auto-loading, well-organized |

### 🟡 Neutral / Trade-offs

| Aspect | Detail |
|--------|--------|
| **Ruby for iOS tooling** | Unconventional choice (most iOS devs use Swift/Python) |
| **xcodeproj gem dependency** | Couples to CocoaPods ecosystem gem |
| **Static frameworks only** | Uses `libtool -static` — no dynamic framework support |
| **Swift submodule** | `xccache-proxy` requires separate Swift toolchain to build |

### 🔴 Weaknesses / Risks

| Aspect | Detail |
|--------|--------|
| **⚠️ Maintenance stall** | Last commit Aug 2025 (11 months ago), last release Jun 2025 |
| **Small community** | 71 stars, 4 contributors (essentially solo dev) |
| **No CocoaPods yet** | Planned but not implemented — limits addressable market |
| **macOS only** | Ruby gem but fundamentally tied to Xcode/macOS |
| **SPM-only** | Projects using mixed CocoaPods+SPM need separate tools |
| **No CI recipes** | No pre-built GitHub Actions / CircleCI examples |

---

## 9. Competitor Landscape

| Tool | SPM | CocoaPods | Remote Cache | Active | Notes |
|------|-----|-----------|-------------|--------|-------|
| **xccache** | ✅ | ☐ planned | Git, S3 | ⚠️ stalled | Proxy package pattern |
| **XCRemoteCache** | ❌ | ⚠️ partial | HTTP server | ✅ | Spotify's tool, general structure |
| **Rugby** | ❌ | ✅ | ❌ | ✅ | CocoaPods-focused |
| **cocoapods-binary-cache** | ❌ | ✅ | ✅ (S3, Git) | ⚠️ | Pre-build pods |
| **Xcode Build Cache** | ✅ | ❌ | ❌ | ✅ | Built into Xcode 16+ (limited) |
| **Bazel** | N/A | N/A | ✅ | ✅ | Full build system (overkill) |
| **Tuist** | ✅ | ❌ | ✅ | ✅ | Project generation + caching |

---

## 10. Security & Supply Chain Notes

- **xccache-proxy submodule**: The Swift binary is built from source (`make proxy.build`). No pre-built binaries distributed.
- **S3 credentials**: Stored in `~/.xccache/s3.creds.json` — not encrypted at rest. Users should `chmod 600`.
- **Git remote cache**: Uses SSH (`git@`) or HTTPS with credentials in git config.
- **No network calls beyond**: Git clone/fetch, S3 sync, SPM package resolution (standard).
- **No telemetry**: No analytics, tracking, or phone-home behavior detected.

---

## 11. Documentation Map

All docs live under `docs/`:

| Document | Content |
|----------|---------|
| `README.md` | Project overview, badges, installation, quick start |
| `overview.md` | High-level: cache as xcframeworks, cache fallback, validation model |
| `getting-started.md` | Step-by-step: install, init, build cache, use cache |
| `how-to-install.md` | Installation via Bundler, RubyGems |
| `features-roadmap.md` | Live features (✅) vs planned (☐) |
| `under-the-hood/packaging-as-xcframework.md` | Deep dive: swift build → libtool → xcodebuild pipeline |
| `under-the-hood/proxy-packages.md` | Proxy package architecture, manifest rewriting |
| `under-the-hood/ensuring-bundle-module.md` | Resource bundle handling (Bundle.module) |
| `under-the-hood/macro-as-binary.md` | Swift macro prebuilding |
| `troubleshooting.md` | Unknown product dependencies, common issues |
| `case-study-kickstarter.md` | Real-world usage on Kickstarter iOS |
| `contributing-guidelines.md` | PR process, code style |
| `configuration.md` | xccache.yml reference (linked from code, not in tree) |

---

## 12. Key Design Decisions & Rationale

### 12.1 Why Ruby (not Swift)?

The author chose Ruby primarily for the `xcodeproj` gem — the de-facto library for manipulating `.xcodeproj` files, maintained by the CocoaPods team. There is no equivalent Swift library with the same maturity. The trade-off is that most iOS developers don't have Ruby in their toolchain, but Bundler makes this manageable.

### 12.2 Why Proxy Packages (not xcodebuild schemes)?

Alternative approaches like XCRemoteCache use xcodebuild schemes and build settings manipulation. The proxy package approach is more elegant because:
- It works at the SPM manifest level (declarative)
- No fragile build setting injection
- Xcode natively understands `.binaryTarget`
- Source fallback is a simple manifest change

### 12.3 Why Static Frameworks (libtool -static)?

`swift build` produces `.o` files but not `.framework` bundles. Using `libtool -static` is the simplest path to a framework binary. Dynamic frameworks would require additional linker flags and runtime considerations. The static approach works well for most use cases since SPM already links statically by default.

### 12.4 Cache Redesign (v1 → v2)

The project underwent a significant architecture change around PR #83-84:
- **v1**: Umbrella package approach — single package with all deps
- **v2**: Proxy package approach — per-dependency proxy with binaryTarget support
- The migration is handled transparently in `migrate_umbrella_to_proxy()`

---

## Sources

1. [GitHub Repository](https://github.com/trinhngocthuyen/xccache) — Full source tree, README, 190 commits
2. [`xccache.gemspec`](https://raw.githubusercontent.com/trinhngocthuyen/xccache/main/xccache.gemspec) — Dependencies: claide, xcodeproj, parallel, tty-*
3. [`lib/xccache.rb`](https://raw.githubusercontent.com/trinhngocthuyen/xccache/main/lib/xccache.rb) — Module root with ROOT/LIBEXEC constants
4. [`lib/xccache/command.rb`](https://raw.githubusercontent.com/trinhngocthuyen/xccache/main/lib/xccache/command.rb) — CLAide-based CLI with option parsing
5. [`lib/xccache/core/config.rb`](https://raw.githubusercontent.com/trinhngocthuyen/xccache/main/lib/xccache/core/config.rb) — Singleton config, sandbox paths, remote config
6. [`lib/xccache/core/cacheable.rb`](https://raw.githubusercontent.com/trinhngocthuyen/xccache/main/lib/xccache/core/cacheable.rb) — Memoization mixin pattern
7. [`lib/xccache/core/lockfile.rb`](https://raw.githubusercontent.com/trinhngocthuyen/xccache/main/lib/xccache/core/lockfile.rb) — Lockfile: package tracking, unknown dep detection
8. [`lib/xccache/installer.rb`](https://raw.githubusercontent.com/trinhngocthuyen/xccache/main/lib/xccache/installer.rb) — Orchestrator: perform_install pipeline
9. [`lib/xccache/installer/build.rb`](https://raw.githubusercontent.com/trinhngocthuyen/xccache/main/lib/xccache/installer/build.rb) — Build workflow: swift build → xcframework
10. [`lib/xccache/installer/use.rb`](https://raw.githubusercontent.com/trinhngocthuyen/xccache/main/lib/xccache/installer/use.rb) — Use workflow: replace source→binary
11. [`lib/xccache/spm/build.rb`](https://raw.githubusercontent.com/trinhngocthuyen/xccache/main/lib/xccache/spm/build.rb) — Buildable base: swift build wrapper with library evolution
12. [`lib/xccache/storage/base.rb`](https://raw.githubusercontent.com/trinhngocthuyen/xccache/main/lib/xccache/storage/base.rb) — Abstract Storage with no-op warnings
13. [`lib/xccache/storage/git.rb`](https://raw.githubusercontent.com/trinhngocthuyen/xccache/main/lib/xccache/storage/git.rb) — Git remote cache: fetch/push with branch management
14. [`lib/xccache/storage/s3.rb`](https://raw.githubusercontent.com/trinhngocthuyen/xccache/main/lib/xccache/storage/s3.rb) — S3 remote cache: aws s3 sync with credentials
15. [`docs/overview.md`](https://raw.githubusercontent.com/trinhngocthuyen/xccache/main/docs/overview.md) — Cache as xcframeworks, validation model
16. [`docs/under-the-hood/proxy-packages.md`](https://raw.githubusercontent.com/trinhngocthuyen/xccache/main/docs/under-the-hood/proxy-packages.md) — Proxy package architecture explained
17. [`docs/under-the-hood/packaging-as-xcframework.md`](https://raw.githubusercontent.com/trinhngocthuyen/xccache/main/docs/under-the-hood/packaging-as-xcframework.md) — Build pipeline: swift build → libtool → xcodebuild
18. [`docs/features-roadmap.md`](https://raw.githubusercontent.com/trinhngocthuyen/xccache/main/docs/features-roadmap.md) — Current & planned features
19. [`docs/troubleshooting.md`](https://raw.githubusercontent.com/trinhngocthuyen/xccache/main/docs/troubleshooting.md) — Unknown product dependencies resolution
20. [`.gitmodules`](https://raw.githubusercontent.com/trinhngocthuyen/xccache/main/.gitmodules) — xccache-proxy Swift submodule reference
21. [`Makefile`](https://raw.githubusercontent.com/trinhngocthuyen/xccache/main/Makefile) — Build targets: install, format, test, proxy.build
22. [`VERSION`](https://raw.githubusercontent.com/trinhngocthuyen/xccache/main/VERSION) — Current version: 1.0.5
