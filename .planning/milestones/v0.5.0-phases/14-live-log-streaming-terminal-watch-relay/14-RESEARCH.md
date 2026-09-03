# Phase 14: Live Log Streaming + Terminal/Watch Relay - Research

**Researched:** 2026-09-01
**Domain:** SSE-over-WEBrick transport + runs-dir file tailer + state derivation for a localhost Ruby dashboard (SPMCache v0.5.0)
**Confidence:** HIGH — every integration seam re-read in this repo at file:line this session; WEBrick 1.9.2 gem source read directly (httpresponse/httpserver/server/config/httprequest), and the three load-bearing transport behaviors **machine-probed live** on this machine (chunked flush timing, Last-Event-ID round-trip, keep-alive close); WHATWG SSE processing model fetched verbatim from the spec today

## Summary

Phase 14 adds one SSE stream over the shared run log. The transport verdict is settled (file-tail of `.spm-cache/runs/*.jsonl`; CONTEXT "Carrying forward") so this research deepens exactly the four MEDIUM areas the milestone flagged: **WEBrick transport mechanics, tailer design, watcher interplay, and state derivation**. The headline findings, all verified against the installed webrick 1.9.2 gem and the WHATWG spec:

1. **The sanctioned WEBrick streaming pattern works and flushes per write — verified live.** `res.chunked = true` + `res.body = proc { |out| ... }` routes through `send_body_proc` → `ChunkedWrapper#write`, which writes each chunk to the socket immediately (webrick httpresponse.rb:535-578). A live probe on this machine (Ruby 3.2.3) measured per-event arrival within 0.01s of the write across a 6-event stream — no Ruby IO buffering stall, no manual flush needed. The milestone's "buffering" hazard is real for intermediaries, not for this server.
2. **The 503 clause of CP11 is wrong in one direction and the plan must not copy it.** The WHATWG SSE processing model (§9.2.3, fetched verbatim 2026-09-01) fails the connection *permanently* for **any non-200 status**: "if res's status is not 200, or if res's Content-Type is not text/event-stream, then fail the connection… Once the user agent has failed the connection, it does not attempt to reconnect." 204 is not uniquely fatal — **503 is equally fatal**, and an HTTP `Retry:` response header plays no role in the SSE model (only the in-stream `retry:` field sets reconnection time). The correct "not ready" posture: the endpoint always answers **200 text/event-stream** and holds with heartbeats / in-stream `retry:`. Auth failures (401/403) are permanent-by-design and map to the existing token-invalid surface.
3. **Graceful shutdown has a hidden join-hang that the design must defuse.** WEBrick's accept-loop `ensure` **joins every connection thread** (webrick server.rb:210). An SSE body proc that loops forever would hang `server.shutdown` — violating WEB-03 (TERM/INT → exit 0). The broadcaster must end each proc on a shutdown sentinel, and each request thread must pop its queue with a bounded timeout that doubles as the heartbeat timer. The one port-0 integration spec proves shutdown-within-bound.
4. **Byte-offset ids over the JSONL files are safe and sufficient.** RunLog writes valid UTF-8 (scrubbed at write, run_log.rb:248) with `JSON.generate` escaping every newline inside strings, so `\n`-splitting is unambiguous at the byte level and offsets are stable. `Last-Event-ID` round-trips a composite id (`"<filename>:<offset>"` — filenames contain no colons, format regex-verified) through WEBrick's header parser — **verified live**, including the exact string a reconnecting tab will send. Client-supplied ids are attacker input: validate with the filename regex + runs-dir containment before any `File.open` (T-13-04 precedent).
5. **Everything Phase 14 needs from Phases 12/13 already exists as seams**: `RunLog.current`, the frozen event vocabulary, `pid_alive?` (Process.kill(0)) for CP10/CP14, the blocking-flock sites for D-05's line, `Middleware.valid_token?` + `req.query['token']` (EventSource cannot send headers — the query-param path is already implemented), and `spec/support/web_server_boot.rb` for the single port-0 integration boot. No new runtime dependency.

**Primary recommendation:** One `Web::Events` module (tailer thread + per-client bounded queues + shutdown sentinel), a `GET /api/events` route that always answers 200 `text/event-stream` with `keep_alive = false` and heartbeat-by-pop-timeout, ids of the form `<filename>:<byte-offset>` with regex+containment validation, a `GET /api/runs` directory-listing read model for D-12/D-13, and the "Waiting for build lock…" probe-then-announce-then-block insert at the two existing blocking-flock sites. Stream the JSONL lines verbatim as SSE `data:` (they are already JSON); render client-side keyed on the `event` field per T-12-01.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Live view behavior**
- **D-01:** Auto-follow with pause-on-scroll — view locks to the tail; scrolling up pauses with a "paused — N new lines · jump to live" pill; clicking resumes. (reversible)
- **D-02:** Bounded render ring (~500 lines) — older lines leave the DOM, replaced by an "… N earlier lines — reload to replay from start" notice. Mirrors the server-side bounded-queue stance (CP11). Full run always on disk (Phase 12 D-05). (reversible)
- **D-03:** Failure surfaces as a sticky banner (exit status + jump-to-first-error anchor) plus in-stream error-line styling via the existing `:fail` color vocabulary. (reversible)

**Multi-run presentation**
- **D-04:** New run while an older one is viewed → stream auto-switches to the newest run with a persistent "switched to new run — previous: <run-id>" notice; previous run stays reachable. (reversible)
- **D-05:** Lock contention shows INLINE: "waiting for build lock…" attribution in-stream for the blocked run, derived from the flock + run logs (CP10), never server memory. The research mandates this line in the Installer — Phase 14 wires its display. (costly — touches the Installer's output seam; same line feeds terminal users, wording is user-visible in two surfaces)
- **D-06:** Run identity renders as a CARD above the stream: trigger-source badge + command + config + started-at + argv detail + live status dot flipping to ✓/✗ on `run_end`. (reversible)

**Anchors & run identity**
- **D-07:** Anchor rail covers the FULL frozen Phase-12 D-04 vocabulary: `package_start` events AND phase markers (detect/integrate/build/fidelity) as jump targets. (reversible)
- **D-08:** Anchors live in a sticky chip rail on the log panel's edge (graph-legend precedent), visible while following the tail. (reversible)
- **D-09:** Anchor click JUMPS and FILTERS — non-matching lines dim/hide with a "filtered: <pkg>" pill. (reversible)
- **D-10:** On run failure while a filter is active, the banner PIERCES the filter: shows regardless; its jump-to-error anchor exits the filter (real position, pill cleared). (reversible)
- **D-11:** Trigger-source badge derives from the run-log header (command + argv; watch cycles carry `command: watch` per Phase 12 D-09). The `UI` badge is forward-compatible: reserved/hidden until Phase 15's spawned argv carries the marker. (costly — attribution vocabulary feeds Phase 15's job machinery)

**Replay & history scope**
- **D-12:** Current run + a compact recent-runs dropdown (identity + status per entry, read straight from the runs dir — no DB, no search, no extra storage). (reversible)
- **D-13:** Cold load shows live-or-last: live run → replay from byte 0 then follow; no live run → most recent completed run replayed with a "completed <time> ago" identity card. (reversible)
- **D-14:** 14-VALIDATION's manual table explicitly includes an agent-browser streaming probe as a recorded, repeatable step: start a real `spm-cache` run from a terminal, assert live render + replay + reconnect-without-loss across a server kill/restart mid-run. (reversible)

**Carrying forward (research/roadmap-locked — do not re-litigate)**
- Transport: file-tail of the JSONL run logs; UDS is the documented sandbox fallback only.
- SSE + `EventSource` (not WebSocket); failed connects answer 503 + `Retry:` (NEVER 204); `Last-Event-ID` replay; ~15s heartbeats; bounded per-client queues with drop-oldest + explicit notice (CP11). *(Research note: the 503 clause is refined by this research — see State of the Art; the "never 204" intent — never answer a stream request with a reconnect-killing status — is upheld and strengthened.)*
- Relay hygiene: watcher-daemon-only subscription (exclude legacy `--watch` path, CP5); SIGTERM forwarding + web-run self-trigger guard extended (CP6); health-check-before-open (CP12).
- Honest pid-dead-without-exit-line runs (CP14 detection nuance).
- Single stream + per-package anchors (N panes declined); stateless file reader; flock is the only mutex.

### Claude's Discretion
- `Web::Events` internal structure (tailer polling interval, ring buffer sizing, broadcaster thread model) within the CP11 constraints → recommended below.
- SSE endpoint path/naming and event payload field names (same-launch client/server, no versioning) → recommended below.
- Exact CSS/DOM layout of the log panel within the dark-first/system-font/status-color constraints.
- Recent-runs dropdown placement and entry truncation.

### Deferred Ideas (OUT OF SCOPE)
- Full historical browsing with per-run filters (status/verb/date) — borders the declined run-history-DB anti-feature.
- UI-triggered run streaming — Phase 15 (rides this phase's stream; UI badge reserved in the identity vocabulary now).
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| LOGS-02 | Browser shows a single live log stream with per-package anchors while a build runs | Tailer (Pattern 2) + `/api/events` (Pattern 1); anchors from the frozen vocabulary verbatim quotes (`package_start` build_pipeline.rb:68, `phase` markers use.rb:24/29, build.rb:41, build_pipeline.rb:92) |
| LOGS-03 | Loading mid-build replays from start; reconnects resume without lost lines (Last-Event-ID; never 204) | Byte-offset ids `<file>:<offset>` (Pattern 2); Last-Event-ID verified live through WEBrick's parser; 200-always posture per spec §9.2.3 (State of the Art) |
| LOGS-04 | Terminal- and `watch`-initiated runs stream into the same browser view as UI-triggered runs | File-tail transport is writer-agnostic: every run is a `.jsonl` file with the same header (`trigger` field, run_log.rb:137); watch cycles already land per-cycle files (D-09, run_log.rb:103 skips the Main-level watch log) |
| LOGS-05 | Each run shows identity — trigger source, command, status — with external-run detection from the build lock | Header verbatim keys (run_log.rb:128-139) for the D-06 card; CP10 derivation = non-blocking flock probe (Pattern 4) + `pid_alive?` reuse (run_log.rb:395-402) + CP14 honest states |
</phase_requirements>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Run-log tailing (poll, byte-offset read, line split) | `Web::Events` tailer thread (API/backend tier) | — | Server is the file reader; RunLog stays a writer, untouched |
| SSE transport (framing, heartbeat, backpressure, replay) | `Web::Events` broadcaster + `Router` `/api/events` route | WEBrick connection thread (body proc) | WEBrick's thread-per-connection runs the body proc; broadcaster owns queues/sentinel |
| Run discovery + identity/status derivation (CP10) | `Web::Events` / read model (flock probe + header parse) | `Core::RunLog` helpers (`pid_alive?`, header shape) | Truth on disk only; server never holds the lock, never keeps run state in memory |
| D-05 "waiting for build lock…" emission | `Installer::Build`/`Installer::Use` (the blocked run itself) | `Core::UI` → tee → run log | The line must exist in the run log for the stream to attribute it; terminal sees the same line (D-05) |
| Recent-runs listing (D-12) + cold-load choice (D-13) | `GET /api/runs` read model | frontend dropdown | Directory listing + header/exit parse; no DB (D-12) |
| Log panel UI (ring, anchors, pills, banner, filter) | Frontend (`log.js` module + index.html/styles.css) | — | el()/textContent discipline; SSE-driven; state-table polling continues independently |
| Watch relay hygiene (CP5/CP6) | Structural (no coupling) | — | Zero new watcher coupling: cycles are already files; `Core::Watcher` untouched |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| (none new — Ruby stdlib + existing deps only) | — | `webrick` (server, already runtime dep), `json` (line parse/generate), `socket` (integration probe), `open3` (existing) | Project constraint: webrick is the milestone's ONLY sanctioned new runtime dep (landed Phase 13); everything Phase 14 needs rides it or stdlib |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| webrick | 1.9.2 (Gemfile.lock pin; gemspec `>= 1.8, < 2` [VERIFIED: spm_cache.gemspec:40]) | HTTP server; `HTTPResponse#chunked=` + proc body = SSE | The ONLY server surface; verified streaming mechanics this session |
| claide (existing) | — | no new flags needed this phase (`web` verb exists) | Only if a flag emerges; none identified |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Per-client writer threads | Request thread pops its own queue (recommended) | A dedicated writer per client doubles threads and adds handoff; the WEBrick connection thread is already the natural per-client writer — bounded pop gives heartbeat timing for free |
| `SizedQueue#pop` with timeout | `Queue` + separate heartbeat timer thread | A timer thread adds shutdown ordering complexity; `pop(timeout:)` (Ruby ≥ 2.3 for Queue; SizedQueue always) bounds heartbeat latency with zero extra threads |
| Server-side line rendering → SSE `text` | Stream JSONL verbatim, render client-side (recommended) | Re-encoding doubles work and risks drift from T-12-01 semantics; the JSONL line IS the payload |
| Polling `/api/runs` from JS for D-12/D-13 | SSE `switch`/`hello` events only | Dropdown needs an on-open listing; one token-gated GET is cheaper than inventing SSE request semantics |

**Installation:** nothing to install — `bundle install` already resolves webrick 1.9.2 [VERIFIED: Gemfile.lock].

## Package Legitimacy Audit

> No external packages are installed by this phase — webrick is already the Phase 13 runtime dependency; nothing new enters the gemspec. Audit table intentionally empty.

| Package | Registry | Age | Downloads | Source Repo | Verdict | Disposition |
|---------|----------|-----|-----------|-------------|---------|-------------|
| (none) | — | — | — | — | — | — |

**Packages removed due to [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

## Architecture Patterns

### System Architecture Diagram

```
 TERMINAL / WATCH (writers, unchanged)                    BROWSER (127.0.0.1:PORT)
 spm-cache build / use / watch cycle                      index.html + app.js + log.js
      │  tee + Sh sinks (Phase 12)                              │
      ▼                                                         │ EventSource GET
 .spm-cache/runs/*.jsonl  ◄─ retention prune at each            │ /api/events?token=…
      │           open (D-07; live-pid runs immune)             ▼
      │                                                    Router.service
      │  mtime+size poll (Core::Watcher precedent)          Host/Origin gate (all routes)
      └────────────────────────┐                            token gate (?token=)
                               ▼                                 │
                    Web::Events::Tailer (1 thread)               ▼
                    ├── discover new run file ──► switch notice (D-04)
                    ├── read appended bytes (binary, byte offsets)
                    ├── split complete lines; partial tail buffered
                    └── fan out to per-client bounded queues ──► drop-oldest + notice (CP11)
                               │
              ┌────────────────┼─────────────────┐
              ▼                ▼                 ▼
        conn thread 1    conn thread 2    conn thread N   (WEBrick thread-per-connection)
        pop(timeout 15s) pop(timeout 15s) pop(timeout 15s)
        ── heartbeat ──  ── heartbeat ──  ── heartbeat ──   ": ping" comment on timeout
        write SSE frame  write SSE frame  write SSE frame    (ChunkedWrapper per-write flush)
              │                │                 │
              └── shutdown sentinel ends every proc ──► server.shutdown joins cleanly (WEB-03)

 STATE DERIVATION (CP10, no memory):
   GET /api/events (fresh connect) ──► pick active run: newest file with
     alive header pid AND no run_end; else newest file overall (D-13)
   flock probe .spm-cache-build.lock (LOCK_EX|LOCK_NB, release immediately)
     held + attributable run ► "running <run>"; held + none ► "unknown holder" (LOGS-05);
     free ► idle
   pid dead + no exit line (CP14) ► "interrupted — exit unknown", never "running"
```

### Recommended Project Structure

```
lib/spm_cache/
├── installer/
│   ├── build.rb             # MOD: probe→announce→block in acquire_build_lock (D-05)
│   └── use.rb               # MOD: same shape in with_build_lock (D-05)
├── web/
│   ├── router.rb            # MOD: dispatch '/api/events' (SSE) + '/api/runs' (GET)
│   ├── events.rb            # NEW: Tailer + Broadcaster (or events/ subdir if it grows)
│   └── read_models/
│       └── runs.rb          # NEW: D-12 directory listing + identity/status per entry
└── web/assets/
    ├── index.html           # MOD: log panel section + <script type="module" src="assets/log.js">
    └── log.js               # NEW: second ES module (14-CONTEXT permits exceeding app.js budget)
spec/
├── events_tailer_spec.rb    # NEW: tailer units (tmpdir fixtures)
├── events_broadcaster_spec.rb # NEW: queue bounds, drop-oldest, sentinel
├── web_events_route_spec.rb # NEW: SSE route rows (extends the 13-04 matrix posture)
├── web_runs_read_model_spec.rb # NEW: D-12 listing + status derivation units
├── installer_lock_notice_spec.rb # NEW: D-05 line on both flock sites
└── web_integration_spec.rb  # extend: SSE row(s) from the ONE port-0 boot
```

### Pattern 1: SSE route over WEBrick (all mechanics verified this session)

**What:** `GET /api/events` behind the existing Host/Origin/token gate; `res.chunked = true`, `res.body = proc { |out| ... }`, `res.keep_alive = false`.

**Verified mechanics (webrick 1.9.2, file:line):**
- `chunked=` + proc body is the documented streaming pattern (httpresponse.rb:63-68 doc comment); `send_body_proc` calls the proc with a `ChunkedWrapper` when chunked (httpresponse.rb:538-539) and writes the `0\r\n\r\n` terminator when the proc returns (line 540).
- `ChunkedWrapper#write` → `socket.write` per call (httpresponse.rb:561-572) — **live probe: per-event arrival within 0.01s of each write** across a 6-event stream. No buffering workaround needed.
- `res.keep_alive = false` → `Connection: close` on the wire (setup_header httpresponse.rb:313-315) and the connection thread exits right after the stream (httpserver.rb:117-118) — **live probe: clean close at terminator.** Without it the thread parks up to RequestTimeout=30s waiting for a next request that never comes (config.rb:50).
- The 30s `RequestTimeout` applies only *between* requests / reading request data (httpserver.rb:75-81; httprequest.rb:596) — **never during a streaming response**; arbitrary heartbeat gaps cannot be killed by WEBrick timers.
- Dead clients: `send_response` rescues `EPIPE`/`ECONNRESET`/`ENOTCONN` and ends the response (httpresponse.rb:243-249); the truncated stream is a network error to the browser → EventSource reconnects with `Last-Event-ID` (spec §9.2.4 — set automatically on reestablishment). **Live probe: `req['last-event-id']` returns the exact composite id string** (values verbatim, header name downcased — httprequest.rb:318-322).
- Shutdown: the accept loop's ensure **joins all connection threads** (server.rb:210) — the proc MUST terminate on a sentinel or `server.shutdown` hangs (WEB-03 violation). `Command::Web` traps TERM/INT → `server.shutdown` (web.rb:83).
- Thread-per-connection with `MaxClients` tokens (default 100; server.rb:181, config.rb:33) — one long-lived SSE connection per open tab is well within budget.

```ruby
# Router#dispatch gains (sketch — planner pins naming):
when '/api/events'
  events_stream(req, res, supplied)

def events_stream(req, res, supplied)
  return reject(res, 401, 'missing or invalid token') unless Middleware.valid_token?(token: supplied, expected_token: @token)
  return reject(res, 404, 'not found') unless req.request_method == 'GET'

  # 200 ALWAYS (never 204/503 — any non-200 kills EventSource reconnect permanently,
  # WHATWG §9.2.3). Auth failures are the deliberate exception: permanent-by-design.
  res.status = 200
  res.content_type = 'text/event-stream'
  res['Cache-Control'] = 'no-store'   # also applied globally (router.rb:179)
  res.keep_alive = false              # stream is one-shot; close after terminator (verified)
  last_event_id = req['last-event-id'] # browser sends on auto-reconnect (spec §9.2.4)
  resume = Events.parse_resume_id(last_event_id) # regex + containment; nil → fresh replay
  res.body = proc do |out|
    client = @events.register(out)     # bounded queue owned by the broadcaster
    @events.stream(client, resume: resume) # ends on shutdown sentinel or server choice
  end
end
```

**EventSource auth:** EventSource cannot set headers — the token rides `?token=` (already accepted: router.rb:60 `req[TOKEN_HEADER] || req.query[TOKEN_PARAM]`). Same trust posture as the locked 302 bootstrap (`/?token=`, 13-CONTEXT); the access log that would leak it is disabled outright (server.rb:33, T-13-03).

### Pattern 2: The tailer — byte-offset ids, replay, discovery, retention interplay

**What:** one poll thread over `Config#runs_dir` (config.rb:119-121) with the `Core::Watcher` mtime+size precedent (watcher.rb:130-135).

- **Id format: `"<filename>:<byte-offset>"`.** Filenames are `%Y%m%dT%H%M%S%3NZ-<pid>-<verb>.jsonl` [VERIFIED: run_log.rb:31,117; spec regex run_log_spec.rb:47] — no colons; split on the LAST colon. Offsets are byte offsets (open `'rb'`); the id records the offset AFTER a line's newline, so resuming seeks exactly to the next line.
- **Why byte-safe:** RunLog scrubs every line to valid UTF-8 (run_log.rb:248) and `JSON.generate` escapes newlines inside strings, so `\n` occurs exactly at line boundaries. Splitting is unambiguous; `Last-Event-ID` round-trips the composite id — **verified live**.
- **Fresh connect (no Last-Event-ID):** pick current-or-newest run (D-13): newest file whose header pid is alive AND has no `run_end`, else newest file overall; replay all lines from byte 0, then follow. A tailer never observes a header-less file (header publishes atomically via tempfile+rename before the append handle exists — run_log.rb:126-148).
- **Reconnect:** validate the id (filename regex + `File.expand_path` containment under runs_dir — client input is attacker input; T-13-04 assets precedent), open, seek, stream.
- **Discovery:** glob + sort each poll; a new file (or `run_start` header in it) → broadcast a `switch` notice (D-04) and continue from the new file's byte 0.
- **Retention interplay (D-07):** `RunLog.prune` runs at every run open (run_log.rb:159-160), deleting oldest-first, excluding the current run and other live-pid runs (run_log.rb:314, 322-323, 407-409). Consequences: (a) hold an open fd for the actively-served run — POSIX keeps an unlinked file readable through its fd; (b) a *completed, viewed* run CAN be pruned by a new run's retention pass — a fresh connect whose Last-Event-ID names a vanished file gets an honest `notice` event and the fresh-replay fallback (D-04's "previous run stays reachable" degrades gracefully, exactly the D-02 reload affordance).
- **Partial-line safety:** like RunLog's own buffering inverted (run_log.rb:216-235) — only complete `\n`-terminated chunks advance the offset; a trailing partial write stays buffered until its newline lands.

```ruby
# Tailer poll (sketch)
def poll_once
  path = newest_run_file
  switch_to(path) if path != @current_path          # emits switch notice (D-04)
  io = @io ||= File.open(@current_path, 'rb')       # fd survives prune-unlink (POSIX)
  io.seek(@offset)
  if (chunk = io.read)
    @line_buf << chunk
    while (nl = @line_buf.index("\n"))
      line = @line_buf.slice!(0..nl)
      @offset += line.bytesize
      broadcaster.publish(@current_path, line)       # id built here: "file:offset"
    end
  end
rescue Errno::ENOENT
  broadcaster.publish_notice('run log pruned while viewing; switching to newest')
  @io = nil; @current_path = nil                     # next poll re-discovers
end
```

### Pattern 3: Broadcaster — bounded queues, heartbeat-by-pop-timeout, shutdown sentinel

**What:** per-client bounded queue; the WEBrick connection thread IS the per-client writer.

```ruby
# Per-client loop (runs inside res.body proc on the connection thread)
def stream(client, resume:)
  client.deliver(hello_event)          # identity + derived status (CP10) for the D-06 card
  client.deliver(replay_entries(resume)) if resume || fresh_replay?
  loop do
    case client.queue.pop(timeout: HEARTBEAT_SECONDS)   # SizedQueue#pop; ~15s (CP11)
    when ShutdownSentinel then break                     # server stopping: end proc
    when nil              then out.write(": ping\n\n")   # heartbeat comment; parser ignores
    when Entry            then out.write(frame(entry))   # id:/event:/data: (+ retry: on hello)
    end
  end
rescue Errno::EPIPE, Errno::ECONNRESET, IOError
  nil                                    # dead client: WEBrick already ends the response
ensure
  broadcaster.unregister(client)
end
```

- **Backpressure:** a slow client stops popping → its queue fills to cap → the tailer drops OLDEST for that client and enqueues a "N lines dropped" notice (CP11). A wedged TCP write blocks only that connection thread (thread-per-connection absorbs it); loopback + a real browser make a permanently wedged socket a non-scenario [ASSUMED — browser socket reads are not timer-throttled; residual graceful-shutdown risk documented below].
- **Shutdown:** `Command::Web` (or the Server adapter) calls `broadcaster.shutdown!` BEFORE `server.shutdown` — every proc sees the sentinel and returns, so server.rb:210's join completes and TERM/INT exits 0 (WEB-03). The bounded pop caps worst-case sentinel latency at one heartbeat period.
- **Hello carries `retry:`** (in-stream field — the ONLY thing that sets EventSource's reconnection time per the spec parse rules) so reconnect pacing is server-pinned, not browser-default.

### Pattern 4: State derivation (CP10) — flock probe + pid attribution + CP14 honesty

**What:** "build running" derives from `.spm-cache-build.lock` (config.rb:110-112) + run-log headers, never server memory.

```ruby
def lock_held?
  File.open(Core::Config.instance.build_lock_path, File::RDONLY) do |f|
    return false if f.flock(File::LOCK_EX | File::LOCK_NB) # acquired: release immediately
    true                                   # EWOULDBLOCK path: someone holds it
  end
rescue Errno::ENOENT
  false                                    # never taken yet: idle
end
```

- **Probe discipline:** acquire-and-release atomically; the server NEVER holds the build lock (milestone stance; CP4's flip side).
- **Attribution:** newest run file whose header `pid` is alive (`Process.kill(0, pid)` — reuse RunLog's exact probe, run_log.rb:395-402) AND whose file lacks `run_end` → "running: <identity>". Held lock + no attributable live run → "unknown holder" — this is LOGS-05's external-run detection (e.g. a `--no-run-log` invocation or a pre-Phase-12 process genuinely holds the lock; flock releases on process death, so a held lock always means a live holder). Free lock → idle.
- **CP14 honesty:** header pid dead + no exit line = the run died without finishing (kill -9 or crash). Display "interrupted — exit unknown"; never "running" (pid liveness is authoritative for liveness; the missing `run_end` only means the STATUS is unknown). The retention code already treats unreadable pid as unprotected (run_log.rb:407-409) — same reading.
- **Race note:** the lock probe and header reads are two snapshots; a run can start between them. At dashboard granularity (heartbeat + 5s poll) this is acceptable display lag, not a correctness bug — derive-and-display, never assert-from-memory.

### Pattern 5: D-05 "Waiting for build lock…" at the Installer's output seam

**What:** the blocked run announces itself, so the line lands in ITS run log (the stream then attributes it inline — D-05) and terminal users see the same line.

The two blocking sites [VERIFIED: installer/build.rb:76-82 `acquire_build_lock`; installer/use.rb:70-81 `with_build_lock`] both call `flock(File::LOCK_EX)` silently today. Insert the same three steps at both:

```ruby
# probe → announce → block (D-05; wording feeds terminal + browser — UI-SPEC pins copy)
unless lock.flock(File::LOCK_EX | File::LOCK_NB)
  Core::UI.info 'Waiting for build lock…'   # tee captures it → this run's JSONL → SSE
  lock.flock(File::LOCK_EX)                 # then block, exactly as today
end
```

`Core::UI.info` → `puts` → tee → body line in the blocked run's file (log.rb:14-16; tee installed by Main.run / CycleWrapper) — the in-stream attribution is literally a body line, no new event type needed. Both sites are inside the run-log tee in every logged verb, so terminal and browser surface identical wording (D-05's reversibility note honored: one string, two surfaces).

### Pattern 6: Frontend log panel — second module, same discipline

- **`log.js`** as a second ES module (14-CONTEXT explicitly permits exceeding app.js's 300–400 LOC budget): same IIFE/self-bootstrap shape as app.js, zero innerHTML, everything through `el()`/`textContent` (app.js:23-29, T-13-13). index.html gains the log section + `<script type="module" src="assets/log.js">` — served as a plain basename through Assets (assets.rb:61-69), no gemspec change (lib glob).
- **EventSource:** `new EventSource('/api/events?token=' + token)` with the sessionStorage token (app.js:13-19). `onerror` + `readyState === EventSource.CLOSED` = permanent failure (auth/origin) → reuse the token-invalid full-page surface (app.js:61-68); CONNECTING = transient → show the connection pill. Failed polls never stop the state-table loop (app.js:309-314 precedent) — the two surfaces are independent.
- **Rendering:** `JSON.parse(e.data)` per entry; key on the parsed `event` field (T-12-01 — body lines carry only ts/stream/text and NEVER an event key, run_log.rb:19-22). Body lines render as text (ANSI codes are data — render verbatim in `mono`, per Phase 12's transform-free stance); structured events drive anchors (D-07: `package_start` + `phase` name ∈ {detect, integrate, build, fidelity}), identity card (D-06), banner (D-03), switch notice (D-04).
- **D-01/D-02 mechanics:** scroll listener toggles follow; ~500-line DOM ring with an "… N earlier lines" head notice; the jump-to-live pill re-scrolls and resumes. Filter state (D-09/D-10) is pure CSS-class toggling over the ring.

### Anti-Patterns to Avoid

- **Answering the stream route with 204/503** for any condition — any non-200 permanently kills EventSource reconnect (spec §9.2.3). Always 200 + heartbeat/retry.
- **Relying on an HTTP `Retry:` header** — it is not part of the SSE processing model; use the in-stream `retry:` field.
- **Looping forever in the body proc** — server.rb:210 joins all connection threads on shutdown; without the sentinel `spm-cache web` TERM/INT hangs (WEB-03 regression).
- **Holding a flock in the server** — the server probes (acquire-and-release) and never holds (milestone stance; CP4).
- **Opening a run file by Last-Event-ID without regex + containment validation** — the header is client-controlled input (path traversal).
- **Text-mode reads for offset tracking** — open `'rb'`; transcodings corrupt byte offsets.
- **Adding any hook into `Core::Watcher`** — CP5/CP6 hygiene IS the absence of coupling; cycles are already files.
- **Keeping run state in server memory across requests** — CP10; derive per connect/per display from disk.
- **innerHTML for log lines** — T-13-13 discipline: `textContent` only; run text is subprocess output (attacker-adjacent data).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| HTTP streaming/chunked framing | Manual `Transfer-Encoding` byte surgery | `res.chunked = true` + proc body (WEBrick) | WEBrick owns framing, terminator, EPIPE handling (httpresponse.rb:472-578, 243-249) |
| Token auth on the stream | Custom query auth scheme | `Middleware.valid_token?` via `?token=` (router.rb:60) | Same constant-time path as every route; EventSource cannot send headers |
| Liveness probe | `ps` shelling, /proc parsing | `Process.kill(0, pid)` (run_log.rb:395-402) | Proven in-repo; ESRCH/EPERM semantics already correct |
| Path containment for client ids | String prefix checks ad hoc | Assets basename/containment pattern (assets.rb:37-45, 61-69) | Battle-tested in 13-04's traversal matrix |
| Replay bookkeeping | Event numbering/dedup serverside | Byte offsets (file position IS the ordering) | Append-only JSONL makes offsets monotonic by construction; `file sync = true` (run_log.rb:151) guarantees durability before visibility |
| Recently-runs listing | A DB or persisted index | Directory glob + header/exit parse (D-12 forbids storage) | 50 files × one `gets` each is microseconds; retention bounds the dir |

**Key insight:** the transport is 90% WEBrick + POSIX semantics this research has verified at the source level — the phase's real work is the tailer's correctness (offsets, discovery, retention interplay) and the state derivation's honesty (CP10/CP14), not HTTP plumbing.

## Runtime State Inventory

> Not a rename/refactor/migration phase — greenfield streaming layer over existing files. Category answers for completeness:
> **Stored data:** none new (reads `.spm-cache/runs/*.jsonl` + probes `.spm-cache-build.lock`; writes nothing outside the repo's own code). **Live service config:** none (no external services involved). **OS-registered state:** none. **Secrets/env vars:** none read; the launch token transits the SSE query string — already the locked 13 posture (302 bootstrap), and AccessLog is disabled (server.rb:33). **Build artifacts:** none affected.

## Common Pitfalls

### Pitfall 1: The 503/204 "not ready" answer kills reconnects permanently
**What goes wrong:** answering a stream request with any non-200 (204 per the original CP11 text; 503 per the carried-forward clause) fires `error`, sets readyState CLOSED, and the tab never reconnects — the dashboard looks dead after a server restart or a slow first tailer tick.
**Why it happens:** the carried-forward clause ("503 + `Retry:`") reads like standard HTTP practice, but the SSE processing model fails the connection on any non-200 status and ignores HTTP `Retry:` headers entirely.
**How to avoid:** the route always answers 200 `text/event-stream` once authed; "not ready" is expressed inside the stream (heartbeats until the tailer's first tick; `retry:` field pacing). 401/403 remain deliberate permanent failures mapped to the token-invalid surface.
**Warning signs:** tabs that stop recovering after `spm-cache web` restarts; error events with readyState stuck at CLOSED.

### Pitfall 2: `server.shutdown` hangs on a forever-looping stream proc
**What goes wrong:** SIGTERM/SIGINT never completes (WEB-03 regression); in specs, `WebServerBoot`'s `thread.join(10)` expires and the example dirty-fails.
**Why it happens:** WEBrick's accept-loop ensure joins every connection thread (server.rb:210); accepted sockets are not closed by listener cleanup, so a proc blocked on queue-pop never ends.
**How to avoid:** broadcaster sentinel pushed to every client queue before `server.shutdown`; every proc ends on the sentinel; heartbeat = `pop(timeout:)` so worst-case sentinel latency is one heartbeat period. Prove it: the integration spec asserts `server.shutdown` + join completes within a bounded time with an OPEN stream.
**Warning signs:** `spm-cache web` ignoring Ctrl-C with a tab open; specs hanging at exit with streams open.

### Pitfall 3: Retention prunes the file being viewed
**What goes wrong:** a user replays a completed run; a new run opens, retention over budget deletes that file; the open tailer fd keeps reading (POSIX) but a NEW connect (or a tab reload) 404s mid-session — "run log vanished mid-view."
**Why it happens:** prune protects only the current run and other live-pid runs (run_log.rb:314, 407-409); a finished run being viewed is a legitimate candidate.
**How to avoid:** hold the fd for the actively-served run; treat ENOENT on (re)open as a first-class `notice` event + fallback to fresh-replay of the newest run (D-04's reachability degrades gracefully; D-02's "reload to replay" is the honest copy).
**Warning signs:** "run no longer available" notices right after a new run starts; tab reloads failing while an old run is displayed.

### Pitfall 4: Last-Event-ID treated as trusted
**What goes wrong:** a crafted `Last-Event-ID: ../../spm-cache.yml:0` (or any absolute path) is seeked and streamed — project files leak through the token-gated-but-readable stream.
**Why it happens:** the header is framed as "browser-internal," but curl can send it; the route is token-gated, not attacker-free (tokens live in the browser's sessionStorage and URLs).
**How to avoid:** parse with the filename regex (`\A\d{8}T\d{6}\d{3}Z-\d+-[a-z]+(-\d+)?\.jsonl:\d+\z`), then `File.expand_path` + runs-dir containment (assets.rb precedent); anything else → fresh replay, never an error surface worth probing.
**Warning signs:** any `File.open` whose path derives from a request value without both checks.

### Pitfall 5: Byte/character offset drift
**What goes wrong:** replay lands mid-line or skips/duplicates lines after reconnect (silent LOGS-03 violation).
**Why it happens:** reading in text mode applies encoding transcoding, so `IO#pos` stops being a byte count; or ids record offsets BEFORE consuming the newline, double-delivering the boundary line.
**How to avoid:** open `'rb'`; ids record the offset AFTER the consumed newline; unit tests assert resume-at-id yields the exact next line for multi-byte content (package names with non-ASCII are real).
**Warning signs:** duplicated or missing boundary lines after a kill/restart cycle — exactly what D-14's probe asserts against.

### Pitfall 6: Poll-grained "live" claims the UI can't keep (CP6 honesty)
**What goes wrong:** the tailer polls (sub-second), but the watcher's cycle cadence is 2s-debounce poll-grained; a UI implying per-keystroke liveness fabricates signal.
**Why it happens:** "live stream" branding invites over-promising (CP6).
**How to avoid:** the log panel IS genuinely live (file tail, not watcher events); every other surface keeps its honest stamps ("Updated Ns ago", app.js:134). The identity card's status dot flips on `run_end`, not on guesses.
**Warning signs:** status dot flapping between runs; stamps derived from `Date.now()` (forbidden, T-13-16).

### Pitfall 7: The tailer becoming a second source of truth
**What goes wrong:** caching "current run" identity/状态 in the broadcaster across reconnects diverges from disk after retention/restarts — CP10 violation by accretion.
**Why it happens:** the tailer naturally memoizes its active file; the leak is serving that memoized identity to NEW connections.
**How to avoid:** the tailer memoizes only its own read position (fd + offset); every connect re-derives identity/status from the runs dir + flock (Pattern 4). Restart-of-server mid-run is then transparent by construction.
**Warning signs:** identity card wrong after server restart while a run lives; two tabs disagreeing about the current run.

## Code Examples

### Verified seams (quote-level, for the planner)

- Event vocabulary — verbatim emitters (D-07 anchors; renderer keys):
  - `emit_run_log_event(run_log, "package_start", name: name)` — build_pipeline.rb:68
  - `emit_run_log_event(run_log, "package_end", name: name, status: success ? "ok" : "failed")` — build_pipeline.rb:110
  - `emit_run_log_event(run_log, "phase", name: "fidelity")` — build_pipeline.rb:92
  - `Core::RunLog.current&.event('phase', name: 'build')` — installer/build.rb:41; `name: 'detect'` — installer/use.rb:24; `name: 'integrate'` — installer/use.rb:29
  - `RunLog.current&.event('sh', cmd: cmd, status: status.exitstatus)` — core/sh.rb:74
  - `event('run_end', 'status' => status.to_i, 'ended_at' => Time.now.utc.strftime(TIMESTAMP_FORMAT))` — run_log.rb:283-285
  - Header keys verbatim — run_log.rb:128-139: `'event' => 'run_start'`, `'ts'`, `'command'`, `'argv'`, `'redacted'`, `'pid'`, `'started_at'`, `'spm_cache_version'`, `'trigger'`, `'cycle'`
  - Body lines verbatim — run_log.rb:247-248: `'ts'`, `'stream'` (`'out'`/`'err'`), `'text'` — and the T-12-01 contract comment: body lines carry only ts/stream/text and never an `event` key (run_log.rb:19-22)
- Filename shape — run_log.rb:31: `FILE_TIMESTAMP_FORMAT = '%Y%m%dT%H%M%S%3NZ'`; base = `"#{...strftime}-#{Process.pid}-#{command}"` (run_log.rb:117)
- Liveness — run_log.rb:395-402: `Process.kill(0, pid)`; ESRCH → dead; any other error → alive
- Flock sites — installer/build.rb:79-81 (`File.open(..., File::CREAT | File::RDWR)` then `lock.flock(File::LOCK_EX)`); installer/use.rb:73-75 (same shape)
- Retention — run_log.rb:159-160 (`log.prune(keep: Config.instance.runs_keep, max_bytes: Config.instance.runs_max_mb * 1024 * 1024)` at every open)
- Watch cycles skip the Main-level log — run_log.rb:103: `main_log_skipped: %w[web watch].include?(verb)`
- Token via query — router.rb:60: `supplied = req[TOKEN_HEADER] || req.query[TOKEN_PARAM]`
- Global security headers — router.rb:177-180 (`X-Frame-Options`, `Cache-Control: no-store`)
- Boot harness — spec/support/web_server_boot.rb:17-32 (`with_server`: port 0, bounded `wait_accepting`, ensure-shutdown + Config restore)

### SSE frame shapes (recommended; planner pins names)

```
retry: 3000                       ← in-stream reconnection pacing (hello, first)
id: 20260901T093012123Z-4821-build.jsonl:1024
event: entry
data: {"ts":"...","stream":"out","text":"  Building Alamofire for iphonesimulator...\n"}

event: hello                      ← fresh connect: identity + derived status (CP10)
data: {"run":"20260901T093012123Z-4821-build.jsonl","command":"build","trigger":"terminal",
       "status":"running","lock":"held"}

event: switch                     ← D-04 auto-switch
data: {"run":"<new>","previous":"<old>"}

event: notice                     ← CP11 drop-oldest / pruned-run fallback
data: {"message":"97 lines dropped"}

: ping                            ← heartbeat comment (parser-ignored)
```

`data:` carries the JSONL line verbatim (already JSON, no raw newlines inside — `JSON.generate` escaped them at write time), so SSE framing is passthrough-safe and the client's `JSON.parse(e.data)` receives the exact frozen vocabulary.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| CP11 clause: "failed connects answer 503 + `Retry:` (NEVER 204)" | **Any non-200 fails EventSource permanently** (204 AND 503 alike); in-stream `retry:` field is the only reconnect-time control; always answer 200 once authed | WHATWG HTML §9.2.3, re-verified verbatim 2026-09-01 | Plan must not emit 503 from the stream route; the carried-forward intent (never kill reconnects) is honored and strengthened |
| "SSE buffering needs explicit flush work on WEBrick" | `chunked = true` + proc body flushes per write on Ruby 3.2.3 / webrick 1.9.2 — no flush machinery needed | Live probe 2026-09-01 (per-event arrival ≤0.01s) | Deletes a whole class of imagined plumbing; intermediary buffering remains a theoretical note (localhost has none) |
| "SSE idle gaps risk WEBrick timeouts" | RequestTimeout applies only between requests / on request reads — never during a streaming response | webrick source (httpserver.rb:75-81, httprequest.rb:596) | Heartbeat interval is free choice (~15s per CP11); no server timer can kill the stream |
| Watcher-guard worry: "web runs re-trigger watch" | Today: web spawns nothing (Phase 15 concern); the guard is the post-regenerate re-snapshot (watcher.rb:53-55, 62-66) and per-cycle files carry `trigger: 'watch'` | Verified in source + MILESTONES.md:32 history | CP6 reduces to: keep Web::Events read-only (it is) + a Phase 15 note that spawned builds legitimately coexist with watch cycles (two runs, correct attribution) |

**Deprecated/outdated:** none new — webrick's `upgrade!` path (httpresponse.rb:229-233) is explicitly NOT used (it disables chunked/keep-alive; SSE needs chunked, not HTTP upgrade).

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Browsers add exponential backoff on repeated reconnect failures (spec sanctions "optionally, wait some more") — reconnect latency after an outage may vary by browser | Pattern 3 / Pitfall 1 | UX-only; the in-stream `retry:` field pins the base delay |
| A2 | A permanently-failed EventSource (401/403 on the stream) surfacing as the token-invalid page is acceptable UX | Pattern 6 | Copy-level; UI-SPEC can pick different wording |
| A3 | One global tailer thread + per-client queue caps (order 10³ entries) absorb xcodebuild burst rates without visible drops | Pattern 3 | Numbers are discretion; drop-oldest + notice makes underestimation visible, not fatal |
| A4 | One `/api/events` endpoint serving current-or-newest run (no per-run query param) satisfies D-12 reachability ("previous run stays reachable" via dropdown → the `/api/runs` listing + a replay affordance) | Open Questions 1 | If direct in-place replay of older runs is wanted without reload, add a token-gated `?run=` param — designed as Open Question, not built blind |
| A5 | A permanently wedged TCP write on loopback (zero-window, peer alive but not reading) does not occur in practice; graceful-shutdown residual risk accepted | Pattern 3 | Worst case: graceful TERM with a wedged tab delays exit until TCP gives up; kill -9 path (D-14) unaffected |
| A6 | The D-14 agent-browser probe runs in the user's default browser via the existing auto-open path; exact browser = whatever `open` selects | Validation Architecture | None — the probe is recorded manually regardless |

## Open Questions (RESOLVED)

1. **Older-run replay affordance: reload vs in-place `?run=` param.**
   - What we know: D-04/D-12 require previous runs stay reachable; the dropdown lists them. A fresh `/api/events` connect always serves current-or-newest (D-13).
   - What's unclear: whether selecting an older run should navigate/reload (cheap, stateless) or stream it in-place via a `?run=` query param (small server addition: validate + serve that file; same regex/containment machinery as Last-Event-ID).
   - Recommendation: implement `?run=` — it reuses the id-validation machinery and makes D-12's "previous stays reachable" literal without page reloads; flag for the planner to confirm against UI-SPEC.
   - **Resolved:** `?run=` adopted — pinned by 14-UI-SPEC.md's 'Recent-runs dropdown (D-12)' interaction row (in-place load from byte 0 via `?run=`) and implemented by 14-03 Task 2 (pinned replay over the shared validation machinery).
2. **D-05 line wording.** "Waiting for build lock…" is BLD-02's quoted phrase and this research's working string; final copy is UI-SPEC territory (user-visible in two surfaces per D-05's reversibility note).
   - **Resolved:** the wording stands verbatim — pinned by 14-UI-SPEC.md's Copywriting Contract row 'Lock-wait line (D-05)' and implemented at both flock sites by 14-02 (Core::UI.info announce, tee'd into the blocked run's JSONL).
3. **Heartbeat interval + queue cap as constants vs Config keys.** Recommendation: constants (CP11's ~15s; cap order 10³) — Config is the user-facing state surface and no user knob is warranted; revisit only if a real session shows drops.
   - **Resolved:** constants — 14-01 pins HEARTBEAT_SECONDS = 15 and QUEUE_CAP = 1000 as code constants in `web/events.rb` (injectable per constructor keyword for specs); no Config keys added.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Ruby | everything | ✓ | 3.2.3 local (rbenv); CI matrix 3.1/3.2/3.3 macos-15 [VERIFIED: .github/workflows/ci.yml, .planning/codebase/INTEGRATIONS.md] | — |
| webrick | server/SSE | ✓ | 1.9.2 (Gemfile.lock pin; gemspec `>= 1.8, < 2`) | — |
| rspec | validation | ✓ | ~> 3.12 (Gemfile.lock) | — |
| Browser with EventSource | D-14 recorded probe | ✓ | user's default browser (auto-open path) | any evergreen browser |
| xcodebuild | real runs in D-14 probe | ✓ | machine Xcode (Phase 12 probe precedent) | a failing `use` in an empty dir exercises failure paths without xcodebuild |

**Missing dependencies with no fallback:** none.
**Missing dependencies with fallback:** none.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | RSpec ~> 3.12 (dev dep; hermetic suite, 441 examples at v0.4.0, grown by Phases 12–13) |
| Config file | none beyond `.rspec` defaults (TESTING.md) |
| Quick run command | `bundle exec rspec spec/events_tailer_spec.rb spec/events_broadcaster_spec.rb` |
| Full suite command | `bundle exec rspec` (Makefile `make test`) |

### Phase Requirements → Test Map

| Req | Behavior | Test Type | Automated Command | File Exists? |
|-----|----------|-----------|-------------------|-------------|
| LOGS-03 | Tailer: byte-offset ids monotonic; resume-at-id yields the exact next line (incl. multi-byte UTF-8 content); partial trailing line buffered until newline | unit (tmpdir) | `bundle exec rspec spec/events_tailer_spec.rb` | ❌ Wave 0 |
| LOGS-02/D-04 | Discovery: new run file → switch notice + follow; retention prune of the served file → fd survives; fresh connect to pruned file → notice + newest fallback | unit (tmpdir, real unlink) | `bundle exec rspec spec/events_tailer_spec.rb` | ❌ Wave 0 |
| CP11 | Broadcaster: queue cap → drop-oldest + "N lines dropped" notice; shutdown sentinel ends every client loop; heartbeat on pop timeout (inject short interval) | unit | `bundle exec rspec spec/events_broadcaster_spec.rb` | ❌ Wave 0 |
| LOGS-03/CP13 | Route: 200 + `text/event-stream` + `no-store`; token gate (401 rows), Host/Origin rows extend the 13-04 matrix; `Last-Event-ID` regex+containment (traversal fixtures 404→fresh-replay, never opened) | unit + integration row | `bundle exec rspec spec/web_events_route_spec.rb` | ❌ Wave 0 |
| CP10/LOGS-05 | State derivation: flock held by an in-process thread → probe reports held; header-pid alive + no run_end → running; dead pid + no exit line → "interrupted — exit unknown"; free lock → idle; held + no attributable run → unknown holder | unit (thread-held flock, tmpdir) | `bundle exec rspec spec/web_runs_read_model_spec.rb` | ❌ Wave 0 |
| D-12 | `/api/runs`: newest-first listing with identity + status per entry, zero storage | unit | `bundle exec rspec spec/web_runs_read_model_spec.rb` | ❌ Wave 0 |
| D-05 | Both flock sites announce "Waiting for build lock…" (UI.info captured via the doctor_spec `$stdout`-swap convention) exactly when a thread holds the lock, then block; free-lock path byte-identical to today | unit | `bundle exec rspec spec/installer_lock_notice_spec.rb` | ❌ Wave 0 |
| LOGS-03 + WEB-03 | THE one port-0 integration boot (extends `WebServerBoot`): raw TCPSocket GET `/api/events` → headers + hello + replayed fixture lines; reconnect with `Last-Event-ID` resumes exactly; **`server.shutdown` with an open stream joins within bound** (sentinel proof) | integration (port 0, loopback only) | `bundle exec rspec spec/web_integration_spec.rb` | extend Wave 0 |
| D-14 | Recorded manual/agent-browser probe (not automated): terminal run → live render + identity card + anchors; second tab mid-run replays from 0; kill -9 + restart server → reconnect without lost/duplicated lines; failing run → sticky banner + ✓/✗ dot | manual (recorded, repeatable) | — | 14-VALIDATION checklist |

### Sampling Rate

- **Per task commit:** the new spec files for the task's module (fast, hermetic, no sockets except the single integration example)
- **Per wave merge:** `bundle exec rspec` (full suite; hermetic posture intact — CP7)
- **Phase gate:** full suite green + the recorded D-14 agent-browser probe before `/gsd-verify-work`

### Wave 0 Gaps

- [ ] `spec/events_tailer_spec.rb` — offsets, replay, discovery, retention interplay
- [ ] `spec/events_broadcaster_spec.rb` — bounds, drops, sentinel, heartbeat
- [ ] `spec/web_events_route_spec.rb` — SSE route rows + id validation matrix
- [ ] `spec/web_runs_read_model_spec.rb` — CP10 derivation + D-12 listing
- [ ] `spec/installer_lock_notice_spec.rb` — D-05 both sites
- [ ] extend `spec/web_integration_spec.rb` + `spec/support/web_server_boot.rb` — the SSE integration row (shutdown-within-bound assertion)

## Security Domain

`security_enforcement: true`, ASVS Level 1 (config.json). Phase surface analysis:

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | Localhost dev tool; per-launch token is the access-control surface (V4), not user auth |
| V3 Session Management | no | No sessions; token is per-launch, rotated every launch (13-CONTEXT) |
| V4 Access Control | yes | SSE + runs routes sit inside the existing Host/Origin + token gate (router.rb:62-67 — structural, ALL routes); no un-gated route may be added |
| V5 Input Validation | yes | `Last-Event-ID` and any `?run=` value: regex + containment before `File.open`; token via `?token=` uses the existing constant-time `valid_token?` (middleware.rb:46-50) |
| V6 Cryptography | no | N/A (SecureRandom token already shipped Phase 13) |
| V7 Logging (integrity) | yes | Token never logged (AccessLog disabled, server.rb:33); run content streams verbatim as data — renderer keys on `event` only (T-12-01) |

### Known Threat Patterns for SSE + file-tail

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Path traversal via `Last-Event-ID`/`?run=` | Information Disclosure | Filename regex + `expand_path` containment (T-13-04 precedent); non-matching → fresh replay |
| Connection flood / slow-loris on the stream | DoS | WEBrick `MaxClients` token semaphore (100); loopback-only bind (server.rb:13); single-user tool — bounded by design |
| Log-content spoofing via crafted run text | Tampering | Payload is data; client renders text as text (`textContent`), trusts only parsed `event` lines (T-12-01, run_log.rb:19-22) |
| Drive-by stream read | Information Disclosure | Same Host/Origin + token gate as every route; EventSource's cross-origin use would need CORS anyway (never granted) |
| Token leakage via stream URL | Information Disclosure | Locked 13 posture: query-param token == bootstrap-redirect posture; AccessLog disabled; sessionStorage-held token, URL cleaned (app.js:17) |

## Sources

### Primary (HIGH confidence — all read/probed this session, 2026-09-01)
- WEBrick 1.9.2 gem source (`~/.xcframework-cli/gems/webrick-1.9.2/lib/webrick/`): httpresponse.rb:63-68 (streaming doc), 117-135 (init/buffer), 238-250 (EPIPE rescue), 255-323 (setup_header: chunked/keep-alive/204-304), 472-578 (send_body_io/proc + ChunkedWrapper); httpserver.rb:69-120 (request loop, RequestTimeout between requests, keep-alive breaks), 125-141 (service); server.rb:154-216 (accept loop, tokens, **join-all-threads at 210**), 287-328 (start_thread); config.rb:31-60 (MaxClients 100, RequestTimeout 30, OutputBufferSize); httprequest.rb:318-322 (`req[]` downcase+join), 596-604 (read timeout)
- WHATWG HTML Standard §9.2 Server-sent events (fetched verbatim 2026-09-01): non-200/non-event-stream → fail permanently; reestablish on network error and on clean end-of-body; Last-Event-ID header set on reestablishment; `retry:` field semantics; heartbeat-comment parsing
- Live probes (this machine, Ruby 3.2.3, webrick 1.9.2): (1) 6-tick chunked stream — every event arrived ≤0.01s after its write; (2) composite `Last-Event-ID` round-trips exactly through the handler; (3) `keep_alive=false` → `Connection: close` + clean close at terminator
- Repo code: `lib/spm_cache/core/run_log.rb` (1-566 full read: header keys 128-139, sync 151, record/buffer 216-250, events 261-267, finish 280-291, prune 313-338, `pid_alive?` 395-409, TeeIO/StreamSink/CycleWrapper 428-563), `core/sh.rb:36-64` (reader threads/sinks), `core/watcher.rb` (27-146: poll signature 130-135, TERM trap 49, re-snapshot guard 53-66, factory seam 90-93), `command/watch.rb:29-58`, `command/web.rb:40-94` (boot flock, traps, marker), `web/server.rb` (lazy require, bind, AccessLog, StartCallback, catch-all servlet), `web/router.rb` (55-90 gate+dispatch, 117-171 api pattern, 177-209 helpers), `web/middleware.rb` (19-66), `web/assets.rb` (37-69 containment), `web/read_models/state.rb` (stateless read posture), `installer/build.rb:18-92` (lock sites), `installer/use.rb:23-81` (lock sites + phase markers), `installer.rb:705-707` (submodule requires), `spm/build_pipeline.rb:50-136` (package brackets + fidelity marker + guarded emit), `core/config.rb:110-131` (build_lock_path/runs_dir/web_dir), `spm_cache.gemspec:35-43`, `spec/support/web_server_boot.rb` (port-0 harness), `spec/run_log_spec.rb` (fixture + guard conventions, filename regex at :47, liveness fixtures at :359-372), `spec/web_integration_spec.rb` + `web_frontend_spec.rb` (13-04/13-05 matrix posture)
- Planning docs: 14-CONTEXT.md (D-01..D-14), 12-CONTEXT.md (D-04/D-05/D-07/D-09), 13-CONTEXT.md (server decisions), REQUIREMENTS.md (LOGS-02..05, BLD-02 wording), research/SUMMARY.md + PITFALLS.md (CP5/CP6/CP10/CP11/CP12/CP14 baseline), STATE.md (Phase 13 acceptances: WR-02 block-then-replace, T-13-03, 13-04 matrix, 13-05 relative assets)

### Secondary (MEDIUM confidence)
- Browser reconnect-backoff specifics (A1); browser socket-read throttling behavior (A5) — training knowledge, flagged assumed
- Milestone research's CP11 framing — superseded in part by the spec-verbatim refinement above

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — zero new deps; webrick pin verified in gemspec + lockfile
- Transport mechanics: HIGH — webrick gem source read at file:line AND three behaviors machine-probed live; SSE processing model quoted verbatim from the spec
- Architecture (tailer/broadcaster/derivation): HIGH — every seam anchored to current code at file:line; thread/shutdown semantics grounded in webrick source
- Pitfalls: HIGH for code/spec-anchored items; MEDIUM only for browser-behavior assumptions (A1/A5, flagged)

**Research date:** 2026-09-01
**Valid until:** 2026-10-01 (stable: codebase- and gem-source-grounded; re-verify if `lib/spm_cache/web` or the webrick pin moves before Phase 14 execution)
