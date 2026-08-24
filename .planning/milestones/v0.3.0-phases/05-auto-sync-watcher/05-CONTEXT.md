# Phase 5: Auto-Sync Watcher - Context

**Gathered:** 2026-08-24
**Status:** Ready for planning

<domain>
## Phase Boundary

Deliver `spm-cache watch` — a filesystem-watch mode that auto-regenerates the proxy package when the Xcode SPM graph changes. IMPORTANT: ALREADY IMPLEMENTED on this branch (commit d7c0fff: `lib/spm_cache/core/watcher.rb` 115 lines, `lib/spm_cache/command/watch.rb`, `spec/watch_spec.rb` 12 specs). This phase's plan is VERIFICATION-SCOPED: prove ROADMAP success criteria against the live code, record the user-accepted watch-mechanism deviation, close doc drift — do NOT re-implement.

</domain>

<decisions>
## Implementation Decisions

### Watch mechanism (USER DECISION 2026-08-24 — supersedes the earlier FSEvents design note)
- mtime+size POLLING (Ruby stdlib only) is the accepted mechanism. The earlier locked decision ("native FSEvents via Fiddle") and ROADMAP criterion 5's mechanism wording are SUPERSEDED by this acceptance; AUTO-05's substance ("no new gem dependency") is satisfied. Poll interval + debounce (default 2s) collapses burst saves; approach is proven via the prior `use --watch` polling.
- ROADMAP criterion 5 must be amended with a dated inline record of this deviation; PROJECT.md/STATE.md claims of "native FSEvents" must be corrected to polling.

### Loop semantics (accepted as shipped)
- Transient regeneration failure → logged with timestamp, loop continues (criterion 4)
- Fatal conditions only (project deleted/unwatchable) → exit non-zero
- SIGINT/SIGTERM flush a pending event and exit 0 (verify the actual trap wiring in Watcher#run)

### Debounce (accepted as shipped)
- Default 2 seconds, `--debounce=SECONDS` flag — matches the locked decision

### `--once` (accepted as shipped)
- Single sync-and-exit for CI/testing; fully unit-testable via injected `installer_factory` (no poll loop, no OS API)

### Claude's Discretion
Verification task granularity; proof organization; doc phrasing for the deviation records.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `lib/spm_cache/core/watcher.rb` — `Core::Watcher`: watched-file resolution (Package.resolved + project.pbxproj inside .xcodeproj), file signatures, debounce, run_once/run loop, injected installer_factory + out sink
- `lib/spm_cache/command/watch.rb` — CLaide subcommand, `--once`, `--debounce=SECONDS`
- `spec/watch_spec.rb` — 12 specs (watching, run_once, change detection, continue-on-error, missing project, debounce, flag parsing)
- `Installer::Use` — the regeneration target (`perform_install`)

### Established Patterns
- Injectable factory + IO sink for testability (mirrors doctor's collector injection)
- `# frozen_string_literal: true`; stdlib-only; no new gem deps

### Integration Points
- `bin/spm-cache` → `Command::Watch` → `Core::Watcher` → `Installer::Use#perform_install`
- Watches `<Proj>.xcodeproj/project.xcodeproj/project.pbxproj` + `<Proj>.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`

</code_context>

<specifics>
## Specific Ideas

- The plan must VERIFY all 5 ROADMAP criteria (criterion 5 with the dated mechanism amendment), confirm the signal-trap wiring actually exists in `Watcher#run` (SIGINT/SIGTERM → flush + exit 0), and correct every "FSEvents/Fiddle" claim in PROJECT.md/STATE.md/SUMMARY-level docs to the accepted polling reality.

</specifics>

<deferred>
## Deferred Ideas

- FSEvents-via-Fiddle binding — rejected 2026-08-24 (polling accepted; latency adequate for a dev tool)
- Retry-with-backoff on transient failures — rejected 2026-08-24 (continue-on-error log suffices)

</deferred>
