# Phase 2: Diagnostics Command - Research

**Researched:** 2026-08-24
**Domain:** Verification-scoped closure of the shipped `spm-cache doctor` feature (Ruby CLI diagnostics registry, CLAide command, RSpec coverage)
**Confidence:** HIGH (every claim below was verified this session against live source, a live `doctor` run, a live spec run, or `git show 5ea68a5`)

## Summary

`spm-cache doctor` is already implemented at commit `5ea68a5` and works live: 7/7 checks `ok`, exit 0, and `doctor --json` emits the exact documented payload shape (`{checks:[…], summary:{ok,warnings,failures}}`). The architecture is exactly what REL-02 asked for structurally: a data-driven registry (`Core::Diagnostics`) of named check blocks that a thin CLAide command (`Command::Doctor`) iterates without knowing anything about individual checks. The registry mechanics — rescue-to-`:fail` isolation, order preservation, `register` as the only extension point — are all verified in source and exercised by spec.

This phase is **verification-scoped**: the plan must prove the four ROADMAP success criteria with concrete evidence (spec runs + CLI invocations), record the two user-accepted limitations (no ANSI color; no version-drift *comparison*), close doc drift, and fix only small gaps. Research confirms most criteria are provable as-is, but found **one genuine runtime gap and several drift items** the plan must route. The most important finding: the `companion_binary` check's "reports the companion `--version` string when present" branch is **dead code at runtime** — the shipped proxy binary has no `--version` support at all (`Error: Unknown option '--version'`, exit 64), so the version suffix never renders on any machine, and the "drift made VISIBLE" behavior accepted in CONTEXT.md never manifests. Second: ROADMAP criterion 4's "unit-testable via injected shell-output collectors" is not what shipped — the specs run checks **live** against the host (tolerant assertions + one `exit` stub), and no injection seam exists anywhere in `Core::Sh` or `Core::Diagnostics`.

**Primary recommendation:** Structure the plan as four criterion-proof tasks (evidence-first), plus one decision-routed task for the `companion_binary --version` dead branch (small fix vs. third accepted limitation), one for the injected-collector criterion deviation (accept-as-deviation record vs. small spec/seam addition), and a doc-drift sweep (SUMMARY line counts / "7 specs" provenance, `doctor --help` color wording, `docs/project-roadmap.md` stale checklist item).

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions (accepted as shipped — verify, do not re-implement)

**Check outcome & exit semantics:**
- Exit 1 only when any check returns `:fail`; warn-only runs exit 0 (CI gates on hard failure)
- A raising check is captured as `:fail` with the error message; the report continues (never aborts)
- Missing companion binary is `:warn` (build falls back to source; binary-gated specs skip), not `:fail`

**Registry & extensibility:**
- Checks added/removed via the Ruby-level `Core::Diagnostics.register` API — the registry is the single source of truth; the `doctor` command is never edited to add checks
- Report order = registration order (preserved)
- Checks receive `Core::Config` (nil-safe outside a project); no global singleton access inside checks

**Output contracts:**
- Text report: `✓/!/✗ name: message`, `↳ fix_hint` on non-ok, trailing `Summary: N ok, N warnings, N failures`
- `--json`: `{checks:[{name,status,message,fix_hint}], summary:{ok,warnings,failures}}`, pretty-printed
- ACCEPTED LIMITATION: REL-02 says "color-coded green/yellow/red"; the shipped report uses plain text markers (✓/!/✗) with NO ANSI color — accepted by user 2026-08-24 as terminal-agnostic, pipe-safe. Record as documented deviation, not a gap.

**Version-drift scope:**
- `companion_binary` = presence check (`File.executable?`) + reports the companion `--version` string when present — drift made VISIBLE, not compared. ACCEPTED LIMITATION (user, 2026-08-24): no explicit gem-VERSION vs companion-version comparison.
- Diagnostics are strictly read-only; fix hints only, no `--fix` flag, no auto-remediation

### Claude's Discretion
Plan task granularity for verification-scoped work; how to organize acceptance-criteria proofs (spec runs vs CLI invocations); minor doc-phrasing fixes.

### Deferred Ideas (OUT OF SCOPE)
- yml-driven check enable/disable list (`doctor.checks:` in spm-cache.yml) — rejected 2026-08-24 in favor of the Ruby registry API
- `--fix` auto-remediation flag — rejected 2026-08-24 (read-only diagnostics)
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| REL-02 | `spm-cache doctor` runs a data-driven registry of diagnostic checks (Xcode version, Swift version, toolchain path, cache-dir health/orphans, library-evolution compatibility, remote-backend connectivity, companion-binary presence) and prints a color-coded green/yellow/red report with per-check fix hints | Registry + all 7 checks verified in `lib/spm_cache/core/diagnostics.rb:66-153`; live run 7/7 ok with fix-hint plumbing confirmed. Three wording-level deviations to route: (1) color → accepted limitation; (2) "cache-dir health/orphans" — shipped check reports dir/file counts, no orphan *detection*; (3) "remote-backend connectivity" — shipped check reports remote *config presence*, no network probe. See Common Pitfalls / Open Questions. |
| REL-03 | `spm-cache doctor --json` emits the same diagnostics as a machine-readable JSON document for CI consumption | Verified live: `--json` prints `JSON.pretty_generate` payload with `checks[]` + `summary{ok,warnings,failures}` (`doctor.rb:67-79`); parses with `JSON.parse`; spec `doctor_spec.rb:49-68` asserts shape; CI-ready exit-1-on-fail verified at `doctor.rb:42`. |
</phase_requirements>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| CLI parsing (`doctor`, `--json`) | Presentation — `Command::Doctor < Command` (CLAide) | Entry — `bin/spm-cache` → `Main.run` | CLAide owns argv/flag parsing and help; Doctor only reads `argv.flag?('json')` and formats output |
| Check orchestration & isolation | Domain — `Core::Diagnostics` | — | Registry + `run_check` rescue-to-`:fail` is pure domain logic, UI-agnostic |
| Individual check execution | Domain — check blocks | Infrastructure — `Core::Sh` (shell-outs), `Core::Config` (state), stdlib `File`/`Dir` | Checks are read-only probes over infra; no check knows about the command layer |
| Config/project context | Infrastructure — `Core::Config` (Singleton) | — | Doctor passes `Config.instance` (load-rescued) into `run_all`; checks are nil-safe |
| Report/JSON formatting & exit code | Presentation — `Command::Doctor#print_report` / `#print_json` | — | Verdict-to-marker mapping and CI exit semantics live with the CLI, not the registry |
| Load wiring | Entry — `SPMCache::Main.load_all` (requires all `lib/**/*.rb` sorted) | — | Deterministic file load order → deterministic registration order → deterministic report order |

## Standard Stack

No new packages — this phase is verification-scoped against shipped code.

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| claide | pinned in Gemfile.lock (already a gem dependency) | Command tree, `argv.flag?`, help | CocoaPods-family CLI standard; already used by every subcommand |
| json (stdlib) | Ruby stdlib | `JSON.pretty_generate` for `--json` | Zero-dependency; already required at `doctor.rb:3` and `diagnostics.rb:3` |
| open3 (stdlib) | Ruby stdlib | `Core::Sh` shell-outs (`capture3`) | Already the project-wide shell seam; every check shells out through it |
| rspec | 3.13.2 [VERIFIED: Gemfile.lock this session] | Test framework | Project standard; 29 spec files already in `spec/` |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| optparse (stdlib) | Ruby stdlib | Nothing — `doctor.rb:4` requires it but CLAide does all parsing | Never (vestigial require; explicitly NOT a gap — surgical-changes principle says leave it) |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Plain ✓/!/✗ markers | ANSI color (hand-rolled or `rainbow` gem) | REJECTED by user 2026-08-24 (terminal-agnostic, pipe-safe). Do not introduce. |
| Ruby `Diagnostics.register` API | yml `doctor.checks:` enable/disable | REJECTED 2026-08-24 (deferred). Do not build config parsing for checks. |

**Installation:** none — no installs this phase.

## Package Legitimacy Audit

**Not triggered — this phase installs no external packages** (verification-scoped; all tooling already in the bundle). No `[ASSUMED]` package names are recommended anywhere in this research.

## Architecture Patterns

### System Architecture Diagram

```mermaid
flowchart TD
    A["bin/spm-cache ARGV"] --> B["SPMCache::Main.run"]
    B --> C["Main.load_all — require lib/**/*.rb sorted"]
    C --> D["Command.run(argv) — CLAide resolves Doctor"]
    D --> E["Command::Doctor#initialize<br/>@json = argv.flag?('json')"]
    E --> F["Core::Config.instance.load<br/>(rescued — nil-safe outside a project)"]
    F --> G["Core::Diagnostics.run_all(config:)"]
    G --> H{"For each registered Check<br/>(registration order preserved)"}
    H --> I["check.run.call(config:)"]
    I -->|returns [:ok/:warn/:fail, msg]| J["Result struct"]
    I -->|raises StandardError| K["Result :fail<br/>'Check raised an error: …'<br/>(report never aborts)"]
    J --> L{--json?}
    K --> L
    L -->|yes| M["print_json<br/>JSON.pretty_generate<br/>checks[] + summary{}"]
    L -->|no| N["print_report<br/>✓/!/✗ + ↳ fix_hint + Summary line"]
    M --> O{"any result.fail?"}
    N --> O
    O -->|yes| P["exit 1 (CI gate)"]
    O -->|no| Q["exit 0"]

    subgraph "Check internals (per check)"
      I -.-> R["Core::Sh.capture_output<br/>xcodebuild / swift / xcrun / proxy --version"]
      I -.-> S["File / Dir stdlib<br/>cache dir, proxy binary"]
      I -.-> T["Config.raw['remote']<br/>(config presence only)"]
    end
```

Trace of the primary use case: `spm-cache doctor` → CLAide dispatch → registry iteration with per-check isolation → text or JSON rendering → exit code. A broken check detours through the rescue path but never aborts the loop.

### Recommended Project Structure (as shipped — nothing to add)
```
lib/spm_cache/
├── core/
│   ├── diagnostics.rb   # Registry + Check/Result structs + 7 built-in checks (156 lines)
│   ├── sh.rb            # Open3 shell seam; capture_output strips stdout; raises GeneralError on nonzero
│   ├── config.rb        # Singleton; CACHE_DIR = ~/.spm-cache; raw['remote'] read by remote check
│   └── error.rb         # Core::GeneralError < BaseError (rescued by xcode_version check)
└── command/
    └── doctor.rb        # CLAide subcommand; --json; exit 1 on any :fail (82 lines)
spec/
└── doctor_spec.rb       # 4 doctor examples (+3 inherited from spec_helper inline describes = 7 total)
```

### Pattern 1: Registry-of-blocks data-driven checks
**What:** Each check is `Check = Struct.new(:name, :run, :fix_hint, keyword_init: true)` appended to an ordered array; the command layer never enumerates checks by name.
**When to use:** Proof of ROADMAP criterion 3 ("addable/removable without editing the command").
**Example:**
```ruby
# Source: lib/spm_cache/core/diagnostics.rb:28-57 (verbatim)
      class << self
        # Ordered registry of checks. Order is preserved for report output.
        def registry
          @registry ||= []
        end

        def register(name, fix_hint:, &block)
          registry << Check.new(name: name, run: block, fix_hint: fix_hint)
        end

        # Run all registered checks and return an array of Result structs.
        # A check that raises is captured as a :fail with the error message so
        # one broken check never aborts the whole report.
        def run_all(config: nil)
          registry.map { |check| run_check(check, config: config) }
        end

        private

        def run_check(check, config:)
          status, message = check.run.call(config: config)
          Result.new(name: check.name, status: status, message: message, fix_hint: check.fix_hint)
        rescue StandardError => e
          Result.new(
            name: check.name,
            status: :fail,
            message: "Check raised an error: #{e.message}",
            fix_hint: check.fix_hint
          )
        end
      end
```

### Pattern 2: The 7 built-in checks — mechanics and edge cases (verification knowledge)

All quotes verbatim from `lib/spm_cache/core/diagnostics.rb` this session. The seven `register` call sites are lines **66, 74, 87, 100, 117, 125, 141**; names in registration (report) order:
`'xcode_version', 'swift_version', 'toolchain_path', 'cache_dir_health', 'library_evolution_compatibility', 'remote_backend_connectivity', 'companion_binary'` [VERIFIED: diagnostics.rb:66,74,87,100,117,125,141]

| Check | Mechanics [VERIFIED: line range] | Statuses reachable | Edge cases a verifier must know |
|---|---|---|---|
| `xcode_version` | `Sh.capture_output('xcodebuild -version')`, first line stripped; `rescue Core::GeneralError` → `:fail` | ok / fail | **Environment-dependent**: no Xcode → GeneralError → `:fail` → `exit 1`. Fix hint says "Xcode 16+" but **no version comparison exists** — any Xcode passes (Xcode 26.3 ok locally; CI pins Xcode 16). |
| `swift_version` | `Sh.capture_output('swift --version')` rescued to `''` → `:fail 'swift not found on PATH'` | ok / fail | PATH-dependent; rescue is broad `StandardError`. |
| `toolchain_path` | `Sh.capture_output('xcrun --find swift 2>/dev/null')` — note the embedded shell redirect works because `Sh` passes **string** commands through the shell [VERIFIED: sh.rb:35 `Open3.capture3(env, cmd, **spawn_opts)`] | ok / fail | CLT-only installs (no full Xcode) resolve differently; empty output → fail. |
| `cache_dir_health` | `Dir.children(CACHE_DIR)` + recursive `Dir.glob` file count; **both branches return `:ok`** (exists / "does not exist yet"); `:warn` only if inspection raises | ok / warn | `CACHE_DIR = File.expand_path("~/.spm-cache")` [VERIFIED: config.rb:25]. **No orphan detection** despite REL-02 wording "health/orphans" and a fix_hint mentioning "orphaned binaries" — it only counts configs/files. |
| `library_evolution_compatibility` | Unconditional `[:ok, 'Library evolution support is built-in (disable with --no-library-evolution)']` — self-described placeholder [VERIFIED: diagnostics.rb:119-122 "This check is a placeholder that confirms the capability is wired."] | ok only | Cannot fail; fine for registry-shape proof, but do not expect warn/fail coverage. |
| `remote_backend_connectivity` | Falls back `config || Config.instance`, rescues `load`, inspects `cfg.raw['remote']`: nil/empty → ok "No remote backend configured (local-only)"; else ok "Remote backend configured — run \`spm-cache remote pull\` to verify connectivity" | ok only | **Config-presence check, not a connectivity probe** — no network I/O ever runs. With a remote configured the message itself defers connectivity to `remote pull`. |
| `companion_binary` | `File.executable?(File.expand_path('tools/spm-cache-proxy/.build/release/spm-cache-proxy', ROOT))` → ok, else `:warn '…proxy generation specs will skip'`; when present, tries `Sh.capture_output("#{bin} --version 2>/dev/null")` to append `" (#{out})"` | ok / warn | **The `--version` branch is dead code**: the shipped proxy has NO version flag — live run this session: `Error: Unknown option '--version'`, exit 64 → `Sh` raises → rescued to `''` → suffix omitted. See Pitfall 1. Binary path derives from `ROOT` [VERIFIED: spm_cache.rb:6 `ROOT = Pathname.new(File.expand_path("..", __dir__))`] — repo-relative, not install-relative: an installed gem's doctor looks for the binary under the *gem's* ROOT, so `:warn` is the expected verdict for Homebrew/gem installs unless the binary ships inside the package. |

### Pattern 3: Output contracts (verbatim, for byte-level verification)
Text report formatting [VERIFIED: doctor.rb:56-65]:
```ruby
      def format_line(result)
        marker = case result.status
                 when :ok then '✓'
                 when :warn then '!'
                 when :fail then '✗'
                 end
        line = "#{marker} #{result.name}: #{result.message}"
        line += "\n    ↳ #{result.fix_hint}" unless result.ok? || result.fix_hint.to_s.empty?
        line
      end
```
Summary line [VERIFIED: doctor.rb:53]: `puts "Summary: #{ok} ok, #{warn} warning#{'s' if warn != 1}, #{fail} failure#{'s' if fail != 1}"` (note singular/plural handling).
JSON payload [VERIFIED: doctor.rb:68-77]: `{ checks: [{name:, status: (String, e.g. "ok"), message:, fix_hint:}], summary: {ok:, warnings:, failures:} }` via `JSON.pretty_generate` — statuses are **strings** in JSON, symbols in `Result`.
Exit semantics [VERIFIED: doctor.rb:42]: `exit 1 if results.any?(&:fail?)` — warn-only runs exit 0.

### Anti-Patterns to Avoid (for any gap-fix work)
- **Do not** add ANSI color, a `--fix` flag, or yml check enable/disable — all explicitly rejected/deferred in CONTEXT.md.
- **Do not** special-case environments inside checks; environment variance is handled by status verdicts, not conditionals.
- **Do not** let a fix introduce a second shell seam; all shell-outs go through `Core::Sh` (established pattern).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON emission | Custom serialization | `JSON.pretty_generate` (stdlib, already used) | Done; keep parity between text and JSON data sources (both render the same `Result` array) |
| Shell execution with error capture | `Open3` calls inside checks | `Core::Sh.capture_output` | Existing seam; concentrates failure-detail logic and is the only place to stub if injection is ever added |
| CLI flag parsing | `OptionParser` inside Doctor | CLAide `self.options` + `argv.flag?` | Established project pattern (Doctor already does this correctly) |

**Key insight:** Every "don't hand-roll" here is already satisfied by the shipped code — the verification plan should assert this stays true after any gap-fix, not build anything.

## Common Pitfalls

### Pitfall 1: `companion_binary --version` dead branch (GAP, decision needed)
**What goes wrong:** The check tries `"#{bin} --version 2>/dev/null"` to surface the companion version, but the shipped proxy supports only `gen-umbrella`, `gen-proxy`, `resolve` + `--help` [VERIFIED: live `--help` run this session; `Error: Unknown option '--version'`, exit 64]. `Sh` raises `GeneralError` on non-zero exit [VERIFIED: sh.rb:36-39], the check rescues to `''`, and the `" (#{out})"` suffix is silently omitted. **On every machine, forever, the version never displays** — so CONTEXT.md's accepted "reports the companion `--version` string when present — drift made VISIBLE" describes behavior that cannot manifest.
**Why it happens:** The check was written against intended proxy behavior that never shipped.
**How to avoid (plan routing):** Either (a) small fix — drop the dead version probe and re-record the limitation as "presence-only", or (b) small fix — add a `version` subcommand to the Swift proxy (touches `tools/spm-cache-proxy`, has a `swift test` surface, larger blast radius), or (c) record as a third accepted limitation with the dead branch removed or kept. This is the one finding that is a *functional* gap rather than wording drift; it needs an explicit decision.
**Warning signs:** Live report shows `companion_binary: Companion binary present at …` with no parenthesized version.

### Pitfall 2: "Injected shell-output collectors" ≠ shipped spec approach (DRIFT vs ROADMAP criterion 4)
**What goes wrong:** ROADMAP criterion 4 and the design spec (`docs/superpowers/specs/2026-08-10-v0.3.0-watch-init-doctor-design.md:172` — "inject the shell-output collector, assert on the verdict… covers each check's ok/warn/fail paths via injected fixtures") describe an injection seam. The shipped `spec/doctor_spec.rb` has **no stubbing of `Sh` at all**: `run_all(config: nil)` executes real `xcodebuild`/`swift`/`xcrun`/file probes against the host; assertions are tolerant (`status ∈ {ok,warn,fail}`, message is a `String`); the only stub in the file is `allow_any_instance_of(SPMCache::Command::Doctor).to receive(:exit)` [VERIFIED: doctor_spec.rb:58]. There is no ok/warn/fail path coverage per check, and no injection point exists in `Sh` (module class-methods, no DI) or `Diagnostics`.
**Why it happens:** Specs were written to pass on any macOS host rather than to the design's unit-test ideal.
**How to avoid:** The plan must route criterion 4 explicitly: either accept-as-deviation ("live-run tolerant specs; hermetic via CI's Xcode 16 runner") or a small gap-fix (e.g., allow `Sh.capture_output` stubbing / add an injectable collector defaulting to `Sh`). **Do not silently claim criterion 4 is met as worded.**
**Warning signs:** Any plan task asserting criterion 4 with only `bundle exec rspec spec/doctor_spec.rb` as evidence.

### Pitfall 3: "7 specs" provenance — only 4 are doctor's
**What goes wrong:** `bundle exec rspec spec/doctor_spec.rb` reports **7 examples** because `spec/spec_helper.rb` (required at the top) contains 3 inline `RSpec.describe SPMCache` examples (version, ROOT, ROOT-resolves) [VERIFIED: spec_helper.rb:5-17 + live run "7 examples, 0 failures"]. `doctor_spec.rb` itself contributes **4**: `registers built-in checks`, `every check returns a Result with a valid status`, `captures a check that raises as a :fail`, `emits valid JSON with checks and summary` [VERIFIED: doctor_spec.rb:12,21,31,50].
**How to avoid:** A criterion-4 proof that says "7 doctor specs pass" is double-counting. Say "4 doctor examples (+3 spec_helper examples), 7 examples total, 0 failures".
**Warning signs:** Any doc claiming per-check spec coverage from the current file.

### Pitfall 4: Environment-dependent verdicts (CI vs local)
**What goes wrong:** Live `doctor` output is a function of the host: Xcode presence/version (CI pins Xcode 16 via `maxim-lobanov/setup-xcode` [VERIFIED: ci.yml:26-29,49-52]; local has Xcode 26.3), PATH, `~/.spm-cache` contents (local: 3 configs, ~12,403 files), repo-relative companion binary presence (local: built; fresh checkout: `:warn`). Verdicts can differ across environments without any code difference.
**How to avoid:** Verification evidence should state the environment alongside the verdict; specs deliberately assert shape, not specific verdicts — that's the shipped mitigation, and it's why the suite passes on both Xcode 16 CI and Xcode 26.3 local.
**Warning signs:** Hardcoding expected statuses like "7 ok" in a proof that must run elsewhere.

### Pitfall 5: `exit` in specs aborts the example process
**What goes wrong:** `Command::Doctor#run` calls `Kernel#exit` (line 42); a spec that runs a failing-check scenario without stubbing `exit` kills the whole RSpec process.
**How to avoid:** Existing spec stubs it via `allow_any_instance_of` [VERIFIED: doctor_spec.rb:58]; any new exit-1 proof must do the same, or prove exit semantics at the CLI boundary (`bundle exec bin/spm-cache doctor; echo $?`) rather than in-process.
**Warning signs:** RSpec "exited" mid-run with no failure output.

### Pitfall 6: Singleton `Config` leaks across examples
**What goes wrong:** `Config.instance` is a process-wide singleton (`@@instance ||= super`, [VERIFIED: config.rb:37-39]); `remote_backend_connectivity` falls back to it and calls `load` — in-process spec state can leak between examples, and the remote verdict depends on whether an `spm-cache.yml` exists in the cwd (repo root has none [VERIFIED: `ls` this session]).
**How to avoid:** For CLI-level proofs, run in a controlled cwd (empty tmpdir = "No remote backend configured (local-only)"; tmpdir with `remote:` in `spm-cache.yml` = the configured message). `Config#reset!` exists [VERIFIED: config.rb:133-135] if in-process isolation is ever needed.
**Warning signs:** Remote-check messages flipping between spec and CLI runs.

### Pitfall 7: Doc-drift surfaces that claim false things (sweep list)
All verified this session; each is a small fix or a doc edit, none require re-implementation:
1. **SUMMARY.md line counts**: claims `diagnostics.rb` "139 lines" (actual 156), `doctor.rb` "78 lines" (actual 82), `doctor_spec.rb` "69 lines" (actual 69 — correct) [VERIFIED: `wc -l` + `git show 5ea68a5 --stat`].
2. **SUMMARY.md/CONTEXT.md "7 specs, injected/stubbed shell collectors, no real Xcode required"** — see Pitfalls 2 and 3; the parenthetical is inaccurate on both counts (only `exit` is stubbed; Xcode IS probed, assertions just tolerate its absence).
3. **`doctor --help` and `self.description` still say "green/yellow/red report" / "color-coded report"** [VERIFIED: doctor.rb:14,17 + live `--help`] — contradicts accepted limitation #1; falls squarely under "minor doc-phrasing fixes" discretion.
4. **`docs/project-roadmap.md:63`** still lists `- [ ] spm-cache doctor command (diagnose environment, toolchain)` as an unchecked future item — shipped; checkbox/ticket should be updated or the item removed as delivered.
5. **ROADMAP criterion 3 wording "addable/removable via config"** — shipped mechanism is the Ruby `register` API (yml config explicitly rejected 2026-08-24); record as accepted interpretation ("config" = data-driven registry, not spm-cache.yml) or adjust the ROADMAP phrasing.
6. **REL-02 wording "cache-dir health/orphans"** vs. shipped count-only health check; **"remote-backend connectivity"** vs. shipped config-presence check — see Pattern 2 table. Neither is flagged in CONTEXT.md's accepted limitations; they need an explicit accept-as-shipped record or a gap decision (see Open Questions).

## Code Examples

### Adding a check (criterion-3 proof — no command edit)
```ruby
# Source: lib/spm_cache/core/diagnostics.rb:34-36 (register) — extension point is Ruby-level only
SPMCache::Core::Diagnostics.register('my_probe', fix_hint: 'Do X to remediate') do |config:|
  [:warn, "probe says warn"]
end
# After this, `spm-cache doctor` reports it in registration order with ↳ fix_hint.
# Removal = delete the register block. doctor.rb is untouched either way.
```

### Exit-1 proof without editing any file (verification recipe)
```bash
# In-process, with exit stubbed (mirrors doctor_spec.rb:58):
ruby -e '
  require "spm_cache/main"
  require "stringio"
  allow = nil
  # RSpec-free: stub via module override
  class SPMCache::Command::Doctor
    def exit(*) = (@exited = true)
    attr_reader :exited
  end
  SPMCache::Core::Diagnostics.register("force_fail", fix_hint: "none") { [:fail, "boom"] }
  cmd = SPMCache::Command.parse(["doctor"])
  cmd.run
  puts "exit-1 path reached: #{cmd.exited.inspect}"
'
# CLI-boundary (real exit code) — run doctor where a check genuinely fails,
# e.g. PATH without xcodebuild, or simplest: trust the any(&:fail?) line + spec stub proof.
```

### Live evidence captured this session (2026-08-24, this machine)
- `bundle exec bin/spm-cache doctor` → 7 lines `✓ …`, `Summary: 7 ok, 0 warnings, 0 failures`, exit 0 (Xcode 26.3, Swift 6.2.4, toolchain path resolved, 3 cache configs/~12,403 files, LE built-in, no remote configured, companion binary present — **without version suffix**, see Pitfall 1).
- `bundle exec bin/spm-cache doctor --json` → valid `JSON.pretty_generate` payload, `summary: {ok: 7, warnings: 0, failures: 0}`, exit 0.
- `bundle exec rspec spec/doctor_spec.rb --format documentation` → **7 examples, 0 failures** (4 doctor + 3 spec_helper), 2.24s.
- `git show 5ea68a5 --stat` → exactly `Gemfile.lock`, `lib/spm_cache/command/doctor.rb` (82 lines), `lib/spm_cache/core/diagnostics.rb` (156 lines), `spec/doctor_spec.rb` (69 lines) — matches SUMMARY's commit claim `5ea68a5`.

## State of the Art

| Old Approach | Current Approach (as shipped) | When Changed | Impact |
|--------------|------------------------------|--------------|--------|
| Hardcoded diagnostic sequence in the command | Registry-of-blocks (`register` + `run_all`) | v0.3.0 design (2026-08-10), shipped 5ea68a5 | Criterion 3 satisfied structurally; extension is Ruby-API-only by locked decision |
| Planned: injected shell-output collectors for hermetic unit tests | Live-execution tolerant assertions + one `exit` stub | Shipped 5ea68a5 (deviation from design) | Criterion 4 not met as worded — must be routed (Pitfall 2) |
| Planned: ANSI green/yellow/red report | Plain ✓/!/✗ markers | Shipped 5ea68a5; accepted 2026-08-24 | REL-02 "color-coded" → documented deviation |

**Deprecated/outdated within this feature's docs:** `docs/superpowers/specs/…design.md:172` (injected-collector testing description), `docs/project-roadmap.md:63` (unchecked future item) — both stale relative to shipped reality.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Homebrew/gem installs of the gem will report `companion_binary` as `:warn` because the binary path is resolved against the gem's `ROOT` and the proxy is not shipped inside the gem package | Pattern 2 table | Low — does not affect this phase's proofs (all run from the repo); worth noting in docs if wrong |
| A2 | `Sh` string commands always execute via the shell, so embedded `2>/dev/null` redirects are honored | Pattern 2 (toolchain_path, companion_binary) | Low — verified behaviorally this session (toolchain_path returns clean path); Ruby's Open3 with a String command does use the shell |

**Otherwise:** all claims above were verified this session against source lines, live CLI runs, a live spec run, `git show`, or `wc -l` — no other `[ASSUMED]` claims.

## Open Questions (RESOLVED)

1. **`companion_binary` version probe (Pitfall 1) — fix or record?**
   - What we know: the `--version` attempt can never succeed against the shipped proxy (no version flag exists).
   - What's unclear: whether the user wants the minimal Ruby-side fix (drop dead branch, re-record limitation as presence-only), a proxy-side `version` subcommand, or a third accepted-limitation entry keeping the code as-is.
   - Recommendation: default to the minimal Ruby-side fix + limitation record; a proxy change drags in Swift build/test surface for marginal value. Needs user/checkpoint confirmation because CONTEXT.md's accepted-decision text describes the version display as part of what was accepted.

2. **Criterion 4 ("injected shell-output collectors") — accept deviation or close the gap?**
   - What we know: no injection seam exists; specs run live with tolerant assertions; suite passes on CI Xcode 16 and local Xcode 26.3.
   - What's unclear: whether the user wants a hermetic seam added (small: e.g., `Diagnostics.run_all(config:, shell: Sh)` default parameter, or spec-level `allow(Sh).to receive(:capture_output)`) or a recorded deviation like the color one.
   - Recommendation: recording the deviation is cheapest and honest; a tiny seam addition also satisfies the letter of the criterion. Planner should pick per "fix small gaps found" guidance.

3. **REL-02 wording nuances — "orphans" and "connectivity": accept-as-shipped records needed?**
   - What we know: shipped checks do count-only health (no orphan detection) and config-presence (no network probe); CONTEXT.md's accepted limitations cover color and version-comparison only.
   - What's unclear: whether these two wording deltas should be formally recorded as accepted deviations (like the color one) so the verifier doesn't count them as gaps.
   - Recommendation: record both as accepted-as-shipped wording deviations in the phase docs; building orphan detection or a connectivity probe is new feature work, out of verification scope.

4. **Should `doctor --help` / `self.description` color wording be fixed under "minor doc-phrasing fixes" discretion?**
   - What we know: help text promises "green/yellow/red" the report doesn't deliver.
   - Recommendation: yes — one-line description edit (`doctor.rb:14,17`), squarely within granted discretion; listed here only because it touches shipped code on a verification-scoped phase.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Ruby + Bundler | specs, CLI | ✓ | Ruby 3.x via bundle (gemspec requires >= 3.1) | — |
| Xcode (`xcodebuild`, `swift`, `xcrun`) | 3 checks' `:ok` verdicts; spec live probes | ✓ | Xcode 26.3, Swift 6.2.4 (local); CI pins Xcode 16 on macos-15 | Checks degrade to `:fail`/tolerant assertions; suite still green |
| Companion binary (`make proxy.build`) | `companion_binary` `:ok`; binary-gated specs | ✓ | built 2026-08-24 at `tools/spm-cache-proxy/.build/release/spm-cache-proxy` | Check degrades to `:warn` (accepted); CI builds it before RSpec [VERIFIED: ci.yml:37-41] |
| `~/.spm-cache` | `cache_dir_health` `:ok` (exists branch) | ✓ | 3 configs, ~12,403 files | "does not exist yet" ok branch |
| Network | Nothing — doctor performs no network I/O | — | — | n/a (connectivity check is config-presence only) |

**Missing dependencies with no fallback:** none.
**Missing dependencies with fallback:** none missing; environment-dependent verdicts all have shipped graceful degradation (see Pitfall 4).

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | RSpec 3.13.2 [VERIFIED: Gemfile.lock] |
| Config file | none (no `.rspec`; `spec/spec_helper.rb` has no `RSpec.configure` — mocks work by default) |
| Quick run command | `bundle exec rspec spec/doctor_spec.rb` (7 examples, ~2–6s) |
| Full suite command | `bundle exec rspec` (29 spec files; same command CI runs [VERIFIED: ci.yml:41]) |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| REL-02 | 7 checks registered with exact names | unit (registry) | `bundle exec rspec spec/doctor_spec.rb` → `registers built-in checks` | ✅ |
| REL-02 | Every check returns Result with valid status/message/fix_hint; raising check isolated as `:fail` | unit (registry) | `bundle exec rspec spec/doctor_spec.rb` → 2 registry examples | ✅ |
| REL-02 | Text report format (✓/!/✗, ↳ fix_hint, Summary line) | smoke (CLI) | `bundle exec bin/spm-cache doctor` — eyeball markers + summary | ✅ (CLI; no automated formatter spec) |
| REL-02 | Registry extensible without editing command | unit + demo | spec `registers built-in checks` + `ruby -e` register-then-run proof (Code Examples) | ✅ (mechanics; extension demo is a plan-task proof) |
| REL-02 | Color-coded report | deviation record | — (accepted limitation #1; verify markers + record) | n/a |
| REL-03 | `--json` shape `{checks, summary}` | unit (command) | `bundle exec rspec spec/doctor_spec.rb` → `emits valid JSON…` | ✅ |
| REL-03 | JSON mirrors text diagnostics; CI exit semantics | smoke (CLI) | `bundle exec bin/spm-cache doctor --json \| ruby -rjson -e '…'` + `echo $?` after both modes | ✅ (CLI; exit-1 path needs forced-fail setup or the in-process stub recipe) |

**What must be stubbed vs live (critical for the plan):** In the shipped spec, only `exit` is stubbed (`allow_any_instance_of`, doctor_spec.rb:58); `$stdout` is swapped for a `StringIO` around the command run (doctor_spec.rb:52-63). All checks run **live** (real `xcodebuild`/`swift`/`xcrun`/FS probes) — that is the shipped interpretation of "no real Xcode *required*" (assertions tolerate absence), NOT the ROADMAP's "injected collectors" (see Pitfall 2). Any new per-check-path spec added during gap-fixing should stub `Sh.capture_output` (module-double) or receive an injected collector if the seam is added.

### Sampling Rate
- **Per task commit:** `bundle exec rspec spec/doctor_spec.rb`
- **Per wave merge:** `bundle exec rspec` (full suite — includes doctor specs on every run)
- **Phase gate:** full suite green + the two CLI smoke invocations (`doctor`, `doctor --json`) with captured output before `/gsd-verify-work`

### Wave 0 Gaps
- None for framework/config — existing infrastructure covers the phase. If the criterion-4 gap-fix route is chosen, the new hermetic spec(s) land in `spec/doctor_spec.rb` (Wave-of-fix, not Wave 0).

## Security Domain

security_enforcement: true (level 1) [VERIFIED: .planning/config.json:47-49]. Doctor is a read-only diagnostics surface; ASVS L1 exposure is minimal and shipped controls already cover it.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | No auth surface; local CLI |
| V3 Session Management | no | None |
| V4 Access Control | no | Local read-only probes |
| V5 Input Validation | marginal | No user input reaches commands: check commands are hardcoded literals; the only interpolation is the repo-constant binary path (`ROOT` + fixed relative path). Config read via `YAML.safe_load` [VERIFIED: config.rb:51] — safe-load blocks arbitrary object deserialization. |
| V6 Cryptography | no | None |
| V12 File Handling | marginal (L1 intent) | All file access is read-only (`File.executable?`, `Dir.children`, `Dir.glob`); no writes anywhere in doctor path — matches the locked "strictly read-only" decision |

### Known Threat Patterns for Ruby CLI shell-outs

| Pattern | STRIDE | Standard Mitigation (shipped) |
|---------|--------|------------------------------|
| Command injection via interpolated shell command | Tampering/Elevation | Not reachable: commands are string literals with no user input; interpolated `bin` path derives from `SPMCache::ROOT` constant. Keep it that way in any gap-fix — never interpolate config values into `Sh` commands. |
| Unsafe YAML deserialization | Tampering | `YAML.safe_load` for spm-cache.yml [VERIFIED: config.rb:51] |
| DoS via huge cache-dir scan | DoS | Bounded in practice: one `Dir.glob` per config dir; acceptable for a diagnostics command; not a shipped concern |

## Sources

### Primary (HIGH confidence — all read/executed this session)
- `lib/spm_cache/core/diagnostics.rb` (full 156 lines) — registry mechanics, all 7 checks, line-anchored quotes
- `lib/spm_cache/command/doctor.rb` (full 82 lines) — CLI, formatters, exit semantics
- `spec/doctor_spec.rb` (full 69 lines) — exact stubbing approach, 4 examples
- `spec/spec_helper.rb` — 3 inline examples explaining "7 examples"
- `lib/spm_cache/core/sh.rb` — Open3 semantics, GeneralError-on-failure, shell-string behavior
- `lib/spm_cache/core/config.rb` — CACHE_DIR, Singleton instance, `raw['remote']`, safe_load, reset!
- `lib/spm_cache/core/error.rb:7` — `class GeneralError < BaseError`
- `lib/spm_cache.rb:6` — ROOT; `lib/spm_cache/main.rb` — load_all wiring; `bin/spm-cache` — entry
- Live runs: `bin/spm-cache doctor` / `--json` / `--help`; `bundle exec rspec spec/doctor_spec.rb` (7/0); proxy `--help` and `--version` probes; `git show 5ea68a5 --stat`; `wc -l`
- `.planning/ROADMAP.md` (Phase 2 criteria 1–4), `.planning/REQUIREMENTS.md` (REL-02/03), `.planning/phases/02-diagnostics-command/02-CONTEXT.md` (accepted decisions/limitations), `SUMMARY.md` (claims cross-checked), `.github/workflows/ci.yml`, `.planning/config.json`
- `docs/superpowers/specs/2026-08-10-v0.3.0-watch-init-doctor-design.md:131-209` — original doctor design + injected-collector testing intent; `docs/project-roadmap.md:63` — stale checklist item

### Secondary (MEDIUM confidence)
- None — no web/registry lookups needed; the domain is entirely in-repo.

### Tertiary (LOW confidence)
- None.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — nothing to choose; all existing, read this session
- Architecture: HIGH — full source of all three files + live runs
- Pitfalls/gaps: HIGH — each verified by direct probe (proxy `--version` exit 64; spec example count; live output)
- Environment-dependent verdicts: HIGH locally; CI verdicts inferred from ci.yml config (Xcode 16 pinned) but not executed this session [ASSUMED only where marked A1/A2]

**Research date:** 2026-08-24
**Valid until:** 2026-09-23 (stable — in-repo code, no fast-moving external deps)
