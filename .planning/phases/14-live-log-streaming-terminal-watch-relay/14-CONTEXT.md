# Phase 14: Live Log Streaming + Terminal/Watch Relay - Context

**Gathered:** 2026-09-01
**Status:** Ready for planning

<domain>
## Phase Boundary

One SSE stream of the shared run log: any build — terminal-started, `watch`-initiated, or (when Phase 15 lands) UI-triggered — appears live in one browser view with mid-build replay from byte 0, reconnect-without-loss, and visible run identity. The transport is the file-tail of `.spm-cache/runs/*.jsonl` (research-adjudicated over UDS), so terminal/`watch` relay is the SAME mechanism as UI-run streaming, not a second feature. The server stays a stateless file reader + run-log tailer; "build running" is derived from the build flock + run logs, never server memory (CP10).

Excludes: build/rollback buttons and UI-triggered spawns (Phase 15 — the UI badge renders "reserved" until then), package toggles (Phase 16), graph edges (post-v0.5 spike), any run-history DB with search (declined anti-feature).

Locked by ROADMAP success criteria SC1–SC4 and requirements LOGS-02..05. UI hint: yes — the log view is a substantial new frontend surface (identity card, anchor rail, pills, banner).

</domain>

<decisions>
## Implementation Decisions

### Live view behavior
- **D-01:** Auto-follow with pause-on-scroll — the view locks to the tail; scrolling up pauses with a "paused — N new lines · jump to live" pill; clicking the pill resumes. — **Reversibility:** reversible — frontend-only behavior.
- **D-02:** Bounded render ring (~500 lines) — older lines leave the DOM, replaced by a "… N earlier lines — reload to replay from start" notice. Mirrors the server-side bounded-queue stance (CP11). The full run always remains on disk (Phase 12 D-05 full-fidelity). — **Reversibility:** reversible.
- **D-03:** Failure surfaces as a sticky banner (exit status + jump-to-first-error anchor) plus in-stream error-line styling via the existing `:fail` color vocabulary. — **Reversibility:** reversible.

### Multi-run presentation
- **D-04:** When a new run starts while an older one is being viewed, the stream auto-switches to the newest run with a persistent "switched to new run — previous: <run-id>" notice; the previous run stays reachable (via the notice / recent list). — **Reversibility:** reversible.
- **D-05:** Lock contention shows INLINE: "waiting for build lock…" attribution in-stream for the blocked run, derived from the flock + run logs (CP10), never server memory. (The research mandates this line in the Installer — Phase 14 wires its display.) — **Reversibility:** costly — touches the Installer's output seam; the same line feeds terminal users, so wording changes are user-visible in two surfaces.
- **D-06:** Run identity renders as a CARD above the stream (not a single line): trigger-source badge + command + config + started-at + argv detail + live status dot flipping to ✓/✗ on `run_end`. — **Reversibility:** reversible.

### Anchors & run identity
- **D-07:** Anchor rail covers the FULL frozen Phase-12 D-04 vocabulary: `package_start` events AND phase markers (detect/integrate/build/fidelity) as jump targets. — **Reversibility:** reversible.
- **D-08:** Anchors live in a sticky chip rail on the log panel's edge (graph-legend precedent from Phase 13), visible while following the tail. — **Reversibility:** reversible.
- **D-09:** Anchor click JUMPS and FILTERS — non-matching lines dim/hide with a "filtered: <pkg>" pill. — **Reversibility:** reversible.
- **D-10:** On run failure while a filter is active, the banner PIERCES the filter: it shows regardless, and its jump-to-error anchor exits the filter (jumps to the error's real position, pill cleared). Failure visibility beats filter intent. — **Reversibility:** reversible.
- **D-11:** Trigger-source badge derives from the run-log header (command + argv; watch cycles carry `command: watch` per Phase 12 D-09). The `UI` badge is forward-compatible: reserved/hidden until Phase 15's spawned argv carries the marker. — **Reversibility:** costly — the attribution vocabulary feeds Phase 15's job machinery; changing it later reworks badge derivation + Phase 15 plans.

### Replay & history scope
- **D-12:** Current run + a compact recent-runs dropdown (identity + status per entry, read straight from the runs dir — no DB, no search, no extra storage). Research's declined anti-feature was the run-history DB with search; this is a directory listing. — **Reversibility:** reversible.
- **D-13:** Cold load shows live-or-last: live run → replay from byte 0 then follow; no live run → most recent completed run replayed with a "completed <time> ago" identity card. Fresh boots of a quiet project never show an empty screen. — **Reversibility:** reversible.
- **D-14:** 14-VALIDATION's manual table explicitly includes an agent-browser streaming probe as a recorded, repeatable step: start a real `spm-cache` run from a terminal, assert live render + replay + reconnect-without-loss across a server kill/restart mid-run. (This net caught Phase 13's ship-blocking G-13-1 that 119 green examples missed.) — **Reversibility:** reversible.

### Carrying forward (research/roadmap-locked — do not re-litigate in planning)
- Transport: file-tail of the JSONL run logs; UDS is the documented sandbox fallback only.
- SSE + `EventSource` (not WebSocket); failed connects answer 503 + `Retry:` (NEVER 204); `Last-Event-ID` replay; ~15s heartbeats; bounded per-client queues with drop-oldest + explicit notice (CP11).
- Relay hygiene: watcher-daemon-only subscription (exclude legacy `--watch` path, CP5); SIGTERM forwarding + web-run self-trigger guard extended (CP6); health-check-before-open (CP12).
- Honest pid-dead-without-exit-line runs (CP14 detection nuance from Phase 12's retention work).
- Single stream + per-package anchors (N panes declined); stateless file reader; flock is the only mutex.

### Claude's Discretion
- `Web::Events` internal structure (tailer polling interval, ring buffer sizing, broadcaster thread model) within the CP11 constraints
- SSE endpoint path/naming and event payload field names (same-launch client/server, no versioning — Phase 13 precedent)
- Exact CSS/DOM layout of the log panel within the dark-first/system-font/status-color constraints
- Recent-runs dropdown placement and entry truncation

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase definition
- `.planning/ROADMAP.md` § "Phase 14: Live Log Streaming + Terminal/Watch Relay" — goal, SC1–SC4, LOGS-02..05, UI hint
- `.planning/REQUIREMENTS.md` § "Live log streaming" — LOGS-02..05 (the four requirements in this phase)

### Milestone research (HIGH confidence, 2026-08-31)
- `.planning/research/SUMMARY.md` — file-tail-over-UDS adjudication, SSE transport verdict (503-not-204, Last-Event-ID, heartbeats, bounded queues), component sketch (`Web::Events` tailer + broadcaster), anti-features list, Phase-3 implications section
- `.planning/research/ARCHITECTURE.md` — `Web::Events` design seam, run-log tail/replay mechanics, watcher interplay
- `.planning/research/PITFALLS.md` — CP5 (legacy `--watch` exclusion), CP6 (watcher lifecycle/self-trigger guard), CP10 (derive running-state from flock+logs), CP11 (SSE transport hazards — 204, buffering, reconnect storms, backpressure), CP12 (health-before-open, explicit env)

### Prior phase context (locked vocabulary + seams this phase consumes)
- `.planning/phases/12-run-log-capture-foundation/12-CONTEXT.md` — D-04 frozen event vocabulary (reversibility note: this phase builds directly on it), D-05 full-fidelity body, D-09 watch per-cycle files, runs-dir conventions
- `.planning/phases/13-server-skeleton-read-only-dashboard/13-CONTEXT.md` — server/middleware/token architecture, offline frontend constraints, envelope discipline, `Web::Server`/`Router` seams the SSE route extends

### Codebase maps (scout, refreshed 2026-08-31)
- `.planning/codebase/ARCHITECTURE.md` — Main entry/dispatch, watch flow (per-cycle regeneration semantics), Core layer inventory
- `.planning/codebase/CONVENTIONS.md` — `Core::Sh` single shell seam, no-monkey-patching, atomic tempfile+rename, default-deny Sh spec guard, hermetic-spec posture (CP7)

No external ADRs/specs — requirements fully captured in decisions above.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Core::RunLog` (Phase 12) — the JSONL writer + frozen event vocabulary this phase tails; `RunLog.current` seam, retention reader, per-cycle watch files
- `Core::Watcher` mtime-polling precedent — the tailer's polling model; CP5/CP6 constraints on which watcher surface to hook
- `Web::Server`/`Web::Router` (Phase 13) — the SSE route mounts behind the same Host/Origin/token gate; WEBrick `HTTPResponse#chunked=` provides SSE streaming (verified in webrick 1.9.2 source per research)
- `app.js` panel architecture (Phase 13) — el()/textContent-only DOM discipline (stored-XSS defense), token/fetch layer, stamp/poll patterns; the log panel extends this file within the 300–400 LOC budget's spirit (a second module is acceptable if the budget is exceeded — same vendored, offline, framework-free constraints)
- Build flock probe (`.spm-cache-build.lock`) — CP10's running-state source
- `:ok`/`:warn`/`:fail` status vocabulary (doctor + state badges) — error/failure styling

### Established Patterns
- Stateless file reader principle — the server never becomes a second source of truth; restartable at any moment
- Envelope discipline `{status, data, generated_at}` for request/response APIs (SSE is a different surface — event-per-line with monotonic byte-offset ids per research)
- Hermetic suite (CP7): seam-tested units + at most one port-0 integration boot; run-log/tailer specs via tmpdir fixtures and StringIO
- Comments cite the planning-doc ID they defend (e.g. "(CP11)", "(D-04)")

### Integration Points
- New `Web::Events` (or equivalent) under `lib/spm_cache/web/` — runs-dir tailer → SSE broadcaster; router gains the stream endpoint
- `lib/spm_cache/installer.rb` — the "waiting for build lock…" line (D-05; research-mandated, wording feeds both terminal and browser)
- `Command::Watch` / `Core::Watcher` boundary — relay subscription hygiene (CP5/CP6), no change to watcher regeneration semantics
- `lib/spm_cache/web/assets/` — log-view frontend (identity card, anchor rail, follow/pause pill, filter pill, failure banner, recent-runs dropdown, connection pill)

</code_context>

<specifics>
## Specific Ideas

No specific requirements beyond the decisions above — open to standard approaches within them. (The UI-SPEC from `/gsd-ui-phase 14`, if run, will pin exact copy strings for pills/banners/cards the way 13-UI-SPEC did — recommended given the UI hint.)

</specifics>

<deferred>
## Deferred Ideas

- Full historical browsing with per-run filters (status/verb/date) — borders the declined run-history-DB anti-feature; revisit post-v0.5 only if the recent-runs dropdown proves insufficient.
- UI-triggered run streaming — Phase 15 (rides this phase's stream; UI badge reserved in the identity vocabulary now).

</deferred>

---

*Phase: 14-Live Log Streaming + Terminal/Watch Relay*
*Context gathered: 2026-09-01*
