# Phase 3: Project Bootstrap - Context

**Gathered:** 2026-08-24
**Status:** Ready for planning

<domain>
## Phase Boundary

Deliver `spm-cache init` — an interactive wizard that bootstraps a new project to a working `spm-cache.yml` + seeded lockfile in one command, removing cold-start friction. IMPORTANT: ALREADY IMPLEMENTED on this branch (commit c51cedc: `lib/spm_cache/command/init.rb` 169 lines, `spec/init_spec.rb`, 7 flags). This phase's plan is VERIFICATION-SCOPED: prove ROADMAP success criteria against the live code, record documented deviations, close doc drift — do NOT re-implement.

</domain>

<decisions>
## Implementation Decisions

### Flag surface (accepted as shipped, 2026-08-24)
- `--default-config=CONFIG` replaces ROADMAP's `--config` wording — DOCUMENTED DEVIATION: the inherited CLaide `Command` base already defines `--config` (SDK config); the rename avoids the collision. Record in phase docs; do not alias.
- Full flag set: `--project=PATH`, `--platform=LIST`, `--default-config=CONFIG`, `--remote=BACKEND`, `--remote-url=URL`, `--branch=BRANCH` (default main), `--creds=PATH` (S3 credentials; superset of the ROADMAP list — accepted).

### Interactive heuristic (accepted as shipped)
- Prompts appear only when stdin is a TTY AND no non-interactive flags were supplied; CI (piped stdin) or any flag → defaults: platforms `ios`, config `debug`, remote `none`, branch `main`
- Empty prompt input falls back to the per-prompt default (`ios`/`debug`/`none`); no re-prompt loop, no abort

### Lockfile seeding & idempotency (accepted as shipped)
- No `Package.resolved` present → seeding skipped with a message; `spm-cache.yml` still generated; exit 0
- Existing `spm-cache.yml` on re-run → idempotent diff-merge (user keys preserved, defaults added, never overwritten); `spm-cache/` appended to `.gitignore` once
- `resolve_project` validates the detected/passed path exists (not just non-nil) — no .xcodeproj → clear error naming `--project`

### Claude's Discretion
Verification task granularity; how to organize acceptance proofs (spec runs vs tmpdir CLI invocations); doc phrasing fixes.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `lib/spm_cache/command/init.rb` — CLaide subcommand; argv.option parsing; TTY-conditional prompts; yml diff-merge; lockfile seeding from Package.resolved; .gitignore append-once
- `spec/init_spec.rb` — tmpdir + fixture .xcodeproj regression specs (bootstrap, idempotency, git remote config, graceful failure)
- `Core::Config`, `Core::Lockfile`, `Syntax::YAMLRepresentable` — config/lockfile plumbing

### Established Patterns
- CLaide command tree (`Command::Init < Command`), `self.options` + `argv.option`
- `# frozen_string_literal: true`; `Core::Sh` for shell-outs; no new gem deps

### Integration Points
- `bin/spm-cache` → `Command::Init`; reads `.xcodeproj` + `Package.resolved`; writes `spm-cache.yml` + `spm-cache.lock` + `.gitignore`
- First `spm-cache use` consumes the seeded artifacts (fast path)

</code_context>

<specifics>
## Specific Ideas

- The plan must VERIFY each ROADMAP success criterion with concrete evidence, and treat the `--config`→`--default-config` rename as a documented deviation (user-accepted 2026-08-24), not a gap.
- Reconcile doc drift: SUMMARY claims 7 specs; `spec/init_spec.rb` currently has 5 `it` blocks — counts must match reality.

</specifics>

<deferred>
## Deferred Ideas

- `--yes`/`--non-interactive` explicit flag — rejected 2026-08-24 (TTY heuristic covers CI; flags imply non-interactive)
- `--config` alias for `--default-config` — rejected 2026-08-24 (rename is the cleaner contract)

</deferred>
