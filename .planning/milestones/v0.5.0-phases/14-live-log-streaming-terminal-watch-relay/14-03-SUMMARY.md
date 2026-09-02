---
phase: 14-live-log-streaming-terminal-watch-relay
plan: 03
subsystem: web
tags: [web, sse, read-model, cp10, state-derivation, api-runs, pinned-replay, tdd, LOGS-03, LOGS-05]

requires:
  - phase: 14-live-log-streaming-terminal-watch-relay plan 01
    provides: Web::Events (tailer/broadcaster//api/events), parse_resume_id's regex+containment validation machinery, resolve_run_name, choose_run, the raw-SSE boot helpers, and the shutdown sentinel ordering
  - phase: 14-live-log-streaming-terminal-watch-relay plan 02
    provides: the D-05 probe→announce→block insert at both flock sites — the honest in-stream attribution whose display half rides this plan's transport
  - phase: 12-run-log-capture-foundation plan 01
    provides: Core::RunLog's frozen JSONL vocabulary (header keys, run_end shape, filename chronology), pid_alive? semantics, and the atomic header publish a derivation can rely on
  - phase: 13-server-skeleton-read-only-dashboard plans 01/02/04
    provides: the api_read envelope row pattern, the read-model State shape (stateless .call), and the one port-0 boot harness this plan's weld extends
provides:
  - SPMCache::Web::ReadModels::Runs — the CP10 state derivation (flock probe + header pids + run_end lines) and the D-12 listing in ONE stateless read model; Runs.derive / Runs.lock_state / Runs.current_path are the shared helpers Events' hello consumes (one derivation, two surfaces, zero drift)
  - GET /api/runs — the fourth api_read row: token-gated, GET-only, standard envelope {runs, lock, now}; LIST_LIMIT = 10; statuses success/failed/running/'interrupted — exit unknown'
  - hello upgraded — the parsed run_start header verbatim + the Task-1 status vocabulary + the lock hash (server-internal; the client renders nothing for it) + a server 'now' ISO8601 stamp
  - ?run= pinned streaming — a validated run name pins the stream: byte-0 replay of the NAMED run via the resume machinery + a per-connection PinnedFollow (Events.drain_appended extracted and shared with the tailer: one line-splitter, two drivers); ENTRY delivery scoped to the named run, switch/notice broadcasts still delivered, the stream never re-pointed; invalid names byte-equivalent to omitting the param; vanished names → the pinned pruned notice + fresh replay
  - the one-boot SSE integration weld — six rows on the single port-0 boot (headers, replay+hello, LIVE, exact resume, phase bound, shutdown-with-open-stream within 10 s — the webrick server.rb:210 sentinel proof)
affects:
  - 14-04/14-05 (the dropdown consumes /api/runs' entry template {glyph command · relative}; log.js's card consumes hello's header/status/now; loadRun rides ?run=; the switch handler drops the pin client-side and reconnects unpinned — exactly the pinned semantics shipped here)

actuals:
  tokens: 13011   # chars/4 over the realized diff (52,044 added + removed chars across the 5 commits); plan estimated 34000 at confidence low — first sample for this profile
  tasks: 3
  commits: 5

tech-stack:
  added: []   # stdlib only (json, time); no new runtime dependency, no gemspec change
  patterns:
    - "One derivation, two surfaces: Runs.derive/lock_state feed BOTH /api/runs and hello, so the D-06 card and the D-12 dropdown agree by construction — Events' own status rules were REMOVED (clean cutover), choose_run delegates to Runs.current_path"
    - "The pinned follow reuses the tailer's drain as a CLASS-level helper (Events.drain_appended): the appended-bytes line-splitter exists once and has two drivers — a pinned connection's entries come solely from its own disk follow, so the shared tailer's entries for newer runs are dropped rather than filtered late"
    - "Pinned pop cadence: pop(timeout: min(heartbeat, poll)) with a heartbeat-window gate — poll-grained follow ticks without comment-frame spam; the sentinel still returns immediately (push beats timeout)"
    - "The lock payload is a 3-key hash {state, holder, holder_status} carried IDENTICALLY by /api/runs and hello — the plan named only held/free; the hash is what lets the CP10 matrix pin attribution ('unknown holder' vs a holder identity) without a second field vocabulary"

key-files:
  created:
    - lib/spm_cache/web/read_models/runs.rb
    - spec/web_runs_read_model_spec.rb
  modified:
    - lib/spm_cache/web/events.rb
    - lib/spm_cache/web/router.rb
    - spec/web_events_route_spec.rb
    - spec/web_integration_spec.rb

key-decisions:
  - "Runs' public surface is call / derive / lock_state / current_path / list rather than the plan's suggested derive_current(config:): hello must reflect RESUMED and PINNED runs, not just the current choice — sharing the RULES (derive + lock_state) is the zero-drift guarantee the plan actually pins; derive_current would have forced a second selection path (the plan offered it as 'if cleanest')"
  - "The hello status vocabulary is richer than 14-01's interim note ('completed'): success/failed/running/'interrupted — exit unknown' per this plan's Task-1 vocabulary and 14-UI-SPEC's glyph table — no spec anywhere pinned 'completed' (grep-verified); the exit line is authoritative for FINISHED runs, pid liveness for liveness"
  - "resolve_run_name reshaped to parse_resume_id's {name, path, exists} contract: hostile input → nil (silent fallback, never an error surface), a well-formed vanished name → exists: false (the pinned pruned notice) — one validation posture across Last-Event-ID and ?run="
  - "Task 3 landed as ONE commit (the rows) — the planned GREEN 'owning-module fixes' commit is intentionally omitted: every row was green on first run and stable across 5 further runs (the plan's own 'verification net' clause anticipated exactly this); an empty commit would have been packaging theater"
  - "The weld's Events instance is injected at spec speed (poll 0.05 s) into the EXISTING before(:all) boot — still exactly ONE boot (CP7); the 15 s runtime-bound example still measures the pre-SSE matrix because the SSE describe is defined after it (order: :defined) and the whole file runs in ~0.3 s"

requirements-completed: [LOGS-05]

coverage:
  - id: LOGS-05
    description: "Each run shows identity — trigger source, command, status — with external-run detection from the build lock (SC4 backend complete)"
    verification:
      - kind: unit
        ref: "spec/web_runs_read_model_spec.rb — CP10 matrix: thread-held flock probe held→free both directions (acquire-and-release atomically proven), running attribution with holder identity, 'unknown holder' never a guess, CP14 'interrupted — exit unknown' never 'running', success/failed/running vocabulary with ended_at, D-12 newest-first listing + LIST_LIMIT, empty-dir guard shape, String-key round-trip"
        status: pass
      - kind: integration
        ref: "spec/web_events_route_spec.rb — hello carries the parsed header verbatim + status + lock + now, asserted equal to a simultaneously fetched /api/runs payload (same run, same status, same lock); pinned ?run= rows prove in-place reachability with never-re-pointed entries"
        status: pass
  - id: LOGS-03
    description: "Loading mid-build replays from start; reconnects resume without lost lines (extends 14-01's coverage with the one-boot weld)"
    verification:
      - kind: integration
        ref: "spec/web_integration_spec.rb 'live log stream (Phase 14 weld)' — byte-0 replay with exact byte-offset ids from the single real boot, LIVE append within the poll bound, exact Last-Event-ID resume (exactly two entry frames, no duplication), and shutdown-with-open-stream joining within 10 s"
        status: pass

duration: 50min
completed: 2026-09-01
status: complete
---

# Phase 14 Plan 03: Runs Read Model (CP10) + `/api/runs` + hello/lock + `?run=` Replay + the One-Boot SSE Weld Summary

**Run identity and status now derive honestly from disk in one stateless read model — a non-blocking flock probe (acquire-and-release in a single File.open; the server never holds), header pids, and run_end exit lines, with CP14's 'interrupted — exit unknown' and LOGS-05's 'unknown holder' external-run detection — serving two surfaces with zero drift: GET /api/runs (the fourth api_read row, newest-first listing, zero storage) and the stream's hello (header verbatim + status + lock + server now); `?run=<valid>` pins a named run in place (byte-0 replay + a per-connection follow sharing the tailer's extracted drain helper — entries never re-pointed, switch/notice broadcasts still delivered), hostile names are byte-equivalent to omitting the param, and the phase's one-boot integration weld proves replay, LIVE delivery, exact resume, and a clean shutdown WITH an open stream — full suite 873 examples, 0 failures.**

## Performance

- **Duration:** ~50 min end-to-end (task commits 20:54–21:14 +0700; preceded by the plan's full read_first pass)
- **Tasks:** 3 (Runs + /api/runs RED→GREEN; hello/pin RED→GREEN; the one-boot weld)
- **Commits:** 5 (`bab942c`/`3b04d1c`, `f8f16ed`/`0f49f88`, `033788c` — the weld's planned GREEN-fixes commit intentionally omitted, see Deviations)
- **Files:** 2 created (runs.rb, web_runs_read_model_spec.rb), 4 modified (events.rb, router.rb, web_events_route_spec.rb, web_integration_spec.rb)

## What Shipped vs Plan

### Task 1 — ReadModels::Runs + GET /api/runs (bab942c RED → 3b04d1c GREEN)
RED exactly as planned: **9 examples, 9 failures** (8 NameError on the unresolved constant — resolved inside examples per the 0-examples trap — + the router-mount row failing 404-vs-401). GREEN: `runs.rb` (stateless `.call(config:)`, derivation/lock/listing helpers, LIST_LIMIT = 10, INTERRUPTED pinned verbatim with the em dash) + the router's fourth api_read row. The thread-held flock helper (the repo's first cross-thread lock fixture) lives in the spec with bounded pops/joins and a JOINED release so the free-direction assertion cannot race the unlock.

### Task 2 — hello/lock/now from the shared derivation + pinned ?run= (f8f16ed RED → 0f49f88 GREEN)
RED: **4 of the 5 new examples failing** (hello-derivation, pinned-older, pinned-live, pruned-notice) + the hostile-values row as a day-one regression pin (see Deviations). GREEN: events.rb cutover — hello consumes `Runs.derive`/`Runs.lock_state`; `stream` accepts `pin:`; `PinnedFollow` delivers the named run's growth through the extracted `Events.drain_appended` (also rewiring the tailer's own read); `pop_loop` scopes ENTRY delivery for pinned connections and shortens the pop timeout with a heartbeat-window gate; `resolve_run_name` reshaped to parse_resume_id's `{name, path, exists}`; router passes the validated pin. `Events.run_state`/`pid_alive?` were REMOVED (clean cutover — no spec pinned them; `choose_run` now delegates to `Runs.current_path` so the tailer spec's seam holds).

### Task 3 — the one-boot SSE weld (033788c)
The existing single boot gained the runs fixture (header pid = the spec process → genuinely 'running') and a real Events instance at spec speed; the six-row describe landed AFTER the runtime-bound example (order: :defined) with the shutdown row LAST: headers, replay+hello, LIVE append, exact resume (two entry frames, no duplication), phase bound (~0.3 s file runtime vs the ~25 s budget), and the shutdown-with-open-stream join within 10 s — WEBrick's accept-loop join (server.rb:210) returned because the sentinel ended the open body proc. **Every row green on the FIRST run, stable across 5 further runs** — the plan's "verification net" expectation held; zero owning-module fixes were needed.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `def self.drain_appended` nested inside `class << self` — the tailer silently stopped publishing**
- **Found during:** Task 2 GREEN (the 14-01 LIVE tracer row regressed; events_tailer_spec showed 7 failures)
- **Issue:** Defining `def self.X` inside `class << self` puts the method on the eigenclass of the eigenclass — `Events.drain_appended` was undefined; the NoMethodError was swallowed by the tailer's continue-on-error `tick` rescue every tick (and killed pinned streams at the first follow drain).
- **Fix:** Plain `def drain_appended` inside the block → a real class method.
- **Files modified:** lib/spm_cache/web/events.rb
- **Verification:** Full events+web set green (77 examples incl. all 14-01 rows).
- **Commit:** 0f49f88

**2. [Rule 1 - Bug] A mis-anchored router edit clobbered `Router#root`'s tail and deleted `Router#asset`**
- **Found during:** Task 2 GREEN (caught by `ruby -c` + full-diff review BEFORE any test run or commit)
- **Issue:** Stale line numbers after an earlier hunk replaced the wrong region — the asset method vanished and root lost its middle.
- **Fix:** Restored both verbatim from the pre-edit read; final router diff verified minimal (comment extension + pin line + pin-passing call).
- **Files modified:** lib/spm_cache/web/router.rb
- **Verification:** web_state/web_server/road-matrix rows green in the wave gate.
- **Commit:** 0f49f88

**3. [Rule 1 - Spec mechanics] Vocabulary-row lookup key mismatch**
- **Issue:** The running fixture's FILENAME carried `pid: Process.pid` but the lookup used the default-pid name → nil lookup.
- **Fix:** Named the fixture once (`running_name`) and reused it for write + lookup.
- **Verification:** Task 1 spec green.
- **Commit:** 3b04d1c (inside GREEN; assertion unchanged in strength)

**4. [Rule 1 - Spec mechanics] Racy replay-count assertions (mid-replay marker + full-count expectation)**
- **Found during:** Task 2 stability runs (intermittent 3-vs-4 payload counts under load)
- **Issue:** Matching 'older two' (payload 3 of 4) or LINE1 (payload 2 of 3) returns before the replay's final frame lands — the count assertion raced chunk arrival.
- **Fix:** Read to the replay's LAST line ('"run_end"' / LINE2_TEXT) before counting.
- **Verification:** 5× consecutive green on the route spec.
- **Commit:** 0f49f88

### Plan-Internal Inconsistencies (documented, not silently absorbed)

**Task 2 RED count — 4/5, not 5/5:** the hostile-?run= row passes against pre-GREEN code because an ignored query param IS the pinned fallback behavior the row asserts (same-shape hello, same byte-0 replay, canary never opened) — and the plan itself PROHIBITS the behavior that would force it red (unvalidated names must fall back silently, never error). Committed as RED with exactly the 4 new-behavior failures; the hostile row serves as a day-one regression pin — the same reconciliation 14-01's Task 3 recorded (3/5 + 2 pins).

**Task 3 GREEN commit — intentionally omitted:** the plan scripts RED (the rows) then GREEN "with any owning-module fixes". Every row was green on the first run and stayed green across 5 further runs — the plan's own behavior text anticipated this ("expected: mostly green immediately once written — this is a verification net; any failing row is a real bug… before GREEN"). An empty commit would have been packaging theater; the omission is recorded here instead.

**hello status vocabulary — 'success'/'failed', not 14-01's interim 'completed':** this plan's Task 1 pins the vocabulary and 14-UI-SPEC's glyph table (✓ success / ✗ failed / ! interrupted / ● running) consumes it; no spec anywhere pinned 'completed' (grep-verified before the cutover). The richer statuses flow to BOTH surfaces through the one derivation.

**Runs' seam — derive/lock_state/current_path, not derive_current:** the plan offered `Runs.derive_current(config:)` "if cleanest" — but hello must reflect RESUMED and PINNED runs, not just the fresh choice; sharing the RULES (derive + lock_state) is the actual zero-drift requirement, and it avoids a second selection path.

### Clarifications (documented, not deviations)

- The lock payload is a hash `{state, holder, holder_status}` (not a bare 'held'/'free' string): the CP10 matrix needs attribution expressible ('unknown holder' vs a holder identity), and hello carries the IDENTICAL hash so `/api/runs`' and hello's lock can be asserted equal.
- The integration weld's resume row is self-contained (open → anchor → capture id → close → append two → reconnect) rather than literally reusing row 3's stream: cross-example instance state does not survive RSpec examples, and the self-contained form proves the same contract (exact resume, no loss, no duplication).
- Shared-file discipline with 14-04 (log.js frontend): their committed content_types one-liner and my boot-wiring + describe landed without overlap; commits interleaved cleanly (verified per-commit diffs).

**Total deviations:** 4 auto-fixed (2 Rule-1 production bugs caught pre-commit/post-run + 2 spec-mechanics), 4 plan-internal reconciliations documented above. **Impact:** none on the frozen wire contract or prohibitions; every prohibition re-verified below.

## Threat Flags

All five register dispositions honored; no surface beyond the plan's threat_model was introduced:

| Flag | File | Description |
|------|------|-------------|
| threat_mitigated: T-14-11 | lib/spm_cache/web/events.rb + spec/web_events_route_spec.rb | ?run= resolves through resolve_run_name — the SAME regex + expand_path containment as parse_resume_id BEFORE any File.open; hostile matrix ('../../spm-cache.yml', '/etc/hosts', 'not a run file', '') proves the traversal canary's content never appears in any frame |
| threat_mitigated: T-14-12 | lib/spm_cache/web/read_models/runs.rb | Stateless per call: no instance state, no memoization (the Doctor pattern explicitly rejected); ONE derivation path serves /api/runs and hello — drift impossible by construction |
| threat_mitigated: T-14-13 | runs.rb + web_runs_read_model_spec.rb | CP14 rows: pid liveness authoritative (Process.kill(0) reuse semantics), dead pid + no run_end → 'interrupted — exit unknown', never 'running'; unknown-holder never fabricates an identity |
| threat_mitigated: T-14-14 | runs.rb | The probe acquires-and-releases inside one File.open with LOCK_EX\|LOCK_NB (never blocks, never holds) — spec row 1 proves BOTH directions; ENOENT → free |
| threat_mitigated: T-14-15 | router.rb | /api/runs rides the structural Host/Origin gate + the standard constant-time token gate (401 row green); same trust level as every /api route — no new exposure class |

## Known Stubs

None. Runs (call/derive/list/lock_state/current_path/pid_alive?/lock_held?), the pinned streaming path (PinnedFollow + drain_appended + scoped pop_loop), the /api/runs row, and the hello upgrade are complete real implementations with spec coverage. No placeholder markers (TODO/FIXME/…) in any touched file (grep-verified).

## Verification

- **Task 1 RED:** `bundle exec rspec spec/web_runs_read_model_spec.rb` → **9 examples, 9 failures** (exactly the nine described rows)
- **Task 1 GREEN:** same → 12 examples (9 + spec_helper's 3), 0 failures; `spec/web_state_spec.rb spec/web_server_spec.rb` → 37 examples, 0 failures
- **Task 2 RED:** `spec/web_events_route_spec.rb` → **4 of the 5 new examples failing** (+ the hostile row as a day-one pin — documented above); all 14-01 rows green at RED
- **Task 2 GREEN:** `spec/web_events_route_spec.rb spec/web_runs_read_model_spec.rb` → 24 examples, 0 failures (spec_helper loads once across files), stable across 5 consecutive full-file runs
- **Regression sweep (the refactor's blast radius):** `spec/web_events_route_spec.rb spec/web_runs_read_model_spec.rb spec/events_tailer_spec.rb spec/events_broadcaster_spec.rb spec/web_state_spec.rb spec/web_server_spec.rb` → **77 examples, 0 failures**
- **Task 3 (the weld):** `spec/web_integration_spec.rb spec/web_server_spec.rb` → **71 examples, 0 failures**; file alone 51 examples in ~0.3 s, stable ×5; still exactly ONE boot; shutdown-with-open-stream joined within bound
- **Wave gate (full suite):** `bundle exec rspec` → **873 examples, 0 failures** (baseline after wave 1: 823)
- Task commits: **bab942c / 3b04d1c / f8f16ed / 0f49f88 / 033788c**

## Self-Check: PASSED

Both created files exist on disk; all five task commits present in history on gsd/v0.5.0-web-interface; prohibition spot-checks green — no run-state memory anywhere in the server (Runs is a stateless callable; grep: no instance variables carrying data across calls in runs.rb), the lock probe never holds (held→free both directions asserted; single File.open block), no unvalidated ?run= value reaches File.open (canary rows; resolve_run_name regex+containment precedes every open), exactly one server boot in web_integration_spec.rb, and the pinned stream is never re-pointed server-side (entry ids keep the named run's filename while the newer run's switch broadcast still arrives — asserted in two rows).

## EXECUTION COMPLETE — 14-03
