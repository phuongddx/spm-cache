# Phase 5: Auto-Sync Watcher - Pattern Map

**Mapped:** 2026-08-24
**Files analyzed:** 8 new/modified files
**Analogs found:** 7 with matches / 8 total

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `lib/spm_cache/core/watcher.rb` | core | event-driven (poll loop) | `lib/spm_cache/core/watcher.rb` (self — verification) | exact |
| `lib/spm_cache/installer.rb` (save-conditioning, if needed) | service | CRUD | `lib/spm_cache/installer.rb` (self — line 468) | exact |
| `spec/watch_spec.rb` (extend: burst-collapse, loop-rescue, subprocess signals) | test | event-driven | `spec/watch_spec.rb` (self — hermetic patterns) | exact |
| `.planning/ROADMAP.md` (criterion 4+5 amendment) | config (planning) | transform | `.planning/ROADMAP.md` (Phases 2–4 amendments) | role-match |
| `.planning/PROJECT.md` (FSEvents→polling correction) | config (planning) | transform | `.planning/PROJECT.md` (self — row 68 status flip) | role-match |
| `.planning/STATE.md` (FSEvents→polling correction) | config (planning) | transform | `.planning/STATE.md` (self — locked decisions) | role-match |
| `README.md` (add `watch` command entry) | documentation | transform | `README.md` (self — Key Features list) | role-match |
| `.planning/phases/05-auto-sync-watcher/SUMMARY.md` (numeric/spec-count corrections) | config (planning) | transform | `.planning/phases/02-diagnostics-command/SUMMARY.md` (Documented deviations section) | role-match |

## Pattern Assignments

### `lib/spm_cache/core/watcher.rb` (core, event-driven — signal-trap wiring if fixed)

**Analog:** `lib/spm_cache/core/watcher.rb` (self, lines 1–115)

This is the file being verified/amended. No creation — only a possible 1–3 line fix (Signal.trap + post-regenerate re-snapshot). The pattern to follow if fixing:

**Run method — where trap and re-snapshot go** (lines 46–74):
```ruby
# lib/spm_cache/core/watcher.rb:46-74 (current, verbatim)
def run
  info "Watching #{watched_files.join(', ')} for changes (Ctrl-C to stop)..."

  # Initial sync so the proxy is current before watching starts.
  @last_signatures = current_signatures
  regenerate

  loop do
    sleep debounce
    current = current_signatures
    next if current == @last_signatures

    @last_signatures = current
    info "\n[watch] SPM graph changed, re-integrating..."
    begin
      regenerate
    rescue StandardError => e
      warn_msg "[#{Time.now}] [watch] integration failed: #{e.message}"
    end
  end
rescue Interrupt
  info "\n[watch] stopped."
rescue StandardError => e
  warn_msg "[watch] fatal: #{e.message}"
  raise
end
```

**Signal-trap fix location** — if the planner opts for the minimal fix, it goes at the top of `run` (before the loop):
```ruby
Signal.trap('TERM') { raise Interrupt }
```
This is ~1 line, mirrors the existing `rescue Interrupt` handler (line 70), and avoids touching the inner loop. No analog needed — it's a Ruby stdlib one-liner.

**Post-regenerate re-snapshot fix** (if self-trigger confirmed) — after `regenerate` at line 62 and line 51:
```ruby
@last_signatures = current_signatures
```
Already exists for in-loop (line 58); missing after the initial `regenerate` (line 51) and could be added after in-loop `regenerate` (line 62) to consume the pbxproj write.

---

### `lib/spm_cache/installer.rb` (service, CRUD — save-conditioning if needed)

**Analog:** `lib/spm_cache/installer.rb:460-470` (the unconditional `project.save`)

**Unconditional save — the self-trigger root cause** (line 468):
```ruby
# lib/spm_cache/installer.rb:468 (verbatim)
      project.save
```

This is inside `integrate_proxy_into_project` (lines 364–470), called by every `perform_install`. The save rewrites `project.pbxproj` unconditionally — even when the fast path short-circuits earlier logic. This is NOT a new edit target unless the planner opts for a save-conditioning fix (dirty check) instead of the watcher re-snapshot fix. The re-snapshot fix in watcher.rb is strongly preferred (smaller blast radius, doesn't touch the installer's integration contract).

**perform_install always-run tail — evidence** (`lib/spm_cache/installer/use.rb:21-33`):
```ruby
# lib/spm_cache/installer/use.rb:21-33 (verbatim)
if fast_path?
  Core::UI.info 'No changes detected. Proxy package up to date.'
else
  recreate_dirs
  ensure_config_file
  sync_lockfile
  prepare_proxy
  yield self if block_given?
end

gen_supporting_files
integrate_proxy_into_project
gen_cachemap_viz
```
Lines 31–33 run OUTSIDE the fast-path `if/else`, proving `integrate_proxy_into_project` (and thus `project.save`) is unconditional.

---

### `spec/watch_spec.rb` (test, event-driven — extend with burst-collapse, loop-rescue, subprocess signals)

**Analog:** `spec/watch_spec.rb` (self, all 137 lines)

**FakeInstaller — hermetic injection pattern** (lines 12–24):
```ruby
# spec/watch_spec.rb:12-24 (verbatim)
class FakeInstaller
  attr_reader :call_count, :last_project

  def initialize(should_fail: false)
    @should_fail = should_fail
    @call_count = 0
  end

  def perform_install
    @call_count += 1
    raise StandardError, 'simulated build failure' if @should_fail
  end
end
```

**Spec boilerplate — tmpdir + fixture setup** (lines 30–44):
```ruby
# spec/watch_spec.rb:30-44 (verbatim)
  let(:tmpdir) { Dir.mktmpdir }
  let(:project_path) { File.join(tmpdir, 'App.xcodeproj') }
  let(:resolved_path) do
    p = File.join(project_path, 'project.xcworkspace/xcshareddata/swiftpm/Package.resolved')
    p
  end

  before do
    FileUtils.mkdir_p(File.dirname(resolved_path))
    File.write(resolved_path, '{"pins":[],"version":1}')
  end

  after { FileUtils.remove_entry(tmpdir) if File.directory?(tmpdir) }

  def make_installer(should_fail: false)
    inst = FakeInstaller.new(should_fail: should_fail)
    [inst, ->(_path) { inst }]
  end
```

**Simulated single poll iteration — loop-avoidance pattern** (lines 74–76, 71–72):
```ruby
# spec/watch_spec.rb:71-76 (verbatim)
    # Bump the mtime+content so the signature differs.
    File.write(resolved_path, '{"pins":[{"identity":"NewDep"}],"version":1}')
    sleep 1 # ensure mtime advances by >= 1s on coarse filesystems

    # Simulate one poll iteration manually (avoids a blocking loop in tests).
    current = watcher.send(:current_signatures)
    expect(current).not_to eq(watcher.instance_variable_get(:@last_signatures))
```
Key insight: vary BOTH content (size) and mtime (sleep 1) — the signature is `[path, mtime.to_i, size]`. Size alone is sufficient; mtime is needed only when content-length stays the same.

**Continue-on-error contract-around-loop** (lines 79–96):
```ruby
# spec/watch_spec.rb:79-96 (verbatim)
  it 'continue-on-error: logs a transient failure and keeps the loop contract' do
    _, factory = make_installer(should_fail: true)
    out = StringIO.new
    watcher = described_class.new(project_path: project_path, installer_factory: factory,
                                  debounce: 0, out: out)

    # run_once raises directly (no loop to rescue); verify the error surfaces
    # so the loop's rescue path is the thing that swallows it.
    expect { watcher.run_once }.to raise_error(StandardError, /simulated build failure/)

    # The loop (not run_once) is responsible for continue-on-error. Verify a
    # failing installer doesn't corrupt state — a fresh watcher with a working
    # installer recovers.
    inst2, factory2 = make_installer(should_fail: false)
    watcher2 = described_class.new(project_path: project_path, installer_factory: factory2, out: StringIO.new)
    expect(watcher2.run_once).to be true
    expect(inst2.call_count).to eq(1)
  end
```
Note: this proves the contract AROUND the loop (run_once raises, fresh watcher recovers), not the loop's actual rescue path. A new loop-rescue spec must use the simulated-iteration pattern to exercise the `begin/rescue StandardError` inside the loop body (watcher.rb:62–66).

**Command spec — CLaide parse + ivar inspection** (lines 118–127):
```ruby
# spec/watch_spec.rb:118-127 (verbatim)
  it 'parses --once and --debounce flags' do
    cmd = described_class.parse(['--once', '--debounce=5'])
    expect(cmd.instance_variable_get(:@once)).to be true
    expect(cmd.instance_variable_get(:@debounce)).to eq(5)
  end

  it 'defaults debounce to the Watcher default' do
    cmd = described_class.parse([])
    expect(cmd.instance_variable_get(:@debounce)).to eq(SPMCache::Core::Watcher::DEFAULT_DEBOUNCE)
  end
```

**Command spec — real run in tmpdir** (lines 129–136):
```ruby
# spec/watch_spec.rb:129-136 (verbatim)
  it 'errors when no .xcodeproj is found' do
    Dir.mktmpdir do |empty_dir|
      Dir.chdir(empty_dir) do
        cmd = described_class.parse([])
        expect { cmd.run }.to raise_error(SPMCache::Core::GeneralError, /No \.xcodeproj found/)
      end
    end
  end
```

**Subprocess signal test pattern** (no existing analog in watch_spec — from RESEARCH Pitfall 5):

No existing `Process.kill`/`Process.wait`/`spawn` pattern exists in `spec/watch_spec.rb`. The closest analogs in the repo are:
- `spec/checkout_enrichment_sequencing_spec.rb:46-54` and `spec/gen_proxy_root_build_regression_spec.rb:66-74`: use `system("git", ...)` for repo setup (not subprocess-signal testing)
- `spec/gen_proxy_*.rb` files: use `system(cmd, out: File::NULL, err: File::NULL)` for binary invocation (no signal testing)

The subprocess signal pattern should follow RESEARCH Pitfall 5's recipe: spawn a child Ruby process wiring a minimal watcher script with `FakeInstaller`, send signal via `Process.kill`, assert `Process.wait2` exit status and captured output. Wrap in `Timeout.timeout(10)`.

**Doctor hermetic collector-injection pattern** (analog for spec structure, `spec/doctor_spec.rb:54-110`):
```ruby
# spec/doctor_spec.rb:54-65 (verbatim)
RSpec.describe SPMCache::Core::Diagnostics, 'hermetic per-check paths (injected shell collectors)' do
  let(:cache_dir) { SPMCache::Core::Config::CACHE_DIR }
  let(:companion_bin) do
    File.expand_path('tools/spm-cache-proxy/.build/release/spm-cache-proxy', SPMCache::ROOT)
  end

  before do
    # Default: every shell probe fails, as on a host with no toolchain.
    allow(SPMCache::Core::Sh).to receive(:capture_output)
      .and_raise(SPMCache::Core::GeneralError.new('Command failed (exit 1): not installed'))
  end

  def result_for(name, config: nil)
    SPMCache::Core::Diagnostics.run_all(config: config).find { |r| r.name == name }
  end
```
Relevance: the `result_for` helper + `before` block that defaults to failure (then per-example overrides) is the project's hermetic spec pattern. Watch specs use the analogous `make_installer` + `StringIO.new` out sink.

---

### `.planning/ROADMAP.md` (config/planning, transform — criterion 4+5 amendment)

**Analog:** `.planning/ROADMAP.md` Phase 2–4 amendment patterns

**Phase 2 criterion 1 amendment** (ROADMAP.md:38):
```
…color-coded green/yellow/red report with per-check fix hints — amended 2026-08-24: plain ✓/!/✗ markers replace ANSI color (user-accepted, terminal-agnostic/pipe-safe; 02-CONTEXT); cache-dir health is count-only (no orphan detection) and remote-backend is config-presence (no network probe), both accepted as shipped (02-01-SUMMARY Documented deviations c/d)
```

**Phase 3 criterion 1 amendment** (ROADMAP.md:48):
```
…so the first `use` hits the fast path — amended 2026-08-24: the `--config`-class flag wording is realized as `--default-config` (CLaide base `Command` already defines `--config` for SDK config; 03-CONTEXT); "first `use` hits the fast path" amended to "so subsequent `use` runs can take the fast path" (proxy must be materialized first by design; `fast_path?` contract at use.rb:45-51); the seeded-lock format defect found in verification was FIXED to the canonical shape during this phase (03-01 Task 1)
```

**Phase 4 criterion 1 amendment** (ROADMAP.md:69):
```
…accepts `command`, `backend`, `backend-url`, `config` inputs — amended 2026-08-24: shipped as the accepted superset adding `branch` and `creds` (mirrors `init`'s remote flags; 04-CONTEXT); input surface and metadata machine-enforced by spec/action_spec.rb (04-01 Task 1)
```

**Amendment format pattern** (consistent across Phases 2–4):
1. Append ` — amended 2026-08-24:` after the criterion text
2. Describe what changed, what it became instead
3. Cite source: `(XX-CONTEXT)`, `(XX-01-SUMMARY Documented deviation Y)`
4. If a fix was delivered (not just accepted-as-shipped), note `(03-01 Task 1)`

**Targets to amend:**
- Criterion 4 (ROADMAP.md:87): `…SIGINT/SIGTERM flush + exit 0` → amend with signal reality
- Criterion 5 (ROADMAP.md:88): `FSEvents binds via Ruby Fiddle (stdlib)` → amend with mtime+size polling

---

### `.planning/PROJECT.md` (config/planning, transform — FSEvents→polling correction)

**Analog:** `.planning/PROJECT.md` (self — Key Decisions table row 68)

**Current row 68** (PROJECT.md:68, verbatim):
```
| `watch` uses native FSEvents via Fiddle, not `listen` gem | macOS-only tool; avoids new dependency; ~80-line binding | — Pending |
```

**Current row 60** (PROJECT.md:60, verbatim):
```
- **Compatibility**: no new runtime gem dependencies without justification (watch uses native FSEvents to avoid `listen`)
```

**Correction pattern:** Replace mechanism text, flip status `— Pending` → `✓ Shipped Phase 5`. The `✓ Shipped Phase N` pattern is used by row 66 (`companion CLI` → `✓ Phase 2`), row 67 (`init` → `✓ Phase 3`), row 68 `Action` → `✓ Shipped in-repo Phase 4`.

---

### `.planning/STATE.md` (config/planning, transform — FSEvents→polling correction)

**Analog:** `.planning/STATE.md` (self — Locked design decisions block)

**Current line 51** (STATE.md:51, verbatim):
```
- watch: native FSEvents via Fiddle (no `listen` gem); watches Package.resolved + project.pbxproj only; continue-on-error loop
```

**Correction:** Replace `native FSEvents via Fiddle` → `stdlib mtime+size polling`. Keep rest of line (no `listen` gem, watched files, continue-on-error — all accurate).

---

### `README.md` (documentation, transform — add `watch` command entry)

**Analog:** `README.md:42` (self — existing `--watch` entry in Key Features list)

**Current line 42** (README.md:42, verbatim):
```
- **Watch Mode** — `--watch` monitors `Package.resolved` and re-integrates on change.
```

This describes the legacy `use --watch` (Package.resolved only). The new `spm-cache watch` command (Phase 5 deliverable) needs its own entry or an update to this line. The Key Features list uses the `- **Bold Title** — description.` pattern throughout.

---

### `.planning/phases/05-auto-sync-watcher/SUMMARY.md` (config/planning, transform — numeric corrections)

**Analog:** `.planning/phases/02-diagnostics-command/SUMMARY.md` (Documented deviations section)

**Phase 2 documented-deviations format** (02-SUMMARY, lines 30-50):
```markdown
## Documented deviations (user-accepted / accepted-as-shipped)

All dated 2026-08-24. Sources: 02-CONTEXT.md (user decisions), RESEARCH.md (Pattern 2 / Pitfall 7), 02-01-PLAN.md (open-question resolutions 1-4).

- **(a) Plain markers instead of color** — REL-02 says "color-coded green/yellow/red report"; the shipped report uses plain ✓/!/✗ markers with no ANSI color. User-accepted (02-CONTEXT, Output contracts): terminal-agnostic, pipe-safe. Not a gap.
```

**Corrections needed in 05-SUMMARY.md:**
- Line 8: `58 lines` → `56 lines`
- Line 9: `12 specs` → `9 specs` (12 reported includes 3 spec_helper.rb globals)
- Line 12: `refactors that into a dedicated Core::Watcher class` → `adds a dedicated Core::Watcher alongside the retained use --watch` (legacy loop still exists at command/use.rb:50-80)
- Add Documented deviations section for mechanism deviation, signal behavior, mid-watch deletion semantics

---

## Shared Patterns

### Hermetic test seam (injectable factory + IO sink)
**Source:** `lib/spm_cache/core/watcher.rb:20-23` (constructor), `spec/watch_spec.rb:12-24` (FakeInstaller), `spec/watch_spec.rb:42-44` (factory lambda)
**Apply to:** All new watch_spec examples
```ruby
# Production wiring (lib/spm_cache/command/watch.rb:35-39)
watcher = Core::Watcher.new(
  project_path: project_path,
  installer_factory: ->(path) { Installer::Use.new(project: path) },
  debounce: @debounce
)

# Spec wiring (spec/watch_spec.rb:41-44)
inst, factory = make_installer
watcher = described_class.new(project_path: project_path, installer_factory: factory, out: StringIO.new)
```

### Simulated single poll iteration (never run the loop in specs)
**Source:** `spec/watch_spec.rb:74-76`
**Apply to:** Burst-collapse spec, loop-rescue spec
```ruby
# Simulate one poll iteration manually (avoids a blocking loop in tests).
current = watcher.send(:current_signatures)
expect(current).not_to eq(watcher.instance_variable_get(:@last_signatures))
```
For burst-collapse: write file twice (different sizes) within one "window" (no sleep between writes), then run ONE simulated poll, assert `call_count == 1`.

### Dated inline ROADMAP amendment
**Source:** `.planning/ROADMAP.md:38,48,54,69-71` (Phases 2–4)
**Apply to:** ROADMAP.md criterion 4 (line 87) and criterion 5 (line 88)

Format: ` — amended 2026-08-24: [what changed] ([source]; [SUMMARY reference])`

### Documented deviations section (SUMMARY.md)
**Source:** `.planning/phases/02-diagnostics-command/SUMMARY.md:30-50`
**Apply to:** 05-SUMMARY.md — add section for mechanism deviation (FSEvents→polling), signal behavior (SIGINT vs SIGTERM), mid-watch deletion semantics, legacy loop duplication

### File header convention
**Source:** Every `.rb` file in `lib/`
**Apply to:** Any new Ruby files
```ruby
# frozen_string_literal: true
```

## No Analog Found

Files with no close match in the codebase (planner should use RESEARCH.md patterns instead):

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| Subprocess signal spec (new test) | test | event-driven | No `Process.kill`/`Process.wait` signal-testing pattern exists in the repo; RESEARCH Pitfall 5 provides the recipe (child process + timeout + status assertion) |

## Metadata

**Analog search scope:** `lib/spm_cache/core/`, `lib/spm_cache/command/`, `lib/spm_cache/installer/`, `spec/`, `.planning/ROADMAP.md`, `.planning/PROJECT.md`, `.planning/STATE.md`, `README.md`, `.planning/phases/*/SUMMARY.md`
**Files scanned:** 12
**Pattern extraction date:** 2026-08-24
