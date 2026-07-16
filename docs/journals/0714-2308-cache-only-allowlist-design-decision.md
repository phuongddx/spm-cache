# Design: `cache_only` allowlist configuration

**Date**: 2026-07-14 23:08  
**Severity**: Medium  
**Component**: Config system, graph status model, Ruby→Swift CLI pipeline  
**Status**: Design-only, awaiting implementation plan  

## What Happened

User requested a new feature inverting the existing `ignore` denylist: a `cache_only` allowlist in `spm-cache.yml` that specifies *only* the packages to cache, with everything else falling back to source. This eliminates hand-maintaining a growing `ignore` list as project dependencies expand. Brainstorm session concluded with a written design report at `plans/reports/brainstorm-0714-2308-cache-only-package-allowlist-report.md`.

## The Brutal Truth

The design decision that hurts: we chose a **new distinct `"excluded"` graph status** instead of reusing the existing `"ignored"` status. The user explicitly wanted this for reporting granularity—to see in stats/cachemap visualization which packages are excluded by the allowlist versus explicitly ignored. It's a sensible choice for UX transparency, but it means touching three separate Ruby modules (`Cachemap`, `Config`, `installer/build.rb`) and the Swift `ProxyGenerator` to thread a fourth status through the system. Zero blast radius was available (reuse `"ignored"`, done), and we took the heavier path. It's justified by the requirement, but it's more surface area to test and maintain.

## Technical Details

**Precedence logic (the elegant part):** When both `ignore` and `cache_only` are defined, `cache_only` wins *outright* — `ignore` is skipped entirely, not combined. This is enforced at the Ruby → Swift boundary: `Proxy#prepare` decides which single CLI flag to send (`--cache-only` or `--ignore`, never both). Swift never sees two competing filters; it only processes one list per run. This keeps `ProxyGenerator` free from filter reconciliation logic.

**The pipeline mirrors existing `ignore` behavior:**
- Ruby: `Config#cache_only_list` reader, CSV-joined in `proxy_executable.rb` (exact clone of `--ignore` logic)
- Swift: `GenProxy` parses `--cache-only`, `ProxyGenerator` forces status `"excluded"` for non-matching packages
- Graph: four-state model (`hit`/`missed`/`ignored`/`excluded`) in `graph.json`

## What We Tried

One alternative (rejected): combine both filters as `only ∩ !ignore` — users could exclude from the allowlist with `ignore`. This was leaner but pointless: once `cache_only` wins outright, there's no use case for `ignore` modifying it. Rejected cleanly.

## Root Cause Analysis

Why design this way at all? Scout work revealed the existing `ignore` enforcement is *not* in Ruby — `Config#should_ignore?` is barely used (only by `spm-cache off` and specs). The real glob-matching is in Swift, fed via CLI flag from Ruby. Sinking a second filter path in Ruby would fork the system and create two sources of truth. Plugging into the existing `--ignore` → Swift pipeline was the only sensible approach.

Why `"excluded"` instead of reusing `"ignored"`? User requirement. They want to report separately on packages excluded by the allowlist versus explicitly ignored. Zero debate once the requirement was stated.

## Lessons Learned

**Schema visibility matters.** The `graph.json` four-state model is the single source of truth in this codebase — Ruby's `Cachemap` only reads it, never re-derives it. Future features that branch on package eligibility should anchor to this model early and design the graph mutation path first, not last.

**Precedence at the boundary, not at the logic.** Enforcing `cache_only` wins by omitting the `--ignore` flag entirely (not by having Swift decide which filter to apply) keeps complexity localized and prevents two systems from conflicting.

## Next Steps

1. **Create implementation plan** — break into phases (Ruby config/CLI, Swift flag parsing, graph status threading, tests, docs).
2. **No code yet.** Design report is the gate; user hasn't requested `/ck:plan` handoff. Waiting for signal to proceed.
3. **Optional: 0%-match guard-rail.** If `cache_only` patterns match zero packages, log a warning (same soft-fail as a typo in `ignore` today, but worth flagging). Noted in report as low-priority follow-up.

**Owner**: Not assigned yet — plan phase will clarify.

---

**Design report:** `/Users/ddphuong/Projects/next-labs/spm-cache/plans/reports/brainstorm-0714-2308-cache-only-package-allowlist-report.md`
