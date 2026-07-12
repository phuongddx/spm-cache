# System Architecture

> **Project:** spm-cache
> **Version:** 0.1.0

## High-Level Architecture

`spm-cache` is a dual-language system: a **Ruby gem** serves as the CLI orchestrator and build pipeline, while a **Swift companion tool** (`spm-cache-proxy`) handles SPM manifest generation and dependency graph resolution.

```
┌─────────────────────────────────────────────────────────┐
│                    User / CI                             │
│                                                         │
│  $ spm-cache          $ spm-cache build    $ spm-cache   │
│                       $ spm-cache rollback  remote pull  │
└──────────────┬──────────────────┬────────────────────────┘
               │                  │
               ▼                  ▼
┌─────────────────────────────────────────────────────────┐
│              Ruby Gem (CLI Orchestrator)                 │
│                                                         │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────────┐ │
│  │  Command    │  │  Installer   │  │  Storage       │ │
│  │  (CLAide)   │→ │  Pipeline    │  │  (Git / S3)    │ │
│  └─────────────┘  └──────┬───────┘  └────────────────┘ │
│                          │                              │
│  ┌───────────────────────┼──────────────────────────┐  │
│  │       SPM Package Model & Build Pipeline         │  │
│  │  (xcframework, macro, buildable, framework slice)│  │
│  └───────────────────────┬──────────────────────────┘  │
│                          │                              │
│  ┌───────────────────────┼──────────────────────────┐  │
│  │  Xcodeproj Extensions + Config + Lockfile        │  │
│  └──────────────────────────────────────────────────┘  │
└──────────────────────────┬──────────────────────────────┘
                           │ shells out
                           ▼
┌─────────────────────────────────────────────────────────┐
│          Swift Proxy Tool (spm-cache-proxy)             │
│                                                         │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────────┐ │
│  │ GenUmbrella │  │  GenProxy    │  │   Resolve      │ │
│  │ (CLI cmd)   │  │  (CLI cmd)   │  │   (CLI cmd)    │ │
│  └──────┬──────┘  └──────┬───────┘  └───────┬────────┘ │
│         │                │                  │          │
│  ┌──────▼──────┐  ┌──────▼───────┐  ┌──────▼────────┐  │
│  │ Umbrella    │  │ Proxy        │  │ Resolver      │  │
│  │ Generator   │  │ Generator    │  │ (metadata)    │  │
│  └─────────────┘  └──────────────┘  └───────────────┘  │
│         │                │                             │
│         └────────┬───────┘                             │
│                  ▼                                     │
│           ┌─────────────┐                              │
│           │ Binaries    │ ← checks ~/.spm-cache/       │
│           │ Cache       │   for .xcframework hits      │
│           └─────────────┘                              │
└─────────────────────────────────────────────────────────┘
```

## Core Concepts

### Proxy Package Architecture

The central innovation. For each SPM dependency, spm-cache generates a **proxy package** that can serve either a cached binary or source code:

**Cache Hit** (`.xcframework` exists in cache):
```swift
// {slug}_proxy/Package.swift
let package = Package(
    name: "{slug}_proxy",
    products: [.library(name: "{product}", targets: ["{slug}_binary"])],
    targets: [.binaryTarget(name: "{slug}_binary", path: ".build/artifacts/{product}.xcframework")]
)
```

**Cache Miss** (no cached binary):
```swift
// {slug}_proxy/Package.swift
let package = Package(
    name: "{slug}_proxy",
    products: [.library(name: "{product}", targets: ["{slug}_source"])],
    targets: [.target(name: "{slug}_source")]
)
```

A **root proxy** (`Package.swift`) aggregates all per-package proxies so Xcode sees a single local package reference. Uses tools-version 6.0:

```swift
// swift-tools-version: 6.0
let package = Package(
    name: "spm_cache_proxy",
    products: [
        .library(name: "spm_cache_proxy", targets: ["spm_cache_root"])
    ],
    dependencies: [
        .package(path: ".proxies/{slug1}"),
        .package(path: ".proxies/{slug2}"),
    ],
    targets: [
        .target(name: "spm_cache_root", dependencies: [
            .product(name: "{product1}", package: "{slug1}"),
            .product(name: "{product2}", package: "{slug2}"),
        ], path: "src/root")
    ]
)
```

The Xcode project references this root proxy as an `XCLocalSwiftPackageReference` with `relativePath = "spm-cache/packages/proxy"`. Product dependencies (`SwiftUICharts`, `ExyteChat`, etc.) point to products exposed by the per-package proxy sub-packages.

### Umbrella Package

A synthetic `Package.swift` that references all project SPM dependencies in one place. This allows the Swift tool to run `swift package describe` and resolve the full dependency graph without modifying the user's project.

### Cachemap & Graph

After proxy generation, a `graph.json` is emitted with per-module status:

```json
[
  { "module": "Alamofire", "status": "hit", "dependencies": [], "hasMacro": false },
  { "module": "MyMacro", "status": "missed", "dependencies": [], "hasMacro": true }
]
```

Statuses: `hit` (cached binary used), `missed` (source fallback), `ignored` (in ignore list).

The Ruby `Cache::Cachemap` class reads this and drives the visualization (HTML) and build decisions.

## Component Architecture

### Ruby Gem Layers

```
Command Layer (CLAide)
    ↓
Installer Pipeline (orchestration)
    ↓
SPM Package Model ←→ Xcodeproj Extensions
    ↓
Build Pipeline (swift build → libtool → xcodebuild)
    ↓
Storage (local cache + remote Git/S3)
```

**Command Layer** (`command/`): Parses CLI args via CLAide, delegates to installers.

**Installer Pipeline** (`installer/`): Orchestrates the full install:
1. `verify_projects!` — ensure project exists
2. `recreate_dirs` — clean sandbox
3. `ensure_config_file` — copy template if missing
4. `sync_lockfile` — load/save lockfile
5. `proxy_pkg.prepare` — call Swift tool (gen-umbrella → resolve → gen-proxy)
6. `gen_supporting_files` — xcconfigs for macros
7. `gen_cachemap_viz` — HTML dependency graph

**SPM Package Model** (`spm/`):
- `Package::Proxy` orchestrates the Swift tool calls
- `Buildable` runs **`xcodebuild build`** (not `swift build`) with library evolution flags, supports multiple destinations (simulator + device)
- `Buildable.create_static_library` uses `libtool -static` to produce `.a` from `.o`
- `Buildable.create_framework` assembles `.framework` with Info.plist, Modules/ (swiftmodule + swiftinterface)
- `XCFramework` merges multiple framework slices via `xcodebuild -create-xcframework`
- `Macro` builds macro targets as `.macro` executables
- `Package::DEFAULT_DESTINATIONS = ["iphonesimulator", "iphoneos"]` — builds both by default

**Xcodeproj Extensions** (`xcodeproj/`): Monkey-patch the `xcodeproj` gem to add proxy package references and product dependencies.

### Swift Proxy Tool Layers

```
CLI Commands (ArgumentParser)
    ↓
Generators (Umbrella, Proxy, Graph, Metadata)
    ↓
Models (Lockfile, BinariesCache)
```

**`GenUmbrella`**: Loads `spm-cache.lock` → merges all project packages/platforms → `UmbrellaGenerator` writes umbrella `Package.swift`.

**`GenProxy`**: Loads lockfile → `ProxyGenerator` iterates packages, checks `BinariesCache` for hits, generates per-package proxy + root proxy + `graph.json`.

**`Resolve`**: Package graph resolution and metadata generation (currently a stub).

## Data Flow

### `spm-cache use` (default command)

```
1. Command::Use.run
2. Installer::Use.new(project:).perform_install
3. SPM::Package::Proxy.prepare:
   a. ProxyExecutable.gen_umbrella  → Swift gen-umbrella → umbrella Package.swift
   b. ProxyExecutable.resolve       → Swift resolve → metadata
   c. ProxyExecutable.gen_proxy     → Swift gen-proxy → proxy packages + graph.json
4. Cache::Cachemap.load(graph.json)
5. gen_cachemap_viz → HTML at spm-cache/cachemap/index.html
6. replace_binaries_for_project (integrate proxy into Xcode project)
```

### `spm-cache build [TARGETS]`

```
1. Command::Build.run
2. Installer::Build.new(project:).perform_install
3. Same as use + build_missed!:
   a. cachemap.missed → targets to build
   b. For each: Package.build_target → swift build → libtool → xcodebuild
   c. Store xcframework in ~/.spm-cache/{config}/
4. Re-run proxy_pkg.prepare (now targets are hits)
```

### `spm-cache remote pull/push`

```
1. Command::Remote::{Pull,Push}.run
2. Remote.create_storage(config_name):
   - Reads spm-cache.yml remote config
   - Returns GitStorage or S3Storage (or Base no-op)
3. storage.pull/push:
   - Git: shallow clone/fetch or add/commit/push
   - S3: aws s3 sync with credentials
```

## Build Pipeline (xcframework creation)

Multi-slice pipeline (simulator + device in one xcframework):

```
For each destination (iphonesimulator, iphoneos):
  xcodebuild build -scheme {name} -destination '{dest}'
    OTHER_SWIFT_FLAGS='-enable-library-evolution -emit-module-interface'
    ↓
  DerivedData/**/{module}.o + .swiftmodule + .swiftinterface
    ↓
  libtool -static -o {module} {module}.o
    ↓
  Assemble {module}.framework (binary + Info.plist + Modules/)
    ↓
Merge all slices:
  xcodebuild -create-xcframework
    -framework {sim_framework}
    -framework {device_framework}
    -output {module}.xcframework
    ↓
Store in ~/.spm-cache/{config}/{module}.xcframework
```

**Library Evolution:** Swift `-enable-library-evolution -emit-module-interface -no-verify-emitted-module-interface` flags
produce `.swiftinterface` files (text-based module descriptors) that allow the prebuilt
binary to work across compiler versions. Without these, `.swiftmodule` files are stripped
by `xcodebuild -create-xcframework` because they are compiler-version-specific.

**Destination Mapping** (`Buildable::DESTINATIONS`):

| Key | xcodebuild destination |
|-----|----------------------|
| `iphonesimulator` / `ios_simulator` | `platform=iOS Simulator,name=iPhone 17` |
| `iphoneos` / `ios_device` | `generic/platform=iOS` |

Each build also sets `CODE_SIGNING_ALLOWED=NO` and uses `-derivedDataPath` to isolate artifacts.

**Package build command:**
```bash
spm-cache pkg build {target} --sdk=all --out={path}
# --sdk=all: both iphonesimulator + iphoneos (default)
# --sdk=iphonesimulator: simulator only
# --sdk=iphoneos: device only
```

## Storage Architecture

### Local Cache

```
~/.spm-cache/
├── debug/
│   ├── Alamofire.xcframework
│   └── MyMacro.macro
└── release/
    └── Alamofire.xcframework
```

### Remote Cache (Git)

- Shallow clone of a dedicated cache repo
- `pull`: `git fetch --depth 1 && git checkout FETCH_HEAD && git clean -fd`
- `push`: `git add . && git commit && git push`

### Remote Cache (S3)

- `aws s3 sync` with `--exact-timestamps` (pull) or `--delete` (push)
- Credentials from JSON file (`{ "access_key_id": "...", "secret_access_key": "..." }`)

## Sandbox Layout (during integration)

```
{project}/
├── spm-cache.yml              # Config
├── spm-cache.lock             # Lockfile
└── spm-cache/                 # Sandbox (regenerated each run)
    ├── packages/
    │   ├── umbrella/          # Umbrella Package.swift + stub sources
    │   │   └── Package.swift
    │   └── proxy/             # Proxy packages + root Package.swift
    │       ├── Package.swift  # Root proxy
    │       ├── .proxies/      # Per-package proxies
    │       │   └── {slug}/Package.swift
    │       ├── src/           # Stub sources for proxy targets
    │       └── .build/
    │           └── artifacts/ # Symlinks to cached xcframeworks
    ├── metadata/              # Package metadata (from resolve)
    ├── xcconfigs/             # Macro xcconfigs (OTHER_SWIFT_FLAGS)
    └── cachemap/
        └── index.html         # Dependency graph visualization
```
