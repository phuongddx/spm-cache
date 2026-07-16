---
phase: 1
title: "Ruby config + CLI plumbing"
status: pending
priority: P2
dependencies: []
effort: "1.5h"
---

# Phase 1: Ruby config + CLI plumbing

## Overview

Add `cache_only` config key + reader, and wire the Ruby→Swift CLI flag. This phase
enforces the precedence rule: `Proxy#prepare` picks exactly ONE flag — if
`cache_only_list` non-empty, send `--cache-only` and omit `--ignore` entirely; else
keep today's `--ignore` passthrough unchanged. No Swift changes here (Phase 2 consumes
the flag).

## Requirements

- New config key `cache_only`, default `[]` (disabled = today's behavior).
- `cache_only_list` reader mirroring `ignore_list` exactly.
- Precedence enforced Ruby-side: `--cache-only` XOR `--ignore`, never both.
- `--cache-only` CLI string built with identical CSV-join/single-quote logic as
  `--ignore`.

## Architecture

Precedence lives in `Proxy#prepare` (the single decision point), NOT in Swift and NOT
in `ProxyExecutable`. `ProxyExecutable#gen_proxy` stays a dumb string builder: it emits
`--cache-only` when given a non-empty list and `--ignore` when given a non-empty list —
it does not know about precedence. `Proxy#prepare` guarantees only one of the two lists
is ever non-empty per call by choosing which to pass.

Data in: `spm-cache.yml` `cache_only:` array. Data out: a single CLI arg string
(`--cache-only 'A,B'` or `--ignore 'A,B'` or neither) consumed by the Swift binary.

## Related Code Files

- `lib/spm_cache/core/config.rb` — `DEFAULT_CONFIG` (config.rb:15-21), `ignore_list`
  (config.rb:104-106) to mirror. MODIFY.
- `lib/spm_cache/spm/pkg/proxy.rb` — `Proxy#prepare` reads `ignore` at proxy.rb:32,
  calls `gen_proxy` at proxy.rb:35; local `gen_proxy` wrapper at proxy.rb:47-49. MODIFY.
- `lib/spm_cache/spm/pkg/proxy_executable.rb` — `gen_proxy` at proxy_executable.rb:60-65;
  `--ignore` construction at proxy_executable.rb:63. MODIFY.
- `spec/config_spec.rb` — `#ignore_list` block at config_spec.rb:35-39; `#should_ignore?`
  glob block follows. EXTEND.
- `spec/proxy_executable_spec.rb` — `#gen_proxy with ignore list` block
  (proxy_executable_spec.rb:20-68). EXTEND.

## Implementation Steps

1. **config.rb**: add `"cache_only" => []` to `DEFAULT_CONFIG` (after the `"ignore"`
   line, config.rb:16). Add reader after `ignore_list` (config.rb:106):
   ```ruby
   def cache_only_list
     raw["cache_only"] || []
   end
   ```
   Do NOT add a `should_cache_only?` predicate — precedence is enforced in `prepare`,
   not via a Config predicate (YAGNI; `should_ignore?` is already barely used).

2. **proxy.rb** `#prepare`: after reading `ignore` (proxy.rb:32), read
   `cache_only = Core::Config.instance.cache_only_list`. Change the `gen_proxy` call
   (proxy.rb:35) so that when `cache_only.any?` it passes `cache_only:` and NOT
   `ignore:`; otherwise passes `ignore:` as today. Extend the local `gen_proxy` wrapper
   (proxy.rb:47-49) and the `ProxyExecutable` call it delegates to with a
   `cache_only: []` kwarg, threaded through.

3. **proxy_executable.rb** `#gen_proxy`: add `cache_only: []` kwarg
   (proxy_executable.rb:60). Mirror the `--ignore` line (proxy_executable.rb:63):
   ```ruby
   args << "--cache-only '#{cache_only.join(",")}'" if cache_only.any?
   ```
   Keep the existing `--ignore` line unchanged — `Proxy#prepare` guarantees only one
   list is non-empty, so no explicit mutual-exclusion branch is needed here.

4. **config_spec.rb**: add a `#cache_only_list` describe block mirroring `#ignore_list`
   (config_spec.rb:35-39): default `[]`; reads from `config.raw["cache_only"]`.

5. **proxy_executable_spec.rb**: add a `#gen_proxy with cache_only list` describe block
   mirroring the `--ignore` assertions (proxy_executable_spec.rb:20-68): appends
   single-quoted `--cache-only` CSV; omits when empty/absent; single-quotes glob chars.
   Add ONE precedence case: call `gen_proxy` with BOTH `ignore: ["X"]` and
   `cache_only: ["Y"]` and assert the emitted command includes `--cache-only 'Y'` and
   does NOT include `--ignore` — this is where the precedence contract is unit-tested.
   (Note: `ProxyExecutable` itself does not enforce precedence; to test the omission
   realistically, assert on `Proxy#prepare`'s selection OR pass only `cache_only:` per
   the `prepare` contract. Prefer a `Proxy#prepare`-level spec if a stub seam exists;
   otherwise document that `prepare` is the enforcement point and test the string
   builder for `--cache-only` presence + `--ignore` omission when only `cache_only` is
   passed.)

## Success Criteria

- [ ] `bundle exec rspec spec/config_spec.rb spec/proxy_executable_spec.rb` green.
- [ ] New spec asserts `--cache-only 'A,B'` CSV/single-quote construction.
- [ ] New spec asserts `--ignore` omitted when `cache_only` is the active list.
- [ ] `bundle exec rspec` (full) still green — no regression to existing `--ignore`
      cases (proxy_executable_spec.rb:21-67).

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Precedence enforced in wrong layer (Swift or Executable instead of `prepare`) | Med | High | Explicit step 2/3 split; precedence ONLY in `Proxy#prepare`; Executable stays a dumb builder |
| Both flags sent, Swift gets ambiguous input | Low | High | `prepare` passes exactly one list; unit test asserts `--ignore` omission |
| `gen_proxy` kwarg signature drift breaks callers | Low | Med | Only caller is `Proxy#gen_proxy` (proxy.rb:47) — thread kwarg through both hops |

**Rollback**: revert the three lib files + two specs; `cache_only` key becomes an inert
unknown key (YAML merge ignores it), zero runtime effect.
