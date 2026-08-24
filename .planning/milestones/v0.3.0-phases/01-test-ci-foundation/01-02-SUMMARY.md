---
phase: 01-test-ci-foundation
plan: '02'
subsystem: testing
tags: [github-actions, ci, rspec, swift, yaml, gap-closure]

requires:
  - phase: 01-test-ci-foundation
    provides: the two-job ci.yml workflow whose coverage gap this plan closes
provides:
  - ruby-tests builds the proxy release binary before RSpec on every matrix leg (full-suite CI coverage)
  - swift-tests runs swift test only (dead release build removed)
  - phase contract docs state the delivered 3.1/3.2/3.3 matrix with gemspec justification
affects: [02-diagnostics-command, verify-work, ship-gate, REL-01]

actuals:
  tokens: 2100   # chars/4 over realized diff (4440) + this SUMMARY artifact
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "binary-gated integration specs require the producing build step inside the same CI job that consumes them (no cross-runner artifacts)"

key-files:
  created:
    - .planning/phases/01-test-ci-foundation/01-02-SUMMARY.md
  modified:
    - .github/workflows/ci.yml
    - .planning/ROADMAP.md
    - .planning/phases/01-test-ci-foundation/PLAN.md
    - .planning/phases/01-test-ci-foundation/SUMMARY.md

key-decisions:
  - "Followed plan fix_decision verbatim: MJ-01 Option A on all matrix legs (one unfiltered `bundle exec rspec` per leg), Xcode pinned via the same maxim-lobanov/setup-xcode@v1 step, dead swift-tests build removed, no MI-03 timeout / no caching / no needs edge snuck in"
  - "Task 2 proof ran RED-then-GREEN against untouched specs: guard reproduces 6 pending in the single-file leg, full suite with binary present reports 0 pending"

patterns-established:
  - "Gap-closure verification contract: local `make proxy.build && bundle exec rspec` summary + `grep -c 'binary not built'` = 0 is the pre-merge gate; production leg logs (`0 pending` on 3.1/3.2/3.3) are the post-merge confirmation"

requirements-completed: [REL-01]

coverage:
  - id: D1
    description: "ruby-tests builds the proxy binary before RSpec (full-suite CI execution, MJ-01 Option A); swift-tests dead build removed (MI-02)"
    requirement: REL-01
    verification:
      - kind: integration
        ref: "python3 yaml structure assertion → STRUCTURE OK (one make proxy.build, in ruby-tests, ordered Set up Ruby < Build proxy < RSpec; swift-tests = 3 steps)"
        status: pass
      - kind: integration
        ref: "make proxy.build && bundle exec rspec → `218 examples, 0 failures` (0 pending), exit 0; grep -c 'binary not built' = 0"
        status: pass
    human_judgment: false
  - id: D2
    description: "Phase contract docs record the delivered 3.1/3.2/3.3 matrix with the 5759c5b/gemspec justification (MI-01)"
    requirement: REL-01
    verification:
      - kind: other
        ref: "grep '3.0 dropped at merge 5759c5b' → ROADMAP 1, PLAN 1, SUMMARY 3; ROADMAP no longer lists 3.0/3.1/3.2/3.3; PLAN.md historical prose (lines 14/32/69-70) byte-unchanged"
        status: pass
    human_judgment: false

duration: 17min
completed: 2026-08-24
status: complete
---

# Phase 1 Plan 02: Full-Suite CI Gap Closure Summary

**ruby-tests now builds the Swift proxy release binary before RSpec on every leg (MJ-01 Option A), so the full 218-example suite — including all binary-gated gen_proxy integration/regression specs — executes in CI with 0 pending; the dead swift-tests release build is gone (MI-02) and the phase contract docs state the delivered Ruby 3.1/3.2/3.3 matrix with its gemspec justification (MI-01).**

## Performance

- **Duration:** ~17 min
- **Started:** 2026-08-23T16:55:00Z
- **Completed:** 2026-08-23T17:15:00Z
- **Tasks:** 3/3
- **Files modified:** 4 (+1 summary created)

## Local Full-Suite Proof (Task 2 gate)

- RED (`make proxy.clean` → single gated file): `9 examples, 0 failures, 6 pending` — 6 × `# spm-cache-proxy binary not built (run make proxy.build)` skip lines; the guard binds exactly the gated examples.
- GREEN (`make proxy.build && bundle exec rspec`): **`218 examples, 0 failures`** — rspec exit 0, and the summary carries **no pending clause** (RSpec prints `N pending` only when N > 0; its absence at the full 218-example count IS `0 pending`).
- `grep -c "binary not built"` over the captured run log: **0**
- gen_proxy layer executed, not excluded: documentation-format run (`--format documentation`, display-only, no filters) shows all six `gen-proxy *` describe groups (lines 200/205/211/219/226/232 of /tmp/01-02-gap-run-doc.log).
- Swift leg: `cd tools/spm-cache-proxy && swift test` → **20 tests, 5 suites, all passed, exit 0** (Swift 6.2.4 local toolchain).
- Logs kept at `/tmp/01-02-red-run.log`, `/tmp/01-02-gap-run.log`, `/tmp/01-02-gap-run-doc.log`.

## Task Commits

Each task was committed atomically:

1. **Task 1: Build the proxy binary inside ruby-tests before RSpec; remove the dead build from swift-tests** — `9f919a9` (fix)
2. **Task 2: Prove the gap closed — full suite runs 0 pending with the binary present** — no commit (plan-declared verification-only task; no file changes; evidence above)
3. **Task 3: Close the MI-01 doc drift** — `2a8f602` (docs)

**Plan metadata:** this summary file, committed as `docs(01-02): plan summary`.

## Files Created/Modified

- `.github/workflows/ci.yml` — ruby-tests: +`Select Xcode 16` (before `Set up Ruby`, so bundler-cache native-extension compilation uses the pinned Swift-6 toolchain) and +`Build proxy (release)` (`make proxy.build`) before `RSpec`; swift-tests: −`Build proxy (release)`. Triggers/concurrency/permissions/matrix/fail-fast byte-untouched; no new `${{ }}` expressions.
- `.planning/ROADMAP.md` — Phase 1 Success Criterion 2 rewritten to the delivered 3.1/3.2/3.3 matrix with justification.
- `.planning/phases/01-test-ci-foundation/PLAN.md` — Success Criteria Mapping item 2 gains the DELIVERED annotation; historical Approach/Risks prose untouched.
- `.planning/phases/01-test-ci-foundation/SUMMARY.md` — lines 13/19/26 corrected in place.
- `.planning/phases/01-test-ci-foundation/01-02-SUMMARY.md` — this file.

## Decisions Made

None beyond the plan — the `<fix_decision>` block was followed verbatim (Option A on all legs; no relitigating).

## Deviations from Plan

No Rule 1–4 deviations (no auto-fixes, no scope changes). Three recorded observations where on-disk/tooling reality differed from the plan's literal expectations, none changing any outcome:

**1. [Observation - count drift] RED single-file count**
- **Found during:** Task 2 (RED step)
- **Issue:** Plan expected `7 examples, 0 failures, 6 pending` from `spec/gen_proxy_ignore_spec.rb`; observed `9 examples, 0 failures, 6 pending` (the file gained non-gated examples since verification).
- **Resolution:** The binding criterion — the guard marking exactly its 6 gated examples pending — held byte-for-byte. Plan's own drift clause applies (then-current counts). The GREEN full-suite count did NOT drift: 218 exactly as required.
- **Commit:** n/a (verification-only task)

**2. [Observation - output format] RSpec omits `0 pending` from the summary line**
- **Found during:** Task 2 (GREEN step)
- **Issue:** Plan expected the literal string `218 examples, 0 failures, 0 pending`; RSpec 3 only appends `, N pending` when N > 0, so the observed line is `218 examples, 0 failures` (and `grep -c "pending"` over the log is 0, not 1).
- **Resolution:** Absence of the pending clause at the full example count is the 0-pending state; additionally proven by `grep -c "binary not built"` = 0. Verifiers grepping for the literal three-clause string should grep for the two-clause form.
- **Commit:** n/a

**3. [Observation - output format] default progress format prints no example lines**
- **Found during:** Task 2 (gen_proxy presence check)
- **Issue:** Plan expected `grep -c "gen_proxy"` over the run log to be non-zero; with default progress format (dots), passing example identifiers never print.
- **Resolution:** Re-ran with `--format documentation` (display-only; no `--example`/`--tag` filtering, no `.rspec` change — prohibition P2 untouched): all six gen-proxy describe groups appear. The CI command remains the bare `bundle exec rspec`.
- **Commit:** n/a

---

**Total deviations:** 0 auto-fixed (3 zero-impact observations recorded)
**Impact on plan:** None — all acceptance criteria satisfied in substance and (where formatting permitted) in letter.

## Issues Encountered

None. (Pre-existing working-tree state — modified `.planning/config.json` plus several untracked files — predates this plan and was left untouched; only plan-declared files were staged.)

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- Gap #1 (REL-01 "full RSpec suite") closed at the wiring + local-proof level: the structural gate (Task 1) and the behavioral gate (Task 2, `218 examples, 0 failures`, 0 skips) both pass.
- Post-merge confirmation (non-blocking, per plan `<verification>` item 4): once merged to main / PR opened, each Ruby leg log must show the no-pending-clause summary — `gh run view <run-id> --log | grep "examples, 0 failures"`.
- MI-03 (`timeout-minutes` on both ci.yml jobs — and update-tap.yml, which shares the gap) remains a recommended follow-up hardening pass, deliberately out of scope here.

## Self-Check: PASSED

- Task 1 acceptance criteria: STRUCTURE OK (python3 YAML assertion); exactly one `make proxy.build` in ruby-tests ordered `Set up Ruby` → `Build proxy (release)` → `RSpec`; setup-xcode@v1/xcode-version '16' in ruby-tests; swift-tests = 3 steps with 0 proxy.build; matrix `['3.1','3.2','3.3']` + `fail-fast: false`; bare `bundle exec rspec`; `yaml.safe_load` exit 0; 0 `secrets.` / 0 `pull_request_target` / 0 `needs:`. ✅
- Task 2 acceptance criteria: RED 6 pending observed; GREEN `218 examples, 0 failures` exit 0 (0 pending — no clause); `binary not built` count 0; gen_proxy groups present in doc-format log; `git status --porcelain spec/ .rspec` clean. ✅
- Task 3 acceptance criteria: `3.0 dropped at merge 5759c5b` in all three docs (1/1/3); ROADMAP reads `(3.1/3.2/3.3)` + `macos-15`, no `3.0/3.1/3.2/3.3`; SUMMARY lines 13/19/26 assert the 3-version matrix; PLAN.md lines 14/32/69–70 byte-unchanged; 01-VERIFICATION/REQUIREMENTS/STATE untouched. ✅
- Commits exist on `gsd/v0.3.0-milestone`: `9f919a9`, `2a8f602` (+ this file's `docs(01-02): plan summary`). ✅

---
*Phase: 01-test-ci-foundation — Plan 02 (gap closure)*
*Completed: 2026-08-24*
