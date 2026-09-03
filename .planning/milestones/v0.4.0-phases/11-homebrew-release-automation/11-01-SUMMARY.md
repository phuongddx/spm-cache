---
phase: 11-homebrew-release-automation
plan: "01"
subsystem: cli-version-flag
tags: [cli, version, claide, tdd, rel-08]
requires:
  - "SPMCache::VERSION constant (lib/spm_cache/version.rb reads the shipped VERSION file)"
provides:
  - "`spm-cache --version` prints the gem version to stdout and exits 0 (REL-08 CLI half)"
  - "spec/main_version_spec.rb — stdout-capture regression spec pinning the VERSION file as source of truth"
affects:
  - "bin/spm-cache entry path via lib/spm_cache/main.rb (no other argv routing changed)"
tech-stack:
  added: []
  patterns:
  - "argv.first guard before CLAide Command.run (default_subcommand routing bypass)"
key-files:
  created:
  - spec/main_version_spec.rb
  modified:
  - lib/spm_cache/main.rb
decisions:
  - "Intercept sits between load_all and Command.run because CLAide routes a bare --version through the default use subcommand, whose option set rejects the root-only flag"
  - "Spec keeps the plan-mandated no-stub form even though the RED state terminates the rspec run via SystemExit — loud red beats a doctored failure count"
metrics:
  duration: 7m 14s
  completed: 2026-08-30
  tasks_completed: 2
  commits: 2
status: complete
actuals:
  tokens: 265
  tasks: 2
  commits: 2
requirements_completed: [REL-08]
---

# Phase 11 Plan 01: `spm-cache --version` intercept Summary

One-line: `spm-cache --version` now prints the VERSION-file gem version and exits 0, via a 2-line argv guard in `Main.run` placed before CLAide's default-subcommand dispatch, delivered RED-then-GREEN.

## What Was Built

`lib/spm_cache/main.rb` gained a single guarded line between `load_all` and `Command.run`:

```ruby
return puts(SPMCache::VERSION) if argv.first == '--version' # before default_subcommand routing
```

plus a blank line after the guard clause (RuboCop Layout/EmptyLineAfterGuardClause).
`spec/main_version_spec.rb` pins the behavior with two stdout-capture examples: one interpolating
`SPMCache::VERSION`, one building the expectation from `File.read('VERSION').strip` — proving the
printed value is the VERSION file's contents (single source of truth), not a hardcoded literal.

## RED (Task 1 — what failed, why)

- Reproduced the field bug before writing anything: `bundle exec bin/spm-cache --version` prints
  the CLAide unknown-option banner and **exits 1** (root cause per 11-RESEARCH Pitfall 1 / Pattern 6:
  `Command.parse` routes a bare `--version` through `default_subcommand` (`use`), whose option set
  lacks the root-only flag, so `validate!` fails and `handle_error` calls `exit 1`).
- New spec committed first (`test(11-01)`): `bundle exec rspec spec/main_version_spec.rb` exits
  non-zero; the run under test raises SystemExit instead of printing the version — failure for the
  proven reason, not a syntax/load error (dry-run registers all 5 examples cleanly).

## GREEN (Task 2 — the intercept)

- After the 2-line change: targeted spec **5 examples, 0 failures**; `bundle exec bin/spm-cache
  --version` prints `0.3.0` and **exits 0**; full suite **418 examples, 0 failures** (416 baseline
  measured 2026-08-30 + 2 new) — other-argv dispatch untouched.
- RuboCop: 0 offenses on `spec/main_version_spec.rb`; `lib/spm_cache/main.rb` retains only the 3
  pre-existing offenses (double-quoted requires at lines 3-4, module documentation) that predate
  this change and are out of scope.

## REFACTOR

None needed — the production change is two lines; no cleanup warranted.

## Commit List

| Commit   | Type | Content |
|----------|------|---------|
| `0ed90e4` | test(11-01) | `spec/main_version_spec.rb` — 2 failing examples (RED) |
| `b393048` | feat(11-01) | `lib/spm_cache/main.rb` — `--version` intercept (GREEN) |

## TDD Gate Compliance

Both gates present and ordered in `git log`: `test(11-01)` (0ed90e4) precedes `feat(11-01)`
(b393048). No missing-gate warning required.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Lint] Cleared the 2 RuboCop offenses introduced by the new guard line**
- **Found during:** Task 2 verification
- **Issue:** `Style/StringLiterals` (double-quoted `"--version"`) and
  `Layout/EmptyLineAfterGuardClause` fired on the newly inserted line under default RuboCop config
  (the repo ships no `.rubocop.yml`).
- **Fix:** Single-quoted flag literal + blank line after the guard clause.
- **Files modified:** `lib/spm_cache/main.rb`
- **Commit:** `b393048`

### Documented Deviations (not auto-fixable within plan constraints)

**2. [Acceptance-shape deviation] RED manifests as SystemExit run-termination, not "2 reported failures"**
- **Found during:** Task 1 verification
- **Issue:** Task 1's acceptance criteria expected `bundle exec rspec spec/main_version_spec.rb` to
  "exit non-zero reporting 2 failures". In this repo's RSpec setup, CLAide's `exit 1` raises
  SystemExit inside the example block, which terminates the rspec run before failure accounting:
  observed output is `4 examples, 0 failures` with exit code 1 (verified mechanism with a
  controlled `expect { exit 1 }.to output(...)` probe spec). The examples do fail for exactly the
  right reason — no version output, unknown-option failure — and the exit code is non-zero.
- **Why not "fixed":** Making RSpec report 2 tidy failures would require rescuing/stubbing
  SystemExit around the call, which the plan explicitly forbids ("Do not stub or mock anything;
  call the real class method"). Loud-and-honest beats a doctored failure count.
- **Resolution:** None needed for the goal; GREEN passes cleanly (no SystemExit occurs after the
  intercept exists). Recorded to the broken-windows ledger as a deviation.
- **Commits:** `0ed90e4` / `b393048`

## Auth Gates

None — no authenticated operations in this plan (gh / secrets / dispatch belong to 11-02 and 11-03).

## Known Stubs

None. No placeholder values, no TODO/FIXME, no unwired data sources introduced.

## Threat Flags

None. The only new surface is exactly the plan's threat_model T-11-CLI-01/02 (one string equality
check on `argv[0]`; prints the already-public gem version) — both registered as `accept`; no
unplanned trust-boundary surface added.

## Self-Check: PASSED

- `spec/main_version_spec.rb` — FOUND
- `lib/spm_cache/main.rb` (modified, guard present between load_all and Command.run) — FOUND
- Commit `0ed90e4` in `git log` — FOUND
- Commit `b393048` in `git log` — FOUND
