# Phase 15: UI Build Controls - Research

**Researched:** 2026-09-02
**Domain:** CLI-subprocess spawning from a WEBrick server (pgroup/detach lifecycle), CLI-side rollback locking, run-log trigger attribution, single-slot mutation routes, and dashboard controls wiring
**Confidence:** HIGH — every integration seam re-read at file:line this session; the load-bearing process semantics (pgroup == child pid, group-kill reach, detach reaping, orphan survival across server death, WEBrick shutdown exit-0 with an in-flight build, explicit-env spawn of the real CLI) **machine-probed live on this machine** (PROBED marks below)

## Summary

Phase 15 makes the dashboard a mutation surface: two build controls and a rollback control that spawn the REAL `spm-cache` CLI as a detached, own-process-group child whose output reaches the browser through the Phase-14 stream (the child writes its own run log; the server never pipes it). The research settles the six genuine unknowns:

1. **Spawn mechanics** — spawn `[RbConfig.ruby, <bin>, verb, *flags]` (array argv, never a shell) with `chdir:` = `Core::Config.instance.project_dir`, explicit env carrying the trigger marker, `pgroup: true` + `Process.detach`. PROBED: pgid == child pid; group-kill reaches descendants; the detach reaper reaps within ~50 ms; the orphan survives server TERM with **exit 0 in 18 ms** (WEB-03 intact); `server.shutdown` does NOT wait on the build. The child writes its own `run_end` (even on raised failure — probed), so the slot learns "ended" from disk, never from a waitpid.
2. **Rollback lock (BLD-04/CP4)** — the fix lands inside `Installer::Rollback#perform_install` (installer/rollback.rb:9-12, currently lock-free), mirroring `acquire_build_lock`'s probe→announce→block shape (installer/build.rb:76-92) with ensure-release (build.rb:97-102). `perform_install` touches ONLY the sandbox `rm_rf` (rollback.rb:18-22) — no xcodeproj edits, no lockfile writes — so the lock wraps a small critical section. Web inherits the fix by spawning the CLI (D-07).
3. **UI-origin marker (D-03)** — the seam is one line: `main.rb:26` hard-codes `trigger: 'terminal'`; the spawned child's env carries `SPM_CACHE_TRIGGER=ui` and Main.run normalizes it. `pre_scan` (run_log.rb:78-105) is argv-only and needs no change; the header CONTRACT (`trigger` field, run_log.rb:137) is already rendered verbatim by 14's D-11 machinery. Scope (`rebuild`) must ride argv, not env, so the identity card's argv row self-documents (UI-SPEC A8) and terminal users get the same verb.
4. **Slot + routes (D-05/D-04)** — a mutex-guarded single-slot collaborator (constructed in `Command::Web#build_server`, web.rb:116-128, injected into the Router like `@events`); `POST /api/build` + `POST /api/rollback` join `dispatch` (router.rb:90-112) behind the EXISTING Host/Origin/token gate (server.rb:87-97 passes every verb through the catch-all servlet — the POSTs inherit it structurally). 409 = the standard error envelope with a machine-readable reason. Recommend including a `lock:` snapshot (reuse `Runs.lock_state`, runs.rb:113-122) in the 2xx envelope per UI-SPEC's waiting-flavor rule. WEBrick is thread-per-connection: the slot's check-then-claim MUST be mutex-atomic (double-click double-POST is a real race).
5. **Frontend** — extend app.js's `request()` (app.js:70-86) with a POST variant that returns the HTTP status (409 must be branchable — the thrown-Error shape hides it); controls row in `#log-body` (index.html:29); `log.js` publishes the sanctioned `spm-run-progress` CustomEvent from exactly three existing code points: `appendBody` (waiting/active — log.js:535-546) and `onRunEnd` (ended — log.js:548-556). Zero new streaming plumbing.
6. **Validation** — RSpec rows cover the slot/route/lock/marker units plus ONE integration row (spawn a fake-bin build, assert server exits 0 with it in flight); the agent-browser probe net (14's D-14 pattern) covers the click→badge→stream→409→confirm-bar flows. Seeded in `15-VALIDATION.md`.

**Primary recommendation:** one `Web::Jobs`-shaped singleton (pid + Mutex + derive-based liveness), two POST routes reusing the existing gate and envelope, the BLD-04 lock inside `Installer::Rollback#perform_install`, the trigger marker via child env normalized at `main.rb:26`, and the frontend's only new machinery the POST helper + the three-point CustomEvent emission.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions (D-01..D-09, 15-CONTEXT.md — abbreviated; verbatim in the source doc)
- **D-01:** verb-level scope: `Build` (exactly `spm-cache build` semantics, missed-only) and `Rebuild all` (forced rebuild scope). No per-package picker (Phase 16).
- **D-02:** POST endpoint spawns the REAL CLI (`bin/spm-cache build|rollback`) via `Process.spawn`, ARRAY argv, `pgroup: true`; server never the build's parent signal-wise; stopping the server must NOT kill an in-flight build; killing a build targets the GROUP. CP14's pgroup mechanics land here. (Costly to change.)
- **D-03:** every UI-spawned run records `trigger: 'ui'` in its run_start header (LOGS-05 vocabulary). Mechanism (flag vs env) is researcher/planner territory; the CONTRACT is the header value. Zero frontend badge work (14 D-11 renders verbatim).
- **D-04:** NO second token. POSTs ride the SAME per-launch token via `X-SPM-Token`, behind the SAME Host/Origin-if-present middleware. Token stays out of logs.
- **D-05:** exactly ONE UI build at a time, enforced SERVER-side; second concurrent POST → HTTP 409 with a machine-readable reason; UI renders the busy message INLINE (never alert(), never a silent queue); button disables while held.
- **D-06:** busy/waiting derived from the BUILD LOCK via existing surfaces (the in-stream announce line + `lock.state: 'held'` already in hello//api/runs). No separate polling channel; server stays a stateless reader.
- **D-07:** Rollback spawns the REAL `spm-cache rollback` subprocess (same pgroup mechanics); BLD-04's lock fix lands in the CLI itself; web never re-implements rollback. (Costly — changes rollback's concurrency contract for ALL callers.)
- **D-08:** rollback confirm = two-step INLINE bar ("Restore source mode — this removes proxy packages from the Xcode project" + Confirm/Cancel). No native dialogs.
- **D-09:** one stream: UI-spawned builds ride the existing /api/events SSE + switch/auto-switch + banner chain. No second websocket, no POST-response streaming.

### Claude's Discretion (15-CONTEXT)
Exact endpoint paths, envelope shapes, spawn-slot data structure, stop control (SC text does not require one; if added it must use the pgroup), and the UI-origin marker mechanism (flag vs env). 15-UI-SPEC (approved) additionally pins: working paths `POST /api/build` `{"scope":"build"|"rebuild"}` and `POST /api/rollback` (empty body), the single slot SHARED by build and rollback (A1), waiting flavor derived lock-first with the announce line as the honest signal (A2), no global lock indicator (A3), `ui` lowercase (A4), confirm focus lands on Cancel (A6), 409 reason never displayed (A9).

### Deferred Ideas (OUT OF SCOPE)
None. Stop/cancel control is WEB2-02 (deferred; the pgroup mechanism lands now so a future stop is possible). Per-package scope = Phase 16.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| BLD-01 | Build/Rebuild spawns real CLI (array argv, pgroup), streams output; second concurrent UI build rejected (single slot) | Spawn pattern + PROBED pgroup/detach semantics (§Q1); slot Mutex + 409 envelope (§Q4); output arrives via the child's OWN run-log tee + 14's tailer — no server-side piping (§Q1) |
| BLD-02 | Busy/waiting state derived from the build lock visible in the UI | In-stream announce line already lands in the run's JSONL (build.rb:87-89, use.rb:81-83); `lock.state` already in hello (events.rb:366-379) and /api/runs (runs.rb:113-122); recommend a `lock:` snapshot in the POST 2xx envelope (§Q4) |
| BLD-03 | Build failures surface with exit status and highlighted errors | PROBED: child writes `run_end` `status` even on raised failure (exit path <1 s); 14's banner chain (log.js onRunEnd 548-556 → showBanner 394) consumes it unchanged; err lines carry `stream: 'err'` (appendBody 535-546) |
| BLD-04 | Rollback restores source mode; rollback acquires the build lock (closes the lock-free race) | Lock inside `Installer::Rollback#perform_install` mirroring build.rb:76-92 + ensure-release build.rb:97-102; critical section is the sandbox `rm_rf` only (rollback.rb:18-22); spec-first shape per installer_lock_notice_spec conventions (§Q2) |
</phase_requirements>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Spawn the real CLI (argv, cwd, env, pgroup, detach) | API/backend (`Web::Jobs` singleton behind the Router) | — | The server is a "CLI-subprocess spawner" (PROJECT constraint); Core::Sh is NOT used — the child is fully detached, its output goes to its own run log |
| Run-log writing for UI runs | CLI child process (`Main.run` tee) | `Core::RunLog` | Writer-agnostic transport: a UI run is just another `.jsonl` file; zero stream changes (D-09) |
| Trigger attribution ('ui') | CLI child (`main.rb` env normalization → `RunLog.open(trigger:)`) | Spawner (sets the env var) | Header is written by the process that owns the run; the spawner only plants the marker |
| Single-slot UI concurrency + 409 | API/backend (Mutex-guarded slot) | — | Server-side by D-05; the flock is NOT the slot (terminal builds must not 409 the UI — UI-SPEC A3) |
| POST auth (token/Host/Origin) | Existing middleware via Router.service (router.rb:65-78) | — | Structural: the catch-all servlet passes every verb through the gate (server.rb:87-97) |
| Build-lock waiting/failure display | CLI child (announce line, run_end) + 14 frontend | — | Lock-derived (D-06), CP10-honest; the row consumes stream facts, never server memory |
| Controls row / confirm bar UI | Frontend (`app.js` + `index.html` + `styles.css`; `log.js` CustomEvent only) | — | UI-SPEC files contract: no new asset file, no framework |

## Machine Probes (PROBED — this machine, Ruby 3.2.3 rbenv, 2026-09-02)

| # | Probe | Result |
|---|-------|--------|
| P1 | `Process.spawn(..., pgroup: true)` → `Process.getpgid(child)` | pgid == child pid (child is group leader) |
| P2 | `Process.kill('-TERM', pgid)` on a child that spawned its own grandchild | Group leader died; grandchild died (became zombie `Z` ≥4 s — nobody reaps an orphaned zombie promptly on macOS; `kill(0)` reports zombies as ALIVE) |
| P3 | `Process.detach` + child exit, parent ALIVE | `Process.kill(0, pid)` flipped to `Errno::ESRCH` in **~51 ms** (detach's reaper thread) — no lingering zombie in the server-slot scenario |
| P4 | Parent spawns detached pgroup child, then parent's whole foreground group gets SIGINT | Parent exited 0; **child survived** (own group ⇒ terminal Ctrl-C on `spm-cache web` cannot kill an in-flight build — D-02 verified mechanically) |
| P5 | WEBrick server (web.rb:83 trap shape) with an in-flight detached pgroup child; TERM | `server.shutdown` **exit 0 in 18 ms**; child still running afterwards — shutdown does NOT wait on, reap, or kill the detached build (WEB-03 + D-02 both hold) |
| P6 | Spawn the REAL CLI `[RbConfig.ruby, bin/spm-cache, build, --log-dir=…]` in a scratch dir (no .xcodeproj) | Exit 1 fast; `run_start` header (command/argv/pid/trigger) + `run_end status:1` both landed <1 s — the BLD-03 failure path is fully exerciseable without xcodebuild |
| P7 | Same real-CLI spawn with EXPLICIT env `{"PATH","HOME","SPM_CACHE_TRIGGER"}` (no bundler vars), `out:/err: → File::NULL` | CLI booted (all gem requires OK on this machine's rbenv layout), failed fast, wrote header+run_end; nothing leaked to the parent's stdout. Header `trigger` is `'terminal'` today (main.rb:26 hard-code — the env seam is that one line) |
| P8 | `File.expand_path('../../../bin/spm-cache', __dir__)` from a file at `lib/spm_cache/web/` | Resolves to the repo bin, executable (`-rwx--x--x`); RubyGems' install layout (`<gem>/lib/spm_cache/web/` + `<gem>/bin/spm-cache`, gemspec `executables = ["spm-cache"]`) preserves the same relative shape [ASSUMED A1 for installed gems] |

## Research Question Verdicts

### Q1 — Spawn mechanics (D-02/CP14): spawn the real CLI, pgroup lifecycle, WEB-03 interplay

**Argv/cwd/env** [VERIFIED: lib/spm_cache/web/router.rb:41-63, lib/spm_cache/command/web.rb:116-128, lib/spm_cache/core/config.rb:38-52]:

```ruby
# lib/spm_cache/web/jobs.rb (sketch — planner pins names)
BIN_PATH = File.expand_path('../../../bin/spm-cache', __dir__) # PROBED P8

def spawn_run(verb_argv) # e.g. ['build'] or ['build', '--rebuild'] or ['rollback']
  env = ENV.to_h.merge('SPM_CACHE_TRIGGER' => 'ui')   # §Q3; see env note below
  pid = Process.spawn(env, RbConfig.ruby, BIN_PATH, *verb_argv,
                      chdir: @config.project_dir,     # config.rb:41; child's find_project globs *.xcodeproj in cwd
                      out: File::NULL, err: File::NULL, # child's tee owns the log; web terminal stays quiet (T-13-03 spirit)
                      pgroup: true)                   # CP14/D-02: own group ⇒ group-kill capable (WEB2-02), Ctrl-C-immune (P4)
  Process.detach(pid)                                 # reaper thread (P3: ~51 ms); server NEVER waits (P5)
  pid
end
```

- **Why `[RbConfig.ruby, BIN_PATH, …]` and not PATH/Gem.bin_path:** PROBED P8 — relative resolution works from the web module's depth in both repo and gem layout, and pinning the interpreter removes PATH-ruby ambiguity. `Gem.bin_path` would require the gem to be installed; `Dir.pwd`-relative paths break under any other cwd.
- **cwd:** `Core::Config.instance.project_dir` (set at Config instantiation from `Dir.pwd`, config.rb:41; `Config.configure(project_dir:)` at :50-52 is the spec seam). `Command::Build#find_project` and `Command::Rollback#find_project` glob `*.xcodeproj` in the child's cwd (command/build.rb:35, command/rollback.rb:24).
- **Env — merge, don't whitelist:** PROBED P7 proves a minimal `{PATH, HOME, +trigger}` boots the CLI on this machine, but a whitelist would silently drop `DEVELOPER_DIR`/`SDKROOT`/proxy-class vars that xcodebuild legitimately consumes. Recommend `ENV.to_h.merge('SPM_CACHE_TRIGGER' => 'ui')`: the child inherits the bundler context exactly like a terminal invocation (P6 proved that path), the token is never in env (web.rb:75 — token lives in the marker file and constructors, not ENV), and the marker is the only addition. The stricter CP12 "explicit env" whitelist remains a planner option; P7 is its evidence.
- **pgroup + detach lifecycle (all PROBED):** pgid == pid (P1) ⇒ `Process.kill(-pgid, sig)` is the future WEB2-02 stop mechanism; group-kill reaches the xcodebuild/swift tree because Core::Sh's popen3 grandchildren inherit the child's group (P2; note core/sh.rb:20-21 has no pgroup of its own — CP14 unchanged there, and unchanged by this phase). `Process.detach` starts a reaper thread ⇒ no zombie while the server lives (P3) and the server never blocks on the build.
- **WEB-03 interplay (PROBED P5):** `Server#shutdown` (web.rb:83-93 shape) with an in-flight detached build exits 0 in 18 ms — the child is not a WEBrick thread and nothing waits on it. Shutdown must NOT kill the group (D-02: stopping the server must not kill the build; no stop control ships). After server death the build runs on as a reparented orphan writing its run log; the restarted server re-derives everything from disk (CP10) and its slot is empty — a second UI POST then queues on the flock with the visible announce line. Honest, not a bug.
- **How the slot learns the run ENDED:** not via wait (detach discards status). The child writes its own `run_end` in Main.run's ensure (main.rb:52) — PROBED P6: lands even on raised failure, <1 s. Slot release options: (a) `Process.kill(0, pid)` liveness (probed ~51 ms false-alive window after exit, P3/P2 caveat); (b) strict: `Web::ReadModels::Runs.derive` on the newest run whose header pid == slot pid (runs.rb:51-81, 174-181 — `run_end` authoritative, `pid_alive?` fallback, CP14 'interrupted' honored). Either is CP10-honest; recommend (a) for the POST-time check (human-granularity clicks make 51 ms irrelevant) with (b) documented as the stricter variant. No monitoring thread.
- **Terminal parity:** the child's stdout/stderr → File::NULL; `TeeIO.write` still records every line into the run log (run_log.rb:444-448), and `tty?` false ⇒ CLAide emits no ANSI (run_log.rb:432-435 comment, TeeIO#tty? :469-471) — UI runs render clean text in the stream.

### Q2 — Rollback lock (BLD-04/CP4)

[VERIFIED: lib/spm_cache/command/rollback.rb:11-19, lib/spm_cache/installer/rollback.rb:9-22, lib/spm_cache/installer/build.rb:76-102, lib/spm_cache/installer/use.rb:70-90]

- **What rollback touches today:** `perform_install` = `restore_packages` (an info PRINT — rollback.rb:14-16) + `remove_proxy` (`FileUtils.rm_rf` of `@config.sandbox_dir`, :18-22). No xcodeproj edits, no lockfile/sandbox-meta writes; `project:` is stored but unused by the perform path. The lock therefore wraps a small critical section.
- **Where the lock goes:** inside `Installer::Rollback#perform_install`, wrapping both steps — NOT in `Command::Rollback` (would miss non-CLI callers of the installer) and NOT in the web layer (D-07: web inherits the fix by spawning the CLI, never re-implements rollback). Shape = `acquire_build_lock` (build.rb:76-92): mkdir_p the lock dir, `File.open(path, File::CREAT | File::RDWR)`, `flock(LOCK_EX | LOCK_NB)` probe → `Core::UI.info 'Waiting for build lock…'` (byte-exact, BLD-02-frozen) → blocking `flock(LOCK_EX)`; `ensure` releases (`LOCK_UN` + close, build.rb:97-102). Terminal behavior unchanged except the contended-path announce — the same idiom build/use already shipped in 14.
- **Spec-first shape:** follow `spec/installer_lock_notice_spec.rb` conventions (manual `$stdout` swap with begin/ensure restore; thread-held real-OS flock for contention, :60-90; byte-exact pinned copy at :20) and `spec/build_lock_spec.rb`'s fork-based OS-lock proof. New spec rows: rollback acquires BEFORE the `rm_rf` (ordering assertion), releases on raise, announces exactly once only under contention, free-lock path byte-identical.
- **Dashboard consequence:** a UI-spawned rollback contending with a terminal build now streams its own "Waiting for build lock…" line (tee'd into ITS JSONL) — BLD-02's two-surfaces rule extends to rollback for free; the lock-snapshot in the POST response (§Q4) lights the row's waiting flavor immediately.

### Q3 — UI-origin marker (D-03)

[VERIFIED: lib/spm_cache/main.rb:19-27, lib/spm_cache/core/run_log.rb:78-105, 114, 128-139, 533-539]

- **The seam:** whole-run logs are opened ONLY in `Main.run` (main.rb:22-27) with the hard-coded kwarg `trigger: 'terminal'` (:26); `CycleWrapper` opens its own with `trigger: 'watch'` (run_log.rb:533-539). `pre_scan` (run_log.rb:78-105) routes verb/--log-dir/--no-run-log from raw argv and is NOT the trigger seam — do not touch it.
- **Recommendation: env marker, one-line diff.** Spawn env `SPM_CACHE_TRIGGER=ui` (§Q1) and normalize at main.rb:26:

```ruby
trigger: ENV['SPM_CACHE_TRIGGER'] == 'ui' ? 'ui' : 'terminal'  # LOGS-05 vocabulary; whitelist, not passthrough
```

  Flag alternative rejected: a CLAide flag needs declarations on build AND rollback (help/option surface changes, argv pollution), while the header contract (`trigger`, run_log.rb:137) is env-invisible and already rendered verbatim by 14's D-11 badge. PROBED P6/P7: the header shape today, and that explicit env reaches a spawned CLI.
- **Scope must ride argv, not env:** UI-SPEC A8 — "the card's argv row is how the user verifies which verb ran". `Rebuild all` therefore needs REAL CLI surface (e.g. a `--rebuild` flag on `Command::Build` — today it has only `--recursive`, build.rb:11-13 — flipping Installer::Build to rebuild the `@cachemap.hit` set as well, build.rb:27-28). That is new CLI surface and terminal-visible; mechanism is planner territory (A8), contract is D-01's "forced rebuild scope".
- **Pitfall:** the marker is attribution-only — never branch CLI behavior on `SPM_CACHE_TRIGGER` (any terminal user can set it; forgeable by design, harmless because nothing reads it for control flow).

### Q4 — Spawn slot + POST routes (D-05/D-04)

[VERIFIED: lib/spm_cache/web/router.rb:65-78, 90-112, 143-163, 240-262; lib/spm_cache/web/server.rb:87-97; lib/spm_cache/web/read_models/runs.rb:113-150]

- **Slot structure:** a singleton collaborator (injectable for specs, like `@events` — router.rb:57-62) holding `{pid, scope, armed_at}` under a `Mutex`. It is NOT the flock: a terminal build holding the lock must not 409 the UI (UI-SPEC A3); the slot guards ONLY UI-originated spawns (D-05). Build and rollback SHARE it (UI-SPEC A1).
- **WEBrick is thread-per-connection ⇒ two rapid POSTs run concurrently:** the check-then-claim must be atomic inside `@mutex.synchronize` — a double-click double-POST that races two `held?` checks yields two spawns. (Client-side disable is the first guard; the Mutex is the real one — cross-tab clicks bypass the client guard.)
- **Routes:** add `when '/api/build'` / `when '/api/rollback'` to `dispatch` (router.rb:90-112). Host/Origin already covered for every verb at `service` (:65-78), and the catch-all servlet funnels POSTs through it structurally (server.rb:87-97 — its comment anticipates exactly this phase). New `api_mutate`-shaped helper mirrors `api_read` (:143-163): `valid_token?` → 401; wrong verb → 404 (house convention, :147); then body validation.
- **Body validation (V5):** `req.body.read` + `JSON.parse` → 400 envelope on malformed; `scope` must be exactly `'build'` or `'rebuild'` (whitelist — never interpolate scope into argv); rollback accepts an empty/`{}` body. 409 = the standard error envelope (router.rb:259-262) with a machine-readable reason (e.g. `'reason' => 'slot_busy'`, planner pins) that the UI never displays (A9).
- **Lock snapshot in the 2xx envelope — recommended YES:** `data: { 'scope' => …, 'lock' => ReadModels::Runs.lock_state(config:) }` (runs.rb:113-122 — one reuse, derived per request, CP10-honest). UI-SPEC's waiting-flavor rule (:144) explicitly admits "the spawn POST's response envelope if the planner includes a lock snapshot"; including it lets the row show `Waiting for build lock…` the instant a terminal build holds the lock, without waiting for the next hello/runs poll.
- **Spawn failure** (Process.spawn raises, bin missing): 500 envelope → the frontend's pinned "Couldn't start the build: {message}…" template (UI-SPEC copy table).
- **Server restart mid-build:** slot is memory-only ⇒ free after restart while the orphaned build runs on (P5). Second UI POST then blocks on the flock with a visible announce line — accepted edge, consistent with CP10 (derive, never memory).

### Q5 — Frontend wiring (controls row, request layer, CustomEvent coupling, 14-review folds)

[VERIFIED: lib/spm_cache/web/assets/app.js:70-86, 304-317; lib/spm_cache/web/assets/log.js:535-556, 566-570; lib/spm_cache/web/assets/index.html:19-29, 100-102]

- **Controls row:** first children of `#log-body` (index.html:29) per the UI-SPEC layout contract — `#build-controls` + `#build-confirm` (hidden swap, the card/banner `hidden` pattern). Script tags exist (:100-102); no new asset file (UI-SPEC prohibition 1).
- **Request layer:** `request()` (app.js:70-86) is GET-shaped and THROWS on `!res.ok` — a 409 and a 500 are indistinguishable at the call site, and the busy copy must branch on 409 (UI-SPEC interaction contract). Add a POST variant returning `{ ok, status, envelope }` (or a typed error carrying `res.status`), keeping the 401/403 → token-invalid page behavior (:77-80) inherited for free. `X-SPM-Token` header only (D-04); body `{scope}` JSON.
- **`spm-run-progress` emission — exactly three existing code points in log.js:**
  - `appendBody` (log.js:535-546): the byte-exact `Waiting for build lock…` line (trailing `\n` already stripped at :537) ⇒ `detail.phase = 'waiting'`; ANY following body line ⇒ `'active'` (the Installer prints nothing while blocked, so a next line is proof the wait ended — UI-SPEC A2). Repeat emissions are idempotent for the listener.
  - `onRunEnd` (log.js:548-556): ⇒ `'ended'` (same facts that flip the card/banner — BLD-03 rides unchanged: non-zero ⇒ banner + ✓/✗, log.js:394 showBanner).
  - Emission is DISPLAYED-run-scoped (the sanctioned constraint, UI-SPEC :143): a pinned older run delays the in-flight run's milestones; the 409 backstop and reload are truth.
- **app.js listener:** `document.addEventListener('spm-run-progress', …)` maps waiting → `Waiting for build lock…`, active → the verb's baseline message (`Building…` / `Rebuilding all…` / `Restoring source mode…`), ended → idle (re-enable, clear message). Entry assist: freshest `hello`/`/api/runs` `lock.state: 'held'` (events.rb:366-379, runs.rb:113-122) or the POST response's lock snapshot (§Q4). No new timer/poll (prohibition 4) — the 5 s state poll (app.js:309-314) stays untouched and carries no controls state.
- **14-UI-REVIEW polish folds (candidates, same surface):**
  - **W1 (contrast AA — load-bearing for this phase):** white-on-`#2196F3` ≈ 3.1:1 FAILS AA (14-UI-REVIEW Pillar 2). TENSION: 15-UI-SPEC :72 pins "white text" on the new accent buttons. Folding W1 while authoring the controls CSS (`color: #0D1117` on accent fill ≈ 6.1:1, one declaration on the shared `.btn` rule, styles.css:129-134) repairs the 14 pills AND avoids shipping new controls on a flagged pair — but contradicts the spec's letter ⇒ needs a spec-first amendment or planner decision (Open Question 2).
  - **W3 (focus-preserving re-render):** the new confirm-bar swap already follows the `hidden` pattern; the fold is behavioral discipline (persistent nodes, toggle `hidden`, patch `textContent`) plus optionally repairing `renderPill`/`renderChips` (log.js:201-202, 484-487) — planner scope call.
  - **W4 (responsive breakpoint):** the row itself flex-wraps per UI-SPEC; the panel-wide `@media` stack for `.log-rail` is a separate decision (scope guard: BLD-01..04 exactly).
  - **W5 (`.log-switch` margin) + M1 (card row gap):** one-token CSS fixes on the same sheet; natural to fold into the controls CSS task.

### Q6 — Validation architecture

See `15-VALIDATION.md` (seeded). Split: RSpec units for slot/409/routes/rollback-lock/marker (hermetic, fake-bin injection — PROBED P6/P7 prove the real CLI needs no xcodebuild to exercise success/failure paths); ONE integration row extending `spec/web_integration_spec.rb` (POST end-to-end + server shutdown exit-0 with an in-flight fake build, boot harness `spec/support/web_server_boot.rb`); the D-14-pattern agent-browser probe for the click→badge→stream→409→confirm-bar flows (repo has no JS runtime; 14's net caught G-13-1 that 119 green examples missed).

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| (none new) | — | `Process.spawn` + `Process.detach` (stdlib core), `Mutex` (core), existing webrick 1.9.2, existing `Web::ReadModels::Runs` | Everything Phase 15 needs is stdlib or already shipped 12-14; gemspec unchanged |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `Process.spawn` + pgroup | `Open3`/`Core::Sh` | Both wait on pipes/children — defeats detach and WEB-03; Core::Sh's popen3 has no pgroup and would make the server the pipe-owner of build output (D-02 forbids) |
| env trigger marker | CLAide flag on build+rollback | Flag touches two option surfaces + help; env is one line at main.rb:26 and leaves argv clean |
| Slot release via monitoring thread | Lazy per-POST derive (recommended) | A thread adds lifecycle/shutdown surface for zero benefit at click granularity; CP10 favors derive-from-disk |
| Whitelist env | `ENV.to_h.merge` (recommended) | Whitelist drops `DEVELOPER_DIR`-class vars xcodebuild consumes; P7 proves the whitelist works but merge is the safe default |

**Installation:** nothing to install.

## Package Legitimacy Audit

> No external packages are installed by this phase — zero new gems, zero npm. Table intentionally empty.

| Package | Registry | Age | Downloads | Source Repo | Verdict | Disposition |
|---------|----------|-----|-----------|-------------|---------|-------------|
| (none) | — | — | — | — | — | — |

## Recommended Project Structure

```
lib/spm_cache/
├── main.rb                        # MOD: one line — trigger from ENV marker (main.rb:26)
├── command/build.rb               # MOD: --rebuild flag (A8 mechanism; planner pins) — new CLI surface
├── installer/rollback.rb          # MOD: probe→announce→block flock + ensure-release (BLD-04)
└── web/
    ├── jobs.rb                    # NEW: spawn (argv/env/chdir/pgroup/detach) + Mutex slot + 409 reason
    ├── router.rb                  # MOD: /api/build + /api/rollback dispatch + mutate helper
    └── assets/
        ├── index.html             # MOD: #build-controls + #build-confirm in #log-body
        ├── app.js                 # MOD: POST helper + controls state machine + spm-run-progress listener
        ├── log.js                 # MOD: 3-point CustomEvent emission (appendBody ×2, onRunEnd)
        └── styles.css             # MOD: controls section + W1/W5/M1 folds
spec/
├── web_jobs_spec.rb               # NEW: spawn shape, slot mutex atomicity, derive release, 409
├── web_build_routes_spec.rb       # NEW: token/verb/body/409/lock-snapshot matrix
├── installer_rollback_lock_spec.rb # NEW: order-before-rm_rf, release-on-raise, byte-exact announce
├── run_log_trigger_spec.rb        # NEW: env normalization → header trigger 'ui' (Main seam)
└── web_integration_spec.rb        # extend: POST row + shutdown-exit-0-with-in-flight-build (P5 as a spec)
```

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Run-end / liveness derivation | Custom pid math, /proc parsing, waitpid plumbing | `Runs.derive`/`status_for` (runs.rb:51-81, 174-181) + `pid_alive?` semantics (run_log.rb:403-410) | CP14-honest vocabulary already shipped; one derivation, zero drift with the card/dropdown |
| POST auth | Any new token scheme | `Middleware.valid_token?` via the existing gate (middleware.rb:46-50, router.rb:70-77) | Constant-time path; structurally un-bypassable (single servlet) |
| Lock wait | Polling/backoff around flock | The blocking-flock probe→announce→block shape (build.rb:76-92) | OS semantics ARE the mechanism; the announce line is already the BLD-02 surface |
| Busy-state source | New polling channel or server memory of lock state | hello//api/runs `lock.state` + in-stream announce + POST lock snapshot | D-06; server stays a stateless reader |
| Trigger badge | Any frontend work | 14's D-11 verbatim header rendering | D-03: zero new frontend code for the badge |

**Key insight:** Phase 15 adds almost no new mechanism — it wires the existing gate, envelope, stream, and lock idioms to one new spawn seam, and the CLI child does the rest (writes its own log, announces its own waits, reports its own exit).

## Runtime State Inventory

> Not a rename/refactor/migration phase — greenfield mutation surface. Category answers for completeness:
> **Stored data:** none new (the child writes run logs the way every CLI run already does; retention bounds the dir). **Live service config:** none. **OS-registered state:** none new — spawned builds are plain child processes, reparented to launchd on server death (P5), not registered anywhere. **Secrets/env vars:** `SPM_CACHE_TRIGGER` is the only new env var — attribution-only, non-secret; token never enters env or logs (web.rb:75, server.rb:30-34). **Build artifacts:** none affected.

## Common Pitfalls

### Pitfall 1: Unsynchronized slot check-then-claim (thread-per-connection race)
**What goes wrong:** two rapid POSTs (double-click, two tabs) both pass the `held?` check on different WEBrick request threads and BOTH spawn.
**Why it happens:** WEBrick serves connections on threads; check and claim are two steps unless forced to be one.
**How to avoid:** `@mutex.synchronize { return 409 if slot.held?; slot.claim(pid, scope) }` — atomic check-and-claim; client-side disable is UX, not the guard.
**Warning signs:** two `build` run logs with overlapping started_at from one double-click.

### Pitfall 2: Treating `kill(0, pid) == alive` as proof of life at the exit boundary
**What goes wrong:** a just-exited child can read "alive" — zombies answer `kill(0)` (P2: an orphaned zombie stayed `Z` ≥4 s; P3: the detached reaper closes the window to ~50 ms when the parent lives).
**How to avoid:** POST-granularity checks make ~50 ms irrelevant; if strictness is wanted, confirm via `Runs.derive` (run_end line authoritative — P6: lands <1 s even on failure).
**Warning signs:** a 409 persisting seconds after the log shows the run finished.

### Pitfall 3: Waiting on, or killing, the build during shutdown
**What goes wrong:** killing the group in `Server#shutdown` violates D-02 (server stop must not kill the build); waiting on it breaks WEB-03's exit-0.
**How to avoid:** do NOTHING about the child in shutdown — PROBED P5: shutdown exits 0 in 18 ms with the build in flight; the orphan writes its own run_end.
**Warning signs:** Ctrl-C on `spm-cache web` that also stops a running build; shutdown latency scaling with build duration.

### Pitfall 4: Child stdout/stderr inheritance
**What goes wrong:** without `out:/err:` redirection the build's output spews into the terminal running `spm-cache web` (T-13-03's quiet-terminal posture broken).
**How to avoid:** `out: File::NULL, err: File::NULL` (P7) — the child's tee still records everything (run_log.rb:444-448), `tty?` false suppresses ANSI.
**Warning signs:** xcodebuild chatter in the web terminal; ANSI codes in the browser stream.

### Pitfall 5: Shell-string spawn or scope interpolation
**What goes wrong:** `Process.spawn("bin/spm-cache #{scope}")` reintroduces shell injection and CP13's param-validation hazard.
**How to avoid:** array argv only (D-02); `scope` validated against the `{'build','rebuild'}` whitelist and mapped to FIXED argv fragments — never interpolated (V5).
**Warning signs:** any string concatenation reaching `Process.spawn`'s first argument.

### Pitfall 6: Lock acquired but not released on raise (rollback)
**What goes wrong:** a rollback that raises mid-`rm_rf` without ensure-release deadlocks every future build/use on the project.
**How to avoid:** the build.rb:97-102 ensure shape verbatim; spec asserts release-on-raise.
**Warning signs:** "Waiting for build lock…" forever after a failed rollback.

### Pitfall 7: Branching CLI behavior on the trigger marker
**What goes wrong:** `SPM_CACHE_TRIGGER` is forgeable by any terminal user; behavioral gating on it creates a privilege seam.
**How to avoid:** the env var feeds ONLY the header value (attribution); no verb reads it for control flow.
**Warning signs:** any `if ENV['SPM_CACHE_TRIGGER']` outside the main.rb:26 normalization.

### Pitfall 8: 409 indistinguishable from other failures in the frontend
**What goes wrong:** reusing `request()` (throws on `!res.ok`) means the busy path can't be told from a 500/network error — the busy message can't render reliably.
**How to avoid:** the POST helper returns the status (§Q5); UI-SPEC prohibition 8 keeps the server reason undisplayed.
**Warning signs:** "Couldn't start the build…" shown for a normal busy rejection.

## Anti-Patterns to Avoid

- **Second token or query-param token on POSTs** — D-04; the custom header is the whole design.
- **Server-side re-implementation of rollback** — D-07: spawn the CLI; the lock fix lives in the installer for ALL callers.
- **Polling `/api/build` for status or a second SSE channel** — D-09: the run IS a run-log file; the existing stream carries it.
- **Disabling buttons because the LOCK is held** — UI-SPEC A3: only the SLOT disables; a terminal-held lock leaves the buttons enabled (a click forms a visible queue).
- **alert()/confirm() for busy or destructive confirm** — D-05/D-08: inline message slot + confirm bar only.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | RubyGems' installed layout keeps `bin/spm-cache` at `<gem>/bin` ⇒ the `../../../bin` relative resolution survives gem install (P8 verified in-repo only) | Q1 | Installed-gem deployments would misresolve; mitigable with a `Gem.bin_path` fallback — dev usage is repo-rooted today |
| A2 | `ENV.to_h.merge` inheritance (bundler vars included) resolves gems for the spawned CLI in END-USER environments as it does here (P6/P7 proved this machine) | Q1 | A vendored-bundle (`vendor/bundle`) deployment would need bundler-aware env or `bundle exec` wrapper — planner note |
| A3 | WEBrick's thread-per-connection ⇒ concurrent POSTs are real (grounded in 14-RESEARCH's MaxClients/thread model + P5's server behavior) | Q4/Pitfall 1 | Low — the Mutex is correct regardless |
| A4 | `req.body.read` + JSON.parse is the WEBrick POST-body idiom (standard WEBrick API, not probed live) | Q4 | Trivial to adjust at implementation; route specs catch it |
| A5 | The group-kill path (P2) stays unexercised in production until WEB2-02; P2's zombie caveat is acceptable for a future phase to handle (it will read run_end, not kill(0), for status) | Q1 | None this phase — no stop control ships |

## Open Questions

1. **Rebuild-all CLI mechanism (A8).** What we know: today `build` is missed-only (build.rb:27-28) with a `--recursive` flag only (build.rb:11-13); D-01 pins the contract, not the mechanism. What's unclear: `--rebuild` flag on `build` (recommend: flips Installer::Build to include the `@cachemap.hit` set) vs a distinct verb. Recommendation: `--rebuild` flag — argv row self-documents (UI-SPEC A8), one verb to gate. **Planner decides; it is new, terminal-visible CLI surface.**
2. **W1 contrast vs the UI-SPEC "white text" pin.** The approved spec pins white-on-accent (:72); 14-UI-REVIEW measures that pair at ≈3.1:1 (AA fail). Recommendation: amend the spec to `color: #0D1117` on accent fills (≈6.1:1) and fold the one-declaration fix into the controls CSS task. **Needs spec-first decision before implementation.**
3. **409 reason field shape** (`'reason' => 'slot_busy'` vs message string) and the malformed-body status (400 recommended — api_read has no precedent for bad REQUEST bodies, only bad project files). Planner pins.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Ruby | everything | ✓ | 3.2.3 local (rbenv); gemspec `>= 3.1.0` (spm_cache.gemspec:27 — CR-01: no 3.2-only APIs) | — |
| webrick | server | ✓ | 1.9.2 (existing pin) | — |
| rspec | validation | ✓ | ~> 3.12 | — |
| xcodebuild | real builds in manual probe | ✓ (machine Xcode; NOT needed for automated rows — P6/P7) | machine Xcode | fail-fast CLI run in a scratch dir exercises BLD-03 headlessly |
| Headless Chromium (agent-browser probe) | manual D-14-pattern rows | ✓ (14-05 used it) | — | none needed |

**Missing dependencies with no fallback:** none. **With fallback:** none.

## Validation Architecture

> `workflow.nyquist_validation: true` in .planning/config.json; full contract seeded in `15-VALIDATION.md`.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | RSpec ~> 3.12 (dev dep; hermetic suite per CP7) |
| Config file | none beyond `.rspec` defaults |
| Quick run command | `bundle exec rspec spec/web_jobs_spec.rb spec/web_build_routes_spec.rb spec/installer_rollback_lock_spec.rb` |
| Full suite command | `bundle exec rspec` (Makefile `make test`) |

### Phase Requirements → Test Map

| Req | Behavior | Test Type | Automated Command | File Exists? |
|-----|----------|-----------|-------------------|-------------|
| BLD-01 | Spawn: array argv `[RbConfig.ruby, BIN, …]`, chdir = config.project_dir, env carries trigger marker, pgroup+detach (assert via fake-bin side effects); slot claim/release via derive; second POST → 409 reason (Mutex-atomic under concurrent threads) | unit (fake-bin injected) | `bundle exec rspec spec/web_jobs_spec.rb` | ❌ Wave 0 |
| BLD-01/D-04 | Routes: POST-only (404 else), token gate (401 rows), Host/Origin inherited, scope whitelist (400 rows), 409 envelope shape, 2xx carries lock snapshot | unit | `bundle exec rspec spec/web_build_routes_spec.rb` | ❌ Wave 0 |
| BLD-04 | Rollback: acquires lock BEFORE rm_rf (ordering), releases on raise, announces exactly once byte-exact under thread-held flock, free path unchanged | unit (`$stdout`-swap + thread-held flock, installer_lock_notice_spec conventions) | `bundle exec rspec spec/installer_rollback_lock_spec.rb` | ❌ Wave 0 |
| D-03 | Trigger: `SPM_CACHE_TRIGGER=ui` → header `trigger:'ui'`; unset/other → `'terminal'`; marker never alters behavior | unit (RunLog.open kwarg + normalization helper) | `bundle exec rspec spec/run_log_trigger_spec.rb` | ❌ Wave 0 |
| BLD-01/WEB-03 | THE integration row: boot (port 0), POST spawn of a fake-bin build, run streams via /api/events, `server.shutdown` exits clean WITH the build in flight (P5 as a regression spec) | integration (port 0, loopback) | `bundle exec rspec spec/web_integration_spec.rb` | extend Wave 0 |
| BLD-02/03, D-05/08 | Click→badge `ui`→stream→disable→in-flight msg→409 on double-click→confirm-bar focus flow→failure banner→rebuild argv row→terminal-held-lock visible queue | manual (agent-browser, D-14 pattern) | — | 15-VALIDATION manual table |

### Sampling Rate
- **Per task commit:** the task's new spec files (hermetic, no real xcodebuild).
- **Per wave merge:** `bundle exec rspec` full suite.
- **Phase gate:** suite green + the agent-browser probe rows executed before `/gsd-verify-work`.

### Wave 0 Gaps
- [ ] `spec/web_jobs_spec.rb` + a fake-bin fixture script (writes a run log; long/short modes)
- [ ] `spec/web_build_routes_spec.rb` (extends the 13-04 route-matrix posture)
- [ ] `spec/installer_rollback_lock_spec.rb`
- [ ] `spec/run_log_trigger_spec.rb`
- [ ] extend `spec/web_integration_spec.rb` (+ `spec/support/web_server_boot.rb` if the POST row needs a spawn-capable boot)

## Security Domain

> `security_enforcement` absent from config.json ⇒ enabled. ASVS Level 1 posture continues.

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2/V3 Auth/Session | no | unchanged 13 posture: per-launch token, no sessions |
| V4 Access Control | yes | POSTs sit inside the SAME Host/Origin + token gate — structural (single servlet, server.rb:87-97); no un-gated route possible |
| V5 Input Validation | yes | scope whitelist → fixed argv fragments (never interpolated); body JSON validated → 400; D-02 array argv |
| V6 Cryptography | no | N/A |
| V7 Logging | yes | token never in env/URL-logs (D-04); spawn errors surface via envelope, never raw dumps |
| V14 (config) | no | no config writes this phase (Phase 16) |

### Known Threat Patterns

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Drive-by POST to /api/build (CSRF) | Elevation/Tampering | Custom header blocked cross-site without a granted preflight + Host/Origin allowlist (D-04, middleware.rb:19-37) |
| DNS-rebinding to reach POSTs | Tampering | Host exact-match on bound port (middleware.rb:19-26) |
| Shell injection via scope | Tampering | Whitelist + fixed argv fragments (Pitfall 5) |
| Fork-bomb via slot bypass | DoS | Mutex-atomic single slot (Pitfall 1); loopback single-user tool |
| Orphaned build abuse after server death | (accepted) | By design (D-02/P5): orphan completes, writes run_end, flock protects artifacts; restart re-derives |

## Sources

### Primary (HIGH confidence — read/probed this session, 2026-09-02)
- Repo code: `web/router.rb` (gate 65-78, dispatch 90-112, api_read 143-163, events 209-225, envelopes 254-262), `web/server.rb` (servlet 87-97, shutdown 54-65, AccessLog 30-34), `web/events.rb` (hello 357-379, shutdown! 325-329, broadcaster 559-668), `web/read_models/runs.rb` (derive 51-81, lock_state 113-122, status_for 174-181), `web/middleware.rb` (19-50), `command/web.rb` (boot flock 48-61, traps 80-93, build_server 116-128), `command/build.rb` (options 11-13, find_project 34-36), `command/rollback.rb` (11-26), `installer/build.rb` (missed-only 27-28, acquire 76-92, release 97-102), `installer/use.rb` (70-90), `installer/rollback.rb` (9-22), `core/run_log.rb` (pre_scan 78-105, open 114-165, header 128-139, pid_alive 403-410, TeeIO 436-488, CycleWrapper 512-570), `core/sh.rb` (20-35: no pgroup — CP14 unchanged), `core/config.rb` (38-52, 110-121), `main.rb` (19-53), `bin/spm-cache`, `spm_cache.gemspec` (executables :24, ruby :27), assets (`app.js` 60-98, 304-317; `log.js` 535-556, 566-570; `index.html`; `styles.css` tokens/btn)
- Planning: 15-CONTEXT.md (D-01..D-09), 15-UI-SPEC.md (approved contract + A1-A10), 14-RESEARCH.md (transport, Patterns 1-6, pitfalls), 14-CONTEXT.md (D-04/D-05/D-11), 14-UI-REVIEW.md (W1-W5, M1-M7), .planning/research/SUMMARY.md (CP4/CP13/CP14 verdicts), ROADMAP §15 (SC1-4), REQUIREMENTS (BLD-01..04), 14-VALIDATION.md (shape precedent)
- PROBED P1-P8: this machine, Ruby 3.2.3 — pgroup/detach/group-kill/zombie semantics, SIGINT group isolation, WEBrick shutdown exit-0 with in-flight detached child (18 ms), detach reaper (~51 ms), real-CLI spawn (fail-fast, header+run_end <1 s, explicit-env boot, null-stdio)

### Secondary (MEDIUM)
- RubyGems install-layout relative-shape assumption (A1); WEBrick POST-body idiom (A4) — training knowledge, flagged

## Metadata

**Confidence breakdown:**
- Spawn mechanics / WEB-03: HIGH — probed live (P1-P8), every seam at file:line
- Rollback lock: HIGH — three-line critical section read end-to-end; idiom precedent spec-backed
- Trigger seam: HIGH — one hard-coded kwarg located; env path probed
- Slot/routes: HIGH on structure (existing gate/envelope reused); MEDIUM only on unpinned names/shapes (planner discretion by design)
- Frontend: HIGH on coupling points (three named code lines); polish folds carry the W1 spec tension (Open Question 2)

**Research date:** 2026-09-02
**Valid until:** 2026-10-02 (stable: codebase- and probe-grounded; re-verify if `web/` or the installer lock sites move before execution)
