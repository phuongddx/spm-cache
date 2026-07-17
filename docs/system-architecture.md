# System Architecture

> **Project:** spm-cache
> **Version:** 0.2.0

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

The central innovation. For each SPM dependency with at least one library product, spm-cache generates a **proxy package** at `.proxies/{slug}_proxy` — note the `_proxy` suffix on the folder (and the wrapper's own package identity): naming it bare `{slug}` would give the wrapper the *same* SwiftPM identity as the real package it depends on, which SwiftPM collapses into one node and turns the wrapper's dependency into a self-cycle ("Conflicting identity" + cyclic-dependency error). A package can export more than one library product (Realm → `Realm` + `RealmSwift`); the proxy exports **every** library product by its real name, sourced from `spm-cache.lock`'s `products[]` metadata — never the lockfile identity — with one target per product:

**Cache Hit** (`.xcframework` exists in cache):
```swift
// .proxies/{slug}_proxy/Package.swift
let package = Package(
    name: "{slug}_proxy",
    products: [
        .library(name: "{realProductName1}", targets: ["{slug}_{realProductName1}_binary"]),
        .library(name: "{realProductName2}", targets: ["{slug}_{realProductName2}_binary"]),
    ],
    dependencies: [ /* only for products still on the source-fallback path */ ],
    targets: [
        .binaryTarget(name: "{slug}_{realProductName1}_binary", path: ".build/artifacts/{realProductName1}.xcframework"),
        .binaryTarget(name: "{slug}_{realProductName2}_binary", path: ".build/artifacts/{realProductName2}.xcframework"),
    ]
)
```

**Cache Miss** (no cached binary for that product — each product has an independent hit/miss status):
```swift
// .proxies/{slug}_proxy/Package.swift
let package = Package(
    name: "{slug}_proxy",
    products: [.library(name: "{realProductName}", targets: ["{slug}_{realProductName}_shim"])],
    dependencies: [.package(url: "{repositoryURL}", from: "{version}")],  // declared once, even if several products fall back to source
    targets: [
        .target(name: "{slug}_{realProductName}_shim", dependencies: [
            .product(name: "{realProductName}", package: "{slug}"),
        ], path: "Sources/{slug}_{realProductName}_shim")
    ]
)
```
The shim source re-exports the real package's module(s) — `@_exported import {moduleName}`, one line per entry in that product's `targets[]` — so app-level `import {realProductName}` still resolves to source compilation. `targets[]` matters because a product's name doesn't always match its underlying module name.

**Legacy fallback:** a lockfile entry with no `products[]` metadata yet (not re-synced since before v0.2.0) is treated as a single library product named `productName ?? name ?? slug` — the old identity-fallback behavior, kept for backward compatibility until the lockfile is enriched on the next run.

**Plugin-only packages** (build-tool plugins like SwiftGenPlugin — `products[]` present with no `library`-type entry) get **no** proxy folder and **no** root-proxy dependency; their original Xcode package reference is preserved directly instead (see Xcode Integration below). A *mixed* package (library + plugin products) is treated as a library package: its library products are proxied as usual and its plugin products are simply out of scope.

A **root proxy** (`Package.swift`) aggregates all per-package proxies (excluding plugin-only ones) so Xcode sees a single local package reference. Uses tools-version 6.0:

```swift
// swift-tools-version: 6.0
let package = Package(
    name: "spm_cache_proxy",
    products: [
        .library(name: "spm_cache_proxy", targets: ["spm_cache_root"])
    ],
    dependencies: [
        .package(path: ".proxies/{slug1}_proxy"),
        .package(path: ".proxies/{slug2}_proxy"),
    ],
    targets: [
        .target(name: "spm_cache_root", dependencies: [
            .product(name: "{product1}", package: "{slug1}_proxy"),
            .product(name: "{product2}", package: "{slug2}_proxy"),
        ], path: "src/root")
    ]
)
```

The Xcode project references this root proxy as an `XCLocalSwiftPackageReference` with `relativePath = "spm-cache/packages/proxy"`. Product dependencies (`SwiftUICharts`, `ExyteChat`, etc.) point to products exposed by the per-package proxy sub-packages.

### Umbrella Package

A synthetic `Package.swift` that references every project SPM dependency (as a plain `.package(...)` entry, with no target/product references at all) purely so `swift package resolve` materializes real checkouts under `{umbrella_dir}/.build/checkouts/{slug}` — the umbrella never validates products, so this works even before `spm-cache.lock` has real product metadata. A package already known to be plugin-only (from a prior enrichment) is skipped here too; an unenriched package is always included so its checkout can be described at least once.

### Lockfile Product Metadata (`spm-cache.lock`)

Each package entry carries a `products` array populated from `swift package describe` against its materialized checkout:

```json
{ "name": "realm-swift", "repositoryURL": "...", "version": "...",
  "products": [
    { "name": "RealmSwift", "type": "library", "targets": ["RealmSwift"] },
    { "name": "Realm", "type": "library", "targets": ["Realm"] }
  ] }
```

`enrich_lockfile_products` (`Installer`) runs once per install, between checkout materialization and proxy generation, and only touches entries that don't have `products` yet (idempotent — a package whose checkout can't be found is left unchanged with a warning, and falls back to identity-derived naming downstream). Renaming a cached module from lockfile identity to its real product name means **existing `~/.spm-cache/<config>/<identity>.xcframework` binaries become unreachable** after upgrading — this is intentional (those binaries were built under the wrong module name) and triggers a one-time full rebuild; stale files are not garbage-collected automatically.

### Cachemap & Graph

`graph.json` has one entry **per library product** (not per package — a multi-product package like Realm contributes two independent entries):

```json
[
  { "module": "Alamofire", "status": "hit", "dependencies": [], "hasMacro": false },
  { "module": "RealmSwift", "status": "missed", "dependencies": [], "hasMacro": false },
  { "module": "Realm", "status": "missed", "dependencies": [], "hasMacro": false },
  { "module": "SnapKit", "status": "excluded", "dependencies": [], "hasMacro": false },
  { "module": "SwiftGenPlugin", "status": "plugin", "dependencies": [], "hasMacro": false }
]
```

Statuses: `hit` (cached binary used), `missed` (source fallback via real package dependency), `ignored` (matches an `ignore` glob pattern; always compiled from source even when a cached binary exists, and never built by `spm-cache build`), `excluded` (does not match any `cache_only` glob when `cache_only` is non-empty; always compiled from source, never built by `spm-cache build`), `plugin` (build-tool plugin package; not cacheable, always skipped by `spm-cache build`).

**Precedence:** when `cache_only` is non-empty it wins outright — `ignore` is not applied and only `hit`/`missed`/`excluded` statuses appear (no `ignored`).

**Matching:** `ignore`/`cache_only` glob patterns match against any of a package's real library product names, or its lockfile identity — matching by identity still applies the resulting status to *every* product of that package (package-level decision).

**CLI target names changed**: `spm-cache build <target>` now takes real product names (`Realm`, `RealmSwift`), not the old lockfile identity (`realm-swift`) — but the identity remains a working **alias** that expands to all of that package's product names, so existing scripts/CI invocations using the old identity keep working.

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
3. `ensure_config_file` — copy template if missing, then load config (ignore_build_errors, default_sdk, ignore settings)
4. `sync_lockfile` — load/save lockfile
5. `prepare_proxy` — `proxy_pkg.prepare` runs the Swift tool + a caller-supplied step in between:
   a. `gen_umbrella` — umbrella `Package.swift` from the lockfile. The umbrella independently pins every package to its own last-resolved version *except* one it can prove is only a transitive dependency of another package already in the list (its products never appear in `dependencies` — see step 4a below); a transitive-only package is left for SwiftPM to resolve on its own through whichever package actually consumes it, rather than double-pinning it at a version that can drift from what that package's own manifest requires
   b. `resolve_umbrella_checkouts` — `swift package resolve` against the umbrella (falls back to the newest matching DerivedData checkouts on failure), materializing real package sources under `{umbrella_dir}/.build/checkouts/{slug}` *before* anything reads product metadata — this ordering fix closes the wrong-product-name bug (no flow previously resolved checkouts before proxy generation)
   c. `enrich_lockfile_products` — `swift package describe` per checkout → writes `products[]` into `spm-cache.lock` (idempotent, skips entries already enriched); if `describe` comes back with no products (seen with binary-target-only packages), falls back to regex-parsing `.library(name:)`/`.binaryTarget(name:)` declarations straight out of the checkout's `Package.swift` text
   d. If (b) failed on its first attempt: regenerate the umbrella and resolve again now that (c) has real product metadata, so the transitive-only-package skip in (a) can actually apply — the first pass runs before anyone has `products[]`, so it still pins everything and can hit the same conflict it's meant to avoid
   e. `gen_proxy` — per-package + root proxy packages, `graph.json`, from the now-enriched lockfile

4a. `refresh_consumed_dependencies` (runs as part of `sync_lockfile`, before `prepare_proxy`) — opens the Xcode project and records, per target, the product names it directly links (`package_product_dependencies`) into the lockfile's `dependencies` field. This is the data step (a) and (d) above use to tell a directly-consumed package apart from a transitive-only one.
6. `gen_supporting_files` — xcconfigs for macros
7. `integrate_proxy_into_project` — rewrite Xcode package references/product deps to point at the proxy, preserving plugin-only package references untouched (see Xcode Integration below)
8. `gen_cachemap_viz` — HTML dependency graph

Note: `use` now pays the `resolve_umbrella_checkouts` cost too (network on a cold SwiftPM cache) — previously only `build` resolved checkouts, and only *after* Xcode integration. The DerivedData fallback plus SwiftPM's own global package cache mitigate the offline/cold-cache case; a resolve failure warns and falls back per-package rather than aborting the run.

### Xcode Integration (plugin-aware)

`integrate_proxy_into_project` rebuilds the project's SPM package references and product dependencies every run:
- **Kept as-is:** any package reference whose (normalized) repository URL matches a plugin-only lockfile entry, plus its product dependency (never deleted, never rewired) — including one already carrying Xcode's `plugin:`-prefixed product-dependency naming, a second belt against ever rewiring a build-tool-plugin dependency onto the proxy.
- **Stripped and rebuilt:** everything else, including *every* `XCLocalSwiftPackageReference` (so a stale proxy ref from a prior run never survives — this is what keeps a plugin's checkout from being pinned into place and what prevents duplicate/colliding refs across runs), replaced by one fresh local proxy reference with rewired product dependencies.
- **Unmatched plugin entry:** if a plugin-only lockfile entry has no matching project reference at all, the run warns loudly rather than silently preserving nothing.
- Local plugin-only packages (`XCLocalSwiftPackageReference`, no URL) are out of scope — `Package.resolved` carries no local pins, so they never get a lockfile entry to key an enrichment or a keep-decision off of. Pre-existing gap, not a regression.

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

**`GenUmbrella`**: Loads `spm-cache.lock` → merges all project packages/platforms/dependencies → `UmbrellaGenerator` writes umbrella `Package.swift` (dependencies only, no target/product references; skips packages already known to be plugin-only, and skips a package whose products are provably never directly consumed per the merged `dependencies` map — letting SwiftPM resolve it transitively through whichever package does consume it, instead of pinning it again at a version that can conflict with what that package's own manifest requires).

**`GenProxy`**: Loads lockfile → `ProxyGenerator` iterates packages, skips plugin-only ones (emitting a `plugin`-status `graph.json` entry instead), otherwise expands each package's real library products (`Lockfile.PackageRef.libraryProducts`, with a single-entry legacy fallback when `products[]` metadata is absent) and checks `BinariesCache` per product name, generating one proxy folder per package (all its products in one manifest) + root proxy + `graph.json`.

**`Resolve`**: Package graph resolution and metadata generation (currently a stub).

## Data Flow

### `spm-cache use` (default command)

```
1. Command::Use.run
2. Installer::Use.new(project:).perform_install
3. sync_lockfile → refresh_consumed_dependencies (records each target's directly-linked product names into lockfile.dependencies)
4. SPM::Package::Proxy.prepare:
   a. ProxyExecutable.gen_umbrella   → Swift gen-umbrella → umbrella Package.swift (skips packages proven transitive-only via dependencies)
   b. resolve_umbrella_checkouts     → swift package resolve (+ DerivedData fallback); returns whether it succeeded on its own
   c. enrich_lockfile_products       → swift package describe per checkout (+ Package.swift text fallback) → products[] into spm-cache.lock
   d. if (b) fell back: retry_umbrella_resolve_after_enrichment → regenerate + resolve again now that products[] is known
   e. ProxyExecutable.gen_proxy      → Swift gen-proxy → proxy packages + graph.json
5. integrate_proxy_into_project (keep plugin-only refs, rewire everything else onto the proxy)
6. Cache::Cachemap.load(graph.json)
7. gen_cachemap_viz → HTML at spm-cache/cachemap/index.html
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

**Scheme Resolution:** Before any build attempt, the pipeline calls `swift package describe` and filters library-type products by exact name match (case-insensitive), then substring containment, then the first available library product. This replaces the previous behavior of deriving the scheme from raw package/target identity, which often resulted in builds using the wrong scheme. If `swift package describe` yields no usable result (e.g., binary-only packages), a fallback heuristic queries `xcodebuild -list` scheme names.

**Umbrella Resolve Fallback:** If `swift package resolve` fails on the umbrella package, the installer falls back to copying the most-recently-modified `~/Library/Developer/Xcode/DerivedData/<ProjectName>-*/SourcePackages/checkouts` into the umbrella's `.build/checkouts/` directory. This avoids the previous behavior of skipping every target with "checkout not found" errors. On a cold run (no `products[]` metadata for anyone yet) the umbrella can't yet tell a transitive-only package apart from a directly-consumed one and pins everything, which can conflict and trigger this fallback; `retry_umbrella_resolve_after_enrichment` regenerates the umbrella and resolves again once `enrich_lockfile_products` has real product metadata, so the retry can usually succeed on its own rather than the run permanently depending on DerivedData being present (absent on CI or after a "clean derived data").

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
    │   ├── umbrella/          # Umbrella Package.swift (deps only)
    │   │   ├── Package.swift
    │   │   └── .build/checkouts/{slug}/   # Real package sources (resolve_umbrella_checkouts)
    │   └── proxy/             # Proxy packages + root Package.swift
    │       ├── Package.swift  # Root proxy (skips plugin-only packages)
    │       ├── .proxies/      # Per-package proxies (plugin-only packages get none)
    │       │   └── {slug}_proxy/Package.swift
    │       ├── src/           # Stub sources for proxy targets
    │       └── .build/
    │           └── artifacts/ # Symlinks to cached xcframeworks, named by real product
    ├── metadata/              # Package metadata (from resolve, currently a stub)
    ├── xcconfigs/             # Macro xcconfigs (OTHER_SWIFT_FLAGS)
    └── cachemap/
        └── index.html         # Dependency graph visualization
```
