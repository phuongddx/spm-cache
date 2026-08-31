# Phase 10: Fidelity Regression Coverage - Research

**Researched:** 2026-08-29
**Domain:** Hermetic RSpec regression coverage over the existing fidelity seams (`Core::Sh` / `Desc` / `Buildable` / `BuildPipeline#report_fidelity`)
**Confidence:** HIGH (every claim below was verified by reading the source file this session or by running the suite; this is pattern-reuse research, not new-technology research — per ROADMAP "Research: Not Needed" for external unknowns)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Drift-Regression Spec (TEST-01 / SC1)**
- Hermetic `Core::Sh`-stub harness — no network, no real `xcodebuild` (SC4). The real-binary
  SC1–SC3 coverage shipped in Phase 9's `gen_proxy_provenance_spec.rb` stays as-is, untouched.
- Both assertion directions: drift (realized ≠ pinned) MUST warn via `report_fidelity`, and
  agreeing pins must NOT warn (false-positive guard).
- Two drift-injection sources: provenance-sidecar disagreement (Phase 9 hit/miss semantics) and
  resolution read-back drift (Phase 8 `report_fidelity` semantics).
- New dedicated file: `spec/fidelity_drift_regression_spec.rb` — the regression contract gets
  its own named spec (the v0.3.0 lesson).

**Bucket-Partition Coverage Assertion (TEST-02 / SC2)**
- Dedicated meta-spec: one synthetic all-classes project driven through the seams; assert every
  `Package.resolved` package lands in exactly ONE bucket — zero-bucket AND double-bucket both fail.
- Bucket enumeration drives the production classifier (single source of truth: Phase 8's
  `report_fidelity` classification); assert completeness + disjointness. No hand-maintained
  bucket list (it would drift).
- One kitchen-sink hermetic fixture containing all edge classes.
- Local/path packages (no `repositoryURL`) land in the excluded/local bucket — never silently
  absent. Extends the DIAG-01 precedent: excluded from the drift *comparison*, but still
  partitioned (SC2's zero-bucket arm demands it).

**Edge-Class Fixture Matrix (TEST-03 / SC3)**
- New table-driven matrix spec enumerating all 8 classes: binary target (Class E), macro with a
  narrow `swift-syntax` pin, vendored `.xcodeproj`, plugin-only, transitive-only, resource
  bundle, private Clang shim, product≠target rename.
- Existing scattered edge-class specs stay untouched — SC3 says the matrix "passes unchanged";
  no churn, no migration.
- Inline builders via the proven Sh-stub pattern; JSON fixture files only for lockfile-shaped
  data (current convention: `spec/fixtures/*-lockfile.json`).
- Ruby-side only — the Swift companion keeps its own suite (36 tests); macro `swift-syntax`
  pinning is lockfile-driven and hermetically coverable from Ruby.
- Named `spec/fidelity_edge_matrix_spec.rb`.

**Hermeticity & CI (SC4)**
- Explicit guard: the new specs' Sh stub allowlists commands and fails on unexpected real
  invocations — SC4 becomes an executable assertion, not a convention.
- Ruby 3.1–3.3 coverage relies on the existing `ci.yml` matrix; new specs use version-agnostic
  syntax (no 3.3-only constructs).
- Memoized shared kitchen-sink fixture via `let`; target ~2–3s total runtime for the new specs.
- Explicit TEST-01/02/03 IDs in `describe` strings for 1:1 verifier traceability.

### Claude's Discretion
None outstanding — all four areas accepted as recommended by the operator on 2026-08-29.

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| TEST-01 | "A regression spec proves an out-of-range pin is detected and reported rather than silently re-resolved" | `report_fidelity` drift read-back is fully drivable hermetically: seed `resolved_pins_file`, have the stubbed `Buildable#build_for_destination` rewrite `pkg_dir/Package.resolved` to a drifted value (the exact injection pattern of `spec/build_pipeline_provenance_spec.rb:50-61`); the false-positive direction is `spec/build_pipeline_provenance_spec.rb:96-124`. Provenance-sidecar disagreement direction is coverable by reusing the `write_sidecar` helper shape from `spec/gen_proxy_provenance_spec.rb:39-44`. |
| TEST-02 | "A coverage assertion proves every package in `Package.resolved` lands in exactly one bucket (pinned / ignored / excluded / plugin-only / resolution-incompatible / not-graph-pinned), with none silently absent" | The six buckets are emitted by TWO production surfaces (see Architecture Patterns §Partition Map): three statuses from Ruby `BuildPipeline#report_fidelity` sidecars, three from the Swift `ProxyGenerator.GraphEntry.Status` enum surfaced via graph.json. `plugin_only_package?` exists Ruby-side at `installer.rb:660-665`. Local/path packages never appear in `Package.resolved` — they enter the universe from the lockfile side (`repositoryURL` empty; `diagnostics.rb:99-118`). |
| TEST-03 | "The v0.2.x edge-class fixture matrix does not regress — binary target (Class E), macro with narrow `swift-syntax`, vendored `.xcodeproj`, plugin-only, transitive-only, resource bundle, private Clang shim, product≠target rename" | 6 of 8 classes have proven hermetic shapes to copy verbatim from existing specs; 2 (macro `swift-syntax` pin, resource bundle) have NO existing fidelity-scenario coverage and need new fixture shapes — both are pure data shapes (see Architecture Patterns §Edge-Class Matrix). |
</phase_requirements>

## Summary

Phase 10 adds zero production code. It pins the fidelity contract (Phases 6–9) with hermetic RSpec
coverage on seams that are already proven across 387 green examples (suite run this session:
`387 examples, 0 failures`, 46.77s wall clock). The three deliverables are the two CONTEXT-locked
spec files (`spec/fidelity_drift_regression_spec.rb`, `spec/fidelity_edge_matrix_spec.rb`) plus a
TEST-02 partition meta-spec whose filename is planner's choice.

The single most important finding for the planner: **the six TEST-02 buckets are NOT all produced
by `report_fidelity`.** The CONTEXT's "single source of truth: Phase 8's `report_fidelity`
classification" premise is only 3/6 true. `report_fidelity` emits exactly three status strings
(`host-pinned`, `resolution-incompatible`, `not-graph-pinned`) into provenance sidecars
[VERIFIED: lib/spm_cache/spm/build_pipeline.rb:128,133,148 — quoted in Partition Map below]. The
other three (`ignored`, `excluded`, `plugin`-only) are decided by the Swift companion's
`ProxyGenerator` into graph.json, plus a Ruby-side `Installer#plugin_only_package?` predicate.
A partition meta-spec that only drives `report_fidelity` can observe at most 3 buckets. The
planner must decide the hybrid shape (recommendation in Open Question 1).

Second finding: **two of the eight TEST-03 edge classes have no existing fidelity-scenario
coverage anywhere.** "Macro with narrow `swift-syntax` pin" appears only as `hasMacro: false`
literals in Swift graph entries, and "resource bundle" appears only incidentally (a binaryTarget
path string in `lockfile_enrichment_spec.rb:122`). Both are nevertheless hermetically coverable
as pure data shapes (a `swift-syntax` pin identity in a seeded `Package.resolved`; a
`"resources"` array on a describe-JSON target). The other six classes have proven fixture shapes
to lift verbatim from existing green specs.

Third finding: the hermetic seam has three tiers — object-level stubs (`Desc::Description`,
`Buildable`, `XCFramework`), the true shell boundary (`Core::Sh`), and real-binary invocation
(`system()` on the compiled proxy with skip-if-not-built). The new TEST-01/TEST-03 specs use tier
1 per CONTEXT; the existing hermeticity assertion idiom
(`expect(SPMCache::Core::Sh).not_to receive(:run)`, provenance spec line 623) generalizes to the
SC4 "allowlist + fail-on-unexpected" guard.

**Primary recommendation:** Build all three specs on the tier-1 object-stub seam with per-class
fixture builders; drive the TEST-02 partition's graph-status legs through the compiled proxy
binary via the existing `gen_proxy_*` pattern (offline, no xcodebuild — SC4-compatible, and CI
builds the binary before RSpec on every matrix leg); derive every bucket name from observed
production output (sidecar `fidelity_status` values + graph.json `status` values), never from a
hand-typed list.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Drift read-back + fidelity status (`host-pinned` / `resolution-incompatible` / `not-graph-pinned`) | Ruby core — `SPM::BuildPipeline#report_fidelity` | — | Single consolidated insertion point after `perform_build` succeeds [VERIFIED: build_pipeline.rb:93-154] |
| Provenance sidecar write/read | Ruby core — `BuildPipeline#write_provenance_sidecar` | Swift `BinariesCache.hit()` reads it back | Tempfile-then-rename, never raises [VERIFIED: build_pipeline.rb:220-237] |
| `ignored` / `excluded` / `plugin` classification | Swift companion — `ProxyGenerator.generate` | Ruby `Cache::Cachemap` reads graph.json back | fnmatch over product names + identity, package-level decision [VERIFIED: ProxyGenerator.swift:39-62,118-130] |
| plugin-only predicate (lockfile-driven) | Ruby — `Installer#plugin_only_package?` | — | Products metadata with no `library`-type product [VERIFIED: installer.rb:660-665] |
| Host `Package.resolved` locate/parse | Ruby — `Core::PackageResolved` | — | Canonical-path tiering (FID-06); `pins_or_nil` tolerant reader [VERIFIED: package_resolved.rb:14-72] |
| Seeding / vendored-.xcodeproj classification | Ruby — `SPM::ResolvedGraph` | — | `vendored_xcodeproj?` glob decides not-graph-pinned before any build [VERIFIED: resolved_graph.rb:61-63] |
| `swift package describe` interception | `Desc::BaseObject.describe` → `Core::Sh.run` | spec stubs at `Desc::Description.new` | The describe JSON is the shape every desc-stub fabricates [VERIFIED: desc/base.rb:51-56] |
| **This phase: regression coverage** | Test tier — 3 new spec files over all above seams | CI matrix gate | No production code change |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| rspec | ~> 3.12 (Gemfile, dev group) | the only test framework; already runs 387 examples | Existing substrate; CONTEXT locks RSpec built-in matchers only |
| json / fileutils / tmpdir / tempfile | Ruby stdlib | fixture + Package.resolved fabrication | Project constraint: no new runtime gem dependencies |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| none | — | — | — |

No packages are installed this phase. `rubocop ~> 1.50` applies to new spec files via existing `make format`.

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| RSpec built-in matchers | rspec-mocks verified doubles / test-prof | Rejected by CONTEXT ("RSpec built-in matchers only" is the established pattern); `instance_double` IS used and is stdlib-rspec — that stays |

**Installation:** none.

**Version verification:** Gemfile dev group read this session: `gem "rspec", "~> 3.12"` and `gem "rubocop", "~> 1.50"` [VERIFIED: Gemfile lines 8-10]. Full suite executed green this session under local ruby 3.2.3.

## Package Legitimacy Audit

No external packages are installed or recommended this phase (test-only, stdlib + existing dev deps).

| Package | Registry | Age | Downloads | Source Repo | Verdict | Disposition |
|---------|----------|-----|-----------|-------------|---------|-------------|
| (none) | — | — | — | — | — | N/A — no installs |

**Packages removed due to [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

## Architecture Patterns

### System Architecture Diagram

How a hermetic fidelity spec drives production code without network or xcodebuild:

```
spec (fixture builders)
   |
   |  writes                     writes
   +--> resolved_pins_file  +--> pkg_dir/<vendored .xcodeproj> | artifacts layout (Class E)
   |     (JSON pins)        |
   v                        v
SPM::BuildPipeline.run(name:, pkg_dir:, destinations:, out_dir:, resolved_pins_file:, config:)
   |
   +--> ResolvedGraph.seed! / vendored_xcodeproj?          [real filesystem, no shell]
   +--> Desc::Description.new ---------- STUB TIER 1 (instance_double) ----------+
   |     (real code would: Core::Sh.run("swift package describe --type json"))   |
   +--> Buildable#build_for_destination -- STUB TIER 1 (returns artifacts hash,  |
   |     may rewrite pkg_dir/Package.resolved == drift injection)                |
   +--> XCFramework.new.build ------------ STUB TIER 1 (returns path)            |
   v                                                                            |
report_fidelity  (ALL REAL)                                                     |
   |--> reads back pkg_dir/Package.resolved (Core::PackageResolved.pins_or_nil) |
   |--> drifted_identities(intended ∩ realized, value inequality)               |
   |--> Core::UI.warn (stderr)  /  Core::UI.info (stdout)                       |
   +--> writes <out>.xcframework.provenance.json  <-- ASSERT ON THIS FILE       |
                                                                                |
   SC4 guard: expect(Core::Sh).not_to receive(:run)  <-- AND ON THIS            |
                                                                             <-+
```

For the graph.json legs (ignored / excluded / plugin / hit / missed): the compiled
`spm-cache-proxy` binary is invoked via `system()` (tier 3, `gen_proxy_*` precedent) — offline,
local binary; CI runs `make proxy.build` before `bundle exec rspec` on every matrix leg
[VERIFIED: .github/workflows/ci.yml — both steps present].

### The TEST-02 Partition Map (read this before planning)

**Fidelity statuses — Ruby side, written to `<name>.xcframework.provenance.json`:**

[VERIFIED: lib/spm_cache/spm/build_pipeline.rb:128,133,148]
```ruby
write_provenance_sidecar(output_path, status: "host-pinned", pins: preserved_pins,
                       config: config, destinations: destinations)
...
write_provenance_sidecar(output_path, status: "not-graph-pinned", pins: {},
                       config: config, destinations: destinations)
...
status = drifted.empty? ? "host-pinned" : "resolution-incompatible"
```

Sidecar keys, exactly five [VERIFIED: build_pipeline.rb:222-228]:
```ruby
content = JSON.generate(
  fidelity_status: status,
  pins: pins,
  spm_cache_version: SPMCache::VERSION,
  config: config,
  destinations: destinations,
)
```
(The five-key shape is already asserted in `spec/build_pipeline_provenance_spec.rb:86`.)

**Graph statuses — Swift side, written to graph.json and read back by `Cache::Cachemap`:**

[VERIFIED: tools/spm-cache-proxy/Sources/Core/Generator/ProxyGenerator.swift:16-19]
```swift
struct GraphEntry: Codable {
    enum Status: String, Codable {
        case hit, missed, ignored, excluded, plugin
    }
```
Decision order [VERIFIED: ProxyGenerator.swift:118-130]:
```swift
let cachedBinary = (ignored || excluded) ? nil
    : cache.hit(module: product.name, identity: pkg.name ?? product.name, currentPin: pkg.pinValue)
let status: GraphEntry.Status
if excluded {
    status = .excluded
} else if ignored {
    status = .ignored
} else if cachedBinary != nil {
    status = .hit
} else {
    status = .missed
}
```
`ignored` = denylist fnmatch over library product names + package identity; `excluded` =
cache_only allowlist inverted [VERIFIED: ProxyGenerator.swift:51-62].

**Bucket → production-source mapping:**

| TEST-02 bucket | Producing code | Observable artifact | Hermetic drive |
|---|---|---|---|
| pinned | `report_fidelity` → `"host-pinned"` | sidecar `fidelity_status` | BuildPipeline.run, agreeing pins |
| resolution-incompatible | `report_fidelity` → `"resolution-incompatible"` | sidecar `fidelity_status` + stderr warn | BuildPipeline.run, injected drift |
| not-graph-pinned | `report_fidelity` → `"not-graph-pinned"` (also `cache list` default) | sidecar `fidelity_status` | vendored `.xcodeproj` pkg_dir, or `resolved_pins_file: nil` |
| ignored | `ProxyGenerator` → `.ignored` | graph.json `status` | `--ignore` flag on proxy binary (gen_proxy pattern) |
| excluded | `ProxyGenerator` → `.excluded`; CONTEXT extends to local/path | graph.json `status`; local = lockfile entry with empty `repositoryURL` | `--cache-only` flag; local entry via lockfile fixture |
| plugin-only | `ProxyGenerator` → `.plugin`; Ruby predicate `plugin_only_package?` | graph.json `status` (one entry per plugin product) | plugin-typed products in lockfile fixture |

**Zero-bucket hazards (things that are silently absent by design — the meta-spec must handle
each explicitly, not accidentally):**
1. Transitive-only packages get NO graph entry at all: [VERIFIED: ProxyGenerator.swift:109] `if pkg.isTransitiveOnly(consumedProducts: consumedProducts) { continue }`. If the partition universe is graph.json ∪ sidecars, a transitive-only package is zero-bucket **by production design** — the spec must classify it from the input side (it is consumed transitively, i.e. pinned through its consumer).
2. Local/path packages never appear in `Package.resolved` [VERIFIED: diagnostics.rb:95-98, "Entries with no repositoryURL are excluded: SwiftPM never lists a local/path package in Package.resolved"]. CONTEXT locks these into the excluded/local bucket via the LOCKFILE side (`next if pkg['repositoryURL'].to_s.empty?` is the DIAG-01 read-side precedent, diagnostics.rb:111).
3. Mixed hit+missed packages: a hit sibling downgrades a missed one to `.excluded` [VERIFIED: ProxyGenerator.swift:155-159] — a package can contribute multiple products with different statuses; partition per-package (by identity), not per-product, or the spec will see "double" buckets that are legitimate product granularity.

### Recommended Project Structure
```
spec/
├── fidelity_drift_regression_spec.rb      # TEST-01/SC1 (CONTEXT-locked name)
├── fidelity_bucket_partition_spec.rb      # TEST-02/SC2 (name is planner's choice)
├── fidelity_edge_matrix_spec.rb           # TEST-03/SC3 (CONTEXT-locked name)
└── fixtures/
    └── fidelity-kitchen-sink-lockfile.json  # only if the kitchen-sink needs
                                              # lockfile-shaped data (convention:
                                              # spec/fixtures/*-lockfile.json)
```
No `spec/support/` directory exists today and none should be created (flat convention; helpers
are local methods inside each spec file, as in every existing spec).

### Pattern 1: The three-tier hermetic seam
**What:** Tier 1 — stub the objects (`Desc::Description`, `Buildable`, `XCFramework`) with
`instance_double`; tier 2 — stub `Core::Sh` itself (only when exercising real command-assembly
code); tier 3 — run the compiled proxy binary via `system()` with skip-if-not-built.
**When to use:** TEST-01 and TEST-03 = tier 1 (CONTEXT lock). TEST-02 fidelity legs = tier 1;
graph legs = tier 3. Never tier 2 unless asserting on command bytes (D-07 precedent).

The canonical tier-1 setup, verbatim from the provenance spec [VERIFIED:
spec/build_pipeline_provenance_spec.rb:18-27,48-49]:
```ruby
def stub_desc_products(products)
  fake_desc = instance_double(SPMCache::SPM::Desc::Description)
  allow(SPMCache::SPM::Desc::Description).to receive(:new).and_return(fake_desc)
  allow(fake_desc).to receive(:fetch)
  allow(fake_desc).to receive(:products).and_return(
    products.map { |p| SPMCache::SPM::Desc::Product.new(raw: p, pkg_dir: pkg_dir) },
  )
  allow(fake_desc).to receive(:raw).and_return({ "targets" => [] })
  fake_desc
end
```
```ruby
allow(SPMCache::SPM::XCFramework::XCFramework).to receive(:new).and_return(
  double("XCFramework", build: File.join(out_dir, "SomePkg.xcframework")),
)
```

The `Desc::Description` seam intercepts the only real shell-out in the describe path
[VERIFIED: lib/spm_cache/spm/desc/base.rb:51-52]:
```ruby
def self.describe(pkg_dir)
  result = SPMCache::Core::Sh.run("swift package describe --type json", cwd: pkg_dir)
  JSON.parse(result[:output])
```

### Pattern 2: Drift injection (TEST-01's core move)
**What:** The stubbed `build_for_destination` block rewrites `pkg_dir/Package.resolved` to the
realized (drifted) value before returning artifacts — simulating xcodebuild's silent
re-resolution. Verbatim [VERIFIED: spec/build_pipeline_provenance_spec.rb:50-61]:
```ruby
allow(fake_buildable).to receive(:build_for_destination) do |*_args, **_kwargs|
  # Simulates xcodebuild's silent re-resolution (STACK.md Experiment H3):
  # the seeded intended pin (aaa111) is discarded and re-resolved to
  # bbb222, rewriting pkg_dir/Package.resolved in place before the build
  # "returns" its artifacts.
  write_resolved(File.join(pkg_dir, "Package.resolved"), "SomePkg", "bbb222")
  {
    derived_data: "/dd",
    object_file: "/dd/SomePkg.o",
    swiftmodule: nil, swiftdoc: nil, swiftsourceinfo: nil, swiftinterface: nil,
  }
end
```
Assertion channels: drift warns go to **stderr**, status line to **stdout** [VERIFIED:
lib/spm_cache/core/log.rb:14-21]:
```ruby
def info(msg = "")
  puts msg
end
...
def warn(msg)
  $stderr.puts "[warn] #{msg}"
end
```
Drift warn text and status line, verbatim [VERIFIED: build_pipeline.rb:143-150]:
```ruby
drifted.each do |identity|
  Core::UI.warn "  #{identity}: drift detected (intended #{intended_pin_map[identity]}, " \
                "realized #{realized_pin_map[identity]})"
end

status = drifted.empty? ? "host-pinned" : "resolution-incompatible"
suffix = status == "resolution-incompatible" ? " (built from source)" : ""
Core::UI.info "  #{name}: #{status}#{suffix}"
```
Existing assertion idiom (both channels chained) [VERIFIED: build_pipeline_provenance_spec.rb:79]:
```ruby
}.to output(/resolution-incompatible/).to_stdout.and output(/SomePkg.*aaa111.*bbb222/).to_stderr
```
The false-positive guard (agreeing pins must NOT warn) has precedent at
build_pipeline_provenance_spec.rb:110 (`expect(SPMCache::Core::UI).not_to receive(:warn)`).

Drift comparison semantics the new spec must respect [VERIFIED: build_pipeline.rb:163-169]:
intersection-only on identity; and pin-value precedence "revision wins over version"
[VERIFIED: build_pipeline.rb:187-191]:
```ruby
def host_pin_value(pin)
  state = pin["state"] || {}
  revision = state["revision"]
  revision.to_s.empty? ? state["version"] : revision
end
```

### Pattern 3: SC4 executable hermeticity guard
**What:** allowlist + fail-on-unexpected instead of blanket allow. Precedent — Class E spec
asserts NO Sh call at all [VERIFIED: spec/build_pipeline_provenance_spec.rb:622-623]:
```ruby
expect(SPMCache::SPM::Buildable).not_to receive(:new)
expect(SPMCache::Core::Sh).not_to receive(:run)
```
Generalization for specs that DO expect specific commands (wrap in `before`):
```ruby
allow(SPMCache::Core::Sh).to receive(:run) do |cmd, *_opts|
  raise "unexpected real invocation: Sh.run(#{cmd.inspect})"
end
allow(SPMCache::Core::Sh).to receive(:capture_output) do |cmd, *_opts|
  raise "unexpected real invocation: Sh.capture_output(#{cmd.inspect})"
end
# then re-allow specific expected commands with .with(...) stubs
```
(Shape follows the existing tier-2 idiom at build_pipeline_seeding_spec.rb:321-322, made
strict.) `Core::Sh.run` and `capture_output` are the only two entry points
[VERIFIED: lib/spm_cache/core/sh.rb:10,44].

### Pattern 4: Real-binary gen-proxy leg (TEST-02 graph buckets)
**What:** skip-if-not-built + `system()` + parse graph.json. Verbatim skip guard [VERIFIED:
spec/gen_proxy_provenance_spec.rb:15-25]:
```ruby
let(:binary) do
  local = SPMCache::ROOT.join("tools", "spm-cache-proxy",
                              ".build", "release", "spm-cache-proxy").to_s
  File.executable?(local) ? local : nil
end

before do
  skip "spm-cache-proxy binary not built (run make proxy.build)" unless binary
end
```
Status extraction idiom [VERIFIED: gen_proxy_provenance_spec.rb:52-55]:
```ruby
def statuses_from(output_dir)
  graph = JSON.parse(File.read(File.join(output_dir, "graph.json")))
  graph.each_with_object({}) { |e, h| h[e["module"]] = e["status"] }
end
```
This is SC4-compatible: the proxy binary is local, compilation happens before RSpec in CI
(`make proxy.build` step precedes `RSpec` step in every matrix leg
[VERIFIED: .github/workflows/ci.yml]), and no network is involved. Binary present locally this
session (verified on disk).

### Edge-Class Matrix — current coverage vs needed fixture shape (TEST-03)

| # | Class | Existing coverage | New fixture shape (hermetic) |
|---|-------|-------------------|------------------------------|
| 1 | binary target (Class E) | `build_pipeline_spec.rb:450+` ("short-circuits to a direct xcframework copy ... FirebaseAnalytics shape"), `build_pipeline_provenance_spec.rb:566-713` | Copy the desc raw + filesystem layout verbatim: `checkouts/firebase-ios-sdk` + sibling `artifacts/firebase-ios-sdk/FirebaseAnalytics/FirebaseAnalytics.xcframework`; forwarder chain with `"sources" => ["dummy.m"]` [VERIFIED shapes: build_pipeline_provenance_spec.rb:582-611; TRIVIAL_FORWARDER_SOURCES = ["dummy.m"].freeze at build_pipeline.rb:539] |
| 2 | macro w/ narrow `swift-syntax` pin | **NONE as fidelity scenario** — `hasMacro` is hardcoded false at ProxyGenerator.swift:91,171 | Pure pin data: seeded `Package.resolved` with a `"swift-syntax"` identity at a narrow pinned revision; drift-inject the realized read-back. No macro-specific production code exists to drive — the class IS the pin-fidelity contract |
| 3 | vendored `.xcodeproj` | `build_pipeline_seeding_spec.rb:165-251`, `build_pipeline_provenance_spec.rb:447+` | `FileUtils.mkdir_p(File.join(pkg_dir, "CryptoSwift.xcodeproj"))` — one dir; classifier is a glob [VERIFIED: resolved_graph.rb:61-63] |
| 4 | plugin-only | `gen_proxy_plugin_spec.rb` + `spec/fixtures/plugin-lockfile.json`; Ruby predicate specs via integrate | Lockfile entry whose `products` are all `type: "plugin"` (fixture file exists verbatim — SwiftGenPlugin entry) |
| 5 | transitive-only | `installer_consumed_dependencies_spec.rb` (consumedProducts); Swift `isTransitiveOnly` skip | Lockfile package not in consumed set → zero graph entry BY DESIGN (see Partition Map hazard 1); the matrix leg asserts it is *classified from the input side*, never silently absent |
| 6 | resource bundle | **NONE as edge class** — only incidental path string at lockfile_enrichment_spec.rb:122 | describe-JSON target carries `"resources": [{"path": ...}]` [VERIFIED parser: desc/target.rb:123-125]; Slice behavior `copy_resource_bundles` copies `*.bundle` with `unless File.exist?(dest)` [VERIFIED: slice.rb:122-128 — the Pitfall 14 stale-bundle behavior]; assert bundle reaches the assembled framework |
| 7 | private Clang shim | `build_pipeline_spec.rb:113-178` | desc raw: target with `target_dependencies` on a `ClangTarget` NOT in product names (the `_NumericsShims` shape) |
| 8 | product≠target rename | `build_pipeline_spec.rb:327+` ("resolves module_name to the product's own target name"), `gen_proxy_field_regression_spec.rb`, `desc_product_spec.rb` | product raw `"targets" => ["<Product>Target"]` differing from product name |

Existing scattered specs stay untouched (CONTEXT lock) — the matrix is NEW coverage that runs
ALONGSIDE them; SC3's "passes unchanged" means no churn to the existing files.

### Anti-Patterns to Avoid
- **Test-of-test vacuity:** asserting on the stub rather than production output. Always assert the sidecar JSON on disk, the stdout/stderr strings, or graph.json — never the double's internals.
- **First-match bucket classification in the spec:** production uses if/elsif (excluded wins over ignored, ProxyGenerator.swift:121-130) — the SPEC's classifier must collect ALL matching buckets per package to detect double-bucketing (SC2's second arm).
- **Iterating the output as the universe:** a partition assertion over "packages the classifier mentioned" is vacuous. Iterate the FIXTURE's declared input list (Package.resolved pins ∪ lockfile local entries).
- **Blanket `allow(Core::Sh).to receive(:run)`:** hides unexpected real invocations; SC4 demands fail-on-unexpected (Pattern 3).
- **Hand-typed bucket name lists:** CONTEXT explicitly forbids; derive from observed `fidelity_status`/`status` values.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Bucket enumeration | Hardcoded `["pinned","ignored",...]` array in the spec | Observed sidecar `fidelity_status` values + graph.json `status` values from production runs | CONTEXT lock: hand-maintained list drifts |
| fnmatch ignore/exclude semantics | Reimplement Ruby-side fnmatch classification to stay "pure" | Drive the production Swift classifier via the gen-proxy binary | A Ruby replica IS a hand-maintained classifier — it drifts from `matchesAnyPattern` |
| Describe-JSON fabrication | Real `swift package describe` in CI | `instance_double(Desc::Description)` + `raw` hashes | Needs Swift toolchain + a real package; violates hermeticity |
| Drift simulation | Real xcodebuild re-resolution | `build_for_destination` stub rewriting `Package.resolved` | The proven injection idiom (Pattern 2) |
| Fixture caching across examples | Global variables / class-level mutation | `let` (per-example) or file-only setup in `before(:context)` | See Pitfall 3 — stubs are illegal in `before(:context)` |

**Key insight:** every problem this phase faces already has a green in-repo precedent; the phase's
risk is entirely in (a) the partition universe definition and (b) the two uncovered edge classes.

## Common Pitfalls

### Pitfall 1: The "single source of truth" premise covers only 3/6 buckets
**What goes wrong:** A TEST-02 spec that drives only `report_fidelity` can never observe
`ignored`/`excluded`/`plugin` — those statuses are Swift-side.
**Why it happens:** CONTEXT says buckets come from "Phase 8's `report_fidelity` classification";
in reality `report_fidelity` emits exactly `"host-pinned"`, `"resolution-incompatible"`,
`"not-graph-pinned"` [VERIFIED: build_pipeline.rb:128,133,148].
**How to avoid:** Hybrid partition (see Open Question 1): fidelity legs via tier-1 seam, graph legs via the compiled binary.
**Warning signs:** meta-spec whose bucket list is a subset of the six; graph-bucket assertions missing.

### Pitfall 2: `let`-memoization does not share across examples
**What goes wrong:** CONTEXT asks for a "memoized shared kitchen-sink fixture via `let`" — but
RSpec `let` is memoized per-EXAMPLE; the kitchen sink rebuilds for every example.
**Why it happens:** `let` semantics; the only cross-example sharing hooks are `before(:context)` /
`before(:all)`, where **stubbing is forbidden and leaks order-dependently**.
**How to avoid:** Either (a) accept per-example builds — the provenance/seeding specs average
well under 1s per group (seeding group: 5.3s/6 examples measured this session; the 2–3s total
target is achievable since each spec's build loop is stubbed), or (b) create only the FILES once
in `before(:context)` (file I/O is legal there) and apply per-example stubs in `before`.
**Warning signs:** suite-time creep beyond ~3s for the new specs; order-dependent failures.

### Pitfall 3: Mixed-granularity partition (product vs package)
**What goes wrong:** graph.json is per-PRODUCT (`module` = product name; one package can emit
several entries with different statuses — and a hit sibling downgrades a missed product to
`.excluded`, ProxyGenerator.swift:155-159). Partitioning per-product yields false "double-bucket".
**How to avoid:** Partition per-package identity (the `name` field of lockfile entries /
`identity` of resolved pins), aggregating product statuses into one package-level bucket.
**Warning signs:** partition assertion fails on the Firebase-style multi-product fixture.

### Pitfall 4: Transitive-only zero-bucket false alarm
**What goes wrong:** asserting "every Package.resolved pin appears in graph.json or a sidecar"
fails BY DESIGN for transitive-only packages (`continue` at ProxyGenerator.swift:109).
**How to avoid:** classify transitive-only pins from the input side (present in
`Package.resolved`, absent from consumed set ⇒ pinned-via-consumer bucket membership), or count
them explicitly in the pinned bucket via their consumer's sidecar pins.
**Warning signs:** realm-core-style fixture pinning the partition red.

### Pitfall 5: `output` matcher swallowing failures
**What goes wrong:** asserting only `.to_stdout` when the contract is the stderr warn (or vice
versa); `Core::UI.warn` prefixes `[warn] ` [VERIFIED: log.rb:20].
**How to avoid:** chain both channels (idiom at provenance spec line 79); match on the drift
trio `intended`/`realized` values verbatim (`aaa111`/`bbb222` precedent).

### Pitfall 6: Ruby 3.1 leg breaking on newer syntax
**What goes wrong:** 3.2+/3.3-only syntax (e.g. `Data.define`, anonymous block forwarding
shorthands, `it` without block in 3.4-isms) greens locally on 3.2 but fails the 3.1 matrix leg.
**How to avoid:** plain RSpec + stdlib; existing 387 examples already run green on 3.1
(CI matrix `ruby: ['3.1', '3.2', '3.3']`, macos-15 [VERIFIED: .github/workflows/ci.yml]).
**Warning signs:** any use of syntax younger than the oldest matrix leg.

### Pitfall 7: Sleeping/timing assertions
**What goes wrong:** inherited flake risk (WR-05 history in STATE.md).
**How to avoid:** no sleeps in the new specs; all interactions are synchronous stubs/filesystem.

## Code Examples

### Class E fixture layout (verbatim, proven)
Source: spec/build_pipeline_provenance_spec.rb:604-613
```ruby
build_root = File.join(tmpdir, "umbrella", ".build")
real_pkg_dir = File.join(build_root, "checkouts", "firebase-ios-sdk")
FileUtils.mkdir_p(real_pkg_dir)
prebuilt = File.join(build_root, "artifacts", "firebase-ios-sdk", "FirebaseAnalytics", "FirebaseAnalytics.xcframework")
FileUtils.mkdir_p(File.join(prebuilt, "ios-arm64", "FirebaseAnalytics.framework", "Headers"))
File.write(File.join(prebuilt, "ios-arm64", "FirebaseAnalytics.framework", "Headers", "FIRAnalytics.h"), "// real header\n")
File.write(File.join(prebuilt, "Info.plist"), "<plist/>")
```
(The artifacts sibling-of-checkouts layout is required by `locate_prebuilt_xcframework`,
build_pipeline.rb:1127-1136 — `File.basename(checkouts_dir) == "checkouts"`.)

### Package.resolved fabrication helper (verbatim)
Source: spec/build_pipeline_provenance_spec.rb:29-31
```ruby
def write_resolved(path, identity, revision)
  File.write(path, JSON.generate("pins" => [{ "identity" => identity, "state" => { "revision" => revision } }]))
end
```
Parser on the read side [VERIFIED: package_resolved.rb:60-72]: tolerant `pins_or_nil` reads
top-level `"pins"`, selecting Hash entries — v2 `object.pins` shape parses to zero pins
(known; diagnostics.rb:128-133 guards it in doctor).

### Lockfile-shaped fixture entry (verbatim, plugin-only)
Source: spec/fixtures/plugin-lockfile.json (SwiftGenPlugin entry)
```json
{
  "repositoryURL": "https://github.com/SwiftGen/SwiftGenPlugin.git",
  "name": "SwiftGenPlugin",
  "version": "6.6.3",
  "products": [
    { "name": "SwiftGenPlugin", "type": "plugin", "targets": ["SwiftGenPlugin"] }
  ]
}
```
Lockfile top-level shape: `{ "<Project>.xcodeproj": { "packages": [...], "dependencies": {}, "platforms": { "ios": "16.0" } } }` [VERIFIED: all four existing `spec/fixtures/*-lockfile.json`].

### Provenance-sidecar fabrication (Phase 9 direction)
Source: spec/gen_proxy_provenance_spec.rb:39-44
```ruby
def write_sidecar(cache_dir, module_name, pins:, status: "host-pinned")
  File.write(
    File.join(cache_dir, "#{module_name}.xcframework.provenance.json"),
    JSON.generate("fidelity_status" => status, "pins" => pins),
  )
end
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| v0.3.0 cache hit = name + `fileExists` | provenance-aware `hit()` (intersection-only pin compare; missing sidecar ⇒ miss) | Phase 9 (v0.4.0) | TEST-01's sidecar-disagreement direction asserts THIS contract |
| unseeded per-package resolution | host-graph seeding before first `describe` (FID-02) | Phase 7 | The seeding the drift read-back then verifies |
| no drift reporting | `report_fidelity` read-back + warn + `resolution-incompatible`/`not-graph-pinned` statuses (FID-03/04/05) | Phase 8 | The classifier TEST-01/02 pin |
| `Dir.glob(...).find` resolved-file location | canonical-path tiered locator (FID-06) | Phase 6 | Specs must fabricate the canonical path when testing locator-adjacent code — new specs here don't need the locator (they pass `resolved_pins_file:` directly) |

**Deprecated/outdated:** `.planning/research/SUMMARY.md:207` suggested a single
`spec/build_fidelity_regression_spec.rb` — superseded by CONTEXT's two dedicated files plus a
meta-spec. The roadmap's "258 green examples" figure is also stale: the suite is now
387 examples (verified by run this session).

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The compiled proxy binary is an acceptable drive mechanism for the graph-status legs of TEST-02 (i.e. SC4's "existing Sh/Desc/Buildable seams" tolerates the gen-proxy tier-3 precedent already present in the suite) | Partition Map, Open Question 1 | If the verifier reads SC4 strictly as tier-1-only, the graph legs need a different observation route; low likelihood since `gen_proxy_provenance_spec.rb` itself ships in the same suite |
| A2 | "Resource bundle" edge class means: a describe-JSON target with a `resources` array, whose `*.bundle` must reach the assembled framework (Pitfall 14 semantics) | Edge-Class Matrix #6 | If the operator means a different v0.2.x incident shape, the fixture asserts the wrong thing |
| A3 | TEST-02 meta-spec filename is planner's discretion (CONTEXT names only two of three files) | Project Structure | Cosmetic only |
| A4 | ~2–3s total-runtime target is achievable with per-example fixture builds under tier-1 stubs (extrapolated from measured seeding-group average 0.88s/example; not yet measured for the kitchen sink) | Pitfall 2 | If kitchen-sink builds prove slower, use `before(:context)` file-only setup |

All other claims in this document are `[VERIFIED: path:lines]` against files read this session, or direct tool output (suite run).

## Open Questions (RESOLVED)

1. **TEST-02 observation route for the three graph buckets** — RESOLVED (2026-08-29, plan adoption)
   - What we know: `ignored`/`excluded`/`plugin` exist ONLY in the Swift ProxyGenerator output (graph.json); no Ruby classifier produces them except the `plugin_only_package?` predicate. CI builds the proxy binary before RSpec on every matrix leg.
   - What was unclear: whether driving the compiled binary inside the new meta-spec violates the CONTEXT's "driven through the seams" phrasing.
   - Recommendation (ADOPTED): hybrid (tier-1 for fidelity legs, tier-3 gen-proxy pattern for graph legs, buckets derived only from observed output). This is the only route that honors "no hand-maintained bucket list".
   - Resolution: the hybrid two-surface route is adopted in 10-02-PLAN.md (objective + Tasks 1-2): fidelity legs (host-pinned / resolution-incompatible / not-graph-pinned) observe provenance sidecars via the tier-1 object-stub seam; graph legs (ignored / excluded / plugin) drive the compiled proxy binary via the tier-3 gen-proxy pattern; every bucket name is derived from observed production output. Assumption A1 (tier-3 binary is SC4-compatible) is accepted on the `gen_proxy_provenance_spec.rb` same-suite precedent.
2. **Kitchen-sink sharing mechanics** — RESOLVED (2026-08-29, plan adoption)
   - What we know: `let` is per-example; `before(:context)` forbids stubs.
   - What was unclear: whether per-example rebuild meets the ~2–3s target for all three specs combined.
   - Recommendation (ADOPTED): start per-example (simplest, no order-dependence); measure; switch to file-only `before(:context)` + per-example stubs only if over target.
   - Resolution: per-example `let` builds are adopted across all three plans (10-01/10-02/10-03 tier-1 scaffolds rebuild per example); runtime is measured and recorded in the plan SUMMARYs against the ~2–3s target (10-02 and 10-03 record the fidelity specs' combined wall-clock). Escalation to file-only `before(:context)` + per-example stubs remains the documented fallback if measurement exceeds the target.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Ruby | all new specs | ✓ | 3.2.3 (local; CI matrix 3.1/3.2/3.3) | — |
| bundler + rspec | test runner | ✓ | rspec ~> 3.12 (suite ran green this session) | — |
| spm-cache-proxy release binary | TEST-02 graph legs (tier 3) | ✓ built locally; CI builds it before RSpec | current main | spec skips with "spm-cache-proxy binary not built" (existing convention) — but then graph-bucket assertions silently do not run locally |
| Xcode / xcodebuild | nothing (SC4 forbids) | not exercised | — | — |
| Network | nothing | not needed | — | — |

**Missing dependencies with no fallback:** none.
**Missing dependencies with fallback:** proxy binary (skip-guard precedent; on CI it is always built, so the Ruby matrix legs always execute it).

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | RSpec ~> 3.12 (bundler, dev group) |
| Config file | none (no `.rspec`, no `spec/spec_helper.rb` config block — helper only requires `spm_cache/main`) |
| Quick run command | `bundle exec rspec spec/fidelity_drift_regression_spec.rb spec/fidelity_bucket_partition_spec.rb spec/fidelity_edge_matrix_spec.rb` |
| Full suite command | `bundle exec rspec` (measured this session: 387 examples, 0 failures, 46.77s) |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| TEST-01 / SC1 | out-of-range pin (resolution read-back drift) is warned + `resolution-incompatible` sidecar, NOT silently re-resolved | unit (hermetic, tier-1) | `bundle exec rspec spec/fidelity_drift_regression_spec.rb` | ❌ Wave 0 |
| TEST-01 / SC1b | agreeing pins produce NO warn (false-positive guard) | unit | same file | ❌ Wave 0 |
| TEST-01 / SC1c | provenance-sidecar disagreement (Phase 9 semantics) yields miss, not silent hit | unit + real-binary leg | same file (sidecar-fabrication pattern; or reuse-t assertion) | ❌ Wave 0 |
| TEST-02 / SC2 | every Package.resolved pin + every lockfile local entry lands in exactly ONE of the six buckets; zero-bucket AND double-bucket both fail the assertion | meta-spec (kitchen sink) | `bundle exec rspec spec/fidelity_bucket_partition_spec.rb` | ❌ Wave 0 |
| TEST-03 / SC3 | 8-class table-driven matrix passes | unit (hermetic, tier-1) | `bundle exec rspec spec/fidelity_edge_matrix_spec.rb` | ❌ Wave 0 |
| SC4 | new specs execute zero real swift/xcodebuild invocations (allowlist guard fails on unexpected) | guard inside each new spec | included in each quick command above | ❌ Wave 0 |
| SC4 (matrix) | suite green on Ruby 3.1/3.2/3.3 | CI | `bundle exec rspec` on ci.yml matrix legs | ✅ ci.yml |

### Sampling Rate
- **Per task commit:** `bundle exec rspec spec/fidelity_*.rb` (target: completes in ~2–3s)
- **Per wave merge:** `bundle exec rspec` (full suite, ~47s)
- **Phase gate:** full suite green on every CI matrix leg before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `spec/fidelity_drift_regression_spec.rb` — TEST-01 (drift both directions + false-positive guard + sidecar-disagreement leg)
- [ ] `spec/fidelity_bucket_partition_spec.rb` — TEST-02 (kitchen-sink fixture + partition assertion; name per A3)
- [ ] `spec/fidelity_edge_matrix_spec.rb` — TEST-03 (8-class table-driven matrix)
- [ ] `spec/fixtures/fidelity-kitchen-sink-lockfile.json` — only if lockfile-shaped fixture data is needed for the kitchen sink
- No framework install needed; no `spec/support/` needed (flat convention maintained)

## Security Domain

`security_enforcement: true`, `security_asvs_level: 1` (config read this session). This phase is
test-only: no production code is added or modified, so no new ASVS controls are introduced.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | test-only phase; no auth surface touched |
| V3 Session Management | no | none |
| V4 Access Control | no | none |
| V5 Input Validation | no (in production) | fixtures are repo-authored data, not runtime user input; existing parse-hardening (`pins_or_nil` tolerant reader, `rescue JSON::ParserError` in `existing_sidecar_pins`) is what the new specs ASSERT against, not extend |
| V6 Cryptography | no | none; sidecar integrity is out of scope (CACHE-F* future work) |

### Known Threat Patterns for this phase

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Fixture/sidecar content treated as instructions (injection into the agent workflow) | Elevation of Privilege | untrusted-input boundary applies to authored fixtures only as data; no eval/exec of fixture content in specs (and none should be added) |
| Secrets leakage into committed fixtures | Information Disclosure | fixtures use fake URLs/revisions only (existing convention: `git@bitbucket.org:axonivy-prod/...` style URLs carry no credentials — keep it that way) |

## Sources

### Primary (HIGH confidence — files read this session, quoted verbatim)
- lib/spm_cache/spm/build_pipeline.rb — `report_fidelity` (102-154), `drifted_identities` (163-169), `host_pin_value` (187-191), sidecar write (220-237), `seed_host_graph` (244-254), Class E path (1069-1136), `TRIVIAL_FORWARDER_SOURCES` (539)
- tools/spm-cache-proxy/Sources/Core/Generator/ProxyGenerator.swift — Status enum (16-24), pattern matching (34-62), status decision (118-130), plugin/transitive skip (84-109), mixed-status downgrade (155-159)
- lib/spm_cache/cache/cachemap.rb — status readers (15-33)
- lib/spm_cache/core/package_resolved.rb — locator + `pins_or_nil` (14-72)
- lib/spm_cache/spm/resolved_graph.rb — `vendored_xcodeproj?` (61-63), `RESOLVED_FILENAME` (15)
- lib/spm_cache/core/diagnostics.rb — local-package exclusion (95-118)
- lib/spm_cache/core/sh.rb — the seam (10-51)
- lib/spm_cache/spm/desc/base.rb — describe shell-out (51-56)
- lib/spm_cache/spm/desc/target.rb — `resource_paths` (123-125)
- lib/spm_cache/spm/xcframework/slice.rb — `copy_resource_bundles` (122-128)
- lib/spm_cache/core/log.rb — UI streams (14-24)
- lib/spm_cache/installer.rb — `plugin_only_package?` (660-665), never-cached products (615-626)
- spec/build_pipeline_provenance_spec.rb, spec/build_pipeline_seeding_spec.rb, spec/resolved_graph_spec.rb, spec/gen_proxy_provenance_spec.rb, spec/gen_proxy_ignore_spec.rb — seam idioms quoted verbatim
- .github/workflows/ci.yml — Ruby matrix 3.1/3.2/3.3 on macos-15, `make proxy.build` before `bundle exec rspec`
- .planning/research/PITFALLS.md (Pitfall 14), .planning/research/SUMMARY.md:161,207 — v0.2.x edge-class definitions
- Tool run this session: full suite `387 examples, 0 failures`, 46.77s; slowest-group profile captured

### Secondary (MEDIUM confidence)
- None needed — no external libraries are introduced by this phase

### Tertiary (LOW confidence)
- None — no external claims were required (ROADMAP classifies this phase as pattern-reuse; external documentation lookups would add nothing)

## Project Constraints (from CLAUDE.md / AGENTS.md)

- **GitHub CLI account:** before any `gh` command, `gh auth switch --hostname github.com --user phuongddx` (not exercised by this phase, listed for completeness)
- **GSD workflow enforcement:** repo edits only through GSD entry points (`/gsd-execute-phase` for this phase's work)
- **Ruby conventions:** `# frozen_string_literal: true` first line of every new `.rb`; RuboCop (~> 1.50) clean, `make format` auto-corrects; snake_case methods, CamelCase classes; flat `spec/` naming `<subject>_spec.rb`; `spec_helper.rb` requires `spm_cache/main`; RSpec built-in matchers only (no new matcher gems)
- **No new runtime gem dependencies without justification** (PROJECT.md constraint) — this phase adds none
- **No `git stash`** (absolute rule, Phase 7 incident)
- **Commit docs:** `commit_docs: true` — research/plan artifacts are committed

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new dependencies; everything verified in-repo
- Architecture (seams + partition map): HIGH — every classification branch located and quoted with line ranges; suite executed green as final proof the seams work
- Pitfalls: HIGH — derived from measured behavior (suite profile) and read source, not speculation
- Graph context: none — `.planning/graphs/graph.json` is stale (60h old, 126 commits behind; Phase 8/9 code postdates the build) and returned zero nodes for capability queries ("fidelity classification report_fidelity", "BuildPipeline", "regression test spec"); treat any graph-derived relationships as unavailable for this phase

**Research date:** 2026-08-29
**Valid until:** indefinite (in-repo code references; re-verify line numbers only after edits to build_pipeline.rb / ProxyGenerator.swift)
