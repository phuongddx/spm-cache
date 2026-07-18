# CI/CD Integration

GitHub Actions workflow for building and sharing spm-cache artifacts.

## Table of Contents

1. [CI Install Options](#ci-install-options)
2. [Full CI Workflow](#full-ci-workflow)
3. [CI Exclusion Strategy](#ci-exclusion-strategy)
4. [Scheduled Cache Maintenance](#scheduled-cache-maintenance)
5. [CI vs Local Strategy](#ci-vs-local-strategy)

## CI Install Options

```yaml
# RubyGems (no extra setup)
- name: Install spm-cache
  run: gem install spm-cache

# Homebrew (avoids the Ruby toolchain step; README's recommended install method)
- name: Install spm-cache
  run: brew install phuongddx/spm-cache/spm-cache
```

Either works in CI — pick whichever fits the runner image. `macos-latest`
GitHub-hosted runners have both Ruby and Homebrew preinstalled.

## Full CI Workflow

```yaml
name: Build & Cache
on: [push]

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install spm-cache
        run: gem install spm-cache

      - name: Pull remote cache
        run: spm-cache remote pull --config=debug
        working-directory: ./YourApp

      - name: Build dependencies into cache
        run: spm-cache build --recursive
        working-directory: ./YourApp

      - name: Use cache
        run: spm-cache
        working-directory: ./YourApp

      - name: Build app
        run: xcodebuild -project YourApp.xcodeproj -scheme YourApp build

      - name: Push updated cache
        run: spm-cache remote push --config=debug
        working-directory: ./YourApp
```

## CI Exclusion Strategy

Two ways to control what CI caches, same config keys as local dev:

- **`ignore`** (denylist) — exclude a small, known-flaky set while caching
  everything else. Best when most dependencies are safe to cache and only a
  few need to always build from source.
- **`cache_only`** (allowlist) — when non-empty it wins outright and `ignore`
  is skipped entirely; every package not listed compiles from source (status
  `excluded`, same behavior as `ignored`, just a different config key drives
  it). Best for CI when you want a small, explicitly reviewed set of cached
  packages rather than a growing exclusion list. No CLI command for
  `cache_only` — set it directly in `spm-cache.yml` (or generate it as a CI
  step before `spm-cache build` runs).

`spm-cache off TARGET` is the CLI equivalent of adding to `ignore` — usable
in CI the same way as local dev, re-run `spm-cache` after to apply.

## Scheduled Cache Maintenance

Separate from the per-push build workflow above — a periodic job to keep the
remote cache from growing unbounded:

```yaml
name: Cache Maintenance
on:
  schedule:
    - cron: "0 3 * * 0"   # weekly, Sunday 03:00 UTC

jobs:
  clean:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install spm-cache
        run: gem install spm-cache

      - name: Preview what would be removed
        run: spm-cache cache clean --all --dry
        working-directory: ./YourApp

      # Review the dry-run output before enabling the actual clean below.
      # - name: Clean cache
      #   run: spm-cache cache clean --all
      #   working-directory: ./YourApp
```

Keep the actual `--all` clean commented out until a human has reviewed a
`--dry` run's output at least once — cache clean is not reversible.

## CI vs Local Strategy

- **CI**: Pull cache → build missed deps → push cache → build app
- **Local dev**: Pull cache → use cache → build app
