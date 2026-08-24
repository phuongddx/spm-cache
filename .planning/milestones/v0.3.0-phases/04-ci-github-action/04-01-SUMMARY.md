---
phase: 04-ci-github-action
plan: 01
subsystem: ci-action
tags: [github-actions, composite-action, rspec, tdd, yaml, doc-closure]

requires:
  - phase: 03-project-bootstrap
    provides: init's real CLI surface (--default-config flag at init.rb:19/31) that the action shell-out must match
provides:
  - spec/action_spec.rb — permanent regression net over action/action.yml (strict-YAML/composite schema, input surface, injection safety, env wiring, init/remote flag cross-refs vs gem sources, sync-composed-in-action, ruby pin, executable match, README parity)
  - F1 fix: action.yml init step passes --default-config (the flag init defines/reads), so config: release seeds default_config: release
  - closed doc drift: README Caveats (F3/F6/F7), INTEGRATIONS.md:92 sync reword (F4), ROADMAP Phase-4 criteria 1-3 dated amendments, phase SUMMARY deviations + 6-item release checklist
affects: [05-auto-sync-watcher]

actuals:
  tokens: 3818    # chars/4 over the realized diff 29c2c5d..68021c5 (15273 chars), excluding this summary + state metadata
  tasks: 2
  commits: 4      # RED, GREEN, docs closure, plan metadata

tech-stack:
  added: []
  patterns:
    - "Emitted-minus-defined flag cross-reference: slice a command file's own options (def self.options → .concat(super)), scan the action step's run script for --name= tokens, assert the difference empty — inherited CLAide base flags live outside the slice by construction"

key-files:
  created:
    - spec/action_spec.rb
    - .planning/phases/04-ci-github-action/04-01-SUMMARY.md
  modified:
    - action/action.yml
    - action/README.md
    - .planning/ROADMAP.md
    - .planning/codebase/INTEGRATIONS.md
    - .planning/phases/04-ci-github-action/SUMMARY.md

key-decisions:
  - "F1 fixed by one-line flag rename only (--config= → --default-config= at action.yml:55); remote steps keep --config (pull.rb/push.rb define it themselves); execution shape and input surface byte-stable"
  - "The spec's defined-flags set is sliced from def self.options through .concat(super) so the inherited base --config (command.rb:19) can never satisfy the cross-reference — the slice construction is the load-bearing part"
  - "gemspec homepage placeholder recorded verbatim in the Release checklist, not edited (outside ONBD-04 scope, OQ2)"

patterns-established:
  - "Action-vs-gem CLI contract spec: spec/action_spec.rb pattern (parse composite YAML with strict Psych, cross-reference every emitted flag against the invoked command's own options slice) — reusable if the action grows more steps"

requirements-completed: [ONBD-04]

coverage:
  - id: F1-FIX
    description: "init step emits only flags init.rb's own options define; config: release seeds default_config: release"
    requirement: ONBD-04
    verification:
      - kind: unit
        ref: "spec/action_spec.rb#init step emits only flags the gem's init command defines (RED 2529d26 → GREEN d9a4c4e)"
        status: pass
    human_judgment: false
  - id: SC1
    description: "input surface: exactly six inputs with descriptions and defaults, README table parity"
    requirement: ONBD-04
    verification:
      - kind: unit
        ref: "spec/action_spec.rb#declares the accepted input surface with per-input metadata + #README input table matches the action inputs"
        status: pass
    human_judgment: false
  - id: SC2
    description: "thin shell-out contract: composite schema, env indirection for all six inputs, remote flags ⊆ pull∪push options, sync composed in-action, ruby pin, executable match"
    requirement: ONBD-04
    verification:
      - kind: unit
        ref: "spec/action_spec.rb examples 1,3,4,6,7,8"
        status: pass
    human_judgment: false
  - id: PROBE-ONBD-04
    description: "composite-schema and input-wiring invariants machine-enforced (authored truth)"
    requirement: ONBD-04
    verification:
      - kind: unit
        ref: "spec/action_spec.rb#parses as strict YAML and satisfies composite schema rules + #never expands GitHub input contexts inside run script bodies + #routes every declared input through step env assignments"
        status: pass
    human_judgment: false
  - id: SC3
    description: "criterion-3 locally provable remainder proven; unreachable remainder recorded as dated ROADMAP amendment + SUMMARY deviations/release checklist (not dropped)"
    requirement: ONBD-04
    verification:
      - kind: unit
        ref: "spec/action_spec.rb (safe-load/schema examples) + ROADMAP:71 amendment + phase SUMMARY Documented deviations (a)/Release checklist"
        status: pass
    human_judgment: false
  - id: DOC-CLOSURE
    description: "all RESEARCH F4 doc items dispositioned (INTEGRATIONS reword, ROADMAP ×3, README Caveats, SUMMARY machine-check pointer)"
    requirement: ONBD-04
    verification:
      - kind: cli
        ref: "TASK2-GATE-OK (amendment count 8; composed-by-the-action == 1; remote pull/push/sync == 0; ## Caveats == 1)"
        status: pass
    human_judgment: false
---

# Phase 04 Plan 01: CI GitHub Action — verification closure + F1 flag fix Summary

Spec/action_spec.rb (9 examples) turning RESEARCH's passing inventory into a permanent regression net, the one-line F1 repair (`--config=` → `--default-config=` at action.yml:55) proven RED→GREEN, and full doc-drift closure (README Caveats, INTEGRATIONS sync reword, 3 ROADMAP amendments, SUMMARY deviations + ordered release checklist).

## What Was Built

**Task 1 (TDD)** — `spec/action_spec.rb` (NEW, 132 lines): nine action-owned examples — (1) strict-Psych parse + composite schema (name/description, using==composite, 4 steps, shell on every run step); (2) exact input surface with per-input metadata and defaults; (3) injection safety (no `${{ inputs.` macro inside run bodies); (4) all six inputs routed through step env assignments, none orphaned; (5) THE F1 NET — init emitted flags minus init.rb's own options (sliced `def self.options`→`.concat(super)`) must be empty; (6) remote flags ⊆ pull∪push own options, pull/push invocations present, no `remote sync` string, remote/ dir == pull.rb+push.rb; (7) quoted ruby pin "3.2" satisfying gemspec >= 3.1.0; (8) `gem install spm-cache --no-document` + gemspec executables match, no other gem binary; (9) README Inputs table parity (names/required/defaults row-for-row). Plus the 3 spec_helper smoke examples = 12 per single-file run.

Then the GREEN edit: action.yml line 55 ONLY — `ARGS="--config=${CONFIG}"` → `ARGS="--default-config=${CONFIG}"`. Remote steps, env maps, backend branching, tolerant `|| true` byte-identical (`git diff -U0`: 1 line; phase-wide diff: spec new + 1 YAML line).

**Task 2 (docs)** — action/README.md `## Caveats` (7 inserted lines, insertion-only hunk): `.xcodeproj`-at-repo-root requirement, green-with-warnings disclosure naming both warn markers + `required: true` non-enforcement, [ASSUMED] git-backend push credentials. INTEGRATIONS.md:92 reworded (sync = pull+push composed by the action; line 93 untouched). ROADMAP Phase-4 criteria 1-3 dated `— amended 2026-08-24:` amendments (file count 5 → 8). Phase SUMMARY.md: Documented deviations (a-c) + 6-item ordered Release checklist (homepage placeholder quoted verbatim, not edited) + Note now machine-check-backed.

## TDD Evidence

- **RED (commit 2529d26):** `bundle exec rspec spec/action_spec.rb` → **12 examples, 1 failure**; the other 8 action examples + 3 smoke green. Failure output:

  ```
  1) action/action.yml init step emits only flags the gem's init command defines
     Failure/Error: expect(undefined).to be_empty, msg
       init step emits flags init.rb's own options do not define: config (RESEARCH F1 — inherited base flags are silently accepted by CLAide and never read by init)
  ```

  The failure names the emitted-but-undefined flag `config` exactly as planned.

- **GREEN (commit d9a4c4e):** 12 examples, 0 failures. `config: release` now reaches `resolve_default_config` (init.rb:78-87) instead of silently falling back to `debug`.

## Verification

| Check | Result |
|---|---|
| `bundle exec rspec spec/action_spec.rb --format documentation` | **12 examples, 0 failures**; nine example strings + 3 smoke listed |
| `make proxy.build && bundle exec rspec` (full suite, assignment-mandated) | **249 examples, 0 failures** |
| `grep -c -- '--default-config=' action/action.yml` | 1 ✓ |
| `grep -c 'ARGS="--config=' action/action.yml` | 0 ✓ |
| remote step untouched (fixed-string count) | `remote "$COMMAND" --config="$CONFIG"` == 1 ✓ |
| `git diff` GREEN commit | exactly 1 line in action/action.yml ✓ |
| `ruby -ryaml` safe_load smoke | `safe_load ok` ✓ |
| `grep -c "amended 2026-08-24" .planning/ROADMAP.md` | 8 ✓ (5 pre-existing + 3 new) |
| `grep -c "composed by the action" INTEGRATIONS.md` / `remote pull/push/sync` | 1 / 0 ✓ |
| `grep -c "## Caveats" action/README.md` | 1 ✓ (7 added / 0 modified / 0 removed) |
| SUMMARY `Documented deviations` / `Release checklist` / `your-org` | ≥1 / ≥1 / ≥1 ✓ |
| `git diff --stat -- spm_cache.gemspec action/action.yml` (Task 2 commit) | empty ✓ |
| TDD provenance in `git log` | test(04-01) 2529d26 → fix(04-01) d9a4c4e → docs(04-01) 68021c5 ✓ |
| Task gates | TASK1-GATE-OK, TASK2-GATE-OK ✓ |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] First RED run failed 2 examples — option-tuple scan missed double-quoted CLAide arrays**
- **Found during:** Task 1 RED authoring (pre-commit)
- **Issue:** `own_option_flags` scanned for single-quoted tuples (`['--flag=`) only; pull.rb/push.rb define options with double quotes (`[["--config=CONFIG", ...`), so `remote_defined_flags` came back empty and the remote example failed alongside the intended init example.
- **Fix:** regex broadened to accept both quote styles (`/\[(?:['"]{1,2})?--([a-z0-9-]+)(?:=|['"])/`); final RED run failed exactly the init example naming `config`, all other 11 green.
- **Files modified:** spec/action_spec.rb
- **Verification:** final RED run `12 examples, 1 failure` (init example only); commit 2529d26
- **Commit:** folded into 2529d26 (fixed before the RED commit was made)

**2. [Rule 3 - Blocking] Task 1 verify gate grep is a GNU-ism on macOS BSD grep**
- **Found during:** Task 1 gate execution
- **Issue:** `grep -c 'remote "$COMMAND" --config="$CONFIG"' action/action.yml` returns 0 on macOS — BSD grep treats the mid-pattern `$` as an anchor, making the pattern unmatchable; the plan's gate was written for GNU grep semantics.
- **Fix:** identical literal check via `grep -cF` (fixed-string) → returns 1. Same semantics (literal string count), no check weakened.
- **Files modified:** none (gate invocation only)
- **Verification:** `grep -Fc 'remote "$COMMAND" --config="$CONFIG"' action/action.yml` == 1; TASK1-GATE-OK emitted with the -F form

**Total deviations:** 2 auto-fixed (1 bug, 1 blocker). **Impact:** none on scope or acceptance criteria — RED/GREEN provenance and all gates hold.

## Authentication Gates

None.

## Known Stubs

None — no placeholders, no unproven claims left in shipped artifacts; the action's external publication chain is an explicitly recorded user-accepted deviation (04-CONTEXT), not a stub.

## Self-Check: PASSED
