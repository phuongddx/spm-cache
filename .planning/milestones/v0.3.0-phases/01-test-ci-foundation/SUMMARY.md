# Phase 1 Summary — Test CI Foundation

> **Phase:** 1 — Test CI Foundation
> **Requirement:** REL-01
> **Status:** Complete
> **Executed:** 2026-08-10 (inline — typed gsd-executor agent unavailable; `--auto` mode)

## What was done
Created `.github/workflows/ci.yml` — the project's first test CI pipeline, distinct from the release-only `update-tap.yml`.

## Deliverables
- **`.github/workflows/ci.yml`** (51 lines) — two jobs:
  - `ruby-tests` — Ruby 3.1/3.2/3.3 matrix on `macos-15` (3.0 dropped at merge 5759c5b — spm_cache.gemspec requires >= 3.1.0), `ruby/setup-ruby@v1` with `bundler-cache: true`, runs `bundle exec rspec`. `fail-fast: false` so every version reports independently.
  - `swift-tests` — `macos-15` with Xcode 16 pinned via `maxim-lobanov/setup-xcode@v1`, runs `make proxy.build` then `swift test` in `tools/spm-cache-proxy`.

## Verification
- YAML parses cleanly (validated via `ruby -ryaml` and `python3 -c yaml.safe_load`)
- Both jobs present (`ruby-tests`, `swift-tests`)
- Ruby matrix = `['3.1','3.2','3.3']` ✓ (3.0 dropped at merge 5759c5b; gemspec >= 3.1.0)
- Xcode pin = `'16'` ✓
- Triggers: `push: branches: [main]` + `pull_request:` ✓
- Concurrency cancels stale runs; `permissions: contents: read`

## Success criteria mapping
1. `ci.yml` exists + triggers on PR + push to main ✓
2. Ruby 3.0–3.3 matrix runs `bundle exec rspec` on macos-15 ✓ — DELIVERED: 3.1/3.2/3.3 (3.0 dropped at merge 5759c5b; spm_cache.gemspec requires >= 3.1.0)
3. Swift runs `make proxy.build` + `swift test`, Xcode pinned ✓

## Notes
- **Actual CI validation** happens on the first push/PR to GitHub — the workflow can't run locally. Local equivalents: `make test` (Ruby), `make proxy.build && (cd tools/spm-cache-proxy && swift test)` (Swift).
- **Known Ruby gotcha:** `on:` parses as boolean `true` under Ruby's YAML1.1 — cosmetic only; GitHub Actions parses it correctly (cross-checked with Python's `yaml.safe_load`, which reads `on` as a string key correctly).
- **Out of scope (deferred):** SimpleCov coverage tool, `.build/` Swift caching, "latest Xcode" canary job.

## Commit
- `b664d0b` — `ci: add test pipeline (RSpec matrix + swift test)`
