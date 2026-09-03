# Phase 14: Live Log Streaming + Terminal/Watch Relay - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-01
**Phase:** 14-Live Log Streaming + Terminal/Watch Relay
**Areas discussed:** Live view behavior, Multi-run presentation, Anchors & run identity, Replay & history scope

---

## Live view behavior

| Option | Description | Selected |
|--------|-------------|----------|
| Auto-follow, pause on scroll | Locks to tail; scrolling up pauses with a "paused — N new lines · jump to live" pill; click resumes. Dozzle/Playwright-UI precedent | ✓ |
| Manual follow only | Never auto-scroll; a Follow button appends and scrolls on demand | |
| Per-run follow memory | Auto-follow on connect and on each new run; pause persists per run | |

**User's choice:** Auto-follow, pause on scroll
**Notes:** —

| Option | Description | Selected |
|--------|-------------|----------|
| Bounded ring (~500) | Keep last ~500 lines rendered; older replaced by "… N earlier lines — reload to replay" notice; mirrors CP11 server-side stance | ✓ |
| Render full run | Every line stays in the DOM for the current run; heavy on 10k+ line xcodebuild runs | |
| Adaptive bound | Ring auto-raises (500 → 2000) when the user scrolls up hunting context; never unbounded | |

**User's choice:** Bounded ring (~500)
**Notes:** Full fidelity always remains on disk (Phase 12 D-05); the bound is browser-only.

| Option | Description | Selected |
|--------|-------------|----------|
| Banner + jump anchor | Sticky banner on run_end failure: exit status + jump-to-first-error; error lines styled in-stream via existing `:fail` vocabulary | ✓ |
| Inline styling only | Error lines styled red in-stream; no banner; failure scrolls out of view on long runs | |
| Banner + auto-jump | Banner plus auto-scroll to first error, overriding follow state | |

**User's choice:** Banner + jump anchor
**Notes:** —

---

## Multi-run presentation

| Option | Description | Selected |
|--------|-------------|----------|
| Auto-switch + notice | Stream switches to newest run with persistent "switched to new run — previous: <run-id>" notice; old run reachable | ✓ |
| Run-selector, manual | New runs queue in a selector; view keeps current selection until user switches | |
| Concatenated separators | Runs concatenate in one scrolling view with separator headers | |

**User's choice:** Auto-switch + notice
**Notes:** —

| Option | Description | Selected |
|--------|-------------|----------|
| Show lock-wait inline | "waiting for build lock…" attribution in-stream for the blocked run, derived from flock + run logs (CP10) | ✓ |
| Sidebar-only waiting | Blocked runs show only in a sidebar/status area; main stream never shows waiting states | |

**User's choice:** Show lock-wait inline
**Notes:** Research already mandates the Installer line; Phase 14 wires its display.

| Option | Description | Selected |
|--------|-------------|----------|
| Single identity line | One header line: badge + command + config + started-at + status dot | |
| Identity card | Card above the stream with room for argv detail: badge, command, config, started-at, argv, status flip to ✓/✗ | ✓ |

**User's choice:** Identity card
**Notes:** —

---

## Anchors & run identity

| Option | Description | Selected |
|--------|-------------|----------|
| Packages + phases | Anchor rail lists package_start events AND phase markers (detect/integrate/build/fidelity) — full frozen D-04 vocabulary | ✓ |
| Packages only | package_start events only (SC1's literal wording); phases as styled separators, not jump targets | |

**User's choice:** Packages + phases
**Notes:** Data already in the log; frontend-only cost.

| Option | Description | Selected |
|--------|-------------|----------|
| Sticky chip rail | Chips on the log panel's right edge that scroll-jump; visible while following tail (Phase 13 graph-legend precedent) | ✓ |
| In-stream only | Anchors as in-stream heading rows only; no persistent rail | |

**User's choice:** Sticky chip rail
**Notes:** —

| Option | Description | Selected |
|--------|-------------|----------|
| Jump only, no filter | Anchor click jumps; stream always shows everything | |
| Jump + filter mode | Anchor click dims/hides non-matching lines with a "filtered: <pkg>" pill | ✓ |

**User's choice:** Jump + filter mode
**Notes:** Follow-up pinned the failure interaction (next table).

| Option | Description | Selected |
|--------|-------------|----------|
| Banner pierces filter | On failure with a filter active: banner shows regardless; its jump-to-error exits the filter (jumps to real position, pill cleared) | ✓ |
| Filter stays strict | Filter authoritative; banner says "error outside current filter — clear filter to view" | |

**User's choice:** Banner pierces filter
**Notes:** Failure visibility beats filter intent.

| Option | Description | Selected |
|--------|-------------|----------|
| Derive from run log | terminal/watch badges from run-log header command + argv (watch cycles: command=watch per D-09); UI badge "reserved" until Phase 15 | ✓ |
| Two-source only for now | Badge says terminal/watch only; UI source decided in Phase 15's own discussion | |

**User's choice:** Derive from run log
**Notes:** Forward-compat with Phase 15's spawned argv marker.

---

## Replay & history scope

| Option | Description | Selected |
|--------|-------------|----------|
| Current + recent list | Live/current run plus compact recent-runs dropdown (identity + status per entry, straight from the runs dir — no DB, no search) | ✓ |
| Current run only | Only current/most-recent run viewable; older runs terminal-only | |
| Full history browse | Current + list + per-run filters (status/verb/date); borders declined run-history-DB anti-feature | |

**User's choice:** Current + recent list (user: "Let go with your recommended")
**Notes:** —

| Option | Description | Selected |
|--------|-------------|----------|
| Live or last run | Live run → replay from byte 0 then follow; none → most recent completed run replayed with "completed <time> ago" card | ✓ |
| Live run only | Live replays + follows; otherwise empty "waiting for the next run…" placeholder | |
| Always land on list | Cold load always opens the recent-runs list, never auto-opens a run | |

**User's choice:** Live or last run
**Notes:** —

| Option | Description | Selected |
|--------|-------------|----------|
| Agent-browser UAT | 14-VALIDATION's manual table includes an agent-browser streaming probe (real terminal run → live render + replay + reconnect across server kill/restart) as a recorded step | ✓ |
| Human-only manual table | Manual table stays human-only; agent browser remains ad-hoc orchestrator tooling | |

**User's choice:** Agent-browser UAT
**Notes:** The agent-browser net caught Phase 13's ship-blocking G-13-1 that 119 green examples missed (same session).

---

## Claude's Discretion

- `Web::Events` internal structure (polling interval, ring buffer sizing, broadcaster thread model) within CP11 constraints
- SSE endpoint path/naming, event payload field names (same-launch client/server, no versioning)
- Log panel CSS/DOM layout within dark-first/system-font/status-color constraints
- Recent-runs dropdown placement and entry truncation

## Deferred Ideas

- Full historical browsing with per-run filters (status/verb/date) — post-v0.5 only if the dropdown proves insufficient
- UI-triggered run streaming — Phase 15 (rides this phase's stream; UI badge reserved now)
