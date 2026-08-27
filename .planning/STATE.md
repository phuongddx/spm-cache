---
gsd_state_version: 1.0
milestone: v0.4.0
milestone_name: Build Fidelity & Release Automation
status: planning
last_updated: "2026-08-27T04:40:40.904Z"
last_activity: 2026-08-27
progress:
  total_phases: 0
  completed_phases: 0
  total_plans: 0
  completed_plans: 0
  percent: 0
---

# Project State: spm-cache

**Initialized:** 2026-08-10
**Current Phase:** — (v0.4.0 starting; defining requirements)
**Project Mode:** Horizontal Layers
**Direction:** v0.4.0 Build fidelity (correctness) + release automation

## Project Memory

### What this project is

`spm-cache` (v0.3.0) caches Swift Package Manager dependencies as `.xcframework` binaries via a proxy-package architecture. Ruby gem CLI + Swift companion binary; macOS-only. Distribution today is Homebrew only — the gem is not published on RubyGems (deferred 2026-08-27), which also leaves the GitHub Action non-functional. The v0.4.0 cycle fixes transitive dependency-version drift in cached builds and repairs the Homebrew release automation.

### Key artifacts

- Codebase map: `.planning/codebase/` (7 docs, 2026-08-10)
- Design spec: `docs/superpowers/specs/2026-08-10-v0.3.0-watch-init-doctor-design.md` (approved)
- PDR: `docs/project-overview-pdr.md`
- Roadmap history: `docs/project-roadmap.md`
- Competitive analysis: `competitive-analysis-2026-07.html`, `scipio-deepdive-features-2026-07.html`

### v0.4.0 problem statement (verified in code 2026-08-27)

Cached builds can link transitive dependency versions the host app never resolved. `Installer::Build#build_single_target` (lib/spm_cache/installer/build.rb:120) passes each package's own checkout dir to `SPM::BuildPipeline.run` (lib/spm_cache/spm/build_pipeline.rb:33), which shells out to `xcodebuild -scheme` inside it. The umbrella's `swift package resolve` (lib/spm_cache/spm/checkout_resolver.rb) produces one unified resolution and materializes checkouts at those versions — but the per-package `xcodebuild` re-resolves from that *package's* committed `Package.resolved`, ignoring the umbrella/host graph. Field symptom (StressMonitor, ~2026-08-09, needs re-reproduction): `spm-cache build ExyteChat --config=release` fails because Chat pins MediaPicker 3.2.4 while the app locks 3.3.2.

### Locked scope decisions (2026-08-27)

- RubyGems publication deferred by user decision — Homebrew stays the only distribution channel
- GitHub Action out of scope this cycle (its `gem install spm-cache` step needs the unpublished gem); broken-window #2 to be waived, not closed
- `TAP_REPO_TOKEN` refresh is an operator step (GitHub Settings → Secrets) — autonomous will pause there

## Phase Status

| Phase | Name | Status | Branch |
|-------|------|--------|--------|
| — | (v0.4.0 roadmap not yet created) | — | — |

v0.3.0 phase history archived to `.planning/milestones/v0.3.0-phases/`.

## Project Reference

See: .planning/PROJECT.md (updated 2026-08-27)

**Core value:** Reduce Xcode clean build times by serving prebuilt SPM dependency binaries transparently, with fallback to source on cache miss.
**Current focus:** v0.4.0 — build fidelity (host-graph-faithful transitive resolution) + Homebrew release automation

## Session Continuity

Last session: 2026-08-24T08:11:57.526Z
Stopped at: Milestone v0.3.0 complete and archived 2026-08-24
Resume file: None

## Performance Metrics

| Plan | Duration | Tasks | Files |
|------|----------|-------|-------|
| Phase 03 P01 | 27min | 3 tasks | 5 files |
| Phase 04 P01 | 660s | 2 tasks | 7 files |
| Phase 05 P01 | ~35 min | 3 tasks | 14 files |

## Decisions

- [Phase 03 — Project Bootstrap]: init seeds canonical lock shape (platforms {}) — pure file-I/O; consumer default makes {} identical to omission
- [Phase 03 — Project Bootstrap]: 03-01 doc drift closed via inline ROADMAP amendments (dated 2026-08-24) + phase SUMMARY Documented deviations (a)-(d); amendment-count gate corrected 6→5 (Phase-2 pre-existing count was 3, not 4)
- [Phase 04 — CI GitHub Action]: F1 fixed one-line only (--config= → --default-config= at action.yml:55); spec/action_spec.rb slices each command's own options (def self.options → .concat(super)) so inherited base flags can never satisfy the cross-reference
- [Phase 04 — CI GitHub Action]: criterion 3 recorded as accepted external deviation (gem unpublished — RubyGems 404; action repo unpublished) with 6-item ordered release checklist; gemspec homepage placeholder recorded, not edited
- [Phase 05 — Auto-Sync Watcher]: 05-01: SIGTERM trap + interrupt flush delivered; self-trigger guard shipped as a real defect fix (A1 probe CONFIRMED); polling deviation + fatal/deletion semantics recorded as dated amendments
- [Release checklist, post-milestone 2026-08-27]: item 4/5 (publish action repo, tag v1) had been done 2026-08-11 — *before* the F1 fix (2026-08-24), so the published `phuongddx/spm-cache-action@v1` still had the buggy `--config=` flag. Resynced `action.yml`+`README.md` from `action/` and force-moved `v1` to the corrected commit (`7114ba6`). Added `.github/workflows/smoke.yml` (item 6) as `workflow_dispatch`-only — no scratch backend configured yet, and it can't pass until the gem is on RubyGems regardless. Gemspec homepage (item 1) already fixed (`cf384d6`). Items 2/3 (`gem build`/`gem push`, verify install) explicitly deferred — no RubyGems credentials on this machine (`gem signin` needed first).

## Current Position

Phase: Not started (defining requirements)
Plan: —
Status: Defining requirements
Last activity: 2026-08-27 — Milestone v0.4.0 started

## Operator Next Steps

- **v0.4.0 blocker:** refresh `TAP_REPO_TOKEN` (repo Settings → Secrets) with a PAT that can push to `phuongddx/homebrew-spm-cache` — the current secret returns "Bad credentials", so `update-tap.yml` fails and formula updates are manual
- Deferred (not in v0.4.0): `gem signin` → `gem build`/`gem push` → verify `gem install spm-cache`; then the Action + its smoke CI become viable
