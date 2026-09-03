# Phase 13: Server Skeleton + Read-Only Dashboard - Context

**Gathered:** 2026-09-01
**Status:** Ready for planning

<domain>
## Phase Boundary

`spm-cache web` starts a localhost-only WEBrick server (the milestone's single sanctioned new runtime dependency) serving a fully-offline read-only dashboard: cache-state table (per-package size, cached/source state, fidelity status), doctor health panel (on-demand, registry-driven), and dependency-graph panel (nodes only — edges deferred pending Swift spike). Hardened against localhost drive-by requests (Host/Origin + per-launch token on every route) BEFORE any mutating endpoint exists (Phase 15). Re-running while live reuses the instance; SIGTERM/SIGINT exits cleanly. The server is a stateless file reader — never a second source of truth; the build flock stays the only mutex.

Excludes: live log streaming/SSE (Phase 14), build/rollback controls (Phase 15), package toggles (Phase 16), graph edges (needs Swift spike, WEB2-01 deferred).

</domain>

<decisions>
## Implementation Decisions

### Launch & Port Behavior
- Default port 7915, probe upward on collision, always skipping AirPlay's 5000/7000
- Foreground process, Ctrl-C to stop (watch-like mental model)
- Auto-open browser on fresh start; `--no-open` flag suppresses (mirrors `--no-ansi` precedent)
- Marker file `.spm-cache/web/server.json` (pid, port, token; 0600; sibling of runs dir — already gitignored)

### Token & Security Middleware (WEB-04)
- Token delivery: bootstrap GET / redirects to `/?token=<t>`; token held in sessionStorage, sent as `X-SPM-Token` header on every API call
- Origin check: reject requests whose Origin is present and ≠ `http://127.0.0.1:PORT`/`http://localhost:PORT`; absent Origin (same-nav/curl) allowed with valid token
- Middleware gates ALL routes uniformly from day one (reads leak project metadata; gate exists before Phase 15 POSTs)
- Token: `SecureRandom.hex(32)` per server launch, stored in marker file, rotated every launch

### Frontend Architecture (offline constraint)
- Hand-written static assets served from `lib/spm_cache/web/assets/` (index.html, app.js, styles.css, vendored cytoscape.min.js) — zero build step, zero CDN; gemspec glob extended to ship the dir
- Vanilla ES modules, no framework (~300–400 LOC JS)
- Refresh: manual Refresh per panel + auto-poll state table every 5s (configurable); doctor on-demand only, cached server-side with timestamp (DASH-02)
- Single hand-rolled CSS, dark-first, system font stack, status colors reuse doctor's :ok/:warn/:fail vocabulary (cachemap-viz precedent)

### API & Read-Model Shape
- Endpoints: `GET /api/state`, `GET /api/doctor`, `GET /api/graph`; JSON envelope `{status, data, generated_at}`; no versioning (same-launch client/server)
- State derivation reuses the CLI's own read path (Core::Lockfile, cache-dir scan, provenance sidecars, Diagnostics) — server never maintains its own store
- Doctor runs synchronously in-request from the check registry; result cached in memory with generated_at
- Graph panel empty-state names the generating command (`spm-cache use`) with a Refresh affordance when graph.json is absent

### Claude's Discretion
- Internal module layout under lib/spm_cache/web/ (server, middleware, read-models, asset routing)
- WEBrick handler decomposition and mounting details
- Exact CSS structure and DOM layout within the dark-first/system-font/status-color constraints
- Port-probe loop implementation (bounded retries, error surface)

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Core::Config` (singleton paths: sandbox, cache_dir, runs_dir — add web marker dir), `Core::Sh`, `Core::UI`
- `Core::Diagnostics` check registry (doctor's data-driven checks — DASH-02 requires registry iteration, no hard-coding)
- `Core::Lockfile` + `SPM::BuildPipeline` provenance/`BinariesCache` readers for cache-state derivation
- `Command::Watch` signal contract (SIGTERM/SIGINT → cleanup → exit 0) and marker/pid-liveness precedent (WEB-02/WEB-03 mirror it)
- `Installer#gen_cachemap_viz` — existing offline HTML+viz precedent (vendored assets, no CDN)
- Phase 12 `Core::RunLog` runs-dir conventions (`.spm-cache/` root, 0600 files)

### Established Patterns
- CLAide subcommands under `lib/spm_cache/command/` with BaseOptions; `web` verb already excluded from run-log capture by name (Phase 12 D-08 — load-bearing here)
- Shell-out only via `Core::Sh`; errors as `Core::GeneralError`; `Core::UI.section` for banners
- Frozen-string-literal + RuboCop enforced; specs hermetic via StringIO/tmpdir seams (doctor_spec precedent)

### Integration Points
- New `Command::Web < Command` (self.command = "web"); Main.run's pre_scan already skips run-log for the `web` verb
- `lib/spm_cache/web/` module tree (server, middleware, read models, asset router) loaded by `Main.load_all`
- gemspec `spec.files` glob must include `lib/spm_cache/web/assets/**` (tarball ships assets)
- `.spm-cache/web/` runtime dir (marker file), gitignored via the Phase 12 `.spm-cache/` entry

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches within the accepted decisions.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>
