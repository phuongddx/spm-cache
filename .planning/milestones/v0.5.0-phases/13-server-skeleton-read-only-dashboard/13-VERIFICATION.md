---
phase: 13-server-skeleton-read-only-dashboard
verified: 2026-09-01T09:02:48Z
status: passed
score: 23/23 must-have truths verified
behavior_unverified: 0 # Refresh 2026-09-01: the five client-UI truths (15–19) are LIVE-VERIFIED by the orchestrator's real headless-Chromium session against a live boot on the reference project (13-UAT Tests 1–3); truth 1's browser-open half and truth 2's reuse half are closed by recorded user acceptances (2026-09-01). See "Delta Verification (this refresh)".
overrides_applied: 1
overrides:
  - must_have: "SC2 reuse half: Re-running while a server is live reuses the running instance and prints 'already running at <url>'"
    reason: "USER-ACCEPTED 2026-09-01 as block-then-replace: a second `spm-cache web` launch blocks on the boot flock for the first server's lifetime, then boots a fresh instance (new pid/port/token) after it exits. The load-bearing halves — 'no error, no second server' — are lock-enforced and live-confirmed; the print-and-reuse reading manifests only in a synthetic lock-free scenario (web_lifecycle_spec.rb:466-491) because marker write AND ensure-clear both run inside the flock (web.rb:53-61). Serialization accepted over reuse-print UX."
    accepted_by: "user (recorded in session, 2026-09-01)"
    accepted_at: "2026-09-01"
re_verification:
  previous_status: human_needed
  previous_score: 17/23
  gaps_closed:
    - "G-13-1 (UAT blocker): index.html bare-relative asset refs 404'd in real browsers — dashboard never activated. Closed by plan 13-05 (5cc40cf RED → 8fdd2df spec repair → 68ff6f8 GREEN 3-line fix → eb10a9b close-out). Re-verified THIS session by spec re-runs at HEAD, an independent RED reproduction at 5cc40cf, a live marker-driven curl smoke, and the orchestrator's real headless-Chromium walkthrough (13-UAT Tests 1–3)"
    - "Prior human item 1 (three-panel browser walkthrough vs 13-UI-SPEC): LIVE-VERIFIED (13-UAT Test 1)"
    - "Prior human item 2 (token bootstrap + auto-poll observation): LIVE-VERIFIED incl. negative paths (13-UAT Tests 2–3)"
    - "Prior human item 3 (true-offline physical disconnect): recorded skip-with-rationale (13-UAT Test 4) — loopback survives a network cut and the offline architecture is grep-proven twice; user leisure spot-check recommended, not a gap"
    - "Prior human item 4 (real Ctrl-C + default-browser auto-open): Ctrl-C half LIVE-VERIFIED twice (13-UAT Test 5); auto-open half USER-ACCEPTED on code+spec evidence (StartCallback-after-bind ordering pinned, web_lifecycle_spec.rb:307-311)"
    - "Prior human item 5 (WR-02 reuse-UX decision): USER-ACCEPTED as block-then-replace (override above)"
    - "Prior human item 6 (judgment-tier prohibitions): re-confirmed by direct grep + live render of real data through the full path with zero page errors (13-UAT Test 6)"
  gaps_remaining: []
  regressions: [] # Git-verified this session: the entire delta 049503b..HEAD touches lib/ ONLY in lib/spm_cache/web/assets/index.html (3 changed lines — the G-13-1 refs); every other baseline truth's code evidence carries over unchanged. Confirmed behaviorally: full suite re-run at HEAD → 787 examples, 0 failures.
gaps: []
deferred: [] # Graph EDGES remain excluded by REQUIREMENTS DASH-03's own text ("edges deferred pending Swift spike") — an in-requirement scope boundary, not an unmet expectation.
coincidental_reliance_items: [] # Baseline advisory finding unchanged (all evidence ran through real seams); the refresh adds live-browser and live-CLI smoke seams — still no undeclared-precondition / incidental-ordering / fixture-only reliance.
---

# Phase 13: Server Skeleton + Read-Only Dashboard Verification Report

**Phase Goal:** `spm-cache web` serves a localhost-only, fully-offline dashboard showing cache state, doctor health, and the dependency graph — read-only, and hardened against localhost drive-by requests before any mutating endpoint exists
**Verified:** 2026-09-01T09:02:48Z (refresh of the 2026-09-01T07:11:49Z initial report)
**Status:** passed (23/23 truths verified — five client-UI truths live-verified in a real browser, two user acceptances recorded, one accepted deviation counted as an override)
**Re-verification:** Yes — refresh after G-13-1 gap closure (plan 13-05), UAT reconciliation, and recorded user acceptances

## Goal Achievement

Verification basis: LIVE CODE + LIVE RUNS, not SUMMARY claims.

**Initial verification (2026-09-01T07:11:49Z, HEAD `049503b`)** — the baseline: the phase's twelve spec files run in three batches (87 + 102 + 119 = **308 examples, 0 failures**), plus two independent live boots of the real CLI over real sockets exercising bootstrap 302, index 200, token/Host/Origin rejects, all three API envelopes, asset serving, traversal probe, second-launch behavior, and SIGTERM exit.

**This refresh (2026-09-01T09:02:48Z, HEAD `28af854`)** — the post-verification delta re-verified independently (details in "Delta Verification (this refresh)" below): RED reproduction at 5cc40cf (**112 examples, exactly the 2 edited failures**), the delta spec pair at HEAD (**112/0**), the web spec set (**185/0**), the full suite (**787 examples, 0 failures**, 55.4 s), a live marker-driven curl smoke of the real CLI (**SMOKE OK**), git scope checks (whole-delta lib/ diff = exactly index.html × 3 lines), and a cross-check of 13-UAT.md (5/6 pass, 1 skip-with-rationale, zero open issues, G-13-1 resolved) whose Tests 1–3 carry the orchestrator's real headless-Chromium evidence that live-verifies truths 15–19.

### Observable Truths

Merged must-haves: ROADMAP SC1–SC5 (non-negotiable contract) + deduplicated plan truths 13-01..13-05 (folded into the 23 rows below — restatements of an SC keep the SC wording).

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | SC1: `spm-cache web` starts a server bound explicitly to 127.0.0.1 (probing past occupied ports, skipping AirPlay's 5000/7000) and opens the dashboard in the default browser | ✓ VERIFIED | `Server::BIND_ADDRESS = '127.0.0.1'` with the CP9 never-hostname/never-0.0.0.0 rationale (server.rb:14-18); bind asserted on a real ephemeral boot (`web_server_spec.rb:32-38`); skip-list `{5000,7000}` pinned and 5000 proven never-bound by holding 4999 and exhausting (`web_lifecycle_spec.rb:160-169`, port_prober.rb:14-16); live boots bound 127.0.0.1 via the real CLI (baseline :59024; this refresh's smoke :50650). Browser-open fires in `StartCallback` inside `#start` after bind (web.rb:117-127, ordering spec `web_lifecycle_spec.rb:307-311`); `--no-open` suppresses. Real-OS browser-launch observation **USER-ACCEPTED 2026-09-01 on code+spec evidence** (the ordering pin is the load-bearing half; a 10-second real observation remains available at leisure — 13-UAT Notes). |
| 2 | SC2: Re-running while a server is live reuses the running instance (marker + pid-liveness — no error, no second server); SIGTERM/SIGINT exits cleanly with cleanup and exit 0 | ✓ VERIFIED (override — accepted deviation, see frontmatter) | Exit half: real-subprocess TERM and INT both exit 0 with marker removed, SIGKILL leaves an honest stale-dead marker (`web_signals_spec.rb:75-106`); exit-0 + marker-removal reproduced live twice at baseline and again in this refresh's smoke (SIGINT → rc=0, marker gone). Reuse half: "no error, no second server" is lock-enforced and live-confirmed; the *print-URL-and-return* reading does not manifest live — a second launch blocks silently on the boot flock for the first server's lifetime, then boots a NEW instance (marker read AND ensure-clear both run inside the flock, web.rb:53-61; reuse print spec-pinned only in a synthetic lock-free scenario, `web_lifecycle_spec.rb:466-491`). **USER-ACCEPTED 2026-09-01 as block-then-replace** — serialization over reuse-print UX; recorded as an override (overrides_applied: 1). |
| 3 | SC3: Dashboard loads fully offline (all assets vendored, zero CDN); a request with invalid Host/Origin or a missing per-launch token is rejected | ✓ VERIFIED | Offline: greps over index.html/app.js/styles.css → zero scheme-absolute URLs, zero `cdn.` (re-confirmed in the UAT session); cytoscape v3.34.2 vendored (first-line version comment, 435,643 bytes, served from /assets/ — live 200 application/javascript). Rejects: 25-cell route × case matrix + CP13 drive-by trio on every /api/* route, one real boot (`web_integration_spec.rb:118-155`) — green in the baseline run and in this refresh's 112/0 pair; live probes reproduced 401 (no token), 403 (evil Host), 403 (evil Origin) on /api/state. True network-cut reload: recorded **skip-with-rationale** (13-UAT Test 4) — loopback traffic survives a network disconnect and the offline architecture is proven by the zero-external-reference greps; the only non-2xx in the whole live session was the browser's automatic /favicon.ico probe (benign, cosmetic). |
| 4 | SC4: The cache-state table shows per-package size, cached/source state, and fidelity status, re-derived from the same files the CLI reads | ✓ VERIFIED (server half; client half = truth 15, now live-verified) | `ReadModels::State.call` joins `Cache::Inventory.scan` (recursive lstat sizes, `.provenance.json` fidelity) with graph.json statuses + `Cachemap#stats` summary + `poll_seconds` (state.rb:16-49) — specs prove the join by module name, nil-state/has_macro defaults, sidecar fidelity, zeros-when-absent-summary, and per-request re-reads (freshness: graph.json mutation and a newly cached artifact both change the next answer without restart, `web_state_spec.rb:155-180`); one shared scan for CLI + web (`Inventory.scan` call sites: command/cache/list.rb:17, state.rb:16); live /api/state answered the ok envelope with poll_seconds 5 (baseline) — and 43 real rows rendered client-side this refresh (truth 15). |
| 5 | SC5: Doctor panel runs checks on demand from the check registry (statuses + fix hints, data-driven, cached with timestamp); graph panel renders package nodes via the repaired vendored-cytoscape visualization, with an affordance when graph.json is absent | ✓ VERIFIED (server half; client halves = truths 16–17, now live-verified) | Doctor: `ReadModels::Doctor` runs `Diagnostics.run_all` synchronously only on a truthy `?run=`, swaps `{data, generated_at}` under a Mutex, serves the cache with the RUN's stamp (nil before first run — passed through verbatim by the router, router.rb:153-182); data-driven proof — a stubbed registry check appears in the payload with zero read-model change (`web_doctor_spec.rb:87-99`); torn-cache thread-pair proof (`:132-146`); serve-through envelope proof (`:152-173`); payload is the exact CLI --json shape via the shared `Diagnostics.payload` (diagnostics.rb:53, doctor.rb:67-70). Graph: `ReadModels::Graph` — present flag from File.exist?, nodes via `Cachemap#depgraph_for_viz`, mtime stamp, malformed → 500 envelope (graph.rb:14-24; `web_graph_spec.rb` incl. deletion-flips-present freshness); live /api/graph answered ok/present/1 node/generated_at and /api/doctor (no run) answered has_run:false with nil stamp. Client rendering live-verified this refresh (truths 16–17). |
| 6 | WEB-04 token hygiene: WEBrick access log disabled; marker written 0600 atomically; token never printed or shelled | ✓ VERIFIED | `AccessLog: []` with the token-leak rationale (server.rb:27-33); marker 0600 via Tempfile+chmod-before-rename (marker.rb:43-56) — live boots observed mode 600 (baseline `100600`; this refresh's smoke `600`); spec pins "never sends the token to the shell or stdout" (`web_lifecycle_spec.rb:313-320`); grep over web/ + command/web.rb: the only UI outputs are the bare already-running URL and a browser-open failure warning — no token-bearing output; bootstrap URL is the only token path (router.rb:97-99). |
| 7 | DASH-03 (server side): GET /api/graph with a valid token returns the {status, data, generated_at} envelope with nodes from `<project>/spm-cache/packages/proxy/graph.json` | ✓ VERIFIED | `web_graph_spec.rb` (present true/false, nodes shape, File.utime mtime stamp, ParserError → error envelope, serve-through, 401 gate) + `web_server_spec.rb` /api/graph envelope group; live-confirmed (truth 5). |
| 8 | Path traversal: /assets/\<anything outside the assets root\> (including encoded .., %2e%2e, ..%2F forms) never resolves outside lib/spm_cache/web/assets | ✓ VERIFIED | Validated-basename resolver: separators/backslashes/../leading-dots/NULs rejected before any FS call + containment check (assets.rb:42-60); unit rejection matrix (`web_assets_spec.rb:46-55`); exact-404s through the real server for every traversal form carrying a target (`:102-111`); bare dot-segment paths never 200 (`:113-119`). Live probe `/assets/%2e%2e%2f%2e%2e%2fconfig.rb` rejected one layer earlier by WEBrick sanitization (400, never 200, never reached the FS) — same security property. The G-13-1 fix did not widen any route: this refresh's smoke re-probed the bare pre-fix paths /styles.css, /app.js, /cytoscape.min.js → **404 × 3** (only the prefixed /assets/* forms serve). |
| 9 | WEB-02 heal semantics: dead-pid / malformed / symlinked marker is cleared and a fresh server starts (0600 atomic write, symlink-rejecting read, pid-liveness) | ✓ VERIFIED | Marker group in `web_lifecycle_spec.rb` (0600 atomic write, symlink read/write behavior, live/dead/unparseable pid); `live?` = parseable pid + `Process.kill(0, pid)` (run_log precedent, marker.rb:79-92); heal path `Marker.clear if marker` before boot (web.rb:65); SIGKILL leaves a stale marker that reads dead — next launch heals (`web_signals_spec.rb:98-106`). |
| 10 | DASH-01: `spm-cache cache list` output is byte-identical after the Cache::Inventory extraction | ✓ VERIFIED | Exact-output spec pins the full printed document; all 10 pre-existing output examples pass unmodified (`command_cache_list_spec.rb` Inventory block); sidecar tolerance moved verbatim (inventory.rb:41-52); grep: exactly two production `Inventory.scan` call sites. Re-confirmed green in this refresh's 787/0 full-suite run. |
| 11 | DASH-02: the doctor payload shape is EXACTLY the CLI --json shape {checks:[{name,status,message,fix_hint}], summary:{ok,warnings,failures}} — one payload method shared by CLI and read model | ✓ VERIFIED | `Diagnostics.payload` (diagnostics.rb:53-62) is the single definition; `print_json` delegates (doctor.rb:67-70); `doctor_spec.rb` pins string statuses, summary counts, and the exact --json document; the read model normalizes through a JSON round-trip so the cached hash IS its served shape (doctor.rb:64-66). |
| 12 | Envelope discipline: every read model answers through the {status, data, generated_at} envelope; a malformed graph.json (parse-, shape-, or encoding-broken) yields the 500 error envelope | ✓ VERIFIED | `api_read` rescues `JSON::JSONError` + `TypeError`, `api_doctor` rescues `StandardError`-never-Interrupt (router.rb:118-149, 158-171 — the WR-01 fix); live-server regression specs: shape-malformed and non-UTF-8 graph.json → 500 envelopes on BOTH /api/graph and /api/state, hostile doctor check strings → envelope (`web_server_spec.rb`, WR-01 group); integration asserts exact envelope keys end-to-end (`web_integration_spec.rb:190-216`). |
| 13 | Poll config: Config#web_poll_seconds Integer-coerces with rescue-to-default 5; /api/state data carries poll_seconds | ✓ VERIFIED | config.rb:30 (DEFAULT 5), :195-199 (coercion); config_spec + state spec default/override examples; live /api/state carried poll_seconds 5 — and the live client honored it (5 s stamp cadence, truth 19). |
| 14 | WEB-04 (offline/vendored): first-party assets contain zero scheme-absolute URLs and zero cdn. references; vendored cytoscape is committed, served from /assets/, first line records the version, > 300 KB | ✓ VERIFIED | Greps: 0/0/0 matches across index.html, app.js, styles.css; cytoscape.min.js first line `/*! cytoscape v3.34.2 — MIT — vendored… */` with no scheme-prefixed URL, 435,643 bytes on disk and 435,643 bytes served live; offline gate + structural pins green (`web_frontend_spec.rb`). The G-13-1 fix preserved the relative-only negative pins byte-identically (git diff 936272f..68ff6f8 touches only the three positive literal pins). |
| 15 | DASH-01 (client): app.js renders the state table from /api/state — columns Package/Config/Size/State/Fidelity, status badges, ◆ macro prefix, mono sizes, exact empty copy | ✓ VERIFIED (LIVE — 13-UAT Test 1) | Baseline: served-source pins for COLS, STATUS_CLASS/FIDELITY_CLASS maps, `◆ ${name}`, humanBytes, `'—'` null-state cell, and the exact empty copy (app.js:27-33, 105-152). Refresh: real headless-Chromium against a live boot on the reference project (stress-ai/ios-stress-app/StressMonitor) rendered **43 state rows with real data** (e.g. `FirebaseInstallations | debug | 660.3 KB | hit | resolution-incompatible`) through the real fetch/render path with zero page errors. Pre-fix the same session observed the G-13-1 failure (bare refs 404, panels stuck on static 'Loading…'); post-fix (68ff6f8) a fresh boot + fresh navigation renders fully. |
| 16 | DASH-02 (client): doctor rows as marker + name + message, '↳ {fix_hint}' second line for non-ok checks with hints, summary line, empty state, 'Cached — generated at {HH:MM:SS}' stamp, Run Doctor → 'Running…' | ✓ VERIFIED (LIVE — 13-UAT Test 1) | Baseline source pins (app.js:174-219): MARKER map ✓/!/✗, `↳ ${fix_hint}`, summary template, has_run empty state, Cached stamp from the SERVER stamp, disabled-while-in-flight button swap. Refresh LIVE: Run Doctor click → button swapped to disabled **'Running…'** → full check rows with ✓ markers (xcode_version Xcode 26.3, swift_version 6.2.4, toolchain_path, cache_dir_health ~42732 files, companion_binary 0.4.0, …) + **'Cached — generated at 15:28:00'** stamp. |
| 17 | DASH-03 (client): graph nodes via vendored cytoscape (elements as-served), node colors by status, macro diamonds, legend top-right, exact empty copy naming `spm-cache use` | ✓ VERIFIED (LIVE — 13-UAT Test 1) | Baseline source pins (app.js:224-285): `elements: data.nodes` with no client transform, NODE_COLOR palette, `node[hasMacro="true"]` diamond selector, legend render, empty-state copy, IN-01 destroy-before-recreate fix. Refresh LIVE: graph panel with **cytoscape canvas mounted (1 child) + legend** rendering real nodes with colors/diamonds; the asset-ref fix restored the cytoscape-before-app.js load ordering. |
| 18 | Token bootstrap per locked decision: token moves from location.search to sessionStorage, replaceState cleans the URL to '/' BEFORE first render; every fetch sends X-SPM-Token; token never in DOM; 401/403 replaces panels with the full-page restart copy | ✓ VERIFIED (LIVE — 13-UAT Test 2) | Baseline source pins (app.js:10-16, :81, :63-70, :36-38). Refresh LIVE: `location.href` cleaned to `http://127.0.0.1:<port>/` (no `?token=`); sessionStorage holds `spm-cache-web-token` (64 chars); full-page DOM search finds the token **nowhere**; negative paths exercised — a mistyped token AND a deliberately corrupted sessionStorage value each yield the exact full-page restart copy ('This page's access token is no longer valid. Restart spm-cache web and open the URL it prints.') with panels replaced. |
| 19 | State panel auto-polls /api/state at data.poll_seconds (default 5s); header stamp shows the effective interval; a failed poll keeps the last rows and never stops the loop | ✓ VERIFIED (LIVE — 13-UAT Test 3) | Baseline source pins (app.js:154-172, 292-303): pollSeconds from payload, `Updated … · auto-refresh {N}s` stamp, error path keeps rendered rows, setTimeout loop continues, zero Date.now. Refresh LIVE: stamp advanced **'Updated 15:27:57' → 'Updated 15:28:02'** (5 s cadence); killed the server with SIGINT mid-poll → exact error copy ('Couldn't load Cache State: network error (Failed to fetch). Check that spm-cache web is still running, then Refresh.'), **ALL 43 last rows retained**, and the loop kept advancing after server death. |
| 20 | WEB-04 (matrix): for EVERY route the full reject matrix holds — foreign Origin → 403, spoofed Host → 403, absent Origin + no token on /api/* → 401 — and the happy path → 2xx/3xx; from one real ephemeral-port boot | ✓ VERIFIED | Table-driven `ROUTES.product(%i[happy foreign_origin spoofed_host no_token wrong_token])` over `/`, `/assets/styles.css`, `/api/{state,doctor,graph}` — 25 self-naming cells (`web_integration_spec.rb:76-124`), plus the localhost:{port} second allowlist entry (`:236-241`) and the <15 s one-boot runtime pin (`:244-248`). Green in the baseline run and in this refresh's 112/0 pair re-run. |
| 21 | WEB-04 (packaging): the built gem ships lib/spm_cache/web/assets/** (all four assets in Gem::Specification.files) AND declares webrick >= 1.8, < 2 as a runtime dependency | ✓ VERIFIED | gemspec:15-16 `{lib,bin,assets,tools}/**/*` glob, :35-40 webrick `>= 1.8, "< 2"` with the CP8 rationale; `web_packaging_spec.rb` pins the four files + glob-ships-the-dir + requirement-window + a REAL gem-build smoke — green in the baseline batch and this refresh's 185/0 web set. |
| 22 | The full dashboard answers end-to-end from ONE boot: token bootstrap redirect → index → three assets → three API payloads with valid token | ✓ VERIFIED | Page-load sequence with the three assets parsed FROM the served HTML and content types asserted, plus the 13-02 payload keys per endpoint (`web_integration_spec.rb:157-217`) — now resolving every scanned ref with browser semantics (URI.join against the document origin, no test-side /assets/ re-prefix — the G-13-1 regression net); independently reproduced by the baseline live boot and by this refresh's smoke (302 exact-token → 200 index with the three `assets/`-prefixed refs → each 200 + correct content type → ok envelopes). The live headless-Chromium session completes the same sequence in a real browser (truths 15–19). |
| 23 | X-Frame-Options: DENY and Cache-Control: no-store present on every HTML/API response in the integration pass | ✓ VERIFIED | `apply_security_headers` runs first in `Router#service` before any gate/dispatch (router.rb:60-61, 186-191); header sweep over bootstrap+index+all three API responses (`web_integration_spec.rb:219-234`); live asset response carried `XFO=DENY`. |

**Score:** 23/23 truths verified (5 client-UI truths live-verified this refresh; 1 accepted deviation counted via override; 0 behavior-unverified)

### Decision Coverage

`gsd-tools query check.decision-coverage-verify` → `{skipped: true, reason: "no trackable decisions"}` — 13-CONTEXT.md's decisions section carries no trackable `<decisions>` entries for the gate parser. Non-blocking by design; the locked decisions were nevertheless verified directly in code (port probe skip-list, token middleware matrix, offline asset architecture, three-endpoint read-model shape — truths 1/3/4/5/6/7).

### Prohibitions (must-NOT checks)

| Statement | Tier | Status | Evidence |
|---|---|---|---|
| MUST NOT bind any interface other than 127.0.0.1 (CP9) | test | ✓ VERIFIED | Single BIND_ADDRESS constant feeds WEBrick + resolve_port probe; real-boot bind spec (truth 1); no other bind site in web/. |
| MUST NOT log the token anywhere (AccessLog records ?token= URLs; never puts/inspect marker content) | test | ✓ VERIFIED | `AccessLog: []` (server.rb:27-33); shell/stdout-never-see-token spec; marker 0600; output-statement grep (truth 6). |
| MUST NOT serve a path resolved outside the assets root | test | ✓ VERIFIED | Truth 8; re-probed this refresh (bare pre-fix paths still 404 — no route widened by the fix). |
| MUST NOT install a second mutex or write any project state — server only reads files and writes its own marker | judgment | ✓ VERIFIED (UAT-confirmed) | Construction-honored (baseline LLM-judge: SUBSTANTIALLY HONORED) + UAT Test 6 re-confirmation: write-surface audit re-run — the ONLY writes are Marker (own dir, atomic) and the web-scoped `.boot.lock` in the same dir; read models are pure readers; the build flock remains the only project mutex. The G-13-1 fix added zero write surface (3 attribute values, same validated basenames, same /assets/* dispatch — T-13-23 accepted flag in 13-05-SUMMARY). |
| MUST NOT cache read-model results across requests (state/graph) — only doctor, always with generated_at | test | ✓ VERIFIED | State/Graph are stateless callables; freshness specs mutate graph.json / cache dirs between calls and see changed answers; doctor deletion-flips-present + stamp-passthrough specs (truths 4/5). |
| MUST NOT hard-code check names, counts, or orderings in the doctor read model | test | ✓ VERIFIED | Stubbed-extra-check proof: registry is the sole source (`web_doctor_spec.rb:87-99`); read model contains zero check names (read in full). |
| MUST NOT let `cache list` printed output change by one byte | test | ✓ VERIFIED | Truth 10; full-suite re-run this refresh. |
| MUST NOT mutate the envelope shape {status, data, generated_at} | test | ✓ VERIFIED | Integration asserts exact keys on all three endpoints; error paths share the same envelope (truth 12). |
| MUST NOT reference any absolute URL/CDN/external host in first-party assets (cytoscape byte-exempt, structurally pinned) | test | ✓ VERIFIED | Truth 14; the G-13-1 fix kept refs RELATIVE (`assets/…`, no leading slash) precisely to hold the web_frontend_spec.rb:71-75 negative pins byte-identically (T-13-22). |
| MUST NOT render dynamic strings via innerHTML/string concatenation (stored-XSS defense) | judgment | ✓ VERIFIED (UAT-confirmed) | Construction-honored (baseline LLM-judge: SUBSTANTIALLY HONORED) + UAT Test 6 re-confirmation: zero innerHTML/insertAdjacentHTML/document.write/outerHTML in app.js (grep re-run in the UAT session); el()/textContent is the only DOM-write path; the live session exercised real repo data through the full render path with zero page errors. |
| MUST NOT deviate from 13-UI-SPEC copy strings / tokens | test | ✓ VERIFIED | Copy-string verbatim pins incl. middots and the '—' em dash (`web_frontend_spec.rb`, green in this refresh's 112/0 pair); the live browser session rendered the exact copy (restart copy, 'Running…', 'Cached — generated at', empty/error copy — truths 16/18/19). |
| MUST NOT introduce a build step, framework, or npm dependency | test | ✓ VERIFIED | app.js remains a ~320-LOC vanilla ES module; index.html references exactly three relative assets (now `assets/`-prefixed); no package.json/node surface added (whole-delta git scope: index.html only). |
| MUST NOT weaken a middleware predicate to make the matrix pass / add new routes in 13-04 | judgment | ✓ VERIFIED (git-proven) | 13-04's two commits (1b6f4df, f12da58) touch only spec/web_integration_spec.rb + spec/web_packaging_spec.rb — zero production edits; the matrix passed as-shipped. The 13-05 delta likewise touched zero middleware/router bytes (lib diff = index.html only). |

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| lib/spm_cache/web/server.rb | WEBrick adapter, 127.0.0.1-only, port-0 pre-resolution, AccessLog off, single servlet, StartCallback | ✓ VERIFIED | 104 lines, read in full; lazy require with install-hint GeneralError |
| lib/spm_cache/web/router.rb | Single catch-all dispatcher; Host/Origin/token gate; envelope helpers; 3 API mounts | ✓ VERIFIED | 212 lines, read in full; gate order Host→Origin→token; WR-01 error-envelope rescues; unchanged through the delta |
| lib/spm_cache/web/middleware.rb | Pure predicates allowed_host?/allowed_origin?/valid_token? | ✓ VERIFIED | Digest-then-XOR fixed-time compare; allowlists derive only from the bound port |
| lib/spm_cache/web/marker.rb | read/write/clear of server.json, 0600, atomic, symlink-rejecting, pid-liveness | ✓ VERIFIED | WR-03 ENOENT-rescue clear + WR-02 pid-guarded clear both present |
| lib/spm_cache/web/port_prober.rb | Skip-list {5000,7000}, bounded upward probe | ✓ VERIFIED | Probe socket closed before return (the 13-01 auto-fix); WR-04 errno rescue |
| lib/spm_cache/web/assets.rb | Traversal-safe static resolution + content types | ✓ VERIFIED | IN-03 dead-code deletion confirmed (no #root reader) |
| lib/spm_cache/command/web.rb | CLAide verb: --port/--no-open, lock, reuse/probe/serve/signal lifecycle | ✓ VERIFIED | Read in full; WR-02 flock + WR-04 range validation present |
| lib/spm_cache/cache/inventory.rb | Shared cache-dir scan | ✓ VERIFIED | One source of truth, two call sites |
| lib/spm_cache/web/read_models/{state,graph,doctor}.rb | Three read models on the CLI's read paths | ✓ VERIFIED | All read in full; state/graph stateless, doctor instance-cached under Mutex |
| lib/spm_cache/core/diagnostics.rb + command/doctor.rb | Shared payload extraction | ✓ VERIFIED | payload at diagnostics.rb:53; print_json delegates |
| lib/spm_cache/core/config.rb | web_dir + web_poll_seconds | ✓ VERIFIED | web_dir at :129-131 (sibling of runs_dir, outside sandbox); poll reader :195-199 |
| lib/spm_cache/web/assets/index.html, styles.css, app.js, cytoscape.min.js | Offline dashboard assets per UI-SPEC | ✓ VERIFIED | index.html 59 lines with the three `assets/`-prefixed relative refs (the G-13-1 fix, :7/:56/:57); app.js ~320, styles.css 364, cytoscape 435,643 bytes — all read/grepped; live-served 200 with correct content types this refresh |
| spm_cache.gemspec | webrick >= 1.8, < 2 + files glob shipping assets | ✓ VERIFIED | :15-16, :35-40 |
| .gitignore | .spm-cache/ entry (marker carries the token) | ✓ VERIFIED | :30-31 with rationale comment |
| spec/web_{middleware,server,lifecycle,assets,signals,state,graph,doctor,frontend,integration,packaging}_spec.rb + spec/support/web_server_boot.rb | 12 spec files + shared boot helper | ✓ VERIFIED | All exist and green — 308 baseline examples + this refresh's 185-example web set and 787-example full suite |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|----|--------|---------|
| Command::Web#run | Full lifecycle | flock → marker read → live?-reuse / heal → PortProber → Server → Marker.write → traps → start → ensure clear | ✓ WIRED | web.rb:44-92; live-observed end to end (truths 1/2/9; this refresh's smoke) |
| Server | Router | Exactly ONE servlet mounted at '/' — gate uniformity is structural | ✓ WIRED | server.rb:74-75 (mount), :94-100 (service override per verb) |
| Router | Middleware + read models | service → gates → dispatch → ReadModels::{State,Graph,Doctor} → envelope | ✓ WIRED | router.rb:60-100; all three endpoints live-answered |
| Router | Assets | / and /assets/* arms through the validated resolver | ✓ WIRED | router.rb:88-108; assets live-served with correct content types |
| Command::Doctor#print_json AND ReadModels::Doctor | Diagnostics.payload | One shared JSON shape | ✓ WIRED | doctor.rb:67-70; doctor.rb (read model):64 |
| Command::Cache::List AND ReadModels::State | Cache::Inventory.scan | One shared scan | ✓ WIRED | list.rb:17; state.rb:16 (grep: exactly two production call sites) |
| main.rb run-log exclusion | web verb | pre_scan main_log_skipped? still skips the tee for web — the token would otherwise land in argv-captured run logs | ✓ WIRED | main.rb:19-24, unchanged from Phase 12 (load-bearing, verified at baseline; untouched by the delta) |
| app.js | /api/state, /api/doctor(?run=1), /api/graph | X-SPM-Token fetch layer consuming the 13-02 payload keys | ✓ WIRED (LIVE) | app.js:78-95 + panel renderers; payload keys match read models exactly; the live browser session exercised all three endpoints through the real fetch layer (truths 15–19) |
| index.html | styles.css, cytoscape.min.js, app.js | Three relative `assets/`-prefixed refs, all served by Web::Assets | ✓ WIRED (LIVE) | index.html:7, 56-57; integration parses refs from served HTML, resolves each with browser semantics (URI.join against the document origin), and asserts 200 + content types; live smoke + real browser confirmed each ref loads (G-13-1 closed) |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| /api/state | packages/summary/poll_seconds | Cache::Inventory scan of ~/.spm-cache/{debug,release} + proxy graph.json + Config | Yes — real file reads per request; freshness specs mutate files and see changed answers | ✓ FLOWING |
| /api/graph | present/nodes/graph_generated_at | File.exist?/mtime + Cachemap#depgraph_for_viz on graph.json | Yes — live-confirmed with a real fixture graph (present=true, 1 node, ISO stamp) | ✓ FLOWING |
| /api/doctor | checks/summary/has_run | Diagnostics registry run_all → payload (JSON round-trip) | Yes — real registry; hermetic Sh stubs in specs, stubbed-extra-check data-driven proof | ✓ FLOWING |
| index + assets | served bytes | Real files under lib/spm_cache/web/assets/ | Yes — cytoscape served 435,643 bytes = on-disk size; this refresh's smoke + real browser loaded all three refs | ✓ FLOWING |
| marker | pid/port/token | Real Process.pid + bound port + SecureRandom.hex(32) | Yes — live-observed (token_len 64, mode 600) | ✓ FLOWING |

No static returns, hardcoded payloads, or mock-only sources anywhere in the chain.

### Behavioral Spot-Checks

Baseline (HEAD `049503b`, 2026-09-01T07:11:49Z) — all re-confirmed green through this refresh's full-suite run:

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| 13-01 spec set | `bundle exec rspec spec/web_{middleware,server,lifecycle,assets,signals}_spec.rb` | 87 examples, 0 failures | ✓ PASS |
| 13-02 spec set | `bundle exec rspec spec/web_{state,graph,doctor}_spec.rb spec/command_cache_list_spec.rb spec/doctor_spec.rb spec/config_spec.rb` | 102 examples, 0 failures | ✓ PASS |
| 13-03/04 spec set | `bundle exec rspec spec/web_{frontend,integration,packaging}_spec.rb` | 119 examples, 0 failures | ✓ PASS |
| Real CLI boot over real sockets | spawned `Main.run(['web','--no-open','--port=0'])` + Net::HTTP probes | 302 exact-token bootstrap; 200 index; /api/state 401/403/403/ok; /api/graph ok; /api/doctor has_run:false; assets 200 w/ DENY; traversal never 200 | ✓ PASS |
| Marker hygiene live | File.stat on the live marker | mode 100600, token 64 hex chars, real pid/port | ✓ PASS |
| SIGTERM contract live | kill -TERM both live servers | exit 0 + marker removed, twice | ✓ PASS |
| Second-launch behavior live | spawn S2 while S1 serves; TERM S1; observe | S2 blocks → after S1 exit-0, S2 boots NEW instance → TERM exit 0 | ⚠ OBSERVED → **accepted 2026-09-01** (override, truth 2) |
| Offline gate | grep scheme-URLs / cdn. over first-party assets | 0 matches (innerHTML/Date.now also 0) | ✓ PASS |

This refresh (HEAD `28af854`, 2026-09-01T09:02:48Z) — delta checks run by this verifier:

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| RED evidence reproduction | detached worktree at 5cc40cf: `bundle exec rspec spec/web_integration_spec.rb spec/web_frontend_spec.rb` | **112 examples, 2 failures — exactly the two edited examples** (web_integration_spec.rb:174 asset-resolution include pin; web_frontend_spec.rb:66 three-relative-assets pin, failing on bare refs in served HTML) | ✓ PASS (RED proven, not trusted) |
| GREEN pair at HEAD | same command at `28af854` | **112 examples, 0 failures** | ✓ PASS |
| Web spec set | `bundle exec rspec spec/web_{integration,frontend,server,lifecycle,assets,packaging}_spec.rb` | **185 examples, 0 failures** (2.65 s) | ✓ PASS |
| Full suite | `bundle exec rspec` | **787 examples, 0 failures** (55.38 s) | ✓ PASS |
| Live marker-driven curl smoke | real CLI boot in a scratch project (`BUNDLE_GEMFILE` + absolute -I/bin, cwd=scratch), marker-polled | mode 600, port 50650, token_len 64; root → 302 exact-token redirect; served HTML refs exactly the three `assets/`-prefixed values; GET /assets/{styles.css,cytoscape.min.js,app.js} → 200 text/css + application/javascript ×2; bare pre-fix paths → 404 ×3; SIGINT → process exited, boot shell rc=0, marker removed | ✓ PASS (SMOKE OK) |
| Delta scope (git) | `git diff 936272f..68ff6f8 -- lib/` and `git diff 049503b..HEAD -- lib/` | both = exactly `lib/spm_cache/web/assets/index.html`, 3 insertions(+), 3 deletions(-) | ✓ PASS |
| Spec-side /assets/ re-prefix residue | grep `/assets/#{` over spec/ | 0 matches; integration resolves via `URI.join("http://127.0.0.1:#{@server.port}/", ref).request_uri` (browser semantics) | ✓ PASS |

Count-consistency note: the pair reports 112 while the files report 70 (frontend) + 45 (integration) solo — `spec/spec_helper.rb` defines a 3-example sanity group counted once per process (67 + 42 own + 3 shared = 112). No examples are dropped or duplicated.

### Probe Execution

Step 7c SKIPPED — this phase declares no `scripts/*/tests/probe-*.sh` probes; its proof edges are spec files (verified green above) plus the 13-VALIDATION manual table and the 13-UAT live session.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|---------------------|----------|----------|
| WEB-01 | 13-01 | 127.0.0.1 server, port probing skipping AirPlay, opens dashboard | ✓ SATISFIED | Truth 1; browser-open observation accepted on code+spec evidence (2026-09-01) |
| WEB-02 | 13-01 | Re-running while live is idempotent (marker + pid-liveness), not an error | ✓ SATISFIED | Truths 2/9; reuse semantics USER-ACCEPTED as block-then-replace (override) |
| WEB-03 | 13-01 | SIGTERM/SIGINT → cleanup, exit 0 | ✓ SATISFIED | Truth 2 (real-subprocess specs + live reproductions ×4 across baseline, UAT, and this refresh's smoke) |
| WEB-04 | 13-01, 13-03, 13-04, 13-05 | Host/Origin + per-launch token validation; assets vendored, fully offline | ✓ SATISFIED | Truths 3/6/8/14/20/21/23; offline physical-disconnect check skip-with-rationale (13-UAT Test 4) |
| DASH-01 | 13-02, 13-03, 13-05 | State table: size, cached/source state, fidelity | ✓ SATISFIED | Truths 4/10/15 — client render LIVE-VERIFIED (43 real rows, 13-UAT Test 1) |
| DASH-02 | 13-02, 13-03, 13-05 | Doctor on-demand from the registry, cached with timestamp, fix hints | ✓ SATISFIED | Truths 5/11/16 — client render LIVE-VERIFIED (Run Doctor flow, 13-UAT Test 1) |
| DASH-03 | 13-01, 13-02, 13-03, 13-05 | Graph nodes via vendored cytoscape; empty affordance (edges deferred by the requirement's own text) | ✓ SATISFIED | Truths 7/17 — client render LIVE-VERIFIED (cytoscape canvas + legend, 13-UAT Test 1) |

Orphaned requirements: none — REQUIREMENTS.md maps exactly WEB-01..04 + DASH-01..03 to Phase 13 and the five plans collectively claim all seven (13-05 re-affirms WEB-04 + DASH-01..03 with the wiring-layer closure).

**Bookkeeping note (non-blocking):** REQUIREMENTS.md still ticks WEB-01/02/03 as `[ ] Pending` while WEB-04/DASH-01..03 were marked Complete; plan 13-01's completion commit never updated its three. The transition step should tick WEB-01/02/03 (all satisfied above).

### Test Quality Audit

| Test File | Linked Req | Active | Skipped | Circular | Assertion Level | Verdict |
|-----------|-----------|--------|---------|----------|-----------------|---------|
| web_middleware/server/lifecycle/assets/signals_spec.rb | WEB-01..04 | 87 | 0 | 0 | Value (exact statuses, exact markers/URLs, real pids) | Strong |
| web_state/graph/doctor_spec.rb | DASH-01..03 | 51 | 0 | 0 | Value (exact row hashes, stamps, thread-pair) | Strong |
| command_cache_list/doctor/config_spec.rb | DASH-01/02 | 51 | 0 | 0 | Value (byte-exact document, exact payload) | Strong |
| web_frontend_spec.rb | WEB-04, DASH-01..03 | 70 (67 own + 3 shared sanity) | 0 | 0 | Value (verbatim copy/ordering pins, offline gate, relative-only negative pins) | Strong — and the copy/behavior it pins is now live-browser-confirmed |
| web_integration_spec.rb | WEB-04, DASH-01..03 | 45 (42 own + 3 shared sanity) | 0 | 0 | Behavioral (real socket matrix; page-load refs resolved with browser semantics) | Strong — the former /assets/ re-prefix blind spot is closed (G-13-1 regression net) |
| web_packaging_spec.rb | WEB-04 | 7 (4 own + 3 shared sanity) | 0 | 0 | Behavioral (real gem build) | Strong |

**Disabled tests on requirements:** 0 (grep across all twelve files: no skip/pending/todo patterns).
**Circular patterns detected:** 0 — expected values are fixture-authored or independently computed (e.g. lstat sums in web_state_spec), never captured from the system under test.
**13-05 delta quality:** zero new examples were added — existing pins were re-keyed to the prefixed refs and the integration loop now resolves scanned refs browser-honestly; the RED run proved both edited examples fail against unfixed production (reproduced independently this refresh).

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| lib/spm_cache/web/assets/cytoscape.min.js | 32 | `TODO` string inside the vendored upstream WebGL shader comment | ℹ️ Info | Upstream cytoscape 3.34.2 dist bytes, byte-level-exempt class per the plan's own prohibition carve-out; not phase-authored debt. No other debt markers in any first-party file (grep: TBD/FIXME/XXX/TODO/HACK/PLACEHOLDER → 0, re-confirmed post-delta). |
| (runtime observation) | — | Browser auto-requests /favicon.ico → 404 in console | ℹ️ Info | Benign, cosmetic only; index.html intentionally references no favicon; no functional impact (13-UAT Test 4 evidence). Cosmetic follow-up candidate. |

Carried review residuals — dispositions now closed: WR-02 lock-hold scope **user-accepted 2026-09-01** (override, truth 2); WR-04 zero-boundary judgment accepted at a55e031 (13-REVIEW-FIX.md, `--port=0` first-class); phase-12 IN-08 credential-redaction gaps remain phase-12 scope (12-VERIFICATION), not Phase 13 debt.

### Human Verification — Closed This Refresh (2026-09-01)

The initial report's six human items are all dispositioned; the list is empty:

1. **Three-panel browser walkthrough vs 13-UI-SPEC** → LIVE-VERIFIED (real headless-Chromium against a live boot on the reference project; 43 state rows, Run Doctor flow with stamp, cytoscape canvas + legend — 13-UAT Test 1).
2. **Token bootstrap + auto-poll observation** → LIVE-VERIFIED (URL cleaned to '/', 64-char token in sessionStorage, token never in DOM, wrong-token restart copy; 5 s stamp advance; SIGINT error resilience with rows retained and loop resumed — 13-UAT Tests 2–3).
3. **True-offline network-cut reload** → skip-with-rationale (13-UAT Test 4): loopback survives a network cut; offline architecture proven twice by zero-external-reference greps; the only non-2xx in the live session was the benign favicon probe. A physical disconnect spot-check remains available at the user's leisure — not a gap.
4. **Real-TTY Ctrl-C + default-browser auto-open** → Ctrl-C LIVE-VERIFIED twice (13-UAT Test 5, independent boots); auto-open **USER-ACCEPTED on code+spec evidence** (StartCallback fires only after bind, ordering-pinned web_lifecycle_spec.rb:307-311; `--no-open` suppresses).
5. **WR-02 live-instance reuse UX (decision)** → **USER-ACCEPTED 2026-09-01 as block-then-replace** — second launch blocks on the boot flock for the first server's lifetime, then boots a fresh instance; mutual exclusion holds; recorded as an accepted deviation (override, truth 2).
6. **Judgment-tier prohibitions** → UAT Test 6 pass: grep re-confirmation (zero innerHTML-family writes; write surface = own marker + boot lock only) + live session exercising real data through the full render path with zero page errors.

### Gaps Summary

No gaps. All artifacts exist, are substantive, are wired, and carry real data; all key links connected — including the one G-13-1 broke (index.html → assets), now fixed, regression-netted with browser-honest spec resolution, and live-verified in a real browser; LOGS-01-adjacent exclusion (web verb never writes a run log) intact; requirements fully claimed and satisfied; no debt markers in first-party code; no disabled/circular tests. Status is **passed**: every behavior-dependent half of every truth is now either exercised by a live browser session (truths 15–19), covered by passing automated behavioral specs plus live CLI runs (truths 1–14, 20–23), or explicitly accepted by the user (truth 1's OS-launch observation; truth 2's block-then-replace semantics — the single recorded override). No truth remains behavior-unverified.

## Delta Verification (this refresh)

Everything below was checked by this verifier directly (not trusted from SUMMARYs) at HEAD `28af854`, branch gsd/v0.5.0-web-interface, on 2026-09-01:

1. **Commit chain present:** e260b5d (UAT session recording the G-13-1 blocker) → 936272f (13-05 gap-closure plan) → 5cc40cf (RED spec) → 8fdd2df (spec repair) → 68ff6f8 (GREEN 3-line fix) → eb10a9b (13-05-SUMMARY close-out) → 28af854 (UAT reconciled, G-13-1 resolved) — confirmed in `git log`.
2. **Production scope:** `git diff 936272f..68ff6f8 -- lib/` is EXACTLY `lib/spm_cache/web/assets/index.html`, 3 insertions / 3 deletions (line 7 `href="assets/styles.css"`, line 56 `src="assets/cytoscape.min.js"`, line 57 `src="assets/app.js"`; `type="module"` untouched). Whole delta `049503b..HEAD -- lib/` = the same 3 lines — the basis for regressions: [] (every baseline truth's production evidence carries over; confirmed behaviorally by the 787/0 full-suite re-run).
3. **Spec-side delta reviewed:** frontend literal pins re-keyed to prefixed values with the relative-only negative pins byte-identical; integration gained `require 'uri'`, re-keyed include/content-type pins, and replaced the manual `get("/assets/#{ref}")` re-prefix (the blind spot that hid G-13-1) with `URI.join("http://127.0.0.1:#{@server.port}/", ref).request_uri` — browser semantics, zero `/assets/#{…}` residue in spec/.
4. **RED reproduced (not trusted):** detached git worktree at 5cc40cf → `bundle exec rspec spec/web_integration_spec.rb spec/web_frontend_spec.rb` → **112 examples, 2 failures**, precisely the two edited examples (integration :174 include pin; frontend :66, whose diff shows the bare `src="cytoscape.min.js"` / `src="app.js"` in served HTML). Worktree removed afterward.
5. **GREEN re-run:** same pair at HEAD → **112 examples, 0 failures**. Web spec set (integration+frontend+server+lifecycle+assets+packaging) → **185 examples, 0 failures**. Full suite `bundle exec rspec` → **787 examples, 0 failures** (55.38 s).
6. **Live smoke reproduced (marker-driven, real CLI):** scratch-project boot → marker (mode 600, port 50650, 64-hex token) → root 302 to the exact-token URL → served HTML carries exactly the three `assets/`-prefixed refs → each ref curled as-is resolves 200 with the right content type (text/css ×1, application/javascript ×2) → bare pre-fix paths /styles.css, /app.js, /cytoscape.min.js still 404 (the fix is in the refs, not a widened route) → SIGINT → clean exit (rc=0) + marker removed. SMOKE OK.
7. **13-UAT.md cross-checked on disk:** status complete; Tests 1–3 pass with the orchestrator's real headless-Chromium post-fix evidence (the live-verification basis for truths 15–19); Tests 5–6 pass; Test 4 skipped with rationale; totals 5/6 pass, 0 issues, 0 pending; G-13-1 status resolved, resolved_by 13-05-PLAN.md; the user-acceptance notes (auto-open, WR-02) and the benign favicon observation are recorded in its Notes section.
8. **User acceptances recorded (2026-09-01, per orchestrator session):** (a) default-browser auto-open accepted on code+spec evidence — folded into truth 1; (b) WR-02 second-launch UX accepted as block-then-replace — recorded as the single override (overrides_applied: 1) on truth 2.
9. **Benign observation carried:** /favicon.ico auto-probe → 404, cosmetic only.

---

_Verified: 2026-09-01T09:02:48Z (refresh)_
_Verifier: Claude (gsd-verifier)_
