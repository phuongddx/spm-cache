# Architecture Research

**Domain:** Local web dashboard layered onto an existing macOS Ruby CLI + Swift companion (spm-cache v0.5.0)
**Milestone:** v0.5.0 — Web Interface
**Researched:** 2026-08-31
**Confidence:** HIGH (every integration seam read in this repo's code at file:line; runtime facts probed empirically on this machine) · MEDIUM (SSE streaming patterns — corroborated across MDN + multiple practitioner sources)

---

## 0. Evidence Standard

Every claim below is tagged:

- **VERIFIED (repo)** — read in this repo's code; `file:line` given.
- **VERIFIED (machine)** — reproduced empirically on this machine (rbenv Ruby 3.2.3, Homebrew Ruby 4.0.0, macOS arm64).
- **SOURCED** — external documentation/community, confidence noted.
- **ASSUMED** — reasoned from platform semantics, flagged where load-bearing.

The v0.5.0 work adds a web layer **around** the existing pipeline. The pipeline itself (locator → lockfile reconcile → proxy → xcodeproj rewrite → build/fidelity) is treated as fixed ground; nothing below modifies it except two small, deliberate touch points (§6).

---

## 1. Verified Ground Truth That Shapes the Design

Five code facts — all read today in this repo — decide the architecture. Each was checked, not assumed:

1. **`Core::LiveLog` is dormant.** Defined at `lib/spm_cache/core/live_log.rb` but instantiated **nowhere** in `lib/`, `spec/`, or `bin/` (repo-wide grep 2026-08-31). The milestone brief's "LiveLog streams subprocess output live in-terminal" describes the class, not current behavior.
2. **Subprocess output is buffered, not streamed, today.** `Core::Sh.run` with no `live_log:` uses `Open3.capture3` (`lib/spm_cache/core/sh.rb:31-40`); on success the output is **discarded** (only `output:` string returned, unused by build paths); on failure only the last 60 lines surface (`failure_detail`, `sh.rb:53-59`). The popen3 branch (`sh.rb:20-29`) exists behind the `live_log:` seam but is equally dormant — and it discards capture entirely (`{ output: "", status: 0 }`, `sh.rb:29`), so its failure messages carry no detail.
3. **`--log-dir` is a stub.** Parsed at `lib/spm_cache/command.rb:20,29`, exposed via `BaseOptions#log_dir` (`command/base.rb:22-24`), consumed by **nothing**. There is no per-run log file anywhere in the system today. (The v0.4.0 architecture doc's "structured logging to optional log dir" describes plumbing, not behavior.)
4. **The sandbox is destroyed on every slow-path run.** `recreate_dirs` `rm_rf`s `spm-cache/`; the build lock deliberately lives **outside** it at `<project_dir>/.spm-cache-build.lock` for exactly this reason (`lib/spm_cache/core/config.rb:95-100`, "Pitfall 15" comment). Any new server-owned state (run logs, web marker) must live outside the sandbox or be destroyed mid-tail.
5. **The cachemap "HTML viz" is a husk, but the data is rich.** The template (`lib/spm_cache/assets/templates/cachemap.html.template`, 31 lines) renders a `#cy` div, a legend, and `const elements = <data>` — with **no rendering library and no render call**. Worse, `Cache::Cachemap#depgraph_for_viz` (`lib/spm_cache/cache/cachemap.rb:58-64`) maps **every** graph entry to a node shape, so edge entries (which carry `source`/`target`, not `module`) become nil-id garbage. Meanwhile `graph.json` itself is already a complete cytoscape elements array: nodes *and* edges, written by the Swift `GraphGenerator.generate()` (`tools/spm-cache-proxy/Sources/Core/Generator/GraphGenerator.swift:12-33`). **Conclusion: embed by serving `graph.json` verbatim to a real renderer — do not resurrect `depgraph_for_viz`.**

And one runtime fact, probed on this machine:

6. **WEBrick is not loadable on any target runtime.** `require "webrick"` fails under rbenv Ruby 3.2.3 (this machine) **and** Homebrew Ruby 4.0.0 (`/opt/homebrew/opt/ruby/bin/ruby`, 2025-12-25 build) — bundled gems are not installed by Homebrew rubies and were removed from the bundled set in Ruby 3.5. `socket` (TCPServer) is a default gem everywhere. **Any web server stack is either a new explicit gemspec dependency or stdlib sockets — there is no "already there" option** (VERIFIED machine; gemspec currently has 6 runtime deps, `spm_cache.gemspec:33-38`).

---

## 2. Recommended Architecture — System Overview

```
┌────────────────────────────────────────────────────────────────────────────┐
│  BROWSER (localhost only)                                                  │
│  dashboard shell (assets) · EventSource log view · toggles · panels        │
└───────────────▲────────────────────────────────────────┬───────────────────┘
                │ SSE  GET /api/events                   │ JSON  GET/POST /api/*
                │ (log lines, run status, lock state)    │ (state, packages,
                │                                        │  doctor, build, toggle)
┌───────────────┴────────────────────────────────────────▼───────────────────┐
│  WEB SERVER  (new)          `spm-cache web` — foreground process           │
│  lib/spm_cache/command/web.rb        CLAide entry (auto-registered)        │
│  lib/spm_cache/web/server.rb         HTTP adapter + router  ◄── stack seam │
│  lib/spm_cache/web/api.rb            read-model + action endpoints         │
│  lib/spm_cache/web/events.rb         run-dir tailer → SSE broadcaster      │
│  lib/spm_cache/web/jobs.rb           single-slot build job manager         │
│  READS FILES ONLY for state: config · lockfile · sidecars · graph.json     │
│  PROBES flock non-blocking for "build in progress" (never holds it)        │
└───────▲────────────────────────────────────────────────────▲───────────────┘
        │ tails                                               │ spawns
        │                                                     │
┌───────┴───────────────────────────┐          ┌──────────────┴──────────────┐
│  .spm-cache/runs/*.log  (NEW)     │          │ UI-triggered build           │
│  JSONL run logs, project-level,   │          │ = ORDINARY CLI subprocess    │
│  OUTSIDE the sandbox              │          │ `spm-cache build <targets>`  │
│  written by EVERY spm-cache run ──┼──────────┤ acquires the same flock,     │
│  (tee hook in Main.run + Sh)      │          │ writes the same run log      │
└───────▲───────────────────────────┘          └─────────────────────────────┘
        │ appends (behavior-preserving)
┌───────┴────────────────────────────────────────────────────────────────────┐
│  EXISTING PIPELINE (unchanged semantics)                                   │
│  CLAide commands → Installer::Use/Build → proxy → xcodeproj → fidelity     │
│  blocking flock @ <project>/.spm-cache-build.lock  ◄── the ONLY mutex      │
│  watch daemon (mtime polling, self-guard) — unchanged                      │
└────────────────────────────────────────────────────────────────────────────┘
```

**The one-sentence architecture:** the server is a *stateless file reader plus a log tailer plus a subprocess spawner* — it never becomes a second source of truth, never holds the build lock, and every mutation it triggers is an ordinary `spm-cache` invocation that terminal users could have typed.

### Component Responsibilities (new layer only)

| Component | Responsibility | Typical Implementation |
|-----------|----------------|------------------------|
| `Command::Web` | CLI entry; port/open flags; existing-server detection | CLAide subcommand, autoloaded like all others |
| `Web::Server` | Accept connections, parse HTTP, route, serve static shell | Thin HTTP/1.1 adapter — see §3 stack seam |
| `Web::Api` | Read-model JSON endpoints; action endpoints (build/toggle/doctor-run) | Plain Ruby classes over `Core::Config`, sidecars, `graph.json` |
| `Web::Events` | Tail `.spm-cache/runs/`, broadcast lines to SSE clients, handle Last-Event-ID | Polling thread (mtime, `Core::Watcher` precedent) + per-client writer |
| `Web::Jobs` | Single-slot UI build launcher; track pid/status; detect orphans after restart | `Process.spawn` + run-log pid liveness |
| `Core::RunLog` | JSONL run-log writer; the `$stdout`/`$stderr` tee; Sh sink | Append-only file sink responding to `output(line)` |

---

## 3. (a) Server Process Model

**Recommendation: foreground long-running process, modeled exactly on `spm-cache watch`.** No daemonization.

**Why foreground (opinionated):**

- **Precedent and consistency.** `watch` is already the project's long-running foreground process with a defined signal contract: TERM trap → `Interrupt` → mask signals → flush → exit 0 (`lib/spm_cache/core/watcher.rb:46-78`). `web` should copy that contract verbatim (trap TERM/INT → stop tailer, close SSE clients, remove marker file, exit 0).
- **"For the current project" is a foreground concept.** The server binds to `Dir.pwd`'s project (same resolution as every other command). A daemon decoupled from a terminal invites stale daemons serving yesterday's gem after a `brew upgrade` — version skew the project already fights with the Swift companion (`doctor`'s `companion_binary` check exists precisely because of Ruby↔Swift drift).
- **Daemonizing adds a launchd/LaunchAgent surface, log capture, and lifecycle verbs (`web start/stop/status`) — a second subsystem to build, test, and document, for zero user value on a dev tool.** Out of scope; noted as a future option only.

**Lifecycle:**

| Concern | Decision |
|---------|----------|
| Binding | `127.0.0.1` **hardcoded** (milestone constraint: localhost-only). No `--host` flag — the flag is the vulnerability. |
| Default port | One fixed default (e.g. `7960`) + `--port` flag. |
| Collision handling | On `EADDRINUSE`, scan upward (`port..port+10`), bind the first free; report the chosen URL. No `SO_REUSEPORT` tricks. |
| Existing-server detection | Marker file `<project_dir>/.spm-cache/web.json` = `{pid, port, project_dir, spm_cache_version, started_at}`. A second `spm-cache web` for the same project: pid alive (`Process.kill(pid, 0)`) → just `open http://localhost:<port>` and exit 0 (idempotent — repeated invocation is the common UX). Pid dead → take over, rewrite marker. |
| Browser auto-open | `system("open", url)` — LaunchServices, stdlib, macOS-only by charter. `--no-open` flag for scripts/CI. No `launchy` gem (it exists for cross-platform; this tool is macOS-only by definition). |
| Shutdown | TERM/INT → remove `web.json`, close tailer thread + SSE sockets, exit 0. Crash-orphans of the marker are healed by the pid-liveness check above. |

**Why the marker file lives at `<project_dir>/.spm-cache/` (new dotdir):** the sandbox `spm-cache/` is `rm_rf`'d on every slow-path run (VERIFIED repo, fact #4); the build lock already established the project-level-dotfile precedent for server-owned state (`config.rb:95-100`). The dotdir needs a gitignore entry — one small MOD to `Command::Init` (§6).

**HTTP stack — decision seam, opinionated default:** the milestone makes "which server stack earns its place" a research subject (STACK.md owns the final gemspec call). The architecture is deliberately **stack-agnostic**: all routing, SSE, tailing, and jobs live above a ~50-line adapter (`Web::Server`) that exposes exactly `read_request → {method, path, headers, body}` and `write_response / write_stream_chunk`. Two candidates fit under that seam:

1. **Hand-rolled HTTP/1.1 on `TCPServer` (recommended default).** Zero new dependencies; matches the standing project precedent of choosing stdlib over gems when the surface is small (`watch` chose mtime polling over the `listen` gem — PROJECT.md Key Decisions). The endpoint surface is ~8 routes of single-user localhost traffic. Robustness strategy: accept only what is needed — request-line + headers via `readline`, small `Content-Length` JSON bodies, reject everything else with 400, `Connection: close` framing except SSE streams. Request smuggling/proxy concerns are structurally irrelevant on a loopback socket with no proxy.
2. **WEBrick as an explicit, justified runtime dependency** (`~> 1.8`, Ruby-core maintained, zero transitive deps). Thread-per-connection handles the handful of concurrent SSE clients naturally. Cost: first new runtime gem in the constraint's crosshairs — and empirically NOT available on Homebrew rubies without it (fact #6). Choose this if review rejects hand-rolled parsing as maintenance risk.

Either way: thread-per-connection is the correct concurrency shape (1-5 simultaneous SSE clients is the realistic ceiling for a single developer's dashboard); an evented framework (falcon/async) is overkill and drags a gem family in.

---

## 4. (b) Log Relay Architecture

**The problem:** live build output must reach the browser from (i) UI-triggered builds and (ii) `use`/`build`/`watch` runs happening in *other terminals*, with full replay when the page loads mid-build.

**Three candidates adjudicated:**

| Option | Verdict | Decisive reasons |
|--------|---------|------------------|
| **Append-only run-log files the server tails** | ✅ **ADOPT** | Replay from byte 0 on connect; works when the CLI run started before the server (or before the page); CLI behavior unchanged when no server exists; survives server restarts; zero protocol; builds directly on the (currently stub) `--log-dir` concept. |
| UDS pub/sub (CLI streams into server socket) | ❌ REJECT | Everything before connection is lost → replay needs a server-side buffer anyway (re-implementing the file, worse); every CLI run grows server-dependency code (connect-fail-fallback paths); untestable without a live socket; kills the "server absent ⇒ CLI unchanged" property. |
| Server-as-single-builder | ❌ REJECT | Terminal builds are the *primary* interface; requiring a daemon to build contradicts the product; also re-creates the version-skew daemon problem from §3. |

**Run-log design (all VERIFIED against the seams it plugs into):**

- **Location:** `<project_dir>/.spm-cache/runs/<UTC-timestamp>-<pid>-<verb>.log` — outside the sandbox (fact #4), sibling convention to the build lock. New `Core::Config#runs_dir`.
- **Format:** JSON lines. Line 1: header `{run: true, command:, argv:, pid:, started_at:, tty:}`. Middle lines: `{ts:, stream: "out"\|"err", text:}`. Final line: `{exit:, status:, ended_at:}`. JSONL gives the tailer timestamps and stream attribution for free, and `jq` keeps the files human-inspectable. ANSI color codes pass through unmodified — the frontend renders them in a `<pre>`; the server stays dumb.
- **Writers — two capture points, both required (this is the crux):**
  1. **Global tee in `SPMCache::Main.run`** (`lib/spm_cache/main.rb:8-13`): before `Command.run`, install tee wrappers on `$stdout`/`$stderr` that write through unchanged *and* append JSONL. This captures Installer's UI narrative (sections, "Cache: X hits…", watch messages) — the part of today's terminal experience that is actually visible.
  2. **`Core::Sh` stream mode:** when a run log is active, `Sh.run` uses the **existing but dormant popen3 branch** (`sh.rb:20-29`) with the run log as the `live_log:` sink. Critically, this must **not** write through to the terminal: today's terminal shows no raw xcodebuild output (capture3 discards it — fact #2), so streaming it to the TTY would change terminal behavior. Sink-to-file-only is behavior-preserving for the terminal while making the browser strictly richer than the terminal. Fix the dormant branch's discarded-capture gap (`{ output: "" }`, `sh.rb:29`) by retaining the lines for `failure_detail` — a pre-existing weakness closed as a side effect.
  - Composition: `Core::RunLog` responds to `output(line)` — the exact contract `Core::Sh` already expects (`sh.rb:24-25`). The seam was built for this; it just was never wired.
- **`spm-cache web` itself skips the tee** (argv check in the hook) — the server must not log into the thing it tails.
- **Retention:** server prunes `runs/` at startup (keep last ~50 files / 14 days). Terminal-only users accumulate files harmlessly (tiny text); the web feature owns cleanup.
- **Active-run detection:** header carries `pid`. Tailer treats a run as live while no `exit:` line exists **and** `Process.kill(pid, 0)` succeeds. (`watch` sessions legitimately have long-lived logs with no exit line — this is why pid liveness, not staleness, is the signal.)

**UI-triggered builds: spawn a subprocess, do not run `Installer` in-process.** Opinionated, with the trade-off stated:

- **Why subprocess (recommended):**
  - **One relay mechanism.** The spawned `spm-cache build` writes the same JSONL run log as every terminal run; the SSE tailer streams it identically. An in-process `Installer::Use/Build` would need a *second* log-capture path (injecting sinks into `Core::Sh` + capturing `Core::UI.puts`) maintained in parallel forever.
  - **Isolation.** `Command`-layer code is littered with process-lifecycle calls — `Command::Doctor#run` literally calls `exit 1` (`lib/spm_cache/command/doctor.rb:53`). Auditing every command path for `exit`/`SystemExit`/fatal error handling *forever* is the kind of tax that compounds; a subprocess makes it structural.
  - **Flock semantics preserved exactly.** The subprocess blocks on `<project_dir>/.spm-cache-build.lock` like any terminal build (§7). The server never touches the lock.
  - Invocation: `Process.spawn` of `Gem.ruby -S <bin> build <targets>…` with the bin resolved from the running executable; `detach` the child (an orphaned build surviving a server restart is *desired* — the new server re-derives its state from run logs + pid liveness).
- **Why not in-process (acknowledged):** zero-copy log fan-out through the `live_log:` seam and no process-spawn overhead. Rejected as primary because it forfeits uniformity and isolation for a single-user tool where neither matters; revisit only if spawn latency ever annoys (it won't — builds take seconds-to-minutes).

**Watch-daemon interplay (self-trigger guard):** a UI- or server-triggered run rewrites `project.pbxproj` (proxy integration) — to a concurrently running `watch`, that is an ordinary *external* change; its post-regenerate re-snapshot absorbs its own writes and it fast-path-no-ops on ours (`watcher.rb:52-60`, empty diff → "No changes detected"). The flock serializes any true overlap. **No new guard is needed** — but note the benign case explicitly in review: server "Integrate" + `watch` in another terminal = one real regen + one fast-path no-op.

**Replay/buffering for mid-build page loads:** SSE event id = **byte offset** in the run-log file. On connect, the tailer emits the file from offset 0 (or from the browser's `Last-Event-ID` offset), then follows. `EventSource` auto-reconnects and replays with `Last-Event-ID` by spec (SOURCED, HIGH — MDN, "Using server-sent events"; corroborated by multiple 2025-2026 practitioner writeups). Per-event flush defeats batching ("events arriving as a batch" is the documented buffering failure mode — SOURCED, MEDIUM); on loopback with no proxy, flush-per-write is sufficient. Known cosmetic limitation: xcodebuild progress uses `\r` without `\n`, so partial progress lines flush late — identical parity to today's terminal, accepted.

---

## 5. (c) Toggle Persistence — One Source of Truth

**The UI toggle IS `spm-cache off`.** The ignore list is the mechanism, verified end to end:

- `Command::Off#run` appends to `config.raw["ignore"]` and `config.save` (`lib/spm_cache/command/off.rb:20-22`) — that is the entire existing write path.
- Honor path: `SPM::Package::Proxy#prepare` reads `Core::Config.instance.ignore_list` (`lib/spm_cache/spm/pkg/proxy.rb:37`) → Swift `ProxyGenerator.isIgnored` (`tools/.../ProxyGenerator.swift:51-55`) → source shim instead of binaryTarget on the next `use`/`build` regen. Toggles therefore take effect on the next integration — the UI's "Apply" button is just `spm-cache use`.
- `rollback` needs no toggle logic: it removes the proxy wholesale (`installer/rollback.rb:10-17`). "Honored by rollback" is satisfied by construction.

**Mechanization (no second config surface):** add two tiny mutators to `Core::Config` — `disable_caching!(name)` / `enable_caching!(name)` (mutate `raw["ignore"]`, re-loading from disk immediately before the read-modify-write). `Command::Off` is refactored to call the first (clean cutover, no duplicated mutation logic), and the server toggle endpoint calls both. CLI and UI provably share one code path.

**Integration hazards, both small and both handled:**

1. **Singleton staleness:** `Core::Config` is a memoized singleton; a long-running server would serve stale config after a CLI run edits `spm-cache.yml`. Rule for all server read paths: `config.load` immediately before rendering (cheap YAML parse), never cache across requests.
2. **Non-atomic save:** `Config#save` is a bare `File.write` (`config.rb:57-64`). Fine when only humans edit; riskier once a UI button does it. Change to tempfile+rename — the pattern already proven for provenance sidecars (v0.4.0 "WR-03"). CLI-vs-UI read-modify-write races remain last-writer-wins: acceptable for a single-user local tool, documented, not engineered away.

**Edge cases:** `ignore` entries are fnmatch patterns (`config.rb:146-148`). UI toggles store exact package identities; re-enabling removes the exact string. A hand-authored *pattern* (`"Google*"` in the yml) that matches a package cannot be removed by exact-match — the UI should render `should_ignore?(name)` as effective state and mark pattern-managed packages "managed by pattern in spm-cache.yml" (read-only in UI). No new CLI `on` command is required for v0.5 (server symmetry suffices); noting it as an optional parity add, not scope.

---

## 6. NEW vs MODIFIED Components (file paths)

### NEW

| File | Responsibility |
|------|----------------|
| `lib/spm_cache/command/web.rb` | `spm-cache web` CLAide subcommand: flags `--port`, `--no-open`; marker-file detection; auto-open; foreground lifecycle (watch-style signal contract). Auto-registered — `Main.load_all` autoloads every `lib/**/*.rb` before `Command.run` (`main.rb:12-19`), and CLAide discovers subclasses; **no edit to `command.rb` needed**. |
| `lib/spm_cache/web/server.rb` | HTTP adapter + router (stack per STACK.md: hand-rolled TCPServer default, WEBrick fallback). Static dashboard shell + JSON + SSE routing. |
| `lib/spm_cache/web/api.rb` | Endpoint handlers: state, packages, doctor (+run), cachemap, events, build, toggle. Thin — delegates to read-models below. |
| `lib/spm_cache/web/events.rb` | Runs-dir tailer (mtime polling, `Core::Watcher` precedent) + SSE broadcaster (per-client writers, byte-offset ids, Last-Event-ID resume). |
| `lib/spm_cache/web/jobs.rb` | Single-slot build job manager: spawn CLI subprocess, track pid/targets/started_at, orphan detection from run-log headers after restart, 409 on second concurrent request. |
| `lib/spm_cache/core/run_log.rb` | `Core::RunLog` JSONL writer; `$stdout`/`$stderr` tee install; `output(line)` sink contract for `Core::Sh`. |
| `lib/spm_cache/assets/web/*` | Dashboard shell (HTML+JS+CSS, no build toolchain — template-rendered like `cachemap.html.template`); log viewer; vendored graph renderer (cytoscape.js — the template already speaks cytoscape elements format; vendored, not CDN, so the dashboard works offline). Gemspec already packages `{lib,bin,assets,tools}/**/*` (`spm_cache.gemspec:20-26`) — **no gemspec change**. |
| `spec/run_log_spec.rb`, `spec/web/*_spec.rb` | Hermetic coverage: run-log writer, tailer resume math, endpoint read-models, job slot, toggle mutators (no live sockets needed for the seam-tested majority). |

### MODIFIED

| File | Change | Why |
|------|--------|-----|
| `lib/spm_cache/main.rb` | Install the run-log tee in `Main.run` before `Command.run` (skipped for `web` argv) | Capture point 1 — every CLI run records (§4) |
| `lib/spm_cache/core/sh.rb` | When a run log is active, take the popen3 branch with the run-log sink (file-only, no TTY write-through); retain captured lines for `failure_detail` | Capture point 2 — subprocess output reaches the log without changing terminal behavior (§4) |
| `lib/spm_cache/core/config.rb` | + `runs_dir`; + `web_dir` (`.spm-cache/`); + `disable_caching!/enable_caching!` mutators; `save` → tempfile+rename | §4 location contract, §5 toggle mechanization, atomic UI writes |
| `lib/spm_cache/command/off.rb` | Route mutation through `Core::Config#disable_caching!` | Clean cutover — one shared code path (§5) |
| `lib/spm_cache/command/init.rb` | Append `.spm-cache/` to the project `.gitignore` alongside the existing `spm-cache/` entry | New dotdir must not be committed in user projects |
| `lib/spm_cache/command/cache/list.rb` | Extract the glob+sidecar scan into `Cache::Inventory#scan` (returns name/config/size/fidelity rows); command prints it, server JSON-encodes it | Read-model reuse without logic duplication (§7 endpoints) |
| `lib/spm_cache/command/doctor.rb` | Extract the `print_json` payload construction into `Core::Diagnostics.json_payload(results)`; command and endpoint share it | Identical JSON shape on CLI and dashboard (§7) |
| `lib/spm_cache/installer/use.rb` (or `installer/build.rb`) | One `Core::UI.info "waiting for build lock…"` line before `with_build_lock` acquisition | Makes flock-wait visible in run logs → browser shows "queued" instead of a silent gap |

### Explicitly NOT modified

- `installer.rb`, `installer/build.rb` pipeline internals, `spm/**`, `xcodeproj/**`, the Swift companion — the web layer reads their *outputs* (lockfile, sidecars, `graph.json`, cachemap) and never their control flow. The two Installer-layer touch points listed above are logging-adjacent only.
- `core/watcher.rb` — no guard changes needed (§4 interplay analysis).
- `spm-cache.gemspec` — unless STACK.md selects WEBrick (then: exactly one new runtime dep, justified there).


---

## 7. Read-Model Endpoints (d) — reuse, don't duplicate

Every dashboard surface maps onto data that already exists on disk or in an existing registry. The server **reads the same files the CLI reads** — it never maintains a shadow model.

| Endpoint | Source (existing, verified) | New work |
|----------|----------------------------|----------|
| `GET /` | Dashboard shell from `assets/web/` | Template-render once at boot |
| `GET /api/state` | `Core::Config#load` (fresh) + `Core::Lockfile` summary + non-blocking flock probe on `.spm-cache-build.lock` + newest run-log header/pid | Assemble only |
| `GET /api/packages` | `Cache::Inventory#scan` (extracted from `Command::Cache::List`, `command/cache/list.rb:15-34`): glob `~/.spm-cache/<config>/*.xcframework` + `.provenance.json` fidelity status. Sizes: recursive directory size (xcframeworks are bundles; N is tens, cost trivial) | Extraction (listed MOD) |
| `GET /api/doctor` | `Core::Diagnostics.run_all(config:)` (`core/diagnostics.rb` — documented side-effect-free except read-only shell-outs) serialized via extracted `json_payload` (shape today at `command/doctor.rb:57-77`). Result **cached with timestamp**; checks shell out to xcodebuild/swift (seconds) — never run per request | Extraction + caching |
| `POST /api/doctor/run` | Same, cache-invalidating; worker thread; UI polls or SSE-notifies completion | Jobs-adjacent |
| `GET /api/cachemap/graph` | **`graph.json` verbatim** (`spm-cache/packages/proxy/graph.json`): nodes *and* edges, already in cytoscape elements format (`GraphGenerator.swift:12-33`). Do **not** route through `depgraph_for_viz` (drops edges, fact #5) | Read + serve |
| Cachemap view | Dashboard panel rendering `/api/cachemap/graph` with vendored cytoscape (the v0.1.0 standalone HTML regressed to a husk — fact #5 — so the dashboard *is* the viz now) | Frontend only |
| `POST /api/toggle` | `Config#enable_caching!/disable_caching!` + atomic `save` (§5); response includes the refreshed effective ignore map | Mutators (listed MOD) |
| `POST /api/build` | `Web::Jobs` → spawn `spm-cache build <targets>` (§4); streaming rides the run-log tailer like every other run | Jobs (NEW) |

**Cachemap freshness note:** `graph.json` only exists after a regen; the dashboard shows a "run Integrate to generate" affordance if absent rather than regenerating server-side.

---

## 8. Concurrency (e)

**Governing stance: the flock remains the ONLY mutex in the system; the server adds no second lock — it observes and defers.**

| Scenario | Behavior |
|----------|----------|
| HTTP read while terminal build holds the lock | Served normally. All read-models are pure file reads; the package currently being written may show a transient partial size — annotate with the lock-probe "build in progress" banner rather than blocking. |
| UI Build clicked while terminal build holds lock | Accepted. Subprocess starts, blocks on the flock exactly like a terminal build would; its run-log header lands immediately, the pre-acquisition "waiting for build lock…" line (listed MOD) makes the queue visible; SSE shows "waiting". |
| Second UI Build while one is in flight | `409` from the single job slot (in-process mutex). The *user* can still run terminal builds freely — the slot limits server-launched builds only. |
| Terminal build while UI build runs | Blocks on flock — **unchanged existing semantics**; the terminal build is the "second" one and waits, same as today. |
| `watch` regen overlapping either | Blocks on flock (today's behavior), fast-path no-op after (§4 interplay). |
| Toggle during a build | Atomic config write is safe mid-build; takes effect on the next regen. UI shows "applies on next Integrate". |
| Server killed mid-UI-build | Subprocess continues as an orphan, finishing its run log. Restarted server re-derives state (running pid, targets) from the newest run-log header + pid liveness. This is the payoff of file-based relay: **the server is restartable at any moment without losing the truth.** |
| Server request floods / abuse | Out of threat model: loopback-only binding, single user, same trust domain as the CLI. One-line `Host: localhost` check as DNS-rebinding hygiene; no auth. |

The non-blocking flock probe (open the path, `flock(LOCK_NB)`, unlock immediately) deserves one caveat for implementers: probing never disturbs holders (flock conflicts are per open-file-description), but the probe fd must not be the same fd the server would (never) use to *take* the lock.

---

## 9. Data Flows (delta views)

### Terminal-run log relay (the new flow)

```
$ spm-cache build Alamofire            (terminal B; server + browser on terminal A's project)
  Main.run → RunLog.open(.spm-cache/runs/…) → tee $stdout/$stderr
  Installer::Build → "waiting for build lock…" (if held) → flock acquired
  Core::Sh (xcodebuild) → popen3 → each_line → RunLog.output   (file only)
        │
        ▼ (tailer polls ≤0.5s)
  Web::Events → SSE: id=<byte-offset>  data:{"ts","stream","text"}
        │
        ▼
  Browser log view (auto-scroll; EventSource auto-resume w/ Last-Event-ID)
```

### UI Build (single mechanism, no forks in the road)

```
[Build] → POST /api/build → Jobs (slot free?) → spawn `spm-cache build T…`
        → subprocess writes run log like ANY terminal run → same tailer → same SSE
        → exit line in log → Jobs marks done → GET /api/packages reflects new sidecars
```

### Toggle

```
[switch OFF] → POST /api/toggle {package, enabled:false}
  → Config#disable_caching! (fresh load → mutate → tempfile+rename save)
  → UI banner "applies on next Integrate" → [Integrate] → POST /api/build {"command":"use"}
  → spawned `spm-cache use` → proxy regen reads ignore_list → source shim (existing honor path)
```

---

## 10. Patterns to Follow

### Pattern 1: File-watch as the universal truth source
**What:** server state is always re-derived from files (config, sidecars, graph.json, run logs, lock probe) on demand.
**When:** every read endpoint.
**Trade-offs:** zero state-sync bugs, trivially restartable; costs a handful of small file reads per request (irrelevant at localhost rates).

### Pattern 2: Sink seam reuse (`output(line)`)
**What:** `Core::RunLog` implements the exact contract `Core::Sh#live_log` already expects (`sh.rb:24-25`) — the relay is a new *implementation* of an existing interface, not a new interface.
**Trade-offs:** Sh stays untouched conceptually; testable with a fake sink.

### Pattern 3: CLI-subprocess as the action API
**What:** every mutating dashboard action spawns the ordinary CLI verb.
**Trade-offs:** one relay mechanism, isolation, flock semantics free; cost = one process spawn (nothing vs multi-second builds).

## Anti-Patterns

### Anti-Pattern 1: Server as second mutex
**Mistake:** server tracks "is a build running" in its own state and gates UI actions on it.
**Why wrong:** two truth sources that drift (orphaned subprocesses, terminal builds invisible to server state).
**Instead:** truth = the flock (probe it) + run logs (read them). Server state is a *cache* of those, never the source.

### Anti-Pattern 2: In-process Command reuse
**Mistake:** server calls `Command::Build.new(...).run` to avoid spawning.
**Why wrong:** `exit 1` in command bodies kills the server (`doctor.rb:53`); CLAide option plumbing assumes argv; singleton config mutation bleeds across requests.
**Instead:** spawn the CLI; reuse only *layer-below* classes (`Diagnostics`, `Cachemap`, extracted read-models) for reads.

### Anti-Pattern 3: A second config surface for toggles
**Mistake:** `web.json` or an in-server store remembering toggle state.
**Why wrong:** terminal and dashboard disagree; violates the milestone's "same source of truth as `spm-cache off`".
**Instead:** `spm-cache.yml` ignore list, via the shared mutators (§5).

### Anti-Pattern 4: Run logs inside the sandbox
**Mistake:** `spm-cache/runs/` feels natural.
**Why wrong:** `recreate_dirs` rm_rf's the sandbox mid-build — the tailer's file vanishes under it (the exact bug class the build lock's placement already solved, `config.rb:95-100`).
**Instead:** `<project_dir>/.spm-cache/runs/`.

---

## 11. Suggested Build Order (dependency-driven)

```
Phase A  Run-log foundation      Core::RunLog + Sh stream mode + Main.run tee
                                 + Config.runs_dir + retention          (no server)
   │                             proves: every CLI run leaves a queryable JSONL log
   ▼
Phase B  Server skeleton + reads Command::Web, Web::Server (adapter), Web::Api
                                 + Cache::Inventory + Diagnostics.json_payload
                                 + port scan + marker + auto-open       (no streaming)
   │                             proves: dashboard shows cache table/doctor/cachemap
   ▼
Phase C  Live streaming          Web::Events (tailer + SSE) + log-view frontend
   │                             proves: terminal/watch runs appear live; reload replays
   ▼
Phase D  UI build controls       Web::Jobs + POST /api/build + waiting-line in Installer
                                 + lock-probe state in /api/state
   │                             proves: Build/Rebuild from browser; collision shows queue
   ▼
Phase E  Toggles + panels        Config mutators (+Off refactor) + POST /api/toggle
                                 + Integrate button + atomic save + init gitignore
                                 (doctor panel & cachemap embed land with B's endpoints;
                                  E is their polish + the last mutating surface)
```

**Ordering rationale:** A before C (nothing to stream without logs); B before C/D (SSE and jobs ride the server skeleton); D after C (build output streams through C's pipe — the moment D lands, feature 2 is complete end to end); E last among mutators because it is the only phase that *writes* user state, so it inherits hardened read paths and can reuse D's job machinery for "Integrate". A, B, and E's toggle mutators are independently testable hermetically; C is the phase most needing a real-browser smoke.

---

## 12. Integration Points Summary (for the planner)

| Boundary | Mechanism | Notes |
|----------|-----------|-------|
| Browser ↔ Server | HTTP + SSE (EventSource, Last-Event-ID = byte offset) | SOURCED HIGH (MDN) |
| Server ↔ run logs | mtime-poll tailer, JSONL, pid-liveness | `Core::Watcher` polling precedent |
| Server ↔ pipeline state | Read config/lockfile/sidecars/graph.json fresh per request | No shadow model |
| Server ↔ build lock | Non-blocking probe only; never hold | §8 |
| Server ↔ mutations | Spawned CLI subprocesses; toggle via shared Config mutators | §4, §5 |
| CLI ↔ run logs | `Main.run` tee + `Sh` popen3 sink | Behavior-preserving for terminals |
| Server ↔ watch daemon | None — external-change/flock semantics already correct | §4 interplay |
| Server stack | Adapter seam in `Web::Server`; final pick = STACK.md (hand-rolled TCPServer default, WEBrick justified fallback) | §3; webrick absent on all target rubies (VERIFIED machine) |

### Open Questions (phase-level research flags)

- **Phase C:** SSE write-error handling on vanished clients (EPIPE/Errno mid-broadcast) — small, but needs a deliberate cleanup path per client writer.
- **Phase C/D:** `\r`-progress lines flush late in the browser (accepted parity with terminal); if it reads as "hung", a heartbeat SSE comment (`: ping`) every ~15s also doubles as proxy-safe keepalive.
- **Phase E:** pattern-authored ignore entries render read-only in the UI (§5 edge case) — confirm with user whether an "edit patterns" affordance is wanted in v0.5 or deferred.
- **STACK.md must settle:** hand-rolled HTTP adapter vs WEBrick gemspec dependency (architecture is identical under both; §3 documents the robustness strategy for the hand-rolled path).

## Sources

- Repo (VERIFIED 2026-08-31): `core/sh.rb`, `core/live_log.rb`, `core/config.rb`, `core/watcher.rb`, `core/diagnostics.rb`, `main.rb`, `command/{off,base,doctor,cache/list}.rb`, `installer/{use,rollback}.rb`, `installer/integration/viz.rb`, `spm/pkg/proxy.rb`, `cache/cachemap.rb`, `assets/templates/cachemap.html.template`, `tools/spm-cache-proxy/Sources/Core/Generator/{GraphGenerator,ProxyGenerator,UmbrellaGenerator}.swift`, `spm_cache.gemspec`
- Machine probes (VERIFIED 2026-08-31): `require "webrick"` under rbenv Ruby 3.2.3 (fail) and Homebrew Ruby 4.0.0 (fail); `socket` default-gem present; `brew list ruby` → 4.0.0
- SOURCED — SSE/EventSource semantics: MDN "Using server-sent events" (developer.mozilla.org, updated 2025-05); http.dev "Last-Event-ID" (2026-04); practitioner buffering-failure writeups (stackoverflow.com/questions/50870716; oneuptime.com SSE-framework guide 2026-01) — confidence HIGH for EventSource/Last-Event-ID, MEDIUM for streaming-pattern details

---
*Architecture research for: spm-cache v0.5.0 Web Interface*
*Researched: 2026-08-31*
