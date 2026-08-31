# Feature Research

**Domain:** Local web dashboards for developer/build tools (applied to spm-cache's six v0.5.0 target features)
**Milestone:** v0.5.0 — Web Interface
**Researched:** 2026-08-31
**Confidence:** HIGH for in-repo capability facts (every claim read or executed against this repo) and for primary-source UX patterns (Dozzle, Playwright, Renovate, MDN, Oligo); MEDIUM for BuildBuddy/Develocity information-architecture details (vendor descriptions, not UI walkthroughs)

> Scope note: the existing CLI (use/build/rollback/off/watch/doctor/init/cache/remote) is treated as shipped substrate and not re-researched. Everything below is scoped to what the six NEW features need, with each feature's dependency on verified existing capability called out. Server-stack choice (stdlib vs gem) is deliberately out of scope here — see STACK.md; this document frames the *feature* requirements that stack choice must satisfy.

---

## What Comparable Tools' Web UIs Actually Do (the evidence base)

| Tool | What its web/dashboard UI is | Log streaming model | State-changing actions | Storage posture |
|------|------------------------------|--------------------|------------------------|-----------------|
| **Dozzle** (14.2k★, Go+Vue) | Real-time container log viewer. Deliberately stores **no logs** — "designed purely for live log viewing", explicitly disclaims offline search. Features: fuzzy container search, regex/SQL log search, **opt-in split screen** for multiple logs, live CPU/mem stats, dark mode. | Server→browser stream via **SSE** (`EventSource` component in its frontend); default is one merged stream per container, split view is a choice. | None of consequence — it is a viewer. | **Zero persistence**, by design. |
| **Playwright UI Mode** | Browser test dashboard: sidebar of test files, expand file/block/test, **run scope selection** (all / file / block / single test), per-item **watch toggle** (eye icon), filter by status, Errors tab pinning failures. | Runs stream into the selected item; results land per-node in the tree. | Run/watch/debug per scope — granular triggers with obvious disabled/active states. | Session-scoped traces, not a history DB. |
| **Vitest UI** | Interactive browser UI, **requires a running server in watch mode** — the dashboard IS the watch loop's face. | Live per-file results; reruns land in place. | Re-run filters/files from the browser. | In-memory. |
| **Renovate Dependency Dashboard** | One issue/page summarizing all **pending** dependency updates. Key semantics: pending updates stay **visible** (including *closed/ignored* ones, with a checkbox to re-apply later); an **approval workflow** can gate which updates are allowed to proceed. | N/A (not a log tool) | Explicit "apply this deferred thing" affordances; deferred ≠ forgotten. | The dashboard IS the pending-state surface. |
| **BuildBuddy** (Bazel) | "Collect, view, share and debug build events in a user-friendly web UI" — **invocation-centric**: everything hangs off a build invocation page (per-invocation logs, target rollups via API). | Streams build events per invocation; replay from the invocation record. | Re-run patterns in the enterprise product. | Persistent invocation store (server product). |
| **Develocity/Gradle Build Scans** | Post-hoc per-build pages: timeline, console log, dependency insight, durations broken out (startup / configure / resolve / execute). Plus a **Live Build Timeline** view in the IDE plugin. | Live timeline during the run; full scan after. | None — analysis only. | Full scan history (enterprise scale). |
| **Browser threat model (Oligo "0.0.0.0 Day")** | Not a tool — the security constraint every localhost dashboard inherits: public websites **can dispatch requests to localhost services** from the visitor's browser; local services that skip CSRF/origin validation "because they run in a strictly controlled environment" are exploitable, and **a single request can be enough** (ShadowRay RCE demo). Chrome PNA + Safari now block 0.0.0.0; coverage is not uniform. | — | — | — |

**SSE/EventSource mechanics (MDN / HPBN, HIGH):** the browser reconnects automatically after a drop, `retry:` sets the backoff, and `Last-Event-ID` carries the last seen id so a server can **resume without data loss**. This is the reconnect+replay backbone Dozzle-class viewers rely on, and it matches the milestone's streaming needs with one-way server→client flow (client actions are plain HTTP POSTs).

**The two patterns that matter most for spm-cache:**
1. **Single stream with structure beats parallel panes.** Every log-centric comp (Dozzle, CI viewers, xcodebuild-based tooling) presents one primary stream; multi-pane views are opt-in extras. xcodebuild output is inherently one sequential stream, and spm-cache's build loop is literally sequential (`missed.each { build_single_target … }`, verified in `installer/build.rb:50-52`) — N per-package panes would be N mostly-empty boxes.
2. **Deferred decisions must stay visible with an explicit apply affordance (Renovate).** spm-cache's toggle semantics today are already deferred: `off` writes the `ignore` list and prints "Run 'spm-cache' to use source mode for these targets" (verified in `command/off.rb`). A toggle button that silently edits yml while the running integration keeps the old state is the exact trap Renovate's dashboard exists to prevent.

---

## Feature Landscape

### Table Stakes (Users Expect These)

| Feature | Why Expected | Complexity | Notes / Dependencies |
|---------|--------------|------------|----------------------|
| **`spm-cache web` starts a localhost server and opens the dashboard bound to the current project** | The entry point. Every comp (Dozzle, Vitest UI, Playwright `--ui`) is one command → browser opens on the right context. Users will assume the dashboard reflects the project in the CWD. | LOW | New subcommand (claide pattern exists, verified across `command/*.rb`). Needs: bind 127.0.0.1 (constraint), port pick + conflict handling, `open` the browser. Project context = `Core::Config.instance` singleton already CWD-scoped (verified). |
| **Single live build-log stream with per-package anchors** | Dozzle/CI/xcodebuild convention: one primary stream, structured by anchors, not N panes. The build loop is sequential (k-of-N), so a single stream with "Now building:_pkg_" headers matches reality 1:1. | MEDIUM | Requires a **log capture sink**: today logging is bare `puts` via `Core::UI` (verified `core/log.rb`) and `LiveLog` captures in-memory per process only (verified `core/live_log.rb` `@captured`). UI-triggered runs can feed an in-server buffer directly (server owns the child); relayed runs need the capture to live where the run lives. |
| **Replay on page load** (open/reload the tab mid-build → see the log so far, then live) | Users open the dashboard *after* kicking off a build or after a refresh. Dozzle shows recent history while streaming; MDN's Last-Event-ID resume is the transport half. A stream that only shows "from now" fails the basic expectation. | MEDIUM–HIGH | Server-side per-run ring buffer for UI-triggered runs (server owns them — easy). **For terminal/`watch` runs this is the hard half: nothing persists today** — verified: no log file writing exists anywhere in `lib/` (grep: no Logger, no log paths, no stdout redirection). The relay mechanism must persist the external run's output somewhere the server can read (file tail or event push — STACK.md decision). Replay + reconnect share the event-id/offset protocol; design them together. |
| **Auto-reconnect without lost lines + visible stale/connection state** | Every user will at some point sleep the Mac or the tab will throttle. EventSource gives auto-reconnect + `retry` + `Last-Event-ID` natively (MDN, HIGH); Dozzle-class viewers hide reconnects entirely. A silently-dead stream is worse than an obviously-dead one. | LOW | Frontend: `EventSource` + a connection-status pill fed by `onerror`/`onopen`. Server: honor `Last-Event-ID` by replaying buffered events after the id. Depends on: per-run event buffer with monotonic ids (shared with replay-on-load). |
| **Run identity: which run am I looking at** (trigger source UI / watch / terminal, config name, started-at, running/success/failure badge) | Invocation-centric IA is the BuildBuddy/Develocity consensus; without identity, a relayed `watch` sync and a UI build are indistinguishable. Also the only way to answer "is that log I'm reading still going?" | MEDIUM | New lightweight run registry (in-server). **External-run detection primitive exists**: the project-level `.spm-cache-build.lock` flock is already shared by `Installer::Build` and `Installer::Use` incl. watch (verified `installer/build.rb:64-74`, `use.rb:60-71`) — the dashboard can show "external run in progress" by probing the lock. Attribution (watch vs terminal vs Xcode-invoked) needs the relay protocol to carry a source tag. |
| **Build/Rebuild button with scope selection: all / specific packages, with busy state while any run holds the build lock** | Playwright UI Mode's run affordances are the pattern: run-all triangle + per-item run, with obvious active states. For spm-cache the lock is real: a second concurrent build must not be offered silently — it would block on the flock for the entire first build (verified blocking `flock(LOCK_EX)` semantics). | LOW–MEDIUM | Scope = pass targets to `Installer::Build` (targets arg exists, verified; `expand_target_aliases` already maps package identities → product names). Disabled/queued state derived from probing the flock. **UI-triggered runs must join the same flock** — never bypass the existing serialization. |
| **Failure surfacing: end-state banner, error lines highlighted, non-zero exit shown** | Playwright pins failures in an Errors tab; doctor already uses ✓/!/✗ markers with fix hints. Users must not scroll a 5k-line stream to learn the build failed. | LOW | Child exit status + stderr already distinguishable for server-owned runs. For relayed runs the relay protocol must carry a final status event. Reuse the marker/fix-hint visual language from doctor for consistency. |
| **Per-package cache toggles that write the SAME config `ignore` list `spm-cache off` writes** | One source of truth (milestone constraint, and verified: `off` appends to `config.raw["ignore"]` + `Config#save`; `should_ignore?` consults it with `File.fnmatch` globs). A separate dashboard-only state would fork the config and rot. | LOW | POST toggle → `Config` load/mutate/save. Must round-trip yml preserving unrelated keys (Config#load merges over DEFAULT_CONFIG and dumps — verified; byte-stability of user comments is NOT preserved today — toggling from the UI rewrites the file, same as `off` does today; acceptable, but say so in the UI's undo affordance). |
| **Pending/apply semantics made visible: toggle saved ≠ applied; show what a re-sync will do** | Today's contract is literally "edit config, then re-run `spm-cache`" (verified `off` output). Renovate's lesson: deferred states must be VISIBLE with an explicit apply affordance or users conclude toggling is broken when behavior doesn't change. | MEDIUM | Toggle UX: flip → "Saved — applies on next sync" + a prominent "Apply now (re-sync)" button that runs `Installer::Use` (the fast path exists and is proven). The toggle row shows state triplet: cached / source (applied) / source (pending). Depends on: run registry + trigger (exists per above rows), `Installer::Use` (exists). |
| **Show WHY a package can't be toggled or is stuck in source mode** | Competitor-adjacent lesson (v0.4.0 research): invisible decisions become support threads. spm-cache already has the vocabulary: graph statuses `hit/missed/ignored/excluded/plugin` (verified in `cache/cachemap.rb`), provenance `fidelity_status` sidecars (verified in `command/cache/list.rb`), and doctor fix hints. Plugin-only and binary-target packages can't be cached — the UI must say that inline, not just render a dead toggle. | MEDIUM | Reason = join of: config `ignore` (incl. matching GLOB — a target may be ignored by pattern, so resolve which pattern matched), graph status, `cache_only`, fidelity status. All inputs exist; the work is the join + copy. Depends on: graph.json (exists), provenance sidecars (exist), lockfile (exists). |
| **Cache state table: per-package × configuration with size + cached/source + fidelity status** | The milestone's own definition, and the natural "home screen". `cache list` already enumerates `~/.spm-cache/{debug,release}/*.xcframework` and reads `fidelity_status` from provenance sidecars (verified); **sizes are not computed today** (verified — trivial `File.size`/du addition). | LOW–MEDIUM | Sortable/filterable table; debug/release split (per-config caching exists); total-size summary. Depends on: cache list data source (exists), sidecars (exist), graph.json for join (exists). |
| **Doctor panel: run checks on demand, show status/message/fix-hint/summary** | Milestone target; trivially grounded — `Core::Diagnostics.run_all(config:)` returns exactly `{name, status(:ok/:warn/:fail), message, fix_hint}` and the JSON shape already exists (verified `command/doctor.rb`). **Checks shell out** (`xcodebuild -version`, `swift --version`, …) so they take seconds — not page-load work. | LOW | POST /doctor/run → run_all in-process → render. Busy state + "last run at" timestamp. Render whatever the registry returns — it is data-driven and already grew past the "7-check" count (8 registered today, verified `core/diagnostics.rb`) so the panel must not hard-code checks. |
| **Origin/Host validation on every mutating endpoint (build trigger, toggle save, doctor run)** | 0.0.0.0 Day (HIGH): localhost binding is NOT origin protection — browsers dispatch cross-site POSTs to localhost from public pages, and one request can trigger real damage. `POST /build` on a dashboard that shells to xcodebuild is precisely the "local service that skipped CSRF checks" profile. | LOW | Validate `Host` is 127.0.0.1[:port] / `[::1]` and `Origin` (when present) matches, on all non-GET routes. Cheap header checks; no tokens/auth needed for a localhost-only tool (see Anti-Features). |
| **Fully offline dashboard: all JS/CSS vendored in the gem, no CDN** | It's a localhost tool for a Homebrew-installed gem; a CDN outage (or an airplane) must not blank the page. The existing asset story is gem-internal ERB templates (verified `utils/template.rb`, `lib/spm_cache/assets/templates/`), so vendoring fits the grain. | LOW | Vendor Cytoscape (or chosen graph lib) into assets; templates render at gen/serve time via the existing ERB path. |

### Differentiators (Competitive Advantage)

| Feature | Value Proposition | Complexity | Notes / Dependencies |
|---------|-------------------|------------|----------------------|
| **Relayed terminal/`watch` runs appear live in the browser** | The milestone's headline. **No SPM competitor has any web UI at all** (xccache, Scipio, Rugby, XCRemoteCache are CLI-only — verified from their repos in the v0.4.0 research). "Start a build in your terminal, watch it on your second monitor" is a capability the entire niche lacks. | HIGH | Requires cross-process capture where today **no run output persists at all** (verified). Candidate mechanisms (STACK.md decision): CLI writes a run-log/event file the server tails; CLI POSTs events to the server when up. Either way the CLI must gain a capture hook at the `Core::UI` boundary (single choke point, verified `core/log.rb` is all puts) and the protocol must carry run identity + final status. Do the UI-triggered stream first; relay reuses the same frontend. |
| **Fidelity status surfaced everywhere (table column, graph node color, toggle reasons)** | spm-cache's provenance-gated cache is unique in the niche (v0.4.0 research, verified from competitor sources). Surfacing "graph-pinned / stale / not-graph-pinned" per package turns an internal correctness mechanism into a visible trust feature no competitor can copy without building the fidelity machinery first. | LOW | Data fully exists: provenance sidecar `fidelity_status` (verified `cache/list.rb`). Pure presentation join. |
| **Embedded dependency graph with real edges** | Today's shipped viz is **broken**: `cachemap.html.template` contains a malformed ERB tag (`< %= data % >` with spaces — proven by executing the ERB render: data is emitted as literal text) and **Cytoscape is never loaded** (no script tag, no CDN ref, no vendored file — verified), so the page renders an empty legend. Additionally the graph data has **no edges**: `ProxyGenerator.swift` constructs every `GraphEntry` with `dependencies: []` (verified lines 90, 170; `GraphGenerator.swift:24` iterates a field nothing populates). Fixing the embed is both a repair and the differentiator "see your graph, colored by cache state, in the dashboard". | MEDIUM | Three stacked work items: (1) fix template + vendor Cytoscape + interpolate data (LOW); (2) populate `GraphEntry.dependencies` in the Swift generator + version the graph.json contract (MEDIUM — Swift-side change, cross-language); (3) embed as a dashboard view (LOW). Until (2) lands, embed honestly renders nodes-without-edges; don't ship it as a "dependency graph". |
| **Cache-state overlay on the graph during a run** | Nodes flip hit/missed/building as the run progresses — the dashboard becomes a live map of the build, tying the log stream and graph views together. Cheap once edges/anchors exist. | MEDIUM | Depends on: per-package progress events (from anchors), graph data with statuses (exists). Passive recolor only — see Anti-Features for live re-layout. |
| **"Build what drifted" one-click scope** | DiffDetector already detects graph drift (Package.resolved + pbxproj, verified in `core/diff_detector.rb` + watcher). A "rebuild changed packages" prefill on the build button turns an existing internal signal into a workflow accelerator. | MEDIUM | Depends on: build trigger with scope (table stakes) + DiffDetector result exposure. Defer unless the drift data is already cheaply reachable from the server process. |
| **Doctor fix affordances that deep-link, not auto-execute** | Every doctor check already carries a `fix_hint` string (verified). Rendering them as copyable commands / one-click *documentation* links (not auto-run) converts diagnostics into remediation without the server gaining arbitrary command-execution endpoints. | LOW | Presentation-layer over existing results. Explicitly do NOT add a "run this command" button (see Anti-Features). |

### Anti-Features (Commonly Requested, Often Problematic)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| **N simultaneous per-package log panes as the default view** | "I want to watch all packages at once." | The build loop is strictly sequential (verified), so N−1 panes are empty at any instant; parallel panes also fight the browser (render cost) and the mental model (where do I look?). Even Dozzle — the log-viewing benchmark — keeps one stream primary and makes split-screen opt-in. | Single stream with per-package anchors + a package jump-list; auto-scroll with user-scroll lock (follow-tail UX). |
| **Persistent run-history database with full-text search over old logs** | "Let me find that failure from last week." | Dozzle — purpose-built for log viewing — deliberately stores nothing and explicitly disclaims offline search; Develocity owns history at enterprise scale with real infrastructure. A history DB drags in schema, retention, migrations, and a search stack — a second product inside v0.5. | Keep the CURRENT run + last N runs in memory; write the live run's log to one file on disk (which the relay needs anyway); point users at that file for older needs. Revisit only if users ask. |
| **Remote access / network exposure (or auth, users, tokens)** | "Can I check builds from my phone / share the URL with my team?" | Violates the milestone's hard localhost-only constraint. Playwright's own docs warn that `--ui-host=0.0.0.0` exposes traces/secrets to the LAN; the 0.0.0.0 Day research shows what public exposure of unauthenticated local services yields (RCE). Auth is a whole feature surface with zero payoff for a single-user local tool. | Bind 127.0.0.1, validate Host/Origin, done. If remote demand appears later, that's a new milestone with a real security design, not a flag. |
| **A general spm-cache.yml editor in the browser** | "Since I'm editing `ignore` anyway, let me edit all config." | The config is a hand-maintained file with diff-merge semantics (`init` is idempotent diff-merge by design, verified in PROJECT.md); free-form yml editing through a form fork the file's ownership, risks corrupting keys the UI doesn't model, and duplicates `init`'s job badly. | Structured controls ONLY for `ignore` (the toggle surface). Every other key: display read-only + link to docs/init. |
| **Cross-process build cancellation (Stop button killing terminal/`watch` runs)** | Obvious expectation next to the Build button. | The server doesn't own externally-started processes; killing them means signaling other processes' children (xcodebuild trees), racing the flock protocol that deliberately uses blocking semantics ("defer rather than interrupt" — verified comment on `acquire_build_lock`). Orphaned xcodebuild processes and corrupted partial artifacts are the failure modes. | v1: cancel ONLY UI-triggered runs (server owns the child process; kill its process group, release flock). For external runs: show "started in terminal — cancel it there". Scoped, honest, safe. |
| **Live animated graph re-layout during builds** | "The graph should pulse/rearrange as packages build." | Cytoscape `cose` is already animated (verified `cachemap.js.template`); re-layout mid-run on every status flip janks on large graphs (the repo's reference project has 59–70 packages) and destroys the user's manual pan/zoom. | Passive recolor/status flip at fixed positions; re-layout only on explicit user action or data change. |
| **Notifications (Slack/email/push) for build completion** | "Tell me when the build finishes." | Integration surface (credentials, config UI) wildly exceeds a localhost tool's value; the browser tab is already the notification surface. | Tab title/favicon state + a completion banner; the OS-level niceties can come later via document.title alone. |
| **Multi-project dashboard (one server, many projects)** | "I have three app repos." | Config/lockfile/sandbox/flock are all per-project-dir by construction (verified paths derive from `Config#project_dir`); multi-project means a project registry, per-project state isolation in one process, and cross-project build-lock semantics — a large architectural lift with niche value. | Run `spm-cache web` per project (distinct ports); the launcher can print the port. Revisit only with real multi-repo demand. |

---

## Feature Dependencies

```
[spm-cache web subcommand + dashboard shell + vendored assets]
    └──requires--> [Core::Config project context] (exists)
    └──enables--> everything below

[Log capture sink at Core::UI boundary]            <-- NEW, hard prerequisite
    └──enables--> [Single-stream live log w/ anchors]
    └──enables--> [Replay-on-load + Last-Event-ID reconnect]  (shared event-id protocol)
    └──enables--> [Relay of terminal/watch runs]  (same sink, other process)

[Run registry + build-lock probe]
    └──requires--> [Project flock .spm-cache-build.lock] (exists; shared Build/Use/watch)
    └──enables--> [Run identity badges]
    └──enables--> [Build button busy/queued state]
    └──enables--> [Pending-toggle "apply on next sync" visibility]

[Build trigger w/ scope]  ──requires--> [Run registry] + [Origin/Host validation]
    └──requires--> [Installer::Build targets arg] (exists)
    └──enhances--> [Failure surfacing] (server owns exit status)

[Toggles → config ignore list] ──requires--> [Config load/mutate/save] (exists)
    └──requires--> [Origin/Host validation]
    └──enhances--> [Pending/apply UX] ──requires--> [Trigger (re-sync = Installer::Use)]

[WHY-not-toggleable reasons]
    └──requires--> [graph.json statuses] (exists) + [ignore globs resolution] (exists)
    └──requires--> [provenance fidelity sidecars] (exists)

[Cache state table]  ──requires--> [cache list enumeration] (exists) + [sizes] (new, trivial)
    └──requires--> [sidecar fidelity status] (exists)

[Doctor panel] ──requires--> [Diagnostics.run_all in-process] (exists)

[Embedded graph — nodes]  ──requires--> [FIX: broken ERB template + vendor Cytoscape] (verified broken)
[Embedded graph — edges]  ──requires--> [Swift GraphEntry.dependencies populated] (verified missing)
    └──enhances--> [Cache-state overlay during runs]

[Relay of terminal/watch runs] ──requires--> [Log capture sink] + [Run registry] + [persistent run output]
    └──conflicts--> [v1 cancellation for external runs] (see Anti-Features: cancel scoped to UI runs only)
```

### Dependency Notes

- **The log capture sink is the keystone.** Verified: `Core::UI` is bare puts, `LiveLog` captures per-process only, and nothing in `lib/` writes run logs to disk. UI-triggered streaming, replay-on-load, reconnect, AND the terminal/`watch` relay all consume the same abstraction. Build it before any streaming UI work; it is the natural Phase 1.
- **Replay and reconnect are one protocol, not two features.** Both are "resume an event stream from an id" (MDN Last-Event-ID). Any phase that ships streaming without ids/offsets will rework the frontend later.
- **The flock is a free primitive.** External-run detection ("a terminal build is running — Build button is queued") falls out of probing the existing project lock; no new state needed. Attribution of WHO started it does need the relay protocol.
- **Toggles inherit `off`'s deferred semantics by design.** The config write and the re-sync are separate steps today (verified `off` output text); the dashboard's job is to make that two-step visible and one-click-able, not to invent instant-apply magic (instant-apply would race the running integration and the flock).
- **The embedded graph is secretly a repair job.** Verified: the shipped cachemap HTML interpolates nothing (malformed ERB, proven by execution) and never loads Cytoscape; and the graph data carries no edges (`dependencies: []`, verified in the Swift generator). "Embed the existing viz" underestimates the work; "rebuild the viz and embed it" is the honest scope, with edges as the second, cross-language step.

---

## MVP Definition

### Launch With (v1)

- [ ] `spm-cache web` → localhost server + browser open + dashboard shell — the entry point
- [ ] Log capture sink at the `Core::UI` boundary — the keystone prerequisite (server-side runs first)
- [ ] Single live log stream w/ per-package anchors for **UI-triggered builds**, replay-on-load, auto-reconnect, stale indicator
- [ ] Run identity (trigger source, config, started-at, status) + external-run detection via the existing flock
- [ ] Build/Rebuild button: all or package scope, busy/queued state, failure banner + highlighted errors
- [ ] Per-package toggles writing the config `ignore` list, with visible pending/apply state + "Apply now (re-sync)"
- [ ] WHY-not-toggleable reasons (ignored-by-pattern / plugin / binary-target / excluded / fidelity)
- [ ] Cache state table: package × config, size, cached/source, fidelity status
- [ ] Doctor panel: on-demand run, statuses + fix hints + summary, busy + last-run timestamp
- [ ] Origin/Host validation on mutating endpoints; 127.0.0.1 binding; fully offline (vendored) assets
- [ ] Embedded graph — **repaired nodes view** (fix template, vendor Cytoscape, interpolate data)

### Add After Validation (v1.x)

- [ ] Relay of terminal/`watch` runs into the same stream — trigger: the capture sink + registry are proven; adds persistence of external run output
- [ ] Graph edges (Swift `GraphEntry.dependencies` populated + contract version) — trigger: relay/streaming stable; independent Swift-side phase
- [ ] Cache-state overlay during runs (passive recolor) — trigger: edges + anchors exist
- [ ] Cancel for UI-triggered runs only — trigger: users actually hit the missing stop button
- [ ] "Rebuild what drifted" prefill — trigger: DiffDetector state cheaply reachable server-side

### Future Consideration (v2+)

- [ ] Run history/search over persisted logs — defer: Dozzle's precedent says live-only is a defensible product
- [ ] Remote access with real auth — defer: hard security boundary, new milestone
- [ ] Multi-project registry — defer: architectural lift, per-project servers suffice

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| `web` subcommand + shell + offline assets | HIGH | LOW | **P1** |
| Log capture sink (Core::UI boundary) | HIGH (enabler) | MEDIUM | **P1** |
| Live single-stream logs (UI runs) + replay + reconnect | HIGH | MEDIUM–HIGH | **P1** |
| Run identity + external-run (flock) detection | HIGH | MEDIUM | **P1** |
| Build trigger w/ scope + busy state + failure surfacing | HIGH | LOW–MEDIUM | **P1** |
| Toggles on config `ignore` + pending/apply visibility | HIGH | MEDIUM | **P1** |
| WHY-not reasons per package | MEDIUM–HIGH | MEDIUM | **P1** |
| Cache state table (sizes + fidelity) | HIGH | LOW–MEDIUM | **P1** |
| Doctor panel | MEDIUM | LOW | **P1** |
| Origin/Host validation | HIGH (security floor) | LOW | **P1** |
| Cachemap repair + nodes embed | MEDIUM | LOW–MEDIUM | **P1** |
| Terminal/`watch` relay | HIGH (headline differentiator) | HIGH | **P2** (first v1.x) |
| Graph edges (Swift-side) | MEDIUM | MEDIUM | **P2** |
| Run overlay on graph | MEDIUM | MEDIUM | **P3** |
| UI-run cancel | MEDIUM | MEDIUM | **P3** |
| Drift-prefill build scope | MEDIUM | MEDIUM | **P3** |
| History/search, remote+auth, multi-project | LOW (for this product) | HIGH | **Deferred** |

---

## Competitor Feature Analysis

| Capability | Dozzle | Playwright UI Mode | Renovate Dashboard | BuildBuddy / Develocity | spm-cache v0.5.0 approach |
|------------|--------|--------------------|--------------------|--------------------------|----------------------------|
| Live log stream | ✓ SSE, primary view | per-run, embedded in node results | n/a | ✓ per-invocation | ✓ SSE-style stream w/ per-package anchors |
| Replay on (re)open | recent history while streaming | session traces | n/a | ✓ invocation record (server-side) | ring buffer (UI runs) / run file (relayed) |
| Reconnect w/o loss | seamless (SSE) | session-scoped | n/a | ✓ | EventSource retry + Last-Event-ID |
| Multi-pane logs | opt-in split screen | — | — | — | anti-feature: single stream + anchors |
| Run scope selection | per-container | ✓ all / file / block / single | — | per-target patterns (Bazel) | ✓ all / packages (reuses targets arg) |
| Pending-state visibility | — | — | ✓ core design (deferred ≠ forgotten) | — | ✓ toggle pending → "Apply now (re-sync)" |
| Show why action unavailable | — | disabled states | approval gates | — | ✓ reason join (ignore glob / plugin / binary / excluded / fidelity) |
| Dependency graph viz | — | — | — | Develocity: dependency insight pages | ✓ embedded graph — but must be REBUILT (broken template, no edges today) |
| Health/diagnostics panel | container stats | — | deprecation warnings | — | ✓ doctor registry reuse (data-driven, don't hard-code checks) |
| Storage posture | none (deliberate) | session traces | the dashboard itself | full history | current run + last N in memory; no history DB |
| Security posture | optional auth (multi-user product) | warns on 0.0.0.0 exposure | n/a (SaaS) | enterprise auth | 127.0.0.1 + Host/Origin validation; no auth |

---

## Sources

**This repository (all read or executed directly, HIGH):**
- `lib/spm_cache/core/live_log.rb` — TTY sticky-section log w/ in-memory `@captured`; terminal-only
- `lib/spm_cache/core/log.rb` — `Core::UI` is puts-based (the capture-sink choke point)
- `lib/spm_cache/core/config.rb` — `ignore` list + `should_ignore?` fnmatch globs; yml load/save; `build_lock_path`
- `lib/spm_cache/command/off.rb` — toggle = config append + "Run 'spm-cache'" deferred-apply message
- `lib/spm_cache/command/doctor.rb` + `core/diagnostics.rb` — registry, 8 registered checks, `run_all`, JSON shape
- `lib/spm_cache/installer/build.rb` — blocking shared flock (`:64-74`); sequential build loop (`:50-52`); targets filtering/alias expansion
- `lib/spm_cache/installer/use.rb:51-71` — same flock wraps `Installer::Use` incl. watch fast path
- `lib/spm_cache/command/watch.rb` + `core/watcher.rb` — mtime polling, debounce, `Installer::Use` factory
- `lib/spm_cache/cache/cachemap.rb` — node-only viz data; status buckets hit/missed/ignored/excluded/plugin
- `lib/spm_cache/installer/integration/viz.rb` + `assets/templates/cachemap.{html,js}.template` — ERB render; **malformed `< %= data % >` proven by executing the ERB render; Cytoscape never loaded; no edges in data**
- `tools/spm-cache-proxy/Sources/Core/Generator/ProxyGenerator.swift:90,170` — `dependencies: []` (verified still unpopulated post-v0.4.0); `GraphGenerator.swift:24` iterates it
- `lib/spm_cache/command/cache/list.rb` — xcframework enumeration + provenance `fidelity_status`; no sizes today
- `spm_cache.gemspec` — runtime deps: claide, xcodeproj, parallel, tty-cursor, tty-screen, CFPropertyList (no web stack)
- grep across `lib/` — **no log-file writing exists** (relay requires new persistence)

**Primary web sources (HIGH unless noted):**
- Dozzle README (github.com/amir20/dozzle) — no-storage posture, feature list, split screen, search; SSE `EventSource.vue` in repo tree
- Playwright UI Mode docs (playwright.dev/docs/test-ui-mode) — run scope selection, watch toggles, Errors tab; 0.0.0.0 exposure warning
- Vitest UI docs (vitest.dev/guide/ui) — server-required interactive watch UI
- Renovate Dependency Dashboard docs (docs.renovatebot.com/key-concepts/dashboard/) — pending visibility, closed/ignored re-apply checkboxes, approval workflow
- MDN Using server-sent events + HPBN SSE chapter — EventSource auto-reconnect, `retry`, `Last-Event-ID` resume
- Oligo Security, "0.0.0.0 Day" (Aug 2024) — browsers dispatch requests to localhost services; local services skipping origin/CSRF checks are exploitable (ShadowRay RCE); PNA/Safari/Firefox status
- Gradle Build Scan docs (docs.gradle.org/current/userguide/inspect.html) + Develocity Live Build Timeline post — invocation pages, timeline/console breakdowns

**Secondary (MEDIUM — vendor descriptions, not UI walkthroughs):**
- BuildBuddy GitHub README — invocation-centric build-event web UI

**Inherited from v0.4.0 research (competitor source-verified, HIGH):** no SPM competitor (Scipio, xccache, Rugby, XCRemoteCache) ships any web UI.

---
*Feature research for: spm-cache v0.5.0 Web Interface*
*Researched: 2026-08-31*
