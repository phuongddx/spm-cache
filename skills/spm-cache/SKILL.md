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

## When NOT to Use spm-cache

Skip this skill and tell the user it's likely not worth it when:

- The project has fewer than ~3 SPM dependencies — the proxy-package setup
  and sandbox overhead outweigh the clean-build time saved.
- Clean builds aren't a real pain point (e.g. CI already caches
  `DerivedData`, or the team rarely runs clean builds).
- The project only ever does incremental builds — caching only helps clean
  builds; incremental builds already skip recompiling unchanged dependencies.

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

### 1. Analyze & categorize project dependencies

Before anything else, discover the SPM packages already resolved in the
project AND classify each one, so the exclusion question (step 2) and the
build strategy (step 3) are grounded in real cache-eligibility data, not
guesses:

```bash
find . -name Package.resolved -not -path "*/spm-cache/*"
cat path/to/Package.resolved | grep '"identity"'    # list package identities
```

If no `Package.resolved` exists yet, tell the user to open the project in
Xcode once to resolve dependencies first — this also materializes each
package's checkout, which the categorization below needs.

**This step must stay read-only** — do NOT run any `spm-cache` command yet.
`spm-cache build` already rewires the `.xcodeproj` (it runs the same
`integrate_proxy_into_project` step as `spm-cache use`), so it can't be used
as a "look before you leap" step; only an external `swift package describe`
pass keeps this analysis safe to run before anything is touched.

For each package identity found, locate its checkout and describe it:

```bash
# Prefer the project's own SPM checkout; fall back to the newest Xcode
# DerivedData checkout (same location spm-cache itself falls back to):
ls -d ~/Library/Developer/Xcode/DerivedData/<ProjectName>-*/SourcePackages/checkouts/<slug> \
  2>/dev/null | xargs -I{} stat -f "%m %N" {} | sort -rn | head -1 | cut -d' ' -f2-

cd <checkout-dir> && swift package describe --type json
```

Classify each package from the JSON output. **Check Local first** — it
overrides the other three rows regardless of product shape (a local package
with no library products is still "Local," not "Plugin-only"):

| Category | Signal | Meaning |
|----------|--------|---------|
| **Local** (check first) | the dependency entry in `Package.resolved` carries a `path` | Candidate for `ignore_local: true` instead of an `ignore` entry |
| **Plugin-only** | `products` present, none with `"type": "library"` | Never cacheable — don't ask about these, don't count them toward batching |
| **Binary-only / metadata-thin** | `describe` returns no `products` at all | Cacheable, but higher risk — verify carefully after caching |
| **Regular library** | everything else | The real caching candidates — these are what step 2 asks about |

Within "regular library", also note `.dependencies.length` from the same
`describe` output: `0` means the package has no further SPM deps of its own
(a leaf) — leaf packages are safest to cache and verify first since they
can't hit a transitive version conflict. Suggest a leaf-first order for step 3.

Don't try to detect "transitive-only" packages here (e.g. a package pulled in
solely by another package, like realm-core via realm-swift) — the 4
categories above don't distinguish it, it lands in "Regular library" like
any other. That's fine: `spm-cache` v0.2.1+ auto-handles the transitive-only
version-pinning conflict internally regardless of what the user answers in
step 2, so asking about it there causes no harm beyond one possibly-redundant
question — this is a build-graph concern, not a caching-exclusion one.

Present a short summary table to the user: category, count, and the
leaf-first order for regular-library packages, with one-line pros/cons per
category (plugin/local need no exclusion question; binary-only is cacheable
but worth extra verification; regular-library leaf-first is safest to
validate the pipeline on).

**If the project has more than 20 packages**, tell the user upfront that this
analysis takes a couple of minutes (`swift package describe` runs once per
package) before starting the loop — don't run it silently.

If a package's checkout can't be found, mark it "unresolved" and skip
categorizing it rather than blocking the rest of the analysis.

### 2. Ask which packages should not be cached

Using the categorized list from step 1, ask the user about **regular-library**
packages only: "Are there any of these that should NOT be cached (always
built from source)?" — e.g. packages with build-time codegen or known-flaky
binaries. Plugin-only packages need no question at all; local packages get
an `ignore_local` suggestion instead of this question.

If they name any, write glob patterns to the `ignore` key in `spm-cache.yml`
before the first run — create the file yourself with just this key if it
doesn't exist yet (patterns match product name or package identity; no need
to hunt for the gem's internal template, `spm-cache` merges any partial YAML
with its defaults):

```yaml
ignore:
  - MyCodegenPackage
  - LocalPackage*
```

Skip this step if the user has no exclusions in mind — `ignore: []` is the
default and running `spm-cache` will auto-generate the full config file
anyway.

### 3. Build and integrate

`spm-cache build` already integrates the proxy into the Xcode project as
part of its pipeline (same `integrate_proxy_into_project` step `spm-cache
use` runs) — it's not a separate, non-integrating step. A later bare
`spm-cache` call re-confirms the integration but isn't strictly required.

**5 or fewer regular-library packages** (from step 1's categorization): build
once, as usual:

```bash
spm-cache build --recursive     # build all targets in the dependency graph; already integrates
spm-cache                       # optional re-confirmation (same as `spm-cache use`)

# Build config options: debug (default) or release
spm-cache build --recursive --config=release
```

**More than 5 regular-library packages**: build in batches of at most 5 (leaf-first, per
step 1's suggested order) to keep each round fast and easy to debug if a
target fails. Each `build` call already integrates; verify after every batch
before starting the next one:

```bash
spm-cache build PkgA PkgB PkgC PkgD PkgE   # batch 1 (leaf-first, from step 1); already integrates
spm-cache cache list                        # verify batch 1 hits
spm-cache build PkgF PkgG PkgH ...          # batch 2, repeat until done
```

Multi-slice xcframework for a single target (either path):

```bash
spm-cache pkg build Alamofire --sdk=all --out=~/.spm-cache/debug
```

Either way, this creates a `spm-cache/` sandbox with proxy packages — Xcode
now uses cached binaries for hits, source for misses. Add to `.gitignore`:

```bash
echo "spm-cache/" >> .gitignore
echo "spm-cache.lock" >> .gitignore
```

### 4. Verify cache status

```bash
spm-cache cache list           # list cached packages
```

### 5. Rollback (fully reversible)

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
| `ignore` | `[]` | Glob patterns to exclude from caching; matches product name or package identity |
| `cache_only` | `[]` | Allowlist: cache ONLY these glob patterns; overrides `ignore` entirely when non-empty |
| `ignore_local` | `false` | Skip local packages |
| `ignore_build_errors` | `false` | Don't fail on build errors |
| `keep_pkgs_in_project` | `false` | Keep original package refs alongside proxy |
| `default_sdk` | `iphonesimulator` | Default SDK for builds |

Force source mode for specific targets (adds to ignore list). Patterns
match the resolved product name OR the package identity (e.g. `MyCompany*`
ignores all modules whose product or package name starts with `MyCompany`):

```bash
spm-cache off ProblematicTarget
spm-cache          # re-run to apply
```

Ignored targets are always compiled from source, even when a cached
xcframework exists. They are never built by `spm-cache build`.

To cache only a handful of packages instead of maintaining a growing ignore
list, set `cache_only` in `spm-cache.yml` instead of using `spm-cache off` —
when non-empty it wins outright and `ignore` is skipped entirely; every
package not listed compiles from source (status `excluded`, same behavior as
`ignored`, just a different config key drives it). No CLI command for
`cache_only` — edit `spm-cache.yml` directly.

Building specific targets:

```bash
spm-cache build Alamofire SnapKit   # build only these targets
spm-cache build                     # build all missed targets
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
**Cachemap visualization**: an interactive dependency graph is generated at
`spm-cache/cachemap/index.html` every run — open with
`open spm-cache/cachemap/index.html` to inspect hit/missed/ignored/excluded/plugin
status per package visually.
