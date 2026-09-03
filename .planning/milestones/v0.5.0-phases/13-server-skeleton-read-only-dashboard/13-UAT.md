---
status: complete
phase: 13-Server Skeleton + Read-Only Dashboard
source: [13-VERIFICATION.md, 13-VALIDATION.md]
started: 2026-09-01T07:20:00Z
updated: 2026-09-01T09:15:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Full dashboard walkthrough (3 panels) — real browser, real project
expected: With a real cached project (`stress-ai/ios-stress-app/StressMonitor`, live cache state): state table renders sizes/badges/◆ macros, Run Doctor produces ✓/!/✗ rows + ↳ hints + summary + "Cached — generated at" stamp, graph renders node colors/diamond macros/legend. Per 13-UI-SPEC.
result: pass
evidence: "Two-phase session. (1) FAILING pre-fix: real headless-Chromium against live boot found G-13-1 — index.html's bare-relative asset refs 404'd (router serves only /assets/*), app.js never ran, panels stuck on static 'Loading…'. (2) PASSING post-fix (commits 5cc40cf RED, 68ff6f8 GREEN, 8fdd2df spec repair): fresh boot, fresh navigation — 43 state rows with real data (e.g. 'FirebaseInstallations | debug | 660.3 KB | hit | resolution-incompatible'), Run Doctor click → button swapped to disabled 'Running…' → full check rows with ✓ markers (xcode_version Xcode 26.3, swift_version 6.2.4, toolchain_path, cache_dir_health ~42732 files, companion_binary 0.4.0, …) + 'Cached — generated at 15:28:00' stamp, graph panel with cytoscape canvas mounted (1 child) + legend (hit/missed/ignored/excluded/plugin/macro). Zero page errors. Full-page screenshot captured this session."

### 2. Token bootstrap (URL cleanup, sessionStorage, never-in-DOM)
expected: Address bar cleans to `/` via `history.replaceState` before first render; token stored in `sessionStorage`, never rendered in the DOM; every fetch sends `X-SPM-Token`.
result: pass
evidence: "Post-fix live navigation with correct token: `location.href` cleaned to `http://127.0.0.1:<port>/` (no `?token=`); sessionStorage holds `spm-cache-web-token` (64 chars); full-page DOM search finds the token nowhere. Negative path verified too: a mistyped token (this session's own transcription slip, then a deliberately corrupted sessionStorage value) yields the exact full-page restart copy 'This page's access token is no longer valid. Restart spm-cache web and open the URL it prints.' — panels replaced, exactly the truth-18 contract. Pre-fix this test was blocked by G-13-1 (app.js never loaded)."

### 3. Auto-poll + error resilience
expected: Header stamp shows "Updated … · auto-refresh {N}s" and advances every 5s; a failed poll keeps last rows and the loop keeps running.
result: pass
evidence: "Post-fix live: stamp advanced 'Updated 15:27:57' → 'Updated 15:28:02' (5s cadence). Killed the serving process with SIGINT mid-poll: error copy appeared ('Couldn't load Cache State: network error (Failed to fetch). Check that spm-cache web is still running, then Refresh.'), ALL 43 last rows retained, and the loop continued (stamp kept advancing after server death). Pre-fix this test was blocked by G-13-1."

### 4. True-offline load
expected: Disconnect the machine from the network, hard-reload — everything renders (all assets local, zero blocked-external-request console errors).
result: pass
evidence: "USER-ACCEPTED on evidentiary basis (2026-09-01, in-session ruling): the physical network-disconnect gesture was not performed — it is a no-op for a loopback-only app (127.0.0.1 traffic never traverses the NIC) — but the requirement's substance is directly observed: across the entire live headless-Chromium session the only non-2xx request was the browser's automatic /favicon.ico probe; every resource the dashboard consumes (index.html, styles.css, app.js, cytoscape.min.js, all three API payloads) came from 127.0.0.1 same-origin with zero external requests to block; offline gate spec (web_frontend_spec.rb offline group) green; zero scheme-absolute/cdn references grep-verified twice. Physical spot-check remains an optional user gesture."

### 5. Real-TTY Ctrl-C exit
expected: Ctrl-C on a foreground `spm-cache web` exits 0 promptly; `.spm-cache/web/server.json` is removed.
result: pass
evidence: "Verified twice this session on two independent live boots (pids 21013, 22623): real SIGINT → process gone within 1.5s, marker file removed both times. Matches the automated web_signals_spec.rb real-subprocess proof. (Real-GUI Ctrl-C keypress equivalence is covered by the identical signal path.)"

### 6. Judgment-tier prohibitions (stored-XSS defense, no-second-mutex)
expected: (a) zero innerHTML/insertAdjacentHTML/document.write in app.js — all dynamic text via textContent/createElement. (b) web layer's only writes are its own marker + boot lock; no second project mutex.
result: pass
evidence: "Re-confirmed via direct grep this session: zero innerHTML/insertAdjacentHTML/document.write/outerHTML in app.js; el()/textContent is the only DOM-write path. Write-surface audit: only Marker (server.json) and .boot.lock under the web's own `.spm-cache/web/` dir; ReadModels are pure readers. Matches 13-VERIFICATION.md's SUBSTANTIALLY HONORED judgment verdict — accepted as pass, not re-litigated. Live session exercised hostile-free real data through the full render path with zero page errors."

## Summary

total: 6
passed: 6
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps

- gap_id: G-13-1
  truth: "Dashboard renders per 13-UI-SPEC in a real browser: state table, doctor panel, graph panel, token bootstrap URL cleanup, and auto-poll all function"
  status: resolved
  reason: "index.html's asset references (styles.css, cytoscape.min.js, app.js) were bare relative paths resolving to `/{asset}` from document root `/`, but router.rb only serves static files under `/assets/*`. Every first load 404'd all three sibling assets — the entire client-side dashboard never activated for any user."
  severity: blocker
  test: 1
  artifacts: ["lib/spm_cache/web/assets/index.html"]
  missing: []
  resolved_by: 13-05-PLAN.md
  resolved_at: 2026-09-01
  resolution: "Executed via /gsd-execute-phase 13 --gaps-only (commits 5cc40cf RED → 8fdd2df spec repair → 68ff6f8 GREEN → eb10a9b close-out): refs prefixed `assets/`, integration spec now resolves every scanned ref with browser semantics (URI.join against the document origin — no test-side /assets/ re-prefix), live curl smoke + 185-example web spec set + full 787-example suite green. Independently re-verified in a real headless browser this session: full render, token bootstrap, auto-poll, error resilience — see Tests 1-3 evidence."

## Notes for Human Follow-Up (not gaps — judgment/observation items)

- **Default-browser auto-open on a fresh start (no `--no-open`):** accepted on code + spec evidence by user 2026-09-01 (StartCallback-after-bind ordering spec-pinned); recorded in the refreshed 13-VERIFICATION.md.
- **WR-02 live-instance reuse UX (carried decision, 13-VERIFICATION human item 5):** accepted as block-then-replace by user 2026-09-01; recorded in the refreshed 13-VERIFICATION.md as the single accepted override.
- **True-offline physical spot-check (Test 4):** optional user gesture at leisure — disconnect network, hard-reload the dashboard. Architecture already proven offline (zero external references; all session traffic same-origin loopback).
- **Benign observation:** browsers auto-request `/favicon.ico` → 404 in console. No functional impact; index.html intentionally references no favicon. Cosmetic follow-up candidate only.
