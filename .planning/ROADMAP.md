# Roadmap: spm-cache v0.3.0

**Mode:** Horizontal Layers
**Granularity:** Standard
**Created:** 2026-08-10
**Project:** spm-cache

## Overview

Five phases delivering the v0.3.0 "Mixed" cycle — reliability first (foundation), then adoption, then the moat feature. Each phase is a horizontal layer that builds complete technical capability before assembly. Phased so that each layer de-risks the next: test CI enables confident delivery; `doctor` surfaces environment issues before they bite `init`/`watch`; `init` enables the Action; `watch` (highest integration surface) lands last with all foundations in place.

| # | Phase | Goal | Requirements | Success Criteria |
|---|-------|------|--------------|------------------|
| 1 | Test CI Foundation | A CI pipeline that runs the full test suite on every PR | REL-01 | 3 |
| 2 | Diagnostics Command | `doctor` self-diagnoses toolchain + cache health | REL-02, REL-03 | 4 |
| 3 | Project Bootstrap | `init` bootstraps a project in one command, idempotently | ONBD-01, ONBD-02, ONBD-03 | 4 |
| 4 | CI GitHub Action | Thin Action restores/saves cache in CI | ONBD-04 | 3 |
| 5 | Auto-Sync Watcher | `watch` auto-regenerates the proxy on project change | AUTO-01–05 | 5 |

---

### Phase 1: Test CI Foundation
**Goal:** Establish a CI pipeline that runs the full RSpec + Swift test suite on every PR and push, giving the project a test pipeline for the first time.
**Requirements:** REL-01
**Success Criteria**:
1. `.github/workflows/ci.yml` exists and triggers on PR + push to main
2. Ruby matrix (3.0/3.1/3.2/3.3) runs `bundle exec rspec` on macOS-latest and passes
3. Swift companion runs `make proxy.build` then `swift test` and passes; Xcode version pinned via `xcode-select`

### Phase 2: Diagnostics Command
**Goal:** Deliver `spm-cache doctor` so users can self-diagnose toolchain drift, cache-dir health, and remote-backend connectivity in one command — including the `companion_binary` check that closes the Ruby↔Swift version-drift gap.
**Requirements:** REL-02, REL-03
**Success Criteria**:
1. `spm-cache doctor` runs a data-driven check registry (7 checks: xcode_version, swift_version, toolchain_path, cache_dir_health, library_evolution_compatibility, remote_backend_connectivity, companion_binary) and prints a color-coded green/yellow/red report with per-check fix hints
2. `spm-cache doctor --json` emits the same diagnostics as a JSON document
3. Checks are addable/removable via config without editing the command (data-driven registry)
4. `doctor` is unit-testable via injected shell-output collectors (no real Xcode install required)

### Phase 3: Project Bootstrap
**Goal:** Deliver `spm-cache init` — an interactive wizard that bootstraps a new project to a working `spm-cache.yml` + seeded lockfile in one command, removing cold-start friction.
**Requirements:** ONBD-01, ONBD-02, ONBD-03
**Success Criteria**:
1. `spm-cache init` detects `.xcodeproj`, prompts for platforms/config/remote-backend, and generates `spm-cache.yml` + a `spm-cache.lock` seeded from `Package.resolved` so the first `use` hits the fast path
2. Non-interactive flags (`--platform`, `--config`, `--remote`, `--remote-url`, `--branch`) work for scripting/CI
3. Re-running `init` idempotently diff-merges (preserves user keys, adds defaults, never overwrites) and appends `spm-cache/` to `.gitignore` once
4. `init` passes its regression spec (`init_spec.rb`) in a tmpdir with a fixture `.xcodeproj`

### Phase 4: CI GitHub Action
**Goal:** Ship `phuongddx/spm-cache-action@v1` as a thin CI wrapper so teams can restore/save cache with a 5-line workflow — the adoption accelerant.
**Requirements:** ONBD-04
**Success Criteria**:
1. The Action (in its separate repo) accepts `command`, `backend`, `backend-url`, `config` inputs
2. The Action shells out to the installed gem (no logic duplication) and runs `pull`/`push`/`sync`
3. The Action is smoke-tested in its own repo's CI

### Phase 5: Auto-Sync Watcher
**Goal:** Deliver `spm-cache watch` — a filesystem-watch mode that auto-regenerates the proxy package when the Xcode SPM graph changes, deepening the structural moat (zero-touch auto-sync that Scipio/xccache cannot match).
**Requirements:** AUTO-01, AUTO-02, AUTO-03, AUTO-04, AUTO-05
**Success Criteria**:
1. `spm-cache watch` watches `Package.resolved` + `project.pbxproj` and regenerates the proxy via `Installer::Use` on a non-empty diff, with no manual re-run
2. Burst saves collapse via configurable debounce (default 2s, `--debounce`) to one regeneration
3. `watch --once` performs a single sync-and-exit (CI/testing) without the watch loop
4. The loop continues on transient errors (logs with timestamp) and exits non-zero only on fatal conditions; SIGINT/SIGTERM flush + exit 0
5. FSEvents binds via Ruby `Fiddle` (stdlib) with no new gem dependency; `--once` path is unit-testable without the OS API

---

**Coverage:** 12/12 v1 requirements mapped across 5 phases ✓
