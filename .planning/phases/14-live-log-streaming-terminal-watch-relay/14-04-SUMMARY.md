---
phase: 14-live-log-streaming-terminal-watch-relay
plan: 04
subsystem: web
tags: [web, frontend, sse, log-panel, eventsource, tdd, LOGS-02, LOGS-03]

requires:
  - phase: 14-live-log-streaming-terminal-watch-relay plan 01
    provides: the SSE wire contract — named events hello/entry/switch/notice, entry ids '<run>:<offset>', hello {run, header, status} (+14-03's lock/now), notices {message}, the 200-always/CLOSED-is-permanent reconnect semantics
  - phase: 13-server-skeleton-read-only-dashboard plan 03
    provides: the app.js idiom set (el()/textContent discipline, sessionStorage token key, renderEmpty/panel-error postures, boot/bail-out guard), the served-asset conventions, and the G-13-1 relative-ref rule
  - phase: 13-server-skeleton-read-only-dashboard plan 05
    provides: the browser-honest asset-ref scan in spec/web_integration_spec.rb — the net that the new assets/log.js ref must resolve through
provides:
  - assets/log.js — the dashboard's second ES module: EventSource lifecycle, D-06 identity card, D-13 three-branch cold load, T-12-01 line taxonomy, D-02 500-line ring with head elision notice, D-01 follow/pause with the counted pill, D-03/CP14 banners with the jump chain, connection pill + the CLOSED token-invalid terminal page, server-stamp-only relative times
  - the Run Log panel skeleton in index.html (FIRST per A1): a11y-complete (role=log viewport, aria-live card/pill, role=alert banner slot, Phases/Packages rail, overlay slot, runs-slot for 14-05) + the relative assets/log.js module tag after app.js
  - the log-section CSS on the existing token sheet (zero new tokens; the .cmd declaration remains the sheet's ONE accent-text home, shared with .log-live per A3)
  - 30 source-contract examples in spec/web_frontend_spec.rb gating every pinned copy string, the XSS/date/offline/timer prohibitions, the DOM skeleton, and the follow/banner/jump mechanics
affects:
  - 14-05 (consumes the DOM ids, COPY strings, resetForRun/clearFilter seams, the #log-switch + #runs-slot containers, and the dividers-as-anchor-targets contract this plan ships)
  - Phase 15 (the verbatim trigger render + reserved neutral 'UI' badge path; UI-triggered runs ride this module unchanged)

actuals:
  tokens: 46700   # chars/4 over the realized diff (988 added + 3 removed across the 4 commits); plan estimated 38000 at confidence low
  tasks: 2
  commits: 4

tech-stack:
  added: []   # vanilla ES module + hand-rolled CSS on the existing sheet; zero npm, zero CDN, zero build step (locked decision)
  patterns:
    - "Accent-text budget under a count gate: extending accent to the liveness surfaces (A3) without touching the Phase 13 eq(1) scan means widening the ONE existing declaration's selector group (.cmd, .log-live) — a new rule would break the old pin, a second token would break the sheet's zero-new-tokens contract"
    - "Replay-completion detection without timers or a client clock (both banned by spec gates): the replay/queue boundary is invisible on the wire, so engagement is event-driven — a bottom-stick check on append plus any-scroll-exits-passive-replay; the pill's !replaying guard keeps it a live-tail affordance only"
    - "Task-scoped copy deferral so the next task's RED is achievable: the paused/failed/interrupted banner strings and the .log-pill-btn/focus CSS belong to Task 2's behaviors, so they land in Task 2's GREEN — shipping them early would pass Task 2's RED examples (the 14-01 Task-2 precedent, applied forward)"

key-files:
  created:
    - lib/spm_cache/web/assets/log.js
    - .planning/phases/14-live-log-streaming-terminal-watch-relay/14-04-SUMMARY.md
  modified:
    - lib/spm_cache/web/assets/index.html
    - lib/spm_cache/web/assets/styles.css
    - spec/web_frontend_spec.rb
    - spec/web_integration_spec.rb

key-decisions:
  - "hello 'completed' renders the success vocabulary provisionally and the replayed run_end entry refines it to ✗ failed + banner (or confirms ✓ success) — the exit status lives ONLY on the run_end JSONL line, hello carries just the derived status; a missing run_end never derives completion (the partial-state truth)"
  - "Config renders '—' today: no wire surface attributes a build config in Phase 14 (the header carries none and 14-03's runs payload serves none), so A2's fallback branch is the live path — log.js reads header.config first, keeping the Config debug rendering forward-compatible without hardcoding it"
  - "Ring eviction is tracked against the jump anchor: evicting the element that IS firstErrEl sets errEvicted, and jumpTarget degrades first-err → oldest-retained-line (errEvicted) → first retained err (lost-anchor defense) → final line → top — never a dead control"
  - "The empty-state copy renders inside the stream viewport: the rail group labels stay (UI-SPEC 'always rendered'), the card/banner/pills are absent, and the connection pill remains the only live control — 'the empty copy owns the panel' with zero contradictory rows"
  - "The switch handler ships as the resetForRun(data.run, { followOn: true }) seam: ring/banner/filter state resets, the new file's replayed run_start header rebuilds the card, follow drops the viewer at the new tail (D-04) — the switch-notice BAR stays a hidden 14-05 container, exactly the plan's 'containers and event wiring, not their behaviors' split"
  - "Cross-agent shared-file discipline: the one-line 'assets/log.js' => 'application/javascript' addition to spec/web_integration_spec.rb's content_types map (required because my index.html change makes the per-ref fetch raise KeyError on the new ref) was verified diff-isolated and committed promptly with my Task-1 GREEN per the sibling's coordination request — no other line of their files touched"

requirements-completed: [LOGS-02, LOGS-03]

coverage:
  - id: LOGS-02
    description: "Browser shows a single live log stream with per-package anchors"
    verification:
      - kind: integration
        ref: "spec/web_frontend_spec.rb 'log.js + Run Log panel (Plan 14-04)' — line taxonomy (out verbatim/err ✗-prefixed/── name ── dividers/no-line events/unknown keys ignored), D-02 ring + elision, D-01 follow/pause pill, D-03/CP14 banners + jump chain, D-06 card — 30 examples green"
        status: pass
      - kind: manual-pending
        ref: "Anchor rail chips + filter/piercing are 14-05's surfaces (containers shipped here); browser-visible behavior exercised by the D-14 recorded probe in 14-05 Task 3 — the repo has no JS runtime, source-contract gates are the automated half"
        status: pending
  - id: LOGS-03
    description: "Loading mid-build replays from start; reconnects resume without lost lines"
    verification:
      - kind: integration
        ref: "spec/web_frontend_spec.rb cold-load rows — live-run replay with follow-at-completion state, finished-run end-state card + Started/completed time row, empty-state branch; connection pill states + the CLOSED token-invalid terminal page (browser Last-Event-ID resume is engine-handled; 14-01 pins the server half)"
        status: pass
      - kind: manual-pending
        ref: "Reconnect-without-loss in a real browser (D-14 probe, 14-05)"
        status: pending

duration: 55min
completed: 2026-09-01
status: complete
---

# Phase 14 Plan 04: Frontend stream core — log.js module, identity card, follow/ring, banners, cold load Summary

**The Run Log panel is live end-to-end at the source-contract level: a second vanilla ES module (assets/log.js) consumes the 14-01 wire contract — EventSource on /api/events?token=, named hello/entry/switch/notice handlers, the D-06 identity card with verbatim trigger rendering and server-stamp-only relative times, the three-branch D-13 cold load, T-12-01 line taxonomy (out verbatim, err ✗-prefixed, ── name ── dividers, no-line events, unknown keys ignored), the D-02 500-line ring with its head elision notice, D-01 follow/pause with the counted one-button pill, D-03 failure + CP14 interrupt banners with a degradation-honest jump chain, and the CLOSED token-invalid terminal page — all textContent-only (zero markup-writing APIs), timer-free, offline, and pinned by 30 new examples; app.js untouched, the token sheet grew zero tokens, and the full suite runs 867 examples green.**

## Performance

- **Duration:** ~55 min (wall clock across the wave, interleaved with the 14-03 sibling on the same tree)
- **Tasks:** 2 (Task 1 RED→GREEN, Task 2 RED→GREEN)
- **Commits:** 4 (`c579bd6`/`845eadb`, `56b1574`/`8223ede`)
- **Files:** 1 created (log.js, 500 lines), 3 modified (index.html, styles.css, spec/web_frontend_spec.rb) + 1 shared-file one-liner (spec/web_integration_spec.rb content_types map)

## What Shipped vs Plan

### Task 1 — log.js + panel skeleton (c579bd6 RED → 845eadb GREEN)
RED exactly as planned: **20 examples, 20 failures** (87+3 total, every failure a new row — log.js absent raised ENOENT, the skeleton/styles rows failed on missing strings, the served row 404'd). GREEN: log.js (token read → EventSource → pill state machine; hello handler building the D-06 card and driving the cold-load branches incl. reconnect re-derivation on the same run; the entry dispatcher keyed ONLY on the parsed event field; the ring with head elision), index.html (Run Log panel FIRST with the a11y skeleton + the relative assets/log.js tag after app.js), styles.css (log section on existing tokens + the .cmd/.log-live accent group), and the integration content_types one-liner.

### Task 2 — follow/pill/banners/jump/a11y (56b1574 RED → 8223ede GREEN)
RED exactly as planned: **10 examples, 10 failures**. GREEN: the follow state machine (instant stick, upward-scroll disengage, bottom-stick engagement with the replaying gate so the pill never shows mid-replay), the pause pill (one native button, whole label, uncapped live counter, resume path), both banner variants with the Jump to first error button and the clearFilter()-before-jump seam, card flip on run_end, the jump chain over the ring with anchor-eviction tracking, the dead/alive() teardown guard on every handler, and the .log-pill-btn + focus-visible CSS.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Spec mechanics] My own 480px count pin was written wrong**
- **Found during:** Task 1 GREEN
- **Issue:** The pin expected `height: 480px` ×2 (graph + viewport) but the anchor rail is also fixed 480px — the honest count is 3.
- **Fix:** Corrected MY new example to eq(3) with the rail named in the comment; no pre-existing row touched.
- **Commit:** 845eadb

**2. [Rule 1 - Bug] A Task-1 CSS comment contained the literal string `max-height`**
- **Issue:** The Phase 13 table pin (`not_to include('max-height')`) scans the whole stylesheet — the comment "(fixed height — never max-height)" tripped it.
- **Fix:** Reworded the comment; zero declaration changes.
- **Commit:** 845eadb

### Plan-Internal Ambiguities (documented, not silently absorbed)

- **Replay-completion detection:** the plan pins "follow engages at replay completion" but bans every tool that could detect the replay/queue boundary (no timers, no client clock — both spec-gated). Resolved event-driven: a bottom-stick check on every append engages follow when the viewport is at the tail (short files engage immediately; a scrolled-down viewer engages on the next line), and ANY scroll event exits passive replay mode so the pill becomes available the moment the user interacts. The `!replaying` guard keeps the pill hidden mid-replay for the passive viewer, per the UI-SPEC.
- **hello 'completed' exit state:** the exit status exists only on the replayed run_end line; hello carries the derived status word only. The card renders success provisionally at hello and the run_end entry flips it (typically within the same burst). Never the reverse (missing run_end never derives completion).
- **Config slot (A2):** rendered `Config —` today — no Phase 14 wire surface attributes a build config; log.js reads `header.config` so A2's "Config debug" rendering lights up when a future header/read-model carries it, without hardcoding.
- **Task-split copy deferral:** COPY.paused/failedBanner/interruptedBanner/jumpToError and the .log-pill-btn/focus-visible CSS belong to Task 2's behaviors and landed in Task 2's GREEN — shipping them in Task 1 would have passed Task 2's RED examples (the 14-01 Task-2 count-reconciliation precedent, applied forward).

**Total deviations:** 2 auto-fixed (both Rule 1, both in files this plan created). **Impact:** none on the pinned copy, prohibitions, or the 14-05 contract surfaces.

## Threat Flags

All register dispositions honored; no surface beyond the plan's threat model was introduced:

| Flag | File | Description |
|------|------|-------------|
| threat_mitigated: T-14-16 | lib/spm_cache/web/assets/log.js | el()/textContent-only rendering — the four markup-writing APIs are spec-absent; rendering keyed only on the parsed 'event' field; package names, run ids, argv, and notice messages flow through the same textContent path |
| threat_mitigated: T-14-17 | lib/spm_cache/web/assets/log.js | `Date.now` absent by spec gate; serverNowTs derives solely from the hello 'now' stamp, re-derived per hello; relative vocabulary pinned |
| threat_mitigated: T-14-18 | lib/spm_cache/web/assets/log.js | The token rides only the EventSource query param from sessionStorage; never rendered, never logged; app.js's URL cleaning has already run (module order) |
| threat_mitigated: T-14-19 | lib/spm_cache/web/assets/log.js | D-02 ring: newest 500 line elements + counted plain-text head notice; reload replays the full run from disk |
| threat_mitigated: T-14-20 | lib/spm_cache/web/assets/log.js | Sibling module with its own failure domain: zero setTimeout/fetch in log.js (spec-gated), app.js byte-untouched, shared state limited to sessionStorage; the dead/alive() guard stops every handler once panels are replaced |

## Known Stubs

None. Every named component (connection pill state machine, hello/cold-load branches, entry dispatcher, ring + elision, card builder, time row, follow/pause, banners, jump chain, teardown guard) is a complete real implementation with spec coverage. The 14-05 surfaces (anchor chips, filter/piercing UI, switch-notice bar, runs dropdown) are intentional CONTAINERS and hook points per this plan's own scope split — #log-switch, #runs-slot, rail group containers, activeFilter/clearFilter(), and the resetForRun seam — not stubs of this plan's behaviors. No placeholder markers (TODO/FIXME/…) in any touched file (grep-verified).

## Verification

- **Task 1 RED:** `bundle exec rspec spec/web_frontend_spec.rb` → **90 examples, 20 failures** (all the new rows)
- **Task 1 GREEN:** `bundle exec rspec spec/web_frontend_spec.rb spec/web_assets_spec.rb` → **102 examples, 0 failures**; `bundle exec rspec spec/web_integration_spec.rb` → **45 examples, 0 failures** (the new assets/log.js ref resolves browser-honestly through the /assets/* arm)
- **Task 2 RED:** same file → **100 examples, 10 failures** (all the new rows)
- **Task 2 GREEN:** same file → **100 examples, 0 failures**; with assets spec → **112 examples, 0 failures**
- **Wave gate (full suite):** `bundle exec rspec` → **867 examples, 0 failures** (baseline before this plan: 823; +30 mine, +14 the 14-03 sibling's rows)
- **JS syntax:** `node --check lib/spm_cache/web/assets/log.js` → clean (the repo has no JS test runtime; this is the mechanical floor under the source-contract gates)
- Task commits: **c579bd6 / 845eadb / 56b1574 / 8223ede**

## Self-Check: PASSED

log.js exists on disk (500 lines); index.html carries the panel FIRST and the relative module tag; all four task commits present in history on gsd/v0.5.0-web-interface; prohibition spot-checks green — zero markup-writing APIs, zero client-clock reads, zero timers, zero scheme-absolute/CDN refs, no color-only status (every color pairs a glyph, the card pairs a word), app.js byte-identical, styles.css declares zero new tokens and keeps exactly one accent-text declaration.

## EXECUTION COMPLETE — 14-04
