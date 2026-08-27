---
phase: 06-graph-authority-lockfile-reconciliation
plan: 05
subsystem: lockfile-reconciliation
tags: [fid-01, fid-06, gap-closure, host-graph, locator, parent-tier, tdd]
status: complete

requires:
  - "06-02 Core::PackageResolved.locate — the single locator whose four tiers (canonical, workspace, under-root, parent) this plan makes the installer see in full, by asking the detector rather than by acquiring the detector's posture"
  - "06-02 the recorded acceptance criterion at 06-02-PLAN.md:431 — `parent_fallback: true` appears in exactly one file; this plan keeps that true"
  - "06-03 Installer#reconcile_lockfile_from_host_graph — the consumer that resolved the host graph independently and could therefore disagree with DiffDetector"
provides:
  - "Core::DiffDetector#host_graph_path — public, nil-safe memoized: one answer per detector to 'where is the host Package.resolved', and still the only site in lib/ that passes parent_fallback"
  - "SPMCache::Installer#host_graph_detector — the run's single DiffDetector; detect_diff, reconcile_lockfile_from_host_graph and generate_lockfile_from_resolved all read from it"
  - "spec/lockfile_reconciliation_spec.rb `describe 'parent-directory tier project shape'` — 4 examples: drift closure, resolve-once structural guard, first-run seeding, malformed-parent-tier posture pin"
affects:
  - "Any future host-graph consumer added to installer.rb — `resolves the host graph exactly once per run` fails the moment it locates independently, so the invariant is a test rather than a review convention"
  - "Projects whose Package.resolved sits beside the .xcodeproj (SwiftPM-rooted dir with a generated project) — the installer now reconciles and seeds on that shape instead of warning and declining forever"
  - "core/diagnostics.rb is NOT affected — it keeps its own fallback-free locator, a known fail-safe asymmetry recorded below"

tech-stack:
  added: []
  patterns:
    - "Structural agreement over aligned postures: when two components must agree about a fact, delete one of the two answers rather than making today's answers coincide. Divergence then costs a test failure instead of a code review."
    - "Memoize on `defined?`, not `||=`, when nil is a legitimate answer — `||=` re-runs the lookup forever for exactly the input whose lookup is slowest (all four locator tiers missing)."
    - "Widening a call site's REACH is independent of widening its TOLERANCE: the seeding path now sees the parent tier and still raises on a malformed graph, pinned by a positive grep plus an example."
    - "Obtaining a located path must not parse it, so a guard that distinguishes 'unreadable' from 'empty' can still run before any parse."

key-files:
  created: []
  modified:
    - lib/spm_cache/core/diff_detector.rb
    - lib/spm_cache/installer.rb
    - spec/lockfile_reconciliation_spec.rb

key-decisions:
  - "Chose fix shape (C) resolve-once-and-share over (A) pass parent_fallback from the installer and (B) remove it from DiffDetector. (A) leaves three independent resolvers so the next call site can diverge identically, and puts parent_fallback in two files, breaking 06-02-PLAN.md:431. (B) regresses real pre-Phase-6 detection that spec/package_resolved_spec.rb:65 asserts. (C) removes the second and third resolvers instead of aligning them."
  - "host_graph_path is memoized on `defined?(@host_graph_path)` rather than `||=`. Verified empirically: a nil answer is computed once and stays stable across three calls; `||=` would have re-globbed all four tiers on every call."
  - "host_graph_detector is lazy, not built in `initialize`. run_reconcile_only(diff:) injects @diff and reaches sync_lockfile without detect_diff ever running, which an eager detector would not break but which makes laziness the honest contract."
  - "Guard order in reconcile_lockfile_from_host_graph is unchanged and deliberate: path (no parse) -> pins_or_nil unreadable guard + warn/return -> lock_project_data -> live_packages. Fetching the live set earlier would convert D-04's warn-and-degrade into a raise (T-06-22)."
  - "WINDOWS #5 left open on purpose even though this plan edits the very line above it — see `## WINDOWS #5` below, including a decision-fidelity tension against D-04 that the deferral record did not previously state."

requirements-completed: [FID-01, FID-06]
requirements-note: >
  FID-01 and FID-06 were already marked satisfied by Plans 02-03; this plan closes the single
  project shape on which FID-01's success criterion did not actually hold. Criterion 1 ("after a
  non-fast-path run, re-running DiffDetector returns an empty diff") now holds on every shape the
  locator can resolve, in both the lock-already-exists and no-lock-yet forms, each proven by an
  example that reconstructs a fresh DiffDetector and asserts it empty. FID-06 (the nested stale
  copy defect class) is undiminished: the parent tier still passes `exclude_under: project_path`.

coverage:
  tests-added: 4
  tests-red-before-fix: 4
  suite: "307 examples, 0 failures (baseline 303 + 4; zero lines removed from any spec file)"

metrics:
  duration: ~12m
  completed: 2026-08-27
  tasks: 2
  commits: 2

actuals:
  tokens: 15238
  tasks: 2
  commits: 2
---

# Phase 6 Plan 05: One Host-Graph Answer Per Run Summary

Collapsed three independent host-graph resolvers inside `Installer` into one memoized per-run
answer, closing the single gap in `06-VERIFICATION.md`: on a project whose `Package.resolved` is
reachable only through the locator's parent-directory tier, `DiffDetector` reported drift that the
reconciler declined to close — permanently, on every subsequent run.

## The gap, and why it was permanent

`DiffDetector` located the host graph with the parent tier enabled; the reconciler and the first-run
seeder did not. `locate(p)` and `locate(p, parent_fallback: true)` return early and identically on
tiers 1-3, so the parent tier was the entire divergence surface — but on that one shape the detector
found a file the reconciler could not, warned "No Package.resolved found", and returned. The lock
never moved, so the next run computed the same non-empty diff, forever. With no lock at all, the
seeder found nothing either, so no lock was ever written.

## What was built

| Site | Before | After |
|---|---|---|
| `DiffDetector#find_package_resolved` (private) | locator call per `live_packages` invocation | promoted to public `host_graph_path`, memoized on `defined?`, nil-safe |
| `Installer#detect_diff` | built a detector inline, then discarded it | reads `host_graph_detector` |
| `Installer#reconcile_lockfile_from_host_graph` | own `locate` + a **second** `DiffDetector.new` for the live set | both read the shared detector |
| `Installer#generate_lockfile_from_resolved` | own `locate` | reads the shared detector's path; parse still strict |

Net: `installer.rb` holds **zero** direct locator calls and **one** `DiffDetector.new`. The
duplicate detector took a redundant `Xcodeproj::Project.open` and a redundant lockfile read with it.

## Structural agreement, not aligned postures

The root cause was "two independent resolvers can disagree", so the fix removed the second and third
resolvers rather than making their answers coincide today. Shape (A) — pass `parent_fallback: true`
from the installer's own calls — was rejected on the record: it restores agreement now while leaving
the next call site free to diverge identically, and it puts `parent_fallback` in two files, breaking
the recorded acceptance criterion at `06-02-PLAN.md:431`. Shape (B) — remove the parent tier from
`DiffDetector` — was rejected because it trades a convergence bug for a detection bug, regressing
behavior `spec/package_resolved_spec.rb:65` asserts.

One claim in the gap brief did not survive source reading and is corrected here: `installer.rb:156`
(the reconciler) is the **tolerant** site — it reads `pins_or_nil` and warns. The **strict** `pins`
accessor lives at `installer.rb:293` in `generate_lockfile_from_resolved`. Those are two different
call sites with two deliberately different postures, and both were preserved distinctly.

## The behavior delta, stated plainly

**The installer now accepts a parent-level `Package.resolved` it previously ignored.** This was
widened deliberately, and three properties already in the locator bound it:

- `sandboxed?` drops any candidate whose path relative to the search root contains `spm-cache`, so
  the hazard `06-RESEARCH.md` §Q1 point 3 measured on the reference project — reading spm-cache's
  own generated `umbrella`/`proxy` resolved files as "the host graph" — cannot occur (T-06-20).
- The parent tier passes `exclude_under: project_path`, so the project's own nested stale copy
  cannot re-enter from above. That is the FID-06 defect class, still closed (T-06-21).
- The parent tier is consulted only after tiers 1-3 all miss, so **no project that works today
  changes its answer.**

A consequence worth recording for the next reader: because `sandboxed?` excludes everything under
`spm-cache/`, the memoized path can never point inside the sandbox that `recreate_dirs` wipes
between `detect_diff` and `sync_lockfile`. That, plus the source fact that `Config#load` writes only
`@config_path`/`@raw` and `lockfile_path` derives from `project_dir` alone, is why memoizing the
detector across `ensure_config_file` cannot serve a stale path (T-06-25).

## Seeding path: reach widened, tolerance unchanged

`generate_lockfile_from_resolved` now sees the parent tier, so a first run on a parent-tier-only
project seeds `spm-cache.lock` instead of writing nothing. It still reads pins through the strict
accessor that propagates `JSON::ParserError` / `TypeError`, so a malformed host graph raises out of
`use` rather than seeding a lock claiming the project has no packages — the lock-erasure path
`06-RESEARCH.md` §Q1 point 2 names (T-06-23). Pinned two ways: a positive grep for
`PackageResolved.pins(` in `<verify>`, and the `raises rather than seeding an empty lock when a
parent-tier host graph is malformed` example.

## RED evidence — 4 of 4 genuine

All four examples were observed failing against the tree before the corresponding `lib/` edit, each
with a real behavioral failure rather than a `NoMethodError` from a not-yet-existing symbol.

| # | Example | Actual pre-fix failure |
|---|---|---|
| E1 | reconciles a project whose host graph is reachable only through the parent-directory tier | `(SPMCache::Core::UI).warn("No Package.resolved found for Fake.xcodeproj; leaving spm-cache.lock untouched.")` — expected 0 times, received 1 time, raised from `installer.rb:158` |
| E2 | resolves the host graph exactly once per run | `(SPMCache::Core::PackageResolved (class)).locate(...)` — expected 1 time, received 2 times, from `installer.rb:156` |
| E3 | seeds a first-run lock from a host graph reachable only through the parent-directory tier | `expect(File.exist?(lockfile_path)).to be(true)` — `expected true, got false` (no lockfile written at all) |
| E4 | raises rather than seeding an empty lock when a parent-tier host graph is malformed | `expected JSON::ParserError but nothing was raised` |

Two honesty notes on the RED, since the plan predicted slightly different text:

1. **E2 reported "received: 2 times", not the 3 the plan's premise measured.** Both numbers are
   correct for different observations. RSpec's `receive(:locate).once` fails at the moment of the
   second call, so the third (the reconciler's own second detector) never happens. The planner
   measured 3 by counting without the constraint aborting the run. The RED is genuine either way —
   the assertion the fix must satisfy is "exactly one", and pre-fix it was not one.
2. **E1's warn assertion fails fast, masking its version and fresh-diff assertions.** The failure
   arises at the `return` in the unreachable-graph guard, which is precisely what leaves the lock at
   `1.0.0` / `rev-old` and the fresh diff non-empty — mechanically determined by the early return,
   and recorded as measured by the planner's hermetic reproduction. Post-fix all three assertions
   pass together.

Additionally verified empirically rather than asserted: `host_graph_path` computes a **nil** answer
once and returns it stably across repeated calls (`answer=nil stable=true locate_calls=1`). Under
`||=` that same probe would report `locate_calls=3`, which is the mutation proof that the
`defined?`-guard is load-bearing and not stylistic.

## Guard order — T-06-22

Unchanged and re-verified in the final diff: path (line 168, performs no parse) → `pins_or_nil`
unreadable guard with warn-and-return → `lock_project_data` → `live_packages`. Both pre-existing
D-04 examples (`leaves the lock untouched when Package.resolved is unreadable` and `... is missing`)
pass **unedited**, each asserting exactly one warn and a byte-identical lock.

## WINDOWS #5 — left open, with a tension the deferral record did not name

`diff_detector.rb` parses the host graph unguarded (now at the line reading `host_graph_path`). Two
of the three original deferral reasons no longer apply: `core/diff_detector.rb` IS in this plan's
`files_modified`, and the change is no longer unrelated to the work. **The third stands and is why
it stays open:** routing that parse through the tolerant accessor flips `DiffDetector` from
raise-loudly to silently-degrade for *every* caller of `detect`, and makes the printed summary
report spurious removals ("-8 packages") for a graph that is merely unreadable. That is a
posture-and-UX decision, not a gap closure.

Carried forward for the next planner, as analysis rather than conclusion: **D-04 is a locked
decision reading "never crash", and for truncated input spm-cache currently does crash.** The
reconciler's guard is correct but field-unreachable for that one shape, because `detect_diff` raises
first. So #5 is a decision-fidelity gap against D-04, not merely a robustness nice-to-have — which
strengthens the case for a small dedicated follow-up plan. Task 1's guard order was specified so
that closing #5 later needs no rework here.

## Known asymmetry — `core/diagnostics.rb`, unfixed and fail-safe

A fourth resolver lives at `core/diagnostics.rb:83` and calls the locator **without** the parent
tier, so `spm-cache doctor` on a parent-tier-only project reports `:ok — Host Package.resolved could
not be located` rather than comparing. Out of scope and left alone: it is fail-safe (never `:fail`,
never blocks CI), it is asserted by `spec/doctor_lock_fidelity_spec.rb:180`, the gap report does not
name it, and DIAG-01 is Complete. After this plan the lock on that shape is reconciled on every
non-fast-path run, so doctor's silence there now describes a lock that **agrees** rather than one
that has drifted unnoticed.

## Deviations from Plan

**1. [Finding, not auto-fixed] Task 1's `<verify>` grep asserts a condition Task 2 delivers**

- **Found during:** Task 1 verification
- **Issue:** Task 1's `<verify>` and acceptance criteria require
  `grep -c 'PackageResolved\.locate'` in `installer.rb` to be **0**, but Task 1's `<action>` scopes
  the reconciler only — the seeding path's call is Task 2's edit. After Task 1 the count is
  necessarily 1.
- **Resolution:** Did **not** pull Task 2's edit into Task 1. Doing so would have destroyed Task 2's
  RED-first discipline, which hard constraint 6 explicitly requires. Verified instead that both of
  Task 2's examples remain genuinely RED after Task 1's fix (they do — the seeding path still
  resolved `nil`), captured that RED, then satisfied the grep at Task 2. The gate reads 0 now.
- **Files modified:** none (sequencing decision only)
- **Commit:** n/a — recorded as a plan-internal inconsistency for the phase verifier

No other deviations. No Rule 1/2/3 auto-fixes were needed: the plan's source claims all held on
reading, including the two it had already corrected (the tolerant-vs-strict site identities and the
absence of any `DiffDetector.new` outside `installer.rb`).

## Verification

| Gate | Result |
|---|---|
| `bundle exec rspec spec/lockfile_reconciliation_spec.rb spec/diff_detector_spec.rb spec/installer_use_fast_path_spec.rb` | 38 examples, 0 failures |
| `bundle exec rspec spec/watch_spec.rb spec/watch_loop_spec.rb spec/watch_signals_spec.rb spec/init_spec.rb spec/doctor_spec.rb spec/doctor_lock_fidelity_spec.rb spec/package_resolved_spec.rb` | 78 examples, 0 failures |
| `make proxy.build` | `Build complete! (4.97s)` |
| `bundle exec rspec` | **307 examples, 0 failures** (baseline 303 + 4) |
| locator calls in `installer.rb`, comments excluded | 0 |
| `parent_fallback` in `lib/` outside `package_resolved.rb` + `diff_detector.rb` | 0 |
| `DiffDetector.new` in `installer.rb` | 1 |
| `PackageResolved.pins(` in `installer.rb` | present |
| `git diff --stat` | exactly 3 files: `core/diff_detector.rb`, `installer.rb`, `lockfile_reconciliation_spec.rb` |
| spec lines **removed** | 0 — no pre-existing assertion edited, renamed, or reordered |

`find_package_resolved` still appears in `command/use.rb` and `command/init.rb`, but those are each
that file's own private method, not the removed `DiffDetector` one — both explicitly out of scope.
The removed private method has no remaining caller anywhere in `lib/` or `spec/`.

## Commits

| Task | Commit | Subject |
|---|---|---|
| 1 | `5f618a7` | `fix(06-05): resolve the host graph once per run so the reconciler and the detector agree` |
| 2 | `fb1fcb8` | `fix(06-05): seed a first-run lock from the run's single host-graph answer` |

## Known Stubs

None. No placeholder values, no skipped tests, no unrun `<verify>` steps — every automated check in
both tasks was executed, and its output is recorded above.

## Self-Check: PASSED

All three modified source files exist; both commits (`5f618a7`, `fb1fcb8`) are reachable in
`git log`; every `must_haves.artifacts` `contains` token is present (`host_graph_path`,
`host_graph_detector`, `parent-directory tier`); `spec/lockfile_reconciliation_spec.rb` is 451 lines
against a `min_lines: 440` floor.
