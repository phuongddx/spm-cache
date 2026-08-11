# spm-cache

## What This Is

`spm-cache` is a macOS CLI tool that caches Swift Package Manager dependencies as `.xcframework` binaries and swaps them transparently at the SPM manifest level using a proxy-package architecture. It reads the Xcode project directly, auto-detects SPM graph changes, and falls back to source compilation on cache miss — no separate manifest, no manual drag-drop. It ships as a Ruby gem with a Swift companion binary, distributed via Homebrew and RubyGems, for iOS/macOS development teams, CI pipelines, and individual developers who want faster clean builds.

## Core Value

Reduce Xcode clean build times by serving prebuilt SPM dependency binaries transparently, with automatic fallback to source compilation on cache miss — so a cache hit never breaks a build.

## Requirements

### Validated

- ✓ Proxy-package architecture that swaps binaries at the SPM manifest level — v0.1.0
- ✓ `spm-cache use` auto-integrates proxy package into the Xcode project from `.xcodeproj` — v0.1.0
- ✓ `spm-cache build [TARGETS]` builds targets into `.xcframework` files — v0.1.0
- ✓ Cache-miss automatic fallback to source compilation — v0.1.0
- ✓ `spm-cache rollback` restores original project state — v0.1.0
- ✓ Per-configuration caching (Debug/Release separate) — v0.1.0
- ✓ Multi-slice xcframeworks (`--sdk=all`, simulator + device) — v0.1.0
- ✓ Swift Macro targets built and cached as `.macro` binaries — v0.1.0
- ✓ Resource-bundle handling (`Bundle.module` works in cached frameworks) — v0.1.0
- ✓ Library evolution flags applied for binary compatibility — v0.1.0
- ✓ Remote cache via Git and S3 (`remote push`/`remote pull`) — v0.1.0
- ✓ `spm-cache off [TARGETS]` forces source mode per target — v0.1.0
- ✓ `cache list` / `cache clean` cache management — v0.1.0
- ✓ Interactive cachemap visualization (HTML dependency graph) — v0.1.0
- ✓ Auto-sync diff detection (DiffDetector reads Package.resolved + pbxproj) — v0.2.0
- ✓ Plugin-only / transitive-only / binary-target package edge-case handling — v0.2.0–v0.2.8

### Active

- [ ] `spm-cache watch` — filesystem-watch mode that auto-regenerates the proxy package when the Xcode SPM graph changes (v0.3.0 moat feature)
- [ ] `spm-cache init` — interactive project bootstrap wizard generating `spm-cache.yml` + seeded lockfile (v0.3.0 adoption feature)
- [ ] GitHub Action (`phuongddx/spm-cache-action`) — thin CI wrapper for cache restore/save (v0.3.0 adoption feature)
- [ ] `spm-cache doctor` — environment diagnostics with green/yellow/red report + `--json` output (v0.3.0 reliability feature)
- [ ] Test CI pipeline (`.github/workflows/ci.yml`) — runs RSpec + `swift test` on every PR (v0.3.0 reliability feature)

### Out of Scope

- CocoaPods support — spm-cache is SPM-only; CocoaPods is served by Rugby/cocoapods-binary
- App-target caching — only SPM dependencies are cached; caching app code is XCRemoteCache/Bazel territory
- Content-addressed cache keys — HIGH effort, deferred to v0.5 (Team Features)
- Selective/partial caching (only changed deps) — deferred to v0.3.x/v0.4
- Mergeable libraries support — parity feature, deferred to v0.4
- Non-macOS platforms — the tool relies on the macOS/Xcode toolchain

## Context

`spm-cache` is at v0.2.8, mature and field-tested (59–70 package real-project runs). The v0.2.x line was a series of field-bugfix releases (identity collisions, wrong product names, plugin-only packages, version drift, stale metadata). The competitive landscape (`competitive-analysis-2026-07.html`) shows two direct SPM competitors: Scipio (544★, Swift-native, requires a separate hand-written manifest) and xccache (71★, Ruby gem, shares the proxy-package architecture). spm-cache's structural moat is that it reads the Xcode project directly and integrates transparently — Scipio cannot match this without rearchitecting. The v0.3.0 cycle deepens that moat (`watch`), removes adoption friction (`init` + Action), and hardens reliability (`doctor` + test CI). The design spec is at `docs/superpowers/specs/2026-08-10-v0.3.0-watch-init-doctor-design.md`.

Known gaps from the codebase map: no CI runs the test suite today (only the release Homebrew-tap updater); `build_pipeline.rb` (919 LOC) and `installer.rb` (578 LOC) are complexity hotspots; shell-string interpolation in `core/git.rb` is a low-but-present injection surface; Ruby↔Swift companion version drift has no explicit handshake.

## Constraints

- **Tech stack**: Ruby gem (>= 3.0) + Swift 6.0 companion tool; macOS-only (Xcode toolchain) — `core/sh.rb` shells out to swift/xcodebuild
- **Distribution**: Homebrew tap (`phuongddx/spm-cache`) + RubyGems; GitHub account `phuongddx` for releases
- **Architecture**: proxy-package swap at the SPM manifest level; lockfile (`spm-cache.lock`) + config (`spm-cache.yml`) as the state surface
- **Compatibility**: no new runtime gem dependencies without justification (watch uses native FSEvents to avoid `listen`)
- **GitHub Action**: must live in a separate repo per `uses:` resolution rules

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| v0.3.0 direction = Mixed (features + hardening) | User chose balanced cycle — moat + adoption + reliability | — Pending |
| `watch` uses native FSEvents via Fiddle, not `listen` gem | macOS-only tool; avoids new dependency; ~80-line binding | — Pending |
| `watch` watches only Package.resolved + project.pbxproj | Whole .xcodeproj bundle is too noisy (Xcode rewrites many files) | — Pending |
| `init` re-runs are idempotent diff-merge | Mirrors `use` diff philosophy; prevents data loss | — Pending |
| `doctor` uses data-driven check registry | Checks addable/removable via config; no command edits | — Pending |
| Test CI is a separate `ci.yml` from release `update-tap.yml` | Release workflow stays focused; test pipeline runs on every PR | — Pending |
| GitHub Action is a separate thin repo shelling out to the gem | GitHub `uses:` requirement; logic stays in the gem | — Pending |
| Content-addressed cache deferred to v0.5 | HIGH effort; current lockfile-based key is adequate for v0.3 | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `$gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `$gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-08-10 after initialization*
