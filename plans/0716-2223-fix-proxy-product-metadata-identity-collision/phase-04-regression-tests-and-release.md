---
phase: 4
title: "Regression tests and release"
status: pending
effort: "S"
priority: P1
dependencies: [1, 2, 3]
---

# Phase 4: Regression tests and release

## Overview

End-to-end regression sweep across all three fixes, docs update, and v0.2.0 release through the now-working tag → GitHub Release → Homebrew tap pipeline.

## Requirements

- Functional: one fixture-driven end-to-end spec covering all three bug scenarios in a single lockfile (multi-product package, plugin-only package, miss-path package) against the real built binary.
- Non-functional: docs reflect new lockfile schema, `plugin` status, and `_proxy` folder convention; release notes name all three field bugs.

## Related Code Files

- Create: `spec/gen_proxy_field_regression_spec.rb` — combined fixture (skips gracefully when binary not built, mirroring existing fixture specs).
- Modify: `docs/system-architecture.md` (lockfile schema, proxy folder naming, status list), `docs/codebase-summary.md`, `docs/project-roadmap.md` (mark bugs fixed).
- Modify: `VERSION` (0.1.3 → 0.2.0 — VALIDATED DECISION: minor bump signals the behavior changes: CLI target names, cache rekeying, use-flow resolve), `Gemfile.lock` (via `bundle install`).

## Implementation Steps

1. Build release binary (`make proxy.build`), run full `bundle exec rspec` + `swift test`; fix any regressions (do not weaken tests).
2. Write the combined field-regression fixture spec; assert: real product names in proxies, `_proxy` folder naming, plugin package skipped + preserved, no identity string appearing as both wrapper folder and dependency identity.
3. Docs sweep (read-before-write per docs rules; keep each file under its maxLoc). Release notes MUST call out (red-team M3/M2): (a) existing `~/.spm-cache` binaries become unreachable after the module-name rekeying — full rebuild on first run; correct because old binaries were built with identity-derived (wrong) module names; no GC, stale files can be manually deleted; (b) CLI target names changed from package identity to real product names (`spm-cache build Realm`, not `realm-swift`); (c) `use` now performs checkout resolution (network on cold SwiftPM cache; DerivedData fallback covers offline).
4. Version bump: `VERSION` → 0.2.0, `bundle install`, commit sequence per repo convention (feature commits first, then `chore: bump version to 0.2.0`).
5. Tag `v0.2.0`, push, `gh release create v0.2.0` (ensure `gh` active account is `phuongddx` per CLAUDE.md; TAP_REPO_TOKEN secret already fixed), verify `update-tap.yml` run succeeds and tap formula shows 0.2.0. (VALIDATED DECISION: no separate GitHub issues for the three bugs — release notes carry the descriptions.)

## Success Criteria

- [ ] Combined regression spec green against the real binary.
- [ ] Full rspec + swift test green; no lint/build errors.
- [ ] Docs updated and consistent with implemented schema/naming.
- [ ] v0.2.0 released; tap workflow run `success`; formula url/sha updated to v0.2.0.

## Risk Assessment

- Tap workflow regression → verified working for v0.1.3; re-verify run status, don't assume.
- Schema change lands in a patch release — acceptable pre-1.0, but release notes must call out lockfile auto-enrichment so users understand the lockfile diff.
