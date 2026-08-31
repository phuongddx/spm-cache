---
title: Technology Stack
focus: tech
mapped_date: 2026-08-31
last_mapped_commit: fdb3a70abe81852ec9310a3ff410341a4adcfa0c
---

# Technology Stack

**Analysis Date:** 2026-08-31

## Languages

**Primary:**
- Ruby >= 3.1.0 — CLI gem, build pipeline, installer, config, remote storage, all commands (`lib/spm_cache/`)

**Secondary:**
- Swift 6.0 (swift-tools-version: 6.0) — Companion proxy/umbrella generator binary (`tools/spm-cache-proxy/Sources/`)
- JavaScript — `cachemap.js.template` for Xcode build-phase cache visualization (`lib/spm_cache/assets/templates/cachemap.js.template`)

## Runtime

**Environment:**
- Ruby (minimum 3.1.0, tested on 3.1 / 3.2 / 3.3 in CI matrix)
- macOS only (darwin arm64; `Gemfile.lock` platforms: `arm64-darwin-23` + `ruby`)
- Requires Xcode 16+ and Swift 6.0 toolchain for xcframework builds
- Homebrew installs run under keg-only `ruby@3.3` (tap formula wrapper execs it explicitly — the CLI cannot boot under Homebrew Ruby ≥ 3.4, where `nkf`/`kconv` left the default-gem set; fixed tap-side at `phuongddx/homebrew-spm-cache@5fd0f0d`)

**Package Manager:**
- Bundler 4.0.13
- Lockfile: `Gemfile.lock` (present, SHA256 checksums)
- Swift Package Manager — for `tools/spm-cache-proxy/` (separate `Package.swift`, resolved pins in `tools/spm-cache-proxy/Package.resolved` v3: swift-argument-parser 1.8.2, Rainbow 4.2.1)

## Frameworks

**Core:**
- claide 1.1.0 — CLI command dispatch (argument parsing, subcommand routing). Base class `SPMCache::Command` in `lib/spm_cache/command/base.rb`
- xcodeproj 1.28.1 — Xcode project file manipulation (.pbxproj editing, target/group management). Used via `lib/spm_cache/xcodeproj/`

**Testing:**
- RSpec 3.13.2 — Ruby test framework (`spec/`, 441 examples after the v0.4.0 fidelity regression specs)
- Swift Testing (stdlib) — Proxy tool tests (`tools/spm-cache-proxy/Tests/spm-cache-proxyTests/`: `ProxyGeneratorTests.swift`, `UmbrellaGeneratorTests.swift`, plus v0.4.0 additions `LockfileTests.swift`, `CacheTests.swift`)

**Build/Dev:**
- parallel 1.28.0 — Parallel xcframework building for multiple SDKs
- tty-cursor 0.7.1 / tty-screen 0.8.2 — Terminal cursor and screen-size detection for spinner/progress UI
- CFPropertyList 3.0.8 — Apple plist parsing (`.pbxproj` is XML plist)
- rubocop 1.88.2 — Linting and auto-formatting (dev dependency; **no `.rubocop.yml` in the repo** — rubocop runs on defaults via `make format` and pre-commit)

**Swift Proxy Tool Dependencies:**
- swift-argument-parser >= 1.3.0 (locked 1.8.2) — CLI argument parsing for the Swift binary
- Rainbow >= 4.0.1 (locked 4.2.1) — Terminal color output for the Swift binary

## Key Dependencies

**Critical:**
- `claide` ~> 1.1 — Every command inherits from `SPMCache::Command < CLAide::Command`. Without it, no CLI works.
- `xcodeproj` >= 1.26.0 — All `.xcodeproj` manipulation (dependency swapping, build configuration injection, target creation) depends on this.
- `CFPropertyList` ~> 3.0 — Required by `xcodeproj` for plist serialization. Under Ruby 3.4 it transitively needs `nkf`/`kconv`, which is why the tap formula pins keg-only `ruby@3.3`.
- `parallel` ~> 1.23 — Powers multi-SDK parallel builds in `lib/spm_cache/core/parallel.rb`.

**Infrastructure:**
- `tty-cursor` ~> 0.7 — Terminal cursor control (spinner animation) in `lib/spm_cache/live_log.rb`
- `tty-screen` ~> 0.8 — Terminal width detection for status output

## Configuration

**Environment:**
- CLI config file: `spm-cache.yml` per-project (YAML). Schema defined in `lib/spm_cache/core/config.rb` (`DEFAULT_CONFIG`: `ignore`, `cache_only`, `ignore_local`, `ignore_build_errors`, `keep_pkgs_in_project`, `default_sdk` = `iphonesimulator`).
- Global cache directory: `~/.spm-cache/` (hardcoded in `lib/spm_cache/core/config.rb` as `CACHE_DIR`); per-config subdirectories via `Config#cache_dir(config)`. Entries are `<name>.xcframework` bundles plus `<name>.xcframework.provenance.json` and optional `<name>.xcframework.shims.json` sidecars.
- Project-local sandbox: `<project>/spm-cache/` (hardcoded as `SANDBOX_DIR`). Subdirectories: `packages/proxy/`, `packages/umbrella/`, `packages/clones/` (new — shared SPM checkout clones, `Config#clones_dir`), `metadata/`, `xcconfigs/`, `local-packages/`.
- Cross-run build lock: `<project>/.spm-cache-build.lock` (`Config#build_lock_path`) — deliberately OUTSIDE the sandbox so `recreate_dirs` can never delete the path a live flock holds.
- Lockfile: `spm-cache.lock` per-project (YAML). Reconciled from the host SPM graph on every non-fast-path run; carries a per-project `spm_cache_version` stamp (`lib/spm_cache/installer.rb`) — a missing or other-version stamp is treated as stale.
- No `.env` file required; remote backend credentials passed via `--creds` flag (JSON file path) or shell env vars set by GitHub Action.

**Build:**
- `Makefile` — Five targets: `install`, `format`, `test`, `proxy.build`, `proxy.clean`
- `spm_cache.gemspec` — Ruby gem packaging. Files: `{lib,bin,assets,tools}/**/*`, `Gemfile`, `LICENSE.txt`, `README.md`, `VERSION`, `Makefile`, `*.gemspec`. Homepage is the real repo URL `https://github.com/phuongddx/spm-cache` (placeholder fixed in `cf384d6`).
- `tools/spm-cache-proxy/Package.swift` — Swift Package Manager manifest for companion binary (swift-tools 6.0, macOS 14+, unchanged since v0.3.0)
- `.pre-commit-config.yaml` — Pre-commit hook running rubocop `v1.50.0` with `--auto-correct`
- `VERSION` — Single-line `0.4.0`, read at gem load via `lib/spm_cache/version.rb`. The Swift proxy carries a matching `static let proxyVersion = "0.4.0"` in `tools/spm-cache-proxy/Sources/CLI.swift` — the two MUST be bumped in lockstep (spec-enforced; the lockstep spec caught the initial v0.4.0 miss).

## Platform Requirements

**Development:**
- macOS 14+ (Sonoma) for Swift proxy tool (`.macOS(.v14)` in `tools/spm-cache-proxy/Package.swift`)
- Xcode 16+ with Swift 6.0 toolchain
- Ruby >= 3.1.0 with Bundler
- `aws` CLI (optional, for S3 remote backend)

**Production (end-user):**
- macOS with Xcode 16+
- Install via Homebrew tap `phuongddx/spm-cache/spm-cache` (the ONLY distribution channel — v0.4.0 live; formula depends on keg-only `ruby@3.3` so it boots on Homebrew Ruby 3.4 images). The gem is NOT on RubyGems (publish deferred by user decision).
- Git (for git remote backend)
- AWS CLI (for S3 remote backend)

---

*Stack analysis: 2026-08-31*
<!-- refreshed: 2026-08-31 -->
