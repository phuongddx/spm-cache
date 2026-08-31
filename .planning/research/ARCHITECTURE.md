# Architecture Research

**Domain:** SPM binary-cache build pipeline (Ruby CLI + Swift companion, macOS/Xcode)
**Milestone:** v0.4.0 — Build Fidelity & Release Automation
**Researched:** 2026-08-27
**Confidence:** HIGH (build fidelity — empirically verified on this machine, Xcode 26.3 / Swift 6.2.4) · MEDIUM (release automation — vendor-documented patterns, not exercised here)

---

## 0. Evidence Standard

Every claim below is tagged:

- **VERIFIED** — read in this repo's code (file:line given) or reproduced empirically on this machine in a scratch harness.
- **ASSUMED** — reasoned from SwiftPM/Xcode semantics, not directly executed.

Empirical probes were run against `tools/spm-cache-proxy` (a real SPM package with two remote deps) and a synthetic package, using `xcodebuild -resolvePackageDependencies` and a full `xcodebuild build`, on **Xcode 26.3 (17C529) / swift-driver 1.127.15 / Apple Swift 6.2.4**. Probe artifacts live under the session scratchpad and are disposable.

---

## 1. The Failure Mechanism — Verified, and Worse Than Stated

The milestone framing says isolated builds "re-resolve from the package's OWN committed `Package.resolved`". The real mechanism is more severe.

**VERIFIED (repo):** `Installer::Build#build_single_target` (`lib/spm_cache/installer/build.rb:119-143`) looks up a checkout dir at line 120 and calls `SPM::BuildPipeline.run` at lines 128-134. That signature (`lib/spm_cache/spm/build_pipeline.rb:33`) carries `name/pkg_dir/destinations/out_dir/library_evolution` — **no resolved-graph parameter exists anywhere in the call chain**.

**VERIFIED (repo):** the actual build shell-out is assembled in `SPM::Buildable#build_command` (`lib/spm_cache/spm/build.rb:98-108`) and executed with `cwd: @pkg_dir` (`lib/spm_cache/spm/build.rb:80`). The command carries no package-resolution flags of any kind. The checkout is therefore a **root package** to xcodebuild.

**VERIFIED (empirical):** surveying the 24 real upstream packages in this machine's SwiftPM repository cache (`~/Library/Caches/org.swift.swiftpm/repositories/`) at their newest tag — firebase-ios-sdk, GoogleUtilities, swift-collections, swift-numerics, AppAuth-iOS, GoogleSignIn-iOS, swift-protobuf, and 17 others — **0 of 24 commit a `Package.resolved`**. Real SPM libraries do not ship one; it is conventionally gitignored for library packages.

So the isolated build does not inherit a stale pin — it has **no pin at all** and resolves each dependency **fresh from the manifest's open range**, i.e. to the newest release satisfying `from:`. That is strictly worse than "stale": it is *unbounded upward drift*, and it drifts differently on every machine and every day depending on what upstream published.

**VERIFIED (empirical, exact reproduction of the drift):** a package pinned at `swift-argument-parser 1.2.0` in its resolved file, against a manifest declaring `from: "1.3.0"`, silently resolved to **1.8.2** — the newest release — with no warning and exit 0.

Concretely for the reported release-config bug: the host graph pins `GoogleUtilities 7.x` (via firebase-ios-sdk's own constraints); the isolated build of `FirebaseCore` reads `.package(url: GoogleUtilities, from: "7.11.0")` and takes **8.x**. The cached `FirebaseCore.xcframework` is compiled and `.swiftinterface`-emitted against 8.x, while the app links 7.x. Debug often tolerates it; Release (library evolution, cross-module inlining, whole-module) does not.

**Second-order VERIFIED consequence:** `swift package describe` also runs inside the checkout — `BuildPipeline#resolve_scheme`, `#resolve_module_name`, `#resolve_forwarded_target`, `#find_private_clang_shims`, `#resolve_public_headers` each construct `Desc::Description.new(pkg_dir:)` and `.fetch` (`build_pipeline.rb:190, 271, 360, 389, 408`). `describe` resolves the manifest too. So **product/target metadata is currently read from the drifted graph as well**, not just the binary. Any fix must seed the resolved file *before the first `describe`*, not just before `xcodebuild`.

---

## 2. Approach Comparison — Empirically Adjudicated

All four candidate approaches were tested or structurally evaluated against this codebase.

| | Approach | Verdict | Decisive evidence |
|---|---|---|---|
| **(a)** | Write a `Package.resolved` into each checkout before building | ✅ **ADOPT — primary** | Verified honored by both `-resolvePackageDependencies` and a full `xcodebuild build`; tolerant of superset pins; indifferent to `originHash` |
| **(b)** | `-clonedSourcePackagesDirPath` shared across all package builds | ✅ **ADOPT — secondary** | Verified to preserve versions via `workspace-state.json` even with *no* resolved file; large cost win |
| **(c)** | Build products through the umbrella workspace/scheme | ❌ **REJECT** | Destroys three independently field-proven invariants (below) |
| **(d)** | `-onlyUsePackageVersionsFromResolvedFile` / SwiftPM mirrors | ❌ **REJECT as default**, keep as opt-in strict mode | Verified to **hard-fail** whenever any dependency is missing from the resolved file — which is guaranteed for any package with an external test-only dependency |

### 2.1 (a) — Seed `Package.resolved` into the checkout

**Where must the file land?** **VERIFIED: at the package root — `<pkg_dir>/Package.resolved`.**

`xcodebuild` invoked with `cwd = <bare package dir>` and `-scheme <product>` treats the directory as a root SPM package and reads the root-level resolved file. Not `.swiftpm/`, not a synthesized `.xcworkspace` path. Confirmed by a **full build**, not just a resolve:

```
# pkgF: Package.resolved hand-pinned to swift-argument-parser 1.5.0 (manifest says from: 1.3.0, latest is 1.8.2)
xcodebuild build -scheme spm-cache-proxy -destination 'generic/platform=macOS' -derivedDataPath DD_F CODE_SIGNING_ALLOWED=NO
# → ** BUILD SUCCEEDED **
git -C DD_F/SourcePackages/checkouts/swift-argument-parser describe --tags  →  1.5.0   ✅ (not 1.8.2)
```

This is exactly the invocation shape at `lib/spm_cache/spm/build.rb:98-108`, so the mechanism transfers verbatim.

**Does it need `-onlyUsePackageVersionsFromResolvedFile`? VERIFIED: NO — and it must NOT be used by default.** See §2.4.

**Four properties that make a near-verbatim copy safe** (all VERIFIED empirically):

| Property | Probe | Result |
|---|---|---|
| Satisfiable pins are honored | pin AP 1.5.0, manifest `from: 1.3.0` | resolved 1.5.0 ✅ |
| **Extraneous pins are tolerated** | added an unrelated `swift-collections` pin | AP still 1.5.0; extra pin silently pruned from the rewritten file; no full re-resolve ✅ |
| **Missing pins are filled in, others preserved** | deleted the `rainbow` pin | rainbow resolved fresh at 4.2.1, AP **stayed** at 1.5.0 ✅ |
| **`originHash` is irrelevant** | zeroed hash / removed hash / downgraded to `version: 2` format | all three honored the 1.5.0 pin ✅ |

The "extraneous pins tolerated" result is the big architectural simplification: **the umbrella's `Package.resolved` — a superset covering the entire host graph — can be copied byte-for-byte into every checkout.** No per-package filtering to the dependency closure, no hash recomputation, no manifest parsing.

**The one hazard — VERIFIED:** an *unsatisfiable* pin (below the manifest's floor) is **silently discarded and re-resolved to latest**, exit 0, no diagnostic. Seeding is therefore best-effort and requires a **post-build verification read-back** to be trustworthy. That read-back is also precisely the mechanism the milestone's second requirement ("regression coverage proving transitive-version drift cannot silently return") needs, so it is not extra work — it is the deliverable.

Conveniently, xcodebuild **rewrites `<pkg_dir>/Package.resolved` in place** with what it actually resolved (VERIFIED in every probe), so the read-back source is free.

### 2.2 (b) — Shared cloned-packages directory

**VERIFIED (structural):** `-clonedSourcePackagesDirPath` produces exactly `{artifacts, checkouts, repositories, workspace-state.json}` — the same layout as `DerivedData/*/SourcePackages/` and a subset of a SwiftPM `.build/`.

**VERIFIED (empirical), and stronger than expected:** a package with **no `Package.resolved` at all**, pointed at a pre-populated shared clone dir holding `swift-argument-parser @ 1.5.0`, resolved to **1.5.0, not 1.8.2** — SwiftPM reuses the existing working copy recorded in `workspace-state.json` rather than floating. So (b) alone is a *partial* fidelity mechanism.

Value of (b) is nonetheless mostly **cost**, not correctness: today every one of N package builds clones that package's entire dependency graph into its own `-derivedDataPath` tree. On a 59–70-package project that is a large, wholly redundant fetch/checkout cost. One shared dir collapses it.

**Critical constraint — do NOT point it at `{umbrella_dir}/.build`.** `BuildPipeline#locate_prebuilt_xcframework` (`lib/spm_cache/spm/build_pipeline.rb:873-882`) reads Class-E binaryTarget artifacts from `{umbrella}/.build/artifacts/...`, derived by walking up from `pkg_dir`. Letting xcodebuild write its own workspace state and `artifacts/` into that tree risks clobbering the exact directory the Class-E path depends on, and corrupts SwiftPM's umbrella state mid-run. Use a **dedicated sibling dir** instead.

**Residual hazard (ASSUMED):** shared mutable state — if package P's manifest floor exceeds the shared dir's checked-out version, SwiftPM upgrades the shared working copy, and a *later* package Q's build then sees the upgraded version. Combining (b) with (a) mitigates it (each build restates intent), and the drift read-back detects it if it happens.

### 2.3 (c) — Build through the umbrella — REJECT

Three separately field-proven invariants would be destroyed:

1. **Per-checkout DerivedData isolation.** `derived_data_dir_for` (`build_pipeline.rb:911-915`) exists because of a reproduced firebase-ios-sdk failure documented at `build_pipeline.rb:896-907`. Umbrella-level builds collapse that isolation.
2. **Library-evolution flags are per-invocation, not per-target.** `library_evolution_flags` (`build.rb:411-414`) sets `OTHER_SWIFT_FLAGS` + `BUILD_LIBRARY_FOR_DISTRIBUTION` for the whole invocation. The comment at `build_pipeline.rb:519-524` records a verified Zendesk failure — "Multiple commands produce …swiftmodule" — from exactly this multi-target-in-one-invocation shape. An umbrella build is that shape by construction, for every package at once.
3. **Vendored-`.xcodeproj` handling.** `project_disambiguation_flag` (`build.rb:123-129`), the SVGKit multi-project scheme scrape (`build_pipeline.rb:216-222`), and the `run_with_scheme` fallback (`build_pipeline.rb:126-181`) all operate on a single checkout's own project files. There is no umbrella-level equivalent.

This is a rewrite of the entire build layer to re-litigate ~12 documented field bugs. Reject.

### 2.4 (d) — Strict flags / mirrors — REJECT as default

**VERIFIED:** `xcodebuild -help` on Xcode 26.3 offers `-onlyUsePackageVersionsFromResolvedFile`, `-disableAutomaticPackageResolution` (documented identically), `-skipPackageUpdates`, and `-disablePackageRepositoryCache`.

**VERIFIED failure:** with one pin absent from the resolved file, `-onlyUsePackageVersionsFromResolvedFile` **fails the build**:

```
xcodebuild: error: Could not resolve package dependencies:
  an out-of-date resolved file was detected at .../Package.resolved, which is not allowed
  when automatic dependency resolution is disabled; ...
  Running resolver because the following dependencies were added: 'rainbow'
```

**Why that is guaranteed to bite — VERIFIED:** a package built standalone is a *root* package, so SwiftPM resolves its **entire** dependency list, including dependencies used only by `testTarget`s. Reproduced with a synthetic package whose `Rainbow` dependency is referenced *only* by its test target: building **only the `Lib` library scheme** still fetched and checked out Rainbow, and wrote it into `Package.resolved`.

The umbrella never pins those — SwiftPM skips test-only dependencies of *non-root* packages. So the seeded file is **systematically missing** every package's external test dependencies (Quick, Nimble, swift-testing, SwiftCheck…), and the flag would hard-fail those packages. This is the decisive argument.

Keep the flag available behind an opt-in strict/CI mode where a hard failure is preferable to silent drift, but never as the default.

SwiftPM **mirrors** (`swift package config set-mirror`) map a dependency *URL* to another URL; they do not pin versions and solve nothing here. `--force-resolved-versions` is a `swift build`/`swift package` flag — spm-cache builds via `xcodebuild`, whose equivalent is the flag above. Reject.

---

## 3. Recommended Architecture

**Direction: (a) as the correctness mechanism + (b) as the cost mechanism + a read-back drift gate as the proof.**

### 3.1 System Overview

```
┌──────────────────────────────────────────────────────────────────────────┐
│  Installer#perform_install  (installer.rb:31-44)          [UNCHANGED]    │
│    recreate_dirs → sync_lockfile → prepare_proxy                         │
│                                     │                                    │
│                                     ├─ gen-umbrella (Swift)              │
│                                     ├─ resolve_umbrella_checkouts ───────┼──┐
│                                     ├─ enrich_lockfile_products          │  │
│                                     └─ gen-proxy (Swift)                 │  │
└──────────────────────────────────────────────────────────────────────────┘  │
                                                                              │
        ┌─────────────────────────────────────────────────────────────────────┘
        │  writes {umbrella_dir}/Package.resolved  (SwiftPM, VERIFIED convention)
        ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                    Core::PackageResolved            ★ NEW                │
│   locate(project_path)  — one home for the 5 duplicated globs            │
├──────────────────────────────────────────────────────────────────────────┤
│                    SPM::ResolvedGraph               ★ NEW                │
│   source_for(umbrella_dir:, project_path:)  → best available pin source  │
│   pins(path)          → { identity => {location, version, revision} }    │
│   seed!(source, into: pkg_dir)  → writes <pkg_dir>/Package.resolved      │
│   drift(expected:, pkg_dir:)    → [{identity, expected, actual}]         │
│   (pure filesystem + JSON — ZERO shell-out, ZERO network)                │
└───────────────────────────┬──────────────────────────────────────────────┘
                            │ resolved_pins_file: (new kwarg)
                            ▼
┌──────────────────────────────────────────────────────────────────────────┐
│  Installer::Build#perform_install / #build_single_target   [MODIFIED]    │
│    checkout_map → pin source → BuildPipeline.run(resolved_pins_file:)   │
└───────────────────────────┬──────────────────────────────────────────────┘
                            ▼
┌──────────────────────────────────────────────────────────────────────────┐
│  SPM::BuildPipeline.run                                   [MODIFIED]    │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │ ① SEED  — ResolvedGraph.seed! BEFORE the first `swift package       │ │
│  │           describe`  (must precede build_pipeline.rb:47)            │ │
│  │ ② describe / scheme / module / shim resolution      [unchanged]     │ │
│  │ ③ per-destination xcodebuild via Buildable          [flag added]    │ │
│  │ ④ VERIFY — re-read <pkg_dir>/Package.resolved, diff vs expected     │ │
│  │ ⑤ xcframework assembly                              [unchanged]     │ │
│  │ ⑥ write <Name>.xcframework.resolved.json sidecar    ★ NEW           │ │
│  └────────────────────────────────────────────────────────────────────┘ │
└───────────────────────────┬──────────────────────────────────────────────┘
                            ▼
┌──────────────────────────────────────────────────────────────────────────┐
│  SPM::Buildable#build_command                             [MODIFIED]    │
│    + " -clonedSourcePackagesDirPath '<clones_dir>'"  when supplied       │
│    → {sandbox}/packages/clones   (NOT {umbrella}/.build — see §2.2)      │
└──────────────────────────────────────────────────────────────────────────┘
```

### 3.2 Component Inventory — NEW vs MODIFIED

**★ NEW files**

| File | Responsibility | Shells out? |
|---|---|---|
| `lib/spm_cache/core/package_resolved.rb` | Single locator for the host project's `Package.resolved`; parse pins to a normalized hash | No |
| `lib/spm_cache/spm/resolved_graph.rb` | Choose pin source (umbrella → host), seed a checkout, read back, diff | No |
| `spec/resolved_graph_spec.rb` | Pure-filesystem unit coverage | No |
| `spec/build_fidelity_regression_spec.rb` | The milestone's anti-regression gate (§7) | No |

**MODIFIED files**

| File:line | Change | Why |
|---|---|---|
| `lib/spm_cache/spm/build_pipeline.rb:33` | Add `resolved_pins_file: nil`, `clones_dir: nil` keywords; **default nil ⇒ today's behavior byte-for-byte** | Keeps `Command::Pkg::Build` and every existing spec working unchanged |
| `lib/spm_cache/spm/build_pipeline.rb:36-47` | Insert seed step between `mkdir_p(out_dir)` and `resolve_forwarded_target` | `describe` resolves too (§1); seeding after it would leave metadata read from the drifted graph |
| `lib/spm_cache/spm/build_pipeline.rb:57-64` and `:129-136` | Pass `clones_dir:` into both `Buildable.new` sites | `run_with_scheme` is the path vendored-`.xcodeproj` packages actually take (`build_pipeline.rb:160-162`) — it must not be a fidelity hole |
| `lib/spm_cache/spm/build_pipeline.rb:110-121` | After `xcframework.build`, emit `<output>.resolved.json` alongside the existing `.shims.json` write (`:119`) | Reuses the established sidecar convention |
| `lib/spm_cache/spm/build_pipeline.rb:857` | `rm_f` the new sidecar in `copy_prebuilt_binary_target` too | Same stale-sidecar bug already documented at `:850-857` for `.shims.json` |
| `lib/spm_cache/spm/build.rb:48-57` | `Buildable#initialize` accepts `clones_dir:` | — |
| `lib/spm_cache/spm/build.rb:98-108` | `build_command` appends `-clonedSourcePackagesDirPath` when set | Pure string assembly ⇒ unit-testable, mirrors the existing quoting fix at `:98-97` |
| `lib/spm_cache/installer/build.rb:37` | After `checkout_map`, resolve the pin source once per run | One filesystem read for N targets |
| `lib/spm_cache/installer/build.rb:119-134` | Thread `resolved_pins_file:` / `clones_dir:` into `BuildPipeline.run` | The integration point named in the milestone |
| `lib/spm_cache/installer/build.rb:25` | Extend the existing hit→missed promotion with a pin-staleness check | §6 — the only existing hook that already demotes a "hit" |
| `lib/spm_cache/core/config.rb:76` | Add `clones_dir` next to `proxy_dir`/`umbrella_dir` | Path ownership already lives here |
| `lib/spm_cache/command/cache/clean.rb:41-49` | Sweep `<target>.*` sidecars, not just the bare path | Pre-existing gap; the new sidecar makes it load-bearing |

**Explicitly NOT modified**

- `lib/spm_cache/spm/checkout_resolver.rb` — no change needed. It already materializes checkouts and the umbrella already pins by exact `revision:` (`tools/spm-cache-proxy/Sources/Core/Lockfile.swift:118-127`), so `{umbrella_dir}/Package.resolved` is already host-faithful the moment it exists. The fix is downstream of it.
- The Swift companion (`UmbrellaGenerator`, `ProxyGenerator`, `BinariesCache`) — the recommended design is **Ruby-only**. Avoiding a cross-language change removes the Ruby↔Swift version-drift risk that `doctor` exists to surface, and keeps the milestone shippable without a companion-binary release.
- `lib/spm_cache/installer.rb` — untouched by the fidelity work (see §5 for a *separate* pre-existing defect found there).

### 3.3 Where the resolved graph lives in-process, and how it reaches the call site

There is currently **no in-process representation of the resolved graph at build time**. `@lockfile` is the closest thing and it is unsuitable as the pin source (§5). The recommendation is to keep the graph **on disk, as a file path**, and pass the *path* — not a parsed structure — down to `BuildPipeline`.

Rationale: (a)'s mechanism is literally "put this file there", so a path is the natural currency; a path is trivially stubbed in specs; and it keeps `BuildPipeline`'s signature additive rather than introducing a new domain object across a module boundary.

Source precedence, evaluated once per run in `Installer::Build#perform_install`:

1. **`{umbrella_dir}/Package.resolved`** — written by `swift package resolve` at `checkout_resolver.rb:24`. Highest fidelity: it is *the* graph the checkouts on disk were materialized from, and the umbrella pins by exact revision. **ASSUMED** that SwiftPM writes it at the package root for the umbrella — this is SwiftPM's universal convention and is VERIFIED for `tools/spm-cache-proxy/Package.resolved` on disk. A one-line existence check makes this self-correcting either way.
2. **The host project's own `Package.resolved`** — located exactly as `Core::DiffDetector#find_package_resolved` does today (`lib/spm_cache/core/diff_detector.rb:150-155`). This is the authoritative host graph and, crucially, is the *correct* source under the DerivedData fallback (§4).
3. **Nothing found** → warn once and behave exactly as today. No new failure mode.

Both sources are already `Package.resolved` v3 JSON, so step (1)/(2) is a `FileUtils.cp` with an optional `originHash` strip. No synthesis needed (§2.1).

**DRY opportunity worth folding in:** the same `Package.resolved` glob is duplicated **five times** — `installer.rb:169`, `diff_detector.rb:150-155`, `core/watcher.rb:118`, `command/init.rb:196`, `command/use.rb:83`. `Core::PackageResolved.locate(project_path)` collapses all five. Low risk, hermetic, and it makes the new pin source share a code path with the change detector that must agree with it.

### 3.4 Data flow

**Before (VERIFIED):**

```
host Package.resolved ─→ spm-cache.lock ─→ umbrella Package.swift (revision-pinned)
                                                    │
                                       swift package resolve
                                                    ▼
                                    {umbrella}/.build/checkouts/<slug>
                                                    │
                                          checkout_map[target]
                                                    ▼
                                    BuildPipeline.run(pkg_dir:)     ✗ graph ends here
                                                    │
                                   describe + xcodebuild, cwd=checkout
                                                    ▼
                            ✗ FRESH resolution from manifest ranges → newest releases
                                                    ▼
                              ~/.spm-cache/<config>/<Name>.xcframework   (name-keyed only)
```

**After:**

```
host Package.resolved ──┬──────────────────────────────────────────────┐
                        │                                              │
                        ▼                                              │
              spm-cache.lock ─→ umbrella Package.swift                 │
                                          │                            │
                             swift package resolve                     │
                                          ├──→ {umbrella}/Package.resolved  ◄── preferred
                                          ▼                            │        pin source
                        {umbrella}/.build/checkouts/<slug>             │
                                          │              ┌─────────────┘ fallback source
                                          │              │  (and the ONLY source under
                                          │              │   the DerivedData fallback)
                                          ▼              ▼
                        BuildPipeline.run(pkg_dir:, resolved_pins_file:, clones_dir:)
                                          │
                        ① cp → <pkg_dir>/Package.resolved       ★ fidelity
                        ② describe (now sees the host graph)
                        ③ xcodebuild -clonedSourcePackagesDirPath {sandbox}/packages/clones
                        ④ read back <pkg_dir>/Package.resolved → diff vs expected
                                          ▼
                        ~/.spm-cache/<config>/<Name>.xcframework
                        ~/.spm-cache/<config>/<Name>.xcframework.resolved.json   ★ NEW
```

**New component boundaries introduced:** exactly one — `ResolvedGraph` owns "what versions should this checkout build against, and did it comply?". `BuildPipeline` keeps owning "how do I turn a checkout into an xcframework". `Installer::Build` keeps owning "which targets, from where, into where". No responsibility is moved between existing components; one is added beneath them.

---

## 4. Interaction with the DerivedData Fallback

**Does fidelity hold on the `fallback_xcode_checkouts` path? YES — arguably better than on the happy path.**

**VERIFIED (repo):** `fallback_xcode_checkouts` (`lib/spm_cache/spm/checkout_resolver.rb:49-68`) copies from `DerivedData/<Project>-<hash>/SourcePackages/checkouts` into `{umbrella}/.build/checkouts`. It fires when `swift package resolve` on the umbrella raised (`checkout_resolver.rb:26-34`).

Consequences for the design:

1. **No `{umbrella_dir}/Package.resolved` exists** in that path (resolve failed). Source precedence therefore falls to the host project's `Package.resolved` — which is *exactly right*, because those checkouts came from **Xcode's own resolution of that same file**. Source and checkouts are consistent by construction. Fidelity is arguably tighter than on the umbrella path, where the umbrella's independent resolve could in principle differ from Xcode's.
2. **No filtering or special-casing is required.** The superset tolerance verified in §2.1 means the same host file is copyable into every fallback checkout unmodified.
3. **The read-back gate stays meaningful.** If a fallback checkout's manifest floor exceeds a host pin, the silent-upgrade behavior (§2.1) fires and the drift diff catches it.
4. **One caveat, already documented in-repo:** the fallback copies only `SourcePackages/checkouts`, **not** `SourcePackages/artifacts` — noted at `lib/spm_cache/installer.rb:311-320` (the `eh_xcframework` case). So Class-E binaryTarget copying (`build_pipeline.rb:873-882`) is already degraded there. The fidelity work neither improves nor worsens this; do not conflate the two.
5. **`-clonedSourcePackagesDirPath` is orthogonal** here — a fresh shared clone dir works identically whichever way the checkouts were materialized.

**Net:** one source-precedence rule covers both paths. No branch in `checkout_resolver.rb`.

---

## 5. Cache-Key and Lockfile Implications

### 5.1 The cache key today has no version component at all — VERIFIED

`BinariesCache.hit(module:)` (`tools/spm-cache-proxy/Sources/Core/Cache.swift:19-22`) is:

```swift
let xcframework = dir.appendingPathComponent("\(module).xcframework")
return FileManager.default.fileExists(atPath: xcframework.path) ? xcframework : nil
```

Pure name + existence. `ProxyGenerator.swift` references no version or revision in any cache path. So:

- a **direct** version bump (Alamofire 5.8 → 5.9) does **not** invalidate the cached artifact;
- a **transitive** version change certainly does not — the dependent module's *name* never changes.

`Installer::Build` currently overwrites on rebuild, and `SPM::Package::Proxy#invalidate_cache` (`lib/spm_cache/spm/pkg/proxy.rb:68-71`) wipes only `proxy_dir`, never the binary cache. **The binary cache is invalidated only by explicit `cache clean`.**

### 5.2 Does `spm-cache.lock` need to record transitive versions?

**It already does — and that is not the problem.** `generate_lockfile_from_resolved` (`lib/spm_cache/installer.rb:164-193`) maps **every pin** in the host's `Package.resolved`, and Xcode's resolved file is the full transitive closure. Transitive versions are already in the lock.

**The real gap is that nothing compares them to what an artifact was built with.** Recommended minimal mechanism (deliberately *not* content-addressing, which PROJECT.md defers to v0.5):

- Write `~/.spm-cache/<config>/<Name>.xcframework.resolved.json` — the pins **actually resolved** (read back post-build, not the intended ones).
- Demote stale hits in `Installer::Build#perform_install` at the **existing** hook, `lib/spm_cache/installer/build.rb:25`:

```ruby
missed.concat(@cachemap.hit.select { |m| !slice_complete?(cache_out, m, destinations) })
missed.concat(@cachemap.hit.select { |m| !pins_current?(cache_out, m, host_pins) })   # ★ NEW
```

`slice_complete?` (`installer/build.rb:51-56`) is the exact precedent: a graph-declared "hit" already gets promoted back to "missed" on a Ruby-side integrity check. This keeps the change Ruby-only and adds no Swift work.

**Known limitation to flag for the roadmap:** `gen-proxy` runs *before* this demotion (`Installer#perform_install` → `prepare_proxy`, `installer.rb:38`), so the generated proxy manifest still declares a `binaryTarget` for a pin-stale artifact. `spm-cache build` then rebuilds and overwrites it at the same path, so the *manifest* stays correct — but a bare `spm-cache use` with no subsequent build would still serve the stale binary for one cycle. This is identical to today's slice-incompleteness behavior and is an acceptable v0.4.0 scope line; closing it fully means moving hit/miss adjudication into the Swift `BinariesCache`, which is v0.5 content-addressing territory.

**Comparison granularity (recommendation):** compare only the **intersection** of the sidecar's recorded pins with the current host pins, keyed by identity, on `revision` (falling back to `version`). Unrelated churn elsewhere in a 70-package graph must not invalidate every artifact — that would make the cache useless on the first dependency bump.

### 5.3 Pre-existing defect found while tracing the pin source — report, do not silently fix

**VERIFIED:** `generate_lockfile_from_resolved` early-returns when the lockfile already exists (`lib/spm_cache/installer.rb:165-166`). `Core::DiffDetector` reads but never writes (`diff_detector.rb:90-113`). Grepping every `lockfile_path` and `@lockfile.save` site shows the only writers are `refresh_consumed_dependencies` (`installer.rb:161`) and `enrich_lockfile_products` (`installer.rb:291`) — neither of which touches `version`/`revision`.

**Therefore package versions in `spm-cache.lock` are written once, on first run, and never refreshed** — even though `DiffDetector` correctly *detects* the change and forces a full regeneration, which then re-runs the early-returning generator. Since `UmbrellaGenerator` pins from the lockfile, the umbrella can be pinned to the *previous* graph.

**Implication for this design:** do **not** use `@lockfile` as the pin source. Both recommended sources (`{umbrella_dir}/Package.resolved`, host `Package.resolved`) sidestep it. This defect is a **separate finding** — it plausibly contributes to the same field symptom and deserves its own roadmap line item, but conflating it with the transitive-resolution fix would muddy both.

---

## 6. Testability Against the Existing `Core::Sh` Seam

The design was shaped so that **almost none of it needs the shell seam at all**.

**VERIFIED existing seam quality:**
- `Core::Sh.run` / `.capture_output` are the sole shell-out points (`lib/spm_cache/core/sh.rb`), and specs stub them directly — e.g. `spec/buildable_spec.rb:313, 329, 341, 350, 375, 414`.
- `Buildable#build_command` is unit-tested as a **pure string builder** with no stubbing at all (`spec/buildable_spec.rb:194-205, 391-404`).
- `spec/build_pipeline_spec.rb:17-32` stubs `Desc::Description` (`.fetch`, `.products`, `.raw`) and `:41-66` stubs a name-aware `Buildable.new` factory — the full pipeline runs with **zero** xcodebuild and zero network.
- `spec/installer_build_spec.rb:17-28` stubs `perform_install`, `resolve_umbrella_checkouts`, `checkout_map`, and `build_single_target`, isolating selection logic.

Mapping each new behavior to an existing seam:

| Behavior | How it is spec'd | Seam |
|---|---|---|
| Pin source precedence | `Dir.mktmpdir`; create/omit `{umbrella}/Package.resolved` and a host one; assert which path is chosen | None needed — pure FS |
| Verbatim seeding + superset tolerance | Write a superset resolved file, call `seed!`, assert `<pkg_dir>/Package.resolved` content | None needed — pure FS |
| Seeding happens **before** `describe` | `expect(SPMCache::SPM::Desc::Description).to receive(:new) { expect(File.exist?(File.join(pkg_dir,"Package.resolved"))).to be true; fake_desc }` | Existing `Desc` stub, `build_pipeline_spec.rb:17` |
| `-clonedSourcePackagesDirPath` in the command | Direct `build_command` string assertion | Existing pure-function pattern, `buildable_spec.rb:194` |
| Flag reaches the real invocation | `allow(Core::Sh).to receive(:run) { |cmd| captured = cmd }`, then assert | Existing `Sh` stub, `buildable_spec.rb:313` |
| Both `run` **and** `run_with_scheme` seed and flag | Force the fallback by making `framework_paths` empty (already exercised in `build_pipeline_spec.rb`) | Existing |
| Drift detection | Hand-write a "post-build" `Package.resolved` in the fake `pkg_dir` with a floated version; assert the diff | None needed — pure FS |
| Sidecar written / stale sidecar removed | Assert `<out>/<Name>.xcframework.resolved.json` exists; assert `copy_prebuilt_binary_target` removes it | Existing tmpdir pattern |
| Hit demotion on stale pins | Extend `spec/installer_build_spec.rb`'s stubbed-cachemap harness with a sidecar file | Existing |
| Backward compatibility | Assert `resolved_pins_file: nil` produces a byte-identical `build_command` and writes no file | Existing |

**The one thing that genuinely cannot be hermetically tested** is that xcodebuild honors the seeded file — which is why it was verified empirically here (§2.1) rather than deferred to a spec. Record the probe result as the evidence and do **not** attempt to bolt a networked integration test onto CI; that would be flaky, slow, and would break the "no real network/xcodebuild" property the suite currently holds (258 examples, CI-green).

**Regression gate for the milestone's second requirement** (`spec/build_fidelity_regression_spec.rb`): construct a fake checkout whose *post-build* `Package.resolved` shows a floated transitive version, run the pipeline with stubbed `Desc`/`Buildable`, and assert (i) the drift is detected, (ii) it is reported, not swallowed, and (iii) the emitted sidecar records the drifted pin — so a future regression that drops the seeding step fails the suite rather than shipping a stale binary.

---

## 7. Suggested Build Order

Dependencies are real; the ordering below front-loads everything that is pure and hermetic.

| # | Phase | Depends on | Deliverable | Risk |
|---|---|---|---|---|
| **1** | **Resolved-graph foundation** | — | `Core::PackageResolved` (collapse the 5 duplicate globs) + `SPM::ResolvedGraph` (`source_for` / `pins` / `seed!` / `drift`). No call-site wiring. Pure FS specs. | LOW |
| **2** | **Seed the checkout (the fix)** | 1 | New `resolved_pins_file:` kwarg on `BuildPipeline.run`, seeding **before** `resolve_forwarded_target` (`build_pipeline.rb:47`); wire `Installer::Build` (`installer/build.rb:37, 128-134`). Default-nil ⇒ behavior-preserving. **This alone closes the milestone's primary requirement.** | MED |
| **3** | **Drift read-back + sidecar** | 2 | Post-build re-read + diff; warn (or fail under `ignore_build_errors? == false`); emit `<Name>.xcframework.resolved.json`; `rm_f` it in `copy_prebuilt_binary_target` (`build_pipeline.rb:857`). | LOW |
| **4** | **Regression coverage** | 2, 3 | `spec/build_fidelity_regression_spec.rb` — the milestone's second requirement. | LOW |
| **5** | **Shared clone dir** | 2 (loosely) | `Config#clones_dir`, `Buildable` flag, plumb through **both** `run` and `run_with_scheme`. Cost win + fidelity reinforcement. **Parallelizable with 3–4.** | MED |
| **6** | **Pin-staleness hit demotion** | 3 | `pins_current?` alongside `slice_complete?` (`installer/build.rb:25, 51-56`); extend `cache clean` sidecar sweep. | MED |
| **7** | **Release automation** | — | §8. **Fully independent — schedulable first, last, or in parallel.** | LOW |

Deliberately **out** of this milestone, recorded as follow-ups:
- Lockfile version-refresh defect (§5.3) — separate root cause, separate fix, separate verification.
- Moving hit/miss adjudication into Swift `BinariesCache` — v0.5 content-addressing.
- Strict mode (`-onlyUsePackageVersionsFromResolvedFile` behind a flag) — only worth it once §5's sidecar makes "complete pins" a checkable property.

---

## 8. Release Automation — Removing the Human-PAT SPOF

**VERIFIED from `.github/workflows/update-tap.yml`:** the cross-repo checkout at lines 25-31 uses `token: ${{ secrets.TAP_REPO_TOKEN }}`. A classic/fine-grained PAT is bound to a human account, carries an expiry, and dies on rotation, 2FA reset, or offboarding — the observed failure.

| Option | SPOF removed? | Setup cost | Notes |
|---|---|---|---|
| **1. GitHub App installation token** ⭐ | **Yes** | Medium (one-time) | App owned by `phuongddx`, `Contents: read & write`, installed **only** on `homebrew-spm-cache`. Store `TAP_APP_ID` + `TAP_APP_PRIVATE_KEY`; mint per-run with `actions/create-github-app-token`. Token lives ~1 h, no expiry to babysit, not tied to a person, independently rotatable, distinctly auditable. Drops straight into `actions/checkout`'s `token:` — **no other workflow change needed**. |
| **2. Tap-side scheduled pull** | **Yes — zero cross-repo secret** | Low | Move the logic into the tap repo on `schedule` + `workflow_dispatch`; read the **public** releases API; commit with the built-in `GITHUB_TOKEN` (write access to its own repo). No secret exists to expire. Cost: cron latency, and the logic leaves this repo. Excellent **reconciliation safety net** even if not primary. |
| **3. `repository_dispatch` fan-out** | Partially | Medium | Logic lives beside the formula, but *sending* the dispatch still needs `Contents: write` on the tap — same credential class as option 1, so no standalone security win. Best used **with** option 1. |
| **4. Write-enabled deploy key** | **Yes** | **Lowest** | Keypair; public half as a write deploy key on the tap; private half as a secret here; `actions/checkout` with `ssh-key:`. Repo-scoped, no user, no expiry. Weaker audit identity and manual rotation. Solid pragmatic choice if a GitHub App is more ceremony than wanted. |
| **5. Fine-grained PAT on a machine account** | No | Low | Still an account with an expiry — reproduces the current failure on a slower clock. Reject. |

**Recommendation:** **Option 1** primary; **Option 4** as the lower-ceremony substitute; **Option 2** optionally as a belt-and-braces reconciler.

### Hardening worth folding into the same phase (all VERIFIED from the workflow text)

1. **`update-tap.yml:50` — `git commit -m "…" || exit 0`** treats *every* commit failure as success. A hook failure, a bad identity, an unwritable index all exit 0 and the release looks published. Replace with an explicit `git diff --quiet && exit 0` no-op check, so genuine failures fail.
2. **`update-tap.yml:38-40` — unanchored `sed` patterns.** `sha256 ".*"` and `version ".*"` rewrite **every** matching line in the formula. The moment the formula grows a second `sha256` (bottle block, resource stanza) the rewrite corrupts it silently. Generate the formula from a checked-in template, or anchor per-stanza.
3. **`update-tap.yml:3-5` — trigger is `release: [published]` only.** With no `workflow_dispatch`, a transient token/network failure can only be retried by re-publishing a release. Add `workflow_dispatch` with a `tag` input.
4. **No `permissions:` block** — add least-privilege `permissions: { contents: read }` at the job level; the cross-repo write comes from the app/deploy-key credential, not `GITHUB_TOKEN`.
5. **No post-publish verification.** Add a `macos-latest` job running `brew audit --strict --formula ./Formula/spm-cache.rb` and ideally `brew install --build-from-source` before the push. Without it, "publishes unattended" can mean "publishes something broken, unattended".

---

## 9. Anti-Patterns to Avoid in This Milestone

**Rebuilding the resolved file instead of copying it.** Synthesizing pins from `spm-cache.lock` invites the staleness defect of §5.3 and the format churn of `originHash`/`version: 3`. Verified: a verbatim copy of a superset file works, extra pins are pruned, the hash is ignored. Copy the file.

**Filtering pins to each package's dependency closure.** It requires manifest parsing per package, and §2.1 proves it buys nothing.

**Adding `-onlyUsePackageVersionsFromResolvedFile` "for safety".** Verified to hard-fail on any missing pin, and the umbrella *systematically* omits every package's test-only dependencies. It converts a silent-drift bug into a loud build-breakage for a large class of packages.

**Pointing `-clonedSourcePackagesDirPath` at `{umbrella}/.build`.** Layout-compatible and superficially tempting, but it is the directory `locate_prebuilt_xcframework` (`build_pipeline.rb:873-882`) reads Class-E artifacts from, and it is SwiftPM's live umbrella state.

**Seeding after `swift package describe`.** `describe` resolves too (§1). Product/target metadata would still be read from the drifted graph, so scheme and module resolution stay wrong even though the binary becomes right — a subtler bug than the one being fixed.

**Fixing only `BuildPipeline.run` and forgetting `run_with_scheme`.** The fallback at `build_pipeline.rb:126-181` is the path vendored-`.xcodeproj` packages actually take — explicitly documented at `:160-162`. Two `Buildable.new` sites, two seedings.

**Trusting the seed without reading back.** Verified: an unsatisfiable pin is discarded and re-resolved to latest, exit 0, silently. Without the read-back, the milestone's second requirement ("drift cannot silently return") is unmet by construction.

**Making the cache key too strict.** Invalidating an artifact whenever *any* pin anywhere in a 70-package graph moves makes the cache worthless after the first bump. Intersect on identity; compare only pins the artifact actually recorded.

---

## 10. Open Questions

1. **Does `swift package resolve` on the umbrella emit `{umbrella_dir}/Package.resolved` in every failure/partial mode?** VERIFIED as SwiftPM's universal convention and VERIFIED present for `tools/spm-cache-proxy`; not exercised against a *failing-then-retried* umbrella (`installer.rb:240-243`). The existence check makes it self-correcting, but a one-line field probe on the real 59–70-package project would settle it.
2. **On drift detection: warn or fail?** `@config.ignore_build_errors?` (`installer/build.rb:137`) is the obvious existing lever, but drift is a *correctness* signal, not a build failure — a user with `ignore_build_errors: true` arguably still wants to hear about it. Needs a product decision.
3. **How much does the shared clone dir actually save?** Unmeasured. If the SwiftPM `repositories` cache already makes per-build clones cheap, phase 5 may be low-value and safely deferrable.
4. **Does any real package in the field carry a committed `Package.resolved` at its resolved tag?** 0 of 24 here, but the sample is this machine's cache. If one does, the seed **overwrites** a file the package tracks in git — harmless within a run (the sandbox is wiped by `recreate_dirs`, `installer.rb:107-114`) but worth confirming it never confuses a later `git status` check.
5. **Interaction with `spm-cache watch`.** A watch-triggered `Installer::Use` regenerates the umbrella and its resolved file; a concurrent `spm-cache build` reading the same path mid-rewrite is a narrow race. Probably theoretical, unverified.

---

## 11. Sources

**Primary — this repository (VERIFIED by reading):**
`lib/spm_cache/spm/build_pipeline.rb` · `lib/spm_cache/spm/build.rb` · `lib/spm_cache/spm/checkout_resolver.rb` · `lib/spm_cache/installer/build.rb` · `lib/spm_cache/installer.rb` · `lib/spm_cache/installer/use.rb` · `lib/spm_cache/core/lockfile.rb` · `lib/spm_cache/core/diff_detector.rb` · `lib/spm_cache/core/config.rb` · `lib/spm_cache/core/sh.rb` · `lib/spm_cache/spm/pkg/proxy.rb` · `lib/spm_cache/storage/git.rb` · `lib/spm_cache/command/cache/clean.rb` · `tools/spm-cache-proxy/Sources/Core/Cache.swift` · `tools/spm-cache-proxy/Sources/Core/Lockfile.swift` · `tools/spm-cache-proxy/Sources/Core/Generator/UmbrellaGenerator.swift` · `.github/workflows/update-tap.yml` · `spec/buildable_spec.rb` · `spec/build_pipeline_spec.rb` · `spec/installer_build_spec.rb` · `.planning/codebase/ARCHITECTURE.md` · `.planning/PROJECT.md`

**Primary — empirical probes on this machine (VERIFIED by execution), Xcode 26.3 / Swift 6.2.4:**
`xcodebuild -help` flag inventory · resolved-file honoring under `-resolvePackageDependencies` and full `xcodebuild build` · superset-pin tolerance · missing-pin fill-in · `originHash` / format-version indifference · unsatisfiable-pin silent upgrade · `-onlyUsePackageVersionsFromResolvedFile` hard failure · shared-clone-dir version preservation via `workspace-state.json` · test-only dependency resolution when building a library-only scheme · committed-`Package.resolved` survey across 24 cached upstream packages

**Secondary (MEDIUM confidence, vendor-documented, not exercised here):**
GitHub App installation tokens for cross-repository Actions writes · repository deploy keys · `repository_dispatch` · Homebrew tap formula publishing conventions

---
*Architecture research for: spm-cache v0.4.0 — build fidelity + release automation*
*Researched: 2026-08-27*
