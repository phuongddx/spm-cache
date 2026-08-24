# Phase 2 Summary — Diagnostics Command

**Requirement:** REL-02, REL-03
**Status:** Complete

## Deliverables
- `lib/spm_cache/core/diagnostics.rb` (156 lines) — data-driven check registry: 7 checks (xcode_version, swift_version, toolchain_path, cache_dir_health, library_evolution_compatibility, remote_backend_connectivity, companion_binary). Each check returns :ok/:warn/:fail + message + fix_hint. Checks addable/removable without editing the command.
- `lib/spm_cache/command/doctor.rb` (82 lines) — `spm-cache doctor` subcommand with `--json` output.
- `spec/doctor_spec.rb` (69 lines at ship; 257 lines after plan 02-01 Task 2) — 4 doctor examples + 3 spec_helper examples = 7 (spec provenance per RESEARCH Pitfall 3); plan 02-01 added the hermetic collector-injection layer over the `Core::Sh` seam (exact per-check ok/fail/warn paths, absent-toolchain full report + exit 1, raising-check JSON validity) — 23 examples in the file post-fix, all passing.
- Companion `--version` support (plan 02-01 Task 1, post-fix): `spm-cache-proxy --version` exits 0 and prints `0.3.0` from the single `proxyVersion` constant in `tools/spm-cache-proxy/Sources/CLI.swift`; the live `doctor` companion_binary check renders the ` (0.3.0)` suffix (previously a dead probe branch).

## Verification
- `doctor` runs live: 7/7 checks ok (Xcode 26.3, Swift 6.2.4, toolchain, cache dir, LE, no remote, companion binary present with version suffix)
- `doctor --json` emits valid JSON with checks[] + summary{ok,warnings,failures}
- Data-driven registry verified: a raising check is captured as :fail without aborting the report

## Documented deviations (user-accepted / accepted-as-shipped)

All dated 2026-08-24. Sources: 02-CONTEXT.md (user decisions), RESEARCH.md (Pattern 2 / Pitfall 7), 02-01-PLAN.md (open-question resolutions 1-4).

- **(a) Plain markers instead of color** — REL-02 says "color-coded green/yellow/red report"; the shipped report uses plain ✓/!/✗ markers with no ANSI color. User-accepted (02-CONTEXT, Output contracts): terminal-agnostic, pipe-safe. Not a gap.
- **(b) Companion version drift displayed, never compared** — `companion_binary` reports presence + the companion `--version` string; there is no gem-VERSION vs companion comparison and no exit-code gating on drift. User-accepted (02-CONTEXT, Version-drift scope). Not a gap.
- **(c) REL-02 "cache-dir health/orphans" → count-only health** — the shipped `cache_dir_health` check counts configs/files; it performs no orphan detection. Accepted as shipped (RESEARCH Pattern 2; 02-01-PLAN OQR 3).
- **(d) REL-02 "remote-backend connectivity" → config-presence only** — the shipped `remote_backend_connectivity` check tests config presence (`raw['remote']` nil/empty); it runs no network probe. Accepted as shipped (RESEARCH Pattern 2; 02-01-PLAN OQR 3).
- **(e) ROADMAP SC3 "via config" → Ruby register API** — "config" is delivered as the data-driven Ruby `Core::Diagnostics.register` API; a yml `doctor.checks:` enable/disable list was explicitly rejected (02-CONTEXT, Deferred Ideas). Accepted interpretation (02-01-PLAN OQR 2).
- **(f) ROADMAP SC4 → Sh-seam collector injection, not constructor injection** — the delivered unit-test mechanism is spec-level injection of stubbed shell-output collectors over the existing `Core::Sh` seam (`allow(SPMCache::Core::Sh).to receive(:capture_output)`); no production-code constructor/parameter seam was added. Accepted interpretation (02-01-PLAN OQR 2).
- **(g) Companion `--version` honored via the proxy root flag** — the check's version-probe branch was dead code at ship (the binary rejected `--version`, exit 64); plan 02-01 Task 1 fixed it by adding the root-level `--version` flag with a single `proxyVersion` constant. Gap fix delivered this phase.

## Commits
- `5ea68a5` feat: add spm-cache doctor command (REL-02, REL-03)
- `792576c` test(02-01): RED add failing companion --version spec
- `789c4e5` fix(02-01): honor companion --version probe via root version flag
- `c627a98` test(02-01): hermetic collector-injection specs for doctor checks
