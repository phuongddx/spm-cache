---
phase: 03-project-bootstrap
verified: 2026-08-24T03:31:51Z
status: passed
score: 12/12 must-haves verified
behavior_unverified: 0
overrides_applied: 0
prohibitions_confirmed: 3
prohibitions_unverified: 0
---

# Phase 3: Project Bootstrap Verification Report

**Phase Goal:** Deliver `spm-cache init` — an interactive wizard that bootstraps a new project to a working `spm-cache.yml` + seeded lockfile in one command, removing cold-start friction.
**Verified:** 2026-08-24T03:31:51Z (branch `gsd/v0.3.0-milestone` at `fc237f8`)
**Status:** passed
**Re-verification:** No — initial verification (no prior `*-VERIFICATION.md` in the phase directory)

## Verification Method

All evidence below was gathered this session by running commands against the current working tree and reading source directly — nothing taken from SUMMARY.md/03-01-SUMMARY.md/03-REVIEW.md on faith. Commit provenance confirmed on branch: `6933c11` (RED, spec-only, 104+/0 in `spec/init_spec.rb`) → `880df4e` (GREEN, `lib/spm_cache/command/init.rb` only, 24+/5−) → `1d512d5` (doc closure) → review fixes `427628d` (WR-01 parse guard + malformed spec), `80fb0bd`/`55a9f2d` (IN-03/IN-04), `fdc7e55`/`5b48404`/`fc237f8` (doc/resolution). The ephemeral CLI proof script was re-run by this verifier (with only its P1 count assertion updated to post-review reality — 11 vs 10 examples — the WR-01 fix added one spec); the TTY-positive interactive branch was additionally exercised first-hand via a real PTY session, which no prior evidence covered.

## Goal Achievement

### Observable Truths (03-01-PLAN must_haves + ROADMAP Phase-3 criteria)

| # | Truth | Status | Evidence (first-hand, this session) |
|---|-------|--------|--------------------------------------|
| 1 | **SC1**: `init` bootstraps a fixture project exit-0, creating `spm-cache.yml` + canonical-seeded `spm-cache.lock` + `.gitignore` with `spm-cache/`; fast-path wording amended to *subsequent* `use` runs; `--default-config` rename documented | ✓ VERIFIED | PROOF-2 re-run: exit 0; yml+lock+.gitignore exist; lock top-level key `"Fake.xcodeproj"` (not `pins`/`version`/`projects`), `packages[0]` name=Alamofire version=5.0.0; `.gitignore` contains `spm-cache/`. Cwd auto-detect run (no `--project`, empty dir): exit 0, canonical lock. Amendment (d) grounded: `use.rb:45-51` `fast_path?` requires a materialized `proxy_dir/Package.swift` — a first run can never fast-path by design. Deviations (a)/(b) recorded in ROADMAP criterion-1 amendment (names rename, subsequent-runs rewording, and the format defect FIXED) |
| 2 | **SC2**: non-interactive flag matrix works for scripting/CI under piped stdin | ✓ VERIFIED | PROOF-3 re-run: `--platform=ios --default-config=release --remote=git --remote-url=https://github.com/example/cache.git --branch=release` via Open3 (non-TTY stdin) → exit 0; yml `platforms==[ios]`, `default_config==release`, remote includes the git URL. Additional `--remote`-only invocation (no `--platform`) → exit 0. Shipped flag surface `--project/--platform/--default-config/--remote/--remote-url/--branch/--creds` confirmed in `self.options`; CLaide base `--config` collision confirmed at `command.rb:19` |
| 3 | **SC3**: re-run idempotently diff-merges (byte-stable, user keys survive, defaults added, gitignore once) | ✓ VERIFIED | PROOF-4 re-run: double-run yml sha256 `d1d2f51eb3b7…==d1d2f51eb3b7…` (byte-stable); injected `custom_key: keep-me` preserved while `default_config` updated to release on divergent re-run; `.gitignore.scan('spm-cache/').length == 1`. Spec `is idempotent — re-running preserves user keys…` green |
| 4 | **SC4**: `spec/init_spec.rb` passes in tmpdir fixtures; adjacent lockfile contracts remain green | ✓ VERIFIED | This verifier's run: `spec/init_spec.rb` → **11 examples, 0 failures** (8 init-owned + 3 spec_helper smoke; the plan-time "10" predates the WR-01 malformed-pins spec — delta documented in 03-REVIEW). Three-file scoped run `init_spec + diff_detector_spec + installer_use_fast_path_spec` → **28 examples, 0 failures** |
| 5 | **LOCK-CANONICAL**: both `seed_lockfile` branches write the canonical lock shape; byte-copy and `{"projects":[]}` skeleton gone | ✓ VERIFIED | Direct read of `init.rb:144-176`: pins branch maps `location→repositoryURL`, `identity→name`, `state.version→version`, `state.revision→revision` keyed `File.basename(project_path)` with `dependencies: {}`, `platforms: {}`, via `JSON.pretty_generate`; empty branch writes the same shape with `packages: []`. Field-for-field parity with `installer.rb:176-189` confirmed line-by-line (sole divergence `platforms: {}` vs `detect_platforms` — grounded in consumer default `core/lockfile.rb:143-147` `data["platforms"] || {}` and the ONBD-01 prohibition). `grep -c FileUtils init.rb` = **0**; `grep -c Xcodeproj init.rb` = **0** |
| 6 | **USE-E2E**: init-seeded lock consumable by the `use` path (no TypeError; empty diff; perform_install completes) | ✓ VERIFIED | Named passing spec `→ Installer::Use seeded-lock compatibility` (real `Xcodeproj::Project` fixture → `Command::Init#run` → `Installer::Use#perform_install` with exactly the seven heavy regeneration methods stubbed via `allow`; `verify_projects!`/`detect_diff` real): no raise, `installer.diff` empty — green in this verifier's run. PROOF-5 re-run: `Core::DiffDetector#detect` on the CLI-produced lock → no raise, empty diff ("No changes detected. Proxy package up to date."). RED provenance corroborated: `6933c11` is spec-only (git stat 104 insertions, zero lib files) and the recorded TypeError signature matches the real failure site `diff_detector.rb:103` (`proj_data['packages']` String-indexing the pins array — verified against current consumer code) |
| 7 | **PROBE-ONBD-01**: prompts fire only when stdin is a TTY AND neither `--platform` nor `--remote` supplied | ✓ VERIFIED (behavioral, both branches) | Code: `interactive?` = `$stdin.tty? && @platforms.nil? && @remote.nil?` — exactly the two flags. Non-TTY half: every Open3/subprocess run this session (P2/P3/P4, remote-only, no-resolved) printed zero prompts and exited 0 with defaults applied. TTY-positive half — **exercised by this verifier via a real PTY session** (`PTY.spawn` driver, /tmp/verif-03-pty-probe.rb): all 3 prompts fired in order (Platforms / Default build config / Remote backend), answers landed in the yml (`platforms=["macos"]`, `default_config="release"`, remote absent for `none`), canonical lock seeded, exit 0. Empty-Enter nuance confirmed: empty platforms input **omits the key** (observed `platforms nil` — matches the recorded accepted-as-shipped note verbatim) |
| 8 | **PROBE-ONBD-02**: every scripting invocation passing `--platform` and/or `--remote` completes without blocking on stdin | ✓ VERIFIED | Full matrix, all non-TTY, all exit 0: `--platform` only (P2), `--platform`+`--default-config`+`--remote`+`--remote-url`+`--branch` (P3), `--remote`+`--remote-url` only (this verifier's run), triple sequential runs (P4). No invocation hung or waited on stdin |
| 9 | **PROBE-ONBD-03a**: identical-flags re-run yields byte-stable yml | ✓ VERIFIED | PROOF-4 sha256 equality across two CLI runs (Config#load merge convergence — `config.rb:47-49`) |
| 10 | **PROBE-ONBD-03b**: no-`Package.resolved` project still bootstraps fully with the informational message naming `spm-cache use` | ✓ VERIFIED | This verifier's CLI run: exit 0; `spm-cache.yml` + `.gitignore` (`# spm-cache sandbox` / `spm-cache/`) + lock parses to `{"Fake.xcodeproj"=>{"packages"=>[], "dependencies"=>{}, "platforms"=>{}}}`; stdout contains `Created empty spm-cache.lock (run \`spm-cache use\` after resolving deps).` Spec empty-skeleton example green (shape + DiffDetector consumption) |
| 11 | **PROBE-ONBD-03c**: on key collision the USER value wins; init assigns only managed keys | ✓ VERIFIED | `config.rb:48` `DEFAULT_CONFIG.merge(YAML.safe_load(...) || {})` — file wins. `write_config` body read directly: assigns exactly `platforms` (when non-empty), `default_config` (when truthy), `default_sdk` (only `unless key?`), `remote` (when non-empty). P4 + idempotency spec confirm behaviorally |
| 12 | **DOC-CLOSURE**: all seven RESEARCH drift items closed | ✓ VERIFIED | ROADMAP: `amended 2026-08-24` count **5** (3 pre-existing Phase-2 + 2 new Phase-3; plan's ==6 gate was arithmetically wrong — Deviation 2, waived in WINDOWS.md `open_count: 0`); criterion-1 amendment names rename + subsequent-runs + format FIXED; criterion-2 names the superset. SUMMARY: `Documented deviations` section with exactly 4 records (a)–(d); provenance string present; 6 `PROOF-` lines; Notes carry TTY nuances + platforms rationale + docs-roadmap check. init description phrase count **1**; stale `169 lines|107 lines` count **0**; `grep -in "init\|bootstrap" docs/project-roadmap.md` → zero matches. See informational note below on post-review count drift |

**Score:** 12/12 truths verified (0 present-but-behavior-unverified — the TTY branch, the only candidate, was exercised via PTY)

### Informational Notes (not gaps)

1. **Post-review count drift:** SUMMARY/03-01-SUMMARY record `196/209` line counts and `10 examples` — accurate at doc-closure commit `1d512d5`, but the review cycle (`427628d` guard + spec, `80fb0bd`/`55a9f2d`) shifted reality to `wc -l` **213/237** and **11 examples**. The deltas are fully documented in 03-REVIEW.md with commit trail; the DOC-CLOSURE truth's own wording scopes measurement to close time, and the drift items it closed (stale 169/107, missing provenance, absent amendments) remain closed. No action required for this phase; a fresh `wc -l`/count sync can ride the next doc touch.
2. **REQUIREMENTS.md ONBD-01 wording** still reads "so the first `use` is a fast path" (pre-amendment phrasing). The amendment lives in ROADMAP (the contract doc) per the established phase-2 pattern; REQUIREMENTS is the 2026-08-10 definition record. Informational only.
3. **Review advisories IN-01/IN-02** (re-init overwrites a use-enriched lock — pre-existing, self-healing; legacy c51cedc locks crash `use` until re-init) are acknowledged and dispositioned in 03-REVIEW.md — IN-01 a Phase 4/5 hardening candidate, IN-02 a v0.3.0 release-notes item. Treated as documented, not gaps.

### Prohibition Dispositions (descriptor-less, flagged-unverified at plan time — disposed per honest-verifier contract: explicit first-hand evidence → confirmed, never a silent pass)

| # | Prohibition | Disposition | Evidence |
|---|-------------|-------------|----------|
| P1 | ONBD-01 (safety): init MUST NOT invoke the Xcode toolchain or open the project via the xcodeproj gem — pure file I/O; platforms seeds `{}` not `detect_platforms` | ✓ CONFIRMED | `grep -c Xcodeproj lib/spm_cache/command/init.rb` = **0**; `grep -c FileUtils` = **0**; shell-out scan (`system(`/`IO.popen`/`Open3`/`fork`/`%x`) = **0 hits**; the dead `core/sh` require was deleted in `80fb0bd`. Full-file read confirms only `Dir.glob`/`File`/`JSON`/`YAML` I/O. `platforms: {}` confirmed in the seed body; consumer default `core/lockfile.rb:143-147` makes it equivalent |
| P2 | ONBD-02 (safety): init MUST NOT block on stdin prompts in non-TTY contexts | ✓ CONFIRMED (behavioral) | `interactive?` gates on `$stdin.tty?` (code read); every non-TTY invocation this session — 4 flag combinations plus the malformed-input spec — completed without reading stdin (a block would hang; all exited 0 promptly) |
| P3 | ONBD-03 (transparency): a re-run MUST NOT lose or overwrite user-set yml keys outside the managed set | ✓ CONFIRMED | `write_config` assigns exactly the four managed keys (direct read; `default_sdk` only when absent); `Core::Config#load` merges `DEFAULT_CONFIG.merge(file)` so user values win; P4's `custom_key` survived a divergent re-run; idempotency spec green. (IN-01's lock-file overwrite is outside this prohibition's yml scope and is a documented advisory) |

### Required Artifacts

| Artifact | Status | Details |
|----------|--------|---------|
| `lib/spm_cache/command/init.rb` | ✓ VERIFIED | 213 lines (post-review); canonical `seed_lockfile` both branches; WR-01 parse guard with `is_a?(Hash)` + `rescue JSON::ParserError, TypeError` → warn + empty-skeleton; wired via `bin/spm-cache` CLI tree (exercised end-to-end this session) |
| `spec/init_spec.rb` | ✓ VERIFIED | 237 lines; 8 init-owned examples + e2e describe + 3 spec_helper = 11, 0 failures; hermetic (own tmpdirs, `ensure` cleanup, `Config.reset!` before every run) |
| `.planning/ROADMAP.md` | ✓ VERIFIED | Phase-3 criterion 1+2 dated amendments present; `1/1 plans executed` with checkbox ticked |
| `.planning/phases/03-project-bootstrap/SUMMARY.md` | ✓ VERIFIED | Deviations (a)–(d), provenance, 6 PROOF lines, Notes; counts accurate at close time (see informational note 1) |
| `.planning/phases/03-project-bootstrap/03-01-SUMMARY.md` | ✓ VERIFIED | Present; RED evidence quote matches the real `diff_detector.rb:103` site; deviations ledger |
| `.planning/phases/03-project-bootstrap/03-REVIEW.md` | ✓ VERIFIED | status: resolved; WR-01/IN-03..06 fixed with commits; IN-01/02 advisories dispositioned |
| `.planning/WINDOWS.md` | ✓ VERIFIED | Amendment-count deviation row waived; `open_count: 0` — ship gate unblocked |

### Key Link Verification

| From | To | Via | Status |
|------|----|----|--------|
| `Command::Init#seed_lockfile` | `Core::DiffDetector#locked_packages` → `Installer::Use#perform_install` | canonical JSON write → `JSON.parse` + `each_value`/`packages` Array → `detect_diff` | ✓ WIRED (spec-level e2e green + PROOF-5 CLI-artifact bridge; the repaired crash link) |
| CLI flags | `write_config` → `Core::Config#load` → `spm-cache.yml` | managed-key assignment → `DEFAULT_CONFIG.merge(file)` → save | ✓ WIRED (PROOF-3/4 yml values + idempotency) |
| `installer.rb:176-189` transformation ↔ `init.rb` seed | field-for-field mirror | `location/identity/state.version/state.revision` → `repositoryURL/name/version/revision`, basename key | ✓ WIRED (line-by-line parity verified; `platforms` divergence consumer-neutral) |
| ROADMAP amendments ↔ SUMMARY deviations ↔ 03-CONTEXT acceptances | cross-reference chain | dated 2026-08-24 annotations | ✓ WIRED (SC1→(a)/(c)/(d), SC2→(a)/(b); 03-CONTEXT carries the user acceptances) |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| seeded `spm-cache.lock` | `packages[]` | real `Package.resolved` fixture pins (file read → `JSON.parse` → field map) | Yes — Alamofire URL/name/version/revision in every run's output | ✓ FLOWING |
| `spm-cache.yml` | platforms/default_config/remote | CLI flags or TTY prompts → `write_config` → merge → save | Yes — flagged values observed in yml across P2/P3/P4 + PTY session | ✓ FLOWING |
| `.gitignore` | `spm-cache/` entry | append-once guard (`lines.include?`) | Yes — exactly one entry after multi-run | ✓ FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Scoped suite | `bundle exec rspec spec/init_spec.rb spec/diff_detector_spec.rb spec/installer_use_fast_path_spec.rb` | 28 examples, 0 failures | ✓ PASS |
| init_spec alone | `bundle exec rspec spec/init_spec.rb` | 11 examples, 0 failures | ✓ PASS |
| CLI proofs P1–P6 | `bundle exec ruby /tmp/03-01-cli-proofs.rb` (P1 count updated 10→11 post-WR-01) | six `PROOF-n OK` lines, exit 0 | ✓ PASS |
| Interactive TTY session (prompts fire + answers land) | `PTY.spawn` driver feeding macos/release/none | 3 prompts in order; yml platforms=["macos"] default_config="release" remote absent; canonical lock; exit 0 | ✓ PASS |
| Empty-Enter nuance | PTY driver with `\n` answers | platforms key omitted (recorded note confirmed) | ✓ PASS |
| `--remote`-only non-TTY run | Open3-style `</dev/null` invocation | exit 0, no prompts | ✓ PASS |
| No-`Package.resolved` bootstrap | CLI run + JSON/ls inspection | exit 0; yml + `.gitignore` + canonical empty lock; message names `spm-cache use` | ✓ PASS |
| Cwd auto-detect | CLI run in fixture dir without `--project` | exit 0, artifacts created | ✓ PASS |
| Prohibition greps | `grep -c` Xcodeproj/FileUtils/shell-outs in init.rb | 0 / 0 / 0 | ✓ PASS |
| Doc gates | amended-count=5; description-phrase=1; stale-counts=0; provenance=1; deviations=4; PROOF lines=6; docs-roadmap init/bootstrap=0 matches | all as expected | ✓ PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| ONBD-01 | 03-01 | interactive bootstrap: detect `.xcodeproj`, prompts, yml + lock seeded from `Package.resolved` | ✓ SATISFIED | PTY session (prompts + answers), PROOF-2 (canonical seed), auto-detect run, SC4 specs; "first use fast path" amended to subsequent runs in ROADMAP (deviation d) |
| ONBD-02 | 03-01 | non-interactive flags for scripting/CI | ✓ SATISFIED | PROOF-3 + remote-only run + full flag surface; `--config`→`--default-config` documented deviation (a)/(b) |
| ONBD-03 | 03-01 | idempotent diff-merge, gitignore once | ✓ SATISFIED | PROOF-4, idempotency spec, `config.rb` file-wins merge |

REQUIREMENTS.md traceability rows for ONBD-01/02/03 (Phase 3, Complete) match verified reality; no orphaned requirements (ONBD-04→Phase 4, AUTO-*→Phase 5).

### Anti-Patterns Found

| File | Pattern | Severity | Impact |
|------|---------|----------|--------|
| init.rb / init_spec.rb | none — debt-marker scan (`TBD|FIXME|XXX|TODO|HACK|PLACEHOLDER`) zero hits; no empty returns/stubs | — | Clean |

### Human Verification Required

None. The only manual-only item declared by 03-VALIDATION.md (interactive TTY prompt flow) was closed behaviorally by this verifier's PTY-driven session: prompts fire on a real TTY, answers land in the yml, empty-Enter behavior matches the recorded note, and the run completes exit-0. Nothing visual, external, or otherwise unexercisable remains.

### Gaps Summary

No gaps. All 12 must-have truths verified with first-hand evidence (including the previously unexercised TTY-positive branch), all 3 descriptor-less prohibitions confirmed with explicit code/run evidence, all three ONBD requirements satisfied against the live CLI, and the review cycle's WR-01 fix re-proven (guard + regression spec green; scoped suite 28/0). Informational notes (post-review count drift, REQUIREMENTS legacy wording, IN-01/02 advisories) carry documented dispositions and require no action to close this phase.

---

_Verified: 2026-08-24T03:31:51Z_
_Verifier: Phase3Verifier (gsd-verifier)_
