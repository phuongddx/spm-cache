---
phase: "12"
slug: "run-log-capture-foundation"
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
# audit-milestone §5.5 distinguishes NOT-VALIDATED (draft) from PARTIAL (validated + nyquist_compliant: false) (#2117)
status: draft
nyquist_compliant: false
wave_0_complete: false
created: "2026-08-31"
---

# Phase 12 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | RSpec 3.12 (existing suite, 441 examples, hermetic/no-network) |
| **Config file** | `spec/spec_helper.rb` (+ default-deny `Core::Sh` guard) |
| **Quick run command** | `bundle exec rspec spec/run_log_spec.rb` (Wave 0 names the real file) |
| **Full suite command** | `bundle exec rspec` |
| **Estimated runtime** | ~30–60 s full suite (fidelity specs combined: 0.89 s) |

---

## Sampling Rate

- **After every task commit:** Run quick command (target specs)
- **After every plan wave:** Run `bundle exec rspec`
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 60 s

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 12-01-TBD | 01 | TBD | LOGS-01 | — | N/A | unit | `MISSING — Wave 0 …` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

*(Map completed by planner → executor; Wave 0 fills MISSING references.)*

---

## Wave 0 Requirements

- [ ] Run-log spec file(s) named by the planner (stubs for LOGS-01 SC1–SC4)
- [ ] Tee/sink seam fixtures (StringIO + tmpdir run dir) — no new infrastructure needed beyond this

*Existing RSpec infrastructure covers the framework; only the new spec files are Wave 0 items.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Terminal output byte-identical with capture on (SC3) | LOGS-01 | Visual byte-parity across real TTY is not automatable hermetically; automated specs assert via StringIO capture | Run `spm-cache use` with and without `--no-run-log` on the reference project; diff captured terminal transcripts |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60 s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
