---
phase: 13-server-skeleton-read-only-dashboard
plan: 01
subsystem: web
tags: [web, webrick, security-middleware, lifecycle, tracer]

requires:
  - phase: 12-run-log-capture-foundation
    provides: run-log tee with web-verb exclusion (main.rb), .spm-cache/ runs-dir conventions, pid-liveness precedent
provides:
  - Web::Server (WEBrick adapter, 127.0.0.1-only, port-0 pre-resolution, AccessLog disabled, single catch-all servlet mount, StartCallback seam, trap-safe shutdown)
  - Web::Router (single-gate dispatcher: Host/Origin allowlist on every verb+path, token on /api/*, bootstrap 302, {status,data,generated_at} envelope, /assets/* arm)
  - Web::Middleware (pure predicates: allowed_host?/allowed_origin?/valid_token? with digest-then-XOR fixed-time compare)
  - Web::Marker (.spm-cache/web/server.json, 0600 atomic Tempfile+rename, symlink-rejecting read, pid-liveness)
  - Web::PortProber (upward probe from 7915, SKIP_PORTS [5000,7000], probe socket closed before return)
  - Web::Assets (validated-basename static resolver + content types, default root lib/spm_cache/web/assets)
  - Command::Web (`spm-cache web`: --port/--no-open, marker relaunch, signals, health-before-open browser launch, boot_with_retry)
  - Config#web_dir + dev .gitignore .spm-cache/ entry
  - webrick >= 1.8, < 2 runtime dependency (research CP8 verdict)
affects:
  - 13-02 (read models mount behind Router's read_models callables; envelope helper reused)
  - 13-03 (frontend assets served by Web::Assets through the already-wired Router arm)
  - 13-04 (cross-route matrix asserts against Router/Middleware as shipped)
  - 15 (mutating POSTs inherit the method-agnostic gate)

actuals:
  tokens: 17149   # chars/4 over the realized diff (68595 added chars); plan estimated 48000 at confidence low
  tasks: 3
  commits: 6

tech-stack:
  added:
    - "webrick >= 1.8, < 2 (the milestone's single sanctioned runtime dep; 1.9.2 installed)"
  patterns:
    - "Single catch-all servlet: middleware uniformity is structural (mount('/', adapter) routes every HTTP method through Router#service; ProcHandler was rejected — it covers only GET/POST/PUT)"
    - "Expected rejections set status+body directly instead of raising WEBrick status errors (httpserver.rb logs raised 4xx at ERROR level)"
    - "WEBrick option names verified against the installed 1.9.2 source (StartCallback after bind before accept; AccessLog default records ?token= URLs; GenericServer#shutdown is pipe-write, trap-safe)"
    - "Solved-by-construction liveness: WEBrick absolutizes relative Location (httpresponse.rb:318-321) — the bootstrap redirect is pinned as the same-origin absolute URL"
    - "Unique per-file child-script constants (WEB_CHILD_SCRIPT) — same-named top-level CHILD_SCRIPT constants across spec files silently cross-wire subprocess specs"

key-files:
  created:
    - lib/spm_cache/web/server.rb
    - lib/spm_cache/web/router.rb
    - lib/spm_cache/web/middleware.rb
    - lib/spm_cache/web/marker.rb
    - lib/spm_cache/web/port_prober.rb
    - lib/spm_cache/web/assets.rb
    - lib/spm_cache/command/web.rb
    - spec/web_middleware_spec.rb
    - spec/web_server_spec.rb
    - spec/web_lifecycle_spec.rb
    - spec/web_assets_spec.rb
    - spec/web_signals_spec.rb
    - spec/support/web_server_boot.rb
  modified:
    - spm_cache.gemspec
    - Gemfile.lock
    - lib/spm_cache/core/config.rb
    - .gitignore

key-decisions:
  - "Route/auth matrix as shipped: Host allowlist + Origin-if-present allowlist on ALL routes (403); token (X-SPM-Token or ?token) on ALL /api/* (401); GET / without ?token 302-bootstraps; GET /?token= and /assets/* serve without token check (assets cannot send headers, carry zero project data — commented in Router citing 13-CONTEXT)"
  - "Router's /assets dispatch arm and the nil-tolerant assets: kwarg landed with Task 1's Router; Task 3 added only the Assets class, its annotation, and the real-boot wiring — no Router structural change was needed"
  - "fixed_time_equal? digests BOTH sides (equal length) then XOR-OR-folds byte pairs to a single zero check — exact and constant-work; only the expected (server-held) side may early-exit when absent"
  - "PortProber returns socket.addr[1] (the actually-bound port) so start_port 0 works for --port=0"
  - "boot_with_retry (BOOT_RETRIES=2) converts the plan's 'accepted ephemeral-reuse race' into a re-probe past the squatter"

requirements-completed: [WEB-01, WEB-02, WEB-03, WEB-04, DASH-03]

coverage:
  - id: WEB-01
    description: "127.0.0.1 bind (never hostname/0.0.0.0), ephemeral-port specs, AirPlay-skipping upward probe from 7915"
    verification:
      - kind: unit
        ref: "spec/web_server_spec.rb#binds explicitly to 127.0.0.1 on an ephemeral port and exposes #port"
        status: pass
      - kind: unit
        ref: "spec/web_lifecycle_spec.rb PortProber group (SKIP_PORTS/default, held-4999 exhaustion proving 5000 never bound, upward probe, range-naming error)"
        status: pass
  - id: WEB-02
    description: "Live marker reuse (no second server, no marker rewrite, bare URL only); dead/malformed/symlink markers heal"
    verification:
      - kind: unit
        ref: "spec/web_lifecycle_spec.rb#prints the running URL, reuses, and never constructs a server"
        status: pass
      - kind: unit
        ref: "spec/web_lifecycle_spec.rb Marker group (0600 atomic write, symlink read/write behavior, live/dead/unparseable pid)"
        status: pass
  - id: WEB-03
    description: "SIGTERM/SIGINT to a real spawned spm-cache web stop the server, remove the marker, exit 0; SIGKILL leaves an honest stale marker"
    verification:
      - kind: integration
        ref: "spec/web_signals_spec.rb (3 real-subprocess examples)"
        status: pass
      - kind: unit
        ref: "spec/web_lifecycle_spec.rb#installs TERM/INT traps that call shutdown, then masks them during cleanup"
        status: pass
  - id: WEB-04
    description: "Host allowlist + Origin-if-present allowlist on every route (403), token on every /api/* route (401), bootstrap 302; access log disabled, marker 0600, token never printed"
    verification:
      - kind: unit
        ref: "spec/web_middleware_spec.rb (full predicate matrix incl. fixed-time-compare length case)"
        status: pass
      - kind: unit
        ref: "spec/web_server_spec.rb reject matrix (API + non-API + assets routes, method-agnostic POST gate, X-Frame-Options/no-store, no-log/token assertions)"
        status: pass
  - id: DASH-03
    description: "GET /api/graph returns the {status,data,generated_at} envelope with nodes from graph.json (present/generated_at semantics, malformed 500 envelope)"
    verification:
      - kind: unit
        ref: "spec/web_server_spec.rb /api/graph envelope group"
        status: pass

duration: 105min
completed: 2026-09-01
status: complete
---

# Phase 13 Plan 01: WEBrick server skeleton + security middleware + `spm-cache web` lifecycle Summary

**Tracer slice shipped end-to-end: `spm-cache web` boots a 127.0.0.1-only WEBrick server behind one structural Host/Origin/token gate, bootstraps the per-launch token via 302, serves the {status,data,generated_at} graph envelope, survives idempotent relaunch, and exits 0 on TERM/INT with the marker cleared — webrick added as the milestone's single runtime dep; full suite 608 examples green (536 baseline + 72 new).**

## Performance

- **Duration:** ~105 min
- **Tasks:** 3 (each RED-then-GREEN, 6 commits)
- **Files:** 17 changed (13 created, 4 modified), 68,595 added chars

## What Shipped vs Plan

### Task 1 — Web::Server + Web::Middleware + Web::Router (RED db743c3 → GREEN e726cd4)
As planned: gemspec webrick `>= 1.8, "< 2"` + bundle install (1.9.2); pure Middleware predicates with digest-then-XOR-fold token compare; Server with lazy webrick require (LoadError → install-hint GeneralError), port-0 TCPServer bind-read-close resolution, `AccessLog: []` with the token-leak rationale, DoNotReverseLookup, exactly ONE servlet at `/`; Router with the pinned route/auth matrix and the ok/error envelope helpers; the inline graph reader over `Cache::Cachemap#depgraph_for_viz`. All WEBrick option names/behaviors verified against the installed 1.9.2 source, not memory.

### Task 2 — Marker + PortProber + Config#web_dir + Command::Web (RED 0906f42 → GREEN af63c0a)
As planned: 0600 atomic marker (chmod before rename; rename replaces planted symlinks), lstat-rejecting read, run_log-cited pid liveness; SKIP_PORTS probe; web_dir sibling of runs_dir with the outside-sandbox rationale; the CLAide verb with --port Integer coercion, --no-open, reuse/stale/serve/signal lifecycle, StartCallback browser open degraded to warn; dev .gitignore `.spm-cache/` entry.

### Task 3 — Assets + signal contract (RED 5b4bbe7 → GREEN 5b214d4)
As planned: validated-basename Assets + content types, encoded/raw traversal 404s through the real server, Host-gated asset route, three real-subprocess WEB-03 examples (TERM/INT exit-0 + marker removed; SIGKILL honest stale). Router's asset arm already existed from Task 1 (only annotation + real-boot wiring added).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Bootstrap redirect Location arrives absolutized**
- **Found during:** Task 1 GREEN
- **Issue:** The plan pins `Location "/?token=<t>"`; WEBrick unconditionally merges relative Location against the request URI (httpresponse.rb:318-321, verified in source).
- **Fix:** Spec pins the same-origin absolute URL `http://127.0.0.1:<port>/?token=<exact token>` — identical browser behavior, strictly stronger origin pin.
- **Files:** spec/web_server_spec.rb
- **Commit:** e726cd4

**2. [Rule 1 - Bug] Malformed-graph message pin relaxed to non-empty String**
- **Found during:** Task 1 GREEN
- **Issue:** json 2.20's ParserError wording ("expected object key, got 'not' at line 1 column 2") does not contain the raw snippet; wording varies across json versions.
- **Fix:** Envelope shape + `data.keys == ['message']` + non-empty message (the raised message, verbatim) — version-independent.
- **Files:** spec/web_server_spec.rb
- **Commit:** e726cd4

**3. [Rule 1 - Bug] PortProber leaked its probe socket**
- **Found during:** Task 3 RED (the plan's own signal spec caught it)
- **Issue:** pick returned the port without closing the probe TCPServer, so WEBrick deterministically collided with our own held socket — every real `web --port=0` boot died with EADDRINUSE (100% repro; the plan's "try → close → return" was missing the close).
- **Fix:** read `addr[1]`, close, then return. Plus the RED run also surfaced the missing `require 'socket'` (masked in-process by other specs requiring it).
- **Files:** lib/spm_cache/web/port_prober.rb
- **Commits:** 5b4bbe7 (RED evidence), 5b214d4

**4. [Rule 1 - Robustness] boot_with_retry added beyond the plan**
- **Found during:** Task 3 (diagnosing #3)
- **Fix:** Command::Web re-probes (BOOT_RETRIES=2) on Errno::EADDRINUSE around probe+construct, converting the plan's "accepted ephemeral-reuse race" into a graceful move-past-the-squatter; spec pins the retry.
- **Files:** lib/spm_cache/command/web.rb, spec/web_lifecycle_spec.rb
- **Commit:** 5b214d4

**5. [Rule 1 - Bug] Spec constant collision broke watch_signals in combined runs**
- **Found during:** full-suite verification
- **Issue:** web_signals_spec.rb defined a top-level `CHILD_SCRIPT`, silently replacing watch_signals_spec.rb's once both files loaded — each spec's children ran the other's script (watch children booted web servers; web children crashed on `Float(ARGV[2])`).
- **Fix:** Renamed to `WEB_CHILD_SCRIPT` with a comment documenting the hazard.
- **Files:** spec/web_signals_spec.rb
- **Commit:** 5b214d4

**6. [Rule 3 - Blocking] Command::Web wires Web::Assets in Task 3 (file outside the task's list)**
- **Issue:** Task 3's read_first notes "Router constructor takes assets:" — but the only constructor caller is build_server; without wiring it there the real CLI 404s every asset and Plan 13-03's frontend would be dead through `spm-cache web`.
- **Fix:** `assets: ::SPMCache::Web::Assets.new` in build_server (+ require).
- **Files:** lib/spm_cache/command/web.rb
- **Commit:** 5b214d4

### Planned-but-different
- Bare dot-segment paths (`/assets/..`) collapse to `/` in the HTTP layer pre-dispatch (observed, not constructed); they land on the bootstrap redirect and never touch the filesystem. The spec pins "never 200" for those and exact 404s for every traversal form carrying a target.

## Threat Flags

| Flag | File | Description |
|------|------|-------------|
| none | — | No security-relevant surface beyond the plan's threat_model. All mitigations shipped as planned: T-13-01/02 (gate), T-13-03 (AccessLog disabled, 0600 marker, bare URLs, no-store, web-verb run-log exclusion untouched), T-13-04 (basename validation + containment, encoded forms proven), T-13-05 (rename-not-through-symlink, lstat read), T-13-06 (fixed-time compare), T-13-07 (DENY). T-13-08 accepted as planned. |

## Known Stubs

None. The deliberate tracer gap (GET /?token= → 404 until index.html exists) is the plan's own boundary: Plan 13-03 lands the real assets in `lib/spm_cache/web/assets/`, which the Router/Assets path already serves — verified with fixture files in web_assets_spec.rb.

## Verification

- Plan's five spec files: **75 examples, 0 failures** (`bundle exec rspec spec/web_middleware_spec.rb spec/web_server_spec.rb spec/web_lifecycle_spec.rb spec/web_assets_spec.rb spec/web_signals_spec.rb`)
- Full suite: **608 examples, 0 failures** (536 pre-existing green at baseline, all still green)
- CP8 smoke: `bundle exec ruby -e "require 'webrick'"` → 1.9.2
- Structural greps: webrick runtime dep (gemspec:40), `def web_dir` (config.rb:126), disabled AccessLog with rationale (server.rb:33)
- End-to-end CLI smoke (beyond specs): a real `spm-cache web --no-open --port=0` child → marker written; `GET /` → 302 with token; `GET /api/graph` (X-SPM-Token) → ok envelope; SIGTERM → exit 0, marker removed

## Self-Check: PASSED

All 13 created files exist on disk; all 6 plan commits (db743c3, e726cd4, 0906f42, af63c0a, 5b4bbe7, 5b214d4) present in history on gsd/v0.5.0-web-interface; ROADMAP plan progress updated (1/4, wave 1 complete).
