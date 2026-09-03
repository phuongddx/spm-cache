---
phase: "12"
slug: "run-log-capture-foundation"
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
# audit-milestone §5.5 distinguishes NOT-VALIDATED (draft) from PARTIAL (validated + nyquist_compliant: false) (#2117)
status: validated
nyquist_compliant: true
wave_0_complete: true
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
| 12-01-T1 | 01 | 1 | LOGS-01 (SC1/SC3, D-01/02/03/08) | T-12-01, T-12-03, T-12-05 | JSON.generate escaping; Tempfile+rename header; degrade-not-raise | unit (e2e via Main.run harness) | `bundle exec rspec spec/main_run_log_spec.rb spec/main_version_spec.rb` | ❌ Wave 0 (RED step creates it) | ✅ green |
| 12-01-T2 | 01 | 1 | LOGS-01 (edge empty/adjacency) | T-12-01 | verbatim/ANSI round-trip; mutex integrity; degradation | unit | `bundle exec rspec spec/run_log_spec.rb spec/main_run_log_spec.rb` | ❌ Wave 0 (RED step creates it) | ✅ green |
| 12-02-T1 | 02 | 2 | LOGS-01 (SC2, D-05) | T-12-01, T-12-04 | stream-tagged sink; tail bounds only the raise, never the file | unit (real echo through real Sh) | `bundle exec rspec spec/sh_run_log_sink_spec.rb spec/core_spec.rb` | ❌ Wave 0 (RED step creates it) | ✅ green |
| 12-02-T2 | 02 | 2 | LOGS-01 (SC2, Pitfall 5) | T-12-01 | sh events carry cmd+status only | unit | `bundle exec rspec spec/sh_run_log_sink_spec.rb` | ✅ (created by 12-02-T1) | ✅ green |
| 12-03-T1 | 03 | 2 | LOGS-01 (SC4, D-06) | T-12-04 | Integer coercion (user-authored yml) | unit | `bundle exec rspec spec/config_spec.rb` | ✅ exists (extend) | ✅ green |
| 12-03-T2 | 03 | 2 | LOGS-01 (SC4, D-06/D-07, edge ordering) | T-12-04 (disposes high) | live-pid immunity; oldest-first; never current | unit | `bundle exec rspec spec/run_log_spec.rb` | ✅ (created by 12-01-T2) | ✅ green |
| 12-03-T3 | 03 | 2 | LOGS-01 (D-02) | T-12-05 | runs dir kept out of VCS | unit | `bundle exec rspec spec/init_spec.rb` | ✅ exists (extend) | ✅ green |
| 12-04-T1 | 04 | 3 | LOGS-01 (SC2, D-04/D-05) | T-12-01, T-12-04 | events distinguishable by `event` key; nil-disables | unit | `bundle exec rspec spec/build_pipeline_spec.rb spec/build_pipeline_seeding_spec.rb spec/build_pipeline_provenance_spec.rb` | ✅ exists (extend) | ✅ green |
| 12-04-T2 | 04 | 3 | LOGS-01 (D-04, edge empty zero-pins) | T-12-01 | nil-guarded markers never fail a build | unit | `bundle exec rspec spec/installer_use_fast_path_spec.rb spec/installer_build_spec.rb spec/installer_spec.rb` | ✅ exists (extend) | ✅ green |
| 12-05-T1 | 05 | 4 | LOGS-01 (SC1/SC3, D-09) | T-12-04 (cycle prune), T-12-01 | cycle files same writer guarantees; watcher untouched | unit | `bundle exec rspec spec/watch_spec.rb spec/watch_loop_spec.rb spec/watch_signals_spec.rb` | ✅ exists (extend) | ✅ green |
| 12-05-T2 | 05 | 4 | LOGS-01 (D-08 proof, A6/A5) | T-12-05 | argv-only capture (no env/secrets) | unit | `bundle exec rspec spec/run_log_spec.rb spec/main_run_log_spec.rb` | ✅ (created earlier) | ✅ green |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

*(Map filled by planner 2026-08-31. Wave 0 = the RED step inside each TDD task creates its spec file; no external scaffolding needed beyond the tasks themselves.)*

---

## Wave 0 Requirements

- [x] Run-log spec file(s) named by the planner: spec/main_run_log_spec.rb + spec/run_log_spec.rb created RED-first inside 12-01-T1/T2; spec/sh_run_log_sink_spec.rb inside 12-02-T1 — no separate Wave-0 scaffold task needed (TDD-mode tasks embed the RED step)
- [x] Tee/sink seam fixtures (StringIO + tmpdir run dir) — covered by the spec conventions cited in 12-PATTERNS.md (doctor_spec.rb $stdout swap; fidelity_bucket_partition_spec.rb tmpdir + default-deny guard; core_spec.rb real-echo precedent)

*Existing RSpec infrastructure covers the framework; only the new spec files are Wave 0 items, and each is authored by its own task's RED commit.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| ✅ Terminal output byte-identical with capture on (SC3) (2026-09-01, executed — recorded in [12-UAT.md](12-UAT.md) test 1) | LOGS-01 | Visual byte-parity across real TTY is not automatable hermetically; automated specs assert via StringIO capture | PASS — matched full-regen pair on the reference project through a real TTY (`script`), capture-on vs `--no-run-log` transcripts md5-identical, exit 0/0; `.jsonl` written only for capture-on; also byte-identical on the `use` fast path with real ANSI |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 60 s
- [x] `nyquist_compliant: true` set in frontmatter
- [x] Manual-only table executed and recorded (1 item above — executed 2026-09-01, recorded in [12-UAT.md](12-UAT.md): real-TTY byte-parity PASS, md5-identical transcripts)

**Approval:** validated 2026-09-02 — 11/11 map rows green (241 examples, 0 failures, scoped re-run); the single manual-only row executed 2026-09-01 and recorded in [12-UAT.md](12-UAT.md).


---

## Validation Audit 2026-09-02

| Metric | Count |
|--------|-------|
| Gaps found | 0 |
| Resolved | 0 |
| Escalated | 0 |

Reconciliation evidence (validate-phase §6, State A):
- All 11 Per-Task Map rows re-run scoped on 2026-09-02: `bundle exec rspec` over spec/main_run_log_spec.rb, spec/main_version_spec.rb, spec/run_log_spec.rb, spec/sh_run_log_sink_spec.rb, spec/core_spec.rb, spec/config_spec.rb, spec/init_spec.rb, spec/build_pipeline_spec.rb, spec/build_pipeline_seeding_spec.rb, spec/build_pipeline_provenance_spec.rb, spec/installer_use_fast_path_spec.rb, spec/installer_build_spec.rb, spec/installer_spec.rb, spec/watch_spec.rb, spec/watch_loop_spec.rb, spec/watch_signals_spec.rb → **241 examples, 0 failures (23.0 s)**.
- Wave 0 spec files (spec/main_run_log_spec.rb, spec/run_log_spec.rb, spec/sh_run_log_sink_spec.rb) confirmed present on disk → `wave_0_complete: true`.
- The single manual-only row (real-TTY byte parity, SC3) was executed 2026-09-01 and recorded in [12-UAT.md](12-UAT.md) (test 1 PASS: md5-identical transcripts, exit 0/0). Every requirement (LOGS-01) also carries automated evidence, so `nyquist_compliant: true`.
