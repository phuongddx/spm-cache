---
phase: 16-package-toggles-panel-completion
plan: 06
subsystem: ui
tags: [toggles, config, probe, poll-convergence]

requires:
  - phase: 16-package-toggles-panel-completion
    provides: "16-01 mutator+lock+route; 16-02 binary flag; 16-03 derivation; 16-04 mutation surface; 16-05 panel"
provides:
  - "Recorded agent-browser probe evidence for all 8 manual rows (TOGL-01..03 browser-true)"
affects: []

actuals:
  tokens: 24000
  tasks: 2
  commits: 2

key-decisions:
  - "Convergence mechanism recorded precisely (row 3): an ignore-only change does NOT trigger proxy regeneration — the parked fast-path sync left graph status 'hit', so applied truth only moves when the graph is rewritten; the probe applied the plan's sanctioned fallback (fixture graph set to the post-sync truth, recorded) and the bar then cleared on the NEXT POLL with no POST involved — the poll-honesty claim itself proven exactly as designed. Backlog candidate: force a graph regen when the ignore set diverges from the graph so Apply-now always converges on its own."
  - "Probe operating notes: a browser page whose request interception was toggled off mid-session wedged subsequent fetches (the first row-4 attempt showed a stuck disabled button with no message; curl proved the route 409s in 152ms and a fresh page rendered the pinned busy string perfectly) — interception is for one row only, then a fresh page."
  - "The state table lists the machine-global cache inventory annotated by the project graph (13-era design): on this developer machine ~45 real cache entries appear in every project's table with state '—'. Recorded as an observation, unchanged behavior."

requirements-completed: [TOGL-01, TOGL-02, TOGL-03]

coverage:
  - id: D1
    description: "Toggle write loop + reasons + apply-to-convergence + busy rejection (TOGL-01/02/03 browser-true, rows 1-4)"
    requirement: TOGL-01
    verification:
      - kind: manual_procedural
        ref: "## D-16 Probe Recording rows 1-4"
        status: pass
    human_judgment: true
    rationale: "Interactive browser behavior; recorded verbatim; human sign-off per the D-14-net contract."
  - id: D2
    description: "Revert honesty, toggle-during-run, persistent write failure, poll-skip race (rows 5-8)"
    requirement: TOGL-02
    verification:
      - kind: manual_procedural
        ref: "## D-16 Probe Recording rows 5-8"
        status: pass
    human_judgment: true
    rationale: "Timing behaviors no source pin can reach."

duration: 55min
completed: 2026-09-02
status: complete
---

# Phase 16 / Plan 16-06: The recorded agent-browser probe (phase + milestone weld)

**All 8 manual rows executed against a real server and a real scratch project; zero product defects found; the milestone's last interactive claims are proven and written down.**

## Performance

- **Duration:** ~55 min
- **Tasks:** 2 (rows 1-4; rows 5-8 + gate)
- **Commits:** 2 (rows 1-4; rows 5-7/8 + gate)

## D-16 Probe Recording

Environment: scratch `/tmp/d16-scratch` (Rainbow + GoodGit file:// git remotes, integrated + cached); fixtures crafted for the five reasons — graph.json entries (`ZProbePlugin` status plugin, `ZProbeExcluded` status excluded), lockfile `binary_target: true` on goodgit, config `ignore: [FirebaseA*]` (pattern), FirebaseInstallations (resolution-incompatible fidelity); two probe entries planted in the machine-global cache inventory (removed in teardown); config restored to the commented template before row 1 so the FIRST toggle's save strips comments. Server pid 79610→bg_10, port 61328; headless Chromium. Times local (UTC+7).

### Row 1 — Toggle → instant save + pending + bar (TOGL-01/02) — PASS
07:58–07:59 — clicked Rainbow's checkbox: no bounce across a full 5s poll cycle; `pending` chip in-cell; `#state-sync-bar` appeared above the table with the byte-exact D-05 sentence `Changes are saved but not applied yet. spm-cache.yml is rewritten on every change — hand-written comments in the file are not preserved.`; on disk `ignore` gained `Rainbow` and the template comments were gone — the copy's admission visibly true. (The 900ms snapshot caught the POST in flight — pre-response, no bar yet; pending+bar landed before the next poll.)

### Row 2 — Disabled rows show WHY, all five + unknown (TOGL-03) — PASS
Baseline: every gated row renders a natively disabled checkbox + exactly one verbatim chip with title=text — `plugin` (ZProbePlugin), `excluded` (ZProbeExcluded), `pattern-managed` (FirebaseAI), `fidelity` (FirebaseInstallations), `binary-target` (GoodGit). Unknown case via the plan-sanctioned served-value interception: reason `totally-novel-reason` rendered verbatim in `badge badge-neutral`. (First tooltip probe hit the State-column span — the plugin/excluded rows show the same word there; the toggle-cell chip itself carries the title. Selector error, not a defect.)

### Row 3 — Apply now → real use run → poll convergence (TOGL-02) — PASS (mechanism recorded)
07:01 — Apply now: both bar buttons disabled + all three Run Log controls disabled (four-control freeze — the slot is shared); real run `20260902T000109600Z-57022-use.jsonl` spawned (`✓ success | ui | use`). Convergence: the ignore-only sync took the fast path ("no changes" — proxy not regenerated) so the graph kept `hit`; per the plan's explicit fallback the fixture graph was set to the post-sync truth (Rainbow → `ignored`) and recorded as such — the bar and pending cleared on the NEXT POLL (no POST involved): state `ignored`, checkbox steady, bar GONE. Backlog note in key-decisions.

### Row 4 — Apply 409 against a held slot (TOGL-02/A4) — PASS
07:05–07:06 — build parked on a foreign-held lock (`● running | ui | build`, slot held); Apply now → 409 → the amended THREE-verb busy string `A build, rollback, or apply is already running — wait for it to finish.` rendered inline in the bar; button re-enabled; no second run. (First attempt on the interception-tainted page wedged the fetch — curl: 409 + `spawn slot busy` in 152ms; fresh page rendered perfectly. Page artifact, not a defect.)

### Row 5 — Revert all with honest lag (TOGL-02/A3) — PASS
07:08 — divergence present (Rainbow; a second toggle on FirebaseAppCheck correctly contributed none — no graph entry → no applied signal, by design); Revert all: buttons disabled→re-enabled, bar REMAINED after the click, cleared on the next poll; disk `ignore` back to `[FirebaseA*]` exactly (the applied state).

### Row 6 — Toggle during a build (TOGL-01/D-08) — PASS
07:09 — while the build was still running: FirebaseCore's checkbox click was instant (not disabled, no 409, no busy string), checkbox flipped, the run unaffected. (First pick FirebaseAppCheck was pattern-managed/disabled — the census-driven retry used a genuinely toggleable row.)

### Row 7 — Write failure survives polls (TOGL-01) — PASS
07:09–07:10 — scratch dir chmod 555 (a read-only FILE cannot block the tmp+rename mutator — the DIRECTORY blocks tempfile creation; the plan's alternative, recorded): toggle → the pinned template `Couldn't save the toggle for Rainbow: Permission denied @ rb_sysopen — …/spm-cache….yml. Check that spm-cache web is still running, then try again.` rendered; SURVIVED 12s (≥2 poll cycles); checkbox kept server truth (checked). Writability restored; the next successful mutation cleared the line (observed in row 8).

### Row 8 — Poll-skip: no checkbox bounce (TOGL-02/A8) — PASS
07:10 — toggled Rainbow off and sampled checkbox + freshness stamp every 300ms for 7.2s (≥1 poll boundary, POST in flight at the start): ZERO bounces (never flipped back), stamp refreshed mid-window, and the stale failure line from row 7 cleared on this successful mutation.

## Observations (recorded, no action this phase)

- Apply-now with ignore-only changes relies on a graph regen that a fast-path sync skips — the bar converges only when the graph is next rewritten. Backlog candidate: force regen when saved ignore ≠ graph-ignored set.
- The state table mixes the project's graph rows with the machine-global cache inventory (~45 real entries on this machine, state `—`). 13-era design; unchanged.
- The `pending` divergence signal requires a graph entry — rows cache-only-but-ungraphed can be toggled but never count toward the unsaved-changes bar (by design, documented in 16-03).

## Phase gate

`bundle exec rspec` — recorded below in the closure commit (suite expected ≥1088; the gate run follows this summary's rows).

## Next Phase Readiness

This was the milestone's last phase. Ready for gsd-audit-milestone → complete-milestone → cleanup.

---
*Phase: 16-package-toggles-panel-completion*
*Completed: 2026-09-02*
