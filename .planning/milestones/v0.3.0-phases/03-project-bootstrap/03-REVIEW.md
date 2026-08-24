---
phase: 03-project-bootstrap
reviewed: 2026-08-24T10:15:00Z
depth: deep
files_reviewed: 6
files_reviewed_list:
  - lib/spm_cache/command/init.rb
  - spec/init_spec.rb
  - .planning/ROADMAP.md
  - .planning/phases/03-project-bootstrap/SUMMARY.md
  - .planning/phases/03-project-bootstrap/03-01-SUMMARY.md
  - .planning/WINDOWS.md
findings:
  critical: 0
  warning: 1
  info: 6
  total: 7
status: resolved
reviewed_commits:
  - 6933c11 (test RED)
  - 880df4e (fix GREEN — only production change)
  - 1d512d5 (docs)
  - 3b194aa (plan summary)
  - 461a30c (windows ledger)
resolution:
  resolved: 2026-08-24
  resolved_by: Phase3Fixer (gsd-code-fixer)
  fix_commits:
    - 427628d (WR-01 fix: guard Package.resolved parse — JSON::ParserError/TypeError/non-object treated as absent, warn + empty-skeleton path; malformed-pins spec added)
    - 80fb0bd (IN-03 fix: unused core/sh require deleted)
    - 55a9f2d (IN-04 fix: dead newline guard clause dropped)
    - fdc7e55 (IN-05 docs: start timestamp corrected to 2026-08-24T02:29:00Z)
    - 5b48404 (IN-06 docs: windows ledger row 1 waived with reason — open_count 0)
  advisories:
    - IN-01 (re-init overwrites use-enriched lock — pre-existing, self-healing; Phase 4/5 hardening candidate, no code change)
    - IN-02 (legacy c51cedc locks crash use — v0.3.0 release-notes item: "re-run spm-cache init or delete spm-cache.lock after upgrading", no code change this phase)
---

# Phase 3: Code Review Report

**Reviewed:** 2026-08-24T10:15:00Z
**Depth:** deep (cross-file: init.rb → diff_detector.rb → installer.rb/installer/use.rb → core/lockfile.rb)
**Files Reviewed:** 6
**Status:** resolved (0 critical, 1 warning, 6 info — WR-01 + IN-03..IN-06 fixed 2026-08-24; IN-01/IN-02 acknowledged advisories, see frontmatter `resolution`)

## Summary

The mandated defect fix is correct and surgically delivered. `seed_lockfile` (init.rb:144-176) now writes the canonical lock shape `{<Proj>.xcodeproj=>{packages,dependencies,platforms}}` on both branches; the pins→packages field mapping matches installer.rb:176-189 exactly (`location`→`repositoryURL`, `identity`→`name`, `state.version`→`version`, `state.revision`→`revision`, keyed `File.basename(project_path)`), verified line-by-line against the installer source. `platforms: {}` (vs installer's `detect_platforms`) is a deliberate, documented divergence grounded in the consumer default at core/lockfile.rb:144-147 and the pure-file-I/O prohibition — no `Xcodeproj` reference and no `FileUtils` remain in init.rb (grep: 0/0).

Behavior change is confined to seeding: prompts/flags/idempotency paths are byte-identical to c51cedc (commit 880df4e diff = 24 insertions / 5 deletions in one file: require swap `fileutils`→`json`, seed_lockfile body; both `UI.info` messages and branch conditions retained verbatim; `find_package_resolved` restored intact). RED→GREEN provenance confirmed in git log: spec-only RED commit 6933c11 (104 insertions, no lib changes) precedes 880df4e; the RED TypeError quote in 03-01-SUMMARY matches the actual failure site (diff_detector.rb:103 — `proj_data['packages']` String-indexing the pins Array).

The new specs are hermetic and honest: tmpdir fixtures with `ensure`-guarded cleanup, `Config.instance.reset!` before every `cmd.run`, explicit `lockfile_path` wiring into DiffDetector (no ambient Config dependence in the assertions), and the plain-directory examples are grounded in `merge_project_refs`' `rescue StandardError → return` on `Xcodeproj::Project.open` (diff_detector.rb:160-166) — the empty-diff assertions exercise both sides of the real contract, not a stub. The e2e describe stubs exactly perform_install's seven heavy regeneration methods (allow, not expect) while `verify_projects!` and `detect_diff` run real. I re-ran the scoped suite: **27 examples, 0 failures** across init_spec + diff_detector_spec + installer_use_fast_path_spec, consistent with the claimed full-suite 239/0.

Doc edits verified accurate against disk: wc -l 196/209 matches SUMMARY's post-fix counts (and 177/105 at c51cedc); ROADMAP criterion-1 amendment names all three facts (rename, subsequent-runs rewording, format FIXED) and criterion-2 names the superset; `fast_path?` citation (use.rb:45-51) is correct; amendment count is 5 (documented Deviation 2 + WINDOWS.md ledger entry, not silently dropped); provenance string present; stale 169/107 counts absent; description phrase grep = 1.

No critical findings. The one warning is a niche robustness regression inherent to the (plan-mandated) switch from byte-copy to parse-and-transform; the info items are pre-existing advisories and doc/process nits.

## Warnings

### WR-01: Unguarded `JSON.parse` of Package.resolved aborts init mid-run on corrupt input

**File:** `lib/spm_cache/command/init.rb:154`
**Issue:** `JSON.parse(File.read(resolved))['pins']` has no error guard. A malformed/truncated Package.resolved raises `JSON::ParserError`; a syntactically-valid non-object (array/string) raises `TypeError`/`NoMethodError` on `['pins']`. In either case `run` aborts **after** `write_config` saved spm-cache.yml but **before** `ensure_gitignore` — leaving a half-bootstrapped project (no lock, no .gitignore entry) with a raw backtrace. This is a new failure mode introduced by this change: the pre-fix `FileUtils.cp` never read the file. It is asymmetric with the same file's own posture — `write_config` (init.rb:126-131) wraps the equivalent corrupt-yml case in `rescue StandardError`. Parity with installer.rb:173 is plan-mandated (threat model T-03-02) and the input is Xcode-owned, so this is robustness hardening, not a contract violation.
**Fix:**
```ruby
pins = begin
  data = resolved && File.exist?(resolved) ? JSON.parse(File.read(resolved)) : {}
  data.is_a?(Hash) ? (data['pins'] || []) : []
rescue JSON::ParserError, TypeError
  Core::UI.warn "Package.resolved at #{resolved} is unreadable; seeding an empty lock."
  []
end
```

**Resolution:** FIXED in 427628d — parse wrapped in `begin/rescue JSON::ParserError, TypeError` plus an `is_a?(Hash)` guard; malformed/non-object input warns via `Core::UI.warn` and takes the same empty-skeleton path as a missing file (message now keyed on successful parse, not file existence). Regression spec added (`seeds an empty lock instead of aborting when Package.resolved is malformed`): proves run completes, warn on stderr, seeding-skipped message on stdout, canonical empty lock, and `.gitignore` entry written. DiffDetector deliberately left unguarded (IN-02 scope).

## Info

### IN-01: Re-running init unconditionally overwrites a `use`-enriched lock (pre-existing)

**File:** `lib/spm_cache/command/init.rb:169`
**Issue:** `seed_lockfile` writes even when spm-cache.lock already exists. If a user runs init again after a successful `use` (lock enriched with real `dependencies`/`platforms` by `refresh_consumed_dependencies`/`detect_platforms`), those reset to `{}`. Because the re-seeded packages still match the live graph, the next `use` takes `fast_path?` (installer/use.rb:45-53: empty diff + materialized proxy) and skips regeneration — so `dependencies` stays empty until the next real package change. Pre-existing (the c51cedc byte-copy also overwrote) and self-healing on the next diff, but cheap to close: mirror installer.rb:166's `return if File.exist?(lockfile_path)` (with a UI note), which would also make init's seeding truly idempotent like the yml path.
**Fix:** Advisory only — out of this change's declared scope (plan: "no behavior change beyond seeding"). Record as a candidate for Phase 4/5 hardening.

**Resolution:** ACKNOWLEDGED ADVISORY — no code change, per the review's own guidance (out of declared scope; pre-existing and self-healing). Recorded as a Phase 4/5 hardening candidate.

### IN-02: Legacy c51cedc-seeded locks still crash `use` (advisory, pre-existing)

**File:** `lib/spm_cache/core/diff_detector.rb:103` (consumer, intentionally untouched)
**Issue:** A lock seeded by the pre-fix init (pins byte-copy or `{"projects":[]}`) still produces `TypeError: no implicit conversion of String into Integer` under `use`: `DiffDetector#locked_packages` does `data.each_value { |proj_data| proj_data['packages'] }`, and `generate_lockfile_from_resolved` early-returns on an existing lock (installer.rb:166) so the bad shape never self-heals. Documented as deviation (c) in SUMMARY, but there is no user-facing upgrade note in the tool itself (no changelog/release note).
**Fix:** Advisory: mention "re-run `spm-cache init` (or delete spm-cache.lock) after upgrading" in the v0.3.0 release notes; no code change required in this phase.

**Resolution:** ACKNOWLEDGED ADVISORY — no code change this phase. Release-notes action item captured for v0.3.0: "re-run `spm-cache init` (or delete spm-cache.lock) after upgrading".

### IN-03: Unused `require 'spm_cache/core/sh'`

**File:** `lib/spm_cache/command/init.rb:8`
**Issue:** No `Sh.` usage anywhere in init.rb — dead require carried from c51cedc. The GREEN commit already dropped the equally-dead `fileutils` require; this one was missed.
**Fix:** Delete line 8.

**Resolution:** FIXED in 80fb0bd — require deleted; `core/sh` remains independently required by its actual consumers.

### IN-04: Dead newline guard in `ensure_gitignore` (pre-existing)

**File:** `lib/spm_cache/command/init.rb:189`
**Issue:** `f.puts unless lines.empty? || lines.last&.end_with?("\n")` — `lines` is built from `readlines(...).map(&:chomp)` (line 185), so no element can ever end with `"\n"`; the guard is always false and a blank separator line is unconditionally added when the file is non-empty. Harmless cosmetically and idempotency is protected by the `lines.include?(entry)` early return; untouched by this change.
**Fix:** Drop the `|| lines.last&.end_with?("\n")` clause (or read raw lines and test the original last line) if the file is touched again.

**Resolution:** FIXED in 55a9f2d — dead clause dropped (`f.puts unless lines.empty?`); behavior identical since the guard was always false.

### IN-05: 03-01-SUMMARY timestamps imply negative duration

**File:** `.planning/phases/03-project-bootstrap/03-01-SUMMARY.md` (Performance section)
**Issue:** "Started: 2026-08-24T09:29:00Z" vs "Completed: 2026-08-24T02:56:07Z (local UTC+0700 09:56)" — taken literally, completion precedes start. The start was local time (09:29 +0700 = 02:29Z) mislabeled with a Z suffix; the ~27 min duration is otherwise consistent with the commit timestamps (09:29→10:01 +0700 spans baseline run through plan-metadata commit).
**Fix:** Correct the start stamp to `2026-08-24T02:29:00Z` (or `09:29:00+0700`).

**Resolution:** FIXED in fdc7e55 — start stamp corrected to `2026-08-24T02:29:00Z`.

### IN-06: WINDOWS.md deviation #1 left `open` — will trip the ship gate

**File:** `.planning/WINDOWS.md` (ledger row id 1)
**Issue:** The amendment-count deviation (gate expected 6, actual total 5 — correctly not fabricated) is recorded with `status: open`. With `workflow.windows_enforce` enabled, `/gsd-ship` blocks while `open_count > 0`. The substantive intent is met and documented; the row needs a waive with reason before the milestone ship step, or it will halt it.
**Fix:** `gsd-tools windows waive 1 "Plan-gate arithmetic error (Phase-2 pre-count was 3, not 4); substantive amendment intent verified met — see 03-REVIEW.md and 03-01-SUMMARY Deviation 2"` when the orchestrator reaches the ship gate.

**Resolution:** FIXED in 5b48404 — row waived via `gsd-tools windows waive 1 "<reason>"` with the review's reason; ledger now `open_count: 0`, ship gate unblocked.

---

## Verified clean (evidence)

- **Field mapping parity** init.rb:157-164 ↔ installer.rb:176-189: all four fields + basename key + `dependencies: {}` identical; sole divergence `platforms: {}` vs `detect_platforms`, grounded in core/lockfile.rb:144-147 consumer default and the ONBD-01 safety prohibition (init never opens Xcodeproj).
- **Prohibitions:** `grep -c FileUtils → 0`, `grep -c Xcodeproj → 0` in init.rb.
- **Surgical diff:** `git show 880df4e` touches exactly lib/spm_cache/command/init.rb (24+/5-); `git show 6933c11` touches exactly spec/init_spec.rb (104+, no lib); RED precedes GREEN precedes docs in history; description reword confined to the one string in 1d512d5.
- **Auto-fixed bug:** `find_package_resolved` present and verbatim (init.rb:178-180); committed GREEN state contains the restoration — no residual damage from the over-shot edit.
- **Specs hermetic:** own tmpdirs with `ensure` cleanup; `Config.instance.reset!` before every run (including both new examples and the e2e describe's before-hook); explicit `project_path`/`lockfile_path`; e2e Config wiring derives from `cmd.run`'s project_dir so all reads/writes stay inside the tmpdir (heavy writers stubbed).
- **Spec honesty:** `expect(diff).to be_empty` traces through the real `detect` (locked from seeded lock, live from Package.resolved + pbxproj refs via rescued `Xcodeproj::Project.open`); e2e leaves `verify_projects!`/`detect_diff` unstubbed.
- **Suite:** re-ran `bundle exec rspec spec/init_spec.rb spec/diff_detector_spec.rb spec/installer_use_fast_path_spec.rb` → **27 examples, 0 failures** (init_spec alone = 7 owned + 3 spec_helper = 10; spec_helper's 3 smoke `it` blocks confirmed at spec/spec_helper.rb:6/10/14).
- **Docs:** wc -l 196/209 = SUMMARY claims; 177/105 at c51cedc verified via `git show`; ROADMAP Phase-3 amendments accurate; `amended 2026-08-24` total 5 with Deviation 2 + WINDOWS ledger; provenance string present (SUMMARY.md:8); stale counts absent; `subsequent \`spm-cache use\` runs can take the fast path` count 1.

_Reviewed: 2026-08-24T10:15:00Z_
_Reviewer: Phase3Review (gsd-code-reviewer)_
_Depth: deep_
