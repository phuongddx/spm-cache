---
phase: 8
slug: drift-read-back-fidelity-status-provenance
status: planned
nyquist_compliant: true
wave_0_complete: true
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

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 08-01 Task 1 | 08-01 | 1 | FID-03, FID-04, CACHE-01, DIAG-02 | T-08-01, T-08-02 | Drift read-back never hard-fails; status classified on success path only; sidecar carries exactly 5 keys | unit (tracer, starts red) | `bundle exec rspec spec/build_pipeline_provenance_spec.rb` | new file | planned |
| 08-01 Task 2 | 08-01 | 1 | FID-03, FID-04, CACHE-01 | T-08-01 | Not-graph-pinned/Class E paths never write a stale or false sidecar | unit (tdd) | `bundle exec rspec spec/build_pipeline_provenance_spec.rb` | extend | planned |
| 08-01 Task 3 | 08-01 | 1 | FID-03, FID-04, CACHE-01 | T-08-01, T-08-02 | Diff scoped to intersection only; nil-tolerant defaults; ignore_build_errors? cannot mask | unit (tdd) | `bundle exec rspec spec/build_pipeline_provenance_spec.rb && bundle exec rspec` | extend | planned |
| 08-02 Task 1 | 08-02 | 2 | DIAG-02 | T-08-01, T-08-02 | Sidecar is display-only; malformed input never crashes | unit (tracer, starts red) | `bundle exec rspec spec/command_cache_list_spec.rb` | new file | planned |
| 08-02 Task 2 | 08-02 | 2 | DIAG-02 | T-08-01 | Missing/malformed sidecar falls back to not-graph-pinned, never raises | unit (tdd) | `bundle exec rspec spec/command_cache_list_spec.rb && bundle exec rspec` | extend | planned |

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements — RSpec + `bundle exec rspec` already exercises the exact modules this phase extends (`BuildPipeline`, `Installer::Build`, `Cache::Cachemap`). No new test framework or fixtures needed.

---

## Manual-Only Verifications

All phase behaviors have automated verification. Drift read-back's core mechanism (xcodebuild silently discarding an out-of-range pin and rewriting `Package.resolved` in place) is already empirically verified on this machine (Xcode 26.3 / Swift 6.2.4) per `08-RESEARCH.md`, not something Phase 8's own specs need to re-prove against a live Xcode invocation — they exercise the Ruby-side read-back/comparison logic with fixture `Package.resolved` files.

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references (both new spec files are created by their plan's Task 1, `type="tracer"`, starting red)
- [x] No watch-mode flags
- [x] Feedback latency < 45s (full suite ~40s)
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** planned — 08-01-PLAN.md, 08-02-PLAN.md
