---
phase: 02
slug: diagnostics-command
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
# audit-milestone §5.5 distinguishes NOT-VALIDATED (draft) from PARTIAL (validated + nyquist_compliant: false) (#2117)
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-08-24
---

# Phase 02 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | RSpec 3.x (Ruby) |
| **Config file** | `.rspec` / `spec/spec_helper.rb` |
| **Quick run command** | `bundle exec rspec spec/doctor_spec.rb` |
| **Full suite command** | `make proxy.build && bundle exec rspec` |
| **Estimated runtime** | ~60 seconds |

---

## Sampling Rate

- **After every task commit:** Run `bundle exec rspec spec/doctor_spec.rb`
- **After every plan wave:** Run `make proxy.build && bundle exec rspec`
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 02-01-01 | 01 | 1 | REL-02 | — | N/A | integration | `bundle exec rspec spec/doctor_spec.rb` | ✅ | ⬜ pending |
| 02-01-02 | 01 | 1 | REL-03 | — | N/A | integration | `bundle exec rspec spec/doctor_spec.rb` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

*Existing infrastructure covers all phase requirements (RSpec suite + doctor_spec.rb already present; no new framework needed).*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Live color-coded/marker report rendering on a real terminal | REL-02 | Verdicts depend on the local Xcode/ Swift toolchain; CI legs differ | Run `bundle exec bin/spm-cache doctor` — verify 7 checks render with ✓/!/✗ markers, fix hints, and a Summary line |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
