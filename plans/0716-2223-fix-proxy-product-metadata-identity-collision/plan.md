---
title: "Fix proxy product metadata + identity collision (3 field bugs)"
description: "Fix the 3 field-reported bugs that block spm-cache on real projects: proxy package-identity collision (dup GUIDs), wrong product names from identity fallback, and plugin-only packages breaking graph resolution."
status: pending
priority: P1
branch: "main"
tags: [bugfix, proxy-generator, lockfile]
blockedBy: []
blocks: []
created: "2026-07-16T15:24:23.763Z"
createdBy: "ck:plan"
source: skill
---

# Fix proxy product metadata + identity collision (3 field bugs)

## Overview

A field run against a real 59-package iOS project (Realm, Firebase, FacebookCore, ScanbotSDK, PSPDFKit, SwiftGenPlugin, internal SDKs) surfaced three blocking bugs, all root-caused in
`plans/reports/debugger-0716-2209-proxy-product-name-plugin-guid-triage-report.md`:

1. **Identity collision / duplicate product GUIDs (hard blocker, any cache-miss package).** The proxy wrapper folder is named exactly the package slug, colliding with the real package's SwiftPM identity → "Conflicting identity" + cyclic-dependency error; Xcode refuses to load the graph. Fix verified by real `swift build` repro: rename wrapper folder to `<slug>_proxy`.
2. **Wrong product names (53/59 packages).** `spm-cache.lock` never records real product names; Swift side falls back to package identity (`realm-swift` instead of `Realm`/`RealmSwift`) → umbrella resolution fails immediately.
3. **Plugin-only packages break resolution (SwiftGenPlugin).** No product-type concept exists anywhere; generators emit a `.library` for every package including plugin-only ones → whole-graph resolution failure at the umbrella step.

Bugs 2+3 share one root: no `swift package describe` product metadata (name, type) ever reaches the lockfile. Bug 1 is independent and cheapest — fixed first.

**Key design decisions (validated, amended per red-team review `plans/reports/from-red-team-to-planner-0716-2223-proxy-bugfix-plan-review-report.md`):**
- Lockfile schema evolves to a `products: [{name, type, targets}]` array per package (not a singular `product_name`) because real packages (Realm, Firebase) export multiple library products and `integrate_proxy_into_project` rewires per-product names taken from the host project. `targets` (module names) are needed for shim `@_exported import` lines where product name != module name.
- **No flow currently materializes checkouts before `gen_proxy`** (red-team BLOCKER 1: `gen-umbrella` never runs resolve; the only resolve is in `Installer::Build` AFTER proxy generation; the sandbox is `rm_rf`'d every run). Phase 2 therefore extracts the existing resolve+DerivedData-fallback from `Installer::Build` into shared code and runs it in ALL flows between `gen_umbrella` and a new enrichment step, before `gen_proxy`. Cost: `use` gains a resolve step (network on cold cache); offline order: DerivedData fallback → legacy per-package fallback → warn.
- graph.json granularity becomes **one entry per library product** — this changes CLI target names (`realm-swift` → `Realm`/`RealmSwift`), hit/miss counts, and means N builds per N-product checkout (documented in Phase 2/4).
- Product-name rekeying makes all existing `~/.spm-cache/<config>/<identity>.xcframework` binaries unreachable (full rebuild, no GC). Correct, not just tolerable: those binaries were built with the wrong module name anyway. Called out in release notes (Phase 4).
- Plugin-only packages are skipped by both generators. Xcode integration keeps ONLY refs URL-matching a plugin-only lockfile entry; everything else (incl. all local refs, i.e. prior proxy refs) is stripped as today — preserving unmatched refs would recreate the identity-collision bug and accumulate proxy refs across runs (red-team BLOCKER 2).

## Phases

| Phase | Name | Status |
|-------|------|--------|
| 1 | [Proxy identity collision fix](./phase-01-proxy-identity-collision-fix.md) | Pending |
| 2 | [Lockfile product metadata plumbing](./phase-02-lockfile-product-metadata-plumbing.md) | Pending |
| 3 | [Plugin-only package handling](./phase-03-plugin-only-package-handling.md) | Pending |
| 4 | [Regression tests and release](./phase-04-regression-tests-and-release.md) | Pending |

Dependencies: Phase 1 independent. Phase 3 depends on Phase 2 (needs product-type metadata). Phase 4 depends on 1-3.

## Acceptance criteria (plan-level)

- A cache-miss package no longer produces a SwiftPM "Conflicting identity" warning or cyclic-dependency error (Phase 1, provable with existing fixture specs running the real binary).
- Proxies and umbrella reference real library product names (e.g. `RealmSwift`), sourced from `swift package describe`, for single- and multi-product packages (Phase 2).
- A plugin-only package (SwiftGenPlugin-like) resolves: skipped by generators, original Xcode package reference preserved (Phase 3).
- Full `bundle exec rspec` + `swift test` + fixture specs green; docs updated; v0.2.0 released via existing tag/release/tap flow (Phase 4).

## Dependencies

None cross-plan. (`plans/0714-2347-cache-only-package-allowlist` shows `status: pending` in frontmatter but its work shipped in v0.1.3 — stale metadata, no overlap.)

## Open questions

- Whether `eh_oauth_sdk_ios` in the field report was on the miss path (assumed; the verified fix covers all miss-path packages regardless).
- Stale-lockfile migration: `generate_lockfile_from_resolved` short-circuits when `spm-cache.lock` exists, so existing users keep metadata-less lockfiles — Phase 2 adds a regenerate/enrich-when-missing rule.
