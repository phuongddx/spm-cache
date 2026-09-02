---
phase: 13-server-skeleton-read-only-dashboard
plan: 02
subsystem: web
tags: [web, read-models, inventory, doctor, api-state, api-graph, api-doctor]

requires:
  - phase: 13-server-skeleton-read-only-dashboard
    plan: 01
    provides: Web::Router with the {status,data,generated_at} envelope helpers, the read_models constructor seam, WebServerBoot spec helper, the gated /api/graph tracer slice
provides:
  - Cache::Inventory (shared debug/release *.xcframework scan: name/config/size_bytes/fidelity; cache_root spec seam; one source of truth for `cache list` and the web state model)
  - Web::ReadModels::State (/api/state data: packages rows joined with graph.json statuses + has_macro, Cachemap#stats summary, poll_seconds — re-read per request, zero memoization)
  - Web::ReadModels::Graph (tracer's inline graph reader extracted: present/nodes/graph mtime stamp)
  - Web::ReadModels::Doctor (registry-driven synchronous run under ?run=1, in-memory {data, generated_at} cache swapped under a Mutex, honest run-time stamp)
  - Core::Diagnostics.payload (the shared doctor JSON shape for CLI --json and the web read model)
  - Config#web_poll_seconds (default 5, Integer-coerced with rescue-to-default)
  - Router arms for /api/state and /api/doctor (token-gated; doctor envelope passes the cache's generated_at through verbatim)
affects:
  - 13-03 (frontend app.js consumes the pinned /api/state, /api/doctor, /api/graph payload shapes and poll_seconds this wave)
  - 13-04 (integration matrix re-proves per-endpoint token gates and envelope shapes end-to-end)
  - 15 (mutating endpoints inherit the api_read gate pattern)

actuals:
  tokens: 16471   # chars/4 over the realized diff (65885 chars across 6 commits); plan estimated 42000 at confidence low
  tasks: 3
  commits: 6

tech-stack:
  added: []   # stdlib + existing gems only, per plan
  patterns:
    - "One scan, two consumers: Cache::Inventory.scan is the single cache-dir read; `cache list` and the state read model both call it (grep-verified: exactly two production call sites)"
    - "One payload, two consumers: Diagnostics.payload is the single doctor JSON definition; print_json and the doctor read model both derive from it"
    - "Doctor data is normalized through the serializer the router serves (JSON round-trip) so the cached hash is defined AS its JSON shape — String keys at every level, matching the DASH-02 pin"
    - "api_read generalizes the tracer's api_graph: every GET-only /api/* endpoint shares the token-gate-then-verb-check-then-500-envelope-on-parse-error shape"
    - "Router doctor arm treats any PRESENT ?run= value as truthy (spec pins ?run=1, the button's form)"

key-files:
  created:
    - lib/spm_cache/cache/inventory.rb
    - lib/spm_cache/web/read_models/state.rb
    - lib/spm_cache/web/read_models/graph.rb
    - lib/spm_cache/web/read_models/doctor.rb
    - spec/web_state_spec.rb
    - spec/web_graph_spec.rb
    - spec/web_doctor_spec.rb
  modified:
    - lib/spm_cache/command/cache/list.rb
    - lib/spm_cache/core/config.rb
    - lib/spm_cache/assets/templates/spm-cache.yml.template
    - lib/spm_cache/core/diagnostics.rb
    - lib/spm_cache/command/doctor.rb
    - lib/spm_cache/web/router.rb
    - spec/command_cache_list_spec.rb
    - spec/config_spec.rb
    - spec/doctor_spec.rb

key-decisions:
  - "Inventory.scan keeps the CLI's sidecar tolerance verbatim (absent/malformed/non-Hash/keyless -> not-graph-pinned) and sizes recursively via lstat sums, counting symlinked entries at link size and never following them"
  - "`cache list` keeps its printed bytes exactly (new exact-output spec pins the full document); sizes are NOT printed in the CLI — that surface belongs to the web model"
  - "State joins graph.json by entry['module'] == artifact name; an artifact absent from the current graph gets state nil + has_macro false (the UI's '—' cell); summary = Cachemap#stats stringified, zeros when graph.json is absent"
  - "A malformed graph.json yields the 500 error envelope on /api/state as well as /api/graph (api_read rescues JSON::ParserError uniformly) — one failure mode, one shape"
  - "Doctor returns {data:, generated_at:} with nil stamp before the first run; the router passes the stamp through verbatim instead of stamping now(), so 'Cached — generated at' always labels the producing run"
  - "Only run:true executes checks (T-13-12); the {data, generated_at} pair swaps under one Mutex (T-13-10) so a WEBrick request thread can never read a torn cache"

requirements-completed: [DASH-01, DASH-02, DASH-03]

coverage:
  - id: DASH-01
    description: "/api/state serves one row per cached xcframework with size_bytes, graph status, fidelity, has_macro — re-derived per request from the CLI's own read path; `cache list` byte-identical after the Inventory extraction"
    verification:
      - kind: unit
        ref: "spec/web_state_spec.rb (14 examples: join/nil-state/has_macro default, summary stats + zeros, empty-cache trigger, poll_seconds default/override, string-key JSON round-trip, graph + cache-dir freshness re-reads, /api/state 401 gate)"
        status: pass
      - kind: unit
        ref: "spec/command_cache_list_spec.rb Inventory block (10 examples) + the byte-exact `cache list` output pin; all 10 pre-existing output examples pass unmodified"
        status: pass
  - id: DASH-02
    description: "/api/doctor returns the cached result with its original generated_at (or has_run:false); ?run=1 runs the registry synchronously, data-driven; payload shape EXACTLY the CLI --json shape"
    verification:
      - kind: unit
        ref: "spec/web_doctor_spec.rb (10 examples: never-run shape, run semantics, sleep-past-resolution cached stamp, stubbed-extra-check proof, hermetic ok/fail verdicts, no-yml tolerance, Mutex swap pair, envelope stamp passthrough incl. nil-before-first-run, 401 gate)"
        status: pass
      - kind: unit
        ref: "spec/doctor_spec.rb .payload pins (string statuses, summary counts, exact --json document) + the pre-existing --json examples passing unmodified"
        status: pass
  - id: DASH-03
    description: "GET /api/graph via Web::ReadModels::Graph — present flag, depgraph_for_viz nodes, mtime stamp; malformed -> 500 error envelope with the parse message"
    verification:
      - kind: unit
        ref: "spec/web_graph_spec.rb (8 examples: present true/false, nodes shape, zero-entry graph, File.utime mtime stamp, ParserError propagation, deletion-flips-present freshness, serve-through envelope, 401 gate)"
        status: pass

duration: 13min
completed: 2026-09-01
status: complete
---

# Phase 13 Plan 02: Read models — shared Inventory + /api/state + /api/graph + /api/doctor Summary

**The server's full read surface landed on the CLI's own read paths: one shared `Cache::Inventory` scan (byte-identical `cache list`), three read models answering the locked `{status, data, generated_at}` envelope (`/api/state` joined with graph.json, `/api/graph` extracted from the tracer, `/api/doctor` registry-driven with a Mutex-cached honest timestamp), one `Diagnostics.payload` shared by CLI --json and the dashboard, plus the `web_poll_seconds` config knob — 102 examples across the plan's six spec files, full suite 683 green.**

## Performance

- **Duration:** ~13 min
- **Tasks:** 3 (each RED-then-GREEN, 6 commits)
- **Files:** 15 changed (7 created, 8 modified)

## What Shipped vs Plan

### Task 1 — Cache::Inventory + Config#web_poll_seconds (RED 2cd459c → GREEN 9a911a4)
As planned: `Inventory.scan(config:, cache_root:)` returning keyword Structs `{name, config, size_bytes, fidelity}` sorted config-then-name; recursive lstat sizes with symlinks at link size; sidecar tolerance moved verbatim; `cache list` delegates with byte-identical output (new exact-output pin + all 10 pre-existing examples unmodified); `DEFAULT_CONFIG['web_poll_seconds']=5` + Integer-coercing reader (runs_keep posture) + template documentation line.

### Task 2 — State + Graph read models, router mounts (RED 9907517 → GREEN 8c2fdf4)
As planned: `ReadModels::State.call` joins Inventory rows with a module-keyed graph.json index (`state` nil + `has_macro` false for non-graph artifacts), stringified Cachemap#stats summary, `poll_seconds`; `ReadModels::Graph` lifted from the tracer's inline reader; Router mounts `/api/state`, re-points `/api/graph` through the generalized `api_read` helper (token gate → verb check → 500 error envelope on JSON::ParserError), constructor gains injectable `config:`.

### Task 3 — Diagnostics.payload + Doctor read model (RED 582c28d → GREEN 2e1f68f)
As planned: `Diagnostics.payload(results)` moved verbatim out of `print_json`; `print_json` delegates (existing --json specs unmodified); `ReadModels::Doctor` — instance per server, `run:true` executes `run_all` synchronously in-request with tolerant config load, `{data, generated_at}` swapped under a Mutex, `run:false` serves the cache with the RUN's stamp (sleep-past-resolution spec proves it), never-run shape `has_run:false`/zeros/nil stamp; Router `/api/doctor` passes the read model's stamp through verbatim; data-driven proof via a stubbed extra check; hermetic default-deny `Core::Sh` posture.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Correctness] /api/state also converts a malformed graph.json to the 500 error envelope**
- **Found during:** Task 2
- **Issue:** The plan pins the malformed→500 envelope only for /api/graph, but State reads the same graph.json; an uncaught parse error would escape the servlet as a WEBrick HTML 500.
- **Fix:** The shared `api_read` helper rescues JSON::ParserError uniformly for state and graph — one failure mode, one envelope shape.
- **Files:** lib/spm_cache/web/router.rb
- **Commit:** 8c2fdf4

**2. [Rule 1 - Contract] Doctor cached data normalized to String keys via the JSON serializer**
- **Found during:** Task 3 GREEN (spec failures)
- **Issue:** The plan's action sketched merging the symbol-keyed payload into the data hash, but the pinned DASH-02 data shape is String-keyed (`{"has_run"=>false, "checks"=>[], ...}`); symbol-keyed nested hashes also made unit-level assertions ambiguous.
- **Fix:** `data = {'has_run' => true}.merge(JSON.parse(JSON.generate(payload)))` — the cached hash is defined AS its JSON shape; the served envelope is unchanged either way.
- **Files:** lib/spm_cache/web/read_models/doctor.rb
- **Commit:** 2e1f68f

**3. [Plan-count gap] web_graph_spec needed an 8th example**
- **Found during:** Task 2 acceptance check
- **Issue:** The plan's listed graph cases produce 7 examples against a "≥ 8" acceptance bar.
- **Fix:** Added the no-memoization example (deleting graph.json flips present back to false between two calls) — it also directly serves the freshness prohibition.
- **Files:** spec/web_graph_spec.rb
- **Commit:** 8c2fdf4

### Planned-but-different
- `?run=` truthiness is implemented as "param present" (`!req.query['run'].nil?`), the Ruby-truthy reading of "any ?run= value truthy"; the spec pins `?run=1`, the Run Doctor button's form.
- During Task 3 GREEN the edit tool's stale-snapshot recovery twice mangled router.rb hunks; the file was repaired by a full rewrite and re-verified — the final router is byte-reviewed and all web specs pass against it.

## Threat Flags

| Flag | File | Description |
|------|------|-------------|
| none | — | No security-relevant surface beyond the plan's threat_model. All mitigations shipped as planned: T-13-09 (every new /api/* arm token-gated; 401 examples per endpoint), T-13-10 (Mutex around the atomic {data, generated_at} swap, proven by the thread-pair spec), T-13-11 (state/graph re-read per request — freshness specs; doctor stamp passed through verbatim), T-13-12 (only run:true executes checks). |

## Known Stubs

None. All three read models derive from real files/registry with no placeholders.

## Verification

- Plan's read-model specs: **35 examples, 0 failures** (`bundle exec rspec spec/web_state_spec.rb spec/web_graph_spec.rb spec/web_doctor_spec.rb`)
- CLI refactor + config specs: **70 examples, 0 failures** (`bundle exec rspec spec/command_cache_list_spec.rb spec/doctor_spec.rb spec/config_spec.rb`)
- Full suite: **683 examples, 0 failures, 1 pending** — the single pending lives in sibling 13-03's `spec/web_frontend_spec.rb` (not this plan's files; this plan's six spec files: 102 examples, 0 failures, 0 pending)
- Structural greps: `Inventory.scan` has exactly two production call sites (command/cache/list.rb:17, web/read_models/state.rb:16); `def payload` at core/diagnostics.rb:53
- End-to-end CLI smoke (beyond specs): real `bundle exec bin/spm-cache cache list` prints the exact pre-refactor document against the live cache; `doctor --json` prints the shared payload shape via the delegation

## Self-Check: PASSED

All 7 created files exist on disk; all 6 plan commits (2cd459c, 9a911a4, 9907517, 8c2fdf4, 582c28d, 2e1f68f) present in history on gsd/v0.5.0-web-interface.
