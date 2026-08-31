# Stack Research

**Domain:** Localhost web dashboard + live log streaming added to a macOS Ruby/Swift CLI (spm-cache v0.5.0 Web Interface)
**Researched:** 2026-08-31
**Confidence:** HIGH — every version number below was verified 2026-08-31 against the RubyGems API, stdgems.org, the Homebrew formula API, or the gem's own source. No estimate or remembered version survived unverified.

## Verdict Up Front

**Add exactly one new runtime dependency: `webrick` (~> 1.8, and it is a cheap, defensible one). Everything else is stdlib.** SSE (not WebSocket) for live logs, a Unix domain socket (not file tail, not Redis) for relaying terminal/`watch` runs into the server, and vanilla JavaScript with no build step for the frontend. Puma, Falcon, Sinatra, Roda, Rack, and any Swift-side HTTP server all fail the no-new-deps-without-justification rule for a single-user, 127.0.0.1-bound, ~10-endpoint dashboard.

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| webrick (new gemspec runtime dep, `spec.add_dependency "webrick", ">= 1.8", "< 2"`) | 1.9.2 latest; Ruby 3.3 ships 1.8.x as a bundled gem | HTTP server for `spm-cache web` (routes + static assets + SSE) | **Zero runtime dependencies, pure Ruby** (verified: no runtime deps, no native extensions — RubyGems API v1). Maintained by the `ruby/` GitHub org. Thread-per-connection model is exactly right for one user with a few tabs. `HTTPResponse#chunked=` (verified present in 1.9.2 source) gives byte-flush streaming for SSE. Justification for breaking the no-new-deps rule: (1) it *is* the stdlib server — bundled with the pinned production Ruby 3.3.12 (tap formula), so under the Homebrew install it resolves from the local bundled copy, no download; (2) declaring it in the gemspec is what keeps Ruby 4.0 (see Version Compatibility) a non-event; (3) it eliminates the entire hand-rolled-HTTP correctness burden (keep-alive, partial reads, header parsing, chunked framing) that a raw `TCPServer` server would take on. |
| Server-Sent Events (`text/event-stream`) — not WebSocket | protocol-level, no gem | Live build-log streaming to the browser | Logs are strictly server→client; SSE is that, nothing more. Browser `EventSource` API is universally supported, gives auto-reconnect and `last-event-id` for free. On WEBrick: `res.chunked_encoding = true`, flush each `data: <line>\n\n`. WebSocket by contrast needs RFC 6455 framing + client-frame masking hand-rolled in stdlib Ruby (no stdlib implementation) or the `websocket-driver` gem (0.8.2) — a second new dependency to solve a problem the dashboard doesn't have (no server-push commands; actions go over normal POSTs). |
| Unix domain socket (`UNIXServer`/`UNIXSocket`, stdlib `socket`) | stdlib | Relay of terminal / `watch`-initiated build logs into the running web server | CLI processes in other terminals `UNIXSocket.open` the socket **if it exists**, write NDJSON event lines, and no-op otherwise (rescue `Errno::ENOENT`/`ECONNREFUSED`/`Errno::EPIPE`). Zero cost when the dashboard isn't running — no files growing, no rotation, no "am I being watched" ambiguity. Connectionless feel, no port allocation, filesystem permissions give free localhost-only confinement, and it reuses the project's existing "dotfile lock at project root" convention. |
| Vanilla ES2020 JavaScript, no framework, no build step | n/a | Dashboard frontend (logs pane, toggles, state table, doctor panel, embedded cachemap) | The whole UI is one page: one EventSource, ~6 `fetch` POSTs, one table render, one embedded graph. A framework buys nothing at this size. htmx doesn't help either: since v2.0, SSE lives in a **separate extension** (`hx-sse` was removed from core — verified in the official migration guide), so you'd vendor 2 files and learn a declarative dialect for ~30 lines of JS that `EventSource` already covers. The existing `cachemap.html.template` is already self-contained (inline `<script>`, data injected as JSON, no CDN/external deps — verified by grep), so the graph view embeds with **zero additional JS libraries**. No node toolchain ever enters the repo or the Homebrew install. |
| ERB (stdlib `erb`) | ships with Ruby | Server-rendered dashboard HTML shell | Zero deps, template is rendered once per page load; everything dynamic flows through JSON endpoints. (erb is a default gem on the entire 3.1–4.0 range — stdgems.) |
| JSON + `Core::Syntax::Json` (stdlib, already used) | stdlib | NDJSON relay frames; `/api/*` state endpoints | Reuses the existing syntax seam; NDJSON lines make partial-relay failure lossy-but-safe (a dropped line is one lost log entry, never a corrupted stream). |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Open3 (stdlib, **already** the project's shell layer `Core::Sh`) | stdlib | UI-triggered Build/Rebuild spawns the real `spm-cache build`/`use` as a subprocess, stdout/stderr lines pumped to the SSE hub | Always for UI-triggered builds. Shelling out (instead of calling `Installer::Build` in-process) means the dashboard build takes the **exact terminal code path**, inherits the process-level `.spm-cache-build.lock` flock unchanged, and can't pollute server-process singletons (`Config.instance`). No new code path, no new dependency. |
| `socket` stdlib (`UNIXServer`, `SO_SNDTIMEO`) | stdlib | Relay client inside `build`/`use`/`watch` | Always; client sets a short send timeout (~250 ms) so a wedged server can never hang a build. New tiny module, e.g. `Core::Relay.emit(hash)` — best-effort by contract, never raises. |
| `fcntl`/`Socket` option constants (stdlib) | stdlib | Stale-socket cleanup: on server start, if the path exists and `File.socket?`, `File.unlink` before `UNIXServer.new` | Always. ( mirrors why `.spm-cache-build.lock` lives outside the sandbox) |
| `open` (macOS shell) via existing `Core::Sh` | n/a | `spm-cache web` opens the browser at `http://127.0.0.1:<port>` after the listener is up | Always. Port: fixed default (e.g. 7915) with `--port` override; bind **only** `127.0.0.1`. |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| RSpec (existing) | Servlet/endpoint tests | Unit-test `WEBrick::AbstractServlet` subclasses with stub request/response objects (pure, fast); plus **one** integration spec that boots the real server on `TCPServer` ephemeral port `127.0.0.1:0` and exercises `/`+`/api/state`+an SSE frame. No Capybara/no headless browser — the JS surface is too small to justify it; manual UAT covers the browser. |
| rubocop (existing, defaults) | Lint | No new cops needed; plain WEBrick code triggers nothing exotic. |

## Installation

```bash
# The only runtime change — in spm_cache.gemspec:
#   spec.add_dependency "webrick", ">= 1.8", "< 2"
# Dev environment (Gemfile is already the dev workflow; nothing else changes):
bundle add webrick --version ">= 1.8", "< 2"

# Frontend: nothing to install. No npm, no vendored JS files needed at all
# (vanilla EventSource/fetch). Static assets, if any are added later, go in
# assets/web/ — the gemspec already ships `assets/**/*`, so no gemspec change.
```

The lower bound `>= 1.8` matters: Homebrew's keg-only `ruby@3.3` bundles webrick **1.8.x**, so the range lets Bundler resolve from the bundled copy without touching the network on end-user installs, while dev machines on Ruby 3.4/4.0 get 1.9.2 from rubygems.org.

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| webrick | Hand-rolled `TCPServer` + manual HTTP parsing (zero gems at all) | Only if even the webrick gemspec declaration is forbidden. It re-implements HTTP/1.1 parsing, keep-alive, and chunked framing (~300+ lines) — the exact class of bug WEBrick exists to prevent. Not worth it to save a pure-Ruby, ruby-org-maintained, bundled-on-production-Ruby gem. |
| webrick | **Sinatra 4.2.1** (+ rack 3.2.7, rackup 2.3.1, mustermann, rack-protection, rack-session, tilt — 6 pure-Ruby runtime deps, verified via RubyGems API) | The defensible "grown-up" fallback. All deps are pure Ruby (no native builds), and Sinatra buys Rack middleware, routing elegance, and `Rack::Test`-based endpoint specs. **Trigger to switch:** endpoint count grows past ~15, or you need sessions/auth middleware. For v0.5's ~10 endpoints it's weight without payoff. |
| webrick | **Roda 3.107.0** (+ rack) | Roda is a leaner single-gem router than Sinatra, but it still drags in Rack, and its tree- routing style pays off at scale, not at 10 endpoints. Same trigger as Sinatra; if that trigger fires, prefer Sinatra for ecosystem familiarity. |
| webrick | **Puma 8.0.2** (+ nio4r) | Never for this project. Puma + nio4r are **native C extensions** — under the Homebrew install they must compile against the keg-only ruby, adding a build step and a new breakage surface to every user's `brew upgrade`/gem-install path. Puma's value is multi-core request throughput for many concurrent clients; a localhost dashboard serving one browser has none of that load. (Versions verified: puma 8.0.2 current, runtime dep = nio4r 2.7.5.) |
| webrick | **Falcon 0.57.0** (async fiber server) | Never for this project. Verified runtime deps: async, async-container, async-http, async-http-cache, async-service, async-utilization, bundler, localhost, openssl, protocol-http, protocol-rack, samovar — **12 direct**, 20+ transitive including the native-ext `io-event`. Falcon's fiber-per-connection model is genuinely the best SSE architecture in Ruby, but adopting it means adopting the whole async ecosystem to serve one local user. Fails the dependency rule by an order of magnitude. |
| SSE | **WebSocket** (needs `websocket-driver` 0.8.2 or hand-rolled RFC 6455) | Only if the dashboard ever needs server-push of *commands* or true bidirectional flow (e.g. an interactive terminal in the browser). Log streaming is one-way; SSE already includes reconnect. Note `websocket-driver`'s native `websocket-native` accelerator is optional — but the framing/upgrade complexity lands regardless. |
| UDS relay | **File tail** (CLI always appends NDJSON to a project event file; server tails it) | Only if UDS proves problematic (e.g. sandboxed environments that block socket files in project dirs). Costs: file grows on every CLI run even with no server; needs truncation/rotation policy; tail needs mtime polling (fine — `watch` already polls). UDS avoids all of it and is the same "if it exists, use it" opt-in philosophy. |
| UDS relay | **Redis / any pub-sub service** | Never. A network service dependency for a localhost, single-machine relay is absurd here and triple-violates the constraints (new runtime dep, new install, new failure mode). |
| UDS relay | **Named pipe (FIFO)** | Rejected on semantics: `open` on a FIFO blocks until a counterpart appears (writer hangs with no reader), and Ruby has no stdlib `mkfifo` (shelling out adds noise). UDS gives the same filesystem-path confinement without the blocking-open trap. |
| Vanilla JS | **htmx 2.x + SSE extension** (vendored) | Acceptable if the team prefers declarative HTML for toggles/table — it's a vendored-file choice, not a dependency. But htmx v2 requires its separate `ext/sse.js` for EventSource (verified: v2.0 removed `hx-sse` from core), and **htmx 4.0.0 shipped 3 days ago (2026-08-28)** — do not adopt a 3-day-old major for a v0.5 feature. Vanilla JS is fewer moving parts for this UI size. |
| Vanilla JS | **React/Vue/Svelte + Vite/esbuild asset pipeline** | Never under current constraints: requires a node toolchain in CI, Homebrew install, and contributor machines, plus a build artifact committed or generated at release. Nothing in the dashboard's complexity needs a virtual DOM. |
| Ruby-side server | **Swift-side serving** (GCDWebServer / Swifter / SwiftNIO) | Rejected. GCDWebServer — the only ergonomic option — is effectively unmaintained (last push 2022-10, verified via GitHub API). A SwiftNIO-based server means a large new Swift dependency tree plus rebuilding the dashboard's config-write/lock-f interaction in a second language. The Ruby gem is the single owner of `spm-cache.yml`, the lockfile, and the flock; the server must live there. The Swift proxy binary's job (proxy/umbrella generation) doesn't change. |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| Puma / nio4r | Native C extensions must compile against Homebrew's keg ruby on every user install; throughput benefits are irrelevant at localhost scale | webrick |
| Falcon / the async gem family | 12 direct + 20+ transitive deps; imports an entire concurrency ecosystem for one local user | webrick (thread-per-connection is fine for ≤ ~10 concurrent SSE tabs) |
| Sinatra/Roda for v0.5 | 1–7 extra pure-Ruby gems to route ~10 endpoints; also drags Rack's API surface into a codebase that has never used it | webrick `AbstractServlet` mounts (class-per-route-prefix, trivially stub-testable) — revisit Sinatra only past ~15 endpoints |
| WebSocket / websocket-driver | Two-way protocol for a one-way problem; framing + masking hand-rolled or new gem | SSE over WEBrick chunked responses |
| File-tail as the primary relay | Writes files during every CLI run even when no dashboard exists; rotation/truncation policy needed | UDS socket that is simply absent when `spm-cache web` isn't running (client no-ops) |
| Redis or any pub/sub broker | Network service dependency in a zero-service localhost tool | UDS NDJSON relay |
| htmx 4.x | Released 2026-08-28 — 3-day-old major version | Vanilla JS (or vendored htmx 2.x + sse extension if declarative HTML is preferred) |
| Any node/npm toolchain or asset pipeline | Violates the gem's zero-build distribution; Homebrew builds from a plain tarball | Hand-written ES2020, served as static files from `assets/web/` |
| Binding anything but `127.0.0.1` / CORS headers | The constraint is localhost-only; CORS headers would *widen* exposure | Bind 127.0.0.1; validate `Host`/`Origin` headers on POSTs (DNS-rebinding defense — a browser page from any origin can otherwise hit `127.0.0.1:<port>`); no CORS headers at all |
| Thin / Unicorn / Rainbows | Thin is effectively dormant (Eventmachine-based); Unicorn/Rainbows are Unix-forking models wrong for SSE streaming and macOS dev tools | webrick |

## Stack Patterns by Variant

**If the dashboard serves the pinned production Ruby 3.3 (today's Homebrew formula):**
- webrick resolves from the Ruby-shipped bundled copy (1.8.x) — the gemspec declaration costs nothing at install time.
- This is the overwhelmingly common path; treat Ruby 4.0 as the edge case below.

**If a user runs the gem under Homebrew's default `ruby` (now 4.0.6) or a fresh ruby-install:**
- WEBrick is **no longer bundled as of Ruby 4.0** (verified: absent from Ruby 4.0.6's bundled-gem set; webrick was a bundled gem from Ruby 3.0 through 3.4.x per stdgems). The gemspec declaration is what makes this a non-event: RubyGems fetches 1.9.2 (pure Ruby, no compile). The mistake to avoid is *relying* on bundled-ness instead of declaring the dependency.

**If the endpoint surface grows (config editor, remote push/pull UI, multi-project switcher):**
- Introduce Sinatra 4.2.1 (+ Rack 3.2.7) and keep webrick as the socket layer (rackup's WEBrick handler) — all pure Ruby, no native builds. To make this migration cheap from day one, keep servlets as thin adapters that call plain controller objects (the same objects the CLI commands call) — then the HTTP layer is swappable without touching business logic.

**If SSE connections ever multiply (many projects, dashboard kept open on multiple machines via ssh tunnel):**
- That is the only scenario where Falcon's fiber model earns its dependency weight. Re-evaluate then, not now.

**Port selection:** fixed default port with `--port` override; on `EADDRINUSE` print the URL of the already-running instance rather than failing (the UDS socket doubles as a "server already running" probe).

## Version Compatibility

| Package A | Compatible With | Notes |
|-----------|-----------------|-------|
| webrick 1.8.x–1.9.2 | Ruby 3.1, 3.2, 3.3 (bundled 1.8.x), 3.4 (bundled 1.9.x), 4.0 (NOT bundled — gem install) | `>= 1.8, < 2` pin covers the whole window. Bundled on 3.0–3.4 per stdgems; removed from the bundled set in Ruby 4.0. |
| webrick | the CI matrix (3.1–3.3) | Bundled everywhere in the matrix; specs never download it. |
| ERB / JSON / socket / Open3 | Ruby 3.1–4.0 | Default-gem stdlib throughout (stdgems). erb is a default gem 3.1→4.0. |
| sinatra 4.2.1 (fallback path only) | Rack 3.2.7, Ruby 3.x | Pure Ruby; only relevant if the endpoint-growth trigger fires. |
| puma 8.0.2 / nio4r 2.7.5 (rejected) | Ruby 3.x, native ext compile | Listed for completeness — the native-compile cost under keg-only ruby@3.3 is the rejection driver. |
| htmx 2.x (rejected; vendored only) | any browser | Requires separate sse extension since 2.0. htmx 4.0.0 is 3 days old — avoid. |
| EventSource browser API | all evergreen browsers | Server-sent events are universally supported; no polyfill needed. |

## Integration With the Existing Gem (for the planner)

- **Log emission hook:** terminal output flows through `Core::UI.info/warn/error` (plain puts) and `Core::LiveLog#output(line)` — which **already captures every line** in `@captured`. The relay is a small observer attached at these two surfaces (new `Core::Relay` module), not a rewrite of the shell layer.
- **Relay transport:** server binds `.spm-cache-web.sock` at the **project root**, beside `.spm-cache-build.lock` — deliberately *outside* the `spm-cache/` sandbox, for the same documented reason the build lock is (`recreate_dirs` must never delete a live path). Client = connect-if-present, NDJSON lines, 250 ms send timeout, rescue-and-no-op on any failure.
- **UI-triggered builds:** server spawns `spm-cache build`/`use` via the existing Open3 seam as a subprocess → inherits the flock and every code path unchanged; its stdout lines publish **directly** to the in-process SSE hub. Terminal/`watch` runs publish via the UDS relay into the same hub. One hub, two producers, zero protocol between them.
- **Per-package toggles:** the source of truth is already proven — `command/off.rb` does `config.raw["ignore"] = ...; config.save` on `spm-cache.yml`. `POST /api/packages/:name/toggle` performs the identical mutation (add/remove from the ignore list) — the web UI and `spm-cache off` are the same write path by construction.
- **Cache state table:** sizes via `Dir.glob(...).sum { File.size }` over the existing `Config#cache_dir(config)` layout (`<name>.xcframework` + `.provenance.json`/`.shims.json` sidecars); fidelity status from the provenance sidecars the v0.4.0 fidelity work already writes.
- **Doctor panel:** reuse the existing `--json` registry in-process (no shell-out needed from the server process).
- **Cachemap graph:** `cachemap.html.template` is already dependency-free (inline script + injected JSON — verified) — serve it as a dashboard view pointing at a `/api/cachemap` data endpoint instead of build-time JSON injection.
- **Security posture (stack-level):** bind 127.0.0.1 only; reject requests whose `Host` header isn't `127.0.0.1:<port>` and POSTs whose `Origin` isn't the dashboard origin (DNS-rebinding mitigation); no CORS headers; UDS socket perms are 0600-by-umask by default on macOS.

## Sources

- RubyGems API (`rubygems.org/api/v1/...`) — latest versions + runtime dependency lists for webrick 1.9.2, puma 8.0.2, falcon 0.57.0, sinatra 4.2.1, roda 3.107.0, rack 3.2.7, rackup 2.3.1, nio4r 2.7.5, websocket-driver 0.8.2 — **HIGH** (primary registry, fetched 2026-08-31)
- stdgems.org — webrick default-gem (≤2.7) / bundled-gem (3.0–3.4, `new-in/3.0`) / removed-in-4.0 (`/removed`, absent from 4.0.6 bundled list) status; erb default-gem status — **HIGH** (canonical gemified-stdlib reference)
- Homebrew formula API (`formulae.brew.sh/api/formula/...`) — `ruby` = 4.0.6 (current default), `ruby@3.3` = 3.3.12, not deprecated/disabled — **HIGH**
- webrick 1.9.2 source (`raw.githubusercontent.com/ruby/webrick`) — `HTTPResponse#chunked=` streaming support confirmed; pure Ruby — **HIGH**
- htmx.org migration guide + docs — `hx-sse`/`hx-ws` removed from core in v2.0, moved to extensions; v4.0.0 published 2026-08-28 (GitHub Releases API) — **HIGH**
- GitHub API — GCDWebServer last push 2022-10-05 (unmaintained) — **HIGH**
- Repo grounding: `.planning/codebase/STACK.md`, `lib/spm_cache/core/{log,live_log,config}.rb`, `lib/spm_cache/command/off.rb`, `lib/spm_cache/assets/templates/cachemap.html.template` — **HIGH** (read directly)
- classify-confidence seam: websearch → LOW, context7 → MEDIUM; all load-bearing claims above were therefore verified against the primary sources listed rather than carried from search snippets.

---
*Stack research for: spm-cache v0.5.0 Web Interface (localhost dashboard, log streaming, toggles)*
*Researched: 2026-08-31*
