---
phase: 04
slug: ci-github-action
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
# audit-milestone §5.5 distinguishes NOT-VALIDATED (draft) from PARTIAL (validated + nyquist_compliant: false) (#2117)
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-08-24
---

# Phase 04 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | RSpec 3.x (Ruby) |
| **Config file** | `.rspec` / `spec/spec_helper.rb` |
| **Quick run command** | `bundle exec rspec spec/action_spec.rb` |
| **Full suite command** | `make proxy.build && bundle exec rspec` |
| **Estimated runtime** | ~60 seconds |

---

## Sampling Rate

- **After every task commit:** Run `bundle exec rspec spec/action_spec.rb`
- **After every plan wave:** Run `make proxy.build && bundle exec rspec`
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 04-01-01 | 01 | 1 | ONBD-04 | — | N/A | unit | `bundle exec rspec spec/action_spec.rb` | ❌ W0 | ⬜ pending |
| 04-01-02 | 01 | 1 | ONBD-04 | — | N/A | doc/CLI | CLI cross-reference assertions | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `spec/action_spec.rb` — Psych YAML parse + composite-schema assertions + CLI source cross-reference (init flag names, remote subcommands) + README-vs-action.yml input equality. Skeleton drafted in RESEARCH.md against the POST-F1 state (fails until the flag fix lands).

*Existing RSpec infrastructure otherwise covers all phase needs.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Published Action end-to-end in a consumer workflow | ONBD-04 | Requires the separate `phuongddx/spm-cache-action` repo + gem on RubyGems (external; recorded as deviation) | After publication: 5-line consumer workflow calling the Action with `command: pull` then `push` |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
