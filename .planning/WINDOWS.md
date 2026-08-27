---
schema_version: 1
open_count: 5
waived_count: 1
fixed_count: 0
total_count: 6
last_updated: 2026-08-27T08:24:12.828Z
---

# Broken Windows Ledger

> Cross-phase defect register. With `workflow.windows_enforce` enabled, `/gsd-ship` blocks while `open_count > 0`.
> Waive with `gsd-tools windows waive <id> "<reason>"` (reason required).
> Mark fixed with `gsd-tools windows fixed <id>`.

| id | phase | kind | file | line | description | status | reason | recorded_at | resolved_at |
|----|-------|------|------|------|-------------|--------|--------|-------------|-------------|
| 1 | 03 | deviation | .planning/ROADMAP.md | 54 | 03-01 acceptance gate 'amended 2026-08-24 == 6' unsatisfiable: Phase-2 pre-existing count was 3, not 4; Phase-3 added 2 → actual total 5 (substantive intent met; documented in 03-01-SUMMARY Deviation 2) | waived | Plan-gate arithmetic error (Phase-2 pre-count was 3, not 4); substantive amendment intent verified met — see 03-REVIEW.md and 03-01-SUMMARY Deviation 2 | 2026-08-24T03:00:58.233Z | 2026-08-24T03:21:42.678Z |
| 2 | 04 | deviation | .planning/phases/04-ci-github-action/SUMMARY.md |  | criterion-3 own-repo CI smoke test unreachable from this repo (gem unpublished — RubyGems 404; action repo unpublished); recorded as accepted external deviation + 6-item release checklist | open |  | 2026-08-24T04:29:10.965Z |  |
| 3 | 06 | unrun-verify | .planning/phases/06-graph-authority-lockfile-reconciliation/06-M1-MEASUREMENT.md |  | M1 step 4 live Release xcodebuild not run: A3 failed (fb8e773 removed exyte state from feature-branch tip) and the only probative commit is reachable solely via detached checkout in a dirty reference tree whose build would overwrite the pre-fix artifacts; version attribution established from realized checkout HEADs instead | open |  | 2026-08-27T06:39:49.087Z |  |
| 4 | 06 | deviation | spec/package_resolved_spec.rb |  | Task 3's two parity examples passed on write (no RED phase) because they assert locator properties Tasks 1-2 had already delivered; commit order preserved but they are guard rails, not RED evidence | open |  | 2026-08-27T07:55:37.028Z |  |
| 5 | 6 | unrun-verify | lib/spm_cache/core/diff_detector.rb | 140 | live_packages JSON.parses the host Package.resolved unguarded, so a truncated file aborts detect_diff before the reconciler's D-04 warn-and-degrade path is reachable | open |  | 2026-08-27T08:11:34.058Z |  |
| 6 | 06 | deviation | lib/spm_cache/core/diagnostics.rb |  | lock_graph_fidelity guards cfg.respond_to?(:lockfile_path) because a verifying instance_double raises MockExpectationError (not a StandardError) and escapes run_check's capture | open |  | 2026-08-27T08:24:12.828Z |  |

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
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-24T04:29:10.965Z",
    "resolved_at": null
  },
  {
    "id": 3,
    "kind": "unrun-verify",
    "phase": "06",
    "file": ".planning/phases/06-graph-authority-lockfile-reconciliation/06-M1-MEASUREMENT.md",
    "line": null,
    "description": "M1 step 4 live Release xcodebuild not run: A3 failed (fb8e773 removed exyte state from feature-branch tip) and the only probative commit is reachable solely via detached checkout in a dirty reference tree whose build would overwrite the pre-fix artifacts; version attribution established from realized checkout HEADs instead",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-27T06:39:49.087Z",
    "resolved_at": null
  },
  {
    "id": 4,
    "kind": "deviation",
    "phase": "06",
    "file": "spec/package_resolved_spec.rb",
    "line": null,
    "description": "Task 3's two parity examples passed on write (no RED phase) because they assert locator properties Tasks 1-2 had already delivered; commit order preserved but they are guard rails, not RED evidence",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-27T07:55:37.028Z",
    "resolved_at": null
  },
  {
    "id": 5,
    "kind": "unrun-verify",
    "phase": "6",
    "file": "lib/spm_cache/core/diff_detector.rb",
    "line": 140,
    "description": "live_packages JSON.parses the host Package.resolved unguarded, so a truncated file aborts detect_diff before the reconciler's D-04 warn-and-degrade path is reachable",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-08-27T08:11:34.058Z",
    "resolved_at": null
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
  }
]
````
