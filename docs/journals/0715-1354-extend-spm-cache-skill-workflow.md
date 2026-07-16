# Extend spm-cache skill: ask user about package exclusions before integration

**Date**: 2026-07-15 13:54  
**Severity**: Medium  
**Component**: skills/spm-cache (end-user agent)  
**Status**: Resolved  

## What Happened

User requested extending the `skills/spm-cache` end-user agent skill to ask "what packages should not be cached?" before running the integration step, mapping to the existing `ignore` config key. Scope expanded mid-session via two AskUserQuestion rounds into a 5-step workflow: (1) analyze project dependencies (discover packages), (2) ask user about exclusions, (3) build and integrate in batches (>5 packages), (4) verify cache status, (5) rollback. Rewrote the Core Workflow section of `SKILL.md` and synced a cross-reference note into `troubleshooting.md`. Committed as `57f2c47`, docs-only.

## The Brutal Truth

The humbling discovery: the actual Ruby installer (`lib/spm_cache/installer.rb:82`) already discovers packages via glob for `Package.resolved`. The new "analyze project dependencies" step just asks the agent to replicate that same discovery manually (`find` + `cat`) in the skill markdown *before* the tool ever runs. It's not redundant—it's pedagogical. The agent tells the user what it found, *then* asks which to exclude, *then* runs spm-cache to validate. Feels like friction, but it's actually UX: users know what's being touched before build begins.

The painful part: the review pass caught that the draft told the agent to "create spm-cache.yml from the template if it doesn't exist," but the gem's packaged template is unreachable from a user's project directory and is itself missing the `cache_only` key (drift risk). This is a gap in how `spm-cache` onboards—no good way for an external agent to bootstrap the config cleanly. Fixed by deleting that instruction and saying "write the `ignore` key directly; `spm-cache` merges any partial YAML with defaults" (verified against `Config#load`'s `DEFAULT_CONFIG.merge(...)` behavior). Simpler and always correct.

## Technical Details

**Workflow structure (five steps):**

1. **Analyze project dependencies** — Agent runs `find . -name Package.resolved` and parses package names
2. **Ask which packages should not be cached** — Agent prompts user, writes `ignore` key to `spm-cache.yml`
3. **Build and integrate** — Conditional: if ≤5 packages, one-shot `spm-cache on --recursive`; if >5, batches of 5 max, build→integrate→verify after *each* batch (not just at the end)
4. **Verify cache status** — Renamed from step 3; agent checks `spm-cache status`
5. **Rollback** — Renamed from step 4; instructions for `spm-cache off`

**Batching decision logic:**

- Batching kicks in only when package count exceeds 5
- Each batch flows through build→integrate→verify before the next batch starts (incremental validation, not deferred)
- Prevents resource exhaustion and gives user confidence with early feedback

**Config merge behavior:**

- `Config#load` in Ruby does `DEFAULT_CONFIG.merge(user_provided_yaml)`, so partial YAML works
- Agent writes only the `ignore` key; no need to know the full schema or fetch a template file

## What We Tried

**Rejected scope (1):** Make this an interactive CLI prompt in the Ruby gem itself. Scoped as out-of-bounds—the skill is documentation-driven, not runtime-interactive. The Ruby tool stays focused on build and cache integration, not onboarding.

**Rejected scope (2):** Ask about `cache_only` (the allowlist from the earlier design session today). User explicitly wanted the exclusion workflow, not inclusion. Two different mental models; sticking with `ignore`.

**Expanded scope (accepted):** Add a discovery step *before* the exclusion question. Prevents blind guessing and builds confidence. User convinced during second AskUserQuestion round; added to the workflow.

**Expanded scope (accepted):** Batching for large projects. User added proactively: "if many packages, don't do one giant `--recursive` build." Makes sense for safety and user feedback. Scoped carefully: only when >5 packages, integrate after each batch to catch errors incrementally.

## Root Cause Analysis

Why add a discovery step if the tool already does it? Because the agent is the user's interface. Users need to *see* what's being discovered and *decide* what to exclude before the tool runs. The discovery happens twice—once by the agent (for the user), once by spm-cache (for validation). It's redundant in code, but not in user intent.

Why batching? Large SPM projects can timeout or exhaust resources on a single `--recursive` build. Batching is a load-distribution pattern, but the user-facing win is checkpoints: verify each batch works before the next begins. Prevents a user from running 10 hours of builds, hitting a crash on package #47, and losing all confidence in the tool.

## Lessons Learned

**Skills can extend tool workflows without modifying the tool.** The Ruby installer already had all the package discovery logic. The agent skill just *orchestrated* it with user questions and feedback. Zero code changes needed.

**Boundary validation is key.** The config merge behavior (`DEFAULT_CONFIG.merge(...)`) meant we could avoid the template-file gap entirely. Knowing the tool's contract let us route around an onboarding friction point.

**Batching is about UX, not just performance.** 5-package threshold isn't arbitrary—it's a heuristic for "fit in one human-checkable cycle." Below that, one build is fine. Above that, break it up so users see progress and catch errors early.

## Next Steps

1. **Committed.** Workflow is final; no pending implementation. `57f2c47` closes this session.
2. **Skill is documented.** Future agents using `skills/spm-cache` will follow this five-step pattern.
3. **Config behavior note filed.** If the `cache_only` implementation hits config-template issues, refer to this session's discovery: partial YAML + defaults merge beats template-file gymnastics.

**Owner**: Session complete. Skill docs are stable. Next work is user-facing: end-user agents will follow this workflow.

---

**Related design doc**: `/Users/ddphuong/Projects/next-labs/spm-cache/plans/reports/brainstorm-0714-2308-cache-only-package-allowlist-report.md` (today's earlier allowlist session; this session uses `ignore`, not `cache_only`)
