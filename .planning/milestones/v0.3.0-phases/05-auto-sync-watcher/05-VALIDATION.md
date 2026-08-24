---
phase: 05
slug: auto-sync-watcher
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
# audit-milestone §5.5 distinguishes NOT-VALIDATED (draft) from PARTIAL (validated + nyquist_compliant: false) (#2117)
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-08-24
---

# Phase 05 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | RSpec 3.x (Ruby) |
| **Config file** | `.rspec` / `spec/spec_helper.rb` |
| **Quick run command** | `bundle exec rspec spec/watch_spec.rb` |
| **Full suite command** | `make proxy.build && bundle exec rspec` |
| **Estimated runtime** | ~60 seconds |

---

## Sampling Rate

- **After every task commit:** Run `bundle exec rspec spec/watch_spec.rb`
- **After every plan wave:** Run `make proxy.build && bundle exec rspec`
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 05-01-01 | 01 | 1 | AUTO-04 | T-05-02 | SIGINT/SIGTERM flush + exit 0; fatal initial failure exits 1 | subprocess | `bundle exec rspec spec/watch_signals_spec.rb` | ✅ | ✅ green |
| 05-01-02 | 01 | 1 | AUTO-01, AUTO-02, AUTO-04 | T-05-01 | Self-trigger guard; burst collapse uses final state; deletion logged-once, no busy-loop | subprocess | `bundle exec rspec spec/watch_loop_spec.rb` | ✅ | ✅ green |
| 05-01-03 | 01 | 1 | AUTO-01–AUTO-05 | T-05-SC | Criterion proofs (static + specs), dated amendments, 18-row doc-drift closure | static/docs | grep gates + `make proxy.build && bundle exec rspec` | ✅ | ✅ green |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

*Existing infrastructure covers all phase requirements (watch_spec.rb + subprocess/child-process pattern for signal tests; no new framework needed).*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Long-running watch loop against a live Xcode project | AUTO-01 | Needs a real project + sustained observation | Run `bundle exec bin/spm-cache watch` in a fixture project; touch Package.resolved; observe one regeneration with timestamp log; Ctrl-C exits 0 after flushing |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 60s
- [x] `nyquist_compliant: true` set in frontmatter
