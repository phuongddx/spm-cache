# Phase 9: Cache Identity & Invalidation - Research

**Researched:** 2026-08-29
**Domain:** Cache invalidation via provenance comparison (Ruby installer + Swift proxy generator), spanning two languages and two call paths
**Confidence:** HIGH — every claim below is grounded in a `Read` of the actual source this session (paths + line numbers cited); no web research was needed, this is a pure codebase-tracing phase

## Summary

CACHE-02/CACHE-03 require making `BinariesCache.hit(module:)` (Swift) provenance-aware instead of
a bare `fileExists` check. Tracing the actual call path (the phase's stated open question #1)
surfaces three findings that materially change how this must be planned, none of which are visible
from CONTEXT.md alone:

1. **The comparison data is already co-located at the call site — no new data threading is
   needed.** `ProxyGenerator.swift:119`'s `for pkg in packages { ... cache.hit(module: product.name) }`
   loop already holds `pkg.name` (package identity) and `pkg.version`/`pkg.revision` (the
   host-reconciled current pin, care of Phase 6/7's FID-01/FID-02) in the exact same scope as the
   `hit()` call. The provenance sidecar's `pins` hash (written by Ruby, Phase 8) is keyed by that
   same identity string. `hit()` just needs two new parameters.

2. **A naive "sidecar missing ⇒ miss" rule, applied uniformly, breaks caching forever for every
   vendored-`.xcodeproj` (Class E) package.** `report_fidelity`'s `unless seeded` branch (and
   `copy_prebuilt_binary_target`'s own redundant `rm_f`) **delete or never write** a provenance
   sidecar for this package class, unconditionally, by design — not a legacy artifact of pre-Phase-9
   builds. If "no sidecar" universally means "miss," every Class E package (the exact package class
   Phase 7's benchmark measured Firebase-style savings against) becomes a permanent, every-build
   cache miss, which is a plausible **PERF-01 regression risk**, not just a correctness nuance.

3. **`Installer::Use`'s fast path bypasses gen-proxy entirely** when the host graph hasn't changed
   and a proxy `Package.swift` already exists on disk — which is exactly SC1's upgrade scenario
   (nothing in the host graph changed; only the gem version did). `fast_path?` has no
   spm-cache-version awareness today, so a bare `spm-cache use` after upgrading would silently keep
   serving the stale, pre-Phase-9 proxy forever. `spm-cache build` is unaffected (its `perform_install`
   always calls the unconditional base `perform_install`), so SC1 is achievable via `spm-cache build`
   alone — but `use`'s fast path is a real gap the planner must close for the default, no-args
   workflow README describes.

**Primary recommendation:** Extend `Cache.swift`'s `hit(module:)` to accept `(identity: String,
currentPin: String?)`, read `<module>.xcframework.provenance.json`, and apply intersection-only
comparison against `pins[identity]` (present+disagree ⇒ miss; absent from `pins` ⇒ hit, no
evidence of drift — this is what makes Class E safe). Change `report_fidelity`'s `unless seeded`
branch to **write** a `fidelity_status: "not-graph-pinned"` sidecar with empty `pins` instead of
deleting it, so "sidecar totally absent" becomes unambiguous evidence of a genuine pre-v0.4.0
legacy artifact (handles SC1) without permanently miss-ing every Class E package (handles the
regression risk in finding 2). Separately, gate `Installer::Use#fast_path?` on a per-project
`spm_cache_version` stamp (the exact mechanism `enrich_lockfile_products` already uses for
`products[]` staleness) so an upgrade forces one full run through gen-proxy even with an unchanged
host graph.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Cache hit/miss decision (per product) | Swift (`Cache.swift` / `ProxyGenerator.swift`) | Ruby (provides pins via `spm-cache.lock`) | `hit()` is the sole existing decision point; Ruby already threads reconciled pins into the same process via `spm-cache.lock` — no new IPC needed |
| Provenance sidecar read/parse | Swift (`Cache.swift`, new) | — | Mirrors the existing `.shims.json` sidecar-read pattern already in `Cache.swift:31-42` |
| Provenance sidecar write | Ruby (`BuildPipeline.report_fidelity`) | — | Already shipped in Phase 8; only the `unless seeded` branch's behavior changes this phase |
| `spm-cache build`'s "which targets to rebuild" | Ruby (`Installer::Build#perform_install`) | Swift (supplies `graph.json`'s `missed` list) | `@cachemap.missed` (from `graph.json`, written by gen-proxy) directly drives the build loop — this is the actual "one-time rebuild" mechanism for SC1 |
| `spm-cache use` fast-path eligibility | Ruby (`Installer::Use#fast_path?`) | — | Must gain version-awareness so an upgrade forces at least one full run; independent of the Swift-side hit() change |
| `cache clean` orphan sweep (CACHE-03) | Ruby (`Command::Cache::Clean`) | — | Currently only supports `--all`/named-target `rm_rf`; the sidecar sweep is wholly new code, not a modification of existing sweep logic (there is no existing sweep) |

## Package Legitimacy Audit

**N/A — this phase introduces no new external packages.** It changes existing Ruby (`lib/spm_cache/**`)
and Swift (`tools/spm-cache-proxy/Sources/**`) source only. No `gem install`, no SPM package
addition, no `npm`/`pip`/`cargo` dependency. Skip the legitimacy gate.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CACHE-02 | A cache hit requires recorded provenance to match the current host graph; missing provenance counts as a miss | Architecture Pattern 1 (below) gives the exact `hit()` signature change and comparison rule; Common Pitfall 1 gives the Class E hazard that a naive implementation would hit; Common Pitfall 2 gives the `Installer::Use` fast-path gap |
| CACHE-03 | `cache clean` sweeps provenance sidecars alongside the artifacts they describe | Architecture Pattern 2 gives the exact code location (`lib/spm_cache/command/cache/clean.rb`) and the sweep logic to add, matching the `.shims.json` cleanup precedent already used in `copy_prebuilt_binary_target` |
</phase_requirements>

## Standard Stack

No new libraries. This phase is pure application logic in the existing Ruby gem
(`lib/spm_cache/**`, RSpec) and Swift proxy tool (`tools/spm-cache-proxy/Sources/**`, Swift Testing
`@Suite`/`@Test`). Both toolchains and their test frameworks are already wired into the repo from
prior phases — nothing to install, nothing to verify against a registry.

## Architecture Patterns

### System Architecture Diagram

```
                     ┌─────────────────────────────────────────────┐
                     │  Ruby: Installer::Build#perform_install      │
                     │  (spm-cache build — ALWAYS full path,        │
                     │   no fast-path short-circuit exists here)    │
                     └───────────────────┬───────────────────────────┘
                                         │ super (base Installer#perform_install)
                                         ▼
        detect_diff → recreate_dirs → sync_lockfile (reconciles pins       [Phase 6/7]
                    into spm-cache.lock: PackageRef.version/.revision)
                                         │
                                         ▼
                            prepare_proxy → SPM::Package::Proxy#prepare
                                         │
                    gen_umbrella → between_umbrella_and_proxy            [checkouts materialize;
              (resolve_umbrella_checkouts, enrich_lockfile_products)      vendored_xcodeproj? is
                                         │                                knowable here if needed]
                                         ▼
                         gen_proxy → spm-cache-proxy binary (Swift)
                                         │
                          ┌──────────────┴───────────────┐
                          │ ProxyGenerator.generate(for:) │
                          │  for pkg in packages:          │
                          │   for product in pkg.libraryProducts: │
                          │    cache.hit(module: product.name)  ◄── THIS is the CACHE-02
                          │      [NEW: + pkg.name (identity),        decision point.
                          │       + pkg.pinValue (current host pin)] │
                          │    reads <module>.xcframework.provenance.json
                          │    compares pins[pkg.name] vs pkg.pinValue
                          └──────────────┬───────────────┘
                                         │ writes graph.json {module, status: hit|missed|...}
                                         ▼
                     Ruby: @cachemap.missed  (Cache::Cachemap.load(graph.json))
                                         │
                                         ▼
                Installer::Build builds every "missed" target → BuildPipeline.run
                                         │
                                         ▼
                   report_fidelity writes/overwrites <name>.xcframework.provenance.json
                    (fresh pins recorded — next run's hit() check sees the new truth)


                     ┌─────────────────────────────────────────────┐
                     │  Ruby: Installer::Use#perform_install        │
                     │  (spm-cache use / spm-cache — DEFAULT cmd)   │
                     └───────────────────┬───────────────────────────┘
                                         │
                              if fast_path?:  ◄── GAP: no version check today.
                                skip sync_lockfile/prepare_proxy      An upgrade with an
                                entirely — gen-proxy NEVER runs,      unchanged host graph
                                stale proxy Package.swift is reused   takes this branch and
                              else: (same full path as Build)         never re-checks provenance.
```

### Recommended Project Structure

No new files/directories. Every change lands in an existing file:

```
tools/spm-cache-proxy/Sources/Core/
├── Cache.swift                  # hit(module:) signature change + sidecar read
├── Generator/ProxyGenerator.swift  # one call site update (line 119)
lib/spm_cache/
├── spm/build_pipeline.rb        # report_fidelity's `unless seeded` branch: write, not delete
├── installer/use.rb              # fast_path? gains a spm_cache_version check
├── command/cache/clean.rb       # new orphan-sidecar sweep
```

### Pattern 1: Provenance-aware `hit(module:)`

**What:** `hit()` currently ignores everything except file existence
(`tools/spm-cache-proxy/Sources/Core/Cache.swift:19-22`):

```swift
// Source: tools/spm-cache-proxy/Sources/Core/Cache.swift:19-22 (read this session, verbatim)
func hit(module: String) -> URL? {
    let xcframework = dir.appendingPathComponent("\(module).xcframework")
    return FileManager.default.fileExists(atPath: xcframework.path) ? xcframework : nil
}
```

Its one caller is `ProxyGenerator.swift:119` (verbatim, read this session):
```swift
let cachedBinary = (ignored || excluded) ? nil : cache.hit(module: product.name)
```
— inside a `for pkg in packages { for product in pkg.libraryProducts.map { ... } }` loop
(`ProxyGenerator.swift:84,118`), where `pkg: Lockfile.PackageRef` already carries `pkg.name`,
`pkg.version`, `pkg.revision` (`Lockfile.swift:21-27`, read this session).

**Recommended shape** (mirroring the exact revision-over-version precedence rule
`Lockfile.PackageRef.versionRequirement` already implements at `Lockfile.swift:118-126`, and that
`BuildPipeline#host_pin_value` implements independently in Ruby at `build_pipeline.rb:152-155` —
same precedence, verified in two places, so a shared computed property is the DRY fix):

```swift
// Recommended addition to Lockfile.PackageRef (Lockfile.swift) -- factor
// versionRequirement's precedence into a raw-value accessor both it and
// hit() can share:
var pinValue: String? {
    if let revision = revision, !revision.isEmpty { return revision }
    if let version = version, !version.isEmpty { return version }
    return nil
}

// Cache.swift -- new signature
func hit(module: String, identity: String, currentPin: String?) -> URL? {
    let xcframework = dir.appendingPathComponent("\(module).xcframework")
    guard FileManager.default.fileExists(atPath: xcframework.path) else { return nil }

    let sidecar = dir.appendingPathComponent("\(module).xcframework.provenance.json")
    guard let data = try? Data(contentsOf: sidecar),
          let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return nil // sidecar missing or unparsable -- fail-safe miss (CONTEXT.md decision)
    }
    guard let pins = parsed["pins"] as? [String: String] else { return nil }

    // Intersection-only: this identity absent from `pins` is NOT evidence of
    // drift (mirrors build_pipeline.rb's drifted_identities philosophy,
    // build_pipeline.rb:121-134) -- it is the not-graph-pinned steady state
    // once report_fidelity is changed to write (not delete) that sidecar.
    if let recorded = pins[identity], let current = currentPin, recorded != current {
        return nil // miss: pin disagreement
    }
    return xcframework
}

// ProxyGenerator.swift:119 call site update
let cachedBinary = (ignored || excluded) ? nil
    : cache.hit(module: product.name, identity: pkg.name ?? product.name, currentPin: pkg.pinValue)
```

**Why identity, not module name, keys the pins lookup:** `hit(module:)` is called per PRODUCT
(e.g., `Realm` and `RealmSwift` are two products of the ONE package `realm-swift`), but the
provenance sidecar's `pins` hash is keyed by PACKAGE identity strings sourced from
`Core::PackageResolved`'s `pin["identity"]` (`build_pipeline.rb:141-149`, verified) — the SAME
identity string that ends up in `spm-cache.lock`'s `PackageRef.name` via the reconciler
(`installer.rb:260`, `new_lock_entry`). Both sides trace to the same source, so they match
byte-for-byte; `pkg.name` (not `product.name`) is the correct lookup key. **This is
`[VERIFIED: tools/spm-cache-proxy/Sources/Core/Lockfile.swift:21-27,52-77]` +
`[VERIFIED: lib/spm_cache/spm/build_pipeline.rb:141-155]` +
`[VERIFIED: lib/spm_cache/installer.rb:253-264]`** — confirmed by reading the three call chains
this session, not inferred.

**Empirically confirmed the sidecar's `pins` DOES include the package's own self-entry** (not just
its transitive dependency closure) in the no-drift case — `spec/build_pipeline_provenance_spec.rb:89,123`
(read this session) asserts `"pins" => { "SomePkg" => "aaa111" }` for a package literally named
`SomePkg`, because `ResolvedGraph.seed!` copies the ENTIRE host `Package.resolved` verbatim into
the checkout before build (`resolved_graph.rb:36-41`) — so the host's own pin for the package being
built is present in the seeded snapshot, and (absent a silent re-resolve) survives into the
sidecar. This is what makes cross-project identity comparison (CONTEXT.md's "Cross-Project
Identity" decision, SC3) possible without any new schema field.

### Pattern 2: `cache clean` orphaned-sidecar sweep (CACHE-03)

**What:** `Command::Cache::Clean#run` (`lib/spm_cache/command/cache/clean.rb:23-37`, read this
session, verbatim) currently supports only two modes and has **no sidecar-awareness of any kind**:

```ruby
# Source: lib/spm_cache/command/cache/clean.rb:23-37 (verbatim, read this session)
def run
  config = Core::Config.instance
  ["debug", "release"].each do |cfg|
    cache_dir = config.cache_dir(cfg)
    next unless File.directory?(cache_dir)

    if @all
      remove_path(cache_dir, cfg)
    elsif @targets.any?
      @targets.each { |t| remove_path(File.join(cache_dir, t), cfg) }
    else
      puts "Specify --all or target names to clean"
    end
  end
end
```

CACHE-03's orphan sweep is **wholly new code to add**, not a modification of an existing sweep —
there is no prior orphan-cleanup logic to build on here. The precedent to mirror is
`copy_prebuilt_binary_target`'s existing suffix-stripped basename sidecar cleanup
(`build_pipeline.rb:1029-1045`, verified):

```ruby
# Pattern already established (build_pipeline.rb:1030-1045) -- suffix-stripped
# basename match between an xcframework and its sidecars. Recommended addition
# to Command::Cache::Clean, run unconditionally (independent of --all/--targets):
def sweep_orphaned_sidecars(cache_dir)
  Dir.glob(File.join(cache_dir, "*.{provenance,shims}.json")).each do |sidecar|
    basename = File.basename(sidecar).sub(/\.xcframework\.(provenance|shims)\.json\z/, "")
    fw_path = File.join(cache_dir, "#{basename}.xcframework")
    next if File.directory?(fw_path)

    if @dry
      puts "[dry] Would remove orphaned sidecar: #{sidecar}"
    else
      FileUtils.rm_f(sidecar)
      puts "Removed orphaned sidecar: #{sidecar}"
    end
  end
end
```

Per CONTEXT.md's already-locked decision, this sweep runs **regardless of `--all`/target
filtering** (it's a hygiene pass, not tied to the removal modes) and must NOT touch xcframeworks
that lack a sidecar (that's the separate, deliberately-out-of-scope "provenance-less pre-v0.4.0
entries" case).

### Pattern 3: Making `not-graph-pinned` an explicit sidecar state, not an absent one

**What goes wrong today:** `report_fidelity`'s `unless seeded` branch
(`build_pipeline.rb:92-101`, verified) and `copy_prebuilt_binary_target`
(`build_pipeline.rb:1043-1045`, verified — a second, redundant `rm_f` at the same effective
condition) both **delete or never write** a provenance sidecar for every vendored-`.xcodeproj`
(Class E) package, on every single build, forever:

```ruby
# Source: lib/spm_cache/spm/build_pipeline.rb:92-101 (verbatim, read this session)
def report_fidelity(name:, pkg_dir:, output_path:, seeded:, intended_pin_map:, config:, destinations:)
  unless seeded
    FileUtils.rm_f("#{output_path}.provenance.json")
    return
  end
  # ...
```

`seeded` is `false` whenever `ResolvedGraph.vendored_xcodeproj?(pkg_dir)` is true
(`build_pipeline.rb:198-203`, `resolved_graph.rb:54-63`) — i.e. structurally, permanently, for this
whole package class, not just for legacy pre-Phase-8 artifacts.

**Recommended fix:** change the `unless seeded` branch to WRITE a sidecar instead of deleting one:

```ruby
unless seeded
  write_provenance_sidecar(output_path, status: "not-graph-pinned", pins: {},
                                         config: config, destinations: destinations)
  return
end
```

**Why this is safe and matches Pattern 1's comparison rule:** `hit()`'s intersection-only lookup
(`pins[identity]` absent ⇒ no evidence of drift ⇒ hit) treats an *empty* `pins: {}` exactly the same
as a normal sidecar whose intersection happens to be empty — the identity is never present, so it's
never flagged as disagreeing. Once every Class E artifact has gone through ONE post-upgrade build
under this fix, "sidecar totally absent" becomes an **unambiguous** signal of a genuine pre-v0.4.0
legacy artifact — closing the ambiguity Pattern 1 depends on, and matching `cache list`'s existing
`"not-graph-pinned"` status string (`command/cache/list.rb:30,33,35`, verified) so the vocabulary
stays consistent between CACHE-02's hit-decision and DIAG-02's display.

### Anti-Patterns to Avoid

- **Treating "sidecar absent" as unconditionally "miss" without first closing Pattern 3.** This is
  the single highest-risk implementation mistake in this phase: it reads as a faithful
  implementation of CONTEXT.md's literal words ("No provenance sidecar at all... → silent miss +
  rebuild"), passes every test that doesn't specifically fixture a Class E/vendored-`.xcodeproj`
  package, and silently regresses caching for that entire package class — the same class Phase 7's
  real benchmark measured savings against (Firebase Analytics variants, per `07-BENCHMARK.md`'s own
  notes).
- **Assuming `spm-cache use`'s fast path is irrelevant to CACHE-02** because "the actual rebuild
  happens in `spm-cache build`." True for the rebuild mechanism itself, but SC1's "upgrading...
  produces a rebuild" is evaluated against whatever the user's actual command is — and README's
  documented default workflow is bare `spm-cache` (== `spm-cache use`, no args), which the fast path
  can silently no-op on an upgrade with an unchanged host graph.
- **Adding a new Swift-side data file/flag to distinguish Class E packages.** Not needed — Pattern
  3's fix (write an empty-pins sidecar) requires zero new data flow to Swift; `hit()`'s comparison
  logic stays uniform across every package class.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Revision-vs-version precedence for the identity pin comparison | A third, independently-written precedence check in `Cache.swift` | Factor `Lockfile.PackageRef.versionRequirement`'s existing precedence (`Lockfile.swift:118-126`) into a shared `pinValue` accessor | Two implementations of the same rule already exist (Swift's `versionRequirement`, Ruby's `host_pin_value`); a third, subtly different one is exactly how these two already-verified-consistent rules would drift apart |
| Sidecar-corruption handling | New try/catch philosophy for CACHE-02 | Mirror `Command::Cache::List#fidelity_status_for`'s existing tolerant fallback (`command/cache/list.rb:29-38`) — corrupt/missing/non-Hash JSON all fall through to the same conservative outcome | CONTEXT.md explicitly says to match this precedent; diverging here means `cache list`'s displayed status and `hit()`'s actual decision can disagree about the same artifact |
| Orphan sidecar matching | A new naming/matching scheme for CACHE-03 | Suffix-stripped basename match, exactly as `copy_prebuilt_binary_target`'s existing `.shims.json`/`.provenance.json` cleanup already does (`build_pipeline.rb:1030-1045`) | One matching convention across the whole cache lifecycle (write-time cleanup and `cache clean`-time cleanup) |

**Key insight:** every piece of this phase already has a same-shaped precedent shipped in Phases 6-8
(pin precedence, tolerant sidecar reads, suffix-stripped sidecar matching). The design work here is
almost entirely about REUSING those exact patterns consistently across the two new call sites
(`hit()` and `cache clean`), not inventing new ones.

## Common Pitfalls

### Pitfall 1: Naive miss-on-no-provenance defeats Class E caching (see Pattern 3)

**What goes wrong:** Every vendored-`.xcodeproj` package becomes a permanent, every-build cache
miss.
**Why it happens:** `report_fidelity` and `copy_prebuilt_binary_target` both actively suppress the
sidecar for this package class, by design, at two separate call sites
(`build_pipeline.rb:92-101,1043-1045`, both verified).
**How to avoid:** Implement Pattern 3 (write an explicit `not-graph-pinned` sidecar with empty
`pins`) before or alongside Pattern 1's `hit()` change — the two are interdependent, not sequential.
**Warning signs:** A regression test fixturing a Class E-shaped package (xcframework present, no
sidecar) that keeps reporting `missed` build after build, even with an unchanged host graph.

### Pitfall 2: `Installer::Use`'s fast path silently no-ops a post-upgrade run

**What goes wrong:** `fast_path?` (`installer/use.rb:73-79`, verified) requires only (1) a
non-empty `@diff` check reporting empty, (2) the lockfile existing, (3) the proxy `Package.swift`
existing — **no spm-cache-version check at all**. An upgrade with an unchanged host graph takes
this branch, skipping `sync_lockfile`/`prepare_proxy` (and therefore gen-proxy/`hit()`) entirely;
the pre-upgrade proxy manifest is reused verbatim.
**Why it happens:** the fast path was designed purely around host-graph staleness (Phase 3-era
optimization), predating any notion of spm-cache's own version mattering.
**How to avoid:** extend `fast_path?` with a stamp check mirroring `enrich_lockfile_products`'s
existing `invalidate_stale_products!` pattern (`installer.rb:417-437`, verified) — read the
project's persisted `spm_cache_version` from the on-disk lockfile JSON directly (cheap: `@lockfile`
is not yet loaded at the point `fast_path?` runs, since `sync_lockfile` is what populates it) and
require it to equal `SPMCache::VERSION` before taking the fast path.
**Warning signs:** SC1's acceptance test passing only when driven via `spm-cache build` and failing
(stale binary served) when driven via the default `spm-cache`/`spm-cache use` with no host-graph
change since the last pre-upgrade run.

### Pitfall 3: Comparing `product.name` instead of `pkg.name` against the sidecar's `pins` keys

**What goes wrong:** for a multi-product package (e.g. `realm-swift` → `Realm` + `RealmSwift`),
looking up `pins[product.name]` instead of `pins[pkg.name]` always misses (the sidecar never has a
key for the product name, only the package identity), so every multi-product package's caching
silently breaks.
**Why it happens:** `product.name` is the natural-looking variable already in scope right next to
the `cache.hit()` call (`ProxyGenerator.swift:118-119`) — easy to reach for by habit.
**How to avoid:** always key the lookup by `pkg.name` (the loop's outer package identity), verified
against `spec/build_pipeline_provenance_spec.rb`'s fixture where the sidecar key equals the
PACKAGE name, not any product/target name.

## Code Examples

### Existing sidecar-read pattern to mirror (already shipped, Cache.swift)

```swift
// Source: tools/spm-cache-proxy/Sources/Core/Cache.swift:31-42 (verbatim, read this session)
// -- the .shims.json read is the exact JSON-sidecar-read shape hit()'s new
// .provenance.json read should follow (graceful nil/empty on any failure).
func shims(for module: String) -> [String] {
    let sidecar = dir.appendingPathComponent("\(module).xcframework.shims.json")
    guard let data = try? Data(contentsOf: sidecar),
          let names = try? JSONDecoder().decode([String].self, from: data) else {
        return []
    }
    return names
}
```

### Existing Ruby-side tolerant-fallback pattern to mirror (Phase 8, cache list)

```ruby
# Source: lib/spm_cache/command/cache/list.rb:29-38 (verbatim, read this session)
def fidelity_status_for(sidecar_path)
  return "not-graph-pinned" unless File.exist?(sidecar_path)

  parsed = JSON.parse(File.read(sidecar_path))
  return "not-graph-pinned" unless parsed.is_a?(Hash)

  parsed["fidelity_status"] || "not-graph-pinned"
rescue JSON::ParserError, SystemCallError
  "not-graph-pinned"
end
```

### `GraphEntry.Status` enum (verbatim — the full status vocabulary `hit()`'s decision feeds into)

```swift
// Source: tools/spm-cache-proxy/Sources/Core/Generator/ProxyGenerator.swift:16-19 (verbatim, read this session)
enum Status: String, Codable {
    case hit, missed, ignored, excluded, plugin
}
```

### Existing Swift test pattern to extend (no `Cache.swift`/`BinariesCache` tests exist today)

```swift
// Pattern already used in tools/spm-cache-proxy/Tests/spm-cache-proxyTests/ProxyGeneratorTests.swift:22-38
// (verbatim structure, read this session) -- real temp dirs, real
// FileManager.mkdir()'d xcframework fixtures, no protocol/mock layer.
// A provenance-aware hit() test follows the same shape, adding a real
// `.provenance.json` file next to the fixture xcframework:
let cacheDir = tmp.appendingPathComponent("cache")
try cacheDir.mkdir()
try cacheDir.appendingPathComponent("SomePkg.xcframework").mkdir()
try JSONSerialization.data(withJSONObject: ["pins": ["some-pkg": "aaa111"], "fidelity_status": "host-pinned"])
    .write(to: cacheDir.appendingPathComponent("SomePkg.xcframework.provenance.json"))
```

## State of the Art

Not applicable in the usual "library/framework evolved" sense — this is entirely internal
application logic. The one relevant "before/after" is the phase's own object:

| Old Approach | Current Approach (this phase) | When Changed | Impact |
|--------------|-------------------------------|---------------|--------|
| `hit(module:)` = bare `fileExists` | `hit(module:identity:currentPin:)` = fileExists + sidecar pin comparison | This phase | Existing-user cache entries built before Phase 9 stop being silently trusted |
| `cache clean` = raw `rm_rf` of xcframework dirs/targets only | `cache clean` also sweeps orphaned `.provenance.json`/`.shims.json` with no matching xcframework | This phase | No functional dependency change; purely additive hygiene pass |

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Xcode's build system reliably notices an in-place-overwritten local `binaryTarget`'s content change (mtime/hash) and re-links, without spm-cache needing to touch DerivedData (SC5) | Open Questions / Common Pitfalls | If wrong, a rebuilt-but-same-path xcframework could be silently ignored by Xcode's incremental build, serving a stale linked binary even after a correct cache-side rebuild. Mitigated by strong circumstantial evidence below (not a full falsification), so treat as MEDIUM- not LOW-risk in practice. |
| A2 | `pin["identity"]` strings are stable/lowercase-normalized identically by every call site that reads a `Package.resolved` (Ruby's `Core::PackageResolved`, threaded into both `spm-cache.lock` and the provenance sidecar) | Pattern 1 | If wrong, `pins[pkg.name]` lookups would silently always miss for packages with mixed-case identities — same failure mode as Pitfall 3 but structural, not a coding mistake. Not independently re-verified beyond confirming both paths call the same `Core::PackageResolved` methods. |

**On A1's evidence (not a full falsifier, hence still `[ASSUMED]`, not `[VERIFIED]`):**
`XCFramework#build` (`lib/spm_cache/spm/xcframework/xcframework.rb:33,43`, verified this session)
already does `FileUtils.rm_rf(@output_path)` immediately before every single `xcodebuild
-create-xcframework` invocation — i.e. **every** xcframework build, cache-miss or first-time,
already deletes and recreates the bundle at the identical output path today, and has since before
Phase 9. This is not new behavior CACHE-02 introduces; Phase 7's real benchmark
(`07-BENCHMARK.md`) already exercised cold + warm builds against this exact mechanism in production
against the reference project with no reported staleness symptom. The residual, unverified part is
narrower than CONTEXT.md's framing suggests: not "does overwrite-in-place work at all" (yes,
already field-proven) but "does Xcode's *incremental* build system, when nothing else in the
project changed, notice a local `path:`-declared `binaryTarget`'s content changed between two
`xcodebuild` invocations of the *app* project" — recommend a `checkpoint:human-verify` task in the
plan that builds the reference project once, forces a cache-invalidating rebuild of one package via
this phase's new logic, and confirms (via a binary diff of the linked framework in the app's
DerivedData, or a fresh symbol/version check) that the new content actually made it into the app
binary without a manual DerivedData clear.

## Open Questions

1. **Should `spm-cache pkg build` (the standalone per-package build CLI, distinct from
   `Installer::Build`) also get a `not-graph-pinned` sidecar write on its unseeded path, or is its
   output cache-dir structurally out of scope for CACHE-02 entirely?**
   - What we know: `resolved_pins_file` is `nil` by design for this path
     (`build_pipeline.rb:37-41`, verified comment: "nil (the default) disables seeding entirely...
     so `spm-cache pkg build` (which never passes this) is unaffected"), so it already takes the
     same `unless seeded` branch as Class E.
   - What's unclear: whether `spm-cache pkg build`'s output ever lands in the SAME
     `~/.spm-cache/<config>/` directory that `Installer::Build`/`hit()` reads from, or a wholly
     separate location not covered by CACHE-02 at all.
   - Recommendation: the planner should grep `spm-cache pkg build`'s actual `--cache`/output-dir
     default before writing tasks; if it shares the cache dir, Pattern 3's fix already covers it
     for free (same code path).

2. **Does `Installer::Use#fast_path?`'s version-stamp read need its own lightweight JSON parse, or
   should it reuse `Core::Lockfile`?**
   - What we know: `@lockfile` (the ivar) is `nil` at the point `fast_path?` runs today (only
     populated inside `sync_lockfile`, which the fast path skips) — confirmed by reading
     `installer.rb`'s `initialize` and `sync_lockfile`.
   - What's unclear: whether instantiating a full `Core::Lockfile.new(path).load(path)` just to read
     one stamp is acceptable overhead on every `use` invocation (it's a small JSON parse, likely
     negligible, but not measured this session).
   - Recommendation: use `Core::Lockfile` rather than hand-rolling a second JSON reader — it already
     exists and is already required by `installer.rb`; the "Don't Hand-Roll" table's rationale
     applies here too even though this specific case wasn't listed there explicitly.

## Environment Availability

Skipped — this phase introduces no new external tool/service/runtime dependency. Everything needed
(Ruby, RSpec, Swift toolchain, `xcodebuild`, Swift Testing) is already required by, and verified
present for, Phases 6-8 of this same milestone.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Ruby framework | RSpec (`spec/*.rb`, `spec_helper.rb` already present, used throughout Phases 6-8) |
| Swift framework | Swift Testing (`@Suite`/`@Test`, `tools/spm-cache-proxy/Tests/spm-cache-proxyTests/`) |
| Config file | none new — existing `.rspec`/`Package.swift` test target |
| Quick run (Ruby) | `bundle exec rspec spec/build_pipeline_provenance_spec.rb spec/command_cache_clean_spec.rb` (new file, Wave 0 gap) |
| Quick run (Swift) | `swift test --filter CacheTests` (new file, Wave 0 gap) |
| Full suite (Ruby) | `bundle exec rspec` |
| Full suite (Swift) | `swift test` (from `tools/spm-cache-proxy/`) |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CACHE-02 | Missing sidecar ⇒ miss | unit (Swift) | `swift test --filter CacheTests` | ❌ Wave 0 — no `CacheTests.swift` exists today |
| CACHE-02 | Pin disagreement ⇒ miss (single package) | unit (Swift) | `swift test --filter CacheTests` | ❌ Wave 0 |
| CACHE-02 | Cross-project identity (two projects, same package, different pins, don't share) | integration (Ruby, real binary) | `bundle exec rspec spec/gen_proxy_provenance_spec.rb` mirroring `spec/gen_proxy_cache_only_spec.rb`'s real-binary pattern | ❌ Wave 0 |
| CACHE-02 | Class E / not-graph-pinned artifact still hits after Pattern 3's fix | unit (Ruby) | `bundle exec rspec spec/build_pipeline_provenance_spec.rb` (extend existing file) | ✅ file exists, extend it |
| CACHE-03 | `cache clean` sweeps orphaned sidecars, leaves paired ones | unit (Ruby) | `bundle exec rspec spec/command_cache_clean_spec.rb` | ❌ Wave 0 — no spec file exists for `Command::Cache::Clean` today (confirmed: `spec/` has no `clean` spec; only `command_cache_list_spec.rb`, `gen_proxy_cache_only_spec.rb`, `cachemap_spec.rb` reference `cache`) |
| N/A (Pitfall 2 closure) | `spm-cache use` fast path forces a full run after a version bump | unit (Ruby) | `bundle exec rspec spec/installer_use_fast_path_spec.rb` (new, or extend an existing `Installer::Use` spec if one exists — none found this session) | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** the narrowest of the above per touched file
- **Per wave merge:** `bundle exec rspec` (Ruby) + `swift test` (Swift, from `tools/spm-cache-proxy/`)
- **Phase gate:** both full suites green before `/gsd-verify-work`

### Wave 0 Gaps
- [ ] `tools/spm-cache-proxy/Tests/spm-cache-proxyTests/CacheTests.swift` — no test file exists for
  `BinariesCache`/`Cache.swift` at all today (confirmed: only `UmbrellaGeneratorTests.swift`,
  `ProxyGeneratorTests.swift`, `LockfileTests.swift` exist in the Tests dir)
- [ ] `spec/command_cache_clean_spec.rb` — no spec exists for `Command::Cache::Clean` today
- [ ] `spec/gen_proxy_provenance_spec.rb` (or extend `gen_proxy_cache_only_spec.rb`'s pattern) —
  real-binary smoke test asserting `graph.json` hit/miss status against fixture sidecars
- [ ] A spec exercising `Installer::Use#fast_path?`'s version-awareness (new file; no existing spec
  targets `Installer::Use` in isolation was found — `Installer::Build`/`Installer::Use` behavior is
  currently exercised mostly through `installer.rb`-adjacent specs and Phase 7's benchmark, not a
  dedicated `fast_path?` unit spec)

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-------------------|
| V5 Input Validation | yes | Sidecar JSON parsing must be defensive (non-Hash, corrupt, missing keys) — already established as `fail-safe → treat as miss`/`"not-graph-pinned"` per Phase 8's precedent; no new validation category introduced |
| V2/V3/V4/V6 | no | This phase touches no authentication, session, access-control, or cryptography surface — it is local filesystem cache-metadata comparison only |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|----------------------|
| Sidecar JSON as an untrusted-ish local input (a shared/remote cache backend could serve a
  corrupted or crafted sidecar, per `write_provenance_sidecar`'s own comment about the sidecar
  "travel[ing] through a shared/remote cache backend", `build_pipeline.rb:161`) | Tampering | Never trust the sidecar's content as authoritative without a fail-safe fallback to "miss" on any parse anomaly — already the established pattern this phase must extend, not invent |

## Sources

### Primary (HIGH confidence — all read directly this session)
- `tools/spm-cache-proxy/Sources/Core/Cache.swift` — full file
- `tools/spm-cache-proxy/Sources/Core/Lockfile.swift` — full file
- `tools/spm-cache-proxy/Sources/Core/Generator/ProxyGenerator.swift` — full file
- `tools/spm-cache-proxy/Sources/CLI/GenProxy.swift` — full file
- `lib/spm_cache/spm/pkg/proxy.rb`, `lib/spm_cache/installer.rb`, `lib/spm_cache/installer/use.rb`,
  `lib/spm_cache/installer/build.rb` — full files
- `lib/spm_cache/spm/build_pipeline.rb` — provenance/fidelity/seed/copy_prebuilt_binary_target
  regions (lines 1-230, 1020-1048)
- `lib/spm_cache/spm/resolved_graph.rb` — full file
- `lib/spm_cache/command/cache/clean.rb`, `lib/spm_cache/command/cache/list.rb`,
  `lib/spm_cache/command/use.rb`, `lib/spm_cache/command/build.rb` — full files
- `lib/spm_cache/core/config.rb`, `lib/spm_cache/core/lockfile.rb`, `lib/spm_cache/version.rb` —
  relevant sections
- `spec/build_pipeline_provenance_spec.rb`, `spec/gen_proxy_cache_only_spec.rb`,
  `spec/command_cache_list_spec.rb` — relevant sections
- `tools/spm-cache-proxy/Tests/spm-cache-proxyTests/ProxyGeneratorTests.swift` — relevant sections
- `.planning/phases/09-cache-identity-invalidation/09-CONTEXT.md`, `.planning/REQUIREMENTS.md`,
  `.planning/STATE.md` — required reading

### Secondary / Tertiary
None — no web research was performed; this phase is entirely internal-codebase tracing per its own
"Research: Needed" framing (comparison granularity + call-path questions), and every claim above
resolves to a source line read this session.

## Metadata

**Confidence breakdown:**
- Standard stack: N/A — no new stack
- Architecture (call path, comparison mechanics): HIGH — every call site traced and read directly,
  cross-checked against an existing passing spec's fixture data
- Pitfalls (Class E regression, fast-path bypass): HIGH — both derived from reading the actual
  conditional logic, not inference from CONTEXT.md's prose
- SC5/DerivedData reasoning: MEDIUM (labeled `[ASSUMED]` in the Assumptions Log) — strong
  circumstantial/field evidence, no live xcodebuild experiment run this session

**Research date:** 2026-08-29
**Valid until:** No expiry driver — this is internal-codebase research, not a fast-moving external
dependency; valid until the traced source files themselves change (re-verify if Phase 9's plan is
revisited after any further Phase 6-8 code changes land).
