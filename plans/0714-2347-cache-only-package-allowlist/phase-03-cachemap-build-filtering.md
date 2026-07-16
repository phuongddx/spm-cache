---
phase: 3
title: "Cachemap + build filtering"
status: pending
priority: P2
dependencies: [2]
effort: "1.5h"
---

# Phase 3: Cachemap + build filtering

## Overview

Surface the new `"excluded"` status Ruby-side: add a Cachemap accessor + stats line,
and make `spm-cache build TARGETS` warn (not silently drop) when a user explicitly
requests a target that was excluded by `cache_only`. Mirrors the existing `ignored`
handling exactly.

Depends on Phase 2 — `"excluded"` must exist in `graph.json` before Ruby can read it.

## Requirements

- `Cachemap#excluded` accessor (modules where `status == "excluded"`), mirroring `hit`/
  `missed`/`ignored`.
- Include `excluded` count in `stats` and `print_stats`.
- `Build#filter_requested_targets!`: include `excluded` in `all_known` (so requesting an
  excluded target is not mislabeled "unknown"); warn
  `"'#{t}' is excluded by cache_only; skipping"` for explicit requests of excluded
  targets.

## Architecture

`Cachemap` is a pure reader over `graph.json` (cachemap.rb:1-75) — it never re-derives
status, only projects it. The new accessor is a one-line `select` mirroring `ignored`
(cachemap.rb:23-25).

`Build#filter_requested_targets!` (build.rb:47-56) already: (a) computes `all_known =
missed + hit + ignored` to detect truly-unknown names, (b) warns for
explicitly-requested `ignored` targets, (c) intersects `missed` with requested. Excluded
targets are never in `missed` (they're source fallback, never built), so the only
change is adding `excluded` to `all_known` and a parallel warn loop. No change to the
`missed.replace(missed & @requested_targets)` line (build.rb:55).

Data in: `graph.json` via `Cachemap.load`. Data out: stats line + warnings; excluded
targets remain unbuilt (correct — they're source, Xcode compiles them).

## Related Code Files

- `lib/spm_cache/cache/cachemap.rb` — `ignored` accessor (cachemap.rb:23-25), `stats`
  (cachemap.rb:31-38), `print_stats` (cachemap.rb:45-52). MODIFY.
- `lib/spm_cache/installer/build.rb` — `filter_requested_targets!` (build.rb:47-56):
  `all_known` (build.rb:48), ignored-warn loop (build.rb:52-54). MODIFY.
- `spec/installer_build_spec.rb` — graph fixture with `"ignored"` entry
  (installer_build_spec.rb:37), "warns when requested target is ignored"
  (installer_build_spec.rb:63-65). EXTEND.
- `spec/cachemap_spec.rb` — NEW (no dedicated cachemap spec exists today; see step 4).

## Implementation Steps

1. **cachemap.rb**: add accessor after `ignored` (cachemap.rb:25):
   ```ruby
   def excluded
     @graph_data.select { |e| e["status"] == "excluded" }.map { |e| e["module"] }
   end
   ```
   Add `excluded: excluded.size` to the `stats` hash (cachemap.rb:31-38). Add
   `puts "  Excluded: #{s[:excluded]}"` to `print_stats` (after the Ignored line,
   cachemap.rb:51).

2. **build.rb** `#filter_requested_targets!` (build.rb:47-56):
   - Change `all_known` (build.rb:48) to `missed + @cachemap.hit + @cachemap.ignored +
     @cachemap.excluded`.
   - Add a warn loop after the ignored loop (build.rb:52-54):
     ```ruby
     @requested_targets.select { |t| @cachemap.excluded.include?(t) }.each do |t|
       Core::UI.warn "'#{t}' is excluded by cache_only; skipping"
     end
     ```
   - Leave the `missed.replace(...)` line (build.rb:55) unchanged.

3. **installer_build_spec.rb**: extend the graph fixture (installer_build_spec.rb:37
   area) with an `{ "module" => "ExcludedLib", "status" => "excluded" }` entry. Add a
   test mirroring "warns when requested target is ignored"
   (installer_build_spec.rb:63-65): request `["ExcludedLib"]`, assert stderr matches
   `/'ExcludedLib' is excluded by cache_only; skipping/` and that it is NOT reported as
   an unknown target.

4. **spec/cachemap_spec.rb** (NEW): no dedicated Cachemap spec exists today (gap). Add a
   minimal spec covering the new `excluded` accessor + `stats[:excluded]` from a small
   in-memory `graph_data` array (no fixture file needed — `Cachemap.new(graph_data:
   [...])`). Keep it lean: assert `excluded` returns only `"excluded"`-status modules
   and `stats` includes the count. (If the team prefers not to add a new spec file,
   fold these two assertions into `installer_build_spec.rb`; a dedicated file is
   cleaner and preferred.)

## Success Criteria

- [ ] `bundle exec rspec spec/cachemap_spec.rb spec/installer_build_spec.rb` green.
- [ ] `Cachemap#excluded` returns only `"excluded"`-status modules.
- [ ] `stats[:excluded]` present; `print_stats` shows an Excluded line.
- [ ] Requesting an excluded target via `spm-cache build ExcludedLib` warns
      `'ExcludedLib' is excluded by cache_only; skipping` and does NOT warn "unknown
      target".
- [ ] `bundle exec rspec` (full) green — no regression to ignored-target handling
      (installer_build_spec.rb:63-65).

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Excluded target mislabeled "unknown" (not added to `all_known`) | Med | Low | Step 2 adds `excluded` to `all_known`; spec asserts no unknown warning |
| `stats`/`print_stats` shape change breaks viz consumers | Low | Med | `depgraph_for_viz` (cachemap.rb:54-65) reads `entry["status"]` generically — new status flows through unchanged; only additive keys in `stats` |
| No existing cachemap spec → new file friction | Low | Low | Minimal in-memory spec; fallback = fold into installer_build_spec |

**Rollback**: revert cachemap.rb + build.rb changes and delete new spec. `"excluded"`
entries in `graph.json` then fall through as unrecognized status — Cachemap ignores
them (not in hit/missed/ignored), build treats them as unknown targets if explicitly
requested. Low blast radius; roll back with Phase 2 to avoid orphan status.
