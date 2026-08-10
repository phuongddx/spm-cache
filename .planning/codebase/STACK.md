---
title: Technology Stack
focus: tech
mapped_date: 2026-08-10
last_mapped_commit: 5687b4641c1d7a36ef4fc99d59fdccf6dc09c5e0
---

# Technology Stack

## Overview

`spm-cache` is a **polyglot CLI tool** that caches Swift Package Manager dependencies as `.xcframework` binaries to accelerate Xcode clean build times. It combines a Ruby gem CLI (the orchestrator/UI) with a Swift executable companion (the proxy-package generator). Distribution: Homebrew tap and RubyGems.

## Languages & Runtimes

- **Ruby (primary CLI)** — `>= 3.0.0` (`spm_cache.gemspec` `spec.required_ruby_version`). ~6,000 LOC in `lib/spm_cache/`.
- **Swift (companion tool)** — Swift 6.0 tools version (`tools/spm-cache-proxy/Package.swift` `// swift-tools-version: 6.0`), targeting macOS 14+. The companion lives in `tools/spm-cache-proxy/`.

## Ruby Dependencies

Runtime (declared in `spm_cache.gemspec`):
- `claide` `~> 1.1` — CLI command tree / argument parsing (`lib/spm_cache/command.rb`)
- `xcodeproj` `>= 1.26.0` — read/edits Xcode `project.pbxproj` (`lib/spm_cache/xcodeproj/`)
- `parallel` `~> 1.23` — parallel builds (`lib/spm_cache/core/parallel.rb`)
- `tty-cursor` `~> 0.7`, `tty-screen` `~> 0.8` — terminal UI
- `CFPropertyList` `~> 3.0` — plist parsing for framework metadata

Development:
- `bundler` `>= 2.0`, `rspec` `~> 3.12`, `rubocop` `~> 1.50`

## Swift Companion Dependencies

Declared in `tools/spm-cache-proxy/Package.swift`:
- `apple/swift-argument-parser` `from: 1.3.0` — CLI subcommands (`GenProxy`, `GenUmbrella`, `Resolve`)
- `onevcat/Rainbow` `from: 4.0.1` — colored terminal output (`tools/spm-cache-proxy/Sources/Core/Log/`)

## Configuration Files

- `spm_cache.gemspec` — gem metadata, file globs, dependency declarations
- `Gemfile` / `Gemfile.lock` — bundler dependency resolution
- `VERSION` — single source of truth for the gem version (read by `lib/spm_cache/version.rb`); currently `0.2.8`
- `Makefile` — `install`, `format` (rubocop --auto-correct), `test` (rspec), `proxy.build` (`swift build -c release`), `proxy.clean`
- `.rubocop` — RuboCop lint/style config
- `.pre-commit-config.yaml` — pre-commit hooks
- `tools/spm-cache-proxy/Package.swift` — SwiftPM manifest for the companion
- `tools/spm-cache-proxy/Package.resolved` — Swift dependency lockfile (gitignored, regenerated on build)
- `CLAUDE.md` — agent guidance (GitHub account must be `phuongddx` for `gh`)

## Build & Dev Tooling

- **Ruby:** `bundle install` (or `make install`), `bundle exec rspec` / `make test`, `bundle exec rubocop` / `make format`
- **Swift companion:** `make proxy.build` (`swift build -c release` in `tools/spm-cache-proxy/`); `make proxy.clean`
- **Versioning:** `VERSION` file; CI bumps are coordinated with Homebrew formula updates

## Packaging & Distribution

- **RubyGems:** published as the `spm-cache` gem; `spec.executables = ["spm-cache"]` (`bin/spm-cache`)
- **Homebrew:** tap `phuongddx/spm-cache/spm-cache` (documented in `README.md`); formula updated automatically by CI
- **CI:** `.github/workflows/update-tap.yml` — on `release: published`, computes the tarball sha256 and updates the external Homebrew tap repo, then commits/pushes the formula
- **Pre-commit:** `.pre-commit-config.yaml`

## Runtime Artefacts (generated, gitignored)

- `spm-cache/` sandbox dir, `spm-cache.lock` (lockfile), `spm-cache.yml` (config) — all in `.gitignore`
- `~/.spm-cache` global cache dir (`lib/spm_cache/core/config.rb` `CACHE_DIR`)
- `tools/spm-cache-proxy/.build/`, `.swiftpm/`, `Package.resolved` — Swift build artefacts (gitignored)
