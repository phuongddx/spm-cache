---
phase: 14-live-log-streaming-terminal-watch-relay
plan: 01
subsystem: web
tags: [web, sse, streaming, events, tailer, broadcaster, tdd, LOGS-02, LOGS-03, LOGS-04, WEB-03]

requires:
  - phase: 12-run-log-capture-foundation plan 01
    provides: Core::RunLog JSONL writer — the frozen event vocabulary, file naming (incl. the -<n> collision suffix, run_log.rb:120-123), atomic header publish, UTF-8-scrubbed newline-escaped lines, retention prune
  - phase: 13-server-skeleton-read-only-dashboard plans 01/02
    provides: Web::Server/Router/Middleware — the Host/Origin/token gate (?token= query path at router.rb:60), the injectable-collaborator wiring precedent, and the WEBrick chunked/proc-body mechanics (14-RESEARCH live probes)
  - phase: 13-server-skeleton-read-only-dashboard plan 04
    provides: spec/support/web_server_boot.rb — the one port-0 boot harness this plan extends with raw-SSE helpers
provides:
  - the SSE wire contract fixed for 14-03..14-05 — named events hello/entry/switch/notice, entry ids '<run-filename>:<byte-offset>' (offset AFTER the newline), hello carrying retry: 3000 + run + parsed run_start header + derived status (running/completed/interrupted/idle), switch {run, previous}, notice {message}
  - SPMCache::Web::Events — lazy singleton-free facade (parse_resume_id / resolve_run_name / choose_run / run_state / each_entry / frame) + Broadcaster + Client + Tailer + ShutdownSentinel, injectable per keyword for specs
  - GET /api/events — always 200 text/event-stream once authed, keep_alive=false, chunked one-write frames, heartbeat-by-pop-timeout ': ping', exactly-once replay→queue handoff, hostile Last-Event-ID → fresh replay (never opened)
  - Web::Server#shutdown → Router#shutdown_events → Events#shutdown! sentinel ordering (WEB-03: WEBrick's connection-thread join cannot hang; trap-context safe via a ThreadError fallback thread)
  - WebServerBoot.raw_stream_open / raw_read_until / raw_close — bounded raw-socket SSE reading, reused by 14-03's integration rows
affects:
  - 14-03 (runs read model, hello lock field, ?run= replay — consumes resolve_run_name, the validation machinery, and the hello shape)
  - 14-04/14-05 (frontend log panel — consumes the event names, id format, and pinned notice strings verbatim)

actuals:
  tokens: 17218   # chars/4 over the realized diff (68,525 added + 349 removed across the 6 commits); plan estimated 48000 at confidence low — no prior samples for this profile
  tasks: 3
  commits: 6

tech-stack:
  added: []   # webrick 1.9.2 was already the Phase 13 runtime dep; stdlib only (thread, json, socket via existing requires)
  patterns:
    - "One SSE frame = ONE out.write call = one WEBrick chunk — frame bytes stay contiguous on the wire, so raw-socket pattern assertions are unambiguous against the chunked stream"
    - "Exactly-once replay→queue handoff by id-based suppression: after the disk replay, queued entries with composite id (filename, byte-offset) <= the last delivered id are dropped — filename-first comparison means a newer file's entries are never suppressed by an older file's offset"
    - "pop(timeout:) IS the heartbeat timer — no dedicated thread; the periodic write also probes the writer, so a dead client is discovered even when no further entries arrive"
    - "Forward-only discovery switching: a vanished-from-listing file keeps its held fd (POSIX unlink survival) — switching away on disappearance would break D-07 fd survival"
    - "Trap-context safety by rescue: Mutex#synchronize raises ThreadError in a signal handler (probed on Ruby 3.2.3), so the sentinel fan-out falls back to a short-lived thread"

key-files:
  created:
    - lib/spm_cache/web/events.rb
    - spec/events_tailer_spec.rb
    - spec/events_broadcaster_spec.rb
    - spec/web_events_route_spec.rb
  modified:
    - lib/spm_cache/web/router.rb
    - lib/spm_cache/web/server.rb
    - spec/support/web_server_boot.rb

key-decisions:
  - "Tailer attach offsets: initial attach lands at the LAST COMPLETE LINE (only post-attach appends are queued — a client's own disk replay covers history, and big files don't flood queues into spurious drop notices); a D-04 switch lands at BYTE 0 (connected clients have not replayed the new run). The exactly-once suppression rule makes the handoff correct regardless of the tailer's start offset."
  - "Full-file replay including the run_start header line as an ordinary entry frame: the stream is the FILE verbatim from byte 0 (LOGS-03), hello separately carries the parsed header — skipping any line in replay would break byte-offset/id arithmetic"
  - "parse_resume_id returns {exists: boolean} for well-formed+contained names: hostile input is nil (silent fresh replay), while a vanished (pruned) run is a first-class honest notice (Task 3) — one parse signature across both tasks"
  - "register-under-shutdown guard: a client registering after the sentinel fan-out receives its sentinel under the registry lock — no sentinel-less straggler can hang WEBrick's shutdown join"
  - "POST /api/events?token= is 401, not 404: WEBrick parses no URL query for POST bodies — the gate row's POST sends the token via the X-SPM-Token header (pre-existing router-wide behavior, not an events-route bug)"

requirements-completed: [LOGS-03]

coverage:
  - id: LOGS-03
    description: "Loading mid-build replays from start; reconnects resume without lost lines (Last-Event-ID; never 204)"
    verification:
      - kind: integration
        ref: "spec/web_events_route_spec.rb — replay-from-byte-0 row, Last-Event-ID round-trip (exact next line, no re-delivery), collision-suffixed-name resume, hostile-id matrix (traversal canary never opened), 200-always + Connection: close rows"
      - kind: unit
        ref: "spec/events_tailer_spec.rb — multi-byte resume exactness, partial-line buffering, id monotonicity (offset AFTER the newline)"
      - kind: integration
        ref: "spec/web_events_route_spec.rb exactly-once row — double-delivery window opened live against a 2000-line fixture, marker id counted exactly once"
        status: pass
  - id: LOGS-02
    description: "Browser shows a single live log stream with per-package anchors (transport half here; browser rendering is 14-04/14-05)"
    verification:
      - kind: integration
        ref: "spec/web_events_route_spec.rb LIVE tracer row — one real line appended to a tmpdir fixture reaches a raw-socket HTTP client through tailer → broadcaster → /api/events within the poll bound"
        status: pass
      - kind: manual-pending
        ref: "Browser rendering with anchors (14-04/14-05); D-14 recorded agent-browser probe"
        status: pending
  - id: LOGS-04
    description: "Terminal- and watch-initiated runs stream into the same browser view as UI-triggered runs (writer-agnostic mechanism here)"
    verification:
      - kind: unit
        ref: "spec/events_tailer_spec.rb — watch-cycle fixture tails identically (verb 'watch' + trigger 'watch'); discovery/switch row proves any new run file switches the stream (D-04)"
        status: pass
      - kind: manual-pending
        ref: "Same-browser-view equivalence (14-05); UI-triggered runs are Phase 15 (badge reserved)"
        status: pending
  - id: WEB-03
    description: "Shutdown stays exit-0 with open streams (unit-proven here; integration row lands in 14-03)"
    verification:
      - kind: unit
        ref: "spec/events_broadcaster_spec.rb — sentinel return bound, idempotence, register-during-shutdown, shutdown-mid-race (no stragglers); Server seam ordered before @http.shutdown"
        status: pass

duration: 34min
completed: 2026-09-01
status: complete
---

# Phase 14 Plan 01: Tracer — `Web::Events` Tailer + Broadcaster + `/api/events` SSE Route Summary

**The live-log streaming spine is shipped end-to-end: one real run-log line appended to a tmpdir fixture now reaches a raw-socket HTTP client as an SSE frame through tailer → broadcaster → GET /api/events — always 200 text/event-stream once authed (any non-200 permanently kills EventSource reconnect, WHATWG §9.2.3; the milestone's 503 clause is falsified and was NOT implemented), replaying from byte 0 on fresh connect, resuming byte-exactly on Last-Event-ID (multi-byte content and same-millisecond collision-suffixed run names included), exactly-once across the replay→queue handoff, heartbeat ': ping' by pop-timeout, '{N} lines dropped' drop-oldest notices, a pinned pruned-run fallback notice, and a shutdown sentinel ordered before WEBrick's connection-thread join — committed as three RED/GREEN pairs (15 + 6 + 5 spec examples), with the full suite at 823 examples, 0 failures.**

## Performance

- **Duration:** ~34 min (13:03–13:37 UTC) — includes the mandatory green-baseline full-suite run (787 examples) and the wave-gate full-suite run (823 examples)
- **Tasks:** 3 (tracer RED→GREEN, broadcaster RED→GREEN, discovery/retention RED→GREEN)
- **Commits:** 6 (`bb35be4`/`d959908`, `37bfa84`/`6a4df02`, `38ad1f1`/`c726f94`)
- **Files:** 4 created (events.rb + three spec files), 3 modified (router.rb, server.rb, web_server_boot.rb)

## What Shipped vs Plan

### Task 1 — tracer slice (bb35be4 RED → d959908 GREEN)
RED exactly as planned: **15 examples, 15 failures** (8 tailer + 7 route), every failure the expected `SPMCache::Web::Events` NameError (constants resolved inside examples so the file loads, per the 0-examples trap). GREEN: `events.rb` (Events facade + Entry/Switch/Notice/ShutdownSentinel + Client + Broadcaster + Tailer), router dispatch + `shutdown_events`, server seam, raw-SSE boot helpers. Route rows green including the LIVE tracer row, the exactly-once handoff row (2000-line fixture, marker id exactly once), and the hostile-id matrix (traversal canary never opened).

### Task 2 — broadcaster hardening (37bfa84 RED → 6a4df02 GREEN)
RED exactly as planned: **6 examples, 6 failures** — achieved by scoping Task 1 to the tracer mechanics only (sentinel + registry + non-blocking drop-oldest mechanism) and leaving the six hardening behaviors (notice flush, ping write, shutdown guard, idempotence flag, writer-probing liveness, race coverage) to this task's GREEN. Drop-oldest: cap 3, publish 5 → queue holds the newest 3 and the first received frame is the notice `"2 lines dropped"` (pinned format, exact count). Heartbeat: `: ping` within 1s at heartbeat 0.05 — pop-timeout is the timer (grep-clean: no Timeout, no dedicated thread; `Thread.new` appears only for the tailer loop and the trap-context sentinel fallback).

### Task 3 — discovery/switch + retention (38ad1f1 RED → c726f94 GREEN)
RED: 3 failures (switch event, pruned-reconnect notice, absent-runs-dir recovery) + 2 day-one regression pins (fd survival through real unlink; no-memoization restart) — see Deviations. GREEN: forward-only per-tick discovery (a newer run switches the follow to byte 0 and emits the switch event; a file that vanished from the listing keeps its held fd), the pinned `'run log pruned while viewing; switching to newest'` notice for vanished resume ids (parse-time and mid-flight ENOENT), once-per-episode tailer-side prune notice, and unchanged fd+offset+buffer-only memoization (CP10/Pitfall 7).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `parse_resume_id` dropped the `.jsonl` extension**
- **Found during:** Task 1 GREEN
- **Issue:** RESUME_ID's group 1 excludes the extension by design; the method used `match[1]` as the filename directly, so `exists` was always false — every reconnect silently fell back to fresh replay (LOGS-03 break, caught by the round-trip row).
- **Fix:** Reattach the extension (`"#{match[1]}.jsonl"`) before expand_path/containment.
- **Verification:** Resume round-trip + collision-suffix rows green.
- **Commit:** d959908

**2. [Rule 1 - Bug] `Array#<=` does not exist — the suppression compare crashed the stream**
- **Issue:** `[file, offset] <= [last_file, last_offset]` raises NoMethodError (Arrays have `<=>` only); the exception escaped the body proc and WEBrick closed the stream (EOF in the raw reader). Found via WEBrick's own error log in a manual probe.
- **Fix:** `([item.file, item.offset] <=> [last_file, last_offset]) <= 0`.
- **Commit:** d959908

**3. [Rule 1 - Bug] Partial trailing lines were re-read and re-buffered every poll**
- **Issue:** `read_appended` always seeked to `@offset`; a partial line (no newline) does not advance the offset, so each tick re-read and re-appended it ("parparpar…").
- **Fix:** Seek to `@offset + @buffer.bytesize` — buffered bytes are never re-read.
- **Commit:** d959908

**4. [Rule 1 - Bug] Binary reads tagged lines ASCII-8BIT, breaking byte-equality assertions**
- **Fix:** `Events.utf8!` — force_encoding(UTF_8) without transcoding (the writer guarantees valid UTF-8 bytes, run_log.rb:248); byte offsets untouched ('rb' only). One follow-up receiver bug (`self.class.utf8!` inside Tailer resolved to `Events::Tailer`) was caught by the tailer rows and fixed to `Events.utf8!`.
- **Commit:** d959908

**5. [Rule 1 - Bug] `Router#shutdown_events` landed below the `private` section**
- **Issue:** `Server#shutdown` raised NoMethodError BEFORE `@http.shutdown`; `with_server`'s rescue swallowed it, so WEBrick never stopped and every boot burned the full `join(10)` — a 10s-per-example teardown hang that also masked the real error.
- **Fix:** Moved the seam above `private` (public, with a comment pinning why).
- **Verification:** Suite teardown back to sub-second; web_state/web_server spec runtimes restored.
- **Commit:** d959908

**6. [Rule 1 - Spec mechanics] `raw_read_until` over-reads past its pattern**
- **Issue:** Sequential per-region reads on one socket lose the first read's over-read bytes (headers/body split).
- **Fix:** Single read + `partition("\r\n\r\n")` in the affected examples. Also: the POST gate row sends the token via header (WEBrick parses no URL query for POST → 401, not 404); the replay row expects the full-file replay (header line included — 3 payloads, the honest byte-0 contract); `scan` with a group returns arrays (`.flatten.last`); the exactly-once quiescence uses a 1s greedy drain (pings do not exist until Task 2).
- **Commits:** d959908 (within GREEN; assertions strengthened, none weakened)

**7. [Rule 1 - Spec mechanics] Race example thread exhaustion + unregister ownership**
- **Issue:** Task 2's register/unregister race loop spawned threads unbounded (`can't create Thread`); the racer-side unregister also created a sentinel-less window production never hits (unregister is exclusively the stream's own ensure).
- **Fix:** Bounded iterations (3×40); unregistering is the streams' own ensure-unregister racing itself at shutdown — the production shape.
- **Commit:** 6a4df02

### Plan-Internal Inconsistencies (documented, not silently absorbed)

**Task 2 RED count — achieved as planned (6/6)** by resolving the plan's self-conflict in favor of the pinned counts: Task 1's action prose describes the merged end-state (drop-notice, ping, idempotence), but shipping those in Task 1 would make Task 2's RED (6 failures, load-bearing per the phase TDD contract) impossible. Task 1 therefore shipped the tracer mechanics + the non-blocking drop-oldest MECHANISM (blocking pushes could wedge the tailer on one slow client), and the notice flush / ping write / shutdown-protocol hardening landed in Task 2's GREEN as that task's own name and behavior specify.

**Task 3 RED count — 3/5, not 5/5:** the fd-survival and no-memoization rows pass from Task 1's state because Task 1's own action text MANDATES the held fd ("holds its fd for the served file so prune-unlink keeps it readable (POSIX)") and per-connect disk derivation (CP10). Un-implementing either to force RED would deliberately ship worse interim code against the plan's explicit instructions. Committed as RED with exactly the 3 new-behavior failures; the 2 passing rows serve as day-one regression pins.

### Clarifications (documented, not deviations)

- `spec/support/web_server_boot.rb` gained an additive `events:` kwarg (conditionally forwarded) beyond the three named helpers — required for the route spec's short-poll/heartbeat injection; conditional so the pre-14-01 router shape kept working during the RED window. Shared-file discipline honored (sibling agent's file set untouched).
- The route parses Last-Event-ID once in `events_stream` (before assigning the body proc) rather than inside the proc — identical semantics, no per-connection re-parse.
- Examples 1's hello assertion pins the first chunk as `retry: 3000` + hello (the in-stream retry field is the only reconnect-time control).

**Total deviations:** 7 auto-fixed (6 Rule-1 bugs/spec-mechanics + 1 follow-up receiver fix), 2 plan-internal count reconciliations documented above. **Impact:** none on the frozen wire contract or prohibitions; every prohibition re-verified below.

## Threat Flags

All register dispositions honored; no surface beyond the plan's threat_model was introduced:

| Flag | File | Description |
|------|------|-------------|
| threat_mitigated: T-14-01 | lib/spm_cache/web/events.rb | Last-Event-ID regex (research-verbatim incl. the collision suffix) + expand_path containment BEFORE any File.open; the traversal canary fixture proves the target file is never opened and its content never appears in any frame |
| threat_mitigated: T-14-02 | lib/spm_cache/web/router.rb | The structural Host → Origin → token gate covers the stream (403/403/401 rows); ?token= rides the existing constant-time valid_token?; auth failures deliberately permanent |
| threat_mitigated: T-14-03 | lib/spm_cache/web/server.rb + events.rb | Sentinel fan-out BEFORE @http.shutdown; bounded pop caps sentinel latency at one heartbeat; idempotent; register-during-shutdown guarded; trap-context fallback thread (Mutex raises ThreadError in trap handlers — probed) |
| threat_mitigated: T-14-05 | router.rb / server.rb | Query-param token posture unchanged; Cache-Control no-store + X-Frame-Options DENY stamped on the stream by the existing global header sweep (asserted in the headers row) |
| threat_mitigated: T-14-06 | events.rb | JSONL lines stream VERBATIM as data — no interpretation; the payload never drives server behavior |
| threat_mitigated: T-14-07 | events.rb | Tailer memoizes only fd/offset/buffer; every connect re-derives identity/status from disk — pinned by the no-memoization restart row |

T-14-04 (connection flood) accepted as planned: loopback-only bind + WEBrick MaxClients, no new surface.

## Known Stubs

None. Every named component (Events facade, Tailer, Broadcaster, Client, ShutdownSentinel, parse_resume_id, resolve_run_name, choose_run, run_state, each_entry, frame, the route, the shutdown seam, the raw-SSE helpers) is a complete real implementation with spec coverage. No placeholder markers (`TODO`/`FIXME`/…) in any touched file (grep-verified).

## Verification

- **Task 1 RED:** `bundle exec rspec spec/events_tailer_spec.rb spec/web_events_route_spec.rb` → **15 examples, 15 failures** (all the expected NameError)
- **Task 1 GREEN:** same command → 18 examples (15 + spec_helper's 3), 0 failures; `spec/web_state_spec.rb spec/web_server_spec.rb` green (lazy Events default = zero boot threads, zero regressions)
- **Task 2 RED:** `spec/events_broadcaster_spec.rb` → **6 examples, 6 failures**; GREEN → 9 examples (6 + 3), 0 failures; tailer spec still green; grep-clean (no Timeout, no heartbeat thread)
- **Task 3 RED:** tailer spec → **3 failures** (switch, pruned notice, resilience) + 2 regression pins passing (see Deviations); GREEN → 16 examples, 0 failures
- **Plan-level:** `bundle exec rspec spec/events_tailer_spec.rb spec/events_broadcaster_spec.rb spec/web_events_route_spec.rb spec/web_state_spec.rb spec/web_server_spec.rb` → **63 examples, 0 failures**
- **Wave gate (full suite):** `bundle exec rspec` → **823 examples, 0 failures** (baseline before the plan: 787, 0 failures)
- Task commits: **bb35be4 / d959908 / 37bfa84 / 6a4df02 / 38ad1f1 / c726f94**

## Self-Check: PASSED

All four created files exist on disk; all six task commits present in history on gsd/v0.5.0-web-interface; prohibition spot-checks green — no non-200 for authed stream requests anywhere (200-always asserted), no forever-looping body proc (sentinel rows + shutdown seam), no File.open from Last-Event-ID without regex+containment (canary row), run files opened 'rb' only (grep: no text-mode opens in events.rb), no build-lock held anywhere in the server, no Core::Watcher/Command::Watch coupling (grep-verified zero references), no Core::Parallel usage.

## EXECUTION COMPLETE — 14-01
