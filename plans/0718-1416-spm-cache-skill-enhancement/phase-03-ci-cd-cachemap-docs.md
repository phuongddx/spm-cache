---
phase: 3
title: "CI/CD & Cachemap Docs"
status: completed
priority: P2
dependencies: []
---

# Phase 3: CI/CD & Cachemap Docs

## Overview

Expand `references/ci-cd.md` with `cache_only`/`off` CI guidance, a scheduled
cache-maintenance example, and a Homebrew-based CI install variant (the
Homebrew CI expansion confirmed during the plan's scope challenge).

## Requirements

- Functional:
  - Document `cache_only`/`off` as CI-specific exclusion strategies (distinct
    from the local-dev `ignore` workflow already covered elsewhere).
  - Add a scheduled-maintenance workflow example: periodic `spm-cache cache
    clean --dry` (review) then `--all` (if approved) — separate from the
    per-push build workflow already in the file.
  - Add a Homebrew-based CI install step as an alternative to the existing
    `gem install spm-cache` step, since README recommends Homebrew as the
    primary install method but ci-cd.md only shows RubyGems.
- Non-functional: keep the file's existing structure (Table of Contents +
  fenced YAML workflow blocks), don't restructure what isn't being changed.

## Architecture

Current `ci-cd.md` is 48 lines: one "Full CI Workflow" YAML block (gem install
→ pull → build → use → xcodebuild → push) and a short "CI vs Local Strategy"
note. No mention of `cache_only`, `off`, `cache clean`, or Homebrew — all
confirmed gaps against the actual CLI (`lib/spm_cache/command/{off,cache/clean}.rb`,
already verified accurate in the earlier docs-sync session this plan follows).

Homebrew CI install, per README's documented method:
```bash
brew install phuongddx/spm-cache/spm-cache
```

## Related Code Files

- Modify: `skills/spm-cache/references/ci-cd.md`
- Read-only reference: `README.md` (Homebrew install section),
  `lib/spm_cache/command/off.rb`, `lib/spm_cache/command/cache/clean.rb`
  (CLI accuracy check)

## Implementation Steps

1. Add a "CI Install Options" subsection before the existing workflow YAML:
   show both `gem install spm-cache` (current) and
   `brew install phuongddx/spm-cache/spm-cache` (new) as alternatives, note
   Homebrew avoids a Ruby toolchain dependency in the CI image.
2. Add a "CI Exclusion Strategy" subsection: when to use `cache_only`
   (allowlist a small known-good set for CI) vs. `off`/`ignore` (denylist
   known-flaky packages) — cross-reference the existing SKILL.md wording so
   the two docs don't drift (same phrasing pattern already reused verbatim
   between SKILL.md and troubleshooting.md per the 2026-07-15 review).
3. Add a "Scheduled Cache Maintenance" subsection: a separate cron-triggered
   GitHub Actions workflow example running `spm-cache cache clean --dry` then
   `--all` (only after review), distinct from the per-push build/push workflow.
4. Update the Table of Contents to include the 3 new subsections.

## Success Criteria

- [x] Homebrew CI install step documented alongside the existing gem install.
- [x] `cache_only`/`off` CI guidance present, doesn't contradict SKILL.md's
      existing wording on the same config keys.
- [x] Scheduled `cache clean` example present as a distinct workflow from the
      per-push build workflow.
- [x] Table of Contents matches the final section list.

## Risk Assessment

- Low risk — purely additive, no existing YAML blocks modified.
- **Drift risk**: cache_only/off wording must match SKILL.md's phrasing
  exactly to avoid the two docs disagreeing (same failure mode a prior
  code-review flagged and fixed elsewhere in this skill). Mitigation: copy
  the exact phrasing from SKILL.md's existing `cache_only` paragraph rather
  than re-describing it independently.
