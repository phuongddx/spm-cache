---
phase: 6
slug: graph-authority-lockfile-reconciliation
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
# audit-milestone §5.5 distinguishes NOT-VALIDATED (draft) from PARTIAL (validated + nyquist_compliant: false) (#2117)
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-08-27
---

# Phase 6 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | RSpec 3.13 (rspec-core 3.13.6) |
| **Config file** | none — no `.rspec`; `spec/spec_helper.rb` is itself a spec that only `require "spm_cache/main"` |
| **Quick run command** | `bundle exec rspec spec/package_resolved_spec.rb spec/lockfile_reconciliation_spec.rb spec/doctor_lock_fidelity_spec.rb` |
| **Full suite command** | `make proxy.build && bundle exec rspec` |
| **Estimated runtime** | ~10s quick (Ruby-only, no proxy build) · full suite baseline 258 examples |

---

## Sampling Rate

- **After every task commit:** Run `bundle exec rspec spec/<the touched spec(s)>` — Ruby-only specs need no `make proxy.build`
- **After every plan wave:** Run `bundle exec rspec` (full Ruby suite)
- **Before `/gsd-verify-work`:** `make proxy.build && bundle exec rspec` fully green (baseline 258 examples)
- **Max feedback latency:** ~10 seconds for the quick command

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| TBD | 01 | 0 | FID-06 | — | Locator cannot be redirected to an attacker-writable nested path | unit | `bundle exec rspec spec/package_resolved_spec.rb -e "prefers the canonical"` | ❌ W0 | ⬜ pending |
| TBD | 01 | 0 | FID-06 | — | Locator never returns a path under the `spm-cache` sandbox | unit | `bundle exec rspec spec/package_resolved_spec.rb -e "never returns a sandbox Package.resolved"` | ❌ W0 | ⬜ pending |
| TBD | 01 | 0 | FID-06 | — | N/A | regression | `bundle exec rspec spec/diff_detector_spec.rb spec/init_spec.rb spec/watch_spec.rb spec/watch_loop_spec.rb` | ✅ exists | ⬜ pending |
| TBD | 01 | 1 | FID-01 | — | N/A | unit | `bundle exec rspec spec/lockfile_reconciliation_spec.rb -e "updates version and revision"` | ❌ W0 | ⬜ pending |
| TBD | 01 | 1 | FID-01 | — | N/A | unit | `… -e "preserves products"` | ❌ W0 | ⬜ pending |
| TBD | 01 | 1 | FID-01 | — | N/A | unit | `… -e "drops a package absent from the host graph"` | ❌ W0 | ⬜ pending |
| TBD | 01 | 1 | FID-01 | — | N/A | unit | `… -e "adds a new package without a products key"` | ❌ W0 | ⬜ pending |
| TBD | 01 | 1 | FID-01 | — | Local/`path_from_root` package must NOT be dropped (top regression risk) | unit | `… -e "keeps a local package absent from Package.resolved"` | ❌ W0 | ⬜ pending |
| TBD | 01 | 1 | FID-01 | — | N/A | unit | `… -e "leaves dependencies platforms and version stamp untouched"` | ❌ W0 | ⬜ pending |
| TBD | 01 | 1 | FID-01 | — | Unreadable input degrades safely — never erases the lock | unit | `… -e "leaves the lock untouched when Package.resolved is unreadable"` | ❌ W0 | ⬜ pending |
| TBD | 01 | 1 | FID-01 | — | N/A | integration | `bundle exec rspec spec/installer_use_fast_path_spec.rb` (extend) | ⚠️ extend | ⬜ pending |
| TBD | 01 | 1 | FID-01 | — | N/A | integration | `… -e "leaves DiffDetector reporting an empty diff"` | ❌ W0 | ⬜ pending |
| TBD | 01 | 2 | DIAG-01 | — | N/A | unit | `bundle exec rspec spec/doctor_lock_fidelity_spec.rb -e "warns on zero overlap"` | ❌ W0 | ⬜ pending |
| TBD | 01 | 2 | DIAG-01 | — | N/A | unit | `… -e "warns on a version drift"` | ❌ W0 | ⬜ pending |
| TBD | 01 | 2 | DIAG-01 | — | N/A | unit | `… -e "compares revision before version"` | ❌ W0 | ⬜ pending |
| TBD | 01 | 2 | DIAG-01 | — | N/A | unit | `… -e "reports ok when no lockfile exists"` | ❌ W0 | ⬜ pending |
| TBD | 01 | 2 | DIAG-01 | — | Static check must not execute anything | unit | `… -e "does not shell out"` (`expect(Core::Sh).not_to receive(:capture_output)`) | ❌ W0 | ⬜ pending |
| TBD | 01 | 2 | DIAG-01 | — | `:warn` must leave `doctor` exit 0 (`doctor.rb:42` exits 1 only on `fail?`) | integration | `bundle exec rspec spec/doctor_spec.rb` (extend) | ⚠️ extend | ⬜ pending |
| TBD | 01 | 2 | DIAG-01 | — | N/A | regression | `bundle exec rspec spec/doctor_spec.rb` (3 count/order assertions must change) | ✅ exists | ⬜ pending |

*Task IDs are assigned by the planner; rows are requirement-anchored so the planner can bind them.*

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `spec/package_resolved_spec.rb` — locator preference + sandbox exclusion + nil-tolerance parity for all five call-site shapes
- [ ] `spec/lockfile_reconciliation_spec.rb` — FID-01 semantics (drop / add / preserve / untouched-keys / unreadable)
- [ ] `spec/doctor_lock_fidelity_spec.rb` — DIAG-01 verdicts, precedence, no-shell-out
- [ ] Update `spec/doctor_spec.rb:174-179` (exact check-name array), `:199` (7→8), `:248` (8→9)
- [ ] Extend `spec/installer_use_fast_path_spec.rb` with success criterion 1 (empty diff after a non-fast-path run)

No framework install needed. No shared `conftest`-equivalent needed — project convention is self-contained specs.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| M1 root-cause attribution on the reference project | FID-01 (success criterion 4) | Requires a real 59–70 package Xcode project and a release-config build; cannot be hermetic | Run read-only steps 0–3 first on `/Users/ddphuong/Projects/next-labs/stress-ai/ios-stress-app/StressMonitor` (`main` — confirms the stale-locator hypothesis), then reproduce on branch `feature/spm-cache-integration` and record which mechanism dominates |
| Reference project still builds after reconciliation | FID-01 (success criterion 2) | Needs Xcode toolchain against a real project | After reconciliation, run `spm-cache use` then build; confirm no regression vs the pre-run state |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
