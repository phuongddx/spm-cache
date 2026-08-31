# Phase 11: Homebrew Release Automation - Pattern Map

**Mapped:** 2026-08-29
**Files analyzed:** 4 (1 rewritten workflow, 1 modified lib file, 2 new specs)
**Analogs found:** 4 / 4 (3 with strong in-repo analogs; 1 analog is the file's own current shape + `ci.yml` conventions)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `.github/workflows/update-tap.yml` (rewrite) | config (CI workflow) | event-driven | itself (current shape) + `.github/workflows/ci.yml` | role-match |
| `lib/spm_cache/main.rb` (modify, +1 intercept line) | route (CLI entry/bootstrap) | request-response (argv → stdout) | itself (`main.rb` lines 8-12) | exact (in-place extension) |
| `spec/update_tap_workflow_spec.rb` (new) | test (structural YAML) | file-I/O (parse + assert) | `spec/action_spec.rb` | exact |
| `spec/main_version_spec.rb` (new) | test (unit, stdout capture) | file-I/O (in-process call + stdout) | `spec/core_spec.rb` lines 42-51 | role-match |

## Pattern Assignments

### `.github/workflows/update-tap.yml` (config, event-driven) — REWRITE

**Analog A:** `.github/workflows/update-tap.yml` itself (rewrite in place — preserve trigger shape, step `id:`/`$GITHUB_OUTPUT` conventions, git identity block; replace every failure site).

**Keep from current file** — trigger map (lines 3-5) gains `workflow_dispatch` but keeps the `release` block:

```yaml
on:
  release:
    types: [published]
```

Step-id + output convention to keep (lines 13-15):

```yaml
      - name: Get version from release
        id: version
        run: echo "VERSION=${GITHUB_REF_NAME#v}" >> $GITHUB_OUTPUT
```

Git identity block to keep verbatim (lines 46-48):

```bash
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
```

**Failure sites the rewrite must remove** (line-anchored, from the current file):

| Line | Failure mode | REL |
|------|--------------|-----|
| 21 | `curl -L` (no `-f`, no `--retry`) — hashes error pages | REL-05 |
| 29 | `token: ${{ secrets.TAP_REPO_TOKEN }}` — dead classic PAT | REL-04 |
| 38-40 | three unanchored `sed` calls; the `version` one (line 40) is a live zero-match no-op (tap formula has no `version` stanza) | REL-07 |
| 50 | `git commit ... || exit 0` — converts commit/push failure into a green run | REL-06 |

**Analog B:** `.github/workflows/ci.yml` — the repo's workflow-convention source.

**Top-level hygiene blocks to copy** (ci.yml lines 8-13) — note `cancel-in-progress` flips to `false` for this workflow (queue, never cancel — RESEARCH Pitfall 7):

```yaml
concurrency:
  group: ci-${{ github.ref }}   # adapt to: group: update-tap
  cancel-in-progress: true      # adapt to: false (two releases must queue, not race)

permissions:
  contents: read
```

**Runner + action pinning convention** (ci.yml line 24, update-tap.yml line 11):

```yaml
      - uses: actions/checkout@v5
```

Convention from CONTEXT ("Established Patterns"): `actions/checkout@v5`; ubuntu-latest unless macOS is required (keep `update-tap` on ubuntu — GNU sed; `verify-publish` on macOS). ci.yml also demonstrates the macOS-pin alternative (`runs-on: macos-15`, lines 18/44) if the operator pivots from `macos-latest`.

**No codebase analog for the new machinery** (token minting, dispatch input, integrity gate, brew verify) — copy verbatim from `11-RESEARCH.md` Patterns 1-5 and "Code Examples" (vendor-verified this session). See "No Analog Found" below.

---

### `lib/spm_cache/main.rb` (route, request-response) — MODIFY

**Analog:** itself. The intercept slots between the two existing lines of `self.run` (lines 8-12):

```ruby
    def self.run(argv)
      # Ensure all lib files are loaded
      SPMCache::Main.load_all
      Command.run(argv)
    end
```

Target shape (RESEARCH Pattern 6, proven working locally this session — prints `0.3.0`, exit 0):

```ruby
    def self.run(argv)
      # Ensure all lib files are loaded
      SPMCache::Main.load_all
      return puts(SPMCache::VERSION) if argv.first == "--version"  # before default_subcommand routing
      Command.run(argv)
    end
```

Placement is load-bearing: CLAide's `Command.parse` routes a bare `--version` through `default_subcommand` (`use`), whose options lack the root-only `--version` flag — so the intercept MUST precede `Command.run`. `SPMCache::VERSION` is a String read from the shipped `VERSION` file (`lib/spm_cache/version.rb` line 4):

```ruby
  VERSION = File.read(File.expand_path("../../VERSION", __dir__)).strip
```

Keep `# frozen_string_literal: true` (line 1), the `load_all` method (lines 14-20), and the trailing auto-require (line 25) untouched.

---

### `spec/update_tap_workflow_spec.rb` (test, file-I/O) — NEW

**Analog:** `spec/action_spec.rb` — the repo's 11-example structural-YAML spec precedent. Copy its five idioms:

**Spec header + purpose comment** (lines 1-12) — `frozen_string_literal`, `require 'spec_helper'`, a block comment tying each slice to the phase requirement it guards, then `RSpec.describe` with a file-path string:

```ruby
# frozen_string_literal: true

require 'spec_helper'

# Wave 0 local proofs for the composite Action (04-VALIDATION): parse
# action/action.yml with strict Psych and cross-reference every shell-out
# flag against the gem command file that defines it. ...
RSpec.describe 'action/action.yml' do
```

New spec names `'.github/workflows/update-tap.yml'` the same way.

**Strict YAML load** (line 13) — exact call, new path:

```ruby
  let(:action) { YAML.safe_load_file('action/action.yml', permitted_classes: [], aliases: false) }
```

**DIVERGENCE — the Psych `on:` gotcha:** `action/action.yml` has no `on:` key, but a workflow file does, and Psych parses the unquoted `on:` key as boolean `true` (verified on Ruby 3.2.3 / Psych 5.0.1: `keys => ["name", true, "jobs"]`). The new spec must reach triggers via:

```ruby
  let(:workflow) { YAML.safe_load_file('.github/workflows/update-tap.yml', permitted_classes: [], aliases: false) }
  let(:triggers) { workflow[true] }  # NOT workflow['on'] — that returns nil under Psych
```

**Derived slicing lets** (lines 14-17) — walk steps once in a `let`, select by key, find by body substring (port directly to jobs/steps of the workflow):

```ruby
  let(:steps) { action.dig('runs', 'steps') }
  let(:run_steps) { steps.select { |s| s.key?('run') } }
  let(:init_step) { run_steps.find { |s| s['run'].include?('spm-cache init') } }
```

**Loud-failure slicing guards** (lines 25-28, also 45-46 and 112-113) — when a spec's own slicing depends on a marker being present, `raise` naming the file instead of silently degrading (mirrors this phase's loud-failure philosophy):

```ruby
    src = File.read(path)
    start_idx = src.index('def self.options') or
      raise "#{path} defines no own options block — update the cross-reference source list"
```

**Injection guard — port verbatim, near-identical** (lines 77-83), extended to also ban `github.event.` per RESEARCH SC-injection row:

```ruby
  it 'never expands GitHub input contexts inside run script bodies' do
    run_steps.each do |s|
      msg = "step '#{s['name']}' expands an inputs context inside the script body " \
            '(injection surface, RESEARCH Pattern 1)'
      expect(s['run']).not_to match(/\$\{\{\s*inputs\./), msg
    end
  end
```

**Dual assertion style** (RESEARCH Pattern 7): YAML-walking for structure (jobs, `runs-on`, `needs:`, `uses:`, trigger map via `workflow[true]`), raw-text regex for shell-body properties — the precedent combines both: `YAML.safe_load_file` at action_spec.rb:13 and `File.read('action/README.md')` at line 45:

```ruby
    section = File.read('action/README.md')[/## Inputs\n(.*?)\n## /m, 1] or
      raise 'action/README.md "## Inputs" section lacks a terminating "## " heading — parity slice broken'
```

So REL-05/06/07 assertions (`curl -fL`, no `|| exit 0`, `grep -c` / `-ne 1`, `1f8b`) match on `File.read('.github/workflows/update-tap.yml')` text; REL-04/08/09 structure (token step, `needs:`, `runs-on: macos*`, dispatch input) walks the parsed tree.

**Custom failure messages** (line 60 and lines 95-98) — every non-obvious expectation carries a message explaining the phase rationale:

```ruby
      run_steps.each { |s| expect(s).to include('shell'), "step '#{s['name']}' has run but no shell" }
```

**Env-routing cross-reference** (lines 85-90) — reusable shape for asserting the workflow routes `${{ inputs.tag }}` / secrets through `env:` only:

```ruby
  it 'routes every declared input through step env assignments' do
    referenced = steps.flat_map { |s| (s['env'] || {}).values }
                      .map { |v| v.to_s[/\$\{\{ inputs\.(\S+) \}\}/, 1] }
                      .compact.uniq.sort
    expect(referenced).to eq(action.fetch('inputs').keys.sort)
  end
```

---

### `spec/main_version_spec.rb` (test, unit stdout capture) — NEW

**Analog:** `spec/core_spec.rb` — the repo's idiom for asserting what a class method prints.

**Header** (lines 1-3): `# frozen_string_literal: true` + `require "spec_helper"`. Note `spec/spec_helper.rb` line 3 already does `require "spm_cache/main"` — the new spec needs only `require "spec_helper"` to reach `SPMCache::Main`.

**Class-method describe shape** (lines 42-47) — describe the module, nest a string `".method"` block:

```ruby
RSpec.describe SPMCache::Core::UI do
  describe ".info" do
    it "prints message to stdout" do
      expect { described_class.info("test message") }.to output("test message\n").to_stdout
    end
  end
end
```

**The exact assertion idiom to port** (line 45) — `expect { }.to output(...).to_stdout`, which is what RESEARCH's validation section prescribes for the intercept:

```ruby
RSpec.describe SPMCache::Main do
  describe ".run" do
    it "prints the gem version for --version" do
      expect { described_class.run(["--version"]) }.to output("#{SPMCache::VERSION}\n").to_stdout
    end
  end
end
```

Whole-string compare with trailing `\n` is correct: the intercept `puts`es `SPMCache::VERSION` directly, and CLAide's `print_version` format is exactly the bare version string.

**Explanatory comment convention** (core_spec.rb lines 24-29) — precede non-obvious examples with a comment stating the field bug being guarded (here: CLAide `default_subcommand` routing rejects root-only `--version`).

---

## Shared Patterns

### Ruby file header
**Source:** every `lib/` and `spec/` file (e.g., `spec/action_spec.rb:1-3`, `lib/spm_cache/main.rb:1-4`)
**Apply to:** both new spec files (and any touched lib file keeps it)

```ruby
# frozen_string_literal: true

require "spec_helper"
```

### Structural-spec = strict YAML walk + raw-text regex (dual style)
**Source:** `spec/action_spec.rb:13` (`YAML.safe_load_file('action/action.yml', permitted_classes: [], aliases: false)`) and `:45` (`File.read('action/README.md')[...]`)
**Apply to:** `spec/update_tap_workflow_spec.rb` — structure via parsed tree, shell-body properties via `File.read` + `include`/`match`. Plus the workflow-only `on:` → `true` key handling.

### Injection guard (no context expansion inside `run:` bodies)
**Source:** `spec/action_spec.rb:77-83`
**Apply to:** `spec/update_tap_workflow_spec.rb` — port verbatim, extend the regex to `${{ github.event.`; every dynamic value in the workflow reaches `run:` via `env:`.

### Loud-failure spec slicing (`or raise`)
**Source:** `spec/action_spec.rb:25-28, 45-46, 112-113`
**Apply to:** any `let`/helper in the new spec that slices on a structural marker (e.g., locating the edit step by name) — raise naming the file rather than asserting against `nil`.

### Workflow hygiene conventions
**Source:** `.github/workflows/ci.yml:8-13` (`concurrency`, `permissions: contents: read`), `:24` (`actions/checkout@v5`); CONTEXT "Established Patterns"
**Apply to:** rewritten `update-tap.yml` — add both blocks at top level; `cancel-in-progress: false` here (queue, don't race); `permissions: contents: read` (the app token's power comes from its installation, not GITHUB_TOKEN); ubuntu for the edit job, macOS only for verify.

### VERSION access
**Source:** `lib/spm_cache/version.rb:4`
**Apply to:** `lib/spm_cache/main.rb` intercept and `spec/main_version_spec.rb` expected-output interpolation — always `SPMCache::VERSION` (never hardcode; the `VERSION` file is the single source of truth and is shipped by the gemspec).

## No Analog Found

In-repo analogs cover file shape and spec idioms; the following workflow content is new to this codebase — the planner should copy the RESEARCH-cited verbatim blocks instead of searching for precedents:

| Pattern | Reason no analog | Source to copy |
|---------|------------------|----------------|
| GitHub App token minting (`actions/create-github-app-token@v3` → `checkout(token:)`) | No workflow in the repo mints tokens (only the dead PAT at update-tap.yml:29) | RESEARCH Pattern 1 (vendor README verified) |
| `workflow_dispatch` trigger with `tag` input | No existing workflow uses dispatch | RESEARCH Pattern 5 + Code Examples trigger block |
| Tarball integrity gate (`curl -fL --retry`, `test -s`, `od` gzip `1f8b` magic) | Current step (update-tap.yml:17-23) has none of it | RESEARCH Pattern 4 |
| Anchored sed + `grep -c`==1 + `grep -Fqx` postconditions | Current seds (update-tap.yml:38-40) are unanchored and unpostconditioned | RESEARCH Pattern 2 |
| Explicit no-diff / `set -euo pipefail` publish block | Current `|| exit 0` (update-tap.yml:50) is the anti-pattern | RESEARCH Pattern 3 |
| macOS brew-install verify job (`HOMEBREW_NO_AUTO_UPDATE`, `brew install user/repo/formula`, version assert) | ci.yml's macOS jobs use setup-xcode + bundler, never brew | RESEARCH "Code Examples — Complete verify job" |

## Metadata

**Analog search scope:** `spec/` (49 spec files listed — only `action_spec.rb` does structural YAML; no workflow specs exist), `.github/workflows/` (2 files: `ci.yml`, `update-tap.yml`), `lib/spm_cache/` root (`main.rb`, `version.rb`, `command.rb` via RESEARCH), `spec/spec_helper.rb`
**Files scanned:** ~55 (spec dir listing + 2 workflows + 3 lib files read in full)
**Pattern extraction date:** 2026-08-29
