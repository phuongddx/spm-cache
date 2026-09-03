# Phase 14: Live Log Streaming + Terminal/Watch Relay - Pattern Map

**Mapped:** 2026-09-01
**Files analyzed:** 15 (8 lib, 6 spec/support, 1 implied asset)
**Analogs found:** 15 / 15 files have a nearest analog; 4 of those are PARTIAL — the SSE transport, per-client queues, EventSource client, and thread-held flock helper have **no direct analog in this repo** (flagged below; nearest precedents given instead).

Sources: `14-CONTEXT.md` (D-01..D-14), `14-RESEARCH.md` (file list from § Recommended Project Structure; webrick mechanics verified there at gem file:line), `14-VALIDATION.md` (Wave 0 spec list). All excerpts below are real code read this session at the cited lines.

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `lib/spm_cache/web/events.rb` (NEW) | service (tailer + broadcaster) | event-driven → streaming | `lib/spm_cache/core/watcher.rb` (tailer poll) + `lib/spm_cache/core/run_log.rb` (line split) | role-match; broadcaster core has NO analog |
| `lib/spm_cache/web/read_models/runs.rb` (NEW) | read model | request-response | `lib/spm_cache/web/read_models/state.rb` | exact |
| `lib/spm_cache/web/router.rb` (MOD) | route/controller | request-response (+ one streaming route) | itself (`api_read`/`api_doctor` gate order) | exact for `/api/runs`; `/api/events` is a new surface |
| `lib/spm_cache/command/web.rb` (MOD, maybe) | controller (CLI verb) | event-driven (signals) | itself (WEB-03 trap block) | exact |
| `lib/spm_cache/web/server.rb` (MOD, maybe) | adapter | streaming | itself (servlet seam + `#shutdown`) | exact |
| `lib/spm_cache/installer/build.rb` (MOD) | service | batch | itself (`acquire_build_lock`) | exact |
| `lib/spm_cache/installer/use.rb` (MOD) | service | batch | itself (`with_build_lock`) | exact |
| `lib/spm_cache/web/assets/log.js` (NEW) | component (frontend module) | event-driven (SSE) | `lib/spm_cache/web/assets/app.js` | role-match; SSE client has NO analog |
| `lib/spm_cache/web/assets/index.html` (MOD) | view | request-response | itself (panel sections + script tags) | exact |
| `lib/spm_cache/web/assets/styles.css` (MOD, implied) | view | — | itself (panel/badge/status classes app.js consumes) | exact |
| `spec/events_tailer_spec.rb` (NEW) | test | file-I/O | `spec/run_log_spec.rb` | exact |
| `spec/events_broadcaster_spec.rb` (NEW) | test | event-driven | `spec/web_doctor_spec.rb` (concurrency describe) | role-match; queue-bound tests have NO precedent |
| `spec/web_events_route_spec.rb` (NEW) | test | streaming | `spec/web_state_spec.rb` router-mount describes | role-match |
| `spec/web_runs_read_model_spec.rb` (NEW) | test | request-response | `spec/web_state_spec.rb` | exact |
| `spec/installer_lock_notice_spec.rb` (NEW) | test | batch | `spec/installer_build_spec.rb` (output idioms) | exact |
| `spec/web_integration_spec.rb` + `spec/support/web_server_boot.rb` (EXTEND) | test + support | streaming integration | itself (one port-0 boot) | exact |

---

## Pattern Assignments

### `lib/spm_cache/web/events.rb` (NEW — Tailer + Broadcaster, service, event-driven→streaming)

**Tailer analog:** `lib/spm_cache/core/watcher.rb` — the repo's only filesystem-poll loop, and the research names it as the precedent (`14-RESEARCH.md` Pattern 2).

**Poll-loop pattern** (watcher.rb:57-60, from the `run` loop):
```ruby
loop do
  sleep debounce
  current = current_signatures
  next if current == @last_signatures
```

**mtime+size signature pattern** (watcher.rb:126-134):
```ruby
def current_signatures
  watched_files.map { |f| file_signature(f) }
end

def file_signature(path)
  return nil unless path && File.exist?(path)

  stat = File.stat(path)
  [path, stat.mtime.to_i, stat.size]
end
```
Also copy the **continue-on-error** posture (watcher.rb:64-67: `rescue StandardError => e` → `warn_msg` → keep looping) — the tailer must never die on a transient read error, same as the watcher never dies on a transient regeneration failure.

**Line-split analog:** `lib/spm_cache/core/run_log.rb:222-243` — `record_line`'s buffer-until-newline loop is EXACTLY the transform the tailer inverts (bytes in → complete `\n`-terminated lines out, partial tail stays buffered). Buffers are keyed `[Thread.current, stream]` (WR-01 pair atomicity: a mutex serializes each call, but a writer's partial + completing chunks are two calls — thread-keyed buffers keep concurrent writers' lines whole):
```ruby
def record_line(str, stream)
  ...
  @buffer_mutex.synchronize do
    key = [Thread.current, stream]
    buffer = (@buffers[key] ||= +'')
    buffer << str
    while (nl = buffer.index("\n"))
      record_text(buffer.slice!(0..nl), stream)
    end
    @buffers.delete(key) if buffer.empty?
  end
end
```
The tailer's poll reads appended bytes (`io.seek(@offset); io.read`), pushes into a line buffer, and advances the byte offset by `line.bytesize` per complete line — the offset-after-newline is the SSE id's offset half (`14-RESEARCH.md` Pattern 2).

**Writer-side facts the tailer depends on** (all verified this session):
- File naming: `run_log.rb:31,117` — `'%Y%m%dT%H%M%S%3NZ'` + `-<pid>-<command>` + `.jsonl`; lexicographic == chronological; **no colons** → composite id `"<filename>:<offset>"` splits on the LAST colon.
- Header publishes atomically via same-dir Tempfile + `File.rename` (run_log.rb:126-148) → a tailer never observes a header-less file.
- Header keys for D-06/D-11 identity (run_log.rb:128-139): `event, ts, command, argv, redacted, pid, started_at, spm_cache_version, trigger, cycle`.
- Body lines carry only `ts/stream/text`, structured events carry `event` (run_log.rb:24-26, 261-266) → renderers key on `event`, never interpret `text` (T-12-01).
- Every line UTF-8-scrubbed at write (run_log.rb:248) + `JSON.generate` escapes embedded newlines → `\n`-splitting is byte-unambiguous.
- Retention: `prune` runs at EVERY run open (run_log.rb:159-160, 313-340), oldest-first, whole-file unlink only; liveness protection via `pid_alive?` (run_log.rb:395-402, `Process.kill(0)`/ESRCH) and `protected_run?` (run_log.rb:407-409) — the CP14 precedent for "honest pid-dead" derivation.
- Header pid read precedent: `run_start_pid` (run_log.rb:415-419) — `File.open(path, &:gets)` + `JSON.parse(...)['pid']`, rescue-to-nil. Reuse this shape for `/api/runs` identity parsing.

**Broadcaster: NO ANALOG.** `grep 'Thread\.|Queue|Mutex|flock|trap('` over `lib/` shows the repo's COMPLETE threading vocabulary: `Mutex` (run_log.rb:195-196, doctor.rb:32), short-lived reader threads joined immediately (sh.rb:38-52), `Signal.trap` (watcher.rb:49/78-79, web.rb:83), `flock` (build.rb:80, use.rb:75, web.rb:59). **There is no `Queue`/`SizedQueue`/`ConditionVariable` anywhere.** Per-client bounded queues with drop-oldest, the shutdown sentinel, and pop-timeout heartbeats are novel — plan them from `14-RESEARCH.md` Pattern 3, not from any repo file. What CAN be copied from the repo:
- **Mutex discipline** — one lock per concern, fixed acquisition order (run_log.rb:189-190 comment: `@buffer_mutex` covers append+extract; `record_text` inside it takes `@mutex`, never the reverse, "so the two locks cannot deadlock"). The broadcaster's queue-mutex must follow the same single-order rule.
- **Swap-under-mutex** — doctor.rb:37-41 moves `{data, generated_at}` as ONE pair; the broadcaster's client-set register/unregister belongs under one Mutex the same way.
- **Thread join discipline** — sh.rb:52 `threads.each(&:join)`; spec-side bounded joins (web_server_boot.rb:30 `thread&.join(10)`).
- **`Core::Parallel` is NOT a precedent** — it is a 19-line `refine Array` over the `parallel` gem (parallel.rb:8-17, `Parallel.map/each`) for one-shot array fan-out; irrelevant to a long-lived tailer/broadcaster. Say so in the plan if anyone reaches for it.

---

### `lib/spm_cache/web/read_models/runs.rb` (NEW — read model, request-response)

**Analog:** `lib/spm_cache/web/read_models/state.rb` — the stateless per-request read model.

**Shape to match** (state.rb:15-27, 44-53):
```ruby
def self.call(config: Core::Config.instance, cache_root: nil)
  inventory = Cache::Inventory.scan(config: config, cache_root: cache_root)
  ...
  {
    'packages' => inventory.map do |entry| ... end,
    'summary' => stringified_summary(cachemap.stats),
    'poll_seconds' => config.web_poll_seconds
  }
end

# JSON.generate silently drops symbol keys; the payload is
# String-keyed throughout. (state.rb:44-46)
```
Copy exactly: module-level `.call(config:)` callable; re-reads disk on EVERY call ("the server holds no derived state — never a second source of truth", state.rb:5-9); String keys at every level (state.rb's `stringified_summary` exists solely because `JSON.generate` drops symbol keys). `ReadModels::Graph` (graph.rb:16-25) shows the missing-file guard variant — `return { 'present' => false, ... } unless File.exist?(path)` — the right shape for an empty/nonexistent runs dir.

**Do NOT copy Doctor's statefulness into runs.rb.** `ReadModels::Doctor` (doctor.rb:19-41) is the ONE stateful read model — an instance holding a Mutex-cached `{data, generated_at}` (T-13-10). CP10 forbids run-state caching in the server; `/api/runs` must derive from the runs dir + flock probe per request, i.e. the State shape. (Doctor's instance pattern IS the wiring precedent for `Web::Events`, though — see router below.)

**CP10 derivation pieces (from `Core::RunLog`, no new machinery):**
- Non-blocking flock probe over `Core::Config.instance.build_lock_path` (config.rb:110-112, `.spm-cache-build.lock`). The repo's flock sites are all BLOCKING (build.rb:80, use.rb:75, web.rb:59); a `LOCK_EX | File::LOCK_NB` probe that releases immediately is a new-but-trivial variant — sketch in `14-RESEARCH.md` Pattern 4.
- `pid_alive?` shape: run_log.rb:395-402 (`Process.kill(0)`; ESRCH → dead; other errors → assume alive).
- Header parse: `run_start_pid` shape (run_log.rb:415-419).
- CP14 honesty: pid dead + no `run_end` line → "interrupted — exit unknown", never "running" (prune's `protected_run?` already distinguishes live-pid runs at run_log.rb:407-409).

---

### `lib/spm_cache/web/router.rb` (MOD — route/controller)

**Analog: itself.** The mounting and gate order are structural; copy them verbatim for both new routes.

**Service gate — every byte passes Host/Origin before dispatch** (router.rb:55-69):
```ruby
def service(req, res)
  apply_security_headers(res)

  host = req['host']
  origin = req['origin']
  supplied = req[TOKEN_HEADER] || req.query[TOKEN_PARAM]

  # Gate order is Host, then Origin, then per-route token: a
  # rejected request never reaches dispatch, for any verb.
  return reject(res, 403, 'forbidden host') unless Middleware.allowed_host?(host: host, port: @port)
  return reject(res, 403, 'forbidden origin') unless Middleware.allowed_origin?(origin: origin, port: @port)

  dispatch(req, res, supplied)
end
```
Note `supplied` already accepts the **query param** (router.rb:60) — that is the EventSource auth path (`?token=`), since `EventSource` cannot set headers. Same-launch trust posture as the locked 302 bootstrap.

**Dispatch + token gate + verb check** (router.rb:72-90, 121-135):
```ruby
def dispatch(req, res, supplied)
  case req.path
  when '/', ''
    root(req, res)
  when %r{\A/assets/}
    asset(res, req.path.sub(%r{\A/assets/}, ''))
  when '/api/state'
    api_read(req, res, supplied, :state)
  ...
  else
    reject(res, 404, 'not found')
  end
end

def api_read(req, res, supplied, model)
  unless Middleware.valid_token?(token: supplied, expected_token: @token)
    return reject(res, 401, 'missing or invalid token')
  end
  return reject(res, 404, 'not found') unless req.request_method == 'GET'
  ...
end
```
`/api/runs` is a fourth `api_read`-style row (token gate → GET check → read model → envelope). `/api/events` shares the gate but **departs from the envelope**: it is the one route that never calls `respond_json`.

**Collaborator wiring precedent** (router.rb:39-53): `@read_models` defaults constructed in `initialize`, per-key overridable for specs, with Doctor as the instance-valued entry:
```ruby
@read_models = {
  state: Web::ReadModels::State,
  graph: Web::ReadModels::Graph,
  doctor: Web::ReadModels::Doctor.new(config: config)
}.merge(read_models)
```
Wire `Web::Events` the same way: an instance default (e.g. `events: Web::Events.new(config: config)`) merged over an injectable keyword — specs then inject doubles per-key exactly like `read_models:` today (web_state_spec.rb 'router mount' exercises the default wiring through `WebServerBoot.with_server`).

**Delta — the streaming route (no repo analog).** Per `14-RESEARCH.md` Pattern 1 (webrick 1.9.2 gem source + live probes, anchors cited there): `res.status = 200` ALWAYS (any non-200 permanently fails EventSource reconnect, WHATWG §9.2.3 — the "503 + Retry:" clause is falsified; `Retry:` as an HTTP header plays no role), `res.content_type = 'text/event-stream'`, `res.keep_alive = false` (else the connection thread parks 30 s after the stream ends), `res.chunked = true` + `res.body = proc { |out| ... }` (per-write flush, verified), `last_event_id = req['last-event-id']` (header name downcased by WEBrick). Do NOT add a `rescue => 500 envelope` around the stream — dead clients surface as `EPIPE/ECONNRESET` inside the proc and are handled there.

**Security headers already cover SSE** (router.rb:177-180): `apply_security_headers` stamps `Cache-Control: no-store` on every response including the stream.

**Client-input validation precedent for resume ids:** `Web::Assets` (assets.rb:39-47, 63-73) — validate BEFORE any filesystem call, then containment-check the expanded path:
```ruby
def resolve(name)
  return nil unless valid_name?(name)

  path = File.expand_path(name, @root)
  return nil unless path.start_with?("#{@root}/")
  return nil unless File.file?(path)
  ...
end

def valid_name?(name)
  name.is_a?(String) && !name.empty? && !name.start_with?('.') &&
    !name.include?('/') && !name.include?('\\') && !name.include?('..') && !name.include?("\0")
end
```
`Events.parse_resume_id` must do the same: filename regex (`run_log_spec.rb:45` idiom: `/\A\d{8}T\d{6}\d{3}Z-\d+-<verb>\.jsonl\z/`) + `File.expand_path` containment under `Config#runs_dir`, nil on any failure → fresh replay. Client-supplied ids are attacker input (T-13-04 posture).

---

### `lib/spm_cache/web/server.rb` and `lib/spm_cache/command/web.rb` (MOD, maybe — shutdown ordering)

**Analog: themselves.** WEB-03 discipline already in place:

**Trap → shutdown → IGNORE-masked cleanup** (command/web.rb:74-92):
```ruby
%w[TERM INT].each { |sig| Signal.trap(sig) { server.shutdown } }

begin
  server.start # blocks in the WEBrick run loop until shutdown
ensure
  Signal.trap('TERM', 'IGNORE')
  Signal.trap('INT', 'IGNORE')
  ::SPMCache::Web::Marker.clear(pid: Process.pid)
end
```
Same shape in `Core::Watcher` (watcher.rb:49, 77-81). The watcher comment explains WHY the mask exists: a trap-raise landing inside the handler escapes uncaught and breaks the exit-0 contract.

**Delta:** WEBrick's accept-loop `ensure` joins every connection thread on shutdown (verified: webrick server.rb:210, per `14-RESEARCH.md` finding 3). An SSE body proc that never returns hangs `server.shutdown` past any bound. The broadcaster must end every proc on a shutdown sentinel BEFORE the join. Two candidate seams — planner picks one:
- `Web::Server#shutdown` (server.rb:60-63) currently just calls `@http.shutdown`; it holds `@router`, so it can notify the router's events collaborator first. Zero `Command::Web` changes; benefits every future entry point.
- `Command::Web`'s trap block (web.rb:83) — but a trap context is the wrong place for broadcaster coordination; prefer the Server seam.

The spec proof is the shutdown-within-bound row in `web_integration_spec.rb` (`14-VALIDATION.md` Wave 0): bounded `thread.join` is already the house idiom (web_server_boot.rb:30).

---

### `lib/spm_cache/installer/build.rb` + `use.rb` (MOD — D-05 lock-wait line)

**Analog: the two flock sites themselves.**

`Installer::Build#acquire_build_lock` (build.rb:76-82, released at 88-92):
```ruby
def acquire_build_lock
  path = @config.build_lock_path
  FileUtils.mkdir_p(File.dirname(path))
  lock = File.open(path, File::CREAT | File::RDWR)
  lock.flock(File::LOCK_EX)
  lock
end
```
`Installer::Use#with_build_lock` (use.rb:70-81):
```ruby
def with_build_lock
  path = @config.build_lock_path
  FileUtils.mkdir_p(File.dirname(path))
  lock = File.open(path, File::CREAT | File::RDWR)
  begin
    lock.flock(File::LOCK_EX)
    yield
  ensure
    lock.flock(File::LOCK_UN)
    lock.close
  end
end
```
Both comments pin the design ("A BLOCKING flock — 'defer rather than interrupt' … no polling/backoff needed", use.rb:68-69).

**D-05 delta (identical shape at both sites):** try `flock(File::LOCK_EX | File::LOCK_NB)` first; on `EWOULDBLOCK` print the announce line, then do the existing blocking `flock`. The free-lock path must stay byte-identical (14-VALIDATION: "free-lock path byte-identical to today").

**Why the in-stream attribution is free — key mechanism:** `Core::UI.info` is bare `puts` → `$stdout` (core/log.rb:13-15), and `Core::UI.warn`/`error` → `$stderr` (log.rb:18-24). During any run, Main.run / `CycleWrapper` swap those globals for `TeeIO` (run_log.rb:424-465), whose `#write` mirrors to `record_line` → the JSONL (run_log.rb:451-456). So one `Core::UI.info 'Waiting for build lock…'` before the blocking flock automatically lands in the run log — the server streams it like any body line, terminal users see the same words (D-05's "two surfaces" requirement), and **no new logging machinery is needed**. Watch cycles get it identically via `CycleWrapper` (run_log.rb:494-541).

---

### `lib/spm_cache/web/assets/log.js` (NEW — component, event-driven)

**Analog:** `lib/spm_cache/web/assets/app.js` — the repo's entire frontend idiom set (one vanilla ES module, IIFE, `'use strict'`, no framework, fully offline).

**DOM discipline — textContent only, never markup strings** (app.js:22-29; stored-XSS defense T-13-13):
```js
const byId = (id) => document.getElementById(id);
const el = (tag, opts = {}) => {
  const node = document.createElement(tag);
  if (opts.class) node.className = opts.class;
  if (opts.text !== undefined) node.textContent = opts.text;
  if (opts.title) node.title = opts.title;
  return node;
};
```
Every log line, pill, banner, anchor chip, and identity-card field MUST render through `el()` + `textContent` — run-log `text` bodies are subprocess output (attacker-adjacent by construction, T-12-01).

**Authed transport — token from sessionStorage** (app.js:12-19): boot token → `sessionStorage` → URL cleaned via `history.replaceState` before first render. `log.js` reads the same `spm-cache-web-token` key (shared module scope via `sessionStorage`, not imports) and connects `new EventSource('/api/events?token=' + token)` — query param because EventSource cannot set headers; the server already accepts it (router.rb:60). This is the ONE place log.js cannot copy app.js's `request()` fetch layer (app.js:70-96): SSE has no envelope and no status handling — a failed EventSource fires `onerror` and auto-reconnects; there is no 401-envelope branch. Keep `renderTokenInvalid` (app.js:63-68) behavior in mind: a permanently-rejected token (401/403 is permanent-by-design per the amended CP11) means the stream never opens — surface the dead-connection pill.

**Poll loop precedent for follow/heartbeat feel** (app.js:309-313):
```js
const loop = async () => {
  if (!byId('state-body')) return; // panels replaced (token invalid)
  await refreshState();
  window.setTimeout(loop, pollSeconds * 1000);
};
```
The "panels replaced → bail out" guard is the pattern for log.js teardown-safety.

**Empty states** (app.js:101-106): heading + body parts, `dataset.rendered = '1'` flag, `replaceChildren`. D-13's "fresh boots of a quiet project never show an empty screen" uses this with the completed-run identity card. Panel-error keeps-last-good behavior (app.js:85-93) is the model for keeping rendered log lines alive when `/api/runs` hiccups.

**Sticky chip rail precedent** (app.js:241-252): `renderLegend` builds the graph-legend chips (`el('span', {class:'legend-item'})` + swatch) — D-08 explicitly cites this as the anchor-rail precedent. Badge vocabulary precedent: `STATUS_CLASS`/`MARKER` maps (app.js:36-41, ~185-189: `{ ok: '✓', warn: '!', fail: '✗' }`) — reuse for the identity-card status dot (D-06) and `:fail` error lines (D-03).

**Delta (no analog):** `EventSource` lifecycle (`onmessage` JSON.parse per data line, `addEventListener` for named `switch`/`hello`/`notice` events, last-event-id handled by the browser automatically), the ~500-line render ring (D-02), scroll-pause (D-01), filter+banner interplay (D-09/D-10). All frontend-new; `14-UI-SPEC.md` pins copy strings.

---

### `lib/spm_cache/web/assets/index.html` (MOD — view)

**Analog: itself.** Panel section shape (index.html:15-26):
```html
<section class="panel">
  <div class="panel-header">
    <h2>Cache State</h2>
    <div class="panel-actions">
      <span class="stamp" id="state-stamp"></span>
      <button type="button" class="btn" id="state-refresh">Refresh</button>
    </div>
  </div>
  <div class="panel-body" id="state-body">
    <p class="loading">Loading…</p>
  </div>
</section>
```
The log panel copies this skeleton (stamp slot becomes the connection/status pill slot). Script registration precedent (index.html:55-56):
```html
<script src="assets/cytoscape.min.js"></script>
<script type="module" src="assets/app.js"></script>
```
→ add `<script type="module" src="assets/log.js"></script>` after app.js. Order matters only for globals (cytoscape precedent); log.js needs none — it talks only to DOM + SSE. The graph panel (index.html:39-53) shows the pattern for a panel with a nested structural region (`graph-wrap` with legend + canvas, toggled via `hidden`) — the identity-card + anchor-rail region follows it.

---

### `spec/events_tailer_spec.rb` (NEW — test, file-I/O)

**Analog:** `spec/run_log_spec.rb` — hermetic JSONL fixture conventions.

**Fixture + guard idioms** (run_log_spec.rb:12-30):
```ruby
let(:runs_dir) { Dir.mktmpdir }

before do
  allow(SPMCache::Core::Sh).to receive(:run) do |cmd, *_opts|
    raise "unexpected real invocation: Sh.run(#{cmd.inspect})"
  end
  allow(SPMCache::Core::Sh).to receive(:capture_output) do |cmd, *_opts|
    raise "unexpected real invocation: Sh.capture_output(#{cmd.inspect})"
  end
end

after do
  described_class.current = nil
  FileUtils.rm_rf(runs_dir)
end

def open_log(**kwargs)
  described_class.open(runs_dir: runs_dir, command: 'use', **kwargs)
end
```
Copy: tmpdir runs-dir per example; default-deny `Core::Sh` (the tailer must never shell out — the guard proves it); cleanup in `after`. Filename/shape assertions (run_log_spec.rb:33-46): `expect(File.basename(log.path)).to match(/\A\d{8}T\d{6}\d{3}Z-\d+-use\.jsonl\z/)`, per-line `JSON.parse` validity, exact line-count assertions (`expect(lines.length).to eq(3)` — header + body + run_end). Partial-line buffering fixtures (run_log_spec.rb:135-152, `record_line('par')` + `record_line("tial\n")` → ONE line) are the exact fixtures the tailer's inverse transform needs; the UTF-8 scrub fixtures (run_log_spec.rb:93-115) bound the multi-byte resume-offset rows from `14-VALIDATION.md`.

---

### `spec/events_broadcaster_spec.rb` (NEW — test, event-driven)

**Nearest analog:** `spec/web_doctor_spec.rb` — the repo's only thread-coordination spec.

**Config-swap around-block** (web_doctor_spec.rb:24-33):
```ruby
around do |example|
  previous = config.project_dir
  SPMCache::Core::Config.configure(project_dir: project_dir)
  config.reset!
  example.run
ensure
  config.reset!
  SPMCache::Core::Config.configure(project_dir: previous)
  FileUtils.rm_rf(project_dir)
end
```
Its `concurrency (T-13-10)` describe tests Mutex-atomicity with real threads — the posture for the sentinel/drop-oldest examples. **No precedent exists for queue-cap/drop-oldest/sentinel assertions** — write them from `14-VALIDATION.md`'s rows (cap → drop-oldest + "N lines dropped" notice; sentinel ends every loop; heartbeat on pop timeout) using plain RSpec + real `SizedQueue`s and threads with bounded joins (web_server_boot.rb:30 idiom).

---

### `spec/web_events_route_spec.rb` (NEW — test, streaming route)

**Analog:** the `router mount` describes in `spec/web_state_spec.rb:182-191` and `spec/web_doctor_spec.rb:149-185`:
```ruby
describe 'router mount' do
  it 'token-gates GET /api/state (401 without the launch token)' do
    Dir.mktmpdir do |project|
      WebServerBoot.with_server(project_dir: project) do |handle|
        res = WebServerBoot.http_get(handle, '/api/state')
        expect(res.code).to eq('401')
        body = JSON.parse(res.body)
        expect(body['status']).to eq('error')
      end
    end
  end
end
```
Copy for the 401 rows and the Host/Origin matrix extensions (`14-VALIDATION.md`: "Host/Origin rows extend the 13-04 matrix").

**Delta:** a plain `WebServerBoot.http_get` on `/api/events` blocks until the stream closes — the route's whole point is that it doesn't close. Streaming rows need raw sockets: `TCPSocket` connect → hand-written `GET /api/events?token=… HTTP/1.1` → read headers + first frames, exactly how `wait_accepting` already proves raw loopback reachability (web_server_boot.rb:43-52):
```ruby
def self.wait_accepting(port)
  deadline = Time.now + 5
  loop do
    TCPSocket.new('127.0.0.1', port).close
    return
  rescue SystemCallError
    raise "server never accepted connections on 127.0.0.1:#{port}" if Time.now > deadline
    sleep 0.02
  end
end
```
Extend `web_server_boot.rb` with a bounded raw-socket read helper (and a bounded drain/close) — that extension is already a Wave 0 item. `Last-Event-ID` traversal fixtures send hostile ids and assert fresh-replay + that the file was never opened.

---

### `spec/web_runs_read_model_spec.rb` (NEW — test, request-response)

**Analog:** `spec/web_state_spec.rb` — read-model unit spec with a real router-mount row. Copy the around-block (web_doctor_spec.rb:24-33 shape), tmpdir project dirs, hand-authored fixtures on disk, exact-shape assertions, and the 401 router-mount row. Fixture precedent for hand-authored JSONL: run_log_spec.rb:38-46 (header shape) + `14-VALIDATION.md`: "tmpdir runs-dirs with hand-authored JSONL (header/body/exit shapes per Phase 12 vocabulary)".

**No precedent: the thread-held flock helper.** CP10's "held" rows need a helper that takes `LOCK_EX` on `build_lock_path` from a background thread and releases in ensure. Build it once in the spec file (Thread.new + bounded join, web_server_boot discipline); it has no repo ancestor.

---

### `spec/installer_lock_notice_spec.rb` (NEW — test, batch)

**Analog:** `spec/installer_build_spec.rb` output idioms (e.g. installer_build_spec.rb:54-55, 63-67):
```ruby
expect { inst.perform_install }.to output(/Building 2 target.*Alamofire.*SnapKit/m).to_stdout
...
expect do
  expect { inst.perform_install }.to output(/No targets to build/).to_stdout
end.to output(/unknown target 'Nonexistent'/).to_stderr
```
RSpec `to output(...).to_stdout` matchers ARE the "$stdout-swap convention" (core_spec.rb:59-67 pins `UI.info` → stdout, `UI.warn` → `[warn] …` stderr). The three rows per `14-VALIDATION.md`: thread-held lock → `/Waiting for build lock/` on stdout then blocks; free lock → byte-identical output to today (`not_to output` the notice); combined with a run log open, assert the notice ALSO lands as a JSONL body line (that's the tee mechanism — the strongest D-05 proof). Use the run_log_spec default-deny Sh guard where installers would shell out.

---

### `spec/web_integration_spec.rb` + `spec/support/web_server_boot.rb` (EXTEND)

**Analog: themselves.** The ONE port-0 boot with real wiring (web_integration_spec.rb:29-51):
```ruby
before(:all) do
  @project_dir = Dir.mktmpdir('spm-cache-integration')
  ...
  SPMCache::Core::Config.configure(project_dir: @project_dir)
  router = SPMCache::Web::Router.new(token: @token, port: 0,
                                     assets: SPMCache::Web::Assets.new)
  @server = SPMCache::Web::Server.new(port: 0, token: @token, router: router)
  @thread = Thread.new { @server.start }
  WebServerBoot.wait_accepting(@server.port)
end

after(:all) do
  WebServerBoot.shutdown(@server)
  @thread&.join(10)
  ...
end
```
Extend with SSE rows: raw-TCPSocket GET → assert `200` + `text/event-stream` + `no-store` + hello frame + replayed fixture lines; reconnect with `Last-Event-ID` resumes exactly; **the shutdown-within-bound assertion reuses `@thread&.join(10)` with an open stream** — that bounded join against a live SSE connection IS the sentinel proof (WEBrick joins connection threads inside `shutdown`). Keep CP7 intact: still exactly one boot.

---

## Shared Patterns

### Token gate (all routes, both new ones included)
**Source:** `lib/spm_cache/web/router.rb:55-69, 121-127`
**Apply to:** `/api/events` and `/api/runs`
```ruby
supplied = req[TOKEN_HEADER] || req.query[TOKEN_PARAM]   # router.rb:60 — ?token= is the EventSource path
return reject(res, 403, 'forbidden host')  unless Middleware.allowed_host?(...)
return reject(res, 403, 'forbidden origin') unless Middleware.allowed_origin?(...)
unless Middleware.valid_token?(token: supplied, expected_token: @token)
  return reject(res, 401, 'missing or invalid token')
end
```

### Client-input → filesystem validation (defense-in-depth)
**Source:** `lib/spm_cache/web/assets.rb:39-47, 63-73` (T-13-04)
**Apply to:** `Events.parse_resume_id` (`Last-Event-ID` is attacker input): regex-validate the filename, `File.expand_path`, containment under `Config#runs_dir`, nil → fresh replay.

### String-keyed JSON payloads
**Source:** `lib/spm_cache/web/read_models/state.rb:44-53`, doctor.rb:60-64
**Apply to:** `/api/runs` payload and every SSE frame: `JSON.generate` drops symbol keys; keep everything String-keyed (or round-trip through `JSON.parse(JSON.generate(...))` like doctor.rb does).

### Graceful-shutdown discipline
**Source:** `lib/spm_cache/command/web.rb:74-92`, `lib/spm_cache/core/watcher.rb:49, 77-81`
**Apply to:** the broadcaster sentinel must fire before WEBrick's connection-thread join; IGNORE-mask further signals during cleanup; exit-0 is the contract (WEB-03).

### Cross-process exclusion is flock; in-process shared state is Mutex (never both muddled)
**Sources:** build.rb:76-92, use.rb:70-81, web.rb:49-61 (flock); run_log.rb:189-190/364-373, doctor.rb:32-41 (Mutex, fixed lock order, swap-as-one-pair)
**Apply to:** CP10 lock probe (LOCK_NB variant — new, trivial); broadcaster client-registry mutex.

### Spec hermeticity
**Sources:** run_log_spec.rb:12-30 (tmpdir + default-deny Sh), web_doctor_spec.rb:24-33 (Config configure/reset around-block), web_integration_spec.rb:29-60 (the ONE port-0 boot, bounded join)
**Apply to:** every Wave 0 spec file.

### Comments cite the planning-doc ID they defend
**Source:** pervasive (e.g. state.rb:5-9, use.rb:68-69, router.rb:27-33)
**Apply to:** all new code — "(CP11)", "(D-05)", "(CP10)", "(T-12-01)" etc.

---

## No Analog Found

Planner should source these from `14-RESEARCH.md` Patterns 1-4 (gem-source + live-probe verified) and `14-UI-SPEC.md`, NOT from repo files:

| Component | Role | Data Flow | Why no analog | Nearest precedents to imitate |
|-----------|------|-----------|---------------|-------------------------------|
| `Web::Events` broadcaster (per-client bounded `SizedQueue`, drop-oldest + notice, pop-timeout heartbeat, shutdown sentinel) | service | pub-sub | Zero `Queue`/`SizedQueue`/`ConditionVariable` usage in `lib/` (grep-verified); repo threading vocabulary is exactly: Mutex, short-lived joined threads, traps, flock | Mutex lock-order discipline (run_log.rb:189-190), swap-under-mutex (doctor.rb:37-41), bounded thread joins (sh.rb:52, web_server_boot.rb:30), trap-mask shutdown (web.rb:83-89) |
| SSE route body (`chunked=` + proc body, `keep_alive=false`, 200-always, heartbeat frames, `Last-Event-ID`) | route | streaming | No repo code streams a response; every current handler builds a full String body (`respond`, router.rb:195-199) | The gate/dispatch skeleton it mounts in (router.rb:55-90); research Pattern 1 carries the verified webrick mechanics |
| `EventSource` client lifecycle (auto-reconnect, named events, no custom headers) | component | event-driven | Frontend has only `fetch` + envelope (app.js:70-96) and a poll loop (app.js:309-313) | el()/textContent discipline, sessionStorage token, renderEmpty/panel-error posture, legend-chip rail |
| Thread-held flock helper for CP10 specs | test support | — | All repo flock usage is same-thread blocking; no spec holds a lock across threads | command/web.rb boot-lock shape + web_server_boot thread/join idiom |

Also note explicitly: **`Core::Parallel` is not a threading precedent** for this phase (array fan-out refine over the `parallel` gem, parallel.rb:8-17) — do not reach for it in `Web::Events`.

---

## Metadata

**Analog search scope:** `lib/spm_cache/web/**` (router, server, read_models, assets, assets.rb), `lib/spm_cache/core/**` (run_log, watcher, sh, parallel, config, log), `lib/spm_cache/installer/{build,use}.rb`, `lib/spm_cache/command/web.rb`, `spec/{run_log,web_state,web_doctor,web_integration,installer_build}_spec.rb`, `spec/support/web_server_boot.rb`
**Files scanned:** 20 read in full or targeted ranges this session; threading/validation vocabulary cross-checked with repo-wide grep
**Pattern extraction date:** 2026-09-01
