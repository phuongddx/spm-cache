# Phase 4: CI GitHub Action - Research

**Researched:** 2026-08-24
**Domain:** GitHub Actions composite-action verification (verification-scoped closure — action already implemented at commit 9e35030)
**Confidence:** HIGH

<user_constraints>

## User Constraints (from CONTEXT.md)

### Locked Decisions

**Input surface (accepted as shipped, 2026-08-24):**
- Inputs: `command` (pull/push/sync), `backend` (git/s3), `backend-url`, `config`, `branch`, `creds` — superset of the ROADMAP criterion-1 list (mirrors `init`'s remote flags); accepted.

**Execution shape (accepted as shipped):**
- 4-step composite: setup-ruby → `gem install spm-cache` → `spm-cache init` → `spm-cache remote <command>` — thin shell-out, zero logic duplication
- `spm-cache init` runs inside the Action to seed config before the remote step (works from flags, no user-authored spm-cache.yml required)
- No gem version pinning input (tracks latest RubyGems release) — accepted; pinning rejected 2026-08-24

**Criterion 3 — external dependency (accepted as deviation):**
- ROADMAP criterion 3 ("smoke-tested in its own repo's CI") is UNREACHABLE from this repo: it requires publishing to `phuongddx/spm-cache-action` (repo-owner action). Record as a documented external-dependency deviation + release-checklist item. The plan verifies everything locally verifiable: YAML validity, composite schema, input wiring, shell-out commands matching the gem's actual CLI.

**Phase boundary:** "This phase's plan is VERIFICATION-SCOPED: prove action.yml structure/inputs/shell-out locally, record the external-dependency deviation for criterion 3, close doc drift — do NOT re-implement."

### Claude's Discretion
- Verification task granularity
- Local proof organization (YAML parse, input-to-step wiring assertions, README accuracy)
- Doc phrasing

### Deferred Ideas (OUT OF SCOPE)
- Gem version-pinning input — rejected 2026-08-24
- Requiring user-authored spm-cache.yml instead of init-seeding — rejected 2026-08-24

</user_constraints>

<phase_requirements>

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| ONBD-04 | `phuongddx/spm-cache-action@v1` (separate repo) restores/saves cache in CI via a thin shell-out to the gem, configurable with `command`, `backend`, `backend-url`, `config` inputs in a 5-line workflow | F5: all four named inputs (plus `branch`/`creds` superset) exist and are wired [VERIFIED: action/action.yml:8-31]; shell-out shape proven against gem CLI [VERIFIED: lib/spm_cache/command/]; F1: one flag defect found in the init shell-out (fix recommended, phase-3 precedent); F2: RubyGems publication prerequisite discovered (external, feeds criterion-3 deviation record); criterion-3 remainder is the accepted external deviation |

</phase_requirements>

## Summary

The Action is fully implemented at commit `9e35030` as an 86-line composite (`action/action.yml`) plus a 49-line README (`action/README.md`) [VERIFIED: git show --stat 9e35030; both files read this session]. Its structure is schema-correct per the official metadata-syntax reference: `runs.using: "composite"`, 4 steps, every `run` step carries `shell: bash`, all six inputs have required `description` fields, and every input enters scripts only through `env:` indirection (`BACKEND: ${{ inputs.backend }}` etc.) — exactly the injection-safe pattern GitHub recommends [VERIFIED: docs.github.com metadata-syntax + secure-use guidance]. All SUMMARY.md numeric claims (86 lines, 49 lines, 6 inputs, 4 steps, commit hash) check out against disk and git.

Cross-referencing the shell-outs against the gem's real CLI surface found **one genuine defect (F1)**: the init step passes `--config=${CONFIG}` [VERIFIED: action/action.yml:55], but `init` defines `--default-config`, not `--config` — `--config` is only the *inherited base-command* flag (`["--config=CONFIG", "Build configuration (default: debug)"]` at lib/spm_cache/command.rb:19) which init's run path never reads. CLAide accepts the flag silently, so `config: release` users get a seeded config of `default_config: debug` (resolve_default_config falls back to `'debug'` when `@default_config` is nil, non-interactive) [VERIFIED: lib/spm_cache/command/init.rb:78-87]. The remote step is correct: `remote pull`/`remote push` each define `--config=CONFIG` [VERIFIED: pull.rb:12, push.rb:12]. A second, external finding (**F2**): the `spm-cache` gem is **not published on RubyGems** (API 404 with a 200 control on `rspec`; `gem list --remote --exact spm-cache` empty, probed 2026-08-24), so the action's `gem install spm-cache --no-document` step cannot succeed on any runner until the owner runs `gem push` — this must join the criterion-3 external-deviation record and release checklist.

**Primary recommendation:** Build the plan as local proofs (RSpec spec parsing `action/action.yml` + source cross-referencing `lib/spm_cache/command/*.rb`), apply the one-line F1 fix (`--config=` → `--default-config=` on the init ARGS line) following the phase-3 "fix found defects" precedent, record F2 + criterion-3 as the documented external-deviation block (ROADMAP amendment + SUMMARY), and close the two small doc-drift items (INTEGRATIONS.md sync phrasing; optional README hardening notes).

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Action metadata (inputs/defaults/branding) | CI composite-action layer | — | Declarative YAML consumed by GitHub's runner; nothing else owns it |
| Cache restore/save semantics | Gem CLI (`spm-cache remote pull/push`) | — | Locked design: "separate thin repo, shell-out only"; action must never duplicate |
| Config seeding before remote step | Gem CLI (`spm-cache init`) | Action (arg assembly only) | Init owns merge semantics; action only translates inputs→flags |
| Ruby runtime provisioning on runner | `ruby/setup-ruby@v1` | — | Standard; pinned `ruby-version: "3.2"` |
| `sync` command semantics | Action step (composition) | Gem (pull + push primitives) | Gem has NO `remote sync` subcommand; action composes pull-then-push [VERIFIED: action/action.yml:78-81, glob of lib/spm_cache/command/remote/] |
| Publication (`phuongddx/spm-cache-action@v1`) | External repo (owner action) | — | `uses:` resolution requires the separate repo; locked deviation |
| Phase verification | Repo test layer (RSpec, stdlib Psych) | — | nyquist_validation enabled; no runner needed for the locally provable set |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| (none new) | — | Phase installs ZERO new packages | Verification-scoped; proofs use Ruby stdlib (`yaml`/Psych) + existing RSpec [VERIFIED: spm_cache.gemspec:37 rspec ~> 3.12 dev dependency] |
| `ruby/setup-ruby@v1` | v1 (already used) | Action step 1 | Same action this repo's ci.yml uses [VERIFIED: .github/workflows/ci.yml:32] |
| GitHub composite-action format | `runs.using: composite` | Action packaging | Only format supporting multi-step shell-out without JS/Docker |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Ruby stdlib `yaml` (Psych) | bundled (ruby 3.2.3 local) | YAML parse + safe_load proof | Primary local validation method; validated live this session |
| RSpec | ~> 3.12 (existing) | Encode schema/wiring/cross-ref assertions as specs | nyquist per-task sampling |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Psych-based spec assertions | `actionlint` | actionlint is the purpose-built linter but is NOT installed locally (`command -v actionlint` empty); installing it adds an environment dependency for no additional guarantee over the targeted assertions this phase needs. Optional planner choice, not required |
| Psych-based spec assertions | `yq` | Not installed either; adds nothing Psych lacks here |

**Installation:**
```bash
# none — no new packages this phase
```

**Version verification:** Not applicable — no packages recommended for installation. Existing toolchain probed: `ruby 3.2.3` local ✓.

## Package Legitimacy Audit

**Phase installs no external packages.** The gate protocol is therefore vacuous this phase; recorded for completeness.

| Package | Registry | Age | Downloads | Source Repo | Verdict | Disposition |
|---------|----------|-----|-----------|-------------|---------|-------------|
| (none) | — | — | — | — | — | No installs planned |

**Packages removed due to [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

*Related supply-chain fact (not an install): the action itself runs `gem install spm-cache --no-document` unpinned at runner time — accepted decision (pinning rejected 2026-08-24) — but see F2: the gem is not yet on RubyGems at all.*

## Architecture Patterns

### System Architecture Diagram

```
user workflow (5 lines)                    phuongddx/spm-cache-action (published copy of action/)
─────────────────────────                  ────────────────────────────────────────────────
- uses: .../spm-cache-action@v1    ──▶  inputs: command backend backend-url branch config creds
  with: {command: pull, ...}              │
                                          ▼
                              ┌─ step 1: ruby/setup-ruby@v1 (ruby 3.2) ─┐
                              │ step 2: gem install spm-cache            │ ⚠ F2: not on RubyGems yet
                              │ step 3: spm-cache init  ◀── env-indirected inputs
                              │            ARGS="--config=${CONFIG}"      ⚠ F1: gem expects --default-config
                              │            + --remote/--remote-url/--branch  (git)
                              │            + --remote/--remote-url/--creds   (s3)
                              │            unsupported backend → ::error exit 1
                              │            `|| true` (tolerate init failure) ⚠ F3
                              │ step 4: case $COMMAND
                              │            pull|push → spm-cache remote <cmd> --config=$CONFIG
                              │            sync      → remote pull; remote push   (action-side composition)
                              │            *         → ::error exit 1
                              └────────────────────┬───────────────────────┘
                                                   ▼
                              gem CLI (this repo): init (seeds spm-cache.yml/lock)
                                                   remote pull/push → Storage::Git|S3|Base
                                                   Base fallback = warn + skip, exit 0  ⚠ F3
                                                   (external: git/S3 backend repo or bucket)
```

A reader can trace the primary use case: workflow `with:` → inputs → env → init seeding → remote pull/push → storage backend. Everything inside the dashed region except the gem CLI is the composite; the gem owns all caching semantics.

### Recommended Project Structure

```
action/
├── action.yml        # composite (86 lines, shipped — do not re-implement; only the F1 one-liner)
└── README.md         # usage + design rationale (49 lines, shipped)
spec/
└── action_spec.rb    # NEW (Wave 0) — local proofs: YAML/schema/wiring/CLI cross-reference
.planning/phases/04-ci-github-action/
├── 04-CONTEXT.md     # locked decisions
├── RESEARCH.md       # this file
└── SUMMARY.md        # append deviation record at execution
```

### Pattern 1: Inputs via env indirection (already shipped — verify, don't change)

**What:** Never interpolate `${{ inputs.* }}` directly into `run:` script text; assign to step `env:` and reference `$VAR_NAME`.
**When to use:** Always, in any composite/run step consuming inputs.
**Why:** `${{ }}` is macro-expanded into the shell program body before execution; attacker-controlled values containing `$(…)`, `;`, quotes, or newlines can restructure the script. Env assignment moves untrusted values out of the program body [CITED: docs.github.com/en/actions/reference/security/secure-use; securitylab.github.com/resources/github-actions-untrusted-input].
**Shipped state:** action.yml steps 3 and 4 follow this pattern for all six inputs [VERIFIED: action/action.yml:47-52, 69-71]. Verification should assert this invariant (no `${{ inputs.` substring inside any `run:` block).

### Pattern 2: Local proof via stdlib Psych + source cross-reference (the plan's core method)

**What:** Parse `action/action.yml` with `YAML.load_file`/`YAML.safe_load_file`, assert schema keys, then assert that every flag the action's scripts build exists verbatim in the corresponding gem command file.
**When to use:** All criterion-1/criterion-2 local proofs.
**Validated this session:**

```bash
$ ruby -ryaml -e 'd=YAML.load_file("action/action.yml"); puts "ok composite=#{d["runs"]["using"]} steps=#{d["runs"]["steps"].size} inputs=#{d["inputs"].keys.join(",")}"'
ok composite=composite steps=4 inputs=command,backend,backend-url,branch,config,creds
$ ruby -ryaml -e 'YAML.safe_load_file("action/action.yml", permitted_classes: [], aliases: false); puts "safe_load ok"'
safe_load ok
```
[VERIFIED: executed 2026-08-24, output above]

### Anti-Patterns to Avoid

- **Re-implementing any caching logic in the action:** locked decision — shell-out only. The plan must not grow storage/auth logic into action.yml.
- **Trusting `required: true` as enforcement:** official docs state "Actions using `required: true` will not automatically return an error if the input is not specified" [CITED: docs.github.com metadata-syntax, `inputs` note]. `backend-url` required+defaultless is NOT runner-enforced; absence yields empty string, not an error.
- **Direct `${{ inputs.* }}` in `run:` bodies:** see Pattern 1.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| YAML validation | Custom YAML parser/regex walker | Ruby stdlib `YAML.safe_load_file` | Psych is the battle-tested parser; regex-on-YAML misses anchors/types |
| Ruby provisioning in CI | brew install ruby / rbenv in action | `ruby/setup-ruby@v1` | Prebuilt binaries on PATH in ~5s; already the repo convention [CITED: github.com/ruby/setup-ruby] |
| Composite schema knowledge | Guessing required fields | Official metadata-syntax reference | `shell` is "Required if `run` is set"; `name`/`description` required; icon/color are enums |
| Cache restore/save semantics | Anything in the action | `spm-cache remote pull/push` | Locked design decision |

**Key insight:** the entire phase is *proving an existing thin wrapper*; every temptation to "improve while verifying" violates the CONTEXT boundary except the F1 one-liner (a correctness fix to make the shell-out match the gem's real CLI — the explicit cross-check this phase exists to perform).

## Verification Findings (action.yml ↔ gem CLI cross-reference)

> This is the section the planner builds tasks from. F-numbers are referenced by the requirement map and pitfalls.

### F1 — init flag mismatch: `--config` vs `--default-config` (DEFECT — fix recommended)

- Action builds `ARGS="--config=${CONFIG}"` then runs `spm-cache init $ARGS || true` [VERIFIED: action/action.yml:55, 65].
- Gem's `init` options, verbatim [VERIFIED: lib/spm_cache/command/init.rb:17-23]:
  ```ruby
  ['--project=PATH', 'Path to the .xcodeproj (default: auto-detect in cwd)'],
  ['--platform=LIST', 'Comma-separated platforms (ios,macos,watchos,tvos)'],
  ['--default-config=CONFIG', 'Default build config (debug/release)'],
  ['--remote=BACKEND', 'Remote backend (none/git/s3)'],
  ['--remote-url=URL', 'Git remote URL or S3 URI'],
  ['--branch=BRANCH', 'Git remote branch (default: main)'],
  ['--creds=PATH', 'S3 credentials JSON file path']
  ```
- Base command defines, verbatim [VERIFIED: lib/spm_cache/command.rb:19]: `["--config=CONFIG", "Build configuration (default: debug)"]` — inherited by init via `.concat(super)` + `super` in initialize; init's run path reads `@default_config`, never `@config`.
- Net behavior: `spm-cache init --config=release` parses without error but seeds nothing — `resolve_default_config` sees nil and falls to `'debug'` in non-interactive mode [VERIFIED: lib/spm_cache/command/init.rb:78-87: `if @default_config ... else 'debug'`].
- Blast radius: LOW within the action's own four steps (step 4 passes `--config` directly to `remote pull/push`, which DO define it — [VERIFIED: lib/spm_cache/command/remote/pull.rb:12 `[["--config=CONFIG", "Build configuration (default: debug)"]].concat(super)`, push.rb:12 identical]); REAL for users who pass `config: release` and then run their own `spm-cache build/use` steps against the action-seeded config (seeded default is silently `debug`).
- **Recommended fix (one line):** action.yml:55 `ARGS="--config=${CONFIG}"` → `ARGS="--default-config=${CONFIG}"`. All other init flags used by the action (`--remote`, `--remote-url`, `--branch`, `--creds`) exist verbatim in init's options. Precedent: phase 3 fixed the canonical lock-seeding defect found in verification (03-01 Task 1). The CONTEXT locks the input *surface* and *execution shape* as shipped — not the flag spelling; fixing F1 is squarely within "shell-out commands matching the gem's actual CLI."

### F2 — gem not published on RubyGems (EXTERNAL blocker — record, don't fix here)

- Action step 2 runs `gem install spm-cache --no-document` [VERIFIED: action/action.yml:43].
- Live probe 2026-08-24: `https://rubygems.org/api/v1/gems/spm-cache.json` → HTTP 404; control `.../gems/rspec.json` → 200; `gem list --remote --exact spm-cache` → empty output [VERIFIED: executed this session].
- Consequence: the action cannot succeed on any runner until `gem build` + `gem push` publish the gem. This is an owner action outside this repo's GSD flow — it belongs in the same external-deviation record as criterion 3 and in the release checklist (publish gem → publish action repo → tag v1).
- Related pre-publish hygiene: gemspec homepage is the placeholder `"https://github.com/your-org/spm-cache"` [VERIFIED: spm_cache.gemspec:12]; RubyGems displays this. Fixing the string is a trivial doc-level change planner MAY fold into the deviation task (judgment call — it is not ONBD-04 scope; flag, don't silently expand).

### F3 — silent-green failure mode (`|| true` × Storage::Base fallback) (PITFALL — document)

- Init failure is swallowed: `spm-cache init $ARGS || true` [VERIFIED: action/action.yml:65].
- With no seeded remote config, `Remote.create_storage` returns `Storage::Base` [VERIFIED: lib/spm_cache/command/remote.rb:17 `return Storage::Base.new unless remote`], whose pull/push only warn — verbatim [VERIFIED: lib/spm_cache/storage/base.rb:22-24]: `Core::UI.warn("No remote cache configured. Skipping #{action}.")` / `Core::UI.warn("Configure remote cache in spm-cache.yml to enable.")` — and exit 0.
- Also: `init` raises when no `.xcodeproj` is found in cwd [VERIFIED: lib/spm_cache/command/init.rb:40-43 — 'No .xcodeproj found — pass --project or run inside an Xcode project directory']; nested-project repos (xcodeproj not at repo root) therefore seed nothing, the `|| true` hides it, and pull/push no-op green. The action exposes no `--project` passthrough (init supports it; not in the accepted input surface).
- Disposition: keep behavior as shipped (tolerant init is a defensible UX choice and changing control flow would breach the verification-scoped boundary); close the gap in *docs* — Claude's discretion covers doc phrasing. Recommended README note: "requires an `.xcodeproj` at the repository root" + misconfiguration currently exits green with warnings.

### F4 — doc drift catalogue (close)

| Item | Location | Claim vs reality | Action |
|------|----------|------------------|--------|
| SUMMARY numeric claims | .planning/phases/04-ci-github-action/SUMMARY.md:7-8 | 86 lines / 49 lines / 6 inputs / 4 steps / commit 9e35030 — ALL accurate [VERIFIED: file reads + git show --stat] | No correction needed |
| SUMMARY "Validated: well-formed YAML" | SUMMARY.md:11 | Claim has no committed machine check behind it | Back it with spec/action_spec.rb (Wave 0) |
| SUMMARY omission | SUMMARY.md | Does not mention F1 flag mismatch or F2 RubyGems absence | Add Documented-deviation block at execution |
| `remote pull/push/sync` phrasing | .planning/codebase/INTEGRATIONS.md:92 ("Wraps the gem: ... runs `spm-cache init` + `spm-cache remote pull/push/sync`") | Gem has NO `remote sync`; only pull.rb + push.rb exist [VERIFIED: glob lib/spm_cache/command/remote/*.rb]; sync is action-side composition | One-line rewording ("remote pull/push; sync = pull+push composed by the action") |
| ROADMAP criteria 1-3 | .planning/ROADMAP.md:69-71 | Unamended; need dated inline amendments per phase-2/3 precedent: (a) criterion-1 input superset (branch/creds, accepted 04-CONTEXT), (b) criterion-2 note that sync is action-composed, (c) criterion-3 external deviation incl. F2 | Amendment task at execution |
| README example conventions | action/README.md:12,14 | `macos-15` + `actions/checkout@v5` — matches repo ci.yml conventions [VERIFIED: .github/workflows/ci.yml:18,24] | No drift; current GitHub docs examples show checkout@v6 but v5 remains valid — leave as-is |

### F5 — what already passes (verification-positive inventory)

| Check | Result | Evidence |
|-------|--------|----------|
| YAML parses; safe_load clean | PASS | Executed this session (Pattern 2 output) |
| `runs.using == "composite"` (required value) | PASS | [VERIFIED: action/action.yml:34; docs: "You must set this value to 'composite'"] |
| `name`, `description` present (required keys) | PASS | [VERIFIED: action/action.yml:1-2; docs: both Required] |
| Every `run` step has `shell` ("Required if `run` is set") | PASS | steps 2-4 `shell: bash` [VERIFIED: action/action.yml:42,46,68]; step 1 is a `uses` step (no run/shell needed) |
| All 6 inputs have `description` (required per input) | PASS | [VERIFIED: action/action.yml:8-31] |
| README input table == action.yml inputs (names, required, defaults) | PASS | 6/6 rows match incl. defaults pull/git/main/debug and "—" for backend-url/creds [VERIFIED: action/README.md:38-45 vs action/action.yml:8-31] |
| Branding valid | PASS | icon `package` in the exhaustive Feather v4.28.0 list; color `blue` in the enum (`white, black, yellow, blue, green, orange, red, purple, gray-dark`) [VERIFIED: docs.github.com metadata-syntax branding section] |
| Env indirection everywhere (injection-safe) | PASS | `${{ inputs.* }}` appears only in `env:` maps [VERIFIED: action/action.yml:47-52, 69-71] |
| Ruby pin satisfies gemspec | PASS | `"3.2"` (quoted string — avoids the YAML float trap) ≥ required `>= 3.1.0` [VERIFIED: action/action.yml:39; spm_cache.gemspec:27] |
| Executable name matches | PASS | gemspec `spec.executables = ["spm-cache"]` == invoked `spm-cache` [VERIFIED: spm_cache.gemspec:24; action/action.yml:65,76,79,80] |
| remote subcommands exist | PASS | pull.rb/push.rb define `Remote::Pull`/`Remote::Push` [VERIFIED: file reads] |

### F6 — `required: true` is not runner-enforced (GAP — document, optional guard out of scope)

`backend-url` is `required: true` with no default [VERIFIED: action/action.yml:17-19], but GitHub docs explicitly note required inputs are not auto-errored when omitted [CITED: docs.github.com metadata-syntax `inputs` note]. Omitted `backend-url` → empty `--remote-url=` → `resolve_remote` returns `{}` → F3's silent-green path. The action validates `backend` value but not `BACKEND_URL` emptiness [VERIFIED: action/action.yml:56-64]. Disposition: note in README/disclaimer; a code guard would exceed the verification boundary — leave as recorded observation unless planner judges a one-line `-z` guard as F1-class (it is control-flow, so default recommendation: no).

### F7 — git-backend push auth on runners (ASSUMED — open question for README)

[ASSUMED] Pushing to a git backend from a runner requires credentials for the *cache* repository; `actions/checkout`'s default token is scoped to the *workflow* repository, so a separate-repo cache backend likely needs a PAT or deploy key configured by the user. Research did not verify Storage::GitStorage's auth path (lib/spm_cache/storage/git.rb not read this session). Doc-level note recommended; behavioral verification out of scope.

## Common Pitfalls

### Pitfall 1: CLAide inherited-flag silent acceptance
**What goes wrong:** A flag spelled from the base command (`--config`) is accepted by a subcommand that defines a differently-named variant (`--default-config`) — no parse error, value silently ignored (F1).
**Why it happens:** `Command.options` concatenates `super`; initialize stores both; run paths read only their own ivars.
**How to avoid:** Cross-reference every emitted flag against the *specific* command file's `self.options` (the exact check this phase's spec must encode).
**Warning signs:** A flag "works" (exit 0) but seeded config shows defaults.

### Pitfall 2: Silent-green misconfiguration
**What goes wrong:** Action exits 0 while caching nothing (F3: `|| true` + Base warn-and-skip).
**Why it happens:** Tolerant init × no-op storage fallback compose.
**How to avoid:** Read runner logs for the two `Core::UI.warn` lines; document the failure mode in README.
**Warning signs:** Suspiciously fast "restore" steps; empty cache repo.

### Pitfall 3: Composite `shell` omission
**What goes wrong:** A `run` step without `shell` is a schema error for composites.
**Why it happens:** Workflow muscle-memory (top-level workflow steps infer shell from runner OS; composite steps do not).
**How to avoid:** Spec asserts `steps.select { _1.key?('run') }.all? { _1.key?('shell') }` [CITED: docs "Required if `run` is set"].
**Warning signs:** None locally — fails only at GitHub parse time; hence the local spec.

### Pitfall 4: Unquoted numeric ruby-version
**What goes wrong:** YAML coerces `3.2` to a float (historically `3.0` → `3.10`-style surprises).
**Why it happens:** YAML scalar typing.
**How to avoid:** Quote it — shipped correctly as `"3.2"` [VERIFIED: action/action.yml:39] [CITED: docs.github.com building-and-testing-ruby].

### Pitfall 5: Publishing-order assumption
**What goes wrong:** Tagging the action repo `v1` before the gem exists on RubyGems (F2) ships an action whose step 2 always fails.
**Why it happens:** The two publications are separate owner actions.
**How to avoid:** Release checklist ordering: gem push → verify `gem install spm-cache` → publish action repo → tag v1.
**Warning signs:** RubyGems 404 on the API endpoint.

### Pitfall 6: Unpinned `gem install` (accepted risk)
**What goes wrong:** A breaking gem release changes action behavior with no action change.
**Why it happens:** No version pinning input (rejected 2026-08-24 — locked decision; do not relitigate).
**How to avoid:** N/A — record as accepted; the gem's semver discipline is the mitigation.

## Code Examples

### Local proof commands (all executed this session — Pattern 2)
```bash
# YAML validity + shape
ruby -ryaml -e 'd=YAML.load_file("action/action.yml"); abort "not composite" unless d.dig("runs","using")=="composite"; abort "steps!=4" unless d.dig("runs","steps").size==4; puts "ok"'
# Strict parse
ruby -ryaml -e 'YAML.safe_load_file("action/action.yml", permitted_classes: [], aliases: false); puts "safe_load ok"'
```

### CLI cross-reference method (for spec/action_spec.rb — Wave 0 skeleton)
```ruby
# Source: derived this session from lib/spm_cache/command/{init,remote/pull,remote/push}.rb
RSpec.describe "action/action.yml" do
  let(:action) { YAML.safe_load_file("action/action.yml", permitted_classes: [], aliases: false) }

  it "declares the accepted input surface" do
    expect(action.fetch("inputs").keys.sort).to eq %w[backend backend-url branch command config creds].sort
  end

  it "puts shell on every run step (composite schema rule)" do
    runs = action.dig("runs", "steps").select { |s| s.key?("run") }
    expect(runs).to all(include("shell"))
  end

  it "never interpolates inputs directly into run bodies (injection safety)" do
    action.dig("runs", "steps").each do |s|
      next unless s.key?("run")
      expect(s["run"]).not_to include("${{ inputs.")
    end
  end

  it "passes only flags the gem's init actually defines" do
    init_options = File.read("lib/spm_cache/command/init.rb")
    %w[--default-config --remote --remote-url --branch --creds].each do |flag|
      expect(init_options).to include("'#{flag}") # matches ['--flag=X', ...] literals
    end
  end
end
```
Note: the last example is written against the POST-F1 state (`--default-config` in the emitted-flags list); if F1 is not fixed, that assertion must instead FAIL — which is the point: the spec is the regression net for the cross-check.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `actions/checkout@v4/v5` in examples | Docs examples now show `@v6` | docs current | None — `@v5` (repo + action README convention) remains fully valid; no change recommended |
| Ruby 3.0 on macOS runner images | Removed 2025-02-17; images default 3.3/3.4 | runner-images #11345 | None — action pins 3.2 via setup-ruby (consistent behavior across images) |
| Workflow-level `INPUT_*` env auto-exposure | Composite actions must use the `inputs` context | long-standing | Action already compliant |

**Deprecated/outdated:** Nothing in the shipped action is deprecated.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Git-backend push from a runner needs user-provided credentials for the cache repo (checkout token is workflow-repo-scoped); `Storage::GitStorage` auth path not read this session | F7, Pitfalls | Low — doc-note only; if wrong, note is harmless |
| A2 | Publication (`gem push` + action repo + tag v1) will be performed by the repo owner per the release checklist | F2, Open Questions | The action simply cannot function before it; checklist ordering handles it |
| A3 | `bundle exec rspec spec/action_spec.rb` runs locally as in ci.yml's `bundle exec rspec` [VERIFIED: .github/workflows/ci.yml:41 — command string]; local bundle execution itself not exercised this session | Validation Architecture | Trivial — executor discovers instantly; Gemfile.lock present in repo |

## Open Questions

1. **F1 disposition — fix vs record-only?**
   - What we know: mismatch is real, fix is a one-line change, phase-3 precedent fixed found defects.
   - What's unclear: whether the orchestrator treats the CONTEXT's "accepted as shipped" as freezing the init ARGS line.
   - Recommendation: fix (the CONTEXT freezes input surface + execution shape; flag spelling is exactly what "commands matching the gem's real CLI" asks to correct).
2. **Gemspec homepage placeholder — in scope?**
   - What we know: `"https://github.com/your-org/spm-cache"` [VERIFIED: spm_cache.gemspec:12] surfaces on RubyGems after publish.
   - Recommendation: fold into the F2 deviation task only if the planner accepts a trivial string edit; otherwise record in checklist.
3. **README hardening notes (F3/F6/F7) — which to add?**
   - Claude's discretion explicitly covers doc phrasing; recommend all three as 3-5 added lines, no behavior change.
4. **actionlint adoption?**
   - Not installed locally; Psych specs cover this phase's needs. Optional `brew install actionlint` as an executor convenience — recommend NOT making it a dependency.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Ruby (stdlib Psych) | YAML proofs | ✓ | 3.2.3 (local) | — |
| Bundler + RSpec | spec/action_spec.rb | ✓ | rspec ~> 3.12 (Gemfile/gemspec) | — |
| actionlint | optional lint | ✗ | — | Psych assertions (recommended primary) |
| yq | not needed | ✗ | — | — |
| rubygems.org network probe | F2 verification | ✓ | used this session | `gem list --remote` (also used) |
| GitHub macOS runner + published action repo | criterion 3 | ✗ external | — | accepted deviation (04-CONTEXT) |

**Missing dependencies with no fallback:** none blocking — the only unreachable items are the accepted external-deviation set.
**Missing dependencies with fallback:** actionlint → Psych-based spec assertions.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | RSpec ~> 3.12 (existing; dev dependency in spm_cache.gemspec:37) |
| Config file | none dedicated — spec/spec_helper.rb + repo-wide `.rspec` conventions |
| Quick run command | `bundle exec rspec spec/action_spec.rb` |
| Full suite command | `bundle exec rspec` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| ONBD-04 (criterion 1) | action.yml declares command/backend/backend-url/config (+branch/creds) with descriptions/defaults; YAML valid; composite schema (using/shell) | unit | `bundle exec rspec spec/action_spec.rb` | ❌ Wave 0 |
| ONBD-04 (criterion 2) | emitted init flags ⊆ init.rb options; remote pull/push --config exists; sync composed of pull+push; no `${{ inputs.` inside run bodies | unit | `bundle exec rspec spec/action_spec.rb` | ❌ Wave 0 |
| ONBD-04 (docs) | README input table matches action.yml inputs/required/defaults | unit | `bundle exec rspec spec/action_spec.rb` | ❌ Wave 0 |
| ONBD-04 (criterion 3) | external — deviation record (ROADMAP amendment + SUMMARY block + release checklist) | manual-only | n/a (documented; no runner available — accepted deviation per 04-CONTEXT) | n/a |

### Sampling Rate
- **Per task commit:** `bundle exec rspec spec/action_spec.rb`
- **Per wave merge:** `bundle exec rspec`
- **Phase gate:** Full suite green before `/gsd-verify-work`

### Wave 0 Gaps
- [ ] `spec/action_spec.rb` — covers all three local ONBD-04 proof rows above (skeleton in Code Examples)
- [ ] None other — framework, helper, and fixtures already exist

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | n/a (action authenticates nothing; runner-level git/S3 creds are user-supplied — F7 note) |
| V3 Session Management | no | n/a |
| V4 Access Control | no | n/a (no privileged context consumed) |
| V5 Input Validation | yes | Whitelists before shell use: `case "$COMMAND"` and backend if/elif with `::error` + `exit 1` [VERIFIED: action/action.yml:56-64, 74-85]; env indirection for all values (Pattern 1). Gap F6: emptiness not checked — documented |
| V6 Cryptography | no | n/a |
| V14 Config / supply chain (extended) | yes | Unpinned `gem install` = accepted risk (locked 2026-08-24); F2 publication prerequisite; gemspec homepage placeholder flagged |

### Known Threat Patterns for composite actions

| Pattern | STRIDE | Standard Mitigation | Shipped state |
|---------|--------|---------------------|---------------|
| Script injection via inputs (macro-expanded `${{ }}`) | Tampering/Elevation | env-var indirection | ✓ compliant [VERIFIED: action/action.yml:47-52, 69-71] |
| Supply-chain: installing unpinned gem | Tampering | version pinning | ✗ by locked decision; semver discipline + F2 checklist |
| Silent no-op (integrity spoofing: "cache restored" green) | Repudiation | fail loudly on missing config | ✗ shipped tolerant (F3); documented in README instead |

## Sources

### Primary (HIGH confidence)
- docs.github.com/en/actions/reference/workflows-and-actions/metadata-syntax — fetched verbatim this session: required keys, `shell` "Required if `run` is set", inputs context note, `required:true` non-enforcement, branding enums (color list incl. `blue`; exhaustive Feather icon list incl. `package`)
- docs.github.com/en/actions/tutorials/create-actions/create-a-composite-action — canonical composite example (env-indirection shape; same-repo local-`uses:` possibility noted)
- In-repo reads (all [VERIFIED] citations above): action/action.yml, action/README.md, lib/spm_cache/command/{command,init}.rb, lib/spm_cache/command/remote/{pull,push}.rb, lib/spm_cache/command/remote.rb, lib/spm_cache/storage/base.rb, spm_cache.gemspec, .github/workflows/{ci,update-tap}.yml, .planning/{ROADMAP,REQUIREMENTS,STATE}.md, phase 04 CONTEXT/SUMMARY
- Live probes (this session): rubygems.org API (spm-cache 404 / rspec 200), `gem list --remote`, `ruby -ryaml` parse smoke, `git show --stat 9e35030`
- Context7 `/websites/github_en_actions` — composite metadata queries (cross-confirmed the two docs.github.com fetches)

### Secondary (MEDIUM confidence)
- docs.github.com/en/actions/reference/security/secure-use + securitylab.github.com untrusted-input — env-indirection rationale (surfaced via websearch, cross-checked against fetched docs)
- actions/runner-images issue #11345 + docs building-and-testing-ruby — macOS image Ruby defaults; version quoting

### Tertiary (LOW confidence)
- ruby/setup-ruby README claims (5-second prebuilt binaries) — not directly fetched; non-load-bearing for the plan

## Metadata

**Confidence breakdown:**
- Verification findings (F1-F7): HIGH — every in-repo claim backed by a this-session file read with line ranges; external claims backed by live probes
- Composite schema requirements: HIGH — official metadata-syntax reference fetched and quoted
- RubyGems/runner currency claims: MEDIUM — point-in-time probes and third-party runner-images sources
- F7 (git-backend auth): LOW — [ASSUMED], flagged for README note only

**Research date:** 2026-08-24
**Valid until:** 2026-09-23 (stable domain; re-probe RubyGems 404 before relying on F2 after any publish event)
