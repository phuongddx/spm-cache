---
phase: 10
slug: fidelity-regression-coverage
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
# audit-milestone §5.5 distinguishes NOT-VALIDATED (draft) from PARTIAL (validated + nyquist_compliant: false) (#2117)
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-08-29
---

# Phase 10 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | RSpec 3.12 (Swift companion covered separately by `swift test`, out of this phase's scope) |
| **Config file** | none — existing `spec/spec_helper.rb` + default RSpec configuration |
| **Quick run command** | `bundle exec rspec spec/fidelity_drift_regression_spec.rb spec/fidelity_bucket_partition_spec.rb spec/fidelity_edge_matrix_spec.rb` |
| **Full suite command** | `bundle exec rspec` |
| **Estimated runtime** | ~47 seconds (full suite, measured 2026-08-29: 387 examples, 0 failures) |

---

## Sampling Rate

- **After every task commit:** Run the quick run command for the spec(s) touched by the task
- **After every plan wave:** Run `bundle exec rspec`
- **Before `$gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| (filled by validate-phase once PLAN.md files exist) | | | | | | | | | |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements — the RSpec suite, hermetic Sh/Desc/Buildable
seams, and `spec/fixtures/` JSON conventions already exist; no new framework or conftest is needed.

---

## Manual-Only Verifications

All phase behaviors have automated verification (hermetic by design — SC4).

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
