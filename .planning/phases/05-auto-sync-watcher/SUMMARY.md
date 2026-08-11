# Phase 5 Summary — Auto-Sync Watcher

**Requirement:** AUTO-01, AUTO-02, AUTO-03, AUTO-04, AUTO-05
**Status:** Complete

## Deliverables
- `lib/spm_cache/core/watcher.rb` (115 lines) — `Core::Watcher`: watches Package.resolved + project.pbxproj, mtime+size polling (Ruby stdlib only — no new gem), configurable debounce (default 2s), `run_once` for CI/testing, continue-on-error loop, fatal-exit on missing project.
- `lib/spm_cache/command/watch.rb` (58 lines) — `spm-cache watch` subcommand with `--once` and `--debounce=SECONDS`.
- `spec/watch_spec.rb` (137 lines) — 12 specs covering file watching, run_once, change detection, continue-on-error, missing project, debounce, flag parsing. All passing.

## Design note
The spec proposed native FSEvents via Fiddle; the existing `use --watch` already used portable mtime polling successfully. Phase 5 refactors that into a dedicated `Core::Watcher` class + `watch` command with the full feature set (debounce, --once, continue-on-error), keeping the zero-dependency polling approach since it's proven and macOS stdlib-sufficient. AUTO-05 ("no new gem dependency") is satisfied.

## Commits
- `d7c0fff` feat: add spm-cache watch command (AUTO-01-05)
