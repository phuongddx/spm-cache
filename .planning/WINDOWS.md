---
schema_version: 1
open_count: 3
waived_count: 5
fixed_count: 0
total_count: 8
last_updated: 2026-08-30T01:10:46.904Z
---

# Broken Windows Ledger

> Cross-phase defect register. With `workflow.windows_enforce` enabled, `/gsd-ship` blocks while `open_count > 0`.
> Waive with `gsd-tools windows waive <id> "<reason>"` (reason required).
> Mark fixed with `gsd-tools windows fixed <id>`.

| id | phase | kind | file | line | description | status | reason | recorded_at | resolved_at |
|----|-------|------|------|------|-------------|--------|--------|-------------|-------------|
| 1 | 03 | deviation | .planning/ROADMAP.md | 54 | 03-01 acceptance gate 'amended 2026-08-24 == 6' unsatisfiable: Phase-2 pre-existing count was 3, not 4; Phase-3 added 2 → actual total 5 (substantive intent met; documented in 03-01-SUMMARY Deviation 2) | waived | Plan-gate arithmetic error (Phase-2 pre-count was 3, not 4); substantive amendment intent verified met — see 03-REVIEW.md and 03-01-SUMMARY Deviation 2 | 2026-08-24T03:00:58.233Z | 2026-08-24T03:21:42.678Z |
| 2 | 04 | deviation | .planning/phases/04-ci-github-action/SUMMARY.md |  | criterion-3 own-repo CI smoke test unreachable from this repo (gem unpublished — RubyGems 404; action repo unpublished); recorded as accepted external deviation + 6-item release checklist | waived | v0.3.0 carryover: RubyGems publication deferred by user decision 2026-08-27 (recorded in REQUIREMENTS.md Out of Scope). The own-repo smoke CI this gates cannot run until the gem exists on RubyGems. | 2026-08-24T04:29:10.965Z | 2026-08-27T09:17:34.113Z |
| 3 | 06 | unrun-verify | .planning/phases/06-graph-authority-lockfile-reconciliation/06-M1-MEASUREMENT.md |  | M1 step 4 live Release xcodebuild not run: A3 failed (fb8e773 removed exyte state from feature-branch tip) and the only probative commit is reachable solely via detached checkout in a dirty reference tree whose build would overwrite the pre-fix artifacts; version attribution established from realized checkout HEADs instead | waived | M1 live Release xcodebuild unreachable: research assumption A3 failed (fb8e773 removed the exyte state from the feature-branch tip). Attribution completed from committed revisions via git show instead of a substituted repro. Not retroactively fixable. | 2026-08-27T06:39:49.087Z | 2026-08-27T09:17:34.205Z |
| 4 | 06 | deviation | spec/package_resolved_spec.rb |  | Task 3's two parity examples passed on write (no RED phase) because they assert locator properties Tasks 1-2 had already delivered; commit order preserved but they are guard rails, not RED evidence | waived | Historical process gap: two parity examples in 06-02 passed on write (no RED phase) because they assert locator properties Tasks 1-2 had already delivered. Cannot be made RED after the fact; the examples are valid regression guards and pass. Self-reported by the executor rather than concealed. | 2026-08-27T07:55:37.028Z | 2026-08-27T09:17:34.307Z |
| 5 | 6 | unrun-verify | lib/spm_cache/core/diff_detector.rb | 140 | live_packages JSON.parses the host Package.resolved unguarded, so a truncated file aborts detect_diff before the reconciler's D-04 warn-and-degrade path is reachable | waived | Truncated Package.resolved aborts detect_diff (diff_detector.rb:140 unguarded parse) before D-04's warn-and-degrade is reachable. NOTE: this violates locked decision D-04's 'never crash', so it is a decision-fidelity gap, not merely missing hardening. Waived per explicit user authorization 2026-08-27 under that stronger framing. Proper fix requires deciding DiffDetector's posture for ALL detect callers and keeping the diff report honest about unreadable-vs-removed; 06-05-PLAN.md guard ordering was specified so closing it later needs no rework. | 2026-08-27T08:11:34.058Z | 2026-08-27T09:17:34.399Z |
| 6 | 06 | deviation | lib/spm_cache/core/diagnostics.rb |  | lock_graph_fidelity guards cfg.respond_to?(:lockfile_path) because a verifying instance_double raises MockExpectationError (not a StandardError) and escapes run_check's capture | open |  | 2026-08-27T08:24:12.828Z |  |
| 7 | 10 | deviation | lib/spm_cache/spm/xcframework/slice.rb | 31 | FrameworkSlice unwired dead code: copy_resource_bundles unreachable (private resource_paths defeats respond_to? guard, bare-Sh NameError, template binding mismatch) — TEST-03 class 6/8 drives the real copy via send; logged in deferred-items.md | open |  | 2026-08-29T16:38:32.821Z |  |
| 8 | 11 | deviation | spec/main_version_spec.rb |  | RED manifests as SystemExit run-termination (exit 1, no version output) instead of '2 reported failures' — stubbing forbidden by plan; GREEN unaffected | open |  | 2026-08-30T01:10:46.904Z |  |

````json
[
  {
    "id": 1,
    "kind": "deviation",
    "phase": "03",
    "file": ".planning/ROADMAP.md",
    "line": 54,
    "description": "03-01 acceptance gate 'amended 2026-08-24 == 6' unsatisfiable: Phase-2 pre-existing count was 3, not 4; Phase-3 added 2 → actual total 5 (substantive intent met; documented in 03-01-SUMMARY Deviation 2)",
    "status": "waived",
    "reason": "Plan-gate arithmetic error (Phase-2 pre-count was 3, not 4); substantive amendment intent verified met — see 03-REVIEW.md and 03-01-SUMMARY Deviation 2",
    "recorded_at": "2026-08-24T03:00:58.233Z",
    "resolved_at": "2026-08-24T03:21:42.678Z"
  },
  {
    "id": 2,
    "kind": "deviation",
    "phase": "04",
    "file": ".planning/phases/04-ci-github-action/SUMMARY.md",
    "line": null,
    "description": "criterion-3 own-repo CI smoke test unreachable from this repo (gem unpublished — RubyGems 404; action repo unpublished); recorded as accepted external deviation + 6-item release checklist",
    "status": "waived",
    "reason": "v0.3.0 carryover: RubyGems publication deferred by user decision 2026-08-27 (recorded in REQUIREMENTS.md Out of Scope). The own-repo smoke CI this gates cannot run until the gem exists on RubyGems.",
    "recorded_at": "2026-08-24T04:29:10.965Z",
    "resolved_at": "2026-08-27T09:17:34.113Z"
  },
  {
    "id": 3,
    "kind": "unrun-verify",
    "phase": "06",
    "file": ".planning/phases/06-graph-authority-lockfile-reconciliation/06-M1-MEASUREMENT.md",
    "line": null,
    "description": "M1 step 4 live Release xcodebuild not run: A3 failed (fb8e773 removed exyte state from feature-branch tip) and the only probative commit is reachable solely via detached checkout in a dirty reference tree whose build would overwrite the pre-fix artifacts; version attribution established from realized checkout HEADs instead",
    "status": "waived",
    "reason": "M1 live Release xcodebuild unreachable: research assumption A3 failed (fb8e773 removed the exyte state from the feature-branch tip). Attribution completed from committed revisions via git show instead of a substituted repro. Not retroactively fixable.",
    "recorded_at": "2026-08-27T06:39:49.087Z",
    "resolved_at": "2026-08-27T09:17:34.205Z"
  },
  {
    "id": 4,
    "kind": "deviation",
    "phase": "06",
    "file": "spec/package_resolved_spec.rb",
    "line": null,
    "description": "Task 3's two parity examples passed on write (no RED phase) because they assert locator properties Tasks 1-2 had already delivered; commit order preserved but they are guard rails, not RED evidence",
    "status": "waived",
    "reason": "Historical process gap: two parity examples in 06-02 passed on write (no RED phase) because they assert locator properties Tasks 1-2 had already delivered. Cannot be made RED after the fact; the examples are valid regression guards and pass. Self-reported by the executor rather than concealed.",
    "recorded_at": "2026-08-27T07:55:37.028Z",
    "resolved_at": "2026-08-27T09:17:34.307Z"
  },
  {
    "id": 5,
    "kind": "unrun-verify",
    "phase": "6",
    "file": "lib/spm_cache/core/diff_detector.rb",
    "line": 140,
    "description": "live_packages JSON.parses the host Package.resolved unguarded, so a truncated file aborts detect_diff before the reconciler's D-04 warn-and-degrade path is reachable",
    "status": "waived",
    "reason": "Truncated Package.resolved aborts detect_diff (diff_detector.rb:140 unguarded parse) before D-04's warn-and-degrade is reachable. NOTE: this violates locked decision D-04's 'never crash', so it is a decision-fidelity gap, not merely missing hardening. Waived per explicit user authorization 2026-08-27 under that stronger framing. Proper fix requires deciding DiffDetector's posture for ALL detect callers and keeping the diff report honest about unreadable-vs-removed; 06-05-PLAN.md guard ordering was specified so closing it later needs no rework.",
    "recorded_at": "2026-08-27T08:11:34.058Z",
    "resolved_at": "2026-08-27T09:17:34.399Z"
  },
  {
    "id": 6,
    "kind": "deviation",
    "phase": "06",
    "file": "lib/spm_cache/core/diagnostics.rb",
    "line": null,
    "description": "lock_graph_fidelity guards cfg.respond_to?(:lockfile_path) because a verifying instance_double raises MockExpectationError (not a StandardError) and escapes run_check's capture",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-27T08:24:12.828Z",
    "resolved_at": null
  },
  {
    "id": 7,
    "kind": "deviation",
    "phase": "10",
    "file": "lib/spm_cache/spm/xcframework/slice.rb",
    "line": 31,
    "description": "FrameworkSlice unwired dead code: copy_resource_bundles unreachable (private resource_paths defeats respond_to? guard, bare-Sh NameError, template binding mismatch) — TEST-03 class 6/8 drives the real copy via send; logged in deferred-items.md",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-29T16:38:32.821Z",
    "resolved_at": null
  },
  {
    "id": 8,
    "kind": "deviation",
    "phase": "11",
    "file": "spec/main_version_spec.rb",
    "line": null,
    "description": "RED manifests as SystemExit run-termination (exit 1, no version output) instead of '2 reported failures' — stubbing forbidden by plan; GREEN unaffected",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-30T01:10:46.904Z",
    "resolved_at": null
  }
]
````
