# Project Overview & PDR

> **Project:** spm-cache
> **Version:** 0.1.2
> **Status:** Release-Ready (v0.1.0 shipped)
> **License:** MIT

## Problem Statement

iOS projects using Swift Package Manager (SPM) dependencies suffer from long clean build times because Xcode recompiles all Swift package sources from scratch on every clean build. Existing cache tools (CocoaPods-Binary-Cache, Rugby, XCRemoteCache) either lack SPM support or require invasive project changes.

## Solution

`spm-cache` prebuilds SPM dependencies into `.xcframework` binaries and swaps them at the SPM manifest level using a **proxy package architecture**. This approach is non-invasive: the original `Package.swift` declarations remain untouched, and a generated proxy package intercepts dependency resolution to serve cached binaries when available, falling back to source compilation on cache miss.

## Goals

- Reduce Xcode clean build times by eliminating recompilation of stable SPM dependencies
- Provide seamless cache integration with automatic fallback to source on miss
- Support Swift macros, resource bundles, and per-configuration (Debug/Release) caching
- Enable team-wide cache sharing via Git or S3 remote backends
- Maintain a clean, reversible integration (rollback restores original project state)

## Non-Goals

- CocoaPods support (out of scope)
- Swift plugins (out of scope for v0.1.0)
- Caching of the main app target (only SPM dependencies are cached)

## Target Users

- iOS/macOS development teams using SPM for dependency management
- CI pipelines seeking to reduce build times
- Individual developers who want faster incremental builds after `clean`

## Key Metrics

| Metric | Target | Achieved |
|--------|--------|----------|
| Clean build time reduction | >70% for dependency-heavy projects | **51%** (8 deps, 4 cached) |
| Cache hit ratio (warm cache) | >90% | 50% (4/8 cached, rest source fallback) |
| Integration time (`spm-cache use`) | <10 seconds for typical projects | <5s (proxy generation) |
| Rollback time | <5 seconds | <2s |
| Multi-slice support | simulator + device | ✅ `--sdk=all` |

## Product Requirements

### P1 - Core Caching

- **REQ-001:** `spm-cache use` integrates proxy package into Xcode project and replaces source deps with cached binaries
- **REQ-002:** `spm-cache build [TARGETS]` builds specified targets into `.xcframework` files in local cache
- **REQ-003:** Cache miss automatically falls back to source compilation (no build failure)
- **REQ-004:** `spm-cache rollback` restores original project state (removes sandbox, proxy references)
- **REQ-005:** Per-configuration caching (Debug and Release caches are separate)
- **REQ-005b:** Multi-slice xcframeworks (`--sdk=all` builds both simulator + device)

### P2 - Advanced Support

- **REQ-006:** Swift macro targets are built and cached as `.macro` binaries
- **REQ-007:** Resource bundles are properly handled (`Bundle.module` accessor works in cached frameworks)
- **REQ-008:** Library evolution flags (`-enable-library-evolution -emit-module-interface -no-verify-emitted-module-interface`) are applied for binary compatibility
- **REQ-009:** xcframework checksums are computed for cache validation

### P3 - Remote Cache

- **REQ-010:** `spm-cache remote pull` syncs cache from Git or S3
- **REQ-011:** `spm-cache remote push` pushes local cache to Git or S3
- **REQ-012:** Remote config is per-configuration (debug/release can use different backends)

### P4 - Developer Experience

- **REQ-013:** `spm-cache off [TARGETS]` forces source mode for specific targets
- **REQ-014:** `spm-cache cache list` lists cached packages
- **REQ-015:** `spm-cache cache clean [--all]` cleans cache
- **REQ-016:** Interactive cachemap visualization (HTML dependency graph)

## Success Criteria

- Running `spm-cache` in a project with 10+ SPM dependencies reduces clean build time by >70%
- Cache hit produces a working binary framework that links correctly
- Rollback fully restores the original Xcode project state
- Remote cache sync works with both Git and S3 backends

## v0.1.0 Delivered Features

Beyond core caching, v0.1.0 includes:

- **RSpec Test Suite** — 4 test files, 19 examples covering Core utilities, Config singleton, Lockfile parsing, and Buildable naming
- **GitHub Actions CI** — Automated release workflow (update-tap.yml) that publishes to Homebrew tap on release
- **Homebrew Distribution** — Distributed via external tap `phuongddx/spm-cache` (recommended install method)
- **Agent Skills** — Two Claude/agent skills for end-users:
  - `skills/spm-cache` — guided workflows, CLI reference, remote cache setup, CI/CD patterns, troubleshooting
  - `skills/spm-cache-issue` — automated GitHub issue filing with diagnostics collection

## Constraints

- Command name: `spm-cache` (gem name: `spm-cache`)
- Ruby module namespace: `SPMCache`
- Config file: `spm-cache.yml` (YAML)
- Lockfile: `spm-cache.lock` (JSON)
- Local cache: `~/.spm-cache/{debug,release}/`
- Sandbox dir: `spm-cache/` (in project root)
- Ruby >= 3.0.0, Swift 6.0+ (for proxy tool)
- macOS only (relies on Xcode toolchain)
