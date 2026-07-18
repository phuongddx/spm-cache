---
phase: 1
title: "Analyze Phase & SKILL.md"
status: completed
priority: P1
dependencies: []
---

# Phase 1: Analyze Phase & SKILL.md

## Overview

Rewrite `skills/spm-cache/SKILL.md` Step 1 from a flat package count into a
real cache-eligibility categorization + leaf-first priority ordering. Correct
Step 3's "build, then integrate" framing. Document the cachemap visualization
in the Architecture section. Add a new "When not to use spm-cache" guidance
section.

## Requirements

- Functional:
  - Step 1 must categorize every package from `Package.resolved` into one of:
    plugin-only, binary-only/metadata-thin, local, regular-library.
  - Regular-library packages get a leaf-first suggested order.
  - Step 2's exclusion question must reference the categorized list, not a
    flat name dump.
  - Step 3 must state plainly that `spm-cache build` already integrates the
    proxy into the project; a later bare `spm-cache` call re-confirms but
    isn't a required separate step.
  - New section: guidance on when spm-cache isn't worth adopting (e.g. very
    few SPM deps, clean-build time not a real pain point).
- Non-functional:
  - No new subprocess tooling beyond `swift package describe --type json`
    against each package's own checkout dir — reuse the exact technique
    `SPM::CheckoutResolver#fallback_xcode_checkouts` already uses internally,
    don't invent a new one.
  - Latency must be flagged honestly to the user for >20 packages (mirror the
    existing ">5 packages → batch" pattern's spirit), not hidden.
  - This step must be genuinely read-only: it must NOT invoke any `spm-cache`
    command (build/use both rewire the `.xcodeproj` per Phase 1's own
    research finding below) or write any file.

## Architecture

**Why not just run `spm-cache build --recursive` first for cheap categorization?**
Verified in `docs/system-architecture.md`'s `spm-cache build [TARGETS]` pipeline
diagram: step 3 is literally "Same as use + build_missed!" — `Installer::Build`
inherits the base `Installer#perform_install`, which unconditionally calls
`integrate_proxy_into_project` (rewires `.xcodeproj` package refs, calls
`project.save`) for every flow, not just `use`. So `build` is not read-only;
it can't be used as a "look before you leap" step. This is why the analyze
phase needs its own external `swift package describe` pass instead.

**Categorization algorithm** (per package identity in `Package.resolved`):

1. Locate the package's checkout directory. Prefer the project's own SPM
   checkout location if one already exists; otherwise fall back to the newest
   Xcode DerivedData checkout — same location and same "pick newest by mtime"
   logic as `SPM::CheckoutResolver#fallback_xcode_checkouts`
   (`lib/spm_cache/spm/checkout_resolver.rb:44-62`):
   ```bash
   ls -d ~/Library/Developer/Xcode/DerivedData/<ProjectName>-*/SourcePackages/checkouts/<slug> \
     2>/dev/null | xargs -I{} stat -f "%m %N" {} | sort -rn | head -1 | cut -d' ' -f2-
   ```
   (`<ProjectName>` = the `.xcodeproj` basename without extension; `<slug>` =
   repo basename without `.git`, matching `Dependency#slug` in
   `lib/spm_cache/spm/desc/dep.rb:34-41`.)
2. If no checkout is found for a package: mark it "unresolved — run the
   project in Xcode once to resolve dependencies" (this is already a stated
   prerequisite in SKILL.md's Step 1) and skip categorization for it, don't
   block the rest.
3. `cd` into the checkout dir, run `swift package describe --type json`.
4. Classify from the JSON:
   - No `products` array at all, or empty → **binary-only / metadata-thin**
     (the exact gap `Description`/`Product` (`lib/spm_cache/spm/desc/product.rb`)
     and the Ruby-side regex fallback exist for — cacheable but verify after).
   - `products` present, none with `"type": "library"` (or `type` is a hash
     whose only key isn't `library`, per `Product#type`'s
     `t.is_a?(Hash) ? t.keys.first : t`) → **plugin-only** (never cacheable).
   - Otherwise → **regular library**. Also record `.dependencies.length` from
     the same JSON: `0` → leaf (no further SPM deps, safest to cache first).
   - Separately, if the resolved dependency in `Package.resolved` carries a
     `path` (local package, per `Dependency#local?` in `dep.rb:18-20`) →
     **local** (overrides the above — surface as "local, consider
     `ignore_local`" regardless of its product shape).
5. Do NOT attempt to detect "transitive-only" pre-run (would require parsing
   the host `.xcodeproj`'s product dependencies, same as
   `refresh_consumed_dependencies` in `lib/spm_cache/installer.rb` — fragile
   pbxproj text-parsing for a case `spm-cache` v0.2.1+ already auto-handles).
   State directly in the skill text that this category is auto-handled by the
   tool, no user action needed.

**Priority order**: within "regular library", leaf packages (dependencies
count 0) first, then the rest, matching the user's chosen "dependency-graph
position" priority logic from the brainstorm.

## Related Code Files

- Modify: `skills/spm-cache/SKILL.md` (Step 1 rewrite, Step 2 rewording, Step 3
  wording fix, new "When not to use" section, Architecture section cachemap note)
- Read-only reference (ground truth, do not modify):
  - `docs/system-architecture.md` (`spm-cache build [TARGETS]` pipeline —
    confirms build integrates)
  - `lib/spm_cache/spm/checkout_resolver.rb` (DerivedData fallback path pattern)
  - `lib/spm_cache/spm/desc/product.rb`, `lib/spm_cache/spm/desc/dep.rb`
    (categorization field semantics: `type`, `local?`)
  - `tools/spm-cache-proxy/Sources/Core/Lockfile.swift` (`isPluginOnly`,
    `isTransitiveOnly` — confirms why transitive-only is out of scope here)

## Implementation Steps

1. Draft the new Step 1 text: package discovery (unchanged) → per-package
   checkout lookup + `swift package describe` → categorize into the 4 buckets
   → present a summary table (category, count, leaf-first order for
   regular-library) with one-line pros/cons per category inline.
2. Add the >20-package latency warning before the categorization loop starts.
3. Reword Step 2 to reference the categorized list ("ask about exclusions
   only for regular-library packages; plugin-only/transitive-only need no
   question; local packages get an `ignore_local` suggestion instead").
4. Fix Step 3: replace "build, then integrate" framing with the corrected
   explanation (build already integrates; second `spm-cache` call is
   redundant re-confirmation).
5. Add "When not to use spm-cache" section: few SPM deps (e.g. <3), clean-build
   time not a real pain point, or a project that never does clean builds.
6. Add a short cachemap note to the existing "Architecture" section:
   `spm-cache/cachemap/index.html` is generated every run; open with
   `open spm-cache/cachemap/index.html`.
7. Re-read the full SKILL.md end to end for step-number consistency (no stale
   "step N" cross-references elsewhere in the file — same check the prior
   code-review pass already did for the 2026-07-15 rewrite).

## Success Criteria

- [x] Step 1 categorizes every discovered package into exactly one of the 4
      buckets, with leaf-first ordering shown for regular-library packages.
- [x] Step 1 states the >20-package latency cost explicitly when it applies.
- [x] Step 2's exclusion question references categories, not a flat list.
- [x] Step 3 no longer implies `build` and `use` are separable
      integration-wise; states plainly that `build` already integrates.
- [x] New "When not to use" section exists with concrete, non-vague criteria.
- [x] Architecture section documents the cachemap HTML path and how to open it.
- [x] No stale numeric step cross-references anywhere in the file after the edit.

## Risk Assessment

- **Latency risk**: N `swift package describe` calls for large projects
  (~1-3 min for the 59-package field project from the v0.2.2 commit).
  Mitigation: explicit upfront warning, doesn't block — same trade-off
  accepted during the brainstorm's Approach A vs B debate.
- **Missing checkout risk**: a package with no resolvable checkout (fresh
  clone, Xcode never opened) breaks the categorization loop. Mitigation:
  per-package skip with "unresolved" status, point back to the existing
  prerequisite instruction, don't fail the whole step.
- **Drift risk**: if the Ruby/Swift `isPluginOnly`/`Product#type` logic changes
  later, this skill's categorization heuristic could silently diverge.
  Mitigation: Success Criteria's cross-check against `spm-cache.lock`'s real
  `products[]` after the first run catches this in practice; no code-level
  guard possible since this is markdown-only guidance.
