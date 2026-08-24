---
schema_version: 1
open_count: 1
waived_count: 1
fixed_count: 0
total_count: 2
last_updated: 2026-08-24T04:29:10.965Z
---

# Broken Windows Ledger

> Cross-phase defect register. With `workflow.windows_enforce` enabled, `/gsd-ship` blocks while `open_count > 0`.
> Waive with `gsd-tools windows waive <id> "<reason>"` (reason required).
> Mark fixed with `gsd-tools windows fixed <id>`.

| id | phase | kind | file | line | description | status | reason | recorded_at | resolved_at |
|----|-------|------|------|------|-------------|--------|--------|-------------|-------------|
| 1 | 03 | deviation | .planning/ROADMAP.md | 54 | 03-01 acceptance gate 'amended 2026-08-24 == 6' unsatisfiable: Phase-2 pre-existing count was 3, not 4; Phase-3 added 2 → actual total 5 (substantive intent met; documented in 03-01-SUMMARY Deviation 2) | waived | Plan-gate arithmetic error (Phase-2 pre-count was 3, not 4); substantive amendment intent verified met — see 03-REVIEW.md and 03-01-SUMMARY Deviation 2 | 2026-08-24T03:00:58.233Z | 2026-08-24T03:21:42.678Z |
| 2 | 04 | deviation | .planning/phases/04-ci-github-action/SUMMARY.md |  | criterion-3 own-repo CI smoke test unreachable from this repo (gem unpublished — RubyGems 404; action repo unpublished); recorded as accepted external deviation + 6-item release checklist | open |  | 2026-08-24T04:29:10.965Z |  |

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
  }
]
````
