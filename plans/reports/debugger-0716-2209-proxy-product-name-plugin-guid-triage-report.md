# Triage: 3 field-reported proxy-generation bugs (spm-cache, reported v0.1.2, confirmed still present at HEAD)

Scope: read-only investigation of tools/spm-cache-proxy/Sources (Swift) + lib/spm_cache (Ruby). No code changed. One empirical repro built under `/private/tmp/.../scratchpad/repro*` using real `swift build` to prove/disprove SwiftPM behavior claims (not committed to repo).

## Executive summary

All three bugs trace back to **one missing pipeline step**: nothing in spm-cache ever runs `swift package describe --type json` (or equivalent) per resolved dependency and feeds real product metadata (name, type) into `spm-cache.lock`. The lockfile writer only copies `Package.resolved` pin fields (identity, url, version, revision) — never product info. Downstream code (Swift `Lockfile.PackageRef`, Ruby `checkout_map`) already has dead/no-op fallback paths waiting for a `product_name` key that is never populated. Bug 3 is structurally independent (a package-identity collision in the proxy's own dependency graph, confirmed by direct repro), but its most visible failure mode is amplified by Bug 1 being unfixed.

| Bug | Root cause file:line | Confirmed | Shared root w/ | Effort |
|---|---|---|---|---|
| 1 — wrong product names | `lib/spm_cache/installer.rb:89-98` (never writes `product_name`); consumed at `tools/spm-cache-proxy/Sources/Core/Lockfile.swift:27-29` | Yes (static, dead-code trace) | Bug 2 | Medium |
| 2 — plugin-only packages break proxy | `tools/spm-cache-proxy/Sources/Core/Generator/UmbrellaGenerator.swift:30-35` and `ProxyGenerator.swift:63-110` (no product-type filter exists anywhere) | Yes (static; no `type`/`plugin` concept in the Lockfile schema at all) | Bug 1 | Medium (schema change) |
| 3 — duplicate product GUID / graph won't load | `ProxyGenerator.swift:64-66` (proxy dir named `slug`) + `ProxyGenerator.swift:180-195` (`sourceDependencyLines`) | **Yes — reproduced with real `swift build`** | Independent | Small (one rename) |

---

## Bug 1 — Wrong product names (53/59 packages)

**Code path traced:** `Installer#sync_lockfile` (`lib/spm_cache/installer.rb:66-75`) → `generate_lockfile_from_resolved` (`lib/spm_cache/installer.rb:77-106`) writes `spm-cache.lock` straight from `Package.resolved` pins:

```ruby
"packages" => pins.map do |pin|
  {
    "repositoryURL" => pin["location"],
    "name" => pin["identity"],
    "version" => pin.dig("state", "version"),
    "revision" => pin.dig("state", "revision"),
  }
end
```
(`lib/spm_cache/installer.rb:91-98`) — **no `product_name` key is ever written**, for any package, ever. `generate_lockfile_from_resolved` also short-circuits entirely if the lockfile already exists (`return if File.exist?(lockfile_path)`, line 79), so even upgrading spm-cache doesn't regenerate a stale lockfile with better data.

That JSON is read by the Swift CLI: `Lockfile.PackageRef` (`tools/spm-cache-proxy/Sources/Core/Lockfile.swift:56-68`) parses `product_name` (line 64) into `productName: String?`, and:
```swift
var resolvedProductName: String {
    productName ?? name ?? slug   // Lockfile.swift:27-29
}
```
Since `productName` is always `nil` from the Ruby writer, this always falls back to `name` (== package identity == `realm-swift`, not `RealmSwift`). This value (`resolvedProductName`) is what `ProxyGenerator` uses everywhere it emits a `.library(name: ...)` product or a `.product(name:package:)` dependency (`ProxyGenerator.swift:65,84,145,162,186,192,213,215`) and what `UmbrellaGenerator` uses to declare the umbrella's own product dependency (`UmbrellaGenerator.swift:20,33`). Since the umbrella runs `swift package resolve`/build first (`lib/spm_cache/spm/pkg/proxy.rb:34` `gen_umbrella` before `gen_proxy`), resolution fails at the very first step for any package whose real product name differs from its identity — matches "package resolution fails immediately."

**Corroborating dead code:** `lib/spm_cache/installer/build.rb:122-125` already special-cases `pkg["product_name"]` for checkout-dir lookup — this branch has literally never executed in production because the field it checks for is never written. This is strong evidence the "populate product_name" step was intended/half-built but never wired in.

**Note on the recent related fix:** `afad0c1` added `SPMCache::SPM::BuildPipeline.resolve_scheme` (`lib/spm_cache/spm/build_pipeline.rb:141-155`), which *does* call `swift package describe` via `Desc::Description` (`lib/spm_cache/spm/desc/base.rb:52`) — but only to pick an **Xcode scheme** at build time, per package, after checkout. It is not called during lockfile generation and its result is never persisted back into `spm-cache.lock`. Proxy generation (which happens before any build) has the identical identity-vs-product confusion that afad0c1 fixed for scheme selection, just unfixed.

**Proposed fix:** In `generate_lockfile_from_resolved` (or a new step run right after it, still inside `sync_lockfile`), for each pin, checkout/locate the package (checkouts are already resolved via the umbrella in the Build flow; for the plain install flow a lightweight `swift package describe` against the pin's checkout, or reuse `Desc::Description` per pin) and write real library-product name(s) into the lock entry. Given `SPM::Desc::Description#products` / `Desc::Product#type` (`lib/spm_cache/spm/desc/product.rb:23-26`) already parses `swift package describe` output and distinguishes `library` from other types, this is largely "call existing code from a new place," not new parsing logic.

**Schema caveat:** `Lockfile.PackageRef` (both Ruby hash and Swift struct) is 1 pkg → 1 `product_name` (singular). Real packages routinely expose multiple library products per identity (Firebase, GRDB, etc. all cited in the field report's package list). A minimal fix (populate first/best-matching library product) unblocks single-product packages but under-serves multi-product ones — recommend evolving the schema to `product_names: [String]` (or one lockfile pkg entry per exported product) as a follow-up, not required to close this bug for the reported single-product cases.

**Severity:** High (blocks 53/59 packages, i.e., de-facto blocks the whole feature for any non-trivial real project).
**Effort:** Medium — no new parsing needed (reuse `Desc::Description`), but touches the lockfile schema (Ruby writer + Swift `Lockfile.PackageRef`) and needs checkout resolution ordering to be right (packages must be checked out before `describe` can run on them).

---

## Bug 2 — Build-tool plugin packages break the graph (SwiftGenPlugin)

**Root cause:** `Lockfile.PackageRef` carries no product-type information at all — no `type`, no `isLibrary`, no list of products, just an optional singular `productName` string (`Lockfile.swift:4-10`). Every consumer treats every package as if it exports exactly one library product:
- `UmbrellaGenerator.generate()` unconditionally emits a `.target` depending on `.product(name: productName, package: packageIdentity)` for every `pkg in lockfile.packages`, no skip/filter (`UmbrellaGenerator.swift:18-35`).
- `ProxyGenerator.generate()` unconditionally emits a proxy `Package.swift` with `.library(name: productName, ...)` for every `pkg in packages`, no skip/filter (`ProxyGenerator.swift:63-110`, manifest body at `133-175`).

For `SwiftGenPlugin` (a package with only a `.plugin` product, no library product), both generators still try to declare/consume a library product named `SwiftGenPlugin` (falls back through the same `resolvedProductName` chain as Bug 1, since it too has no `product_name` in the lockfile). That product does not exist in the real package's manifest → `swift package resolve`/build fails on the **umbrella** step, before proxy generation even gets a chance to run, i.e. this is a harder blocker than Bug 1 for the affected package (whole graph resolution fails, not just one wrong name).

**Confirmed statically:** grepped the entire Lockfile/ProxyGenerator/UmbrellaGenerator source — no `type`, `plugin`, `.select { library }`-style filter exists anywhere in `tools/spm-cache-proxy/Sources`. There is no code path that could skip a plugin-only package even if the lockfile did have accurate names.

**Proposed fix:** Two coordinated changes, sharing Bug 1's metadata-population work:
1. Ruby: when populating real product metadata (Bug 1 fix), also record whether the package has *any* library product (`Desc::Product#type == "library"`, already available at `lib/spm_cache/spm/desc/product.rb:23-26`). Write e.g. `"has_library": false` or omit `product_name` entirely with a `"kind": "plugin"` marker for such packages.
2. Swift: in `UmbrellaGenerator.generate()` (`UmbrellaGenerator.swift:18`) and `ProxyGenerator.generate()` (`ProxyGenerator.swift:63`), skip (`continue`) packages that have no library product — don't emit a dependency/target/proxy entry for them at all. Plugin packages aren't binary-cacheable the same way libraries are; they should either be left entirely untouched by spm-cache (excluded from the proxy rewiring so Xcode still resolves them directly/normally) or explicitly passed through as source-only with their original plugin product dependency preserved on the Ruby/xcodeproj side (`lib/spm_cache/installer.rb:134-174` `integrate_proxy_into_project`, which currently rewires **every** old product dependency onto the proxy — line 165-170 `old_deps.each` has no type check either, so even if generation didn't crash, plugin-type product dependencies would be pointed at a proxy package with no such product).

**Severity:** High for affected packages (total resolution failure, not just naming — blocks the umbrella step for the entire graph, not just this package).
**Effort:** Medium — needs the Bug 1 metadata plumbing plus a skip-list check in 2 Swift generators and 1 Ruby integration site (`installer.rb:165`).

---

## Bug 3 — Duplicate product GUIDs (eh_oauth_sdk_ios-style identity==product packages)

**Empirically reproduced and root-caused** (not just static inference) using a minimal 3-package local fixture under `/private/tmp/.../scratchpad/repro` and real `swift build`.

Root cause: for any package that is **not a cache hit** (i.e. goes through the "miss"/"ignored" source-fallback branch — `ProxyGenerator.swift:152-174`, `sourceDependencyLines` at `180-195`), the local proxy sub-package directory is created at:
```swift
let proxyDir = proxiesDir.appendingPathComponent(slug)   // ProxyGenerator.swift:64-66
```
i.e. the **wrapper's own on-disk folder is named exactly `slug`** — the same identity string SwiftPM independently derives for the **real** upstream package the wrapper depends on (via `.package(url:...)` in `sourceDependencyLines`, `ProxyGenerator.swift:189-193`, or `.package(path:...)` for local pkgs, `182-187`). SwiftPM identifies packages globally by this identity string across the whole resolved graph, not per-manifest-scope.

**Repro (before fix):** built a 3-package graph (`root_proxy` → `proxies/eh_oauth_sdk_ios` [wrapper, folder literally named `eh_oauth_sdk_ios`] → `real_checkout/eh_oauth_sdk_ios` [the "real" package, also identity `eh_oauth_sdk_ios`]), mirroring exactly what `ProxyGenerator`+`generateRootProxy` (`ProxyGenerator.swift:207-237`) produce. `swift build` output:
```
warning: 'eh_oauth_sdk_ios': Conflicting identity for eh_oauth_sdk_ios: dependency '.../real_checkout/eh_oauth_sdk_ios' and dependency '.../proxies/eh_oauth_sdk_ios' both point to the same package identity 'eh_oauth_sdk_ios'. ... This will be escalated to an error in future versions of SwiftPM.
error: cyclic dependency declaration found: RootTarget -> ShimTarget -> ShimTarget
```
SwiftPM collapses the two same-identity graph nodes into one, so the shim's own dependency on the *real* package's product resolves back onto *itself* — a self-cycle. This is the mechanism behind "Xcode refuses to load the dependency graph" / duplicate `PRODUCTREF-PACKAGE-PRODUCT` GUIDs reported for `eh_oauth_sdk_ios` (Xcode's own SwiftPM-graph-driven package integration hits the same identity collision, surfacing as a duplicate/blocked product reference rather than a clean CLI error).

**Important scope correction vs. the bug's framing:** I re-ran the identical repro with `productName != identity` (`realm-swift` → product `RealmSwift`) to test whether this is really specific to identity==product packages. It is **not** — the same "Conflicting identity" warning + `cyclic dependency` error reproduced identically. The defect is generic to *any* package that takes the miss/source-fallback path; `eh_oauth_sdk_ios` is simply the case where the resulting duplicate string (`eh_oauth_sdk_ios-...-eh_oauth_sdk_ios`) is visually/grep-obviously a duplicate, and (per Bug 1) is also a package whose `resolvedProductName` collapses to its identity, making it doubly likely to be the one a user notices and reports. Packages where identity != product likely hit the *same* underlying SwiftPM error class, just with less obviously-duplicated-looking names in the failure text — worth flagging to the user as a broader-than-reported defect, though out of the explicit repro scope requested.

**Fix confirmed by repro:** renaming only the wrapper's own folder (and all `.proxies/<slug>` path references to it) to something that doesn't collide with the real package's identity — e.g. `<slug>_proxy`, which conveniently is *already* the manifest's own `name:` field (`ProxyGenerator.swift:143,160`) but not its folder — eliminates the collision entirely. Re-ran the identical `eh_oauth_sdk_ios` 3-package graph with the wrapper folder renamed to `eh_oauth_sdk_ios_proxy` (and root's dependency/product-package references updated to match): **clean `swift build`, no warning, no error, `Build complete!`**

**Proposed fix (files/lines):**
1. `ProxyGenerator.swift:64-66` — change `proxyDir` from `proxiesDir.appendingPathComponent(slug)` to `proxiesDir.appendingPathComponent("\(slug)_proxy")` (or any suffix guaranteed not to equal the wrapped package's own identity).
2. `ProxyGenerator.swift:214` (`generateRootProxy`, `.package(path: ".proxies/\(slug)\")`) — update to the new folder name.
3. `ProxyGenerator.swift:215` (`.product(name: productName, package: "\(slug)")`) — the `package:` argument must reference the *wrapper's* identity (which, once renamed, is `\(slug)_proxy`, matching its manifest `name:` already at line 143/160), not the real package's identity.
4. Any other path that constructs `.proxies/<slug>` (grep for `.proxies/` — confirm none of `Resolve.swift`/`Resolver.swift`/Ruby side hardcode the old convention; `Resolver.swift` is currently a no-op stub so N/A there).

**Severity:** Hard blocker where it hits (per report: survives DerivedData wipe, matches — this is a structural manifest defect, not a build cache staleness issue, so wiping caches can never fix it).
**Effort:** Small — one folder-naming convention change plus updating the 2-3 string interpolations that reference it. No schema change, independent of Bug 1/2 fixes. Recommend fixing this first since it's cheapest and has a verified-working fix.

---

## Are the fixes independent or a shared root?

- **Bug 1 & Bug 2 share a root**: absence of any real `swift package describe` product metadata in the lockfile pipeline. A single "populate lockfile with real product info (name + type) per resolved package" change (Ruby `installer.rb` + Swift `Lockfile.PackageRef` schema) is prerequisite plumbing for both; Bug 2 additionally needs a "skip if no library product" filter in the two Swift generators plus the Ruby integration step, which is cheap once the type info exists.
- **Bug 3 is independent** — it's a package-identity-collision bug in the proxy's own generated dependency graph (folder-naming), unrelated to product-name accuracy or product type. It can and should be fixed on its own, first, since it's the smallest change and has a verified (`swift build`-tested) fix.

## Unresolved questions
- Whether `eh_oauth_sdk_ios` was actually in the **miss/ignored** branch in the user's real run (I inferred this because it's plausible it's an uncached internal SDK) or the **hit/cached-binary** branch — the identity-collision repro applies specifically to the miss/ignored source-fallback branch (`ProxyGenerator.swift:152-174`); the cache-hit branch (`136-151`) has no nested `.package()` dependency at all and so cannot hit this specific collision. If it turns out to be a cache-hit-status package, Bug 3's root cause would need to be re-derived (candidate: multi-.xcodeproj workspace where `integrate_proxy_into_project`, which only rewires one `@project_path`, leaves a second target/project's original SPM reference to the same package intact — not confirmed, no multi-project evidence in the task input).
- Whether the broader "same bug affects any miss-status package, not just identity==product ones" (shown by my `realm-swift` repro) was already silently occurring for other packages in the user's run but simply wasn't singled out in their report.
- Real-world checkout-availability timing for the Bug 1 fix: `generate_lockfile_from_resolved` currently runs before any package is checked out under spm-cache's own control; running `swift package describe` per pin requires either checking packages out first (ordering change) or reusing Xcode's/umbrella's already-resolved checkouts — needs a design decision, not resolved here since fixes were out of scope.

Status: DONE
Summary: All three bugs root-caused with file:line evidence; Bug 3 additionally empirically confirmed and fixed via a real `swift build` repro (before/after). Bugs 1+2 share one missing metadata-population step; Bug 3 is an independent, small, verified fix.
Concerns/Blockers: See "Unresolved questions" above — Bug 3's scope may be broader than reported (affects any miss-status package, not just identity==product ones), and its root cause assumes eh_oauth_sdk_ios was in the miss/ignored branch (plausible but not directly confirmed from the task input).
