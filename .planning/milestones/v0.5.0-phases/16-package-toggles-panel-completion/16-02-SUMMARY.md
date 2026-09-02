---
phase: 16-package-toggles-panel-completion
plan: 02
subsystem: lockfile
tags: [binary-target, enrichment, lockfile, toggl]

requires:
  - phase: 16-package-toggles-panel-completion
    provides: "enrich_lockfile_products describe pass + per-version invalidation (spm_cache_version stamp)"
provides:
  - "Per-package `binary_target` boolean written beside products[] by the enrichment pass, derived from the same `swift package describe` output (no second shell-out), invalidated with products[] on version bump"
  - "Core::Lockfile#binary_backed_names(project_name) — Set of identity ∪ product names ∪ product target names for binary-backed packages; total over legacy/malformed shapes; the contract 16-03's reason derivation consumes"
affects: [16-03, 16-06]

actuals:
  tokens: 4700   # chars/4 over the realized diff (estimate was 34000, confidence low — 0 samples)
  tasks: 2
  commits: 4

key-decisions:
  - "Key named `binary_target` (snake_case, sibling of products[]/spm_cache_version house style; the reason-vocabulary word stays `binary-target` in D-09's chip strings)"
  - "Flag derived via `desc.targets.any? { |t| t.send(:binary?) }` — the existing predicate is private on base Target (public only on BinaryTarget); send keeps the change inside plan files instead of widening visibility on a shared class"
  - "No manifest-fallback branch: a failed describe yields no targets, so the flag falls out false — an honest false, never a guess (the fallback parses product declarations only)"
  - "Reader answers a Set (pinned in spec) — the read model asks once per /api/state call and membership-tests every row; identity fallback mirrors checkout_map's `name || basename(URL)` idiom"
  - "TOGL-03 NOT marked complete: the requirement spans 16-02..16-06 (reason derivation lands in 16-03, panel proof in 16-06); this plan lands only its fact source"

requirements-completed: []

coverage:
  - id: truth-1
    description: "Flag recorded in the same pass, beside products[], Ruby-side only; explicitly false when derived-not-binary; skipped packages untouched"
    requirement: TOGL-03
    verification:
      - kind: unit
        ref: "spec/lockfile_enrichment_spec.rb 'derived binary-target flag' rows 1-4 (19 examples, 0 failures)"
        status: pass
    human_judgment: false
  - id: truth-2
    description: "Version-bump invalidation clears the flag with products[]; never a stale flag beside fresh products; idempotence unchanged"
    requirement: TOGL-03
    verification:
      - kind: unit
        ref: "spec/lockfile_enrichment_spec.rb invalidation + idempotence rows"
        status: pass
    human_judgment: false
  - id: truth-3
    description: "Undetectable stays undetected: no-checkout / no-describe packages left entirely unenriched, warning still prints"
    requirement: TOGL-03
    verification:
      - kind: unit
        ref: "spec/lockfile_enrichment_spec.rb untouched-skip rows (new pin + 2 pre-existing warning rows)"
        status: pass
    human_judgment: false
  - id: truth-4
    description: "Lockfile answers the binary-backed name set (identity ∪ product names ∪ product target names) as a membership-testable Set; total over legacy/empty/absent shapes"
    requirement: TOGL-03
    verification:
      - kind: unit
        ref: "spec/lockfile_spec.rb #binary_backed_names rows (15 examples, 0 failures)"
        status: pass
    human_judgment: false
  - id: truth-5
    description: "Format compatibility: per-package sibling key inside an existing project entry; reconciliation deltas and real-checkout sequencing unperturbed"
    requirement: TOGL-03
    verification:
      - kind: unit
        ref: "spec/lockfile_reconciliation_spec.rb spec/checkout_enrichment_sequencing_spec.rb (23 examples, 0 failures)"
        status: pass
    human_judgment: false

duration: 25min
completed: 2026-09-02
status: complete
---

# Phase 16 / Plan 16-02: The binary-target fact — one derived flag, recorded where the describe output already lives

**The enrichment pass that already runs `swift package describe` per package now records a derived `binary_target` boolean beside products[] (invalidated with it on version bump), and `Core::Lockfile#binary_backed_names` answers the Set of table-row names a binary-backed package covers — so `binary-target` stops being TOGL-03's only reason with no fact behind it. Swift proxy tool untouched.**

## Task Commits
1. RED — six failing enrichment rows + stub helper gains `targets:` (built through the real `Target.from_raw` factory) — `87d1ba0`
2. GREEN — installer.rb derives and writes the flag; `invalidate_stale_products!` deletes both — `8bbe8e8`
3. RED — five failing name-set reader rows — `c263ef2`
4. GREEN — `Core::Lockfile#binary_backed_names` reader — `0d42fca`

## Notes
- **Deviations (auto-fixed, Rule 3):** `Target#binary?` turned out to be private on the base class (public only on the `BinaryTarget` subclass the factory dispatches to), so the plan's `desc.targets.any?(&:binary?)` raised `NoMethodError` — including against the real offline checkout in `checkout_enrichment_sequencing_spec.rb`. Fixed with `t.send(:binary?)` to stay inside the plan's file list rather than widening visibility on the shared `Target` class.
- **Wave gate deferred:** the plan's Task-2 "full suite `bundle exec rspec`" gate is NOT run here — wave-1 executors run under `isolation=none` with a sibling editing the same tree, and the orchestrator runs the wave gate once all plans land. Plan-scoped verifies (below) are all green.
- **`requirements.mark-complete` intentionally skipped:** TOGL-03 spans 16-02/03/04/05/06; marking it complete after the fact-source slice would be false.

## Verify
- `bundle exec rspec spec/lockfile_enrichment_spec.rb` — 19 examples, 0 failures
- `bundle exec rspec spec/lockfile_spec.rb` — 15 examples, 0 failures
- `bundle exec rspec spec/lockfile_reconciliation_spec.rb spec/checkout_enrichment_sequencing_spec.rb` — 23 examples, 0 failures
- Full suite — orchestrator's wave-1 merge gate (see deviation above)

## Honest caveats (carried from 16-RESEARCH A5 + field history)
- **Under-detection, bounded:** a package whose checkout can't be found, or whose `describe` errors (A5: local-path `binaryTarget` with the artifact absent from the checkout copy — the eh_xcframework case), carries no flag and renders exactly as it does today. The manifest fallback supplies products but honestly records `binary_target: false`, never a guess.
- **Mid-development-version edge:** invalidation fires on `spm_cache_version` mismatch only. While spm-cache itself is under development between releases (VERSION unchanged), a fix to the derivation does NOT re-derive flags already written — they refresh on the next version bump, exactly like products[] (the pre-existing field-bug-history trade-off this mechanism inherited).

## Files
- lib/spm_cache/installer.rb (enrich_lockfile_products + invalidate_stale_products! + comments)
- lib/spm_cache/core/lockfile.rb (require "set" + binary_backed_names)
- spec/lockfile_enrichment_spec.rb (stub helper `targets:` kwarg + 6 rows)
- spec/lockfile_spec.rb (5 reader rows)

## Self-Check: PASSED

All four task commits (87d1ba0, 8bbe8e8, c263ef2, 0d42fca) verified in git log; SUMMARY.md present on disk.
