# Phase 15: UI Build Controls - Context

**Gathered:** 2026-09-01 (auto mode — resumed autonomous run /gsd-autonomous --from 14 --to 16; every auto-selection logged inline)
**Status:** Ready for planning

<domain>
## Phase Boundary

Users can trigger builds and rollback from the dashboard with the same locking, live output, and failure visibility as the terminal: Build/Rebuild buttons that spawn the REAL CLI subprocess (array argv, own process group) streaming into the Phase-14 log view, lock-derived busy/waiting state, failure surfacing, and a Rollback button whose execution acquires the build lock (closing the current lock-free rollback race). Scope = BLD-01..04 exactly. Package-level build selection is NOT here (Phase 16 owns the per-package surface); toggles are NOT here.

</domain>

<decisions>
## Implementation Decisions

### Build invocation surface
- **D-01 (scope selection = verb-level):** two controls — **Build** (incremental, exactly `spm-cache build` semantics: missed-only) and **Rebuild all** (forced rebuild scope). No per-package scope picker in this phase — per-package surface is Phase 16's toggle panel territory (scope-creep guard). — **Reversibility:** reversible — UI labels/controls only. — [auto] Q: "Scope selection shape?" → Selected: "verb-level Build / Rebuild-all" (recommended; matches CLI verbs and keeps 15 off 16's surface)
- **D-02 (spawn mechanics, carrying milestone research forward):** POST endpoint spawns the REAL CLI binary (`bin/spm-cache build|rollback`) via `Process.spawn` with an ARRAY argv (never a shell string) and `pgroup: true` — the server never becomes the build's parent signal-wise; stopping the server must NOT kill an in-flight build, and killing a build targets the process GROUP. CP14's pgroup mechanics land here per the milestone research verdicts. — **Reversibility:** costly — the pgroup lifecycle (spawn, detach, group-kill, exit reaping) touches the server's shutdown and the stop control; changing it later means re-proving WEB-03's exit-0 with an in-flight build.
- **D-03 (UI-run identity):** every UI-spawned run records `trigger: 'ui'` in its run_start header (LOGS-05 vocabulary: ui/terminal/watch). The spawned argv carries the UI-origin marker so the CLI's pre-scan/run-log header records it; the exact mechanism (flag or env) is a research/planning question, the CONTRACT is the header value. 14-04 D-11 already renders the badge verbatim — zero frontend work for the badge itself. — [auto] Q: "How do UI builds identify themselves?" → Selected: "trigger 'ui' in the run header" (recommended; the reserved vocabulary lights up with no new rendering)

### Mutation security surface
- **D-04 (mutation token depth — the decision Phase 13 deferred to the first mutating endpoint):** NO second token. POST /api/* requires the SAME per-launch token via the X-SPM-Token header, behind the SAME Host/Origin-if-present middleware (Origin must match when present). Cross-site form posts cannot set custom headers without a CORS preflight the server never grants; localhost is not a trust boundary beyond the token + origin checks already shipped. Token stays out of logs (T-13-03 posture). — **Reversibility:** reversible — a second token could be layered later; nothing published. — [auto] Q: "Separate mutation token vs same per-launch token?" → Selected: "same token, custom-header-gated POSTs" (recommended; 13's middleware already answers)
- **D-05 (single slot, rejection shape):** exactly ONE UI build at a time, enforced SERVER-side (in-process spawn slot); a second concurrent UI-build POST is rejected — HTTP 409 with a machine-readable reason — and the UI renders the busy message INLINE in the button area (never alert(), never a silent queue). The build button disables while the slot is held. — **Reversibility:** reversible. — [auto] Q: "Second concurrent UI build UX?" → Selected: "inline busy message + disabled control" (recommended)
- **D-06 (busy/waiting state):** derived from the BUILD LOCK (BLD-02): the server-side spawn slot covers UI-originated concurrency; lock-held-by-ANYONE surfaces through the run's own stream — the spawned build's "Waiting for build lock…" line (14-02's D-05 line) already renders inline in the log view, and the panel shows the waiting state derived from the lock state already carried in hello//api/runs (`lock.state: held`). No separate polling channel. — [auto] Q: "Where does waiting state come from?" → Selected: "lock-derived via existing surfaces" (recommended; no new state source — the server stays a stateless reader)

### Rollback
- **D-07 (rollback = CLI subprocess + lock):** the Rollback button POSTs to a rollback endpoint that spawns the REAL `spm-cache rollback` subprocess (same pgroup mechanics). BLD-04's lock fix lands in the CLI itself: rollback ACQUIRES the build lock before touching the project (CP4) — the web layer inherits the fix by spawning the CLI, never re-implementing rollback server-side. — **Reversibility:** costly — the CLI-side lock acquisition changes rollback's concurrency contract for ALL callers (terminal included).
- **D-08 (rollback confirmation):** destructive action → two-step INLINE confirm: first click swaps the button area to a confirm bar ("Restore source mode — this removes proxy packages from the Xcode project") with explicit Confirm/Cancel buttons. No native dialogs (none exist in the dashboard; consistent with the panel idiom). — [auto] Q: "Rollback confirmation shape?" → Selected: "two-step inline confirm bar" (recommended)

### Streaming
- **D-09 (one stream, no new channels):** UI-spawned builds stream through the SAME /api/events SSE machinery — the run appears via the existing switch/auto-switch path (D-04 of 14-CONTEXT), lands in the recent-runs dropdown as trigger 'ui', and failure surfacing reuses the banner/jump chain (D-03/D-10) already browser-proven. No second websocket, no POST-response streaming. — **Reversibility:** reversible.

### Claude's Discretion
Exact endpoint paths, request/response envelope shapes, spawn-slot data structure, stop control (if any — SC text does not require a stop button; if the planner adds one it must use the pgroup), and the UI-origin marker mechanism (flag vs env) — researcher/planner ground these in the codebase.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements + roadmap
- `.planning/REQUIREMENTS.md` § Build control — BLD-01..04 verbatim contracts
- `.planning/ROADMAP.md` § Phase 15 — goal, deps (13, 14), SC1-SC4
- `.planning/PROJECT.md` — constraint "server is a stateless file reader + run-log tailer + CLI-subprocess spawner — never a second source of truth; the build flock stays the only mutex"

### Milestone research verdicts (load-bearing)
- `.planning/research/SUMMARY.md` — CP4 rollback-flock + CP14 pgroup mechanics land in THIS phase; localhost trust posture
- `.planning/phases/14-live-log-streaming-terminal-watch-relay/14-RESEARCH.md` — transport reality, Pitfall 4 (Last-Event-ID as attacker input), Pattern 3 (broadcaster)

### Prior phase contracts this builds on
- `.planning/phases/13-server-skeleton-read-only-dashboard/13-CONTEXT.md` — middleware decisions (Host/Origin + token; WR-02 second-launch block-then-replace)
- `.planning/phases/14-live-log-streaming-terminal-watch-relay/14-CONTEXT.md` — D-04 auto-switch, D-05 lock-wait line, D-11 verbatim trigger badge (the 'UI' badge), D-12 dropdown
- `.planning/phases/14-live-log-streaming-terminal-watch-relay/14-UI-SPEC.md` — copy/state/matrix conventions the new controls must extend

### Code surfaces (verified this session)
- `lib/spm_cache/web/router.rb` — /api/* registration + token/Host/Origin gate the POST routes ride
- `lib/spm_cache/web/assets/app.js` — request layer (X-SPM-Token + envelope) the new controls duplicate, never import
- `lib/spm_cache/command/rollback.rb` — the real rollback verb BLD-04 locks (currently lock-free — the race to close)
- `lib/spm_cache/installer/build.rb:80`, `installer/use.rb:75` — the flock sites (rollback joins them)
- `lib/spm_cache/core/run_log.rb` — `trigger` header field ('terminal'/'watch'/'ui' vocabulary)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- app.js request layer: token-gated fetch + envelope check — the POST controls reuse the exact pattern (custom header, never query-param, for POSTs)
- log.js switch/auto-switch machinery: a UI-spawned run reaching the stream needs ZERO new frontend plumbing to display
- Web::Events broadcaster + tailer: run discovery/switch already publishes on new run files
- Router middleware: POST routes inherit Host/Origin/token posture by registration order

### Established Patterns
- CLAide command pattern for the rollback lock change (CLI-side, spec-first)
- bash-tool async-job pattern for any verification servers/processes (this session's proven probe pattern — nohup+disown gets reaped)
- G-13-1 class: any new asset referenced as `assets/<name>` with browser-resolution spec coverage

### Integration Points
- Router: new POST /api/build + POST /api/rollback routes (exact paths discretionary)
- Spawn slot: server-side singleton holding the pgroup handle; WEB-03 shutdown must remain exit-0 with an in-flight build (the build is NOT the server's child to kill — pgroup + detach)
- RunLog trigger field: the UI-origin marker lands in the run_start header the dashboard already renders

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches consistent with the 13/14 dashboard idiom (existing tokens, inline states, no dialogs, no client clock/timers outside app.js's single poll).

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope. (Phase 14's verification noted SC3's "same view as UI-triggered runs" informational deferral — that resolves HERE, in this phase, by construction.)

</deferred>

---

*Phase: 15-UI Build Controls*
*Context gathered: 2026-09-01*
