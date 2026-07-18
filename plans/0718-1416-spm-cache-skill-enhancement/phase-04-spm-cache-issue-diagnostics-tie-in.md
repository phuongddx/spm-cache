---
phase: 4
title: "spm-cache-issue Diagnostics Tie-in"
status: completed
priority: P3
dependencies: []
---

# Phase 4: spm-cache-issue Diagnostics Tie-in

## Overview

Complete the two-way escalation link from Phase 2: add a "Transitive
conflict" row to `skills/spm-cache-issue/SKILL.md`'s issue-classification
table, and note that Phase 1's pre-run categorization output (when available)
can enrich a filed issue's body.

**Correction from initial plan (found during Step 4 testing):** the plan
originally assumed `collect_diagnostics.sh` needed no changes because its
`isinstance(g, dict)` branch iterates and prints every status. That branch
is dead code — `ProxyGenerator.generateGraphJSON` encodes `graph.json` as a
top-level JSON **array** (`tools/spm-cache-proxy/Sources/Core/Generator/ProxyGenerator.swift:179-186`),
so the script actually hit the `isinstance(g, list)` branch, which only
printed a bare count (`graph: N entries`), not per-module statuses. Fixed by
adding a ~10-line iteration over the list branch to print `module: status`
per entry (dict branch kept as a harmless legacy fallback). This makes the
skill's new diagnostics claim actually true.

## Requirements

- Functional:
  - Add "Transitive conflict" as a new row in the Issue Type classification
    table (Step 3 of `skills/spm-cache-issue/SKILL.md`), with an appropriate
    label (e.g. `bug`, `version-conflict`) and description.
  - Note in Step 2 ("Collect Diagnostics") that if the agent already ran
    Phase 1's categorization for this project earlier in the session, that
    output is worth pasting into the issue body alongside the script's output
    — don't re-run the categorization loop just for the issue filing.
- Non-functional: `collect_diagnostics.sh` fix must be minimal (fix the dead
  branch only, don't restructure the script) and must not change its CLI
  usage (`collect_diagnostics.sh [project_dir]`) or output format for callers.
- Scope boundary: this phase does NOT touch `skills/spm-cache/` files (those
  are Phases 1-3); it only touches `skills/spm-cache-issue/`.

## Architecture

`ProxyGenerator.generateGraphJSON` (`tools/spm-cache-proxy/Sources/Core/Generator/ProxyGenerator.swift:179-186`)
encodes `[GraphEntry]` directly — `graph.json`'s top level is a JSON
**array** of `{module, status, dependencies, hasMacro}` objects, never a
dict. `collect_diagnostics.sh`'s "Sandbox" section originally branched on
`isinstance(g, dict)` (iterate + print status — dead code, never hit in
practice) vs. `isinstance(g, list)` (bare `len(g)` count — the actual path
every real run takes). Fixed: the list branch now iterates each entry and
prints `module: status`; the dict branch is kept as a harmless legacy
fallback in case the schema ever changes back. This is the gap `SKILL.md`'s
classification table also had — no row for a transitive-only version
conflict (now auto-fixed in v0.2.1/v0.2.2, but still worth a label if a
genuinely new conflict of that shape ever gets filed).

## Related Code Files

- Modify: `skills/spm-cache-issue/SKILL.md`,
  `skills/spm-cache-issue/scripts/collect_diagnostics.sh`
- Read-only reference: `tools/spm-cache-proxy/Sources/Core/Generator/ProxyGenerator.swift`
  (`GraphEntry`, `generateGraphJSON`)
- Cross-reference: Phase 2's new troubleshooting.md "Still stuck?" section
  (this phase is its landing target), Phase 1's categorization output format

## Implementation Steps

1. Add "Transitive conflict" row to the Step 3 classification table:
   Labels `bug`, `version-conflict` (new label — check if it exists on the
   repo first per the existing "if labels don't exist, omit --label" rule
   already in the file); Description: "swift package resolve fails with
   conflicting version requirements on a package never linked directly by
   the app (e.g. realm-core via realm-swift)".
2. In Step 2 ("Collect Diagnostics"), add one sentence: if Phase 1's
   categorization was already run earlier in the same session for this
   project, include that category summary in the issue body — don't
   re-derive it.
3. Fix `collect_diagnostics.sh`'s list branch to iterate `g` and print
   `module: status` per entry instead of a bare count; keep the dict branch
   as a fallback. Verify with a dry-run against a synthetic JSON array.

## Success Criteria

- [x] "Transitive conflict" row added to the classification table with a
      label and description.
- [x] Step 2 references reusing Phase 1's categorization output when available.
- [x] `collect_diagnostics.sh`'s list branch now prints per-module status
      (verified via `bash -n` syntax check + a synthetic-array dry run).
- [x] No duplication of Phase 2's troubleshooting content — this phase only
      adds the issue-filing-side classification, not another explanation of
      the transitive-only fix itself (that lives in troubleshooting.md).

## Risk Assessment

- **Label drift risk**: `version-conflict` may not exist as a GitHub label on
  the repo yet. Mitigation: the file's existing rule ("if labels don't exist,
  omit --label and mention in body") already covers this, no new handling needed.
- **Script fix risk**: low — the fix only changes the list branch's print
  behavior (count → per-entry detail), doesn't change the script's exit
  code, CLI usage, or any other branch. Verified with a syntax check and a
  synthetic dry-run before considering this done.
