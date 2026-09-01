---
fixed_at: 2026-09-01T06:54:27Z
review_path: .planning/phases/13-server-skeleton-read-only-dashboard/13-REVIEW.md
iteration: 1
findings_in_scope: 8
fixed: 8
skipped: 0
status: all_fixed
---
**Fixed at:** 2026-09-01T06:54:27Z (post-fix full suite: 787 examples, 0 failures — baseline 772 + 15 new regression specs)
# Phase 13: Code Review Fix Report

**Fixed at:** 2026-09-01 (post-fix full suite: 787 examples, 0 failures — baseline 772 + 15 new regression specs)
**Source review:** .planning/phases/13-server-skeleton-read-only-dashboard/13-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 8
- Fixed: 8
- Skipped: 0

## Fixed Issues

### WR-01: Error-envelope contract only covers JSON parse errors

**Files modified:** `lib/spm_cache/web/router.rb`, `spec/web_server_spec.rb`
**Commit:** 3c67e47
**Applied fix:** `api_read` rescues `JSON::JSONError` (covers ParserError AND its sibling GeneratorError — invalid-UTF-8 strings parse fine and explode at `JSON.generate` inside `respond_json`) plus `TypeError` (shape-malformed graph.json: object → `[key, value]` iteration → String-into-Integer). `api_doctor` gains the same 500-envelope rescue (StandardError, never Interrupt) — its in-model JSON round-trip raises GeneratorError before an envelope exists. Regression specs (live-server): malformed-shape graph.json → envelope on `/api/graph` AND `/api/state`; non-UTF-8 bytes in graph.json → envelope; hostile doctor check strings → envelope. All three proven RED pre-fix (raw WEBrick 500 HTML), GREEN post-fix.

### WR-02: Concurrent launches race the marker check-then-write

**Files modified:** `lib/spm_cache/command/web.rb`, `lib/spm_cache/web/marker.rb`, `spec/web_lifecycle_spec.rb`
**Commit:** 13f4861
**Applied fix:** `Command::Web#run` holds an flock `LOCK_EX` boot lock (`<web_dir>/.boot.lock`, installer/build.rb precedent) from before the marker check until the server stops; the launch body moved to private `#boot_and_serve`. `Marker.clear` gains `pid:` — a launch clears only its OWN record (the heal path stays unconditional); the shutdown ensure calls `clear(pid: Process.pid)`. Specs: lock-held-during-boot (blocking probe thread — macOS quirk: same-process LOCK_NB never conflicts, so the probe claims blocking), block-then-reuse serialization under a held lock, and foreign-marker survival when overwritten mid-serve. All five new examples RED pre-fix, GREEN post-fix.

### WR-03: Marker.clear exist?-then-unlink race breaks the exit-0 contract

**Files modified:** `lib/spm_cache/web/marker.rb`, `spec/web_lifecycle_spec.rb`
**Commit:** b1f0822
**Applied fix:** bare `File.unlink` + `rescue Errno::ENOENT` — a vanished-between-check-and-unlink marker can no longer raise from the shutdown ensure. Regression spec simulates the race via an argument-qualified `File.exist?` stub; RED on the old body, GREEN on the new.

### WR-04: Out-of-range --port values crash with a raw errno backtrace

**Files modified:** `lib/spm_cache/command/web.rb`, `lib/spm_cache/web/port_prober.rb`, `spec/web_lifecycle_spec.rb`
**Commits:** e3e16e5, a55e031 (range correction)
**Applied fix:** `parse_port` validates the coerced value and raises a clear `GeneralError` ("--port must be between 0 and 65535") instead of letting unbindable values die as raw errno/SocketError dumps deep in the boot; garbage input still falls back to the default (existing spec). `PortProber.bind` additionally rescues `SystemCallError, SocketError` so any unbindable candidate (ports above 65535 raise SocketError on macOS, EADDRNOTAVAIL on Linux) is probed past and exhaustion raises the friendly GeneralError. Boundary correction: the first cut used 1..65535; the full-suite run caught the real-subprocess signal contract specs booting with `--port=0` — a first-class input here (`Server#resolve_port`, prober `start_port 0`) — so the range is 0..65535. Specs: `--port=-5`/`--port=70000` → friendly GeneralError (RED pre-fix with raw SocketError); `--port=0/1/65535` accepted; prober exhaustion over 65536+.

### IN-01: Graph re-render never destroys the previous cytoscape instance

**Files modified:** `lib/spm_cache/web/assets/app.js`, `spec/web_frontend_spec.rb`
**Commit:** 52d35dc
**Applied fix:** module-scoped `let cyGraph = null`; `renderGraph` destroys the previous instance before re-creating (`if (cyGraph) cyGraph.destroy(); cyGraph = window.cytoscape({...})`). Source-contract pin: destroy call present, exactly one `window.cytoscape(` construction site.

### IN-02: Empty-state "Refresh" styled as an accent .cmd span

**Files modified:** `lib/spm_cache/web/assets/app.js`, `spec/web_frontend_spec.rb`
**Commit:** 52d35dc
**Applied fix:** `Refresh` renders as plain text in both empty-state bodies (`cmd('Refresh')` → inline literal); `.cmd` stays reserved for `spm-cache build` / `spm-cache use`. New pin asserts `cmd('Refresh')` is gone and both corrected copy literals are present; the two old copy pins were updated to the corrected literals (`' to populate the cache, then Refresh.'`, `' to generate graph.json, then Refresh.'`).

### IN-03: Dead surface — Server#stop alias and Assets#root reader

**Files modified:** `lib/spm_cache/web/server.rb`, `lib/spm_cache/web/assets.rb`
**Commit:** 909e9c1
**Applied fix:** deleted `alias stop shutdown` and `attr_reader :root` (zero callers re-verified by grep across lib/ + spec/ before deletion; `@root` stays as internal state). No spec — dead-code deletion, protected by the existing suite.

### IN-04: Doctor check-line ellipsis hard-clips (flex children lack min-width: 0)

**Files modified:** `lib/spm_cache/web/assets/styles.css`, `spec/web_frontend_spec.rb`
**Commit:** 52d35dc
**Applied fix:** `min-width: 0;` added to `.check-name` and `.check-message` so `text-overflow: ellipsis` actually ellipsizes inside the flex row. Pin parses both rule blocks and asserts the declaration. (`flex: 0 1 auto` skipped — it is the flex-item default; only min-width was load-bearing.)

## Verification

- Full suite: `bundle exec rspec` — **787 examples, 0 failures** (baseline 772 + 15 new regression specs).
- RED→GREEN proven by stash-and-rerun for WR-01 (3 examples), WR-02 (5), WR-03 (1), WR-04 (CLI + prober).
- Verification ran in the main checkout (`gsd/v0.5.0-web-interface`); no worktree (`workflow.use_worktrees: false`).
- Semantic-logic notes for human spot-check: WR-02's lock-hold scope (held across `server.start`, released at the `File.open` block exit) and WR-04's 0-boundary decision are the two judgment calls worth an eyeball in verify-work.

---

_Fixed: 2026-09-01_
_Fixer: Claude (gsd-code-fixer, Phase13Fixer)_
_Iteration: 1_
