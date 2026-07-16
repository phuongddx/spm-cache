# Brainstorm: `cache_only` package allowlist

> Date: 2026-07-14 | Project: spm-cache | Mode: brainstorm (no flags)

## Problem statement

Today `spm-cache.yml`'s `ignore` key is a denylist: list packages to *exclude* from
caching, everything else is cache-eligible. User wants the inverse: a config key to
list the *only* packages they want cached, everything else falls back to source —
without hand-maintaining a growing `ignore` list as deps are added.

## Requirements (confirmed)

- New config key: **`cache_only`** (array of glob patterns, default `[]` = disabled,
  fully backward compatible — empty means today's `ignore`-only behavior).
- Matching semantics: same glob matching as `ignore` today (package name or product
  name).
- Precedence: **`cache_only` wins outright** when non-empty; `ignore` is skipped
  entirely (not combined/intersected).
- Graph status: excluded-by-`cache_only` packages get a **new distinct `"excluded"`
  status** in `graph.json` (not reused `"ignored"`) — user wants it separately
  reportable in stats/cachemap viz from explicit `ignore` entries.
- No new CLI command — config-file only, no `spm-cache only TARGETS` mutator (unlike
  the existing `spm-cache off TARGETS` which mutates `ignore`).

## Scout findings (why this design, not a parallel system)

`ignore` enforcement isn't in Ruby — `Config#should_ignore?` is barely used (only by
`spm-cache off` and specs). The real glob-match happens in Swift
(`ProxyGenerator.isIgnored`, `tools/spm-cache-proxy/Sources/Core/Generator/ProxyGenerator.swift`),
fed by Ruby via a `--ignore` CSV CLI flag (`lib/spm_cache/spm/pkg/proxy_executable.rb` →
`gen-proxy`). `graph.json`'s `hit`/`missed`/`ignored` status is the single source of
truth; Ruby's `Cachemap` (`lib/spm_cache/cache/cachemap.rb`) only reads it, never
re-derives it. `spm-cache build [TARGETS]` (`lib/spm_cache/installer/build.rb`)
filters against that status but doesn't compute it. New feature must plug into this
same pipeline, not fork a second one.

## Approaches considered

1. **Accepted (with modifications below)** — mirror the `ignore` pipeline exactly:
   new config key, new CLI flag Ruby→Swift, Swift computes status.
2. Rejected: reuse `"ignored"` status for `cache_only` exclusions (simpler, zero
   blast radius) — user wants a distinct `"excluded"` bucket for reporting, so this
   is out.
3. Rejected: combine `only ∩ !ignore` — redundant once `only` wins outright; adds a
   confusing second filter axis for no behavioral gain.
4. Rejected (for now): `spm-cache only TARGETS` CLI mutator — out of scope, config
   file only per decision.

## Design

**Key implementation trick — precedence enforced Ruby-side, not Swift-side:**
`Proxy#prepare` decides which single flag to send. If `cache_only` is non-empty, it
sends `--cache-only` and **omits `--ignore` entirely**; if `cache_only` is empty, it
sends `--ignore` as today. Swift never needs to combine both filters — it only ever
sees one active list per run. Keeps `ProxyGenerator` single-responsibility.

### Ruby changes
- `lib/spm_cache/core/config.rb`: add `"cache_only" => []` to `DEFAULT_CONFIG`; add
  `cache_only_list` reader (mirrors `ignore_list`).
- `lib/spm_cache/spm/pkg/proxy.rb` (`Proxy#prepare`): read `cache_only_list`; if
  non-empty, pass `--cache-only` and skip `--ignore`; else current `--ignore`
  passthrough unchanged.
- `lib/spm_cache/spm/pkg/proxy_executable.rb` (`gen_proxy`): mirror the existing
  `--ignore` CSV-join/quoting logic for `--cache-only`.
- `lib/spm_cache/cache/cachemap.rb`: add `excluded` accessor (status ==
  `"excluded"`), include in `stats`/`print_stats`.
- `lib/spm_cache/installer/build.rb` (`filter_requested_targets!`): include
  `excluded` in `all_known`; warn `"'#{t}' is excluded by cache_only; skipping"` for
  explicit requests of excluded targets (parallel to the existing ignore warning).

### Swift changes (`tools/spm-cache-proxy/Sources/`)
- `CLI/GenProxy.swift`: parse `--cache-only` into `cacheOnlyPatterns` (mirrors
  `--ignore` parsing).
- `Core/Generator/ProxyGenerator.swift`: when `cacheOnlyPatterns` is non-empty, force
  status `"excluded"` for packages that don't match any pattern, bypassing cache
  lookup entirely, reusing the same source-fallback manifest code path `"ignored"`
  uses today. When empty, current `ignore`-based logic is untouched. Share the glob
  helper between both paths (DRY — same fnmatch function, different pattern list).

### Docs
- `docs/deployment-guide.md`: add `cache_only: []` to the config template with a
  precedence note ("overrides ignore when non-empty").
- `docs/system-architecture.md`: update the 3-state status description to 4 states
  (`hit`/`missed`/`ignored`/`excluded`) with the precedence rule spelled out.

### Tests (mirroring existing patterns)
- `spec/config_spec.rb`: `cache_only_list` default + read from yaml.
- `spec/proxy_executable_spec.rb`: assert `--cache-only` CLI string construction;
  assert `--ignore` is omitted when `cache_only` is non-empty.
- New `spec/gen_proxy_cache_only_spec.rb` (mirrors `spec/gen_proxy_ignore_spec.rb`):
  Swift-binary fixture asserting `graph.json` status `"excluded"` vs `"hit"`/`"missed"`,
  and that excluded packages still get a source-fallback `Package.swift`.
- `spec/installer_build_spec.rb`: extend for the new excluded-target warning path.

## Risks

- **Silent full-exclusion on typo**: if `cache_only` patterns match zero packages,
  everything becomes `"excluded"` — same soft-fail nature as an `ignore` typo today
  (falls back to source, doesn't break the build). Cheap guard-rail worth adding:
  log a warning if `cache_only` is non-empty but matched 0 of N packages.
  Not mandatory for v1 — flagging as an easy follow-up, not blocking.
- Backward compatibility: default `cache_only: []` is behaviorally identical to
  today. No migration needed, no risk.
- Swift fixture specs (`gen_proxy_ignore_spec.rb`-style) are skipped if the Swift
  binary isn't built locally — same pre-existing constraint applies to the new spec,
  not a new risk.

## Success criteria

- Setting `cache_only: ["Alamofire"]` in `spm-cache.yml` and running `spm-cache use`
  results in `graph.json` showing `Alamofire` as `hit`/`missed` (cache-eligible) and
  every other package as `"excluded"`.
- `ignore` list is silently skipped (not combined) when `cache_only` is non-empty —
  verify via CLI-arg spec (no `--ignore` flag sent).
- `spm-cache build` with no args builds only `missed` (unaffected by `excluded`
  packages, which are never in `missed`).
- Existing `ignore`-only behavior (empty `cache_only`) is unchanged — full regression
  pass on `spec/gen_proxy_ignore_spec.rb` and friends.

## Unresolved questions

- None blocking. Optional follow-up: 0%-match warning guard-rail (see Risks) —
  defer to plan phase, mention as a nice-to-have task.
