# Phase 3: Project Bootstrap - Pattern Map

**Mapped:** 2026-08-24
**Files analyzed:** 7
**Analogs found:** 6 / 7

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `lib/spm_cache/command/init.rb` (seed_lockfile fix, conditional) | command | file-I/O | `lib/spm_cache/installer.rb` (canonical lock generation) | data-flow-match |
| `spec/init_spec.rb` (extend bootstrap example, conditional) | test | file-I/O verification | `spec/diff_detector_spec.rb:54-62` (canonical lock fixture + consumer) | role-match |
| `spec/init_spec.rb` (new CLI smoke examples, if any) | test | request-response verification | `spec/init_spec.rb` (existing 4 examples) | exact |
| `.planning/phases/03-project-bootstrap/SUMMARY.md` | config/doc | transform | `.planning/phases/02-diagnostics-command/SUMMARY.md` | exact |
| `.planning/ROADMAP.md` (Phase-3 criteria amendments) | config/doc | transform | `.planning/ROADMAP.md` (Phase-2 amendment pattern, lines 38-41) | exact |
| `docs/project-roadmap.md` (v0.3.0 init item check, if needed) | config/doc | transform | Phase 2 plan's `docs/project-roadmap.md` artifact | role-match |
| CLI smoke proof scripts (inline in plan, no committed file) | utility/proof | request-response | `spec/init_spec.rb:22-33` (fixture setup) + RESEARCH CLI skeleton | role-match |

## Pattern Assignments

### `lib/spm_cache/command/init.rb` — seed_lockfile method (command, file-I/O)

**Analog:** `lib/spm_cache/installer.rb` lines 165-191

This is the **conditional** file — only touched if the user approves the seed-format fix (Open Question 1 from RESEARCH.md). The transformation from Xcode pins format to canonical lock shape already exists here.

**Canonical lock shape** (installer.rb:176-188):
```ruby
lockfile_data = {
  File.basename(@project_path) => {
    "packages" => pins.map do |pin|
      {
        "repositoryURL" => pin["location"],
        "name" => pin["identity"],
        "version" => pin.dig("state", "version"),
        "revision" => pin.dig("state", "revision"),
      }
    end,
    "dependencies" => {},
    "platforms" => detect_platforms,
  }
}
File.write(lockfile_path, JSON.pretty_generate(lockfile_data))
```

**Current init.rb seed_lockfile** (init.rb:143-161) — the defect site:
```ruby
def seed_lockfile(project_path)
  resolved = find_package_resolved(project_path)
  lockfile_path = File.join(File.dirname(project_path), Core::Config::LOCKFILE_FILENAME)

  if resolved && File.exist?(resolved)
    FileUtils.cp(resolved, lockfile_path)  # BUG: byte-copies pins format
    Core::UI.info "Seeded #{Core::Config::LOCKFILE_FILENAME} from #{resolved}."
  else
    File.write(lockfile_path, "{\"projects\":[]}\n")  # BUG: empty-skeleton also crashes DiffDetector
    Core::UI.info "Created empty #{Core::Config::LOCKFILE_FILENAME} (run `spm-cache use` after resolving deps)."
  end
end
```

**Fix approach:** Replace `FileUtils.cp` with the pins→packages transformation from installer.rb. The `detect_platforms` call cannot be reused (it opens the xcodeproj via the gem; init's contract is pure file I/O). Instead, extract platforms from the CLI `--platform` flag (already resolved by the time `seed_lockfile` runs) or write an empty `{}`. The empty-skeleton path must also write canonical shape (empty packages array under the project key).

**Consumer contract** (diff_detector.rb:101-104) — what the output must satisfy:
```ruby
data = JSON.parse(content)
data.each_value do |proj_data|
  (proj_data['packages'] || []).each do |pkg|
    key = identity_key(pkg['repositoryURL'], pkg['path_from_root'] || pkg['path'], pkg['name'])
    result[key] = { 'name' => pkg['name'], 'repositoryURL' => pkg['repositoryURL'], ... }
  end
end
```

---

### `spec/init_spec.rb` — extending the bootstrap example (test, file-I/O verification)

**Analog:** `spec/diff_detector_spec.rb:54-62` (write_lockfile fixture helper)

If the seed-format fix lands, the existing bootstrap `it` block needs an assertion that the seeded lock is consumable by DiffDetector.

**Canonical lock fixture helper pattern** (diff_detector_spec.rb:57-65):
```ruby
def write_lockfile(packages, project_name = 'Fake.xcodeproj')
  File.write(lockfile_path, JSON.generate(
    project_name => {
      'packages' => packages,
      'dependencies' => {},
      'platforms' => { 'ios' => '16.0' }
    }
  ))
end
```

**Existing init_spec bootstrap example** (init_spec.rb:40-62) — where the new assertion goes:
```ruby
it 'generates spm-cache.yml + seeded lockfile + .gitignore entry (non-interactive)' do
  cmd = parse_init(["--project=#{project_path}",
                    '--platform=ios,macos',
                    '--default-config=debug',
                    '--remote=none'])
  config = SPMCache::Core::Config.instance
  config.reset!
  cmd.run

  yml_path = File.join(tmpdir, 'spm-cache.yml')
  lock_path = File.join(tmpdir, 'spm-cache.lock')
  gitignore_path = File.join(tmpdir, '.gitignore')

  expect(File.exist?(yml_path)).to be true
  expect(File.exist?(lock_path)).to be true
  expect(File.exist?(gitignore_path)).to be true

  parsed = YAML.safe_load(File.read(yml_path))
  expect(parsed['platforms']).to eq(%w[ios macos])
  expect(parsed['default_config']).to eq('debug')

  lock = File.read(lock_path)
  expect(lock).to include('Alamofire')

  expect(File.read(gitignore_path)).to include('spm-cache/')
end
```

**Fixture setup pattern** (init_spec.rb:17-33) — reuse for any new test:
```ruby
before do
  FileUtils.mkdir_p(project_path)
  FileUtils.mkdir_p(File.join(project_path, 'project.xcworkspace', 'xcshareddata', 'swiftpm'))
  File.write(File.join(project_path, 'project.xcworkspace', 'xcshareddata', 'swiftpm', 'Package.resolved'),
             '{"pins":[{"identity":"Alamofire","kind":"remoteSourceControl","location":"https://github.com/Alamofire/Alamofire.git","state":{"revision":"deadbeef","version":"5.0.0"}}],"version":1}')
end
after { FileUtils.remove_entry(tmpdir) if File.directory?(tmpdir) }
```

**Singleton hygiene pattern** (init_spec.rb:35-37) — MUST precede every `cmd.run`:
```ruby
config = SPMCache::Core::Config.instance
config.reset!
```

---

### `.planning/phases/03-project-bootstrap/SUMMARY.md` (config/doc, transform)

**Analog:** `.planning/phases/02-diagnostics-command/SUMMARY.md`

**Doc-closure pattern** — Phase 2 SUMMARY structure to copy:
```markdown
# Phase 3 Summary — Project Bootstrap

**Requirement:** ONBD-01, ONBD-02, ONBD-03
**Status:** Complete

## Deliverables
- `lib/spm_cache/command/init.rb` (177 lines) — [accurate description]
- `spec/init_spec.rb` (105 lines) — 4 specs (+3 shared helper examples = 7 total) covering [list]. All passing.

## Documented deviations (user-accepted / accepted-as-shipped)

All dated 2026-08-24. Sources: 03-CONTEXT.md (user decisions), RESEARCH.md.

- **(a) `--default-config` replaces ROADMAP's `--config`** — CLaide base `Command` already defines `--config` (SDK config) at command.rb:19; the rename avoids the collision. User-accepted 2026-08-24.
- **(b) ROADMAP criterion 2 flag list incomplete** — shipped superset adds `--project` and `--creds` beyond the 5 ROADMAP-listed flags.
- **(c) Seeded lock format crash** — [if fix approved: "Fixed: seeded lock now written in canonical shape" / if recorded: "Recorded as known issue: byte-copy seed crashes `use` at diff_detector.rb:103"]
- **(d) ROADMAP criterion 1 'first use fast path' overstates** — `fast_path?` requires a materialized proxy (use.rb:45-51); a first run always fully regenerates by design. The seed's value is lock continuity for *subsequent* runs. Criterion wording amended.

## Verification
- [evidence per criterion]

## Commits
- `c51cedc` feat: add spm-cache init wizard (ONBD-01/02/03)
```

---

### `.planning/ROADMAP.md` — Phase 3 criteria amendments (config/doc, transform)

**Analog:** `.planning/ROADMAP.md` lines 38-41 (Phase 2 amendment inline pattern)

**ROADMAP amendment pattern** — append `— amended YYYY-MM-DD: [rationale]` to the criterion text:
```markdown
1. `spm-cache init` detects `.xcodeproj`, prompts for platforms/config/remote-backend, and generates `spm-cache.yml` + a `spm-cache.lock` seeded from `Package.resolved` so the first `use` hits the fast path — amended 2026-08-24: `--config` renamed to `--default-config` (CLaide base collision; 03-CONTEXT); "first `use` fast path" amended to "so subsequent `use` runs can take the fast path" (proxy must be materialized first by design); [conditional: seeded-lock format fixed to canonical shape]
2. Non-interactive flags (`--platform`, `--config`, `--remote`, `--remote-url`, `--branch`) work for scripting/CI — amended 2026-08-24: `--config` shipped as `--default-config`; superset adds `--project`, `--creds` (03-CONTEXT)
```

---

### CLI smoke proof scripts (utility, request-response)

**Analog:** RESEARCH.md "CLI smoke proof skeleton" + `spec/init_spec.rb:17-33` (fixture)

**Fixture setup for CLI subprocess proofs** (from RESEARCH, executed this session):
```ruby
require 'tmpdir'; require 'fileutils'; require 'open3'
CLI = File.expand_path('bin/spm-cache')
Dir.mktmpdir do |dir|
  proj = File.join(dir, 'Fake.xcodeproj')
  FileUtils.mkdir_p(File.join(proj, 'project.xcworkspace/xcshareddata/swiftpm'))
  File.write(File.join(proj, 'project.xcworkspace/xcshareddata/swiftpm/Package.resolved'),
    '{"pins":[{"identity":"Alamofire","kind":"remoteSourceControl","location":"https://github.com/Alamofire/Alamofire.git","state":{"revision":"deadbeef","version":"5.0.0"}}],"version":1}')
  out, err, st = Open3.capture3('bundle', 'exec', 'ruby', '-Ilib', CLI,
    'init', "--project=#{proj}", '--platform=ios', '--default-config=debug')
  # st.exitstatus == 0
  # File.exist?(File.join(dir, 'spm-cache.yml'))
  # File.exist?(File.join(dir, 'spm-cache.lock'))
  # File.read(File.join(dir, '.gitignore')).include?('spm-cache/')
end
```

**Key constraints for CLI proofs** (from RESEARCH Pitfalls 4-7):
- Use absolute `--project` paths (tmpdir from `Dir.mktmpdir`)
- One .xcodeproj per tmpdir
- `use` has no `--project` flag — cwd must be the project dir
- Bogus `--project` silently falls back to auto-detect; no-.xcodeproj proofs need empty tmpdir

---

## Shared Patterns

### Config Singleton Hygiene
**Source:** `spec/init_spec.rb:35-37`
**Apply to:** Any in-process verification invoking `Command::Init#run`
```ruby
SPMCache::Core::Config.instance.reset!
```
Must precede every `cmd.run` — `Main.load_all` (auto-required by spec_helper) can leave Config pointed at the real cwd.

### Error-Raising Contract
**Source:** `lib/spm_cache/command/init.rb:41-43`
**Apply to:** Any verification of the no-.xcodeproj error path
```ruby
raise Core::GeneralError,
      'No .xcodeproj found — pass --project or run inside an Xcode project directory'
```
Spec expects: `raise_error(SPMCache::Core::GeneralError, /No \.xcodeproj found/)`

### Canonical Lockfile Shape
**Source:** `spec/diff_detector_spec.rb:57-65` and `spec/installer_use_fast_path_spec.rb:30-38`
**Apply to:** Any fixture writing a lockfile for DiffDetector consumption
```ruby
JSON.generate(
  'ProjectName.xcodeproj' => {
    'packages' => [{ 'repositoryURL' => '...', 'name' => '...', 'version' => '...', 'revision' => '...' }],
    'dependencies' => {},
    'platforms' => { 'ios' => '16.0' }
  }
)
```

### Non-Interactive Forcing
**Source:** `spec/init_spec.rb` (all examples pass `--platform` and/or `--remote`)
**Apply to:** Any test or proof invoking init
Only `--platform` and `--remote` suppress interactivity (`interactive?` checks exactly those two). CI/piped stdin is the second safety net.

### Doc-Closure Verification (Phase 2 pattern)
**Source:** `.planning/phases/02-diagnostics-command/02-01-PLAN.md` must_haves truth `DOC-CLOSURE`
**Apply to:** Phase 3 plan's doc tasks
Pattern: ROADMAP criteria annotated with inline `— amended YYYY-MM-DD: [rationine]` suffixes; SUMMARY.md gets a `## Documented deviations` section with lettered items sourcing back to CONTEXT/RESEARCH; line counts corrected; spec provenance clarified (N file examples + M shared helper examples = total).

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `docs/project-roadmap.md` (init item check) | config/doc | transform | Phase 2 checked this file but the plan artifact list doesn't record its exact edit pattern; minor — follow Phase 2 plan's `files_modified` list which includes it |

## Metadata

**Analog search scope:** `lib/spm_cache/`, `spec/`, `.planning/phases/02-diagnostics-command/`
**Files scanned:** 11 (init.rb, installer.rb, diff_detector.rb, diff_detector_spec.rb, installer_use_fast_path_spec.rb, init_spec.rb, ROADMAP.md, Phase 2 SUMMARY, Phase 2 PLAN, Phase 3 SUMMARY, RESEARCH.md)
**Pattern extraction date:** 2026-08-24
