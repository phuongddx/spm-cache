---
gsd_state_version: 1.0
milestone: v0.4.0
milestone_name: Build Fidelity & Release Automation
current_phase: "Phase 6 — Graph Authority: Lockfile Reconciliation (in progress — 2/4 plans)"
current_phase_name: "Graph Authority: Lockfile Reconciliation"
status: in-progress
stopped_at: Completed 06-03-PLAN.md
last_updated: "2026-08-27T08:11:29.520Z"
last_activity: 2026-08-27
last_activity_desc: 06-02 shipped FID-06 canonical Package.resolved locator + lockfile reconciliation (275 examples, 0 failures)
state_head: c55099070be999b87ee016dca8a32bbd067e2961
progress:
  total_phases: 6
  completed_phases: 0
  total_plans: 4
  completed_plans: 3
  percent: 0
---

# Project State: spm-cache

**Initialized:** 2026-08-10
**Current Phase:** Phase 6 — Graph Authority: Lockfile Reconciliation (in progress — 2/4 plans)
**Project Mode:** Horizontal Layers
**Direction:** v0.4.0 Build fidelity (correctness) + release automation

## Project Memory

### What this project is

`spm-cache` (v0.3.0) caches Swift Package Manager dependencies as `.xcframework` binaries via a proxy-package architecture. Ruby gem CLI + Swift companion binary; macOS-only. Distribution today is Homebrew only — the gem is not published on RubyGems (deferred 2026-08-27), which also leaves the GitHub Action non-functional. The v0.4.0 cycle fixes transitive dependency-version drift in cached builds and repairs the Homebrew release automation.

### Key artifacts

- Roadmap: `.planning/ROADMAP.md` (v0.4.0 Phases 6–11, created 2026-08-27)
- Requirements: `.planning/REQUIREMENTS.md` (20 v0.4.0 REQ-IDs, 20/20 mapped)
- Research: `.planning/research/SUMMARY.md` (root-cause model, HIGH confidence)
- Codebase map: `.planning/codebase/` (7 docs, 2026-08-10)
- Design spec: `docs/superpowers/specs/2026-08-10-v0.3.0-watch-init-doctor-design.md` (approved)
- PDR: `docs/project-overview-pdr.md`
- Roadmap history: `docs/project-roadmap.md`
- Competitive analysis: `competitive-analysis-2026-07.html`, `scipio-deepdive-features-2026-07.html`

### v0.4.0 root-cause model — CORRECTED BY M1 FIELD MEASUREMENT (2026-08-27)

**M1 verdict: H-wrongfile 25 · H-lock 0 · H-float 0.** The dominant cause is the **stale-locator
selection** (FID-06), not the never-refreshed lockfile. `Dir.glob(File.join(root,"**/Package.resolved")).find`
returns a git-ignored nested copy (`<root>/X.xcodeproj/X.xcodeproj/...`, 8 pins, 2026-07-12) instead of the
canonical `project.xcworkspace/xcshareddata/swiftpm/Package.resolved` (17 pins, 2026-08-13), because
`S`(0x53) sorts before `p`(0x70). Set arithmetic: lock ∩ picked = 8/8, lock ∩ canonical = 0/17.

H-lock excluded by provenance: the lock holds AnchoredPopup `1.1.3/2fb9d1ac101b`, which appears in **none**
of the 9 committed revisions of the canonical file — so the lock is not a frozen read of the host graph,
it is a faithful read of the wrong file. H-float excluded by construction: all 8 packages are emitted as
exact `revision:` pins, leaving no range to float within.

**FID-01 without FID-06 is actively harmful** — reconciling from the current locator's answer writes the
phantom graph back onto itself, converting a visible non-empty diff into a false green.

Symptom reproduced: 4 packages linked strictly older than host pin (AnchoredPopup 1.1.3<1.2.1,
Kingfisher 8.8.1<8.11.0, libwebp-Xcode 1.5.0<1.6.0, MediaPicker 3.3.2<3.4.2).
Evidence: `.planning/phases/06-graph-authority-lockfile-reconciliation/06-M1-MEASUREMENT.md`

### v0.4.0 root-cause model (as originally researched — superseded by the M1 verdict above)

Cached builds can link transitive dependency versions the host app never resolved. This is **two
independent drift mechanisms**, not one:

1. **DOMINANT — never-refreshed lockfile.** `installer.rb:165-166` early-returns whenever
   `spm-cache.lock` exists, so every package's `version`/`revision` is frozen at first run forever.
   The umbrella is generated from that lockfile (`installer.rb:241`), `Lockfile.swift:118-126`
   converts a held revision into an exact `revision:` pin, `UmbrellaGenerator.swift:73` emits it,
   and `swift package resolve` materializes checkouts at that stale commit. Only this chain explains
   a **downward** pin (older than host). `DiffDetector` detects the change correctly but the diff is
   never applied.

2. **Secondary — fresh upward re-resolution in isolated per-package builds.** No resolved-graph
   parameter exists anywhere in `BuildPipeline.run` → `Buildable#build_command`. Reproduced:
   swift-argument-parser 1.2.0 → 1.8.2, exit 0, no warning.

The original hypothesis ("the isolated build resolves from the package's own committed
`Package.resolved`") is **falsified** — `exyte/Chat` commits no such file (HTTP 404 both canonical
paths), and 0 of 24 surveyed upstream packages commit one.

**Delivery blocker:** `Cache.swift:19-22` `hit(module:)` is a bare name + `fileExists` check against
the global `~/.spm-cache`. Without invalidation, a perfectly correct fix reaches **zero existing
users**. Phases 7, 8 and 9 must ship in the same release.

Field symptom (StressMonitor, ~2026-08-09): `spm-cache build ExyteChat --config=release` links
MediaPicker 3.2.4 while the app resolves 3.3.2.

### Locked scope decisions (2026-08-27)

- Fidelity violation → warn + source fallback, **never hard-fail** (Core Value; all four comparable tools degrade to source)
- Missing provenance ⇒ cache miss (one-time full rebuild) — the only option that delivers the fix to existing users
- `-onlyUsePackageVersionsFromResolvedFile` **not** enabled by default — missing-pin hard failure is structural and broad (test-only deps); opt-in strict mode only
- `~/.spm-cache` partitioning + content-addressed keys stay v0.5; provenance detection is the v0.4.0 floor
- RubyGems publication deferred by user decision — Homebrew stays the only distribution channel
- GitHub Action out of scope this cycle (its `gem install spm-cache` step needs the unpublished gem); broken-window #2 waived, not closed
- Tap token: GitHub App installation token (`actions/create-github-app-token@v3`); classic PAT re-mint rejected — creating/installing the App is an **operator step**, autonomous will pause at Phase 11

## Phase Status

| Phase | Name | Status | Branch |
|-------|------|--------|--------|
| 6 | Graph Authority — Lockfile Reconciliation | In progress (2/4 plans) | gsd/v0.4.0-build-fidelity-release-automation |
| 7 | Host-Faithful Checkout Seeding | Not started | — |
| 8 | Drift Read-Back, Fidelity Status & Provenance | Not started | — |
| 9 | Cache Identity & Invalidation | Not started | — |
| 10 | Fidelity Regression Coverage | Not started | — |
| 11 | Homebrew Release Automation | Not started | — |

Hard chain: 6 → 7 → 8 → 9. Phase 10 depends on 7–9 (fixtures authorable in parallel). Phase 11 is
fully independent and schedulable anywhere.

Research flags: **Phase 7** and **Phase 9** need `--research-phase` during planning; 6, 8, 10, 11 reuse established patterns.

v0.3.0 phase history archived to `.planning/milestones/v0.3.0-phases/`.

## Milestone Re-scope Decision (2026-08-27, post-M1)

**User decision:** finish Phase 6 (the actual fix) and verify it closes the field failure, THEN re-plan
Phases 7–9 with M1's evidence in hand. Rationale: M1 observed Phase 7's target mechanism (isolated
upward re-resolution) **zero times** in the field, and Phases 8–9 largely exist to support Phase 7.
Phase 9's cache invalidation is still required regardless — without it, even the FID-06 fix reaches zero
existing users, since `Cache.swift:19-22` `hit(module:)` is a bare name + `fileExists` check.

Do NOT execute Phases 7–9 against the current roadmap text. Re-plan them after Phase 6 verification.
Phase 11 (release automation) is unaffected — it is fully independent.

## Open Measurements (block design decisions)

| # | Measurement | Runs in | Blocks |
|---|-------------|---------|--------|
| M1 | Reproduce + attribute the stale-transitive release build on the real 59–70 package project | Phase 6 (first work) | Phase 7 design lock |
| M2 | Report-only pinning run: count `resolution-incompatible` packages | Phase 7 (produced) | Phase 8 policy commitment; rescope trigger if high |
| M3 | Wall-clock / disk delta from pin-list fan-out (verbatim superset vs minimal closure) | Phase 7 | PERF-01; narrowing decision |
| M4 | Does xcodebuild write back realized versions on the `run_with_scheme` / vendored-`.xcodeproj` path? | Phase 7 (early probe) | Sole falsifier of the no-flag design |

## Project Reference

See: .planning/PROJECT.md (updated 2026-08-27)

**Core value:** Reduce Xcode clean build times by serving prebuilt SPM dependency binaries transparently, with fallback to source on cache miss.
**Current focus:** v0.4.0 — build fidelity (host-graph-faithful transitive resolution) + Homebrew release automation

## Session Continuity

Last session: 2026-08-27T08:11:29.502Z
Stopped at: Completed 06-03-PLAN.md
Resume file: None

## Performance Metrics

| Plan | Duration | Tasks | Files |
|------|----------|-------|-------|
| Phase 03 P01 | 27min | 3 tasks | 5 files |
| Phase 04 P01 | 660s | 2 tasks | 7 files |
| Phase 05 P01 | ~35 min | 3 tasks | 14 files |
| Phase 06 P01 | 35m | 2 tasks | 2 files |
| Phase 06 P02 | ~25m | 3 tasks | 8 files |
| Phase 6 P03 | ~25m | 3 tasks | 3 files |

## Decisions

- [Phase 03 — Project Bootstrap]: init seeds canonical lock shape (platforms {}) — pure file-I/O; consumer default makes {} identical to omission
- [Phase 03 — Project Bootstrap]: 03-01 doc drift closed via inline ROADMAP amendments (dated 2026-08-24) + phase SUMMARY Documented deviations (a)-(d); amendment-count gate corrected 6→5 (Phase-2 pre-existing count was 3, not 4)
- [Phase 04 — CI GitHub Action]: F1 fixed one-line only (--config= → --default-config= at action.yml:55); spec/action_spec.rb slices each command's own options (def self.options → .concat(super)) so inherited base flags can never satisfy the cross-reference
- [Phase 04 — CI GitHub Action]: criterion 3 recorded as accepted external deviation (gem unpublished — RubyGems 404; action repo unpublished) with 6-item ordered release checklist; gemspec homepage placeholder recorded, not edited
- [Phase 05 — Auto-Sync Watcher]: 05-01: SIGTERM trap + interrupt flush delivered; self-trigger guard shipped as a real defect fix (A1 probe CONFIRMED); polling deviation + fatal/deletion semantics recorded as dated amendments
- [Release checklist, post-milestone 2026-08-27]: item 4/5 (publish action repo, tag v1) had been done 2026-08-11 — *before* the F1 fix (2026-08-24), so the published `phuongddx/spm-cache-action@v1` still had the buggy `--config=` flag. Resynced `action.yml`+`README.md` from `action/` and force-moved `v1` to the corrected commit (`7114ba6`). Added `.github/workflows/smoke.yml` (item 6) as `workflow_dispatch`-only — no scratch backend configured yet, and it can't pass until the gem is on RubyGems regardless. Gemspec homepage (item 1) already fixed (`cf384d6`). Items 2/3 (`gem build`/`gem push`, verify install) explicitly deferred — no RubyGems credentials on this machine (`gem signin` needed first).
- [Roadmap, 2026-08-27]: v0.4.0 numbered Phases 6–11 (continues v0.3.0, does not restart). Lockfile reconciliation ordered FIRST because research overrode ARCHITECTURE.md's "out of milestone" classification — it is the dominant root cause and every later phase is unverifiable against a stale graph.
- [Roadmap, 2026-08-27]: DIAG-01 (static lock-vs-`Package.resolved` doctor check) mapped to Phase 6 rather than the diagnostics phase — it is the user-observable assertion of the invariant Phase 6 establishes, and needs no build.
- [Roadmap, 2026-08-27]: PERF-01 mapped to Phase 7 — pin fan-out is created there and mitigated there (shared `-clonedSourcePackagesDirPath`, gated on M3). A wall-clock regression is a milestone blocker, not a follow-up.
- [Phase 06 — M1, 2026-08-27]: M1 attributes the field failure to **H-wrongfile** — counts H-wrongfile 25, H-lock 0, H-float 0, both 0 — because the locator picks a nested git-ignored 2026-07-12 `Package.resolved` (8 pins, matching the lock 8/8) over the canonical 2026-08-13 file (17 pins, matching the lock 0/17), so 4 packages linked strictly older than their host pin (AnchoredPopup 1.1.3<1.2.1, Kingfisher 8.8.1<8.11.0, libwebp-Xcode 1.5.0<1.6.0, MediaPicker 3.3.2<3.4.2) while the other 17 were never declared; H-float is excluded because all 8 were emitted as exact `revision:` pins with `U == L` byte-for-byte, so Phase 7 still proceeds (D-14) but is demoted to hardening while candidate disambiguation is promoted into Phase 6/FID-01 as blocking — reconciling against the currently-picked file would write the phantom graph back onto itself and turn success criterion 1 into a false green. Evidence: `.planning/phases/06-graph-authority-lockfile-reconciliation/06-M1-MEASUREMENT.md` (live release build withheld: assumption A3 failed — `fb8e773` removed the exyte state from the feature-branch tip — and building the only probative commit would have overwritten the pre-fix artifacts).
- [Phase 06 — 02, 2026-08-27]: FID-06 shipped — Core::PackageResolved resolves the canonical project.xcworkspace/xcshareddata/swiftpm/Package.resolved by exact path (tier 1) ahead of a workspace glob (tier 2), a filtered recursive search (tier 3) and a filtered parent search (tier 4, DiffDetector only), so Dir.glob byte order can no longer select the stale nested copy M1 attributed the field failure to. Recorded as an INTENTIONAL observable behavior change at four of five call sites (research Open Question 1), bounded by keeping the legacy unfiltered recursive search as tier 3 so nothing that previously found a file stops finding one. Exclusion scoping is asymmetric on purpose: the .xcodeproj-component rejection is tier 3 ONLY (at tier 4 it would void diff_detector.rb's legitimate parent fallback onto a sibling project's canonical file), while tier 4 instead rejects candidates under project_path (otherwise the project's own nested copy re-enters through the parent root); SANDBOX_DIR is rejected in both recursive tiers so spm-cache's own generated umbrella/proxy resolved files can never stand in for the host graph.
- [Phase 06 — 02, 2026-08-27]: FID-01 left Pending, not marked Complete. Version/revision reconciliation runs on every non-fast-path run (Installer#reconcile_lockfile_from_host_graph, self-gated on a non-empty diff per D-03, keyed on DiffDetector#live_packages' resolved-union-pbxproj set, saving independently of refresh_consumed_dependencies) and provably preserves enriched products[]; but the D-01 drop rule, the D-02 add rule and the D-04 warn-once on an unreadable host graph are Plan 03's scope. Marking FID-01 Complete now would assert the lock describes the current graph while the 8 phantom reference-project packages would still persist in it.
- [Phase Phase 6 — Graph Authority: Lockfile Reconciliation (in progress — 2/4 plans)]: FID-01 D-02 realized as OMISSION of the products key on added packages, not products: [] — enrichment guards with 'next if pkg_data["products"]' and [] is truthy in Ruby, so a present-but-empty key would suppress product metadata permanently (2026-08-27)
- [Phase Phase 6 — Graph Authority: Lockfile Reconciliation (in progress — 2/4 plans)]: The lockfile reconciler resolves its project entry extension-insensitively (Fake matches Fake.xcodeproj) — narrow on purpose, and what makes its own save observably load-bearing since refresh_consumed_dependencies matches the basename strictly (2026-08-27)

## Current Position

Phase: 6 — Graph Authority: Lockfile Reconciliation (in progress)
Plan: 4 (next) — 2 of 4 plans complete (06-01 M1 measurement, 06-02 FID-06 locator + reconciliation)
Status: FID-06 complete; FID-01 partially delivered (version/revision reconcile + products preservation), membership rules pending in 06-03
Last activity: 2026-08-27 — 06-02 shipped Core::PackageResolved, collapsed all five glob sites, 275 examples 0 failures

## Operator Next Steps

- **Phase 11 gate:** create a GitHub App owned by `phuongddx` (`Contents: read & write` + `Metadata: read`, installed on `homebrew-spm-cache` only, never `workflow` scope) and store its app id + private key as repo secrets. This replaces the dead `TAP_REPO_TOKEN` (classic PAT, auto-deleted after a year unused). A write-access deploy key is the accepted lower-ceremony substitute.
- **Phase 6 first work (M1):** reproduce the stale-transitive release build on the real 59–70 package reference project and attribute the cause before Phase 7's design is locked.
- Deferred (not in v0.4.0): `gem signin` → `gem build`/`gem push` → verify `gem install spm-cache`; then the Action + its smoke CI become viable.
