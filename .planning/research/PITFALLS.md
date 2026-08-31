# Pitfalls Research

**Domain:** SPM binary-cache tooling — forcing a host-resolved dependency graph onto isolated per-package `xcodebuild` builds, plus cross-repo release automation
**Researched:** 2026-08-27
**Confidence:** HIGH (core SwiftPM/xcodebuild claims verified empirically on this machine; codebase claims verified by reading source)

---

## Verification Basis

Every SwiftPM/xcodebuild claim below was reproduced locally rather than recalled. Toolchain used:

- `xcodebuild -version` → **Xcode 26.3 (17C529)**
- `swift --version` → **Apple Swift 6.2.4 (swiftlang-6.2.4.1.4)**

Probe scripts and outputs live in the session scratchpad (`probe-xcodebuild-pin-fidelity.sh`, `probe-xcodebuild-out-of-range.sh`). Four load-bearing results:

| # | Experiment | Result |
|---|-----------|--------|
| V1 | Seed a package checkout with a `Package.resolved` pinning an **older but in-range** version, run plain `swift package resolve` / `xcodebuild -scheme` | **Pin is honored.** No float to latest. File not rewritten. Checkouts land in `<derivedDataPath>/SourcePackages/checkouts`, *not* the package's `.build`. |
| V2 | Same, but pin is **out of range** of the package's own `Package.swift` (`upToNextMinor(from: "1.0.0")` vs pin `1.1.1`) — plain `xcodebuild` | **exit 0, `** BUILD SUCCEEDED **`.** SwiftPM silently discarded the pin, resolved `1.0.3`, and **rewrote `Package.resolved` in the checkout**. Green build, wrong artifact, evidence destroyed. |
| V3 | Same mismatch with `-onlyUsePackageVersionsFromResolvedFile` | **exit 74**, `xcodebuild: error: Could not resolve package dependencies: an out-of-date resolved file was detected at …, which is not allowed when automatic dependency resolution is disabled`. **`Package.resolved` left untouched.** SwiftPM CLI equivalent exits **1**. |
| V4 | Format probe: tools-version `5.9` vs `6.0` | `5.9` → `"version": 2`, no `originHash`. `6.0` → `"version": 3` **with** `originHash`. A v3 file with a **deliberately corrupt `originHash` and extra foreign pins** was still accepted (exit 0) — and SwiftPM **checked out every listed pin**, including packages the manifest never depends on. |

Flag aliasing, verified from `swift package --help` (Swift 6.2.4):

```
RESOLUTION:
  --force-resolved-versions, --disable-automatic-resolution, --only-use-versions-from-resolved-file
                          Only use versions from the Package.resolved file and
                          fail resolution if it is out-of-date.
```

Three names, one flag. The `xcodebuild` counterparts (`-onlyUsePackageVersionsFromResolvedFile`, `-disableAutomaticPackageResolution`) carry an identical description in `xcodebuild -help` and behave the same (V3).

**The single most important consequence: the fix is only safe if it is applied together with the forced-resolution flag.** Injecting a host `Package.resolved` *without* it converts today's "wrong version, at least deterministically" into "wrong version, silently, with the injected file overwritten so nothing downstream can tell." V2 is the shape of the worst outcome of this milestone.

---

## Critical Pitfalls

### Pitfall 1: Treating the umbrella's resolved graph as "the host graph"

**What goes wrong:**
The obvious implementation is to reuse whatever `swift package resolve` produced in `{umbrella_dir}/.build/` (`checkout_resolver.rb:24`) as the authoritative graph and push it down into per-package builds. But the umbrella is **not** the host app — it is a synthesized root manifest (`UmbrellaGenerator.swift`) whose dependency list is deliberately *not* the app's:

- `if pkg.isPluginOnly { continue }` — plugin-only packages are **omitted entirely** (line 42).
- `if pkg.isTransitiveOnly(consumedProducts:), pkg.revision == nil || pkg.repositoryURL == nil { continue }` — transitive-only packages are **omitted when no revision is held** (lines 64–67), by design, because pinning them independently was breaking resolve.
- Platforms are **clamped** to whatever the `PackageDescription` enum defines (lines 95–104).

A different root manifest with a different dependency set is a different resolution problem. SwiftPM is free to (and will) resolve omitted-and-floated transitive packages to versions the app never resolved. Enshrining that as "the host graph" ships a *second* wrong graph and calls it fidelity.

**Why it happens:**
The umbrella is the only place `swift package resolve` currently runs, so it feels like the resolution authority. It is not — it is a *checkout materializer*, exactly as its own comment says ("The umbrella's only job is checkout materialization").

**How to avoid:**
Make the **app's own `Package.resolved`** the sole authority for versions. The umbrella keeps its current job (fetching sources). Add an explicit assertion step that compares umbrella-resolved versions against the app's pins and reports every divergence — that diff is the actual bug surface and should be visible, not implicit.

**Warning signs:**
- Any code path that reads `{umbrella_dir}/Package.resolved` and calls it "the host graph."
- A package whose cached artifact version cannot be traced back to a line in the app's `Package.resolved`.

**Phase to address:** Graph Authority (proposed Phase 1) — before any injection work.

---

### Pitfall 2: The "host graph" you inject is a stale first-run snapshot

**What goes wrong:**
`spm-cache.lock` is the only structure carrying host versions, and it is **written exactly once, ever**:

```ruby
# lib/spm_cache/installer.rb:164-166
def generate_lockfile_from_resolved
  lockfile_path = @config.lockfile_path
  return if File.exist?(lockfile_path)   # <-- never refreshed
```

`Core::Lockfile#load` replaces `@raw` wholesale from disk; nothing else writes `version`/`revision`. `refresh_consumed_dependencies` touches only `dependencies`; `invalidate_stale_products!` touches only `products[]`. And `lockfile_path` is `project_dir/spm-cache.lock` — **outside** `sandbox_dir`, so `recreate_dirs`' `rm_rf(sandbox)` never clears it.

So: `DiffDetector` correctly *detects* that Alamofire moved 5.8.0 → 5.10.2 and correctly forces a full regeneration — and then the regeneration rebuilds the umbrella from a lockfile that still says 5.8.0. The umbrella pins `revision:` at the 5.8.0 commit (`Lockfile.swift:119-120`: revision wins over version). Checkouts materialize at 5.8.0. Everything downstream is faithful — to a graph the app abandoned.

This is a strong candidate for the *actual* root of "release-config cache builds link stale transitive versions," independent of the `-scheme`-in-isolated-checkout problem stated in the milestone. **Verify which one dominates before building the fix**, or the milestone can ship a correct injection mechanism fed by stale input and still be wrong.

**Why it happens:**
The early-return reads as an idempotency guard ("don't clobber the user's lockfile"), and `DiffDetector` gives a convincing illusion of freshness because it prints an accurate diff. The diff is computed but never *applied*.

**How to avoid:**
Make lockfile sync a real reconciliation: re-read the app's `Package.resolved` on every non-fast-path run and update `version`/`revision` per package (preserving enriched `products[]`, which is expensive to recompute and orthogonal to version). Treat `DiffDetector`'s `updated` list as the contract — after a run, re-running the detector must return an empty diff. That is a directly testable invariant.

**Warning signs:**
- `DiffDetector` reports the *same* `~N updated` set on two consecutive `use` runs.
- `spm-cache.lock` versions differ from the project's `Package.resolved`.
- Deleting `spm-cache.lock` "fixes" a stale-binary complaint.

**Phase to address:** Graph Authority (proposed Phase 1). This must land **before** injection, or Phase 2 is unverifiable.

---

### Pitfall 3: Silent re-resolution — the injected pin is discarded, the build goes green, the file is overwritten

**What goes wrong:**
Verified as **V2** above. When the injected host pin falls outside the package's own declared requirement, plain `xcodebuild` does not warn, does not fail, and does not stop. It resolves to something else, **rewrites the `Package.resolved` you just wrote into the checkout**, and reports `BUILD SUCCEEDED` with exit 0.

The rewrite is the vicious part: it deletes the evidence. A post-build audit that re-reads the file in the checkout sees a self-consistent, plausible graph and confirms the build was "faithful."

**Why it happens:**
SwiftPM's default posture is "resolve to something that works." A resolved file is a *hint*, not a constraint, unless you say otherwise. Nothing in a normal build log flags the substitution.

**How to avoid:**
1. **Always pass the forced-resolution flag** with the injection — `-onlyUsePackageVersionsFromResolvedFile` for `xcodebuild` (build_pipeline's `Buildable#build_command`), `--only-use-versions-from-resolved-file` for any `swift package` invocation. Verified (V3): this yields **exit 74** with an explicit `an out-of-date resolved file was detected` message, and leaves the file untouched.
2. Never rely on "the build succeeded" as evidence of fidelity. Assert the *resolved-at* version post-build (see Pitfall 5's provenance manifest).
3. Add a spec that pins a fixture package out of range and asserts the pipeline **fails** rather than succeeds. A green-only test suite cannot catch this class.

**Warning signs:**
- Post-build `git status`/mtime shows `Package.resolved` modified inside a checkout.
- Build succeeds for a package whose manifest range demonstrably excludes the host pin.

**Phase to address:** Pinned Resolution (proposed Phase 2), with the negative test in Regression Coverage (proposed Phase 4).

---

### Pitfall 4: Defining the incompatible-graph policy as "fall back to what works"

**What goes wrong:**
Once the flag from Pitfall 3 is in place, builds that used to pass will now **hard-fail** (exit 74). The tempting fix is to catch that and retry without the flag — which reinstates Pitfall 3 by another name, and does so precisely for the packages where fidelity matters most.

There is also an existing amplifier: `Installer::Build#build_single_target` swallows failures when `@config.ignore_build_errors?` and merely warns. A resolution incompatibility would be logged as one line in a 60-package run and scroll away.

**What should happen when the host graph is genuinely incompatible with a package's declared requirements:**

The host graph is, by construction, the truth — the app *does* build with it. If a package's manifest range excludes the host pin, one of these holds:
1. The package's declared range is stale/over-narrow but it actually compiles fine against the host version (common: `upToNextMinor` on a well-behaved dep).
2. The package genuinely cannot compile against the host version (real API break).

Case 2 means the app itself is only building because SwiftPM found a graph-wide solution that spm-cache's per-package view cannot see (e.g. the app links a *different* product, or the conflicting edge is condition-excluded by platform).

The correct policy is therefore **not** "pick a version" — it is **"do not cache this product."**

**How to avoid:**
- On resolution incompatibility, **skip caching that one product and let it fall through to source compilation.** spm-cache already has this exact escape hatch as a first-class, validated behavior ("Cache-miss automatic fallback to source compilation — v0.1.0"; `spm-cache off [TARGETS]`). A source-compiled product is *always* correct. Use it.
- Report the skip **prominently and structurally**, not as a warning line: a machine-readable list of `resolution-incompatible` products, surfaced in `cache list`, in the `doctor` registry (a natural 8th check), and in the cachemap as a distinct status alongside `hit`/`missed`/`ignored`/`excluded`/`plugin`.
- Make it **loud on first occurrence, quiet afterwards** — record it in the lockfile so a repeat run doesn't re-fail, but a *newly* incompatible package always announces itself.
- Do **not** let `ignore_build_errors` mask a resolution incompatibility. It is a build-error valve, not a correctness valve; resolution failures should bypass it.

**Warning signs:**
- A retry-without-the-flag branch anywhere in the pipeline.
- Cache hit-rate stays at 100% after the fix ships (it should measurably drop; a fix that changes nothing changed nothing).

**Phase to address:** Pinned Resolution (proposed Phase 2) for the policy; Cache Identity (proposed Phase 3) for the status plumbing.

---

### Pitfall 5: The cache key cannot express the fix — every pre-fix artifact stays a "hit"

**What goes wrong:**
This is the pitfall most likely to make the entire milestone invisible to users. Cache hit is a bare filesystem existence check:

```swift
// tools/spm-cache-proxy/Sources/Core/Cache.swift
func hit(module: String) -> URL? {
    let xcframework = dir.appendingPathComponent("\(module).xcframework")
    return FileManager.default.fileExists(atPath: xcframework.path) ? xcframework : nil
}
```

Nothing about version, revision, transitive graph, toolchain, or spm-cache version participates. Three consequences, all live today and all made **worse** by fixing resolution:

1. **The fix does not reach existing users.** Every `~/.spm-cache/<config>/*.xcframework` built by v0.3.0 with the wrong transitive graph remains a hit under v0.4.0. Users upgrade, see no change, and correctly conclude the fix does not work.
2. **Cross-project poisoning.** `CACHE_DIR = File.expand_path("~/.spm-cache")` is **global, not per-project** (`core/config.rb:25`). Project A on Alamofire 5.8 and Project B on 5.10 share one `Alamofire.xcframework`. Whoever built first wins, silently, for both. Fixing per-package transitive resolution does nothing about this — it arguably makes it more surprising, because now the artifact's *contents* depend on a graph the other project never had.
3. **Version bumps never invalidate.** Bump a dep, `DiffDetector` reports it, and the cached xcframework from the old version is still a hit.

`Installer::Build` only bypasses a hit for **slice** incompleteness (`slice_complete?`), never for graph identity.

**Why it happens:**
Content-addressed cache keys are explicitly deferred to v0.5 in `PROJECT.md` ("HIGH effort"). That deferral was made when the cache key's only job was "do we have this module." Once artifact *contents* become a function of the resolved graph, key-by-name is no longer a performance shortcut — it is a correctness hole.

**How to avoid:**
Full content-addressing is not required and should stay deferred. The minimum viable v0.4.0 mechanism is a **provenance sidecar** — reuse the pattern already proven by `<module>.xcframework.shims.json`:

- Write `<module>.xcframework.provenance.json` recording: the product's own resolved version/revision, the resolved version/revision of every transitive dependency actually compiled against, the `spm-cache` version, config, and destination set.
- Extend the hit check: a hit requires the provenance to **match the current host graph**. Missing provenance (every pre-v0.4.0 artifact) ⇒ **miss**, forcing a one-time rebuild. That is the invalidation mechanism, and it costs one JSON read.
- This also makes the cross-project collision *detectable* (Project B sees a provenance mismatch and rebuilds) rather than silent. Whether to then partition the cache directory per-graph is a v0.5 decision; detecting is the v0.4.0 obligation.

**Warning signs:**
- Post-fix upgrade produces zero rebuilds.
- Two projects on the same machine with different pins of the same package both report 100% hits.
- `cache list` cannot answer "what version is this artifact?"

**Phase to address:** Cache Identity & Invalidation (proposed Phase 3). **This phase is not optional** — without it Phase 2's correctness never reaches a user's machine.

---

### Pitfall 6: Dirtying a checkout that is shared across products, destinations, and runs

**What goes wrong:**
Writing `Package.resolved` into `{umbrella}/.build/checkouts/<pkg>/` mutates state that is **not** private to one build:

- **Shared across products.** `checkout_map` maps *every* product name of a package to the *same* checkout dir. realm-swift's `Realm` and `RealmSwift`, or Collections' whole family, all build from one directory, sequentially, each writing the file.
- **Shared across destinations.** `BuildPipeline.run` loops `destinations.each` over the same `pkg_dir`.
- **Shared across runs.** `derived_data_dir_for` is deliberately keyed by `Digest::SHA256(File.expand_path(pkg_dir))` "so it stays stable and is reused across different targets built from the same checkout, preserving incremental-build speed."
- **Already mutated.** `Buildable#xcodebuild` runs `FileUtils.chmod_R("u+w", @pkg_dir)` on every invocation — the checkout is not treated as read-only today. That was a *targeted* permission grant (DeviceKit's gyb script); it should not be read as license for arbitrary writes.
- **And xcodebuild writes back.** Verified (V2): on a mismatch, xcodebuild rewrites the file itself.

Net effect: build product 1 (writes graph G), build product 2 from the same checkout (writes G again, fine), but interleave a *rewrite* from V2 and the checkout now holds a graph nobody chose.

**Why it happens:**
`Package.resolved` "belongs next to `Package.swift`," so writing it into the checkout looks like the natural home. The checkout is dependency source under `.build/`, though — conceptually read-only vendored code.

**How to avoid:**
- Write the injected file **atomically** (temp + `File.rename`) and **restore/remove it** in an `ensure` block so a checkout is never left carrying a graph from an aborted build.
- Snapshot the original `Package.resolved` (many checkouts commit one) before overwriting; a package left permanently holding spm-cache's synthetic file is a debugging trap for anyone who inspects the checkout.
- Prefer isolating the resolution scratch state via `-clonedSourcePackagesDirPath` (verified present in Xcode 26.3: "specifies the directory to which remote source packages are fetch or expected to be found") so per-build resolution artifacts land somewhere spm-cache owns, not in the shared checkout.
- Add an idempotency assertion: building the same product twice must leave the checkout **byte-identical**. The v0.3.0 cycle already established this pattern (`init` byte-stable double-run) — reuse it.

**Warning signs:**
- Second build of the same package behaves differently from the first.
- A checkout's `Package.resolved` differs from what spm-cache wrote.
- Building product B of a package changes the artifact for product A.

**Phase to address:** Pinned Resolution (proposed Phase 2).

---

### Pitfall 7: Class E binary targets break when resolution paths move

**What goes wrong:**
`copy_prebuilt_binary_target` → `locate_prebuilt_xcframework` (build_pipeline.rb:873-882) hard-codes SwiftPM's scratch layout and a positional assumption:

```ruby
checkouts_dir = File.dirname(pkg_dir)
return nil unless File.basename(checkouts_dir) == "checkouts"
build_dir = File.dirname(checkouts_dir)
primary = File.join(build_dir, "artifacts", File.basename(pkg_dir), target_name, "#{target_name}.xcframework")
```

It requires `pkg_dir`'s parent to be *literally named* `checkouts`, and expects `artifacts/` as its sibling — i.e. it depends on the umbrella's `swift package resolve` having unpacked the `.binaryTarget` there as a side effect. Any change that (a) redirects resolution to a per-package scratch/`-clonedSourcePackagesDirPath`, (b) moves checkouts, or (c) resolves per-package instead of via the umbrella, breaks this.

The failure is not subtle — `raise "No prebuilt .xcframework found for binaryTarget…"` — but under `ignore_build_errors` it degrades to a warning, and FirebaseAnalytics/FirebaseFirestoreInternal silently drop out of the cache. That is a direct regression of the v0.2.8 Class E fix.

Note the `xcodebuild` counterpart is a *second*, independent checkout tree: verified (V1) that `xcodebuild -derivedDataPath D` clones into `D/SourcePackages/checkouts`, **not** the package's `.build`. The umbrella tree and the build tree are already two different graphs on disk; a fix that only pins one of them is half a fix.

**Why it happens:**
The Class E path short-circuits *before* scheme resolution and any xcodebuild call, so it looks orthogonal to a "build" change. It is not — it is coupled to resolution layout.

**How to avoid:**
- Route binary-target artifact lookup through **one** function that derives paths from the same configuration the resolution step uses; never re-derive by `File.dirname` walking.
- Keep a Class E fixture (FirebaseAnalytics-shaped: product name == binaryTarget name, wrapper chain two hops deep) in the regression matrix.
- Assert the `raise` path is reachable and tested — silence here is the failure mode.

**Warning signs:**
- `FirebaseAnalytics`/`FirebaseFirestoreInternal` move from cached to skipped.
- `No prebuilt .xcframework found for binaryTarget` in logs.

**Phase to address:** Regression Coverage (proposed Phase 4), with the path-derivation refactor in Phase 2.

---

### Pitfall 8: `Package.resolved` format-version and `originHash` mismatches

**What goes wrong:**
The host and the package can disagree about the file format. Verified (V4): the format version is a function of the **root manifest's** `swift-tools-version` — `5.9` → v2 (no `originHash`), `6.0` → v3 (`originHash` present). A modern app writes v3; a package pinned at tools-version 5.7 does not natively produce one.

Two specific traps:

1. **`originHash` is a hash over the root manifest's dependency declarations.** The host's `originHash` is computed from the *host's* dependency set and is meaningless inside a package checkout. Verified (V4): a corrupt `originHash` was tolerated (exit 0) in the cases probed — but this is undocumented tolerance, not a contract, and is exactly the kind of thing a toolchain update tightens. Do not rely on it.
2. **Extra pins are checked out.** Verified (V4): a resolved file listing packages the manifest never depends on caused SwiftPM to **create working copies for all of them**. See Pitfall 9.

**How to avoid:**
- **Synthesize, don't copy.** Do not `cp` the host `Package.resolved` into a checkout. Generate a fresh file per package: read the package's own tools-version, emit the matching format version (v2 vs v3), include only pins the package's own dependency closure needs, and **omit `originHash` entirely** for v3 rather than copying a wrong one (a v3 file with no `originHash` is the honest representation of "synthesized").
- Detect the tools-version from `swift package describe`/manifest rather than assuming — the codebase already runs `Desc::Description#fetch` for every package on every build, so the data is a field away.
- Cover both format versions with fixtures; a pure-v3 test suite will not catch a v2 package.

**Warning signs:**
- `Package.resolved` "unknown version" / decode errors on older packages.
- Injection works on modern packages and silently no-ops on older ones.

**Phase to address:** Pinned Resolution (proposed Phase 2).

---

### Pitfall 9: Resolution fan-out — N packages × the whole host graph

**What goes wrong:**
Verified (V4): SwiftPM checks out **every** pin listed in a resolved file, not just the ones the manifest needs. Naively injecting the full host graph into each of 59–70 package checkouts means each isolated resolve materializes the entire graph. Combined with the fact that `xcodebuild` maintains its *own* `SourcePackages/checkouts` per `-derivedDataPath` (V1), and `derived_data_dir_for` creates one DerivedData **per checkout per destination**, the worst case is:

`70 packages × 2 destinations × 70 clones` of source into `~/.spm-cache/derived_data/`.

That is a disk-space and wall-clock regression severe enough to negate the tool's entire value proposition, and it would present as "spm-cache got slow," not as "the resolution fix is wrong."

**How to avoid:**
- Emit a **minimal** per-package resolved file (Pitfall 8) containing only that package's dependency closure — not the host's full pin list.
- Share the clone store across builds via `-clonedSourcePackagesDirPath` pointing at one spm-cache-owned directory, and/or `-packageCachePath` for the repository cache (both verified present in Xcode 26.3). Also consider `-disablePackageRepositoryCache` being left **off** — the repository cache is what makes repeat clones cheap.
- Benchmark before/after on a real 59–70 package project. The repo already has `benchmark-report.html`; treat a wall-clock regression as a milestone blocker, not a follow-up.

**Warning signs:**
- `~/.spm-cache/derived_data` growth measured in tens of GB.
- "Fetching …/Creating working copy for …" for packages unrelated to the product being built.
- Build time increases after the fix.

**Phase to address:** Pinned Resolution (proposed Phase 2), verified in Regression Coverage (proposed Phase 4).

---

### Pitfall 10: Reused DerivedData retains modules compiled against the previous graph

**What goes wrong:**
`derived_data_dir_for` is keyed **only** by the checkout path — deliberately, "so it stays stable and is reused across different targets built from the same checkout, preserving incremental-build speed." Nothing in the key reflects the resolved graph. Change the graph, rebuild, and Xcode's incremental machinery may reuse `.swiftmodule`s built against the *old* transitive versions.

This produces the exact silent-corruption signature the milestone exists to eliminate — and it survives the fix, because the fix changes what gets resolved, not what gets reused.

**How to avoid:**
- Incorporate a graph fingerprint into the DerivedData key (the same fingerprint the provenance sidecar uses in Pitfall 5). A graph change then naturally lands in a fresh tree; the old tree is garbage-collectable.
- Alternatively, wipe the DerivedData tree when the fingerprint changes. Slower, simpler, and still far cheaper than a wrong binary.
- Do **not** simply stop reusing DerivedData — that is a large, uncompensated build-time regression on the tool's core promise.

**Warning signs:**
- A rebuild after a dep bump completes suspiciously fast.
- Artifact contents differ between a fresh-machine build and an incremental one — a good CI check: build twice from clean vs. incremental and compare provenance.

**Phase to address:** Cache Identity & Invalidation (proposed Phase 3) — shares the fingerprint with the provenance sidecar.

---

### Pitfall 11: Vendored `.xcodeproj` packages ignore `Package.resolved` entirely

**What goes wrong:**
A significant, already-hardened class of packages in this codebase build from a **committed `.xcodeproj`**, not from `Package.swift`: CryptoSwift, AppAuth-iOS, SVGKit, DTCoreText, DeviceKit, AEXML, FSPagerView, SkeletonView. For these, `Buildable#project_disambiguation_flag` adds `-project '<vendored>.xcodeproj'` and `BuildPipeline#run_with_scheme` drives the fallback path.

`xcodebuild -project Foo.xcodeproj` resolves dependencies from **the project's own package references**, not from a sibling `Package.swift`/`Package.resolved`. Injecting a resolved file next to `Package.swift` is a **no-op** for this whole class. Two failure modes follow:

1. **False confidence.** The milestone reports "all packages now build against the host graph"; this class silently still doesn't.
2. **New hard failures.** If the fix adds `-onlyUsePackageVersionsFromResolvedFile` unconditionally and a vendored project *does* carry package references whose resolved state doesn't match, previously-green builds start exiting 74. These packages were fixed one at a time across v0.2.x; each regression is a field bug returning.

Aggravating detail: `xcodebuild -list -project` (used by `schemes_across_projects` and `project_has_scheme?`) can itself trigger package resolution — meaning *scheme discovery* can rewrite state before the build begins.

**How to avoid:**
- Classify each package before injecting: SPM-native vs. vendored-`.xcodeproj`. Apply injection and the forced flag **only** to the SPM-native path.
- Report vendored-project packages as an explicit, named category of "not graph-pinned" rather than folding them into "cached." Honest partial coverage beats a false 100%.
- Keep the whole named list above in the regression matrix — each represents a paid-for fix.

**Warning signs:**
- Any of the eight named packages changes status after the fix.
- `Unknown build action`, `contains N projects`, `libarclite`, or `is only available in iOS X` errors reappearing — these are the v0.2.x signatures.

**Phase to address:** Pinned Resolution (proposed Phase 2) for the classification; Regression Coverage (proposed Phase 4) for the fixtures.

---

### Pitfall 12: Macro targets and the `swift-syntax` version conflict

**What goes wrong:**
`swift-syntax` is the single most likely source of a genuine host-vs-package incompatibility. Macro packages pin it narrowly (`509.0.0`, `510.x`, `600.x`) and a host graph routinely carries a newer major than an individual macro package's manifest accepts. Under the forced flag this is exactly the exit-74 case from V3 — and macros are load-bearing: a failed macro plugin fails every consumer target, not just its own.

Additionally, `spm-cache` caches macros as `.macro` binaries (validated v0.1.0), and `BinariesCache.binaryPath(for:)` is the same name-only existence check as `hit(module:)` — so Pitfall 5 applies to macros with no separate mechanism.

**How to avoid:**
- Treat macro packages as a **first-class case in the incompatibility policy** (Pitfall 4), not an edge case: on conflict, drop the macro to source compilation rather than failing the run.
- Consider excluding macro packages from graph pinning in v0.4.0 entirely if the fixture matrix shows conflicts are common — a documented, narrow exclusion beats a broad breakage. Record it as a dated decision, matching the v0.3.0 amendment pattern.
- Note `-skipMacroValidation` exists (`xcodebuild -help`, Xcode 26.3) for the *trust-prompt* problem — it does not affect version resolution and must not be reached for as a fix here.

**Warning signs:**
- `exit 74` concentrated on macro packages.
- Macro plugin fails to load; every consumer target fails to compile.

**Phase to address:** Pinned Resolution (proposed Phase 2), fixture in Regression Coverage (proposed Phase 4).

---

### Pitfall 13: Plugin-only and transitive-only packages disappear from the pinned graph

**What goes wrong:**
Both classes were explicitly hardened in v0.2.0–v0.2.8 and both are *omitted from the umbrella by design* (`UmbrellaGenerator.swift:42`, `:64-67`). If the injected resolved file is derived from the umbrella (Pitfall 1) rather than the app:

- **Plugin-only packages are missing from the pin list.** Any package with a build-tool plugin dependency (SwiftLint, swift-protobuf, SwiftGen) then has an unpinnable edge. Under the forced flag → `an out-of-date resolved file was detected` → exit 74 for every such package. This is a broad regression, not a narrow one.
- **Transitive-only packages float.** The realm-core case documented in `refresh_consumed_dependencies` is precisely a package the app never links directly. If it is absent from the injected pins, SwiftPM resolves it freely — and transitive drift is *the exact bug this milestone exists to fix*.

**How to avoid:**
- Derive pins from the **app's `Package.resolved`**, which contains every resolved package regardless of how it is reached, including plugin-only and transitive-only ones. The umbrella's omissions are a resolve-time workaround and must not propagate into the pin source.
- Add a coverage assertion: every package in the app's `Package.resolved` is either (a) pinned in some injected file, (b) explicitly classified `ignored`/`excluded`/`plugin`, or (c) reported `resolution-incompatible`. No package may silently fall through.
- Keep `expand_target_aliases`' plugin-only handling intact — it deliberately leaves plugin-only identities unmapped rather than vanishing them (`installer/build.rb:107-109`).

**Warning signs:**
- Packages with build-tool plugins fail en masse after the fix.
- A package present in `Package.resolved` appears in none of spm-cache's status buckets.

**Phase to address:** Graph Authority (proposed Phase 1) + Regression Coverage (proposed Phase 4).

---

### Pitfall 14: Stale resource bundles survive a graph change

**What goes wrong:**
`Slice#copy_resource_bundles` refuses to overwrite:

```ruby
Dir.glob(File.join(build_dir, "*.bundle")).each do |bundle|
  dest = File.join(@framework_path, File.basename(bundle))
  FileUtils.cp_r(bundle, dest) unless File.exist?(dest)   # <-- skip if present
end
```

Bundle names are stable across versions (`<Package>_<Target>.bundle`), so after a version change the *name* still matches and the **old bundle content is kept**. Localized strings, assets, and `.strings` files silently stay at the previous version while code moves forward. `Bundle.module` resolves — to stale resources. Green build, wrong app.

This is independent of the resolution fix but is amplified by it: the whole point of v0.4.0 is that artifact contents now track the graph, and resources are the one part that provably don't.

**How to avoid:**
- Make bundle copying unconditional within a fresh build (`rm_rf(dest)` then `cp_r`), or scope the guard to genuine within-run duplicates rather than across-run staleness.
- Include resource-bundle content in the provenance fingerprint (Pitfall 5).
- Fixture: a package with a resource bundle, built at v1 then v2 with a changed string; assert the cached bundle carries the v2 string.

**Warning signs:**
- Updated dependency, unchanged localized strings or assets in the app.
- Bundle mtimes older than the surrounding framework.

**Phase to address:** Cache Identity & Invalidation (proposed Phase 3).

---

### Pitfall 15: `watch` re-entrancy destroys checkouts mid-build

**What goes wrong:**
`recreate_dirs` does `FileUtils.rm_rf(sandbox_dir)` — and `umbrella_dir` is `sandbox/packages/umbrella`, so **every non-fast-path run deletes `.build/checkouts` wholesale**. `UmbrellaGenerator.generate()` then calls `outputDir.recreate()`, deleting it again.

Today builds are strictly sequential (`missed.each`), so this is survivable. But v0.3.0 shipped `watch`, which re-triggers integration on `Package.resolved`/`project.pbxproj` change. An Xcode-initiated re-resolve during a long `spm-cache build` fires the watcher, which re-runs `use`, which `rm -rf`s the checkout tree **out from under the in-flight build**. The result is an arbitrary partial failure — likely surfacing as "checkout not found for 'X'; skipping" or a mid-build file-not-found, i.e. *silently fewer cached products*.

Injecting per-checkout state (Pitfall 6) widens this window and adds a torn-write mode: a build reading a `Package.resolved` that another run is rewriting.

**How to avoid:**
- Add a **process-level lock** (an flock on a file under `sandbox_dir`) held across integration and build. The `watch` debounce is a coalescing timer, not mutual exclusion.
- Make the watcher **defer** rather than interrupt: if a build holds the lock, queue the re-sync for after it. `watch` already has a self-trigger guard (v0.3.0 Phase 5) — extend that ownership model to builds.
- Do not adopt `Core::Parallel` for the build loop in this milestone. Parallel builds over shared checkouts + per-checkout injected state is a data race with a correctness (not just crash) failure mode. Defer.

**Warning signs:**
- "checkout not found for 'X'; skipping" appearing non-deterministically.
- Cached product count varying between identical runs.
- `watch` running concurrently with a manual `spm-cache build`.

**Phase to address:** Pinned Resolution (proposed Phase 2) for the lock; explicitly out of scope for parallelism.

---

### Pitfall 16: Library-evolution does not make a version mismatch safe

**What goes wrong:**
There is a tempting inference: "we build with `-enable-library-evolution` and `BUILD_LIBRARY_FOR_DISTRIBUTION=YES` (`Buildable#library_evolution_flags`), so a cached framework compiled against dependency v1 is ABI-safe when the app links v2."

It is not. Library evolution provides **resilience for the evolving library itself** — a client compiled against `Foo` v1's `.swiftinterface` keeps working with `Foo` v2's binary. It says nothing about a *third* framework that was compiled against `Foo` v1 and is now co-linked with `Foo` v2. Concretely:

- `@inlinable` and `@_transparent` bodies from v1 are **copied into** the cached framework at build time and are not re-emitted. If v1's inlined implementation touched storage that v2 relocated, behavior diverges from what source compilation would produce.
- `@frozen` types and `@usableFromInline` internals are ABI commitments; changes across a *major* dep version are legitimate and will not be caught by the linker.
- Duplicate symbols: if `Foo` is both linked by the app and statically archived into the cached framework's `libtool -static` output (`create_static_library`), the symbol is present twice with different implementations — the same duplicate-symbol family already documented throughout `spm-cache.yml`.
- The codebase already relies on `.swiftinterface` contents at consumer-compile time (`referenced_module_names` scans for `import`/`@_exported import`), so a v1-emitted interface naming v1-only modules is a compile-time break, not just a runtime one.

**How to avoid:**
- Do not treat library evolution as a version-mismatch mitigation anywhere in reasoning, docs, or code comments. It is a *binary-distribution* enabler.
- The mitigation for version mismatch is Pitfall 5's provenance check: a mismatch must produce a **miss**, not a tolerated hit.
- Detect rather than trust: after a cached build, verify each product's `.swiftinterface` `import` list resolves against the *current* graph's modules. A stale interface naming a module the current graph no longer contains is a positive detection signal, cheap to compute, and reuses machinery that already exists.

**Warning signs:**
- Runtime crashes or wrong behavior with no compile-time error, only in cached mode.
- `no such module 'X'` from a cached framework's interface.
- Duplicate-symbol link warnings.

**Phase to address:** Cache Identity & Invalidation (proposed Phase 3).

---

## Release Automation Pitfalls

Reading `.github/workflows/update-tap.yml` against the milestone's "silent workflow failure went unnoticed on v0.2.7" history, the file contains **three independent silent-failure mechanisms**. The expired PAT is the visible symptom; it is not the most dangerous defect present.

### Pitfall 17: `curl -L` without `--fail` hashes a 404 page into the formula

**What goes wrong:**

```yaml
curl -L "$TARBALL_URL" -o release.tar.gz
SHA=$(shasum -a 256 release.tar.gz | awk '{print $1}')
```

Verified from `man curl` on this machine: without `-f/--fail`, "when an HTTP server fails to deliver a document, it returns an HTML document stating so" — curl **writes that error page to the output file and exits 0**. `--fail` is what makes it "fail fast with no output at all on server errors" and return error 22.

`release: published` can fire before the tag's source tarball is servable. When it does, `release.tar.gz` is a GitHub 404 HTML page, `shasum` cheerfully hashes it, and the formula is published with the sha256 of an error page. The workflow is **green**. Every subsequent `brew install spm-cache` fails with a checksum mismatch — for every user, until someone notices manually. This is the same detection gap as v0.2.7, with a worse blast radius.

**How to avoid:**
- `curl --fail --location --show-error --silent --retry 5 --retry-delay 10 --retry-all-errors`.
- Then **verify the artifact is what you think it is**: `tar -tzf release.tar.gz > /dev/null` and assert a non-trivial byte size before hashing. A tarball that does not list is not a tarball.
- Prefer resolving the tarball URL from the release event payload rather than string-building it from `GITHUB_REF_NAME`.

**Warning signs:** Formula sha256 changes but the release did not; `brew install` checksum mismatch reported by a user.
**Phase to address:** Release Automation (proposed Phase 5).

---

### Pitfall 18: `git commit … || exit 0` converts every failure into success

**What goes wrong:**

```yaml
git commit -m "chore: update spm-cache to ${VERSION}" || exit 0
git push
```

The intent is "tolerate no-op re-runs." The effect is that **any** commit failure — including the `sed` commands having matched nothing because the formula's shape changed — exits the step **0**, skips the push, and reports a fully green workflow that published nothing. This is precisely the v0.2.7 failure class, still present.

**How to avoid:**
- Distinguish the two cases explicitly: check `git diff --quiet Formula/spm-cache.rb`. If unchanged **and** the formula already declares the expected version → legitimate no-op, exit 0. If unchanged and it does **not** → hard failure.
- Assert the intended end state before committing: `grep -q "v${VERSION}.tar.gz" "$FORMULA"` and `grep -q "$SHA" "$FORMULA"`, failing loudly otherwise. Verify the outcome, not the mechanism.
- Add `set -euo pipefail` to every multi-line `run:` block. None of them currently have it.

**Warning signs:** Green `update-tap` run with no commit in the tap repo; tap formula version lagging the latest release.
**Phase to address:** Release Automation (proposed Phase 5).

---

### Pitfall 19: Unanchored `sed` rewrites the wrong lines

**What goes wrong:**

```bash
sed -i "s|sha256 \".*\"|sha256 \"${SHA}\"|" "$FORMULA"
sed -i "s|version \".*\"|version \"${VERSION}\"|" "$FORMULA"
```

`s|sha256 ".*"|` is unanchored and matches **every** `sha256` line in the file — including bottle-block sha256 lines, resource-block sha256 lines, and any future addition. Adding bottles to the formula (a natural next step for a Homebrew tap) would corrupt them all in one shot, and the workflow would report success. `sed` also exits 0 when nothing matched, so a formula restructure silently produces a no-op that Pitfall 18 then swallows.

**How to avoid:**
- Anchor to the top-level stanza (`^  sha256 "`) or, better, generate the formula from a template rather than in-place editing a file whose structure the workflow does not control.
- Verify post-condition with `grep -c`, asserting an exact expected match count.
- Consider `brew bump-formula-pr` or `brew audit --strict`/`brew style` against the edited formula as a gate before pushing.

**Warning signs:** Unexpected diff hunks in the tap commit; `brew audit` failures; bottle checksums changing.
**Phase to address:** Release Automation (proposed Phase 5).

---

### Pitfall 20: Fine-grained PAT expiry is a scheduled outage (the current `Bad credentials`)

**What goes wrong:**
`secrets.TAP_REPO_TOKEN` is a cross-repo PAT. Fine-grained PATs carry a **mandatory expiry**; classic PATs with `repo` scope are broader than needed and, if set to no-expiry, are a standing credential. Either way the failure is invisible until a release is attempted — and by then it blocks shipping. `${{ secrets.TAP_REPO_TOKEN }}` is also evaluated at `actions/checkout` time, so an empty/expired secret surfaces as a checkout failure whose message (`Bad credentials`) does not name the token.

**How to avoid:**
- Replace the PAT with a **GitHub App installation token** via `actions/create-github-app-token` (official `actions` org). Installation tokens expire after **1 hour** and are minted per-run, so there is no annual expiry to babysit and no long-lived credential at rest. Inputs: `client-id` (variable) + `private-key` (secret).
- Scope the App installation to the **tap repo only**, with `contents: write` and `metadata: read` — nothing else. Do **not** grant `workflow` scope; the tap contains no workflows to modify, and that scope is what turns a leaked token into a supply-chain compromise.
- Whichever credential is used, add a **cheap liveness probe** that runs on a schedule (not only on release): authenticate and read the tap repo. A monthly cron catching `Bad credentials` two weeks before a release costs nothing. This fits naturally as a `doctor`-style check, matching the v0.3.0 pattern of making invisible drift visible.

**Warning signs:** `Bad credentials`; `Resource not accessible by personal access token`; checkout of the tap failing while everything else passes.
**Phase to address:** Release Automation (proposed Phase 5).

---

### Pitfall 21: The workspace retains the token after checkout

**What goes wrong:**
`actions/checkout` persists credentials into `<path>/.git/config` by default so subsequent `git` commands authenticate. That is what makes the bare `git push` work here — but it also means the token sits in the job workspace for the remainder of the run, readable by any later step or action. The `update-tap` job has no `permissions:` block at all, so it also inherits the repository-default `GITHUB_TOKEN` scope alongside the PAT.

**How to avoid:**
- Add an explicit least-privilege block to the job: `permissions: contents: read` (the PAT/App token supplies tap write; `GITHUB_TOKEN` needs nothing more).
- Keep the tap checkout as the **last** credential-bearing step, and avoid adding third-party actions to this job.
- Never `set -x` in a step that interpolates a secret. `cat "$FORMULA"` is safe today; a debugging `set -x` added later would not be.
- Pin third-party actions by commit SHA rather than tag if any are introduced.

**Warning signs:** New steps appended after the tap checkout; third-party actions added to this job; `set -x` in a `run:` block.
**Phase to address:** Release Automation (proposed Phase 5).

---

### Pitfall 22: Nobody is told when the release workflow fails

**What goes wrong:**
The v0.2.7 incident is the proof: a failure was "only caught manually." A `release: published` workflow runs rarely and asynchronously, so nobody is watching the Actions tab at the moment it fails. Even after Pitfalls 17–19 are fixed to fail *loudly*, loud is worthless without a listener.

**How to avoid:**
- Add a `if: failure()` notification step (issue creation via `gh issue create` is zero-infrastructure and lands in the repo the maintainer already reads).
- Add a **post-publish verification job** that is the actual definition of done: wait for the tap commit, then `brew install --build-from-source phuongddx/spm-cache/spm-cache` on a `macos-*` runner and assert `spm-cache --version` matches the tag. This closes the loop end-to-end and would have caught v0.2.7, the 404-tarball case, and the sed case with one check.
- Make the release checklist assert the *observable outcome* (formula on the tap declares version X and installs) rather than the *action* (workflow ran).

**Warning signs:** A release exists with no corresponding tap commit; users on an older version than the latest release.
**Phase to address:** Release Automation (proposed Phase 5).

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Inject the resolved graph without the forced-resolution flag | No new build failures; nothing regresses | Silent wrong artifacts + the injected file is overwritten (V2), destroying evidence. Strictly worse than today. | **Never** |
| Retry without the flag when resolution fails | Keeps hit-rate at 100% | Reinstates the exact bug the milestone fixes, on the packages where it matters most | **Never** |
| Use the umbrella's resolved graph as the authority | No lockfile-refresh work needed | Ships a second, subtly-wrong graph and calls it fidelity; unfalsifiable | **Never** |
| Ship pinned resolution without cache invalidation | Smaller milestone | The fix reaches no existing user; cache stays cross-project poisoned | **Never** — pair Phase 2 with Phase 3 |
| Copy the host `Package.resolved` verbatim into each checkout | Trivial to implement | Format/`originHash` mismatch; whole-graph clone fan-out per package (V4) | Prototype/spike only |
| Skip caching a resolution-incompatible product (source fallback) | Correct by construction; reuses a validated v0.1.0 behavior | Lower hit rate for those products | **Recommended** — this is the right answer, not debt |
| Exclude macro packages from graph pinning in v0.4.0 | Avoids the most likely conflict class | Macro transitive drift persists | Acceptable **if** recorded as a dated decision with a v0.5 follow-up |
| Leave `~/.spm-cache` globally shared | No migration | Cross-project collisions persist | Acceptable **only** once provenance makes collisions *detected* (miss) rather than silent |
| `git commit … \|\| exit 0` | Tolerates no-op re-runs | Converts every failure into green (v0.2.7) | **Never** |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| `xcodebuild` + SwiftPM | Assuming a green build means the requested versions were used | Pass `-onlyUsePackageVersionsFromResolvedFile`; verified exit 74 on mismatch (V3) |
| `xcodebuild` checkouts | Assuming it reuses `{umbrella}/.build/checkouts` | It clones into `<derivedDataPath>/SourcePackages/checkouts` (V1). Control with `-clonedSourcePackagesDirPath` |
| `swift package resolve` | Believing a pre-seeded pin is always honored | Honored **only** if in-range (V1); silently discarded + file overwritten if not (V2) |
| `Package.resolved` format | Assuming one format | v2 for tools-version 5.x, v3 + `originHash` for 6.x (V4). Synthesize per package |
| `originHash` | Copying the host's value | Meaningless outside the host root manifest. Omit rather than copy a wrong one |
| Resolved-file pin list | Assuming extra pins are ignored | SwiftPM **checks out every listed pin** (V4). Emit the minimal closure |
| Vendored `.xcodeproj` packages | Assuming `Package.resolved` governs them | It does not. Classify and exclude from injection (Pitfall 11) |
| `xcodebuild -list -project` | Treating scheme discovery as read-only | It can trigger resolution and mutate state before the build |
| Homebrew tap | Trusting the workflow's exit code | Verify the observable outcome: `brew install` + `--version` assertion |
| GitHub PAT | Long-lived cross-repo token | `actions/create-github-app-token` (1-hour installation tokens), tap-only, `contents: write` |
| `curl` in CI | Omitting `--fail` | Without it, a 404 HTML page is written to the output file and curl exits 0 |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Full-graph pin list per package | "Fetching…/Creating working copy…" for unrelated packages; tens of GB in `~/.spm-cache/derived_data` | Minimal per-package closure + shared `-clonedSourcePackagesDirPath` | Immediately at this project's real scale (59–70 packages) |
| Per-checkout × per-destination DerivedData | Disk growth; slow cold builds | Shared clone/repository cache; GC old fingerprinted trees | 70 pkgs × 2 destinations today |
| Graph fingerprint in the DerivedData key | Full rebuild on any dep bump | Fingerprint the *package's own closure*, not the whole host graph, so one bump invalidates only affected packages | Any routine dependency update |
| Provenance check on every hit | Slower cache lookup | One small JSON read per module — negligible vs. a build | Not expected to break |
| Parallelizing builds over shared checkouts | Non-deterministic artifacts | Do not parallelize in this milestone; add the lock first | Whenever `Core::Parallel` is adopted for the build loop |

---

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Long-lived PAT with `repo` scope for tap pushes | Standing write access to every repo the owner can reach | GitHub App token, tap-only, `contents: write` + `metadata: read` |
| Granting `workflow` scope to the tap token | A leak lets an attacker modify CI workflows → supply-chain compromise | Never grant it; the tap has no workflows |
| No `permissions:` block on `update-tap` | Job inherits default `GITHUB_TOKEN` scope on top of the PAT | Explicit `permissions: contents: read` |
| Token persisted in the workspace `.git/config` after checkout | Readable by any later step/action in the job | Keep the tap checkout last; add no third-party actions; pin any by SHA |
| `set -x` in a secret-interpolating step | Token printed to logs | Prohibit; use `set -euo pipefail` without `-x` |
| Publishing a formula whose sha256 was never verified against a real tarball | Users install unverified content, or installs break | `--fail` + `tar -tzf` validation + post-publish `brew install` check |
| Shell-string interpolation in `core/git.rb` (carried from v0.3.0) | Injection surface via package URLs/names | Out of scope here, but note that Phase 2 adds more interpolated shell args (`build_command`) — do not widen it |

---

## "Looks Done But Isn't" Checklist

- [ ] **Pinned resolution:** often missing the forced-resolution flag — verify a deliberately out-of-range fixture **fails** (exit 74 / exit 1), not succeeds
- [ ] **Pinned resolution:** often missing the file-rewrite guard — verify the checkout's `Package.resolved` is byte-identical after a build
- [ ] **Graph authority:** often uses the umbrella's graph — verify every injected pin traces to a line in the **app's** `Package.resolved`
- [ ] **Lockfile freshness:** often unfixed — verify `DiffDetector` returns an **empty** diff on the run immediately after a version bump
- [ ] **Cache invalidation:** often absent — verify a pre-v0.4.0 artifact is treated as a **miss**, not a hit
- [ ] **Cache invalidation:** often untested cross-project — verify two projects with different pins of one package do not share an artifact silently
- [ ] **Coverage completeness:** verify every package in `Package.resolved` lands in exactly one bucket (pinned / ignored / excluded / plugin / resolution-incompatible) — none silently absent
- [ ] **Binary targets:** verify `locate_prebuilt_xcframework` still resolves after any path change (FirebaseAnalytics fixture)
- [ ] **Vendored `.xcodeproj`:** verify all eight named packages build; verify they are reported as *not graph-pinned* rather than as cached
- [ ] **Macros:** verify a macro package with a narrow `swift-syntax` pin either builds or falls back to source — never fails the whole run
- [ ] **Resource bundles:** verify a changed string in a bumped dependency actually reaches the cached bundle
- [ ] **Performance:** verify wall-clock and disk on a real 59–70 package project, before/after
- [ ] **Concurrency:** verify `watch` cannot delete checkouts during an in-flight build
- [ ] **Release:** verify the tap formula installs and reports the right version — not merely that the workflow was green
- [ ] **Release:** verify a deliberately broken tarball URL makes the workflow **red**

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Silent wrong artifact shipped (P3) | **HIGH** | No detection after the fact — the rewrite destroys evidence. Recovery = purge `~/.spm-cache` on every machine + rebuild. Prevention is the only real control. |
| Stale lockfile (P2) | LOW | Delete `spm-cache.lock`, re-run `use`. Add the reconciliation so it cannot recur. |
| Stale cache after fix (P5) | LOW | `cache clean` + rebuild. Ship provenance so it self-heals instead. |
| Checkout dirtied (P6) | LOW | `rm -rf {sandbox}/packages/umbrella` and re-resolve; checkouts are derived state. |
| Class E regression (P7) | MEDIUM | Restore the path derivation; rebuild affected products. Detectable via the `raise`. |
| Fan-out blowup (P9) | LOW | `rm -rf ~/.spm-cache/derived_data`; fix the pin-list scope. |
| Bad sha256 in tap formula (P17/P19) | MEDIUM | Push a corrected formula immediately; users see checksum failures until then. Post-publish `brew install` check bounds exposure to minutes. |
| Expired token (P20) | LOW (blocking) | Mint a new credential; re-run the workflow. Move to App tokens + scheduled probe so it stops recurring. |
| Corrupted formula from unanchored `sed` (P19) | MEDIUM | Revert the tap commit; regenerate from template. |

---

## Pitfall-to-Phase Mapping

Phase names are **proposals** — `.planning/ROADMAP.md` has no v0.4.0 phases yet. Ordering is load-bearing: Phase 1 must precede Phase 2 (Phase 2 is unverifiable against a stale graph), and Phase 3 must ship with Phase 2 (without it Phase 2 reaches no user).

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| P1 Umbrella-as-authority | 1 — Graph Authority | Every injected pin traces to the app's `Package.resolved`; umbrella-vs-app divergence is reported |
| P2 Stale lockfile snapshot | 1 — Graph Authority | Post-run `DiffDetector` returns empty; lock versions == `Package.resolved` |
| P13 Plugin-only / transitive-only omitted | 1 — Graph Authority | Every resolved package lands in exactly one status bucket |
| P3 Silent re-resolution | 2 — Pinned Resolution | Out-of-range fixture exits 74/1; checkout `Package.resolved` byte-identical after build |
| P4 Incompatibility policy | 2 — Pinned Resolution | Incompatible product is reported `resolution-incompatible` and source-compiled, never silently substituted |
| P6 Dirtied checkout | 2 — Pinned Resolution | Double-build byte-stability (reuse the `init` idempotency pattern) |
| P8 Format / `originHash` | 2 — Pinned Resolution | Fixtures at tools-version 5.x (v2) and 6.x (v3) both pin correctly |
| P9 Fan-out | 2 — Pinned Resolution | Clone count and disk delta bounded on a 59–70 package project |
| P11 Vendored `.xcodeproj` | 2 — Pinned Resolution | All eight named packages build; reported as not-graph-pinned |
| P12 Macro / `swift-syntax` | 2 — Pinned Resolution | Narrow-pin macro fixture builds or falls back; never fails the run |
| P15 `watch` re-entrancy | 2 — Pinned Resolution | Concurrent `watch` + `build` cannot delete checkouts; lock held |
| P5 Name-only cache key | 3 — Cache Identity | Pre-v0.4.0 artifact ⇒ miss; two projects with different pins do not share silently |
| P10 DerivedData reuse | 3 — Cache Identity | Clean-vs-incremental builds produce matching provenance |
| P14 Stale resource bundles | 3 — Cache Identity | Bumped-dependency string change reaches the cached bundle |
| P16 Library-evolution false safety | 3 — Cache Identity | Cached `.swiftinterface` imports resolve against the current graph |
| P7 Class E path assumption | 4 — Regression Coverage | FirebaseAnalytics fixture still cached; `raise` path tested |
| All v0.2.x edge classes | 4 — Regression Coverage | Fixture matrix green: plugin-only, transitive-only, binary target, macro, vendored `.xcodeproj`, multi-project, resource bundle, private Clang shim, cross-package companion, product≠target rename |
| P17 `curl` without `--fail` | 5 — Release Automation | Broken tarball URL makes the workflow red |
| P18 `\|\| exit 0` | 5 — Release Automation | Non-matching `sed` makes the workflow red |
| P19 Unanchored `sed` | 5 — Release Automation | `grep -c` post-condition asserts exact match counts |
| P20 PAT expiry | 5 — Release Automation | App-token mint succeeds; scheduled liveness probe green |
| P21 Token in workspace | 5 — Release Automation | Explicit `permissions:` block; tap checkout is the last credentialed step |
| P22 Silent workflow failure | 5 — Release Automation | Post-publish `brew install` + `--version` assertion; `if: failure()` notification |

---

## Prioritization for Roadmap

Ordered by *risk of regressing currently-working behavior*, highest first — per the downstream consumer's instruction to prioritize regression over theory:

1. **P3 / P4** — the flag and the incompatibility policy. Getting these wrong makes v0.4.0 strictly worse than v0.3.0.
2. **P2** — stale lockfile. Plausibly the real root cause; certainly makes Phase 2 unverifiable if left.
3. **P5** — cache key. Determines whether the fix reaches anyone.
4. **P11 / P13 / P7 / P12** — the paid-for v0.2.x edge classes most exposed to a resolution change.
5. **P6 / P15** — checkout mutation and `watch` re-entrancy; latent today, activated by this change.
6. **P9 / P10** — performance and incremental-reuse; will present as "spm-cache got slow/wrong" rather than as a resolution bug.
7. **P17 / P18 / P19 / P22** — release automation silent-failure trio + detection. Small, independent, and the highest value-per-hour work in the milestone.
8. **P20 / P21** — token durability and scope. Fixes the visible symptom; do it, but do not mistake it for fixing the pipeline.

---

## Open Questions for Planning

1. **Which root cause dominates?** The milestone states the isolated-checkout `-scheme` problem. P2 (never-refreshed lockfile) is an independent, verified-in-code path to the same symptom. Reproduce a release-config stale-transitive build and attribute it **before** Phase 2 is planned — the fix differs.
2. **Where does the injected resolved file live?** Inside the checkout (simple, mutates shared state — P6) vs. a spm-cache-owned scratch reached via `-clonedSourcePackagesDirPath` (cleaner, interacts with the Class E path assumption — P7). This is the central design decision of Phase 2.
3. **How wide is the incompatibility blast radius?** Unknown until measured. Run the injection + forced flag against the real 59–70 package project in report-only mode and count exit-74s **before** committing to the policy. If it is 2 packages, hard-fail-and-source-compile is trivially right; if it is 20, the milestone needs rescoping.
4. **Is `~/.spm-cache` partitioned in v0.4.0 or v0.5?** Provenance-detects-collision is the minimum. Per-graph partitioning is a bigger change that overlaps the deferred content-addressing work.
5. **Does the `action/` composite repo need coordinated changes?** It is out of scope per `PROJECT.md`, but if the cache key gains provenance, any cached-artifact restore step in the Action is affected.

---

## Sources

**Primary — empirical, this machine, 2026-08-27** (highest confidence):
- `xcodebuild -version` → Xcode 26.3 (17C529); `swift --version` → Apple Swift 6.2.4
- `xcodebuild -help` — SPM flag inventory and descriptions (`-onlyUsePackageVersionsFromResolvedFile`, `-disableAutomaticPackageResolution`, `-clonedSourcePackagesDirPath`, `-packageCachePath`, `-skipPackageUpdates`, `-disablePackageRepositoryCache`, `-resolvePackageDependencies`, `-skipPackagePluginValidation`)
- `swift package --help` — RESOLUTION section confirming the three-name alias of one flag
- `man curl` — `-f, --fail` semantics
- Probe scripts: `probe-xcodebuild-pin-fidelity.sh`, `probe-xcodebuild-out-of-range.sh` (V1–V4 in the Verification Basis table)

**Primary — codebase, read directly**:
- `lib/spm_cache/spm/build_pipeline.rb` (Class E, companions, shims, DerivedData keying, scheme resolution)
- `lib/spm_cache/spm/build.rb` (`Buildable#build_command`, `chmod_R u+w`, library-evolution flags, object-file fan-out)
- `lib/spm_cache/spm/checkout_resolver.rb`, `lib/spm_cache/installer.rb`, `lib/spm_cache/installer/build.rb`, `lib/spm_cache/installer/use.rb`
- `lib/spm_cache/core/lockfile.rb`, `core/config.rb`, `core/diff_detector.rb`, `cache/cachemap.rb`, `spm/xcframework/slice.rb`
- `tools/spm-cache-proxy/Sources/Core/Cache.swift`, `Sources/Core/Generator/UmbrellaGenerator.swift`, `Sources/Core/Lockfile.swift`
- `.github/workflows/update-tap.yml`, `.github/workflows/ci.yml`
- `.planning/PROJECT.md`, `.planning/RETROSPECTIVE.md`, `.planning/ROADMAP.md`

**Secondary — web** (MEDIUM confidence, used only for release-automation context):
- [actions/create-github-app-token](https://github.com/actions/create-github-app-token) — 1-hour installation tokens, `client-id` + `private-key` inputs
- [Push commits to another repository with GitHub Actions](https://some-natalie.dev/blog/multi-repo-actions/) — cross-repo token patterns
- [GitHub community discussion #191613 — safely using a token to push](https://github.com/orgs/community/discussions/191613) — `GITHUB_TOKEN` vs PAT guidance
- [GitHub community discussion #160535 — fine-grained PATs and private repo checkout](https://github.com/orgs/community/discussions/160535) — mandatory expiry, `Bad credentials` causes
- [softprops/action-gh-release #217 — release 404](https://github.com/softprops/action-gh-release/issues/217) — release-event timing/404 class

---
*Pitfalls research for: SPM binary-cache build fidelity + cross-repo release automation (spm-cache v0.4.0)*
*Researched: 2026-08-27*
