---
title: spm-cache skill enhancement (analyze phase, troubleshooting, escalation, cachemap/CI)
date: 2026-07-18 14:16
status: approved
type: brainstorm
---

# spm-cache Skill Enhancement

## Problem Statement

`skills/spm-cache/` (the end-user agent skill, 5 files / ~486 lines) is documentation-only —
no code changes to the gem. Real incident: a user/agent went into caching blind — didn't know
which packages were plugin-only, local, or binary-only until a build broke. Root cause: SKILL.md's
Step 1 ("Analyze project dependencies") only counts packages via `find`/`grep` on
`Package.resolved` — no categorization at all before the user is asked what to exclude.

Three more gaps found while scouting (session started right after syncing `docs/` for v0.2.2):
troubleshooting.md doesn't mention the just-shipped v0.2.1/v0.2.2 transitive-only-package fix or
the full `graph.json` status vocabulary; no escalation pointer to `skills/spm-cache-issue`; and
cachemap visualization + richer CI/CD patterns are undocumented in the skill.

## Requirements

- **Expected output**: edits to `SKILL.md` + `references/troubleshooting.md` +
  `references/ci-cd.md` (no code, no new files unless a reference doc split is warranted).
- **Acceptance criteria**: Step 1 categorizes every resolved package by cache-eligibility risk and
  orders regular-library candidates leaf-first before Step 2 asks about exclusions;
  troubleshooting.md explains all 5 graph.json statuses + the transitive-only auto-fix +
  escalation to `skills/spm-cache-issue`; ci-cd.md covers `cache_only`/`off`/scheduled `cache clean`.
- **Scope boundary**: docs-only, this skill only (not `skills/spm-cache-issue` itself, not gem code).
- **Constraints**: no new subprocess tooling beyond what the gem's own `CheckoutResolver`/`Description`
  models already do (reuse existing DerivedData-checkout + `swift package describe` patterns, don't
  invent new ones); flag added latency honestly, don't hide it.
- **Touchpoints**: `SKILL.md` (Step 1 + Architecture section), `references/troubleshooting.md`,
  `references/ci-cd.md`.

## Key Finding (changes design)

`spm-cache build` is **not** read-only — `docs/system-architecture.md`'s own pipeline confirms
`Command::Build` runs the identical `integrate_proxy_into_project` step as `Command::Use` (rewires
`.xcodeproj` package refs, saves the project), then builds missed targets on top. SKILL.md currently
implies `build` and bare `spm-cache` (`use`) are cleanly separable steps ("build, then integrate") —
inaccurate; `build` already integrates, a later `spm-cache` call is redundant re-confirmation, not a
required distinct step. Reversible via `rollback`, but not inert.

This rules out "run `spm-cache build --recursive` first to get real categorization cheaply" as a
safe pre-analysis step for the new Step 1 — it already touches the project.

## Evaluated Approaches — Analyze/Categorize Phase

**A. Per-package `swift package describe` (chosen)** — locate each package's checkout under
`~/Library/Developer/Xcode/DerivedData/<Project>-*/SourcePackages/checkouts/<slug>` (same path
`CheckoutResolver#fallback_xcode_checkouts` already uses), run `swift package describe --type json`
there, classify from real fields:

| Category | Signal | Meaning |
|---|---|---|
| Plugin-only | products present, none `type: library` | never cacheable, don't ask about these |
| Binary-only / metadata-thin | `describe` returns no products at all | cacheable, higher risk (the exact gap the Ruby regex-fallback exists for) |
| Local | `path` in `Package.resolved` | candidate for `ignore_local` |
| Regular library | everything else | real caching candidates |

Leaf-first priority within "regular library": a package whose own `.dependencies` (same `describe`
call) is empty has no further SPM deps → cache/verify first, can't hit a transitive conflict.
- Pro: genuinely read-only, matches chosen category basis + priority exactly, mirrors a pattern the
  tool already trusts internally.
- Con: real latency — one subprocess per package, a few seconds each (~1-3min for a 59-package
  project, the real field project from the v0.2.2 commit).

**B. Cheap-first, refine-later (rejected)** — categorize only `Package.resolved`'s free fields
(local vs. remote) upfront, ask exclusions on that thin basis, surface full categories after the
first (project-touching) build.
- Pro: instant.
- Con: reintroduces the exact "unclear risk before caching" pain point that triggered this session —
  plugin-only/binary-only risk stays invisible until the project's already been rewired.

**Decision: A.** User explicitly wants analysis *before* anything runs; only A satisfies that. Add
an explicit latency warning to the skill text for >20 packages, mirroring the existing ">5 packages
→ batch" pattern's spirit.

## Final Recommended Solution

### 1. SKILL.md — rewrite Step 1 into "Analyze & categorize project dependencies"

- Keep the `Package.resolved` discovery, but for each identity: locate its DerivedData checkout,
  run `swift package describe --type json`, classify into the 4-category table above.
- If package count > 20, tell the user upfront: "analyzing N packages, this takes ~1-3 minutes."
- Present a summary table to the user: category, count, and (for regular-library packages) a
  leaf-first suggested order — pros/cons per category inline (plugin/local = "don't bother asking,
  auto-excluded/candidate for ignore_local"; binary-only = "cacheable but verify after"; regular
  library, leaf-first = "safest to validate the pipeline on first").
- Step 2 (exclusion question) now asks against this categorized list instead of a flat name dump.
- Correct Step 3's "build, then integrate" framing: note that `spm-cache build` already integrates
  the proxy into the project (per the Key Finding above); a later bare `spm-cache` call re-confirms
  but isn't a required separate step.

### 2. references/troubleshooting.md

- New subsection: "Version conflicts on transitive-only packages" — explains the v0.2.1/v0.2.2 fix
  (e.g. realm-core/realm-swift double-pinning), how to recognize it's the known-and-fixed case vs.
  a new unresolved conflict.
- Expand "Cache not hitting" section's `graph.json` guidance to cover all 5 statuses
  (`hit`/`missed`/`ignored`/`excluded`/`plugin`), not just `missed`.
- New final section: "Still stuck?" pointing to `skills/spm-cache-issue` for diagnosed issue filing.

### 3. references/ci-cd.md

- Add `cache_only`/`off` usage note for CI-specific exclusion strategy.
- Add a scheduled-maintenance example: periodic `spm-cache cache clean --dry` (then `--all` if
  approved) job, separate from the per-push build workflow already documented.

### 4. SKILL.md — Architecture section

- Document `spm-cache/cachemap/index.html` (generated every run) and how to open it
  (`open spm-cache/cachemap/index.html`) — currently invisible to the skill despite being generated
  every single run per `system-architecture.md`.

## Implementation Considerations & Risks

- The per-package `describe` loop needs a fallback instruction for when DerivedData checkouts aren't
  found (mirror the existing prerequisite: "open the project in Xcode once to resolve dependencies
  first" already covers the checkout-existence precondition).
- Categorization is best-effort guidance for the agent, not a hard gate — if `describe` fails for a
  package (e.g. malformed local package), fall back to "uncategorized, treat as regular library."
- Transitive-only detection (the 5th real category from the Swift/Ruby side) is intentionally NOT
  replicated in the skill — computing it pre-run requires parsing the host `.xcodeproj`'s product
  dependencies (same as `refresh_consumed_dependencies`), which means fragile textual parsing of a
  pbxproj for no real benefit: spm-cache already auto-handles this case since v0.2.1/v0.2.2. State
  that directly instead of re-deriving it.

## Success Metrics / Validation Criteria

- An agent following the new Step 1 on a real multi-package project produces a category table
  matching what `spm-cache.lock`'s `products[]`/plugin status shows after the first real run (cross-
  check, don't just trust the pre-run guess).
- troubleshooting.md's new sections don't contradict `docs/system-architecture.md` (ground truth).
- No regression to the existing 5-step workflow's batching logic (>5 packages) — the new
  categorization sits *before* batching, doesn't replace it.

## Next Steps

Hand off to `/ck:plan` (default mode — this is a moderate, well-scoped doc change, not a refactor
of critical logic needing `--tdd`). Suggested phases: (1) SKILL.md Step 1 rewrite + Step 3 wording
fix, (2) troubleshooting.md additions, (3) ci-cd.md additions + Architecture/cachemap note.

## Unresolved Questions

None — all decisions confirmed via AskUserQuestion during this session.
