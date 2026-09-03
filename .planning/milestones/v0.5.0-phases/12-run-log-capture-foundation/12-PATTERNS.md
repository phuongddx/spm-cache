# Phase 12: Run-Log Capture Foundation - Pattern Map

**Mapped:** 2026-08-31
**Files analyzed:** 17 (4 new, 13 modified/extended)
**Analogs found:** 17 / 17 (13 exact self-modification precedents; 4 role-match composites — this phase is integration of existing mechanisms, not greenfield architecture)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `lib/spm_cache/core/run_log.rb` (NEW) | service (file sink + IO wrappers + retention) | streaming + file-I/O | `core/live_log.rb` (`output(line)` contract) + `spm/build_pipeline.rb:220-237` (atomic Tempfile+rename sidecar write) | role-match (composite) |
| `lib/spm_cache/main.rb` (MOD) | entrypoint/controller | request-response | itself — argv pre-scan precedent (main.rb:11) | exact (self) |
| `lib/spm_cache/core/sh.rb` (MOD) | service (single shell seam) | streaming (popen3 reader threads) | itself — capture3 `failure_detail` tail (sh.rb:55-71) is the exact pattern the popen3 branch copies | exact (self) |
| `lib/spm_cache/core/config.rb` (MOD) | config | CRUD (yml read) | itself — `DEFAULT_CONFIG` + `raw[...] || default` readers + `build_lock_path` outside-sandbox placement | exact (self) |
| `lib/spm_cache/command.rb` (MOD) | route (CLI base flag surface) | request-response | itself — `--no-merge-slices` flag precedent (command.rb:19,30) | exact (self) |
| `lib/spm_cache/command/base.rb` (MOD) | config defaults + readers | request-response | itself — `Options::LOG_DIR` / `#log_dir` stub (base.rb:8,22-24) | exact (self) |
| `lib/spm_cache/command/init.rb` (MOD) | command | file-I/O | itself — `ensure_gitignore` append-once (init.rb:200-211) | exact (self) |
| `lib/spm_cache/command/watch.rb` (MOD) | controller (daemon wiring) | event-driven | itself — `installer_factory` lambda (watch.rb:35-39) | exact (self) |
| `lib/spm_cache/spm/build_pipeline.rb` (MOD) | service (build orchestration) | batch/transform | itself — `run` begin/ensure (build_pipeline.rb:55-88) + "consolidated insertion point" convention (build_pipeline.rb:93-102) | exact (self) |
| `lib/spm_cache/installer/use.rb` (MOD) | orchestrator | request-response | itself — `perform_install` fast-path/full branches (use.rb:21-45) | exact (self) |
| `lib/spm_cache/installer/build.rb` (MOD) | service | batch | itself — per-package loop (build.rb:52-54) | exact (self) |
| `lib/spm_cache/spm/build.rb` (MOD, likely) | utility (Buildable) | request-response | itself — `live_log:` pass-through (build.rb:80-87) gains out/err variants | exact (self) |
| `lib/spm_cache/assets/templates/spm-cache.yml.template` (MOD) | config documentation | — | itself — commented-out key convention (`# remote:` block) | exact (self) |
| `spec/run_log_spec.rb` (NEW) | test | — | `spec/core_spec.rb` (unit shape) + `spec/fidelity_bucket_partition_spec.rb:53-67` (tmpdir + default-deny guard) | role-match |
| `spec/main_run_log_spec.rb` (NEW) | test | — | `spec/main_version_spec.rb` (Main.run harness) + `spec/doctor_spec.rb:186-195` ($stdout swap + exit expectation) | role-match |
| `spec/sh_run_log_sink_spec.rb` (NEW) | test | — | `spec/core_spec.rb:6-31` (real `echo` through real `Core::Sh`) | role-match |
| `spec/init_spec.rb` (MOD/extend) | test | — | itself — gitignore assertions (init_spec.rb:60, 146-168) | exact (self) |

## Pattern Assignments

### `lib/spm_cache/core/run_log.rb` (service, streaming + file-I/O) — NEW

**Analog 1 — the `output(line)` consumer contract** that `Core::Sh`'s dormant popen3 branch already calls (sh.rb:24-25: `Thread.new { stdout.each_line { |l| live_log.output(l) } }`). `Core::LiveLog` is the only existing implementor — copy the duck-type shape, NOT its rendering (research: "do not reuse for the sink"; it captures unboundedly and prints TTY cursor codes):

`lib/spm_cache/core/live_log.rb:26-29`:
```ruby
def output(line)
  @captured << line
  move_to_sticky_area
  print line
end
```

**Analog 2 — atomic publish (Tempfile + same-dir rename, rescue-to-warning degradation).** Copy `write_provenance_sidecar` for the header file (write complete JSONL header to a Tempfile in the target dir, rename into place, so a Phase 14 tailer can never observe a run file without its identity header). Note the degradation convention: a metadata-write failure must never mask the run it surrounds:

`lib/spm_cache/spm/build_pipeline.rb:220-237`:
```ruby
def write_provenance_sidecar(output_path, status:, pins:, config:, destinations:)
  destination = "#{output_path}.provenance.json"
  content = JSON.generate(
    fidelity_status: status,
    pins: pins,
    ...
  )

  tmp = Tempfile.new(["provenance", ".tmp"], File.dirname(destination))
  tmp.write(content)
  tmp.close
  File.rename(tmp.path, destination)
rescue StandardError => e
  tmp&.unlink
  Core::UI.warn "  could not write provenance sidecar for #{File.basename(output_path)}: #{e.message}"
end
```

Binary-safe variant with explicit unlink-on-failure — `lib/spm_cache/spm/resolved_graph.rb:71-84`:
```ruby
def atomic_write(destination, content)
  tmp = Tempfile.new(["resolved_graph", ".tmp"], File.dirname(destination))
  tmp.binmode
  tmp.write(content)
  tmp.close
  File.rename(tmp.path, destination)
rescue StandardError
  tmp&.unlink
  raise
end
```

**Analog 3 — JSON line generation** (never string-interpolate payloads; escaping is where hand-rolled JSONL corrupts tailers): `build_pipeline.rb:222-227` uses `JSON.generate` on a keyword hash; `require "json"` sits at build_pipeline.rb:7.

**Data-object shape** when defining per-run structs — `Struct.new(keyword_init: true)` per `core/diagnostics.rb:22-27`:
```ruby
Check = Struct.new(:name, :run, :fix_hint, keyword_init: true)
Result = Struct.new(:name, :status, :message, :fix_hint, keyword_init: true) do
```

---

### `lib/spm_cache/main.rb` (entrypoint, request-response) — MOD

**Analog: itself.** The entire file is 27 lines; the tee install + exit capture wraps `Command.run(argv)` inside it. The argv pre-scan for `--no-run-log` / `--log-dir` copies the existing bare pre-scan (the tee must install before CLAide parses, exactly as `--version` must intercept before default-subcommand routing):

`lib/spm_cache/main.rb:8-13`:
```ruby
def self.run(argv)
  # Ensure all lib files are loaded
  SPMCache::Main.load_all
  return puts(SPMCache::VERSION) if argv.first == '--version' # before default_subcommand routing

  Command.run(argv)
end
```

Exception shapes that reach this boundary (research-verified, machine-probed): `Core::GeneralError` does NOT include `CLAide::InformativeError` (repo-wide grep = zero lib hits; error.rb:7-14 carries `exit_status` default 1), so real failures re-raise out of `Command.run` as uncaught StandardError → backtrace dump → exit 1. Bare `raise` re-raise in rescue/ensure preserves today's stderr and exit code bit-for-bit (research Pitfall 2).

---

### `lib/spm_cache/core/sh.rb` (service, streaming) — MOD

**Analog: itself.** Two patterns live here:

1. The popen3 branch to be modified — the discarded-capture gap. Reader threads drop every line, the raise carries no detail, and the return is a stub. The fix shape copies the capture3 branch's failure-detail handling into the streaming branch (research "Sh popen3 fix shape"):

`lib/spm_cache/core/sh.rb:20-33` (current):
```ruby
if live_log
  Open3.popen3(env, cmd, **spawn_opts) do |stdin, stdout, stderr, wait_thr|
    stdin.close
    threads = [
      Thread.new { stdout.each_line { |l| live_log.output(l) } },
      Thread.new { stderr.each_line { |l| live_log.output(l) } },
    ]
    threads.each(&:join)
    status = wait_thr.value
    unless status.success?
      raise GeneralError.new("Command failed (exit #{status.exitstatus}): #{cmd}")
    end
  end
  { output: "", status: 0 }
```

2. The detail-retention pattern to copy into it — bounded 60-line tail, both streams, stdout-first rationale. Note the comment convention: a prose paragraph citing the field bug it defends, then the constant:

`lib/spm_cache/core/sh.rb:54-71`:
```ruby
# Tools like xcodebuild write their actual failure reason (compiler
# errors, linker errors) to STDOUT, not STDERR -- a plain `stderr_str`
# in the raised error hid the real cause behind an uninformative
# "Command failed (exit N): <cmd>" for every such failure. Bounded to
# the last FAILURE_DETAIL_LINES of each stream (not the full log,
# which can be thousands of lines for a full Xcode build) since the
# actual error line is almost always near the end, right before the
# tool's own final failure summary.
FAILURE_DETAIL_LINES = 60

def failure_detail(stdout_str, stderr_str)
  [tail_lines(stdout_str), tail_lines(stderr_str)].reject(&:empty?).join("\n")
end

def tail_lines(str)
  str.to_s.lines.last(FAILURE_DETAIL_LINES).join.strip
end
```

Stream attribution (research Pitfall 4): the single `live_log:` object cannot distinguish the two reader threads' streams; plan must add per-stream sinks (`RunLog::StreamSink.new(run_log, "out"|"err")` wrapped around the same `output(line)` contract) or a `live_log_out:`/`live_log_err:` opt pair.

---

### `lib/spm_cache/core/config.rb` (config, CRUD) — MOD

**Analog: itself.** Three verbatim patterns:

1. Flat snake_case `DEFAULT_CONFIG` keys — `runs_keep` / `runs_max_mb` join here (then the yml template documents them):

`lib/spm_cache/core/config.rb:15-22`:
```ruby
DEFAULT_CONFIG = {
  "ignore" => [],
  "cache_only" => [],
  "ignore_local" => false,
  "ignore_build_errors" => false,
  "keep_pkgs_in_project" => false,
  "default_sdk" => "iphonesimulator",
}.freeze
```

2. The outside-sandbox placement rationale to mirror verbatim in a `runs_dir` comment (cite D-02 where this one cites Pitfall 15):

`lib/spm_cache/core/config.rb:95-103`:
```ruby
# Stable, OUTSIDE sandbox_dir by construction (a project_dir-level
# dotfile) so recreate_dirs' rm_rf(sandbox_dir) can never delete the
# path a live flock is held on (Pitfall 15).
def build_lock_path
  File.join(project_dir, ".spm-cache-build.lock")
end
```

3. The `raw[...] || default` reader convention (`config.rb:122-148`), e.g. `default_sdk` (`raw["default_sdk"] || "iphonesimulator"`). Integer coercion for retention values: research V5 row — `Integer()`-coerce with rescue-to-default (yml is user-authored, not adversarial). `Config` is a Singleton with `reset!` (config.rb:29-34, 150-152) — specs call `Core::Config.instance.reset!` (init_spec.rb:148,219 precedent).

---

### `lib/spm_cache/command.rb` (route, request-response) — MOD

**Analog: itself.** `--no-run-log` copies the `--no-merge-slices` boolean-flag declaration exactly (options row + `argv.flag?(name, default)` parse), composed with `.concat(super)`:

`lib/spm_cache/command.rb:14-32`:
```ruby
def self.options
  [
    ["--sdk=SDK", "SDK to build for (default: iphonesimulator)"],
    ["--config=CONFIG", "Build configuration (default: debug)"],
    ["--log-dir=DIR", "Directory for log files"],
    ["--no-merge-slices", "Disable merging framework slices"],
    ["--no-library-evolution", "Disable Swift library evolution flags"],
  ].concat(super)
end

def initialize(argv)
  @sdk = argv.option("sdk")
  @config = argv.option("config")
  @log_dir = argv.option("log-dir")
  @merge_slices = argv.flag?("merge-slices", true)
  @library_evolution = argv.flag?("library-evolution", true)
  super
end
```

The `--log-dir=DIR` stub row (line 17) becomes load-bearing per D-01 (repurpose, do not add a second flag). Companion reader stub in `command/base.rb:6-10,22-24`:
```ruby
module Options
  SDK = "iphonesimulator"
  CONFIG = "debug"
  LOG_DIR = nil
  ...
def log_dir
  @log_dir || Options::LOG_DIR
end
```

---

### `lib/spm_cache/command/init.rb` (command, file-I/O) — MOD

**Analog: itself.** `ensure_gitignore` gains a second entry (`.spm-cache/`) via the same append-once, comment-labeled pattern. Extend independently — do not generalize the method into an entry list unless the planner prefers it; the existing shape is one entry per concern:

`lib/spm_cache/command/init.rb:200-211`:
```ruby
def ensure_gitignore(project_path)
  gitignore = File.join(File.dirname(project_path), '.gitignore')
  entry = 'spm-cache/'
  lines = File.exist?(gitignore) ? File.readlines(gitignore).map(&:chomp) : []
  return if lines.include?(entry)

  File.open(gitignore, 'a') do |f|
    f.puts unless lines.empty?
    f.puts '# spm-cache sandbox'
    f.puts entry
  end
end
```

---

### `lib/spm_cache/command/watch.rb` (controller, event-driven) — MOD

**Analog: itself.** The `installer_factory` lambda is the D-09 seam: wrap the returned installer in a cycle-log decorator (responds to `perform_install`, opens a per-cycle RunLog around it, exit line in its own ensure). `Core::Watcher` stays untouched (it calls `@installer_factory.call(project_path)` then `perform_install`, watcher.rb:90-93):

`lib/spm_cache/command/watch.rb:33-40`:
```ruby
watcher = Core::Watcher.new(
  project_path: project_path,
  installer_factory: ->(path) { Installer::Use.new(project: path) },
  debounce: @debounce
)
```

Note `require 'spm_cache/installer/use'` inside `#run` (watch.rb:31) — the cycle wrapper require must live at the same lazy site, not the file top, to keep CLI startup load order stable.

---

### `lib/spm_cache/spm/build_pipeline.rb` (service, batch) — MOD

**Analog: itself.** `package_start`/`package_end` events bracket `run(...)` — the single choke point shared by `Installer::Build`'s loop and `pkg build`. The insertion convention to follow is the file's own "single consolidated insertion point" discipline and its never-let-metadata-mask-the-operation guard (event emission wrapped so a log failure can never fail a build):

`lib/spm_cache/spm/build_pipeline.rb:50-88` (structure):
```ruby
def run(name:, pkg_dir:, destinations:, out_dir:, library_evolution: true, resolved_pins_file: nil,
        clones_dir: nil, config: nil)
  raise "Target name required" if name.nil? || name.empty?

  FileUtils.mkdir_p(out_dir)
  seed_snapshot, seeded = seed_host_graph(name, pkg_dir, resolved_pins_file)

  success = false
  begin
    ...
    result, built_destinations = perform_build(...)
    success = true
    begin
      report_fidelity(...)
    rescue StandardError => e
      Core::UI.warn "  could not compute/write provenance for #{File.basename(result)}: #{e.message}"
    end
    result
  ensure
    ResolvedGraph.restore!(pkg_dir, seed_snapshot) if seeded && !success
  end
end
```

And the consolidated-point rationale comment (build_pipeline.rb:93-102): "Single consolidated insertion point (RESEARCH.md Pattern 2): ... all happen here, once, right after `perform_build` succeeds -- covering all three artifact-producing paths". Emit `package_start`/`package_end` the same way — once, in `run`, not at each of the three build paths. Pass the run-log sink in as an optional kwarg (nil-safe; `pkg build` and specs call `run` without it — same nil-disables precedent as `resolved_pins_file`, documented at build_pipeline.rb:42-45).

---

### `lib/spm_cache/installer/use.rb` + `installer/build.rb` (orchestrator/service) — MOD

**Analog: themselves.** Phase-marker events emit from the existing branch boundaries — no restructuring. `Use#perform_install` is a single `Core::UI.section('spm-cache')` wrapping fast-path vs full branches (use.rb:21-45); `Build#perform_install` ends in the per-package loop (build.rb:52-54):
```ruby
Core::UI.info "Building #{missed.size} target(s): #{missed.join(', ')}..."
missed.each do |target_name|
  build_single_target(target_name, checkouts, destinations, cache_out, resolved_pins_file, @config.clones_dir)
end
```

Sink threading follows the injected-dependency precedent — `Core::Watcher` takes `out:` at construction and every narrative line routes through it (watcher.rb:21-27, 137-143):
```ruby
# @param out [IO] output sink for log lines (default $stdout)
def initialize(project_path:, installer_factory:, debounce: DEFAULT_DEBOUNCE, out: $stdout)
  ...
  @out = out
...
def info(msg)
  @out.puts msg
end
```

---

### `lib/spm_cache/spm/build.rb` (utility) — MOD (likely)

**Analog: itself.** The only `live_log:` pass-through in the repo (dormant — no caller sets it today). If `Core::Sh` gains per-stream opts (Pitfall 4), this forwarding site updates in the same commit:

`lib/spm_cache/spm/build.rb:80-91`:
```ruby
def xcodebuild(destination, derived_data_path: nil, **opts)
  dd = derived_data_path || File.join(@pkg_dir, "DerivedData")
  cmd = build_command(destination, dd, opts)
  FileUtils.chmod_R("u+w", @pkg_dir)

  begin
    SPMCache::Core::Sh.run(cmd, cwd: @pkg_dir, live_log: opts[:live_log])
  rescue SPMCache::Core::GeneralError => e
    raise unless e.message.match?(LOW_DEPLOYMENT_TARGET_ERROR_PATTERN)

    retry_cmd = "#{cmd} IPHONEOS_DEPLOYMENT_TARGET=#{LOW_DEPLOYMENT_TARGET_RETRY_VALUE}"
    SPMCache::Core::Sh.run(retry_cmd, cwd: @pkg_dir, live_log: opts[:live_log])
  end
  dd
end
```

---

### `spec/run_log_spec.rb` (test) — NEW

**Analog: `spec/core_spec.rb` (unit shape) + `spec/fidelity_bucket_partition_spec.rb:50-67` (hermetic tmpdir + default-deny guard).** Two conventions to copy:

The per-file default-deny Sh guard (spec_helper does NOT install one — research Pitfall 8; each spec arms its own where zero shell-outs are expected):
`spec/fidelity_bucket_partition_spec.rb:53-67`:
```ruby
before do
  FileUtils.mkdir_p(umbrella_dir)
  ...
  # SC4 executable hermeticity guard (default-deny, both Core::Sh entry
  # points): the tier-1 seam must need ZERO shell-outs, so any invocation
  # that survives the object stubs raises instead of running. ...
  allow(SPMCache::Core::Sh).to receive(:run) do |cmd, *_opts|
    raise "unexpected real invocation: Sh.run(#{cmd.inspect})"
  end
  allow(SPMCache::Core::Sh).to receive(:capture_output) do |cmd, *_opts|
    raise "unexpected real invocation: Sh.capture_output(#{cmd.inspect})"
  end
end

after { FileUtils.rm_rf(tmpdir) }
```

---

### `spec/main_run_log_spec.rb` (test) — NEW

**Analog 1: `spec/main_version_spec.rb`** — the class-level `Main.run` harness with a prose "field bug" comment above the describe; whole file is 21 lines:
```ruby
RSpec.describe SPMCache::Main do
  describe '.run' do
    it 'prints the gem version to stdout for --version' do
      expect { described_class.run(['--version']) }.to output("#{SPMCache::VERSION}\n").to_stdout
    end
  end
end
```

**Analog 2: `spec/doctor_spec.rb:185-195`** — the manual `$stdout` swap with begin/ensure restore (the tee-parity test shape), plus `expect_any_instance_of(...).to receive(:exit).with(1).and_return(nil)` for exit-status capture without aborting the spec process:
```ruby
out = StringIO.new
original_stdout = $stdout
$stdout = out
begin
  # exit 1 would abort the spec process; expect it instead (any :fail => 1).
  expect_any_instance_of(SPMCache::Command::Doctor).to receive(:exit).with(1).and_return(nil)
  cmd = SPMCache::Command.parse(['doctor'])
  cmd.run
ensure
  $stdout = original_stdout
end
```

**Analog 3: `spec/watch_signals_spec.rb:69-78`** (per research) — traps never run inside RSpec; test the cycle wrapper at `run_once` level, never with real signal handlers.

---

### `spec/sh_run_log_sink_spec.rb` (test) — NEW

**Analog: `spec/core_spec.rb:6-31`.** Real-subprocess-through-real-Sh is established suite precedent — use `echo` / `sh -c 'echo err >&2'` (not xcodebuild heuristics; a failing `false` with both-stream output is already proven here):
```ruby
it "includes stdout content in the raised error message, not just stderr" do
  expect { described_class.run("echo 'the real error is here' && false") }
    .to raise_error(SPMCache::Core::GeneralError, /the real error is here/)
end

it "still includes stderr content in the raised error message" do
  expect { described_class.run("echo 'stderr detail' 1>&2 && false") }
    .to raise_error(SPMCache::Core::GeneralError, /stderr detail/)
end
```

---

### `spec/init_spec.rb` (test) — EXTEND

**Analog: itself.** Existing assertions the `.spm-cache/` entry joins: `expect(File.read(gitignore_path)).to include('spm-cache/')` (init_spec.rb:60) and the idempotency pair (init_spec.rb:146-168) — `it 'is idempotent — re-running preserves user keys and does not duplicate .gitignore'` asserting `gitignore.scan('spm-cache/').length).to eq(1)`. Add the analogous scan-count assertion for `.spm-cache/`.

---

## Shared Patterns

### `# frozen_string_literal: true` first line
**Source:** every lib file (sh.rb:1, config.rb:1, main.rb:1, ...)
**Apply to:** `core/run_log.rb` and all new spec files.

### Comments cite the planning-doc ID they defend
**Source:** `config.rb:95-97` ("(Pitfall 15)"), `use.rb:56-57` ("D-06 ... Pitfall 15"), `build_pipeline.rb:212` ("mirroring ResolvedGraph.atomic_write"), `main_version_spec.rb:6-9` (field-bug prose)
**Apply to:** every Phase 12 addition — cite D-01…D-09, SC1-SC4, LOGS-01, CP3/CP14 where the code defends them.

### Atomic Tempfile + same-dir rename publish
**Source:** `build_pipeline.rb:220-237` (rescue-to-warn variant), `resolved_graph.rb:71-84` (re-raise variant)
**Apply to:** RunLog header creation. Choose the variant deliberately: header write failure is fatal to logging but must not crash the user's build — degrade like the sidecar, or re-raise and have `Main.run` proceed unlogged (planner's call; state it).

### `output(line)` duck contract over concrete types
**Source:** `live_log.rb:26-29` (implementor), `sh.rb:24-25` (consumer)
**Apply to:** RunLog's Sh-facing surface and StreamSink wrappers — anything passed as `live_log`/`live_log_out`/`live_log_err` must only be required to respond to `output(line)` (lines arrive WITH trailing `"\n"` via `each_line`).

### Nil-option disables (opt-in kwargs)
**Source:** `build_pipeline.rb:42-45` (`resolved_pins_file: nil` "disables seeding entirely -- byte-identical to pre-Phase-7 behavior")
**Apply to:** every new kwarg threading the run-log sink (`build_pipeline.run`, `Sh.run`, `Buildable#xcodebuild`) — nil default keeps every existing caller byte-identical.

### `.concat(super)` options composition + `argv.flag?(name, default)`
**Source:** `command.rb:14-31`, `watch.rb:21-31`
**Apply to:** `--no-run-log` declaration in `Command.options` + `initialize`; keep the CLAide-level declaration even though `Main.run` pre-scans raw argv (research Pitfall 1 — without it CLAide rejects the argv).

### Hermetic specs: default-deny Sh guard per file; real `echo` where a subprocess is wanted
**Source:** `fidelity_bucket_partition_spec.rb:56-67`; `core_spec.rb:6-31`
**Apply to:** all three new spec files. `spec_helper.rb` is 18 lines and installs NO global guard.

### Singleton reset in config specs
**Source:** `init_spec.rb:148,219` (`SPMCache::Core::Config.instance.reset!` between examples)
**Apply to:** retention/config-key specs.

## No Analog Found

Complete files are all mapped; these three NEW sub-mechanisms have no in-repo precedent (planner should use RESEARCH.md Patterns 1-6 for their internal design):

| Mechanism (within mapped files) | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `TeeIO` write-through wrappers (`run_log.rb`) | utility | streaming | No IO-wrapper class exists in the repo; closest gestures are `Watcher`'s `out:` injection (watcher.rb:27) and doctor_spec's StringIO swap — both consumers of IOs, not implementors. Delegation surface (`write`/`puts`/`<<`/`tty?`/`isatty`/`sync`/`flush`) comes from RESEARCH.md Pattern 1. |
| Retention prune loop (`run_log.rb`) | utility | batch (file-I/O) | Nothing in the repo prunes by count+size (`cache clean` deletes by orphans, not budgets). ~20 lines of stdlib per RESEARCH.md Pattern 5; lexicographic-newest-first ordering is bought by the `<UTC ts>-<pid>-<verb>.jsonl` naming, which is also unprecedented. |
| Exit-line rescue/ensure in `Main.run` (`main.rb`) | orchestrator | request-response | `Main.run` is 6 lines today and has no exception handling at all; the three-shape rescue (SystemExit/Interrupt/StandardError) is designed from research-verified CLAide leak shapes, not copied code. |

## Metadata

**Analog search scope:** `lib/spm_cache/{main,command,command/*,core/*,spm/*,installer/*}.rb`, `assets/templates/`, `spec/`
**Files read for excerpts:** main.rb, core/{sh,live_log,log,watcher,config,package_resolved,diagnostics,error}.rb, command{,.rb, base.rb, init.rb, watch.rb}, spm/{build_pipeline (targeted), resolved_graph (71-84), build (70-92)}, installer/{use,build}.rb, spm-cache.yml.template, spec/{spec_helper,core,main_version,doctor (175-205),fidelity_bucket_partition (45-75),init (grep)}.rb
**Pattern extraction date:** 2026-08-31
