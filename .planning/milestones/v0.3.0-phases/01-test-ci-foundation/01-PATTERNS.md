# Phase 1: Test CI Foundation - Pattern Map

**Mapped:** 2026-08-23
**Files analyzed:** 2 (ci.yml modification, Makefile reference)
**Analogs found:** 2 / 2

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `.github/workflows/ci.yml` | config (CI workflow) | request-response (job orchestration) | `.github/workflows/ci.yml` (itself — existing) | self-modify |
| `.github/workflows/ci.yml` (conventions) | config (CI workflow) | request-response | `.github/workflows/update-tap.yml` | conventions-match |

## Pattern Assignments

### `.github/workflows/ci.yml` (config, CI workflow — self-modify)

**Analog:** `.github/workflows/ci.yml` (existing, 36 lines)

The gap fix modifies this file in-place. The existing structure IS the pattern.

**Full existing file for reference:**
```yaml
# .github/workflows/ci.yml (current — 36 lines)
name: CI

on:
  push:
    branches: [main]
  pull_request:

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

permissions:
  contents: read

jobs:
  ruby-tests:
    name: Ruby ${{ matrix.ruby }}
    runs-on: macos-15
    strategy:
      fail-fast: false
      matrix:
        ruby: ['3.1', '3.2', '3.3']
    steps:
      - uses: actions/checkout@v5

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: ${{ matrix.ruby }}
          bundler-cache: true

      - name: RSpec
        run: bundle exec rspec

  swift-tests:
    name: Swift (proxy tool)
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v5

      - name: Select Xcode 16
        uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: '16'

      - name: Build proxy (release)
        run: make proxy.build

      - name: Test proxy
        working-directory: tools/spm-cache-proxy
        run: swift test
```

**Gap: `ruby-tests` lacks `make proxy.build` step before RSpec.**

All 23 binary-gated specs share this guard pattern (from `spec/gen_proxy_ignore_spec.rb:13-16,28-29`):
```ruby
  let(:binary) do
    local = SPMCache::ROOT.join("tools", "spm-cache-proxy",
                                ".build", "release", "spm-cache-proxy").to_s
    File.executable?(local) ? local : nil
  end

  before do
    skip "spm-cache-proxy binary not built (run make proxy.build)" unless binary
```

The binary path is `tools/spm-cache-proxy/.build/release/spm-cache-proxy`, produced by `make proxy.build`.

**Makefile target** (Makefile:12-13):
```makefile
proxy.build:
	cd tools/spm-cache-proxy && swift build -c release
```

**Fix options (from VERIFICATION.md gap analysis):**

- **Option A:** Add `make proxy.build` + Xcode selection to `ruby-tests` job before RSpec. Simple, runs the full suite including all 23 gen_proxy specs on every Ruby leg.
- **Option B:** Move the 6 `spec/gen_proxy_*_spec.rb` files into `swift-tests` after the build. Avoids Xcode setup on Ruby legs but splits the RSpec suite across jobs.

**Consequence of Option A:** `swift-tests` becomes redundant for the release build — it builds a binary nothing in that job consumes (MI-02). Consider removing `make proxy.build` from `swift-tests` or restructuring that job.

---

### `.github/workflows/update-tap.yml` (conventions reference)

**Analog:** `.github/workflows/update-tap.yml` (existing, 38 lines)

Only used for convention alignment — this file is NOT modified.

**Workflow conventions to mirror in ci.yml edits:**

- **Checkout version:** Both files already use `actions/checkout@v5` (ci.yml:15,29; update-tap.yml:7,23).
- **Concise step names:** Both use short, capitalized names (`"RSpec"`, `"Build proxy (release)"`, `"Select Xcode 16"`).
- **`permissions:` hygiene:** ci.yml already has `permissions: contents: read` (line 11). Update-tap.yml omits it because it needs write (push to tap repo).

---

## Shared Patterns

### CI Job Structure
**Source:** `.github/workflows/ci.yml`
**Apply to:** All ci.yml modifications
```yaml
# Every job follows: checkout → setup → build (if needed) → test
jobs:
  <job-name>:
    name: <descriptive>
    runs-on: <runner>
    strategy:              # if matrix
      fail-fast: false
      matrix: { ... }
    steps:
      - uses: actions/checkout@v5
      - <setup steps>
      - <build steps>
      - <test steps>
```

### Concurrency Grouping
**Source:** `.github/workflows/ci.yml:7-9`
**Apply to:** ci.yml (unchanged — already correct)
```yaml
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true
```

### Proxy Binary Build
**Source:** `Makefile:12-13`
**Apply to:** `ruby-tests` job (the gap fix)
```makefile
proxy.build:
	cd tools/spm-cache-proxy && swift build -c release
```

Note: Running `make proxy.build` requires Xcode/Swift toolchain. On a `macos-15` runner, Xcode is pre-installed but the default version may not be 16. Must add `maxim-lobanov/setup-xcode@v1` with `xcode-version: '16'` to `ruby-tests` if adding the build step (Swift 6.0 requirement).

### `timeout-minutes` (review MI-03 — optional improvement)
**Source:** `01-REVIEW.md:140-157` (review recommendation, not yet in any workflow)
**Apply to:** Both jobs in ci.yml
```yaml
ruby-tests:
  timeout-minutes: 30
swift-tests:
  timeout-minutes: 45
```

## No Analog Found

None — the gap closure modifies only files with direct analogs in the codebase.

## Metadata

**Analog search scope:** `.github/workflows/`, `Makefile`, `Gemfile`, `tools/spm-cache-proxy/Package.swift`, `spec/gen_proxy_*_spec.rb`
**Files scanned:** 9
**Pattern extraction date:** 2026-08-23
