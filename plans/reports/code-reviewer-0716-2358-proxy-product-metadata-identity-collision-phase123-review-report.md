# Code Review: proxy product-metadata + identity-collision fix (Phases 1-3)

Scope: uncommitted diff implementing `plans/0716-2223-fix-proxy-product-metadata-identity-collision/` phases 1-3 (phase 4 docs/release excluded per instructions). Verified against the plan's phase-01/02/03 requirements, ran the built `spm-cache-proxy` release binary, and reproduced a real `swift build` failure with local fixtures (no network).

## Critical Issues

### 1. `generateRootProxy` still wires product deps by package identity, not real product name — breaks `swift build` for every enriched multi-product/mismatched-identity package (the exact case Phase 2 exists to fix)

`tools/spm-cache-proxy/Sources/Core/Generator/ProxyGenerator.swift:258-268`:

```swift
for pkg in packages {
    let slug = pkg.slug
    let productName = pkg.resolvedProductName   // == productName ?? name ?? slug (legacy, singular)
    deps.append(".package(path: \".proxies/\(slug)_proxy\")")
    targetDeps.append(".product(name: \"\(productName)\", package: \"\(slug)_proxy\")")
}
```

`resolvedProductName` was never updated for the new `products[]` array (Lockfile.swift:64-67 — still `productName ?? name ?? slug`, i.e. the package's lockfile *identity*, not one of its real library product names). But the sub-proxy package it references (`generateProxyManifest`, same file, lines ~178-224) now declares its products under their **real** names (e.g. `RealmSwift`, `Realm`), never under the package identity. So the root proxy's own target (`spm_cache_root`) depends on a product name that does not exist in the very package it just declared a dependency on.

Reproduced directly (isolated, local git repo, no network — see commands below): generated root `Package.swift` for a two-product local package (`MyLib` → products `ProductA`/`ProductB`) emits:

```swift
.target(name: "spm_cache_root", dependencies: [
    .product(name: "MyLib", package: "MyLib_proxy")
], path: "src/root")
```

Running `swift build` against the generated proxy tree fails:

```
error: 'proxy': product 'MyLib' required by package 'proxy' target 'spm_cache_root' not found in package 'MyLib_proxy'.
```

Also reproduced against the repo's own `spec/fixtures/products-lockfile.json` (Realm/RealmSwift fixture) — the generated root manifest is:

```swift
.product(name: "realm-swift", package: "realm-swift_proxy")
```

while `realm-swift_proxy`'s `Package.swift` only exports products `RealmSwift` and `Realm` — same failure mode.

**Impact**: `proxy_ref` (the `XCLocalSwiftPackageReference` installer.rb:220-223 adds to the real `.xcodeproj`) points exactly at this root `Package.swift` (`spm-cache/packages/proxy`). This is not an internal-only artifact — it's the package Xcode itself resolves/builds. Any package whose lockfile identity differs from its real product name(s) (the majority of the 53/59 field-reported cases, and specifically the Realm/RealmSwift fixture this phase was built to fix) will fail to resolve/build once `spm-cache.lock` is enriched with real `products[]` metadata. This regresses Phase 2's own headline bug (Bug 2: wrong product names) at the root-proxy layer, even though it's correctly fixed at the per-package proxy layer.

**Fix**: `generateRootProxy` must iterate `pkg.libraryProducts` (like `generate()` already does) and emit one `.product(name:, package:)` line per real library product, not one `resolvedProductName` line per package.

**Why this passed CI**: no spec exercises `swift build`/`swift package resolve` against the *generated proxy output* for a package with real `products[]` metadata. `spec/gen_proxy_products_spec.rb` and `spec/gen_proxy_field_regression_spec.rb` (the two specs that do use `products[]` fixtures) only assert graph.json module names, directory existence, and substring absence of the old `.proxies/<slug>` (non-`_proxy`) path in the root manifest — never that the root manifest's product name matches something the sub-proxy actually declares. The one spec that does read the root manifest against a `products[]`-bearing fixture (`gen_proxy_field_regression_spec.rb:63-67`) only checks for absence of collision paths, not correctness of the emitted product name. All other specs touching the root manifest (`gen_proxy_ignore_spec.rb`, `gen_proxy_cache_only_spec.rb`, `gen_proxy_plugin_spec.rb`) use fixtures with only the legacy `product_name` field (no `products[]`), where `resolvedProductName` and the sub-proxy's declared product name coincide by construction — masking the bug entirely. "`swift build -c release` clean" (task description) refers to building the `spm-cache-proxy` CLI tool itself, not the tool's generated output; it does not exercise this path.

**Repro commands** (for verification):
```bash
# build the local package, tag it, and generate + build the proxy tree
cd /Users/ddphuong/Projects/next-labs/spm-cache
./tools/spm-cache-proxy/.build/release/spm-cache-proxy gen-proxy \
  --umbrella <tmp>/umbrella --lockfile <lockfile-with-two-library-products> \
  --output <tmp>/proxy --cache <tmp>/cache
cd <tmp>/proxy && swift build   # fails: product '<identity>' ... not found in package '<slug>_proxy'
```

## High Priority

### 2. `enrich_lockfile_products` silently swallows `swift package describe` failures with no warning and no retry-avoidance

`lib/spm_cache/installer.rb:145-169`: when the checkout directory exists but `desc.fetch`/`desc.products` yields `[]` (e.g. `swift package describe` itself fails — `Desc::BaseObject.describe` rescues `GeneralError` and returns `{}`, `lib/spm_cache/spm/desc/base.rb:51-56`, pre-existing pattern), the code does `next if products.empty?` with **no warning at all** (contrast with the "no checkout found" branch, which does warn). Two consequences:
- Silent, unexplained fallback to legacy identity-based product naming for that package on every run — the exact bug this whole plan set out to fix — with no diagnostic trail.
- Because `pkg_data["products"]` is never set, this package is re-described (shells out to `swift package describe`) on *every* subsequent run indefinitely, since the idempotency guard (`next if pkg_data["products"]`) never triggers for it.

Recommend: warn on empty `products` the same way as the missing-checkout branch, so operators can see it and it doesn't look like a silently-correct legacy package.

## Medium Priority

### 3. `plugin_only_package?` / `isPluginOnly` classify any package with zero `library`-typed products as "plugin", including non-plugin executable-only packages

`lib/spm_cache/installer.rb:285-291` and `Lockfile.swift` `isPluginOnly` (`!products.contains { $0.type == "library" }`) — this matches the plan's architecture exactly ("none of type `library`" = plugin-only), so it's not a deviation from spec, but the naming is imprecise: a package that exports only an `executable` product (no library, no plugin) would also be classified `plugin` (graph status `plugin`, Xcode-side "keep ref as-is" treatment) even though it isn't a build-tool plugin. Low real-world likelihood (SwiftPM executable-only dependencies added via Xcode are rare) but worth a one-line doc/comment correction acknowledging the broader "non-library" semantics, since the current comments say "plugin" specifically.

### 4. `kept_refs.include?(package_ref)` relies on `Xcodeproj::Project::Object::AbstractObject#==`, which is structural (`to_hash` equality), not UUID/identity-based

Verified: `Xcodeproj::Project::Object::AbstractObject#==` (`xcodeproj-1.28.1/lib/xcodeproj/project/object.rb:483-485`) is `other.is_a?(AbstractObject) && to_hash == other.to_hash`. In the code path used here (`lib/spm_cache/installer.rb:196-235`), this happens to be safe in practice because `dep.package` and every ref in `project.root_object.package_references` are the *same canonical Ruby object* per UUID (Xcodeproj maintains one live object per UUID), so identity coincides with the structural check trivially (an object always structurally equals itself). However, if a project ever contains two genuinely distinct `XCRemoteSwiftPackageReference` objects with byte-identical attributes (duplicate "Add Package" actions, a known real-world Xcode footgun), `Array#include?` would treat them as interchangeable. This is a pre-existing Xcodeproj behavior, not introduced by this diff, and the plan explicitly asked to verify this — documenting it here as requested rather than as a new defect. No action required unless duplicate-ref corruption is a known issue in target projects.

### 5. `expand_target_aliases` (installer/build.rb:72-89) expands a package identity to *all* of its lockfile `products[]` entries, including non-`library` ones

For a "mixed" package (library + plugin products in the same lockfile entry — explicitly in-scope per phase-03's architecture: "mixed packages are treated as library packages, plugin products out of scope"), requesting the package identity via CLI (`spm-cache build <identity>`) expands to include the plugin product's name too, since `pkg["products"]` is not filtered to `type == "library"` here (contrast with `Lockfile.swift`'s `libraryProducts`, which does filter). That name won't appear in `all_known` (`missed + hit + ignored + excluded + plugin`, since ProxyGenerator never emits a graph entry for a mixed package's non-library products at all — `generate()` only processes `pkg.libraryProducts` for non-plugin-only packages), producing a spurious "unknown target" warning. Minor, edge-case (mixed packages), no functional breakage — just a confusing warning. Filter to `type == "library"` in `expand_target_aliases` for consistency with `libraryProducts`.

## Low Priority / Observations

- `enrich_lockfile_products` (installer.rb:159) and `checkout_map` (checkout_resolver.rb:67-89) each independently reconstruct `File.join(@config.umbrella_dir, ".build", "checkouts", slug)`. Not a bug, but the checkout-path construction logic is duplicated across two files; could be a single shared helper (`checkout_dir_for(pkg)`) in `CheckoutResolver` — minor DRY opportunity, matches YAGNI/DRY guidance loosely but not worth blocking on.
- `Core::Lockfile::Pkg#to_h`'s new `products` round-trip (core/lockfile.rb:44-53) is currently dead code for the write path: nothing in `lib/` calls `Pkg.new(...).to_h` to reconstruct the lockfile (writes go through raw-hash mutation in `enrich_lockfile_products` and `generate_lockfile_from_resolved`, both of which read/write `@raw`/`@projects` directly, the same object). Harmless defensive parity per the phase-02 doc's "write-path trap" callout, but as implemented it protects a path that doesn't exist yet. Not a blocker — cheap insurance if a future writer starts using `Pkg#to_h`.
- Phase 1 rename verified correct and complete: `.proxies/<slug>_proxy`, `.package(path:)`, and `.product(name:package:)` `package:` argument are all consistently updated in `ProxyGenerator.swift`; dead `Sources/Core/Proxy/{ProxyPackage,ProxyPackageProtocol,RootProxyPackage}.swift` deletion confirmed zero remaining references anywhere under `tools/` or `lib/` (only stale `.build/` artifact-cache references, which are regenerated on next build).
- `UmbrellaGenerator.swift`'s stub-target removal (empty `targets: []`, no product/target references) is correct and matches the phase-03 "chicken-and-egg" requirement: only *already-known* plugin-only packages (enriched `products[]` present, no `library` entry) are skipped from the umbrella; unenriched packages (no `products` key yet) are still included so their checkout can be resolved once for `enrich_lockfile_products` to inspect. Verified via reading the code and the real (non-mocked) `spec/checkout_enrichment_sequencing_spec.rb`.
- `spec/installer_integrate_proxy_spec.rb` is solid: covers keep-set survival, stale-proxy-ref stripping, idempotency across repeated runs, `plugin:`-prefixed dep exemption, and loud-warning-on-unmatched-plugin-entry — all five success-criteria cases from phase-03 are present and exercise the real logic (not mocked away).
- `spec/checkout_enrichment_sequencing_spec.rb` is a genuine, non-mocked, offline (`file://`) end-to-end test of the resolve→enrich ordering with a real product-name-≠-package-identity fixture (`FixturePkg` → `FixtureLib`) — good evidence for the sequencing fix, but stops short of continuing into `gen_proxy` + `swift build`, which is exactly the next step that would have caught Critical Issue #1.

## Test Coverage Gaps (relative to phase-01/02/03 "Success Criteria")

- No spec builds (`swift build`/`swift package resolve`) the *generated proxy output* end-to-end for a `products[]`-bearing multi-product fixture. This is the single gap that let Critical Issue #1 through — every other check (graph.json, directory layout, per-package sub-proxy manifest, shim imports) is well covered.
- Phase 2 success criterion "`spm-cache.lock` entries carry `products` (name/type/targets) after a run against a resolved project" is covered only via the mocked `lockfile_enrichment_spec.rb` and the offline real-checkout `checkout_enrichment_sequencing_spec.rb` — no spec runs the full `use`/`build` flow end-to-end against a real multi-package project. Given the scope (unit + fixture-binary specs elsewhere in this codebase), this is consistent with existing test strategy, not a new gap introduced by this diff.

## Plan Follow-ups

- Phase 1: complete, verified correct.
- Phase 2: mostly complete; the lockfile enrichment, sequencing, Ruby-side `Pkg`/checkout plumbing, and per-package `ProxyGenerator`/shim logic are all correct and well-tested. The root-proxy manifest generator was missed — recommend treating Critical Issue #1 as a Phase 2 completion blocker before considering Phase 2 done, since it directly reintroduces the phase's own headline bug.
- Phase 3: complete, verified correct and well-tested (keep-set, dep-exemption, URL normalization, warning-on-unmatched, mixed-package handling).
- Recommend adding one fixture spec that runs `swift build` (or at minimum `swift package resolve` plus a `.product` name cross-check against the sub-proxy's declared products) on the generated root proxy for a `products[]` multi-product fixture, to close the coverage gap that let Critical Issue #1 ship.

## Unresolved Questions

- None — Critical Issue #1 is directly reproducible and the fix is localized to `generateRootProxy`; no design ambiguity blocks a fix.
