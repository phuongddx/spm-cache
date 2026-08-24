# Phase 3: Project Bootstrap - Research

**Researched:** 2026-08-24
**Domain:** Verification-scoped closure of the already-implemented `spm-cache init` CLI (CLaide command, Ruby)
**Confidence:** HIGH (every code claim below was read from source this session; every behavioral claim marked VERIFIED was executed this session)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Flag surface (accepted as shipped, 2026-08-24)**
- `--default-config=CONFIG` replaces ROADMAP's `--config` wording — DOCUMENTED DEVIATION: the inherited CLaide `Command` base already defines `--config` (SDK config); the rename avoids the collision. Record in phase docs; do not alias.
- Full flag set: `--project=PATH`, `--platform=LIST`, `--default-config=CONFIG`, `--remote=BACKEND`, `--remote-url=URL`, `--branch=BRANCH` (default main), `--creds=PATH` (S3 credentials; superset of the ROADMAP list — accepted).

**Interactive heuristic (accepted as shipped)**
- Prompts appear only when stdin is a TTY AND no non-interactive flags were supplied; CI (piped stdin) or any flag → defaults: platforms `ios`, config `debug`, remote `none`, branch `main`
- Empty prompt input falls back to the per-prompt default (`ios`/`debug`/`none`); no re-prompt loop, no abort

**Lockfile seeding & idempotency (accepted as shipped)**
- No `Package.resolved` present → seeding skipped with a message; `spm-cache.yml` still generated; exit 0
- Existing `spm-cache.yml` on re-run → idempotent diff-merge (user keys preserved, defaults added, never overwritten); `spm-cache/` appended to `.gitignore` once
- `resolve_project` validates the detected/passed path exists (not just non-nil) — no .xcodeproj → clear error naming `--project`

### Claude's Discretion
Verification task granularity; how to organize acceptance proofs (spec runs vs tmpdir CLI invocations); doc phrasing fixes.

### Deferred Ideas (OUT OF SCOPE)
- `--yes`/`--non-interactive` explicit flag — rejected 2026-08-24 (TTY heuristic covers CI; flags imply non-interactive)
- `--config` alias for `--default-config` — rejected 2026-08-24 (rename is the cleaner contract)
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| ONBD-01 | `spm-cache init` interactively bootstraps a project — detects `.xcodeproj`, prompts for platforms/config/remote-backend, generates `spm-cache.yml` + a `spm-cache.lock` seeded from `Package.resolved` so the first `use` is a fast path | Implementation exists and generates all artifacts (`init.rb` run flow). **BUT**: the seeded lock is a byte-copy of `Package.resolved` in pins format, which crashes `use`'s DiffDetector — see "Critical Finding". The "first `use` is a fast path" clause is not achievable as shipped (crash) and is conceptually impossible on a *first* run anyway (`fast_path?` requires an already-materialized proxy). |
| ONBD-02 | Non-interactive flags (`--platform`, `--config`, `--remote`, `--remote-url`, `--branch`) work for scripting/CI | Spec-proven (3 of 4 specs exercise flag-driven runs). ROADMAP's `--config` shipped as `--default-config` — user-accepted documented deviation (CLaide base `Command` already defines `--config`, `[VERIFIED: lib/spm_cache/command.rb:19]`). |
| ONBD-03 | Re-running `init` idempotently diff-merges (preserves user keys, adds defaults, never overwrites) and appends `spm-cache/` to `.gitignore` once | Spec-proven (`init_spec.rb` examples 2). Merge mechanics verified down to `Config#load`'s `DEFAULT_CONFIG.merge(file)` — see "yml diff-merge mechanics". |
</phase_requirements>

## Summary

Phase 3's deliverable is **already implemented and committed** (`c51cedc`, verified via `git show --stat`: exactly `lib/spm_cache/command/init.rb` 177 insertions + `spec/init_spec.rb` 105 insertions, nothing else). The phase plan must be **verification-scoped**: run the existing regression spec, prove each ROADMAP criterion against live behavior via tmpdir CLI invocations, correct doc drift in `SUMMARY.md`, and record the `--config` → `--default-config` deviation. There is nothing to design and no re-implementation (locked in CONTEXT.md).

However, research uncovered **one material, empirically reproduced defect** that the plan cannot paper over: `init` seeds `spm-cache.lock` as a byte-copy of Xcode's `Package.resolved` (`{"pins":[...],"version":1}`), while every lockfile consumer in the codebase — `DiffDetector#locked_packages` (`lib/spm_cache/core/diff_detector.rb:101-104`), `Installer#generate_lockfile_from_resolved` (`lib/spm_cache/installer.rb:175-191`), and the existing spec fixtures (`spec/diff_detector_spec.rb:54-57`, `spec/installer_use_fast_path_spec.rb:30-38`) — expects the canonical shape `{"<Proj>.xcodeproj"=>{"packages"=>[...], "dependencies"=>{...}, "platforms"=>{...}}}`. End-to-end execution this session (`init` exit 0 → `use` in same project) crashed with `TypeError: no implicit conversion of String into Integer` at `diff_detector.rb:103`, full stack trace, non-zero exit. The empty-skeleton fallback `{"projects":[]}` crashes identically. This directly contradicts ROADMAP criterion 1's "seeded from Package.resolved so the first `use` hits the fast path" — as shipped, init-seeded projects **cannot run `use` at all**.

**Primary recommendation:** Build the plan as criterion-by-criterion verification proofs (spec run + tmpdir CLI invocations), fix SUMMARY.md drift (4 specs not 7; 105/177 lines not 107/169), record the `--default-config` deviation — and surface the seeded-lock format crash to the user as a scope decision (Open Question 1): either a minimal, surgical fix task (seed in canonical format — the transformation already exists at `installer.rb:164-193` and is spec-covered), or record it as a known-issue deviation like Phase 2 did. Do not silently close criterion 1 as "verified".

## Critical Finding: Seeded Lock Format Is Incompatible With `use` (VERIFIED by execution)

**What was run** (this session, repo cwd, ruby 3.2.3):

1. **Component repro** — `Init` into a tmpdir fixture (real `TestApp.xcodeproj` dir + `project.xcworkspace/xcshareddata/swiftpm/Package.resolved` with one Alamofire pin), then `Core::DiffDetector.new(project_path:, lockfile_path:).detect`:
   - Seeded lock (byte-copied pins JSON): `detect RAISED TypeError: no implicit conversion of String into Integer`
   - Control, canonical shape `{"TestApp.xcodeproj"=>{"packages"=>[...]}}`: `detect OK — empty=true summary="No changes detected. Proxy package up to date."`
   - Empty-skeleton `{"projects":[]}`: `detect RAISED TypeError: no implicit conversion of String into Integer`
2. **End-to-end** — real CLI `bundle exec ruby -Ilib bin/spm-cache init --project=<tmp>/Fake.xcodeproj --platform=ios --default-config=debug` (exit 0, seeded lock message printed), then `bin/spm-cache use` with cwd = project dir:
   - Crashed with full backtrace: `use.rb:28 run → run_once → perform_install → installer.rb:57 detect_diff → diff_detector.rb:57 detect → :102 each_value → :103 (proj_data['packages'] || [])` — `TypeError: no implicit conversion of String into Integer`.

**Root cause chain** `[VERIFIED: lib/spm_cache/core/diff_detector.rb:101-104]`:

```ruby
data = JSON.parse(content)
data.each_value do |proj_data|
  (proj_data['packages'] || []).each do |pkg|
```

With pins format, `each_value` yields the `pins` **Array** (then Integer `1`); `Array#[]('packages')` raises TypeError. With `{"projects":[]}` it yields `[]` — same raise.

**Why the lock is never self-healing:** `Installer#generate_lockfile_from_resolved` — the method that writes the canonical format — starts with `return if File.exist?(lockfile_path)` `[VERIFIED: lib/spm_cache/installer.rb:165-166]`, so on an init-seeded project the correct generator **never runs**, and even if it did, `detect_diff` crashes *before* `sync_lockfile` in `perform_install` (`use.rb:17-27`: `detect_diff` precedes everything). The file also never gets rewritten because the process dies at first diff.

**Impact on "first `use` fast path":** even with a correctly-shaped seed, `fast_path?` requires three conditions `[VERIFIED: lib/spm_cache/installer/use.rb:45-51]` — non-nil diff, empty diff, **proxy `Package.swift` materialized** — and a freshly-bootstrapped project has no proxy, so the first `use` is always a full regeneration *by design* (the fast path is for the *second* run onward; `spec/installer_use_fast_path_spec.rb:112` is literally titled "regenerates when lockfile is missing (first run)"). The requirement's "first `use` is a fast path" phrasing overstates what the mechanism delivers; the seeded lock's real value is only that `generate_lockfile_from_resolved` would early-return — which, given the format bug, is currently a liability, not a feature.

**Scope note for the planner:** CONTEXT.md locks seeding policy "as shipped" (skip-when-no-Package.resolved, messages, exit 0) — but the *format incompatibility* was not visible in any phase doc and invalidates criterion 1's stated purpose. This is precisely the kind of discovery verification exists to surface. Present both options to the user; do not decide unilaterally, and do not mark criterion 1 green without addressing it.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| .xcodeproj detection / path validation | CLI command layer (`Command::Init#resolve_project`) | — | Pure filesystem probing in `Dir.pwd`; no service involvement |
| Interactive prompts (TTY heuristic) | CLI command layer (`#interactive?` + `$stdin.gets`) | — | Terminal UX concern; gated by TTY detection so CI never blocks |
| Flag parsing | CLaide argv (`self.options` + `argv.option`) | — | Inherited CLaide `Command` machinery; collision with base `--config` drove the rename |
| yml generation / diff-merge | `Core::Config` singleton + `Syntax::YAMLRepresentable` | `Command::Init#write_config` | Config owns load/merge/save; Init only orchestrates key assignment |
| Lockfile seeding | `Command::Init#seed_lockfile` (raw `FileUtils.cp`) | `Installer#generate_lockfile_from_resolved` (canonical format — NOT used by init) | Divergent implementations of "seed from Package.resolved" — the defect above |
| .gitignore append-once | `Command::Init#ensure_gitignore` | — | Pure file append with exact-string dedup |
| Lockfile consumption (diff/fast path) | `Core::DiffDetector` / `Installer::Use` | — | Owns the canonical format contract init violates |
| Executable wiring | `bin/spm-cache` → `SPMCache::Main.run` → `Command.run` | `Main.load_all` (requires every lib .rb sorted) | CLaide resolves the `init` subcommand to `Command::Init` automatically |

## Existing Implementation Reference (verified facts)

All quotes below are verbatim from files read this session.

### Flag surface — `[VERIFIED: lib/spm_cache/command/init.rb:16-26]`

```ruby
def self.options
  [
    ['--project=PATH', 'Path to the .xcodeproj (default: auto-detect in cwd)'],
    ['--platform=LIST', 'Comma-separated platforms (ios,macos,watchos,tvos)'],
    ['--default-config=CONFIG', 'Default build config (debug/release)'],
    ['--remote=BACKEND', 'Remote backend (none/git/s3)'],
    ['--remote-url=URL', 'Git remote URL or S3 URI'],
    ['--branch=BRANCH', 'Git remote branch (default: main)'],
    ['--creds=PATH', 'S3 credentials JSON file path']
  ].concat(super)
end
```

7 init-owned flags, matching CONTEXT's accepted set. `initialize` defaults `@branch = argv.option('branch') || 'main'` `[VERIFIED: init.rb:29-37]`. Base `Command` adds `--sdk=SDK`, `--config=CONFIG`, `--log-dir=DIR`, `--no-merge-slices`, `--no-library-evolution` `[VERIFIED: lib/spm_cache/command.rb:16-24]` — the `--config` entry at `command.rb:19` is the documented collision motivating `--default-config`.

### TTY heuristic — `[VERIFIED: lib/spm_cache/command/init.rb:119-121]`

```ruby
def interactive?
  $stdin.tty? && @platforms.nil? && @remote.nil?
end
```

**Precise semantics (drift vs CONTEXT wording):** only `--platform` and `--remote` suppress interactivity. `--default-config`, `--branch`, `--remote-url`, `--creds`, `--project` alone do **not** — on a real TTY with only e.g. `--project` given, prompts still fire. CONTEXT's "any flag → defaults" is a simplification. CI is safe regardless because stdin is piped (`.tty?` false).

**Empty-input nuance (drift vs CONTEXT wording):** the `||` fallback fires only on EOF (nil), not on empty Enter — `($stdin.gets&.chomp || 'ios')` keeps `""` (truthy in Ruby). Empty Enter on the platforms prompt yields `[]` → the `platforms` key is omitted (see merge mechanics); on the config prompt `""` is written as `default_config: ''` (truthy passes the `if cfg` guard); on the remote prompt `''` hits `backend.empty?` → treated as `none`. CONTEXT's "empty prompt input falls back to the per-prompt default" is therefore accurate for remote, effectively-omitted for platforms, and wrong for default_config (writes empty string). TTY-only path — unreachable in specs (stdin not a TTY); record, don't spec.

### Project detection — `[VERIFIED: lib/spm_cache/command/init.rb:62-66]`

```ruby
def resolve_project
  return @project if @project && File.directory?(@project)

  Dir.glob(File.join(Dir.pwd, '*.xcodeproj')).find { |p| File.directory?(p) }
end
```

- `--project` must be the `.xcodeproj` **bundle directory** itself (`File.directory?` — .xcodeproj is a dir on disk) and must **exist**; a non-existent path silently falls through to auto-detect (cwd), and only if *that* finds nothing does `run` raise `Core::GeneralError, 'No .xcodeproj found — pass --project or run inside an Xcode project directory'` `[VERIFIED: init.rb:39-43]`. (Passing a *bogus* `--project` inside a real project dir therefore inits the *detected* project, not an error — nuance worth knowing when writing negative-path proofs.)
- Auto-detect is **cwd-only, non-recursive** (`Dir.pwd + '/*.xcodeproj'`). With **multiple** .xcodeproj bundles in cwd, `.find` takes the first glob result — deterministic but silently ambiguous; no warning, no selection prompt. (Glob ordering is alphabetical on current MRI `[ASSUMED]`; the contract is simply "first match".)
- `run` then prints `Core::UI.info "Bootstrapping spm-cache for #{File.basename(project_path)}..."` and resolves platforms/config/remote before writing anything `[VERIFIED: init.rb:38-58]`.

### yml diff-merge mechanics (criterion 3 core) — `[VERIFIED: lib/spm_cache/command/init.rb:126-142]`

```ruby
def write_config(project_path, platforms, cfg, remote_hash)
  config = Core::Config.instance
  config.project_dir = File.dirname(project_path)
  config.config_path = File.join(config.project_dir, Core::Config::CONFIG_FILENAME)
  begin
    config.load
  rescue StandardError
    nil
  end

  config.raw['platforms'] = platforms unless platforms.empty?
  config.raw['default_config'] = cfg if cfg
  config.raw['default_sdk'] = 'iphonesimulator' unless config.raw.key?('default_sdk')
  config.raw['remote'] = remote_hash unless remote_hash.empty?

  config.save
end
```

`Config#load` — `[VERIFIED: lib/spm_cache/core/config.rb:47-54]`:

```ruby
def load(path = nil)
  @config_path = path if path
  if @config_path && File.exist?(@config_path)
    @raw = DEFAULT_CONFIG.merge(YAML.safe_load(File.read(@config_path)) || {})
  end
  @raw
end
```

with `DEFAULT_CONFIG` — `[VERIFIED: lib/spm_cache/core/config.rb:15-22]`:

```ruby
DEFAULT_CONFIG = {
  "ignore" => [], "cache_only" => [], "ignore_local" => false,
  "ignore_build_errors" => false, "keep_pkgs_in_project" => false,
  "default_sdk" => "iphonesimulator",
}.freeze
```

**Exact semantics:**
1. Existing file values **win** over `DEFAULT_CONFIG` (file is the merge argument) → user keys preserved, missing defaults **added** — this is the "adds defaults" half of criterion 3.
2. Only 4 keys are then assigned: `platforms` (skipped when resolved list is empty), `default_config` (when truthy), `default_sdk` (only `unless key?` — never overwritten), `remote` (only when the resolved hash is non-empty — a re-run with `--remote=none` **preserves** an existing remote rather than clearing it).
3. "Never overwrites" (criterion 3) is true for every user key **outside** init's managed set (`platforms`, `default_config`, `remote` are deliberately overwritten when supplied; `default_sdk` never). The idempotency spec proves the contract with `custom_key` preserved + `default_config` updated `[VERIFIED: spec/init_spec.rb:60-82]`.
4. Corrupt/unparsable existing yml: `config.load` raises inside, swallowed by `rescue StandardError; nil` → raw stays `DEFAULT_CONFIG.dup` (fresh process) → `save` **overwrites the corrupt file with defaults**. "Never overwrites" has this one edge: unreadable files are replaced.
5. `save` writes via `Syntax::YAMLRepresentable#save` → `File.write(@path, YAML.dump(raw))` `[VERIFIED: lib/spm_cache/core/syntax/yml.rb:21-27]`; `CONFIG_FILENAME = "spm-cache.yml"` `[VERIFIED: config.rb:24-26]`.

### Lockfile seeding — `[VERIFIED: lib/spm_cache/command/init.rb:143-161]`

```ruby
def seed_lockfile(project_path)
  resolved = find_package_resolved(project_path)
  lockfile_path = File.join(File.dirname(project_path), Core::Config::LOCKFILE_FILENAME)

  if resolved && File.exist?(resolved)
    FileUtils.cp(resolved, lockfile_path)
    Core::UI.info "Seeded #{Core::Config::LOCKFILE_FILENAME} from #{resolved}."
  else
    File.write(lockfile_path, "{\"projects\":[]}\n")
    Core::UI.info "Created empty #{Core::Config::LOCKFILE_FILENAME} (run `spm-cache use` after resolving deps)."
  end
end

def find_package_resolved(project_path)
  Dir.glob(File.join(project_path, '**/Package.resolved')).find { |f| File.exist?(f) }
end
```

- Search scope: **inside the .xcodeproj bundle only** (`project_path/**/Package.resolved`) — modern Xcode location `<proj>.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`. A **root-level** `Package.resolved` (Xcode ≤13 layout, or standalone SPM package) is NOT found → empty-skeleton path. Both written shapes crash DiffDetector (Critical Finding).
- Lock lands at project root: `File.dirname(project_path)/spm-cache.lock`; `LOCKFILE_FILENAME = "spm-cache.lock"` `[VERIFIED: config.rb:26]`.
- Canonical shape for reference — `[VERIFIED: lib/spm_cache/installer.rb:175-191]` writes `{"<basename(.xcodeproj)>"=>{"packages"=>[{repositoryURL,name,version,revision}...],"dependencies"=>{},"platforms"=>{...}}}`; the pins→packages transformation exists there and could seed correctly if a fix is approved.

### .gitignore append-once — `[VERIFIED: lib/spm_cache/command/init.rb:162-174]`

```ruby
def ensure_gitignore(project_path)
  gitignore = File.join(File.dirname(project_path), '.gitignore')
  entry = 'spm-cache/'
  lines = File.exist?(gitignore) ? File.readlines(gitignore).map(&:chomp) : []
  return if lines.include?(entry)

  File.open(gitignore, 'a') do |f|
    f.puts unless lines.empty? || lines.last&.end_with?("\n")
    f.puts '# spm-cache sandbox'
    f.puts entry
  end
end
```

- Dedup is **exact-string** against `spm-cache/` (matches `SANDBOX_DIR = "spm-cache"` `[VERIFIED: config.rb:23]`). A pre-existing `/spm-cache/` or bare `spm-cache` variant would get a duplicate append — cosmetic, note-only.
- `lines` are chomped, so `lines.last&.end_with?("\n")` is always false — the trailing-newline check is dead code; behavior: a blank separator line is always added before `# spm-cache sandbox` when the file is non-empty. Cosmetic-only drift from the evident intent; no functional impact.

### Spec suite reality — `[VERIFIED: spec/init_spec.rb raw read + executed run, 2026-08-24]`

- **4 `it` blocks** (bootstrap non-interactive; idempotency; git remote; graceful no-.xcodeproj failure). Executed: `bundle exec rspec spec/init_spec.rb` → **`7 examples, 0 failures` in 0.12s**.
- The 7 = 4 init examples **+ 3 smoke examples defined inside `spec/spec_helper.rb` itself** (`RSpec.describe SPMCache` — "has a version", "has ROOT constant", "resolves ROOT to the repo root, not its parent") `[VERIFIED: spec/spec_helper.rb:5-17]`; any spec file that requires spec_helper runs them. SUMMARY's "7 specs" is a run-count, not a file count; CONTEXT's "5 it blocks" is also wrong (4).
- Fixture pattern: `Dir.mktmpdir`; mkdir `TestApp.xcodeproj` + `project.xcworkspace/xcshareddata/swiftpm/Package.resolved` (one Alamofire pin JSON) inside the bundle; `after { FileUtils.remove_entry(tmpdir) }`.
- Non-interactive is forced **doubly**: rspec stdin is not a TTY, and every run passes `--platform` or `--remote` (both `interactive?` guards false). Prompts are unreachable in the suite.
- Singleton hygiene: `SPMCache::Core::Config.instance.reset!` before every `cmd.run` — spec comment: "load_all may have wired Config to the real cwd; point at tmpdir" (`spec_helper` requires `spm_cache/main`, whose `load_all` requires every lib file, some of which touch the Config singleton) `[VERIFIED: lib/spm_cache/main.rb:14-20, spec/init_spec.rb:35-37]`. Any new verification script invoking `Init` in-process MUST do the same `reset!`.
- Error-path example expects `raise_error(SPMCache::Core::GeneralError, /No \.xcodeproj found/)` `[VERIFIED: spec/init_spec.rb:95-104]`.

## Standard Stack

No new packages are installed or needed in this phase (verification only). Existing locked-in stack the verification touches:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| claide | 1.1.0 (vendored at ~/.xcframework-cli/gems) | CLI command tree, argv parsing | Already the gem's CLI framework; `Command::Init < Command` `[VERIFIED: e2e backtrace path]` |
| rspec | bundled | Test framework | Repo standard; `bundle exec rspec spec/init_spec.rb` |
| xcodeproj | bundled (Gemfile) | Building real `.xcodeproj` fixtures programmatically | Used by `spec/installer_use_fast_path_spec.rb:24-28` to create a valid project in tmpdir |
| tmpdir/fileutils/yaml/json | stdlib | Fixtures | No deps |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Open3 | stdlib | Capturing real CLI exit codes/output in proofs | e2e invocations of `bin/spm-cache` |

**Installation:** none — `bundle install` already satisfied (session ran specs and CLI without changes).

## Package Legitimacy Audit

Not applicable — this phase installs no external packages (verification-scoped; no new gems). Existing deps unchanged.

## Architecture Patterns

### System Architecture Diagram (verification data flow)

```mermaid
flowchart TD
    A["tmpdir fixture\n(mkdir .xcodeproj + Package.resolved)"] --> B["bin/spm-cache init\n--project/--platform/--remote flags"]
    B --> C{"resolve_project\n--project exists?\nelse glob Dir.pwd/*.xcodeproj"}
    C -->|"nothing"| X["raise GeneralError\n'No .xcodeproj found...'\n(exit non-zero)"]
    C --> D{"interactive?\nstdin.tty? AND\nno --platform/--remote"}
    D -->|yes TTY| E["$stdin prompts\nplatforms/config/remote"]
    D -->|no CI/flags| F["defaults\nios/debug/none/main"]
    E --> G["write_config\nConfig.load: DEFAULT_CONFIG.merge(file)\nassign 4 managed keys\nsave spm-cache.yml"]
    F --> G
    G --> H{"Package.resolved\ninside .xcodeproj?"}
    H -->|yes| I["FileUtils.cp → spm-cache.lock\n(pins format — CRASHES use)"]
    H -->|no| J["write {\"projects\":[]}\n(also crashes use)"]
    I --> K["ensure_gitignore\nappend 'spm-cache/' once"]
    J --> K
    K --> L["exit 0"]
    L -.->|"next run: bin/spm-cache use"| M["Installer::Use#perform_install\ndetect_diff → DiffDetector"]
    M --> N["TypeError: no implicit conversion\nof String into Integer\ndiff_detector.rb:103 (VERIFIED e2e)"]
```

### Recommended Verification Structure (for the planner)

Proofs map 1:1 onto ROADMAP criteria; each is a tmpdir invocation, no shared state:

1. **Spec run proof** — `bundle exec rspec spec/init_spec.rb --format documentation` → expect `7 examples, 0 failures` (document the 4+3 split so nobody "fixes" the count).
2. **Criterion proofs** — one bash/ruby snippet per criterion against `bin/spm-cache` in a tmpdir (scripts inline in this doc; `--project` must be **absolute**; for `use` invocations cwd must be the project dir — `use` takes no `--project` flag and globs cwd `[VERIFIED: lib/spm_cache/command/use.rb:34-36]`).
3. **Deviation records** — `--default-config` rename rationale + the format-crash decision land in the phase SUMMARY (Claude's discretion: doc phrasing).

### Anti-Patterns to Avoid
- **Re-implementing init features** — locked out by CONTEXT; the plan proves, records, and (only if user approves) surgically fixes the seed format.
- **New spec files asserting SUMMARY line counts** — drift numbers are doc bugs; fix the docs, don't enshrine them.
- **Interactive-path specs** — `$stdin` TTY mocking for prompt flows is out of scope (TTY heuristic accepted as shipped; prompts unreachable in CI).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Real .xcodeproj fixture | Hand-written pbxproj strings | `Xcodeproj::Project.new(path)` + `new_target(:application,'MyApp',:ios)` + `save` (pattern at `spec/installer_use_fast_path_spec.rb:24-28`) | pbxproj format is brittle; xcodeproj gem is already a dependency with a proven fixture pattern |
| Canonical lock for control experiments | Hand-rolled JSON | Shape from `spec/diff_detector_spec.rb:54-57` / `installer.rb:175-191` | It's the format contract all consumers share |
| CLI exit-code capture | `system` + `$?` | `Open3.capture3` | Separates stdout/stderr and gives a Process::Status |

**Key insight:** every proof this phase needs already has an in-repo precedent spec or method; the verification plan should copy fixture patterns, not invent them.

## Common Pitfalls

### Pitfall 1: Config singleton leaks across invocations
**What goes wrong:** `Core::Config` is a Singleton; `Main.load_all` (auto-required by spec_helper) can leave it pointed at the real cwd. In-process verification runs write `spm-cache.yml` into the wrong directory or merge a stale raw hash.
**How to avoid:** Call `SPMCache::Core::Config.instance.reset!` immediately before every `Init#run` (note: `reset!` only resets `@raw = DEFAULT_CONFIG.dup` — it does NOT reset `project_dir`/`config_path`, but `write_config` reassigns both per run `[VERIFIED: config.rb:130-132, init.rb:127-129]`, so reset! alone suffices). The shipped specs do exactly this.
**Warning signs:** yml appearing in repo root during a verification run.

### Pitfall 2: Forcing non-interactive in proofs
**What goes wrong:** assuming prompts are suppressed because flags were passed — only `--platform`/`--remote` suppress them (`interactive?` checks exactly those two).
**How to avoid:** every proof invocation passes `--platform` (and/or `--remote`), which is also the spec suite's pattern; CI/piped stdin is the second safety net.
**Warning signs:** a proof hanging on stdin.

### Pitfall 3: The seeded-lock format crash masquerading as a `use` bug
**What goes wrong:** any e2e "init then use" proof dies with `TypeError` in diff_detector — it looks like a DiffDetector defect but is caused by `init`'s byte-copy seed.
**How to avoid:** read the Critical Finding; control experiments must write the canonical lock shape.
**Warning signs:** `no implicit conversion of String into Integer`.

### Pitfall 4: Multiple .xcodeproj bundles in cwd
**What goes wrong:** auto-detect silently picks the first glob hit; a proof fixture with two projects validates nothing about user intent.
**How to avoid:** one .xcodeproj per tmpdir; use explicit absolute `--project` in proofs.

### Pitfall 5: Relative vs absolute paths
**What goes wrong:** `--project=TestApp.xcodeproj` (relative) works — `File.dirname` yields `.` and artifacts land cwd-relative — but proofs that `Dir.chdir` between parse and run will scatter files.
**How to avoid:** absolute tmpdir paths everywhere (the shipped spec uses absolute `project_path` from `Dir.mktmpdir`).

### Pitfall 6: `use` has no `--project` flag
**What goes wrong:** `spm-cache use --project=X` → CLaide "Unknown option" banner, exit 1 — misread as an init failure.
**How to avoid:** `use` proofs must run with cwd = project dir (`Dir.glob('*.xcodeproj').first` at `use.rb:34-36`).

### Pitfall 7: Bogus `--project` silently falls back to auto-detect
**What goes wrong:** `--project=/nonexistent` inside a directory containing an .xcodeproj inits the *detected* project (exit 0), because `resolve_project` treats a non-existent `--project` as "not given". Only a *completely* project-less context raises.
**How to avoid:** no-.xcodeproj proofs must run from an empty tmpdir without `--project`, or with `--project` pointing into an empty tmpdir (the spec's approach — nonexistent `Nope.xcodeproj` inside an empty tmpdir, no cwd project).

### Pitfall 8: Example-count confusion (7 vs 4)
**What goes wrong:** "7 examples" in a run is misattributed to init_spec having 7 tests; docs get "corrected" against reality.
**How to avoid:** 4 init `it` blocks + 3 `spec_helper.rb` smoke examples = 7; record the split in the corrected SUMMARY.

## Doc Drift Catalogue (verified against reality, 2026-08-24)

| # | Location | Claim | Reality | Verdict |
|---|----------|-------|---------|---------|
| 1 | SUMMARY.md L7 | `init.rb` "169 lines" | **177 lines** (`wc -l`; `git show --stat c51cedc`: 177 insertions) | Fix |
| 2 | SUMMARY.md L8 | `init_spec.rb` "(107 lines) — 7 specs" | **105 lines, 4 `it` blocks**; runs as 7 examples only because spec_helper defines 3 SPMCache smoke examples | Fix (state "4 specs (+3 shared helper examples)"; 105 lines) |
| 3 | ROADMAP criterion 2 | flags `--platform`, `--config`, `--remote`, `--remote-url`, `--branch` | Shipped `--default-config` in place of `--config`; superset adds `--project`, `--creds` | Record as DOCUMENTED DEVIATION (user-accepted 2026-08-24, CONTEXT) — amend ROADMAP like Phase 2 did |
| 4 | CONTEXT.md heuristic bullet | "CI (piped stdin) or any flag → defaults" | Only `--platform`/`--remote` suppress prompts; other flags alone still prompt on a TTY | Optional CONTEXT wording note (decision itself unchanged) |
| 5 | CONTEXT.md heuristic bullet | "Empty prompt input falls back to the per-prompt default (ios/debug/none)" | Fallback fires on EOF only; empty Enter → platforms key omitted / `default_config: ''` / remote treated as none | Optional wording note (TTY-only path, accepted-as-shipped) |
| 6 | SUMMARY.md L8 | "All passing" | True — re-executed 2026-08-24: 7 examples, 0 failures, 0.12s | Keep |
| 7 | REQUIREMENTS/ROADMAP "first `use` is a fast path" | seeding enables fast path | Seeded format crashes `use` outright; even canonical seed can't fast-path a *first* run (proxy not yet materialized) | Open Question 1 — user scope decision |

## Runtime State Inventory

Not applicable — this phase is verification of an already-shipped greenfield feature; no rename/refactor/migration is involved. (No stored data, live-service config, OS-registered state, secrets, or build artifacts embed phase strings.)

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| ruby | everything | ✓ | 3.2.3 (rbenv, arm64-darwin23) | gemspec floor >= 3.1 `[CITED: .planning/ROADMAP.md:29]` |
| bundler + Gemfile deps | rspec, CLI runs | ✓ | bundle exec used throughout session | — |
| xcodeproj gem | real-project fixtures | ✓ | in bundle (used by existing specs) | plain dir fixture (init does not open the project) |
| Xcode toolchain | NOT required | — | — | init is pure file I/O; no xcodebuild/swift invocation anywhere in init.rb |
| git | commit_docs | ✓ | repo on branch gsd/v0.3.0-milestone | — |

**Missing dependencies with no fallback:** none.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | RSpec (bundled) |
| Config file | none beyond `spec/spec_helper.rb` (no .rspec file) |
| Quick run command | `bundle exec rspec spec/init_spec.rb` (~0.1s + ~1.7s load) |
| Full suite command | `bundle exec rspec` (main-agent scope — 31 spec files incl. swift-dependent ones; NOT this phase's gate) |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| ONBD-01 | bootstrap generates yml + seeded lock + .gitignore from fixture .xcodeproj | unit (existing) | `bundle exec rspec spec/init_spec.rb -e 'generates spm-cache.yml'` | ✅ |
| ONBD-01 (intent) | seeded lock consumable by `use` / fast path | **manual-only e2e — currently FAILS (crash)** | repro script (below) | ❌ known defect — Open Question 1 |
| ONBD-02 | flag-driven non-interactive runs | unit (existing) | `bundle exec rspec spec/init_spec.rb -e 'non-interactive' -e 'git remote backend'` | ✅ |
| ONBD-03 | idempotent diff-merge + gitignore-once | unit (existing) | `bundle exec rspec spec/init_spec.rb -e idempotent` | ✅ |
| ONBD-03 (error path) | no .xcodeproj → GeneralError naming --project | unit (existing) | `bundle exec rspec spec/init_spec.rb -e 'fails gracefully'` | ✅ |
| ROADMAP c1..c4 | CLI-level proof (real bin/spm-cache, real exit codes) | smoke (tmpdir, to write by executor) | snippet below | ❌ Wave-0-adjacent (plan task, ~15 lines) |

**CLI smoke proof skeleton** (pattern proven this session; nothing must be faked beyond the .xcodeproj dir + Package.resolved — init never opens Xcode):

```ruby
# Source: executed verbatim this session (e2e repro); expected outputs observed
require 'tmpdir'; require 'fileutils'; require 'open3'
CLI = File.expand_path('bin/spm-cache')
Dir.mktmpdir do |dir|
  proj = File.join(dir, 'Fake.xcodeproj')
  FileUtils.mkdir_p(File.join(proj, 'project.xcworkspace/xcshareddata/swiftpm'))
  File.write(File.join(proj, 'project.xcworkspace/xcshareddata/swiftpm/Package.resolved'),
    '{"pins":[{"identity":"Alamofire","kind":"remoteSourceControl","location":"https://github.com/Alamofire/Alamofire.git","state":{"revision":"deadbeef","version":"5.0.0"}}],"version":1}')
  out, err, st = Open3.capture3('bundle', 'exec', 'ruby', '-Ilib', CLI,
    'init', "--project=#{proj}", '--platform=ios', '--default-config=debug')
  # assert st.exitstatus == 0
  # assert File.exist?(File.join(dir, 'spm-cache.yml')) && ...spm-cache.lock && .gitignore includes 'spm-cache/'
end
# For `use` invocations: NO --project flag exists — pass chdir: dir (criterion-1 proof gated on Open Question 1)
```

**What must be faked vs real:** fixture .xcodeproj = plain directory (init only stats/globs it — no xcodeproj-gem parse); Package.resolved = minimal pins JSON (exact fixture from init_spec.rb:22). Xcode toolchain NOT needed. Real CLI subprocess (Open3) preferred over in-process for exit-code fidelity.

### Sampling Rate
- **Per task commit:** `bundle exec rspec spec/init_spec.rb`
- **Per wave merge:** `bundle exec rspec spec/init_spec.rb spec/diff_detector_spec.rb spec/installer_use_fast_path_spec.rb` (adjacent contracts touched by any seed-format fix)
- **Phase gate:** quick set green + CLI smoke proofs recorded with exit codes; full-suite run belongs to the main agent's milestone gate.

### Wave 0 Gaps
- None for pure verification (existing infra covers ONBD-02/03 proofs).
- **Conditional** (only if user approves the seed-format fix in Open Question 1): extend `spec/init_spec.rb` bootstrap example to assert the seeded lock parses under DiffDetector (or matches canonical shape) — one `it` block, pattern available in `spec/diff_detector_spec.rb:54-57`.

## State of the Art

Not applicable — no ecosystem movement relevant to a verification-scoped closure; no deprecated APIs touched. (CLaide option-parsing and RSpec usage are stable, current patterns.)

## Security Domain

`security_enforcement: true`, ASVS level 1 `[VERIFIED: .planning/config.json:47-49]`. Init is local file I/O with no network, auth, or crypto surface.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | none — local CLI |
| V3 Session Management | no | none |
| V4 Access Control | no | none |
| V5 Input Validation | yes | `File.directory?` gate on `--project` (existence, not type/normalization); `interactive?` TTY gate prevents CI stdin hangs; values pass through `YAML.safe_load` on read `[VERIFIED: config.rb:52]` |
| V6 Cryptography | no | none — `--creds` stores a PATH in yml, never secret contents `[VERIFIED: init.rb:100 s3 branch]` |

### Known Threat Patterns for Ruby CLI file-writers

| Pattern | STRIDE | Standard Mitigation (as shipped) |
|---------|--------|------------------|
| Path traversal via `--project` | Tampering | Only mitigation is existence check; user-directed local tool, writes confined to `File.dirname(project_path)` — accepted posture for a dev CLI; no escalation paths (no shell-out in init) |
| Config injection via crafted yml | Tampering/Elevation | `YAML.safe_load` (no arbitrary object deserialization) on every read `[VERIFIED: config.rb:52, syntax/yml.rb:17]` |
| Secret leakage into repo | Info Disclosure | `--creds` value is a file path, not a secret; yml is user-managed |

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `Dir.glob` returns alphabetically-sorted results on MRI ≥3.1 (multiple-.xcodeproj pick order) | Existing Implementation Reference | LOW — the contract is "first match"; order only affects which project wins |
| A2 | CLaide resolves `Command::Init` from `spm_cache/command/init.rb` by naming convention (no explicit registration found in command.rb; empirically `Init.parse` and CLI `init` both work) | Architecture Map | LOW — behavior verified by execution; mechanism inferred |
| A3 | gemspec `required_ruby_version >= 3.1.0` (cited from ROADMAP Phase-1 amendment, not re-read from gemspec this session) | Environment Availability | LOW — does not affect any verification command |

All other claims are `[VERIFIED: <path>]` (read + quoted this session) or `[VERIFIED: executed]` (repro/spec/CLI runs this session).

## Open Questions

1. **Seeded-lock format crash — fix or record? (BLOCKING for criterion 1 sign-off)**
   - What we know: byte-copy seed + empty-skeleton seed both crash `use` at `diff_detector.rb:103`; e2e-verified; canonical transformation exists at `installer.rb:164-193`; CONTEXT locked "do NOT re-implement" but predates this discovery; ROADMAP criterion 1's purpose ("so the first `use` hits the fast path") is unfulfillable as shipped.
   - What's unclear: whether the user wants (a) a minimal surgical fix task in this phase (seed via the canonical shape — small, spec-coverable, no re-implementation of the wizard), or (b) a Phase-2-style "documented deviation / known issue" record closing criterion 1 with the limitation stated.
   - Recommendation: ask the user at plan time (single checkpoint); prepare the plan so either answer is a one-task delta. Under (a), verification then includes an init→use e2e proof; under (b), the crash repro becomes the recorded evidence.
2. **Does ROADMAP criterion 1's "first `use` hits the fast path" need re-wording regardless?**
   - What we know: `fast_path?` requires a materialized proxy (`use.rb:45-51`), so a first run always fully regenerates by design; the seed's real function is lock continuity, not skipping work.
   - Recommendation: amend the criterion wording (à la Phase 2 amendments) to "…seeded from Package.resolved so subsequent `use` runs can take the fast path" — doc-phrasing change within Claude's discretion.
3. **Should CONTEXT.md's two heuristic wording imprecisions (drift #4, #5) be annotated?**
   - What we know: decisions are locked and behavior accepted; only the prose is loose.
   - Recommendation: no CONTEXT edit (locked doc); capture both nuances in the phase SUMMARY's notes so future readers aren't misled. Planner's discretion.

## Sources

### Primary (HIGH confidence)
- `lib/spm_cache/command/init.rb` (full read, raw, lines 1-177) — flag surface, TTY heuristic, merge, seeding, gitignore
- `spec/init_spec.rb` (full raw read + executed: `7 examples, 0 failures`) — fixture pattern, count truth
- `lib/spm_cache/core/config.rb`, `core/lockfile.rb`, `core/syntax/yml.rb`, `core/diff_detector.rb`, `installer.rb`, `installer/use.rb`, `command.rb`, `command/use.rb`, `main.rb`, `bin/spm-cache`, `spec/spec_helper.rb`, `spec/installer_use_fast_path_spec.rb`, `spec/diff_detector_spec.rb` — consumer contracts and wiring
- Executed repros this session: component DiffDetector matrix (seeded/canonical/empty) and e2e `bin/spm-cache init` → `bin/spm-cache use` (TypeError backtrace captured verbatim)
- `git show --stat c51cedc`, `wc -l` — line-count truth (177/105)
- `.planning/03-CONTEXT.md`, `.planning/REQUIREMENTS.md`, `.planning/ROADMAP.md`, `.planning/phases/03-project-bootstrap/SUMMARY.md`, `.planning/config.json`, `.planning/STATE.md`, `CLAUDE.md`

### Secondary (MEDIUM confidence)
- `[CITED: .planning/ROADMAP.md:29]` — gemspec Ruby floor >= 3.1 (not re-read from gemspec)

### Tertiary (LOW confidence)
- None (A1-A3 in Assumptions Log)

## Metadata

**Confidence breakdown:**
- Existing implementation facts: HIGH — every quoted line read raw this session
- Behavioral findings: HIGH — spec run, component repro matrix, and e2e CLI crash all executed this session
- Doc drift catalogue: HIGH — counts verified via `wc -l`, `git show --stat`, `grep -c`, and a live rspec run
- Fix-scope recommendation: MEDIUM — the technical options are certain; the user decision is pending (Open Question 1)

**Research date:** 2026-08-24
**Valid until:** 2026-09-24 (stable local codebase; re-verify only if init.rb/diff_detector.rb change)
