# Phase 3 Summary — Project Bootstrap

**Requirement:** ONBD-01, ONBD-02, ONBD-03
**Status:** Complete

## Deliverables
- `lib/spm_cache/command/init.rb` (196 lines post-fix; 177 at original ship `c51cedc`) — `spm-cache init` wizard. Auto-detects .xcodeproj, prompts for platforms/config/remote (interactive when TTY, non-interactive via flags). Generates spm-cache.yml (idempotent diff-merge) + seeds spm-cache.lock from Package.resolved **in the canonical lockfile shape** (03-01 Task 1 fix, mirroring installer.rb:176-189 field-for-field) + appends to .gitignore once.
- `spec/init_spec.rb` (209 lines post-fix; 105 at original ship) — 7 init examples + 3 spec_helper examples = 10 (run count). The 7 init-owned examples: bootstrap non-interactive, `seeds spm-cache.lock in the canonical shape consumable by DiffDetector`, `writes a canonical empty-skeleton lock when Package.resolved is absent`, idempotency, git remote config, graceful no-.xcodeproj failure, and the `→ Installer::Use seeded-lock compatibility` describe (init → `Installer::Use#perform_install` end-to-end). All passing.

## Key decisions
- Renamed `--config` to `--default-config` to avoid collision with the inherited Command `--config` (SDK config) option.
- `resolve_project` validates the path exists (not just non-nil).
- Lock seeding writes the canonical shape with `platforms: {}` — init is pure file I/O and never opens the project via the xcodeproj gem; the only Ruby consumer (`Core::Lockfile#platforms_for_project`, core/lockfile.rb:144-147) defaults to `{}` when the key is absent/empty, so `{}` is consumer-identical to omission. `dependencies: {}` fills with real values on the first full `use` (`refresh_consumed_dependencies`).

## Documented deviations (user-accepted / accepted-as-shipped)

All dated 2026-08-24. Sources: 03-CONTEXT.md (user decisions), RESEARCH.md, 03-01-PLAN.md (open-question resolutions 1-3).

- **(a) `--default-config` replaces ROADMAP's `--config`** — CLaide base `Command` already defines `--config` (SDK config) at command.rb:19; the rename avoids the collision. User-accepted (03-CONTEXT). No alias shipped.
- **(b) Shipped flag superset adds `--project` and `--creds`** beyond the ROADMAP-listed five (`--platform`, `--config`→`--default-config`, `--remote`, `--remote-url`, `--branch`). User-accepted (03-CONTEXT).
- **(c) Seeded-lock format defect — FOUND in verification and FIXED** — the original seed byte-copied Package.resolved (`FileUtils.cp`) and the empty branch wrote a `{"projects":[]}` skeleton; both crashed `use` with `TypeError: no implicit conversion of String into Integer` at diff_detector.rb:103 (e2e-verified in RESEARCH). Fixed to the canonical shape in this phase (03-01 Task 1, RED `6933c11` → GREEN `880df4e`).
- **(d) ROADMAP criterion 1 "first `use` fast path" amended** — `fast_path?` requires a materialized proxy (use.rb:45-51); a first run always fully regenerates by design. The fast path materializes from the *second* `use` run; the seed's value is lock continuity. Criterion wording amended inline (2026-08-24).

## Verification
- RED → GREEN provenance: `test(03-01)` (6933c11, 3 failing examples, all `TypeError: no implicit conversion of String into Integer` with backtrace at diff_detector.rb:103) precedes `fix(03-01)` (880df4e, 10 examples 0 failures) in git history.
- PROOF-1 OK: bundle exec rspec spec/init_spec.rb -> 10 examples, 0 failures (7 init-owned examples + 3 spec_helper smoke examples), exit 0 — criterion 4
- PROOF-2 OK: init exit 0; artifacts spm-cache.yml+spm-cache.lock+.gitignore created; lock top-level key "Fake.xcodeproj" (canonical, not pins/version/projects); packages[0] name=Alamofire version=5.0.0; .gitignore has spm-cache/ — criterion 1
- PROOF-3 OK: full flag matrix (--platform/--default-config/--remote/--remote-url/--branch) exit 0 under piped (non-TTY) stdin; yml platforms=[ios] default_config=release remote includes git URL — criterion 2
- PROOF-4 OK: double-run yml byte-stable (sha256 d1d2f51eb3b7…==d1d2f51eb3b7…); custom_key preserved + default_config updated on divergent re-run; gitignore count == 1 — criterion 3
- PROOF-5 OK: Core::DiffDetector.detect on the CLI-produced lock -> no raise, empty diff ("No changes detected. Proxy package up to date.") — criterion 1 consumption bridge
- PROOF-6 OK: init in empty dir (no --project) -> exit 1, output matches /No \.xcodeproj found/ — error path
- Adjacent lockfile contracts untouched by the seed change: `spec/diff_detector_spec.rb spec/installer_use_fast_path_spec.rb` → 0 failures (17 examples).
- Proof script: `/tmp/03-01-cli-proofs.rb` (ephemeral, never committed; six Open3 subprocess invocations with real exit codes).

## Notes
- TTY-heuristic nuances (accepted-as-shipped; manual-only verification per 03-VALIDATION): only `--platform`/`--remote` suppress prompts (`interactive?` at init.rb checks exactly those two — other flags alone still prompt on a real TTY); the `||` fallback fires on EOF only, not empty Enter — empty Enter on the platforms prompt omits the key, on the config prompt writes `default_config: ''`, on the remote prompt is treated as `none`. CI is safe regardless (piped stdin ⇒ `.tty?` false). 03-CONTEXT.md is a locked decisions doc — recorded here instead of editing it.
- platforms:{} seeding rationale: init's pure file-I/O contract (no xcodeproj gem, no Xcode toolchain anywhere in the init path) + consumer default `core/lockfile.rb:144-147`.
- docs/project-roadmap.md check: `grep -in "init\|bootstrap" docs/project-roadmap.md` → zero matches; the v0.3.0 section contains no init/bootstrap item, so no edit was needed. Absence documented here rather than left silent.

## Commits
- `c51cedc` feat: add spm-cache init wizard (ONBD-01/02/03)
- `6933c11` test(03-01): add failing specs for canonical lock seeding (init→use TypeError) — RED
- `880df4e` fix(03-01): seed spm-cache.lock in canonical shape so init→use works — GREEN
