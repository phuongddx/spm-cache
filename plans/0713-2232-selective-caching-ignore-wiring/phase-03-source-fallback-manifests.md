---
phase: 3
title: Source fallback manifests for miss and ignored
status: completed
priority: P1
dependencies:
  - 1
effort: M
---

# Phase 3: Source fallback manifests for miss and ignored

## Overview

Make "fallback to source" real. Today a cache miss generates an *empty stub* target (`ProxyGenerator.swift:53-55`): the proxy vends a library whose only source is an empty `.swift` file, so `import Alamofire` in the app fails — the module doesn't exist. This phase makes miss and ignored packages resolve to the **original package source** via the proxy layer. This is the core promise of REQ-003 ("cache miss automatically falls back to source compilation — no build failure").

## Requirements

- Functional: an app depending on a missed or ignored package compiles and links against the real package source, fetched by SPM from the original URL (remote) or path (local). `hit` behavior unchanged.
- Non-functional: no duplicate-product-name errors in the SPM graph; lockfile remains the single source of package coordinates.

## Architecture

Lockfile `PackageRef` already carries what's needed (`Lockfile.swift:4-9`): `repositoryURL`, `pathFromRoot`, `name` (identity), `version`. The umbrella generator (`UmbrellaGenerator.swift:24-29`) already emits real `.package(url:_, from:)` / `.package(path:)` dependencies — reuse that exact pattern.

**Design decision — two candidates, spike required (Step 1):**

- **Option A — per-slug proxy re-export (preferred if it links):** the miss/ignored proxy manifest declares the original package as a dependency and vends a shim target that re-exports the real product:
  ```swift
  // <slug>_proxy/Package.swift  (miss/ignored branch)
  let package = Package(
      name: "<slug>_proxy",
      products: [.library(name: "<productName>", targets: ["<slug>_shim"])],
      dependencies: [.package(url: "<repositoryURL>", from: "<version>")],
      targets: [.target(name: "<slug>_shim",
                        dependencies: [.product(name: "<productName>", package: "<identity>")])]
  )
  ```
  Shim source contains `@_exported import <ModuleName>` so `import Alamofire` in the app resolves. **Risk:** proxy product name equals the real product name in the same graph — SPM may reject duplicate product names depending on toolchain; the spike must confirm on Swift 6.0.
- **Option B — root-proxy direct dependency (fallback):** skip the per-slug proxy for miss/ignored; `generateRootProxy` (`ProxyGenerator.swift:124`) adds the original package to `dependencies` and its product to `spm_cache_root`'s target deps. Avoids name collision entirely, but app targets whose product deps were re-pointed at the proxy (`installer.rb:163-168` sets `product_name` per original dep) then need those specific products vended — meaning the installer must instead keep the original package reference in the Xcode project for miss/ignored packages (i.e., only remove/replace package refs for `hit` packages). Larger installer change, but collision-proof.

**Decision gate:** spike both against a sample project with one hit + one miss; pick the one that builds and links. Record choice in this file before proceeding.

## Related Code Files

- Modify: `tools/spm-cache-proxy/Sources/Core/Generator/ProxyGenerator.swift` — miss/ignored branch of `generateProxyManifest` + shim source generation (`@_exported import`), or root-proxy changes per spike outcome
- Modify: `tools/spm-cache-proxy/Sources/Core/Lockfile.swift` — only if module name ≠ product name mapping is needed (add `moduleName` passthrough)
- Modify (Option B only): `lib/spm_cache/installer.rb` — `integrate_proxy_into_project` keeps original package refs for miss/ignored packages
- Modify: `lib/spm_cache/spm/pkg/proxy.rb` — no change expected; verify graph loading still correct

## Implementation Steps

1. **Spike (timeboxed):** hand-write both manifest variants for one real package (e.g. swift-log) in a scratch project; `xcodebuild` resolve+build; record which links. If both work, choose Option A (smaller change surface).
2. Implement the chosen variant in `generateProxyManifest` miss branch; ignored branch uses the identical source path (per validation decision: ignored = always source, even on cache hit).
3. Replace the empty stub write (`ProxyGenerator.swift:53-55`) with shim source containing `@_exported import <module>` (Option A) or remove stub generation for miss (Option B).
4. Handle local packages: `pathFromRoot` → `.package(path:)` with path resolved relative to the proxy dir (compute correct relative hops from `.proxies/<slug>/` back to project root).
5. Rebuild (`make proxy.build`); run `spm-cache use` on a sample project with an empty cache; confirm the app builds — this is the REQ-003 acceptance test.

## Success Criteria

- [ ] Sample app with 0 cached packages: `spm-cache use` → Xcode build succeeds, all imports resolve from source
- [ ] Sample app with 1 hit + 1 miss: hit links binary, miss compiles source, both import correctly
- [ ] Ignored package with a cached binary present: source is used (binary bypassed)
- [ ] Local package (`pathFromRoot`) miss resolves via `.package(path:)`
- [ ] No duplicate-product-name resolution errors on Swift 6.0 toolchain
- [ ] Spike outcome + chosen option recorded in this file

## Risk Assessment

- **Duplicate product names (Option A):** primary risk; the spike exists to retire it early. Mitigation: Option B is collision-proof by construction.
- **`@_exported import` module name mismatch:** product name ≠ module name for some packages (e.g. product "Collections" → modules "OrderedCollections"…). Lockfile has no module list. Mitigation: use product-level re-export via target dependency (works without `@_exported` for linking; `@_exported` only aids the app's `import X` where X is the product's module). Document the limitation for multi-module products; graph entries for such products may need `productName` refinement — flag during spike.
- **Version pinning drift:** `versionRequirement` uses `from:` (`Lockfile.swift:30-41`), so source fallback may resolve a newer version than the cached binary was built from. Acceptable for this plan (matches umbrella behavior); note in docs.
