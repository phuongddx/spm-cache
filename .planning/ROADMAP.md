# Roadmap: spm-cache

## Milestones

- ✅ **v0.3.0 Mixed Cycle** — Phases 1–5 (shipped 2026-08-24)
- ✅ **v0.4.0 Build Fidelity & Release Automation** — Phases 6–11 (shipped 2026-08-31)

## Overview

v0.4.0 closed the only known correctness failure (cached builds compiled against transitive
dependency versions the host never resolved) and repaired the Homebrew release path end-to-end.
All 21 requirements satisfied; 6/6 phases verified; publish path live-proven including a real
tap push. The v0.4.0 git release cut (VERSION bump → tag → asset upload → green verify) is the
remaining operator step.

No next milestone defined yet — run `/gsd-new-milestone` when ready (v0.5 candidates on record:
`~/.spm-cache` partitioning + content-addressed keys, RubyGems publication).

<details>
<summary>✅ v0.3.0 Mixed Cycle (Phases 1–5) — SHIPPED 2026-08-24</summary>

- [x] Phase 1: Test CI Foundation (2/2 plans) — completed 2026-08-24
- [x] Phase 2: Diagnostics Command (2 plans) — completed 2026-08-24 (verification refreshed same day)
- [x] Phase 3: Project Bootstrap (2 plans) — completed 2026-08-24
- [x] Phase 4: CI GitHub Action (2 plans) — completed 2026-08-24
- [x] Phase 5: Auto-Sync Watcher (2 plans) — completed 2026-08-24

Full phase detail: `milestones/v0.3.0-ROADMAP.md` · Audit: `milestones/v0.3.0-MILESTONE-AUDIT.md`

</details>

<details>
<summary>✅ v0.4.0 Build Fidelity & Release Automation (Phases 6–11) — SHIPPED 2026-08-31</summary>

- [x] Phase 6: Graph Authority — Lockfile Reconciliation (5 plans) — completed 2026-08-27 (verified via documented override + gap closure)
- [x] Phase 7: Host-Faithful Checkout Seeding (2 plans) — completed 2026-08-29
- [x] Phase 8: Drift Read-Back, Fidelity Status & Provenance (2 plans) — completed 2026-08-29
- [x] Phase 9: Cache Identity & Invalidation (3 plans) — completed 2026-08-29
- [x] Phase 10: Fidelity Regression Coverage (3 plans) — completed 2026-08-30
- [x] Phase 11: Homebrew Release Automation (3 plans) — completed 2026-08-31

Full phase detail: `milestones/v0.4.0-ROADMAP.md` · Audit: `v0.4.0-MILESTONE-AUDIT.md`

</details>
