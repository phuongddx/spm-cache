# Project State: spm-cache

**Initialized:** 2026-08-10
**Current Phase:** 2 (ready for `$gsd-plan-phase 2` — Diagnostics Command)
**Project Mode:** Horizontal Layers
**Direction:** v0.3.0 Mixed cycle (moat + adoption + reliability)

## Project Memory

### What this project is
`spm-cache` (v0.2.8) caches Swift Package Manager dependencies as `.xcframework` binaries via a proxy-package architecture. Ruby gem CLI + Swift companion binary; macOS-only; distributed via Homebrew + RubyGems. The v0.3.0 cycle adds `watch` (auto-sync moat), `init` (onboarding), `doctor` (reliability), plus the first-ever test CI pipeline.

### Key artifacts
- Codebase map: `.planning/codebase/` (7 docs, 2026-08-10)
- Design spec: `docs/superpowers/specs/2026-08-10-v0.3.0-watch-init-doctor-design.md` (approved)
- PDR: `docs/project-overview-pdr.md`
- Roadmap history: `docs/project-roadmap.md`
- Competitive analysis: `competitive-analysis-2026-07.html`, `scipio-deepdive-features-2026-07.html`

### Phase order rationale
1. Test CI (REL-01) — foundation; no test pipeline exists today
2. doctor (REL-02/03) — self-contained, de-risks via `companion_binary` check
3. init (ONBD-01/02/03) — touches Config/Lockfile, enables the Action
4. GitHub Action (ONBD-04) — separate repo, depends on `init`
5. watch (AUTO-01–05) — highest integration surface; lands last with foundations in place

### Locked design decisions
- watch: native FSEvents via Fiddle (no `listen` gem); watches Package.resolved + project.pbxproj only; continue-on-error loop
- init: idempotent diff-merge on re-run; non-interactive flags for CI
- doctor: data-driven check registry; `--json` output
- GitHub Action: separate thin repo, shell-out only
- Test CI: separate `ci.yml` from release `update-tap.yml`; Ruby 3.0–3.3 × macOS matrix

## Phase Status

| Phase | Name | Status | Branch |
|-------|------|--------|--------|
| 1 | Test CI Foundation | complete | b664d0b |
| 2 | Diagnostics Command | pending | — |
| 3 | Project Bootstrap | pending | — |
| 4 | CI GitHub Action | pending | — |
| 5 | Auto-Sync Watcher | pending | — |
