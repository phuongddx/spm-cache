---
phase: 13-server-skeleton-read-only-dashboard
reviewed: 2026-09-01T06:12:00Z
depth: deep
files_reviewed: 33
files_reviewed_list:
  - lib/spm_cache/web/server.rb
  - lib/spm_cache/web/router.rb
  - lib/spm_cache/web/middleware.rb
  - lib/spm_cache/web/assets.rb
  - lib/spm_cache/web/marker.rb
  - lib/spm_cache/web/port_prober.rb
  - lib/spm_cache/web/read_models/state.rb
  - lib/spm_cache/web/read_models/graph.rb
  - lib/spm_cache/web/read_models/doctor.rb
  - lib/spm_cache/web/assets/index.html
  - lib/spm_cache/web/assets/app.js
  - lib/spm_cache/web/assets/styles.css
  - lib/spm_cache/web/assets/cytoscape.min.js
  - lib/spm_cache/command/web.rb
  - lib/spm_cache/command/cache/list.rb
  - lib/spm_cache/command/doctor.rb
  - lib/spm_cache/core/config.rb
  - lib/spm_cache/core/diagnostics.rb
  - lib/spm_cache/cache/inventory.rb
  - lib/spm_cache/cache/cachemap.rb
  - lib/spm_cache/assets/templates/spm-cache.yml.template
  - spm_cache.gemspec
  - spec/support/web_server_boot.rb
  - spec/web_middleware_spec.rb
  - spec/web_server_spec.rb
  - spec/web_assets_spec.rb
  - spec/web_lifecycle_spec.rb
  - spec/web_signals_spec.rb
  - spec/web_state_spec.rb
  - spec/web_graph_spec.rb
  - spec/web_doctor_spec.rb
  - spec/web_frontend_spec.rb
  - spec/web_integration_spec.rb
  - spec/web_packaging_spec.rb
  - spec/command_cache_list_spec.rb
  - spec/config_spec.rb
  - spec/doctor_spec.rb
findings:
  critical: 0
  warning: 4
  info: 4
  total: 8
severity:
  blocker: 0
  major: 1
  minor: 3
  info: 4
findings_count: 8
findings_status:
  WR-01: resolved
  WR-02: resolved
  WR-03: resolved
  WR-04: resolved
  IN-01: resolved
  IN-02: resolved
  IN-03: resolved
  IN-04: resolved
status: resolved
---

# Phase 13: Code Review Report

**Reviewed:** 2026-09-01T06:12:00Z
**Depth:** deep (full read of every changed source file, cross-file call-chain tracing, WEBrick 1.9.2 gem-source verification, UI-SPEC/plan-contract diffing)
**Files Reviewed:** 33 source files (diff scope `cf5a273..dc8814e`; `.planning/` excluded per contract)
**Status:** findings

## Summary

The phase 13 web layer is well-built: the security middleware is genuinely hardened (exact-match Host/Origin allowlists derived only from the bound port, digest-then-XOR fixed-time token compare with no length short-circuit), the catch-all servlet makes the gate structural, asset serving stacks three independent traversal defenses, the marker is atomic/0600/symlink-rejecting, the access log is disabled with the token-leak rationale cited, and app.js renders every dynamic string through `textContent` — no `innerHTML`, no `eval`, token never in the DOM. The 25-cell route×auth integration matrix, drive-by trio, real-subprocess signal contract, and packaging pins are all present and match the plans' contracts. Conventions are honored throughout (frozen-string headers, CLAide `.concat(super)` pattern, `Core::Sh`-only shell-outs, planning-ID citations).

Residual defects found: one major (the router's error-envelope contract is only half-implemented — structurally-malformed or non-UTF-8 project files escape as raw WEBrick 500 HTML plus a terminal backtrace), three minors in the lifecycle races and CLI input validation, and four info-level items. No blockers: I verified the traversal defense at the WEBrick gem-source level (`httprequest.rb:219-220` unescapes then dot-segment-normalizes the path before dispatch, so encoded and literal `..` forms are both neutralized before the router even sees them, with the Assets basename+containment check behind it), confirmed WEBrick's pinned `>= 1.8` floor carries the escaped-HTML error-page fix, and traced every XSS-relevant data flow (module names, check messages, fix hints, JSON error messages) to a `textContent` sink. Accepted residuals: IN-08 (credential redaction) is phase-12 scope and not re-flagged; T-13-08 DoS acceptance and the ephemeral-port bind race stand as planned.

## Major Issues

### WR-01: Error-envelope contract only covers JSON parse errors — shape-malformed or non-UTF-8 project files produce raw WEBrick 500 HTML and a terminal backtrace
**Status:** resolved — fix 3c67e47 (13-REVIEW-FIX.md)

**File:** `lib/spm_cache/web/router.rb:121-155` (rescue at 129; `api_doctor` has no rescue at all), with `lib/spm_cache/web/read_models/state.rb:16-18` and `lib/spm_cache/cache/cachemap.rb:66-84` as the raising sites
**Issue:** The phase contract (13-01 behavior bullet, re-asserted in the router's own doc comment: "Malformed project files (graph.json) surface as the 500 error envelope") is implemented as `rescue JSON::ParserError` only. Three realistic hostile-project inputs escape it:
1. **Valid JSON, wrong shape** — `graph.json` holding an object instead of an array: `Cachemap.load` succeeds, then `graph_data.each_with_object` yields `[key, value]` pairs and `entry['module']` raises `TypeError: no implicit conversion of String into Integer` (state read model, `cachemap.rb:83` `modules_with_status`, `depgraph_for_viz`). Not rescued.
2. **Non-UTF-8 bytes planted in graph.json strings** (exactly the T-13-13 hostile-repo trust boundary 13-02 declares: "a hostile repo could plant hostile strings in module names/messages") — `JSON.generate` in `respond_json` raises `JSON::GeneratorError`. `GeneratorError` and `ParserError` are *siblings* under `JSON::JSONError`; the rescue does not catch it, and `respond_json` itself is outside the begin block.
3. **`api_doctor` has no rescue whatsoever** — the same GeneratorError escapes from `ReadModels::Doctor`'s JSON round-trip (`doctor.rb:64`).

Escape consequence: WEBrick's generic handler returns a non-contract HTML 500 (the UI degrades to "Couldn't load …: HTTP 500" instead of rendering the served message — the error-envelope copy path the UI was built for) and logs the exception + backtrace to the terminal at ERROR level, which the phase explicitly tried to keep quiet (T-13-03 posture). Note this is a robustness/contract defect, not an XSS: WEBrick ≥ 1.8 escapes error-page HTML, and the caught-ParserError path already renders messages through `textContent`.
**Fix:**
```ruby
# router.rb — api_read
rescue JSON::JSONError, TypeError => e   # JSONError covers Parser + Generator
  respond_json(res, 500, error_envelope(e.message))

# router.rb — api_doctor: wrap the call + respond
result = begin
  @read_models[:doctor].call(run: !req.query['run'].nil?)
rescue JSON::JSONError, TypeError, StandardError => e
  return respond_json(res, 500, error_envelope(e.message))
end
```
(Keep `Interrupt` out of the net — `StandardError` already excludes it.)

## Minor Issues

### WR-02: Concurrent `spm-cache web` launches race the marker check-then-write; the unconditional clear can orphan a live server's liveness record
**Status:** resolved — fix 13f4861 (13-REVIEW-FIX.md)

**File:** `lib/spm_cache/command/web.rb:44-56` (read → live? → probe → write with no mutual exclusion), `lib/spm_cache/web/marker.rb:61-63` (clear unlinks whatever sits at the path), `marker.rb:72-89` (live? is pid-only)
**Issue:** Two simultaneous invocations both observe a dead/absent marker before either writes; both boot servers on different ports (PortProber converges them onto distinct candidates), and the last `Marker.write` wins — the first server becomes an unrecorded zombie. Worse, `Marker.clear` is path-global: when the *overwritten* process later exits, its ensure deletes the *other live server's* marker, so the next `web` launch boots a third server instead of reusing it. All servers remain loopback-bound and token-gated, so this is a correctness/resource degradation of WEB-02's single-instance intent, not an exposure. (Plan 13-01 promised atomic marker writes — delivered — but never mutual exclusion.)
**Fix:**
```ruby
# a) boot lock (project precedent: build-lock flock, installer/build.rb:68)
lock_path = File.join(Core::Config.instance.web_dir, '.boot.lock')
File.open(lock_path, File::CREAT | File::RDWR, 0o600) do |lock|
  lock.flock(File::LOCK_EX)
  # ...existing marker read / probe / write / trap / start-ensure body...
end

# b) pid-guarded shutdown clear — only clear your own record
def self.clear(pid: nil, path: default_path)
  return if pid && (entry = read(path: path)) && entry['pid'] != pid
  File.unlink(path)
rescue Errno::ENOENT
  nil
end
```
Keep the heal-path clear (`Marker.clear if marker`) unconditional.

### WR-03: `Marker.clear`'s `exist?`-then-`unlink` race can crash the signal-cleanup ensure and break the exit-0 contract
**Status:** resolved — fix b1f0822 (13-REVIEW-FIX.md)

**File:** `lib/spm_cache/web/marker.rb:61-63`; consumer `lib/spm_cache/command/web.rb:64-68`
**Issue:** `File.unlink(path) if File.exist?(path)` — if the file vanishes between the check and the unlink (concurrent clear, i.e. WR-02's two-process exit, or any future second clearer), `Errno::ENOENT` is raised *from the ensure block*, propagating out of `run` after a successful shutdown and producing a non-zero exit — precisely what WEB-03's contract forbids.
**Fix:**
```ruby
def clear(path: default_path)
  File.unlink(path)
rescue Errno::ENOENT
  nil
end
```

### WR-04: Out-of-range `--port` values crash with a raw errno backtrace, contradicting `parse_port`'s "never a crash mid-verb" posture
**Status:** resolved — fix e3e16e5 + a55e031 (13-REVIEW-FIX.md)

**File:** `lib/spm_cache/command/web.rb:125-129` (`Integer()` accepts anything numeric), `lib/spm_cache/web/port_prober.rb:40-44` (`bind` rescues only `Errno::EADDRINUSE`)
**Issue:** `spm-cache web --port=-5` (or `--port=70000`, or a start port within 25 of 65536) passes `parse_port`, then `TCPServer.new` raises `Errno::EADDRNOTAVAIL`/`Errno::EPERM` — unrescued by `PortProber.pick` and `boot_with_retry` (both catch `EADDRINUSE` only) — escaping to `main.rb`'s bare re-raise: stderr dump + exit 1. The flag's own comment promises "user-authored CLI input … never a crash mid-verb"; the coercion handles `abc` but not numerically-valid garbage.
**Fix:**
```ruby
def parse_port(raw)
  port = Integer(raw || DEFAULT_PORT)
  (0..65_535).cover?(port) ? port : DEFAULT_PORT
rescue ArgumentError, TypeError
  DEFAULT_PORT
end
```
and/or in `PortProber.bind`, `rescue SystemCallError` → `nil` so any unbindable candidate is probed past and exhaustion raises the friendly `GeneralError`.

## Info

### IN-01: Graph re-render never destroys the previous cytoscape instance
**Status:** resolved — fix 52d35dc (13-REVIEW-FIX.md)

**File:** `lib/spm_cache/web/assets/app.js:273-278`
**Issue:** Every `renderGraph` (panel load, Refresh, poll-free reload after 0→N nodes) calls `window.cytoscape({ container: byId('cy-canvas'), … })` anew. Cytoscape instances own canvases, listeners, and graph objects inside the container; repeated refreshes stack instances in the long-lived tab.
**Fix:** hold one instance (`let cyGraph`) and `cyGraph?.destroy()` before re-creating (or update via `cyGraph.json({ elements: data.nodes })`).

### IN-02: Empty-state copy styles the non-command word "Refresh" as an accent `.cmd` span — deviation from the UI-SPEC accent contract
**Status:** resolved — fix 52d35dc (13-REVIEW-FIX.md)

**File:** `lib/spm_cache/web/assets/app.js:135-137, 257-259`
**Issue:** Copy text is verbatim per 13-UI-SPEC, but the Color contract reserves empty-state accent for "`spm-cache build` / `spm-cache use` command references"; `cmd('Refresh')` applies accent + mono to a plain word. (13-03-PLAN's "two command references" phrasing appears to have smuggled it in — worth a note to the UI checker for the post-phase audit.) Cosmetic.
**Fix:** render `Refresh` as plain text in both empty-state bodies (or introduce a non-accent emphasis class).

### IN-03: Dead surface — `Server#stop` alias and `Assets#root` reader have no callers
**Status:** resolved — fix 909e9c1 (13-REVIEW-FIX.md)

**File:** `lib/spm_cache/web/server.rb:59` (`alias stop shutdown`), `lib/spm_cache/web/assets.rb:34` (`attr_reader :root`)
**Issue:** Neither appears in `lib/` or any spec; both are unused API surface (verified by grep across lib + spec).
**Fix:** delete both, or wire `stop` into a spec if it is intended as public API.

### IN-04: Doctor check-line ellipsis will hard-clip instead of ellipsizing — flex children lack `min-width: 0`
**Status:** resolved — fix 52d35dc (13-REVIEW-FIX.md)

**File:** `lib/spm_cache/web/assets/styles.css:270-295`
**Issue:** `.check-name`/`.check-message` set `overflow: hidden; text-overflow: ellipsis` inside a flex row, but flex items default to `min-width: auto`, so long check names/messages (the "long-text" UI-SPEC row) can push siblings out and clip without the ellipsis glyph.
**Fix:** add `min-width: 0;` (and `flex: 0 1 auto;`) to `.check-name` and `.check-message`.

## Verified Clean (adversarial checks that found nothing)

- **Token compare timing (T-13-06):** SHA256-digest both sides then XOR-fold; wrong-length tokens pay full compare (spec pins it).
- **Host/Origin allowlists:** exact `"host:port"` / `"scheme://host:port"` membership from the bound port only; case-insensitive host, `null` Origin rejected, userinfo-bearing and IPv6 Host forms rejected by construction; gate order Host→Origin→token is method-agnostic (structural via the single servlet `service` override).
- **Path traversal (T-13-04):** three independent layers — WEBrick `unescape` + `normalize_path` before dispatch (verified in gem source, `httprequest.rb:219-220`), basename-only validation (separators/backslash/`..`/leading-dot/NUL), and `expand_path` containment; matrix spec drives the encoded forms end-to-end.
- **Token leakage (T-13-03):** `AccessLog: []` with rationale; marker 0600 via chmod-before-rename; bootstrap redirect is the only token delivery; `no-store` + `X-Frame-Options: DENY` on every response; stdout asserted token-free; dev `.gitignore` entry present; `main.rb:21` web run-log exclusion intact.
- **XSS (T-13-13):** no `innerHTML`/`outerHTML`/`document.write`/`eval`/`new Function` in app.js; all dynamic strings via `textContent`/`createTextNode`; server error messages rendered through the same sink; class-name interpolation of server strings is inert attribute assignment; cytoscape labels are canvas-drawn; vendored cytoscape is committed (v3.34.2, 436 KB, version comment without scheme URL) and first-party assets pass the offline grep gate.
- **Marker (T-13-05):** lstat symlink-reject on read, rename-replaces-symlink on write, malformed/absent → nil → heal-on-restart; `Process.kill(0)` liveness mirrors the `run_log.rb` precedent.
- **Doctor honesty (T-13-10/T-13-11):** mutex-guarded atomic `{data, generated_at}` swap; cached stamp passed through verbatim (nil before first run, integration-pinned); registry is the only check source; per-check `StandardError` rescue in `run_check` keeps `run_all` total.
- **One-source-of-truth:** `Inventory.scan` has exactly two production callers; `Diagnostics.payload` shared by CLI and read model; `cache list` output preserved (spec-pinned); envelope shape untouched across all three endpoints.
- **Packaging:** webrick `>= 1.8, < 2` runtime declaration with research-verdict comment; glob-ships-assets pin plus real `gem build` smoke.
- **Conventions:** frozen-string literals on every new `.rb` file, CLAide parse-before-super + `.concat(super)`, `Core::Sh`-only execution, `Struct keyword_init`, planning-ID citations — all conform to `.planning/codebase/CONVENTIONS.md`.

---

_Reviewed: 2026-09-01T06:12:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep_
