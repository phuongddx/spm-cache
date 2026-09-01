# spm-cache

## What This Is

`spm-cache` is a macOS CLI tool that caches Swift Package Manager dependencies as `.xcframework` binaries and swaps them transparently at the SPM manifest level using a proxy-package architecture. It reads the Xcode project directly, auto-detects SPM graph changes, and falls back to source compilation on cache miss — no separate manifest, no manual drag-drop. It ships as a Ruby gem with a Swift companion binary, distributed via Homebrew (RubyGems publication deferred), for iOS/macOS development teams, CI pipelines, and individual developers who want faster clean builds.

## Core Value

Reduce Xcode clean build times by serving prebuilt SPM dependency binaries transparently, with automatic fallback to source compilation on cache miss — so a cache hit never breaks a build.

## Current State: v0.4.0 shipped (2026-08-31)

Build fidelity closed end-to-end: cached builds are compiled, verified, and invalidated
against the host app's resolved dependency graph (canonical locator → host-graph seeding →
drift read-back + provenance sidecars → provenance-gated cache hits), pinned by hermetic
regression specs (441 examples). Release automation repaired and live-proven: rewritten
`update-tap.yml` (every failure loud, deploy-key auth, byte-stable asset pinning, first real
tap push landed 2026-08-31), `--version` intercept working. Remaining operator step: the
v0.4.0 release cut itself (bump VERSION → tag → attach tarball asset → watch first fully-green
verify-publish).

## Current Milestone: v0.5.0 Web Interface

**Goal:** Give spm-cache a local web dashboard — live-streaming build logs, per-package
cache control, and cache/health visibility for the current project.

**Target features:**
- `spm-cache web` subcommand: localhost server + browser open, dashboard for the current project
- Live streaming build logs in the browser — from UI-triggered builds (Build/Rebuild button) AND from terminal/`watch`-initiated runs relayed to the server
- Per-package cache on/off toggles persisted in config, honored by build/use/rollback (same source of truth as `spm-cache off`)
- Cache state table: per-package sizes, cached/source state, fidelity status
- Embedded cachemap dependency graph (today's HTML viz as a dashboard view)
- Doctor health panel reusing the 7-check registry

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
- ✓ The fidelity contract is pinned by hermetic specs (drift regression, six-bucket partition coverage, 8-class v0.2.x edge matrix — 416 examples green on the Ruby 3.1–3.3 CI matrix, no network, no real xcodebuild) — Phase 10 (v0.4.0)
- ✓ Release automation end-to-end: `update-tap.yml` publishes the Homebrew formula unattended via a scoped write deploy key (`TAP_DEPLOY_KEY`), every failure mode loud, integrity-gated byte-stable tarball pinning, idempotent re-runs, and a brew verify job whose version assertion demonstrably has teeth — live-proven including a real tap push (2026-08-31) — Phase 11 (v0.4.0)
- ✓ `spm-cache --version` prints the gem version and exits 0 (pre-CLAide intercept) — Phase 11 (v0.4.0)
- ✓ Run-log capture foundation — every CLI run (except `web`/`watch` verbs and `--no-run-log`) leaves a complete queryable JSONL run log: credential-redacted argv header, full-fidelity stream body, structured `run_start`/`phase`/`package_*`/`sh`/`run_end` event vocabulary, and hybrid count+size retention (50 runs / 500 MB) — Phase 12 (v0.5.0)
- ✓ `spm-cache web` read-only dashboard — hardened localhost WEBrick server (Host/Origin/token middleware, 25-cell route×auth matrix), fully-offline 4-asset frontend (vendored cytoscape), three read-model panels (state/doctor/graph) sharing the CLI's exact read paths; live-browser-verified after the G-13-1 asset-path gap closure — Phase 13 (v0.5.0)

### Active


- [ ] Web dashboard served locally for the current project (`spm-cache web`)
- [ ] Live streaming build logs from UI-triggered and terminal/`watch` builds
- [ ] Per-package cache on/off toggles persisted and honored end-to-end
- [ ] Cache state table with sizes and fidelity status
- [ ] Cachemap dependency graph embedded in the dashboard
- [ ] Doctor health panel in the browser

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
- **Web UI**: localhost-only binding, no remote exposure; server stack must justify any new runtime gem dependency (research question)

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| v0.3.0 direction = Mixed (features + hardening) | User chose balanced cycle — moat + adoption + reliability | ✓ Shipped — 5/5 phases verified 2026-08-24 |
| `watch` uses stdlib mtime+size polling, not `listen` gem | zero native binding, portable, avoids new dependency; binding design superseded 2026-08-24 (05-CONTEXT) | ✓ Shipped Phase 5 — stdlib polling (amended 2026-08-24) |
| Run logs live in `.spm-cache/runs/` as file-tail JSONL; header redacts credentials, body stays verbatim | Relay transport for Phase 14 streaming chosen over UDS at research; full-fidelity body is the offline-reconstruction contract (D-05), retention is the disk-fill bound (T-12-04) | ✓ Shipped Phase 12 — 5/5 plans, verification passed, UAT 2/2, threats_open 0 |
| Dashboard asset refs are relative `assets/…` and every integration assertion resolves scanned refs with browser semantics (URI.join vs document origin) | Test-side `/assets/#{ref}` re-prefixing hid a ship-blocking 404 (all three assets) from 119 green examples; the first real-browser exercise caught it in minutes — no JS runtime in CI means served-bytes pins must include "the HTML points there" | ✓ Shipped Phase 13 — 5/5 plans + G-13-1 gap closure; verification 23/23; UAT 6/6 (one on user-accepted evidence); SECURITY SECURED 23/23 |
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
| Regression coverage observes BOTH production surfaces (Ruby sidecar statuses + Swift graph.json) with fail-first mutation-proven assertions, not just passing examples | An implemented feature is not a done phase (v0.3.0 lesson) — a regression spec that can't fail is false assurance; the partition must catch zero-bucket AND double-bucket misses | ✓ Shipped Phase 10 — TEST-01/02/03 verified 23/23, review converged after WR-01/02 fixes |
| Fidelity violation → warn + source fallback, never hard-fail; missing provenance ⇒ cache miss (one-time rebuild) | Core Value: a cache hit never breaks a build; grandfathering would keep serving artifacts built against unverified graphs | ✓ Shipped v0.4.0 — Phase 8/9 |
| Tap credential = scoped write deploy key (not GitHub App token, not classic PAT) | Operator-authorized pivot at the Phase 11 blocking-human gate 2026-08-31: single-repo scope, no workflow reach, non-expiring; classic PAT re-mint rejected (the one-year auto-delete caused the outage) | ✓ Shipped Phase 11 — REL-04 as long-lived machine credential (dated accepted deviation) |
| Resolution-incompatible classification runs strictly on the success path, never via `raise` | Structurally unmaskable by `ignore_build_errors?` — a package that can't satisfy the host graph still builds and caches, just gets reported, never hard-fails | ✓ Shipped Phase 8 — FID-04 |
| Provenance sidecar write is atomic (tempfile + rename) and never raises on I/O failure | A metadata-write failure must never be mistaken for a build failure — the xcframework it describes already built successfully | ✓ Shipped Phase 8 (WR-03 code-review fix) |
| Missing provenance ⇒ unconditional cache miss; pin comparison is intersection-only (absence never drift); `fast_path?` version stamp forces one regen after any spm-cache upgrade | The only invalidation design that delivers the fidelity fix to existing users without needlessly emptying the cache on unrelated bumps | ✓ Shipped Phase 9 — CACHE-02/CACHE-03 verified, SC5 operator-PASS |
| Regression coverage observes BOTH production surfaces (Ruby sidecar statuses + Swift graph.json) with fail-first mutation-proven assertions, not just passing examples | An implemented feature is not a done phase (v0.3.0 lesson) — a regression spec that can't fail is false assurance; the partition must catch zero-bucket AND double-bucket misses | ✓ Shipped Phase 10 — TEST-01/02/03 verified 23/23, review converged after WR-01/02 fixes |

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
*Last updated: 2026-09-01 after Phase 12 (Run-Log Capture Foundation)*
