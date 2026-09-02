---
phase: 16-package-toggles-panel-completion
plan: 03
subsystem: api
tags: [read-model, toggl, state, derivation, ruby]

requires:
  - phase: 16-package-toggles-panel-completion
    provides: "state.rb carries saved_cached/applied_cached/pending computed from a fresh per-call config read (16-01); Core::Lockfile#binary_backed_names, the reachability Set over identity/product/target names (16-02)"
provides:
  - "The state read model's per-row `toggleable` (bool) and `reason` (nil | one of five D-09 words), derived server-side in one pinned-precedence pass: excluded -> plugin -> binary-target -> pattern-managed -> fidelity"
  - "`pending` narrowed to toggleable rows only -- a locked row never raises an unsaved-changes bar the UI could not clear"
  - "Pattern-managed derivation: glob match against the fresh on-disk ignore list WITHOUT an exact entry (an exact entry is the normal off state and stays toggleable)"
  - "Fidelity gate fires only on the `resolution-incompatible` warn status; `not-graph-pinned`/`graph-pinned`/`host-pinned` stay neutral/toggleable"
  - "The binary-backed name Set read once per /api/state call (unioned across every project the lockfile tracks) and membership-tested per row, never re-parsed per row"
affects: [16-04, 16-05, 16-06]

actuals:
  tokens: 5750   # chars/4 over the realized diff (estimate was 46000, confidence low)
  tasks: 2
  commits: 4

tech-stack:
  added: []
  patterns:
    - "Precedence-as-control-flow: a private class method returning on the first matching branch in the pinned order, rather than a lookup table -- the ordering IS the code (State.toggle_reason)"
    - "Per-call fact collections computed once before the row loop (saved ignore list, binary-backed name Set) and passed into a pure per-row derivation -- mirrors the existing graph_entries join"

key-files:
  created: []
  modified:
    - lib/spm_cache/web/read_models/state.rb
    - spec/web_state_spec.rb
    - spec/web_integration_spec.rb

key-decisions:
  - "Lockfile project key resolved by unioning binary_backed_names across EVERY project the lockfile tracks (lockfile.projects.keys), not a single guessed xcodeproj basename -- the web tier has never known that filename and a project tracks exactly one in practice, so this is total and correct without adding a new Config accessor outside the plan's file list"
  - "lockfile_binary_names rescues SystemCallError (unreadable lockfile) to an empty Set, matching the plan's explicit 'absent or unreadable' tolerance instruction; malformed lockfile JSON is left to Core::Lockfile's own raise, already caught by api_read's existing JSON::JSONError rescue -- not a behavior this plan's spec matrix tests, so no second rescue layer was added"
  - "Precedence-chain spec (Task 1 row 7) constructed as a 4-row cascade (excluded-status, plugin-status, hit-status, hit-status) each stacked with every lower-precedence fact (binary/pattern/fidelity) present simultaneously, since graph status is a single field and 'excluded AND plugin on one row' is not literally constructible -- this proves the full descending order end-to-end without a false premise"
  - "requirements.mark-complete intentionally skipped for TOGL-02 and TOGL-03: both requirements span this plan through 16-04/16-05 (toggle UI + Apply-now) and 16-06 (panel proof) -- same convention 16-02's SUMMARY recorded for TOGL-03"

requirements-completed: []

coverage:
  - id: D1
    description: "Every /api/state row carries toggleable + exactly one of five reason words when non-toggleable, resolved by fixed precedence (excluded > plugin > binary-target > pattern-managed > fidelity)"
    requirement: TOGL-03
    verification:
      - kind: unit
        ref: "spec/web_state_spec.rb 'the reason matrix' (10 examples)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Saved truth is exact-entry-on-disk; applied truth is the last sync's graph verdict; pending is narrowed to toggleable rows only"
    requirement: TOGL-02
    verification:
      - kind: unit
        ref: "spec/web_state_spec.rb 'saved vs applied' (6 examples)"
        status: pass
    human_judgment: false
  - id: D3
    description: "The read path stays total over missing/malformed config, absent lockfile, and absent graph.json -- no exception escapes api_read"
    requirement: TOGL-03
    verification:
      - kind: unit
        ref: "spec/web_state_spec.rb 'the read path stays total' (4 examples)"
        status: pass
    human_judgment: false
  - id: D4
    description: "16-01's tracer integration rows still pass under the narrowed pending rule and the wider row shape"
    verification:
      - kind: integration
        ref: "spec/web_integration_spec.rb 'POST /api/toggle (16-01 tracer)' rows"
        status: pass
    human_judgment: false

duration: 35min
completed: 2026-09-02
status: complete
---

# Phase 16 / Plan 16-03: The one server-side derivation — toggleable, why not, and saved vs applied

**Every /api/state row now answers, server-side and in one pinned-precedence pass, whether it may be toggled, exactly which of five words explains it when it may not, and whether the saved config disagrees with what the last sync actually applied — narrowed so an unclearable bar can never be raised.**

## Performance

- **Duration:** 35 min
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- `State.toggle_reason` derives `toggleable`/`reason` per row from five facts (graph status, the lockfile's binary-backed name Set, the fresh on-disk ignore list, provenance fidelity) in the pinned precedence order excluded → plugin → binary-target → pattern-managed → fidelity, expressed as control flow with a first-hit-wins return chain
- `pending` narrowed to `toggleable && applied signal present && saved != applied` — a locked row (pattern-managed, plugin, excluded, binary-target, or fidelity-warn) never contributes to the unsaved-changes bar
- Pattern-managed correctly distinguished from the ordinary user-toggled-off state: a glob match WITHOUT an exact ignore entry gates the row; an exact entry never does
- The binary-backed name Set and the saved ignore list are each read once per `/api/state` call, before the row loop, and membership-tested per row — no second read path, no memoization
- The read path is total: absent/malformed `spm-cache.yml`, an absent lockfile, and an absent `graph.json` all degrade to honest empty answers with no exception escaping into WEBrick's error log

## Task Commits

Both tasks were TDD (RED → GREEN):

1. **Task 1: The reason matrix** — `cf12b54` (test), `78535b3` (feat)
2. **Task 2: Saved vs applied — divergence, freshness, degradation** — `376327c` (test), `b4bef59` (feat)

**Example progression (RED → GREEN):**
- `cf12b54` added 11 new/updated examples to `spec/web_state_spec.rb` asserting `toggleable`/`reason` on every row shape (10 new "reason matrix" examples plus the pre-existing "package join" full-row `eq` widened to include the two new fields) — 11 failures confirmed before implementation.
- `78535b3` implemented `State.toggle_reason`/`State.pattern_managed?`/`State.lockfile_binary_names` and wired them into the row builder — all 27 examples green.
- `376327c` added 10 new examples ("saved vs applied" ×6, "the read path stays total" ×4) — exactly 1 failure (the `LockedDivergent` pending-narrowing row), confirming the narrowing was genuinely unimplemented until this commit.
- `b4bef59` narrowed `pending` to require `toggleable`, and updated the one pre-existing full-key `contain_exactly` assertion in `spec/web_integration_spec.rb` (16-01's tracer row) to include the two new keys — `spec/web_state_spec.rb` + `spec/web_integration_spec.rb` both green (95 examples).

**Plan metadata:** this commit.

## Files Created/Modified
- `lib/spm_cache/web/read_models/state.rb` — the reason derivation, the binary-backed name reader, the narrowed pending rule
- `spec/web_state_spec.rb` — the reason matrix, saved-vs-applied, freshness, and degradation rows
- `spec/web_integration_spec.rb` — the 16-01 tracer's row-shape assertion widened for the two new keys

## Decisions Made
See `key-decisions` in frontmatter — summarized: (1) lockfile binary-name resolution unions every project key the lockfile tracks rather than guessing an xcodeproj basename; (2) an unreadable (not malformed) lockfile degrades to an empty Set; (3) the precedence-chain spec proves the full descending order via a 4-row cascade since a single graph-status field cannot literally hold two values at once; (4) `TOGL-02`/`TOGL-03` left unmarked-complete — both span through 16-06.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Widened `spec/web_integration_spec.rb`'s 16-01 tracer row-shape assertion**
- **Found during:** Task 2's own specified verify (`bundle exec rspec spec/web_state_spec.rb spec/web_integration_spec.rb`)
- **Issue:** The pre-existing `contain_exactly('name', 'config', 'size_bytes', 'state', 'fidelity', 'has_macro', 'saved_cached', 'applied_cached', 'pending')` assertion in `web_integration_spec.rb` (a file not in this plan's `files_modified`) predates this plan's two new row keys and failed once `toggleable`/`reason` landed on every row, including the tracer fixture's.
- **Fix:** Added `'toggleable'` and `'reason'` to the expected key list (both fixture packages carry no gating fact, so no other assertion needed changing).
- **Files modified:** `spec/web_integration_spec.rb`
- **Verification:** `bundle exec rspec spec/web_state_spec.rb spec/web_integration_spec.rb` — 95 examples, 0 failures
- **Committed in:** `b4bef59` (Task 2 GREEN commit)

---

**Total deviations:** 1 auto-fixed (1 bug — a stale exact-key assertion made stale by this plan's own additive, spec-required field change)
**Impact on plan:** Necessary to satisfy this plan's own `<verify>` gate and the acceptance criterion "the tracer's integration rows from 16-01 still pass against the narrowed pending rule." No scope creep — no other integration-spec assertion was touched.

## Issues Encountered
None beyond the deviation above.

## User Setup Required
None — no external service configuration required.

## Next Phase Readiness
- 16-04's toggle route can ask this read model whether a package is toggleable before writing, using the same `toggleable`/`reason` fields and the frozen `SPMCache::Web::ReadModels::State::REASON_*` / `REASONS` constants as the single source of truth
- 16-05's client can render `toggleable`, `reason`, `saved_cached`, `applied_cached`, and `pending` verbatim with no client-side derivation (CP10 held: one derivation, server-side)
- 16-06's panel proof still needs a live-browser check that chips and the pending marker render — nothing in this plan claims that

## Self-Check: PASSED

- `lib/spm_cache/web/read_models/state.rb` — FOUND
- `spec/web_state_spec.rb` — FOUND
- `spec/web_integration_spec.rb` — FOUND
- `cf12b54` — FOUND in git log
- `78535b3` — FOUND in git log
- `376327c` — FOUND in git log
- `b4bef59` — FOUND in git log

---
*Phase: 16-package-toggles-panel-completion*
*Completed: 2026-09-02*
