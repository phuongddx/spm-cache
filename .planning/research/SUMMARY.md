# Project Research Summary

**Project:** spm-cache
**Milestone:** v0.4.0 — Build Fidelity & Release Automation
**Domain:** SwiftPM/xcodebuild binary-dependency caching (Ruby CLI + Swift companion, macOS-only) + cross-repo GitHub Actions release automation
**Researched:** 2026-08-27
**Confidence:** HIGH (build fidelity — empirically reproduced on Xcode 26.3 / Swift 6.2.4 by three independent researchers plus orchestrator source-verification) / MEDIUM (release automation — vendor-documented, not exercised end-to-end)

## Executive Summary

spm-cache builds each cached package **in isolation**, as a root SwiftPM package, with no representation of the consuming app's resolved dependency graph anywhere in the build call chain. The symptom the milestone exists to close — a cached `ExyteChat.xcframework` compiled against MediaPicker 3.2.4 while the host app resolves 3.3.2 — is not one bug but **two independent drift mechanisms feeding the same failure**, and the dominant one is not the one the milestone originally hypothesized. The original hypothesis ("the isolated build resolves from the package's own committed `Package.resolved`") is **falsified**: `exyte/Chat` commits no such file (HTTP 404 at both canonical paths, probed 2026-08-27), and 0 of 24 surveyed upstream packages commit one either. The real dominant cause is a **never-refreshed lockfile**: `installer.rb:165-166` early-returns whenever `spm-cache.lock` exists, so every package's `version`/`revision` is frozen at first-run forever; the umbrella is generated from that lockfile (`installer.rb:241`), `Lockfile.swift:118-126` converts a held revision into an exact `revision:` pin, `UmbrellaGenerator.swift:73` emits it, and `swift package resolve` materializes checkouts at that stale commit. That chain — and only that chain — explains a **downward** pin to an older version, which pure fresh-upward drift cannot.

The recommended approach is deliberately unglamorous and Ruby-side: **refresh the lockfile so the graph is current, seed the host's `Package.resolved` verbatim into every checkout before the first `swift package describe`, read back what was actually realized, and invalidate cached artifacts whose recorded provenance no longer matches the host graph.** Empirical probing established that a superset resolved file is honored verbatim (extra pins pruned, missing pins filled in, `originHash` ignored), which removes the need for per-package filtering, format synthesis, or manifest parsing. The competitive landscape corroborates the shape: xccache and XCRemoteCache both achieve fidelity *structurally*, and Rugby and XCRemoteCache both propagate transitive changes into cache keys — while **neither SPM-native competitor invalidates on transitive drift**, making that the highest-leverage differentiator available here.

The two dominant risks are both about the fix being invisible or actively worse. First, `Cache.swift`'s `hit(module:)` is a bare name + file-existence check against a **global** `~/.spm-cache`, so without an invalidation mechanism a perfectly correct fix reaches **zero existing users** and cross-project poisoning persists. Second, seeding without verification converts "wrong version, deterministically" into "wrong version, silently, with the injected file overwritten" — xcodebuild silently discards an out-of-range pin, rewrites the file, and reports `BUILD SUCCEEDED`. The mitigation for both is the same artifact: a **post-resolve read-back compared against separately-retained intended pins**, emitted as a provenance sidecar that doubles as the cache-invalidation key. Policy on violation is settled: **warn and fall back to source compilation, never hard-fail** — consistent with the project's Core Value and with all four comparable tools, none of which aborts a build on inconsistency.

## Key Findings

### ⚠ SUPERSEDED BY FIELD MEASUREMENT (M1, 2026-08-27)

**The ranking below is FALSIFIED.** Phase 6's M1 measurement scored **H-wrongfile 25 · H-lock 0 · H-float 0**.
Surface #1 ("never-refreshed lockfile") was ranked DOMINANT here and is now excluded by provenance: the
reference project's lock holds AnchoredPopup `1.1.3/2fb9d1ac101b`, a value that appears in **none** of the
9 committed revisions of the canonical `Package.resolved` — so the lock is not a frozen read of the host
graph at all. It is a *faithful* read of the WRONG file. The locator (`Dir.glob(...).find`) selects a stale
git-ignored nested copy (8 pins, 2026-07-12) over the canonical file (17 pins, 2026-08-13). Surface #2
(fresh upward re-resolution) was observed **zero** times in the field — all 8 packages are emitted as exact
`revision:` pins, leaving no range to float within.

**Corrected ranking:** (1) stale-locator selection [FID-06] — DOMINANT, sole field cause;
(2) never-refreshed lockfile [FID-01] — real mechanism, hardening, and *actively harmful without FID-06*
(reconciling from the wrong file writes the phantom graph back onto itself, converting a visible diff into
a false green); (3) fresh upward re-resolution [Phase 7] — real in isolation, unobserved in the field.

See `.planning/phases/06-graph-authority-lockfile-reconciliation/06-M1-MEASUREMENT.md`.

### The Root-Cause Model (as originally researched — see the correction above before relying on this ranking)

Contributing surfaces, **ranked by dominance**:

| # | Surface | Direction | Evidence | Dominance |
|---|---------|-----------|----------|-----------|
| **1** | **Never-refreshed lockfile → revision-pinned umbrella → stale checkouts** | **Downward** (older than host) | Fully source-verified 5-link chain: `installer.rb:165-166` early return → `installer.rb:241` `gen_umbrella --lockfile` → `Lockfile.swift:118-126` `revision:` pin → `UmbrellaGenerator.swift:73` emission → `swift package resolve` materializes | **DOMINANT.** The only mechanism that explains the motivating downward drift. `DiffDetector` correctly *detects* the change and forces regeneration, which then re-runs the early-returning generator — the diff is computed but never applied. |
| **2** | **Fresh upward re-resolution in isolated per-package builds** | **Upward** (newest satisfying `from:`) | Reproduced: swift-argument-parser resolved 1.2.0 → **1.8.2**, exit 0, no warning. No resolved-graph parameter exists anywhere in `BuildPipeline.run` → `Buildable#build_command`. | **REAL, secondary.** Applies to every package the umbrella does not pin — including plugin-only and transitive-only packages the umbrella omits *by design* (`UmbrellaGenerator.swift:42`, `:64-67`). |
| **3** | **`swift package describe` also reads the drifted graph** | Both | `BuildPipeline` constructs `Desc::Description.new(pkg_dir:)` at `:190, 271, 360, 389, 408` — `describe` resolves too | **AMPLIFIER.** Product/target/scheme metadata is currently read from the drifted graph, not just the binary. Any fix must seed **before the first `describe`**. |
| **4** | **Name-only cache key over a global cache dir** | N/A | `Cache.swift:19-22` is `fileExists`; `CACHE_DIR = ~/.spm-cache` is global | **DELIVERY BLOCKER.** Not a drift cause, but the reason a fix would reach nobody. |
| **5** | **DerivedData reuse keyed only by checkout path** | N/A | `derived_data_dir_for` = `SHA256(pkg_dir)`, no graph component | **RESIDUAL.** Survives the fix; can reuse `.swiftmodule`s built against the old graph. |

**A false premise to delete from the codebase:** the comment at `UmbrellaGenerator.swift:57-63` justifies revision-pinning as reproducing "the host's resolved graph (`Package.resolved` is consistent, so the commit satisfies every parent's range by construction)". That holds **only if the lockfile is fresh — and it never is.** This also explains the field note that v0.2.8's transitive-pinning fix was "necessary, not sufficient": it made revision-pinning *more* prevalent, hardening the staleness rather than relieving it.

### Conflict Resolution: `-onlyUsePackageVersionsFromResolvedFile`

STACK.md and ARCHITECTURE.md reached opposite conclusions. **They are not contradictory — they probed different failure inputs**, and both results are correct:

| Input | Without the flag | With the flag |
|---|---|---|
| Pin **out of range** of the package's manifest | Silently discarded, re-resolved to latest, checkout's `Package.resolved` **rewritten**, `BUILD SUCCEEDED`, exit 0 (STACK V2 / ARCH §2.1 / PITFALLS V2) | **exit 74**, explicit `an out-of-date resolved file was detected`, file untouched (STACK V3 / PITFALLS V3) |
| Pin **missing** for a dependency (incl. test-only deps of the root package) | Filled in fresh, other pins preserved (ARCH §2.1) | **Hard failure** — and the umbrella *systematically* omits every package's external test dependencies, because SwiftPM skips test-only deps of non-root packages (ARCH §2.4, reproduced) |

**RECOMMENDED DIRECTION: do NOT enable the flag by default. Seed verbatim without it, and detect drift by explicit post-resolve comparison of realized versions against separately-retained intended pins.**

Rationale:

1. The missing-pin hard failure is **guaranteed, broad, and structural** — any package with an external test dependency (Quick, Nimble, swift-testing, SwiftCheck) or a build-tool plugin (SwiftLint, SwiftGen, swift-protobuf) breaks. That is a large fraction of a 59–70 package graph, and it converts a silent-correctness bug into a loud build breakage across paid-for v0.2.x edge classes.
2. The flag would also hard-fail, which the **locked fidelity policy forbids** (warn + source fallback, never hard-fail).
3. **STACK.md's "evidence is destroyed" objection does not survive the design.** Evidence is only destroyed if detection depends on re-reading the file spm-cache itself wrote. It must not. Retain the intended pin set in memory (and in the provenance sidecar), and compare it against the realized state read back **after** resolution. The rewrite is then not evidence destruction — it is the free, authoritative read-back source, since xcodebuild rewrites `<pkg_dir>/Package.resolved` in place with what it actually resolved (verified in every probe). Where `-clonedSourcePackagesDirPath` is in play, `workspace-state.json` is the equivalent source.
4. Keep the flag as an **opt-in strict/CI mode**, worth enabling only once the sidecar makes "complete pins" a checkable property.

**What would falsify this recommendation:** evidence that xcodebuild does *not* write back realized versions on some real code path — specifically the vendored-`.xcodeproj` path (`run_with_scheme`), or when `-clonedSourcePackagesDirPath` redirects the write away from both `<pkg_dir>/Package.resolved` and a readable `workspace-state.json`. If read-back has no reliable source on a given path, detection on that path must fall back to the flag (accepting hard failure) or that path must be reported as *not graph-pinned*. **Probe this on the real project during Phase 2 before committing.**

### Cache-Invalidation Constraint (carried forward — non-negotiable)

`BinariesCache.hit(module:)` (`tools/spm-cache-proxy/Sources/Core/Cache.swift:19-22`) is `fileExists(atPath: "<module>.xcframework")` — no version, revision, graph, toolchain, or spm-cache version participates. `CACHE_DIR` is the global `~/.spm-cache` (`core/config.rb:25`), not per-project. Three consequences, all live and all made *worse* by fixing resolution:

- **The fix reaches zero existing users.** Every v0.3.0-era artifact built against the wrong graph remains a hit under v0.4.0. Users upgrade, observe nothing, and correctly conclude the fix does not work.
- **Cross-project poisoning.** Project A on Alamofire 5.8 and Project B on 5.10 share one artifact; whoever built first wins for both, silently.
- **Version bumps never invalidate.** `Installer::Build` bypasses a hit only for slice incompleteness (`slice_complete?`), never for graph identity.

**Minimum viable v0.4.0 mechanism (full content-addressing stays deferred to v0.5):** a `<module>.xcframework.provenance.json` sidecar — reusing the proven `.shims.json` pattern — recording the **realized** pins (read back post-build, not the intended ones) plus spm-cache version, config, and destination set. Extend the hit check so a hit requires provenance to match the current host graph; **missing provenance ⇒ miss**, which is exactly the one-time rebuild that delivers the fix to existing users. Compare only the **intersection** of recorded pins with current host pins, keyed by identity on `revision` (falling back to `version`) — invalidating on any churn anywhere in a 70-package graph would make the cache worthless after the first bump. Precedent for the demotion hook already exists at `installer/build.rb:25` alongside `slice_complete?`.

Known scope line: `gen-proxy` runs *before* this demotion, so a bare `spm-cache use` with no subsequent build still serves a stale binary for one cycle — identical to today's slice-incompleteness behavior, and acceptable for v0.4.0. Closing it fully means moving adjudication into Swift `BinariesCache`, which is v0.5 territory.

### Recommended Stack

Ruby-side, Xcode-26.3-verified, no companion-binary release required for the core fix.

**Core technologies:**
- **`Package.resolved` v3, copied verbatim into `<pkg_dir>/Package.resolved`** — the *only* thing that actually changes which version is built. Package-root path, not `.swiftpm/xcode/...` (spm-cache builds a bare package dir). Superset pins tolerated and pruned; missing pins filled in; `originHash` verified not enforced. No synthesis, no filtering, no format branching needed.
- **Post-resolve read-back diff** — the correctness *proof*, and the milestone's second requirement. Free, since xcodebuild rewrites the file with realized versions.
- **`xcodebuild -clonedSourcePackagesDirPath <dedicated sibling dir>`** — cost mechanism and secondary fidelity reinforcement (verified to preserve versions via `workspace-state.json` even with no resolved file). **Must NOT point at `{umbrella}/.build`** — that is where `locate_prebuilt_xcframework` (`build_pipeline.rb:873-882`) reads Class-E binaryTarget artifacts from, and it is SwiftPM's live umbrella state.
- **GitHub App installation token via `actions/create-github-app-token@v3`** — for the tap push. 1-hour tokens minted per run; removes the recurring-expiry failure class entirely. Deploy key (`ssh-key:` on `actions/checkout`) is the lower-ceremony substitute.

**Explicitly rejected:** SwiftPM mirrors (URL→URL only, carry no version information); `--replace-scm-with-registry`; `-packageCachePath` as a fidelity lever; building through the umbrella workspace (destroys three field-proven invariants — per-checkout DerivedData isolation, per-invocation library-evolution flags, vendored-`.xcodeproj` handling — re-litigating ~12 documented field bugs); re-minting a classic PAT (restores the status quo *including* the one-year auto-deletion that caused the outage); hard-failing on fidelity violation.

### Expected Features

**Must have (table stakes):**
- Lockfile version reconciliation on every non-fast-path run — the dominant root cause; without it everything downstream is faithful to an abandoned graph
- Per-package builds resolve transitive deps from the host graph, not their own requirements — the correctness floor
- Dependent artifacts invalidated when a transitive resolved version changes — without it the fix is invisible
- Degrade to source compilation on genuine conflict, never abort — settled policy; all four competitors degrade
- Per-package build output states which resolution was used — an invisible decision is unauditable
- Regression coverage pinning the fidelity contract — explicit milestone requirement; the v0.3.0 retrospective ("an implemented feature is not a done phase", 4 of 5 phases harbored defects) makes it non-optional
- Homebrew formula published unattended, and the tap workflow **fails loudly** on token/push/commit failure

**Should have (competitive):**
- **Transitive-aware cache keys** — Rugby and XCRemoteCache have this; *neither SPM competitor does* (xccache's miss propagation is commented out; Scipio's VersionFile is single-package). Same work as the table-stakes invalidation row: sequence once, claim twice.
- `doctor` fidelity check — a static `spm-cache.lock` vs `Package.resolved` comparison, no build required, plugging into the existing `Core::Diagnostics.register` registry. Rugby's `doctor` is a static text checklist; this would be a real assertion no competitor has.
- Named per-package fidelity status (`host-pinned` / `resolution-incompatible → source`) as a new `GraphEntry.Status` case
- Post-publish release verification (`brew install --build-from-source` + `--version` assertion) — the real definition of "published"

**Defer (v2+ / v0.5):**
- Content-addressed cache keys (Merkle-over-resolved-versions gets ~90% of the benefit; forward-compatible key *shape*)
- Per-graph partitioning of `~/.spm-cache` (detecting collisions is the v0.4.0 obligation; partitioning is v0.5)
- Cachemap real dependency edges (every `GraphEntry` is constructed `dependencies: []` today — nodes render, no edges)
- Moving hit/miss adjudication into Swift `BinariesCache`
- Parallelizing the build loop (`Core::Parallel`) — a correctness-class data race over shared checkouts

**Anti-features (explicitly rejected):** hard-failing on fidelity violation; silently preferring the host graph with no report; skipping the cache whenever any pin disagrees (disagreement is the *normal* case, this would delete the product's value); `brew bump-formula-pr` fork-and-PR flow for a self-owned tap (reintroduces the manual merge step the milestone exists to remove).

### Architecture Approach

Ruby-only, additive, default-nil-preserves-today's-behavior. One new component is added *beneath* the existing ones; no responsibility moves between existing components.

**Major components:**
1. **`Core::PackageResolved`** (NEW) — single locator + parser for the host's `Package.resolved`. Collapses the same glob currently duplicated **five times** (`installer.rb:169`, `diff_detector.rb:150-155`, `core/watcher.rb:118`, `command/init.rb:196`, `command/use.rb:83`), which also makes the new pin source share a code path with the change detector that must agree with it.
2. **`SPM::ResolvedGraph`** (NEW) — `source_for` / `pins` / `seed!` / `drift`. Pure filesystem + JSON, zero shell-out, zero network, trivially spec'd.
3. **`SPM::BuildPipeline`** (MODIFIED) — new `resolved_pins_file:` / `clones_dir:` kwargs; seed **before** `resolve_forwarded_target` (i.e. before the first `describe`); post-build read-back diff; emit the provenance sidecar. **Both `run` and `run_with_scheme` must be wired** — the latter is the path vendored-`.xcodeproj` packages actually take.
4. **`Installer::Build`** (MODIFIED) — resolve the pin source once per run; thread it through; extend the existing hit→missed promotion at `:25` with a pin-staleness check.
5. **`Installer` lockfile reconciliation** (MODIFIED) — remove the `installer.rb:165-166` early return; re-read the host's `Package.resolved` and update `version`/`revision` per package while preserving enriched `products[]`.

**Pin-source precedence** (one rule covers both the happy path and the DerivedData fallback, no branch in `checkout_resolver.rb`): `{umbrella_dir}/Package.resolved` → host project's `Package.resolved` → warn once and behave exactly as today. Under the DerivedData fallback no umbrella resolved file exists, so precedence naturally lands on the host file — which is *exactly right*, because those checkouts came from Xcode's own resolution of that same file.

### Critical Pitfalls

1. **Ship pinning without invalidation** — the fix reaches zero users and looks done. **Phase 2 and Phase 4 must ship together.**
2. **Seed without verifying** — an out-of-range pin is silently discarded, re-resolved to latest, the file rewritten, exit 0. Strictly worse than today. Mitigation: retain intended pins separately and compare realized state post-resolve. **Never** add a "retry without the flag" branch, and **never** let `ignore_build_errors` mask a `resolution-incompatible` status (it is a build-error valve, not a correctness valve).
3. **Treat the umbrella's graph as "the host graph"** — the umbrella is a synthesized root manifest that *by design* omits plugin-only packages (`UmbrellaGenerator.swift:42`) and revision-less transitive-only packages (`:64-67`), and clamps platforms. Enshrining it ships a second wrong graph and calls it fidelity. The **app's** `Package.resolved` is the sole authority.
4. **Vendored-`.xcodeproj` packages ignore `Package.resolved` entirely** — CryptoSwift, AppAuth-iOS, SVGKit, DTCoreText, DeviceKit, AEXML, FSPagerView, SkeletonView build from a committed project whose own package references govern resolution. Injection is a **no-op** for this whole class. Classify before injecting and report them as an explicit *not graph-pinned* category; honest partial coverage beats a false 100%. Aggravator: `xcodebuild -list -project` can itself trigger resolution during scheme discovery.
5. **Resolution fan-out** — SwiftPM checks out *every* pin listed in a resolved file, including ones the manifest never needs. 70 packages × 2 destinations × a full-graph pin list is a disk and wall-clock regression severe enough to negate the product's value, and it presents as "spm-cache got slow", not as a resolution bug. Mitigation: shared `-clonedSourcePackagesDirPath`, leave the repository cache on, and **benchmark on the real project — treat a wall-clock regression as a milestone blocker.** (Note: this is the one place where ARCHITECTURE.md's "copy the superset verbatim, it's free" and PITFALLS.md's "emit the minimal closure" genuinely trade off. Verbatim-copy is correct for *correctness*; fan-out is a *cost* question. Start verbatim, measure, and narrow to the closure only if the benchmark demands it.)

**Also carried forward, lower rank:** `watch` re-entrancy (`recreate_dirs` `rm_rf`s `.build/checkouts` out from under an in-flight build — needs a process-level flock, not the debounce timer); Class-E path derivation (`locate_prebuilt_xcframework` requires `pkg_dir`'s parent to be literally named `checkouts`); macro packages with narrow `swift-syntax` pins as the most likely genuine-conflict class; stale resource bundles (`copy_resource_bundles` skips when the destination exists, and bundle names are version-stable); DerivedData reuse retaining modules built against the old graph; and the standing warning that **library evolution is not a version-mismatch mitigation** — it protects the evolving library, not a third framework compiled against the old version and co-linked with the new one.

### Release Automation Defects (`update-tap.yml`) — consolidated

Five independent defects, of which the expired token is the *visible* symptom and the *least* dangerous:

| Defect | Line | Effect |
|---|---|---|
| Expired/revoked `TAP_REPO_TOKEN` | `:29` | `Bad credentials` at cross-repo checkout. Secret exists (updated 2026-08-09), destination repo is PUBLIC. Most likely cause: **GitHub auto-deletes classic PATs unused for a year** — and a tap-update token fires only on release. |
| `curl -L` without `--fail` | `:35`-ish | Verified from `man curl`: on an HTTP error curl writes the **error page to the output file and exits 0**. `release: published` can fire before the tarball is servable ⇒ a 404 HTML page is hashed into the formula, workflow green, every `brew install` fails checksum for every user. |
| `git commit … \|\| exit 0` | `:50` | Converts **every** commit failure into success — this is exactly the v0.2.7 silent-failure class, still present. |
| Unanchored `sed s\|sha256 ".*"\|` | `:38-40` | Matches *every* `sha256`/`version` line. Single-`sha256` formula today; the moment a bottle block or resource stanza is added the release silently corrupts it. `sed` also exits 0 on zero matches, which defect #3 then swallows. |
| GNU-only `sed -i` (no backup suffix) | `:38-40` | Correct on `ubuntu-latest`; this workflow must never move to a `macos-*` runner, where BSD `sed -i` requires an explicit argument. |

**Durable token fix:** GitHub App installation token (`actions/create-github-app-token@v3`), App owned by `phuongddx`, `Contents: read & write` + `Metadata: read`, installed on `homebrew-spm-cache` **only**, never `workflow` scope. Drops straight into `actions/checkout`'s `token:` with no other workflow change. Deploy key with write access is the acceptable lower-ceremony substitute.

**But the real gap is post-publish verification.** All four content defects above produce a **green workflow that published something broken**. Fixing them to fail loudly is worthless without a listener. The definition of done is a `macos-*` job that runs `brew install --build-from-source phuongddx/spm-cache/spm-cache` and asserts `spm-cache --version` matches the tag, plus an `if: failure()` notification (`gh issue create` is zero-infrastructure). One check catches v0.2.7, the 404-tarball case, and the `sed` case. Also add: `set -euo pipefail` in every `run:` block (none have it today), an explicit `permissions: contents: read`, and a `workflow_dispatch` trigger with a `tag` input so a transient failure can be retried without re-publishing a release.

## Implications for Roadmap

PITFALLS.md proposed 5 phases; ARCHITECTURE.md proposed 7. Consolidated into **6**, ordered by hard dependency.

### Phase 1: Graph Authority — Lockfile Reconciliation
**Rationale:** This is the **dominant root cause**, and it makes every later phase verifiable. Seeding a correct mechanism from a stale source produces a confidently wrong result. ARCHITECTURE.md classified this as a "separate finding, out of milestone"; the orchestrator's source-verified chain **overrides that** — it is the primary fix, not a follow-up.
**Delivers:** `Core::PackageResolved` (collapsing the 5 duplicate globs); removal of the `installer.rb:165-166` early return; real reconciliation of `version`/`revision` on every non-fast-path run, preserving enriched `products[]`; deletion of the false premise comment at `UmbrellaGenerator.swift:57-63`.
**Testable invariant:** after a run, re-running `DiffDetector` returns an **empty** diff. Lock versions equal `Package.resolved` versions.
**Avoids:** P1 (umbrella-as-authority), P2 (stale snapshot), P13 (plugin-only/transitive-only omissions).

### Phase 2: Seed the Checkout — Host-Faithful Per-Package Resolution
**Rationale:** The second drift mechanism. Depends on Phase 1 for a trustworthy source.
**Delivers:** `SPM::ResolvedGraph`; `resolved_pins_file:` kwarg on `BuildPipeline.run` **and** `run_with_scheme`; seeding **before the first `describe`**; atomic write + `ensure`-block restore so an aborted build never leaves a checkout carrying a synthetic graph; SPM-native vs vendored-`.xcodeproj` classification with the latter reported as *not graph-pinned*; process-level flock so `watch` cannot delete checkouts mid-build. Default-nil ⇒ today's behavior byte-for-byte.
**Uses:** verbatim superset copy; no flag by default (see conflict resolution).
**Avoids:** P3, P6, P8, P11, P12, P15.
**Early probe required:** confirm read-back has a reliable source on the `run_with_scheme` path.

### Phase 3: Drift Read-Back + Provenance Sidecar
**Rationale:** The proof. Without it the milestone's second requirement ("drift cannot silently return") is unmet **by construction**. Must ship with Phase 2.
**Delivers:** post-resolve re-read, diff against retained intended pins, warn + `resolution-incompatible` status → source fallback (never hard-fail, never masked by `ignore_build_errors`); `<Name>.xcframework.provenance.json`; `rm_f` of the sidecar in `copy_prebuilt_binary_target` (mirroring the documented `.shims.json` stale-sidecar bug); new `GraphEntry.Status` case surfaced in `cache list`, `doctor`, and the cachemap.

### Phase 4: Cache Identity & Invalidation
**Rationale:** **Ships with Phases 2–3 or the milestone reaches nobody.** Not optional.
**Delivers:** `pins_current?` alongside `slice_complete?` at `installer/build.rb:25`; missing provenance ⇒ miss (the one-time rebuild that delivers the fix to existing users); intersection-on-identity comparison granularity; graph fingerprint in the DerivedData key (or wipe-on-change); unconditional resource-bundle copy within a fresh build; extended `cache clean` sidecar sweep.
**Avoids:** P5, P10, P14, P16.

### Phase 5: Regression Coverage
**Rationale:** Explicit milestone requirement, and the v0.3.0 lesson.
**Delivers:** `spec/build_fidelity_regression_spec.rb` — an out-of-range fixture asserted to be **detected and reported**, not swallowed; double-build byte-stability (reusing the `init` idempotency pattern); a coverage assertion that every package in `Package.resolved` lands in **exactly one** bucket (pinned / ignored / excluded / plugin / resolution-incompatible / not-graph-pinned) with none silently absent; the full v0.2.x fixture matrix (Class-E binary target with a FirebaseAnalytics shape, macro with narrow `swift-syntax`, all eight vendored-`.xcodeproj` packages, plugin-only, transitive-only, resource bundle, private Clang shim, product≠target rename). All hermetic — the existing `Core::Sh` / `Desc` / `Buildable` stubs suffice; do **not** bolt a networked xcodebuild integration test onto CI.

### Phase 6: Release Automation (fully independent — parallelizable, schedulable first or last)
**Rationale:** Zero coupling to the fidelity work: no shared files, no shared state, no ordering constraint. Highest value-per-hour in the milestone.
**Delivers:** GitHub App token; `curl --fail --retry` + `tar -tzf` validation; explicit no-op-vs-failure discrimination replacing `|| exit 0`; anchored `sed` (or template generation) with `grep -c` post-conditions; `set -euo pipefail`; `permissions: contents: read`; `workflow_dispatch` with a `tag` input; **post-publish `brew install` + `--version` verification job**; `if: failure()` issue creation; optional scheduled token liveness probe.

### Phase Ordering Rationale

- **1 → 2 → 3 → 4 is a hard chain.** Phase 2 is unverifiable against a stale graph (Phase 1); Phase 3 is the only proof Phase 2 worked; Phase 4 is the only way Phases 2–3 reach a user.
- **3 and 4 must ship in the same release as 2.** Shipping pinning alone is exactly xccache's current state (structural guarantee, no invalidation) and is not a bar worth clearing.
- **Phase 6 parallelizes completely.** Also a good first phase if a quick, independent win is wanted.
- **Shared clone dir (`-clonedSourcePackagesDirPath`) is folded into Phase 2** as a cost mechanism, gated on the benchmark rather than shipped unconditionally.
- **Phase 5 depends on 2–4** but its hermetic fixtures can be authored in parallel with them.

### Research Flags

Phases likely needing `--research-phase` during planning:
- **Phase 2** — the vendored-`.xcodeproj` classification boundary and the read-back source on `run_with_scheme` are the least-characterized surfaces; also the fan-out/benchmark trade-off between verbatim-superset and minimal-closure pin lists.
- **Phase 4** — comparison granularity and the DerivedData fingerprint interact with the deferred v0.5 content-addressing work; getting the key *shape* forward-compatible matters more than the key itself.

Phases with standard patterns (skip research):
- **Phase 1** — the defect and its fix are fully source-verified; a mechanical change to a 30-line method.
- **Phase 3** — reuses the established `.shims.json` sidecar and `Core::Diagnostics` registry patterns verbatim.
- **Phase 5** — existing spec seams (`Core::Sh`, `Desc::Description`, `Buildable` factory) already proven across 258 green examples.
- **Phase 6** — vendor-documented; `actions/create-github-app-token@v3` drops in with no design work.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Root-cause model | **HIGH** | Fully source-verified 5-link chain; original hypothesis independently falsified by HTTP probe; corroborated by a 24-package survey |
| Stack | **HIGH** | Every load-bearing claim executed on this machine (Xcode 26.3 / Swift 6.2.4), reproduced independently by three researchers with concordant results |
| Features | **HIGH** | Competitor mechanisms read from implementation source and shipped docs, not blog posts or search summaries |
| Architecture | **HIGH** | Every integration point cited by `file:line` in this repo; empirical probes for every behavioral assumption |
| Pitfalls | **HIGH** | 4 load-bearing experiments (V1–V4) reproduced locally; every codebase claim read from source |
| Release automation | **MEDIUM** | Vendor documentation + live `gh secret list` / `gh repo view`, but no end-to-end dry run against `phuongddx/homebrew-spm-cache` |

**Overall confidence: HIGH** for the diagnosis and the recommended direction; **MEDIUM** for cost/blast-radius, which is unmeasured.

### Gaps to Address

- **Root-cause attribution has not been reproduced against the real 59–70 package project.** The chain is source-verified and the motivating symptom is explained, but the *relative* contribution of surfaces #1 and #2 in the field is inferred, not measured. **Reproduce a release-config stale-transitive build on the real project early in Phase 1** and attribute it before Phase 2's design is locked.
- **The blast radius of pinning is UNMEASURED.** Nobody knows how many of 59–70 packages would report `resolution-incompatible`. Run seeding in **report-only mode** against the real project and count, *before* committing to the policy. If it is 2 packages the source-fallback policy is trivially right; if it is 20, the milestone needs rescoping (e.g. a documented, dated exclusion of macro packages from graph pinning with a v0.5 follow-up).
- **Wall-clock and disk cost is UNMEASURED.** Treat a regression on the real project as a milestone blocker, not a follow-up. `benchmark-report.html` already exists in the repo.

### Open Questions — deduplicated and ranked

| # | Question | Type |
|---|---|---|
| 1 | Which root-cause surface dominates in the field, and does the lockfile fix alone resolve the motivating ExyteChat/MediaPicker case? | **NEEDS EMPIRICAL MEASUREMENT** — Phase 1, blocking Phase 2's design |
| 2 | How many packages report `resolution-incompatible` under pinning? | **NEEDS EMPIRICAL MEASUREMENT** — report-only run, blocking policy commitment |
| 3 | What is the wall-clock/disk delta from the pin-list fan-out? Verbatim superset vs minimal closure? | **NEEDS EMPIRICAL MEASUREMENT** — benchmark decides; start verbatim |
| 4 | Does xcodebuild write back realized versions on the `run_with_scheme` / vendored-`.xcodeproj` path? | **NEEDS EMPIRICAL MEASUREMENT** — the sole falsifier of the no-flag recommendation |
| 5 | Cache-key migration: is a one-time full rebuild acceptable, or is a key-version namespace needed so old artifacts age out? | **USER DECISION** |
| 6 | Exclude macro packages from graph pinning in v0.4.0, contingent on Q2's answer? | **USER DECISION** (record as a dated decision if taken) |
| 7 | Is `~/.spm-cache` partitioned per-graph in v0.4.0 or v0.5? | **USER DECISION** — detect-via-provenance is the v0.4.0 floor either way |
| 8 | Does a local package's own remote dependency get host-pinned too? | **USER DECISION** — recommendation: yes, same rule; confirm no local-package workflow depends on independent resolution |
| 9 | On drift detection: warn or fail? | **RESOLVED-BY-SYNTHESIS** — warn + source fallback, never hard-fail (locked decision); `ignore_build_errors` must not mask it |
| 10 | Should `-onlyUsePackageVersionsFromResolvedFile` be the default? | **RESOLVED-BY-SYNTHESIS** — no; opt-in strict mode only, pending Q4 |
| 11 | Does a package's genuinely-unsatisfiable constraint also invalidate its dependents' cached artifacts? | **RESOLVED-BY-SYNTHESIS** — propagate; a dependent built against a source-compiled dep is the only self-consistent outcome (Rugby's behavior) |
| 12 | Where does the injected resolved file live? | **RESOLVED-BY-SYNTHESIS** — package root `<pkg_dir>/Package.resolved` (empirically the only path honored), atomic write with `ensure`-block restore; scratch isolation via a *dedicated sibling* `-clonedSourcePackagesDirPath`, never `{umbrella}/.build` |
| 13 | Tap token type? | **RESOLVED-BY-SYNTHESIS** — GitHub App installation token; deploy key as substitute; classic PAT rejected |
| 14 | Does `swift package resolve` emit `{umbrella}/Package.resolved` in every failure/partial mode (`installer.rb:240-243` retry path)? | **RESOLVED-BY-SYNTHESIS** — the existence check in the precedence rule makes it self-correcting; a one-line field probe would settle it |
| 15 | Does the `action/` composite repo need coordinated changes if the cache key gains provenance? | **RESOLVED-BY-SYNTHESIS** — out of scope for v0.4.0 (locked); record as a v0.5 follow-up |

## Sources

### Primary (HIGH confidence)
- **Empirical, this machine, 2026-08-27, Xcode 26.3 (17C529) / Swift 6.2.4:** experiments A–H (STACK.md), §2.1–2.4 probes (ARCHITECTURE.md), V1–V4 (PITFALLS.md) — pin honoring, superset tolerance, missing-pin fill-in, `originHash` indifference, out-of-range silent re-resolution + file rewrite, `-onlyUsePackageVersionsFromResolvedFile` exit 74, test-only dependency resolution for library-only schemes, shared-clone-dir version preservation, `.build/` ↔ `SourcePackages/` layout equivalence, 24-package committed-`Package.resolved` survey, `man curl --fail` semantics
- **Orchestrator verification, 2026-08-27:** HTTP 404 probe of `exyte/Chat` `Package.resolved` at both canonical paths; source trace of `installer.rb:165-166,191,241` → `Lockfile.swift:118-126` → `UmbrellaGenerator.swift:73`
- **This repository, read directly:** `lib/spm_cache/{installer.rb, installer/build.rb, spm/build.rb, spm/build_pipeline.rb, spm/checkout_resolver.rb, core/{config,diff_detector,lockfile,sh,diagnostics}.rb, command/cache/clean.rb}`; `tools/spm-cache-proxy/Sources/Core/{Cache,Lockfile,Generator/UmbrellaGenerator,Generator/ProxyGenerator}.swift`; `.github/workflows/update-tap.yml`; `spec/{buildable,build_pipeline,installer_build}_spec.rb`
- **Competitor source and shipped docs:** xccache (`docs/under-the-hood/proxy-packages.md`, `lib/xccache/spm/desc/target.rb`), Scipio (`cache-system.md`, `prepare-cache-for-applications.md`), Rugby (`TargetsHasher.swift`, `Docs/commands-help/doctor.md`), XCRemoteCache (`README.md`)
- `gh secret list` / `gh repo view` against the live repos

### Secondary (MEDIUM confidence)
- Context7 `/swiftlang/swift-package-manager` — mirrors, path dependencies, `swift package edit`
- GitHub Docs — PAT expiry/auto-removal, OAuth scopes, GitHub App tokens in Actions
- `actions/create-github-app-token`, `mislav/bump-homebrew-formula-action`, `peter-evans/create-pull-request` READMEs
- Homebrew Discussions #5129 (App tokens require `brew bump --no-fork`), #4389 (fine-grained PAT failures)

### Tertiary (LOW confidence — corroborating only)
- Apple Developer Forums thread 755995 — `originHash` purpose (independently VERIFIED above)
- swiftlang/swift-package-manager#7644 — lazy `originHash` updates
- softprops/action-gh-release#217 — release-event 404 timing class

---
*Research completed: 2026-08-27*
*Ready for roadmap: yes*
