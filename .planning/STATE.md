---
gsd_state_version: 1.0
milestone: v0.4.0
milestone_name: Build Fidelity & Release Automation
current_phase: 11
current_phase_name: Homebrew Release Automation
status: executing
stopped_at: Completed 11-03-PLAN.md (operator gate + deploy-key pivot + live dispatch dry-run)
last_updated: "2026-08-30T16:33:25.545Z"
last_activity: 2026-08-30
last_activity_desc: Phase 11 plans complete (3/3) — pending phase verification
state_head: 8a331477c80f8e0fe32143ac38ca41577dea8c4d
progress:
  total_phases: 6
  completed_phases: 5
  total_plans: 18
  completed_plans: 18
  percent: 83
---

# Project State: spm-cache

**Initialized:** 2026-08-10
**Current Phase:** 11
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

> **⚠ CORRECTION 2026-08-27 (post-verification).** The falsifier below claiming *"no committed revision
> of the canonical file ever held AnchoredPopup 1.1.3"* is **FALSE**. Four commits hold it —
> `893fb8b`, `3bf9e91`, `64e960d`, `9075971` — and the nested "wrong file" is **byte-identical** to
> canonical@`9075971`. The original check produced a false negative: the path was passed without a
> leading `./`, so `git show` resolved it against the repo root and failed on every revision, and a
> swallowed exception rendered the failures as "not found".
>
> **Consequence:** the wrongly-picked file IS an old canonical snapshot, so *which file the lock matches*
> cannot distinguish H-lock from H-wrongfile. **The `H-wrongfile 25 · H-lock 0` scoring is unsupported;
> both mechanisms remain consistent with the evidence.**
>
> **What still holds:** `H-float = 0` is sound and independent — every package is emitted as an exact
> `revision:` pin, leaving no range to float within. The Phase 7 rescope rests on H-float, not on the
> H-lock/H-wrongfile split, so that decision stands. Phase 6 fixed BOTH candidate mechanisms (FID-06
> canonical locator + FID-01 reconciliation), so there is no code consequence — only this record.
> Evidence: `.planning/phases/06-graph-authority-lockfile-reconciliation/06-VERIFICATION.md`.

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
| 6 | Graph Authority — Lockfile Reconciliation | Complete (verified) | gsd/v0.4.0-build-fidelity-release-automation |
| 7 | Host-Faithful Checkout Seeding | Complete (verified 5/5, code-review clean) | gsd/v0.4.0-build-fidelity-release-automation |
| 8 | Drift Read-Back, Fidelity Status & Provenance | Complete (verified 8/8, code-review clean after 2 fix iterations) | gsd/v0.4.0-build-fidelity-release-automation |
| 9 | Cache Identity & Invalidation | Complete (verified 4/5 + SC5 operator-PASS, UAT 1/1, code-review clean, security 5/5 closed) | gsd/v0.4.0-build-fidelity-release-automation |
| 10 | Fidelity Regression Coverage | Complete (verified 23/23 + operator-confirmed assumption, code-review clean after WR-01/02 fixes, security 12/12 closed) | gsd/v0.4.0-build-fidelity-release-automation |
| 11 | Homebrew Release Automation | Complete (3/3 plans: 11-01 --version intercept, 11-02 update-tap rewrite, 11-03 operator gate + deploy-key pivot + live v0.3.0 dry-run; pending verification) | gsd/v0.4.0-build-fidelity-release-automation |

Hard chain: 6 → 7 → 8 → 9. Phase 10 depends on 7–9 (fixtures authorable in parallel). Phase 11 is
fully independent and schedulable anywhere.

Research flags: **Phase 7** and **Phase 9** need `--research-phase` during planning; 6, 8, 10, 11 reuse established patterns.

v0.3.0 phase history archived to `.planning/milestones/v0.3.0-phases/`.

## Phase 7 Process Notes (2026-08-29)

- **`gsd-tools.cjs query phase.complete 7` computed the wrong `next_phase`.** Both Phase 6 and
  Phase 7 were already `disk_status: complete` per `roadmap.analyze`, so the true next incomplete
  phase is 8 — but the CLI returned `next_phase: "6"` and wrote `current_phase: 6` into STATE.md
  (with a `preservation_warnings` entry noting it "preserved [the] disagreeing derived" value for
  `current_phase_name`, suggesting it detected the conflict but resolved it wrong). Caught by the
  orchestrator comparing against `roadmap.analyze`'s phase list before trusting the tool's output;
  corrected manually to Phase 8 in this transition. Not yet filed upstream as a tool bug.

## Phase 7 Process Notes (2026-08-27)

- **07-02 executor briefly used `git stash`** during a verification step — against an absolute
  rule with no exceptions. Self-caught, `git stash pop` recovered immediately, verified via
  `git diff`/`git stash list` (nothing lost). Logged here rather than silently passed over.

- **Reference-project restoration claim was slightly overstated.** The benchmark left
  `StressMonitor.xcodeproj/.../StressMonitor.xcscheme` at `version = "1.8"` (was `1.7"`) —
  an Xcode auto-migration side effect of running a build/resolve against the project, not
  something spm-cache wrote. Caught by the orchestrator post-hoc (not by the executor), reverted
  via `git checkout --`. `AGENTS.md`/`CLAUDE.md` mods and `.agents/`/`.bg-shell/` untracked dirs
  one level above `StressMonitor/` predate this session and were left alone — outside the
  benchmarked project, not caused by it.

## Phase 7 Result (2026-08-27)

FID-02, FID-05, PERF-01 all Complete. 341 examples, 0 failures (from 332). Real benchmark against
the reference project: wall-clock **-40.6%** (18m15s -> 10m50s), disk **-34%** (4.1G -> 2.7G) —
the shared clone dir is a genuine improvement, not just neutral. See
`.planning/phases/07-host-faithful-checkout-seeding/07-BENCHMARK.md`.

Phase 7 canonically verified 2026-08-29 (5/5 must-haves passed) after a code-review pass found
and fixed 2 Critical findings (a residual build-lock coverage gap in `Installer::Use`'s fast
path, and `slice_complete?` treating a hit-but-missing-from-disk xcframework as complete) plus 5
Warning findings; 1 warning (sleep-based timing specs) and 3 Info items deliberately deferred with
documented rationale in `07-REVIEW-FIX.md`. Final suite: 342 examples, 0 failures. Transitioned to
Phase 8.

## Milestone Re-scope Decision (2026-08-27, post-M1) -- OVERRIDDEN same day

**Override (2026-08-27, later same day):** user explicitly chose, after being asked twice
with the tradeoff stated plainly, to skip the remainder of Phase 6 UAT and run
`/gsd-autonomous` across Phases 6-11 directly against the CURRENT roadmap text --
superseding the "re-plan 7-9 first" instruction below. Phase 6's VERIFICATION.md status was
set to `passed` by this same override (see its `## User Override` section); the live-build
half of criterion 2 remains genuinely unverified. This is a recorded risk acceptance, not a
retraction of the M1 analysis -- H-float=0 and the rationale for demoting Phase 7 still hold;
the user chose to proceed without re-planning around them first.

## Milestone Re-scope Decision (2026-08-27, post-M1)

**User decision:** finish Phase 6 (the actual fix) and verify it closes the field failure, THEN re-plan
Phases 7–9 with M1's evidence in hand. Rationale: M1 observed Phase 7's target mechanism (isolated
upward re-resolution) **zero times** in the field, and Phases 8–9 largely exist to support Phase 7.
Phase 9's cache invalidation is still required regardless — without it, even the FID-06 fix reaches zero
existing users, since `Cache.swift:19-22` `hit(module:)` is a bare name + `fileExists` check.

Do NOT execute Phases 7–9 against the current roadmap text. Re-plan them after Phase 6 verification.
Phase 11 (release automation) is unaffected — it is fully independent.

## Open Measurements (block design decisions)

| # | Measurement | Runs in | Blocks | Status |
|---|-------------|---------|--------|--------|
| M1 | Reproduce + attribute the stale-transitive release build on the real 59–70 package project | Phase 6 (first work) | Phase 7 design lock | ✓ Done — H-wrongfile (see root-cause model above) |
| M2 | Report-only pinning run: count `resolution-incompatible` packages | Phase 7 (produced) | Phase 8 policy commitment; rescope trigger if high | ✓ Done 2026-08-29 — 0/17, not a rescope trigger (`08-M2-MEASUREMENT.md`). Never run in Phase 7 itself (research/verifier gap); run retroactively before Phase 8 planning via static manifest analysis against the reference project's own Xcode-resolved checkouts, not a live resolve/build sweep. |
| M3 | Wall-clock / disk delta from pin-list fan-out (verbatim superset vs minimal closure) | Phase 7 | PERF-01; narrowing decision | ✓ Done — -40.6% wall-clock / -34% disk, no narrowing needed (`07-BENCHMARK.md`) |
| M4 | Does xcodebuild write back realized versions on the `run_with_scheme` / vendored-`.xcodeproj` path? | Phase 7 (early probe) | Sole falsifier of the no-flag design | Moot, not run — Phase 7 took the conservative branch unconditionally: `BuildPipeline#seed_host_graph` classifies `vendored_xcodeproj?` checkouts as not-graph-pinned and skips seeding entirely, before any build happens (`build_pipeline.rb:69-79`), regardless of whether xcodebuild would have written back realized versions on that path. Nothing is ever claimed pinned there, so there is nothing for Phase 8 to detect drift against — M4's answer no longer affects any design decision. Verified by direct code inspection 2026-08-29, not re-litigated in Phase 8 discuss/plan. |

## Project Reference

See: .planning/PROJECT.md (updated 2026-08-29)

**Core value:** Reduce Xcode clean build times by serving prebuilt SPM dependency binaries transparently, with fallback to source on cache miss.
**Current focus:** Phase 11 — Homebrew Release Automation

## Session Continuity

Last session: 2026-08-30T16:33:14.374Z
Stopped at: Completed 11-03-PLAN.md (operator gate + deploy-key pivot + live dispatch dry-run)
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
| Phase 06 P04 | ~6m | 3 tasks | 4 files |
| Phase 06 P05 | ~12m | 2 tasks | 3 files |
| Phase 07 P01 | ~55m | 3 tasks | 6 files |
| Phase 07 P02 | ~2h (incl. ~29min real xcodebuild) | 3 tasks | 9 files |
| Phase 10 P01 | 10min | 3 tasks | 1 files |
| Phase 10 P02 | 831s | 3 tasks | 2 files |
| Phase 10 P03 | 561s | 3 tasks | 1 files |
| Phase 11 P01 | 7m | 2 tasks | 2 files |
| Phase 11 P02 | 18m | 3 tasks | 2 files |
| Phase 11 P03 | 30m | 3 tasks | 4 files |

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
- [Phase Phase 6 — Graph Authority: Lockfile Reconciliation (in progress — 2/4 plans)]: DIAG-01 lock_graph_fidelity excludes lock entries with no repositoryURL from the drift comparison (lock side only) — Package.resolved structurally never lists local/path_from_root packages, so including them would warn forever on any project with a local package; only_in_host is still computed unconditionally
- [Phase Phase 6 — Graph Authority: Lockfile Reconciliation (in progress — 2/4 plans)]: Drift is a :warn, never a :fail — the remedy is automatic on the next non-fast-path spm-cache use, so a :fail would redden CI before a first run; asserted by a command-level not_to receive(:exit) example rather than inferred from doctor.rb
- [Phase Phase 6 — Graph Authority: Lockfile Reconciliation (4/4 plans executed — pending verification)]: Phase 6 gap closure: chose structural agreement (one memoized host-graph resolution per run, shared by DiffDetector and both installer consumers) over aligning three independent resolvers' postures — divergence now costs a test failure, not a code review
- [Phase Phase 6 — Graph Authority: Lockfile Reconciliation (4/4 plans executed — pending verification)]: The installer's reach over the locator's parent-directory tier was widened deliberately, bounded by sandboxed? (excludes spm-cache's own generated resolved files) and exclude_under: project_path (keeps the FID-06 nested stale copy closed)
- [Phase Phase 6 — Graph Authority: Lockfile Reconciliation (4/4 plans executed — pending verification)]: WINDOWS #5 (unguarded host-graph parse in DiffDetector) left open: routing it through the tolerant accessor would flip every detect caller to silently-degrade. Recorded as a decision-fidelity gap against D-04 'never crash', not just robustness — warrants a dedicated follow-up plan
- [Phase 07 — Host-Faithful Checkout Seeding (1/2 plans)]: 07-01 shipped SPM::ResolvedGraph and wired it into BuildPipeline.run/Installer::Build — FID-02 (seed host graph before first `swift package describe`) and FID-05 (vendored-.xcodeproj packages reported not-graph-pinned, never silently folded into pinned) marked Complete; the run's single pin source is resolved once via the already-memoized `host_graph_detector` (no second locator, per Phase 6 Plan 05's invariant); `run`'s body was extracted into a private `perform_build` so the seed/restore lives in one success-flag + ensure region around it, restoring on StandardError AND Interrupt, never on success; `-onlyUsePackageVersionsFromResolvedFile` deliberately NOT added (D-02). PERF-01 (shared clone dir, watch/build lock, benchmark gate) deferred to 07-02 per ROADMAP's own mapping.
- [Phase 07 — Host-Faithful Checkout Seeding (2/2 plans — Phase 7 complete)]: 07-02 shipped `Config#clones_dir`/`#build_lock_path`, threaded `clones_dir` through both `Buildable.new` call sites (including `run_with_scheme`'s vendored-.xcodeproj fallback), and a process-level blocking flock shared by `Installer::Build` (held across `super` + the whole build loop) and `Installer::Use`'s non-fast-path branch (blocks before `recreate_dirs`) — closing Pitfall 15. PERF-01 proven by a real cold-cache `spm-cache build --config=release` against the StressMonitor reference project: wall-clock 18m15s→10m50s (-40.6%), `~/.spm-cache` disk 4.1G→2.7G (-34%), no regression on either axis (`07-BENCHMARK.md`). A pre-existing, out-of-scope Class E binaryTarget rename gap (3 Firebase Analytics variant products backed by one differently-named binaryTarget) was discovered live during the benchmark and worked around via the reference project's own gitignored `ignore_build_errors: true` knob (not fixed, logged only — present identically on both before/after commits so it does not bias the comparison). FID-02, FID-05, PERF-01 all Complete — Phase 7 fully done.
- [Phase 07 — canonical verification + code review, 2026-08-29]: Re-planning found nothing left to plan (research independently re-derived all 5 success criteria from source, 341/0 suite) — user chose "view existing, skip replanning" over adding a plan or replanning from scratch. Code review then found 2 Critical + 6 Warning + 3 Info findings against the already-shipped Phase 7 code: CR-01 (`Installer::Use`'s build lock didn't cover trailing `gen_supporting_files`/`integrate_proxy_into_project`/`gen_cachemap_viz`) was only partially fixed by a fixer agent that crashed mid-run (transient API connection error) — its own commit left the fast-path branch of the same three calls unlocked and added a test asserting the wrong invariant ("nothing to protect against" on the fast path); a re-review caught this as CR-01b and it was closed by locking both branches identically. CR-02 (`slice_complete?` treating a hit-but-missing-from-disk xcframework as complete) was fixed cleanly with a new regression test. 5 of 6 warnings fixed (opts-splat bug, slice_satisfies? catch-all, duplicated swiftinterface scan, 3 overly-broad rescues narrowed, redundant resolve_destinations branches); WR-05 (sleep-based lock-contention timing specs) deliberately left unchanged after independent analysis found the flake risk low and the tests load-bearing. Final re-review (iteration 3 of the 3-iteration cap) converged clean. Canonical goal-backward verification then passed 5/5. `gsd-tools.cjs query phase.complete 7` itself had a bug (see Phase 7 Process Notes above) — computed `next_phase: 6` when Phase 6 was already complete; corrected manually to Phase 8 during transition.
- [Phase 08 — Drift Read-Back, Fidelity Status & Provenance, 2026-08-29, autonomous execution]: Both plans executed sequentially (workflow.use_worktrees=false) via `/gsd-autonomous --from 8`. 08-01 shipped `BuildPipeline#report_fidelity` (drift read-back, host-pinned/resolution-incompatible classification, provenance sidecar write/cleanup) as a single consolidated insertion point covering all three artifact-producing paths uniformly; threaded `config:` into `Installer::Build`'s call site. 08-02 shipped `cache list`'s per-package fidelity-status column (`Dir.glob("*.xcframework")` replacing raw `Dir.entries`, fixing a pre-existing bug where sidecar files printed as spurious package entries). Deep code review (5 files) found 1 Critical + 3 Warning + 1 Info; a 2-iteration auto-fix loop closed all Critical/Warning findings (CR-01: reject non-Hash JSON + rescue SystemCallError in `cache list`'s TOCTOU race; WR-01: track actually-built destinations instead of the raw request; WR-02: move `intended_pin_map` capture inside the seed/restore exception boundary; WR-03: atomic tempfile-then-rename sidecar write, never raises) plus one finding the re-review itself surfaced mid-loop (WR-04: Class E's direct-copy path narrowed to actual xcframework slices via a new `slice_satisfies?`, mirroring `Installer::Build`'s existing predicate). Final re-review (iteration 3) converged at 0 Critical/0 Warning — 2 Info items (one pre-existing, one code-duplication note on the newly-added `slice_satisfies?`) deliberately left unfixed, out of `critical_warning` scope. Canonical goal-backward verification passed 8/8; full suite 342→368 (+26), 0 failures throughout. `gsd-tools.cjs query phase.complete 8` reproduced the SAME `next_phase` bug as the Phase 7 transition (returned `6` instead of `9`, both already complete) — corrected manually to Phase 9 again; still not filed upstream.
- [Phase 09 — Cache Identity & Invalidation, 2026-08-29]: 09-01 made the Swift companion's `BinariesCache.hit()` provenance-aware (sidecar `pins[identity]` vs lockfile pin; intersection-only comparison — absence is never drift; any parse anomaly is an unconditional miss); 09-02 closed the default-command gap (`fast_path?` gains a `spm_cache_version` stamp guard so any spm-cache bump forces one full regen) and added `cache clean`'s orphan-sidecar sweep (D-10 paired survival); 09-03 authored the SC5 empirical DerivedData runbook. Verification 4/5 + SC5 operator-PASS via UAT; deep code review converged clean after CR-01 (drop pre-emptive provenance `rm_f` in `copy_prebuilt_binary_target`, preserving prior host-pinned pins per WR-03); security audit 5/5 threats closed (3 mitigated, 2 accepted); suites 387 Ruby / 36 Swift green. `phase.complete 9` computed `next_phase: 10` correctly this time. Tooling quirk (4th, unfixed upstream): any extra `*-VERIFICATION.md` sorting before the canonical report shadows status reads — `gsd-tools` reads only the first sorted candidate, so the SC5 runbook made every status surface report "missing"; resolved by giving the runbook accurate frontmatter (`status: passed`) rather than renaming it.
- [Phase 10 — Fidelity Regression Coverage, 2026-08-29/30, autonomous execution]: Three test-only plans shipped hermetically (387→416 examples, 0 failures; zero production changes — verification confirmed via git-range audit): `spec/fidelity_drift_regression_spec.rb` (TEST-01, drift both directions, both injection sources, mutation-proven fail-first), `spec/fidelity_bucket_partition_spec.rb` + kitchen-sink fixture (TEST-02, hybrid two-surface observation — report_fidelity sidecars AND ProxyGenerator graph.json, since the CONTEXT's single-source premise was 3/6 true; completeness+disjointness both arms fail-first), `spec/fidelity_edge_matrix_spec.rb` (TEST-03, all 8 v0.2.x edge classes incl. the two no-analog shapes). Deep code review found 0 Critical/2 Warning (both false-assurance risks — tautological assertions); WR-01/WR-02 fixed with mutation proofs and re-review converged clean. Verification 23/23 with one operator-confirmed flagged assumption (resource-bundle class 6/8 baseline intent — accepted 2026-08-30); security 12/12 threats closed (L1 short-circuit). The one Rule-3 deviation worth remembering: class 6/8 drives `FrameworkSlice#copy_resource_bundles` via `send` because the class is unwired dead code with three pre-existing defects (private `resource_paths`, bare-`Sh` NameError at slice.rb:64, template mismatch) — logged in the phase's deferred-items.md and WINDOWS ledger as a future cleanup candidate. `phase.complete 10` computed next_phase 11 correctly. Cosmetic tooling note: phase.complete's file-reference warnings misread prose strings ("bundle exec rspec ...", "pkg_dir/Package.resolved") as missing paths — heuristic noise, no action.
- [Phase ?]: Phase 10 Plan 01: one spec file, two describe blocks — tier-1 read-back legs under the default-deny Core::Sh guard (both entry points raise on unexpected invocation, SC4 as an executable assertion), tier-3 gen-proxy sidecar legs outside it
- [Phase ?]: Phase 10 Plan 01: missing-realized-file edge simulated by the stub consuming the seeded Package.resolved — seed_host_graph necessarily creates it, so absence at read-back is only reachable via the build removing it
- [Phase ?]: Phase 10 Plan 01: tier-3 lockfile fixture pins by revision (aaa111) not version, mirroring pinValue revision-over-version precedence so the sidecar drift compare is an exact string match
- [Phase ?]: Phase 10 Plan 02: TEST-02's six buckets observed via the hybrid two-surface route — sidecar statuses through the tier-1 seam, graph statuses through the compiled proxy — with the universe always the declared input set (fixture lockfile packages incl. empty-repositoryURL local/path entry + tier-1 pin identities), never classifier output
- [Phase ?]: Phase 10 Plan 02: cache-availability graph statuses (hit/missed) are excluded from the bucket vocabulary by OBSERVING them via a config-unconstrained canary package run against empty and populated caches — no status name is typed anywhere; input-side rules (local/path -> excluded, transitive-only -> consumer's pinned bucket) reuse observed values only
- [Phase ?]: Phase 10 Plan 02: partition is per-PACKAGE identity via a fixture-authored product->package ownership map (graph.json is per-product); the mixed hit+missed downgrade keeps multi-product packages at exactly one bucket (adjacency probe), and the local/path entry joins the observed excluded bucket rather than introducing a seventh bucket
- [Phase ?]: Phase 10 Plan 03 (TEST-03): FrameworkSlice resource-bundle leg drives the REAL copy_resource_bundles semantics directly (send) against the slice's public framework_path — the class is unwired dead code (private resource_paths defeats the respond_to? guard, bare-Sh NameError, template binding mismatch); zero production changes honored, gap logged in deferred-items.md
- [Phase ?]: Phase 10 Plan 03 (TEST-03): eight-class edge matrix shipped as one hermetic file — tier-1 legs under the default-deny Core::Sh guard (both entry points, libtool prefix-allowlisted for the shim leg), tier-3 plugin/transitive legs via the local compiled proxy only; class 2/8 macro kept as ONE example covering both pin directions so each class number appears exactly once as an example string; three fidelity specs combined 0.89s (2-3s target)
- [Phase ?]: 11-01: --version intercepted in Main.run before CLAide dispatch (argv.first guard, prints SPMCache::VERSION from VERSION file); RED-then-GREEN per TDD plan
- [Phase ?]: 11-02: update-tap.yml rewritten two-trigger/two-job with every failure loud - app-token auth (create-github-app-token@v3), integrity-gated download (curl -fL retry + 1f8b magic before hash), anchored exactly-one url/sha256 edits with grep -Fqx postconditions, explicit no-diff push replacing || exit 0, macOS brew verify; 20-example structural spec pins REL-04..09
- [Phase ?]: 11-02: version asserted via URL-tag postcondition only - no version-field edit, no stanza added (live tap formula has none; Homebrew derives version from URL tag; old version sed was a silent zero-match no-op)
- [Phase ?]: 11-02: verify-publish on macos-latest per locked CONTEXT; macos-15 pin is the documented one-line fallback if the first live run hits an OS-specific failure
- [Phase 11]: 11-03 (2026-08-30): operator gate resolved via pivot — claimed UI-set App secrets verifiably absent, so the pre-authorized deploy-key substitute was applied API-first (write deploy key on the tap, TAP_DEPLOY_KEY the only repo secret, TAP_REPO_TOKEN deleted); REL-04 truth = long-lived machine credential (non-human, non-expiring). Live v0.3.0 dispatch: update-tap GREEN on the idempotent notice branch (REL-05/06/07/09), verify-publish RED at the version assertion per the documented pre-intercept fail-first proof (REL-08) after pinning macos-15; tap-formula Homebrew-Ruby-3.4 boot defect logged to deferred-items.md (fix needed before the v0.4.0 release's first green verify).

## Current Position

Phase: 11 (Homebrew Release Automation) — ALL PLANS EXECUTED
Plan: 3 of 3 complete (11-03 shipped the operator gate via deploy-key pivot + live dispatch dry-run)
Status: Phase 11 plans complete; pending phase verification (`11-LIVE-RUN.md` holds the live-run evidence)
Last activity: 2026-08-30 — 11-03: deploy-key pivot, 3 live dispatch runs, anchor/runner fixes, 438 examples 0 failures

### Historical position (Phase 6, prior to this update)

Phase: 6 — Graph Authority: Lockfile Reconciliation (in progress)
Plan: 4 (next) — 2 of 4 plans complete (06-01 M1 measurement, 06-02 FID-06 locator + reconciliation)
Status: FID-06 complete; FID-01 partially delivered (version/revision reconcile + products preservation), membership rules pending in 06-03
Last activity: 2026-08-27 — 06-02 shipped Core::PackageResolved, collapsed all five glob sites, 275 examples 0 failures

## Deferred Verification

None — Phase 9's deferred SC5 human check was executed and PASSED by the operator on 2026-08-29
(`09-UAT.md` 1/1 pass; `09-SC5-VERIFICATION.md` `## Outcome`).

## Operator Next Steps

- **Phase 11 gate:** create a GitHub App owned by `phuongddx` (`Contents: read & write` + `Metadata: read`, installed on `homebrew-spm-cache` only, never `workflow` scope) and store its app id + private key as repo secrets. This replaces the dead `TAP_REPO_TOKEN` (classic PAT, auto-deleted after a year unused). A write-access deploy key is the accepted lower-ceremony substitute.
- Deferred (not in v0.4.0): `gem signin` → `gem build`/`gem push` → verify `gem install spm-cache`; then the Action + its smoke CI become viable.
