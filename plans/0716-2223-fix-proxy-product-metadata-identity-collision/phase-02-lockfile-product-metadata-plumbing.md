---
phase: 2
title: "Lockfile product metadata plumbing"
status: pending
effort: "M"
priority: P1
dependencies: []
---

# Phase 2: Lockfile product metadata plumbing

## Overview

Populate `spm-cache.lock` with real product metadata (`products: [{name, type, targets}]` per package) from `swift package describe`, and make the Swift generators consume it — fixing the identity-as-product-name fallback that broke 53/59 packages (triage Bug 1). Amended per red-team review: the original design assumed checkouts exist before `gen_proxy`; they do not, in any flow — checkout materialization must be moved.

## Requirements

- Functional: umbrella and proxies declare/consume real library product names; multi-product packages (Realm → `Realm`+`RealmSwift`) export ALL library products from their proxy, each with its own shim target importing the product's real MODULE names (`products[].targets`).
- Non-functional: backward compatible — a lockfile without `products` must still work via the old `productName ?? name ?? slug` fallback; stale lockfiles get enriched in place. Pin drift (versions changed in `Package.resolved` while `spm-cache.lock` exists) remains a NON-GOAL this round (`return if File.exist?` at installer.rb:79 untouched for pins) — explicit, so it isn't rediscovered as a regression.

## Architecture

**Corrected pipeline (red-team BLOCKER 1):** today no flow runs `swift package resolve` before `gen_proxy` — `Proxy#prepare` (proxy.rb:21-44) is `gen_umbrella → invalidate_cache → gen_proxy`; the only resolve lives in `Installer::Build#resolve_umbrella_checkouts` (build.rb:63-74, with DerivedData fallback at :76-107) and runs after integration, `build` flow only; `recreate_dirs` (installer.rb:48-55) wipes the sandbox every run. Fix:

```
sync_lockfile (pins only, unchanged)
  → gen_umbrella
  → materialize_checkouts (MOVED: shared resolve + DerivedData fallback, all flows)
  → enrich_lockfile_products (NEW: Desc::Description per checkout → products[] into spm-cache.lock)
  → gen_proxy (reads products[])
```

- Extract `resolve_umbrella_checkouts` + `fallback_xcode_checkouts` from `Installer::Build` into a shared module; call from `prepare` (all flows); `Installer::Build` drops its now-duplicate call.
- Soundness: `swift package resolve` does not validate `.product(name:)` references (that's build-time), so resolving the pre-enrichment umbrella with wrong names is safe. Resolve failure → existing DerivedData fallback → per-package legacy fallback + warn (offline path).
- Cost note (user-facing, → Phase 4 docs): `use` gains a resolve step — network on cold SwiftPM cache, mitigated by SwiftPM global cache + DerivedData fallback.

**graph.json granularity decision:** one `GraphEntry` PER LIBRARY PRODUCT (not per package). Ripple effects, all in scope:
- `BuildPipeline` runs once per product → N xcodebuild passes over the same checkout for an N-product package (cost documented; acceptable — each product is a distinct xcframework).
- CLI target names change (`spm-cache build realm-swift` → `Realm` / `RealmSwift`) — user-facing, documented in Phase 4. VALIDATED DECISION: package identity stays usable as an ALIAS — in `filter_requested_targets!` (installer/build.rb:47-59), a requested name equal to a package identity expands to all that package's library products; product names match directly.
- `matchesAnyPattern` (ignore/cache_only globs): match against ANY library product name OR package identity; the resulting status applies to ALL of that package's products (package-level decision, matches existing gen_proxy_ignore_spec expectations).
- Shims: one shim target + sources dir PER product; `@_exported import` uses the product's `targets` (module names), not the product name.

**Cache-key invalidation (red-team M3):** `BinariesCache.hit(module:)` keys on `<module>.xcframework`; renaming modules from identity to real product names makes every existing cached binary unreachable → full rebuild for existing users, stale files linger (no GC). This is CORRECT — old binaries were built with `module_name` = identity, i.e. broken. Release notes must say so (Phase 4).

Schema (per package entry in `spm-cache.lock`):
```json
{ "name": "realm-swift", "repositoryURL": "...", "version": "...",
  "products": [
    {"name": "RealmSwift", "type": "library", "targets": ["RealmSwift"]},
    {"name": "Realm", "type": "library", "targets": ["Realm"]}
  ] }
```

**Write-path trap:** `Core::Lockfile::Pkg#to_h` (core/lockfile.rb:44-52) projects a whitelist and would silently DROP `products` on save — write via `@raw`/deep merge or extend `Pkg` to round-trip `products`.

## Related Code Files

- Modify: `lib/spm_cache/installer/build.rb` — extract `resolve_umbrella_checkouts`/`fallback_xcode_checkouts` (`:63-107`) to shared module; adapt dormant `product_name` branch (`:122-125`) to `products` array.
- Create: shared checkout-materialization module (e.g. `lib/spm_cache/spm/checkout_resolver.rb` — follow existing module layout under `lib/spm_cache/spm/`).
- Modify: `lib/spm_cache/spm/pkg/proxy.rb` — `prepare` gains materialize + enrich steps between `gen_umbrella` and `gen_proxy`.
- Modify: `lib/spm_cache/installer.rb` — `enrich_lockfile_products` implementation (owns lockfile writes).
- Modify: `lib/spm_cache/core/lockfile.rb` — `Pkg` round-trips `products` (`:44-52` projection trap).
- Modify: `tools/spm-cache-proxy/Sources/Core/Lockfile.swift` — `PackageRef.products: [ProductRef]?` (`:4-10`, `:56-68`); `libraryProductNames`/`libraryProducts` with legacy fallback.
- Modify: `tools/spm-cache-proxy/Sources/Core/Generator/UmbrellaGenerator.swift` (`:18-35`), `ProxyGenerator.swift` (`:63-110`, `:133-175`, shims `:96-101`/`:199-205`, `sourceDependencyLines` `:180-195`, `matchesAnyPattern` `:29-39`) — per-product emission per the granularity decision.
- Modify: `spec/fixtures/*.json`, `spec/gen_proxy_*_spec.rb`; Create: `spec/lockfile_enrichment_spec.rb`, sequencing spec.

## Implementation Steps

1. Extract checkout materialization into the shared module; wire into `prepare` for all flows; remove the duplicate from `Installer::Build`. Add the sequencing spec FIRST (red-team amendment: assert checkouts materialize before enrichment — use a local path-based fixture package so no network is needed).
2. Implement `enrich_lockfile_products`: per lockfile package, locate checkout (umbrella checkouts → DerivedData fallback), run `Desc::Description`, write `products` (name, type, targets) via a round-trip-safe path (step guards `Pkg#to_h` trap). Missing checkout → leave entry unchanged, warn once, legacy fallback downstream. Idempotent: only enrich entries missing `products`.
3. Swift: extend `Lockfile.PackageRef`; per-product `GraphEntry` emission; per-product shim targets importing `targets` module names; `matchesAnyPattern` per the decision above; cache-hit per product.
4. Multi-product package status: each product gets its own hit/miss status (per-product entries make the old "all products hit" package rule moot — a package's products are independent cache entries now).
5. Fixtures: multi-product package (hand-written `products[]` — red-team verified Swift side is fixture-testable this way), legacy products-less entry (fallback), product-name≠module-name case.
6. Specs: enrichment (mocked `Desc`), sequencing (real, path-based), fixture specs for per-product manifests/graph, legacy fallback.

## Success Criteria

- [ ] Sequencing spec proves checkouts exist before enrichment in the `use` flow (not just `build`).
- [ ] `spm-cache.lock` entries carry `products` (name/type/targets) after a run against a resolved project.
- [ ] Proxy manifest for a multi-product fixture exports every library product by real name, with per-product shims importing module names.
- [ ] `graph.json` has one entry per library product; ignore/cache_only globs match product name or identity.
- [ ] `spm-cache build <identity>` still works via the alias expansion (spec in installer_build_spec.rb).
- [ ] Legacy lockfile without `products` still generates via fallback — no crash, warning emitted.
- [ ] Existing + new rspec and `swift test` green.

## Risk Assessment

- `use` flow gains resolve wall-time/network → DerivedData fallback + SwiftPM global cache mitigate; offline path documented; warn-not-abort per package.
- Existing binary caches fully invalidated by module rename → correct (old binaries mis-moduled); release-notes callout in Phase 4; no GC this round.
- N-product packages build N times → acceptable per-product xcframeworks; cost documented.
- Pin-drift staleness explicitly deferred (non-goal).
