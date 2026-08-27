# Stack Research

**Domain:** SwiftPM/xcodebuild build-graph fidelity + GitHub Actions cross-repo release automation
**Researched:** 2026-08-27
**Confidence:** HIGH (Part A — build fidelity, empirically executed on this machine) / MEDIUM (Part B — release automation, doc-derived)

---

## Verification Method

Part A is **not** answered from memory or docs. Every claim marked VERIFIED below was executed on this machine today against a purpose-built reproduction package (`Alpha` → `swift-argument-parser`, `from: "1.2.0"`):

| Component | Version | How established |
|-----------|---------|-----------------|
| Xcode | **26.3** (build 17C529) | `xcodebuild -version` |
| Swift | **6.2.4** (swiftlang-6.2.4.1.4) | `swift --version` |
| macOS SDK | MacOSX26.2.sdk | build transcript |
| `Package.resolved` format | **v3** (`"version": 3`, `originHash`) | written by the toolchain above |

Claims sourced from web/docs rather than execution are tagged `[MEDIUM — doc]`. Nothing here is tagged from pre-2025 memory.

---

# PART A — Build Fidelity

## The Headline Finding

> **Neither `xcodebuild` resolution flag pins versions. The on-disk `Package.resolved` does the pinning. The flags only decide whether a pin that cannot be satisfied fails loudly or is silently discarded.**

This inverts the framing in the milestone question and it changes the design. The fix for spm-cache is **write the right `Package.resolved` into the checkout**; the flag is a *guard rail*, not the mechanism.

### Experiment Matrix (all VERIFIED, Xcode 26.3 / Swift 6.2.4)

| # | Pin in `Package.resolved` | Command | Outcome |
|---|---------------------------|---------|---------|
| A | `1.2.0` (hand-edited down from `1.8.2`), **`originHash` left stale** | `swift package resolve` | **Honored `1.2.0`.** Stale hash not validated. |
| B | `1.2.0`, stale hash | `swift package resolve --force-resolved-versions` | exit 0, kept `1.2.0` |
| C | `0.5.0` — **violates** manifest `from: "1.2.0"` | `swift package resolve` | **Silently re-resolved to `1.8.2` and rewrote the file.** No warning. |
| D | `0.5.0` (violating) | `swift package resolve --force-resolved-versions` | **`error: an out-of-date resolved file was detected … not allowed when automatic dependency resolution is disabled`** |
| E | `1.2.0` | `xcodebuild … -onlyUsePackageVersionsFromResolvedFile` | Checked out **`1.2.0`**, `BUILD SUCCEEDED` |
| F | `1.2.0` | `xcodebuild …` **no flag** | Checked out **`1.2.0`**, `BUILD SUCCEEDED` |
| G | `1.2.0`, clone dir **pre-populated at `1.8.2`** | `xcodebuild … -clonedSourcePackagesDirPath <dir>` | `Checking out 1.2.0 of package 'swift-argument-parser'` — **mutated the shared dir in place** |
| H1 | `0.5.0` (violating) | `xcodebuild … -onlyUsePackageVersionsFromResolvedFile` | **`xcodebuild: error: Could not resolve package dependencies: an out-of-date resolved file was detected …`** |
| H2 | `0.5.0` (violating) | `xcodebuild … -disableAutomaticPackageResolution` | **Byte-identical error to H1** |
| H3 | `0.5.0` (violating) | `xcodebuild …` **no flag** | **Silently re-resolved to `1.8.2`, `BUILD SUCCEEDED`** ← *this is spm-cache's bug today* |

**Read E vs F:** the flag made no difference when the pin was satisfiable — the resolved file alone pinned it.
**Read H1 vs H2:** the two flags are behaviourally indistinguishable aliases.
**Read H3:** the current no-flag invocation at `build.rb:99` will happily build against a version nobody asked for and report success. That is the silent-drift failure mode the milestone exists to close.

---

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| `Package.resolved` **v3** written into the package checkout | Format v3 (Xcode 15.3+ / tools 5.10+) | Carries the host's pins into the per-package build | VERIFIED (A/E/G) as the *only* thing that actually changes which version is built. Stale `originHash` is tolerated, so a synthesized file works. |
| `xcodebuild -onlyUsePackageVersionsFromResolvedFile` | Xcode 11+, present in **26.3** | Turns an unsatisfiable pin into a hard error | VERIFIED (H1). Without it, drift is silent (H3). Converts a correctness bug into a build failure spm-cache can report. |
| `xcodebuild -clonedSourcePackagesDirPath <dir>` | Xcode 11+, present in **26.3** | Points the build's SwiftPM workspace at an existing checkout tree | VERIFIED (G) that a SwiftPM `.build/` directory is layout-compatible and is reused. Enables one shared, host-pinned dependency tree across all per-package builds. |
| `swift package resolve --force-resolved-versions` | Swift 5.x–**6.2.4** | Pins the *umbrella* resolve to the host's pins | VERIFIED (D) that it errors rather than drifting. Makes the umbrella resolution host-faithful at the source. |

### Exact Flag Reference (from `xcodebuild -help`, Xcode 26.3 — VERIFIED)

| Flag (exact spelling) | Official help text | What it actually does |
|---|---|---|
| `-onlyUsePackageVersionsFromResolvedFile` | "prevents packages from automatically being resolved to versions other than those recorded in the `Package.resolved` file" | **Strictness.** Errors if the resolved file cannot be satisfied. Does *not* pin. |
| `-disableAutomaticPackageResolution` | *identical string* | **Alias.** Same error, same behaviour (H1≡H2). Pick one; do not pass both. |
| `-skipPackageUpdates` | "Skip updating package dependencies from their remote" | **Network.** This — not the two above — is the flag that suppresses remote fetches. |
| `-clonedSourcePackagesDirPath PATH` | "specifies the directory to which remote source packages are fetch or expected to be found" | Relocates `checkouts/` + `artifacts/` + `workspace-state.json`. |
| `-packageCachePath PATH` | "path of caches used for package support" | Shared *repository/manifest* cache — **not** the checkouts. Equivalent to `swift package --cache-path`. Irrelevant to version selection. |
| `-disablePackageRepositoryCache` | "disable use of a local cache of remote package repositories" | Forces fresh clones. Slows builds; no fidelity benefit. |
| `-resolvePackageDependencies` | "resolves any Swift package dependencies referenced by the project or workspace" | Resolve-only action; useful to pre-resolve and inspect before building. |

**No Xcode 26-specific replacement exists.** All of the above are still the current spelling in 26.3; nothing is deprecated and no newer equivalent was introduced.

### SwiftPM Equivalents (from `swift package --help`, Swift 6.2.4 — VERIFIED)

The help output lists these as **one flag with three spellings**:

```
--force-resolved-versions, --disable-automatic-resolution, --only-use-versions-from-resolved-file
                        Only use versions from the Package.resolved file and
                        fail resolution if it is out-of-date.
```

So the question "which one pins vs which prevents network" resolves to: **they are the same flag**, they enforce strictness, and `--skip-update` is the separate network-suppression flag.

### `Package.resolved` Format & Location

| Format | Introduced | Distinguishing key | Notes |
|--------|-----------|--------------------|-------|
| v1 | SwiftPM 4 | `object.pins[].package` + `repositoryURL` | Legacy; not written by Xcode 26 |
| v2 | Xcode 13 / tools 5.6 | top-level `pins[]`, `identity`, `kind`, `location` | Still readable |
| **v3** | Xcode 15.3 / tools **5.10** | adds top-level **`originHash`** | What Xcode 26.3 writes — confirmed against this repo's own `tools/spm-cache-proxy/Package.resolved` |

`originHash` is a SHA-256 over the root manifest (plus any local path-dependency manifests) `[MEDIUM — doc]`. **VERIFIED that it is not enforced:** experiments A, B and E all honored a pin file whose `originHash` no longer matched the manifest. Writing a synthesized `Package.resolved` into a checkout is therefore workable in practice.

**Locations:**

| Context | Path |
|---------|------|
| Raw SwiftPM package (what spm-cache builds) | `<pkg>/Package.resolved` ← **the one that matters here** |
| Package opened in Xcode | `<pkg>/.swiftpm/xcode/package.xcworkspace/xcshareddata/swiftpm/Package.resolved` |
| App workspace | `<App>.xcworkspace/xcshareddata/swiftpm/Package.resolved` |

spm-cache builds a *checkout directory containing `Package.swift`*, so the **package-root path is the correct one**. The `.swiftpm/xcode/...` path only applies once an `.xcworkspace` is involved.

---

## Recommended Approach

**Seed the host's pins at the umbrella, then propagate them into every per-package build, and fail loudly on conflict.**

Three composable steps, in dependency order:

1. **Make the umbrella resolution host-faithful.** Before `swift package resolve` in `checkout_resolver.rb:24`, copy the host app's `Package.resolved` to `{umbrella_dir}/Package.resolved`, then resolve with `--force-resolved-versions`. Today the umbrella resolves *freely* — it is derived from the host lockfile but SwiftPM is free to pick different versions. This step removes that gap at the source.
2. **Propagate to each per-package build.** Write the umbrella's resolved pin set into `{pkg_dir}/Package.resolved` before `xcodebuild`. This is what makes ExyteChat see MediaPicker 3.3.2 instead of its own committed 3.2.4.
3. **Add the guard rail.** Append `-onlyUsePackageVersionsFromResolvedFile` to the `xcodebuild` invocation so a genuinely unsatisfiable pin (H1) fails the build instead of silently drifting (H3).

Step 3 without steps 1–2 would just make current builds fail. Steps 1–2 without step 3 would fix the common case but leave drift silent. Ship them together.

### Why the ExyteChat symptom is a correctness bug, not cosmetic

Under `BUILD_LIBRARY_FOR_DISTRIBUTION=YES` (already applied at `build.rb:411`), the cached `ExyteChat.xcframework` ships a `.swiftinterface` that carries `import MediaPicker` as part of its public contract. That interface is **re-typechecked at consumer compile time** against whatever `MediaPicker` module is on the search path — the host's 3.3.2. If ExyteChat's interface was emitted against 3.2.4's API surface, any signature that changed between the two fails to typecheck in the consumer, not in the cached build. That is why the failure surfaces late and why "it built fine" is not evidence of correctness.

---

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| Write `Package.resolved` into the checkout | **Build via the umbrella's own workspace** instead of the isolated checkout | Structurally the cleanest ("one resolution, one graph"), but Xcode auto-generates schemes **only for the root package's own products** — dependency packages get no scheme. `resolve_scheme` (`build_pipeline.rb:189`) depends on per-package schemes, so this needs a scheme-synthesis mechanism that does not exist today. Revisit only if per-checkout pinning proves insufficient. |
| Write `Package.resolved` into the checkout | `-clonedSourcePackagesDirPath {umbrella}/.build` (shared tree) | Worth adding *alongside* the resolved file — VERIFIED (G) that the layouts are compatible. Saves re-cloning every transitive dep per package. **See the sharing hazard below.** |
| Write `Package.resolved` into the checkout | Rewrite the checkout's `Package.swift` to use `.package(path:)` overrides | Path dependencies "do not enforce version constraints" `[MEDIUM — Context7 /swiftlang/swift-package-manager]`, so this *guarantees* the exact host source tree. But it means parsing and rewriting arbitrary third-party manifests (conditional deps, traits, platform predicates). Far more fragile. Reserve as an escape hatch for packages whose manifest genuinely cannot admit the host version. |
| Write `Package.resolved` into the checkout | `swift package edit <name> --path <dir>` | Same override effect without editing the manifest `[MEDIUM — Context7]`. Cleaner than manifest rewriting, but adds per-dependency state to the checkout and is not exercised by `xcodebuild`. Prototype before committing. |

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| **SwiftPM mirrors** (`swift package config set-mirror --original … --mirror …`) | Mirrors map a **URL/identity → URL/identity** only. They carry **no version information**, so they cannot pin a transitive version — the exact thing this milestone needs. `[MEDIUM — Context7]` | `Package.resolved` propagation |
| `--replace-scm-with-registry` / `--use-registry-identity-for-scm` | Registry transformation, not version pinning. Requires a package registry the project does not have. Adds a network dependency and a whole new failure surface. | `Package.resolved` propagation |
| `-packageCachePath` as a fidelity lever | It is the shared *repository/manifest* cache, not the checkout tree. Changing it affects download reuse, never version selection. | `-clonedSourcePackagesDirPath` |
| Passing **both** `-onlyUsePackageVersionsFromResolvedFile` and `-disableAutomaticPackageResolution` | VERIFIED aliases (H1≡H2). Passing both is noise that implies a distinction that does not exist. | Pick `-onlyUsePackageVersionsFromResolvedFile` (more self-describing) |
| Relying on `originHash` to detect staleness | VERIFIED not enforced (A/B/E). It also updates lazily — only written when the graph changes `[MEDIUM — swift-package-manager#7644]`. | Compare pin sets directly |
| Continuing to build with **no** resolution flag | VERIFIED (H3) to silently build the wrong version and report success. | `-onlyUsePackageVersionsFromResolvedFile` |

### Sharing Hazard — must be designed around

VERIFIED in experiment G: when `-clonedSourcePackagesDirPath` points at a pre-populated tree whose checkout is at a different version than the resolved file, xcodebuild **re-checks out the git working copy in place** (`Checking out 1.2.0 of package 'swift-argument-parser'`).

spm-cache builds **inside** `{umbrella}/.build/checkouts/<slug>` (`installer/build.rb:120` → `build_pipeline.rb`, `cwd: @pkg_dir` at `build.rb:80`). If the shared clone dir is that same tree, a build of package X can re-checkout the working copy of package Y — potentially the directory a later build will use, or the one currently being built.

This is **benign iff every per-package build is handed the identical host pin set**, because then every re-checkout converges on the same revision and is idempotent after the first. It is **actively dangerous** if pin sets differ per build. Either commit to one uniform pin set, or give each per-package build its own clone dir and accept the re-clone cost.

---

## Integration Points Against Existing Code

| File:line | Current state | Change needed |
|-----------|---------------|---------------|
| `lib/spm_cache/spm/checkout_resolver.rb:24` | `Core::Sh.run("swift package resolve", cwd: @config.umbrella_dir)` | Seed `{umbrella_dir}/Package.resolved` from the host's resolved file first; add `--force-resolved-versions`. Note `installer.rb:240` `retry_umbrella_resolve_after_enrichment` regenerates the umbrella from scratch — the seeding must be re-applied on that path too. |
| `lib/spm_cache/spm/build_pipeline.rb:33` | `run(name:, pkg_dir:, destinations:, out_dir:, library_evolution:)` | Add a `resolved_file:` (or `host_pins:`) keyword. Both `run` **and** `run_with_scheme` (`:126`) construct `Buildable` and must thread it through — the fallback path is the one vendored-`.xcodeproj` packages actually take. |
| `lib/spm_cache/spm/build.rb:98` `build_command` | Builds the `xcodebuild` string; no resolution flags | Append `-onlyUsePackageVersionsFromResolvedFile`. Consider `-clonedSourcePackagesDirPath`. |
| `lib/spm_cache/spm/build.rb:74` `xcodebuild` | Already does `FileUtils.chmod_R("u+w", @pkg_dir)` | **Free win** — checkouts are mode 444 after `swift package resolve` (see the DeviceKit comment at `:59`). The existing chmod already makes the checkout writable, so writing `Package.resolved` into it needs no new permission handling. Write *after* the chmod. |
| `lib/spm_cache/installer/build.rb:128` | Call site of `SPM::BuildPipeline.run` | Pass the umbrella pin set through. |
| `lib/spm_cache/core/config.rb:72` | `umbrella_dir` = `sandbox/packages/umbrella` | The umbrella's `Package.resolved` lives at `{umbrella_dir}/Package.resolved`; its checkouts at `{umbrella_dir}/.build/checkouts`. |

**Cache-key consequence (out of scope to fix, in scope to notice):** the cache key does not currently incorporate the transitive pin set. Two host apps pinning different MediaPicker versions would collide on the same `ExyteChat.xcframework`. Content-addressed keys are deferred to v0.5 per PROJECT.md; until then this is a known sharp edge worth a note rather than a fix.

---

## Version Compatibility

| Component | Compatible With | Notes |
|-----------|-----------------|-------|
| `Package.resolved` v3 | Xcode 15.3+ / swift-tools 5.10+ | Xcode 26.3 reads v1/v2/v3; only writes v3 |
| `-onlyUsePackageVersionsFromResolvedFile` | Xcode 11 → **26.3** | Stable spelling; no deprecation in 26.x |
| `--force-resolved-versions` | Swift 5.x → **6.2.4** | Aliased to `--disable-automatic-resolution` / `--only-use-versions-from-resolved-file` |
| SwiftPM `.build/` ↔ Xcode `SourcePackages/` | Xcode 26.3 | VERIFIED same shape: `checkouts/`, `artifacts/`, `repositories/`, `workspace-state.json` |

---

# PART B — Release Automation

## Diagnosis

Established from the live repo today:

| Fact | Evidence |
|------|----------|
| `TAP_REPO_TOKEN` secret **exists**, updated `2026-08-09` | `gh secret list --repo phuongddx/spm-cache` |
| Destination repo `phuongddx/homebrew-spm-cache` is **PUBLIC** | `gh repo view --json visibility` → `PUBLIC` |
| Workflow uses it at `update-tap.yml:29` for `actions/checkout` then plain `git push` | file read |

A present secret returning "Bad credentials" means the **token behind it was revoked, expired, or auto-deleted** — not that wiring is missing. The most likely cause: **GitHub automatically removes classic PATs unused for a year** `[MEDIUM — GitHub Docs]`. A tap-update token fires only on release, so a quiet year is entirely plausible.

Because the destination repo is **public**, the minimum classic scope is `public_repo` — **not** the broader `repo` that most tutorials reach for.

## Options

| Option | Exact permission strings | Expiry | Verdict |
|--------|--------------------------|--------|---------|
| **Classic PAT** | `public_repo` (sufficient — destination is public). `repo` only if it ever goes private. | Can be no-expiry, but **auto-deleted after 1 year unused** | Works; same failure recurs |
| **Fine-grained PAT** | `Contents: Read and write` + `Metadata: Read`, scoped to `phuongddx/homebrew-spm-cache` | **Max 366 days** | Least-privilege, but guaranteed to expire — worse for a low-frequency release job |
| **GitHub App installation token** ⭐ | App permission `Contents: Read and write`; mint via `actions/create-github-app-token@v3` with `owner` + `repositories: homebrew-spm-cache` | 1 hour, minted per run — **never expires** | **Recommended.** Removes the recurring-expiry class of failure entirely. |
| **Deploy key** | SSH key with **"Allow write access"** on `homebrew-spm-cache`; private half as a secret | No expiry | Simplest zero-maintenance option; repo-scoped by construction. Requires switching `actions/checkout` to SSH and cannot open PRs. |
| `peter-evans/create-pull-request@v8` | Still needs one of the above for cross-repo auth | — | Orthogonal — changes push→PR, does not solve auth. Unnecessary for a single-file formula bump. |
| Default `GITHUB_TOKEN` | — | — | **Cannot work.** Scoped to the current repository only. |

`actions/create-github-app-token@v3` and `peter-evans/create-pull-request@v8` are the current majors `[MEDIUM — GitHub Docs / marketplace]`.

## Recommendation

**GitHub App installation token**, with **deploy key** as the low-ceremony fallback.

The App removes the entire recurring-expiry failure mode: tokens are minted per run and cannot go stale. The cost is one-time setup (register App → grant `Contents: write` → install on the tap repo → store App ID + private key). A deploy key gets 80% of the benefit for 20% of the setup, at the price of being SSH-only and PR-incapable — acceptable for a job that only rewrites one formula file.

**Explicitly not recommended:** re-minting a classic PAT. It restores the status quo *including* the one-year auto-deletion that most likely caused this outage.

### Unrelated latent bug found while reading the workflow

`update-tap.yml:38-40` uses GNU `sed -i "s|…|"` with no backup suffix. This is correct on `ubuntu-latest` and will keep working — but it is worth a `[ci]` note that this workflow must never be moved to a `macos-*` runner, where BSD `sed -i` requires an explicit argument and would fail. Not part of this milestone; recording it so it is not rediscovered later.

---

## Sources

**Empirical (HIGHEST confidence — executed on this machine, 2026-08-27, Xcode 26.3 / Swift 6.2.4):**
- Experiments A–H above — reproduction package at `Alpha` → `swift-argument-parser`
- `xcodebuild -help`, `swift package --help`, `swift build --help` — exact flag spellings and help strings
- `.build/` layout inspection of `tools/spm-cache-proxy`
- `gh secret list`, `gh repo view` against the live repos

**Curated docs (MEDIUM):**
- Context7 `/swiftlang/swift-package-manager` — mirrors (`PackageConfigSetMirror.md`), path dependencies (`AddingDependencies.md`), `swift package edit` (`EditingDependencyPackage.md`)
- [GitHub Docs — Managing personal access tokens](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens) — fine-grained max 366 days; classic auto-removal after 1 year unused; `Contents: write`
- [GitHub Docs — OAuth scopes](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/scopes-for-oauth-apps) — `public_repo` vs `repo`
- [GitHub Docs — Authenticated API requests with a GitHub App in Actions](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/making-authenticated-api-requests-with-a-github-app-in-a-github-actions-workflow) — `actions/create-github-app-token@v3`

**Community (MEDIUM — corroborating only, not load-bearing):**
- [Apple Developer Forums — purpose of `originHash`](https://developer.apple.com/forums/thread/755995) — corroborates the non-enforcement independently VERIFIED in experiments A/B/E
- [swift-package-manager#7644 — `originHash` should update more eagerly](https://github.com/swiftlang/swift-package-manager/issues/7644) — lazy update behaviour
- [actions/create-github-app-token](https://github.com/actions/create-github-app-token) — `owner`/`repositories` scoping inputs
- [peter-evans/create-pull-request releases](https://github.com/peter-evans/create-pull-request/releases) — v8 current

---
*Stack research for: SwiftPM build-graph fidelity + cross-repo GitHub Actions release automation*
*Researched: 2026-08-27*
