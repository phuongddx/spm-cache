---
phase: 3
title: "Plugin-only package handling"
status: pending
effort: "M"
priority: P1
dependencies: [2]
---

# Phase 3: Plugin-only package handling

## Overview

Skip packages with no library product (build-tool plugins like SwiftGenPlugin) in both Swift generators, and keep their original references intact during Xcode project integration — fixing the whole-graph resolution failure (triage Bug 2). Amended per red-team review: keep-set logic inverted from the original draft; dep-exemption mechanism now specified.

## Requirements

- Functional: a plugin-only package (a) gets no umbrella dependency, (b) gets no proxy wrapper, (c) keeps its ORIGINAL remote package reference and product dependencies in the Xcode project after integration, so the plugin still runs.
- Non-functional: mixed packages (library + plugin products) are treated as library packages — library products proxied, plugin products out of scope (documented limitation). LOCAL plugin-only packages (`XCLocalSwiftPackageReference`) are out of scope: they have no lockfile entry (Package.resolved carries no local pins) and no URL to match — pre-existing gap, documented, not a regression.

## Architecture

Phase 2 gives every lockfile entry `products: [{name, type, targets}]`. "Plugin-only" = entry has products metadata AND none of type `library`. Entries WITHOUT metadata (legacy fallback) are treated as library packages (status quo — never silently drop a package on missing data).

Enforcement sites:

1. `UmbrellaGenerator` — skip plugin-only packages (no `.package`, no `.product` dep). *Optional simplification worth evaluating first (red-team minor 6): the umbrella's stub `.target` product references are pure liability — its only runtime role is checkout materialization via resolve. Dropping product/target references from the umbrella manifest entirely makes resolve immune to wrong/plugin product names and shrinks this phase's umbrella change to nothing. Evaluate; adopt if `swift package resolve` still fetches dependency checkouts without target references (verify with a quick local experiment before committing to it).*
2. `ProxyGenerator` — skip: no wrapper folder, no root-proxy dependency; emit `graph.json` entry with new `plugin` status (mirror the `excluded` wiring from v0.1.3: `Cachemap` accessor + stats + print, `installer/build.rb` known-target + distinct warning, cachemap.js.template node style).
3. Ruby `integrate_proxy_into_project` (installer.rb:134-174) — **keep-set rule (inverted from draft, red-team BLOCKER 2):**
   - KEEP exactly: package references that URL-match (normalized: scheme, host case, trailing `.git`, ssh↔https) a plugin-only lockfile entry.
   - STRIP everything else — including ALL `XCLocalSwiftPackageReference`s — exactly as today. This is what keeps re-runs idempotent (the previous run's proxy ref must always be stripped) and prevents duplicate-identity refs (an unmatched-but-preserved library ref alongside proxy-rewired product deps would recreate Bug 3 at the Xcode layer).
   - If a plugin-only lockfile entry matches NO project ref: warn loudly (visible "plugin may break" signal) — never preserve arbitrary unmatched refs as a fallback.
   - **Dep exemption mechanism (red-team M1):** `old_deps` currently captures only `{target:, product: dep.product_name}` (installer.rb:139-144), discarding the `dep.package` association before the strip. Change: capture `dep.package` too (available — `XCSwiftPackageProductDependency` `has_one :package`, verified in xcodeproj 1.28.1). Exempt a product dep from BOTH the delete loop (:151-156) and the rewire loop (:165-170) when its package is a kept ref OR its `product_name` starts with `"plugin:"` (Xcode serializes build-tool-plugin deps with that prefix — cheap second belt; rewiring them onto the proxy is today's silent corruption).

## Related Code Files

- Modify: `tools/spm-cache-proxy/Sources/Core/Generator/UmbrellaGenerator.swift` (`:18-35`) — skip filter (or stub-target removal if the optional simplification pans out).
- Modify: `tools/spm-cache-proxy/Sources/Core/Generator/ProxyGenerator.swift` (`:63-110`) — skip filter + `plugin` in `GraphEntry.Status`.
- Modify: `lib/spm_cache/installer.rb:134-174` — keep-set + dep-exemption logic per Architecture.
- Modify: `lib/spm_cache/cache/cachemap.rb`, `lib/spm_cache/installer/build.rb`, `lib/spm_cache/assets/templates/cachemap.js.template` — `plugin` status wiring (checklist: the v0.1.3 `excluded` diff).
- Modify/Create: fixture lockfile with plugin-only entry (hand-written `products: [{type: "plugin"}]`); `spec/gen_proxy_plugin_spec.rb`; installer integration spec (temp `.xcodeproj` — installer_spec.rb already builds one) covering: kept plugin ref, stripped library refs, stripped stale proxy ref on re-run, exempted `plugin:`-prefixed dep, loud warning on unmatched plugin entry.

## Implementation Steps

1. Decide the umbrella question first (experiment: does a target-reference-free umbrella manifest still materialize checkouts on resolve?). Then implement generator skips accordingly.
2. Swift: `isPluginOnly` helper on `Lockfile.PackageRef`; skips + `plugin` graph status.
3. Ruby: `plugin` status through `Cachemap`/build warnings/template.
4. Ruby: integration keep-set + dep exemption per Architecture (URL normalization helper with specs for ssh↔https/`.git` forms).
5. Fixtures + the five integration spec cases listed above; mixed library+plugin package case (only library products proxied).
6. Full suite run.

## Success Criteria

- [ ] Plugin-only fixture package: absent from umbrella manifest, no `.proxies/` folder, `graph.json` shows `plugin` status.
- [ ] Integration spec: plugin ref + its product deps survive; all other refs (incl. a pre-seeded stale proxy ref) stripped; re-run produces no duplicate proxy refs.
- [ ] `plugin:`-prefixed product deps are never rewired onto the proxy.
- [ ] Unmatched plugin-only lockfile entry produces a loud warning, not a preserved ref.
- [ ] Mixed-products package: library products proxied, no crash.
- [ ] Full rspec + `swift test` green.

## Risk Assessment

- URL normalization misses an exotic remote form → dep stays exempted only if its ref was kept; a missed match degrades to today's behavior (plugin stripped) + loud warning — visible, not silent corruption.
- Local plugin-only packages remain broken (pre-existing, documented out of scope).
- Legacy lockfiles (no metadata) keep today's behavior for plugin packages until enriched — Phase 2's enrich-on-missing closes this automatically.
