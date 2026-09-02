# Phase 15: UI Build Controls - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-01
**Phase:** 15-UI Build Controls
**Mode:** --auto (resumed autonomous run /gsd-autonomous --from 14 --to 16; recommended options auto-selected and logged; user may override any decision before/during planning)
**Areas discussed:** Scope selection shape, UI-run identity, Mutation token depth, Concurrent-build rejection, Busy/waiting source, Rollback confirmation

---

## Scope selection shape

| Option | Description | Selected |
|--------|-------------|----------|
| Verb-level (Build / Rebuild all) | Two controls matching the CLI verbs; per-package surface stays in Phase 16 | ✓ |
| Per-package picker | Checkbox list next to Build — overlaps Phase 16's toggle panel | |

**[auto] Q:** "Scope selection shape?" → Selected: "verb-level Build / Rebuild-all" (recommended; matches CLI verbs and keeps 15 off 16's surface)

## UI-run identity

| Option | Description | Selected |
|--------|-------------|----------|
| trigger 'ui' in the run header | LOGS-05 vocabulary; 14-04's verbatim badge renders it with zero frontend work | ✓ |
| Separate UI run list | New surface — contradicts D-12's single recent-runs dropdown | |

**[auto] Q:** "How do UI builds identify themselves?" → Selected: "trigger 'ui' in the run header" (recommended)

## Mutation token depth (deferred to this phase by 13)

| Option | Description | Selected |
|--------|-------------|----------|
| Same per-launch token, custom-header POSTs | X-SPM-Token on POST behind the shipped Host/Origin middleware; cross-site forms can't set custom headers without a preflight the server never grants | ✓ |
| Second mutation token | Extra UX cost; no additional threat answered on a localhost boundary | |

**[auto] Q:** "Separate mutation token vs same per-launch token?" → Selected: "same token, custom-header-gated POSTs" (recommended; 13's middleware already answers)

## Concurrent-build rejection (BLD-01 single slot)

| Option | Description | Selected |
|--------|-------------|----------|
| Inline busy message + disabled control | Server-side single slot, 409 + reason, rendered in the button area | ✓ |
| Alert dialog | Native dialogs don't exist in the dashboard idiom | |
| Silent queue | Explicitly forbidden by SC2 ("never a silent queue") | |

**[auto] Q:** "Second concurrent UI build UX?" → Selected: "inline busy message + disabled control" (recommended)

## Busy/waiting state source (BLD-02)

| Option | Description | Selected |
|--------|-------------|----------|
| Lock-derived via existing surfaces | The spawned run's own "Waiting for build lock…" line + lock.state in hello//api/runs | ✓ |
| New polling channel | Violates the stateless-server constraint; second source of truth | |

**[auto] Q:** "Where does waiting state come from?" → Selected: "lock-derived via existing surfaces" (recommended)

## Rollback confirmation (BLD-04)

| Option | Description | Selected |
|--------|-------------|----------|
| Two-step inline confirm bar | Destructive action; explicit Confirm/Cancel inline, no native dialogs | ✓ |
| One-click | Destructive without confirmation | |

**[auto] Q:** "Rollback confirmation shape?" → Selected: "two-step inline confirm bar" (recommended)

---

## Claude's Discretion

Endpoint paths, envelope shapes, spawn-slot structure, stop-control inclusion, UI-origin marker mechanism (flag vs env).

## Deferred Ideas

None — discussion stayed within phase scope.
