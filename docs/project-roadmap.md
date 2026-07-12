# Project Roadmap

> **Project:** spm-cache
> **Last Updated:** 2026-07-12 (rev 3)

## Current Status

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

- [ ] Add RSpec test suite for Ruby gem
- [ ] Add Swift tests for proxy tool
- [ ] End-to-end integration tests with real SPM projects
- [ ] Error handling hardening (edge cases in framework slice creation)
- [ ] Resource bundle accessor compilation fix (swiftc fallback)
- [ ] `Resolver` implementation (currently a stub in Swift tool)
- [ ] CI pipeline (GitHub Actions: test + lint on push)

## v0.2.0 — Polish & DX

- [ ] Progress indicators during long builds (tty-spinner)
- [ ] Verbose/quiet log levels
- [ ] `spm-cache doctor` command (diagnose environment, toolchain)
- [ ] `spm-cache cachemap --open` (open visualization in browser)
- [ ] Checksum validation on cache load
- [ ] Incremental cache updates (only build changed dependencies)
- [ ] Pre-built binary distribution of Swift proxy tool (GitHub Releases)

## v0.3.0 — Additional Platforms

- [ ] macOS catalyst support
- [ ] visionOS support
- [x] ~~Device + simulator slice merging~~ (done in v0.1.0)
- [x] ~~Multiple SDK targets in single build command~~ (done: `--sdk=all`)
- [ ] Conditional compilation handling in umbrella package

## v0.4.0 — Team Features

- [ ] Cache manifest with content-addressed storage (SHA-based)
- [ ] Distributed cache with automatic deduplication
- [ ] `spm-cache remote sync` (bidirectional sync)
- [ ] Cache statistics and reporting
- [ ] Slack/CI notifications for cache misses
- [ ] Cache warming in CI (pre-build on dependency change)

## v0.5.0 — Advanced

- [ ] Swift plugins support
- [ ] Binary caching for local packages
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
