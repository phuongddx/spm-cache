---
phase: 2
title: "Troubleshooting & Escalation"
status: completed
priority: P1
dependencies: []
---

# Phase 2: Troubleshooting & Escalation

## Overview

Add a transitive-only-package-conflict note and the full `graph.json` status
vocabulary to `references/troubleshooting.md`, plus a final escalation section
pointing to `skills/spm-cache-issue` when nothing else resolves the problem.

## Requirements

- Functional:
  - New subsection explaining the v0.2.1/v0.2.2 transitive-only-package fix
    (realm-core/realm-swift-style double-pinning) and how to tell the
    known-fixed case apart from a genuinely new conflict.
  - "Cache not hitting" section's `graph.json` guidance must cover all 5
    statuses (`hit`/`missed`/`ignored`/`excluded`/`plugin`), not just `missed`.
  - New final "Still stuck?" section pointing to `skills/spm-cache-issue`.
- Non-functional: must not contradict `docs/system-architecture.md` (ground
  truth for pipeline/status behavior).

## Architecture

`graph.json` status enum, confirmed at
`tools/spm-cache-proxy/Sources/Core/Generator/ProxyGenerator.swift:17-18`:
`enum Status: String, Codable { case hit, missed, ignored, excluded, plugin }`.
Current troubleshooting.md's "Cache not hitting" section (`grep -A2 missed`)
only surfaces `missed` — a user grepping for their package and seeing
`ignored`/`excluded`/`plugin` instead would get no context on what that means
or whether it's expected.

Transitive-only fix: `docs/system-architecture.md`'s `GenUmbrella`/`GenProxy`
component descriptions (already accurate, updated in the 2026-07-18 docs sync)
describe `PackageRef.isTransitiveOnly(consumedProducts:)` skipping a package
whose products never appear in any target's directly-linked dependencies —
this is what auto-resolves version conflicts like realm-core (pulled in only
via realm-swift) being independently pinned at a conflicting version.

## Related Code Files

- Modify: `skills/spm-cache/references/troubleshooting.md`
- Read-only reference: `docs/system-architecture.md` (Component Architecture
  section — `GenUmbrella`/`GenProxy`/`isTransitiveOnly`),
  `tools/spm-cache-proxy/Sources/Core/Generator/ProxyGenerator.swift`
  (`enum Status`), `skills/spm-cache-issue/SKILL.md` (escalation target)

## Implementation Steps

1. Add "Version conflicts on transitive-only packages" subsection after the
   existing "Cache not hitting" section: describe the symptom (e.g. `swift
   package resolve` fails with conflicting version requirements on a package
   like realm-core that the app never links directly), state it's
   auto-resolved since v0.2.1 (umbrella) / v0.2.2 (real proxy graph), and give
   one diagnostic: if the conflict persists after upgrading to >= v0.2.2, it's
   a new/different conflict, not this one — escalate (points to step 3 below).
2. Expand the "Cache not hitting" section: add a table of all 5 statuses with
   one-line meaning each (`hit` = using cached binary, `missed` = needs
   `spm-cache build`, `ignored` = in `ignore` list/`spm-cache off`, `excluded`
   = not in `cache_only` allowlist, `plugin` = build-tool plugin, never
   cacheable).
3. Add final "Still stuck?" section: if none of the above resolves it, use
   `skills/spm-cache-issue` to file a diagnosed GitHub issue (name the skill
   explicitly so an agent recognizes the trigger).
4. Update the Table of Contents at the top of the file to include the two new
   sections.

## Success Criteria

- [x] Transitive-only-conflict subsection exists, cites the correct version
      (v0.2.1 umbrella-only, v0.2.2 extended to real proxy graph).
- [x] All 5 `graph.json` statuses documented with correct one-line meanings.
- [x] "Still stuck?" section references `skills/spm-cache-issue` by name.
- [x] Table of Contents updated to match the new section list.
- [x] No claim contradicts `docs/system-architecture.md`.

## Risk Assessment

- **Version-number drift**: if a future release changes transitive-only
  behavior again, this note could go stale. Mitigation: cite the mechanism
  (`isTransitiveOnly`) not just the version number, so the note stays
  meaningful even if a later version changes the exact fix commit.
- **Low risk overall** — purely additive documentation, no existing content
  removed or reworded except the ToC.
