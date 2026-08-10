---
title: External Integrations
focus: tech
mapped_date: 2026-08-10
last_mapped_commit: 5687b4641c1d7a36ef4fc99d59fdccf6dc09c5e0
---

# External Integrations

`spm-cache` is a build-time tool that orchestrates several external systems. It does **not** ship its own server or database; integration is via shell-out to developer toolchains, git, cloud storage, and the `xcodeproj` Ruby library.

## Swift / Xcode Toolchain (shell-out)

All external command execution is centralized in `lib/spm_cache/core/sh.rb` (`Core::Sh.run` → `Open3.popen3` / `Open3.capture3`). It shells out to:
- `swift package` / `swift build` / `swiftc` — SPM resolution and source compilation (`lib/spm_cache/spm/build.rb`, `lib/spm_cache/swift/swiftc.rb`)
- `xcodebuild` — builds `.xcframework` slices per destination; the build pipeline runs this per SDK/arch (`lib/spm_cache/spm/build_pipeline.rb`)
- `xcrun` / SDK resolution (`lib/spm_cache/swift/sdk.rb`)

`Core::Sh.run` raises `Core::GeneralError` on non-zero exit, including the tail of stdout+stderr (`failure_detail`, last 60 lines) since tools like `xcodebuild` report real errors to stdout.

## Xcode Project Manipulation

- `xcodeproj` gem (>= 1.26) — reads and edits `project.pbxproj` directly
- Extension layer in `lib/spm_cache/xcodeproj/` (`project.rb`, `pkg.rb`, `pkg_product_dependency.rb`, `target.rb`, `group.rb`, `build_configuration.rb`) augments Xcodeproj objects to integrate/remove the proxy package and rewire `XCSwiftPackageProductDependency` refs

## SPM Package Resolution & Metadata

- Parses `Package.resolved` and `project.pbxproj` SPM references into `Core::Lockfile` (`lib/spm_cache/core/lockfile.rb`)
- `lib/spm_cache/spm/desc/` — parses `swift package describe --type json` output into `Desc::Target`, `Desc::Product`, `Desc::Dep` models
- `lib/spm_cache/spm/checkout_resolver.rb` — resolves package checkout directories
- `lib/spm_cache/core/diff_detector.rb` — compares lockfile snapshot vs live project SPM graph to detect added/removed/updated packages

## Swift Companion Tool (process boundary)

Ruby invokes the prebuilt Swift binary `tools/spm-cache-proxy/.build/release/spm-cache-proxy` via `Core::Sh`:
- `gen-proxy` — generates the proxy `Package.swift` (`tools/spm-cache-proxy/Sources/CLI/GenProxy.swift`)
- `gen-umbrella` — generates umbrella modules (`Sources/CLI/GenUmbrella.swift`)
- `resolve` — SPM resolution helper (`Sources/CLI/Resolve.swift`)

This is the Ruby→Swift boundary; passing a stale or unbuilt binary degrades gracefully (regression specs skip if the binary is absent).

## Remote Cache Backends

Pluggable storage in `lib/spm_cache/storage/`, both subclass `Storage::Base` (`lib/spm_cache/storage/base.rb`):
- **Git** (`lib/spm_cache/storage/git.rb`) — `GitStorage` clones/fetches/pushes the cache to a git remote branch via `Core::Git` (`lib/spm_cache/core/git.rb`); uses shallow fetches (`--depth 1`) and force-clean
- **S3** (`lib/spm_cache/storage/s3.rb`) — `S3Storage` runs `aws s3 sync` (requires local `awscli`); AWS credentials are read from a JSON file pointed to by `--creds` and injected as env vars (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`) — never written to disk or logs

Commands `spm-cache remote push` / `remote pull` (`lib/spm_cache/command/remote/`) drive these.

## Terminal UI

- `tty-cursor` + `tty-screen` — progress/section rendering (`lib/spm_cache/core/ui.rb` via `Core::UI.info` / `section`)
- `lib/spm_cache/core/live_log.rb` — streams subprocess stdout/stderr line-by-line to the terminal during builds
- `Core::Log` (`lib/spm_cache/core/log.rb`) — structured logging to optional log dir

## CI / Release Publishing

- `.github/workflows/update-tap.yml` — GitHub Actions; on release publish updates the Homebrew tap
- GitHub CLI (`gh`) — release/PR operations; `CLAUDE.md` notes the active account must be switched to `phuongddx` first (`gh auth switch --user phuongddx`)

## Property-List & Metadata Parsing

- `CFPropertyList` (~> 3.0) — reads `.plist` files inside `.xcframework` slices and built products (`lib/spm_cache/spm/xcframework/metadata.rb`, `slice.rb`)
- `lib/spm_cache/core/syntax/plist.rb` — plist serialization mixin
