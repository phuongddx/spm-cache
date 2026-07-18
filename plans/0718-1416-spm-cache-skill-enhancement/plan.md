---
title: "Enhance skills/spm-cache: analyze phase, troubleshooting, escalation, cachemap/CI"
description: >-
  Docs-only enhancement of the end-user agent skill: replace the flat
  package-count Step 1 with a real cache-eligibility categorization + leaf-first
  priority ordering, document the v0.2.1/v0.2.2 transitive-only-package fix and
  full graph.json status vocabulary, add an escalation link to
  skills/spm-cache-issue, document cachemap visualization + richer CI/CD
  patterns (including Homebrew install), add "when not to use spm-cache"
  guidance, and tie skills/spm-cache-issue's issue classification into the new
  categories. No gem code changes.
status: completed
priority: P2
branch: "main"
tags: [skill, docs, dx, spm-cache]
blockedBy: []
blocks: []
created: "2026-07-18T07:38:44.979Z"
createdBy: "ck:plan"
source: skill
---

# Enhance skills/spm-cache: analyze phase, troubleshooting, escalation, cachemap/CI

## Overview

Real incident: a user/agent went into caching blind — didn't know which packages
were plugin-only, local, or binary-only until a build broke. Root cause:
`skills/spm-cache/SKILL.md` Step 1 only counts packages via `find`/`grep` on
`Package.resolved`, no categorization before Step 2 asks what to exclude.

Brainstormed and decided across 5 `AskUserQuestion` rounds (full trade-off
analysis in `plans/reports/brainstorm-0718-1416-spm-cache-skill-enhancement-report.md`):
- New Step 1 categorizes every package by cache-eligibility risk
  (plugin-only / binary-only / local / regular-library) using real
  `swift package describe` data against each package's DerivedData checkout —
  genuinely read-only (confirmed `spm-cache build` already rewires the
  `.xcodeproj` via `integrate_proxy_into_project`, so it can't be used as a
  "safe" pre-analysis step; a real describe-per-package pass is the only
  read-only option). Regular-library packages get a leaf-first suggested
  order (own `.dependencies` empty in `describe` output = no further SPM
  deps = safest to validate first).
- Step 3's "build, then integrate" framing gets corrected: `spm-cache build`
  already integrates (per `docs/system-architecture.md`'s pipeline), a later
  bare `spm-cache` call is redundant re-confirmation, not a required step.
- `troubleshooting.md` gets a transitive-only-conflict note and the full
  5-status `graph.json` vocabulary (`hit`/`missed`/`ignored`/`excluded`/`plugin`
  — currently only `missed` is documented), plus an escalation pointer to
  `skills/spm-cache-issue`.
- `ci-cd.md` gets `cache_only`/`off` CI guidance, a scheduled `cache clean`
  maintenance example, and a Homebrew-based CI install variant (README
  recommends Homebrew as primary install, but ci-cd.md only shows `gem install`).
- New "when not to use spm-cache" guidance section (small projects where the
  overhead isn't worth it).
- `skills/spm-cache-issue/SKILL.md`'s issue-classification table gets a
  "Transitive conflict" row. **Correction found during Step 4 testing:** the
  plan initially assumed `collect_diagnostics.sh` needed no changes, but its
  dict-branch status loop was dead code — `graph.json`'s top level is
  actually a JSON array (`ProxyGenerator.generateGraphJSON` encodes
  `[GraphEntry]` directly), so the script's real code path only printed a
  bare entry count. Fixed with a small iteration over the list branch so the
  script actually prints per-module status as the new doc text claims.

Scope challenge: HOLD then EXPANSION selected (3 files → 4 files, 3 phases →
4 phases, still 0 new abstractions — under all scope-challenge thresholds).
Explicitly rejected: fixing stale `pending` status on already-shipped plans
(`0714-2347-cache-only-package-allowlist`, `0716-2223-fix-proxy-product-metadata-identity-collision`)
— unrelated repo hygiene, not a skill enhancement, out of scope for this plan.

## Phases

| Phase | Name | Status |
|-------|------|--------|
| 1 | [Analyze Phase & SKILL.md](./phase-01-analyze-phase-skill-md.md) | Completed |
| 2 | [Troubleshooting & Escalation](./phase-02-troubleshooting-escalation.md) | Completed |
| 3 | [CI/CD & Cachemap Docs](./phase-03-ci-cd-cachemap-docs.md) | Completed |
| 4 | [spm-cache-issue Diagnostics Tie-in](./phase-04-spm-cache-issue-diagnostics-tie-in.md) | Completed |

## Dependencies

None — no cross-plan blocking relationships. Scanned all 4 unfinished plans
under `plans/` (`0713-2232-...`, `0714-1309-...`, `0714-2347-...`,
`0716-2223-...`); none touch `skills/spm-cache/` or `skills/spm-cache-issue/`.

## Success Criteria

- All 4 phases' file-level changes land with no contradiction of
  `docs/system-architecture.md` (ground truth for pipeline behavior).
- An agent following the new Step 1 on a real project produces categories
  matching what `spm-cache.lock`'s `products[]`/plugin status shows after the
  first real run (spot-check, don't just trust the pre-run guess).
- No regression to the existing 5-step workflow's >5-package batching logic —
  categorization sits before batching, doesn't replace it.

## Validation Log

### Session 1 — 2026-07-18
**Trigger:** `/ck:plan validate` after initial plan creation.
**Questions asked:** 4

#### Verification Results
- **Tier:** Standard (4 phases → Fact Checker + Contract Verifier)
- **Claims checked:** ~14 | **Verified:** 12 | **Failed→Fixed:** 2 | **Unverified:** 0

##### Fixed citations
1. [Fact Checker] `Dependency#local?` — phase-01 cited `dep.rb:15-17`, actual `dep.rb:18-20`. Fixed.
2. [Fact Checker] `ProxyGenerator.Status` enum — phase-02 cited `ProxyGenerator.swift:18`, actual declaration spans `:17-18`. Fixed.

##### Contract check
- Grepped `skills/spm-cache/` for internal `step N` cross-references: 4 found
  (SKILL.md:47,60,82,98) — all covered by Phase 1's existing "re-read for
  step-number consistency" implementation step, no plan change needed.
- Grepped repo for external references to SKILL.md's internal structure:
  `docs/*.md` + README.md mention the skill's existence only, never its
  step-by-step content — no stale-reference risk from this plan.
- Grepped `collect_diagnostics.sh` callers: only within
  `skills/spm-cache-issue/` itself — Phase 4 scope confirmed self-contained.

#### Questions & Answers

1. **[Risk]** Phase 1's ">20 packages" latency-warning threshold is new (no
   existing skill convention to derive it from). Keep 20, or align to
   something else?
   - Options: Keep >20 (Recommended) | Always show an estimate | Match >5
   - **Answer:** Keep >20
   - **Rationale:** 4x the existing >5-package batching threshold — wide
     enough gap that small/medium projects never see the warning.

2. **[Tradeoffs]** Phase 3: should Homebrew install replace `gem install` as
   the CI default, or sit alongside it as an alternative?
   - Options: Alongside, as alternative (Recommended) | Replace gem install
   - **Answer:** Alongside, as alternative
   - **Rationale:** Matches the plan as drafted; CI image constraints vary,
     let the user's runner dictate which is faster.

3. **[Scope]** Phase 4: should the plan actively create the new
   `version-conflict` GitHub label via `gh label create`, or rely on the
   existing "omit --label if missing" fallback already in the file?
   - Options: Rely on existing fallback (Recommended) | Actively create the label
   - **Answer:** Rely on existing fallback
   - **Rationale:** Zero extra repo-mutating steps in an otherwise docs-only
     workflow; existing fallback already handles this gracefully.

4. **[Architecture]** Phase 4 declares `dependencies: [1, 2]` — real blocking
   dependency or cross-reference only?
   - Options: Cross-reference only, remove dependency (Recommended) | Keep as real dependency
   - **Answer:** Cross-reference only, remove dependency
   - **Rationale:** Phase 4 only touches `skills/spm-cache-issue/SKILL.md`, a
     different file from Phases 1-3; the "Phase 1 output" mention is agent
     runtime guidance, not an implementation-order requirement. All 4 phases
     can be implemented in any order or in parallel.

#### Confirmed Decisions
- Latency threshold: >20 packages, unchanged from draft.
- Homebrew CI: documented alongside `gem install`, not replacing it.
- New GH label: no active creation step added; existing fallback suffices.
- Phase 4 dependency: changed from `[1, 2]` to `[]` in phase-04 frontmatter.

#### Action Items
- [x] Fix `dep.rb` line citation in phase-01 (18-20, was 15-17).
- [x] Fix `ProxyGenerator.swift` line citation in phase-02 (17-18, was 18).
- [x] Remove `dependencies: [1, 2]` from phase-04 frontmatter → `[]`.

#### Impact on Phases
- Phase 1: citation fix only, no scope change.
- Phase 2: citation fix only, no scope change.
- Phase 3: no change, drafted approach confirmed.
- Phase 4: `dependencies` field corrected to `[]`; no longer blocks on 1/2.

### Whole-Plan Consistency Sweep
- Files reread: `plan.md`, `phase-01-analyze-phase-skill-md.md`,
  `phase-02-troubleshooting-escalation.md`, `phase-03-ci-cd-cachemap-docs.md`,
  `phase-04-spm-cache-issue-diagnostics-tie-in.md`
- Decision deltas checked: 4 (threshold, Homebrew framing, GH label, phase-4 dependency)
- Reconciled stale references: 2 (citation line numbers, phase-04 dependency field)
- Unresolved contradictions: 0
