# spm-cache

## What This Is

`spm-cache` is a macOS CLI tool that caches Swift Package Manager dependencies as `.xcframework` binaries and swaps them transparently at the SPM manifest level using a proxy-package architecture. It reads the Xcode project directly, auto-detects SPM graph changes, and falls back to source compilation on cache miss — no separate manifest, no manual drag-drop. It ships as a Ruby gem with a Swift companion binary, distributed via Homebrew and RubyGems, for iOS/macOS development teams, CI pipelines, and individual developers who want faster clean builds.

## Core Value

Reduce Xcode clean build times by serving prebuilt SPM dependency binaries transparently, with automatic fallback to source compilation on cache miss — so a cache hit never breaks a build.

## Current Milestone: v0.4.0 Build Fidelity & Release Automation

**Goal:** Make cached builds faithful to the host app's resolved dependency graph, and repair the Homebrew release path so shipping stops requiring manual steps.

**Target features:**
- Package builds resolve transitive dependencies from the host project's resolved graph, not each package's own committed `Package.resolved`
- Regression coverage proving transitive-version drift cannot silently return
- `TAP_REPO_TOKEN` repaired so `update-tap.yml` publishes the Homebrew formula without manual intervention

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
- ✓ Test CI pipeline (`ci.yml`) — full RSpec + swift-test suite on every PR/push, proxy binary built on every ruby-tests leg — Phase 1 (v0.3.0)
- ✓ `spm-cache doctor` — 7-check data-driven registry, marker report + fix hints, `--json`, hermetic Core::Sh-seam specs, companion `--version` probe working (0.3.0) — Phase 2 (v0.3.0)
- ✓ `spm-cache init` — 7-flag bootstrap wizard, TTY-conditional prompts, idempotent yml diff-merge, canonical lockfile seeding (init→use fast path proven) — Phase 3 (v0.3.0)
- ✓ GitHub Action (`action/` → `phuongddx/spm-cache-action`) — 6-input thin composite, `--default-config` wiring fixed, 12-example structural spec; publication is a release-checklist item — Phase 4 (v0.3.0)
- ✓ `spm-cache watch` — mtime+size polling (user-accepted 2026-08-24, supersedes FSEvents design), debounce 2s, `--once`, signal-safe flush (INT/TERM masked during flush), self-trigger guard — Phase 5 (v0.3.0)
- ✓ Package builds resolve transitive dependencies from the host project's resolved graph (fixes release-config cache builds linking stale transitive versions) — Phase 6 (canonical locator + lockfile reconciliation) + Phase 7 (host-graph seeding, vendored-project classification, no perf regression) (v0.4.0)

### Active

- [ ] Regression coverage proving transitive-version drift cannot silently return — v0.4.0
- [ ] `update-tap.yml` publishes the Homebrew formula unattended (`TAP_REPO_TOKEN` valid) — v0.4.0

### Out of Scope

- CocoaPods support — spm-cache is SPM-only; CocoaPods is served by Rugby/cocoapods-binary
- App-target caching — only SPM dependencies are cached; caching app code is XCRemoteCache/Bazel territory
- Content-addressed cache keys — HIGH effort, deferred to v0.5 (Team Features)
- Selective/partial caching (only changed deps) — deferred to v0.3.x/v0.4
- Mergeable libraries support — parity feature, deferred to v0.4
- Non-macOS platforms — the tool relies on the macOS/Xcode toolchain
- RubyGems publication (`gem push`) — deferred by user decision 2026-08-27; Homebrew remains the working distribution channel
- `gem install spm-cache` verification — depends on RubyGems publication; deferred with it
- GitHub Action + its own-repo smoke CI — the action's `gem install spm-cache` step cannot succeed while the gem is unpublished, so the action stays published-but-non-functional; broken-window #2 waived rather than closed

## Context

`spm-cache` is at v0.3.0 (code complete, pending release). The v0.2.x line was a series of field-bugfix releases (identity collisions, wrong product names, plugin-only packages, version drift, stale metadata), mature and field-tested on 59–70 package real-project runs. The v0.3.0 Mixed cycle deepened the moat (`watch` auto-sync), removed adoption friction (`init` + GitHub Action), and hardened reliability (`doctor` + full-suite test CI); all five phases verified 2026-08-24 with 258-example CI-green coverage. The competitive landscape (`competitive-analysis-2026-07.html`) still shows two direct SPM competitors: Scipio (544★, Swift-native, requires a separate hand-written manifest) and xccache (71★, Ruby gem, shares the proxy-package architecture). spm-cache's structural moat — reads the Xcode project directly, integrates transparently, now auto-syncs — remains unmatched without rearchitecting.

Known state after v0.3.0: test CI runs the full suite on every PR/push (was: none); `build_pipeline.rb` and `installer.rb` remain complexity hotspots; shell-string interpolation in `core/git.rb` is still a low-but-present injection surface; Ruby↔Swift version drift is now VISIBLE via `doctor`'s companion_binary check (`--version` probe) though not compared. Release checklist outstanding: gemspec homepage placeholder, `gem push` 0.3.0, publish `phuongddx/spm-cache-action`, tag v1, action-repo smoke CI.

## Constraints

- **Tech stack**: Ruby gem (>= 3.0) + Swift 6.0 companion tool; macOS-only (Xcode toolchain) — `core/sh.rb` shells out to swift/xcodebuild
- **Distribution**: Homebrew tap (`phuongddx/spm-cache`) + RubyGems; GitHub account `phuongddx` for releases
- **Architecture**: proxy-package swap at the SPM manifest level; lockfile (`spm-cache.lock`) + config (`spm-cache.yml`) as the state surface
- **Compatibility**: no new runtime gem dependencies without justification (watch uses stdlib mtime polling to avoid `listen`)
- **GitHub Action**: must live in a separate repo per `uses:` resolution rules

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| v0.3.0 direction = Mixed (features + hardening) | User chose balanced cycle — moat + adoption + reliability | ✓ Shipped — 5/5 phases verified 2026-08-24 |
| `watch` uses stdlib mtime+size polling, not `listen` gem | zero native binding, portable, avoids new dependency; binding design superseded 2026-08-24 (05-CONTEXT) | ✓ Shipped Phase 5 — stdlib polling (amended 2026-08-24) |
| `watch` watches only Package.resolved + project.pbxproj | Whole .xcodeproj bundle is too noisy (Xcode rewrites many files) | ✓ Shipped Phase 5 |
| `init` re-runs are idempotent diff-merge | Mirrors `use` diff philosophy; prevents data loss | ✓ Shipped Phase 3 — byte-stable double-run proven |
| init seeds spm-cache.lock in canonical consumer shape | Pins byte-copy crashed `use` (TypeError, diff_detector.rb:103); canonical shape reuses installer mapping | ✓ Phase 3 — DiffDetector consumes seeded lock: "No changes detected" |
| companion CLI exposes `--version` (CommandConfiguration version:) | Makes Ruby↔Swift drift visible in `doctor`; honors accepted 2026-08-24 decision | ✓ Phase 2 — `spm-cache-proxy --version` → 0.3.0, exit 0 |
| Action shells out thin: setup-ruby → gem install → init → remote | Zero logic duplication; `uses:` resolution requires the separate repo | ✓ Shipped in-repo Phase 4 (d9a4c4e flag fix); publish + own-repo CI smoke = release checklist |
| ruby-tests builds the proxy binary before RSpec; Ruby matrix is 3.1–3.3 | Binary-gated gen_proxy specs (23/218) silently skipped without the build; 3.0 dropped at merge 5759c5b (gemspec >= 3.1.0) | ✓ Proven 2026-08-24: 218 examples, 0 failures, 0 pending |
| Content-addressed cache deferred to v0.5 | HIGH effort; current lockfile-based key is adequate for v0.3 | — Pending (carried) |
| v0.4.0 direction = build fidelity + release automation | Only known correctness failure (release-config builds link stale transitive versions) strikes the core value directly; Homebrew automation is small and independent | — Pending |
| RubyGems publication deferred out of v0.4.0 | User decision 2026-08-27; Homebrew builds from the GitHub release tarball and needs no gem on RubyGems | — Pending |
| Host graph seeded verbatim before first `swift package describe`, no `-onlyUsePackageVersionsFromResolvedFile` flag | Xcodebuild silently upgrades a seeded pin below a package's manifest floor rather than hard-failing; detecting that drift is Phase 8's job, not Phase 7's | ✓ Shipped Phase 7 — FID-02/FID-05 complete |
| Shared `-clonedSourcePackagesDirPath` + process-level build lock | Verbatim host-graph seeding fans out per-package clones; a shared clone dir plus a lock closing the watch/build race were required to avoid a wall-clock/disk regression | ✓ Shipped Phase 7 — PERF-01: -40.6% wall-clock, -34% disk vs pre-seeding baseline on the reference project |

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
*Last updated: 2026-08-29 after Phase 7*
