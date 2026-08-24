---
phase: 05-auto-sync-watcher
fixed_at: 2026-08-24T08:55:00Z
review_path: .planning/phases/05-auto-sync-watcher/05-REVIEW.md
iteration: 1
findings_in_scope: 3
fixed: 3
skipped: 0
status: all_fixed
---

# Phase 5: Code Review Fix Report

**Fixed at:** 2026-08-24T08:55:00Z
**Source review:** .planning/phases/05-auto-sync-watcher/05-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope (critical_warning): 3 (WR-01 major, WR-02 minor, WR-03 minor)
- Fixed: 3
- Skipped: 0

## Fixed Issues

### WR-01: A second signal during `flush_pending_event` kills the process (MAJOR)

**Files modified:** `spec/watch_signals_spec.rb`, `lib/spm_cache/core/watcher.rb`
**Commits:** 6fbd052 (RED spec), 2771a69 (fix)
**Applied fix:** `Signal.trap('TERM', 'IGNORE')` + `Signal.trap('INT', 'IGNORE')` at the top of the `rescue Interrupt` handler, exactly per the review's snippet — a trap-raise can no longer land inside the unwinding handler. New subprocess example: slow (3s) installer, pending change, INT, then TERM + INT mid-flush.
**Verification:** RED observed against pre-fix code — `exitstatus: nil` (child killed by signal), matching the reviewer's reproduction. GREEN after fix: `exitstatus 0`, stdout includes `[watch] stopped.`, marker == 2 lines (initial + flush). Full signal file: 9 examples, 0 failures (6 authored + 3 spec_helper globals).

### WR-02: Interrupt during in-flight loop regeneration abandons the announced change (MINOR)

**Files modified:** `lib/spm_cache/core/watcher.rb`, `.planning/phases/05-auto-sync-watcher/05-01-SUMMARY.md`
**Commit:** ad0ea76
**Applied fix:** documentation option per the review's resolution note — the `flush_pending_event` comment now states the accepted edge (change consumed pre-regeneration → flush sees matching signatures → abandoned; healed by next run's initial sync), and SUMMARY deviation (f) carries a dated 2026-08-24 amendment. No `@regenerating` flag, keeping the watcher diff minimal per the phase's lean-diff budget.
**Verification:** comment text present at watcher.rb:93-98; deviation (f) amendment present at 05-01-SUMMARY.md:160. No behavioral change → suite unaffected.

### WR-03: Flush-failure branch has zero spec coverage (MINOR)

**Files modified:** `spec/watch_signals_spec.rb`
**Commit:** 9bf563a
**Applied fix:** new subprocess example per the review's recipe — `fail_flush` child mode raises `StandardError` on every install after the first, keyed off marker-file line count (not instance state); pending change + INT → asserts `exitstatus 0`, stdout includes `[watch] flush failed` and `[watch] stopped.`, marker == 1 line.
**Verification:** green at birth (pins existing correct behavior, as the review predicted); fails if the flush rescue is removed or exit becomes non-zero.

## Verification

- **Where gates ran:** MAIN checkout (repo root) — `workflow.use_worktrees: false` in `.planning/config.json`, so no isolated worktree was created and edits/commits landed directly on `gsd/v0.3.0-milestone`.
- Per-fix: Tier 1 (re-read modified sections) + Tier 2 (RSpec execution = Ruby parse + behavior) for every change; WR-01 additionally observed RED→GREEN.
- Full-suite gate: `make proxy.build && bundle exec rspec` → `Build complete! (0.22s)` + **258 examples, 0 failures** (was 256; +2 new examples).

## Notes

- Info findings IN-01 / IN-02 were out of scope (`fix_scope: critical_warning`) and untouched, per the review's own "no action required" / "cosmetic" classifications.
- `watch_spec.rb`, `installer.rb`, `run_once`, and `regenerate` remain untouched; watcher.rb production diff is now +12/−2 vs `1429748` (WR-01 masking + comments; WR-02 comment amendment).
- A malformed gsd-tools commit (`65286b1`, path swallowed into the message, planning docs swept in) was immediately undone via `git reset --mixed HEAD~1` — branch history contains only the four clean commits above; no pre-existing working-tree state was lost (verified: `.planning/WINDOWS.md` modification and all pre-existing untracked files still present and uncommitted).

---

_Fixed: 2026-08-24T08:55:00Z_
_Fixer: Claude (gsd-code-fixer, Phase5Fixer)_
_Iteration: 1_
