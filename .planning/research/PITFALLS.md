# Pitfalls Research

**Domain:** spm-cache v0.5.0 "Web Interface" — a local web UI + live-output relay bolted onto an existing zero-dependency Ruby CLI (SwiftPM binary-cache tooling)
**Researched:** 2026-08-31
**Confidence:** HIGH

## Verification Basis

This document supersedes the v0.4.0 pitfalls research (Xcode/pinning domain), which is archived in git history. All code-anchored claims below were verified against **this repo** on 2026-08-31 by a prior pass that read the named sources; this pass re-confirmed the two most load-bearing ones by direct read (`Config#save`, `Core::LiveLog`). Environment claims were machine-probed on this Mac; external claims were verified against primary sources on 2026-08-31. Sections carrying **MEDIUM** are well-established web/platform knowledge added for template coverage — sound, but not re-derived here.

Code grounding map (seeded findings → pitfalls):

| # | Verified fact | Source | Pitfall |
|---|--------------|--------|---------|
| 1 | `Config#save` is a bare `File.write`; Singleton caches `@raw` at load | `lib/spm_cache/core/config.rb` | CP1 |
| 2 | `off` persists via the config `ignore` list | `lib/spm_cache/command/off.rb` | CP2 |
| 3 | Three-channel output: `Core::UI.info/warn` → raw `$stdout`/`$stderr`; `Core::Sh.run` two reader threads; `capture3` buffered; `LiveLog` unbounded + unconditional TTY codes | `lib/spm_cache/core/live_log.rb`, `lib/spm_cache/core/sh.rb` | CP3 |
| 4 | `Installer::Rollback` takes no build lock (flock only in Build/Use); flock = free busy/queue primitive | `lib/spm_cache/installer/rollback.rb`, `installer/build.rb:68`, `installer/use.rb:60` | CP4 |
| 5 | Legacy `--watch` loop in `Command::Use` (Package.resolved-only) alongside `Command::Watch` | `lib/spm_cache/installer/use.rb`, `lib/spm_cache/command/watch.rb` | CP5 |
| 6 | Watcher daemon: mtime polling, SIGTERM trap, self-trigger guard | `lib/spm_cache/core/watcher.rb` | CP6 |
| 7 | Suite is 441 examples, network-free, hermetic via spec seams | `spec/spec_helper.rb` | CP7 |
| 8 | `require 'webrick'` FAILS on rbenv 3.2.3 and Homebrew ruby@3.3 / ruby@4.0 | machine probe | CP8 |
| 9 | `localhost` resolves `::1` first on this Mac (dscacheutil) | machine probe | CP9 |
| 10 | AirPlay ControlCenter holds TCP 5000/7000 | machine probe | CP9 |
| 11 | Chrome 141/142: public pages fetching localhost need user permission (Local Network Access) | external, 2026-08-31 | CP13 |
| 12 | SSE: HTTP 204 stops EventSource reconnect permanently (readyState CLOSED) | external, 2026-08-31 | CP11 |

---

## Critical Pitfalls

### CP1: Stale config writeback — a UI toggle clobbers a concurrent CLI edit

**Confidence:** HIGH (code-anchored, spot-check re-confirmed)

**What goes wrong:**
`Config` is a Singleton that loads `spm-cache.yml` into `@raw` once, and `#save` writes that snapshot back with a bare, non-atomic, lock-free `File.write` (`lib/spm_cache/core/config.rb`). A web toggle that mutates `@raw` and calls `#save` minutes later writes back the snapshot it holds — silently reverting any key edited in the meantime by `spm-cache off`, a manual `spm-cache.yml` edit, or another web request. Worse, the write is not atomic: a reader (or a crash mid-write) can observe a truncated YAML file, and every subsequent CLI command fails to parse it.

**Why it happens:**
The write path was built for a single-process CLI where the Singleton is the only writer and runs are short-lived. A web server is a different lifecycle: long-lived process, config snapshot aged across requests, multiple writers.

**How to avoid:**
Never round-trip a held snapshot. On each mutating web request: re-read the YAML from disk, apply only the delta (e.g. toggle one package in `ignore`), write atomically (temp file + `File.rename`), under an `flock` on a dedicated config lock file (same pattern as `acquire_build_lock`). In the web layer, never cache `Config` state across requests — resolve per-request.

**Warning signs:**
- `spm-cache.yml` diffs show keys reverting that nobody edited.
- Two web toggles in quick succession and the first is lost.
- Intermittent `YAML::SyntaxError` on `spm-cache.yml` after UI use.

**Phase to address:** UI actions phase; the atomic read-modify-write seam belongs in the server foundation phase.

---

### CP2: A second source of truth for the ignore list

**Confidence:** HIGH (code-anchored)

**What goes wrong:**
`off` persists state by writing package names into the `ignore` list of `spm-cache.yml` (`lib/spm_cache/command/off.rb`). If the web UI implements its own toggle store (a JSON sidecar, localStorage, a DB row), the project now has two definitions of "is this package cached?" The UI says off, the CLI still caches; or the CLI's `ignore` list says off and the UI happily shows it enabled. Reconciliation bugs of this class are unrecoverable by users — there is no visible reason for the disagreement.

**Why it happens:**
The web layer reaches for the easiest local persistence instead of the existing canonical store, because going through the CLI's config path feels indirect.

**How to avoid:**
Web toggles MUST mutate the same `ignore` key in `spm-cache.yml` through the same code path — either call the existing command object or extract the toggle into a shared service both CLI and web call. No parallel store, no UI-side cache of enable/disable state that outlives a request.

**Warning signs:**
- `spm-cache off Foo` then the UI still shows Foo as cached (or vice versa).
- Any proposal for a UI-specific config file during planning.

**Phase to address:** UI actions phase.

---

### CP3: The three-channel output capture problem

**Confidence:** HIGH (code-anchored core) / MEDIUM (Ruby IO thread-safety guidance)

**What goes wrong:**
Human-visible output is scattered across three channels with no common seam:
1. `Core::UI.info`/`warn` print straight to raw `$stdout`/`$stderr` — sinks are not injectable.
2. `Core::Sh.run` streams subprocess output through **two reader threads** into the live log (`lib/spm_cache/core/sh.rb`).
3. `capture3` calls buffer whole subprocess outputs and dump them at completion.

And `Core::LiveLog` (`lib/spm_cache/core/live_log.rb`) makes both worse for a relay: `@captured` grows **without bound**, and every `output`/`sticky_section` call prints unconditional `TTY::Cursor` escape codes with no `tty?` check — both verified by direct read. A relay that taps only channel 2 shows a spinner and missing announcements; tapping the raw stream injects cursor-control bytes into SSE frames; a long watch session balloons memory.

**Why it happens:**
The existing design optimizes for one human in one terminal. A web relay is a second consumer that arrived after the output architecture set.

**How to avoid:**
- Add an injectable sink/broadcast to `Core::UI` (observer list; default behavior unchanged) so `info`/`warn` reach the relay without monkey-patching `$stdout`.
- Cap `LiveLog.captured` as a ring buffer and suppress cursor codes when not attached to a TTY or when relaying.
- Fan both `Sh.run` reader-thread lines and `capture3` results into the same event bus.
- Thread-safety: Ruby IO objects are not safe for concurrent writes — a **single writer thread must own each SSE response**; producers push onto a sized `Queue` (backpressure) rather than appending to shared arrays from multiple threads.

**Warning signs:**
- Relay shows runs but no "Cache hit"/warning lines (channel 1 untapped).
- Escape sequences visible in the browser console or SSE frames.
- RSS creep during long watch sessions; garbled interleaved output with two tabs open.

**Phase to address:** relay phase; the `Core::UI` sink seam must land in the server foundation phase because everything else depends on it.

---

### CP4: Rollback without a build lock — `rm_rf` under a live build; and the flock is your busy/queue primitive

**Confidence:** HIGH (code-anchored) / MEDIUM (double-click UX guidance)

**What goes wrong:**
Two failure modes, opposite directions:
1. `Installer::Rollback#perform_install` runs `restore_packages` + `remove_proxy` with **no build lock** — the flock covers `Installer::Build#perform_install` (`acquire_build_lock`, `lib/spm_cache/installer/build.rb:19,68`) and `Command::Use` (`with_build_lock`, `lib/spm_cache/installer/use.rb:23,35,60`) only. A web rollback during a live build deletes the sandbox out from under xcodebuild: cryptic mid-build failures, corrupted partial artifacts.
2. The flip side is an opportunity: the existing blocking flock **is** a complete busy/queue primitive. A web Build button that ignores it spawns duplicate builds; with it, a double-click queues rather than deduplicates — two xcodebuild runs back-to-back is not what the user asked for either.

**Why it happens:**
Rollback predates the lock and was considered "safe" because users ran it from a terminal, visibly, when nothing else was running. A browser button removes both guards: opacity and timing.

**How to avoid:**
- Wrap `Rollback` in the same flock (`config.build_lock_path` → `.spm-cache-build.lock`) before the UI-actions phase ships any rollback button.
- Decide **busy vs queue** explicitly for Build: recommended v0.5 posture is **busy** — a second build attempt gets an immediate "build in progress" response derived from lock state, rather than silently queueing minutes of xcodebuild from a stray click. Client-side button-disabling is UX sugar, never the mechanism; server-side in-flight dedupe (single in-flight build marker keyed by the lock) is.

**Warning signs:**
- Transient xcodebuild "file not found"/crash reports while a rollback ran.
- One click producing two sequential builds.
- UI shows "building" while the CLI reports the lock free (or vice versa).

**Phase to address:** UI actions phase (rollback locking is a prerequisite of the rollback button, not a follow-up).

---

### CP5: Two watcher paths — the relay double-counts runs

**Confidence:** HIGH (code-anchored)

**What goes wrong:**
A legacy `--watch` loop lives inside `Command::Use` (watching only `Package.resolved`) **alongside** the dedicated `Command::Watch` (`lib/spm_cache/command/watch.rb`). A relay that subscribes to both — or instruments Use generically — reports two runs per file save, or shows contradictory run state between the two paths.

**Why it happens:**
The legacy path exists for backward compatibility and is easy to forget; a relay author instrumenting "the CLI" naturally wraps both.

**How to avoid:**
The relay hooks exactly one path: the watcher daemon. Treat legacy `--watch` as CLI-only and explicitly excluded from the relay; note its deprecation in docs. If instrumenting shared code, tag events with their origin path and filter.

**Warning signs:**
- Two run cards per save in the UI.
- Run counters drifting from what the terminal shows.

**Phase to address:** relay phase.

---

### CP6: Watcher daemon integration — lifecycle and self-trigger hazards

**Confidence:** HIGH (code-anchored)

**What goes wrong:**
The watcher daemon (`lib/spm_cache/core/watcher.rb`) has three load-bearing behaviors a relay must respect, not fight:
- **mtime polling** — "live" status is poll-grained; any UI promising per-file, real-time progress is fabricating signal.
- **SIGTERM trap** — a web server that spawns the daemon and exits without forwarding signals orphans it; an orphaned watcher keeps mutating the sandbox with nobody watching.
- **Self-trigger guard** (against installer pbxproj rewrites re-triggering watch) — a web-initiated build also rewrites the pbxproj; if the guard doesn't know about web-originated runs, the UI's own Build button re-triggers a watch run, which streams another run, which…

**Why it happens:**
The guard was written when the only writer was the CLI. The web layer is a new writer class that the guard has never seen.

**How to avoid:**
Server owns the daemon lifecycle: spawn as a child, forward SIGTERM on shutdown, verify exit on stop. Extend the self-trigger guard to recognize web-initiated runs (tag runs with origin and have the guard skip relay-echoed events). Surface poll-grained honesty in the UI ("checked 5s ago") instead of fake live streams.

**Warning signs:**
- Watcher process alive after server quit.
- A web Build causing an immediate second (watch) run in the relay.
- UI flickering between run states.

**Phase to address:** relay phase.

---

### CP7: Web specs breaking the hermetic 441-example suite

**Confidence:** HIGH (code-anchored)

**What goes wrong:**
The suite is 441 examples, network-free, and hermetic via the spec seams in `spec/spec_helper.rb`. Web-layer specs that bind real ports, boot the real server, or spawn real watcher processes end that: port collisions in parallel runs, order dependence, external-network flakiness, and a suite that passes solo and fails in CI.

**Why it happens:**
A server feels like it must be tested by starting it. The existing seams make that unnecessary, but they are easy to skip when writing the first handler spec.

**How to avoid:**
Test handlers, routing logic, and event-bus behavior as pure units through the existing seams; inject fake socket/IO doubles. If a smoke test is unavoidable, exactly one tagged integration spec binding port 0 on `127.0.0.1` (OS-assigned port, never fixed), isolated from the hermetic run.

**Warning signs:**
- Spec wall-time jumps by seconds after web specs land.
- Flaky `Errno::EADDRINUSE` in the suite; specs green only when run alone.

**Phase to address:** server foundation phase — the seams are designed there; retrofitting them after the relay exists is the expensive path.

---

### CP8: WEBrick is not available — the dependency declaration is load-bearing

**Confidence:** HIGH (machine-verified 2026-08-31)

**What goes wrong:**
`require 'webrick'` fails on this machine's rbenv Ruby 3.2.3 and on Homebrew ruby@3.3 and ruby@4.0. WEBrick left the stdlib in Ruby 3.0 and rode the bundled-gems list only through 3.4; on 4.0 it is gone entirely. A server that boots in the maintainer's bundler context raises `LoadError: cannot load such file -- webrick` for gem-installed users — found in the field, not in CI.

**Why it happens:**
Dev machines carry webrick transitively (some other gem depends on it), so the missing declaration is invisible locally.

**How to avoid:**
Declare the server (`webrick` or the chosen alternative) as a **runtime dependency in the gemspec** — this is load-bearing, not optional. Add a smoke spec asserting the `require` succeeds outside a `Bundler` context.

**Warning signs:**
- `cannot load such file -- webrick` in issue reports; "works for me" replies.
- Any plan that says "webrick is in the stdlib".

**Phase to address:** server foundation phase, before the first `require`.

---

### CP9: Loopback binding traps — `::1` resolves first, AirPlay owns 5000/7000

**Confidence:** HIGH (machine-verified 2026-08-31)

**What goes wrong:**
Two environment facts, one symptom class ("connection refused while the log says listening"):
- `localhost` resolves `::1` **first** on this Mac (dscacheutil). A server binding `localhost` may listen IPv6-only while the browser, a health probe, or a relay client dials `127.0.0.1` — refused, with the server insisting it is up.
- AirPlay ControlCenter occupies TCP **5000 and 7000**. The "obvious" default port collides with ControlCenter — `Errno::EADDRINUSE`, or worse, something alien answering on 5000.

**Why it happens:**
Name-based binds hide which address family actually bound, and port choices made on Linux assumptions don't survive macOS services.

**How to avoid:**
Bind explicit `127.0.0.1` (or deliberately dual-stack both families) — never the bare name. Print the exact bound URL. Select the port by probing: bind port 0 and report the OS-assigned port, or probe a candidate list that skips 5000/7000. Persist the chosen port so the relay tab reconnects to the same endpoint across restarts.

**Warning signs:**
- Intermittent `ERR_CONNECTION_REFUSED` on some machines only.
- EADDRINUSE on a hand-picked default; a ControlCenter dialog appearing when the UI is opened.

**Phase to address:** server foundation phase.

---

### CP10: Relay/process lifecycle races

**Confidence:** MEDIUM (structural races; specifics from code grounding)

**What goes wrong:**
Three races between the CLI world and the server world:
1. A CLI run starts before the server is up — the UI never learns the run happened.
2. The server restarts mid-run — SSE clients reconnect, but in-memory run state is gone; the UI shows idle while xcodebuild lives.
3. Interleaved concurrent runs — events from two builds interleave into one stream with no attribution.

**Why it happens:**
The natural implementation keeps run state in server memory and streams live events only — a design that works until the server and the CLI have independent lifecycles, which is exactly the web milestone's premise.

**How to avoid:**
Persist a run journal to disk (reuse `metadata_dir` conventions) so state survives restarts. Derive "a build is running" from the flock (`.spm-cache-build.lock`) rather than from server memory, so pre-server runs are discoverable at boot. Tag every event with a `run_id` and origin. On boot, adopt or clearly flag orphaned runs — never claim a running xcodebuild is dead.

**Warning signs:**
- UI idle during a terminal-initiated build; two builds' lines interleaved in one card; current run vanishes after server restart while `ps` shows xcodebuild alive.

**Phase to address:** relay phase.

---

### CP11: SSE transport hazards — buffering, reconnect storms, replay, backpressure

**Confidence:** MEDIUM (transport practice) / HIGH for the 204 clause (externally verified 2026-08-31)

**What goes wrong:**
Four distinct ways the live stream breaks:
1. **Buffering** — an intermediary (AV/VPN local proxy, any future reverse proxy) holds chunked SSE frames; the user sees nothing for minutes, then a burst.
2. **Reconnect storm + the 204 trap** — EventSource auto-reconnects by default; a dead server plus several open tabs is a thundering herd. And a "not ready" handler that answers **HTTP 204 stops reconnection permanently** (readyState CLOSED per the WHATWG SSE spec) — tabs go silent forever, with no error shown.
3. **Lost lines on reconnect** — without Last-Event-ID replay, clients silently miss everything emitted while disconnected. The failure line of a failed build is precisely the likely casualty.
4. **Backpressure** — xcodebuild can emit thousands of lines per second; per-client unbounded queues balloon memory the moment a client is slow or half-dead.

**How to avoid:**
`Content-Type: text/event-stream`, flush headers immediately, heartbeat comment (`: ping`) every ~15s to defeat idle timeouts and detect dead sockets. For "not ready", respond 503 with a `Retry:` header — never 204. Assign monotonic event IDs and implement Last-Event-ID replay from the CP3 ring buffer. Size per-client queues; drop-oldest with an explicit "N lines dropped" event rather than growing without bound.

**Warning signs:**
- Events arriving in multi-minute bursts; tabs silently never reconnecting after a restart (the 204 bug); missing failure lines after reconnect; RSS growth while a tab sits backgrounded.

**Phase to address:** relay phase.

---

### CP12: Browser/session lifecycle on macOS

**Confidence:** MEDIUM (template knowledge; grounded in the TTY/env facts of CP3)

**What goes wrong:**
Launch and session edges pile up: `open <url>` targets the default browser without new-window guarantees and breaks on non-default setups; the server dies mid-build leaving orphaned tabs reconnect-looping against nothing; macOS sleep suspends the server mid-stream and on wake every tab reconnects at once (feeding the CP11 storm). Separately, existing code paths assume TTY semantics (`Core::LiveLog` cursor codes) and a shell-grade environment — a server launched from Finder/launchd has a different PATH and no TTY, so running the installer in-process can diverge from CLI behavior in env- and TTY-dependent code.

**How to avoid:**
Idempotent launcher: health-check first, open the tab only after (or reuse a running server). For build/rollback actions prefer spawning the CLI entry as a subprocess with explicit env — reusing existing env handling — over running the installer in-process inside the server. Heartbeat-based dead-socket detection client-side; cap reconnect `retry` and show an explicit "server offline" state. All UI state re-hydrates from the server journal on reconnect (CP10), so wake/restart recovery is automatic.

**Warning signs:**
- Two app windows per launch; tabs reconnect-looping silently; wrong UI state after wake; builds behave differently launched from UI vs terminal.

**Phase to address:** server foundation phase (launcher, subprocess-vs-in-process decision), relay phase (reconnect policy), UI actions phase (state rehydration).

---

### CP13: Localhost is not trusted — DNS-rebinding, CSRF, command injection

**Confidence:** MEDIUM (security canon) / HIGH for the Chrome clause (externally verified 2026-08-31)

**What goes wrong:**
Binding to loopback does not make the server private. Any public web page can fire cross-origin POSTs at `http://127.0.0.1:<port>` (drive-by build/cancel/rollback), and DNS-rebinding can turn a public hostname into your loopback and read responses. The endpoints here are unusually destructive for their size: build, rollback (`rm_rf` of the sandbox), config toggles. If any request param — package name, target, path — is interpolated into a shell string, that is command injection with full user privileges. Chrome 141/142 now gates public-page → localhost requests behind a Local Network Access permission prompt, which reduces drive-by exposure but is one browser's mitigation, not a boundary.

**How to avoid:**
- Validate `Host` and `Origin` on **every** mutating endpoint; reject absent/foreign origins. The UI is same-origin, so no CORS machinery is needed — just rejection. Bind loopback only, never `0.0.0.0`.
- Require a per-launch token embedded in the served page on mutating calls — cheap CSRF defense that also blocks rebinding reads.
- Treat every param as data: spawn subprocesses with array argv (`Process.spawn` array form / `system([cmd, cmd], *args)`), never shell-string interpolation; validate package/target names against the project's known packages (config/lockfile) before acting; resolve any client-supplied path and require it stays under `project_dir`.

**Warning signs:**
- `curl -X POST` with no Origin header succeeds — decide deliberately whether that is a feature (CLI integration) or a hole. Any `"#{param}"` inside a backtick/shell string. Extensions or other tabs' scripts able to trigger builds.

**Phase to address:** server foundation phase (Host/Origin middleware, token issuance), UI actions phase (param validation at each action).

---

## Technical Debt Patterns

**Confidence:** MEDIUM

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| String-interpolated shell commands for build triggers | Fast to write | Injection + quoting bugs (CP13) | Never |
| Redirecting global `$stdout` to capture output | Quick "relay" | Breaks CLI UX, thread-unsafe, races with reader threads | Never — use the injectable `Core::UI` sink |
| Unbounded in-memory event log | Simple code | RSS creep on long watch sessions | Only with a hard ring-buffer cap |
| UI-side JSON toggle store | Decoupled from config | Second source of truth vs the `ignore` list (CP2) | Never |
| Lazy `require 'webrick'` without gemspec entry | No gem release hassle | `LoadError` in the field (CP8) | Never |
| Polling-only JS client "for now" | Demo ships sooner | Whole client rework when SSE lands | v0.5 throwaway demo only, if explicitly marked |

## Integration Gotchas

**Confidence:** MEDIUM

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| macOS `open` | Assuming a fresh window/default browser exists | Health-check then launch; idempotent (CP12) |
| Homebrew service mode | Running the server under `brew services` and wondering why TTY-dependent output and PATH differ | Foreground run only for v0.5; document service mode as unsupported (LiveLog/TTY assumptions) |
| xcodebuild from a GUI-launched server | Inheriting the server's env (no TTY, reduced PATH) | Spawn the CLI entry with explicit env; never trust inherited env (CP12) |
| EventSource probes | 204 or tiny-timeout responses to "is it up" checks | 503 + `Retry:` header; 204 kills reconnect permanently (CP11) |
| Chrome Local Network Access (141/142) | Assuming a public page can fetch localhost freely | Same-origin UI avoids the prompt entirely; expect prompts for any cross-page access |

## Performance Traps

**Confidence:** MEDIUM

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Unbounded output buffers (`LiveLog.captured` pattern) | Memory creep over long sessions | Ring buffer with cap (CP3) | Multi-hour watch sessions |
| Per-client fan-out copies of full history | RSS scales with tab count | Shared ring buffer + per-client cursor (CP11) | Third concurrent tab |
| High-frequency status polling | CPU spin, log noise | SSE push + heartbeat | First multi-tab user |
| Status re-read per event on burst output | Disk thrash during builds | Cache per `run_id`, invalidate on state change | Thousands of lines/sec |

## Security Mistakes

**Confidence:** MEDIUM

| Mistake | Risk | Prevention |
|---------|------|------------|
| "It's localhost, skip auth" | Drive-by CSRF from any web page triggers build/rollback/toggles (CP13) | Host/Origin validation + per-launch token on mutating endpoints |
| Interpolating params into shell strings | Command injection via crafted names/paths (CP13) | Array argv spawn; validate names against project packages |
| Serving the UI on `0.0.0.0` "for phone testing" | LAN-wide exposure of build controls | Loopback bind only; document an ssh tunnel for remote access |
| Trusting client-supplied paths | Path traversal in rollback/inspect endpoints | Resolve + require prefix under `project_dir` |

## UX Pitfalls

**Confidence:** MEDIUM

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| No build-in-progress indicator | Double-clicks, duplicate builds | Busy state derived from the flock (CP4) |
| Lost scrollback after reconnect | User misses the failure line | Last-Event-ID replay + retained ring buffer (CP11) |
| Fake live progress from mtime polling granularity | Flicker, misinformation | Honest "checked Ns ago" states (CP6) |
| Port changes between launches | Bookmarks die silently | Persist chosen port; pinned URL (CP9) |

## "Looks Done But Isn't" Checklist

**Confidence:** MEDIUM (execution-time verification list)

- [ ] **Build button:** often missing the busy-vs-queue decision — verify double-click and a concurrent CLI build
- [ ] **Off toggle:** verify `spm-cache.yml`'s `ignore` list changed, not a UI-side store (CP2)
- [ ] **Output relay:** verify `Core::UI.warn`/stderr content appears, not just `Sh.run` stdout (CP3)
- [ ] **SSE reconnect:** kill -9 the server, restart, verify missed lines replay (CP11)
- [ ] **Rollback during build:** verify it locks or is rejected while the flock is held (CP4)
- [ ] **Gem-installed run:** verify the server boots outside bundler — dependency declared (CP8)
- [ ] **Hermetic suite:** verify web specs bind no fixed ports and the 441-example base stays green solo or shuffled (CP7)
- [ ] **Sleep/wake:** Mac sleeps mid-stream; on wake, tabs recover state (CP10/CP12)
- [ ] **Mutation security:** `curl -X POST` without Origin/token is rejected (CP13)

## Recovery Strategies

**Confidence:** MEDIUM

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Config clobbered (CP1) | LOW | Restore from editor/backup; re-apply toggles; add pre-write backup |
| Sandbox `rm_rf`'d mid-build (CP4) | MEDIUM | Re-run build; lock now prevents recurrence; no user data lost, time only |
| Orphaned watcher daemon (CP6) | LOW | Kill by process name; add single-instance guard |
| Event-buffer memory bloat (CP3/CP11) | LOW | Restart server; clients auto-reconnect and replay |
| Port stolen by AirPlay/system update (CP9) | LOW | Re-probe, persist new port, reopen tab |

## Pitfall-to-Phase Mapping

**Confidence:** HIGH (placement follows from the code grounding)

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| CP1 stale config writeback | UI actions phase | Concurrent CLI-edit + web-toggle spec; atomic write asserted |
| CP2 ignore-list divergence | UI actions phase | Toggle → assert `ignore` list in `spm-cache.yml` |
| CP3 output capture | Server foundation (sink seam) + relay | Spec: `UI.warn`, `Sh.run` stream, `capture3` all reach the bus |
| CP4 rollback/build concurrency | UI actions phase | Rollback-while-flock-held spec; double-click dedupe test |
| CP5 double watcher paths | Relay phase | Single-subscription spec; legacy `--watch` excluded |
| CP6 watcher lifecycle | Relay phase | SIGTERM stop test; web-run self-trigger guard test |
| CP7 hermetic suite | Server foundation phase | Web specs green shuffled, no fixed ports |
| CP8 webrick dependency | Server foundation phase | Post-install `require` smoke spec |
| CP9 loopback binding/ports | Server foundation phase | Boot prints reachable `127.0.0.1` URL; 5000/7000 skipped |
| CP10 lifecycle races | Relay phase | Restart-mid-run adoption test |
| CP11 SSE transport | Relay phase | Replay spec; no-204 assertion; backpressure test |
| CP12 macOS session edges | Server foundation + relay phase | Sleep/wake script; idempotent launch test |
| CP13 localhost security | Server foundation + UI actions phase | No-Origin mutation rejected; injection-attempt fixture |

## Sources

- Code grounding: this repo — `lib/spm_cache/core/config.rb`, `core/live_log.rb`, `core/sh.rb`, `core/watcher.rb`, `command/off.rb`, `command/watch.rb`, `installer/{build,use,rollback}.rb`, `spec/spec_helper.rb` (verified 2026-08-31; CP1/CP3 re-confirmed by direct read in this pass)
- Machine probes (2026-08-31): `require 'webrick'` matrix (rbenv 3.2.3; Homebrew ruby@3.3, ruby@4.0); dscacheutil `localhost` → `::1` ordering; AirPlay ControlCenter occupancy of TCP 5000/7000
- External (2026-08-31): Chrome 141/142 Local Network Access permission shift; WHATWG HTML spec, Server-Sent Events (204 terminates EventSource reconnection)
- Template-coverage knowledge (MEDIUM, unverified here): SSE buffering/replay practice, Ruby threaded-IO semantics, localhost web-security canon

---
*Pitfalls research for: spm-cache v0.5.0 Web Interface*
*Researched: 2026-08-31*
