---
title: "cache_only package allowlist"
description: "Config-file allowlist inverting the ignore denylist; cache_only wins outright, emits distinct excluded graph status."
status: pending
priority: P2
effort: 6h
branch: "main"
tags: [config, cli, swift, caching, dx]
blockedBy: []
blocks: []
created: "2026-07-14T16:48:44.140Z"
createdBy: "ck:plan"
source: skill
---

# cache_only package allowlist

## Overview

Add `cache_only` config key — an allowlist inverting today's `ignore` denylist. When
`cache_only` non-empty: only listed packages are cache-eligible; all others fall back
to source and get a new distinct `"excluded"` graph status. Empty `cache_only` =
today's behavior byte-for-byte (backward compat guarantee).

**4 confirmed design decisions (from brainstorm, not re-litigated):**
1. Precedence: `cache_only` (non-empty) wins outright over `ignore`, enforced Ruby-side
   by omitting `--ignore` when `--cache-only` sent. Swift never combines both.
2. New distinct `"excluded"` status in `graph.json` (NOT reused `"ignored"`).
3. Config key name: `cache_only`.
4. No CLI mutator command — config-file only.

Source design doc: `../reports/brainstorm-0714-2308-cache-only-package-allowlist-report.md`

## Data Flow

```
spm-cache.yml (cache_only: [...])
  → Config#cache_only_list                            [Phase 1]
  → Proxy#prepare picks ONE flag:                     [Phase 1]
      cache_only non-empty → send --cache-only, omit --ignore
      cache_only empty     → send --ignore (unchanged)
  → ProxyExecutable#gen_proxy builds CLI string       [Phase 1]
  → GenProxy.swift parses --cache-only                [Phase 2]
  → ProxyGenerator: non-matching pkgs → "excluded"    [Phase 2]
      (reuses ignored source-fallback manifest path)
  → graph.json {status: "excluded"}                   [Phase 2]
  → Cachemap#excluded accessor + stats                [Phase 3]
  → Build#filter_requested_targets! warns on excluded [Phase 3]
  → docs describe 4th status + precedence             [Phase 4]
```

## Phases

| Phase | Name | Status | Depends |
|-------|------|--------|---------|
| 1 | [Ruby config + CLI plumbing](./phase-01-ruby-config-cli-plumbing.md) | Pending | — |
| 2 | [Swift status resolution](./phase-02-swift-status-resolution.md) | Pending | 1 |
| 3 | [Cachemap + build filtering](./phase-03-cachemap-build-filtering.md) | Pending | 2 |
| 4 | [Docs + full regression](./phase-04-docs-full-regression.md) | Pending | 1,2,3 |

## Dependencies

Sequential chain: 1 → 2 → 3 → 4. Phase 2 needs the `--cache-only` flag from Phase 1;
Phase 3 needs the `"excluded"` status from Phase 2; Phase 4 documents + regresses all.

No cross-plan blockers. Prior plans `plans/0713-2232-selective-caching-ignore-wiring`
(built the `ignore` mechanism this extends) and `plans/0714-1309-fix-github-issues-1-4`
are both DONE — neither blocks nor is blocked by this plan.

## Backward Compatibility

Default `cache_only: []` is behaviorally identical to today (empty → today's `--ignore`
path unchanged). No migration, no data reshape. The critical guarantee is validated in
Phase 4 by a full regression pass confirming all pre-existing `ignore` specs stay green.

## File Ownership (no overlap between phases)

- Phase 1: `lib/spm_cache/core/config.rb`, `lib/spm_cache/spm/pkg/proxy.rb`,
  `lib/spm_cache/spm/pkg/proxy_executable.rb`, `spec/config_spec.rb`,
  `spec/proxy_executable_spec.rb`
- Phase 2: `tools/spm-cache-proxy/Sources/CLI/GenProxy.swift`,
  `tools/spm-cache-proxy/Sources/Core/Generator/ProxyGenerator.swift`,
  `spec/gen_proxy_cache_only_spec.rb` (new), `spec/fixtures/` (new fixture if needed)
- Phase 3: `lib/spm_cache/cache/cachemap.rb`, `lib/spm_cache/installer/build.rb`,
  `spec/installer_build_spec.rb`, `spec/cachemap_spec.rb` (new)
- Phase 4: `docs/deployment-guide.md`, `docs/system-architecture.md`

## Global Success Criteria

- `cache_only: ["Alamofire"]` + `spm-cache use` → Alamofire `hit`/`missed`, all others
  `"excluded"` in `graph.json`.
- `ignore` silently skipped (not combined) when `cache_only` non-empty — no `--ignore`
  flag sent (asserted in Phase 1 spec).
- Empty `cache_only` = unchanged behavior — full `bundle exec rspec` green including
  all pre-existing `--ignore` cases.
