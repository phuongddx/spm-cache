# Phase 12: Run-Log Capture Foundation - Research

**Researched:** 2026-08-31
**Domain:** Output-capture tee + JSONL run-log sink for a Ruby CLI (SPMCache v0.5.0)
**Confidence:** HIGH (every integration seam re-read in this repo this session at file:line; exit-semantics probed empirically on this machine; claide 1.1.0 gem source read directly)

## Summary

Phase 12 adds `Core::RunLog` — a JSONL writer that (1) is fed by a tee swapped in for `$stdout`/`$stderr` inside `Main.run`, and (2) doubles as the `live_log:` sink `Core::Sh`'s dormant popen3 branch already expects (`output(line)` contract). Everything needed exists: the tee captures 100% of today's terminal output because every terminal write in `lib/` routes through the `$stdout`/`$stderr` globals (Kernel#puts in `Core::UI`, raw `puts` in commands, `$stderr.puts` for warn/error) — no code writes to the `STDOUT`/`STDERR` constants, and CLAide's ANSI detection reads `STDOUT.tty?` (the constant, claide-1.1.0 `command.rb:129`), so the global swap cannot change color behavior. The exit line is capturable with byte-identical exit codes because CLAide's dispatcher (`Command.run`, `rescue Object` → `handle_exception` → `exit(status)` or re-raise) leaks exactly three exception shapes to `Main.run`: `SystemExit`, `Interrupt`, and `StandardError` — each with a deterministic status (probed: uncaught `Interrupt` exits 130; `GeneralError#exit_status` = 1; `CLAide::Help` = 0 when no error message, 1 otherwise).

Two locks shape the design more than anything else. First, **watch is not one run** (D-09): `Command::Watch` → `Core::Watcher#run` regenerates N times per process, so the watch verb must skip the Main-level log and open a per-cycle file per `perform_install` — drivable from `Command::Watch`'s `installer_factory` closure (watcher.rb:90-93) with zero changes to `Core::Watcher`. Second, **the `--log-dir`/`--no-run-log` values must be pre-scanned from raw argv** in `Main.run`, because the tee installs before CLAide parses — the bare `--version` pre-scan at main.rb:11 is the exact in-repo precedent (the CLAide-level flag declarations must stay: they are what makes the flags legal to parse).

The fix of `Core::Sh`'s discarded-capture gap is small and behavior-preserving: the popen3 reader threads (sh.rb:24-25) currently drop every line (`{ output: "", status: 0 }`, sh.rb:33) and raise detail-free errors; retaining a bounded per-stream tail (60 lines, the `FAILURE_DETAIL_LINES` constant) restores `failure_detail` quality while the full stream goes to the file sink. No new runtime dependencies (project constraint); retention is ~20 lines of stdlib (count+size prune at run start per D-06/D-07).

**Primary recommendation:** One `Core::RunLog` class owning file lifecycle (header via tempfile+rename, mutex-serialized appends, exit line in a `Main.run` ensure), a tee IO-wrapper pair installed in `Main.run` after the `--version` intercept, the popen3 branch fixed to retain a 60-line tail per stream, watch handled as per-cycle files via the `installer_factory` seam, and retention (`runs_keep`/`runs_max_mb`, 50/500 defaults) pruned after the new header lands.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Repurpose the existing `--log-dir` stub as the run-log dir override (default + override convention, à la dbt/glog). Do NOT introduce a second flag; do not leave the knob dead.
- **D-02:** Default run dir is `.spm-cache/runs/` at the project root — sibling of the `.spm-cache-build.lock` dotted-prefix convention, outside the sandbox. The matching `.gitignore` entry ships in this phase.
- **D-03:** Add a `--no-run-log` escape-hatch flag (matches the existing `--no-merge-slices` / `--no-library-evolution` precedent) so capture can be disabled per-invocation.
- **D-04:** The JSONL body carries BOTH terminal-parity lines (stream-tagged: stdout/stderr) AND structured events — at minimum `run_start`, `package_start`/`package_end`, phase markers, `run_end` — interleaved in one file, one schema. Reversibility: Phase 14's SSE tailer, event-id/replay design, and browser anchors build directly on this event vocabulary; fix it now.
- **D-05:** Full fidelity — a run is never truncated (SC2). No per-run size cap, no head+tail clipping. Disk is bounded by the retention policy, not by mangling logs.
- **D-06:** Retention = keep-last-N runs AND prune-oldest-until-under-a-total-size-budget (count + size hybrid). Defaults: N=50 runs / 500MB, configurable in `spm-cache.yml`.
- **D-07:** Cleanup runs at run start — each new run prunes old ones after writing its header (rotation-time cleanup; no separate maintenance command).
- **D-08:** ALL commands log uniformly via the `Main.run` tee — build/use/watch/doctor/cache/rollback/remote/pkg/init — no allowlist. Exactly two exclusions: the future `web` command (by design, SC3) and `--no-run-log` invocations.
- **D-09:** The `watch` daemon writes per-cycle files — each regeneration cycle is its own timestamped run log with its own header/exit lines. No rolling session file.

### Claude's Discretion (research recommendations required)

- Run-log file naming scheme (timestamp format vs monotonic sequence) — any scheme satisfying per-run-file semantics and lexicographic age ordering. → Recommended below.
- Exact JSONL field names within the locked event vocabulary; atomics of the writer (a `Core::RunLog`-style class implementing the `output(line)` contract `Core::Sh` already expects is the research-shaped seam). → Recommended below.
- Which internal phase markers to emit beyond the minimum event set. → Recommended below.

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| LOGS-01 | Every CLI run (build/use/watch) writes a JSONL run log (header/body/exit lines) under the project run dir, outside the sandbox | `Config#runs_dir` (new, `.spm-cache/runs/`, mirrors `build_lock_path` pattern config.rb:101-103); tee in `Main.run` (main.rb:8-14); Sh popen3 sink (sh.rb:20-33); exit capture via `Main.run` rescue/ensure (verified CLAide leak shapes); retention per D-06/D-07 |
</phase_requirements>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Terminal-parity capture (UI narrative, raw puts) | Core (`Core::RunLog` tee on `$stdout`/`$stderr`) | — | All terminal writes flow through the swappable globals (verified: no `STDOUT`/`STDERR` constant writes in lib/) |
| Subprocess output capture (xcodebuild/swift) | Core (`Core::Sh` popen3 branch) | — | Single shell seam by convention (CONVENTIONS.md "Shell Execution"); `live_log:` contract already defined (sh.rb:24-25) |
| Run lifecycle (header/exit, exit status) | `Main.run` orchestration | `Core::RunLog` | `Main.run` sees raw ARGV and the exception boundary; RunLog owns bytes on disk |
| Per-cycle watch files | `Command::Watch` (installer_factory closure) | `Core::RunLog` | The factory proc (watch.rb:35-39) wraps `perform_install`; `Core::Watcher` stays unchanged |
| Retention | `Core::RunLog` (prune called at open) | `Core::Config` (keys) | Pure file-dir bookkeeping; config owns knob values |
| Config keys (`runs_keep`, `runs_max_mb`, `runs_dir`) | `Core::Config` | — | `DEFAULT_CONFIG` + `raw[...]` reader pattern (config.rb:15-22, 122-148) |
| gitignore entry for `.spm-cache/` | `Command::Init` | — | `ensure_gitignore` append-once pattern exists (init.rb:200-211) |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| (none — Ruby stdlib only) | — | `json` (JSONL lines), `tempfile` (atomic header), `fileutils`, `time` | Project constraint: "no new runtime gem dependencies without justification" (AGENTS.md). Everything Phase 12 needs is stdlib; `json` is already required by build_pipeline.rb:7 |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| claide (existing dep) | 1.1.0 (Gemfile.lock pin) | Flag-legality declarations for `--no-run-log` | Declaring the flag in `Command.options` is what keeps `--no-run-log` parseable; compose with `.concat(super)` per convention |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Global `$stdout`/`$stderr` tee | Injectable sinks through `Core::UI` (CP3 suggestion) | Injection would touch every `Core::UI`/`puts` call site and still miss raw `puts` in commands (pkg/build.rb:39, build.rb:29). The global tee captures every channel with two assignments. Rejected injection for this phase. |
| Writer thread + Queue | Mutex around appends | A writer thread is Phase 14's shape (SSE fan-out, backpressure). Phase 12 has at most 3 in-process writers (main thread + 2 Sh reader threads); a Mutex is sufficient and has no drain-on-crash semantics to get wrong. |
| `at_exit` for the exit line | `Main.run` ensure | `ensure` has deterministic ordering vs stream restoration and re-raise semantics; `at_exit` would run after unknown other handlers and can't re-raise correctly. |

**Installation:** nothing to install — zero new packages (gemspec unchanged).

**Version verification:** no registry packages in this phase; claide 1.1.0 behavior was verified by reading the installed gem source (`~/.xcframework-cli/gems/claide-1.1.0/lib/claide/command.rb`, `help.rb`), not from training memory.

## Package Legitimacy Audit

> No external packages are installed by this phase — stdlib only (project constraint). Audit table intentionally empty.

| Package | Registry | Age | Downloads | Source Repo | Verdict | Disposition |
|---------|----------|-----|-----------|-------------|---------|-------------|
| (none) | — | — | — | — | — | — |

**Packages removed due to [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

## Architecture Patterns

### System Architecture Diagram

```
 $ spm-cache <verb> (any verb except web / --no-run-log)
        │
        ▼
 Main.run(argv)  ── pre-scan raw argv: '--version' (existing, main.rb:11),
        │          '--no-run-log', '--log-dir[= ]X', verb ∈ {watch, web}
        ▼
 [not watch/web] Core::RunLog.open(runs_dir, verb, argv, pid)
        │    header file: tempfile+rename → <ts>-<pid>-<verb>.jsonl
        │    then: prune(runs_keep, runs_max_mb)   (D-07)
        ▼
 $stdout = TeeOut.new   $stderr = TeeErr.new        (write-through + append)
        │
        ▼
 Command.run(argv)  ──► CLAide parse/validate/run
        │
        ├─ Core::UI.info/section, raw puts ──► $stdout ──► tee ─┐
        ├─ Core::UI.warn/error ──► $stderr ──► tee ─────────────┤ JSONL body
        │                                                       │ {ts,stream,text}
        ├─ Installer::Build loop (build.rb:52-54)               │
        │    └─ SPM::BuildPipeline.run (pipeline.run:50)        │
        │         ├─ package_start / package_end events ────────┤ {event,...}
        │         └─ Buildable#xcodebuild (build.rb:81)         │
        │              └─ Core::Sh.run(live_log: run_log) ──► popen3
        │                   ├─ 2 reader threads ──► run_log.output(line) ─┤
        │                   └─ 60-line tail retained for failure_detail   │
        ▼                                                                 │
 rescue SystemExit / Interrupt / StandardError ── status captured         │
 ensure: restore $stdout/$stderr, write exit line, close ─────────────────┘
        │
        ▼
 re-raise unchanged → CLAide/top-level → SAME exit code as today (SC3)

 watch verb: Main.run opens NO session file (D-09).
 Command::Watch's installer_factory wraps each perform_install:
   RunLog.open(cycle) → perform_install → exit line → close  (N files)
 web verb (future, Phase 13): argv guard skips everything (SC3).
```

### Recommended Project Structure

```
lib/spm_cache/
├── main.rb                  # MOD: tee install + exit capture around Command.run
├── core/
│   ├── run_log.rb           # NEW: JSONL writer, tee wrappers, prune, cycle API
│   ├── sh.rb                # MOD: popen3 branch retains tail for failure_detail
│   └── config.rb            # MOD: runs_dir, runs_keep, runs_max_mb, DEFAULT_CONFIG keys
├── command.rb               # MOD: --no-run-log declaration (options + initialize)
└── command/
    ├── init.rb              # MOD: ensure_gitignore gains .spm-cache/ entry
    └── watch.rb             # MOD: installer_factory wraps cycles in RunLog files
spec/
├── run_log_spec.rb          # NEW: writer shape, atomicity, prune, tee mechanics
├── main_run_log_spec.rb     # NEW: Main.run wiring, exclusions, exit-line parity
└── sh_run_log_sink_spec.rb  # NEW: popen3 branch sinks + failure_detail restored
```

### Pattern 1: The global tee (capture point 1)

**What:** swap `$stdout`/`$stderr` for write-through wrappers that append JSONL.
**Why it is safe here:** every terminal write in `lib/` goes through the globals — `Core::UI.info` is Kernel `puts` (log.rb:14-16), `warn`/`error` use `$stderr.puts` (log.rb:19-25), commands use raw `puts` (pkg/build.rb:39,51,55-56; build.rb:29), and `Core::Watcher` takes `out: $stdout` evaluated at construction (watcher.rb:27) — after the swap, so it receives the tee. Repo-wide grep found **no** `STDOUT`/`STDERR` constant writes and no `.tty?` reads outside `init.rb:120` (`$stdin`). CLAide reads `STDOUT.tty?` — the constant — for ANSI decisions (claide command.rb:127-132), so the swap cannot change colors.

```ruby
# Core::RunLog-installed wrappers (sketch)
class TeeIO
  def initialize(real, sink, stream)
    @real, @sink, @stream = real, sink, stream
  end
  def write(str) = @sink.record_line(str, @stream) # returns count, like IO#write
  def puts(*args) = args.each { |a| write(a.to_s.chomp + "\n") }
  def <<(str) = write(str); self
  def tty? = @real.tty?          # delegate — cheap insurance even though
  def sync = @real.sync          # claide reads the constant, not the global
  def sync=(v) = @real.sync = v
  def flush = @real.flush
  def isatty = @real.isatty
end
```

Terminal write-through must be immediate (no internal buffering) or stdout/stderr interleaving changes — that alone would violate SC3.

**Source: in-repo verified seams (log.rb:14-25, watcher.rb:27; convention precedent: doctor_spec.rb:187-191 swaps `$stdout` to capture command output).**

### Pattern 2: Core::RunLog — the file sink (both `output(line)` and structured events)

**What:** one class owning the per-run file: atomic header creation, mutex-serialized appends, `output(line)` for `Core::Sh`, explicit event emission, exit line + close.

```ruby
module SPMCache
  module Core
    class RunLog
      # Sh contract: each_line yields lines WITH trailing "\n" (sh.rb:24-25)
      def output(line) = record_text(line, "out")   # stream tag refined below

      def record_line(str, stream)                  # tee entry: may be partial
        str.each_line { |l| record_text(l, stream) }
      end

      def event(name, **fields)                     # package_start, phase, ...
        append(JSON.generate({"event" => name, "ts" => now_iso}.merge(fields)))
      end

      def finish(status, ended_at: Time.now.utc)    # exit line; idempotent
        event("run_end", status: status, ended_at: iso(ended_at)) unless @finished
        @finished = true
      end
    end
  end
end
```

- Appends go to a `File` opened `WRONLY|APPEND|CREAT` with `sync = true` — every line hits disk at once, so a Ctrl-C'd run leaves everything up to the interrupt (SC2) without any `at_exit` machinery.
- One `Mutex` guards `append` — the concurrent writers are the main thread (tee) plus two Sh reader threads (sh.rb:24-25). Cross-process contention does not exist: each run owns its own file.
- Header atomicity: write the header-only file via `Tempfile` in the same dir + `File.rename` (the `SPM::ResolvedGraph.atomic_write` precedent, resolved_graph.rb:71-79), then reopen in append mode. A Phase 14 tailer can therefore never observe a run file without its identity header.
- Sh reader threads hand raw `each_line` chunks to `output(line)`; both stdout and stderr lines carry stream tags, so `Sh.run` must pass the stream name — give `live_log` a pair-shaped call or wrap the sink per stream: `RunLog::StreamSink.new(run_log, "err")` responding to `output(line)`. (The current single `live_log` object cannot distinguish streams — sh.rb:24-25 call it identically; the plan must add per-stream sinks or a second opt.)

### Pattern 3: Exit-line capture in `Main.run` (verified exception shapes)

`CLAide::Command.run` wraps everything in `rescue Object => exception` and either `exit(status)` (for `InformativeError` — which includes `CLAide::Help`) or re-raises via `report_error` (claide command.rb:324-338, 387-397, 409-416). Because `Core::GeneralError` does **not** include `CLAide::InformativeError` (error.rb:1-15; repo-wide grep for `InformativeError` = zero lib hits), today's real failure path is: GeneralError/RuntimeError re-raised out of `Command.run` → uncaught at top level → Ruby prints message + backtrace to stderr, **exit 1** (probed on the real CLI: `spm-cache use` with no xcodeproj → `use.rb:25` RuntimeError, exit 1). Uncaught `Interrupt` exits **130** (probed: `ruby -e 'raise Interrupt'` → 130). `exit 1` in doctor (doctor.rb:42) surfaces as `SystemExit`. Plain `--help` exits **0** (`CLAide::Help` with no error message, claide help.rb:30).

So exactly three shapes escape to `Main.run`:

```ruby
def self.run(argv)
  SPMCache::Main.load_all
  return puts(SPMCache::VERSION) if argv.first == '--version' # existing pre-scan precedent

  exclusions = { 'web' => :skip, 'watch' => :watch_cycles }   # verb from raw argv
  run_log = Core::RunLog.maybe_open(argv) unless Core::RunLog.suppressed?(argv)
  old_out, old_err = $stdout, $stderr
  status = 0
  begin
    $stdout = run_log.tee_out(old_out) if run_log
    $stderr = run_log.tee_err(old_err) if run_log
    Command.run(argv)
  rescue SystemExit => e
    status = e.status; raise
  rescue Interrupt
    status = 130; raise                      # probed: matches Ruby top-level exit
  rescue StandardError => e
    status = e.respond_to?(:exit_status) ? e.exit_status : 1  # GeneralError (error.rb:8-13)
    raise
  ensure
    $stdout, $stderr = old_out, old_err      # restore BEFORE finishing the log
    run_log&.finish(status)                  # exit line + flush + close; idempotent
  end
end
```

Re-raising preserves today's behavior bit-for-bit: `raise` with no args re-raises `$!` with its original backtrace; the interpreter then produces the identical stderr dump and exit code it produces today. `Command::Watch` and `use --watch` rescue `Interrupt` internally (watcher.rb:73-81; use.rb:80-81), so watch sessions reach `ensure` with `status = 0` — correct: the watch PROCESS exits cleanly; the per-cycle files carry their own exit lines (below).

### Pattern 4: Watch per-cycle files (D-09) via the installer_factory seam

`Core::Watcher` calls `@installer_factory.call(project_path)` then `perform_install` (watcher.rb:90-93), and the factory is injected from `Command::Watch#run` (watch.rb:35-39). Wrap the returned installer in a decorator that opens a cycle file around `perform_install`:

```ruby
# Command::Watch#run
installer_factory = lambda do |path|
  installer = Installer::Use.new(project: path)
  Core::RunLog.cycle_wrapper(installer, verb: 'watch', argv: ARGV) # responds to perform_install
end
```

The cycle wrapper writes its own header (command "watch", cycle marker), streams the tee output while active, and writes the exit line in its own ensure — a mid-regeneration TERM (watcher's `Signal.trap('TERM') { raise Interrupt }`, watcher.rb:49) still lands the exit line via that ensure, then watcher's `rescue Interrupt` (watcher.rb:73) proceeds as today. `watch --once` flows through `run_once` → the same factory (watcher.rb:35-45, watch.rb:41-43), so it logs identically. **`Core::Watcher` is not modified.**

Watch's inter-cycle narrative ("Watching …", "[watch] SPM graph changed…") hits the tee while no cycle file is active → terminal-only by design (D-09 forbids a session file). State this in the plan so it is a decision, not an accident.

### Pattern 5: Retention (D-06/D-07) — ~20 lines of stdlib

After the new header lands (D-07 ordering), prune: list `runs_dir/*.jsonl` (timestamp-prefixed names sort lexicographically newest-first), delete oldest while `count > runs_keep` **or** `total_bytes > runs_max_mb`, never deleting the current run's own file. Config keys join `DEFAULT_CONFIG` (config.rb:15-22) as flat snake_case: `"runs_keep" => 50, "runs_max_mb" => 500`, read in the established `raw[...] || default` style (config.rb:122-148). Document the yml keys as comments in `assets/templates/spm-cache.yml.template` (the template is the discoverability surface; `Command::Init#write_config` merges over DEFAULT_CONFIG so existing ymls keep working untouched).

### Pattern 6: Naming (discretion, recommended)

`<UTC timestamp>-<pid>-<verb>.jsonl`, timestamp `Time.now.utc.strftime('%Y%m%dT%H%M%SZ')` → `20260831T154502Z-4821-build.jsonl`. Zero-padded UTC gives lexicographic = chronological age ordering (retention needs no stat calls for ordering); pid disambiguates same-second launches; `.jsonl` states the format. SC1's "outside the sandbox" is satisfied structurally: `runs_dir = File.join(project_dir, ".spm-cache", "runs")` — `recreate_dirs` only `rm_rf`s `sandbox_dir` (`spm-cache/`), the same reason `build_lock_path` lives at the project root (config.rb:95-103).

### Anti-Patterns to Avoid

- **Monkey-patching `puts`/IO** — prohibited by convention (CONVENTIONS.md "Mixins and Refinements"). Swap the `$stdout` global; do not reopen `IO`.
- **A second shell-out path** — the capture must ride `Core::Sh`'s existing `live_log:` seam; never add a parallel Open3/backtick path. (Pre-existing violation to ignore, not copy: `pkg/build.rb:56` uses a backtick `du`.)
- **Transforming the stream** — the tee writes through verbatim (ANSI codes included; the Phase 13+ frontend renders them). Any line rewriting breaks byte-parity (SC3) and doubles the test surface.
- **Per-run size caps / head+tail clipping** — D-05 forbids truncation; disk is bounded only by retention.
- **Session file for watch** — D-09 forbids it; one file per regeneration cycle.
- **Buffering the terminal leg** — write-through immediately; only the file leg has flush policy (and it is `sync = true` anyway).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON encoding of log lines | String interpolation of payloads | `JSON.generate` (stdlib json) | Escaping (newlines, quotes, ANSI bytes inside strings) is exactly where hand-rolled JSONL corrupts tailers |
| Atomic file publish | open-write-hope | `Tempfile` + `File.rename` same-dir | In-repo proven precedent: `SPM::ResolvedGraph.atomic_write` (resolved_graph.rb:71-79) |
| Timestamp formatting | manual epoch math | `Time#utc` + `strftime('%Y%m%dT%H%M%SZ')` | Lexicographic ordering guarantee for free |
| Exit-status plumbing | re-implementing CLI error mapping | Rescue the three shapes CLAide actually leaks (SystemExit/Interrupt/StandardError) | Verified leak surface; anything finer (e.g. parsing CLAide internals) couples Phase 12 to gem internals |
| Retention prune framework | gem or scheduler | ~20-line count+size loop at run open | D-07 pins rotation-time cleanup; a maintenance command is explicitly out |

**Key insight:** the project's no-new-deps constraint plus the existing `output(line)` seam means the entire phase is composition of mechanisms already in the repo — the risk is integration fidelity (exit codes, terminal bytes, watch cycles), not library selection.

## Common Pitfalls

### Pitfall 1: The flag chicken-and-egg (tee installs before CLAide parses)
**What goes wrong:** `Main.run` must know `--no-run-log` / `--log-dir` / the verb before `Command.run` parses argv, or the first lines of a run are already lost/mis-routed.
**Why it happens:** CLAide parsing happens inside `Command.run`; the tee must wrap the streams *around* it to capture parse errors and help output.
**How to avoid:** pre-scan raw argv in `Main.run` — the `argv.first == '--version'` intercept (main.rb:11) is the exact in-repo precedent. Match `--log-dir=X` and `--log-dir X` forms; treat `--no-run-log` anywhere in argv as off. **Keep** the CLAide-level declarations (`--log-dir` already at command.rb:20/29; declare `--no-run-log` like `--no-merge-slices`, parsed `argv.flag?('run-log', true)` at command.rb:30-31 pattern) — the declarations are what keep the flags legal to parse; without them CLAide rejects the argv before `Main.run` even sees the command.
**Warning signs:** `spm-cache --no-run-log use` still writes a log; `--log-dir` ignored.

### Pitfall 2: Exit code drift via rescue-and-reraise
**What goes wrong:** "improving" error handling (rescuing GeneralError and `exit 1` cleanly) changes stderr output (backtrace disappears) or masks statuses — SC3 violation.
**Why it happens:** today's failure output *is* an uncaught-exception dump (probed: `use.rb:25` RuntimeError → backtrace → exit 1).
**How to avoid:** always bare `raise` (re-raise `$!` untouched); only observe status in rescue/ensure. Never `exit` from the ensure.
**Warning signs:** any spec asserting stderr content changes; manual diff of before/after stderr for a failing run differs.

### Pitfall 3: `tty?`/ANSI behavior change
**What goes wrong:** a tee wrapper without `tty?` breaks code that probes it; ANSI styling flips off.
**How to avoid:** delegate `tty?`/`isatty`/`sync`/`flush` to the real stream. Note CLAide specifically reads the `STDOUT` *constant* (claide command.rb:129), so the global swap is inherently invisible to it — delegation is defense-in-depth for future callers.
**Warning signs:** colors vanish under a TTY; `--help` output loses styling.

### Pitfall 4: Sh reader threads and stream attribution
**What goes wrong:** the current `live_log:` contract calls one object for both streams (sh.rb:24-25) — a run-log sink keyed to a single stream tag silently mislabels xcodebuild stdout as stderr (or vice versa), corrupting SC2's "reconstructable offline".
**How to avoid:** pass per-stream sinks: wrap the RunLog in a `StreamSink.new(run_log, "out"|"err")` per reader thread (keeps `output(line)` intact), or extend the opt to `live_log_out:`/`live_log_err:` with a back-compat path for the single-object form.
**Warning signs:** body lines whose `stream` contradicts their content (compiler errors tagged `out` are legitimate — xcodebuild reports to stdout, sh.rb:55-58 comment — so test with an `echo`-to-stderr case, not with xcodebuild heuristics).

### Pitfall 5: CP3 three-channel capture — tapping only one channel
**What goes wrong:** capturing Sh output but not the tee (or vice versa) yields logs missing the "Building X…"/failure narrative or missing subprocess output.
**How to avoid:** both capture points ship in this phase (tee + Sh sink); `capture3` results must ALSO reach the log — today `capture_output` results are consumed as values (e.g. scheme detection, build_pipeline.rb:472-476) and never printed; log them at the Sh boundary (one `run_log.event`/body line per completed capture3 call with cmd + truncated output) or accept that value-returning captures are invisible. Recommendation: record capture3 commands as structured events (`{"event":"sh","cmd":...,"status":N}`) — cheap, bounded, and makes `swift package describe`/`xcodebuild -list` visible in reconstruction.
**Warning signs:** a run log with UI narrative but zero xcodebuild lines during a real build (Sh sink missing); the inverse (subprocess spam, no narrative) means the tee missed.

### Pitfall 6: Retention racing a concurrent reader/pruner
**What goes wrong:** two processes finishing runs simultaneously both prune; or Phase 14's tailer reads a file being unlinked.
**How to avoid:** pruning only files that are (a) older than the newest, (b) not the current run, (c) not lacking an exit line *while their header pid is alive* — the CP14 rule applied defensively at birth: a live pid's log is never a prune candidate. Within-process Mutex is enough for our own appends; unlink races across processes are benign on POSIX (open fds stay valid).
**Warning signs:** "run log vanished mid-build" reports after Phase 14.

### Pitfall 7: Sandbox vs runs dir (CP-adjacent, already structural)
**What goes wrong:** placing run logs under `sandbox_dir` gets them `rm_rf`'d mid-run by `recreate_dirs` (installer/use.rb:36).
**How to avoid:** `runs_dir` at project root (Pattern 6) — the `build_lock_path` comment (config.rb:98-100) documents exactly this reasoning; mirror it in the `runs_dir` comment citing D-02.
**Warning signs:** logs disappearing on every slow-path `use`.

### Pitfall 8: The spec-suite guard is per-spec, not in spec_helper
**What goes wrong:** new run-log specs assume `spec/spec_helper.rb` installs the default-deny `Core::Sh` guard — it does not; the file is 18 lines (verified) and only smoke-tests `SPMCache` constants. The guard is a per-file pattern from the fidelity specs (fidelity_bucket_partition_spec.rb:56-67: stub both `Sh.run` and `Sh.capture_output` to raise).
**How to avoid:** each new spec file arms its own guard where zero shell-outs are expected; where a real subprocess is fine, note that `capture_output("echo hello")` through the real `Core::Sh` is established suite precedent (core_spec.rb:6-8).
**Warning signs:** a spec passing because Sh is stubbed in a *different* file's before-block (they don't leak — rspec mocks are per-example — but a copy-pasted assumption silently disables coverage).

## Runtime State Inventory

> Not a rename/refactor/migration phase — greenfield capture layer. Category answers for completeness:
> **Stored data:** none new (writes only new files under `.spm-cache/runs/`). **Live service config:** none. **OS-registered state:** none. **Secrets/env vars:** none read or written; argv is recorded — today's flags carry no secrets (verified flag surface command.rb:16-24). **Build artifacts:** none affected.

## Code Examples

### Verified current seams (quote-level, for the planner)

- `Main.run` insertion point — main.rb:8-14: `run(argv)` → `load_all` → `--version` intercept → `Command.run(argv)`. Nothing else.
- `Core::UI` writes — log.rb:14-25: `info` → `puts msg`; `warn` → `$stderr.puts "[warn] #{msg}"`; `error` → `$stderr.puts "[error] #{msg}"`; `error!` → error + `raise GeneralError`.
- `Core::Sh` — sh.rb:10-42: `live_log` opt; popen3 branch (20-33) spawns two reader threads calling `live_log.output(l)`, joins, raises `"Command failed (exit #{status.exitstatus}): #{cmd}"` **without detail**, returns `{ output: "", status: 0 }`; capture3 branch (35-41) embeds `failure_detail` (last 60 lines per stream, sh.rb:63-71) on failure.
- `live_log:` suppliers today: **none** — the only pass-through is `Buildable#xcodebuild` (build.rb:80-87) forwarding `opts[:live_log]`, and no caller sets it (repo grep). The seam is dormant, exactly as the milestone research stated.
- Per-package build loop — installer/build.rb:52-54 `missed.each { build_single_target(...) }`; `build_single_target` (157-184) prints "  Building #{target_name}...", calls `SPM::BuildPipeline.run` (the same entry `pkg build` uses, pkg/build.rb:43), prints "  Cached: #{result}", honors `ignore_build_errors?`.
- Watch cycle boundary — watcher.rb:90-93 `regenerate` = `@installer_factory.call(project_path)` + `perform_install`; factory injected at watch.rb:35-39.
- `--log-dir` stub — command.rb:20 (options), command.rb:29 (`@log_dir = argv.option("log-dir")`), base.rb:8 (`LOG_DIR = nil`), base.rb:22-24 (`log_dir` reader). Consumers: **none**.
- Flag precedent — command.rb:30-31: `@merge_slices = argv.flag?("merge-slices", true)` (the `--no-merge-slices` shape D-03 cites).
- gitignore append-once — init.rb:200-211: reads lines, `return if lines.include?(entry)`, appends comment + entry. Extend independently for the second entry `.spm-cache/`.
- DEFAULT_CONFIG — config.rb:15-22 verbatim: `"ignore" => [], "cache_only" => [], "ignore_local" => false, "ignore_build_errors" => false, "keep_pkgs_in_project" => false, "default_sdk" => "iphonesimulator"`. New keys follow this flat snake_case shape.
- `Core::GeneralError` — error.rb:7-14: carries `exit_status` (default 1). Not a `CLAide::InformativeError`.
- doctor exit — doctor.rb:42: `exit 1 if results.any?(&:fail?)`.

### Sh popen3 fix shape (behavior-preserving)

```ruby
# core/sh.rb — popen3 branch
out_tail, err_tail = [], []   # bounded: keep last FAILURE_DETAIL_LINES each
sink_out = opts[:live_log_out] || StreamSink.new(live_log, "out")
sink_err = opts[:live_log_err] || StreamSink.new(live_log, "err")
Open3.popen3(env, cmd, **spawn_opts) do |stdin, stdout, stderr, wait_thr|
  stdin.close
  threads = [
    Thread.new { stdout.each_line { |l| sink_out.output(l); out_tail << l; out_tail.shift if out_tail.size > FAILURE_DETAIL_LINES } },
    Thread.new { stderr.each_line { |l| sink_err.output(l); err_tail << l; err_tail.shift if err_tail.size > FAILURE_DETAIL_LINES } },
  ]
  threads.each(&:join)
  status = wait_thr.value
  unless status.success?
    raise GeneralError.new("Command failed (exit #{status.exitstatus}): #{cmd}\n#{failure_detail(out_tail.join, err_tail.join)}")
  end
end
{ output: out_tail.join, error: err_tail.join, status: 0 }
```

Terminal behavior is preserved because today's terminal never sees live xcodebuild output at all (capture3 discards it; only the failure message surfaces — now with the same 60-line detail the capture3 path has always had). No caller reads the popen3 return value today (build.rb:81,86 ignore it), so the enriched return hash changes nothing observable.

### Run-file shape (D-04 vocabulary, recommended field names)

```jsonl
{"event":"run_start","ts":"2026-08-31T15:45:02Z","command":"build","argv":["build","Alamofire"],"pid":4821,"started_at":"2026-08-31T15:45:02Z","spm_cache_version":"0.4.0"}
{"ts":"2026-08-31T15:45:02Z","stream":"out","text":"\n============\nspm-cache\n============\n"}
{"event":"phase","ts":"...","name":"build"}
{"event":"package_start","ts":"...","name":"Alamofire"}
{"ts":"...","stream":"out","text":"  Building Alamofire for iphonesimulator...\n"}
{"ts":"...","stream":"out","text":"...xcodebuild output verbatim, ANSI included...\n"}
{"event":"package_end","ts":"...","name":"Alamofire","status":"ok"}
{"event":"run_end","ts":"...","status":0,"ended_at":"..."}
```

Header = `run_start` (one line serves SC1's header and D-04's event), exit line = `run_end`. `package_*` emitted at `SPM::BuildPipeline.run` entry/exit (build_pipeline.rb:50-89) — the single choke point shared by `Installer::Build`'s loop and `pkg build`. Phase markers: minimum `{detect, integrate, build, fidelity}`; emit from `Installer::Use#perform_install` branches (use.rb:21-45) and `Installer::Build#perform_install` (build.rb:18-58). Optional forward-compat field `trigger` (`terminal`/`watch`) on `run_start` — LOGS-05 will want it; one field now is cheaper than a schema rev later (flag for planner decision).

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Capture via injectable UI sinks only (CP3 draft idea) | Global `$stdout`/`$stderr` tee + Sh sink | This research | Covers raw `puts` call sites UI-injection would miss (pkg/build.rb:39, build.rb:29) |
| UDS relay transport (STACK.md draft) | File-tail JSONL run logs | v0.5.0 milestone research (SUMMARY.md verdict, baked into ROADMAP) | Phase 12 *is* the transport; SSE/Last-Event-ID ride it in Phase 14 |
| `failure_detail` only on capture3 path | Same detail on popen3 path (tail ring) | This phase's scope | Failing live-mode builds regain error lines (milestone-flagged gap) |

**Deprecated/outdated:** none relevant — no gems, no APIs removed.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Verb detection from raw argv (first non-`-` argument; default `use`) is sufficient for exclusion routing; a target literally named `watch`/`web` as the first positional of another verb is accepted as a non-issue | Pattern 1/Pitfall 1 | Mis-routed tee for a pathological invocation — cosmetic, self-heals with D-08 defaults |
| A2 | `capture3` calls should be recorded as structured `sh` events (cmd + status), not full output | Pitfall 5 / vocabulary | If planner disagrees, value-returning captures stay unlogged — SC2 still met (they are not terminal-visible today) |
| A3 | `trigger` field on `run_start` now (vs Phase 14) is the cheaper ordering | Code Examples | One optional field; harmless if dropped |
| A4 | Per-stream sink pair (`live_log_out`/`live_log_err`) or StreamSink wrapper added to `Core::Sh` opts is the right stream-attribution shape | Pitfall 4 | Misattributed streams if single-sink form kept as-is |
| A5 | Inter-cycle watch narrative (banners between regenerations) is intentionally not persisted (D-09 reading) | Pattern 4 | If user expected it captured, needs a session-file conversation — D-09 currently forbids one |
| A6 | `use --watch` (legacy CP5 loop, use.rb:52-82) logs as ONE session-level `use` run (Main-level file), not per-cycle — D-09's per-cycle mandate targets the `watch` daemon; CP5/CP6 treat the legacy loop as CLI-only | Open Questions | If per-cycle wanted here too, extra plumbing through a private loop; recommend explicit plan note either way |

## Open Questions

1. **Legacy `use --watch` per-cycle or session-level?**
   - What we know: two watch loops exist (use.rb:52-82 legacy; Command::Watch/Watcher canonical). D-09 says the watch daemon writes per-cycle files; it does not name the legacy loop.
   - Recommendation: session-level for `use --watch` (A6), documented in the plan; revisit only if Phase 14's relay needs parity (CP5 says treat it CLI-only).
2. **`trigger` field: now or Phase 14?** (A3) — planner's call; both defensible.
3. **Should the exit line's `status` for uncaught non-GeneralError exceptions distinguish 1 vs 130 vs "signal"?** Recommendation: numeric only (0/1/130/e.status); CP14's later detector keys on exit-line *presence* + pid liveness, not fine-grained cause.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Ruby | everything | ✓ | 3.2.3 (rbenv, this machine; gemspec floor >= 3.0) | — |
| rspec | validation | ✓ | ~> 3.12 pinned (Gemfile.lock) | — |
| json / tempfile / fileutils (stdlib) | RunLog | ✓ | bundled with Ruby | — |
| claide | flag declarations | ✓ | 1.1.0 (Gemfile.lock pin) | — |

**Missing dependencies with no fallback:** none.
**Missing dependencies with fallback:** none. (No network, no xcodebuild required for the spec suite; real-subprocess specs use `echo` per core_spec precedent.)

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | RSpec ~> 3.12 (gemspec dev dep; suite ~441 examples, hermetic) |
| Config file | none beyond `.rspec` defaults; no spec/support dir (verified) |
| Quick run command | `bundle exec rspec spec/run_log_spec.rb` |
| Full suite command | `bundle exec rspec` (Makefile `make test`) |

### Phase Requirements → Test Map

| Req | Behavior | Test Type | Automated Command | File Exists? |
|-----|----------|-----------|-------------------|-------------|
| LOGS-01/SC1 | Header/body/exit JSONL shape; `runs_dir` = `<project>/.spm-cache/runs` (outside `sandbox_dir`) | unit | `bundle exec rspec spec/run_log_spec.rb` | ❌ Wave 0 |
| SC1/SC3 | Tee is byte-invisible: with capture on, `$stdout`+`$stderr` bytes identical to capture off (StringIO baselines; existing `$stdout`-swap convention, doctor_spec.rb:187-191) | unit | `bundle exec rspec spec/main_run_log_spec.rb` | ❌ Wave 0 |
| SC1/SC3 | Exit line present with correct status on: normal return, SystemExit (doctor-style `exit 1`, help → 0), GeneralError (→ 1), Interrupt (→ 130); re-raise unchanged | unit | `bundle exec rspec spec/main_run_log_spec.rb` | ❌ Wave 0 |
| SC3 | Exclusions: `web` argv and `--no-run-log` produce no run file; `--log-dir=X` overrides dir (pre-scan) | unit | `bundle exec rspec spec/main_run_log_spec.rb` | ❌ Wave 0 |
| SC2 | Sh popen3 branch: both streams land in sink with correct tags; failure_detail regains tail (GeneralError message contains tail lines); capture3 path unchanged; a real `echo`/`sh -c 'echo err >&2'` through the real Sh is in-bounds (core_spec precedent) | unit | `bundle exec rspec spec/sh_run_log_sink_spec.rb` | ❌ Wave 0 |
| SC2 | Tee captures `Core::UI.info/warn/error` AND raw `puts` into the file verbatim (incl. ANSI bytes) | unit | `bundle exec rspec spec/run_log_spec.rb` | ❌ Wave 0 |
| D-04 | `package_start`/`package_end` emitted around `SPM::BuildPipeline.run` (both `pkg build` and Installer loop paths) | unit | `bundle exec rspec spec/build_pipeline_spec.rb spec/run_log_spec.rb` | ❌ Wave 0 |
| D-09 | Watch cycles: factory-wrapped installer opens a fresh file per `perform_install`, each with header+exit; `Core::Watcher` untouched (run_once-level, no traps in-process — watch_signals_spec.rb:69-78 explains why traps never run inside RSpec) | unit | `bundle exec rspec spec/watch_spec.rb spec/run_log_spec.rb` | ❌ Wave 0 |
| D-06/D-07/SC4 | Retention: prune keeps newest `runs_keep`, enforces size budget, never deletes current run, runs after header write; config keys read with defaults 50/500 | unit | `bundle exec rspec spec/run_log_spec.rb spec/config_spec.rb` | ❌ Wave 0 |
| D-02 | `.gitignore` gains `.spm-cache/` (append-once, idempotent) | unit | `bundle exec rspec spec/init_spec.rb` (extend) | extend Wave 0 |
| SC1-SC4 (gate) | Real-CLI smoke (manual/E2E at verify): fixture project → `bin/spm-cache build/use/watch --once` leaves parseable JSONL; failing run (no xcodeproj) exits 1 with byte-identical stderr vs pre-change; `jq`/ruby parses every line | manual | — | Phase verify checklist |

### Sampling Rate

- **Per task commit:** `bundle exec rspec spec/run_log_spec.rb spec/main_run_log_spec.rb spec/sh_run_log_sink_spec.rb` (fast, hermetic)
- **Per wave merge:** `bundle exec rspec` (full suite must stay green — existing 441 examples are the terminal-parity regression net, esp. main_version_spec.rb for the `--version` pre-scan path)
- **Phase gate:** full suite green + manual real-CLI smoke before `/gsd-verify-work`

### Wave 0 Gaps

- [ ] `spec/run_log_spec.rb` — writer shape, tee mechanics, retention, events
- [ ] `spec/main_run_log_spec.rb` — Main.run wiring, exclusions, exit-line parity
- [ ] `spec/sh_run_log_sink_spec.rb` — popen3 sink + failure_detail restoration
- [ ] extend `spec/init_spec.rb` — `.spm-cache/` gitignore entry

## Security Domain

`security_enforcement: true`, ASVS Level 1 (config.json). Surface analysis for this phase:

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | N/A — local CLI, no auth surface |
| V3 Session Management | no | N/A |
| V4 Access Control | no | Files inherit project-dir trust domain (same as spm-cache.yml/lockfile today) |
| V5 Input Validation | minimal | `--log-dir` is a local path from the same user; no untrusted input enters parsing. Retention config values: `Integer()`-coerce with rescue-to-default (yml is user-authored, not adversarial) |
| V6 Cryptography | no | N/A |
| V7 Logging (integrity) | yes | JSONL via `JSON.generate` (escaping defeats accidental log forgery via crafted package/output text); logs are append-only, local, no secrets in argv (flag surface verified command.rb:16-24) |

### Known Threat Patterns

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Log-content spoofing by subprocess output | Tampering | Body lines are data (`stream`/`text`), events are structured (`event` field) — a renderer trusts only `event` lines; document for Phase 14 |
| Disk-fill via log growth | DoS | D-06 retention (count+size) — the phase's own control |
| Path traversal via `--log-dir` | — | Same-trust-domain local user; out of threat model (mirrors existing `--config`/project_dir handling) |

## Sources

### Primary (HIGH confidence — all read this session, 2026-08-31)
- `lib/spm_cache/main.rb:8-14` — insertion point; `--version` pre-scan precedent
- `lib/spm_cache/core/log.rb:1-45` — UI write paths (puts / $stderr.puts)
- `lib/spm_cache/core/sh.rb:10-71` — popen3/capture3 branches, `live_log:` contract, FAILURE_DETAIL_LINES, discarded-capture gap
- `lib/spm_cache/core/live_log.rb` — dormant; unbounded capture + unconditional TTY codes (do not reuse for the sink)
- `lib/spm_cache/core/config.rb:15-22,64-103,122-148` — DEFAULT_CONFIG verbatim, build_lock_path placement rationale, raw-reader pattern
- `lib/spm_cache/command.rb:16-33`, `command/base.rb:1-41` — `--log-dir` stub end-to-end, flag parse precedents
- `lib/spm_cache/core/watcher.rb:27,46-93` — TERM trap, Interrupt contract, regenerate/factory seam
- `lib/spm_cache/command/watch.rb`, `command/use.rb:22-82` — both watch loops (CP5), Interrupt rescue paths
- `lib/spm_cache/installer/use.rb:16-71`, `installer/build.rb:18-58,157-184` — locks, recreate_dirs, per-package loop
- `lib/spm_cache/spm/build_pipeline.rb:50-89,102-153,302-310,472-476` — pipeline.run, report_fidelity, build sections, capture3 consumers
- `lib/spm_cache/spm/build.rb:80-87` — only live_log pass-through (dormant)
- `lib/spm_cache/spm/resolved_graph.rb:71-79` — atomic_write precedent
- `lib/spm_cache/command/init.rb:39-57,200-211` — init flow, gitignore append-once
- `lib/spm_cache/core/error.rb` — GeneralError (no InformativeError)
- `lib/spm_cache/assets/templates/spm-cache.yml.template` — doc surface for new keys
- claide 1.1.0 gem source (`~/.xcframework-cli/gems/claide-1.1.0/lib/claide/command.rb:324-338,387-397,409-416,127-132`; `help.rb:24-31`) — dispatcher, handle_exception/report_error, STDOUT.tty?, Help exit statuses
- spec conventions: `spec/spec_helper.rb` (18 lines, no global guard — corrected from CONTEXT.md), `fidelity_bucket_partition_spec.rb:56-67` (default-deny guard pattern), `core_spec.rb:6-8` (real `echo` precedent), `doctor_spec.rb:187-191` ($stdout-swap convention), `watch_signals_spec.rb:69-78` (traps never in-process), `main_version_spec.rb`, `config_spec.rb`

### Machine probes (2026-08-31)
- `spm-cache use` in empty dir → RuntimeError from use.rb:25, stderr backtrace, exit 1 (today's failure shape)
- `ruby -e 'raise Interrupt'` → exit 130; `exit 3` → 3; uncaught StandardError → 1

### Secondary (MEDIUM — planning docs, treated as context not evidence)
- `.planning/research/ARCHITECTURE.md` §4 (run-log design, tee + Sh capture points), `PITFALLS.md` CP3/CP5/CP6/CP7/CP14, `SUMMARY.md` (file-tail JSONL verdict)
- `.planning/codebase/CONVENTIONS.md` (no-monkey-patching, `.concat(super)`, cite-pitfall-ID comments)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — zero new deps; all stdlib usage already precedented in-repo
- Architecture: HIGH — every seam re-read at file:line this session; CLAide gem source read directly (not remembered)
- Pitfalls: HIGH — code-anchored; exit-code table machine-probed; spec-guard drift corrected

**Research date:** 2026-08-31
**Valid until:** 2026-09-30 (stable: codebase-grounded; re-verify if `lib/` moves before Phase 12 execution)
