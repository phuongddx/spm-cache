---
title: 'Wire selective caching: ignore list + build target filtering'
description: >-
  Fix the documented-but-unwired ignore feature so users can permanently exclude
  specific packages from caching, make spm-cache build honor its TARGETS
  argument, implement real source fallback for cache misses, and wire the actual
  build pipeline into Installer::Build
status: completed
priority: P1
branch: main
tags:
  - bug-fix
  - selective-caching
  - ruby
  - swift
blockedBy: []
blocks: []
created: '2026-07-13T15:33:59.086Z'
createdBy: 'ck:plan'
source: skill
---

# Wire selective caching: ignore list + build target filtering

## Overview

**Verified bugs (2026-07-13, firsthand code read):** the selective-caching feature is documented (SKILL.md, deployment-guide.md, system-architecture.md) but not functionally wired:

1. `Config#should_ignore?` (`lib/spm_cache/core/config.rb:124`) is defined but never called anywhere in `lib/` or `tools/`.
2. `spm-cache off TARGETS` (`lib/spm_cache/command/off.rb:20-22`) correctly persists targets into `spm-cache.yml` `ignore:` — but nothing downstream reads that list, so it silently does nothing.
3. Swift `gen-proxy` (`tools/spm-cache-proxy/Sources/CLI/GenProxy.swift`) has no `--ignore` option; `ProxyGenerator.generate` (`ProxyGenerator.swift:38`) only ever assigns `.hit`/`.missed`. The `.ignored` enum case (line 14), Ruby `Cachemap#ignored`, and `Proxy#cache_ignored` are dead downstream plumbing waiting to be fed.
4. `spm-cache build TARGETS` parses `@targets` (`lib/spm_cache/command/build.rb:16`) then discards it — `installer.perform_install` (line 28) takes no filter.
5. Cache-miss "fallback to source" emits an *empty stub* target (`ProxyGenerator.swift:53-55`) — a miss produces a nonexistent module at compile time, violating REQ-003. *(Added to scope by Validation Session 1.)*
6. `Installer::Build#perform_install` (`lib/spm_cache/installer/build.rb:8-17`) only logs "Building X..." — no compilation ever happens; the real pipeline exists only in `pkg build`. *(Added to scope by Validation Session 1.)*

**User-facing failure mode:** "cache 8 of my 10 libs, always source-compile the 2 volatile ones" silently doesn't work — `off` reports success but all 10 remain cache candidates. Silent wrong behavior, worse than an error.

**Fix strategy:** thread `Config#ignore_list` through the existing Ruby→Swift seam as a `--ignore` CSV option matched in Swift via `fnmatch` against both product name and package identity (Phase 1); filter `Installer::Build` by CLI TARGETS (Phase 2); replace empty-stub miss manifests with real source-fallback dependencies from lockfile coordinates (Phase 3); extract the `pkg build` pipeline into a shared module and invoke it from `Installer::Build` over umbrella checkouts (Phase 4); tests + docs (Phase 5).

## Phases

| Phase | Name | Status |
|-------|------|--------|
| 1 | [Wire ignore list end-to-end](./phase-01-wire-ignore-list-end-to-end.md) | Completed |
| 2 | [Build command target filtering](./phase-02-build-command-target-filtering.md) | Completed |
| 3 | [Source fallback manifests for miss and ignored](./phase-03-source-fallback-manifests.md) | Completed |
| 4 | [Real build pipeline in Installer::Build](./phase-04-real-build-pipeline.md) | Completed |
| 5 | [Tests and docs](./phase-05-tests-and-docs.md) | Completed |

## Dependencies

- Phase 2 depends on Phase 1 (ignored targets must be excluded from `missed` before build filtering is meaningful).
- Phase 3 depends on Phase 1 (ignored branch reuses the source-fallback manifest path).
- Phase 4 depends on Phases 2 and 3 (builds the selected list; assumes correct miss semantics).
- Phase 5 depends on Phases 1-4.
- No cross-plan dependencies (`plans/` had no other unfinished plans at creation time).

## Acceptance Criteria

- `spm-cache off VolatileLib` then `spm-cache use`: `VolatileLib` appears as `ignored` in `graph.json` and cache stats; its proxy manifest resolves to source even when a cached xcframework exists.
- Glob patterns work: `ignore: ["MyCompany*"]` ignores all modules matching by product name or package identity.
- A cache miss compiles the real package source (app builds with an empty cache) — REQ-003 actually holds.
- `spm-cache build Alamofire SnapKit` builds exactly those targets into `~/.spm-cache/{config}/` as multi-slice xcframeworks; a following `spm-cache use` reports them `hit`. Unknown names warn, don't crash.
- Ignored targets are never built by `spm-cache build` (with or without TARGETS).
- `pkg build` behavior unchanged after pipeline extraction.
- `make test` (RSpec) passes; Swift proxy tool builds via `make proxy.build`.
- Docs updated to match actual behavior.

## Out of Scope (deliberate, YAGNI)

- `ignore_local` behavior (separate config flag, separate concern).
- Remote cache interaction with ignored targets (push/pull semantics unchanged).
- Multi-module products (product vending several modules): Phase 3 documents the limitation; full support deferred.

## Validation Log

### Verification Results (Session 1, 2026-07-13)

- Claims checked: ~20 across all phases (file paths, line numbers, symbols, doc references)
- Verified: all | Failed: 0 | Unverified: 0
- Tier: Standard (Fact Checker + Contract Verifier)
- Notable: `config.raw` accessor confirmed via `HashRepresentable` (`syntax/hash.rb:7`); `should_ignore?` glob matching confirmed by runtime smoke (`Foo*` → FooKit true, Bar false); `Sh.run` confirmed shell-interpreting (`Open3.capture3` with string cmd) so single-quoting of `--ignore` values is load-bearing; doc line refs corrected: troubleshooting.md 76-78 (was ~74-78).

### Interview Decisions (Session 1, 4 questions)

1. **Ignore match key → Both**: patterns match `resolvedProductName` OR lockfile package identity (`pkg.name`). Propagated to Phase 1 Step 1.
2. **Ignored + cached binary exists → Always source**: ignored means full source mode; binary bypassed even on hit. Propagated to Phases 1 and 3.
3. **Swift-side testing → Fixture smoke**: RSpec example runs the built binary against a fixture lockfile, skips when binary absent; no Swift Tests target. Propagated to Phase 5.
4. **Pre-existing gaps (empty-stub miss fallback; log-only Installer::Build) → Expand this plan**: added as Phases 3 and 4 instead of filing follow-up issues. Plan grew from 3 to 5 phases; phase files renumbered (`tests-and-docs` 3→5).

### Whole-Plan Consistency Sweep (Session 1)

- Re-read all 6 plan files after propagation.
- Fixed: phase-02 stale "log-only remains in this plan" note (superseded by Phase 4); phase-02 out-of-scope pointer now references Phase 4; phase-05 dependencies/effort updated (deps [1,2,3,4], effort M); plan.md overview/acceptance criteria/out-of-scope rewritten for the expanded scope; former Unresolved Question #1 (empty stub) converted into Phase 3; transitive-ignore question resolved as per-module matching (documented in Phase 1 architecture).
- Remaining contradictions: none.
- Open implementation flags (deliberate, decided at cook time, carried in phase risk sections): (a) Option A vs B for source-fallback manifests — Phase 3 Step 1 spike decides; (b) umbrella checkout location vs sandbox `rm_rf` on each install — Phase 4 risk section carries both mitigations.

## Unresolved Questions

None blocking. Two implementation-time decisions are embedded as explicit spike/decision steps with fallbacks (Phase 3 Step 1; Phase 4 checkout-persistence risk).
