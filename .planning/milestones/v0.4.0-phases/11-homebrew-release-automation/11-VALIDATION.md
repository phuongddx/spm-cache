---
phase: 11
slug: homebrew-release-automation
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
# audit-milestone §5.5 distinguishes NOT-VALIDATED (draft) from PARTIAL (validated + nyquist_compliant: false) (#2117)
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-08-30
---

# Phase 11 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | RSpec 3.12 (structural YAML specs per `spec/action_spec.rb` precedent + one behavior spec for the `--version` intercept) |
| **Config file** | none — existing `spec/spec_helper.rb` + default RSpec configuration |
| **Quick run command** | `bundle exec rspec spec/update_tap_workflow_spec.rb spec/main_version_spec.rb` |
| **Full suite command** | `bundle exec rspec` |
| **Estimated runtime** | ~45 seconds (full suite, measured 2026-08-29 baseline 416 examples) |

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

Existing infrastructure covers all phase requirements — structural spec precedent (`spec/action_spec.rb`), the RSpec suite, and the workflow YAML all exist; no new framework is needed.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Live publish path with real GitHub App token | REL-04, SC1 | Requires operator-created App + repo secrets (one-time human step outside the repo) and a real release/dispatch event — not reproducible hermetically | After the operator gate: `workflow_dispatch` with `tag: v0.3.0` — exercises the full path, lands on the idempotent "already up to date" branch, then the brew verify job runs |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
