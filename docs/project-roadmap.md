# Project Roadmap

> **Project:** spm-cache
> **Last Updated:** 2026-07-18 (rev 7)

## Current Status

**v0.2.0** — Field-bugfix release. A 59-package real-project field run surfaced three blocking bugs, all now fixed:
- ✅ Proxy identity collision (dup GUIDs / cyclic dependency on any cache-miss package) — wrapper folders renamed `<slug>_proxy`
- ✅ Wrong product names (53/59 packages) — `spm-cache.lock` now carries real `products: [{name, type, targets}]` from `swift package describe`, consumed everywhere instead of falling back to lockfile identity
- ✅ Plugin-only packages breaking whole-graph resolution (e.g. SwiftGenPlugin) — skipped by both generators, original Xcode reference preserved

See `docs/system-architecture.md` for the corrected pipeline order and schema. Existing `~/.spm-cache` binaries are unreachable after this upgrade (module names changed from identity to real product names) — expect a one-time full rebuild; `spm-cache build <target>` now takes real product names, with the old package identity kept working as an alias.

**v0.2.1** — Umbrella-layer transitive-only skip. `UmbrellaGenerator` now skips packages proven to be transitive-only (products never appear in any target's directly-linked dependencies, tracked via `refresh_consumed_dependencies` + `lockfile.dependencies`), preventing version conflicts on dual-pinned dependencies (e.g., realm-core/realm-swift at conflicting versions). Added binary-target product-metadata fallback (regex-parses `Package.swift` when `swift package describe` returns no products). See `docs/system-architecture.md` for pipeline updates.

**v0.2.2** — Real proxy graph transitive-only skip. Extends the v0.2.1 umbrella fix to `ProxyGenerator` (the actual root proxy wired into Xcode), preventing the same version conflict from re-appearing one layer deeper in the real project's package graph. Both UmbrellaGenerator and ProxyGenerator now use the shared `PackageRef.isTransitiveOnly(consumedProducts:)` helper. Verified on a real 59-package field project: root proxy now resolves cleanly without version conflicts.

**v0.2.3** — Fixed fabricated products from binary-target-only packages. Field bug (70-package real project, `eh_xcframework`): when `swift package describe` fails outright for a package (e.g. a local-path `.binaryTarget` whose artifact isn't present in the checkout copy), the text-scraping fallback in `products_from_manifest_fallback` used to scan both `.library(name:)` *and* `.binaryTarget(name:)` declarations as if both declared products — fabricating a nonexistent product (`abcd`, an internal binaryTarget dependency of the package's real single product `eHealth`) that broke `swift package resolve`/`xcodebuild` project-wide with `product 'abcd' ... not found`. Fixed: only `.library(name:)` counts as a product now (a `.binaryTarget` is a target, never a product on its own). Also improved the same fallback to capture each library's actual `targets:` array instead of assuming it always equals `[name]`.

**v0.2.4** — Fixed `.swiftmodule` bundle directory misclassification. Field bug (real downstream `eh_xcframework` project): `Buildable#create_framework`'s `find_file` glob could match a directory-shaped `.swiftmodule` bundle (Xcode's multi-arch/library-evolution output form) instead of the expected flat file. `FileUtils.cp` crashed with `Errno::EISDIR` trying to copy it. Fixed by extracting `copy_module_artifact` helper that uses `FileUtils.cp_r` for directories, `FileUtils.cp` for flat files, merging correctly with any existing `sm_dir` created by the `swiftinterface` handling.

**v0.1.0** — Core implementation complete. All 8 phases from the original plan are implemented:

- ✅ Gem scaffold + CLAide CLI framework
- ✅ Core utilities (Config, Lockfile, Sh, Git, Log, syntax mixins)
- ✅ SPM build pipeline (xcodebuild → libtool → xcodebuild -create-xcframework)
- ✅ **Multi-slice xcframework support** (simulator + device via `--sdk=all`)
- ✅ Swift proxy tool (gen-umbrella, gen-proxy, resolve)
- ✅ Installer pipeline (use, build, rollback)
- ✅ Storage backends (Git, S3)
- ✅ Xcodeproj extensions for proxy integration
- ✅ Cachemap visualization
- ✅ **End-to-end verified on ios-stress-app** (8 SPM deps, 2.06x speedup, both sim + device builds)

## v0.1.x — Stabilization

**v0.1.1 / v0.1.2 Patch Fixes:**
- [x] Fixed: `spm-cache.yml` config (ignore_build_errors, default_sdk, ignore) now loads during build/use (was silently ignored)
- [x] Fixed: revision-only Package.resolved pins now resolve correctly (previously always fell back to a bogus version)
- [x] Fixed: umbrella resolve falls back to Xcode DerivedData checkouts instead of skipping every target
- [x] Fixed: Xcode scheme resolved from `swift package describe` product metadata instead of raw package identity (fixes builds using the wrong scheme)

**Ongoing Stabilization:**
- [x] Add RSpec test suite for Ruby gem (grown to 100+ examples across Core, Config, Lockfile, Buildable, checkout/enrichment sequencing, proxy-Xcode integration, and the combined field-regression fixture)
- [x] Add Swift tests for proxy tool (`swift test` — `PackageRef.versionRequirement`; product-metadata/plugin behavior covered by Ruby-side fixture specs against the real binary)
- [ ] End-to-end integration tests with real SPM projects
- [ ] Error handling hardening (edge cases in framework slice creation)
- [ ] Resource bundle accessor compilation fix (swiftc fallback)
- [ ] `Resolver` implementation (currently a stub in Swift tool)
- [x] CI pipeline (GitHub Actions: update-tap.yml on release published)
- [x] Homebrew distribution via external tap (`phuongddx/spm-cache`)
- [x] Agent skills for guided usage + issue filing (`skills/spm-cache`, `skills/spm-cache-issue`)

## v0.3.0 — Polish & DX

- [ ] Progress indicators during long builds (tty-spinner)
- [ ] Verbose/quiet log levels
- [ ] `spm-cache doctor` command (diagnose environment, toolchain)
- [ ] `spm-cache cachemap --open` (open visualization in browser)
- [ ] Checksum validation on cache load
- [ ] Incremental cache updates (only build changed dependencies)
- [ ] Pre-built binary distribution of Swift proxy tool (GitHub Releases)
- [ ] GC for cache binaries orphaned by the v0.2.0 module-name rekeying

## v0.4.0 — Additional Platforms

- [ ] macOS catalyst support
- [ ] visionOS support
- [x] ~~Device + simulator slice merging~~ (done in v0.1.0)
- [x] ~~Multiple SDK targets in single build command~~ (done: `--sdk=all`)
- [ ] Conditional compilation handling in umbrella package

## v0.5.0 — Team Features

- [ ] Cache manifest with content-addressed storage (SHA-based)
- [ ] Distributed cache with automatic deduplication
- [ ] `spm-cache remote sync` (bidirectional sync)
- [ ] Cache statistics and reporting
- [ ] Slack/CI notifications for cache misses
- [ ] Cache warming in CI (pre-build on dependency change)

## v0.6.0 — Advanced

- [ ] Binary caching for local packages
- [x] ~~Swift plugins support~~ (done in v0.2.0: plugin-only packages skipped + original reference preserved; local plugin-only packages remain out of scope)
- [ ] Custom build scripts per target
- [ ] Cache eviction policies (LRU, size-based)
- [ ] `spm-cache analyze` (build time analysis + recommendations)
- [ ] Integration with Xcode Cloud

## Backlog (Unscheduled)

- [ ] CocoaPods interop (cache pods as xcframeworks)
- [ ] Linux/Windows support (if Swift toolchain allows)
- [ ] GUI app for cache management
- [ ] VS Code extension
- [ ] Bazel build integration

## Release Process

1. Update `VERSION` file
2. Update `docs/project-overview-pdr.md` status
3. Tag release: `git tag v{version}`
4. Build gem: `gem build spm_cache.gemspec`
5. Publish: `gem push spm-cache-{version}.gem`
6. Build Swift proxy release binary (if updated)
7. Create GitHub Release with changelog
