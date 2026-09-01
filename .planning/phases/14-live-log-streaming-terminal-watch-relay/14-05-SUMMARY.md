---
phase: 14-live-log-streaming-terminal-watch-relay
plan: 05
subsystem: ui
tags: [sse, eventsource, dashboard, watch, run-log, filtering, webrick]

requires:
  - phase: 14-live-log-streaming-terminal-watch-relay
    provides: "14-03 /api/runs + pinned ?run= + SSE weld; 14-04 log.js stream core, card, follow/banner/jump, rail container + clearFilter seam"
provides:
  - "Full-vocabulary anchor rail with jump + filter dimming and banner piercing (D-07..D-10)"
  - "Unconditional auto-switch with one-slot previous-run notice and single loadRun(?run=) path (D-04)"
  - "Recent-runs dropdown over /api/runs (per-open fresh fetch, D-12)"
  - "Verbatim notice + lock-wait rendering (D-05/A11)"
  - "D-14 recorded agent-browser probe evidence for all 7 manual rows (LOGS-02/03/04/05)"
affects: [15-ui-build-controls, 16-package-toggles-panel-completion]

actuals:
  tokens: 54700
  tasks: 3
  commits: 7

tech-stack:
  added: []
  patterns:
    - "Thread-keyed [thread, stream] partial buffers for pair-atomic concurrent writers (WR-01 layer 2 — found live by the probe-adjacent baseline run)"
    - "Dim-not-hide filtering as pure CSS-class toggling over the render ring (positions stable under any filter)"

key-files:
  created: []
  modified:
    - lib/spm_cache/web/assets/log.js
    - lib/spm_cache/web/assets/index.html
    - lib/spm_cache/web/assets/styles.css
    - spec/web_frontend_spec.rb
    - lib/spm_cache/core/run_log.rb
    - .planning/phases/14-live-log-streaming-terminal-watch-relay/14-VALIDATION.md
    - .planning/phases/14-live-log-streaming-terminal-watch-relay/14-UI-SPEC.md
    - .planning/phases/14-live-log-streaming-terminal-watch-relay/14-PATTERNS.md

key-decisions:
  - "Probe catch #1 (207133d): the UI-SPEC card-copy template and the relative-time vocabulary contradicted each other — 'completed {relative} ago' doubled the ago ('12 hr ago ago' live, 'Sep 1, 02:49 ago' at >=24h). {relative} keeps its own phrasing; template, spec pin, and both UI-SPEC rows amended."
  - "Probe catch #2 (3d2481a): statusKey compared the bare word 'interrupted' while the server vocabulary (hello + /api/runs) carries the FULL CP14 phrase 'interrupted — exit unknown' — a pid-dead run's card rendered '● running' and the interrupt banner never fired. Both spellings map to interrupted; phrase-aware pin added."
  - "Row-3 browser shape under per-launch token rotation: kill -9 + restart on the same port makes the old tab's auto-retry hit 401 → CLOSED → the A6 locked page (correct terminal posture, asserted); reopening bootstraps the new token and replays byte-exact. The Last-Event-ID resume mechanism is proven separately live on the wire (curl reconnect: 0 duplicated, exact tail continuation) and by the 14-03 integration rows."
  - "Scratch-project probe fixture: local PATH packages are dropped from the graph by lockfile sync (Package.resolved never pins them; the umbrella cannot materialize them) — the failing-package fixture uses file:// GIT remotes (GoodGit compiles, ZBrokenGit carries a deliberate type error), which pin, checkout, and build like real remotes."
  - "Environment: long-idle nohup+disown background processes get silently reaped on this machine (empty-log SIGKILLs killed a parked server and run mid-probe) — the bash tool's async tracked jobs hold foreground processes reliably for servers/watchers/runs."

patterns-established:
  - "Anchor/filter engine: SEG WeakMap per line element + anchors registry; package filter matches package_start..package_end inclusive, phase filter marker→next marker/package_start; pre-anchor lines dim under any filter; active chip = accent badge + aria-pressed; clicking active chip clears with view staying put"
  - "loadRun(name): the ONE replay path — closes EventSource, reconnects with '?run=' + encodeURIComponent(name); switch notice's {run-id} control and every dropdown selection funnel through it"

requirements-completed: [LOGS-02, LOGS-04, LOGS-05]

coverage:
  - id: D1
    description: "Anchor rail (full frozen D-04 vocabulary, dedupe-by-name), jump + filter dimming, filter pill, banner piercing through the clearFilter seam"
    requirement: LOGS-02
    verification:
      - kind: unit
        ref: "spec/web_frontend_spec.rb — anchor/filter/pierce describes (10 rows), Task 1"
        status: pass
    human_judgment: false
  - id: D2
    description: "Auto-switch with one-slot previous-run notice, recent-runs dropdown over /api/runs, verbatim notice + lock-wait rendering"
    requirement: LOGS-04
    verification:
      - kind: unit
        ref: "spec/web_frontend_spec.rb — switch/dropdown/notice describes (12 rows), Task 2"
        status: pass
    human_judgment: false
  - id: D3
    description: "D-14 recorded agent-browser streaming probe — all 7 manual-verification rows executed against real servers and real CLI runs"
    requirement: LOGS-05
    verification:
      - kind: manual_procedural
        ref: "## D-14 Probe Recording below — per-row commands, timestamps, observed outcomes"
        status: pass
    human_judgment: true
    rationale: "Browser-visible streaming behavior; agent-browser (headless Chromium) evidence recorded verbatim per row, but final sign-off is a human judgment per D-14's own contract — the same net that caught G-13-1 and both probe catches this session."

duration: 95min
completed: 2026-09-01
status: complete
---

# Phase 14 / Plan 14-05: Frontend completion + the D-14 recorded probe (phase weld)

**Anchor rail with jump/filter-dim/pierce, unconditional auto-switch with previous-run notice, recent-runs dropdown, verbatim notices — welded shut by the D-14 agent-browser probe, which passed all 7 manual rows and caught two real frontend defects on the way.**

## Performance

- **Duration:** ~95 min (Tasks 1–2 via gsd-executor ~27 min; Task 3 probe + fixes + recording ~68 min)
- **Started:** 2026-09-01T14:55Z
- **Completed:** 2026-09-01T16:30Z
- **Tasks:** 3 (2 TDD + 1 recorded probe)
- **Files modified:** 8 (+ probe fixtures under /tmp, removed)

## Accomplishments
- Anchor rail over the full frozen Phase-12 vocabulary; chips render as anchors arrive; jump + filter that DIMS (never hides) with stable positions; failure banner pierces every filter state and the jump clears the filter first
- Auto-switch is unconditional (drops ?run= pins, closes the EventSource, reconnects unpinned); ONE notice slot, latest wins; {run-id} sourced from the previously-DISPLAYED run (view state), proven live in the strict divergence case
- Recent-runs dropdown: per-open fresh /api/runs fetch, glyph vocabulary, viewing suffix, failure copy, ONE loadRun path
- All 7 D-14 manual rows executed and recorded (below); two probe-caught defects fixed spec-first
- Baseline hardening before wave 3: a loaded full-suite run exposed WR-01's residual call-granularity race — partial buffers are now [thread, stream]-keyed (`a5b41fa`)

## Task Commits

1. **Task 1 RED: anchor/filter/pierce specs (10 examples)** — `0d04398` (test)
2. **Task 1 GREEN: anchor rail + jump/filter dimming + banner piercing** — `e638c07` (feat)
3. **Task 2 RED: switch/dropdown/notice specs (12 examples)** — `2ed13c9` (test)
4. **Task 2 GREEN: auto-switch + recent-runs dropdown + notice rendering** — `d41fc71` (feat)
5. **Probe catch #1: completed-row doubled 'ago'** — `207133d` (fix)
6. **Probe catch #2: statusKey CP14 phrase** — `3d2481a` (fix)
7. **Task 3: D-14 recorded probe + manual table ticks** — this commit (test/docs)

## Files Created/Modified
- `lib/spm_cache/web/assets/log.js` — anchor model + registry + segment engine, dim/pill/pierce, switch/notice/loadRun, dropdown controller
- `lib/spm_cache/web/assets/index.html` — Recent runs label + native select in the reserved header slot
- `lib/spm_cache/web/assets/styles.css` — chip/dim/pill/dropdown/switch rules on existing tokens
- `spec/web_frontend_spec.rb` — 22 plan rows + 2 probe-catch rows
- `lib/spm_cache/core/run_log.rb` — thread-keyed partial buffers (pre-probe baseline fix, `a5b41fa`)
- `14-VALIDATION.md` — manual table ticked with dates + evidence

## D-14 Probe Recording

Environment: reference project `/Users/ddphuong/Projects/next-labs/stress-ai/ios-stress-app/StressMonitor` (real, cached); scratch project `/tmp/d14-scratch` (generated Xcode project; Rainbow remote + GoodGit/ZBrokenGit file:// git remotes) for the failing-run rows. Servers: `spm-cache web --no-open --port=0` (A: StressMonitor, ports 62640→62774 across restarts) and `--port=62800` (B: scratch). Browser: headless Chromium (browser tool), tabs opened at the root URL (302 token bootstrap). All timestamps UTC.

### Row 1 — Live render of a terminal-started run (LOGS-02/04) — PASS
- 15:22 boot A (pid 57498, port 62640). 15:28 lock held on `.spm-cache-build.lock` (holder pid 64112); `spm-cache use` started → run `20260901T152823620Z-64142-use.jsonl` streamed `── detect ──` / `── integrate ──` dividers, "No changes detected. Proxy package up to date.", then parked at "Waiting for build lock…" — all rendered live in tab 1 with card `● running | terminal | use`, chips `detect`,`integrate`, follow pinned at tail. After lock release the run completed (run_end 0): card flipped `✓ success`, "completed just now" row, follow tracked to "Done! Cache integrated into StressMonitor.xcodeproj"; rows grew 10→14 live. Second observation pass (server 73863, port 62774): scratch build run `20260901T155801025Z-2699-build.jsonl` rendered live mid-build with chips `build`,`GoodGit` and xcodebuild lines streaming.

### Row 2 — Mid-run replay in a second tab (LOGS-03) — PASS
- 15:28–15:29 with run 64142 parked: second tab opened at root → replayed the run from its first line (banner/`Using project:` header first), same identity card, follow engaged at the tail (viewport at bottom, last line the lock-wait line), correctly NO switch notice (no previously-displayed run in that tab).

### Row 3 — Reconnect without loss or duplication (LOGS-03) — PASS
- 15:29 `kill -9` server A mid-run; restarted on the same port (new launch token). Old tab: transient '↻ reconnecting…' then auto-retry hit 401 (rotated token) → CLOSED → A6 locked page "This page's access token is no longer valid. Restart spm-cache web and open the URL it prints." (correct terminal posture, asserted). Fresh reopen: full replay of parked run `20260901T153231074Z-73859` — DOM line elements == renderable disk entries exactly (10/10; multi-line texts within elements), first/last/lock-line indices matching, zero loss, zero duplication. Wire-level: `curl -sN -D -` first connect → `HTTP/1.1 200`, `Content-Type: text/event-stream`, `Cache-Control: no-store`, in-stream `retry: 3000`, hello + 38 id-bearing entries; reconnect with `Last-Event-ID: <last composite id>` → hello + 0 entries (byte-exact tail resume, no dupes). Shutdown: `kill -INT` with two open SSE streams → process gone <3 s, marker cleared (WEB-03 sentinel holds; job completed cleanly).

### Row 4 — Failure surfacing (LOGS-05/D-03) — PASS
- Scratch run `20260901T155132497Z-93453` (lockfile-missing failure, exit 1): card `✗ failed | terminal | use`, sticky banner `Run failed — exit status 1` + `Jump to first error`, ✗-prefixed err lines. Rich pass on `20260901T155801025Z-2699-build` (ZBrokenGit compile failure, 83 err lines, `** BUILD FAILED **`): same banner shape, jump landed on the first retained `log-err` line (`✗ ** BUILD FAILED **`, 18 err lines in view — the DOM's earliest err had been ring-evicted per the documented degradation chain).

### Row 5 — Filter/banner interaction (D-09/D-10) — PASS
- On the failing build run: clicked the `GoodGit` chip → pill `filtered: GoodGit`, chip aria-pressed=true + accent class, **357 of 500 lines dimmed via `log-dim`, totalLines unchanged at 500 — nothing removed (A5)**; failure was in ZBrokenGit (foreign package) yet the banner remained visible (pierce). `Jump to first error` under the active filter: filter CLEARED first (pill gone, 0 dimmed, chips reverted) then jumped into the error region. Banner persisted throughout.

### Row 6 — Watch-cycle relay + auto-switch from a pinned run (LOGS-04/D-04) — PASS
- 15:38 watch daemon started (pid 80197): initial sync produced cycle `20260901T153909827Z`; trigger produced cycle `20260901T154426076Z` (both run_end 0, dropdown `✓ watch` entries). Tab pinned cycle 1 via the dropdown (card showed trigger badge `watch`, pinned run id, `viewing` suffix, URL clean). Triggered cycle 3 (`20260901T154602186Z`): the PINNED connection received the switch broadcast, dropped the pin, reconnected unpinned — card flipped to cycle 3's id and the notice read **"switched to new run — previous: 20260901T153909827Z-80197-watch.jsonl"** — naming the PINNED (previously-displayed) run, not the event's `previous` field (which was cycle 2 `154426`): the strict divergence case, decided by view state exactly as pinned.

### Row 7 — Lock-wait attribution (D-05/CP10) — PASS
- With the build lock thread-held, the blocked `use` run's stream rendered "Waiting for build lock…" VERBATIM as a plain out line — no badge, no special styling (source pin: zero lock-wait special-casing in log.js). Held-lock state also surfaced in hello's `lock.state`.

### Probe-caught defects (fixed spec-first, both browser-re-verified)
1. `207133d` — card completed row doubled the "ago" phrasing (UI-SPEC template vs vocabulary contradiction). Live before: "completed 12 hr ago ago"; after: "completed 12 hr ago".
2. `3d2481a` — statusKey missed the full CP14 phrase 'interrupted — exit unknown' → pid-dead run rendered `● running` with no banner. Live after (pinned reaped run 64142): card `! interrupted — exit unknown`, banner "Run interrupted — exit unknown." + jump.

### Observations (no action in this phase — recorded for the backlog)
- `Watcher#resolve_watched_files` globs `**/project.pbxproj` and picks the first match; StressMonitor contains a NESTED duplicate `.xcodeproj` whose pbxproj wins, so touches to the real top-level pbxproj do not trigger watch cycles on this project. Pre-existing (Plan 12-05 wrapped cycles; Watcher untouched). Worth a dedicated fix + spec if watch misses are reported in the field.
- Local PATH packages are dropped from the spm-cache graph (lockfile sync cannot pin them; the umbrella cannot materialize their checkouts — "[warn] No checkout found; legacy fallback"). Pre-existing posture; probe worked around it with file:// git remotes.

## Decisions Made
See key-decisions above.

## Deviations from Plan

### Auto-fixed Issues

**1. [Owning-module rule] Doubled "ago" in the card completed row**
- **Found during:** Task 3 (probe row 1)
- **Issue:** UI-SPEC copy template `{relative} ago` contradicted the vocabulary's already-ago forms
- **Fix:** drop the trailing literal; amend pin + both UI-SPEC rows
- **Committed in:** `207133d`

**2. [Owning-module rule] statusKey missed the full CP14 phrase**
- **Found during:** Task 3 (interrupt-shape spot check)
- **Issue:** bare `'interrupted'` compare let the server phrase fall through to `running`
- **Fix:** map both spellings; phrase-aware pin added
- **Committed in:** `3d2481a`

**3. [Baseline gate] WR-01 residual call-granularity race (pre-plan)**
- **Found during:** pre-wave-3 baseline (loaded full-suite run failed the WR-01 example with every lock held)
- **Issue:** the buffer mutex serializes each CALL; a writer's partial+completing chunks are two calls — a second writer interleaving between them merges/splits lines
- **Fix:** `[thread, stream]`-keyed partial buffers + deterministic Queue-forced interleave spec; 30×+15× hammers green
- **Committed in:** `a5b41fa`

---

**Total deviations:** 3 auto-fixed (2 owning-module probe catches, 1 baseline-gate fix)
**Impact on plan:** All necessary for correctness. No scope creep.

## Issues Encountered
- Long-idle nohup+disown background processes are silently reaped on this machine (a parked server and run died mid-probe with empty logs) — switched to the bash tool's tracked async jobs holding foreground processes; all subsequent actors stayed up.
- The watch trigger initially appeared dead: the project's nested duplicate `.xcodeproj` wins the watcher's pbxproj glob (observation recorded above); touching the full watched set fires cycles normally.

## User Setup Required
None.

## Next Phase Readiness
- The log panel is feature-complete per 14-UI-SPEC; Phase 15's build controls ride the same stream module and the reserved UI badge without edits to these surfaces.
- Full suite green at phase gate (see VALIDATION); no blockers.

---
*Phase: 14-live-log-streaming-terminal-watch-relay*
*Completed: 2026-09-01*
