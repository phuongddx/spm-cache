# Phase 16: Package Toggles + Panel Completion - Research

**Researched:** 2026-09-02
**Domain:** Shared config mutators with locked merge-write (flock + atomic rename), saved-vs-applied derivation in the cache-state read model, per-row WHY-not reasons from persisted facts, and one instant POST route beside the Phase 15 slot machinery
**Confidence:** HIGH — every integration seam re-read at file:line this session; the load-bearing write-path semantics (Psych comment loss, the off write shape, stale-writer clobber, cross-process flock, rename-vs-lock-chain, sidecar stability, fnmatch exactness) **machine-probed live on this machine** (PROBED marks below)

## Summary

Phase 16 makes the dashboard a config-writer. The one source of truth is the `ignore` array in `spm-cache.yml` — today an array of `File.fnmatch` glob patterns that only `spm-cache off` writes, via `Config#save`'s plain `File.write(@config_path, YAML.dump(@raw))` (config.rb:65-71). That save is neither atomic nor locked, and `off`'s flow (load → merge whole array → save) is a last-writer-wins full-file clobber: PROBED, a stale second writer silently discards the first writer's entry. D-03/D-04's shared mutator with a locked merge-write therefore lands inside `Config` (both callers inherit it), and the D-05 comment-loss honesty note is not hypothetical — PROBED: the very first `off` already rewrites the user's commented yml into a bare 9-key dump.

The decisive design finding is PROBED P5: **a tmp+rename write silently breaks an flock held on the file being replaced** — a waiter wakes up holding a lock on a dead inode, and a new opener of the new inode is unblocked. D-04's "flock on the config" must therefore target a **sidecar lock file** (e.g. `spm-cache.yml.lock`), PROBED inode-stable across config rewrites (P6), using the repo's own build-lock idiom (`File.open(path, File::CREAT | File::RDWR)` + `LOCK_EX|LOCK_NB` truthiness probe, build.rb:88-104 — Ruby's `flock` with `LOCK_NB` returns `false`, it never raises). Algorithm: lock sidecar → `config.load` (fresh re-read kills CP1's boot-time snapshot) → assign the one key (never `<<` — DEFAULT_CONFIG's inner arrays are unfrozen and shared by `dup`) → `save` via the same-dir Tempfile+rename precedent (marker.rb:43-53, run_log.rb:126-141) → unlock in ensure. Put the whole thing in the mutator and CLI-vs-web races are closed for free.

Saved-vs-applied is already half-served: saved = the ignore list on disk (exact-entry test `ignore_list.include?(name)` for toggleable rows), applied = graph.json's per-module `status` — written by the gen tool with exactly the vocabulary `hit/missed/ignored/excluded/plugin` (ProxyGenerator.swift:18). Four of the five TOGL-03 reasons derive from facts that persist today: `pattern-managed` (matched by a non-exact pattern), `plugin` (graph status `plugin` = plugin-only packages), `excluded` (cache-only inverted allowlist), `fidelity` (provenance-sidecar `fidelity_status`). The one genuine gap: **`binary-target` is not persisted anywhere the web tier reads** — graph entries carry only module/status/hasMacro, metadata files carry target names only, and the lockfile enrichment (installer.rb:390-421) runs `swift package describe` but stores product-level `{name, type, targets}` and discards target types. The cheapest honest fix is one derived field in that enrichment (Ruby-side only; the Swift tool already ignores unknown lockfile keys — installer.rb:430-432).

**Primary recommendation:** one `Config` mutator (`set_ignored(package, boolean)` shape) doing sidecar-flock → fresh load → key-level assign → tmp+rename save, shared by `off` and `POST /api/toggle`; `POST /api/apply` = `Jobs::SCOPES` gains `'use'`; `POST /api/revert` = the same mutator batched; `/api/state` rows gain `toggleable`/`reason`/saved+applied derived once server-side (fresh disk read per call — the state model never loads config today); the frontend reuses `requestPost` verbatim and amends `CTRL.busy` to the three-verb string (app.js:324).

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions (D-01..D-09, 16-CONTEXT.md — verbatim where load-bearing)
- **D-01 (placement):** toggles live IN the Cache State panel's existing per-package table — one new column of native checkboxes (checked = cached, unchecked = ignored), disabled with a reason chip where not toggleable. No new panel, no separate toggles view.
- **D-02 (control):** native `<input type="checkbox">` per row — keyboard operable, no ARIA-reinvented switch. Reversible.
- **D-03 (shared mutators):** `spm-cache off` is refactored onto shared config mutators (e.g. `Config#set_ignored(package, boolean)`) and the web POST uses the SAME path — one source of truth, CLI behavior unchanged (its own specs stay green byte-identical on the free path). **Costly to change — `off` is a published CLI contract; the refactor must be behavior-preserving.**
- **D-04 (atomic + clobber-proof save):** same-dir tempfile + rename pattern (the run_start-header precedent) and a read-merge-write under an flock on the config (the build-lock precedent): take the lock, RE-READ, merge the one toggled key, write, release.
- **D-05 (comment-loss honesty — roadmap-pinned):** the yml rewrite drops hand-written comments; the UI SURFACES this verbatim-pinned in the apply/undo copy.
- **D-06 (semantics):** a row's checkbox reflects SAVED config (the ignore list on disk). "Applied" = what the last sync actually used (the graph/lockfile truth the read model already serves). Divergence ⇒ unsaved-changes bar: copy + exactly ONE `Apply now` + a revert-all affordance.
- **D-07 (Apply-now mechanics):** spawns the real re-sync (`spm-cache use`) through Phase 15's Web::Jobs slot (trigger 'ui', same single-slot 409 semantics, same stream view). No second sync mechanism, no server-side config applying.
- **D-08 (mutation route):** POST /api/toggle (single package per request, `{package, cached}`) behind the same structural gate + per-route body validation, 409 shared with build/rollback for the slot; the toggle POST itself is instant config write, NOT slot-gated.
- **D-09 (vocabulary):** exactly five reasons — `pattern-managed` / `plugin` / `binary-target` / `excluded` / `fidelity` — derived in the read model (server-side, one derivation), rendered as text chips with title tooltips. No new reason strings client-side.

### Claude's Discretion (16-CONTEXT)
Exact endpoint path names, request/response envelopes, the mutator method names, the merge algorithm details (key-level vs list-level for the ignore list), and the chip styling. 16-UI-SPEC (approved) additionally pins working paths `POST /api/toggle` `{"package": "<raw name>", "cached": <bool>}`, `POST /api/apply` (empty body), `POST /api/revert` (empty body); poll-skip integrity while a toggle POST is in flight (redraw AND stamp skipped); no client-side reason derivation; unknown reasons render verbatim-neutral; endpoint paths are A9 working names.

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| TOGL-01 | Toggles persist to the same config ignore list `spm-cache off` writes — one source of truth, `off` refactored onto shared mutators, atomic save | Ignore-list truth + off write path mapped and PROBED (§Q1); shared mutator + sidecar-flock merge-write design with rename-vs-lock PROBED verdict (§Q2); off's behavior-preservation surface (byte-identical free path, output lines, no existing Off spec — new pins required) |
| TOGL-02 | Toggle UI shows saved-vs-applied with explicit Apply-now (re-sync) | Applied truth = graph.json status (ProxyGenerator.swift:18 vocabulary), saved = ignore list on disk; divergence derivation + poll-skip integrity seams at app.js:156-168/130-151; Apply-now = `use` scope through the existing Jobs slot (jobs.rb:39-43 SCOPES table, command/use.rb bare-verb verified) |
| TOGL-03 | Non-toggleable packages show WHY (pattern-managed / plugin / binary-target / excluded / fidelity) | Four reasons map to persisted facts (config patterns; graph `plugin`/`excluded` statuses; provenance `fidelity_status`); `binary-target` gap proven negative with the enrichment seam recommended (§Q4); one server-side derivation in `State.call` with unknown→neutral fallback |
</phase_requirements>

## Machine Probes (PROBED — this machine, Ruby 3.2.3 rbenv, macOS/darwin arm64, 2026-09-02)

| # | Probe | Result |
|---|-------|--------|
| P1 | Psych round-trip of the shipped `spm-cache.yml.template` (comments, key order, shapes) | Comments DROPPED (`safe_load` → `dump`); key order = insertion order preserved; `ignore` parses as Array |
| P2 | Live exercise of the exact off.rb:16-22 write path against a tmp-dir config seeded with the real template | File rewritten as bare 9-key YAML.dump (`---` + every DEFAULT_CONFIG key, list-dash style); template comments GONE on first write |
| P3 | Stale-writer race simulation (server writes `ignore: [A]`, then a CLI holding a pre-write snapshot saves `ignore: [B]`) | Last-writer-wins full-file clobber: `A` silently lost — today's lost-update window is real, not theoretical |
| P4 | Cross-process flock (parent holds `LOCK_EX` on a `CREAT\|RDWR` fd; forked children probe) | Child `'r'` fd REFUSED; child `CREAT\|RDWR` fd REFUSED — flock conflicts cross-process as expected. **Ruby's `File#flock(LOCK_EX\|LOCK_NB)` returns `false` when blocked, never raises** (verdict = truthiness, exactly build.rb:99's `unless lock.flock(...)` idiom) |
| P5 | Rename over a flock-held file: hold lock on yml, `File.rename(tmp, yml)`, new process opens the path and probes | **ACQUIRED** — the rename replaced the inode; the lock chain is broken. A lock on the config file ITSELF is unsound under a tmp+rename writer |
| P6 | Sidecar lock file (`spm-cache.yml.lock`) held while the config is rewritten by rename underneath | REFUSED (still held) — the sidecar is inode-stable across content rewrites; it is the sound lock target |
| P7 | `File.fnmatch` exactness | `fnmatch('ExactName','ExactName')` → true; case-SENSITIVE (`exactname` ≠ `ExactName`); `Test*`/`MyCompany?` globs match as config_spec pins; `.` is literal (`A.B` ↛ `AxB`) |
| — | (bg job) blocking-flock positive case | The probe's blocking row hung on its own test harness; the positive case is nonetheless PROVEN in production: installer/build.rb:99-102's blocking flock + release-on-ensure is shipped, exercised behavior (build_lock_spec.rb fork-based OS-lock proof) |

## Research Question Verdicts

### Q1 — Config ignore-list truth: shape, load/save path, what `off` writes, atomicity gaps, the shared-mutator surface

**Shape** [VERIFIED: lib/spm_cache/core/config.rb:15-31, 150-152, 201-203; spec/config_spec.rb:142-173]:

```ruby
# config.rb:15-31 (verbatim keys) — 'ignore' is an Array of fnmatch glob patterns
DEFAULT_CONFIG = {
  'ignore' => [],
  'cache_only' => [],
  'ignore_local' => false,
  'ignore_build_errors' => false,
  'keep_pkgs_in_project' => false,
  'default_sdk' => 'iphonesimulator',
  'runs_keep' => 50,
  'runs_max_mb' => 500,
  'web_poll_seconds' => 5
}.freeze
```

```ruby
# config.rb:150-152, 201-203 (verbatim)
def ignore_list
  raw['ignore'] || []
end

def should_ignore?(package_name)
  ignore_list.any? { |pattern| File.fnmatch(pattern, package_name) }
end
```

Patterns are globs: exact names, `Test*`, `MyCompany?` (config_spec.rb:142-164 pins all three) [PROBED P7: case-sensitive, `.` literal].

**Load/save path** [VERIFIED: lib/spm_cache/core/config.rb:57-71]:

```ruby
# config.rb:57-71 (verbatim)
def load(path = nil)
  @config_path = path if path
  if @config_path && File.exist?(@config_path)
    @raw = DEFAULT_CONFIG.merge(YAML.safe_load(File.read(@config_path)) || {})
  end
  @raw
end

def save(path = nil)
  @config_path = path || @config_path
  return unless @config_path

  FileUtils.mkdir_p(File.dirname(@config_path))
  File.write(@config_path, YAML.dump(@raw))
end
```

- **`save` is a plain truncating `File.write`** — no tempfile, no rename, no lock. Atomicity gaps: (a) torn-write window (crash mid-write leaves a truncated/empty yml), (b) lost-update window (last full-file writer wins). Both closed by the §Q2 merge-write.
- **Singleton staleness (CP1) is real and structural:** `Command::Web` loads config ONCE at boot (web.rb:41-43 `config = Core::Config.instance; config.load`); the server's `@raw` is a boot-time snapshot. `off` runs in its own process (fresh `load`, off.rb:18) so today nobody notices — but the web toggle route and the state read model MUST NOT trust the singleton's `@raw` for saved truth. `State.call` receives the singleton and never calls `load` [VERIFIED: web/read_models/state.rb:15-17].
- **Shallow-dup hazard:** `.freeze` on DEFAULT_CONFIG (config.rb:31) freezes the hash, NOT the inner arrays; `@raw = DEFAULT_CONFIG.dup` (config.rb:43) shares them until a `load` replaces `raw['ignore']` with the parsed YAML array. `raw['ignore'] << x` on a never-loaded instance would pollute DEFAULT_CONFIG process-wide. The mutator must ASSIGN (`raw['ignore'] = new_list`), never mutate in place — off.rb:20-22 already models the assignment shape.

**What `spm-cache off` writes today** [VERIFIED: lib/spm_cache/command/off.rb:16-26 + PROBED P2]:

```ruby
# off.rb:16-26 (verbatim run body)
def run
  config = Core::Config.instance
  config.load

  ignore = config.ignore_list + @targets
  config.raw["ignore"] = ignore.uniq
  config.save

  puts "Added #{@targets.join(', ')} to ignore list"
  puts "Run 'spm-cache' to use source mode for these targets"
end
```

PROBED P2 output (verbatim, seeded from the real template):

```yaml
---
ignore:
- NewPkg
cache_only: []
ignore_local: false
ignore_build_errors: false
keep_pkgs_in_project: false
default_sdk: iphonesimulator
runs_keep: 50
runs_max_mb: 500
web_poll_seconds: 5
```

Every save serializes the FULL merged raw (all 9 keys — defaults materialize into the file on first save), and **comments are already dropped by today's `off`** (P1/P2) — D-05's honesty copy describes existing behavior, not a new cost.

**Shared-mutator surface + behavior-preserving constraints:**
- The mutator (planner pins the name; `set_ignored(package, boolean)` per D-03's example) lives on `Config`, does the §Q2 locked merge-write internally, and both `off` and the web POST call it. Key-level merge (replace the exact entry in `raw['ignore']`) is the natural grain — list-level (whole-array swap) would clobber concurrent pattern edits.
- **`off` has NO spec today** [VERIFIED: no `command_off_spec.rb` in spec/; grep across spec/*.rb finds no `Command::Off` reference]. "Byte-identical on the free path" therefore needs NEW spec rows pinned in the same task that lands the refactor: the two output lines byte-exact (off.rb:24-25), exit status unchanged, the written file byte-identical to today's YAML.dump shape on the uncontended path, and config_spec.rb's existing rows untouched.
- Keeping off.rb's own `config.load` (off.rb:18) is harmless but redundant once the mutator loads under the lock — planner call (removal keeps exactly one load path).

### Q2 — Locked merge-write design: flock target, algorithm, failure posture

**The flock target must be a SIDECAR, not the yml inode.** PROBED P5: after `File.rename(tmp, yml)` over a lock-held yml, a fresh opener of the path ACQUIRES immediately — rename replaces the inode and orphans the lock. PROBED P6: a sidecar (`spm-cache.yml.lock`) stays locked across config rewrites. Cross-process contention itself works exactly as the build lock relies on (PROBED P4; build_lock_spec.rb's fork proof).

**Idiom to copy** [VERIFIED: lib/spm_cache/installer/build.rb:88-104, 106-112]:

```ruby
# build.rb:88-104 (verbatim acquire shape; the merge-write's lock half mirrors it)
def acquire_build_lock
  path = @config.build_lock_path
  FileUtils.mkdir_p(File.dirname(path))
  lock = File.open(path, File::CREAT | File::RDWR)
  # D-05: probe -> announce -> block. LOCK_NB returns false (never
  # raises) under contention ...
  unless lock.flock(File::LOCK_EX | File::LOCK_NB)
    Core::UI.info 'Waiting for build lock…'
    lock.flock(File::LOCK_EX)
  end
  lock
end
```

**Recommended algorithm (inside the shared mutator — both callers inherit clobber-proofing):**

1. `lock = File.open("#{@config_path}.lock", File::CREAT | File::RDWR)`; `flock(LOCK_EX | LOCK_NB)` probe → blocking `flock(LOCK_EX)` (click-granularity writers make blocking right; no announce — a web request has no stream, and printing to the web terminal breaks T-13-03's quiet posture).
2. **Under the lock:** `load` (fresh re-read — destroys CP1's snapshot), apply the ONE key: cached → `raw['ignore'] = ignore_list - [package]`; ignored → `raw['ignore'] = (ignore_list + [package]).uniq` (assignment, never `<<` — Q1's shallow-dup hazard).
3. `save` upgraded to same-dir Tempfile + `File.rename` (marker.rb:43-53 and run_log.rb:126-141 are the in-repo precedents — D-04 names the run_start-header one), chmod-permissive temp handling per marker.rb's shape; `mkdir_p` already guaranteed by save (config.rb:69).
4. `ensure` → `flock(LOCK_UN)` + close (build.rb:106-112's always-release shape).

**Failure/degradation posture (never raise into the request):** every raise inside the mutator (disk full, permissions, malformed yml mid-race) is rescued at the route into the standard 500 envelope — reason e.g. `'config_write_failed'` — matching api_mutate's rescue shape (router.rb:286-291). The UI renders the pinned `Couldn't save the toggle for {package}…` template and the checkbox keeps server truth (UI-SPEC). A terminal yml EDITOR (vim) takes no advisory lock — that window is unfixable and accepted (spm-cache.yml is user-authored, not adversarial — config.rb:174-177 posture).

**Feasibility:** yes — flock-on-sidecar is the same mechanism, file, and idiom as the build lock; only the path differs. Confined critical section (one load + one small write) keeps hold time ~ms.

### Q3 — Applied-vs-saved derivation, the toggle POST response, poll-skip integrity

**Applied truth** [VERIFIED: web/read_models/state.rb:17-33; tools/spm-cache-proxy ProxyGenerator.swift:18, 112-129]:

```ruby
# state.rb:23-34 (verbatim row shape today — the extension lands beside these keys)
'packages' => inventory.map do |entry|
  graph_entry = graph_entries[entry.name]
  {
    'name' => entry.name,
    'config' => entry.config,
    'size_bytes' => entry.size_bytes,
    'state' => graph_entry && graph_entry['status'],
    'fidelity' => entry.fidelity,
    'has_macro' => graph_entry ? (graph_entry['hasMacro'] || false) : false
  }
end,
```

graph.json is written by the gen tool per sync; each entry carries `module`, `status`, `hasMacro` (GraphGenerator.swift:17-20). Statuses: `case hit, missed, ignored, excluded, plugin` (ProxyGenerator.swift:18, verbatim). `ignored` = the denylist matched at sync time (isIgnored, :51-55, :112-125) — so **applied-ignored ⇔ `status == 'ignored'`; applied-cached ⇔ `hit`/`missed`**. This is D-06's "graph/lockfile truth the read model already serves" — no new source.

**Saved truth:** the ignore list on disk. For a toggleable row (exact-entry semantics), `ignore_list.include?(name)` [VERIFIED config.rb:150-152]. **Divergence (pending) = `saved_ignored != (applied_status == 'ignored')`** for rows with a graph entry. Rows with NO graph entry (`state` nil — state.rb:29-31's "—" cell) have no applied signal: recommend they contribute no divergence (nothing to converge to). Planner pins.

**The state model must read config fresh per call:** `State.call` never loads [VERIFIED state.rb:15-17] — the saved truth extension needs either a `config.load` on the singleton (mutating shared state from a read path — ugly but consistent with off's flow) or a local `YAML.safe_load(File.read(path))` parse. Recommend the local parse (a read model holding no mutable singleton state matches its "re-read on EVERY call" comment, state.rb:6-11). Planner pins.

**Toggle POST response:** recommend the standard `ok_envelope` with `{'package' => name, 'cached' => <new saved bool>}` — enough for the UI to branch ok/err; the TABLE truth stays poll-served (UI-SPEC A8/poll-skip + prohibition 13: no optimistic applied claims). NOT a full state payload, NOT slot data. `/api/revert` (batch saved:=applied for all diverging rows, instant write, not slot-gated per UI-SPEC A3) returns the same shape per package or a count — planner pins.

**Poll-skip integrity seams** [VERIFIED: lib/spm_cache/web/assets/app.js:130-151, 156-168, 309-314]:
- `refreshState` (:156-168) is BOTH the 5s poll body (`loop` at :309-314) and the Refresh button handler. The skip guard is one boolean (`toggleInFlight`): when true, the poll skips `renderState` AND the `state-stamp` update (:133-134 — "the stamp never claims data newer than what is shown"). A manual Refresh click SHOULD bypass the skip (user-invoked reads are never torn — the config write is atomic under the lock). Planner pins.
- The bar derives from the freshest `/api/state` (present when ≥1 row diverges) — pure read-model rendering in `renderState` (:130-151); `body.replaceChildren` ordering puts the bar above the table only when rows exist (empty state replaces the whole body — :135-139, by construction).

### Q4 — Reasons derivation: where the five facts live today

| Reason | Fact source today | Evidence | Verdict |
|--------|-------------------|----------|---------|
| `pattern-managed` | `should_ignore?(name) && !ignore_list.include?(name)` — matched by a non-exact pattern; removal needs pattern editing (UI prohibition 10) | config.rb:201-203; fnmatch probed (P7); gen tool matches patterns against product names AND package identity (ProxyGenerator.swift:37-47) — a wildcard row can be graph-`ignored` with no exact entry to remove | VERIFIED |
| `plugin` | graph status `plugin` — plugin-only packages (`isPluginOnly`: products[] metadata exists, none of type `library`) get `.plugin`, never proxied, nothing to cache | ProxyGenerator.swift:84-91; Lockfile.swift:84-89 (verbatim classifier); cachemap.rb:31-33 reads it back | VERIFIED |
| `binary-target` | **NOT persisted anywhere the web tier reads.** Graph entries: module/status/hasMacro only (GraphGenerator.swift:17-21). Metadata files: package/target-names/platforms only (MetadataGenerator.swift:12-16). Lockfile `products[]`: `{name, type, targets}` — target TYPES discarded (installer.rb:407, Lockfile.swift:161). descs are in-memory describe objects (desc.rb); `binary_targets` in installer/integration/descs.rb:15-19 returns `@cachemap.hit` — a misnamed legacy helper, not a fact source | Negative verified across all four persistence layers | GAP — see below |
| `excluded` | graph status `excluded` — cache-only INVERTED allowlist: `cacheOnlyPatterns` non-empty and the package matches NONE (isCacheOnlyExcluded) | ProxyGenerator.swift:57-61, :123; installer.rb:615-616's comment ("permanently excluded/ignored … never be replaced by a cached binary given the current config") | VERIFIED |
| `fidelity` | Inventory entry.fidelity from the `.provenance.json` sidecar's `fidelity_status` (absent/malformed → `not-graph-pinned`, never raises) | inventory.rb:33, 50-59; sidecar written with statuses incl. `host-pinned` (build_pipeline.rb:173) and `not-graph-pinned` (:178); UI warn bucket = `resolution-incompatible` (app.js:34-37 FIDELITY_CLASS) | VERIFIED |

**The binary-target gap — options for the planner:**
1. **(recommended) Extend `enrich_lockfile_products` (installer.rb:390-421) to record it.** The enrichment ALREADY runs `swift package describe` per package (installer.rb:405-406) and could store a `binary: true`-style package flag (describe's targets carry `type: "binary"`). Ruby-side only; the Swift tool ignores unknown lockfile keys (installer.rb:430-432 comment — VERIFIED). Cost note: `invalidate_stale_products!` (:433-437) re-derives `products[]` on version bump — v0.5.0 bumps anyway. The read model then joins `config.lockfile_path` for the flag.
2. Extend the Swift gen tool's graph entry — cross-boundary change + tool rebuild (the binary builds from in-repo source, proxy_executable.rb:31-40 `build_from_source`; `.build/release` binary is looked up first :24-28). Heavier; same information, worse blast radius.
3. Ship without the fact — the `binary-target` reason then never fires and a binary-backed row renders toggleable (wrong: un-caching a no-source package breaks the project — pkg/base.rb:57-58 "Cannot build binary target"; build_pipeline.rb:307-310 "no source to build at all"). Only acceptable if the enrichment is deferred knowingly — TOGL-03 would be partially unmet.

**Derivation shape (one place, server-side — CP10):** in `State.call`, per row: `toggleable` (bool), `reason` (nil | one of the five D-09 strings), plus saved/applied booleans for D-06. Recommended precedence when multiple facts apply (planner pins): `excluded` → `plugin` → `binary-target` → `pattern-managed` → `fidelity` — deterministic single reason (the UI cell renders ONE reason chip beside an optional `pending` chip). Unknown reason strings, if any ever arise, ride to the client verbatim and render neutral (UI-SPEC pins the client half; no server allowlist filter). Config fact freshness: see Q3's fresh-read note.

**Fidelity gate value (planner pins):** recommend `resolution-incompatible` only (the warn bucket — provenance pins can't be verified against the current graph); `not-graph-pinned` stays toggleable (neutral informational).

### Q5 — Toggle route, Apply-now, and the A4 busy-string amendment

**Route skeleton — mirror api_mutate minus the slot** [VERIFIED: lib/spm_cache/web/router.rb:261-299 (the template), 95-127 (dispatch), 42-67 (injection seams — `@jobs` defaulted exactly like `@events`; a toggle collaborator is injectable the same way)]:

- `POST /api/toggle`: token → 401 (:262-264); non-POST → house 404 (:265); body `JSON.parse` → 400 `bad_body` (:267-276); `package` must be String, non-empty → 400 `bad_package`; `cached` must be EXACTLY `true`/`false` (no truthy coercion — V5 posture, router.rb:248-250's "matched EXACTLY" precedent) → 400 `bad_cached`; unknown package (not in the current inventory ∪ graph module set — the read model is one call away) → 404 `unknown_package` (house 404-for-unknown convention, router.rb:162; prevents typos polluting the yml); toggle attempt on a non-toggleable package → 400 `not_toggleable` (stale-DOM defense; the derived reason rides the envelope data); mutator raise → 500 `config_write_failed`. 2xx: `ok_envelope('package' => …, 'cached' => …)`. **Never touches `@jobs`** (D-08: toggling stays live during runs).
- `POST /api/apply`: `api_mutate(req, res, supplied, fixed_scope: 'use')` — VERBATIM reuse. `Jobs::SCOPES` (jobs.rb:39-43, the frozen scope→argv table) gains `'use' => ['use'].freeze`; bare `use` is the real re-sync verb (command/use.rb verified — watch flag defaults false). Inherits 409 `slot_busy`, 500 `spawn_failed`, and the 2xx `lock:` snapshot (correct for apply — `use` takes the build lock, installer/use.rb:63-68).
- `POST /api/revert`: instant config write (batched mutator), not slot-gated (UI-SPEC A3); empty body; same 400/500 posture as toggle.

**A4 amendment — one constant** [VERIFIED: lib/spm_cache/web/assets/app.js:323-328]:

```javascript
// app.js:323-328 (verbatim CTRL — the A4 target is line 324)
const CTRL = {
  busy: 'A build or rollback is already running — wait for it to finish.',
  wait: 'Waiting for build lock…',
  inflight: { build: 'Building…', rebuild: 'Rebuilding all…', rollback: 'Restoring source mode…' },
  failure: (name, message) => `Couldn't start the ${name}: ${message}. Check that spm-cache web is still running, then try again.`,
};
```

Superseded per UI-SPEC: `busy` → the three-verb string; `inflight` gains the apply verb (`Applying…` — the copy table's pinned string); the `ctl` map (:329) gains the apply button so `freeze()` (:363) covers all four (A5's freeze-set extension is literally one object entry). `requestPost` (:337-352) is reused as-is for all three new POSTs. The toggle cell lands in `stateRow` (:110-128 — `aria-label` must carry the RAW `p.name`; the rendered name gets the `◆` prefix at :113); `COLS`/`COL_CLASS` (:38-39) grow the sixth entry.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Ignore-list mutation (toggle, revert, off) | Core (`Config` shared mutator: sidecar flock → fresh load → assign → tmp+rename save) | — | One source of truth (D-03); both CLI and web inherit atomicity + clobber-proofing by calling the same code |
| Concurrency control for config writes | Core (the sidecar flock) | — | OS semantics ARE the mechanism (build-lock precedent); NOT the Jobs slot (D-08) and NOT the build lock |
| Apply-now (re-sync) | API/backend (`Web::Jobs` slot, `use` scope) | CLI child (`Installer::Use` + build lock) | D-07: real re-sync through existing machinery; no server-side config applying |
| Saved-vs-applied derivation + reasons | API/backend (`ReadModels::State` — one server-side derivation per call) | — | CP10: every status vocabulary derives server-side once; client renders verbatim |
| Toggle/apply/revert routes + validation | API/backend (Router dispatch behind the existing gate) | — | Structural: the catch-all servlet passes POSTs through Host/Origin/token (server.rb:87-97; router.rb:70-83) |
| Checkbox column, bar, chips, poll-skip | Frontend (`app.js` + `styles.css`; zero new files) | — | UI-SPEC files contract: no new assets, no framework, no new timers |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| (none new) | — | stdlib `YAML`/`Tempfile`/`FileUtils`/`flock`, existing `Web::Jobs`/`Router`/read models, existing vanilla ES-module frontend | Everything Phase 16 needs is stdlib or already shipped 12-15; gemspec unchanged |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Sidecar lock file | flock on the yml itself | PROBED P5: rename breaks the inode's lock chain — unsound under the mandated tmp+rename write; sidecar is inode-stable (P6) |
| Blocking flock in the mutator | NB + retry loop / Mutex only | Mutex covers web-vs-web only; the flock closes web-vs-CLI too (D-03/D-04); blocking is the repo's proven idiom (build.rb:101) at click granularity |
| Lockfile-enrichment binary flag | Swift tool graph.json field | Ruby-side-only change vs cross-boundary + tool rebuild (Q4 options) |
| Local YAML parse in the read model | `config.load` on the singleton | Keeps the read path side-effect-free (state.rb:6-11's "re-read on EVERY call" stance); mutating a singleton from a GET is the CP1 posture that caused this phase's pitfall |

**Installation:** nothing to install.

## Package Legitimacy Audit

> No external packages are installed by this phase — zero new gems, zero npm. Table intentionally empty.

| Package | Registry | Age | Downloads | Source Repo | Verdict | Disposition |
|---------|----------|-----|-----------|-------------|---------|-------------|
| (none) | — | — | — | — | — | — |

## Architecture Patterns

### System Architecture Diagram

```
                 toggle click / Revert all          off (CLI)                Apply now
                          │                            │                        │
                          ▼                            ▼                        ▼
                 POST /api/toggle              spm-cache off <pkgs>      POST /api/apply
                 POST /api/revert                     │                        │
                          │                            │                        │
                          │     ┌──────────────────────┘                        │
                          ▼     ▼                                               ▼
              ┌─────────────────────────────┐                        ┌──────────────────┐
              │ Config shared mutator        │                        │ Web::Jobs slot    │
              │  flock sidecar(.yml.lock)    │                        │  Mutex + 409      │
              │  RE-READ spm-cache.yml       │                        │  SCOPES['use']    │
              │  assign raw['ignore'] key    │                        └────────┬─────────┘
              │  save: tmp + rename (atomic) │                                 │ spawn
              │  unlock (ensure)             │                                 ▼
              └──────────────┬──────────────┘                        spm-cache use (child, pgroup)
                             │ writes                                         │
                             ▼                                                ▼
                     spm-cache.yml ◄──── reads fresh ────────────┐    gen-proxy tool
                             │                                    │    (Swift, external)
                             │ saved truth                        │         │ writes
                             ▼                                    │         ▼
                  GET /api/state ◄────────────────────────────────┘    graph.json (module,status,hasMacro)
                             │  derives per row: toggleable, reason,           │
                             │  saved vs applied (= status=='ignored')         ▼
                             ▼                                       applied truth (join)
                  app.js: checkbox col + pending chip + unsaved bar
                             │  (poll 5s; toggle-in-flight skips redraw+stamp)
                             ▼
                  bar → Apply now → stream shows the use run → poll shows convergence → bar clears
```

Entry: browser checkbox/CLI verb. Processing: shared mutator (locked) or Jobs slot (spawns). Decision: toggleable facts per row (reason derivation). External: the Swift gen tool is the only writer of applied truth (graph.json) — reached only through the spawned `use`.

### Recommended Project Structure

```
lib/spm_cache/
├── core/config.rb                  # MOD: shared mutator(s) + locked merge-write save
├── command/off.rb                  # MOD: route run through the shared mutator (output lines byte-exact)
├── installer.rb                    # MOD (option 1): enrichment records the binary flag
└── web/
    ├── jobs.rb                     # MOD: SCOPES gains 'use' => ['use']
    ├── router.rb                   # MOD: /api/toggle + /api/apply + /api/revert dispatch
    └── read_models/state.rb        # MOD: per-row toggleable/reason + saved/applied (fresh disk read)
spec/
├── config_mutator_spec.rb          # NEW: merge-write, lock, clobber-proof, byte-identical free path
├── command_off_shared_mutator_spec.rb # NEW: the D-03 byte-identical pins (no Off spec exists today)
├── web_state_spec.rb               # extend: toggle fields + reason derivation matrix
├── web_toggle_routes_spec.rb       # NEW: token/verb/body/package/cached/unknown/not_toggleable matrix
├── web_jobs_spec.rb                # extend: 'use' scope row
├── web_frontend_spec.rb            # extend: sixth column, bar, chips, CTRL.busy amendment pins
└── web_integration_spec.rb         # extend: toggle → state convergence end-to-end
```

### Pattern 1: Locked merge-write (the phase's core pattern)
**What:** flock a stable sidecar; re-read the file INSIDE the lock; assign the one key; atomically replace via tmp+rename; release in ensure.
**When to use:** every config mutation from every caller (D-03/D-04).
**Example:**
```ruby
# Shape only — planner pins names. Precedents: build.rb:88-104 (flock),
# marker.rb:43-53 (tmp+rename), off.rb:20-22 (key-level assignment).
def set_ignored(package, ignored)
  FileUtils.mkdir_p(File.dirname(@config_path))
  lock = File.open("#{@config_path}.lock", File::CREAT | File::RDWR)
  lock.flock(File::LOCK_EX)  # probe+announce is the CLI's flavor; web wants silent blocking
  begin
    load
    list = ignore_list
    raw['ignore'] = ignored ? (list + [package]).uniq : list - [package]
    save_atomic   # same-dir Tempfile + File.rename over @config_path
  ensure
    lock.flock(File::LOCK_UN)
    lock.close
  end
end
```

### Anti-Patterns to Avoid
- **flock on the yml itself under a rename writer** — PROBED P5: the rename orphans the lock; two writers can then both "hold" it. Sidecar only.
- **`raw['ignore'] << pkg`** — DEFAULT_CONFIG's inner arrays are shared by `dup` (config.rb:31, 43); assignment only.
- **Trusting the web singleton's `@raw` for saved truth** — CP1: it is a boot-time snapshot (web.rb:41-43); re-read from disk on every derivation/mutation.
- **Slot-gating the toggle POST** — D-08: the slot governs Apply-now only; gating toggles would freeze config edits during runs for no safety gain.
- **Client-side reason or divergence math** — D-09/CP10: the read model derives once; the client renders `saved !== applied` per row and nothing more.
- **Server-side config "applying"** — D-07: Apply-now spawns the real `use`; no second sync mechanism.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Atomic file replacement | fsync dances, backup-file schemes | Same-dir Tempfile + `File.rename` (marker.rb:43-53, run_log.rb:126-141) | Shipped, chmod-before-rename aware, reviewed twice in-repo |
| Cross-process write mutual exclusion | Polling, touch-mtime protocols, a second Mutex | flock on a sidecar via the build-lock idiom (build.rb:88-104) | OS semantics ARE the mechanism; PROBED P4/P6 |
| Applied state | Re-deriving "what would the sync do" server-side | graph.json `status` (state.rb:17-33, cachemap.rb:79-84) | The gen tool already encoded the last sync's decision; second-guessing it creates a second truth |
| Slot/concurrency for Apply-now | Any new semaphore | `Web::Jobs` + `'use'` scope (jobs.rb:39-43, 58-72) | The whole D-07 point: one spawn slot, one 409 semantics, one stream |
| Busy/failure copy | New strings per surface | `CTRL` constants + the pinned UI-SPEC copy table (one `CTRL.busy` amendment, A4) | Single source of client copy; checker tests byte-exactness |

**Key insight:** this phase adds almost no new mechanism — it wraps the repo's own lock and atomic-write idioms around a two-line key merge, and wires one instant route + one spawned verb into surfaces that already exist.

## Runtime State Inventory

> Not a rename/refactor/migration phase — no stored strings move. Category answers for completeness:
> **Stored data:** the `ignore` list itself (spm-cache.yml) is the phase's subject; first save materializes all 9 DEFAULT_CONFIG keys and drops comments (PROBED P2) — existing behavior, now honestly labeled (D-05). The sidecar `spm-cache.yml.lock` is a NEW zero-content runtime artifact at project level (create-on-lock, like `.spm-cache-build.lock`, config.rb:110-112; harmless if gitignored-adjacent — planner decides .gitignore entry). **Live service config:** none. **OS-registered state:** none. **Secrets/env vars:** none new; the token stays out of env and logs (web.rb:75 posture). **Build artifacts:** none (option 1's lockfile enrichment writes a new products[] sibling field — data-format addition handled by the existing per-version re-derivation, installer.rb:433-437).

## Common Pitfalls

### Pitfall 1: Locking the config inode and writing by rename
**What goes wrong:** the lock and the atomic write fight — every rename orphans every held/waiting lock; two writers interleave "safely" and still clobber.
**Why it happens:** D-04 names both "flock on the config" and "tempfile + rename" without pinning that they must target different inodes.
**How to avoid:** sidecar lock file (`spm-cache.yml.lock`); PROBED P5/P6 settle it.
**Warning signs:** intermittent double-writes under load; a stuck "held" lock after a save.

### Pitfall 2: Merging against the singleton snapshot
**What goes wrong:** the toggle route merges into the boot-time `@raw` and saves — silently reverting every CLI `off`/yml edit made since server boot.
**Why it happens:** `Config` is a singleton and `Command::Web` loads once (web.rb:41-43); nothing else ever refreshes it.
**How to avoid:** `load` INSIDE the lock, every mutation (Q2 algorithm); the read model reads disk per call too.
**Warning signs:** a toggle that resurrects previously-removed entries.

### Pitfall 3: In-place mutation of `raw['ignore']`
**What goes wrong:** `raw['ignore'] << pkg` pollutes `DEFAULT_CONFIG` (the hash is frozen; its arrays are not — config.rb:31,43) — every future `DEFAULT_CONFIG.dup` in the process carries the package.
**Why it happens:** Ruby's `freeze` is shallow; the dup/merge idiom shares inner objects.
**How to avoid:** key-level assignment of a NEW array (off.rb:20-22's shape); spec asserts DEFAULT_CONFIG stays pristine after a mutate.
**Warning signs:** ignore entries appearing in a fresh unrelated Config instance.

### Pitfall 4: Reading Ruby's `flock(LOCK_NB)` failure as an exception
**What goes wrong:** `begin f.flock(LOCK_EX|LOCK_NB); rescue Errno::EAGAIN` — the rescue never fires; Ruby returns `false` on contention. A "try-lock failed" branch silently runs the contended path.
**Why it happens:** Ruby's File#flock returns false with LOCK_NB instead of raising (build.rb:92-94 documents it; PROBED P4 re-confirmed).
**How to avoid:** truthiness checks (`unless lock.flock(...)`), exactly build.rb:99.
**Warning signs:** two writers both reporting "acquired".

### Pitfall 5: Deriving saved truth from `should_ignore?` alone
**What goes wrong:** a wildcard-matched row reads "ignored" but has no exact entry — the toggle then adds/removes an entry that changes nothing the pattern doesn't already decide.
**Why it happens:** `should_ignore?` is pattern-truth; the toggle is exact-entry-truth.
**How to avoid:** two tests, two purposes — `include?(name)` for saved state and mutability; `should_ignore?(name) && !include?(name)` for `pattern-managed` (Q4 table).
**Warning signs:** a toggle that "works" (entry added) but the row stays graph-ignored forever.

### Pitfall 6: The toggle POST racing the 5s poll redraw
**What goes wrong:** the poll lands between the POST and the next read and repaints the checkbox to its old value — the visible "bounce" lie UI-SPEC A8 exists to kill.
**How to avoid:** the one-boolean skip guard in the poll path covering BOTH `renderState` and the `state-stamp` (app.js:133-134, 156-168).
**Warning signs:** flapping checkboxes for one cycle after each click.

### Pitfall 7: Slot-gating the toggle "for safety"
**What goes wrong:** toggles freeze during builds; the D-08 contract is broken and the UI's always-live checkbox lies.
**How to avoid:** only `/api/apply` touches `@jobs`; toggle/revert go straight to the mutator.
**Warning signs:** 409 `slot_busy` from `/api/toggle`.

### Pitfall 8: Divergence math that treats `has_macro` as a live signal
**What goes wrong:** planning reason derivation around `has_macro` — the generator writes it LITERAL FALSE today (ProxyGenerator.swift:91,171), so it never fires and macro-backed packages are not plugin-flagged.
**Why it happens:** the field exists in the schema and the UI's `◆` rendering implies liveness.
**How to avoid:** derive `plugin` from graph `status == 'plugin'` only; record the macro gap as a known limitation (Assumptions A3).
**Warning signs:** specs asserting `has_macro: true` fixtures that no real generator run produces.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The state read model may add fields to the `/api/state` rows (field names planner-discretionary per UI-SPEC A1) without a versioned envelope | Q3 | Low — the envelope is `{status, data, generated_at}` and the sole consumer is our own app.js |
| A2 | Sidecar `spm-cache.yml.lock` placement at project level (beside the yml) needs no cleanup lifecycle — zero-byte artifact, recreated on demand | Q2/Pitfall 1 | Cosmetic: an extra dotfile in the project root; a `.gitignore` entry may be wanted (planner) |
| A3 | `plugin` = plugin-only packages exactly; macro-executable packages are NOT detected today (hasMacro always false in current generator output) and remain toggleable | Q4/Pitfall 8 | If the phase is expected to protect macro packages, TOGL-03 is under-met for them — needs the planner's explicit accept or the gen-tool follow-up |
| A4 | Fidelity gate = `resolution-incompatible` only; `not-graph-pinned` rows stay toggleable | Q4 | If `not-graph-pinned` should also gate, the reason derivation adds one comparison — cheap to change pre-implementation |
| A5 | Enrichment option (Q4 option 1) keeps the Swift tool and its shipped binary untouched — the flag rides the lockfile | Q4 | If describe-based enrichment misses local-path packages (the installer.rb:439-443 checkout caveat), those rows fall back to no-flag (toggleable) — same under-detection as status quo |
| A6 | Manual Refresh click bypasses the poll-skip (user-invoked reads are never torn because writes are atomic under the lock) | Q3 | Minor UX divergence from the spec's letter (spec speaks of "the 5s poll" only) — planner confirms |
| A7 | WEBrick thread-per-connection makes concurrent toggle POSTs real (same premise as 15-RESEARCH A3, slot Mutex) | Q2 | Low — the flock is correct regardless |

## Open Questions

1. **Binary-target fact (TOGL-03's one real gap).** What we know: nothing persists it today; the enrichment seam (installer.rb:390-421) already runs describe and can record it Ruby-side (option 1), or the reason ships never-firing (option 3). What's unclear: whether describe's target types are reliably present for local-path packages (checkout caveat, installer.rb:439-443). Recommendation: option 1, accepting A5's under-detection caveat; **planner decides**.
2. **`off`'s redundant `config.load`** (off.rb:18) once the mutator loads under the lock: keep (harmless, smaller diff) or remove (one load path). Recommendation: keep — the byte-identical free-path constraint argues for the smallest possible diff to a published CLI. Planner pins.
3. **Unknown-package posture** — 404 `unknown_package` (recommended; house 404 convention) vs 400. Planner pins the reason vocabulary for the new 400s (`bad_package`/`bad_cached`/`not_toggleable`), following the api_mutate precedent's shape (router.rb:251-255).
4. **Revert-all batching** — one locked transaction (single merge-write applying N key changes) vs N mutator calls (N lock round-trips). Recommendation: one transaction inside one lock acquisition (the mutator grows a batch form); N calls are correct but needlessly re-lock. Planner pins.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Ruby + stdlib (yaml/tempfile/fileutils/flock) | everything | ✓ | 3.2.3 (rbenv) | — |
| RSpec | validation | ✓ | ~> 3.12 (Gemfile) | — |
| spm-cache-proxy tool | applied-truth production (existing behavior; option 2 only) | ✓ (`.build/release` binary; source in-repo) | — | `build_from_source` (proxy_executable.rb:31-40) |

**Missing dependencies with no fallback:** none. **Missing with fallback:** none.

## Validation Architecture

> Included — `.planning/config.json` `workflow.nyquist_validation: true`. Seeded in `16-VALIDATION.md`.

### Test Framework
| Property | Value |
|----------|-------|
| Framework | RSpec ~> 3.12 (hermetic suite per CP7) |
| Config file | none beyond `.rspec` defaults |
| Quick run command | `bundle exec rspec spec/config_mutator_spec.rb spec/web_toggle_routes_spec.rb spec/web_state_spec.rb spec/web_jobs_spec.rb` |
| Full suite command | `bundle exec rspec` (Makefile `make test`) |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| TOGL-01 | Mutator merge-write: lock → fresh load → assign → atomic save → unlock-on-raise; clobber-proof vs stale writer; DEFAULT_CONFIG pristine | unit | `bundle exec rspec spec/config_mutator_spec.rb` | ❌ Wave 0 |
| TOGL-01 | `off` free path byte-identical (output lines, exit, file shape) through the shared mutator | unit | `bundle exec rspec spec/command_off_shared_mutator_spec.rb` | ❌ Wave 0 |
| TOGL-02 | State rows carry toggleable/reason/saved/applied; divergence math; fresh disk read per call | unit | `bundle exec rspec spec/web_state_spec.rb` | ✅ extend |
| TOGL-02 | Apply-now = `use` scope through the slot (409 semantics unchanged) | unit | `bundle exec rspec spec/web_jobs_spec.rb` | ✅ extend |
| TOGL-01/02/03 | Route matrix: token 401 / POST-404 / `bad_body` / `bad_package` / `bad_cached` / `unknown_package` / `not_toggleable` / 500 `config_write_failed` / 2xx envelope | unit | `bundle exec rspec spec/web_toggle_routes_spec.rb` | ❌ Wave 0 |
| TOGL-01/02 | Integration: toggle → `/api/state` shows saved≠applied → apply spawns fake-bin `use` → convergence clears the bar | integration | `bundle exec rspec spec/web_integration_spec.rb` | ✅ extend |
| UI contract | Sixth column, bar markup/copy, chips, `CTRL.busy` three-verb amendment, poll-skip guard pins | unit (source/byte pins — no JS runtime in CI) | `bundle exec rspec spec/web_frontend_spec.rb` | ✅ extend |

### Sampling Rate
- **Per task commit:** the task's new/extended spec files (hermetic, <60 s)
- **Per wave merge:** `bundle exec rspec` (full suite)
- **Phase gate:** full suite green + the manual browser table executed before `/gsd-verify-work`

### Wave 0 Gaps
- [ ] `spec/config_mutator_spec.rb` — merge-write + clobber-proof + DEFAULT_CONFIG-pristine
- [ ] `spec/command_off_shared_mutator_spec.rb` — the D-03 byte-identical pins (no Off spec exists today)
- [ ] `spec/web_toggle_routes_spec.rb` — full route validation matrix
- (extend existing: web_state_spec, web_jobs_spec, web_frontend_spec, web_integration_spec)

## Security Domain

> Required — `security_enforcement: true`, ASVS Level 1.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no (localhost token model, unchanged) | per-launch token via `X-SPM-Token` (D-04 posture; middleware.rb:46-50) |
| V3 Session Management | no | stateless per-launch token; no sessions |
| V4 Access Control | yes (new mutation routes) | same structural gate — Host/Origin then token, un-bypassable via the single servlet (router.rb:70-83, server.rb:87-97) |
| V5 Input Validation | yes (three new POST bodies) | whitelist/exact-match posture: `cached` exactly boolean, `package` String validated against the read-model universe, `scope` fixed — never interpolated (V5 precedent router.rb:248-255) |
| V6 Cryptography | no | nothing cryptographic in the phase |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Config injection via crafted `package` (yml special chars) | Tampering | the value round-trips through `YAML.safe_load`/`YAML.dump` data structures only — never string-interpolated into yml text; still validate as non-empty String |
| Cross-tab/cross-client toggle storm | DoS (local) | flock serializes writes; UI poll-skip keeps renders honest; no queue needed at click granularity |
| Stale-DOM bypass of disabled checkboxes | Tampering | server re-derives toggleable per request → 400 `not_toggleable`; client disabled state is UX, not the guard |
| Envelope message rendering | Information/Tampering | server messages render only through the pinned failure templates' `{message}` slot via `el()`/`textContent` (UI-SPEC prohibition 2) |
| Forged Apply (bypassing UI freeze) | Elevation | slot is server-side (Mutex + 409); the flock backstops `use` itself — a forged POST queues visibly, never corrupts |

## Sources

### Primary (HIGH confidence)
- `lib/spm_cache/core/config.rb` — DEFAULT_CONFIG, load/save, ignore_list/should_ignore? (read in full, this session)
- `lib/spm_cache/command/off.rb` — the CLI contract being preserved (read in full)
- `lib/spm_cache/web/router.rb`, `web/jobs.rb`, `web/read_models/state.rb`, `web/assets/app.js` — route/slot/read-model/frontend seams (read in full)
- `lib/spm_cache/installer/build.rb:88-112` — the flock idiom; `web/marker.rb:43-53`, `core/run_log.rb:126-141` — atomic-write precedents
- `lib/spm_cache/cache/cachemap.rb`, `cache/inventory.rb` — graph/provenance read paths
- `tools/spm-cache-proxy/Sources/Core/Generator/ProxyGenerator.swift`, `GraphGenerator.swift`, `Core/Lockfile.swift`, `Core/Generator/MetadataGenerator.swift` — the applied-truth vocabulary and the negative result for binary-target
- Machine probes P1-P7 (this machine, 2026-09-02)

### Secondary (MEDIUM confidence)
- `.planning/phases/15-ui-build-controls/15-RESEARCH.md`, `15-VALIDATION.md` — slot/spawn/route/validation precedents (repo docs)
- `.planning/phases/16-package-toggles-panel-completion/16-UI-SPEC.md` — the approved contract this research grounds

### Tertiary (LOW confidence)
- None — every load-bearing claim is code-anchored or probed.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — zero new dependencies; everything stdlib or shipped in-repo
- Architecture (mutator/merge-write/routes): HIGH — every seam read at file:line; lock-target and atomicity semantics machine-probed
- Reason derivation: HIGH for four reasons (facts read at source, including the Swift generator); the binary-target gap is a verified negative with options, not a guess
- Pitfalls: HIGH — each is grounded in probed behavior or repo-documented precedent

**Research date:** 2026-09-02
**Valid until:** 2026-10-02 (stable: codebase- and probe-grounded; re-verify if config.rb, the router dispatch, or the gen tool's graph schema move before execution)
