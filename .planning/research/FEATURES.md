# Feature Research

**Domain:** Swift/Xcode binary dependency caching (SPM proxy-package architecture) + OSS release automation
**Milestone:** v0.4.0 — Build Fidelity & Release Automation
**Researched:** 2026-08-27
**Confidence:** HIGH for competitor mechanisms (read from their own source code and shipped docs); MEDIUM for release-automation token guidance (vendor docs + maintainer discussion, not empirically reproduced here)

> Scope note: this milestone is narrow. Everything already shipped through v0.3.0 (`use`, `build`, `rollback`, `off`, `cache list/clean`, remote cache, cachemap, `doctor`, `init`, `watch`, per-config caching, multi-slice xcframeworks, macros, resource bundles) is treated as existing substrate, not researched again. Findings below are scoped to (A) dependency-graph fidelity and (B) Homebrew release automation.

---

## Competitor Mechanism Findings (the evidence base)

Every claim in this section was read from the competitor's own repository — source code where behavior matters, shipped docs where intent matters. No claim rests on a blog post or search summary.

### How each tool guarantees a prebuilt binary matches the consuming app's graph

| Tool | Resolution mechanism | Fidelity guarantee | Strength |
|------|---------------------|--------------------|----------|
| **Scipio** (giginet, ~544★) | All app dependencies must be declared in **one separate `Package.swift`** (`MyAppDependencies`). SwiftPM resolves that single manifest; every xcframework is built from that one resolution. | By **convention only**. The Scipio manifest is a *different file* from the app's own Xcode SPM references, and nothing reconciles the two. If the app adds an SPM dependency in Xcode and forgets the Scipio manifest, drift is undetected and unreported. | WEAK |
| **xccache** (trinhngocthuyen, ~71★) | An **umbrella package** (`xccache/packages/umbrella`) is the single resolution root. Each package gets a proxy whose manifest is derived from the real one, but with dependencies **rewritten from remote URLs to sibling paths**: `.package(url: "https://…/Alamofire.git", .upToNextMajor(from: "5.0.0"))` becomes `.package(path: "../Alamofire")`. All proxies symlink the umbrella's `.build/checkouts`. | **Structural.** A package physically cannot resolve a different version, because the remote requirement no longer exists in its manifest. There is nothing left to re-resolve. | STRONGEST |
| **Rugby** (swiftyfinch, CocoaPods) | Does not resolve at all — explicitly "Doesn't change Podfile and Podfile.lock". CocoaPods owns resolution; there is exactly one graph by construction. | N/A for resolution. Correctness is enforced downstream via hashing (below). | N/A |
| **XCRemoteCache** (Spotify) | The entire graph is pinned to **one git commit sha**: `xcprepare` scans the 10 most recent common shas with the remote branch (first-parent), picks the newest for which *all* artifact markers exist, writes it to `arc.rc`. Marker key is `commitSha-Target-Configuration-Platform-XcodeBuildNumber-ContextBuildSettings-SchemaID`. | **Structural + content-addressed.** One sha = one consistent artifact set, and per-target fingerprints are computed over real compiler input files (from `.d` output, shipped in `meta.json`). | STRONGEST |

**Where spm-cache sits today (verified in this repo):**
`tools/spm-cache-proxy/Sources/Core/Generator/ProxyGenerator.swift:327-342` (`sourceDependencyLines`) emits, for every non-local package:

```swift
let depLine = ".package(url: \"\(url)\", \(req))"
```

Each proxy therefore carries **its own remote version requirement**, so SwiftPM re-resolves per proxy and is free to select a transitive version the host app never resolved. This is precisely the xccache mechanism *minus* the URL→path rewrite. spm-cache already has the umbrella and the shared-checkout machinery; it is one manifest-generation change away from xccache's structural guarantee.

### Cache invalidation on transitive drift

| Tool | Cache key contents | Invalidates dependents on transitive change? |
|------|--------------------|---------------------------------------------|
| **Rugby** | `TargetsHasher.swift` hashes depth-first and sets `targetHashContext["dependencies"] = dependencyHashes` before hashing. Context = name, swift_version, xcode_version, xcargs, buildPhases (file content hashes), product, configurations, cocoaPodsScripts, buildRules. | **YES** — Merkle-style. A dep's hash change propagates to every dependent automatically. |
| **XCRemoteCache** | Fingerprint over actual input files discovered from clang/swift `.d` output. A dependency's module output *is* an input of the dependent. | **YES** — automatic, by construction. |
| **xccache** | `lib/xccache/spm/desc/target.rb`: `@checksum ||= root.git&.sha \|\| sources_path.checksum` — the package's **own** git sha or source tree only. | **NO.** And "Cache miss propagation" is written into `docs/overview.md` but **commented out** — designed, not shipped. |
| **Scipio** | `VersionFile` JSON (`.$FRAMEWORK.version`): `pin.revision` + `pin.version` **of that package only**, plus buildOptions, clangVersion, xcodeVersion, scipioVersion, targetName. | **NO.** A transitive bump rebuilds the bumped package but leaves its dependents' xcframeworks cached and stale. |

**Conclusion for Q3:** yes, a host transitive-version change *must* invalidate dependent artifacts. Neither SPM competitor does this. Both general-purpose binary caches do. This is the single highest-leverage finding in this research.

### Behavior when fidelity is violated — nobody hard-fails

| Tool | Observed behavior |
|------|-------------------|
| **xccache** | "In case of cache miss, it automatically uses the original dependency." Silent source fallback. |
| **XCRemoteCache** | Focused targets "compare local fingerprint with one available remotely and **fallbacks to the local compilation** if it doesn't match." A new source file forces whole-target local compilation. After a miss, cache is disabled for that target until `arc.rc`'s sha changes. |
| **Rugby** | Ships a README *preconditions* section warning that pods must build standalone, else "you can get a state when one of them can't be reused correctly without the source of its dependencies." Escape hatches are `-e BadPod` (exclude) and `--ignore-cache`. |
| **Scipio** | Rebuilds. Prints `✅ Valid Logging.xcframework (<hash>) is exists. Skip building.` on reuse. |

Not one of the four aborts the build on a consistency problem. The universal contract is **degrade, never break** — which is verbatim spm-cache's own Core Value ("a cache hit never breaks a build").

### Diagnostics and observability

| Tool | Surface |
|------|---------|
| **Scipio** | Build output only — one line per framework naming the decision and the hash. |
| **xccache** | `xccache.lock` (human-readable state) + cachemap HTML showing per-package checksum + a cache-stats UI listing hits and misses. |
| **XCRemoteCache** | `xcprepare` prints `result / commit / age / recommended_remote_address` before the build. |
| **Rugby** | `rugby doctor` exists — but it is a **static remediation checklist** (update, check config, `--ignore-cache`, `rugby clear`, clean DerivedData, verify the project builds without Rugby) plus a pointer to `~/.rugby/logs`. It runs **zero programmatic assertions**. |

spm-cache's `doctor` is already stronger than Rugby's: a 7-check data-driven registry (`Core::Diagnostics.register(name, fix_hint:) { |config:| … }`) with `--json` and CI exit semantics. Adding a fidelity check is an extension, not new infrastructure.

---

## Feature Landscape

### Table Stakes (Users Expect These)

| Feature | Why Expected | Complexity | Notes / Dependencies |
|---------|--------------|------------|----------------------|
| **Proxy manifests resolve transitive deps from the host graph, not their own requirements** | This is the correctness floor. A binary compiled against a version the app doesn't ship is a wrong answer served silently. xccache guarantees it structurally; it is the reason its proxy design exists. | **MEDIUM** | Change `ProxyGenerator.sourceDependencyLines` to emit `.package(path: "../<slug>_proxy")` for packages already in the host graph. Depends on: **umbrella + shared checkouts (exists)**, **lockfile package set (exists)**, **package→package edges (DOES NOT EXIST — see Dependencies)**. |
| **Degrade to source, never abort, when the host graph and a package's own requirement genuinely conflict** | All four competitors fall back. spm-cache's Core Value already promises it. A tool that can fail a build is a tool teams remove. | **LOW** | Reuses the existing cache-miss → source-fallback path (`GraphEntry.status = .missed`). No new mechanism, just a new trigger. |
| **Dependent artifacts invalidated when a transitive resolved version changes** | Without this, fixing resolution makes builds *correct once* and stale thereafter. Rugby and XCRemoteCache both treat this as baseline. Fixing resolution without fixing invalidation ships a half-fix. | **MEDIUM** | Merkle over the **lockfile** graph (resolved version+revision of the transitive closure), NOT content-addressed hashing of file contents — that remains deferred to v0.5. Depends on: **cache key (exists)**, **lockfile (exists)**, **package→package edges (missing)**. |
| **Per-package build output states which resolution was used** | Every competitor prints a per-package decision line. Users of a cache tool debug by reading build output; an invisible decision is unauditable. | **LOW** | Extend existing per-package hit/miss logging. No new surface. |
| **Regression coverage that pins the fidelity contract** | Already an explicit v0.4.0 requirement. The v0.3.0 retrospective's central lesson — "an implemented feature is not a done phase", 4 of 5 phases harbored defects — makes this non-optional. | **MEDIUM** | Fixture: package A depends on B; host resolves B at a version ≠ A's own pin; assert generated proxy manifest and cache key. Depends on: **existing RSpec + swift-test CI (exists)**, `ProxyGeneratorTests.swift` (exists). |
| **Homebrew formula published unattended on release** | Homebrew is the *only* working distribution channel (RubyGems publication is explicitly out of scope). A release path requiring manual steps is a broken release path. | **LOW** | Workflow exists at `.github/workflows/update-tap.yml`; only the token is broken. `GITHUB_TOKEN` cannot write cross-repo — a PAT or App token is mandatory. |
| **Tap workflow fails loudly on token/push failure** | The current `git commit … \|\| exit 0` swallows a genuine commit failure identically to "nothing to commit". A silent green release is how `TAP_REPO_TOKEN` rotted unnoticed. | **LOW** | Distinguish "no diff" from "commit failed"; verify the push landed. |

### Differentiators (Competitive Advantage)

| Feature | Value Proposition | Complexity | Notes / Dependencies |
|---------|-------------------|------------|----------------------|
| **Transitive-aware cache keys in the SPM niche** | Rugby and XCRemoteCache have this; **neither SPM competitor does**. xccache's miss-propagation is commented out; Scipio's VersionFile is single-package. Shipping it makes spm-cache the only SPM binary cache that cannot serve a stale-transitive artifact. | **MEDIUM** | Same work as the table-stakes invalidation row — it is table stakes against the *category* and a differentiator against the *SPM segment*. Sequence it once, claim it twice. |
| **`doctor` check for host-graph ⟷ cached-artifact drift** | Rugby's `doctor` is a static text checklist. spm-cache's is a real assertion registry. A check that reports "N cached artifacts were built against transitive versions the host no longer resolves" is a capability no competitor has. | **LOW** | Plugs directly into `Core::Diagnostics.register`. Static comparison of `spm-cache.lock` vs `Package.resolved` — no build required. Depends on: **doctor registry (exists)**, **lockfile (exists)**, **edges (missing)**. |
| **Cachemap edges showing the resolved transitive graph** | xccache's cachemap shows per-package checksums but the tool has no dependency edges either. spm-cache already ships the HTML visualization; drawing real edges turns a list into a graph and makes fidelity legible at a glance. | **LOW–MEDIUM** | **Verified gap:** every `GraphEntry` in `ProxyGenerator.swift` is constructed with `dependencies: []` (lines 90, 169) — the cachemap currently renders **no edges at all**. Populating them is a byproduct of building the edge model. |
| **Explicit, named fidelity decision per package (`host-pinned` / `conflict → source`)** | Competitors print hit/miss. Naming *why* a package fell back turns a support thread into a self-serve answer. Directly addresses the v0.2.x field-bug class (version drift, stale metadata). | **LOW** | Extends `GraphEntry.Status` enum (currently `hit, missed, ignored, excluded, plugin`). |

### Anti-Features (Commonly Requested, Often Problematic)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| **Hard-fail the build on a fidelity violation** | "Correctness first — surface the problem loudly." | Directly contradicts the stated Core Value ("a cache hit never breaks a build") and **zero of four competitors do it**. A caching tool that can break a build is uninstalled the first time it does. Worse: the violation is often benign (a package's committed pin is simply older than the host's), so hard-fail would abort on non-problems. | Warn + build that package from source. Loud in output, harmless to the build. Escalate to non-zero exit **only** in `doctor --json`, which is the designated CI gate. |
| **Silently prefer the host graph with no report** | Simplest to implement; it is what xccache effectively does (the package's own requirement is erased, so there is nothing to report). | spm-cache's own history argues against it: the v0.2.x line was a series of field-bugfix releases for exactly this class (identity collisions, wrong product names, version drift, stale metadata), and v0.3.0 shipped `doctor` specifically to make invisible state visible. Reintroducing an invisible decision walks that back. | Prefer the host graph (correct default) **and** emit a per-package line naming the override. Cost is one log line. |
| **Skip the cache entirely whenever any pin disagrees** | Maximally safe. | Package-committed `Package.resolved` files are *routinely* stale relative to a host app — that is normal SPM life, not an anomaly. This policy would produce near-total cache misses and delete the product's entire value. | Disagreement is the expected case; the host graph simply wins. Fall back to source only on a genuine **unsatisfiable** constraint. |
| **Full content-addressed cache keys (hash file contents) to solve this** | It is the "real" fix and what XCRemoteCache does. | Already assessed HIGH effort and deferred to v0.5 in PROJECT.md. Adopting it here would swallow the milestone. Merkle-over-resolved-versions gets ~90% of the correctness benefit at a fraction of the cost, and is forward-compatible. | Hash the transitive closure's resolved version+revision from the lockfile. Upgrade to content-addressing in v0.5 without changing the key's *shape*. |
| **GitHub App (`create-github-app-token`) for the tap push** | It is the modern best practice and avoids PAT expiry. | Over-engineered for **one personal tap owned by the same account**: register an app, store a private key, handle 1-hour token expiry, and accept that `brew bump-formula-pr` fails with App tokens unless you use `brew bump --no-fork` (Homebrew Discussion #5129). Substantial ceremony for a single `contents:write` push. | A PAT scoped to the tap repo. Revisit only if the tap moves to an org or the token becomes a recurring operational cost. |
| **`brew bump-formula-pr` fork-and-PR flow for a self-owned personal tap** | It is the canonical Homebrew automation and what most guides show. | The fork+PR flow exists to serve `Homebrew/homebrew-core`, where you cannot push. For a tap you own it **adds** a fork and a manual PR merge — reintroducing the exact manual step this milestone exists to remove. Also carries the fine-grained-PAT incompatibility reported in Homebrew Discussion #4389. | Keep direct push to the tap. If replacing the hand-rolled `sed`, use `mislav/bump-homebrew-formula-action` with `create-pullrequest: false`. |
| **Hand-rolled `sed` formula rewriting (status quo)** | Already written; zero dependencies. | **Latent bug:** the current `sed -i "s\|sha256 \".*\"\|sha256 \"${SHA}\"\|"` and `s\|version \".*\"\|…\|` are unanchored and replace **every** matching line. The formula is single-`sha256` today, but the moment a `bottle do` block or a resource stanza is added, the release silently corrupts the formula. | `mislav/bump-homebrew-formula-action@v4` — field-aware, auto-computes `sha256` from the release archive, and defaults `download-url` to exactly the tarball URL already in use. Roughly a net line reduction. |

---

## Feature Dependencies

```
[Package -> package dependency edge model]        <-- MISSING TODAY, hard prerequisite
    |
    +--requires--> [spm-cache.lock] (exists; holds packages + per-Xcode-target
    |                                product names, but NO package->package edges)
    +--requires--> [Lockfile.PackageRef] (exists; has version + revision,
                                          NO dependencies field)
    |
    +--enables--> [Host-graph pinning in proxy manifests]
    |                 (rewrite .package(url:) -> .package(path:))
    |                     |
    |                     +--requires--> [Umbrella + shared checkouts] (exists)
    |                     +--requires--> [ProxyGenerator] (exists)
    |
    +--enables--> [Merkle cache key over transitive resolved versions]
    |                 +--requires--> [existing cache key / storage] (exists)
    |
    +--enables--> [doctor fidelity check]
    |                 +--requires--> [Core::Diagnostics registry] (exists)
    |
    +--enables--> [Cachemap real edges]
                      +--requires--> [GraphEntry.dependencies] (exists as a field,
                                      always populated []; cachemap has no edges)

[Host-graph pinning] --requires--> [Merkle cache key]   (ordering constraint)
[Fidelity decision in build output] --enhances--> [Host-graph pinning]
[Regression coverage] --requires--> [Host-graph pinning] + [Merkle cache key]

[Tap token repair] ---- INDEPENDENT ---- (no coupling to the fidelity work)
[Loud tap failure] --enhances--> [Tap token repair]
```

### Dependency Notes

- **Everything fidelity-related requires a package→package edge model, and it does not exist.** Verified: `Lockfile.PackageRef` (`tools/spm-cache-proxy/Sources/Core/Lockfile.swift:21-28`) has `repositoryURL`, `pathFromRoot`, `name`, `productName`, `version`, `revision`, `products` — **no dependencies field**. `Lockfile.dependencies` is `[String: [String]]` mapping *Xcode target name → product names*, not package → package. And every `GraphEntry` is built with `dependencies: []`. This is the true first phase of the milestone; treat it as such rather than assuming the lockfile already carries the graph.
- **Host-graph pinning requires Merkle cache keys to ship in the same milestone.** Pinning alone makes the *next* build correct while leaving already-cached artifacts stale — the fix would be invisible and, worse, would look done. This is exactly xccache's shipped state (structural resolution guarantee, no invalidation) and is not a bar worth clearing.
- **`doctor` fidelity check needs no new infrastructure.** `Core::Diagnostics.register(name, fix_hint:) { |config:| … }` (`lib/spm_cache/core/diagnostics.rb:34`) is the extension point; the 7 existing checks are the template. It also runs without a build, making it the natural CI gate.
- **`installer.rb:137-162` already models the adjacent problem.** `refresh_consumed_dependencies` distinguishes directly-consumed from transitive-only packages so the umbrella does not independently pin a transitive package at a conflicting version (the realm-core case). The edge model generalizes machinery that is already half-built — reuse it rather than starting fresh.
- **Release automation is fully independent.** No shared files, no shared state, no ordering constraint against the fidelity work. It can run in parallel or be sequenced purely on convenience.

---

## Prioritization

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Package→package edge model in the lockfile | HIGH (enabler for all of the above) | MEDIUM | **P1** |
| Host-graph pinning in proxy manifests | HIGH | MEDIUM | **P1** |
| Merkle cache key over transitive resolved versions | HIGH | MEDIUM | **P1** |
| Conflict → source fallback (never abort) | HIGH | LOW | **P1** |
| Regression coverage for transitive drift | HIGH (explicit milestone requirement) | MEDIUM | **P1** |
| `TAP_REPO_TOKEN` repaired / tap publishes unattended | HIGH (only working distribution channel) | LOW | **P1** |
| Loud failure on tap push/commit error | MEDIUM | LOW | **P1** |
| Per-package fidelity decision in build output | MEDIUM | LOW | **P2** |
| `doctor` fidelity check | MEDIUM | LOW | **P2** |
| Replace hand-rolled `sed` with a field-aware bump action | MEDIUM (removes latent corruption bug) | LOW | **P2** |
| Cachemap real dependency edges | LOW–MEDIUM | LOW–MEDIUM | **P3** |
| Content-addressed cache keys | HIGH | HIGH | **v0.5 — out of scope** |

---

## Competitor Feature Matrix

| Capability | Scipio | xccache | Rugby | XCRemoteCache | spm-cache today | spm-cache v0.4.0 target |
|-----------|--------|---------|-------|---------------|-----------------|------------------------|
| Single shared resolved graph | Convention (separate manifest) | **Structural** (path-rewritten proxies) | N/A (CocoaPods owns it) | **Structural** (one commit sha) | ✗ per-proxy `.package(url:)` | **Structural** (path-rewritten proxies) |
| Transitive-aware invalidation | ✗ (own pin only) | ✗ (own git sha; propagation commented out) | ✓ (recursive dep hashes) | ✓ (input-file fingerprints) | ✗ | ✓ (Merkle over resolved versions) |
| Never aborts on inconsistency | ✓ (rebuilds) | ✓ (silent source fallback) | ✓ (exclude / `--ignore-cache`) | ✓ (local compilation fallback) | ✓ (source fallback) | ✓ (preserved) |
| Names the fidelity decision | ✗ | ✗ | ✗ | partial (`xcprepare` summary) | ✗ | ✓ |
| Programmatic `doctor` assertions | ✗ | ✗ | ✗ (static checklist only) | ✗ | ✓ (7 checks) | ✓ (+ fidelity check) |
| Dependency graph visualization | ✗ | ✓ (nodes + checksums) | ✗ | ✗ | ✓ (nodes only, **no edges**) | ✓ (edges) |
| Reads the Xcode project directly | ✗ | partial | ✗ (Pods project) | ✓ | ✓ | ✓ |

---

## Open Questions for Requirements

1. **Locally-developed packages.** Path-rewriting is unambiguous for remote packages, but local packages already use `.package(path:)`. Does a local package's own remote dependency get host-pinned too? (Recommendation: yes, same rule — but confirm no local-package workflow depends on independent resolution.)
2. **Genuinely unsatisfiable constraints.** When a package's manifest requires `>= 6.0` and the host resolved `5.9`, the correct action is source fallback for *that package*. Should its dependents also fall back, or may they keep cached binaries? (Rugby propagates; xccache designed propagation and did not ship it. Recommendation: propagate — a dependent built against a source-compiled dep is the only self-consistent outcome.)
3. **Cache-key migration.** Changing the key invalidates every existing local and remote artifact on upgrade. Is a one-time full rebuild acceptable, or is a key-version namespace needed so old artifacts age out instead of thrashing? (Not answerable from competitor research; it is a product call.)
4. **Tap token type.** Classic PAT (`repo` scope) vs fine-grained PAT (`contents:write` on the tap repo only). Fine-grained is the better security posture and the direct-push path avoids the `bump-formula-pr` incompatibilities reported in Homebrew Discussion #4389 — but this was **not empirically verified** in this research and should be proven with a live dry-run before the requirement is written as satisfied.

---

## Sources

Read directly from the projects' own repositories (source code and shipped docs):

- **xccache** — `docs/under-the-hood/proxy-packages.md` (URL→path rewrite, proxy manifest derivation), `docs/overview.md` (umbrella, cache fallback, checksum model, commented-out miss propagation), `lib/xccache/spm/desc/target.rb` (`checksum` implementation), `docs/features-roadmap.md`, `docs/troubleshooting.md`
- **Scipio** — `Sources/scipio/scipio.docc/cache-system.md` (VersionFile schema, cache policies), `prepare-cache-for-applications.md` (single-manifest concept, CLI flags incl. `--only-use-versions-from-resolved-file`), `build-pipeline.md` (cache actors, storage backends)
- **Rugby** — `Sources/RugbyFoundation/Core/Common/Hashers/TargetsHasher.swift` (recursive dependency hashing — the definitive evidence), `README.md` (preconditions, standalone-build warning), `Docs/commands-help/doctor.md`, `Docs/commands-help/shortcuts/cache.md`
- **XCRemoteCache** — `README.md` (fingerprinting, `meta.json`, `arc.rc` sha selection, marker key format, focused/thin targets, local-compilation fallback, consumer eligibility gates)
- **Release automation** — `mislav/bump-homebrew-formula-action` README; `dawidd6/action-homebrew-bump-formula` README; `actions/create-github-app-token` README; Homebrew Discussion [#5129](https://github.com/orgs/Homebrew/discussions/5129) (GitHub App tokens require `brew bump --no-fork`), Discussion [#4389](https://github.com/orgs/Homebrew/discussions/4389) (fine-grained PAT failures)
- **This repository** — `tools/spm-cache-proxy/Sources/Core/Generator/ProxyGenerator.swift`, `.../Lockfile.swift`, `.../GraphGenerator.swift`, `lib/spm_cache/installer.rb`, `lib/spm_cache/core/diagnostics.rb`, `.github/workflows/update-tap.yml`

**Confidence note:** competitor mechanism claims are HIGH — they were read from implementation source or shipped documentation, not inferred. The release-automation token guidance is MEDIUM: it comes from vendor documentation and a Homebrew maintainer discussion but was not empirically reproduced against `phuongddx/homebrew-spm-cache`.

---
*Feature research for: SPM binary dependency caching — build fidelity & release automation*
*Researched: 2026-08-27*
