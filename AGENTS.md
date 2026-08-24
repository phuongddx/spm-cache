<!-- GSD:project-start source:PROJECT.md -->

## Project

**spm-cache**

`spm-cache` is a macOS CLI tool that caches Swift Package Manager dependencies as `.xcframework` binaries and swaps them transparently at the SPM manifest level using a proxy-package architecture. It reads the Xcode project directly, auto-detects SPM graph changes, and falls back to source compilation on cache miss — no separate manifest, no manual drag-drop. It ships as a Ruby gem with a Swift companion binary, distributed via Homebrew and RubyGems, for iOS/macOS development teams, CI pipelines, and individual developers who want faster clean builds.

**Core Value:** Reduce Xcode clean build times by serving prebuilt SPM dependency binaries transparently, with automatic fallback to source compilation on cache miss — so a cache hit never breaks a build.

### Constraints

- **Tech stack**: Ruby gem (>= 3.0) + Swift 6.0 companion tool; macOS-only (Xcode toolchain) — `core/sh.rb` shells out to swift/xcodebuild
- **Distribution**: Homebrew tap (`phuongddx/spm-cache`) + RubyGems; GitHub account `phuongddx` for releases
- **Architecture**: proxy-package swap at the SPM manifest level; lockfile (`spm-cache.lock`) + config (`spm-cache.yml`) as the state surface
- **Compatibility**: no new runtime gem dependencies without justification (watch uses stdlib mtime polling to avoid `listen`)
- **GitHub Action**: must live in a separate repo per `uses:` resolution rules

<!-- GSD:project-end -->

<!-- GSD:stack-start source:codebase/STACK.md -->

## Technology Stack

## Overview

## Languages & Runtimes

- **Ruby (primary CLI)** — `>= 3.0.0` (`spm_cache.gemspec` `spec.required_ruby_version`). ~6,000 LOC in `lib/spm_cache/`.
- **Swift (companion tool)** — Swift 6.0 tools version (`tools/spm-cache-proxy/Package.swift` `// swift-tools-version: 6.0`), targeting macOS 14+. The companion lives in `tools/spm-cache-proxy/`.

## Ruby Dependencies

- `claide` `~> 1.1` — CLI command tree / argument parsing (`lib/spm_cache/command.rb`)
- `xcodeproj` `>= 1.26.0` — read/edits Xcode `project.pbxproj` (`lib/spm_cache/xcodeproj/`)
- `parallel` `~> 1.23` — parallel builds (`lib/spm_cache/core/parallel.rb`)
- `tty-cursor` `~> 0.7`, `tty-screen` `~> 0.8` — terminal UI
- `CFPropertyList` `~> 3.0` — plist parsing for framework metadata
- `bundler` `>= 2.0`, `rspec` `~> 3.12`, `rubocop` `~> 1.50`

## Swift Companion Dependencies

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

<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->

## Conventions

## Ruby Style

- **`# frozen_string_literal: true`** at the top of every `.rb` file (verified across `lib/`).
- **Enforced by RuboCop** (`~> 1.50`); `make format` runs `bundle exec rubocop --auto-correct`. Config in `.rubocop`.
- **Module structure:** top-level `SPMCache`, nested by concern — `Core`, `SPM`, `Installer`, `Storage`, `Command`, `Swift`, `Utils`, `XcodeprojExt`.
- **Naming:** `CamelCase` classes/modules, `snake_case` methods/vars, `SCREAMING_SNAKE` constants.
- **Loading:** `lib/spm_cache/main.rb` `Main.load_all` recursively `require`s all `.rb` under `lib/spm_cache/` sorted for deterministic order. Module roots declare `autoload`.

## CLaide Command Pattern

- Root command `SPMCache::Command < CLAide::Command` (`lib/spm_cache/command.rb`); `self.abstract_command = true`, `self.command = "spm-cache"`, `default_subcommand = "use"`.
- Global options declared via `self.options`: `--sdk`, `--config`, `--log-dir`, `--no-merge-slices`, `--no-library-evolution`.
- Each subcommand class parses argv in `initialize(argv)` (`argv.option`, `argv.flag?`) and implements `run`.
- `Command::Options` / `BaseOptions` (`lib/spm_cache/command/base.rb`) hold defaults (`SDK="iphonesimulator"`, `CONFIG="debug"`, `MERGE_SLICES=true`, `LIBRARY_EVOLUTION=true`).

## Error Handling

- Custom error hierarchy in `lib/spm_cache/core/error.rb`: `Core::BaseError < StandardError`, `Core::GeneralError` (carries `exit_status`, default 1).
- Expected failures raise `Core::GeneralError.new(msg)`; `Installer` sections wrap in `Core::UI.section`.

## Shell-Out Convention

- **Always via `Core::Sh.run` / `capture_output` / `run!`** (`lib/spm_cache/core/sh.rb`) — `Open3.popen3` (live log) or `Open3.capture3`. Never backticks or `system()`.
- On non-zero exit, raises `GeneralError` with `failure_detail` (tail 60 lines of stdout+stderr, since `xcodebuild` reports to stdout).
- `Core::Git` (`lib/spm_cache/core/git.rb`) wraps git commands over the same helper.

## Logging & UI

- `Core::Log` (`lib/spm_cache/core/log.rb`) — structured logging to optional log dir.
- `Core::UI` — `info`, `section` (block-wrapped), warnings; backed by `tty-cursor`/`tty-screen`.
- `Core::LiveLog` (`lib/spm_cache/core/live_log.rb`) — streams subprocess output live during builds.

## Mixins & Refinements (no monkey-patching)

- Behavior via `include` (`Log`, `BaseOptions`, `Syntax::JSONRepresentable`, `Syntax::YAMLRepresentable`).
- Core extensions via `refine` (`HashExt`, `ParallelExt`, `SystemExt`) — avoids global monkey-patches. E.g. `ParallelExt` (`lib/spm_cache/core/parallel.rb`) adds `parallel_map`/`parallel_each` to Array.

## SPM Metadata Parsing

- `lib/spm_cache/core/syntax/` provides representable mixins: `json.rb`, `hash.rb`, `yml.rb`, `plist.rb`.
- Lockfile is JSON (`JSONRepresentable`); config is YAML (`YAMLRepresentable`).
- `Desc` parsing wraps `swift package describe --type json` output.

## Templates

- ERB templates under `lib/spm_cache/assets/templates/`; rendered via `Utils::Template.render(name, vars)` / `render_to` (`lib/spm_cache/utils/template.rb`).
- Template files named `{name}.template`.

## Swift Companion Conventions

- Tools version 6.0; structure `CLI/` (ArgumentParser commands) + `Core/` (domain).
- `PascalCase` types, `camelCase` members; protocols for abstraction (`CommandRunning`, `ProxyPackageProtocol`).
- Logging via `Logger` struct with Rainbow colors (`tools/spm-cache-proxy/Sources/Core/Log/`).
- Errors via `throws`/`try`; CLI exits via `ExitCode.failure`.
- One primary type per file.

<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->

## Architecture

## Pattern

## Layers (top → bottom)

## Core Mechanism: Proxy-Package Architecture

## Data Flow (typical `spm-cache use`)

```

```

## Fast Path

## Key Abstractions

| Abstraction | File | Role |
|---|---|---|
| `Installer` | `lib/spm_cache/installer.rb` | Orchestrates a full run |
| `SPM::BuildPipeline` | `lib/spm_cache/spm/build_pipeline.rb` | xcframework build loop |
| `SPM::Desc` / `Target` / `Product` | `lib/spm_cache/spm/desc/` | `swift package describe` model |
| `SPM::Xcframework` / `Slice` | `lib/spm_cache/spm/xcframework/` | Framework assembly & metadata |
| `SPM::Pkg::Proxy` | `lib/spm_cache/spm/pkg/proxy.rb` | Proxy Package.swift model |
| `Storage::GitStorage` / `S3Storage` | `lib/spm_cache/storage/` | Remote cache backends |
| `Core::Lockfile` | `lib/spm_cache/core/lockfile.rb` | SPM graph snapshot |
| `Core::DiffDetector` | `lib/spm_cache/core/diff_detector.rb` | Change detection |
| `Core::Config` | `lib/spm_cache/core/config.rb` | Singleton paths/options |
| `Core::Sh` | `lib/spm_cache/core/sh.rb` | Shell-out (Open3) |

## Entry Points

- `bin/spm-cache` — Ruby executable (`spec.executables`)
- `lib/spm_cache/main.rb` — `Main.run(argv)` → `Main.load_all` (requires all `.rb` under `lib/spm_cache/` sorted) → `Command.run(argv)`
- `tools/spm-cache-proxy` — Swift executable, subcommands `gen-proxy`, `gen-umbrella`, `resolve`

<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->

## Project Skills

No project skills found. Add skills to any of: `.claude/skills/`, `.agents/skills/`, `.cursor/skills/`, `.github/skills/`, or `.codex/skills/` with a `SKILL.md` index file.
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->

## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:

- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->

<!-- GSD:profile-start -->

## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
