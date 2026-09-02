---
phase: 15-ui-build-controls
plan: 06
subsystem: ui
tags: [build-controls, rollback, pgroup, spawn, probe, eventsource]

requires:
  - phase: 15-ui-build-controls
    provides: "15-01 spawn/slot/stream tracer; 15-02 rollback lock + trigger 'ui'; 15-03 --rebuild; 15-04 mutation routes; 15-05 controls surface"
provides:
  - "Recorded agent-browser probe evidence for all 7 manual rows (BLD-01..04 browser-true)"
  - "One probe-caught defect fixed spec-first: confirm-bar DOM order (Tab-from-Cancel)"
affects: [16-package-toggles-panel-completion]

actuals:
  tokens: 21000
  tasks: 2
  commits: 3

key-decisions:
  - "Probe catch (0962522): the confirm bar shipped [Confirm, Cancel]; focus lands on Cancel (the safe default) and Tab from it EXITED the bar into the failure banner's Jump button — the UI-SPEC A6 contract (Tab reaches Confirm) requires Cancel to precede Confirm in DOM order. Order pin added RED-first; visual order quiet-then-danger."
  - "Probe operating pattern (refined from D-14): small browser cells (click cell, poll cell — never one long cell) after a 30s in-cell timeout wedged the first tab; the locked-page symptom was a cell artifact, not a server fault (curl + fresh reload disproved it)."
  - "Rows 2+3+7 share one lock-held window by design: the parked run gives the in-flight state for the 409 rejection, the visible queue, and the cross-tab visibility in a single controlled sequence."
  - "Rollback's stream-visible lock wait is BLD-04's browser-true proof: the spawned rollback (a real CLI process the web layer never touches) announced 'Waiting for build lock…' under a foreign holder, then took the lock and completed after release (D-07)."

requirements-completed: [BLD-01, BLD-02, BLD-03, BLD-04]

coverage:
  - id: D1
    description: "Build/Rebuild-all buttons spawn real attributed runs, streaming live with single-slot rejection and lock-derived waiting (BLD-01/02 browser-true)"
    requirement: BLD-01
    verification:
      - kind: manual_procedural
        ref: "## D-15 Probe Recording rows 1-4, 7"
        status: pass
    human_judgment: true
    rationale: "Interactive browser behavior; agent-browser evidence recorded verbatim; human sign-off per the D-14-net contract."
  - id: D2
    description: "Rollback confirm bar (keyboard contract) + spawned rollback taking the build lock; failing build banner chain (BLD-03/04 browser-true)"
    requirement: BLD-04
    verification:
      - kind: manual_procedural
        ref: "## D-15 Probe Recording rows 5-6"
        status: pass
    human_judgment: true
    rationale: "Same net — focus/keyboard semantics and visual failure judgment are browser-observable only."

duration: 45min
completed: 2026-09-02
status: complete
---

# Phase 15 / Plan 15-06: The recorded agent-browser probe (phase weld)

**All 7 manual rows executed against a real server and real CLI runs; one keyboard-order defect caught and fixed spec-first; the full suite green.**

## Performance

- **Duration:** ~45 min
- **Tasks:** 2 (rows 1-4; rows 5-7 + gate)
- **Commits:** 3 (rows 1-4 recording; keyboard-order fix 0962522; rows 5-7 recording)

## D-15 Probe Recording

Environment: scratch project `/tmp/d15-scratch` (generated Xcode project; stage A = Rainbow + GoodGit file:// git remotes, both cached from the D-14 era — instant completing builds; stage B added ZBrokenGit for the failing row). Server: `spm-cache web --no-open --port=0` (pid 79610, port 49502), token from `.spm-cache/web/server.json`. Browser: headless Chromium, two tabs. Background processes (lock holders) as tracked async jobs / nohup, all reaped. Times local (UTC+7).

### Row 1 — Build click → attributed live run (BLD-01/D-03/D-09) — PASS
03:59 — clicked `Build`. Instant (captured at 600ms): all three controls disabled, row message `Building…`. The spawned run arrived via auto-switch: card `● running | ui | build` — **verbatim lowercase `ui` badge**; dropdown top `✓ build · just now`; lines streamed live; completion: card `✓ success | ui | build`, argv `spm-cache build`, last line `Build complete!`, row returned to idle (all enabled, message cleared). Run: `20260901T195949696Z-83196-build.jsonl`.

### Row 2 — Second UI build rejected inline (BLD-01/D-05) — PASS
03:00–03:02 — with run `84317` parked in flight (see row 3), tab B (fresh) clicked `Build` → HTTP 409 → row rendered **`A build or rollback is already running — wait for it to finish.`** inline in the message slot — no native dialog, no queued second run (runs dir gained no second file), tab A's run unaffected.

### Row 3 — Terminal-held lock → visible queue, buttons not disabled-by-lock (BLD-02/D-06/A3) — PASS
03:00 — lock held by a foreign ruby process (pid 84187) on `.spm-cache-build.lock`. Clicked `Build`: POST accepted (2xx), run `20260901T200027636Z-84317-build.jsonl` spawned; row message read **`Waiting for build lock…`** within 600ms (the POST's lock snapshot — before any stream line), card `● running | ui | build`; the identical frozen string rendered in-stream as the run's own announce line. On release: the run proceeded (`Build complete!`), message cleared, row idle, card ✓.

### Row 4 — Rebuild all → distinct verb + argv proof (BLD-01/A8) — PASS
03:01 — clicked `Rebuild all`: message `Rebuilding all…`; the run's identity card argv row read **`spm-cache build --rebuild`** — the forced-rebuild flag exactly as the CLI spells it; real rebuild ran (package chips `GoodGit`, `Rainbow` + `build`/`fidelity`); completed ✓.

### Row 5 — Rollback confirm bar + lock (BLD-04/D-08/A6) — PASS (after one spec-first fix)
03:08 — armed the bar: byte-exact sentence `Restore source mode — this removes proxy packages from the Xcode project`, focus on **Cancel**. **First attempt FAILED the keyboard contract**: Tab from Cancel exited into the banner's Jump button — the bar shipped `[Confirm, Cancel]`. Fixed spec-first (order pin RED → DOM swap → GREEN, commit `0962522`, 156 examples) and re-ran: **Tab from Cancel reaches Confirm** ✓; Cancel → bar hides, focus restored to Rollback ✓. Confirm leg (lock held by bg_4): both bar buttons disabled, POST accepted, row in-flight (waiting flavor `Waiting for build lock…`), spawned rollback `20260901T200828456Z-92605-rollback.jsonl` card `● running | ui | rollback` with its stream showing the lock announce; after release: `Rollback complete!`, ✓ success, row idle. Disk truth: the `spm-cache/` sandbox removed.

### Row 6 — Failing build → banner chain (BLD-03) — PASS
03:03 — stage B added ZBrokenGit (compile-broken); `Rebuild all` forced its rebuild → run failed: sticky banner **`Run failed — exit status 1`** + `Jump to first error`, card `✗ failed | ui | build` with `--rebuild` argv, 82 err lines `✗`-prefixed in fail color; jump landed the first err line in view; row returned to idle (one-click retry available).

### Row 7 — Cross-tab slot visibility (D-05/A1) — PASS
03:00–03:02 — tab B (opened during the parked run) saw the run via the stream (same card, wait line) without any action, and its own Build attempt got the inline 409 busy message — the single slot is server-side, not a per-tab illusion.

## Probe-caught defect

**Confirm-bar DOM order (`0962522`)** — see Row 5. UI-SPEC A6's keyboard contract vs the shipped [Confirm, Cancel] order; the safe default (Cancel) must precede the destructive control so Tab reaches it. Order pin added to web_frontend_spec (RED-first).

## Observations (recorded, no action this phase)

- Rollback removes the sandbox and lets the xcodeproj keep a dangling local proxy reference (`spm-cache/packages/proxy`) — pre-existing v0.2-era semantics (rollback.rb touches only the sandbox; BLD-04 added the lock, not a de-integration). Xcode resolution behavior with the dangling ref is a backlog question (candidate: a future rollback de-integration or documentation note).
- The row's `Waiting for build lock…` arrived from the POST's lock snapshot BEFORE the run's announce line — the UI-SPEC's "no later than the announce line" holds with margin.

## Phase gate

`bundle exec rspec` — **983 examples, 0 failures** (baseline 950 → 982 through waves 1-3 → 983 with the keyboard-order pin). No probe process, scratch artifact, or server survived: all reaped/removed (verified).

## Deviations from Plan

Rows 2/3/7 executed in one shared lock-held window (recorded separately) — a sequencing choice, not a scope change. One defect fixed per the honesty rule (spec-first, row re-run green).

## Next Phase Readiness

Phase 16 inherits the controls surface, the spawn slot, and this net. No blockers.

---
*Phase: 15-ui-build-controls*
*Completed: 2026-09-02*
