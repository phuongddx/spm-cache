# Phase 2: Diagnostics Command - Pattern Map

**Mapped:** 2026-08-24
**Files analyzed:** 6
**Analogs found:** 5 / 6

> **Verification-scoped phase.** The feature is already shipped (commit `5ea68a5`). The files below are the *targets* the plan must prove against or apply small fixes to. No new implementation files; only potential gap-fixes and doc drift corrections.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `tools/spm-cache-proxy/Sources/CLI/Version.swift` (potential) | component (ArgumentParser subcommand) | request-response | `tools/spm-cache-proxy/Sources/CLI/GenProxy.swift` | exact (if created) |
| `lib/spm_cache/core/diagnostics.rb` (potential dead-branch fix) | service (registry) | request-response | `lib/spm_cache/core/diagnostics.rb` (itself) | self-modify |
| `lib/spm_cache/command/doctor.rb` (help-text fix) | controller (CLAide subcommand) | request-response | `lib/spm_cache/command/watch.rb` | exact |
| `spec/doctor_spec.rb` (potential hermetic seam addition) | test | request-response | `spec/doctor_spec.rb` (itself) + `spec/config_spec.rb` | self-modify + conventions |
| `docs/project-roadmap.md` (drift fix) | documentation | — | Phase 1 ROADMAP amendments | pattern-match |
| `.planning/phases/02-diagnostics-command/SUMMARY.md` (line-count fix) | documentation | — | Phase 1 SUMMARY corrections | pattern-match |

## Pattern Assignments

### `tools/spm-cache-proxy/Sources/CLI/Version.swift` (component, request-response — **conditional, decision-routed**)

**Analog:** `tools/spm-cache-proxy/Sources/CLI/GenProxy.swift`

This file may or may not be created — Pitfall 1 in RESEARCH.md identifies the `--version` dead branch in the companion_binary check. The plan must route this: (a) add a `version` subcommand to the Swift proxy, or (b) drop the dead branch on the Ruby side and record a limitation.

**If created, follow this ArgumentParser subcommand pattern:**

**Imports + struct pattern** (GenProxy.swift:1-7):
```swift
import Foundation
import ArgumentParser

struct GenProxy: AsyncParsableCommand, CommandRunning {
    static let configuration = CommandConfiguration(
        commandName: "gen-proxy",
        abstract: "Generate proxy packages from umbrella"
    )
```

**Main entry registration** (CLI.swift:20-25):
```swift
@main
struct CLI: AsyncParsableCommand, CommandRunning {
    static let configuration = CommandConfiguration(
        commandName: "spm-cache-proxy",
        abstract: "Proxy package generator for spm-cache",
        subcommands: [GenUmbrella.self, GenProxy.self, Resolve.self]
    )
}
```

**Key constraints:**
- New subcommand must be appended to the `subcommands` array in `CLI.swift:25`
- Follow `AsyncParsableCommand, CommandRunning` protocol conformance (all existing subcommands do)
- Must be a `struct` (matches project convention — no classes)
- Should print version and exit 0 — synchronous, no async needed (can be `ParsableCommand` instead of `AsyncParsableCommand` if preferred, but all existing subcommands use `AsyncParsableCommand`)

---

### `lib/spm_cache/core/diagnostics.rb` (potential dead-branch fix — **self-modify**)

**Analog:** Itself — the companion_binary check block (lines 141-153 approximately).

**Current companion_binary check pattern** (diagnostics.rb:141-153, structure from RESEARCH.md Pattern 2):
```ruby
register('companion_binary', fix_hint: 'Run `make proxy.build` to build the Swift companion binary') do |config:|
  bin = File.expand_path('tools/spm-cache-proxy/.build/release/spm-cache-proxy', ROOT)
  if File.executable?(bin)
    out = Sh.capture_output("#{bin} --version 2>/dev/null").strip  # DEAD BRANCH
    msg = "Companion binary present at #{bin}"
    msg += " (#{out})" unless out.empty?
    [:ok, msg]
  else
    [:warn, 'Companion binary not found — proxy generation specs will skip']
  end
end
```

**Pattern for dead-branch removal** (if routed to option (a) — minimal Ruby-side fix):
- Remove the `Sh.capture_output("#{bin} --version 2>/dev/null")` call and the `msg += " (#{out})"` line
- Keep the `File.executable?` presence check and both branches intact
- Update the check's conceptual documentation to "presence-only"

**Anti-pattern:** Do NOT introduce a second shell seam or interpolate config values into `Sh` commands (RESEARCH.md anti-patterns).

---

### `lib/spm_cache/command/doctor.rb` (help-text fix — **2-line edit**)

**Analog:** `lib/spm_cache/command/watch.rb` (CLAide command conventions)

**Current help-text that needs fixing** (doctor.rb:14,17):
```ruby
self.summary = 'Run environment diagnostics'
self.description = 'Checks the Xcode/Swift toolchain, cache-dir health, remote-backend config, and the Swift companion binary. Prints a green/yellow/red report. Use --json for machine-readable output (CI).'
```

**`--json` option description** (doctor.rb:19):
```ruby
['--json', 'Emit diagnostics as JSON instead of a color-coded report']
```

**CLAide command conventions** (from watch.rb, the closest sibling):
```ruby
# frozen_string_literal: true

require 'spm_cache/command'
require 'spm_cache/core/watcher'

module SPMCache
  class Command
    class Watch < Command
      include BaseOptions

      self.summary = 'Watch the Xcode project and auto-regenerate the cache proxy'
      self.description = 'Monitors Package.resolved and project.pbxproj for changes and re-runs the spm-cache integration automatically. Use --once for a single sync (CI/testing).'

      def self.options
        [
          ['--once', 'Run a single sync and exit (no watch loop)'],
          ['--debounce=SECONDS', 'Seconds between detecting a change and regenerating (default: 2)']
        ].concat(super)
      end
```

**Fix pattern:** Replace "green/yellow/red report" / "color-coded report" with terminal-agnostic wording. Mirror the concise factual style of `watch.rb`'s description. The `# frozen_string_literal: true` header and `require` block pattern (doctor.rb:1-7) must remain unchanged.

---

### `spec/doctor_spec.rb` (potential hermetic seam addition — **self-modify**)

**Analog:** Itself (existing 4 doctor examples) + `spec/config_spec.rb` (RSpec conventions)

**Existing spec structure and conventions** (doctor.rb:1-69, full file in context):
```ruby
# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'spm_cache/core/diagnostics'

RSpec.describe SPMCache::Core::Diagnostics do
  it 'registers built-in checks' do
    names = described_class.registry.map(&:name)
    expect(names).to include(
      'xcode_version', 'swift_version', 'toolchain_path',
      'cache_dir_health', 'library_evolution_compatibility',
      'remote_backend_connectivity', 'companion_binary'
    )
  end
  # ... 2 more registry examples ...
end

RSpec.describe 'spm-cache doctor --json' do
  it 'emits valid JSON with checks and summary' do
    # ... StringIO stdout capture + exit stub pattern ...
  end
end
```

**Existing spec conventions** (from config_spec.rb:1-8):
```ruby
# frozen_string_literal: true

require "spec_helper"

RSpec.describe SPMCache::Core::Config do
  subject(:config) { described_class.instance }

  before do
    config.reset!
    config.project_dir = "/tmp/test-project"
  end
```

**Key patterns if adding hermetic specs:**
- `# frozen_string_literal: true` header on every spec file
- `require 'spec_helper'` as first require (brings in 3 inline SPMCache examples)
- `subject(:...)` for test subjects (see config_spec.rb:5)
- `before { ... }` for setup (see config_spec.rb:7-9)
- Exit stub pattern: `allow_any_instance_of(SPMCache::Command::Doctor).to receive(:exit).and_return(nil)` (doctor_spec.rb:58)
- Stdout capture: `StringIO` swap of `$stdout` with `ensure` restore (doctor_spec.rb:52-63)
- Registry isolation for tests that add temporary checks: save/restore `@registry` via `instance_variable_set` (doctor_spec.rb:27-36)

**Anti-pattern:** Do NOT use `allow(Sh).to receive(...)` without first confirming `Sh` methods are stubbable (they are module-level class methods — `allow(SPMCache::Core::Sh).to receive(:capture_output)` should work, but verify before committing).

---

### `docs/project-roadmap.md` (drift fix — line 63)

**Analog:** Phase 1 ROADMAP amendments (01-VERIFICATION.md truth 7, SUMMARY corrections)

**Current stale text** (project-roadmap.md:63):
```markdown
- [ ] `spm-cache doctor` command (diagnose environment, toolchain)
```

**Phase 1 ROADMAP amendment pattern:** In Phase 1, ROADMAP SC 2 was rewritten to match delivered reality, and the justification was cross-recorded in PLAN.md, SUMMARY.md, and ROADMAP.md. The fix is a one-line change: mark the item as delivered `[x]` or remove the unchecked line.

**Also:** ROADMAP.md line 36 criterion 3 says "addable/removable via config" — the shipped mechanism uses the Ruby `register` API (yml config explicitly rejected). This is a wording drift, not a code gap. Phase 1 pattern: record as accepted interpretation, don't silently change ROADMAP wording without cross-recording.

---

### `.planning/phases/02-diagnostics-command/SUMMARY.md` (line-count fix)

**Analog:** Phase 1 SUMMARY corrections (01-VERIFICATION.md truth 7)

**Current stale claims** (SUMMARY.md:7-9):
```markdown
- `lib/spm_cache/core/diagnostics.rb` (139 lines) — ...
- `lib/spm_cache/command/doctor.rb` (78 lines) — ...
- `spec/doctor_spec.rb` (69 lines) — 7 specs, all passing.
```

**Actual line counts** (verified by RESEARCH.md `wc -l`): diagnostics.rb = 156, doctor.rb = 82, doctor_spec.rb = 69 (correct).

**"7 specs" provenance** (RESEARCH.md Pitfall 3): 4 doctor examples + 3 spec_helper inline examples = 7 total. The SUMMARY should clarify this if it references spec count.

**Phase 1 correction pattern:** SUMMARY line counts were corrected in-place during Phase 1 gap closure (01-VERIFICATION.md truth 7). Same approach: update numbers to match reality.

## Shared Patterns

### CLAide Command Structure
**Source:** `lib/spm_cache/command/watch.rb` + `lib/spm_cache/command/doctor.rb`
**Apply to:** Any modification to `doctor.rb`
```ruby
# frozen_string_literal: true

require 'spm_cache/command'
require 'spm_cache/core/<module>'

module SPMCache
  class Command
    class SubcommandName < Command
      self.summary = '...'
      self.description = '...'

      def self.options
        [['--flag', 'description']].concat(super)
      end

      def initialize(argv)
        super
        @flag = argv.flag?('flag', false)
      end

      def run
        # ...
      end
    end
  end
end
```

### RSpec File Conventions
**Source:** `spec/doctor_spec.rb`, `spec/config_spec.rb`, `spec/spec_helper.rb`
**Apply to:** Any new or modified specs
```ruby
# frozen_string_literal: true

require 'spec_helper'
# additional requires as needed

RSpec.describe SPMCache::Namespace do
  # subject(:var) { described_class.method }  # when useful
  # before { ... }                          # when setup needed

  it 'description' do
    expect(actual).to eq(expected)
  end
end
```

### Doc Drift Amendment (Phase 1 established pattern)
**Source:** Phase 1 ROADMAP SC 2 rewrite + SUMMARY line-count corrections
**Apply to:** `docs/project-roadmap.md:63`, `SUMMARY.md:7-9`, ROADMAP.md:34-37
- Phase 1 crossed ROADMAP wording with PLAN.md and SUMMARY.md; corrections were in-place with justification
- ROADMAP criterion wording drifts are recorded as "accepted interpretation" with cross-references, not silently changed
- SUMMARY line counts corrected to match `wc -l` reality

### Shell-Out Seam
**Source:** `lib/spm_cache/core/sh.rb` (used by all checks)
**Apply to:** Any gap-fix that touches check internals
- All shell-outs go through `Core::Sh.capture_output(command)` — never raw `Open3` or backticks
- `Sh` raises `Core::GeneralError` on non-zero exit — checks that call it must rescue or accept the `run_check` rescue-to-fail safety net
- String commands execute via the shell (embedded `2>/dev/null` works)

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| N/A | — | — | All files have direct analogs. This is a verification-scoped phase modifying existing files; the shipped code IS the analog. |

## Metadata

**Analog search scope:** `lib/spm_cache/command/`, `lib/spm_cache/core/`, `spec/`, `tools/spm-cache-proxy/Sources/CLI/`, `docs/`, `.planning/phases/01-test-ci-foundation/`
**Files scanned:** 12
**Pattern extraction date:** 2026-08-24