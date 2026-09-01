---
phase: 13-server-skeleton-read-only-dashboard
verified: 2026-09-01T07:11:49Z
status: human_needed
score: 17/23 must-have truths verified
behavior_unverified: 5 # The five client-side UI truths (state table / doctor panel / graph panel rendering, token bootstrap, auto-poll loop): served-source pins and live-served bytes prove the surface, but the repo has no JS runtime — no automated spec exercises actual browser behavior. All five route to the 13-VALIDATION browser-walkthrough human items below.
overrides_applied: 0
re_verification:
  previous_status: none
  previous_score: none
  gaps_closed: []
  gaps_remaining: []
  regressions: []
  note: "Initial verification — no prior VERIFICATION.md existed (Step 0 confirmed empty)."
human_verification:

  - test: "Real browser walkthrough of the three panels against the approved 13-UI-SPEC (the phase's designated manual check: colors, spacing, copy, badges, ◆ macro prefix, doctor ✓/!/✗ + ↳ hints + 'Cached — generated at' stamp, Run Doctor → 'Running…' → rows, cytoscape node colors/diamonds/legend, all three exact empty-state copy strings)."
    expected: "Panels render per the UI-SPEC with data from the real project; every dynamic string renders (the served app.js uses textContent/createElement only). Covers the behavior-unverified halves of truths 15–19 (DASH-01/02/03 client, token bootstrap, auto-poll)."
    why_human: "No JS runtime in CI; specs pin served bytes, not rendered behavior. Visual fidelity vs the approved spec is judgment-tier."
  - test: "Token bootstrap observation: load the printed URL, watch the address bar; reload; inspect the DOM."
    expected: "Address bar cleans to '/' via history.replaceState before first render; reload works (302 re-bootstraps); the token value never appears in any DOM node; killing the server mid-poll shows error copy with last rows retained, loop resuming on return; leave open ≥ 15 s to see 'Updated … · auto-refresh 5s' advance."
    why_human: "Browser address-bar/sessionStorage/DOM state and live polling observation are not automatable in this repo."
  - test: "True-offline load: disconnect the machine from the network, hard-reload the dashboard."
    expected: "Everything renders — all four assets are vendored and served from /assets/ (grep-proven zero scheme-absolute URLs / cdn. in first-party assets; cytoscape structurally pinned), zero console errors about blocked external requests."
    why_human: "Network-level isolation is a physical test; the static offline proof (zero external references) is already automated and green."
  - test: "Real-TTY Ctrl-C on a foreground `spm-cache web` (and real default-browser auto-open on a fresh start)."
    expected: "Ctrl-C exits 0 promptly and removes .spm-cache/web/server.json (real-subprocess SIGTERM/SIGINT specs prove the mechanism — my own live runs reproduced exit 0 + marker removal twice); a fresh start without --no-open opens the default browser at the printed URL only after the listener is bound (StartCallback ordering is spec-pinned)."
    why_human: "Real terminal signal semantics and a real OS browser launch are human-observable only; the harness covers the mechanism."
  - test: "DECISION REQUESTED — Live-instance reuse UX (carried WR-02 judgment call, sharpened by live evidence): while a server serves, run `spm-cache web` again in a second terminal."
    expected: "OBSERVED LIVE (this verification, /tmp hermetic project): the second invocation does NOT print 'already running at <url>' — it blocks silently on the .boot.lock flock for as long as the first server serves; when the first exits (exit 0, marker cleared), the second unblocks and boots a NEW instance (new pid, new port, new token). The 'no error, no second server' halves of SC2 hold (lock-enforced); the 'reuses the running instance / prints the URL' reading does not manifest live (marker write AND clear both happen inside the lock, so lock-free + live-marker is unreachable in production). The reuse print is spec-pinned only in a synthetic lock-free scenario (web_lifecycle_spec.rb:466-491). This is exactly the WR-02 lock-hold scope the fixer flagged for eyeball in 13-REVIEW-FIX.md. Decide: accept block-then-replace semantics, or require a lock-free fast-path marker check before the flock."
    why_human: "Product judgment on a documented, spec-pinned, deliberate tradeoff (serialization vs reuse UX); autonomous verifier records evidence, cannot adjudicate SC2 intent."
  - test: "Judgment-tier prohibitions — human confirmation recommended (non-authoritative LLM-judge verdicts recorded below)."
    expected: "(a) Stored-XSS defense: zero innerHTML/insertAdjacentHTML/document.write in app.js (grep-proven this session); every dynamic string flows through el()/textContent — hostile repo strings render inert. (b) Stateless reader / no second mutex: the web layer's entire write surface is its own .spm-cache/web/ dir (marker + boot lock — audited by grep this session); read models are read-only; the build flock remains the only project mutex. Verdict: both SUBSTANTIALLY HONORED by construction. Carried residuals referenced, not re-litigated: WR-04 zero-boundary judgment (0..65535 incl. ephemeral 0 — 13-REVIEW-FIX.md) and phase-12 IN-08 credential-redaction gaps (12-VERIFICATION human item 2)."
    why_human: "verification: judgment prohibitions cannot be closed by an autonomous verifier; the flag must never be a silent pass."
gaps: [] # No truth FAILED, no artifact MISSING/STUB, no link NOT_WIRED, no blocker anti-pattern. Status is human_needed, not gaps_found.
deferred: [] # Graph EDGES are excluded from this phase by REQUIREMENTS DASH-03's own text ("edges deferred pending Swift spike") — an in-requirement scope boundary, not an unmet expectation. No later-phase overlap with any truth.
coincidental_reliance_items: [] # Advisory #1955 check: every VERIFIED truth's evidence runs through real seams (real subprocess SIGTERM/SIGINT, real socket boots, real file fixtures through the real Inventory/Cachemap readers, real gem build). No undeclared-precondition / incidental-ordering / fixture-only reliance identified.
---

# Phase 13: Server Skeleton + Read-Only Dashboard Verification Report

**Phase Goal:** `spm-cache web` serves a localhost-only, fully-offline dashboard showing cache state, doctor health, and the dependency graph — read-only, and hardened against localhost drive-by requests before any mutating endpoint exists
**Verified:** 2026-09-01T07:11:49Z
**Status:** human_needed (17/23 truths verified against live code; 5 client-UI truths present-but-behavior-unverified awaiting the browser walkthrough; 1 carried judgment call (WR-02 reuse semantics) routed for human decision)
**Re-verification:** No — initial verification

## Goal Achievement

Verification basis: LIVE CODE + LIVE RUNS, not SUMMARY claims. At HEAD `049503b` (branch gsd/v0.5.0-web-interface) I ran the phase's twelve spec files myself in three batches:

- `bundle exec rspec spec/web_middleware_spec.rb spec/web_server_spec.rb spec/web_lifecycle_spec.rb spec/web_assets_spec.rb spec/web_signals_spec.rb` → **87 examples, 0 failures** (includes the 15 WR-01..04/IN regression specs added by 13-REVIEW-FIX)
- `bundle exec rspec spec/web_state_spec.rb spec/web_graph_spec.rb spec/web_doctor_spec.rb spec/command_cache_list_spec.rb spec/doctor_spec.rb spec/config_spec.rb` → **102 examples, 0 failures**
- `bundle exec rspec spec/web_frontend_spec.rb spec/web_integration_spec.rb spec/web_packaging_spec.rb` → **119 examples, 0 failures** (frontend spec has grown 67→70 pins from IN-01/02/04 fixes; no pendings)

**308 examples, 0 failures in my own runs** (full suite 787 green is reported at HEAD by the fixer; I relied on my targeted subsets per the hermetic-suite rule). Additionally, TWO independent live boots of the real CLI (`ruby child.rb` → `SPMCache::Main.run(['web','--no-open','--port=0'])` in tmpdir projects) exercised the server over real sockets from my own process: bootstrap 302, index 200, token/Host/Origin rejects, all three API envelopes, asset serving, traversal probe, second-launch behavior, and SIGTERM exit — results quoted per-truth below.

### Observable Truths

Merged must-haves: ROADMAP SC1–SC5 (non-negotiable contract) + deduplicated plan truths 13-01..13-04 (26 declared; folded into the 23 rows below — restatements of an SC keep the SC wording).

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | SC1: `spm-cache web` starts a server bound explicitly to 127.0.0.1 (probing past occupied ports, skipping AirPlay's 5000/7000) and opens the dashboard in the default browser | ✓ VERIFIED | `Server::BIND_ADDRESS = '127.0.0.1'` with the CP9 never-hostname/never-0.0.0.0 rationale (server.rb:14-18); bind asserted on a real ephemeral boot (`web_server_spec.rb:32-38`); skip-list `{5000,7000}` pinned and 5000 proven never-bound by holding 4999 and exhausting (`web_lifecycle_spec.rb:160-169`, port_prober.rb:14-16); my live boot bound 127.0.0.1:59024 via the real CLI. Browser-open fires in `StartCallback` inside `#start` after bind (web.rb:117-127, ordering spec `web_lifecycle_spec.rb:307-311`); `--no-open` suppresses; real-OS launch observation → Human item 4. |
| 2 | SC2: Re-running while a server is live reuses the running instance (marker + pid-liveness — no error, no second server); SIGTERM/SIGINT exits cleanly with cleanup and exit 0 | ⚠️ UNCERTAIN (carried WR-02 judgment — decision requested) | Exit half VERIFIED: real-subprocess TERM and INT both exit 0 with marker removed, SIGKILL leaves an honest stale-dead marker (`web_signals_spec.rb:75-106`); I reproduced exit-0 + marker-removal twice live. Reuse half: "no error, no second server" is lock-enforced and live-confirmed, but the *print-URL-and-return* reading does not manifest live — my live check: a second launch **blocked silently on the boot flock for the first server's entire lifetime**, then (after the winner's exit-0 + marker clear) booted a NEW instance (pid 61175, port 59428 ≠ 59418). Root cause: `boot_and_serve` (marker read AND ensure-clear) runs inside the `File.open(.boot.lock) { flock(LOCK_EX) … }` block (web.rb:53-61), so lock-free + live-marker is unreachable in production; the reuse print is spec-pinned only in a synthetic lock-free scenario (`web_lifecycle_spec.rb:466-491`). This is exactly the lock-hold scope the fixer flagged for eyeball (13-REVIEW-FIX.md, WR-02) — carried per the phase contract, routed to Human item 5. |
| 3 | SC3: Dashboard loads fully offline (all assets vendored, zero CDN); a request with invalid Host/Origin or a missing per-launch token is rejected | ✓ VERIFIED | Offline: my greps over index.html/app.js/styles.css → zero scheme-absolute URLs, zero `cdn.`; cytoscape v3.34.2 vendored (first-line version comment, 435,643 bytes, served from /assets/ — live 200 application/javascript). Rejects: 25-cell route × case matrix + CP13 drive-by trio (foreign-Origin POST w/ valid token → 403, same-Host no-Origin tokenless POST → 401, Origin "null" → 403) on every /api/* route, one real boot (`web_integration_spec.rb:118-155`) — green in my run; my live probes reproduced 401 (no token), 403 (evil Host), 403 (evil Origin) on /api/state. True network-cut reload → Human item 3 (belt-and-braces; the static zero-external-references proof is already green). |
| 4 | SC4: The cache-state table shows per-package size, cached/source state, and fidelity status, re-derived from the same files the CLI reads | ✓ VERIFIED (server half; client half = truth 15) | `ReadModels::State.call` joins `Cache::Inventory.scan` (recursive lstat sizes, `.provenance.json` fidelity) with graph.json statuses + `Cachemap#stats` summary + `poll_seconds` (state.rb:16-49) — specs prove the join by module name, nil-state/has_macro defaults, sidecar fidelity, zeros-when-absent-summary, and per-request re-reads (freshness: graph.json mutation and a newly cached artifact both change the next answer without restart, `web_state_spec.rb:155-180`); one shared scan for CLI + web (`Inventory.scan` call sites: command/cache/list.rb:17, state.rb:16); my live /api/state answered the ok envelope with poll_seconds 5. Client rendering → truth 15. |
| 5 | SC5: Doctor panel runs checks on demand from the check registry (statuses + fix hints, data-driven, cached with timestamp); graph panel renders package nodes via the repaired vendored-cytoscape visualization, with an affordance when graph.json is absent | ✓ VERIFIED (server half; client halves = truths 16–17) | Doctor: `ReadModels::Doctor` runs `Diagnostics.run_all` synchronously only on a truthy `?run=`, swaps `{data, generated_at}` under a Mutex, serves the cache with the RUN's stamp (nil before first run — passed through verbatim by the router, router.rb:153-182); data-driven proof — a stubbed registry check appears in the payload with zero read-model change (`web_doctor_spec.rb:87-99`); torn-cache thread-pair proof (`:132-146`); serve-through envelope proof (`:152-173`); payload is the exact CLI --json shape via the shared `Diagnostics.payload` (diagnostics.rb:53, doctor.rb:67-70). Graph: `ReadModels::Graph` — present flag from File.exist?, nodes via `Cachemap#depgraph_for_viz`, mtime stamp, malformed → 500 envelope (graph.rb:14-24; `web_graph_spec.rb` 8 examples incl. deletion-flips-present freshness); my live /api/graph answered ok/present/1 node/generated_at and /api/doctor (no run) answered has_run:false with nil stamp. Cytoscape rendering → truth 17. |
| 6 | WEB-04 token hygiene: WEBrick access log disabled; marker written 0600 atomically; token never printed or shelled | ✓ VERIFIED | `AccessLog: []` with the token-leak rationale (server.rb:27-33); marker 0600 via Tempfile+chmod-before-rename (marker.rb:43-56) — my live boot observed mode `100600`; spec pins "never sends the token to the shell or stdout" (`web_lifecycle_spec.rb:313-320`); my grep over web/ + command/web.rb: the only UI outputs are the bare already-running URL and a browser-open failure warning — no token-bearing output; bootstrap URL is the only token path (router.rb:97-99). |
| 7 | DASH-03 (server side): GET /api/graph with a valid token returns the {status, data, generated_at} envelope with nodes from `<project>/spm-cache/packages/proxy/graph.json` | ✓ VERIFIED | `web_graph_spec.rb` (present true/false, nodes shape, File.utime mtime stamp, ParserError → error envelope, serve-through, 401 gate) + `web_server_spec.rb` /api/graph envelope group; live-confirmed (truth 5). |
| 8 | Path traversal: /assets/\<anything outside the assets root\> (including encoded .., %2e%2e, ..%2F forms) never resolves outside lib/spm_cache/web/assets | ✓ VERIFIED | Validated-basename resolver: separators/backslashes/../leading-dots/NULs rejected before any FS call + containment check (assets.rb:42-60); unit rejection matrix (`web_assets_spec.rb:46-55`); exact-404s through the real server for every traversal form carrying a target (`:102-111`); bare dot-segment paths never 200 (`:113-119`). My live probe `/assets/%2e%2e%2f%2e%2e%2fconfig.rb` (fully-encoded form) was rejected one layer earlier by WEBrick's request sanitization (400, never 200, never reached the FS) — same security property, different reject layer. |
| 9 | WEB-02 heal semantics: dead-pid / malformed / symlinked marker is cleared and a fresh server starts (0600 atomic write, symlink-rejecting read, pid-liveness) | ✓ VERIFIED | Marker group in `web_lifecycle_spec.rb` (0600 atomic write, symlink read/write behavior, live/dead/unparseable pid); `live?` = parseable pid + `Process.kill(0, pid)` (run_log precedent, marker.rb:79-92); heal path `Marker.clear if marker` before boot (web.rb:65); SIGKILL leaves a stale marker that reads dead — next launch heals (`web_signals_spec.rb:98-106`). |
| 10 | DASH-01: `spm-cache cache list` output is byte-identical after the Cache::Inventory extraction | ✓ VERIFIED | Exact-output spec pins the full printed document; all 10 pre-existing output examples pass unmodified (`command_cache_list_spec.rb` Inventory block, green in my batch 2); sidecar tolerance moved verbatim (inventory.rb:41-52); grep: exactly two production `Inventory.scan` call sites. |
| 11 | DASH-02: the doctor payload shape is EXACTLY the CLI --json shape {checks:[{name,status,message,fix_hint}], summary:{ok,warnings,failures}} — one payload method shared by CLI and read model | ✓ VERIFIED | `Diagnostics.payload` (diagnostics.rb:53-62) is the single definition; `print_json` delegates (doctor.rb:67-70); `doctor_spec.rb` pins string statuses, summary counts, and the exact --json document; the read model normalizes through a JSON round-trip so the cached hash IS its served shape (doctor.rb:64-66). |
| 12 | Envelope discipline: every read model answers through the {status, data, generated_at} envelope; a malformed graph.json (parse-, shape-, or encoding-broken) yields the 500 error envelope | ✓ VERIFIED | `api_read` rescues `JSON::JSONError` + `TypeError`, `api_doctor` rescues `StandardError`-never-Interrupt (router.rb:118-149, 158-171 — the WR-01 fix); live-server regression specs: shape-malformed and non-UTF-8 graph.json → 500 envelopes on BOTH /api/graph and /api/state, hostile doctor check strings → envelope (`web_server_spec.rb`, WR-01 group; green in my batch 1); integration asserts exact envelope keys end-to-end (`web_integration_spec.rb:190-216`). |
| 13 | Poll config: Config#web_poll_seconds Integer-coerces with rescue-to-default 5; /api/state data carries poll_seconds | ✓ VERIFIED | config.rb:30 (DEFAULT 5), :195-199 (coercion); config_spec + state spec default/override examples; my live /api/state carried poll_seconds 5. |
| 14 | WEB-04 (offline/vendored): first-party assets contain zero scheme-absolute URLs and zero cdn. references; vendored cytoscape is committed, served from /assets/, first line records the version, > 300 KB | ✓ VERIFIED | My greps: 0/0/0 matches across index.html, app.js, styles.css; cytoscape.min.js first line `/*! cytoscape v3.34.2 — MIT — vendored… */` with no scheme-prefixed URL, 435,643 bytes on disk and 435,643 bytes served live; offline gate + structural pins green in `web_frontend_spec.rb` (batch 3). |
| 15 | DASH-01 (client): app.js renders the state table from /api/state — columns Package/Config/Size/State/Fidelity, status badges, ◆ macro prefix, mono sizes, exact empty copy | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | Served source read in full this session: COLS, STATUS_CLASS/FIDELITY_CLASS maps, `◆ ${name}`, humanBytes, `'—'` null-state cell, empty state `'No cached packages yet'` + `'Run spm-cache build to populate the cache, then Refresh.'` (app.js:27-33, 105-152) — all pinned by served-source specs (batch 3 green). No JS runtime in CI → actual rendering unexercised → Human item 1. |
| 16 | DASH-02 (client): doctor rows as marker + name + message, '↳ {fix_hint}' second line for non-ok checks with hints, summary line, empty state, 'Cached — generated at {HH:MM:SS}' stamp, Run Doctor → 'Running…' | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | app.js:174-219 read in full: MARKER map ✓/!/✗, `↳ ${fix_hint}`, summary template, has_run empty state, Cached stamp from the SERVER stamp, disabled-while-in-flight button swap — source-pinned (batch 3 green); rendering unexercised → Human item 1. |
| 17 | DASH-03 (client): graph nodes via vendored cytoscape (elements as-served), node colors by status, macro diamonds, legend top-right, exact empty copy naming `spm-cache use` | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | app.js:224-285 read in full: `elements: data.nodes` with no client transform, NODE_COLOR palette, `node[hasMacro="true"]` diamond selector (cachemap.js.template precedent), legend render, empty state copy — plus the IN-01 fix (destroy previous instance before re-create, one `window.cytoscape(` site). Source-pinned; rendering unexercised → Human item 1. |
| 18 | Token bootstrap per locked decision: token moves from location.search to sessionStorage, replaceState cleans the URL to '/' BEFORE first render; every fetch sends X-SPM-Token; token never in DOM; 401/403 replaces panels with the full-page restart copy | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | app.js:10-16 (bootstrap order), :81 (X-SPM-Token header on the single fetch layer), :63-70 (renderTokenInvalid full-page copy), :36-38 (el/textContent-only — token never rendered) — ordering and copy pinned by `web_frontend_spec.rb`; the URL-clean-before-render transition is DOM/History behavior specs cannot execute → Human items 1–2. |
| 19 | State panel auto-polls /api/state at data.poll_seconds (default 5s); header stamp shows the effective interval; a failed poll keeps the last rows and never stops the loop | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | app.js:154-172, 292-303 read in full: pollSeconds from payload, `Updated … · auto-refresh {N}s` stamp, error path keeps rendered rows (`dataset.rendered` check) and the setTimeout loop continues while panels exist; stamps derive from server timestamps only (zero Date.now in the file — my grep). Timer behavior unexercised → Human item 2. |
| 20 | WEB-04 (matrix): for EVERY route the full reject matrix holds — foreign Origin → 403, spoofed Host → 403, absent Origin + no token on /api/* → 401 — and the happy path → 2xx/3xx; from one real ephemeral-port boot | ✓ VERIFIED | Table-driven `ROUTES.product(%i[happy foreign_origin spoofed_host no_token wrong_token])` over `/`, `/assets/styles.css`, `/api/{state,doctor,graph}` — 25 self-naming cells (`web_integration_spec.rb:76-124`), plus the localhost:{port} second allowlist entry (`:236-241`) and the <15 s one-boot runtime pin (`:244-248`, actual 0.18 s reported, 1.17 s for my whole batch-3 run). Green in my run. |
| 21 | WEB-04 (packaging): the built gem ships lib/spm_cache/web/assets/** (all four assets in Gem::Specification.files) AND declares webrick >= 1.8, < 2 as a runtime dependency | ✓ VERIFIED | gemspec:15-16 `{lib,bin,assets,tools}/**/*` glob, :35-40 webrick `>= 1.8, "< 2"` with the CP8 rationale; `web_packaging_spec.rb` pins the four files + glob-ships-the-dir + requirement-window (satisfied_by 1.8/1.9.2, not 2.0/2.1) + a REAL gem-build smoke over a scoped tmpdir tree — green in my batch 3. |
| 22 | The full dashboard answers end-to-end from ONE boot: token bootstrap redirect → index → three assets → three API payloads with valid token | ✓ VERIFIED | Page-load sequence with the three assets parsed FROM the served HTML and content types asserted, plus the 13-02 payload keys per endpoint (`web_integration_spec.rb:157-217`); independently reproduced by my live boot (302 exact-token → 200 index with all three panel titles → 200 assets → ok envelopes). |
| 23 | X-Frame-Options: DENY and Cache-Control: no-store present on every HTML/API response in the integration pass | ✓ VERIFIED | `apply_security_headers` runs first in `Router#service` before any gate/dispatch (router.rb:60-61, 186-191); header sweep over bootstrap+index+all three API responses (`web_integration_spec.rb:219-234`); my live asset response carried `XFO=DENY`. |

**Score:** 17/23 truths verified (5 present-but-behavior-unverified, 1 uncertain — carried judgment call routed for human decision)

### Decision Coverage

`gsd-tools query check.decision-coverage-verify` → `{skipped: true, reason: "no trackable decisions"}` — 13-CONTEXT.md's decisions section carries no trackable `<decisions>` entries for the gate parser. Non-blocking by design; the locked decisions were nevertheless verified directly in code (port probe skip-list, token middleware matrix, offline asset architecture, three-endpoint read-model shape — truths 1/3/4/5/6/7).

### Prohibitions (must-NOT checks)

| Statement | Tier | Status | Evidence |
|---|---|---|---|
| MUST NOT bind any interface other than 127.0.0.1 (CP9) | test | ✓ VERIFIED | Single BIND_ADDRESS constant feeds WEBrick + resolve_port probe; real-boot bind spec (truth 1); no other bind site in web/. |
| MUST NOT log the token anywhere (AccessLog records ?token= URLs; never puts/inspect marker content) | test | ✓ VERIFIED | `AccessLog: []` (server.rb:27-33); shell/stdout-never-see-token spec; marker 0600; my output-statement grep (truth 6). |
| MUST NOT serve a path resolved outside the assets root | test | ✓ VERIFIED | Truth 8. |
| MUST NOT install a second mutex or write any project state — server only reads files and writes its own marker | judgment | ⚠ FLAGGED — unverified-prohibition, human review recommended | Non-authoritative LLM-judge verdict: SUBSTANTIALLY HONORED. My write-surface audit of lib/spm_cache/web/ + command/web.rb: the ONLY writes are Marker (own dir, atomic) and the web-scoped `.boot.lock` in the same dir; read models are pure readers; the build flock remains the only project mutex. The boot lock is launch-serialization in the web's own directory, not a project-state mutex — the honoring is by construction. Human item 6. |
| MUST NOT cache read-model results across requests (state/graph) — only doctor, always with generated_at | test | ✓ VERIFIED | State/Graph are stateless callables; freshness specs mutate graph.json / cache dirs between calls and see changed answers; doctor deletion-flips-present + stamp-passthrough specs (truths 4/5). |
| MUST NOT hard-code check names, counts, or orderings in the doctor read model | test | ✓ VERIFIED | Stubbed-extra-check proof: registry is the sole source (`web_doctor_spec.rb:87-99`); read model contains zero check names (read in full). |
| MUST NOT let `cache list` printed output change by one byte | test | ✓ VERIFIED | Truth 10. |
| MUST NOT mutate the envelope shape {status, data, generated_at} | test | ✓ VERIFIED | Integration asserts exact keys on all three endpoints; error paths share the same envelope (truth 12). |
| MUST NOT reference any absolute URL/CDN/external host in first-party assets (cytoscape byte-exempt, structurally pinned) | test | ✓ VERIFIED | Truth 14. |
| MUST NOT render dynamic strings via innerHTML/string concatenation (stored-XSS defense) | judgment | ⚠ FLAGGED — unverified-prohibition, human review recommended | LLM-judge: SUBSTANTIALLY HONORED — my grep: zero innerHTML/insertAdjacentHTML/document.write/outerHTML in app.js; every dynamic string flows through el()/textContent (file read in full; hostile strings render as text). Human item 6 confirms. |
| MUST NOT deviate from 13-UI-SPEC copy strings / tokens | test | ✓ VERIFIED (served bytes) | Copy-string verbatim pins incl. middots and the '—' em dash (web_frontend_spec.rb, batch 3 green); visual fidelity → Human item 1. |
| MUST NOT introduce a build step, framework, or npm dependency | test | ✓ VERIFIED | app.js is a 320-LOC vanilla ES module (within the 300–400 budget); index.html references exactly three relative assets; no package.json/node surface added (git diff scope). |
| MUST NOT weaken a middleware predicate to make the matrix pass / add new routes in 13-04 | judgment | ✓ VERIFIED (git-proven) | 13-04's two commits (1b6f4df, f12da58) touch only spec/web_integration_spec.rb + spec/web_packaging_spec.rb — zero production edits; middleware.rb's last change is the 13-01 commit; the matrix passed as-shipped. |

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| lib/spm_cache/web/server.rb | WEBrick adapter, 127.0.0.1-only, port-0 pre-resolution, AccessLog off, single servlet, StartCallback | ✓ VERIFIED | 104 lines, read in full; lazy require with install-hint GeneralError |
| lib/spm_cache/web/router.rb | Single catch-all dispatcher; Host/Origin/token gate; envelope helpers; 3 API mounts | ✓ VERIFIED | 212 lines, read in full; gate order Host→Origin→token; WR-01 error-envelope rescues |
| lib/spm_cache/web/middleware.rb | Pure predicates allowed_host?/allowed_origin?/valid_token? | ✓ VERIFIED | Digest-then-XOR fixed-time compare; allowlists derive only from the bound port |
| lib/spm_cache/web/marker.rb | read/write/clear of server.json, 0600, atomic, symlink-rejecting, pid-liveness | ✓ VERIFIED | WR-03 ENOENT-rescue clear + WR-02 pid-guarded clear both present |
| lib/spm_cache/web/port_prober.rb | Skip-list {5000,7000}, bounded upward probe | ✓ VERIFIED | Probe socket closed before return (the 13-01 auto-fix); WR-04 errno rescue |
| lib/spm_cache/web/assets.rb | Traversal-safe static resolution + content types | ✓ VERIFIED | IN-03 dead-code deletion confirmed (no #root reader) |
| lib/spm_cache/command/web.rb | CLAide verb: --port/--no-open, lock, reuse/probe/serve/signal lifecycle | ✓ VERIFIED | Read in full; WR-02 flock + WR-04 range validation present |
| lib/spm_cache/cache/inventory.rb | Shared cache-dir scan | ✓ VERIFIED | One source of truth, two call sites |
| lib/spm_cache/web/read_models/{state,graph,doctor}.rb | Three read models on the CLI's read paths | ✓ VERIFIED | All read in full; state/graph stateless, doctor instance-cached under Mutex |
| lib/spm_cache/core/diagnostics.rb + command/doctor.rb | Shared payload extraction | ✓ VERIFIED | payload at diagnostics.rb:53; print_json delegates |
| lib/spm_cache/core/config.rb | web_dir + web_poll_seconds | ✓ VERIFIED | web_dir at :129-131 (sibling of runs_dir, outside sandbox); poll reader :195-199 |
| lib/spm_cache/web/assets/index.html, styles.css, app.js, cytoscape.min.js | Offline dashboard assets per UI-SPEC | ✓ VERIFIED | index.html 59 lines, app.js 320, styles.css 364, cytoscape 435,643 bytes — all read/grepped; live-served |
| spm_cache.gemspec | webrick >= 1.8, < 2 + files glob shipping assets | ✓ VERIFIED | :15-16, :35-40 |
| .gitignore | .spm-cache/ entry (marker carries the token) | ✓ VERIFIED | :30-31 with rationale comment |
| spec/web_{middleware,server,lifecycle,assets,signals,state,graph,doctor,frontend,integration,packaging}_spec.rb + spec/support/web_server_boot.rb | 12 new/extended spec files | ✓ VERIFIED | All exist; 308 examples across them green in my three batches; boot helper shared, not duplicated |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|----|--------|---------|
| Command::Web#run | Full lifecycle | flock → marker read → live?-reuse / heal → PortProber → Server → Marker.write → traps → start → ensure clear | ✓ WIRED | web.rb:44-92; live-observed end to end (truths 1/2/9) |
| Server | Router | Exactly ONE servlet mounted at '/' — gate uniformity is structural | ✓ WIRED | server.rb:74-75 (mount), :94-100 (service override per verb) |
| Router | Middleware + read models | service → gates → dispatch → ReadModels::{State,Graph,Doctor} → envelope | ✓ WIRED | router.rb:60-100; all three endpoints live-answered |
| Router | Assets | / and /assets/* arms through the validated resolver | ✓ WIRED | router.rb:88-108; assets live-served with correct content types |
| Command::Doctor#print_json AND ReadModels::Doctor | Diagnostics.payload | One shared JSON shape | ✓ WIRED | doctor.rb:67-70; doctor.rb (read model):64 |
| Command::Cache::List AND ReadModels::State | Cache::Inventory.scan | One shared scan | ✓ WIRED | list.rb:17; state.rb:16 (grep: exactly two production call sites) |
| main.rb run-log exclusion | web verb | pre_scan main_log_skipped? still skips the tee for web — the token would otherwise land in argv-captured run logs | ✓ WIRED | main.rb:19-24, unchanged from Phase 12 (load-bearing, verified this session) |
| app.js | /api/state, /api/doctor(?run=1), /api/graph | X-SPM-Token fetch layer consuming the 13-02 payload keys | ✓ WIRED | app.js:78-95 + panel renderers; payload keys match read models exactly (same-wave contract held — zero key reconciliation) |
| index.html | styles.css, cytoscape.min.js, app.js | Three relative-only refs, all served by Web::Assets | ✓ WIRED | index.html:8, 57-58; integration parses refs from served HTML and asserts 200 + content types |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| /api/state | packages/summary/poll_seconds | Cache::Inventory scan of ~/.spm-cache/{debug,release} + proxy graph.json + Config | Yes — real file reads per request; freshness specs mutate files and see changed answers | ✓ FLOWING |
| /api/graph | present/nodes/graph_generated_at | File.exist?/mtime + Cachemap#depgraph_for_viz on graph.json | Yes — live-confirmed with a real fixture graph (present=true, 1 node, ISO stamp) | ✓ FLOWING |
| /api/doctor | checks/summary/has_run | Diagnostics registry run_all → payload (JSON round-trip) | Yes — real registry; hermetic Sh stubs in specs, stubbed-extra-check data-driven proof | ✓ FLOWING |
| index + assets | served bytes | Real files under lib/spm_cache/web/assets/ | Yes — cytoscape served 435,643 bytes = on-disk size | ✓ FLOWING |
| marker | pid/port/token | Real Process.pid + bound port + SecureRandom.hex(32) | Yes — live-observed (token_len 64, mode 0600) | ✓ FLOWING |

No static returns, hardcoded payloads, or mock-only sources anywhere in the chain.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| 13-01 spec set (middleware/server/lifecycle/assets/signals) | `bundle exec rspec spec/web_{middleware,server,lifecycle,assets,signals}_spec.rb` | 87 examples, 0 failures | ✓ PASS |
| 13-02 spec set (state/graph/doctor + cache-list/doctor/config) | `bundle exec rspec spec/web_{state,graph,doctor}_spec.rb spec/command_cache_list_spec.rb spec/doctor_spec.rb spec/config_spec.rb` | 102 examples, 0 failures | ✓ PASS |
| 13-03/04 spec set (frontend/integration/packaging) | `bundle exec rspec spec/web_{frontend,integration,packaging}_spec.rb` | 119 examples, 0 failures | ✓ PASS |
| Real CLI boot over real sockets (my own process, tmpdir project) | spawned `Main.run(['web','--no-open','--port=0'])` + Net::HTTP probes | 302 exact-token bootstrap; 200 index w/ 3 panel titles; /api/state 401/403/403/ok; /api/graph ok; /api/doctor has_run:false nil-stamp; assets 200 w/ DENY; traversal never 200 | ✓ PASS |
| Marker hygiene live | File.stat on the live marker | mode 100600, token 64 hex chars, real pid/port | ✓ PASS |
| SIGTERM contract live | kill -TERM both live servers | exit 0 + marker removed, twice | ✓ PASS |
| Second-launch behavior live | spawn S2 while S1 serves; TERM S1; observe | S2 blocks (6 s: alive, silent, marker untouched) → after S1 exit-0, S2 boots NEW instance (new pid/port) → S2 TERM exit 0 | ⚠ OBSERVED — the carried WR-02 semantics (Human item 5) |
| Offline gate | grep scheme-URLs / cdn. over first-party assets | 0 matches (innerHTML/Date.now also 0) | ✓ PASS |

### Probe Execution

Step 7c SKIPPED — this phase declares no `scripts/*/tests/probe-*.sh` probes; its proof edges are spec files (verified green above) plus the 13-VALIDATION manual table.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|---------------------|----------|----------|
| WEB-01 | 13-01 | 127.0.0.1 server, port probing skipping AirPlay, opens dashboard | ✓ SATISFIED | Truth 1 (browser-open observable → Human item 4) |
| WEB-02 | 13-01 | Re-running while live is idempotent (marker + pid-liveness), not an error | ✓ SATISFIED (code) — UX semantics under human decision | Truths 2/9; WR-02 carried flag (Human item 5) |
| WEB-03 | 13-01 | SIGTERM/SIGINT → cleanup, exit 0 | ✓ SATISFIED | Truth 2 (real-subprocess specs + 2 live reproductions) |
| WEB-04 | 13-01, 13-03, 13-04 | Host/Origin + per-launch token validation; assets vendored, fully offline | ✓ SATISFIED | Truths 3/6/8/14/20/21/23 |
| DASH-01 | 13-02, 13-03 | State table: size, cached/source state, fidelity | ✓ SATISFIED (server verified; client render → Human item 1) | Truths 4/10/15 |
| DASH-02 | 13-02, 13-03 | Doctor on-demand from the registry, cached with timestamp, fix hints | ✓ SATISFIED (server verified; client render → Human item 1) | Truths 5/11/16 |
| DASH-03 | 13-01, 13-02, 13-03 | Graph nodes via vendored cytoscape; empty affordance (edges deferred by the requirement's own text) | ✓ SATISFIED (server verified; client render → Human item 1) | Truths 7/17 |

Orphaned requirements: none — REQUIREMENTS.md maps exactly WEB-01..04 + DASH-01..03 to Phase 13 and the four plans collectively claim all seven.

**Bookkeeping note (non-blocking):** REQUIREMENTS.md still ticks WEB-01/02/03 as `[ ] Pending` while WEB-04/DASH-01..03 were marked Complete by the 13-02/13-03 completion commits; plan 13-01's completion commit never updated its three. The transition step should tick WEB-01/02/03 (code-verified satisfied above).

### Test Quality Audit

| Test File | Linked Req | Active | Skipped | Circular | Assertion Level | Verdict |
|-----------|-----------|--------|---------|----------|-----------------|---------|
| web_middleware/server/lifecycle/assets/signals_spec.rb | WEB-01..04 | 87 | 0 | 0 | Value (exact statuses, exact markers/URLs, real pids) | Strong |
| web_state/graph/doctor_spec.rb | DASH-01..03 | 51 | 0 | 0 | Value (exact row hashes, stamps, thread-pair) | Strong |
| command_cache_list/doctor/config_spec.rb | DASH-01/02 | 51 | 0 | 0 | Value (byte-exact document, exact payload) | Strong |
| web_frontend_spec.rb | WEB-04, DASH-01..03 | 70 | 0 | 0 | Value (verbatim copy/ordering pins, offline gate) | Strong for served bytes (inherent: no JS runtime) |
| web_integration/packaging_spec.rb | WEB-04 | 49 | 0 | 0 | Behavioral (real socket matrix; real gem build) | Strong |

**Disabled tests on requirements:** 0 (grep across all twelve files: no skip/pending/todo patterns).
**Circular patterns detected:** 0 — expected values are fixture-authored or independently computed (e.g. lstat sums in web_state_spec), never captured from the system under test.
**Insufficient assertions:** 0 at requirement level. Documented narrowest cell: /api/state's integration happy path asserts envelope + payload keys only (machine-independence — Inventory's default root is the real ~/.spm-cache); row-level value proof lives in web_state_spec through the real Inventory scan. Accepted.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| lib/spm_cache/web/assets/cytoscape.min.js | 32 | `TODO` string inside the vendored upstream WebGL shader comment (`// TODO make this a vec3`) | ℹ️ Info | Upstream cytoscape 3.34.2 dist bytes, byte-level-exempt class per the plan's own prohibition carve-out (attribution/integrity); not phase-authored debt. No other debt markers in any first-party file (grep: TBD/FIXME/XXX/TODO/HACK/PLACEHOLDER → 0). |

Carried review residuals (documented, deliberately out of fix scope; referenced per the phase contract, not re-litigated): WR-02 lock-hold scope (→ Human item 5, sharpened with live evidence), WR-04 zero-boundary judgment (`--port=0` first-class — 13-REVIEW-FIX.md), phase-12 IN-08 credential-redaction gaps (12-VERIFICATION human item 2).

### Human Verification Required

Six items — see frontmatter `human_verification` for the full test/expected/why_human text:

1. **Real browser walkthrough of the three panels vs 13-UI-SPEC** — covers the behavior-unverified halves of truths 15–17 (DASH-01/02/03 client rendering).
2. **Token bootstrap + auto-poll observation** — URL cleanup to '/', token never in DOM, ≥15 s poll stamp advance, kill-server error resilience (truths 18–19).
3. **True-offline network-cut hard reload** (WEB-04).
4. **Real-TTY Ctrl-C + real default-browser auto-open** (WEB-01/03 observable halves).
5. **DECISION REQUESTED — Live-instance reuse UX (WR-02 lock-hold scope)** — my live evidence shows block-then-replace, not print-and-reuse; accept or require a lock-free fast-path marker check (truth 2).
6. **Judgment-tier prohibition confirmations** — stored-XSS textContent-only posture; stateless-reader/no-second-mutex write-surface audit (both LLM-judged SUBSTANTIALLY HONORED).

### Gaps Summary

No gaps. All artifacts exist, are substantive, are wired, and carry real data; all key links connected; LOGS-01-adjacent exclusion (web verb never writes a run log) intact; requirements fully claimed and code-satisfied; no debt markers in first-party code; no disabled/circular tests. Status is **human_needed** (not passed) because: (a) the five client-side UI truths have no automated behavioral exercise — the repo has no JS runtime, and the phase's own plan designated the browser walkthrough as the behavior check; (b) the carried WR-02 lock-hold-scope judgment call is routed for an explicit human decision with fresh live evidence (second launch blocks, then replaces — mutual exclusion holds, print-and-reuse does not manifest); (c) two judgment-tier prohibitions require human confirmation per the autonomous-mode soft-gate. None of these is a FAILED truth, a missing artifact, or a broken link.

---

_Verified: 2026-09-01T07:11:49Z_
_Verifier: Claude (gsd-verifier)_
