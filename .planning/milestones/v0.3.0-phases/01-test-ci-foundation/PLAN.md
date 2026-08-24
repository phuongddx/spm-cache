# Plan: Phase 1 — Test CI Foundation

> **Phase:** 1
> **Requirement:** REL-01
> **Mode:** Horizontal Layers
> **Plan generated:** 2026-08-10 (inline — typed gsd-planner agent unavailable this session; labeled degraded path)
> **Research:** `.planning/phases/01-test-ci-foundation/RESEARCH.md`

## Goal
Establish a CI pipeline (`.github/workflows/ci.yml`) that runs the full RSpec + Swift test suite on every PR and push to main — the project's first test CI.

## Approach
A single new workflow file with two independent jobs:
1. **`ruby-tests`** — matrix of Ruby 3.0/3.1/3.2/3.3 on `macos-15`, using `ruby/setup-ruby@v1` with `bundler-cache: true`, running `bundle exec rspec`.
2. **`swift-tests`** — single job on `macos-15` with Xcode 16 pinned via `maxim-lobanov/setup-xcode@v1`, running `make proxy.build` then `swift test` in `tools/spm-cache-proxy`.

Two jobs (not one matrixed job) because the Ruby suite has a 4-version matrix while Swift needs one Xcode run; combining would over-build Swift or under-build Ruby. Independent jobs fail independently and both gate the PR.

## Tasks

### Task 1: Create `.github/workflows/ci.yml`
**Owner:** executor
**Files:** `.github/workflows/ci.yml` (new)

Create the workflow with:
- `name: CI`
- Triggers: `on: push: branches: [main]` + `on: pull_request:`
- `concurrency: { group: ci-${{ github.ref }}, cancel-in-progress: true }`
- `permissions: { contents: read }`
- **Job `ruby-tests`:**
  - `runs-on: macos-15`
  - `strategy: { fail-fast: false, matrix: { ruby: ['3.0','3.1','3.2','3.3'] } }`
  - Steps: `actions/checkout@v4` → `ruby/setup-ruby@v1` (`ruby-version: ${{ matrix.ruby }}`, `bundler-cache: true`) → run `bundle exec rspec`
- **Job `swift-tests`:**
  - `runs-on: macos-15`
  - Steps: `actions/checkout@v4` → `maxim-lobanov/setup-xcode@v1` (`xcode-version: '16'`) → `make proxy.build` → `working-directory: tools/spm-cache-proxy`, run `swift test`

Use the skeleton in `RESEARCH.md` §7 as the starting point.

### Task 2: Validate YAML + structure
**Owner:** executor
**Files:** (no file changes — verification only)

- Run `ruby -ryaml -e 'YAML.load_file(".github/workflows/ci.yml"); puts "YAML OK"'` (or `python3 -c 'import yaml; yaml.safe_load(open(".github/workflows/ci.yml"))'`) to confirm the file parses.
- Confirm both jobs present: `grep -E '^\s+(ruby-tests|swift-tests):' .github/workflows/ci.yml`.
- Confirm triggers: `grep -A2 '^on:' .github/workflows/ci.yml`.

### Task 3: Commit the workflow
**Owner:** executor
**Files:** `.github/workflows/ci.yml`

Commit message: `ci: add test pipeline (RSpec matrix + swift test)`.

### Task 4: Document local-validation alternative
**Owner:** executor
**Files:** (note in commit body or README, not a new file)

Since CI won't actually run until pushed to GitHub, note in the final summary that the user can validate locally with `make test` (Ruby) and `make proxy.build && (cd tools/spm-cache-proxy && swift test)` (Swift). The actual CI run is validated on the first PR/push.

## Out of Scope
- Adding a coverage tool (SimpleCov) — not in REL-01
- `.build/` caching for Swift — optional optimization, defer
- Adding a "latest Xcode" canary job — the periodic-canary idea is noted for later; Phase 1 pins Xcode 16 only
- Modifying `update-tap.yml` — release workflow stays untouched
- Linux/Windows runners — tool is macOS-only

## Risks
- **Runner image drift** — Apple/GitHub may update `macos-15`'s default Xcode. Mitigation: `maxim-lobanov/setup-xcode@v1` with `xcode-version: '16'` pins explicitly.
- **First-run failures** — the regression specs skip gracefully when the Swift binary isn't built (`let(:binary)` check), but `make proxy.build` runs first in the Swift job, so the binary will be present for any Ruby-aware checks. Ruby specs that shell out to the binary will find it.
- **macOS runner availability/minutes** — macOS runners consume more minutes than Linux. The 4-version Ruby matrix × macOS is the cost; acceptable for a macOS-only tool. `fail-fast: false` keeps coverage visible.

## Success Criteria Mapping
1. `ci.yml` exists + triggers on PR + push to main → Tasks 1–2
2. Ruby 3.0–3.3 matrix runs `bundle exec rspec` on macos-15 → Task 1 (`ruby-tests` job) — DELIVERED: 3.1/3.2/3.3 (3.0 dropped at merge 5759c5b; spm_cache.gemspec requires >= 3.1.0)
3. Swift runs `make proxy.build` + `swift test`, Xcode pinned → Task 1 (`swift-tests` job)

## Verification (inline plan-check — degraded path)
- [ ] Every task maps to a file (concrete, not abstract)
- [ ] Every success criterion has a task covering it (3/3 ✓)
- [ ] No task depends on a later task (Task 2 validates Task 1's output, Task 3 commits it — linear)
- [ ] Out-of-scope explicitly excludes coverage tool, `.build/` caching, canary job, non-macOS runners
- [ ] Risks have mitigations
