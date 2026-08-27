---
phase: 06-graph-authority-lockfile-reconciliation
plan: 03
subsystem: installer
tags: [fid-01, lockfile, reconciliation, membership, degradation, tdd]
status: complete

requires:
  - "06-02 Core::PackageResolved — the canonical locator; without it this plan's drop rule would be actively harmful (it would delete the real graph and keep the stale one)"
  - "06-02 DiffDetector.identity_key / #live_packages — the public keying and live union this reconciler keys membership on"
provides:
  - "Installer#reconcile_lockfile_from_host_graph — full FID-01 semantics: drop (D-01), add without a products key (D-02), self-gate (D-03), warn-once degrade (D-04), preserve enrichment and frozen keys (D-05), plus the empty-pins drop guard (T-06-16)"
  - "spec/lockfile_reconciliation_spec.rb — 16 examples across drop / add / local-preservation / url-variants / untouched keys / unreadable / missing / empty-diff / differing-lock-key / zero-pins"
  - "spec/installer_use_fast_path_spec.rb — ROADMAP success criterion 1 proven through a real non-fast-path perform_install"
affects:
  - "Plan 04 (DIAG-01 lock_graph_fidelity) — after this plan a non-fast-path run leaves nothing for the check to report, so its fixtures must construct drift explicitly rather than rely on a naturally stale lock"
  - "The reference project — the 8 phantom packages are now purged and the 17 real ones added on the next `spm-cache use`; re-measurement is the outstanding field verification"

tech-stack:
  added: []
  patterns:
    - "Membership decided by set difference against the live union, with surviving entries mutated in place and additions appended — surviving lock order preserved so a reconciled lock diffs minimally"
    - "Retain-over-erase on an ambiguous host signal: an unreadable graph returns without saving; a graph that parses with zero pins keeps remote entries and warns"
    - "Additions omit rather than seed keys that a downstream idempotency guard treats as 'already done'"

key-files:
  created: []
  modified:
    - lib/spm_cache/installer.rb
    - spec/lockfile_reconciliation_spec.rb
    - spec/installer_use_fast_path_spec.rb

key-decisions:
  - "D-02 realized as OMISSION of the products key, not `products: []` — enrich_lockfile_products guards with `next if pkg_data[\"products\"]` and `[]` is truthy in Ruby, so a present-but-empty key would suppress that package's product metadata permanently. The covering example asserts `key?('products') == false`, never `== []`"
  - "The empty-pins drop guard skips only the DROP half when host pins are empty AND the lock holds >= 1 repositoryURL entry; value updates and additions still proceed, and one warn fires (T-06-16)"
  - "Accepted residual: the same guard masks a genuine total removal of every remote dependency. Retain-over-erase, self-correcting on the next non-empty run, surfaced by DIAG-01 in the meantime"
  - "The lock's project entry is resolved extension-insensitively (`Fake` matches `Fake.xcodeproj`) so a lock keyed without the extension still reconciles — this is what makes the reconciler's own save observably load-bearing, since refresh_consumed_dependencies matches the basename strictly and early-returns on that shape (deviation from the plan's literal 'reconcile only projects[File.basename]'; see Deviations)"
  - "version is assigned unconditionally, revision only when the live entry supplies one — asymmetric on purpose: DiffDetector compares `version || revision`, so retaining a stale version would leave criterion 1 unsatisfiable for a pbxproj-only package, while nilling a revision makes UmbrellaGenerator skip the package entirely"
  - "spm_cache_version is never assigned inside the reconciler; stamping early would make invalidate_stale_products! skip its clear and carry stale products across an upgrade (T-06-09)"

requirements-completed: [FID-01]
requirements-note: >
  FID-01 is delivered in full and marked Complete. Every semantic CONTEXT.md locked for it now
  exists in source with a named regression example: version/revision reconcile on every
  non-fast-path run (D-01 value half), a package absent from the live union is dropped (D-01), a
  package new to the host graph is appended with the products key omitted (D-02), reconciliation
  self-gates on a non-empty diff (D-03), a missing or unreadable host Package.resolved warns once
  and leaves the lock byte-identical (D-04), and enriched products[] plus dependencies / platforms
  / spm_cache_version / branch survive untouched (D-05). The empty-pins drop guard (T-06-16) closes
  the one erasure door the D-04 nil-check does not cover.

coverage:
  tests-added: 14
  suite: "289 examples, 0 failures (baseline 275 + 14; no existing spec assertion modified)"

metrics:
  duration: ~25m
  completed: 2026-08-27
  tasks: 3
  commits: 5

actuals:
  tokens: 13860
  tasks: 3
  commits: 5
---

# Phase 6 Plan 03: Full FID-01 Lockfile Reconciliation Semantics Summary

Completed FID-01: `spm-cache.lock`'s package set is now the project's live package set — remote
pins from the canonical `Package.resolved` union local refs from `project.pbxproj` — with
enrichment, the target-to-product map, platforms, the version stamp and hand-written keys all
byte-identical afterward, and every ambiguous host signal degrading to a warning rather than a
deletion.

## What Was Built

`Installer#reconcile_lockfile_from_host_graph` grew from Plan 02's intersection-only value refresh
into a membership decision:

| Semantics | Decision | Implementation |
|---|---|---|
| Value refresh | D-01 | `version` assigned from the live entry always; `revision` only when the live entry supplies one |
| Drop | D-01 | `select` rejects every locked entry whose `DiffDetector.identity_key` is absent from `#live_packages`; the rebuilt array is assigned back onto the same `proj_data` Hash the run shares |
| Add | D-02 | one canonical four-field entry per live key the lock does not hold, appended after the survivors; `products` key **omitted** |
| Self-gate | D-03 | `@diff && !@diff.empty?` retained — the fast path never rewrites the lock |
| Degrade | D-04 | `locate` nil or `pins_or_nil` nil → one `Core::UI.warn`, no `save`, lock byte-identical |
| Empty-pins guard | T-06-16 | host pins `[]` AND lock holds >= 1 `repositoryURL` → skip the drop half, warn once, still update and add |
| Preserve | D-05 | only `version`, `revision` and the `packages` array membership are ever assigned |

Four small private helpers carry the parts worth naming: `lock_project_data`,
`drop_pass_allowed?`, `lock_identity_key`, `additions_for` / `new_lock_entry`.

## The D-02 refinement: the products key is omitted, not written as `[]`

**This is a deliberate realization of D-02's stated intent, not a deviation from it.** D-02 reads
"added with an empty `products[]`, leaving existing enrichment to populate products later." Those
two clauses are in conflict in Ruby: `enrich_lockfile_products` guards each entry with
`next if pkg_data["products"]` (`installer.rb`, enrichment loop), and `[]` is truthy — so writing
`products: []` would make enrichment skip that package on this run and every future run, and the
proxy generator would fall back to the package's lockfile identity as its assumed product name.
That fallback is the original wrong-product-name bug this codebase already carries dense
provenance for.

`new_lock_entry` therefore emits exactly `repositoryURL`, `name`, `version`, `revision` (or
`path_from_root` in place of `repositoryURL` for a local ref) and no `products` key at all.
`Lockfile::Pkg#to_h` already omits the key when products are empty, so the omission is the shape
the rest of the system expects. The covering example asserts
`expect(delta.key?('products')).to be(false)` — deliberately not `eq([])`.

## The membership basis is the union, never the pins

`Package.resolved` structurally never lists a local / `path_from_root` package, so keying the drop
rule on resolved pins would delete every local package from the lock on its first run, after which
the umbrella stops declaring a real dependency (T-06-07, the phase's top regression risk).
Membership keys on `Core::DiffDetector#live_packages` and every comparison goes through
`Core::DiffDetector.identity_key` — no second comparator exists in `installer.rb`
(`grep -c 'DiffDetector\.identity_key'` → 1, `grep -c 'live_packages'` → 1, and
`PackageResolved.pins` — the strict parser — appears only inside `generate_lockfile_from_resolved`).

The named example `keeps a local package absent from Package.resolved` builds the exact hazard: a
lock entry with `path_from_root` and no `repositoryURL`, a host `Package.resolved` that does not
list it, and a real `XCLocalSwiftPackageReference` in the pbxproj. A sibling example proves the
`spm-cache/packages/proxy` ref is still neither live nor added.

## Deviations from Plan

### `lock_project_data` resolves the project key extension-insensitively — Rule 4 resolution of a plan inconsistency

Task 2 asked for two things that cannot both hold. Its action text says "Reconcile only
`@lockfile.projects[File.basename(@project_path)]`", while its named example
`reconciles a project whose lock key differs from the project basename` requires the reconciler to
act on a lock key that is *not* that basename, "even though `refresh_consumed_dependencies`
early-returns on that shape". With strict basename keying both methods early-return identically,
the example is unsatisfiable, and "save independence" is unobservable — `refresh_consumed_dependencies`
would otherwise always persist the reconciler's in-memory mutations for it.

Resolution: `lock_project_data` tries the exact basename first, then falls back to a match whose
`.xcodeproj` extension is stripped on both sides (`Fake` matches `Fake.xcodeproj`; `Fake.xcworkspace`
does **not**). This is narrow on purpose — it only ever adopts an entry naming the same project, so
a monorepo lock holding several project keys, or a lock genuinely written for a different project,
is untouched. Broadening this to "the lock's only project entry" was considered and rejected: it
would let this project's graph reconcile a lock belonging to another project, which is the erasure
class this milestone exists to prevent.

Covered by `reconciles a project whose lock key differs from the project basename`, which runs the
full real `sync_lockfile` — `refresh_consumed_dependencies` genuinely early-returns there, so the
reconciler's own `@lockfile.save` is the only thing that could have persisted the new
version/revision.

### RED honesty: 6 of the 13 new unit examples failed before implementation, 7 passed on write

Wave 2 reported a task with no genuine RED and logged it. Repeating the same disclosure rather than
dressing guard rails up as RED evidence:

| Task | Genuine RED (failed before the fix) | Passed on write (regression guards) |
|---|---|---|
| 1 | `drops a package absent from the host graph`, `adds a new package without a products key` | `keeps a local package absent from Package.resolved`, `does not resurrect the spm-cache proxy ref as a dependency`, `matches identity across url spelling variants` |
| 2 | `leaves the lock untouched when Package.resolved is unreadable`, `leaves the lock untouched when Package.resolved is missing`, `reconciles a project whose lock key differs from the project basename`, `skips the drop pass when the host graph has zero pins but the lock has remote entries` | `preserves products`, `leaves dependencies platforms and version stamp untouched`, `does not clear an existing revision when the host pin has none`, `does not write when the diff is empty` |

The seven that passed on write are not vacuous — Plan 02 had already delivered the value-refresh
and no-touch properties they assert, and each one *would* have failed had this plan's drop rule
been keyed on pins, cleared revisions, or stamped the version. `keeps a local package absent from
Package.resolved` in particular is the guard that fails loudly if T-06-07 is ever reintroduced.
RED-before-GREEN commit order holds for both tasks (`test(06-03)` precedes `feat(06-03)` twice).

### The unreadable-host-graph example injects `@diff` instead of calling `detect_diff`

`Core::DiffDetector#live_packages` does an unguarded `JSON.parse(File.read(resolved))`, so a
truncated `Package.resolved` raises `JSON::ParserError` out of `detect_diff` — *before*
reconciliation is ever reached. The example therefore sets a non-empty `@diff` directly and runs
`sync_lockfile`, which is the only way to exercise the guard being specified. The `missing` and
`zero pins` examples use the real `detect_diff` (both shapes parse or are absent, so the detector
survives them).

This is a pre-existing hazard in a file this plan does not modify, recorded below as a finding
rather than fixed here (out of scope per the executor's scope boundary).

### Byte-identity examples stub `refresh_consumed_dependencies`

`refresh_consumed_dependencies` saves unconditionally right after the reconciler, so any assertion
about the lock's bytes must isolate the reconciler or it measures the wrong writer. The three
byte-identity examples (`unreadable`, `missing`, `does not write when the diff is empty`) and the
frozen-keys example stub it; every membership example runs the full real `sync_lockfile`.

## Finding (not fixed — out of scope)

**`DiffDetector#live_packages` raises on a malformed host `Package.resolved`.** Lines 140-141 of
`lib/spm_cache/core/diff_detector.rb` parse the host graph with no `rescue`, so a truncated or
non-object `Package.resolved` aborts `detect_diff` — and therefore the whole `use` run — before the
reconciler's D-04 warn-and-degrade path can be reached. The reconciler's guard is correct and
covered; it is simply unreachable in the field for that one input shape. The fix belongs in
`diff_detector.rb` (route through `Core::PackageResolved.pins_or_nil` and treat nil as "no resolved
pins, fall through to the pbxproj union"), which is neither in this plan's `files_modified` nor
caused by its changes. Logged to `deferred-items.md`.

## Threat Mitigations Applied

- **T-06-07 (drop rule keyed on the wrong live set)** — membership keys on `#live_packages`;
  `-e "keeps a local package absent from Package.resolved"` fails if that ever regresses to pins.
- **T-06-08 (unreadable host graph read as empty)** — `pins_or_nil` nil → one warn, no `save`;
  `-e "leaves the lock untouched when Package.resolved is unreadable"` asserts byte equality.
- **T-06-16 (pre-v2 `object.pins` read as empty)** — `drop_pass_allowed?` skips the drop half when
  host pins are empty and the lock holds remote entries; covered by
  `-e "skips the drop pass when the host graph has zero pins but the lock has remote entries"`,
  whose fixture is a literal `{"object": {"pins": [...]}}` file.
- **T-06-09 (`spm_cache_version` stamped during reconciliation)** — never assigned; the reconciler
  body contains zero occurrences of the identifier, and
  `-e "leaves dependencies platforms and version stamp untouched"` pins a `0.0.1-frozen` stamp and
  asserts it survives.
- **T-06-10 (path traversal via `path_from_root`)** — identity fields are copied verbatim; no
  `File.expand_path`, no `File.join` and no filesystem access on any package-supplied path inside
  the reconciler.
- **T-06-14 (`verify!` raising on a `dependencies` entry naming a dropped package)** —
  `refresh_consumed_dependencies` rebuilds `dependencies` from the live project immediately after
  the reconciler and nothing calls `verify!` in between; `spec/installer_consumed_dependencies_spec.rb`
  stays green with no assertion edits.

## Verification

| Gate | Result |
|---|---|
| `bundle exec rspec spec/lockfile_reconciliation_spec.rb` | PASS — 18 examples (2 pre-existing + 16 new) |
| `-e "drops a package absent from the host graph"` | PASS |
| `-e "adds a new package without a products key"` (asserts `key?('products') == false`) | PASS |
| `-e "keeps a local package absent from Package.resolved"` | PASS |
| `-e "does not resurrect the spm-cache proxy ref as a dependency"` | PASS |
| `-e "matches identity across url spelling variants"` (array length unchanged, in-place update) | PASS |
| `-e "preserves products"` | PASS |
| `-e "leaves dependencies platforms and version stamp untouched"` (incl. hand-written `branch`) | PASS |
| `-e "leaves the lock untouched when Package.resolved is unreadable"` (byte equality + one warn) | PASS |
| `-e "leaves the lock untouched when Package.resolved is missing"` (byte equality + one warn) | PASS |
| `-e "does not clear an existing revision when the host pin has none"` | PASS |
| `-e "does not write when the diff is empty"` (bytes + mtime) | PASS |
| `-e "reconciles a project whose lock key differs from the project basename"` | PASS |
| `-e "skips the drop pass when the host graph has zero pins but the lock has remote entries"` | PASS |
| `bundle exec rspec spec/installer_use_fast_path_spec.rb -e "leaves DiffDetector reporting an empty diff"` | PASS |
| `spec/diff_detector_spec.rb spec/lockfile_spec.rb spec/lockfile_enrichment_spec.rb spec/installer_spec.rb spec/installer_consumed_dependencies_spec.rb spec/installer_retry_umbrella_resolve_spec.rb spec/checkout_enrichment_sequencing_spec.rb` | PASS — no example-count change, no assertion edits |
| `grep -c 'live_packages' lib/spm_cache/installer.rb` | 1 |
| `grep -c 'DiffDetector\.identity_key' lib/spm_cache/installer.rb` | 1 — no second comparator |
| `PackageResolved.pins` (strict) call sites | 1, inside `generate_lockfile_from_resolved` only |
| `spm_cache_version` inside `reconcile_lockfile_from_host_graph` | 0 occurrences |
| `make proxy.build && bundle exec rspec` | **289 examples, 0 failures** (baseline 275 + 14) |

`spec/installer_use_fast_path_spec.rb`'s three pre-existing examples are unmodified; the only edit
to their scaffolding is `write_package_resolved`'s `'revision' => p[:revision] || 'rev'`, which
preserves their current pin shape exactly.

## ROADMAP Success Criteria

**Criterion 1 — after a non-fast-path run, re-running `DiffDetector` returns an empty diff.**
Proven through a real `Installer::Use#perform_install` in
`spec/installer_use_fast_path_spec.rb -e "leaves DiffDetector reporting an empty diff"`, with
`sync_lockfile` left REAL and only the shell-out steps stubbed. The fixture carries all four
package situations at once — `Drifted` (1.0.0/rev-old → 3.0.0/rev-new), `Removed` (in the lock,
absent from both the host graph and the pbxproj), `Enriched` (surviving with a products array), and
`Newcomer` (in the host graph, never seen by the lock). The assertion is on a **freshly
constructed** `DiffDetector`, not on `installer.diff`.

**Criterion 2 — reconciling versions never costs metadata.** `Enriched`'s `products` array is
`==` to its pre-run value on that same integration path, and the unit example
`leaves dependencies platforms and version stamp untouched` pins `dependencies`, `platforms`,
`spm_cache_version` and a hand-written `branch` key.

## Commits

| Commit | Description |
|---|---|
| `d0b5c72` | RED — drop/add membership (2 genuine failures) plus local-package, proxy-ref and url-variant guards |
| `75a81ef` | GREEN — membership keyed on the live union; additions in the canonical shape with `products` omitted |
| `e5ada2d` | RED — warn-once degradation, differing lock key, empty-pins drop guard (4 genuine failures) |
| `92a0443` | GREEN — warn-once degradation, empty-pins guard, extension-insensitive project key |
| `c550990` | Integration proof of ROADMAP criterion 1 across a real non-fast-path run |

## Known Stubs

None. No hardcoded empty values, no placeholder paths, no skipped or pending examples. The one
piece of absent functionality touched by this plan is `diff_detector.rb`'s unguarded host-graph
parse, recorded above as a finding with a named owner and logged to `deferred-items.md` — it is
pre-existing behavior in a file this plan does not modify.

## Follow-On Consequences

1. **Plan 04's DIAG-01 fixtures must construct drift explicitly.** After this plan a non-fast-path
   run leaves the lock in agreement with the host graph, so a `lock_graph_fidelity` spec that
   simply runs `use` and then looks for drift will find none.
2. **The reference project should be re-measured.** Plan 02 made the locator answer correctly; this
   plan purges the 8 phantom packages and admits the 17 real ones. The end-to-end field symptom is
   only now expected to clear, and that measurement has not yet been taken.
3. **`diff_detector.rb`'s unguarded parse should be routed through `Core::PackageResolved`** so the
   D-04 degrade path is reachable in the field for a truncated host graph, not just for a missing one.
4. **The empty-pins guard's accepted residual is visible only through DIAG-01.** A user who
   genuinely removes every remote dependency keeps stale lock entries behind a warning until their
   next non-empty run; the doctor check is what surfaces that state in the meantime.

## Self-Check: PASSED

- `lib/spm_cache/installer.rb` — FOUND, contains `reconcile_lockfile_from_host_graph`
- `spec/lockfile_reconciliation_spec.rb` — FOUND, contains `keeps a local package absent from Package.resolved`, 376 lines
- `spec/installer_use_fast_path_spec.rb` — FOUND, contains `leaves DiffDetector reporting an empty diff`
- Commits `d0b5c72`, `75a81ef`, `e5ada2d`, `92a0443`, `c550990` — all FOUND
