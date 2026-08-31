---
phase: 06-graph-authority-lockfile-reconciliation
plan: 04
subsystem: diagnostics
tags: [diag-01, doctor, lockfile, drift, static-check, tdd]
status: complete

requires:
  - "06-02 Core::PackageResolved.locate / .pins_or_nil — the canonical locator; the check shares it so `doctor` and `use` cannot disagree about which host graph is authoritative"
  - "06-02 DiffDetector.identity_key — the promoted class method both sides of the comparison are keyed with, so url spelling variants are not reported as drift"
  - "06-03 Installer#reconcile_lockfile_from_host_graph — the remedy the fix hint points at, and the reason drift is a :warn rather than a :fail"
provides:
  - "Core::Diagnostics `lock_graph_fidelity` — the eighth registered check; set-membership AND revision/version comparison of spm-cache.lock against the canonical host Package.resolved, static, never :fail on any input shape its spec exercises"
  - "spec/doctor_lock_fidelity_spec.rb — 13 examples: zero-overlap, version drift, revision-before-version both directions, agreement, no-lockfile, no-xcodeproj, unlocatable host graph, unreadable host graph, unreadable lock, local package, zero-pin guard, no-shell-out"
  - "spec/doctor_spec.rb `spm-cache doctor with a drifted lock` — the DIAG-01 exit contract asserted rather than inferred from reading doctor.rb"
affects:
  - "Any future check registration — the three count/order gates in doctor_spec now state 8 / 8 markers / 9 JSON checks; a ninth check breaks them again by design"
  - "The reference project — re-running `spm-cache doctor` there is now the cheap field verification of Plan 03's reconciliation, needing no build"

tech-stack:
  added: []
  patterns:
    - "A diagnostics check whose every input path returns a status: `run_check` converts a raise into a :fail and `doctor` exits 1 on any :fail, so a malformed file in a user's repo must never become a CI failure"
    - "Verdict severity chosen from remedy availability, not from defect severity: the remedy is automatic on the next non-fast-path `use`, so drift is a :warn"
    - "Comparison value mirrors the consumer's own precedence (revision before version, per UmbrellaGenerator/Lockfile.swift) so the check tests the real emitted pin rather than a parallel notion of equality"

key-files:
  created:
    - spec/doctor_lock_fidelity_spec.rb
  modified:
    - lib/spm_cache/core/diagnostics.rb
    - spec/doctor_spec.rb
    - tools/spm-cache-proxy/Sources/Core/Generator/UmbrellaGenerator.swift

key-decisions:
  - "Lock entries with no `repositoryURL` are excluded from the comparison — lock side only. SwiftPM structurally never lists a local / `path_from_root` package in Package.resolved, so counting one as `only_in_lock` would make the check warn forever on any project holding a local package. This is a research-grounded REFINEMENT of D-06, not an incomplete membership check: the host side keys every pin unconditionally and `only_in_host` is still computed, so drift on remote packages is undiminished in both directions."
  - "The zero-pin guard reports a suspected Package.resolved schema mismatch instead of 100% drift. A pre-v2 (`object.pins`) file parses to zero pins, which would otherwise name the entire lock as drifted. It fires only when host pins are empty AND the lock holds >= 1 repositoryURL entry — the same asymmetry Plan 03's drop guard uses (T-06-16), for the same retain-over-erase reason."
  - "The check bails to :ok when the injected config does not respond to `lockfile_path` / `project_dir` — required, see Deviations: a verifying instance_double raises MockExpectationError, which is not a StandardError and would escape run_check's capture."
  - "Registered LAST in core/diagnostics.rb so the seven existing report positions are unchanged and the doctor_spec deltas are append-only."
  - "Message names packages (ROADMAP success criterion 3) with a 5-label cap plus an 'and N more' tail, so a 70-package graph does not produce an unreadable report line."
  - "The `only_in_host` list is labelled from the host pin's `identity`, not from the lock — those keys have no lock entry to label from."

requirements-completed: [DIAG-01]
requirements-note: >
  DIAG-01 is delivered in full and marked Complete. `spm-cache doctor` now reports whether
  spm-cache.lock agrees with the host Package.resolved, names each disagreeing package, and runs no
  build, resolve, or shell-out (asserted directly with `Core::Sh.not_to receive(:capture_output)`).
  Every CONTEXT.md semantic locked for it exists in source with a named regression example: set
  membership AND version (D-06, `warns on zero overlap`), :warn with the `spm-cache use` fix hint
  (D-07, plus the command-level exit-0 assertion), revision-before-version precedence in both
  directions (D-08), :ok when no lockfile exists (D-09), and static-only operation (D-10).

coverage:
  tests-added: 14
  suite: "303 examples, 0 failures (baseline 289 + 14; no existing spec assertion loosened)"

metrics:
  duration: ~6m
  completed: 2026-08-27
  tasks: 3
  commits: 4

actuals:
  tokens: 10190
  tasks: 3
  commits: 4
---

# Phase 6 Plan 04: DIAG-01 `lock_graph_fidelity` Doctor Check Summary

Completed DIAG-01: the invariant Phase 6 establishes is now user-observable without spending a
build. `spm-cache doctor` reads two files, reports whether `spm-cache.lock` describes the host's
current resolved graph, names every package that disagrees, and returns `:warn` so no CI pipeline
goes red before a first `spm-cache use` has run.

## What Was Built

One check appended to `Core::Diagnostics`, registered eighth and last:

| Property | Decision | Implementation |
|---|---|---|
| Comparison basis | D-06 | `only_in_lock`, `only_in_host`, `value_drift` — set membership in both directions **and** value, never versions over the intersection alone |
| Verdict | D-07 | `:warn` on any non-empty collection; `:ok` otherwise. Never `:fail` on any input shape the spec exercises |
| Value precedence | D-08 | `revision` when present and non-empty, `version` otherwise, computed on each side independently |
| No lockfile | D-09 | `:ok` — a fresh project is not drifted |
| Static | D-10 | two `File.read`s and two `JSON.parse`es; no `Core::Sh`, no `Xcodeproj`, no resolve |
| Locator | T-06-16/17 | `Core::PackageResolved.locate` + `.pins_or_nil` — the same locator the reconciler uses |
| Keying | — | `Core::DiffDetector.identity_key` on both sides, so ssh/https and `.git`-suffix spellings compare equal |
| Fix hint | D-07 | "Run `spm-cache use` to reconcile spm-cache.lock with the host Package.resolved" |

Seven small private class methods carry the parts worth naming: `lock_graph_fidelity`,
`lock_remote_packages`, `host_pin_map`, `compare_lock_to_host`, `lock_pin_value` /
`host_pin_value`, and the `drift_part` / `summarize_labels` / `lock_label` / `host_label` message
helpers.

## The measured case the check exists to catch

`warns on zero overlap between the lock and the host graph` builds exactly the reference-project
shape recorded in 06-M1-MEASUREMENT.md: **8 locked packages, 17 host pins, intersection zero.** A
version-only comparison over the intersection reports "0 drifted" on that input — the lock
describes an application that no longer exists and the check would pass it. The example asserts
`:warn` and that both a locked label (`locked1`) and a host label (`hosted1`) appear in the
message, so the failure mode is caught in both directions rather than only as "8 unknown packages
missing".

## The local-package exclusion is a refinement of D-06, not a gap in it

**Lock entries with no `repositoryURL` are skipped when building the lock-side map.** This is
deliberate and research-grounded, and it does not weaken membership checking:

- SwiftPM structurally never lists a local / `path_from_root` package in `Package.resolved`
  (the same fact that made Plan 03 key its drop rule on `#live_packages` rather than on pins,
  T-06-07). A local package is therefore *always* absent from the host side.
- Without the exclusion, every project holding a local package would report that package as
  `only_in_lock` on every `doctor` run, forever, with no action that could ever clear it. That is
  a category difference between the two files, not staleness — and a permanently-warning check is
  a check users learn to ignore.
- The exclusion is one-sided. The host side keys **every** pin unconditionally and `only_in_host`
  is computed and reported unconditionally, so a package the host graph holds and the lock lacks
  is still named. Drift detection on remote packages is undiminished in both directions.

Covered by `does not treat a local package as drift`: the lock holds one remote package matching
the host graph plus one `path_from_root` package the host graph cannot contain; the verdict is
`:ok` and `LocalKit` does not appear in the message.

## The zero-pin guard

A pre-v2 (`object.pins`) `Package.resolved` parses to zero pins under the v2+ `pins` key. Without
a guard, an 8-package lock against that file yields `8 only in the lock` — a 100%-drift false
positive naming every package the user has, caused entirely by a schema the parser does not read.

`compare_lock_to_host` therefore returns early with `:warn` naming the suspected schema mismatch
and the lock's remote entry count, and never enumerates the lock as drift. It fires only when host
pins are empty **and** the lock holds at least one `repositoryURL` entry, mirroring Plan 03's
drop-pass guard (T-06-16). Covered by
`does not report whole-lock drift when the host graph parses to zero pins`, which asserts the
message contains `zero pins` and does **not** match `/only in lock/`.

One acceptance criterion reads "every `:warn` message names at least one package label". That
holds for every *drift* warning and is asserted in each. It deliberately does not hold for this
one path: naming the packages here is precisely the false positive the guard exists to suppress.
The message reports the lock's entry count instead.

## Deviations from Plan

### The check must guard `cfg.respond_to?(:lockfile_path)` — Rule 3, blocking

The plan's literal shape (`cfg = config || Config.instance`, then read `cfg.lockfile_path`) breaks
two existing `doctor_spec` examples that constraint 11 forbids editing:

```
remote_backend_connectivity returns :ok local-only when no remote is configured
remote_backend_connectivity returns :ok configured when a remote key exists
```

Both inject `instance_double(SPMCache::Core::Config, load: nil, raw: {})` and then call
`run_all`, which runs **every** registered check against that double. Calling `lockfile_path` on a
verifying double whose only stubs are `load` and `raw` raises
`RSpec::Mocks::MockExpectationError` — which inherits from `Exception`, **not** `StandardError`, so
it escapes `run_check`'s `rescue StandardError` entirely and fails the example outright rather than
degrading to a `:fail`.

Fix: the check returns `[:ok, 'No project context available — skipping lock/host graph
comparison']` unless the config responds to both `lockfile_path` and `project_dir`. Verified
empirically that a verifying `instance_double`'s `respond_to?` answers `true` only for stubbed
methods (`:raw` → true, `:lockfile_path` → false), so the guard discriminates correctly rather
than merely suppressing.

This is also the semantically right shape independent of the specs: `run_all(config:)` accepts an
arbitrary config object, and a config that cannot report project paths cannot answer "does my lock
describe my graph?". Both examples pass unedited.

### RED honesty: 13 of 14 new examples were genuine RED; the 14th is a mutation-verified guard

| Task | Genuine RED (failed before implementation) | Passed on write |
|---|---|---|
| 1 | All 13 examples in `spec/doctor_lock_fidelity_spec.rb` (`13 failures` before, `0 failures` after) | — |
| 2 | — | `reports the drift, renders the fix hint, and never reaches the exit branch` |

Task 2's exit-contract example could not be genuine RED: the check it asserts on was committed in
Task 1, so it passed the moment it was written. Rather than label it RED evidence, its bite was
proven by mutation — flipping the drift return from `:warn` to `:fail` in `diagnostics.rb` makes it
fail with `received: 1 time with arguments: (#<...Doctor...>, 1)` from `doctor.rb:42`. The mutation
was reverted before commit (`git diff --stat` clean against the Task 1 commit).

RED-before-GREEN commit order holds: `test(06-04)` (`fb38e65`) precedes `feat(06-04)` (`e6e9bc4`).

### One assertion in the JSON example was extended and then reverted

While updating `parsed['checks'].length` 8 → 9 I also added `lock_graph_fidelity` to the
name-inclusion list that example iterates. That would have been a fourth assertion change, which
constraint 11 forbids even though it strengthens rather than loosens. Reverted before commit; only
the count changed. The registry-order example (updated, as one of the three named) is where the new
name is pinned.

## The three breaking gates, updated in the registration commit

All three landed in `e6e9bc4` alongside `diagnostics.rb`, so the eighth check does not read as an
unrelated regression, and none was loosened from `eq` to inclusion:

| Site | Before | After |
|---|---|---|
| `doctor_spec.rb:176` order-sensitive name array | 7 names, exact `eq` | 8 names ending `lock_graph_fidelity`, still exact `eq` |
| `doctor_spec.rb:201` `marker_lines.length` | `eq(7)` | `eq(8)`; the `3 failures` expectation is unchanged and still passes — inside the spm-cache repo there is no `spm-cache.lock`, so the new check returns `:ok` and adds no failure |
| `doctor_spec.rb:250` `parsed['checks'].length` | `eq(8)` | `eq(9)` (eight built-ins plus the injected `kaboom_json`) |

**`spec/doctor_companion_version_spec.rb` needed no edit — verified, not assumed.** It was read in
full: it is binary-gated on `spm-cache-proxy --version` and carries no registry count or order
assertion of any kind.

## The `UmbrellaGenerator.swift` false premise

The comment justified revision-pinning with "Package.resolved is consistent, so the commit
satisfies every parent's range by construction" — presenting the host graph's internal consistency
as an unconditional structural given, which made a revision pin look safe regardless of the
lockfile's age. Phase 6 falsified that: the guarantee is a property of the **lockfile handed to the
generator**, not of `Package.resolved`, and it is conditional on two things the corrected comment
now states:

1. the pin was **reconciled** from the host's `Package.resolved` on this run (Plan 03) — a lock
   frozen at first creation carries a commit that no longer satisfies any parent's range;
2. the file reconciliation read was the **canonical**
   `project.xcworkspace/xcshareddata/swiftpm/Package.resolved` (Plan 02), not whichever copy a
   recursive search answered with first.

Both words are greppable as required. The change is comment-only, proven mechanically: the
executable-Swift diff filter
(`git diff -U0 | grep '^[+-]' | grep -v '^[+-][+-]' | grep -Ev '^[+-]\s*//'`) finds nothing. The
skip condition, the pin emission and `versionRequirement` are untouched. No plan number, phase
number or requirement ID appears in the comment. `make proxy.build` succeeds and the three
`gen_proxy_*` specs are green against the rebuilt binary.

## Threat Mitigations Applied

- **T-06-15 (check raising on malformed input becomes a `:fail` and reddens CI)** — every input
  path returns a status: missing lock, no `.xcodeproj`, unlocatable host graph, unreadable host
  graph, unreadable lock, and a config that cannot report paths. Two examples assert
  `status).not_to eq(:fail)` on truncated JSON on each side. The `lock_remote_packages` parse is
  wrapped in `rescue JSON::ParserError, TypeError`; the host side goes through the already-tolerant
  `pins_or_nil`.
- **T-06-15 (exit contract)** — `spm-cache doctor with a drifted lock` runs the real command and
  asserts `not_to receive(:exit)`, plus `Summary: 0 ok, 1 warning, 0 failures`. Mutation-verified.
- **T-06-16 (reading a different `Package.resolved` than the reconciler)** — `PackageResolved.locate`
  is the only lookup. `grep -c 'PackageResolved' lib/spm_cache/core/diagnostics.rb` → 2,
  `grep -c 'DiffDetector\.identity_key'` → 2. No parallel glob exists in the file.
- **T-06-17 (path disclosure in CI logs)** — messages emit package labels, counts, and at most the
  located resolved path (already surfaced elsewhere). The no-`.xcodeproj` message says "in this
  directory" rather than interpolating the absolute `project_dir`.
- **T-06-18 (shelling out)** — `does not shell out` asserts
  `expect(SPMCache::Core::Sh).not_to receive(:capture_output)` around a run over the drifted
  fixture and still expects `:warn`, so the check is proven to complete without the seam.
  `grep -c 'Xcodeproj' lib/spm_cache/core/diagnostics.rb` → 0.
- **T-06-19 (drift reported without naming packages)** — every drift `:warn` names labels; the
  zero-overlap example asserts a label from each side appears.

## Known Stubs

None. No placeholder, hardcoded-empty, or unwired path was introduced.

## Verification Evidence

| Check | Result |
|---|---|
| `bundle exec rspec spec/doctor_lock_fidelity_spec.rb` | 16 examples, 0 failures (13 new + 3 from `spec_helper`) |
| `bundle exec rspec spec/doctor_spec.rb spec/doctor_companion_version_spec.rb spec/doctor_lock_fidelity_spec.rb` | 0 failures |
| Registry assertion (`last.name == 'lock_graph_fidelity'`, `size == 8`) | pass |
| `make proxy.build` | Build complete (3.79s) |
| `bundle exec rspec` (full, after rebuild) | **303 examples, 0 failures** |
| `UmbrellaGenerator.swift` non-comment diff filter | no output — comment-only |
| `grep -q canonical` / `grep -q reconciled` / `! grep -q 'by construction'` | all pass |

## Commits

| Commit | Type | Content |
|---|---|---|
| `fb38e65` | test | 13 failing `lock_graph_fidelity` examples (RED) |
| `e6e9bc4` | feat | the check + the three `doctor_spec` count/order gates, atomically |
| `daddfc3` | test | the `:warn`-exits-0 command-level exit contract |
| `6a4fcf1` | docs | `UmbrellaGenerator.swift` false-premise correction (comment-only) |

## Self-Check: PASSED

All four changed/created source paths exist on disk, all four commit hashes are present in
`git log --all`, `spec/doctor_lock_fidelity_spec.rb` is 198 lines (min_lines 110), and the full
suite is 303 examples / 0 failures.
