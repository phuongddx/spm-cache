---
# Phase 16: Package Toggles + Panel Completion - Context

**Gathered:** 2026-09-02 (auto mode — resumed autonomous run; every auto-selection logged inline)
**Status:** Ready for planning
---

<domain>
## Phase Boundary

Per-package cache on/off toggles in the browser THROUGH the same config code path `spm-cache off` uses (shared mutators, atomic save that cannot clobber concurrent CLI edits), honest saved-vs-applied semantics with an explicit Apply-now (re-sync via Phase 15's job machinery), and WHY-not reasons where toggling isn't allowed. This completes the Cache State panel. Scope = TOGL-01..03 exactly. No new panels, no bulk operations, no scheduling.

</domain>

<decisions>
## Implementation Decisions

### Toggle surface
- **D-01 (placement):** the toggles live IN the Cache State panel's existing per-package table — one new column of native checkboxes (checked = cached, unchecked = ignored), disabled with a reason chip where not toggleable. No new panel, no separate toggles view. — [auto] Q: "Where do toggles live?" → Selected: "in the Cache State table" (recommended; 'Panel Completion' is this)
- **D-02 (control):** native `<input type="checkbox">` per row (label-sr-only or the package name as label) — keyboard operable, no ARIA-reinvented switch. — **Reversibility:** reversible.

### Persistence + concurrency (TOGL-01)
- **D-03 (shared mutators):** `spm-cache off` is refactored onto shared config mutators (e.g. Config#set_ignored(package, boolean)) and the web POST uses the SAME path — one source of truth, CLI behavior unchanged (its own specs stay green byte-identical on the free path). — **Reversibility:** costly — `off` is a published CLI contract; the refactor must be behavior-preserving.
- **D-04 (atomic + clobber-proof save):** write via the same-dir tempfile + rename pattern (the run_start-header precedent) and a read-merge-write under an flock on the config (the build-lock precedent) so a concurrent CLI edit cannot be silently overwritten: take the lock, RE-READ, merge the one toggled key, write, release. — **Reversibility:** reversible.
- **D-05 (comment-loss honesty — roadmap-pinned):** the yml rewrite drops hand-written comments; the UI SURFACES this in the apply/undo copy verbatim-pinned (e.g. the unsaved-changes bar notes the config file is rewritten and comments are not preserved). — **Reversibility:** reversible (copy).

### Saved vs applied + Apply-now (TOGL-02)
- **D-06 (semantics):** a row's checkbox reflects SAVED config (the ignore list on disk). "Applied" = what the last sync actually used (the graph/lockfile truth the read model already serves). When any row's saved state differs from applied, the panel shows an unsaved-changes bar: copy + exactly ONE `Apply now` action + a revert-all affordance. — [auto] Q: "saved-vs-applied display?" → Selected: "unsaved-changes bar + Apply now" (recommended)
- **D-07 (Apply-now mechanics):** `Apply now` spawns the real re-sync (`spm-cache use`) through Phase 15's Web::Jobs slot (trigger 'ui', same single-slot 409 semantics, same stream view) — the toggles then converge to applied as the run completes. No second sync mechanism, no server-side config applying. — **Reversibility:** reversible — rides existing machinery. — [auto] Q: "How does Apply-now run?" → Selected: "spawn use via the 15 job slot" (recommended; D-07 of 15-CONTEXT's stateless-server rule)
- **D-08 (mutation route):** POST /api/toggle (single package per request, {package, cached}) behind the same structural gate + per-route body validation, 409 shared with build/rollback (the slot governs Apply-now; the toggle POST itself is instant config write, NOT slot-gated — toggling stays available during a run). — [auto] Q: "Does toggling block during runs?" → Selected: "toggle writes are instant and allowed; only Apply-now takes the slot" (recommended)

### Reasons (TOGL-03)
- **D-09 (vocabulary):** exactly the five TOGL-03 reasons — `pattern-managed` / `plugin` / `binary-target` / `excluded` / `fidelity` — derived in the read model (server-side, one derivation), rendered as text chips with title tooltips on the disabled rows. No new reason strings client-side. — **Reversibility:** reversible.

### Claude's Discretion
Exact endpoint path names, request/response envelopes, the mutator method names, the merge algorithm details (key-level vs list-level for the ignore list), and the chip styling — researcher/planner ground these in the codebase.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

- `.planning/REQUIREMENTS.md` § Package toggles — TOGL-01..03 verbatim
- `.planning/ROADMAP.md` § Phase 16 — goal, deps (13 read models, 15 job machinery), SC1-3
- `.planning/PROJECT.md` — stateless-server constraint; "the build flock stays the only mutex"
- `.planning/phases/15-ui-build-controls/15-CONTEXT.md` — D-02 spawn shape, D-04 token posture, D-05 slot semantics this phase reuses
- `.planning/phases/15-ui-build-controls/15-UI-SPEC.md` — the controls-row conventions the unsaved-changes bar extends
- `.planning/phases/14-live-log-streaming-terminal-watch-relay/14-UI-SPEC.md` — the design system (tokens, copy, states)
- Code: `lib/spm_cache/core/config.rb` (the ignore list + atomic-save precedent), `lib/spm_cache/command/off.rb` (the CLI surface being refactored), `lib/spm_cache/web/read_models/` (the cache-state read model), `lib/spm_cache/web/jobs.rb` (the slot)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- Web::Jobs slot + POST route pattern (15-04's matrix is the template for the toggle route)
- app.js request layer + the read model's package table (the checkbox column lands there)
- The tempfile+rename atomic-write pattern (run_log.rb header; marker.rb)

### Established Patterns
- Server-side derivation of every status vocabulary (CP10 precedent) — reasons derive once, server-side
- 409 shared-slot semantics; instant config writes are NOT slot-gated (D-08)
- el()/textContent; no new assets; no client clock/timers beyond app.js's poll

### Integration Points
- Config: the ignore list mutators + locked merge-write
- Cache State panel: the table + the unsaved-changes bar
- Web::Jobs: Apply-now spawns `use`

</code_context>

<specifics>
## Specific Ideas

No specific requirements — standard approaches consistent with the 13/14/15 dashboard idiom.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 16-Package Toggles + Panel Completion*
*Context gathered: 2026-09-02*
