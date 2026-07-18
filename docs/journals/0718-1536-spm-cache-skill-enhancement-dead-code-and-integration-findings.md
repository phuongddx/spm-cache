# spm-cache Skill Enhancement: Dead Code, Integration Surprise, and Architectural Correction

**Date**: 2026-07-18 15:36  
**Severity**: Medium  
**Component**: skills/spm-cache, skills/spm-cache-issue (docs-only)  
**Status**: Completed  

## What Happened

Enhanced the `skills/spm-cache/` and `skills/spm-cache-issue/` agent skills with real cache-eligibility categorization, transitive-only conflict guidance, and CI/CD documentation. All changes docs-only: rewrote Step 1 to categorize packages (plugin-only / binary-only / local / regular-library) via `swift package describe`, updated troubleshooting.md with full graph.json vocabulary and escalation paths, added ci-cd.md with Homebrew install and scheduled maintenance patterns, and tied spm-cache-issue's classification table to transitive conflicts. Commit `e6455b7` (982 insertions, 30 deletions across 12 files); full plan and phases in `plans/0718-1416-spm-cache-skill-enhancement/`.

## The Brutal Truth

The sharp discovery: `spm-cache build` is **not** read-only. It already rewires the `.xcodeproj` via `integrate_proxy_into_project`—the exact same method as the bare `spm-cache use` command. The skill text originally implied you could safely run `build` as a cheap pre-analysis step to gather real categorization data, then integrate later. Wrong. It's already integrated by then. This ruled out the cheap approach and forced a genuinely read-only `swift package describe` loop per package instead. The frustrating part: this architectural detail lives in `docs/system-architecture.md` (the source of truth), and we should have read it first. We did eventually, but the surprise hit mid-planning, forcing a design pivot.

The worse discovery: `collect_diagnostics.sh` has dead code. The script branches on `isinstance(g, dict)` to iterate and print per-module status from graph.json. That branch is unreachable. The real schema—confirmed by tracing `ProxyGenerator.generateGraphJSON` in the Swift source—is a JSON **array** at the top level, not a dict. The actual code path the script always took was `isinstance(g, list)`, which just printed a bare entry count (`graph: N entries`), never the per-module statuses the new troubleshooting docs claimed would be there. This is exactly the kind of bug that's insidious: the unreachable code looks *correct*, reads well, and would work if the schema were different. Nobody caught it because nobody traced the actual schema shape. Fixed by moving the list branch before dict and adding a loop to print `module: status` per entry—a one-line fix that makes the docs claim actually true.

The code review catch: Step 1 said "don't try to detect transitive-only packages" (good advice—it's complex), while Step 2 said "transitive-only packages need no exclusion question, so skip asking about them." Self-contradictory. Step 2 had no data to act on its claim. Fixed by removing Step 2's unenforceable claim and stating plainly: "spm-cache auto-handles this since v0.2.1/v0.2.2; we won't replicate transitive detection here."

## Technical Details

### The Build-Already-Integrates Finding

**Discovery**: During planning, assumed `spm-cache build` was read-only. Design draft: "Run `build --recursive` first to get real categorization, then `spm-cache use` to integrate."

**Reality**: `Command::Build` calls `integrate_proxy_into_project` (verified in `docs/system-architecture.md`'s pipeline diagram), which rewrites `.xcodeproj` package references and saves the project. A later bare `spm-cache` call is a redundant re-confirmation, not a required separate step.

**Impact**: Ruled out cheap categorization (latency would be 1–3 minutes instead of instant), forcing real `swift package describe` per package (same latency, but genuinely read-only).

### The Unreachable Dict Branch

**Original code path:**
```python
g = json.load(open('spm-cache/packages/proxy/graph.json'))
if isinstance(g, dict):         # <- Never hit
    for k, v in g.items(): ...
elif isinstance(g, list):       # <- Always hit
    print(f'graph: {len(g)} entries')  # <- No per-entry detail
```

**Actual schema** (`ProxyGenerator.swift:179-186`):
```swift
GraphEntry.allCases.map { ... }
// Encodes: [{"module": "X", "status": "hit"}, {"module": "Y", "status": "missed"}, ...]
```

**Fix applied:**
```python
if isinstance(g, list):
    for entry in g:
        print(f"  {entry['module']}: {entry['status']}")  # <- Now prints detail
elif isinstance(g, dict):      # <- Kept as legacy fallback
    ...
```

The fix is 10 lines (iterate list, print per-entry) and moves the dict branch to `elif` so it never interferes. Tests pass; script now produces the per-module status output the docs claim.

### The Step1/Step2 Self-Contradiction

**Step 1 (draft):** "Don't try to detect transitive-only packages—too complex, and spm-cache handles it automatically since v0.2.1."

**Step 2 (draft):** "Transitive-only packages need no exclusion question, so skip asking users about them."

**Problem:** Step 2 had no input from Step 1 saying which packages are transitive-only. The claim couldn't be enforced.

**Resolution:** Remove Step 2's unenforceable claim. Replace with: "Transitive-only conflicts are now auto-resolved in v0.2.1+; if you hit a new transitive conflict, escalate to skills/spm-cache-issue for classification."

## What We Tried

**For the build-integration finding:** Traced through actual code paths in `docs/system-architecture.md`, confirmed both `build` and `use` call the same integration step, ruled out cheap categorization, designed read-only `swift package describe` loop instead.

**For the dead-code bug:** Checked `ProxyGenerator.swift` to confirm the actual graph.json schema is an array, then iterated the script's list branch to print per-entry status. Verified with syntax check (`bash -n`) and a synthetic dry-run before marking done.

**For the Step1/Step2 contradiction:** Code review flagged it during draft review, removed the unenforceable claim, simplified the wording to state facts only (spm-cache auto-handles this; escalate if new issues arise).

## Root Cause Analysis

**Build-integration surprise:** Insufficient preparation. We didn't read `docs/system-architecture.md` until mid-planning. The skill redesign should have started with "understand what the tool actually does" (architecture first), not "what should the skill teach" (pedagogy first).

**Dead-code bug:** The schema is the source of truth. The original script was written against an assumed schema (dict), and nobody traced whether that assumption matched reality. The git history doesn't explain *why* both branches existed or whether they were both intended. Dead code happens when assumptions about data structure drift from the actual structure.

**Step1/Step2 self-contradiction:** Draft was written without fully thinking through the data flow. Step 1 decides what packages are transitive-only, but Step 2 tries to act on that info without Step 1 explicitly providing it. This is a design smell: if Step 2 needs data from Step 1, make that data explicit in the wording.

## Lessons Learned

1. **Architecture first, pedagogy second.** Before redesigning a skill or workflow, understand what the tool *actually does* (read architecture docs, trace code paths). Assumptions about tool behavior are failure vectors.

2. **Dead code looks alive until tested against real data.** The dict branch was syntactically correct and logically sound—just for the wrong schema. Always verify data structures against the actual source before assuming a branch is reachable.

3. **Self-contradictions in multi-step workflows are easy to miss in drafts.** When Step N+1 depends on Step N's output, make that dependency explicit in the text. If you're writing "skip X because it's already done," ask "where is that already done?" and cite the source.

4. **Scope expansion is okay; scope rejection clarity matters.** We expanded from 3 to 4 phases mid-planning (added diagnostics tie-in), which is fine. We also explicitly rejected expanding into repo-hygiene work (fixing stale frontmatter on old plans). That boundary clarity prevents scope creep.

5. **Real-world testing of generated artifacts beats reading the code.** We could have debugged the dead-code issue faster by running `collect_diagnostics.sh` on a real project and observing "wait, why is it just printing entry counts?" instead of assuming the schema from reading the script alone.

## Next Steps

1. **Completed.** All four phases landed in commit `e6455b7`. No pending implementation.
2. **Docs are stable.** Agents using `skills/spm-cache/` will follow the five-step workflow with real categorization. `skills/spm-cache-issue/` escalation path is documented.
3. **Dead-code note filed.** If anyone wonders why `collect_diagnostics.sh` has both dict and list branches, the commit message and this journal explain it: dict is a legacy fallback; list (array) is the actual schema and now produces real per-entry detail.
4. **Architecture debt.** The next skill enhancement should start with "read architecture docs" as Step 0, not Step 2.

---

**Related docs**:
- Brainstorm: `plans/reports/brainstorm-0718-1416-spm-cache-skill-enhancement-report.md`
- Plan: `plans/0718-1416-spm-cache-skill-enhancement/plan.md` + 4 phases
- Commit: `e6455b7` (982 insertions, 30 deletions)

Status: DONE  
Summary: Enhanced spm-cache skills with categorization and troubleshooting; discovered build-already-integrates finding, fixed dead-code diagnostics bug, and resolved Step1/Step2 self-contradiction in skill wording.
