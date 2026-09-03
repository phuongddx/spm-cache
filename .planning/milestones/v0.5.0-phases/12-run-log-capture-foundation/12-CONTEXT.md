# Phase 12: Run-Log Capture Foundation - Context

**Gathered:** 2026-08-31
**Status:** Ready for planning

<domain>
## Phase Boundary

Every CLI run writes a complete, queryable JSONL run log on disk — header (command, argv, pid, started_at), timestamped stream-tagged body lines, exit line — under the project's run dir, OUTSIDE the sandbox (which `recreate_dirs` destroys mid-run). Terminal output and exit codes are byte-identical to today. No server, no UI, no streaming in this phase — this is the keystone capture layer Phase 14 consumes.

Locked by ROADMAP success criteria: SC1 (log shape + location), SC2 (body captures what the terminal showed incl. subprocess output; full run reconstructable offline), SC3 (tee invisible; `spm-cache web` never logs), SC4 (retention caps unbounded growth). Requirement: LOGS-01.

</domain>

<decisions>
## Implementation Decisions

### CLI surface
- **D-01:** Repurpose the existing `--log-dir` stub as the run-log dir override (default + override convention, à la dbt/glog). Do NOT introduce a second flag; do not leave the knob dead.
- **D-02:** Default run dir is `.spm-cache/runs/` at the project root — sibling of the `.spm-cache-build.lock` dotted-prefix convention, outside the sandbox. The matching `.gitignore` entry ships in this phase.
- **D-03:** Add a `--no-run-log` escape-hatch flag (matches the existing `--no-merge-slices` / `--no-library-evolution` precedent) so capture can be disabled per-invocation.

### Log format & content
- **D-04:** The JSONL body carries BOTH terminal-parity lines (stream-tagged: stdout/stderr) AND structured events — at minimum `run_start`, `package_start`/`package_end`, phase markers, `run_end` — interleaved in one file, one schema. — **Reversibility:** costly — Phase 14's SSE tailer, event-id/replay design, and browser anchors build directly on this event vocabulary; changing it after Phase 14 means reworking tailer, frontend, and regression specs together. Fix the vocabulary now, before two phases depend on it.
- **D-05:** Full fidelity — a run is never truncated (SC2). No per-run size cap, no head+tail clipping. Disk is bounded by the retention policy, not by mangling logs.

### Retention
- **D-06:** Retention = keep-last-N runs AND prune-oldest-until-under-a-total-size-budget (count + size hybrid). Defaults: N=50 runs / 500MB, configurable in `spm-cache.yml` (it is the user-facing state surface).
- **D-07:** Cleanup runs at run start — each new run prunes old ones after writing its header (rotation-time cleanup; no separate maintenance command).

### Command coverage
- **D-08:** ALL commands log uniformly via the `Main.run` tee — build/use/watch/doctor/cache/rollback/remote/pkg/init — no allowlist (new verbs log automatically; full audit trail; retention bounds the noise). Exactly two exclusions: the future `web` command (by design, SC3) and `--no-run-log` invocations.
- **D-09:** The `watch` daemon writes per-cycle files — each regeneration cycle is its own timestamped run log with its own header/exit lines. No rolling session file.

### Claude's Discretion
- Run-log file naming scheme (timestamp format vs monotonic sequence) — any scheme satisfying per-run-file semantics and lexicographic age ordering.
- Exact JSONL field names within the locked event vocabulary; atomics of the writer (a `Core::RunLog`-style class implementing the `output(line)` contract `Core::Sh` already expects is the research-shaped seam).
- Which internal phase markers to emit beyond the minimum event set.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase definition
- `.planning/ROADMAP.md` § "Phase 12: Run-Log Capture Foundation" — goal, depends-on, LOGS-01, success criteria SC1–SC4
- `.planning/REQUIREMENTS.md` § "Live log streaming" — LOGS-01 (the only requirement in this phase)

### Milestone research (HIGH confidence, 2026-08-31)
- `.planning/research/SUMMARY.md` — architecture stance (stateless file-reader principle), file-tail JSONL transport verdict, Phase-1 implications, CP mapping
- `.planning/research/ARCHITECTURE.md` — the exact integration seams: `Main.run` tee (skipping `web`), `Core::Sh` stream branch as file-only sink + the discarded-capture gap to fix, `Config#runs_dir`, `--log-dir` stub analysis, run-log header/body/exit shape
- `.planning/research/PITFALLS.md` — CP3 (three-channel output capture — THE keystone pitfall this phase exists to close), CP14 detection nuance (pid-dead-without-exit-line runs must be handled honestly later; the exit-line semantics decided here feed it)

### Codebase maps (scout, refreshed 2026-08-31)
- `.planning/codebase/ARCHITECTURE.md` — Main entry/dispatch path, Core layer inventory, watch flow (per-cycle regeneration semantics), sandbox vs project-root file placement
- `.planning/codebase/CONVENTIONS.md` — `Core::UI`/injected-`out:` IO conventions, `Core::Sh` as the single shell seam, no-monkey-patching rule, atomic tempfile+rename pattern, default-deny Sh spec guard, cite-pitfall-ID comment convention

No external ADRs/specs — requirements fully captured in decisions above.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Core::Sh` (`lib/spm_cache/core/sh.rb`) — its `live_log:` option already defines the `output(line)` consumer contract a run-log sink implements; the popen3 reader-thread branch is where the file sink lands
- `Core::UI` (`lib/spm_cache/core/log.rb`) — the single choke point for human output (`info`/`warn`/`error` → `$stdout`/`$stderr`); the tee wraps here
- Watcher's injected `out:` IO parameter (`lib/spm_cache/core/watcher.rb`) — precedent for output-injection over direct globals, testable via StringIO
- Atomic tempfile+rename write pattern (provenance sidecars, `SPM::ResolvedGraph`) — reuse for run-log header writes
- `defined?`-guarded memoization convention — for any per-process log handle

### Established Patterns
- All shell-outs go through `Core::Sh` — never backticks; the capture seam must not create a second path around it
- No monkey-patching: composition (`include`) and refinements only — the tee is a module-level hook, not a `puts` override
- Hermetic specs: 441 examples, network-free, default-deny `Core::Sh` guard — run-log specs must stay hermetic (StringIO/tmpdir, no real subprocesses required for the tee itself)
- Comments cite the planning-doc ID they defend (e.g. "(LOGS-01)", "(CP3)")
- `# frozen_string_literal: true` first line; `Struct.new(keyword_init: true)` for data objects

### Integration Points
- `lib/spm_cache/main.rb` `Main.run` — tee installation point (after `--version` intercept, before/around `Command.run`); skip for `web` argv and `--no-run-log`
- `lib/spm_cache/core/sh.rb` popen3 branch — becomes file-writing sink in live mode; ALSO fix the existing discarded-capture gap so `failure_detail` regains detail (behavior-preserving for the terminal)
- `lib/spm_cache/core/config.rb` — `runs_dir` (default `.spm-cache/runs/`), `--log-dir` override becomes load-bearing, retention config keys (`runs_keep`/`runs_max_mb` or equivalent) with defaults 50/500
- `lib/spm_cache/command.rb` — `--no-run-log` flag declaration (compose with `.concat(super)`)
- `lib/spm_cache/command/init.rb` — gitignore append for `.spm-cache/` (append-once pattern already exists for `spm-cache/`)
- Watcher regeneration path (`Core::Watcher` → `Installer::Use#perform_install`) — each cycle flows through the same tee, producing D-09's per-cycle files for free

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches. (The MSBuild binlog "record events, not text dumps" precedent and the dbt/glog default+override flag convention informed the granularity and `--log-dir` decisions respectively; they are rationale, not templates to copy.)

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 12-Run-Log Capture Foundation*
*Context gathered: 2026-08-31*
