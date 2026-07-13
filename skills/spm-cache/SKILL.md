---
name: spm-cache
description: Cache Swift Package Manager (SPM) dependencies as .xcframework binaries to reduce Xcode clean build times. Use when the user wants to speed up Xcode builds, cache or prebuild SPM dependencies, manage binary frameworks in iOS/macOS projects, configure remote team cache sharing (Git/S3), troubleshoot xcframework cache misses or missing slices, or set up SPM caching in CI. Triggers include "spm-cache", "slow Xcode build", "cache SPM deps", "prebuild Swift packages", "xcframework cache", "binary cache for SPM", "Swift macro caching".
---

# spm-cache

Cache SPM (Swift Package Manager) dependencies as `.xcframework` binaries to reduce Xcode clean build times. Uses a **proxy package architecture**: on cache hit, Xcode links a prebuilt binary; on cache miss, it falls back to source compilation automatically.

## Prerequisites

```bash
uname -s            # must be Darwin (macOS only)
ruby --version      # >= 3.0
swift --version     # >= 6.0 (proxy tool)
xcode-select -p     # Xcode installed
```

If any prerequisite is missing, tell the user what's needed and stop.

## Install

```bash
# Homebrew (recommended)
brew install phuongddx/spm-cache/spm-cache

# RubyGems
gem install spm-cache

# Bundler: add `gem "spm-cache"` to Gemfile, then `bundle install`
```

Verify: `spm-cache --version`

## Core Workflow

All commands run from the directory containing the `.xcodeproj` file.

```bash
cd /path/to/xcode/project
ls *.xcodeproj        # verify project exists
```

### 1. Build dependencies into cache

```bash
# Build all targets in the dependency graph
spm-cache build --recursive

# Build specific target with multi-slice xcframework (sim + device)
spm-cache pkg build Alamofire --sdk=all --out=~/.spm-cache/debug

# Build config options: debug (default) or release
spm-cache build --recursive --config=release
```

### 2. Integrate cache (default command)

```bash
spm-cache              # same as `spm-cache use`
```

Creates a `spm-cache/` sandbox with proxy packages. Xcode now uses cached binaries for hits, source for misses. Add to `.gitignore`:

```bash
echo "spm-cache/" >> .gitignore
echo "spm-cache.lock" >> .gitignore
```

### 3. Verify cache status

```bash
spm-cache cache list           # list cached packages
```

### 4. Rollback (fully reversible)

```bash
spm-cache rollback             # restore original project state
```

## SDK Options

| Flag | Description |
|------|-------------|
| `--sdk=iphonesimulator` | Simulator only |
| `--sdk=iphoneos` | Device only |
| `--sdk=all` | Both simulator + device (multi-slice xcframework) |

## Configuration (`spm-cache.yml`)

Auto-generated on first run. Key options:

| Option | Default | Description |
|--------|---------|-------------|
| `ignore` | `[]` | Package names to exclude from caching |
| `ignore_local` | `false` | Skip local packages |
| `ignore_build_errors` | `false` | Don't fail on build errors |
| `keep_pkgs_in_project` | `false` | Keep original package refs alongside proxy |
| `default_sdk` | `iphonesimulator` | Default SDK for builds |

Force source mode for specific targets (adds to ignore list):

```bash
spm-cache off ProblematicTarget
spm-cache          # re-run to apply
```

## Quick Command Reference

| Command | Description |
|---------|-------------|
| `spm-cache` (`use`) | Integrate cache (default command) |
| `spm-cache build [TARGETS] [--recursive]` | Build targets into xcframeworks |
| `spm-cache pkg build TARGET [--sdk=all]` | Build single package to xcframework |
| `spm-cache off [TARGETS]` | Force source mode for targets |
| `spm-cache rollback` | Restore original project state |
| `spm-cache cache list` | List cached packages |
| `spm-cache cache clean [--all] [--dry]` | Clean cache |
| `spm-cache remote pull [--config=debug]` | Pull cache from remote |
| `spm-cache remote push [--config=debug]` | Push cache to remote |

## Global Options

| Option | Description |
|------|-------------|
| `--sdk=SDK` | iphonesimulator, iphoneos, or all |
| `--config=CONFIG` | debug or release |
| `--log-dir=DIR` | Directory for log files |
| `--no-merge-slices` | Disable merging framework slices |
| `--no-library-evolution` | Disable Swift library evolution flags |

## Detailed References

Load these only when the user needs them:

- **Remote cache setup (Git/S3)**: See [references/remote-cache.md](references/remote-cache.md)
- **CI/CD integration (GitHub Actions)**: See [references/ci-cd.md](references/ci-cd.md)
- **Troubleshooting (cache misses, missing slices, library evolution, resource bundles)**: See [references/troubleshooting.md](references/troubleshooting.md)
- **Full CLI command reference**: See [references/cli-reference.md](references/cli-reference.md)

## Architecture

spm-cache uses a **proxy package architecture**:

- **Cache hit**: Proxy `Package.swift` serves a `.binaryTarget` pointing to an `.xcframework`
- **Cache miss**: Proxy `Package.swift` falls back to source compilation
- **Root proxy**: Aggregates all per-dependency proxies into one local package reference

Build pipeline uses `xcodebuild` (not `swift build`) with library evolution flags (`-enable-library-evolution -emit-module-interface`) for binary compatibility across compiler versions.

**Local cache**: `~/.spm-cache/{debug,release}/`
**Sandbox**: `spm-cache/` (project root, regenerated each run)
**Lockfile**: `spm-cache.lock` (JSON snapshot of project SPM dependencies)
