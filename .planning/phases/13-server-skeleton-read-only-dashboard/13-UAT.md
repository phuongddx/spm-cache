---
status: partial
phase: 13-Server Skeleton + Read-Only Dashboard
source: [13-VERIFICATION.md, 13-VALIDATION.md]
started: 2026-09-01T07:20:00Z
updated: 2026-09-01T07:37:11Z
---

## Current Test

[testing complete for automatable items — 2 items await user judgment, see Gaps/notes]

## Tests

### 1. Full dashboard walkthrough (3 panels) — real browser, real project
expected: With a real cached project (`stress-ai/ios-stress-app/StressMonitor`, live cache state): state table renders sizes/badges/◆ macros, Run Doctor produces ✓/!/✗ rows + ↳ hints + summary + "Cached — generated at" stamp, graph renders node colors/diamond macros/legend. Per 13-UI-SPEC.
result: issue
severity: blocker
reported: "Orchestrator-driven real headless-Chromium session against a live `spm-cache web` boot (real project, real cache, port 60902). index.html references its own sibling assets as bare relative paths (`href=\"styles.css\"`, `src=\"cytoscape.min.js\"`, `src=\"app.js\"` — index.html:7,56,57), which resolve against the served document root `/`. router.rb only serves static files under `/assets/*` (router.rb:76) — everything else 404s. Verified live: `GET /app.js` → 404, `GET /styles.css` → 404, `GET /cytoscape.min.js` → 404, `GET /assets/app.js` → 200. Console showed three 404 resource-load errors on page load. Because app.js never executes, the DOM never advances past the static `Loading…` placeholders baked into index.html — no state table, no doctor rows, no graph, for every user, every load, unconditionally. Root cause: 13-03 authored index.html with un-prefixed asset refs while router.rb's asset route (same commit's sibling file) requires the `/assets/` prefix — never caught because specs pin `/assets/app.js` served bytes directly (never asserting index.html's own href/src resolve there) and the repo has no JS runtime in CI to observe the runtime 404s. This also transitively breaks the token-bootstrap and auto-poll behavior (Tests 2, 3 below) since neither can run without app.js loading."

### 2. Token bootstrap (URL cleanup, sessionStorage, never-in-DOM)
expected: Address bar cleans to `/` via `history.replaceState` before first render; token stored in `sessionStorage`, never rendered in the DOM; every fetch sends `X-SPM-Token`.
result: skipped
reason: "Blocked by Test 1 (G-13-1) — app.js never loads, so its bootstrap code (app.js:10-16) never executes. URL stayed `?token=...` unclean in my live session; sessionStorage stayed empty. Not a separate defect — same root cause, will be re-verified once G-13-1 is fixed."

### 3. Auto-poll + error resilience
expected: Header stamp shows "Updated … · auto-refresh {N}s" and advances every 5s; a failed poll keeps last rows and the loop keeps running.
result: skipped
reason: "Blocked by Test 1 (G-13-1) — no polling loop ever starts because app.js never loads. Will re-verify once G-13-1 is fixed."

### 4. True-offline load
expected: Disconnect the machine from the network, hard-reload — everything renders (all assets local, zero blocked-external-request console errors).
result: skipped
reason: "Loopback traffic (127.0.0.1) is unaffected by network disconnect, so this test cannot distinguish online/offline today — and is moot regardless while G-13-1 makes every load fail identically online or offline. Zero external/CDN references were independently grep-confirmed (0 matches across index.html/app.js/styles.css), so the offline *architecture* is sound; only the routing wiring is broken. Re-verify after G-13-1 fix, ideally with the user's real network-disconnect test since that's a physical-layer check I cannot perform from this session."

### 5. Real-TTY Ctrl-C exit
expected: Ctrl-C on a foreground `spm-cache web` exits 0 promptly; `.spm-cache/web/server.json` is removed.
result: pass
evidence: "Orchestrator-driven live process test (not a real TTY, but the same signal path): booted `spm-cache web --no-open --port=0` against the reference project (pid 81547), confirmed marker existed, sent real `SIGINT` via `kill -INT`. Process exited within 1.5s, marker file `.spm-cache/web/server.json` was gone afterward, `ps -p <pid>` confirmed no process. Matches the automated `web_signals_spec.rb` real-subprocess proof already in 13-VERIFICATION.md truth 2."

### 6. Judgment-tier prohibitions (stored-XSS defense, no-second-mutex)
expected: (a) zero innerHTML/insertAdjacentHTML/document.write in app.js — all dynamic text via textContent/createElement. (b) web layer's only writes are its own marker + boot lock; no second project mutex.
result: pass
evidence: "Re-confirmed via direct grep this session: zero innerHTML/insertAdjacentHTML/document.write/outerHTML occurrences in app.js; el()/textContent is the only DOM-write path (read app.js in full). Write-surface audit: only Marker (server.json) and .boot.lock live under the web's own `.spm-cache/web/` dir; ReadModels are pure readers. Matches 13-VERIFICATION.md's SUBSTANTIALLY HONORED judgment verdict — accepted as pass, not re-litigated."

## Summary

total: 6
passed: 2
issues: 1
pending: 0
skipped: 3
blocked: 0

## Gaps

- gap_id: G-13-1
  truth: "Dashboard renders per 13-UI-SPEC in a real browser: state table, doctor panel, graph panel, token bootstrap URL cleanup, and auto-poll all function"
  status: failed
  reason: "index.html's asset references (styles.css, cytoscape.min.js, app.js) are bare relative paths resolving to `/{asset}` from document root `/`, but router.rb only serves static files under `/assets/*`. Every first load 404s all three sibling assets — the entire client-side dashboard (rendering, token bootstrap, auto-polling) never activates for any user."
  severity: blocker
  test: 1
  artifacts: ["lib/spm_cache/web/assets/index.html"]
  missing: []
  fix_hint: "Prefix index.html's href/src values with `assets/` (relative, matching how the page is served at `/`) or `/assets/` (absolute) so they resolve through router.rb's existing `/assets/*` route. Add a regression spec that boots the real server and asserts every asset reference parsed out of the served index.html itself resolves 200 through the router — the existing specs assert `/assets/app.js` bytes directly and never parse index.html's own refs, which is exactly the blind spot that let this ship."

## Notes for Human Follow-Up (not gaps — judgment/observation items)

- **Default-browser auto-open on a fresh start (no `--no-open`):** not testable from this headless session without popping a real GUI browser window on the user's desktop unprompted. Code trace + `web_lifecycle_spec.rb` ordering spec already prove `StartCallback` fires only after the listener binds; genuine real-browser-pops-open observation still needs the user, ideally re-run after G-13-1 is fixed (currently pointless — the page would 404 on load anyway).
- **WR-02 live-instance reuse UX (carried decision from 13-VERIFICATION.md human item 5):** product judgment call, not a pass/fail test — a second `spm-cache web` launch blocks silently on the boot lock for the first server's entire lifetime, then boots a NEW instance after the first exits, rather than printing "already running" and reusing it live. This is unrelated to G-13-1 and does not block its fix.
