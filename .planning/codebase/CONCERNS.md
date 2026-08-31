---
title: Codebase Concerns
focus: concerns
mapped_date: 2026-08-31
last_mapped_commit: fdb3a70abe81852ec9310a3ff410341a4adcfa0c
---

# Codebase Concerns

<!-- refreshed: 2026-08-31 -->

A scan of `lib/` and `tools/spm-cache-proxy/Sources/` found **no `TODO`/`FIXME`/`HACK`/`XXX` markers** (re-verified 2026-08-31). The concerns below are inferred from code structure, size, shell-out surface, field-bug history, process lifecycle analysis, and the v0.4.0 phase record (`.planning/phases/06..11*/`).

**Status convention:** every item carries `OPEN`, `RESOLVED <date>`, or `DEFERRED <date> <scope>`.

## Closed by v0.4.0 (Phases 6–9, 2026-08-27 → 08-29) — no longer open

- **Stale `Package.resolved` locator (FID-06, the M1 root cause).** `Dir.glob(...).find` byte-order selection of a nested git-ignored copy is gone: `lib/spm_cache/core/package_resolved.rb` resolves the canonical `project.xcworkspace/xcshareddata/swiftpm/Package.resolved` via exact path (tier 1), workspace glob (tier 2), filtered recursive (tier 3), filtered parent (tier 4, DiffDetector only). Covered by `spec/package_resolved_spec.rb`.
- **Never-refreshed lockfile (FID-01).** `Installer#reconcile_lockfile_from_host_graph` (`lib/spm_cache/installer.rb:164-203`) now refreshes `version`/`revision` in place from the host graph on every non-fast-path run, drops removed entries, appends new ones, and preserves enriched `products[]`. Covered by `spec/lockfile_reconciliation_spec.rb`.
- **Isolated per-package upward re-resolution (FID-02).** `BuildPipeline#seed_host_graph` (`lib/spm_cache/spm/build_pipeline.rb`) seeds `SPM::ResolvedGraph` (shared clone dir + flock, `lib/spm_cache/spm/resolved_graph.rb`, `spec/build_pipeline_seeding_spec.rb`, `spec/resolved_graph_spec.rb`) before per-target builds; `-onlyUsePackageVersionsFromResolvedFile` deliberately not enabled (locked decision D-02).
- **Cache invalidation gap (`Cache.swift hit()` bare name + `fileExists`).** The Swift companion's hit decision is now provenance-aware (CACHE-02, Phase 9): `hit(module:identity:currentPin:)` in `tools/spm-cache-proxy/Sources/Core/Cache.swift` compares the `.xcframework.provenance.json` sidecar pin against the lockfile pin; absent/unparsable sidecar is an unconditional miss; intersection-only so Class E (not-graph-pinned) steady states still hit. The Ruby fast path gained an `spm_cache_version` stamp guard (`lib/spm_cache/installer.rb:417,433-437`) so any spm-cache bump forces one full regen.
- **Watcher SIGTERM handling.** `lib/spm_cache/core/watcher.rb` traps `TERM` (raising `Interrupt`), masks further signals during shutdown, and flushes a pending change on interrupt (v0.3.0 Phase 05). Covered by `spec/watch_signals_spec.rb`.
- **Phase 7 review Criticals.** CR-01: `Installer::Use` build lock now covers trailing `gen_supporting_files`/`integrate_proxy_into_project`/`gen_cachemap_viz` on both fast and non-fast paths (commits `c3bb440`, `c5d1aaa`); CR-02: `Installer::Build#slice_complete?` forces a rebuild when a "hit" module's xcframework is missing from disk (commit `a915188`).
- **`--targets` filtering / alias-expansion test gap.** `spec/installer_build_spec.rb` now covers target filtering, ignore/cache_only exclusions, and package-identity alias expansion (library-only vs plugin products).
- **Doctor lock-vs-resolved drift check (DIAG-01).** `lock_graph_fidelity` registered in `lib/spm_cache/core/diagnostics.rb:289-298`; drift warns, never fails. Covered by `spec/doctor_lock_fidelity_spec.rb`.

## Tech Debt

**BuildPipeline monolith (1,177 lines, `lib/spm_cache/spm/build_pipeline.rb`):** OPEN
- Grew from 919 lines over v0.4.0 (host-graph seeding, drift read-back `report_fidelity`, provenance sidecar write/cleanup, Class E redirect, private-Clang shims). It still carries ~15 named field-bug workarounds (SVGKit scheme disambiguation, FirebaseAnalytics forwarding chains, FirebaseCore object-file fan-out, AEXML BUILD_LIBRARY_FOR_DISTRIBUTION, DeviceKit gyb write-permission, SkeletonView space-in-scheme, CryptoSwift vendored-framework detection, AppAuth-iOS deployment-target, …). Each is correct in isolation; the file is hard to navigate and unit-test.
- Fix approach: extract focused modules (`SchemeResolver`, `ForwardedTargetResolver`, `CompanionDetector`, `FrameworkRenamer`); field-bug comments travel with the extracted code.

**Installer pbxproj surgery (707 lines, `lib/spm_cache/installer.rb`):** OPEN
- `integrate_proxy_into_project` (`lib/spm_cache/installer.rb:493+`) performs a full SPM-graph replacement inside a live `.pbxproj`: deletes product dependencies, removes package references, adds a single local proxy ref, re-creates every dependency. A partial failure mid-rewrite leaves the project broken and unrecoverable by re-running spm-cache. `purge_orphaned_spm_objects` (`lib/spm_cache/installer.rb:92`) exists because earlier versions accumulated orphaned PBXObjects across runs.
- Mitigated since the last audit: process-level blocking flock now wraps the whole `use` path (`lib/spm_cache/installer/build.rb:69-77`, `spec/build_lock_spec.rb`), and `spec/installer_integrate_proxy_spec.rb` (329 lines) drives the surgery directly against fixture projects (plugin refs, excluded products, orphan purge, idempotent re-runs).
- Fix approach: write-then-swap — build the new graph in a temporary in-memory `Xcodeproj::Project`, verify, atomically replace on disk; extend `lib/spm_cache/installer/rollback.rb` as the recovery path.

**Manifest text-scraping fallback (`lib/spm_cache/installer.rb:472-490`):** OPEN
- When `swift package describe` fails, product names are regex-scraped from `Package.swift` text; the `[^)]*` scan truncates on nested parentheses. The v0.2.x `binaryTarget` fabrication bug came from this path being too permissive.
- Impact: wrong product names make the proxy generator emit non-existent dependencies; the Xcode build breaks outright.
- Fix approach: fall back to `swift package dump-package` (JSON) before regex.

**`FrameworkSlice` is unwired dead code with three independent defects:** DEFERRED 2026-08-29 (Phase 10 Plan 03 zero-production-change scope; `.planning/phases/10-fidelity-regression-coverage/deferred-items.md`)
- `lib/spm_cache/spm/xcframework/slice.rb` has no production callers (only the autoload at `lib/spm_cache/spm/xcframework/xcframework.rb:6`), and its public `create_framework` can never complete a real run: (1) `Desc::Target#resource_paths` is private (`lib/spm_cache/spm/desc/target.rb:123` sits below the first `private`), so slice.rb's `respond_to?(:resource_paths)` guards are always false; (2) slice.rb:64 calls bare `Sh.run` — a `NameError` in that namespace (`Sh` resolves only as `Core::Sh`); (3) its `Utils::Template.render_to` plist templates bind no `module_name` (`lib/spm_cache/spm/utils/template.rb:22` binds the template's own context); the live path inlines the plist instead (`lib/spm_cache/spm/build.rb:383`).
- Consequence: on the live assembled-framework path, resource bundles are NOT copied from build products; the only bundle-preserving route is `Buildable#use_existing_framework`'s full `cp_r`. `spec/fidelity_edge_matrix_spec.rb` drives `copy_resource_bundles` semantics directly via `send` to pin the real behavior.
- Fix approach (product decision): either delete `FrameworkSlice` or wire and repair it (public `resource_paths`, qualified `Core::Sh`, fixed template binding).

**Class E binaryTarget rename gap:** DEFERRED (pre-existing; explicitly out of Phase 7 scope, 2026-08-29)
- `lib/spm_cache/spm/build_pipeline.rb:1070-1073` raises `"...name differs from product '...'; renaming a prebuilt xcframework's slices is not implemented"` when a `.binaryTarget`'s target name differs from its product name. Live trigger: FirebaseAnalyticsCore / FirebaseIdentitySupport / FirebaseAnalyticsWithoutAdIdSupport are all backed by one differently-named `FirebaseAnalytics` binaryTarget — 3 of 29 targets on the reference project fail this way (documented in `.planning/phases/07-host-faithful-checkout-seeding/07-BENCHMARK.md`).
- Impact: those targets always miss the cache and fall back to source; the reference project needs `ignore_build_errors: true` in `spm-cache.yml` to complete a run.
- Fix approach: implement slice-directory renaming in `copy_prebuilt_binary_target`, or teach the proxy generator to declare the real binaryTarget name per product. Note Phase 9's hit() intersection-only comparison means Class E steady states are NOT treated as drift (`lib/spm_cache/spm/build_pipeline.rb:108-112`).

**Sleep-based timing specs (`spec/build_lock_spec.rb`):** DEFERRED 2026-08-29 (WR-05, `.planning/phases/07-host-faithful-checkout-seeding/07-REVIEW-FIX.md`)
- Two fork-based lock-contention proofs use brief `sleep` rendezvous / `elapsed >= 0.3` assertions. Review judged practical flake risk low (pipe rendezvous + `Process.wait`; CI delays only make the elapsed assertion truer). Rewriting them risked subtle damage to load-bearing proofs — deliberately kept.

**Config Info-level items:** DEFERRED 2026-08-29 (IN-01..03, Info findings out of `fix_scope: critical_warning`)
- IN-01: `DEFAULT_CONFIG.dup` / `reset!` shallow-copy nested arrays (`lib/spm_cache/core/config.rb:34,150-152`).
- IN-02: `YAML.safe_load` without `aliases: true` rejects alias-style `spm-cache.yml` files (`lib/spm_cache/core/config.rb:51`).
- IN-03: redundant `"Simulator"` substring check in `destination_arch` (`lib/spm_cache/spm/build.rb:376`).

## Known Bugs

**Unguarded host-graph parse in DiffDetector (WINDOWS #5):** OPEN — decision-fidelity gap vs D-04 "warn + degrade, never hard-fail"
- `DiffDetector#live_packages` does an unguarded `JSON.parse(File.read(resolved))` (`lib/spm_cache/core/diff_detector.rb:146-152`). A truncated or non-object `Package.resolved` raises out of `Installer#detect_diff` (`lib/spm_cache/installer.rb:56-60`) and aborts the whole `use` run *before* the reconciler's tolerant `Core::PackageResolved.pins_or_nil` guard (`lib/spm_cache/installer.rb:177-183`) can warn and degrade — for that one input shape the D-04 guard is unreachable.
- Left open deliberately in Phase 6 (2026-08-27): routing it through the tolerant accessor would flip every `detect` caller to silently-degrade. Recorded as warranting a dedicated follow-up plan.

**Tap formula boot crash under Homebrew Ruby ≥ 3.4:** RESOLVED 2026-08-31
- The formula wrapper exec'd the gem binstub via `env ruby` with isolated `GEM_HOME`/`GEM_PATH`; on Ruby 3.4+ hosts `nkf`/`kconv` (bundled gems since 3.4.0) were invisible, so `CFPropertyList` died at boot with `cannot load such file -- kconv (LoadError)`. Fixed by exec'ing keg-only `ruby@3.3` (`phuongddx/homebrew-spm-cache@5fd0f0d`), macos-15 runner pin reverted (`7028069`), live-proven by run 33350215267. Residual watch item: the underlying `CFPropertyList` → `kconv` requirement is latent in the gem itself — a future RubyGems publication should verify boot under Ruby 3.4 without Homebrew's interpreter pin `[INFERENCE from .planning/phases/11-homebrew-release-automation/deferred-items.md]`.

**Watcher `run_once` vs `run` error asymmetry:** OPEN (documented)
- `run_once` (`lib/spm_cache/core/watcher.rb:41-47`) lets errors propagate — `watch --once` in CI fails on transient errors — while the loop catches `StandardError` and continues (`lib/spm_cache/core/watcher.rb:76-80`).

**Silent watch on a project with no `Package.resolved`:** OPEN (minor)
- `resolve_watched_files` finds nothing on a fresh clone; the loop still starts and prints an empty watch list, never triggering. No user feedback that nothing is watched (`lib/spm_cache/core/watcher.rb`, `spec/watch_spec.rb`).

## Security Considerations

**Shell command injection surface (`lib/spm_cache/core/sh.rb` and callers):** OPEN
- `Sh.run` passes command strings through `Open3` with a shell. Unquoted interpolations that remain: `-framework #{fw_path}` (`lib/spm_cache/spm/xcframework/xcframework.rb:43-44`), `swiftc ... -o #{output_path} #{temp_file.path}` (`lib/spm_cache/spm/xcframework/slice.rb:151`), `args.join(" ")` in the proxy binary runner with embedded single quotes in `--ignore` values (`lib/spm_cache/spm/pkg/proxy_executable.rb:51-53`), and all `Core::Git` subcommands (`lib/spm_cache/core/git.rb:16-34`). Quoted today: `libtool -static -o '#{output_path}' -filelist '#{filelist.path}'` (`lib/spm_cache/spm/build.rb:239`, `lib/spm_cache/spm/build_pipeline.rb:933`).
- Risk: `--ignore`/`--cache-only` values come from user-editable `spm-cache.yml`; a crafted value with shell metacharacters could execute commands. Paths otherwise originate from Xcode metadata / SPM checkouts.
- Fix approach: argument-array `Open3` (no shell) for internal commands; validate/escape interpolated values for `xcodebuild`.

**Cache poisoning / artifact integrity:** OPEN (partially mitigated)
- Mitigated by v0.4.0: a cache hit now requires the provenance sidecar's recorded pin to agree with the lockfile pin, and any sidecar parse anomaly is an unconditional miss (`tools/spm-cache-proxy/Sources/Core/Cache.swift` `hit`); the version-stamp guard forces a regen across spm-cache upgrades (`lib/spm_cache/installer.rb:433-437`).
- Still absent: content-hash (SHA256) verification of cached binaries. `lib/spm_cache/storage/git.rb:24-30` trusts `git fetch` + `checkout FETCH_HEAD`; `lib/spm_cache/storage/s3.rb` syncs arbitrary files from a configured S3 URI; `graph.json` and the proxy generator (`tools/spm-cache-proxy/Sources/Core/Generator/ProxyGenerator.swift`) trust cached on-disk xcframeworks.
- Fix approach: record SHA256 per cached xcframework in the lockfile/provenance sidecar; verify on pull and before proxy generation; signed S3 objects.

**S3 credentials handling:** OPEN
- `--creds=PATH` is stored in `spm-cache.yml` unvalidated (`lib/spm_cache/command/init.rb:24,36,100-101`); the file is read at pull time with no existence/format checks and `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` passed as env vars (`lib/spm_cache/storage/s3.rb`). Fix: validate path and warn on world-readable files.

**GitHub Action init swallows errors:** OPEN — and the Action is a waived broken window
- `spm-cache init $ARGS || true` (`action/action.yml:65`) hides misconfiguration before `spm-cache remote` runs.
- Broken window #2 (2026-08-27, waived NOT closed): the composite action's `gem install spm-cache` step cannot work while the gem is unpublished on RubyGems; the action repo's smoke workflow is blocked until publication. Do not close this window without shipping the gem.

**Security audit posture (v0.4.0):** CLOSED
- Phase 9/10/11 security audits all `status: verified`, `threats_open: 0` (`.planning/phases/09-cache-identity-invalidation/09-SECURITY.md`, `.planning/phases/10-fidelity-regression-coverage/10-SECURITY.md`, `.planning/phases/11-homebrew-release-automation/11-SECURITY.md`). Phase 11's tap automation pivoted from GitHub App token to a write-only deploy key (`TAP_DEPLOY_KEY` sole repo secret, dead `TAP_REPO_TOKEN` deleted) with `gh secret set` masking; `update-tap.yml` gates downloads on `curl -fL` + gzip magic + sha256 before the anchored formula edit.

## Performance Bottlenecks

**Sequential per-target builds (`lib/spm_cache/installer/build.rb:59-62`):** OPEN
- Cache misses build one at a time (`missed.each`), each a full `xcodebuild` (30-120s). Fix: bounded process pool (2-4); DerivedData paths are already per-destination content-hashed.

**Per-target `swift package describe` shell-outs (`lib/spm_cache/spm/build_pipeline.rb:425-428,510-513,628-631`):** OPEN
- `resolve_scheme`, `resolve_module_name`, and `find_private_clang_shims` each construct and fetch a fresh `Desc::Description` (shell-out) for the same package. Fix: parse once per package and pass the description down.

**Watcher polling latency (`lib/spm_cache/core/watcher.rb`):** OPEN (accepted)
- Pure `File.stat` mtime+size polling, 2s default debounce — a deliberate portability choice (Ruby stdlib only, no FSEvents/listen dependency). Sub-second latency would require an opt-in native backend.

**Umbrella regenerate + retry (`lib/spm_cache/installer.rb:368-372`):** OPEN (impact reduced)
- A failed first umbrella resolve triggers a full regenerate + `swift package resolve` cycle (30-60s on large graphs). Practical impact shrank in v0.4.0: PERF-01's shared clone dir cut the reference project's wall-clock 40.6% and disk 34% (`.planning/phases/07-host-faithful-checkout-seeding/07-BENCHMARK.md`). Fix: pre-enrich product metadata before the first resolve.

## Fragile Areas

**Proxy-package swap (`lib/spm_cache/installer.rb:493+`):** OPEN
- Plugin packages must be preserved by URL matching — normalization must be perfect or a plugin is silently dropped (now covered: `spec/installer_integrate_proxy_spec.rb:306-326` pins https/ssh/.git/host-case normalization; plugin-only entries warn loudly instead of vanishing). Excluded/ignored products are matched by product name — an upstream rename changes identity and the exemption fails silently. The `dep_exempted?` check runs before deletion; a missed exemption rewires the dependency onto a proxy that lacks the real source.

**DiffDetector identity heuristics (`lib/spm_cache/core/diff_detector.rb:58-76,238-256`):** OPEN
- `normalize_url` strips `.git` and lowercases host but preserves path case — an upstream case-only rename reads as removed+added (noisy but safe: triggers regen). `identity_key` falls back to `"name:#{name}"`, then `"unknown"` — two unknown packages compare equal and could suppress a real diff.
- The stale-locator fragility itself is fixed (canonical tiers, `lib/spm_cache/core/package_resolved.rb`); the wrong-file class of bug is closed.

**Lockfile `products[]` staleness (`lib/spm_cache/installer.rb:390-437`):** OPEN (partially mitigated)
- `invalidate_stale_products!` now keys on a per-project `spm_cache_version` stamp written by `enrich_lockfile_products`, so any spm-cache upgrade clears stale product metadata. Within a single version, enriched data is still trusted permanently — a corrupted enrichment from a partial `swift package describe` persists until the next version bump.

**DerivedData fallback for umbrella checkouts (`lib/spm_cache/spm/checkout_resolver.rb:49-66`):** OPEN (downgraded)
- Picks the newest `DerivedData/<Project>-*` by explicit `File.mtime` max (glob order is filesystem-dependent — documented). Still a heuristic: newest mtime may not be the project being cached. Reach shrank in v0.4.0: vendored-`.xcodeproj` packages are classified not-graph-pinned and skip host-graph seeding entirely, so nothing claims pinship on that path.

**xcframework creation cleanup (`lib/spm_cache/spm/xcframework/xcframework.rb:27-47`):** OPEN
- Failure cleanup is correct (partial xcframeworks are `rm_rf`'d and the error re-raised). But the pre-build `FileUtils.rm_rf(@output_path)` means a future parallel build of the same target would race on the output path — relevant if the serial build loop is ever parallelized.

## Scaling Limits

**Global flat `~/.spm-cache`:** DEFERRED to v0.5 (locked decision 2026-08-27)
- One shared directory keyed by module name across all projects/versions; provenance sidecars + the version-stamp guard are the v0.4.0 floor. Partitioning by project and content-addressed keys remain the scaling path (`lib/spm_cache/core/config.rb` `CACHE_DIR`, doctor's `cache_dir_health` check at `lib/spm_cache/core/diagnostics.rb:234-247`).

**Serial build throughput:** same as the Performance section — wall-clock scales linearly with cache-miss count; the Phase 7 clone-dir win already removed the redundant per-package clone cost.

## Dependencies at Risk

**RubyGems publication (absent):** OPEN — operator-deferred
- Homebrew is the only working distribution channel. Deferred items 2/3 of the release checklist (`gem signin` → `gem build`/`gem push` → verify install) have no RubyGems credentials on this machine. Blocks: the GitHub Action, its smoke CI, and non-Homebrew users.

**Homebrew Ruby interpreter pin (`ruby@3.3` in the tap formula):** WATCH
- The boot fix pins the tap to keg-only ruby@3.3 (`phuongddx/homebrew-spm-cache@5fd0f0d`). If Homebrew drops ruby@3.3 or the formula drifts, the kconv boot crash returns — verify under Ruby 3.4 before unpinning (see Known Bugs).

**Swift companion binary availability:** LOW
- The gem requires `tools/spm-cache-proxy/.build/release/spm-cache-proxy` (`lib/spm_cache/spm/pkg/proxy_executable.rb:35-37` builds it on demand); doctor's `companion_binary` check (`lib/spm_cache/core/diagnostics.rb:275-287`) surfaces absence. No external dependency risk.

**Upstream gems (`xcodeproj`, `claide`, `CFPropertyList`):** no version-pin concerns detected in the gemspec beyond the homepage fix already recorded in STATE.md.

## Missing Critical Features

**Artifact integrity verification:** no SHA256/checksum of cached xcframeworks anywhere in the read or hit path (see Security Considerations).

**Doctor cannot prove cached binaries are importable:** no check runs a `swiftc -parse` against a cached module; `library_evolution_compatibility` only confirms the flag is honored (`lib/spm_cache/core/diagnostics.rb:251-257`); `remote_backend_connectivity` checks configuration, not reachability (`lib/spm_cache/core/diagnostics.rb:259-273`). A corrupted cache (missing swiftinterface, wrong-arch slice) passes all checks.

**No FSEvents backend:** watcher is polling-only by design; sub-second latency needs an opt-in native mode (`lib/spm_cache/core/watcher.rb`).

## Test Coverage Gaps

Suite status: **441 examples, 0 failures** (2026-08-31, up from 332 pre-v0.4.0; Phases 10-11 added `spec/fidelity_drift_regression_spec.rb`, `spec/fidelity_bucket_partition_spec.rb`, `spec/fidelity_edge_matrix_spec.rb`, `spec/build_pipeline_provenance_spec.rb`, `spec/update_tap_workflow_spec.rb`, `spec/package_resolved_spec.rb`, `spec/lockfile_reconciliation_spec.rb`).

**Storage backends (`lib/spm_cache/storage/git.rb`, `lib/spm_cache/storage/s3.rb`):** OPEN — zero spec files. Argument construction and error paths untested. Priority: Medium.

**Rollback (`lib/spm_cache/installer/rollback.rb`):** OPEN — no spec file; proxy-removal/restore behavior untested. Priority: Medium.

**Full `Installer::Use` end-to-end:** PARTIALLY CLOSED — `spec/installer_integrate_proxy_spec.rb` exercises the pbxproj surgery directly and `spec/installer_use_fast_path_spec.rb` covers the fast path, but no test drives project→lockfile→build→integrate as one sequence with partial-failure cleanup assertions. Priority: High.

**GitHub composite action end-to-end:** OPEN — `spec/action_spec.rb` is structural only; no workflow exercises the action. Blocked by the waived broken window (gem unpublished). Priority: Low.

**Tap automation:** adequately covered — `spec/update_tap_workflow_spec.rb` (350 lines, 20 structural examples) pins REL-04..09, and the push path is live-proven (run 33354678763: real formula edit + commit `ee27cc7` + deploy-key push; v0.4.0 cut run 33377121583 fully green, tap `47a0600`).

---

*Concerns audit: 2026-08-31*
