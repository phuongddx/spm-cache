---
phase: 03-project-bootstrap
plan: 01
subsystem: cli
tags: [ruby, cli, claide, lockfile, json, rspec, tdd]

requires:
  - phase: 02-diagnostics-command
    provides: doc-closure amendment pattern (ROADMAP inline amendments + SUMMARY deviations section)
provides:
  - init seeds spm-cache.lock in the canonical lockfile shape consumable by DiffDetector/Installer::Use (both pins and empty-skeleton branches)
  - three regression specs (canonical shape, empty skeleton, init→Use end-to-end) in spec/init_spec.rb
  - CLI criterion proofs P1–P6 for ROADMAP Phase-3 criteria 1–4 (ephemeral /tmp/03-01-cli-proofs.rb)
  - closed doc drift: ROADMAP Phase-3 amendments, corrected phase SUMMARY, init description reword
affects: [04-ci-github-action, 05-auto-sync-watcher]

actuals:
  tokens: 4125   # chars/4 over the realized diff 6fcca3d..1d512d5
  tasks: 3
  commits: 4     # RED, GREEN, docs closure, plan metadata

tech-stack:
  added: []
  patterns:
    - "Canonical lock seeding mirrors installer.rb:176-189 field-for-field from init's pure file-I/O path (no xcodeproj gem)"

key-files:
  created:
    - .planning/phases/03-project-bootstrap/03-01-SUMMARY.md
  modified:
    - lib/spm_cache/command/init.rb
    - spec/init_spec.rb
    - .planning/ROADMAP.md
    - .planning/phases/03-project-bootstrap/SUMMARY.md

key-decisions:
  - "seed_lockfile writes the canonical shape with platforms: {} — init never opens the project via the xcodeproj gem; the consumer default (core/lockfile.rb:144-147) makes {} identical to omission"
  - "Single canonical write site shared by both branches (if/else retained only for the branch-specific UI messages) instead of duplicating the JSON.pretty_generate blocks per branch"

patterns-established:
  - "Init→Use lock contract regression: spec/init_spec.rb '→ Installer::Use seeded-lock compatibility' describe (real Xcodeproj fixture → Init → perform_install with the seven heavy regeneration methods stubbed)"

requirements-completed: [ONBD-01, ONBD-02, ONBD-03]

coverage:
  - id: D1
    description: "init seeds spm-cache.lock in the canonical shape on both branches (pins + empty skeleton), consumable by DiffDetector and Installer::Use#perform_install"
    requirement: ONBD-01
    verification:
      - kind: unit
        ref: "spec/init_spec.rb#seeds spm-cache.lock in the canonical shape consumable by DiffDetector"
        status: pass
      - kind: unit
        ref: "spec/init_spec.rb#writes a canonical empty-skeleton lock when Package.resolved is absent"
        status: pass
      - kind: integration
        ref: "spec/init_spec.rb#→ Installer::Use seeded-lock compatibility"
        status: pass
    human_judgment: false
  - id: D2
    description: "ROADMAP Phase-3 criteria 1–4 carry CLI-level proof evidence (exit-code-real Open3 invocations P1–P6)"
    requirement: ONBD-02
    verification:
      - kind: integration
        ref: "/tmp/03-01-cli-proofs.rb PROOF-1..PROOF-6 (ephemeral; evidence quoted in phase SUMMARY.md ## Verification)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Doc drift closed: ROADMAP Phase-3 criterion 1+2 amendments, corrected SUMMARY counts/provenance/deviations, init description reword"
    requirement: ONBD-03
    verification:
      - kind: other
        ref: "grep gates: description-count=1, amended-count=5 (see Deviation D2), stale-counts=0, provenance present, PROOF-lines=6"
        status: pass
    human_judgment: false

duration: 27min
completed: 2026-08-24
status: complete
---

# Phase 3 Plan 01: Project Bootstrap Closure Summary

**Canonical lock-seeding fix (init→use TypeError) proven RED→GREEN, plus CLI criterion proofs P1–P6 and full doc-drift closure**

## Performance

- **Duration:** ~27 min
- **Started:** 2026-08-24T02:29:00Z (baseline precondition run; local 09:29 +0700, previously mislabeled with a Z suffix)
- **Completed:** 2026-08-24T02:56:07Z (local UTC+0700 09:56)
- **Tasks:** 3/3
- **Files modified:** 4 (+1 created)

## Accomplishments
- Fixed the mandated defect: `seed_lockfile` now writes the canonical lock shape (`{<Proj>.xcodeproj=>{packages:[…],dependencies:{},platforms:{}}}`) on both branches, mirroring installer.rb:176-189 field-for-field; the byte-copy (`FileUtils.cp`) and `{"projects":[]}` skeleton are gone; diff_detector.rb/installer.rb/use.rb untouched; init remains pure file I/O (zero Xcodeproj references).
- Three new regression specs green (canonical shape + DiffDetector consumption, empty-skeleton, init→Installer::Use#perform_install end-to-end with empty diff) alongside the four originals: `spec/init_spec.rb` → 10 examples, 0 failures.
- All four ROADMAP Phase-3 criteria carry CLI-level evidence from `/tmp/03-01-cli-proofs.rb` (six PROOF-OK lines, exit 0, real subprocess exit codes).
- Closed all seven RESEARCH doc-drift items: ROADMAP criterion 1+2 inline amendments, phase SUMMARY corrected (196/209 line counts, 7+3=10 provenance, deviations (a)–(d), six PROOF lines, Notes), init `self.description` reworded to subsequent-runs fast-path semantics; docs/project-roadmap.md verified to contain no init item.

## RED evidence (verbatim, 2026-08-24)

```
1) SPMCache::Command::Init seeds spm-cache.lock in the canonical shape consumable by DiffDetector
   Failure/Error: expect { diff = detector.detect }.not_to raise_error
   expected no Exception, got #<TypeError: no implicit conversion of String into Integer> with backtrace:
     # ./lib/spm_cache/core/diff_detector.rb:103:in `block in locked_packages'
     # ./lib/spm_cache/core/diff_detector.rb:102:in `each_value'
     # ./lib/spm_cache/core/diff_detector.rb:57:in `detect'
...
Finished in 0.18997 seconds
10 examples, 3 failures
```

All three new examples failed RED with the same `TypeError: no implicit conversion of String into Integer` signature at diff_detector.rb:103 (the third via `installer.rb:57 detect_diff → use.rb:17 perform_install`).

## Task Commits

1. **Task 1 (TDD RED): add failing specs for canonical lock seeding** - `6933c11` (test)
2. **Task 1 (TDD GREEN): seed spm-cache.lock in canonical shape so init→use works** - `880df4e` (fix)
3. **Task 3: doc-drift closure (ROADMAP amendments, SUMMARY correction, init description)** - `1d512d5` (docs)
4. **Plan metadata** - `docs(03-01): plan summary` (docs)

Task 2 intentionally produced no commit — the proof script lives in /tmp (ephemeral, per plan) and zero repo files were touched.

## Verification results

- `bundle exec rspec spec/init_spec.rb` → **10 examples, 0 failures**
- `bundle exec rspec spec/init_spec.rb spec/diff_detector_spec.rb spec/installer_use_fast_path_spec.rb` → **27 examples, 0 failures**
- `make proxy.build && bundle exec rspec` (full suite) → **Build complete! (4.46s)** … **239 examples, 0 failures**
- `bundle exec ruby /tmp/03-01-cli-proofs.rb` → six PROOF-OK lines, exit 0
- Acceptance greps: `FileUtils.cp`=0, `FileUtils`=0, `Xcodeproj`=0 in init.rb; description-phrase=1; stale-counts=0; provenance present

## CLI proof evidence (captured verbatim)

```
PROOF-1 OK: bundle exec rspec spec/init_spec.rb -> 10 examples, 0 failures (7 init-owned examples + 3 spec_helper smoke examples), exit 0
PROOF-2 OK: init exit 0; artifacts spm-cache.yml+spm-cache.lock+.gitignore created; lock top-level key "Fake.xcodeproj" (canonical, not pins/version/projects); packages[0] name=Alamofire version=5.0.0; .gitignore has spm-cache/
PROOF-3 OK: full flag matrix (--platform/--default-config/--remote/--remote-url/--branch) exit 0 under piped (non-TTY) stdin; yml platforms=[ios] default_config=release remote includes git URL
PROOF-4 OK: double-run yml byte-stable (sha256 d1d2f51eb3b7…==d1d2f51eb3b7…); custom_key preserved + default_config updated on divergent re-run; gitignore count == 1
PROOF-5 OK: Core::DiffDetector.detect on the CLI-produced lock -> no raise, empty diff ("No changes detected. Proxy package up to date.")
PROOF-6 OK: init in empty dir (no --project) -> exit 1, output matches /No \.xcodeproj found/
```

## Files Created/Modified
- `lib/spm_cache/command/init.rb` - canonical seed_lockfile (both branches), require json (fileutils dropped), description reword (196 lines)
- `spec/init_spec.rb` - +3 examples and the Init→Use describe; requires xcodeproj/installer-use/diff-detector (209 lines)
- `.planning/ROADMAP.md` - Phase-3 criterion 1+2 inline amendments (dated 2026-08-24)
- `.planning/phases/03-project-bootstrap/SUMMARY.md` - corrected counts/provenance, Documented deviations (a)–(d), Verification, Notes
- `.planning/phases/03-project-bootstrap/03-01-SUMMARY.md` - this file

## Decisions Made
- Single canonical write site in seed_lockfile shared by both branches; if/else retained only for the branch-specific UI messages (plan described two duplicated pretty_generate blocks; functionally identical, simpler, field-for-field match preserved).
- Kept both branches' UI.info messages and conditions byte-identical, per plan.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] GREEN edit accidentally deleted find_package_resolved**
- **Found during:** Task 1 (GREEN)
- **Issue:** The first seed_lockfile replacement range over-shot by four lines and removed the adjacent `find_package_resolved` method; verification run failed with 6 NoMethodError failures.
- **Fix:** Restored the method verbatim immediately; re-ran the full verification set → 27 examples, 0 failures.
- **Files modified:** lib/spm_cache/command/init.rb
- **Verification:** `bundle exec rspec spec/init_spec.rb spec/diff_detector_spec.rb spec/installer_use_fast_path_spec.rb --format documentation` → 27 examples, 0 failures
- **Committed in:** 880df4e (GREEN commit contains the corrected final state)

### Documented plan-vs-disk conflicts (closest faithful action)

**2. ROADMAP amendment-count gate (6) unsatisfiable — actual total 5**
- **Found during:** Task 3
- **Issue:** Plan acceptance expected `grep -c "amended 2026-08-24" .planning/ROADMAP.md` == 6 ("Phase-2's existing four + Phase-3's two new"); on-disk reality is THREE pre-existing Phase-2 amendments (lines 38/40/41), not four.
- **Fix:** Added exactly the two Phase-3 amendments as instructed → total 5. Did not fabricate a fourth Phase-2 amendment to satisfy the count; the gate's substantive intent (two new, dated, correctly-scoped Phase-3 amendments) is met.
- **Verification:** `grep -c "amended 2026-08-24" .planning/ROADMAP.md` → 5
- **Committed in:** 1d512d5

**3. seed_lockfile implemented with one shared canonical write instead of two branch-local writes**
- **Found during:** Task 1 (GREEN)
- **Issue/Action:** Plan prose described a separate JSON.pretty_generate per branch; implemented `pins = resolved ? parsed_pins : []` with a single write, keeping the if/else for messages. Functionally identical on both branches (canonical shape either way); noted for the reviewer's diff expectations.
- **Verification:** Task 1 acceptance criteria all pass (both-branch canonical shape proven by the empty-skeleton spec).
- **Committed in:** 880df4e

**4. gsd-tools state handlers (advance-plan/update-progress/record-session) failed on legacy STATE.md schema**
- **Found during:** Post-task state updates
- **Issue:** `state.advance-plan` and `state.update-progress` return "Cannot parse Current Plan or Total Plans in Phase"/"Progress field not found" against this repo's hand-rolled STATE.md (pre-existing schema mismatch; failed identically before any edit this plan). `state.record-metric`, `state.add-decision`, `roadmap.update-plan-progress`, and `requirements.mark-complete` all succeeded.
- **Fix (closest faithful action):** STATE.md updated by hand with the fields those handlers would have written — current_plan/total_plans_in_phase keys added, status `awaiting-verification`, stopped_at/session continuity rewritten, Phase Status row for Phase 3 updated, ROADMAP plan checkbox ticked by `roadmap.update-plan-progress` (1/1 plans executed), decisions added via `state.add-decision`.
- **Verification:** `.planning/STATE.md` and `.planning/ROADMAP.md` contents inspected post-edit.
- **Committed in:** plan-metadata commit.

---

**Total deviations:** 1 auto-fixed (Rule 1 bug), 3 documented plan-vs-disk/tooling/implementation notes
**Impact on plan:** No scope creep; all task acceptance criteria satisfied except the mechanically-unsatisfiable ==6 amendment count (Deviation 2), where the substantive requirement is fully met.

## Issues Encountered
- None beyond Deviation 1 (caught and fixed inside Task 1's verification loop).

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- init→use path works end-to-end; canonical lock contract regression-covered for Phases 4–5 (Action relies on init artifacts; watch relies on Installer::Use diff path).
- TTY interactive prompt flow remains manual-only verification (03-VALIDATION), unchanged by this plan.

## Self-Check: PASSED

- Files exist: lib/spm_cache/command/init.rb, spec/init_spec.rb, .planning/ROADMAP.md, .planning/phases/03-project-bootstrap/SUMMARY.md, 03-01-SUMMARY.md — all FOUND.
- Commits exist on gsd/v0.3.0-milestone: 6933c11 (test RED), 880df4e (fix GREEN), 1d512d5 (docs) — all FOUND; RED precedes GREEN precedes docs in git log.
- All task acceptance criteria verified: init_spec 10/0; adjacent specs 0 failures; RED TypeError evidence captured; per-task diff scope exact; FileUtils.cp=0, FileUtils=0, Xcodeproj=0 in init.rb; live CLI spot-check canonical; six PROOF-OK lines exit 0; git clean of task-2 artifacts; description grep=1; stale counts=0; provenance string present; deviations documented above (amendment count 5 vs 6; legacy STATE.md handler mismatch hand-repaired).

---
*Phase: 03-project-bootstrap*
*Completed: 2026-08-24*
