# Brainstorm: Building spm-cache (xccache Reimplementation)

> **Date:** 2026-07-11
> **Status:** Design Approved - Ready for Plan
> **Source Reference:** [xccache](https://github.com/trinhngocthuyen/xccache) v1.0.5 + [xccache-proxy](https://github.com/trinhngocthuyen/xccache-proxy) v1.0.0

---

## Problem Statement

iOS projects using SPM dependencies suffer long clean build times because Xcode recompiles all Swift package sources from scratch. Existing cache tools (cocoapods-binary-cache, Rugby, XCRemoteCache) **lack SPM support**. `xccache` solves this by prebuilding SPM dependencies into `.xcframework` binaries and swapping them at the manifest level via an innovative **proxy package architecture**.

**Goal:** Build `spm-cache` - a clean reimplementation of xccache using the `spm-cache` command name, preserving the proven architecture while improving structure, testability, and maintainability.

---

## Scout Summary (Codebase Context)

The target repo (`spm-cache`) is currently empty (only contains the architecture analysis doc + git). This is a **greenfield build**. Key findings from source research:

- **xccache** = Ruby gem (CLI + orchestrator) + Swift binary (`xccache-proxy` submodule for SPM manifest generation)
- **~60 Ruby files** organized into: `command/`, `core/`, `installer/`, `spm/`, `storage/`, `xcodeproj/`, `cache/`
- **~24 Swift files** in xccache-proxy: `CLI/`, `Core/Generator/`, `Core/Proxy/`, `Core/Extensions/`
- Core innovation: **proxy packages** - per-dependency `Package.swift` that swaps between `.binaryTarget` (cache hit) and source symlink (cache miss)
- Build pipeline: `swift build` -> `.o` files -> `libtool -static` -> `.framework` -> `xcodebuild -create-xcframework`
- Two storage backends: Git (shallow clone) and S3 (`aws s3 sync`)
- Special handling for Swift macros and resource bundles

---

## Requirements (Concrete)

### Expected Output
A Ruby gem named `spm-cache` with:
1. CLI binary `spm-cache` with subcommands: `use`, `build`, `off`, `rollback`, `cache list`, `cache clean`, `pkg build`, `remote pull`, `remote push`
2. A Swift companion tool `spm-cache-proxy` for umbrella/proxy package generation
3. `spm-cache.lock` (JSON lockfile) and `spm-cache.yml` (YAML config) management
4. xcframework build pipeline (source -> framework slices -> xcframework)
5. Local cache (`~/.spm-cache/{debug,release}/`) + remote cache (Git + S3)

### Acceptance Criteria
- Running `spm-cache` (defaults to `use`) in an Xcode project dir integrates the proxy package and replaces source deps with binaries where cache hits
- `spm-cache build <targets>` builds specified targets into xcframeworks in local cache
- Cache miss -> automatic fallback to source code
- `spm-cache rollback` restores original project state
- `spm-cache remote pull/push` syncs cache with Git/S3
- Swift macros and resource bundles are handled correctly
- Checksum-based cache validation works

### Scope Boundary (This Round)
**In scope:** Full reimplementation of all existing xccache features
**Out of scope:** CocoaPods support, Swift plugins, new features not in xccache v1.0.5

### Non-Negotiable Constraints
- Command name: `spm-cache` (not `xccache`)
- Module namespace: `SPMCache` (not `XCCache`)
- Config file: `spm-cache.yml`, lockfile: `spm-cache.lock`
- Cache dir: `~/.spm-cache/`
- Sandbox dir: `spm-cache/` (not `xccache/`)
- Preserve proxy package architecture (the proven core innovation)
- Ruby gem + Swift companion tool (same dual-language approach)

### Touchpoints
None (greenfield). All files created from scratch.

---

## Evaluated Approaches

### Approach A: Direct Port (Ruby + Swift, mirror xccache structure)

Clone the xccache architecture exactly, renaming `XCCache` -> `SPMCache`, `xccache` -> `spm-cache`.

**Pros:**
- Proven architecture, minimal design risk
- 1:1 mapping makes verification easy against original
- Preserves all edge-case handling (macros, resources, headers, library evolution)

**Cons:**
- Inherits some Ruby metaprogramming complexity (Cacheable mixin)
- Two-language split requires building/distributing the Swift proxy tool

### Approach B: Pure Ruby (eliminate Swift proxy tool)

Absorb the Swift proxy tools logic (SPM manifest generation) into Ruby by parsing `Package.swift` manifests manually or using `swift package describe --type json`.

**Pros:**
- Single language, simpler distribution
- No Swift toolchain build dependency

**Cons:**
- `swift package describe` doesnt give full dependency graph with the resolution context
- Loses access to SwiftPMs `Workspace`, `ModulesGraph`, `Manifest` APIs (critical for proxy generation)
- Would require reimplementing SPM dependency resolution logic in Ruby - fragile and hard to maintain
- **HIGH RISK** - the Swift tool exists precisely because Ruby cant reliably do this

### Approach C: Pure Swift (rewrite everything in Swift)

Rewrite the entire tool in Swift, using SwiftPM directly for both manifest manipulation and build orchestration.

**Pros:**
- Single language
- Direct access to SwiftPM, XcodeProjKit potential
- Modern ecosystem

**Cons:**
- No mature Swift equivalent to the `xcodeproj` gem for `.xcodeproj` manipulation (the #1 reason xccache uses Ruby)
- Would need to reimplement xcodeproj read/write from scratch - massive effort
- Xcode integration (adding package refs, build settings, synced groups) is battle-tested in Ruby

### Recommendation: Approach A (Direct Port)

**Rationale:** The dual Ruby+Swift architecture is not accidental - each language serves a critical role that the other cant easily replace. Ruby gives us the `xcodeproj` gem (irreplaceable for `.xcodeproj` manipulation). Swift gives us native SwiftPM APIs (irreplaceable for manifest generation and dependency graph traversal). YAGNI says dont try to unify; KISS says follow the proven path.

---

## Final Design: spm-cache Architecture

### Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Ruby + Swift dual-language | Ruby: `xcodeproj` gem irreplaceable. Swift: SwiftPM APIs irreplaceable. |
| Proxy package architecture | Declarative SPM-level swap, native `.binaryTarget`, clean fallback |
| CLAide for CLI | Same framework as CocoaPods, battle-tested, auto subcommand discovery |
| Cacheable mixin (memoization) | Avoids redundant file I/O and SPM resolution; prepend-module pattern |
| Template Method (Installer) | `perform_install` pipeline with subclass hooks (Build, Use, Rollback) |
| Strategy pattern (Storage) | Pluggable Git/S3 backends with no-op base |
| Static frameworks (libtool) | Simplest path from `.o` to `.framework`; SPM defaults to static |
| Library evolution flags | Workaround for swift#64669 swiftinterface emission |
| Checksum-based validation | SHA256 of package sources -> 8-char hex; stored in metadata |
| Per-config cache dirs | `~/.spm-cache/debug/` and `~/.spm-cache/release/` isolation |

### CLI Command Map

```
spm-cache (abstract)
+-- use (default)     -> Installer::Use    -> replace source -> binary
+-- build [TARGETS]   -> Installer::Build  -> build(targets) + gen_proxy()
+-- off [TARGETS]     -> Force source mode
+-- rollback          -> Installer::Rollback -> binary -> source
+-- cache (abstract)
|   +-- list          -> List cached packages
|   +-- clean         -> Clean/purge cache
+-- pkg (abstract)
|   +-- build         -> Build single package -> xcframework
+-- remote (abstract)
    +-- push          -> GitStorage or S3Storage push
    +-- pull          -> Pull from remote
```

### Config (`spm-cache.yml`)

```yaml
ignore: []
ignore_local: false
ignore_build_errors: false
keep_pkgs_in_project: false
default_sdk: iphonesimulator
remote:
  debug:
    git: git@github.com:org/cache.git
  release:
    s3:
      uri: "s3://bucket/path"
      creds: "~/.spm-cache/s3.creds.json"
```

### Lockfile (`spm-cache.lock`)

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

### Build Pipeline (Source -> xcframework)

```
swift build --target Alamofire --sdk iphonesimulator
  -> .build/{triple}/{config}/Alamofire.build/*.o

libtool -static -o Alamofire.framework/Alamofire -filelist objects.txt
  -> Static library binary

Assemble framework:
  Info.plist (template)
  Headers/ (Swift + ObjC headers, umbrella header)
  Modules/module.modulemap (template)
  Modules/{module}.swiftmodule/ (swiftinterfaces, swiftmodules)
  Resources/*.bundle (if any, with overridden Bundle.module accessor)

xcodebuild -create-xcframework -framework slice1 -framework slice2 -output Alamofire.xcframework
```

### Swift Proxy Tool (spm-cache-proxy)

Three subcommands:
1. **gen-umbrella** - Reads lockfile -> generates umbrella `Package.swift` with all deps as targets `{Name}.spm_cache`
2. **resolve** - Runs SwiftPM `Workspace.loadPackageGraph` -> outputs package manifest metadata JSON per package
3. **gen-proxy** - Loads graph -> generates per-dependency proxy `Package.swift` (binaryTarget if cache hit, source symlink if miss) -> outputs `graph.json` with cache status + dependency edges + macro paths

### Implementation Considerations and Risks

| Risk | Mitigation |
|------|------------|
| SwiftPM API instability (branch `release/6.2`) | Pin SwiftPM branch, version-lock the proxy tool |
| xcodeproj gem version drift | Pin `>= 1.26.0`, test against current |
| Swift macro build complexity (tool binary extraction) | Follow proven workaround: build associated `.target` not `.macro` |
| Resource bundle `Bundle.module` breakage in binary | Override `resource_bundle_accessor` with framework-aware lookup |
| Header resolution differences (bare vs binary) | Expose all headers via symlink tree in root proxy (`.headers/`) |
| Library evolution swiftinterface emission bug | Apply `-enable-library-evolution` + `-emit-module-interface` flags |
| Proxy binary distribution | Download from GitHub releases (versioned) or build from source |

### Success Metrics and Validation

- `spm-cache use` in a test project with Alamofire -> produces proxy package, Xcode resolves successfully
- `spm-cache build Alamofire --sdk=iphonesimulator` -> `.xcframework` appears in `~/.spm-cache/debug/`
- Second `spm-cache use` -> cache hit, binary used, build time reduced
- `spm-cache rollback` -> project restored to original state
- Swift macro package (e.g., a macro target) -> builds and expands correctly when cached
- Resource bundle package -> `Bundle.module` finds resources inside `.framework`

---

## Implementation Phases (High-Level)

### Phase 1: Core Foundation
Ruby gem scaffold, CLAide CLI skeleton, core utilities (Sh, Git, UI, Config, Lockfile, Syntax, Cacheable, System extensions, Template).

### Phase 2: SPM Build Pipeline
Buildable, FrameworkSlice (swift build -> framework assembly), XCFramework, Macro, Sdk, Swiftc, SPM::Package base, Description parsing.

### Phase 3: Proxy Architecture
Swift proxy tool (gen-umbrella, resolve, gen-proxy), Proxy package (Ruby side), proxy executable manager, graph/cachemap integration.

### Phase 4: Installer Orchestration
Installer template method, Build/Use/Rollback subclasses, integration mixins (build, descs, supporting_files, viz).

### Phase 5: Project Integration
Xcodeproj extensions (Project, Target, PkgRef, Group, BuildConfiguration, Config), project manipulation, xcconfig injection.

### Phase 6: Storage Backends
Storage base, GitStorage, S3Storage, remote commands.

### Phase 7: Remaining Commands
cache list/clean, pkg build, off command, cachemap visualization, templates.

### Phase 8: Documentation and Polish
README, getting-started docs, examples, Makefile, gemspec finalization.

---

## Next Steps

1. Hand off to plan creation for detailed phase-by-phase implementation plan
2. Each phase produces a testable, verifiable increment
3. Build the Swift proxy tool in parallel with the Ruby gem (they are decoupled via CLI interface)
