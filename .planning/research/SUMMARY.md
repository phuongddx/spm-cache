# Project Research Summary

**Project:** spm-cache — v0.5.0 "Web Interface"
**Domain:** Localhost developer-tool web dashboard layered onto an existing macOS Ruby CLI + Swift companion (SPM binary caching)
**Researched:** 2026-08-31
**Confidence:** HIGH

## Executive Summary

spm-cache v0.5.0 adds a local web dashboard (`spm-cache web`) to a deliberately zero-web-dependency Ruby CLI. The comparable-tool evidence (Dozzle, Vitest UI, Playwright UI Mode, Renovate, BuildBuddy/Develocity) converges on one shape: a localhost, single-user, foreground process; a single live log stream over SSE (one-way server→client; actions are plain POSTs); no persistence beyond the current run; no auth; fully offline assets. No SPM competitor (Scipio, xccache, Rugby, XCRemoteCache) ships any web UI at all, so even the table-stakes version is a niche first, and the headline differentiator — "start a build in your terminal, watch it live in the browser" — has no competition.

The recommended approach: **the server is a stateless file reader plus a run-log tailer plus a CLI-subprocess spawner — never a second source of truth.** Every dashboard mutation spawns the ordinary `spm-cache` verb (inheriting the existing flock and all code paths); every read re-derives state from the same files the CLI reads (config, sidecars, graph.json, run logs); the build flock stays the only mutex (server probes it, never holds it). Stack verdict (STACK.md): exactly **one** new runtime dependency — `webrick >= 1.8, < 2` — and its gemspec declaration is **load-bearing, not optional**: machine-verified that `require "webrick"` fails on rbenv 3.2.3 and Homebrew ruby 3.3/4.0 without it (bundled-but-not-installed; gone from the bundled set in Ruby 4.0). SSE rides WEBrick's chunked responses; the frontend is vanilla ES2020, vendored, offline; live logs flow through JSONL run-log files at `<project>/.spm-cache/runs/` (outside the sandbox, which is `rm_rf`'d on every slow-path run) written by every CLI run via a tee at `Main.run` plus the existing-but-dormant `Core::Sh` popen3 sink.

Key risks, all with phase-assigned mitigations: the **three-channel output capture problem** (UI puts, `Sh` reader threads, buffered `capture3` — the capture sink at the `Core::UI`/`Sh` boundary is the keystone prerequisite for every streaming feature); **config writeback races** (Singleton `@raw` + bare non-atomic `File.write` — toggles must do fresh-load → delta → atomic rename through mutators shared with `spm-cache off`); **SSE transport traps** (HTTP 204 permanently kills EventSource reconnect — always 503 + `Retry:`; Last-Event-ID replay and bounded per-client queues are required, not nice-to-haves); **localhost is not a trust boundary** (drive-by CSRF and DNS-rebinding against destructive endpoints — Host/Origin validation, per-launch token, array-argv spawns); **unreaped child processes** (Core::Sh never kills xcodebuild/swift children when a run is interrupted — the server's job manager must own process-tree lifecycle from day one); and the **embedded cachemap is a repair job, not a wiring job** — see the discrepancy verdict below.

## Research Discrepancy Resolved (machine-verified verdict)

**Conflict:** FEATURES.md claims `graph.json` has NO edges ("`dependencies: []` verified post-v0.4.0"); ARCHITECTURE.md claims "graph.json already carries cytoscape edges, written by the Swift `GraphGenerator.generate()`" and the template is a husk. Both cannot be true.

**Verdict: FEATURES.md is correct on substance; ARCHITECTURE.md's graph.json claim is FALSE (it cites dead code), though its "template is a husk" claim is TRUE.** Evidence, read directly in this repo 2026-08-31:

1. **`graph.json` is written by `ProxyGenerator.generateGraphJSON`, not `GraphGenerator`.** `GenProxy.swift:56` calls `generator.generateGraphJSON(entries: entries)`, which `JSONEncoder`-encodes the raw `[GraphEntry]` array (ProxyGenerator.swift:247-254). The output shape is `[{"module":…, "status":…, "hasMacro":…, "dependencies":[]}, …]` — **not** the cytoscape `{data: {…}}` elements form.
2. **Both `GraphEntry` construction sites hard-code `dependencies: []`** — ProxyGenerator.swift:90 and :170. Nothing populates dependencies anywhere.
3. **`GraphGenerator.swift` is dead code.** Its cytoscape-shaped node/edge writer exists but has **zero callers** across `Sources/` and `Tests/`. ARCHITECTURE.md's "already a complete cytoscape elements array: nodes *and* edges" describes code that never runs.
4. **The Ruby consumer confirms the raw shape:** `cache/cachemap.rb#depgraph_for_viz` reads `entry["module"]`/`entry["status"]` directly (no `["data"]` unwrap) and maps *every* entry to a node — so it both expects the raw shape and would corrupt edge entries if edges existed.
5. **The template husk claim is confirmed:** `cachemap.html.template` contains the malformed ERB tag `< %= data % >` (spaces inside the tags → renders as literal text; proven by executing the ERB render) and has **no rendering library and no render call** — no cytoscape script tag, no vendored file.

**Roadmap consequence — "embed graph" is two separable work items, and only the first is small:**

- **(a) Repaired nodes view (small, v0.5):** transform the raw entries array → cytoscape elements (server- or client-side), vendor cytoscape.js into `assets/web/`, and render it as a dashboard panel (the standalone template is beyond patching — replace, don't fix, its inline script).
- **(b) Real edges (separate, cross-language, post-v0.5):** populate `GraphEntry.dependencies` in ProxyGenerator.swift (requires deriving package-dependency data that the current generation pipeline never assembles — genuinely unresearched), then revive or delete the dead `GraphGenerator`, extend the live writer to emit edge entries, and update `depgraph_for_viz`/Ruby consumers to stop mapping edge entries as nodes. Plan a spike before committing this to a phase.

**Second, smaller disagreement adjudicated here:** STACK.md recommends a UDS NDJSON relay for terminal/`watch` runs; ARCHITECTURE.md rejects UDS in favor of append-only JSONL run-log files the server tails. **Recommend ARCHITECTURE.md's file-tail transport**: replay from byte 0 on connect (UDS loses everything before connection), works when the CLI run predates the server, survives server restarts (orphan adoption via run-log header pid + liveness), CLI behavior unchanged when no server exists, and it makes UI-triggered and terminal runs *one* mechanism — the UI-triggered build is just a spawned CLI subprocess writing the same run log. Keep UDS as the documented fallback (sandboxed environments that forbid socket files). Note this overrides STACK.md's UDS recommendation; its other verdicts stand.

## Key Findings

### Recommended Stack (from STACK.md, as amended above)

One new runtime gem, everything else stdlib and reuse:

- **webrick `>= 1.8, < 2`** — the only new dependency (pure Ruby, zero transitive deps, ruby/org-maintained). The gemspec `add_dependency` line is **load-bearing**: `require` fails on every target runtime without it (CP8); add a smoke spec asserting the require succeeds outside a Bundler context. `HTTPResponse#chunked=` (verified in 1.9.2 source) provides SSE streaming.
- **SSE (`text/event-stream`), not WebSocket** — logs are one-way; `EventSource` gives auto-reconnect, `retry`, and `Last-Event-ID` resume natively. WebSocket would mean hand-rolled RFC 6455 framing or a second gem for a problem the dashboard doesn't have.
- **JSONL run logs at `<project_dir>/.spm-cache/runs/`** — header line (`run`, `command`, `argv`, `pid`, `started_at`), body lines (`ts`, `stream`, `text`), exit line. Written by *every* CLI run (tee at `Main.run`, skipping `web` itself) + the `Core::Sh` popen3 branch as file-only sink. **Location is deliberate: outside the sandbox**, which `recreate_dirs` destroys mid-run (same reason the build lock lives at project level).
- **Vanilla ES2020 JS, vendored, offline** — no npm, no CDN, no build step; gemspec already ships `assets/**/*`.
- **Reuse, don't rebuild:** UI-triggered builds spawn the real CLI via Open3 (inherit flock + code paths); toggles call `Core::Config` mutators shared with `off`; cache table reuses the `cache list` glob+sidecar scan (sizes are a trivial addition); doctor reuses `Diagnostics.run_all` + extracted JSON payload; busy state = non-blocking flock probe; `cachemap.html.template`'s data contract informs the vendored-graph panel.
- **Rejected:** Puma/Falcon (native-ext compile under keg-only ruby / 12+ transitive deps), Sinatra/Roda (weight for ~10 endpoints — revisit past ~15), `websocket-driver`, Redis/any broker, htmx 4 (3 days old), any Swift-side HTTP server (GCDWebServer unmaintained; Ruby must own config/lockfile/flock), and hand-rolled `TCPServer` HTTP (fallback only if the webrick declaration is forbidden).

### Expected Features (from FEATURES.md)

**Must have (table stakes — all P1 for v0.5):**
- `spm-cache web`: localhost server (127.0.0.1 hard-coded, no `--host` flag), port probe skipping 5000/7000 (AirPlay), marker-file idempotent relaunch, browser auto-open, watch-style signal contract
- Single live build-log stream with per-package anchors (build loop is sequential — N panes would be N empty boxes), replay-on-load, auto-reconnect without lost lines, visible stale/connection state
- Run identity (trigger source UI/terminal/watch, config, started-at, running/success/failure) + external-run detection via the existing `.spm-cache-build.lock` flock
- Build/Rebuild with scope (all/packages) + busy/queued state + failure banner and highlighted errors
- Per-package toggles writing the **same** config `ignore` list `spm-cache off` writes (one source of truth, one code path), with visible "saved ≠ applied" semantics + "Apply now (re-sync)" button
- WHY-not-toggleable reasons per package (ignored-by-pattern / plugin / binary-target / excluded / fidelity — a join of data that all already exists)
- Cache state table: package × config, sizes (new, trivial), cached/source, fidelity status from provenance sidecars
- Doctor panel: on-demand `run_all`, statuses + fix hints + summary, cached-with-timestamp (checks shell out for seconds), data-driven (8 checks today — never hard-code)
- Origin/Host validation on every mutating endpoint; fully offline vendored assets
- Repaired graph **nodes** view (vendored cytoscape + raw-entries→elements transform)

**Should have (differentiators — mostly v1.x):**
- Relayed terminal/`watch` runs live in the browser — *the* headline; with the file-tail transport this falls largely out of the run-log + SSE work (identity attribution and watcher hygiene remain)
- Fidelity status surfaced everywhere (table column, node color, toggle reasons) — pure presentation join over existing data
- Graph edges (Swift `GraphEntry.dependencies` populated) + cache-state overlay during runs
- "Rebuild what drifted" prefill (DiffDetector), doctor fix-hints as copy/deep-link (never auto-execute)

**Anti-features (declined, with reasons):** N per-package log panes (sequential loop); run-history DB with search (Dozzle deliberately stores nothing); remote access/auth (hard localhost-only constraint; new milestone if ever); general yml editor (structured controls for `ignore` only); cross-process build cancellation (cancel UI-triggered runs only — killing other processes' xcodebuild trees races the flock); animated graph re-layout mid-run (passive recolor at fixed positions); notifications (tab title + banner suffice); multi-project server (per-project ports).

### Architecture Approach (from ARCHITECTURE.md, as amended above)

The server adds a layer *around* an unchanged pipeline. It reads the files the CLI reads, probes the lock the CLI holds, and spawns the CLI to act — restartable at any moment because all truth is on disk.

**Major components (new):**
1. `Command::Web` — foreground CLAide entry (auto-registered; no `command.rb` edit); `--port`, `--no-open`; marker file `<project_dir>/.spm-cache/web.json` with pid-liveness for idempotent relaunch; TERM/INT → cleanup → exit 0 (copied from `watch`'s contract)
2. `Web::Server` — thin HTTP adapter + router (webrick under the adapter seam so the stack stays swappable); Host/Origin/token checks as middleware
3. `Web::Api` — read-model endpoints (`/api/state`, `/api/packages`, `/api/doctor[+/run]`, `/api/cachemap/graph`) + action endpoints (`/api/build`, `/api/toggle`); fresh reads per request, never cached across requests
4. `Web::Events` — runs-dir tailer (mtime polling, `Core::Watcher` precedent) → SSE broadcaster with byte-offset event ids, `Last-Event-ID` replay, ~15s heartbeats, bounded per-client queues (drop-oldest + explicit notice)
5. `Web::Jobs` — single-slot build launcher: `Process.spawn` array-argv of the CLI, pid/status tracking, orphan re-adoption from run-log headers, 409 on a second UI build
6. `Core::RunLog` — JSONL writer + `$stdout`/`$stderr` tee installer; implements the exact `output(line)` contract `Core::Sh` already expects

**Modified (small, deliberate):** `main.rb` (tee, skipped for `web` argv), `core/sh.rb` (popen3 branch as file-only sink; fix its discarded-capture gap so `failure_detail` regains detail — behavior-preserving for the terminal, which never showed raw xcodebuild output), `core/config.rb` (`runs_dir`, `web_dir`, `disable_caching!/enable_caching!`, atomic tempfile+rename save), `command/off.rb` (route through the mutator — clean cutover), `command/init.rb` (gitignore `.spm-cache/`), `command/cache/list.rb` + `command/doctor.rb` (extract read-models both CLI and server share), one "waiting for build lock…" line in the Installer so queued UI builds are visible. **Not modified:** pipeline internals, watcher, Swift companion (except the future edges work).

**Concurrency stance:** the flock is the only mutex. Server never holds it; UI builds block on it exactly like terminal builds; second UI build → 409; terminal-vs-UI collisions keep today's blocking semantics with a visible "waiting" line; toggle mid-build is an atomic write that applies next regen; server killed mid-build → subprocess orphans *by design* and the restarted server re-derives state from run logs.

### Critical Pitfalls (with phase assignment — full set in PITFALLS.md; CP14 is a grounded addition not present in PITFALLS.md)

1. **CP3 — three-channel output capture (CRITICAL, foundation keystone):** visible output lives in `Core::UI` puts (non-injectable), `Sh` reader threads, and buffered `capture3`; `LiveLog` is unbounded and prints TTY cursor codes unconditionally. Build the injectable sink at the `Core::UI` boundary + file-only `Sh` sink + ring buffer first — every streaming feature consumes it. Thread-safety: one writer thread per SSE response, sized `Queue`s.
2. **CP8 — webrick unavailable without declaration (CRITICAL, foundation):** machine-verified `require` failure on rbenv 3.2.3 / Homebrew 3.3 / 4.0. Gemspec runtime dep + post-install smoke spec, before the first `require`.
3. **CP14 — child processes are not reaped on interrupt (NEW — grounded addition contributed by the orchestrator from the original pitfalls researcher; verified here against `core/sh.rb:21-35`):** `Core::Sh`'s popen3 branch has no signal handling, no `Process.kill`, and no `pgroup` spawn option — interrupting a run (Ctrl-C, kill, server shutdown racing a subprocess) orphans the xcodebuild/swift tree, which keeps running and writing artifacts with nobody watching. Two consequences for the web layer: (a) `Web::Jobs` must spawn UI-triggered builds with `pgroup: true` and own process-group termination (`Process.kill(-pgid, …)`) so a future UI-run cancel is *possible* at all — cancel scope stays "UI-triggered only" per the anti-features list, but the mechanism must exist from Phase 4; (b) a run-log whose header pid died without an exit line may still have live grandchildren — the tailer's pid-liveness signal marks the run dead while work continues (Phase 3 detection nuance: surface "run ended, children may linger" rather than claiming clean completion).
4. **CP1/CP2 — config integrity (UI actions; seam in foundation):** stale-singleton writeback through non-atomic `File.write` clobbers concurrent CLI edits; any UI-side toggle store forks the source of truth. Fresh-load → delta → tempfile+rename, under the shared `disable_caching!/enable_caching!` mutators that `off` also calls.
5. **CP11 — SSE transport hazards (relay phase):** 204 stops reconnect *permanently* (503 + `Retry:` instead); buffering, reconnect storms, lost failure lines on reconnect, and unbounded backpressure are each independently fatal. Heartbeats, monotonic ids + `Last-Event-ID` replay from the ring buffer/run log, bounded queues.
6. **CP13 — localhost is not trusted (foundation + UI actions):** any public page can POST to `127.0.0.1:<port>`; endpoints here are destructive (build, rollback `rm_rf`, config writes). Host/Origin validation + per-launch token on mutations; array-argv spawns; validate package/target names against the project's known packages.
7. **CP4 — rollback runs without the build lock (UI actions):** wrap `Installer::Rollback` in the flock before any rollback button ships; decide busy-vs-queue for Build (recommend: busy, derived from the lock — never silent queueing from a stray click).
8. **CP9 — loopback binding traps (foundation):** `localhost` resolves `::1` first on this Mac; AirPlay owns 5000/7000. Bind explicit `127.0.0.1`, print the exact URL, probe/skip ports, persist the choice.

Also carried forward: CP5 (legacy `--watch` path must be excluded from the relay — hook only the watcher daemon), CP6 (own the watcher lifecycle: forward SIGTERM; extend the self-trigger guard to web-originated runs), CP7 (keep the 441-example hermetic suite — seam-tested units, at most one port-0 integration spec), CP10 (derive "build running" from the flock + run logs, never server memory), CP12 (health-check-before-open launcher; explicit env on spawned builds).

## Implications for Roadmap

Five phases; ordering is dependency-driven (nothing to stream without run logs; no SSE without a server; build controls ride the stream; toggles are the last, only-state-writing surface). This preserves ARCHITECTURE.md's A–E build order with the graph verdict and pitfall mapping folded in.

### Phase 1: Run-Log Capture Foundation (no server)
**Rationale:** the capture sink is the keystone every streaming feature consumes; it is independently testable and hermetic.
**Delivers:** `Core::RunLog` (JSONL writer, `output(line)` sink), `Main.run` tee (skipped for `web`), `Core::Sh` stream mode as file-only sink (fixing the discarded-capture gap), `Config#runs_dir`/`web_dir`, retention policy. Proves: every CLI run (build/use/watch) leaves a queryable log, terminal behavior byte-identical.
**Addresses:** FEATURES keystone prerequisite. **Avoids:** CP3.

### Phase 2: Server Skeleton + Read-Only Dashboard
**Rationale:** establish the HTTP adapter, security middleware, and read-models before anything streams or mutates.
**Delivers:** `Command::Web` (watch-style lifecycle, marker relaunch, port probe skipping 5000/7000, auto-open), webrick gemspec declaration + require smoke spec, `Web::Server` adapter with Host/Origin/token middleware, read endpoints, extracted `Cache::Inventory` + `Diagnostics.json_payload`, cache state table (with sizes + fidelity), doctor panel, repaired graph **nodes** panel (vendored cytoscape, raw→elements transform, "run Integrate to generate" affordance when graph.json is absent).
**Addresses:** web entry point, table, doctor, graph nodes. **Avoids:** CP7, CP8, CP9, CP13.

### Phase 3: Live Streaming + Terminal/`watch` Relay
**Rationale:** with run logs (P1) and a server (P2), streaming is one tailer + one broadcaster — and because the transport is the shared run log, terminal/`watch` relay is the *same* mechanism, not a second feature.
**Delivers:** `Web::Events` tailer + SSE (byte-offset ids, `Last-Event-ID` replay, heartbeats, bounded queues, 503-not-204), log-view frontend (single stream + anchors, follow-tail with scroll lock, connection pill, failure banner), run identity + attribution, relay hygiene (watcher-daemon-only subscription, SIGTERM forwarding, web-run self-trigger guard), "waiting for build lock…" line in the Installer, honest handling of pid-dead-without-exit-line runs (CP14 detection nuance).
**Addresses:** live stream, replay, reconnect, relay headline, run identity. **Avoids:** CP5, CP6, CP10, CP11, CP12.

### Phase 4: UI Build Controls
**Rationale:** build triggers are the first destructive mutations; they inherit P2's security middleware and P3's stream (the moment this lands, "trigger from UI, watch it stream" is complete end-to-end).
**Delivers:** `Web::Jobs` single slot (409 on second), `POST /api/build` spawning the CLI (array argv, explicit env, **`pgroup: true` + process-group kill capability per CP14**), lock-probe busy state in `/api/state`, scope selection, failure surfacing with exit status, rollback wrapped in the flock, busy-vs-queue decision implemented.
**Addresses:** build/rebuild button, busy states, failure surfacing. **Avoids:** CP4, CP13 (param validation), CP14 (mechanism).

### Phase 5: Toggles + Panel Completion
**Rationale:** the only phase that writes user state — lands last, on top of hardened read paths and P4's job machinery ("Apply now" = spawned `spm-cache use`).
**Delivers:** `Config#disable_caching!/enable_caching!` + `off` refactor (one code path), atomic save, `POST /api/toggle`, pending/apply UX ("Saved — applies on next sync"), WHY-not reason join (pattern-managed entries read-only), `init` gitignore entry for `.spm-cache/`.
**Addresses:** toggles, pending visibility, reasons. **Avoids:** CP1, CP2.

**Post-v0.5 (explicitly out of the milestone):** graph **edges** (Swift spike first — see Gaps), cache-state overlay on the graph, UI-run cancel (possible once P4's process-group machinery exists), drift-prefill scope, then the deferred list (history, remote+auth, multi-project).

### Phase Ordering Rationale
- **Dependencies discovered in research:** capture sink precedes everything streamed (FEATURES dependency graph); server precedes SSE and jobs; stream precedes build controls (their output must be visible); toggles last because they are the only state writers and can reuse job machinery for "Apply".
- **Grouping by architecture:** P1 is pipeline-adjacent (Core only); P2–P4 are the new `web/` layer in risk order (reads → streams → mutations); P5 closes the config-write surface.
- **Pitfall avoidance by construction:** CP3 is P1's exit criterion; CP7/8/9/13 are P2's; the transport hazards CP10/11 are P3's design constraints, not afterthoughts; CP14's process-group mechanism is built into P4's Jobs rather than retrofitted; CP1/2/4 are exactly P4/P5 scope.

### Research Flags
Phases likely needing deeper research during planning:
- **Phase 3:** heaviest integration surface — SSE lifecycle/backpressure details plus watcher interplay (CP5/CP6/CP10/CP12 all land here). Research exists but is MEDIUM in its transport-practice sections; recommend `--research-phase` or an especially careful plan review.
- **Graph edges (future phase):** genuine spike required — how to derive per-package dependency data (Package.resolved carries no graph; candidates are pbxproj/XcodeProj analysis or `swift package dump-package`), plus the writer/Ruby-consumer shape change. Unresearched; do not schedule without a spike.

Phases with standard patterns (skip research-phase):
- **Phases 1, 2, 4, 5:** code-anchored seams verified in this repo (`output(line)` contract, CLAide auto-registration, flock probe, config mutators); research is HIGH and implementation patterns are established.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Every version verified 2026-08-31 against RubyGems/stdgems/Homebrew APIs; webrick absence machine-probed on all three target rubies; one internal amendment (transport: file-tail over UDS) adjudicated in this summary |
| Features | HIGH | Every in-repo capability claim read or executed against this repo; competitor facts source-verified (MEDIUM only for BuildBuddy/Develocity IA details — non-load-bearing) |
| Architecture | HIGH | Every integration seam at file:line in this repo; MEDIUM for SSE streaming-pattern details. One ARCHITECTURE.md claim (graph.json cytoscape edges) **falsified** and corrected above — resolved, with the dead-code writer identified |
| Pitfalls | HIGH | Code-anchored + machine-probed (webrick matrix, `::1` resolution, AirPlay ports); MEDIUM sections are well-established web/platform canon, flagged as not re-derived; CP14 added from the original researcher's grounded finding and re-verified against `core/sh.rb` in this synthesis |

**Overall confidence:** HIGH — an unusually well-grounded research set; the one material discrepancy was resolved against source rather than argued.

### Gaps to Address

- **Graph-edge data source (spike required):** nothing in the current Swift pipeline assembles package dependencies. Options (pbxproj analysis vs `swift package dump-package`) unexplored. Handle: spike before scheduling an edges phase; v0.5 ships nodes only.
- **Transport adjudication:** this summary recommends ARCHITECTURE.md's file-tail over STACK.md's UDS. Handle: confirm during Phase 1 planning; UDS remains the documented fallback for sandboxed environments.
- **Default port:** research offers two examples (7915 / 7960) — pick one in planning; must skip 5000/7000, probe on conflict, persist the choice (CP9).
- **`--log-dir` stub:** parsed but consumed by nothing today. Decide in Phase 1: repurpose as the run-log dir override (preferred — makes the stub real) or remove it; never leave two dead knobs.
- **Pattern-authored ignore entries:** UI renders them read-only ("managed by pattern in spm-cache.yml") per ARCHITECTURE §5; confirm with the user during discuss whether an edit-patterns affordance is wanted later (recommended: defer).
- **Mutation auth depth:** STACK says header checks suffice; CP13 recommends a per-launch token. Cheap either way; recommend the token since endpoints trigger builds and `rm_rf` — settle in Phase 2 planning.
- **Toggle file-rewrite visibility:** toggling (like `off` today) rewrites `spm-cache.yml` without preserving user comments — acceptable, but surface it in the UI's undo affordance copy rather than silently surprising hand-maintained configs.

## Sources

### Primary (HIGH confidence)
- RubyGems API — versions + runtime-dep lists: webrick 1.9.2, puma 8.0.2, falcon 0.57.0, sinatra 4.2.1, roda 3.107.0, rack 3.2.7, websocket-driver 0.8.2, nio4r 2.7.5
- stdgems.org — webrick bundled-gem 3.0–3.4, removed in 4.0; erb default-gem status
- Homebrew formula API — ruby 4.0.6 default, ruby@3.3 3.3.12 pinned production
- webrick 1.9.2 source — `HTTPResponse#chunked=` verified; pure Ruby
- MDN "Using server-sent events" + HPBN — EventSource reconnect/`retry`/`Last-Event-ID`; WHATWG SSE spec — 204 terminates reconnection (CP11)
- Oligo Security "0.0.0.0 Day" — localhost drive-by/CSRF threat model (CP13); Chrome 141/142 Local Network Access behavior
- Dozzle, Playwright UI Mode, Vitest UI, Renovate Dashboard, Gradle Build Scans docs — UX patterns and storage postures

### Repository (VERIFIED 2026-08-31, HIGH)
- Code: `core/{sh,live_log,config,watcher,diagnostics}.rb`, `main.rb`, `command/{off,doctor,base,cache/list,watch}.rb`, `installer/{build,use,rollback}.rb`, `installer/integration/viz.rb`, `spm/pkg/proxy.rb`, `cache/cachemap.rb`, `assets/templates/cachemap.{html,js}.template`, `spec/spec_helper.rb`, `spm_cache.gemspec`
- Conflict resolution (this synthesis): `tools/spm-cache-proxy/Sources/CLI/GenProxy.swift:56`, `Core/Generator/ProxyGenerator.swift:16-30, 64-90, 121-170, 247-254`, `Core/Generator/GraphGenerator.swift` (zero callers), `lib/spm_cache/cache/cachemap.rb:58-64`, `lib/spm_cache/assets/templates/cachemap.html.template`
- CP14 verification (this synthesis): `lib/spm_cache/core/sh.rb:21-35` — popen3 block with no signal handling, no `Process.kill`, no `pgroup` spawn option
- Machine probes: `require "webrick"` fails on rbenv 3.2.3 / Homebrew ruby 3.3 & 4.0; `localhost` → `::1` first (dscacheutil); AirPlay ControlCenter holds TCP 5000/7000

### Secondary (MEDIUM confidence)
- BuildBuddy README — invocation-centric IA (vendor description, no walkthrough)
- SSE buffering/practitioner writeups (stackoverflow, oneuptime 2026-01); Ruby threaded-IO guidance; localhost web-security canon (CP13 MEDIUM clauses)

---
*Research completed: 2026-08-31*
*Ready for roadmap: yes*
