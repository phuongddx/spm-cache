---
phase: 8
slug: drift-read-back-fidelity-status-provenance
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-08-29
---

# Phase 8 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | RSpec (Ruby) |
| **Config file** | `spec/spec_helper.rb` |
| **Quick run command** | `bundle exec rspec spec/build_pipeline_spec.rb spec/build_pipeline_seeding_spec.rb spec/installer_build_spec.rb` (touched-file scope) |
| **Full suite command** | `bundle exec rspec` |
| **Estimated runtime** | ~40s full suite (342 examples as of Phase 7) |

---

## Sampling Rate

- **After every task commit:** Run the quick run command above
- **After every plan wave:** Run `bundle exec rspec` (full suite)
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** ~45 seconds

---

## Per-Task Verification Map

*Filled in by the planner as tasks are defined — no plans exist yet for this phase.*

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements — RSpec + `bundle exec rspec` already exercises the exact modules this phase extends (`BuildPipeline`, `Installer::Build`, `Cache::Cachemap`). No new test framework or fixtures needed.

---

## Manual-Only Verifications

All phase behaviors have automated verification. Drift read-back's core mechanism (xcodebuild silently discarding an out-of-range pin and rewriting `Package.resolved` in place) is already empirically verified on this machine (Xcode 26.3 / Swift 6.2.4) per `08-RESEARCH.md`, not something Phase 8's own specs need to re-prove against a live Xcode invocation — they exercise the Ruby-side read-back/comparison logic with fixture `Package.resolved` files.

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 45s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
