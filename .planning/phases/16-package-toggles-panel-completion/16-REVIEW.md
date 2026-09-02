---
phase: 16-package-toggles-panel-completion
reviewed: 2026-09-02T00:25:10Z
depth: deep
files_reviewed: 8
files_reviewed_list:
  - lib/spm_cache/core/config.rb
  - lib/spm_cache/command/off.rb
  - lib/spm_cache/core/lockfile.rb
  - lib/spm_cache/installer.rb
  - lib/spm_cache/web/router.rb
  - lib/spm_cache/web/jobs.rb
  - lib/spm_cache/web/read_models/state.rb
  - lib/spm_cache/web/assets/app.js
  - lib/spm_cache/web/assets/styles.css
findings:
  critical: 1
  warning: 2
  info: 0
  total: 3
status: resolved
---

# Phase 16: Code Review Report

**Reviewed:** 2026-09-02T00:25:10Z
**Depth:** deep (cross-file trace: router -> read model -> config/lockfile; frontend event/state trace against 16-UI-SPEC)
**Files Reviewed:** 8 production files (styles.css scanned, no logic to review)
**Status:** resolved (all 3 findings fixed)

## Summary

Reviewed the full `317ce64..HEAD` diff against the pinned contracts (D-01..D-09, the sidecar-lock design, the five-reason precedence, D-06 saved/applied semantics). The sidecar-lock lifecycle, atomic tmp+rename save, in-lock re-read, `LOCK_EX` blocking semantics, the shared `off`/`POST /api/toggle` mutator, the binary-target derivation plumbing (installer.rb -> lockfile.rb -> state.rb), and the five-reason precedence chain are all correctly implemented and match their documented contracts — I could not fault the concurrency-critical mutator path itself.

One **Critical** finding: `POST /api/toggle` and `POST /api/revert` call the state read model directly without the exception guard `GET /api/state` uses for the exact same call, so a realistic (non-adversarial) failure mode — a malformed `graph.json` or a corrupted `spm-cache.lock` — crashes the request instead of returning the router's own documented JSON error envelope, violating the file's own pinned "terminal stays quiet" (T-13-03) invariant. Reproduced against the actual code (not simulated).

Two **Warnings**: a narrower-than-documented rescue clause in `lockfile_binary_names` (a contributing cause of the Critical finding for the lockfile case specifically), and a config-semantics edge case where toggling an exact-override row back to "cached" silently reverts to a no-op when a broader ignore pattern also matches the same name — the mutator succeeds, the checkbox flips, but the package is never actually cached, and nothing tells the user.

**Resolution:** all three findings fixed, atomic commits, RED-first: CR-01 `31b73a2`, WR-01 `f7c20ba`, WR-02 `aec5025`. Full suite green (`bundle exec rspec`: 1095 examples, 0 failures, up from the 1088/0 baseline — the 7 new resolution-verification tests: 2 for CR-01, 1 for WR-01, 4 for WR-02) after all three commits. See each finding's own **Resolution** paragraph below for what changed and how it was verified.

## Critical Issues

### CR-01: `POST /api/toggle` and `POST /api/revert` crash (uncaught exception) on the same read-model failures `GET /api/state` already handles

**File:** `lib/spm_cache/web/router.rb:354` (also `:392`)
**Issue:**

`api_read` (the `GET /api/state` handler) explicitly wraps the state read model call in a rescue for exactly this reason (its own comment, `router.rb:150-159`):

> "Malformed project files (graph.json) surface as the 500 error envelope... JSONError covers ParserError AND its sibling GeneratorError... TypeError covers shape-malformed JSON — e.g. graph.json holding an object..."

```ruby
# router.rb:172-183 (api_read)
begin
  respond_json(res, 200, ok_envelope(@read_models[model].call(config: @config)))
rescue JSON::JSONError, TypeError => e
  respond_json(res, 500, error_envelope(e.message))
end
```

`api_toggle` (`router.rb:333-370`) and `api_revert` (`router.rb:379-408`) call the identical `Web::ReadModels::State.call` with **no such guard**:

```ruby
# router.rb:354 (api_toggle)
row = @read_models[:state].call(config: @config)['packages'].find { |r| r['name'] == package }
...
# router.rb:392 (api_revert)
pending = @read_models[:state].call(config: @config)['packages'].select { |row| row['pending'] }
```

Only the *mutator* call further down each method is wrapped in `rescue StandardError` (`config_write_failed`, tested in `spec/web_toggle_routes_spec.rb:288-302,455-465`) — the *read* call that runs first, to derive `toggleable`, is unprotected. Any exception it raises escapes to WEBrick's generic handler, which (a) prints the backtrace to `$stderr` via the `WEBrick::Log::ERROR` logger configured in `web/server.rb:36`, directly violating this file's own pinned invariant ("a web request has no stream and the terminal running `spm-cache web` stays quiet (T-13-03)", `router.rb:129`), and (b) returns WEBrick's default HTML 500 page instead of the router's `{status, data}` JSON envelope contract every other rejection in this file honors.

Reproduced against the real code (not simulated) with two realistic, non-adversarial triggers:

1. **Malformed `graph.json`** (e.g. left as a JSON object instead of an array by an interrupted/older proxy run — exactly the shape `api_read`'s own comment names):
   ```
   $ bundle exec ruby -Ilib repro.rb   # graph.json = {"foo":"bar"}
   CRASHED as predicted: TypeError: no implicit conversion of String into Integer
   ```
2. **Corrupted `spm-cache.lock`** (e.g. truncated by a process killed mid-write — `Lockfile#save` at `lockfile.rb:79-83` is a plain `File.write`, not the atomic tmp+rename pattern `Config#save` uses, so a truncated file is a real possibility, not a contrived one):
   ```
   $ bundle exec ruby -Ilib repro2.rb   # spm-cache.lock = '{"MyApp": {"packages": ['
   CRASHED as predicted: JSON::ParserError: unexpected end of input at line 1 column 25
   ```

Both crash `Web::ReadModels::State.call` directly, which is exactly what `api_toggle`/`api_revert` call unguarded.

**Fix:** wrap the state-read call in both routes the same way `api_read` does (or, cleaner, factor a `read_state!` helper both `api_read`, `api_toggle`, and `api_revert` share):

```ruby
def api_toggle(req, res, supplied)
  ...
  packages =
    begin
      @read_models[:state].call(config: @config)['packages']
    rescue JSON::JSONError, TypeError => e
      return respond_json(res, 500, error_envelope(e.message))
    end
  row = packages.find { |r| r['name'] == package }
  ...
end
```
and the equivalent in `api_revert`.

**Resolution (fixed):** `31b73a2` — added a shared `read_state_packages(res)` helper on `Router` carrying the exact `rescue JSON::JSONError, TypeError` set `api_read` uses; `api_toggle` and `api_revert` now call it instead of `@read_models[:state].call` directly, and bail on `nil` (the helper has already written the 500 envelope). Verified against the same two triggers the review reproduced: `spec/web_toggle_routes_spec.rb` "read-model failure (CR-01 ...)" — malformed `graph.json` (an object) now answers 500 with the JSON envelope for `/api/toggle`, and truncated `graph.json` answers 500 for `/api/revert`, both RED before the fix (WEBrick's raw HTML 500 page) and GREEN after.

## Warnings

### WR-01: `lockfile_binary_names`'s rescue is narrower than its own documented contract

**File:** `lib/spm_cache/web/read_models/state.rb:140-148`
**Issue:** the method's own comment claims totality:

> "Total by construction -- missing keys, absent packages, unknown projects, and unflagged legacy entries all fall through to nothing... because the web tier calls this on every state poll and a raise here would take out the whole panel."
> "Absent lockfile -> no projects -> empty Set; unreadable (permission) errors degrade the same way -- the binary-target reason simply never fires rather than raising."

but the implementation only rescues permission errors:

```ruby
def self.lockfile_binary_names(config)
  lockfile = Core::Lockfile.new(config.lockfile_path)
  lockfile.projects.keys.each_with_object(Set.new) do |project_name, names|
    names.merge(lockfile.binary_backed_names(project_name))
  end
rescue SystemCallError
  Set.new
end
```

`Core::Lockfile#load` (`lockfile.rb:69-77`) does `JSON.parse(content)` with no rescue of its own, so a corrupted (not merely unreadable) `spm-cache.lock` raises `JSON::ParserError` here, which is **not** a `SystemCallError` and is not caught — contradicting "a raise here would take out the whole panel" and (per CR-01) actually doing so for `/api/toggle`/`/api/revert`.

**Fix:** widen the rescue to match the documented contract:
```ruby
rescue SystemCallError, JSON::ParserError
  Set.new
end
```

**Resolution (fixed):** `f7c20ba` — widened the rescue to `rescue SystemCallError, JSON::ParserError` exactly as suggested, and corrected the method's doc comment (it previously claimed totality it didn't have). Verified with a RED-first unit test (`spec/web_state_spec.rb` "the read path stays total" — corrupted `spm-cache.lock`): raised `JSON::ParserError` before the fix, degrades to `reason: nil` / `toggleable: true` (the honest empty-Set answer) after.

### WR-02: toggling an exact-override entry back to "cached" is a silent no-op when a broader ignore pattern also matches the same name

**File:** `lib/spm_cache/web/read_models/state.rb:173-176` (`pattern_managed?`), consumed by `router.rb:333-370` (`api_toggle`)
**Issue:** by design (Pitfall 5, `16-RESEARCH.md:437-441`), a row with its own exact `ignore` entry is always toggleable, even when a separate glob pattern in the same list also matches its name — `pattern_managed?` only fires when *no* exact entry exists (`spec/web_state_spec.rb:335-344` pins exactly this: `GlobExact` stays toggleable/`reason: nil` even though `Glob*` also matches it).

The gap: nothing stops a user from *acting* on that toggleability in the direction that matters. If `spm-cache.yml` has both `Glob*` and `GlobExact` in `ignore`, and the user clicks `GlobExact`'s checkbox to re-enable caching:

1. `POST /api/toggle {package: "GlobExact", cached: true}` passes validation (`toggleable == true`) and calls `@config.set_ignored('GlobExact', false)`, which removes only the exact `GlobExact` entry — `Glob*` is untouched.
2. The write succeeds (200 OK) and the checkbox flips to checked.
3. `GlobExact` is **still** ignored in reality (`Config#should_ignore?` still matches `Glob*`), so the package will never actually be cached by any subsequent Apply-now/sync.
4. On the next poll, `pattern_managed?('GlobExact', ...)` now evaluates true (the exact entry is gone, the pattern still matches), so the row flips to `toggleable: false, reason: 'pattern-managed'` — but `saved_cached` is still computed purely from exact-entry absence (`state.rb:74`: `!saved_ignored.include?(entry.name)`), so the now-disabled checkbox renders **checked** next to the `pattern-managed` chip, permanently, with the `pending` bar never surfacing the divergence (pattern-managed rows are excluded from `pending` by construction, `state.rb:88`).

The user's action was accepted, produced no error, and had zero real effect — with no code path that ever tells them so. This is exactly the warning sign `16-RESEARCH.md:441` calls out ("a toggle that 'works' ... but the row stays graph-ignored forever"), just in the opposite direction (toggling *on* instead of *off*), and it is not covered by `spec/web_state_spec.rb` or `spec/web_toggle_routes_spec.rb` (both only test the two ends — exact-only and pattern-only — never the coexistence-then-toggle sequence).

**Fix (either is consistent with the phase's existing D-09 vocabulary and requires no new UI copy):**
- Have the toggle-on path additionally check `should_ignore?(package)` after removing the exact entry and, if still matched by a pattern, respond `400 not_toggleable` instead of `200` (fail loud rather than silently no-op) — the read model already has `should_ignore?` available via `Config`; or
- Fold this case into `pattern_managed?`'s precedence directly (drop the `!saved_ignored.include?(name)` exact-entry carve-out when *another*, different pattern entry also matches), which changes `GlobExact`'s classification but removes the reachable dead-end entirely.

Either fix is a genuine design call outside this review's remit; flagging the gap is the review's job.

**Resolution (fixed):** `aec5025` — took the review's first option (400, fail loud), scoped to a pre-mutation check rather than a post-mutation one: `State.would_remain_pattern_ignored?(package, config)` reads the SAME fresh-from-disk ignore list `saved_ignore_list` already uses (never the config singleton's boot-time `@raw`, preserving CP1) and asks whether a DIFFERENT pattern would still match `package` once its own exact entry is hypothetically removed — with no mutation performed either way. `api_toggle` calls this only for the turn-ON direction (`cached: true`) after the existing `toggleable` gate and before the mutator runs; on a hit it answers `400` with the new machine reason `still_pattern_ignored` and the config is left completely untouched (not even the exact entry is removed), so the write is never partially applied and the dead-end state described in the Issue (checkbox stuck checked next to the `pattern-managed` chip) can no longer occur. No new UI copy was needed: `app.js`'s existing `Couldn't save the toggle for {package}: {message}...` template already renders any server `message` verbatim (reasons are for programs, per the router's own pinned comment), so `16-UI-SPEC.md`'s copy table required no amendment. Turning OFF (`cached: false`) is unaffected — that direction only ever adds ignore coverage, so no dead end is reachable from it. Verified with `spec/web_state_spec.rb` (unit: `would_remain_pattern_ignored?` true only when a different pattern survives) and `spec/web_toggle_routes_spec.rb` "exact-entry-under-glob toggle-on (WR-02 ...)" (3 integration rows: the rejection + untouched disk state, the OFF direction unaffected, and the true-positive re-enable case with no surviving pattern), RED before the fix (200 + orphaned exact-entry removal), GREEN after.

---

## Sections confirmed clean (no findings)

- **Sidecar-lock lifecycle** (`config.rb:120-152`): correctly locks the sidecar (never the yml inode), blocks with `LOCK_EX` (not `LOCK_NB`), re-reads fresh under the lock via `reset! + load`, assigns new arrays (never mutates `DEFAULT_CONFIG`'s shared inner array), and unlocks/closes in `ensure` even when `save` raises.
- **Atomic save** (`config.rb:78-96`): same-directory `Tempfile` + `chmod` (before rename) + `File.rename`; mode preserved for existing files, house default (`0o644`) for new ones; byte-identical rendered output.
- **`off`/`POST /api/toggle` parity** (`off.rb`, `config.rb:set_ignored_all`): the batch-merge algorithm (`(current + [package]).uniq` / `current - [package]`) reproduces the pre-refactor `(ignore_list + targets).uniq` ordering exactly, including with duplicate CLI arguments.
- **`POST /api/toggle` body validation** (`router.rb:333-352`): rejects non-string/blank `package`, rejects any non-boolean `cached` (no truthy coercion), 404s on a package absent from the row universe, 400s on a non-toggleable row, all before the mutator runs.
- **Slot interplay** (`router.rb:97-110`, D-08): `/api/toggle` and `/api/revert` never reference `@jobs`; only `/api/apply` claims the shared spawn slot; matches "toggle/revert instant, apply slot-gated."
- **Five-reason precedence** (`state.rb:157-176`): `excluded > plugin > binary-target > pattern-managed > fidelity`, first-hit-wins control flow, matches `spec/web_state_spec.rb:182-208`'s end-to-end precedence chain.
- **`binary_target` derivation** (`installer.rb:407-427`, `lockfile.rb:150-176`): `Target#binary?` dispatch via `Target.from_raw`/`BinaryTarget` verified correct; `binary_target` and `products[]` are invalidated together (`installer.rb:449-457`) so they can never drift; a failed `swift package describe` degrades to `binary_target: false` honestly rather than guessing; the identity-fallback key names (`repositoryURL`/`path_from_root`, never `url`/`path`) match the established convention used identically elsewhere in the codebase (`checkout_resolver.rb:81`, `lockfile.rb:118`).
- **Frontend toggle/poll integrity** (`app.js`): the in-flight *counter* (not boolean) correctly tolerates overlapping toggle POSTs without unskipping the poll early; the toggle-failure line is a genuinely separate DOM node/class from the panel's own fetch-error line; no `innerHTML`/`insertAdjacentHTML`/`document.write` anywhere, all dynamic strings (package names, reason words, envelope messages) go through `textContent`/`setAttribute` — no XSS surface from server-controlled reason/package strings.
- **Unsaved-changes bar / Apply-now / Revert-all** (`app.js`): freeze-set extension to the bar's `Apply now` button is looked up fresh on every render (never a stale cached node reference, since the bar is rebuilt on every table render); `Revert all` correctly excluded from the freeze set per A3; `clickRevert`'s inverse-of-`applied_cached` computation (`router.rb:400`) is semantically correct in both directions (cached→ignored and ignored→cached).
- **Column widths** (`styles.css`): the six `.col-*` percentages sum to exactly 100%.
- **YAML/JSON injection**: package names and reason strings round-trip through `YAML.dump`/`JSON.generate`, which quote/escape correctly; `YAML.safe_load` (default `permitted_classes`, no explicit widening) blocks arbitrary object instantiation from a hostile `spm-cache.yml`.

## Counts

- Critical: 1
- Warning: 2
- Info: 0
- **Total: 3**
- **Resolved: 3/3**

---

_Reviewed: 2026-09-02T00:25:10Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep_

---

_Fixed: 2026-09-02_
_Fixer: Claude — CR-01 `31b73a2`, WR-01 `f7c20ba`, WR-02 `aec5025`_
_Verification: full suite green, `bundle exec rspec` — 1095 examples, 0 failures (baseline 1088/0 + 7 new resolution-verification tests)_
