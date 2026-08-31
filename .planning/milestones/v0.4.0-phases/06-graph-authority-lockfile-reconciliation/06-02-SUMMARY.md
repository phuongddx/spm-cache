---
phase: 06-graph-authority-lockfile-reconciliation
plan: 02
subsystem: core
tags: [fid-06, fid-01, package-resolved, locator, lockfile, reconciliation, tracer]
status: complete

requires:
  - "06-01 M1 attribution verdict (H-wrongfile 25 / H-lock 0 / H-float 0) — the measurement that made the locator fix blocking rather than cosmetic"
provides:
  - "Core::PackageResolved — the single canonical-preferring locator and strict/tolerant parser for the host Package.resolved (FID-06)"
  - "Core::DiffDetector.identity_key / .normalize_url as public class methods, and #live_packages as a public instance method — the keying and the live set any reconciler must reuse"
  - "Installer#reconcile_lockfile_from_host_graph — version/revision refresh keyed on the live union, saving independently of refresh_consumed_dependencies"
  - "spec/lockfile_reconciliation_spec.rb — the end-to-end fixture Plan 03 extends with drop/add membership"
affects:
  - "Plan 03 — drop/add membership, untouched-key guarantees and the D-04 warn-once land on top of this reconciler and its union basis; the save path is already in place"
  - "Plan 04 — the lock_graph_fidelity doctor check reads the host graph through this locator, so the check and the fix cannot disagree about which file is authoritative"
  - "All five former glob call sites — installer, diff_detector, watcher, init, use — now resolve one answer"

tech-stack:
  added: []
  patterns:
    - "Deterministic tier chain (exact path -> workspace glob -> filtered recursive -> filtered parent) replacing Dir.glob byte order; mtime used only as an intra-tier tie-break"
    - "Strict/tolerant parse split (pins vs pins_or_nil) so each caller keeps its own raise-vs-degrade posture behind one locator"
    - "Path components compared as File::SEPARATOR segments, never as substrings, so a directory whose name merely contains the sandbox name is not rejected"

key-files:
  created:
    - lib/spm_cache/core/package_resolved.rb
    - spec/package_resolved_spec.rb
    - spec/lockfile_reconciliation_spec.rb
  modified:
    - lib/spm_cache/core/diff_detector.rb
    - lib/spm_cache/installer.rb
    - lib/spm_cache/core/watcher.rb
    - lib/spm_cache/command/init.rb
    - lib/spm_cache/command/use.rb

key-decisions:
  - "The locator's preference order is an intentional, observable behavior change at four of five call sites, not an internal refactor — on any project carrying a duplicate Package.resolved, installer, watcher, init and use now read a different file than before (research Open Question 1)"
  - "The legacy unfiltered recursive search is retained as tier 3, so no project that previously found a file stops finding one; only the ORDER changed, plus two exclusions"
  - "The .xcodeproj-component exclusion is scoped to tier 3 only — applying it at tier 4 would silently void diff_detector.rb's pre-existing parent fallback, which legitimately finds <parent>/App.xcodeproj/project.xcworkspace/.../Package.resolved"
  - "Tier 4 instead excludes candidates under project_path, denying the project's own nested stale copy a second entrance through the parent root"
  - "The SANDBOX_DIR exclusion applies to tiers 3 and 4, referencing Core::Config::SANDBOX_DIR rather than an inlined literal — spm-cache's own generated umbrella/proxy resolved files sit one level above the .xcodeproj, inside tier 4's search space (T-06-01)"
  - "Reconciliation keys membership on DiffDetector#live_packages (resolved pins UNION pbxproj refs), never on the pins alone, because Package.resolved never lists local/path packages"
  - "The reconciler calls @lockfile.save itself rather than riding refresh_consumed_dependencies' save, which early-returns when the lock's project key differs from File.basename(@project_path)"
  - "pins (strict) now raises TypeError when the pins value is not an Array, so installer.rb fails loudly instead of calling .map on a String"
  - "FID-01 left Pending: version/revision reconciliation and products[] preservation are delivered, but the drop/add membership rules and the D-04 warn-once that CONTEXT.md locked for FID-01 are Plan 03's scope"

requirements-completed: [FID-06]
requirements-evidenced: [FID-01]
requirements-note: >
  FID-06 is delivered in source and covered by named regression examples: the locator resolves
  the canonical project.xcworkspace path by construction, refuses spm-cache's own generated
  resolved files, and refuses a stale nested .xcodeproj copy from either search root. FID-01 is
  only partially delivered and stays Pending. Its version/revision reconciliation runs on every
  non-fast-path run and provably preserves enriched products[], but a package present in the lock
  and absent from the host graph is still retained, a package present in the host graph and absent
  from the lock is still not added, and an unreadable host graph does not yet warn once. Those are
  the membership semantics CONTEXT.md locked for FID-01; Plan 03 delivers them on top of the union
  basis and save path established here. Marking FID-01 Complete now would tell the verifier the
  lock describes the current graph while removed packages still persist in it.

coverage:
  tests-added: 17
  suite: "275 examples, 0 failures (baseline 258 + 17; no existing spec file modified)"

metrics:
  duration: ~25m
  completed: 2026-08-27
  tasks: 3
  commits: 6

actuals:
  tokens: 18000
  tasks: 3
  commits: 6
---

# Phase 6 Plan 02: Canonical Package.resolved Locator & Lockfile Reconciliation Summary

Closed the M1 root cause by making the canonical `project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
win by construction rather than by `Dir.glob` byte order, collapsed all five duplicated glob sites
onto that one locator, and proved a drifted package reconciles end to end against a fixture whose
nested stale copy agrees with the stale lock.

## What Was Built

**`Core::PackageResolved`** — a four-tier locator plus a strict/tolerant parser split:

| Tier | Source | Filters |
|---|---|---|
| 1 | exact `<root>/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` | none (pure path check, cheaper than the glob it replaces) |
| 2 | `<parent>/*.xcworkspace/xcshareddata/swiftpm/Package.resolved`, sorted | none |
| 3 | recursive `<root>/**/Package.resolved` | rejects a nested `.xcodeproj` component and anything under `SANDBOX_DIR`; newest mtime breaks ties |
| 4 | recursive `<parent>/**/Package.resolved`, only when `parent_fallback: true` | rejects anything under `SANDBOX_DIR` or under `project_path`; newest mtime breaks ties |

`locate` never raises and never `File.expand_path`es its argument. `pins` propagates
`JSON::ParserError`/`TypeError`; `pins_or_nil` returns `nil` for absent/unreadable/structurally-wrong
input and `[]` for readable-with-zero-pins — two states that must stay distinguishable, because
reading "unreadable" as "empty host graph" is the lock-erasure path once Plan 03's drop rule lands.

**`Core::DiffDetector`** delegates `find_package_resolved` to the locator and is the only caller that
takes the parent tier. `identity_key` and `normalize_url` were promoted verbatim to public class
methods (private instance delegators retained, so `send(:identity_key, …)` in existing specs still
works) and `live_packages` moved above `private`. No logic changed, including the
`spm-cache/packages/proxy` local-ref skip.

**`Installer#reconcile_lockfile_from_host_graph`** runs inside `sync_lockfile`, between the
`@lockfile.load` line and `refresh_consumed_dependencies`. It self-gates on `@diff && !@diff.empty?`
(D-03, so the trigger holds for the base `Installer` too), refuses to act when the host graph is
unreadable, keys each locked package with `DiffDetector.identity_key` against `live_packages`, assigns
`version` always and `revision` only when the live entry supplies one, and saves independently.
`generate_lockfile_from_resolved`'s `File.exist?` guard is untouched — it writes the whole project
object and would clobber `products`, `dependencies` and `platforms`.

## The locator change is a behavior change, not a refactor

Research Open Question 1 asked that this be surfaced as a named decision rather than absorbed as
internal structure. It is:

**On any project containing more than one `Package.resolved`, `installer.rb`, `core/watcher.rb`,
`command/init.rb` and `command/use.rb` now read a different file than they did before.** That is the
entire point — M1 measured the old idiom returning a git-ignored nested copy frozen 32 days behind
the project's real graph, and four packages linked strictly older than their host pin as a result.

Two properties bound the blast radius:

1. **Nothing that previously found a file stops finding one.** The legacy unfiltered recursive search
   survives as tier 3. Only its position in the chain changed, plus two exclusions that both target
   files no host project should ever be represented by (spm-cache's own generated output, and a stale
   copy inside a second `.xcodeproj` bundle).
2. **Nil-handling and parse posture are unchanged at every site.** The locator centralizes finding the
   file, never deciding what to do without one. `installer.rb` still returns silently and still raises
   on malformed JSON (via the strict `pins`); `diff_detector.rb` keeps its parent tier; `watcher.rb`
   still `.compact`s a nil into "not watched"; `init.rb` keeps its `rescue JSON::ParserError, TypeError`,
   its `data.is_a?(Hash)` check and its `'platforms' => {}` seed; `use.rb` still receives a relative
   path it prints and keys a watch signature on.

Two exclusion-scoping decisions are load-bearing and deliberately asymmetric:

- The `.xcodeproj` exclusion is **tier 3 only**. At tier 4 the search root is the parent directory,
  where a legitimate sibling project's canonical file lives at
  `<parent>/App.xcodeproj/project.xcworkspace/.../Package.resolved` — a path that *does* carry an
  `.xcodeproj` component relative to that root. Filtering there would have silently voided
  `diff_detector.rb`'s pre-existing parent fallback, and `spec/diff_detector_spec.rb` could not have
  caught it, because its fixture writes to the canonical tier-1 path.
- Tier 4 instead excludes candidates **under `project_path`**. Without it, scoping the `.xcodeproj`
  rejection to tier 3 hands the project's own nested stale copy a second entrance: tier 3 rejects it,
  then tier 4 re-adopts it because its parent-relative path is no longer filtered. That is covered by
  its own example, `does not re-adopt the project's own nested copy via the parent fallback`.

## Non-vacuity of the end-to-end proof

`reconciles a single drifted package end to end and leaves DiffDetector reporting an empty diff`
carries a canonical resolved file at `alpha 2.0.0/rev-new`, a **nested** copy at `alpha 1.0.0/rev-old`,
and a lock at `1.0.0/rev-old` — i.e. the nested file agrees with the stale lock, exactly the measured
reference-project shape. Under the legacy glob the reconciler would read the nested file, write nothing,
and a fresh `DiffDetector` reading the same nested file would *also* report empty: criterion 1 satisfied
by two components agreeing on the wrong file. The version/revision assertions are what make the
empty-diff assertion mean something. `spec/package_resolved_spec.rb` additionally asserts the hazard
directly: `expect(legacy_glob(project_path)).to eq(nested_path)`.

`products[]` preservation is asserted in the same example (success criterion 2).

## Deviations from Plan

### Task 3's two new examples passed on write — no RED phase for that task

The plan asked for failing parity examples before the four call sites were edited. Both examples
(`returns nil for a project root with no resolved file, for every caller shape` and `a tolerant caller
sees nil for a truncated file while a strict caller sees the raise`) assert properties of
`Core::PackageResolved` itself, and Tasks 1-2 had already delivered those properties — so they were
green the moment they were written. They were still committed in a `test(06-02)` commit before the
call-site edits, preserving RED-before-GREEN commit order, but the honest characterization is
**parity guard rails, not RED evidence**. Tasks 1 and 2 each have genuine RED evidence: Task 1's
specs failed with `uninitialized constant SPMCache::Core::PackageResolved` (2 failures + 1 load
error), and 7 of Task 2's 8 new examples failed against Task 1's locator. Fabricating a failure for
Task 3 would have meant inventing behavior the plan did not specify.

### `pins` (strict) gained an explicit Array check — Rule 2

The plan specified `pins` as `JSON.parse(File.read(path)).fetch('pins', [])`. A resolved file whose
`pins` value is a String would then return that String, and `installer.rb`'s `pins.map` would die with
`NoMethodError` rather than the `TypeError` the contract promises. Added a one-line
`raise TypeError unless value.is_a?(Array)` so the strict reader is genuinely strict on the same input
the tolerant reader rejects. Covered by `rejects a resolved file whose pins are not an array`
(tolerant side) and the contract's raise-loudly posture (strict side).

### Task 3 committed as `refactor(`, not `feat(`

The call-site collapse adds no behavior of its own — the behavior it centralizes shipped in Tasks 1-2.
`refactor` is the accurate conventional-commit type. Task 3's acceptance criteria do not require a
`feat(` commit; Tasks 1 and 2 both carry `test(` → `feat(` pairs.

## Functional gaps deliberately left to Plan 03

These are scope boundaries the plan drew explicitly, not oversights. The union basis and the
independent save path they need are already in place:

| Gap | Decision | What is missing today |
|---|---|---|
| Drop rule | D-01 | A package in the lock but absent from the host graph is retained, so the lock can still declare a dependency the app no longer has |
| Add rule | D-02 | A package in the host graph but absent from the lock is not appended (with `products` key omitted, not `[]`) |
| Untouched-key guarantees | D-05 (partial) | `products[]` preservation is asserted for the surviving-package case; `branch`, `spm_cache_version` and unrecognized keys have no explicit regression example yet |
| Warn once on unreadable host graph | D-04 | The reconciler returns silently rather than warning when `pins_or_nil` is `nil` |

DIAG-01's `lock_graph_fidelity` check is Plan 04. This plan adds no CLI surface and no diagnostics
check names.

## Threat Mitigations Applied

- **T-06-01 (spoofing — spm-cache's own artifact adopted as the host graph)** — both recursive tiers
  reject any candidate with a path component equal to `Core::Config::SANDBOX_DIR`, referencing the
  constant rather than an inlined literal. Covered by `never returns a sandbox Package.resolved`,
  whose fixture places the umbrella and proxy resolved files exactly where they sit in the field
  (one level above the `.xcodeproj`, inside tier 4's search space).
- **T-06-02 (spoofing — stale nested copy)** — tier 1 wins by exact path, and tier 3 rejects nested
  `.xcodeproj` components. Covered by `prefers the canonical Package.resolved over a nested duplicate`,
  `excludes a candidate nested under a second .xcodeproj component`, and the parent-fallback
  re-adoption example.
- **T-06-03 (tampering — unreadable read as empty)** — `nil` and `[]` stay distinguishable; the
  reconciler returns early on `nil`; `installer.rb` keeps the strict reader. Covered by
  `distinguishes an unreadable file from a readable empty pin list` and the strict-vs-tolerant example.
- **T-06-04 (tampering — identity fields rewritten)** — reconciliation assigns `version` and
  `revision` only. `repositoryURL`, `path_from_root`, `path` and `name` are matched on and never
  written; no package path is expanded or opened during reconciliation.
- **ASVS V5 structural validation** — `pins_or_nil` requires a Hash root AND an Array `pins` value,
  and drops non-Hash array elements so a bare String cannot reach a downstream `dig`. Covered by
  `rejects a resolved file whose pins are not an array` and `skips a pin that is not an object`.

## Verification

| Gate | Result |
|---|---|
| `bundle exec rspec spec/package_resolved_spec.rb spec/lockfile_reconciliation_spec.rb` | PASS |
| `bundle exec rspec spec/lockfile_reconciliation_spec.rb -e "reconciles a single drifted package end to end…"` | PASS |
| `bundle exec rspec spec/lockfile_reconciliation_spec.rb -e "updates version and revision"` | PASS |
| `bundle exec rspec spec/package_resolved_spec.rb -e "prefers the canonical"` | PASS |
| `bundle exec rspec spec/package_resolved_spec.rb -e "never returns a sandbox Package.resolved"` | PASS |
| `spec/diff_detector_spec.rb spec/init_spec.rb spec/watch_spec.rb spec/watch_loop_spec.rb spec/watch_signals_spec.rb spec/installer_spec.rb spec/installer_use_fast_path_spec.rb spec/lockfile_enrichment_spec.rb` | PASS — no assertion edits, no example-count change |
| `git diff --name-only cf384d6..HEAD -- spec/` | only the two NEW spec files |
| `! grep -rn 'Dir\.glob' <the five files> \| grep -q 'Package\.resolved'` | PASS — every glob collapsed |
| `PackageResolved` present in all five former glob sites | PASS |
| `parent_fallback: true` in exactly one file | PASS — `core/diff_detector.rb` |
| `grep -c 'SANDBOX_DIR'` / `grep -c 'File\.expand_path'` in the locator | 1 / 0 |
| `grep -c '@lockfile.save' lib/spm_cache/installer.rb` | 3 (was 2 — the third is the reconciler's own save) |
| `grep -c 'return if File.exist?(lockfile_path)' lib/spm_cache/installer.rb` | 1 — generator guard intact |
| `DiffDetector.identity_key` ssh form == https form | PASS (`github.com/a/b`, a String) |
| `#live_packages` public, `send(:identity_key, …)` still works | PASS |
| `bundle exec rspec` | **275 examples, 0 failures** (baseline 258 + 17) |

## Known Stubs

None. The Plan 03 gaps above are absent functionality with a named owner, not placeholder code — no
hardcoded empty values, no "coming soon" paths, no skipped tests.

## Commits

| Commit | Description |
|---|---|
| `bec25f9` | RED — canonical preference, nil tolerance, parent fallback, strict/tolerant parse, end-to-end reconciliation |
| `331fcf7` | GREEN — `Core::PackageResolved`, detector as consumer, `reconcile_lockfile_from_host_graph` |
| `b7bcfa4` | RED — sandbox/nested exclusions, workspace tier, mtime tie-break, path shape, pin structure |
| `0fe8337` | GREEN — full four-tier chain with scoped exclusions and tightened `pins_or_nil` |
| `cf65ca7` | Parity guards for the collapsed callers (passed on write — see Deviations) |
| `3e3e02f` | Collapse the four remaining glob sites onto the locator |

## Follow-On Consequences

1. **Plan 03 must not reintroduce a pins-only membership basis.** `Package.resolved` never lists
   local/path packages, so the drop rule keyed on pins alone would delete every local package from
   the lock on its first run.
2. **Plan 04's doctor check should read through `Core::PackageResolved`**, or the check and the fix
   will once again be able to disagree about which file is authoritative — the exact pathology M1
   measured.
3. **The reference project should be re-measured after Plan 03.** This plan makes the locator answer
   correctly; until the drop rule lands, the 8 phantom packages remain in the lock and the 17 real
   ones are still absent, so the field symptom is not yet cleared end to end.

## Self-Check: PASSED

- `lib/spm_cache/core/package_resolved.rb` — FOUND, contains `CANONICAL_RELATIVE_PATH`
- `spec/package_resolved_spec.rb` — FOUND, contains `prefers the canonical`
- `spec/lockfile_reconciliation_spec.rb` — FOUND, contains `updates version and revision`
- Commits `bec25f9`, `331fcf7`, `b7bcfa4`, `0fe8337`, `cf65ca7`, `3e3e02f` — all FOUND
