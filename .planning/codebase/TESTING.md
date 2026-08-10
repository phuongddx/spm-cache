---
title: Testing
focus: quality
mapped_date: 2026-08-10
last_mapped_commit: 5687b4641c1d7a36ef4fc99d59fdccf6dc09c5e0
---

# Testing

## Framework

- **RSpec** `~> 3.12` (Ruby); Swift tests via **XCTest** in `tools/spm-cache-proxy/Tests/`.
- ~4,400 LOC across ~30 spec files in `spec/`.

## Running Tests

- Ruby: `bundle exec rspec` or `make test`
- Swift companion: `swift test` inside `tools/spm-cache-proxy/` (build first with `make proxy.build`)
- Swift companion must be built with `make proxy.build` before the integration/regression specs exercise it; those specs **skip gracefully** if the binary is absent (see `spec/gen_proxy_field_regression_spec.rb` `let(:binary)`).

## Test Structure & Naming

- `spec/*_spec.rb`; `spec_helper.rb` bootstraps (`require "spm_cache/main"`) and includes a few base sanity specs (version, ROOT constant).
- Fixtures: `spec/fixtures/*.json` (sample lockfiles for gen-proxy variants, e.g. `field-regression-lockfile.json`, `products-lockfile.json`, `ignore-lockfile.json`, `plugin-lockfile.json`).
- Swift tests: `tools/spm-cache-proxy/Tests/spm-cache-proxyTests/` (`ProxyGeneratorTests.swift`, `UmbrellaGeneratorTests.swift`, `LockfileTests.swift`).

## What the Specs Cover

- **Core units:** `core_spec.rb`, `config_spec.rb`, `lockfile_spec.rb`, `diff_detector_spec.rb`, `cachemap_spec.rb`.
- **SPM domain:** `build_pipeline_spec.rb`, `buildable_spec.rb`, `xcframework_spec.rb`, `desc_target_spec.rb`, `desc_product_spec.rb`, `proxy_executable_spec.rb`, `checkout_enrichment_sequencing_spec.rb`, `lockfile_enrichment_spec.rb`.
- **Installer integration:** `installer_spec.rb`, `installer_build_spec.rb`, `installer_use_fast_path_spec.rb`, `installer_integrate_proxy_spec.rb`, `installer_consumed_dependencies_spec.rb`, `installer_retry_umbrella_resolve_spec.rb`.
- **gen-proxy regression suite** (Swift companion smoke tests against fixtures):
  - `gen_proxy_field_regression_spec.rb` — identity-collision + wrong-product-names + plugin-only bugs combined
  - `gen_proxy_root_build_regression_spec.rb`
  - `gen_proxy_cache_only_spec.rb`
  - `gen_proxy_ignore_spec.rb`
  - `gen_proxy_products_spec.rb`
  - `gen_proxy_plugin_spec.rb`

## Mocking & External Calls

- Regression specs run the **real built Swift binary** in a `Dir.mktmpdir` sandbox (umbrella/output/cache dirs), then assert on generated artefacts — these are integration tests, not pure mocks.
- No obvious heavy mocking framework usage beyond RSpec doubles/stubs; SPM/Xcode shell-outs in unit specs are scoped to the Swift companion (which the Ruby side invokes via `Core::Sh`). Specs skip when the binary isn't built rather than failing.

## Coverage

- **No coverage tool configured** (no SimpleCov in `Gemfile`/`spec_helper.rb`). Coverage is qualitative via the breadth of regression specs.

## CI

- `.github/workflows/update-tap.yml` only handles Homebrew tap updates on release publish — **there is no CI workflow that runs the RSpec/XCTest suite**. Tests are run locally via `make test` / `swift test`.
