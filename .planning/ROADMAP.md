# Roadmap: spm-cache

## Milestones

- ✅ **v0.3.0 Mixed Cycle** — Phases 1–5 (shipped 2026-08-24)
- 🚧 **v0.4.0 Build Fidelity & Release Automation** — Phases 6–11 (in progress)

## Overview

v0.4.0 closes the only known correctness failure in the product: a cached `.xcframework` can be
compiled against transitive dependency versions the host app never resolved. Research established
this is **two independent drift mechanisms feeding one symptom**, and the dominant one is a
never-refreshed `spm-cache.lock` — so the milestone starts by making the lockfile tell the truth
(Phase 6), then seeds each per-package build from the host's resolved graph (Phase 7), then proves
what was actually realized and records it as provenance (Phase 8), then makes that provenance
invalidate stale artifacts so the fix reaches existing users (Phase 9), then pins the contract with
hermetic regression coverage (Phase 10). Phase 11 — repairing the Homebrew release path — shares no
file and no state with any of that and can be scheduled anywhere in the cycle.

**Granularity:** Standard · **Mode:** Horizontal Layers · **Created:** 2026-08-27

## Phases

**Phase Numbering:**

- Integer phases (6, 7, 8): Planned milestone work
- Decimal phases (7.1, 7.2): Urgent insertions (marked with INSERTED)

Numbering continues from v0.3.0 (which ended at Phase 5) — it does not restart.

<details>
<summary>✅ v0.3.0 Mixed Cycle (Phases 1–5) — SHIPPED 2026-08-24</summary>

- [x] Phase 1: Test CI Foundation (2/2 plans) — completed 2026-08-24
- [x] Phase 2: Diagnostics Command (2 plans) — completed 2026-08-24 (verification refreshed same day)
- [x] Phase 3: Project Bootstrap (2 plans) — completed 2026-08-24
- [x] Phase 4: CI GitHub Action (2 plans) — completed 2026-08-24
- [x] Phase 5: Auto-Sync Watcher (2 plans) — completed 2026-08-24

Full phase detail: `milestones/v0.3.0-ROADMAP.md` · Audit: `milestones/v0.3.0-MILESTONE-AUDIT.md`

</details>

### 🚧 v0.4.0 Build Fidelity & Release Automation (Phases 6–11)

**Milestone Goal:** Make cached builds faithful to the host app's resolved dependency graph, and
repair the Homebrew release path so shipping stops requiring manual steps.

- [ ] **Phase 6: Graph Authority — Lockfile Reconciliation** - The lockfile spm-cache builds from always describes the host's *current* resolved graph
- [x] **Phase 7: Host-Faithful Checkout Seeding** - Every per-package build resolves transitive deps from the host graph, not its own requirements (completed 2026-08-29)
- [x] **Phase 8: Drift Read-Back, Fidelity Status & Provenance** - Realized versions are read back, compared, reported, and recorded per artifact (completed 2026-08-29)
- [x] **Phase 9: Cache Identity & Invalidation** - Provenance mismatch (or absence) is a cache miss, so existing users actually receive the fix (completed 2026-08-29)
- [x] **Phase 10: Fidelity Regression Coverage** - Hermetic specs make transitive-version drift unable to silently return (completed 2026-08-30)
- [ ] **Phase 11: Homebrew Release Automation** - Releases publish the formula unattended, and every failure in that path is loud

## Phase Details

### Phase 6: Graph Authority — Lockfile Reconciliation

**Goal**: The lockfile spm-cache builds from always describes the host project's *current* resolved graph, so no later fidelity decision is made against an abandoned first-run snapshot.
**Depends on**: Nothing (v0.4.0 entry phase; continues from Phase 5)
**Requirements**: FID-01, FID-06, DIAG-01
**Success Criteria** (what must be TRUE):

  1. After a non-fast-path run on a project whose `Package.resolved` has changed, re-running `DiffDetector` returns an **empty** diff — every package's lock `version`/`revision` equals the host's resolved value.
  1a. The host `Package.resolved` that reconciliation reads is the **canonical** `project.xcworkspace/xcshareddata/swiftpm/Package.resolved` — proven on a fixture containing a competing nested copy that `Dir.glob` would otherwise return first (amended 2026-08-27: FID-06; without this, criterion 1 passes vacuously with both sides agreeing on a stale file).

  2. Reconciling versions never costs metadata: each package's enriched `products[]` survives the refresh intact, and a project that was working before the run still resolves and builds after it.
  3. `spm-cache doctor` reports whether `spm-cache.lock` agrees with the host `Package.resolved`, naming each drifted package, without running a build.
  4. The motivating stale-transitive release build on the reference 59–70 package project is reproduced, then re-run after reconciliation: either it no longer links a transitive version older than the host's pin, or the residual cause is attributed to isolated re-resolution and recorded.

**Measurements (blocking)**:

  - **M1** — run read-only steps 0–3 FIRST (under a minute): the wrong-file finding makes "stale locator" the leading hypothesis on `main`, which may change how much of the field failure Phase 6 closes. Then reproduce the stale-transitive release build on the real 59–70 package project and attribute the relative contribution of the lockfile chain vs isolated per-package re-resolution. This is the **first work of the phase** and **blocks Phase 7's design lock**.

**Research**: Done 2026-08-27 (`06-RESEARCH.md`) — run despite the roadmap's original "not needed" call because `nyquist_validation` derives VALIDATION.md from it. It paid for itself: found the stale-locator defect (FID-06) that would have made criterion 1 vacuous, confirmed `:warn` does not exit 1 (`doctor.rb:42`), and identified local/path packages as the top drop-rule regression risk.
**Plans:** 5/5 plans executed — 4 in 3 waves, plus one gap-closure plan in wave 5 (from `06-VERIFICATION.md`)

- [x] 06-01-PLAN.md — M1 reproduction and per-package attribution (blocking, first work of the phase)
- [x] 06-02-PLAN.md — FID-06: canonical `Package.resolved` locator, end-to-end reconciliation tracer, five glob sites collapsed
- [x] 06-03-PLAN.md — FID-01: full reconciliation semantics (drop / add / preserve / degrade) and success criterion 1
- [x] 06-04-PLAN.md — DIAG-01: static `lock_graph_fidelity` doctor check, doctor assertion updates, false-premise comment correction
- [x] 06-05-PLAN.md — gap closure: one host-graph resolver per run, so success criterion 1 also holds on the parent-directory-tier project shape

### Phase 7: Host-Faithful Checkout Seeding

**Goal**: Every per-package build — the metadata `describe` reads and the binary that gets cached — resolves its transitive dependencies from the host app's resolved graph rather than from that package's own requirements, at no cost to build time or disk.
**Depends on**: Phase 6 (seeding from a stale source produces a confidently wrong result)
**Requirements**: FID-02, FID-05, PERF-01
**Success Criteria** (what must be TRUE):

  1. A package built by spm-cache checks out the same transitive versions the host app resolved — both the products/targets reported by `swift package describe` and the versions linked into the resulting `.xcframework` match the host's `Package.resolved`.
  2. Vendored-`.xcodeproj` packages, which ignore `Package.resolved` entirely, appear in output as an explicit *not-graph-pinned* category rather than being silently counted as pinned.
  3. An aborted, failed, or interrupted build leaves no checkout carrying a synthetic resolved file, and a concurrent `watch` cycle cannot delete checkouts out from under an in-flight build.
  4. With seeding disabled (default), behavior is byte-for-byte identical to v0.3.0 — the v0.2.x edge classes build exactly as they did before.
  5. A cached build of the reference project shows **no wall-clock or disk regression** versus v0.3.0; if the verbatim pin superset regresses, the narrowed pin closure is adopted and re-measured until it does not.

**Measurements (blocking)**:

  - **M4** — does xcodebuild write back realized versions on the `run_with_scheme` / vendored-`.xcodeproj` path? **Early probe, before the design is locked** — it is the sole falsifier of the no-flag (`-onlyUsePackageVersionsFromResolvedFile`-off) design, and if read-back has no reliable source on a path, that path must be reported as *not graph-pinned*.
  - **M2** — run seeding in **report-only mode** against the real project and count packages reporting `resolution-incompatible`. Produced here, **consumed by Phase 8's policy commitment**; a high count is a rescope trigger (e.g. a dated exclusion of macro packages from graph pinning with a v0.5 follow-up).
  - **M3** — wall-clock and disk delta from pin-list fan-out (verbatim superset vs minimal closure). Gates PERF-01 and the narrowing decision; start verbatim, measure, narrow only if the benchmark demands it.

**Research**: Done 2026-08-27 (compressed into `07-CONTEXT.md` from milestone-level `research/ARCHITECTURE.md` §1-3,9 and `research/PITFALLS.md` Pitfall 6/9/11/15, both empirically verified on Xcode 26.3 — see 07-CONTEXT.md header for why no fresh phase-level research was spawned).
**Plans**: 2 plans across 2 waves

- [x] 07-01-PLAN.md — SPM::ResolvedGraph (source_for/seed!/restore!) + BuildPipeline seed-before-describe wiring + vendored-.xcodeproj classification (FID-02, FID-05)
- [x] 07-02-PLAN.md — shared -clonedSourcePackagesDirPath + process-level watch/build lock + PERF-01 benchmark gate

### Phase 8: Drift Read-Back, Fidelity Status & Provenance

**Goal**: Every cached artifact carries a verifiable record of the graph it was actually built against, and any package whose realized versions differ from the intended pins is reported instead of silently shipped — seeding without this is strictly worse than today.
**Depends on**: Phase 7 (must ship in the same release as Phase 7)
**Requirements**: FID-03, FID-04, CACHE-01, DIAG-02
**Success Criteria** (what must be TRUE):

  1. When xcodebuild silently discards a seeded pin and re-resolves, the run **reports the drift** — the comparison is against separately retained intended pins, never against the file spm-cache itself wrote.
  2. A package whose declared requirements genuinely cannot satisfy the host graph builds from source with a distinct `resolution-incompatible` status; the build succeeds, never hard-fails, and `ignore_build_errors` cannot suppress or mask that status.
  3. Each cached `.xcframework` has a provenance sidecar recording the **realized** pins plus spm-cache version, config, and destination set; replacing a prebuilt binary-target artifact removes the stale sidecar rather than leaving it to lie.
  4. `spm-cache build` output and `cache list` name each package's fidelity status (`host-pinned` / `resolution-incompatible` / `not-graph-pinned`) — no package's resolution outcome is unauditable.

**Measurements (blocking)**:

  - **M2 (consumed)** — the `resolution-incompatible` count from Phase 7's report-only run gates the policy commitment locked here. Confirm the count before committing; rescope if it is large.

**Research**: Done 2026-08-29 (`08-RESEARCH.md`) — run despite this line's original "not needed" call
because the roadmap's own claim about `Core::Diagnostics`/`GraphEntry.Status` reuse proved half
misleading (neither is reachable from `build`/`cache list` output — both are doctor-only or
Swift-side-only); the `.shims.json` sidecar-pattern reuse was confirmed correct.
**Plans**: 2 plans across 2 waves
**Wave 1**

- [x] 08-01-PLAN.md — drift read-back, resolution-incompatible classification, provenance sidecar write/cleanup, build-output status line (FID-03, FID-04, CACHE-01, DIAG-02 build-output half)

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 08-02-PLAN.md — `cache list` fidelity-status column, fixes pre-existing sidecar-as-spurious-entry bug (DIAG-02 cache-list half)

### Phase 9: Cache Identity & Invalidation

**Goal**: Users on an existing cache actually receive the fidelity fix — an artifact built against a graph that no longer matches the host's is treated as a miss and rebuilt, and two projects on different versions stop sharing one binary.
**Depends on**: Phase 8 (must ship in the same release as Phases 7–8; without it the fix reaches zero existing users)
**Requirements**: CACHE-02, CACHE-03
**Success Criteria** (what must be TRUE):

  1. Upgrading from v0.3.0 without clearing `~/.spm-cache` produces a rebuild — an artifact with no provenance is a **miss**, not a hit.
  2. Changing a transitive version in the host `Package.resolved` invalidates only the artifacts whose recorded pins actually disagree; an unrelated bump elsewhere in a 70-package graph does not empty the cache.
  3. Two projects resolving the same package at different versions no longer serve each other's artifact.
  4. `cache clean` leaves no orphaned provenance sidecars behind.
  5. A rebuild triggered by a graph change does not reuse DerivedData modules or resource bundles produced against the previous graph.

**Research**: Done 2026-08-29 (`09-RESEARCH.md`) — traced the actual call path (`Cache.swift`'s
`hit(module:)` / `ProxyGenerator.swift:119`) rather than relying on CONTEXT.md's description
alone; found the Class E cache-defeat hazard (Pattern 3) and the `Installer::Use` fast-path
version-awareness gap (Pitfall 2), both incorporated into the plan below.
**Plans**: 3 plans across 2 waves

- [x] 09-01-PLAN.md — CACHE-02 core: provenance-aware `hit()`, Class E safety net (Pattern 3), real-binary SC1/SC2/SC3 proof
- [x] 09-02-PLAN.md — `spm-cache use` fast-path version gate (default-command SC1 closure) + CACHE-03 `cache clean` orphan-sidecar sweep
- [x] 09-03-PLAN.md — SC5 empirical verification runbook (DerivedData staleness, human-check at end-of-phase)

### Phase 10: Fidelity Regression Coverage

**Goal**: The fidelity contract is pinned by hermetic specs, so transitive-version drift cannot silently return in a later release — the v0.3.0 lesson ("an implemented feature is not a done phase") applied as executable coverage.
**Depends on**: Phases 7–9 (fixtures can be authored in parallel with them)
**Requirements**: TEST-01, TEST-02, TEST-03
**Success Criteria** (what must be TRUE):

  1. A regression spec **fails** if an out-of-range pin is silently re-resolved instead of being detected and reported.
  2. A coverage assertion **fails** if any package in `Package.resolved` lands in zero or in more than one bucket (pinned / ignored / excluded / plugin-only / resolution-incompatible / not-graph-pinned) — none may be silently absent.
  3. The v0.2.x edge-class fixture matrix passes unchanged: binary target (Class E), macro with a narrow `swift-syntax` pin, vendored `.xcodeproj`, plugin-only, transitive-only, resource bundle, private Clang shim, and product≠target rename.
  4. The whole suite runs hermetically on the existing `Core::Sh` / `Desc` / `Buildable` seams — no network, no real `xcodebuild` — and is green on every leg of the Ruby 3.1–3.3 CI matrix.

**Research**: Done 2026-08-29 (`10-RESEARCH.md`, HIGH confidence, pattern-reuse) — run despite the roadmap's original "not needed" call because the six TEST-02 buckets span TWO production surfaces (3 statuses from Ruby `report_fidelity` sidecars; ignored/excluded/plugin decided by the Swift ProxyGenerator into graph.json), so the partition meta-spec needs a hybrid observation route. Pattern map: `10-PATTERNS.md`.
**Plans**: 3/3 plans executed across 1 wave (the three spec files are file-disjoint — fully parallel)

- [x] 10-01-PLAN.md — TEST-01: `spec/fidelity_drift_regression_spec.rb` — drift regression both directions, both injection sources (read-back + provenance-sidecar), SC4 default-deny guard, fail-first mutation proofs
- [x] 10-02-PLAN.md — TEST-02: `spec/fidelity_bucket_partition_spec.rb` + kitchen-sink fixture — hybrid partition meta-spec (tier-1 fidelity legs + tier-3 graph legs), completeness + disjointness both arms fail-first
- [x] 10-03-PLAN.md — TEST-03: `spec/fidelity_edge_matrix_spec.rb` — all 8 v0.2.x edge classes incl. the two no-analog shapes (macro `swift-syntax` pin, resource bundle), existing specs untouched

### Phase 11: Homebrew Release Automation

**Goal**: Publishing a release updates the Homebrew formula unattended and verifiably, and every failure mode in that path is loud rather than green — no human step, no expiring human-owned credential, no silently-published broken formula.
**Depends on**: Nothing — **fully independent** of Phases 6–10 (no shared files, no shared state, no ordering constraint). Schedulable first, last, or in parallel; highest value-per-hour in the milestone.
**Requirements**: REL-04, REL-05, REL-06, REL-07, REL-08, REL-09
**Success Criteria** (what must be TRUE):

  1. Publishing a GitHub release updates `phuongddx/homebrew-spm-cache` with no manual intervention and without any human-owned expiring credential in the path.
  2. A tarball that is not yet servable (404 / HTML error page) **fails the workflow** instead of hashing an error page into the formula.
  3. A commit or push failure, a zero-match substitution, or an over-broad substitution **fails the workflow** — no `|| exit 0` path and no unanchored edit can report success.
  4. A post-publish job installs the published formula on macOS and asserts `spm-cache --version` matches the released tag; a failure raises a visible notification rather than passing unnoticed.
  5. `workflow_dispatch` with a `tag` input re-runs the publish for a transient failure, without cutting or re-publishing a release.

**Operator gate**: The durable-token fix requires a one-time human step outside the repo — create a GitHub App owned by `phuongddx` (`Contents: read & write` + `Metadata: read`, installed on `homebrew-spm-cache` **only**, never `workflow` scope) and store its app id + private key as repo secrets. Autonomous execution pauses here. A deploy key with write access is the accepted lower-ceremony substitute.
**Research**: Done 2026-08-29 (`11-RESEARCH.md`, HIGH confidence — amended 2026-08-30 from the original "not needed" call after discuss-phase surfaced the operator gate): found the `spm-cache --version` exit-1 blocker (CLAide default-subcommand routing — REL-08 cannot pass without a 3-line `Main.run` intercept), verified the live tap formula has **no `version` stanza** (the current version sed is a silent zero-match no-op), and confirmed `GITHUB_REF_NAME` is the dispatch ref, not the tag, under `workflow_dispatch`.
**Plans**: 2/3 plans executed across 2 waves
**Wave 1** *(11-01 and 11-02 are file-disjoint — fully parallel)*

- [x] 11-01-PLAN.md — `spm-cache --version` intercept via TDD (REL-08 CLI half)
- [x] 11-02-PLAN.md — `update-tap.yml` rewrite (2 triggers, 2 jobs, loud failures, anchored edits) + structural spec (REL-04..09)

**Wave 2** *(blocked on Wave 1 + the operator gate)*

- [ ] 11-03-PLAN.md — operator gate (GitHub App + `TAP_APP_ID`/`TAP_APP_PRIVATE_KEY` secrets) + live idempotent dispatch dry-run (tag v0.3.0)

## Phase Ordering Rationale

- **6 → 7 → 8 → 9 is a hard chain.** Phase 7 is unverifiable against the stale graph Phase 6 fixes; Phase 8 is the only proof Phase 7 worked; Phase 9 is the only way Phases 7–8 reach a user.
- **8 and 9 must ship in the same release as 7.** Shipping pinning alone is exactly xccache's current state — a structural guarantee with no invalidation — and is not a bar worth clearing.
- **Phase 10 depends on 7–9**, but its hermetic fixtures can be authored in parallel with them.
- **Phase 11 parallelizes completely** and is also a good *first* phase if an independent quick win is wanted.
- **Shared clone dir (`-clonedSourcePackagesDirPath`) is folded into Phase 7** as a cost mechanism, gated on M3 rather than shipped unconditionally.

## Progress

**Execution Order:** 6 → 7 → 8 → 9 → 10; 11 anywhere (independent)

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Test CI Foundation | v0.3.0 | 2/2 | Complete | 2026-08-24 |
| 2. Diagnostics Command | v0.3.0 | 2/2 | Complete | 2026-08-24 |
| 3. Project Bootstrap | v0.3.0 | 2/2 | Complete | 2026-08-24 |
| 4. CI GitHub Action | v0.3.0 | 2/2 | Complete | 2026-08-24 |
| 5. Auto-Sync Watcher | v0.3.0 | 2/2 | Complete | 2026-08-24 |
| 6. Graph Authority — Lockfile Reconciliation | v0.4.0 | 5/5 | In Progress|  |
| 7. Host-Faithful Checkout Seeding | v0.4.0 | 2/2 | Complete    | 2026-08-29 |
| 8. Drift Read-Back, Fidelity Status & Provenance | v0.4.0 | 2/2 | Complete    | 2026-08-29 |
| 9. Cache Identity & Invalidation | v0.4.0 | 3/3 | Complete    | 2026-08-29 |
| 10. Fidelity Regression Coverage | v0.4.0 | 3/3 | Complete    | 2026-08-30 |
| 11. Homebrew Release Automation | v0.4.0 | 2/3 | In Progress|  |

## Coverage

**21/21 v0.4.0 requirements mapped across 6 phases ✓** — no orphans, no duplicates (FID-06 added 2026-08-27 by Phase 6 research).

| Phase | Requirements |
|-------|--------------|
| 6 | FID-01, FID-06, DIAG-01 |
| 7 | FID-02, FID-05, PERF-01 |
| 8 | FID-03, FID-04, CACHE-01, DIAG-02 |
| 9 | CACHE-02, CACHE-03 |
| 10 | TEST-01, TEST-02, TEST-03 |
| 11 | REL-04, REL-05, REL-06, REL-07, REL-08, REL-09 |

---
*v0.4.0 roadmap created: 2026-08-27*
