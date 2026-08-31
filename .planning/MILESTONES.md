# Milestones


## v0.4.0 Build Fidelity & Release Automation (Shipped: 2026-08-31)

**Phases completed:** 6 phases, 18 plans · 187 commits · 151 files (+28,318/−281) · 2026-08-27 → 2026-08-31
**Closeout:** override (all 6 phases verification passed, 21/21 requirements, audit passed 5/5 seams — see `v0.4.0-MILESTONE-AUDIT.md`; 3 scanner items acknowledged at close: 06/07 UAT leftovers + one deferred item that was actually RESOLVED same day — see STATE.md Deferred Items)
**Known verification overrides:** 3 newly acknowledged, 0 carried forward from a prior close (see STATE.md Deferred Items)

**Key accomplishments:**

- **Graph authority** (FID-01/FID-06/DIAG-01): canonical `Package.resolved` locator (M1 verdict: `Dir.glob` byte order selected a stale nested copy) + reconciliation of `spm-cache.lock` from the host graph on every non-fast-path run + `doctor` drift check — the lockfile now tells the truth.
- **Host-faithful builds** (FID-02/FID-05/PERF-01): every per-package build seeded with the host's resolved graph before first `swift package describe`; vendored-`.xcodeproj` packages honestly classified not-graph-pinned; shared clone dir + process flock — **−40.6% wall-clock, −34% disk** on the 59–70 package reference project.
- **Verifiable artifacts** (FID-03/FID-04/CACHE-01/DIAG-02): realized versions read back after resolution, drift reported (never hard-failed), every cached `.xcframework` carries an atomic provenance sidecar, `cache list` shows per-package fidelity status.
- **The fix reaches existing users** (CACHE-02/CACHE-03): provenance-aware cache hits — missing or mismatched provenance is a miss with a one-time rebuild; version-stamp guard forces one regen per spm-cache bump; `cache clean` sweeps orphaned sidecars.
- **Regression-pinned contract** (TEST-01/02/03): hermetic specs on both production surfaces (Ruby sidecars + Swift graph.json), six-bucket partition with fail-first mutation proofs, 8-class v0.2.x edge matrix — suite grew 258 → **441 examples**, 0 failures.
- **Release automation repaired** (REL-04…09): rewritten `update-tap.yml` — every failure mode loud, scoped deploy-key auth (operator-authorized pivot from the App design), strict-semver tag gate, integrity-gated download preferring byte-stable attached assets, anchored exactly-one edits with postconditions, idempotent no-diff notice, brew verify with a version assertion that demonstrably fails red; `--version` intercept (exit 0); **live-proven end-to-end including the first real tap push** (`ee27cc7`, 2026-08-31). Two more real defects found and fixed live during verification (tap Ruby-3.4 boot; asset-jq field name). Security 15/15 threats closed.

**Remaining operator step:** the v0.4.0 release cut itself — bump `VERSION` → tag `v0.4.0` → attach `spm-cache-<ver>.tar.gz` (git archive from the tag) → watch the first fully-green verify-publish.

## v0.3.0 Mixed Cycle (Shipped: 2026-08-24)

**Phases completed:** 5 phases, 10 plans (6 GSD-tracked), 15 tasks · 86 commits · 87 files (+11,304/−486) · 2026-07-11 → 2026-08-24
**Closeout:** verified (all 5 phases verification passed; 12/12 requirements; audit tech_debt — see milestones/v0.3.0-MILESTONE-AUDIT.md)

**Key accomplishments:**

- **Test CI** (REL-01): first-ever test pipeline — ruby-tests builds the Swift proxy before RSpec on every leg so the full suite (258 examples at close) executes with 0 pending; dead swift-tests build removed; delivered Ruby 3.1–3.3 matrix documented with gemspec justification.
- **Diagnostics** (REL-02, REL-03): `spm-cache doctor` — 7-check data-driven registry, marker report with fix hints, `--json` for CI gating (exit 1 on failures), hermetic spec seam; Swift companion `--version` fixed from dead probe (exit 64 → 0.3.0, exit 0) making Ruby↔Swift drift visible.
- **Bootstrap** (ONBD-01..03): `spm-cache init` — 7-flag wizard, TTY-conditional prompts, idempotent yml diff-merge, `.gitignore` append-once; **canonical lockfile seeding fixed** (pins byte-copy crashed the next `use` with TypeError — now the canonical consumer shape, init→use fast path proven).
- **GitHub Action** (ONBD-04): 6-input thin composite under `action/` (setup-ruby → gem install → init → remote pull/push); `--default-config` flag wiring fixed TDD-clean (config:release was silently ignored); 12-example structural spec cross-referencing the gem CLI; publication to `phuongddx/spm-cache-action` is the recorded release checklist.
- **Auto-Sync Watcher** (AUTO-01..05): `spm-cache watch` — stdlib mtime+size polling (user-accepted 2026-08-24, supersedes the FSEvents/Fiddle design), 2s debounce burst-collapse, `--once`, continue-on-error loop; **SIGTERM contract fixed** (was exit 143 — now traps, masks signals during flush, exits 0) and **self-trigger guard** (installer pbxproj rewrite confirmed as a real re-generation loop).

---
