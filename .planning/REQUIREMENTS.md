# Requirements: spm-cache v0.3.0

**Defined:** 2026-08-10
**Core Value:** Reduce Xcode clean build times by serving prebuilt SPM dependency binaries transparently, with automatic fallback to source on cache miss.

## v1 Requirements

### Reliability

- [x] **REL-01**: Test CI pipeline (`.github/workflows/ci.yml`) runs the full RSpec + `swift test` suite on every PR and push to main (Ruby 3.0–3.3 × macOS-latest matrix), separate from the release-only `update-tap.yml`
- [ ] **REL-02**: `spm-cache doctor` runs a data-driven registry of diagnostic checks (Xcode version, Swift version, toolchain path, cache-dir health/orphans, library-evolution compatibility, remote-backend connectivity, companion-binary presence) and prints a color-coded green/yellow/red report with per-check fix hints
- [ ] **REL-03**: `spm-cache doctor --json` emits the same diagnostics as a machine-readable JSON document for CI consumption

### Onboarding

- [ ] **ONBD-01**: `spm-cache init` interactively bootstraps a project — detects `.xcodeproj`, prompts for platforms/config/remote-backend, and generates `spm-cache.yml` + a `spm-cache.lock` seeded from `Package.resolved` so the first `use` is a fast path
- [ ] **ONBD-02**: `spm-cache init` supports non-interactive flags (`--platform`, `--config`, `--remote`, `--remote-url`, `--branch`) for scripting/CI
- [ ] **ONBD-03**: Re-running `spm-cache init` on an existing config performs an idempotent diff-merge (preserves user keys, adds new defaults, never overwrites) and appends `spm-cache/` to `.gitignore` once
- [ ] **ONBD-04**: `phuongddx/spm-cache-action@v1` (separate repo) restores/saves cache in CI via a thin shell-out to the gem, configurable with `command`, `backend`, `backend-url`, `config` inputs in a 5-line workflow

### Auto-Sync

- [ ] **AUTO-01**: `spm-cache watch` watches `Package.resolved` + `project.pbxproj` for changes and auto-regenerates the proxy package via the `Installer::Use` path, with no manual re-run
- [ ] **AUTO-02**: `watch` collapses burst saves via a configurable debounce (default 2s, `--debounce`) so a single Xcode package-add triggers one regeneration
- [ ] **AUTO-03**: `watch --once` performs a single sync-and-exit (for CI/testing) without starting the filesystem-watch loop
- [ ] **AUTO-04**: `watch` continues the loop on transient regeneration errors (logs with timestamp) and only exits non-zero on fatal conditions (project deleted/unwatchable); SIGINT/SIGTERM flush pending events and exit 0
- [ ] **AUTO-05**: `watch` binds FSEvents via Ruby `Fiddle` (stdlib) with no new gem dependency

## v2 Requirements

### Cache Correctness

- **CACH-01**: Content-addressed cache keys (SHA of source + build flags + toolchain) replace lockfile-based keys — no false hits across code-identical/version-different commits
- **CACH-02**: Selective/partial caching builds only packages whose source changed plus their dependents (`spm-cache build --incremental`)

### Parity

- **PAR-01**: Mergeable libraries support (`spm-cache build --framework-type mergeable|dynamic|static`) with per-package overrides and binary-size warning

## Out of Scope

| Feature | Reason |
|---------|--------|
| CocoaPods support | spm-cache is SPM-only; CocoaPods served by Rugby/cocoapods-binary |
| App-target caching | Only SPM dependencies cached; app-code caching is XCRemoteCache/Bazel territory |
| Non-macOS platforms | Tool relies on the macOS/Xcode toolchain |
| `cachemap --open` polish | Already partially shipped; visualization refinement deferred |
| Plugin-only local packages | Out of scope since v0.2.0 (auto-skipped) |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| REL-01 | Phase 1 | Complete |
| REL-02 | Phase 2 | Pending |
| REL-03 | Phase 2 | Pending |
| ONBD-01 | Phase 3 | Pending |
| ONBD-02 | Phase 3 | Pending |
| ONBD-03 | Phase 3 | Pending |
| ONBD-04 | Phase 4 | Pending |
| AUTO-01 | Phase 5 | Pending |
| AUTO-02 | Phase 5 | Pending |
| AUTO-03 | Phase 5 | Pending |
| AUTO-04 | Phase 5 | Pending |
| AUTO-05 | Phase 5 | Pending |

**Coverage:**
- v1 requirements: 12 total
- Mapped to phases: 12
- Unmapped: 0 ✓

---
*Requirements defined: 2026-08-10*
*Last updated: 2026-08-10 after initial definition*
