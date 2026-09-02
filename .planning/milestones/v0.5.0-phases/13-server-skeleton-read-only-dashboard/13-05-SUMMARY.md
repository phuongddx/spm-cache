---
phase: 13-server-skeleton-read-only-dashboard
plan: 05
subsystem: web
tags: [web, gap-closure, G-13-1, assets, browser-resolution, tdd, live-smoke]

requires:
  - phase: 13-server-skeleton-read-only-dashboard plan 01
    provides: the router's %r{\A/assets/} dispatch + Web::Assets validated serving — the frozen route the fixed refs now resolve through
  - phase: 13-server-skeleton-read-only-dashboard plan 03
    provides: the four offline assets under lib/spm_cache/web/assets/ — index.html's three refs are the gap surface
  - phase: 13-server-skeleton-read-only-dashboard plan 04
    provides: spec/web_integration_spec.rb's page-load sequence (the manual "/assets/#{ref}" re-prefix was the exact blind spot) + the web spec set green baseline
  - phase: 13-server-skeleton-read-only-dashboard verification/UAT
    provides: G-13-1 live headless-Chromium evidence (GET /app.js, /styles.css, /cytoscape.min.js all 404; dashboard stuck at static Loading…)
provides:
  - G-13-1 closed at the wiring layer — every served index.html ref is a relative assets/ path resolving through the existing /assets/* route, so rendering, token bootstrap, and auto-poll can execute in a real browser
  - the permanent regression net — every scanned ref is resolved browser-honestly (URI.join against the document's own origin root, then request_uri); no spec anywhere re-prefixes scanned refs, and a reverted bare ref fails the suite by name
  - the marker-driven live-boot curl smoke procedure (port/token from server.json, refs curled as-is) — recorded below for Phase 14's streaming-fixture copy
affects:
  - 13-UAT Tests 2/3/4 (blocked only by G-13-1's root cause — orchestrator re-verifies in a real browser)
  - 14 (copies the integration boot and the honest resolution example as its streaming fixture)

actuals:
  tokens: 463    # chars/4 over the realized diff (1,188 added + 664 removed chars across the 3 code commits); plan estimated 14000 at confidence low — first sample for the gap-closure micro-fix profile
  tasks: 3
  commits: 3

tech-stack:
  added: []   # an attribute-value prefix over three lines; no new runtime surface, no dependency
  patterns:
    - "The regression net must observe through the same resolution the browser performs (URI.join against the document origin, then request the resolved URI) — never through a rewriting layer between expectation and served bytes"
    - "Fix shape constrained by locked negative pins: the relative assets/ prefix was chosen precisely because web_frontend_spec.rb:71-75 (no leading-slash/protocol-relative/scheme refs) holds verbatim — fix the source, never the test"

key-files:
  created:
    - .planning/phases/13-server-skeleton-read-only-dashboard/13-05-SUMMARY.md
  modified:
    - lib/spm_cache/web/assets/index.html
    - spec/web_integration_spec.rb
    - spec/web_frontend_spec.rb

key-decisions:
  - "Relative `assets/` prefix, never absolute `/assets/`: the locked negative pin (no leading-slash ref values, web_frontend_spec.rb:73) holds verbatim, the page is served only at document root '/' so relative resolution is unambiguous (base '/' + 'assets/app.js' → '/assets/app.js' = the existing route), and 13-CONTEXT's same-origin RELATIVE asset promise is kept"
  - "[Rule 1] The plan's literal `URI.join('/', ref).to_s` is unrunnable Ruby — URI::BadURIError (both URI are relative; Ruby's URI.join demands an absolute base, and URI#merge/#+ reject a relative base the same way). Repaired to `URI.join(\"http://127.0.0.1:#{@server.port}/\", ref).request_uri` — the document's own origin root, base path '/' — identical browser resolution, zero test-side rewriting; a bare ref still resolves to /styles.css and 404s"
  - "The regression net is two-layered: the include pin (web_integration_spec.rb:177) fails FIRST on a bare-ref revert, and the resolution loop is the second layer (bare ref → GET /styles.css → 404) — RED presented as the include-pin mismatch (112 examples, exactly 2 failures, both edited examples)"
  - "Task 2 landed as two atomic commits: the Rule-1 spec repair (8fdd2df), then the GREEN commit (68ff6f8) whose diff is EXACTLY the three production ref lines — matching the plan's done criterion verbatim (one production file, three changed lines)"
  - "Smoke boot mechanics adapted (procedure identical): the plan's literal `cd $SCRATCH && bundle exec ruby -I lib bin/spm-cache` cannot resolve lib/bin from the scratch cwd, so the boot uses BUNDLE_GEMFILE=<repo>/Gemfile + absolute -I/bin paths with cwd = scratch project — real CLI, real bundle, marker at $SCRATCH/.spm-cache/web/server.json as specified"

requirements-completed: [WEB-04, DASH-01, DASH-02, DASH-03]

coverage:
  - id: WEB-04
    description: "All dashboard assets vendored and load fully offline — now including the refs the served HTML itself declares"
    verification:
      - kind: integration
        ref: "spec/web_integration_spec.rb page-load example 'serves every asset referenced by the served HTML with the right content types' — refs pinned as assets/-prefixed, each resolved via URI.join against the document origin and required 200 + pinned content type"
        status: pass
      - kind: smoke
        ref: "Live CLI boot (below): every scanned ref curled as-is against base '/' → 200 (text/css ×1, application/javascript ×2)"
        status: pass
  - id: DASH-01
    description: "Cache state table renders — activation prerequisite (app.js/styles.css actually loading) now wired"
    verification:
      - kind: integration
        ref: "spec/web_integration_spec.rb + spec/web_frontend_spec.rb green post-fix (the panels' data endpoints and source contracts were already green; the loading wiring was the gap)"
        status: pass
      - kind: manual-pending
        ref: "13-UAT Test 1/2 re-run by the orchestrator in a real browser (panels render past Loading…, token bootstrap, URL cleanup)"
        status: pending
  - id: DASH-02
    description: "Doctor panel on-demand checks — activation prerequisite wired"
    verification:
      - kind: integration
        ref: "web spec set green (doctor read model + source contracts unchanged and passing)"
        status: pass
      - kind: manual-pending
        ref: "13-UAT Test 1 re-run by the orchestrator (Run Doctor flow in a real browser)"
        status: pending
  - id: DASH-03
    description: "Graph panel via vendored cytoscape — activation prerequisite wired (cytoscape now actually loads before app.js)"
    verification:
      - kind: integration
        ref: "web spec set green (ordering pin cytoscape-before-app.js holds with prefixed values)"
        status: pass
      - kind: manual-pending
        ref: "13-UAT Test 1/3 re-run by the orchestrator (graph renders, auto-poll advances)"
        status: pending

duration: 12min
completed: 2026-09-01
status: complete
---

# Phase 13 Plan 05: Gap Closure G-13-1 — Dashboard Asset Refs Resolve in Real Browsers Summary

**G-13-1 is closed at the wiring layer: index.html's three asset refs now carry the relative `assets/` prefix so they resolve through the router's existing `/assets/*` dispatch — RED-proven (exactly the two tightened examples failing against production as shipped, 112 examples / 2 failures), GREEN with a production diff of exactly three attribute values, and live-proven by a real `spm-cache web --no-open --port=0` boot whose every served ref curled 200 as-is against base '/' (text/css ×1, application/javascript ×2) with clean SIGINT teardown — while the spec blind spot that hid the bug (the manual `"/assets/#{ref}"` re-prefix) is replaced by browser-honest URI resolution; full suite 787 examples, 0 failures.**

## Performance

- **Duration:** ~12 min (08:07–08:19 UTC)
- **Tasks:** 3 (RED commit → GREEN commits → live smoke + close-out)
- **Files:** 3 modified (1 production, 3 changed lines; 2 spec files), this SUMMARY created

## What Shipped vs Plan

### Task 1 — RED: browser-honest asset-ref pins (5cc40cf)
As planned: `web_integration_spec.rb`'s page-load asset example now pins the prefixed refs (`include('assets/styles.css', 'assets/cytoscape.min.js', 'assets/app.js')`), re-keys the content-type map to those exact strings, and replaces the manual `/assets/#{ref}` re-prefix with per-ref URI resolution (`require 'uri'` added); `web_frontend_spec.rb:66-70` literal pins gain the prefix (example name updated to stop lying). The negative pins (:71-75) and the cytoscape-before-app.js ordering pin were not edited. **RED evidence: `bundle exec rspec spec/web_integration_spec.rb spec/web_frontend_spec.rb` → 112 examples, 2 failures — exactly the two edited examples** (web_integration_spec.rb:174 asset-resolution example, failing at the include pin; web_frontend_spec.rb:66 prefixed literal pins). Matrix, offline gate, packaging: all green.

### Task 2 — GREEN: the 3-line production fix (8fdd2df + 68ff6f8)
As planned plus one Rule-1 repair (below). 68ff6f8 is the plan's GREEN commit verbatim: `git show --stat` = **exactly** `lib/spm_cache/web/assets/index.html, 3 insertions(+), 3 deletions(-)` — line 7 `href="assets/styles.css"`, line 56 `src="assets/cytoscape.min.js"`, line 57 `src="assets/app.js"` (`type="module"` untouched). **GREEN evidence: both files 112 examples, 0 failures.** 8fdd2df is the Rule-1 spec repair (resolution mechanics only, no production bytes).

### Task 3 — live-boot curl smoke + close-out (this SUMMARY)
Real CLI boot against a scratch project (transcript below): 302 bootstrap with the exact launch token, served refs exactly the three prefixed values, every ref 200 with the right content type when curled AS-IS resolved against '/', SIGINT → clean exit + marker removed. Close-out: full web spec set **185 examples, 0 failures**; full suite **787 examples, 0 failures**.

## Live-Boot Smoke Transcript (marker-driven, real CLI)

```
SCRATCH=$(mktemp -d)   # /tmp/spm-cache-smoke.1dAOWP
(cd "$SCRATCH" && BUNDLE_GEMFILE=<repo>/Gemfile bundle exec ruby -I <repo>/lib \
   <repo>/bin/spm-cache web --no-open --port=0) &        # real CLI, cwd = scratch project
# poll $SCRATCH/.spm-cache/web/server.json (≤15 s) → appeared:
MARKER = {"pid":11333,"port":63786,"token":"284bdccf…f3","started_at":"2026-09-01T08:15:18Z"}

$ curl -sS -o /dev/null -w '%{http_code} %{redirect_url}\n' http://127.0.0.1:63786/
302 http://127.0.0.1:63786/?token=284bdccf698a210638c2053de51a24c98e92e2ae8057d3fbf86504640039fff3

$ curl -sS "http://127.0.0.1:63786/?token=$TOKEN" > page.html
$ grep -oE '(href|src)="[^"]+"' page.html        # exact match against expected:
href="assets/styles.css"
src="assets/cytoscape.min.js"
src="assets/app.js"

# each ref AS-IS resolved against '/' (single-slash concat = browser resolution):
$ curl … http://127.0.0.1:63786/assets/styles.css        → 200  text/css
$ curl … http://127.0.0.1:63786/assets/cytoscape.min.js  → 200  application/javascript
$ curl … http://127.0.0.1:63786/assets/app.js             → 200  application/javascript

$ kill -INT 11333    → process exited (well within 10 s); marker file removed; boot shell exit 0
```

**Contrast (pre-fix):** against the page as shipped at plan time, this same smoke curls `/styles.css`, `/cytoscape.min.js`, `/app.js` and gets **404 × 3** — exactly the live headless-Chromium evidence in 13-UAT Test 1 (three 404 resource-load console errors; app.js never executes; the DOM never advances past the static `Loading…` placeholders). Those three GETs are still 404 today — they are simply no longer referenced by the document.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `URI.join('/', ref)` is unrunnable Ruby**
- **Found during:** Task 2 (GREEN run)
- **Issue:** Ruby's `URI.join` demands an absolute base — `URI.join('/', 'assets/app.js')` raises `URI::BadURIError: both URI are relative` (and `URI('/') + ref` / `URI('/').merge(ref)` reject a relative base identically). The literal plan text could never execute the loop; the RED run masked this because the include pin fails first.
- **Fix:** Resolve each scanned ref with `URI.join("http://127.0.0.1:#{@server.port}/", ref).request_uri` — the document's own origin root, so the base path is '/' and the resolution is exactly what a browser performs; then GET the resolved request path. Zero `/assets/` construction anywhere in the request path (prohibition intact); bare `styles.css` still resolves to `/styles.css` and must 404.
- **Files modified:** spec/web_integration_spec.rb (spec mechanics only)
- **Verification:** GREEN run green (112/0); resolution semantics machine-verified before the edit (`URI.join('http://127.0.0.1:60902/', 'styles.css').request_uri → '/styles.css'`, `'assets/app.js' → '/assets/app.js'`)
- **Commit:** 8fdd2df (RED commit 5cc40cf carried the plan-literal form; Task 2 was split so the GREEN commit stays exactly the 3 production lines)

### Clarifications (documented, not deviations)

- Smoke boot mechanics: the plan's literal `(cd "$SCRATCH" && bundle exec ruby -I lib bin/spm-cache …)` cannot resolve `lib`/`bin` from the scratch cwd; the boot uses `BUNDLE_GEMFILE` + absolute `-I`/bin paths with cwd = scratch project. Real CLI, real bundle, identical marker-driven procedure.

**Total deviations:** 1 auto-fixed (Rule 1, spec mechanics). **Impact:** none on the frozen production scope — the production diff remains exactly three ref values; every prohibition held (verified below).

## Threat Flags

All three register dispositions honored; no surface beyond the plan's threat_model was introduced:

| Flag | File | Description |
|------|------|-------------|
| threat_mitigated: T-13-21 | spec/web_integration_spec.rb | Regression net closed: refs pinned prefixed AND resolved browser-honestly (URI.join against the document origin → request_uri, no "/assets/" construction in the request path) — reverting index.html to bare refs fails the suite by name at the include pin or at the loop's 404 |
| threat_mitigated: T-13-22 | spec/web_frontend_spec.rb | Relative-only offline negative pins (:71-75) byte-identical through RED and GREEN — the relative assets/ prefix satisfies them unedited; the absolute form that would force weakening them was never used |
| threat_flag: T-13-23 (accepted) | lib/spm_cache/web/assets/index.html | No new surface: the three refs are the same validated basenames crossing the unchanged /assets/* dispatch + Web::Assets root containment — an attribute-value prefix introduces no traversal or disclosure path |

## Known Stubs

None. The production change is the complete fix for G-13-1's root cause; the remaining 13-UAT items are the orchestrator's designated re-verification half, tracked as manual-pending in coverage — not stubs.

## Verification

- **RED (Task 1):** `bundle exec rspec spec/web_integration_spec.rb spec/web_frontend_spec.rb` → **112 examples, 2 failures** — exactly the two edited examples; every other example green
- **GREEN (Task 2):** same command → **112 examples, 0 failures**; `git show --stat 68ff6f8` → exactly `lib/spm_cache/web/assets/index.html | 3 +++---`, no other production change in any commit
- **Web spec set (Task 3):** web_integration + web_frontend + web_server + web_lifecycle + web_assets + web_packaging → **185 examples, 0 failures**
- **Full suite (Task 3):** `bundle exec rspec` → **787 examples, 0 failures**
- **Live smoke (Task 3):** SMOKE OK — bootstrap 302 + exact token; refs exact-match the three prefixed values; each ref as-is → 200 + expected content type; SIGINT exit clean, marker removed
- Task commits: **5cc40cf** (RED), **8fdd2df** (Rule-1 spec repair), **68ff6f8** (GREEN, 3 lines)

## Self-Check: PASSED

All four key files exist on disk; all three task commits (5cc40cf, 8fdd2df, 68ff6f8) present in history on gsd/v0.5.0-web-interface; prohibition spot-checks green — production diff across the whole plan is exactly `lib/spm_cache/web/assets/index.html` (3 lines), the relative-only negative pins are byte-identical, and no `/assets/#{ref}` construction exists anywhere in the spec.
