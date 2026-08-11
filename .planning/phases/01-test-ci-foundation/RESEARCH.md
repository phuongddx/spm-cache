# Phase 1 Research — Test CI Foundation

> **Phase:** 1 — Test CI Foundation
> **Requirement:** REL-01
> **Method:** Inline research (typed gsd-phase-researcher agent unavailable this session — provider credential error; facts below are from established GitHub Actions conventions + the project's existing workflow)

## 1. GitHub Actions macOS Runners

- **`runs-on: macos-latest`** resolves to the newest generally-available macOS runner image. As of the Swift 6.0 era this is `macos-14` (Apple Silicon) / `macos-15`. To target Swift 6.0 (Xcode 16), **`macos-15` is the safe explicit choice** — Xcode 16 requires macOS 14+ and ships on the macos-15 image.
- **Xcode selection** — the macOS runner images ship multiple Xcode versions preinstalled. Two ways to pin:
  - **`sudo xcode-select -s /Applications/Xcode_16.app`** (manual, fragile if the exact app name differs)
  - **`maxim-lobanov/setup-xcode@v1`** action (recommended — declarative, version-globbed, well-maintained). Usage:
    ```yaml
    - uses: maxim-lobanov/setup-xcode@v1
      with:
        xcode-version: '16'
    ```
  This is the current best practice and self-documents the required Xcode in the workflow.

## 2. Ruby Matrix on macOS Runners

- **`ruby/setup-ruby@v1`** is the standard action. It reads `.ruby-version` if present, or accepts a `ruby-version` input. For a matrix:
  ```yaml
  strategy:
    matrix:
      ruby: ['3.0', '3.1', '3.2', '3.3']
  steps:
    - uses: ruby/setup-ruby@v1
      with:
        ruby-version: ${{ matrix.ruby }}
        bundler-cache: true   # auto-runs `bundle install` + caches gems
  ```
- `bundler-cache: true` removes the need for a separate `bundle install` step and cache config.
- **Native extension gotcha:** `xcodeproj` and `CFPropertyList` both have native C extensions. On a macOS runner with Xcode present and a working Ruby toolchain, `bundle install` compiles them cleanly. The `ruby/setup-ruby` action ensures dev tools are available. No special flag needed, but `bundler-cache: true` speeds repeat runs.
- The gemspec declares `required_ruby_version = ">= 3.0.0"`, so the 3.0–3.3 matrix is the correct coverage floor.

## 3. Swift Companion Testing

- `tools/spm-cache-proxy/Package.swift` declares `// swift-tools-version: 6.0`, so the runner must have **Swift 6.0 / Xcode 16**. This confirms `macos-15` + Xcode 16 selection.
- Build + test:
  ```yaml
  - name: Build proxy (release)
    run: make proxy.build
  - name: Test proxy
    working-directory: tools/spm-cache-proxy
    run: swift test
  ```
  Note: `make proxy.build` runs `swift build -c release`; `swift test` builds the debug test target. The release build validates that the regression specs' expected binary (`.build/release/spm-cache-proxy`) is produced.
- **`.build/` caching** — optional but worth it (Swift builds are slow). Use `actions/cache@v4` keyed on `tools/spm-cache-proxy/Package.resolved`. Low priority for Phase 1; can add later. (`.build/` is gitignored — this is CI-only.)

## 4. Workflow Structure — One Job vs Two

**Recommendation: two jobs, `ruby-tests` and `swift-tests`.** Reasons:
- They have different runners/needs: Ruby matrix (4 versions) vs a single Swift run (one Xcode). A single matrix job would either over-build Swift (×4) or under-build Ruby (×1).
- Independent jobs fail independently — a Swift toolchain hiccup doesn't mask a Ruby failure.
- Both gate a PR via the `checks` requirement.

Both jobs use the same triggers and `concurrency` group to cancel stale runs.

## 5. Triggers + Concurrency

```yaml
on:
  push:
    branches: [main]
  pull_request:
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true
```

This matches the project's intent (run on every PR + push to main) and cancels superseded runs to save CI minutes.

## 6. Existing Workflow Conventions (from `.github/workflows/update-tap.yml`)

Mirror where sensible:
- `actions/checkout@v4` (the tap workflow uses v4 — stay consistent)
- Concise step names
- The tap workflow runs on `ubuntu-latest` because it only updates a formula — **this CI must run on macOS** because the tool is macOS-only and the Swift/Xcode toolchain is required.

## 7. Recommended Workflow Skeleton (for the planner)

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  ruby-tests:
    name: Ruby ${{ matrix.ruby }}
    runs-on: macos-15
    strategy:
      fail-fast: false
      matrix:
        ruby: ['3.0', '3.1', '3.2', '3.3']
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: ${{ matrix.ruby }}
          bundler-cache: true
      - name: RSpec
        run: bundle exec rspec

  swift-tests:
    name: Swift (proxy tool)
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: '16'
      - name: Build proxy (release)
        run: make proxy.build
      - name: Test proxy
        working-directory: tools/spm-cache-proxy
        run: swift test
```

## 8. Gotchas Summary

- **Xcode 16 / Swift 6.0 requires macos-15** (or macos-14 with explicit Xcode 16 selection). Pin Xcode explicitly via `maxim-lobanov/setup-xcode@v1` to avoid silent drift when Apple updates the runner image.
- **`fail-fast: false`** on the Ruby matrix so one Ruby version failing doesn't cancel the others — important for coverage visibility.
- **Native gem extensions** (`xcodeproj`, `CFPropertyList`) compile fine on the macOS runner; `bundler-cache: true` handles install + caching.
- **No coverage tool today** (no SimpleCov) — Phase 1 doesn't add one; it just runs the suite.
- **Permissions:** the tap workflow needs a PAT for cross-repo push; this CI needs no special permissions — default `read` is fine. No `permissions:` block required, but adding `permissions: { contents: read }` is good hygiene.

## Confidence

High. GitHub Actions macOS-runner + Ruby/Swift patterns are stable, mature conventions. The only volatile datum is the exact `macos-*` label resolving to an image with Xcode 16 — pinning via `maxim-lobanov/setup-xcode@v1` with `xcode-version: '16'` removes that risk.
