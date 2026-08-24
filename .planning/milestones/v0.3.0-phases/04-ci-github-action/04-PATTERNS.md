# Phase 4: CI GitHub Action - Pattern Map

**Mapped:** 2026-08-24
**Files analyzed:** 4
**Analogs found:** 3 / 4

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `action/action.yml` | config | request-response (composite action) | `action/action.yml` itself (one-line fix at line 55) | self-edit |
| `spec/action_spec.rb` | test | transform (YAML parse + CLI cross-ref) | `spec/doctor_spec.rb` | role-match |
| `.planning/ROADMAP.md` | config (doc) | request-response | `.planning/ROADMAP.md` phases 2–3 amendments | role-match |
| `.planning/codebase/INTEGRATIONS.md` | config (doc) | request-response | `.planning/codebase/INTEGRATIONS.md` line 92 | role-match |

## Pattern Assignments

### `action/action.yml` (config, one-line fix)

**Analog:** self — the file being modified. RESEARCH.md F1 specifies the exact change.

**Fix (line 55):**
```yaml
# BEFORE (defective — --config is the base-command flag, silently ignored by init)
        ARGS="--config=${CONFIG}"

# AFTER (matches init.rb self.options which defines --default-config)
        ARGS="--default-config=${CONFIG}"
```

**Verification reference — gem's actual init options** (`lib/spm_cache/command/init.rb:17-23`):
```ruby
['--project=PATH', 'Path to the .xcodeproj (default: auto-detect in cwd)'],
['--platform=LIST', 'Comma-separated platforms (ios,macos,watchos,tvos)'],
['--default-config=CONFIG', 'Default build config (debug/release)'],
['--remote=BACKEND', 'Remote backend (none/git/s3)'],
['--remote-url=URL', 'Git remote URL or S3 URI'],
['--branch=BRANCH', 'Git remote branch (default: main)'],
['--creds=PATH', 'S3 credentials JSON file path']
```

All other init flags used by the action (`--remote`, `--remote-url`, `--branch`, `--creds`) already match verbatim — only `--config` → `--default-config` is wrong.

---

### `spec/action_spec.rb` (test, transform — YAML parse + CLI cross-ref)

**Analog:** `spec/doctor_spec.rb` (hermetic spec pattern)

**Imports / file header pattern** (doctor_spec.rb lines 1–3):
```ruby
# frozen_string_literal: true

require 'spec_helper'
```

**Describe block structure** (doctor_spec.rb lines 16–17 — uses string context for grouping):
```ruby
RSpec.describe SPMCache::Core::Diagnostics, 'hermetic per-check paths (injected shell collectors)' do
```

For action_spec.rb the subject is not a Ruby class but the YAML file + gem CLI surface. The describe string should mirror:
```ruby
RSpec.describe 'action/action.yml' do
```

**Let block / setup pattern** (doctor_spec.rb lines 21–25):
```ruby
  let(:cache_dir) { SPMCache::Core::Config::CACHE_DIR }
  let(:companion_bin) do
    File.expand_path('tools/spm-cache-proxy/.build/release/spm-cache-proxy', SPMCache::ROOT)
  end
```

For action_spec.rb the equivalent is:
```ruby
  let(:action) { YAML.safe_load_file('action/action.yml', permitted_classes: [], aliases: false) }
```

**Assertion style — collection shape** (doctor_spec.rb lines 18–23):
```ruby
  it 'registers built-in checks' do
    names = described_class.registry.map(&:name)
    expect(names).to include(
      'xcode_version', 'swift_version', 'toolchain_path',
      'cache_dir_health', 'library_evolution_compatibility',
      'remote_backend_connectivity', 'companion_binary'
    )
  end
```

For action_spec.rb: assert input surface, step shape, injection safety, CLI cross-reference. Wave 0 skeleton from RESEARCH.md Code Examples section:
```ruby
RSpec.describe 'action/action.yml' do
  let(:action) { YAML.safe_load_file('action/action.yml', permitted_classes: [], aliases: false) }

  it 'declares the accepted input surface' do
    expect(action.fetch('inputs').keys.sort).to eq %w[backend backend-url branch command config creds].sort
  end

  it 'puts shell on every run step (composite schema rule)' do
    runs = action.dig('runs', 'steps').select { |s| s.key?('run') }
    expect(runs).to all(include('shell'))
  end

  it 'never interpolates inputs directly into run bodies (injection safety)' do
    action.dig('runs', 'steps').each do |s|
      next unless s.key?('run')
      expect(s['run']).not_to include('${{ inputs.')
    end
  end

  it 'passes only flags the gem\'s init actually defines' do
    init_options = File.read('lib/spm_cache/command/init.rb')
    %w[--default-config --remote --remote-url --branch --creds].each do |flag|
      expect(init_options).to include("'#{flag}")
    end
  end
end
```

---

### `.planning/ROADMAP.md` (config/doc, criterion amendments)

**Analog:** ROADMAP.md phases 2–3 inline amendment pattern

**Phase 2 amendment precedent** (ROADMAP.md lines 38, 40-41):
```markdown
1. ... — amended 2026-08-24: plain ✓/!/✗ markers replace ANSI color (user-accepted, terminal-agnostic/pipe-safe; 02-CONTEXT); cache-dir health is count-only (no orphan detection) and remote-backend is config-presence (no network probe), both accepted as shipped (02-01-SUMMARY Documented deviations c/d)
...
3. ... — amended 2026-08-24: "config" is delivered as the Ruby `Core::Diagnostics.register` API ...
4. ... — amended 2026-08-24: delivered mechanism is spec-level injection of stubbed shell-output collectors ...
```

**Phase 3 amendment precedent** (ROADMAP.md lines 54–55):
```markdown
1. ... — amended 2026-08-24: the `--config`-class flag wording is realized as `--default-config` (CLaide base `Command` already defines `--config` for SDK config; 03-CONTEXT); "first `use` hits the fast path" amended to "so subsequent `use` runs can take the fast path" ...
2. ... — amended 2026-08-24: shipped with `--default-config` in place of `--config` and as a superset adding `--project` and `--creds` (03-CONTEXT)
```

**Pattern:** inline `— amended 2026-08-24: <reason> (<source>)` appended to the criterion text. Each amendment is a single inline clause separated by semicolons for multiple items.

**Phase 4 amendments needed** (ROADMAP.md lines 69–71):
- Criterion 1: amend to note input superset (`branch`, `creds` accepted 04-CONTEXT)
- Criterion 2: amend to note `sync` is action-composed (gem has no `remote sync`)
- Criterion 3: amend to record external-deviation (F2 RubyGems unpublished; requires publishing to separate repo)

---

### `.planning/codebase/INTEGRATIONS.md` (config/doc, one-line rewording)

**Analog:** itself — line 92 is the single line to fix

**Current text** (INTEGRATIONS.md line 92):
```markdown
- Wraps the gem: installs via `gem install spm-cache --no-document`, runs `spm-cache init` + `spm-cache remote pull/push/sync`.
```

**Fix:** reword to clarify sync is action-composed, not a gem subcommand:
```markdown
- Wraps the gem: installs via `gem install spm-cache --no-document`, runs `spm-cache init` + `spm-cache remote pull/push`; `sync` is pull+push composed by the action.
```

---

## Shared Patterns

### RSpec file conventions (apply to spec/action_spec.rb)
**Source:** `spec/doctor_spec.rb` lines 1–3
```ruby
# frozen_string_literal: true

require 'spec_helper'
```
All spec files start with `frozen_string_literal`, then `require 'spec_helper'`. No additional requires needed for `action_spec.rb` (YAML is stdlib, File is stdlib).

### ROADMAP amendment format (apply to ROADMAP.md criteria 1–3)
**Source:** ROADMAP.md lines 38, 40–41, 54–55
- Inline `— amended 2026-08-24: <explanation> (<source reference>)`
- Multiple items separated by semicolons within one amendment clause
- Source references use CONTEXT/SUMMARY plan shortnames (e.g., `04-CONTEXT`, `04-01-SUMMARY`)

## No Analog Found

None — all four files have direct analogs or are self-edits.

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| (none) | — | — | — |

## Metadata

**Analog search scope:** `spec/`, `action/`, `.planning/ROADMAP.md`, `.planning/codebase/INTEGRATIONS.md`
**Files scanned:** 4 (doctor_spec.rb, action.yml, ROADMAP.md, INTEGRATIONS.md)
**Pattern extraction date:** 2026-08-24
