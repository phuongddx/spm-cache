---
phase: 09
slug: cache-identity-invalidation
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-08-29
---

# Phase 09 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | RSpec (Ruby) + Swift Testing (`@Suite`/`@Test`, Swift) |
| **Config file** | none new — existing `.rspec` / `Package.swift` test target |
| **Quick run command** | `bundle exec rspec spec/build_pipeline_provenance_spec.rb spec/command_cache_clean_spec.rb` (Ruby) / `swift test --filter CacheTests` (Swift, from `tools/spm-cache-proxy/`) |
| **Full suite command** | `bundle exec rspec` (Ruby) + `swift test` (Swift, from `tools/spm-cache-proxy/`) |
| **Estimated runtime** | ~40s (Ruby full suite, per Phase 8 baseline) + Swift suite (not yet timed this phase) |

---

## Sampling Rate

- **After every task commit:** Run the narrowest of the per-task commands below
- **After every plan wave:** Run both full suites (`bundle exec rspec` + `swift test`)
- **Before `/gsd-verify-work`:** Both full suites must be green
- **Max feedback latency:** ~60s (dominated by the Ruby full suite)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 09-01-* | 01 | 0 | CACHE-02 | V5 | Sidecar JSON parsed defensively (non-Hash/corrupt/missing key → miss) | unit (Swift) | `swift test --filter CacheTests` | ❌ W0 | ⬜ pending |
| 09-01-* | 01 | 0 | CACHE-02 | — | Missing sidecar ⇒ miss | unit (Swift) | `swift test --filter CacheTests` | ❌ W0 | ⬜ pending |
| 09-01-* | 01 | 0 | CACHE-02 | — | Pin disagreement (single package) ⇒ miss | unit (Swift) | `swift test --filter CacheTests` | ❌ W0 | ⬜ pending |
| 09-01-* | 01 | 0 | CACHE-02 | — | Cross-project identity: two projects, same package, different pins, don't share | integration (Ruby, real binary) | `bundle exec rspec spec/gen_proxy_provenance_spec.rb` | ❌ W0 | ⬜ pending |
| 09-01-* | 01 | 0 | CACHE-02 | — | Class E / not-graph-pinned artifact still hits after the fix | unit (Ruby) | `bundle exec rspec spec/build_pipeline_provenance_spec.rb` | ✅ extend existing | ⬜ pending |
| 09-02-* | 02 | 1 | CACHE-03 | — | `cache clean` sweeps orphaned sidecars, leaves paired ones | unit (Ruby) | `bundle exec rspec spec/command_cache_clean_spec.rb` | ❌ W0 | ⬜ pending |
| 09-0?-* | ? | ? | N/A (Pitfall closure) | — | `spm-cache use` fast path forces a full run after a `spm_cache_version` bump | unit (Ruby) | `bundle exec rspec spec/installer_use_fast_path_spec.rb` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky — table finalized once the planner assigns real task IDs/waves.*

---

## Wave 0 Requirements

- [ ] `tools/spm-cache-proxy/Tests/spm-cache-proxyTests/CacheTests.swift` — no test file exists for `BinariesCache`/`Cache.swift` at all today
- [ ] `spec/command_cache_clean_spec.rb` — no spec exists for `Command::Cache::Clean` today
- [ ] `spec/gen_proxy_provenance_spec.rb` (or extend `gen_proxy_cache_only_spec.rb`'s pattern) — real-binary smoke test asserting hit/miss status against fixture sidecars
- [ ] A spec exercising `Installer::Use#fast_path?`'s version-awareness (new file — no existing spec targets `fast_path?` in isolation)

---

## Manual-Only Verifications

*None — all phase behaviors have automated verification per the map above.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
