---
phase: 07-host-faithful-checkout-seeding
fixed_at: 2026-08-29T14:20:00Z
fix_scope: critical_warning
findings_in_scope: 8
fixed: 7
skipped: 1
iteration: 3
status: partial
---

# Phase 07: Code Review Fix Report

**Fix scope:** critical_warning (Critical + Warning; Info items out of scope)
**Iterations:** 3 (initial fix pass, interrupted mid-run by a transient agent connection failure and completed manually; re-review surfaced a residual critical; second fix pass; final re-review converged clean)

## Fixed (7)

- **CR-01 / CR-01b** — `Installer::Use`'s build lock now wraps the trailing `gen_supporting_files`/`integrate_proxy_into_project`/`gen_cachemap_viz` calls on **both** the fast path and non-fast path, closing a race where a concurrent `Installer::Build#recreate_dirs` could `rm_rf` `sandbox_dir`/`proxy_dir` while the fast path read from it unlocked. Commits `c3bb440` (non-fast-path, partial), `c5d1aaa` (fast-path, closes the residual).
- **CR-02** — `Installer::Build#slice_complete?` now forces a rebuild (`false`) instead of treating a "hit" module as complete when its xcframework directory is entirely missing from disk. Commit `a915188`, with a new regression test.
- **WR-01** — `Buildable#build_for_destination` now splats `**opts` into `xcodebuild` instead of nesting it under an `opts:` key, so `live_log`/`extra_args` actually reach it. Commit `3a972bb`.
- **WR-02** — `slice_satisfies?`'s catch-all branch now returns `false` instead of `true` for any destination key other than `iphonesimulator`/`iphoneos`. Commit `3a972bb`.
- **WR-03** — Extracted `scan_swiftinterfaces` to remove the duplicated swiftinterface-scan block in `referenced_module_names`. Commit `3a972bb`.
- **WR-04** — Narrowed the rescues in `resolve_public_headers`, `resolve_scheme_fallback`, and `schemes_across_projects` from `StandardError`/bare rescue to `SPMCache::Core::GeneralError` (+ `JSON::ParserError` for the desc fetch), matching the existing narrow-rescue pattern elsewhere in the codebase. Commit `3a972bb`.
- **WR-06** — Collapsed `resolve_destinations`' three branches (two of which were byte-identical) into a single ternary. Commit `3a972bb`.

## Skipped (1)

- **WR-05** (sleep-based timing specs in `spec/build_lock_spec.rb`) — deliberately not rewritten. Independent inspection of both flagged tests found the practical flake risk low: the first already rendezvous-syncs via a pipe before its brief `sleep` and confirms release via `Process.wait` (deterministic, not timing-based); the second's `elapsed >= 0.3` assertion is only ever made *more* true by CI scheduling delays, never less. These are load-bearing fork-based lock-contention proofs for this milestone's core concurrency guarantee — rewriting them for a marginal, largely theoretical benefit was judged not worth the risk of introducing a subtler bug into the proof itself.

## Out of scope (not attempted — Info-level, `--all` not requested)

- IN-01 (`Config::DEFAULT_CONFIG.dup` shallow copy), IN-02 (`Config#load` missing `aliases: true`), IN-03 (redundant `"Simulator"` substring check in `destination_arch`).

## Verification

Full suite: 342 examples, 0 failures (baseline 341 + 1 new regression test for CR-02) after every commit in this fix chain. Final re-review (iteration 3) independently re-verified all 7 fixes against current source and confirmed no new issues introduced: `status: clean`.
