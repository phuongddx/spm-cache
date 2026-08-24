# Milestones

## v0.3.0 Mixed Cycle (Shipped: 2026-08-24)

**Phases completed:** 5 phases, 10 plans (6 GSD-tracked), 15 tasks · 86 commits · 87 files (+11,304/−486) · 2026-07-11 → 2026-08-24
**Closeout:** verified (all 5 phases verification passed; 12/12 requirements; audit tech_debt — see milestones/v0.3.0-MILESTONE-AUDIT.md)

**Key accomplishments:**

- **Test CI** (REL-01): first-ever test pipeline — ruby-tests builds the Swift proxy before RSpec on every leg so the full suite (258 examples at close) executes with 0 pending; dead swift-tests build removed; delivered Ruby 3.1–3.3 matrix documented with gemspec justification.
- **Diagnostics** (REL-02, REL-03): `spm-cache doctor` — 7-check data-driven registry, marker report with fix hints, `--json` for CI gating (exit 1 on failures), hermetic spec seam; Swift companion `--version` fixed from dead probe (exit 64 → 0.3.0, exit 0) making Ruby↔Swift drift visible.
- **Bootstrap** (ONBD-01..03): `spm-cache init` — 7-flag wizard, TTY-conditional prompts, idempotent yml diff-merge, `.gitignore` append-once; **canonical lockfile seeding fixed** (pins byte-copy crashed the next `use` with TypeError — now the canonical consumer shape, init→use fast path proven).
- **GitHub Action** (ONBD-04): 6-input thin composite under `action/` (setup-ruby → gem install → init → remote pull/push); `--default-config` flag wiring fixed TDD-clean (config:release was silently ignored); 12-example structural spec cross-referencing the gem CLI; publication to `phuongddx/spm-cache-action` is the recorded release checklist.
- **Auto-Sync Watcher** (AUTO-01..05): `spm-cache watch` — stdlib mtime+size polling (user-accepted 2026-08-24, supersedes the FSEvents/Fiddle design), 2s debounce burst-collapse, `--once`, continue-on-error loop; **SIGTERM contract fixed** (was exit 143 — now traps, masks signals during flush, exits 0) and **self-trigger guard** (installer pbxproj rewrite confirmed as a real re-generation loop).

---
