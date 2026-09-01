# Phase 16: Package Toggles + Panel Completion - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.

**Date:** 2026-09-02
**Phase:** 16-Package Toggles + Panel Completion
**Mode:** --auto (resumed autonomous run; recommended options auto-selected and logged)
**Areas discussed:** Toggle placement, Control shape, Saved-vs-applied display, Apply-now mechanics, Toggle-during-runs policy

---

## Toggle placement

| Option | Description | Selected |
|--------|-------------|----------|
| In the Cache State table | One new checkbox column; disabled+reason rows where not toggleable; completes the panel | ✓ |
| Separate toggles view | New panel — contradicts 'Panel Completion' scope | |

**[auto] Q:** "Where do toggles live?" → Selected: "in the Cache State table" (recommended)

## Saved-vs-applied display (TOGL-02)

| Option | Description | Selected |
|--------|-------------|----------|
| Unsaved-changes bar + Apply now | Saved checkboxes + bar when saved ≠ applied; one action + revert-all | ✓ |
| Per-row apply buttons | N actions, no single re-sync truth | |

**[auto] Q:** "saved-vs-applied display?" → Selected: "unsaved-changes bar + Apply now" (recommended)

## Apply-now mechanics

| Option | Description | Selected |
|--------|-------------|----------|
| Spawn `use` via the 15 job slot | Real re-sync, trigger 'ui', shared 409, stream view convergence | ✓ |
| Server-side config applying | Violates the stateless-server constraint | |

**[auto] Q:** "How does Apply-now run?" → Selected: "spawn use via the 15 job slot" (recommended)

## Toggle-during-runs policy

| Option | Description | Selected |
|--------|-------------|----------|
| Toggles instant + allowed; only Apply-now takes the slot | Config writes are instant; the slot governs the re-sync | ✓ |
| Everything blocked during runs | Over-restrictive; no race exists for locked merge-writes | |

**[auto] Q:** "Does toggling block during runs?" → Selected: "toggle writes are instant and allowed; only Apply-now takes the slot" (recommended)

---

## Claude's Discretion

Endpoint paths, envelopes, mutator names, merge algorithm details, chip styling.

## Deferred Ideas

None.
