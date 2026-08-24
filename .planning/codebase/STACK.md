---
title: Technology Stack
focus: tech
mapped_date: 2026-08-23
last_mapped_commit: f55b9b9a7dc73104b490ed76ec38549b242af03e
---

# Technology Stack

**Analysis Date:** 2026-08-23

## Languages

**Primary:**
- Ruby >= 3.1.0 — CLI gem, build pipeline, installer, config, remote storage, all commands (`lib/spm_cache/`)

**Secondary:**
- Swift 6.0 (swift-tools-version: 6.0) — Companion proxy/umbrella generator binary (`tools/spm-cache-proxy/Sources/`)
- JavaScript — `cachemap.js.template` for Xcode build-phase cache visualization (`lib/spm_cache/assets/templates/cachemap.js.template`)

## Runtime

**Environment:**
- Ruby (minimum 3.1.0, tested on 3.1 / 3.2 / 3.3)
- macOS only (darwin arm64, platform `arm64-darwin-23` in lockfile)
- Requires Xcode 16+ and Swift 6.0 toolchain for xcframework builds

**Package Manager:**
- Bundler 4.0.13
- Lockfile: `Gemfile.lock` (present, SHA256 checksums)
- Swift Package Manager — for `tools/spm-cache-proxy/` (separate `Package.swift`)

## Frameworks

**Core:**
- claide 1.1.0 — CLI command dispatch (argument parsing, subcommand routing). Base class `SPMCache::Command` in `lib/spm_cache/command/base.rb`
- xcodeproj 1.28.1 — Xcode project file manipulation (.pbxprog editing, target/group management). Used via `lib/spm_cache/xcodeproj/`

**Testing:**
- RSpec 3.13.2 — Ruby test framework (`spec/`)
- Swift Testing (stdlib) — Proxy tool tests (`tools/spm-cache-proxy/Tests/`)

**Build/Dev:**
- parallel 1.28.0 — Parallel xcframework building for multiple SDKs
- tty-cursor 0.7.1 / tty-screen 0.8.2 — Terminal cursor and screen-size detection for spinner/progress UI
- CFPropertyList 3.0.8 — Apple plist parsing (`.pbxproj` is XML plist)
- rubocop 1.88.2 — Linting and auto-formatting (dev dependency)

**Swift Proxy Tool Dependencies:**
- swift-argument-parser >= 1.3.0 — CLI argument parsing for the Swift binary
- Rainbow >= 4.0.1 — Terminal color output for the Swift binary

## Key Dependencies

**Critical:**
- `claide` ~> 1.1 — Every command inherits from `SPMCache::Command < CLAide::Command`. Without it, no CLI works.
- `xcodeproj` >= 1.26.0 — All `.xcodeproj` manipulation (dependency swapping, build configuration injection, target creation) depends on this.
- `CFPropertyList` ~> 3.0 — Required by `xcodeproj` for plist serialization.
- `parallel` ~> 1.23 — Powers multi-SDK parallel builds in `lib/spm_cache/core/parallel.rb`.

**Infrastructure:**
- `tty-cursor` ~> 0.7 — Terminal cursor control (spinner animation) in `lib/spm_cache/live_log.rb`
- `tty-screen` ~> 0.8 — Terminal width detection for status output

## Configuration

**Environment:**
- CLI config file: `spm-cache.yml` per-project (YAML). Schema defined in `lib/spm_cache/core/config.rb` (`DEFAULT_CONFIG` hash).
- Global cache directory: `~/.spm-cache/` (hardcoded in `lib/spm_cache/core/config.rb` as `CACHE_DIR`)
- Project-local sandbox: `<project>/spm-cache/` (hardcoded as `SANDBOX_DIR`)
- Lockfile: `spm-cache.lock` per-project (YAML, enriched Package.resolved metadata)
- No `.env` file required; remote backend credentials passed via `--creds` flag (JSON file path) or shell env vars set by GitHub Action.

**Build:**
- `Makefile` — Four targets: `install`, `format`, `test`, `proxy.build`, `proxy.clean`
- `spm_cache.gemspec` — Ruby gem packaging. Files: `{lib,bin,assets,tools}/**/*`, `Gemfile`, `LICENSE.txt`, `README.md`, `VERSION`, `Makefile`, `*.gemspec`
- `tools/spm-cache-proxy/Package.swift` — Swift Package Manager manifest for companion binary
- `.pre-commit-config.yaml` — Pre-commit hook running `rubocop --auto-correct`
- VERSION — Single-line `0.3.0` read at gem load via `lib/spm_cache/version.rb`

## Platform Requirements

**Development:**
- macOS 14+ (Sonoma) for Swift proxy tool (`.macOS(.v14)` in `Package.swift`)
- Xcode 16+ with Swift 6.0 toolchain
- Ruby >= 3.1.0 with Bundler
- `aws` CLI (optional, for S3 remote backend)

**Production (end-user):**
- macOS with Xcode 16+
- Ruby >= 3.1.0 (or use the GitHub Action which installs via `gem install`)
- Git (for git remote backend)
- AWS CLI (for S3 remote backend)

---

*Stack analysis: 2026-08-23*
<!-- refreshed: 2026-08-23 -->
