# Phase 2: Diagnostics Command - Context

**Gathered:** 2026-08-24
**Status:** Ready for planning

<domain>
## Phase Boundary

Deliver `spm-cache doctor` so users can self-diagnose toolchain drift, cache-dir health, and remote-backend connectivity in one command — including the `companion_binary` check that surfaces the Ruby↔Swift companion version. IMPORTANT: this feature is ALREADY IMPLEMENTED on this branch (commit 5ea68a5: `lib/spm_cache/core/diagnostics.rb` 7-check registry, `lib/spm_cache/command/doctor.rb`, `spec/doctor_spec.rb` 7 specs, live run 7/7 ok). This phase's plan is VERIFICATION-SCOPED: prove the ROADMAP success criteria against the live codebase, fix any small gaps found, close doc drift — do NOT re-implement.

</domain>

<decisions>
## Implementation Decisions

### Check outcome & exit semantics (accepted as shipped)
- Exit 1 only when any check returns `:fail`; warn-only runs exit 0 (CI gates on hard failure)
- A raising check is captured as `:fail` with the error message; the report continues (never aborts)
- Missing companion binary is `:warn` (build falls back to source; binary-gated specs skip), not `:fail`

### Registry & extensibility (accepted as shipped)
- Checks added/removed via the Ruby-level `Core::Diagnostics.register` API — the registry is the single source of truth; the `doctor` command is never edited to add checks
- Report order = registration order (preserved)
- Checks receive `Core::Config` (nil-safe outside a project); no global singleton access inside checks

### Output contracts (accepted as shipped)
- Text report: `✓/!/✗ name: message`, `↳ fix_hint` on non-ok, trailing `Summary: N ok, N warnings, N failures`
- `--json`: `{checks:[{name,status,message,fix_hint}], summary:{ok,warnings,failures}}`, pretty-printed
- ACCEPTED LIMITATION: REL-02 says "color-coded green/yellow/red"; the shipped report uses plain text markers (✓/!/✗) with NO ANSI color — accepted by user 2026-08-24 as terminal-agnostic, pipe-safe. Record this as a documented deviation, not a gap.

### Version-drift scope (accepted as shipped)
- `companion_binary` = presence check (`File.executable?`) + reports the companion `--version` string when present — drift made VISIBLE, not compared. ACCEPTED LIMITATION (user, 2026-08-24): no explicit gem-VERSION vs companion-version comparison.
- Diagnostics are strictly read-only; fix hints only, no `--fix` flag, no auto-remediation

### Claude's Discretion
Plan task granularity for verification-scoped work; how to organize acceptance-criteria proofs (spec runs vs CLI invocations); minor doc-phrasing fixes.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `lib/spm_cache/core/diagnostics.rb` — `Diagnostics` class: `Check`/`Result` structs, `register`, `run_all(config:)`, rescue-to-fail per check; 7 built-in checks registered at load (xcode_version, swift_version, toolchain_path, cache_dir_health, library_evolution_compatibility, remote_backend_connectivity, companion_binary)
- `lib/spm_cache/command/doctor.rb` — CLaide subcommand, `--json` flag, exit-1-on-fail semantics
- `spec/doctor_spec.rb` — 7 specs (injected/stubbed shell collectors; no real Xcode required)
- `Core::Sh.capture_output` / `Core::Config` — existing plumbing used by checks

### Established Patterns
- CLaide command tree (`Command::Doctor < Command`), `self.options` + `argv.flag?` parsing
- Registry-of-blocks data-driven design (each check a named callable + fix_hint)
- `# frozen_string_literal: true` header; `Core::Sh` for all shell-outs

### Integration Points
- `bin/spm-cache` → `Command` tree → `Command::Doctor`
- Checks read `Core::Config.instance` (project context optional)
- Companion binary path: `tools/spm-cache-proxy/.build/release/spm-cache-proxy`

</code_context>

<specifics>
## Specific Ideas

- The plan must VERIFY each ROADMAP success criterion (1: 7-check registry + color-coded report — see accepted limitation above; 2: `--json`; 3: addable/removable without editing the command; 4: unit-testable via injected collectors) with concrete evidence (spec runs, CLI invocations), and fix only what fails.
- The two ACCEPTED LIMITATIONS (no ANSI color; no version-drift comparison) must be recorded in the phase docs as user-accepted deviations so the verifier does not count them as gaps.

</specifics>

<deferred>
## Deferred Ideas

- yml-driven check enable/disable list (`doctor.checks:` in spm-cache.yml) — rejected 2026-08-24 in favor of the Ruby registry API
- `--fix` auto-remediation flag — rejected 2026-08-24 (read-only diagnostics)

</deferred>
