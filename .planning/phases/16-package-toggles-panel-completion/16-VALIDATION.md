---
phase: "16"
slug: "package-toggles-panel-completion"
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
# audit-milestone §5.5 distinguishes NOT-VALIDATED (draft) from PARTIAL (validated + nyquist_compliant: false) (#2117)
status: validated
nyquist_compliant: true
wave_0_complete: true
created: "2026-09-02"
---

# Phase 16 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Source: `16-RESEARCH.md` § Validation Architecture (all seams anchored at file:line; write-path semantics machine-probed 2026-09-02 — probes P1-P7: Psych comment loss, off write shape, stale-writer clobber, cross-process flock, rename-breaks-lock-chain, sidecar stability, fnmatch exactness).

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | RSpec ~> 3.12 (dev dep; hermetic suite per CP7) |
| **Config file** | none beyond `.rspec` defaults (per `.planning/codebase/TESTING.md`) |
| **Quick run command** | `bundle exec rspec spec/config_mutator_spec.rb spec/command_off_shared_mutator_spec.rb spec/web_toggle_routes_spec.rb spec/web_state_spec.rb spec/web_jobs_spec.rb` |
| **Full suite command** | `bundle exec rspec` (Makefile `make test`) |
| **Estimated runtime** | new specs are hermetic units (tmpdir configs + graph fixtures, no real xcodebuild); integration row extends the ONE port-0 boot |

---

## Sampling Rate

- **After every task commit:** the new/extended spec files for the task's module (fast, hermetic)
- **After every plan wave:** `bundle exec rspec` (full suite; hermetic posture intact — CP7)
- **Before `/gsd-verify-work`:** full suite green AND the manual/agent-browser probe table executed
- **Max feedback latency:** 60 s

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 16-01-T1/T2 | 16-01 | 1 | TOGL-01 / D-03, D-04 | T-16-01..03, V5, Pitfall 1-4 | Shared mutator merge-write: flock on the SIDECAR (`spm-cache.yml.lock` — PROBED P5/P6: the yml inode is unsound under rename), `load` INSIDE the lock (never the boot snapshot), key-level ASSIGN (never `<<` — DEFAULT_CONFIG arrays are shared), same-dir Tempfile+rename save, unlock in ensure (release-on-raise asserted); stale-writer scenario cannot clobber (P3 as a spec); `flock(LOCK_NB)` verdict read as TRUTHINESS (returns false, never raises — Pitfall 4); DEFAULT_CONFIG pristine after mutation. Planner addition: `Config.configure(project_dir:)` re-derives `config_path` so no mutation can reach a config outside the configured project (T-16-06) | unit (tmpdir config + sidecar; fork-held flock for contention) | `bundle exec rspec spec/config_mutator_spec.rb` | ❌ Wave 0 | ✅ green |
| 16-01-T3 | 16-01 | 1 | TOGL-01 / D-03 | T-16 off-contract | `off` behavior-preserving through the shared mutator: the two output lines byte-exact (off.rb:24-25), exit status unchanged, uncontended written file byte-identical to today's full 9-key YAML.dump shape (PROBED P2), config_spec.rb rows untouched — NO Off spec exists today; these pins ARE the D-03 contract. Planner pin (research Open Q2): off's redundant pre-load is REMOVED — the mutator's in-lock load is the only load feeding the write | unit | `bundle exec rspec spec/command_off_shared_mutator_spec.rb` | ❌ Wave 0 | ✅ green |
| 16-02-T1/T2 | 16-02 | 1 | TOGL-03 / D-09 | T-16-09..11 | Planner decision on research Open Q1 = **option 1**: the `binary-target` fact is derived Ruby-side in `enrich_lockfile_products` from the describe output it already fetches, written beside `products[]`, cleared with it by `invalidate_stale_products!`; `Core::Lockfile` answers the binary-backed NAME SET (identity ∪ product names ∪ product target names) so the read model can join it to a row keyed by module name. Swift tool untouched; A5's checkout under-detection accepted and recorded | unit (stubbed describe; tmpdir lockfiles) | `bundle exec rspec spec/lockfile_enrichment_spec.rb spec/lockfile_spec.rb` | ✅ extend | ✅ green |
| 16-03-T1/T2 | 16-03 | 2 | TOGL-02 / TOGL-03 / D-06, D-09 | T-16-13..16, CP10 | `/api/state` rows gain `toggleable`/`reason` + saved/applied: derived ONCE server-side per call from a FRESH disk read (the model never loads config today — state.rb:15-17); reason matrix: `pattern-managed` (`should_ignore? && !include?`), `plugin` (status `plugin`), `excluded` (status `excluded`), `fidelity` (provenance `resolution-incompatible` per research recommendation — A4 accepted), `binary-target` per 16-02's flag; precedence excluded → plugin → binary-target → pattern-managed → fidelity; divergence = `saved_ignored != (applied == 'ignored')`; nil-graph rows contribute no divergence. Planner narrowing: a row is `pending` ONLY if it is also toggleable — an unclearable bar is worse than no bar | unit (web_state_spec conventions: tmpdir project/cache_root + `write_graph` helper) | `bundle exec rspec spec/web_state_spec.rb` | ✅ extend | ✅ green |
| 16-04-T1/T2 | 16-04 | 3 | TOGL-01/02/03 / D-08 | T-16-17..23, V5, V4 | Toggle/revert route matrix: token 401, GET → house 404, malformed JSON → 400 `bad_body`, `package` non-empty String → 400 `bad_package`, `cached` EXACTLY boolean (no coercion) → 400 `bad_cached`, unknown package → 404 `unknown_package`, non-toggleable attempt → 400 `not_toggleable`, mutator raise → 500 `config_write_failed`, 2xx `ok_envelope('package'…, 'cached'…)`; toggle/revert NEVER touch the slot (D-08); revert is batched-in-one-lock per research recommendation. Planner pin (research Open Q3): the unknown-package universe is EXACTLY the row set `/api/state` serves, so route and UI can never disagree | unit (web_build_routes_spec conventions) | `bundle exec rspec spec/web_toggle_routes_spec.rb` | ❌ Wave 0 | ✅ green |
| 16-04-T2 | 16-04 | 3 | TOGL-02 / D-07 | T-16-19, T-16-21 | `/api/apply` = `api_mutate(fixed_scope: 'use')` verbatim; `Jobs::SCOPES` gains `'use' => ['use']` (bare `use` verified — command/use.rb); 409 `slot_busy` + 500 `spawn_failed` + 2xx lock snapshot unchanged | unit | `bundle exec rspec spec/web_jobs_spec.rb` | ✅ extend | ✅ green |
| 16-05-T1/T2 | 16-05 | 4 | UI contract (UI-SPEC) | T-16-24..29, UI-SPEC prohibitions 1-13 | Frontend pins: sixth `Cached` column in `COLS`/`COL_CLASS`, native checkbox + `aria-label="Toggle caching for {package}"` with the RAW name, reason/pending chips verbatim-neutral fallback, sync-bar markup/copy byte-exact (D-05 sentence, ONE `Apply now`), `CTRL.busy` amended to the THREE-verb string (supersedes app.js:324 — A4), freeze set covers four buttons (A5), poll-skip guard covers redraw AND stamp. Planner pins: the in-flight guard is a COUNTER (overlapping toggles are blessed by A8); the four-button freeze REMEMBERS its state and re-applies to the bar's buttons, which every render recreates | unit (source/byte pins — no JS runtime in CI; the browser net is the manual table) | `bundle exec rspec spec/web_frontend_spec.rb` | ✅ extend | ✅ green |
| 16-01-T1 + 16-04-T3 | 16-01, 16-04 | 1, 3 | TOGL-01/02 | T-16-04, T-16-17 | THE integration row (extends `web_integration_spec.rb` / `WebServerBoot`): toggle POST → `/api/state` shows saved≠applied (bar condition) → `/api/apply` spawns a fake-bin `use` → its run streams → a post-run `/api/state` shows convergence (bar clears). Server shutdown stays exit-0 with the apply in flight (P5 of 15-RESEARCH posture). The toggle→disk→divergence half is the 16-01 tracer; the apply→convergence half is 16-04-T3 | integration (port 0, loopback) | `bundle exec rspec spec/web_integration_spec.rb` | ✅ extend | ✅ green |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*
*(Task IDs filled by the planner; the requirement → spec-file mapping above is fixed by research and must be preserved.)*

---

## Wave 0 Requirements

- [x] `spec/config_mutator_spec.rb` — merge-write under sidecar flock, clobber-proof stale-writer row, release-on-raise, DEFAULT_CONFIG-pristine assertion, LOCK_NB-false handling
- [x] `spec/command_off_shared_mutator_spec.rb` — the D-03 byte-identical free-path pins (no Off spec exists today — these rows are the contract)
- [x] `spec/web_toggle_routes_spec.rb` — token/verb/body/package/cached/unknown/not_toggleable/500/2xx matrix
- [x] Extend `spec/web_state_spec.rb` — toggleable/reason/saved/applied derivation matrix (fresh-read assertion)
- [x] Extend `spec/web_jobs_spec.rb` — `'use'` scope row (spawn shape unchanged)
- [x] Extend `spec/web_frontend_spec.rb` — sixth column + bar + chips + A4 amendment + poll-skip pins
- [x] Extend `spec/web_integration_spec.rb` (+ `spec/support/web_server_boot.rb` as needed) — toggle→apply→convergence row
- [x] Extend `spec/lockfile_enrichment_spec.rb` + `spec/lockfile_spec.rb` — the derived binary-target flag, its invalidation with `products[]`, and the binary-backed name-set reader (planner's Q1 option-1 decision)

---

## Manual-Only Verifications

> The repo has no JS runtime; the toggle surface's client behavior is verified by an **agent-driven real browser** — the D-14/D-15 probe-net pattern (14's net caught G-13-1; 15's net proved the controls end-to-end). Reference project + scratch project as in 14-05/15-06.

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| ✅ Toggle → instant save + pending chip + bar appears | TOGL-01, TOGL-02 / D-06, D-08 | Real click + checkbox visual + cross-request state | Click a package's checkbox → no bounce, `pending` chip renders in-cell, `#state-sync-bar` appears above the table with the byte-exact D-05 sentence; on disk the yml's ignore list changed accordingly (and comments are gone — D-05's honesty is visibly true) |
| ✅ Disabled rows show WHY (all five reasons) | TOGL-03 / D-09 | Visual chip render + tooltips | Fixture config exercising pattern rows, plugin-only package, cache-only exclusion, resolution-incompatible provenance (+ binary flag per planner option): each disabled row renders exactly one reason chip verbatim, tooltip matches, unknown-reason row renders verbatim in neutral |
| ✅ Apply now → real `use` run → stream → convergence | TOGL-02 / D-07, A5, A7 | Real spawn + EventSource + poll convergence | With divergence present: `Apply now` disables, message `Applying…`, run appears in Run Log with `ui` badge; while it runs, Build/Rebuild/Rollback are disabled too (four-button freeze); on completion the poll clears the bar and `pending` chips — bar clears on server truth, never on POST success |
| ✅ Apply 409 while a build holds the slot | TOGL-02 / D-05, A4 | Cross-request UI state | Start a Build, then click `Apply now`: 409, the amended THREE-verb busy string renders in the bar's message slot (`A build, rollback, or apply is already running — wait for it to finish.`), button re-enables |
| ✅ Revert all restores applied state | TOGL-02 / A3 | Batch write + poll honesty | Diverge ≥2 rows → `Revert all` → both buttons re-enable, bar REMAINS until a poll shows zero divergence (honest lag ≤1 cycle), ignore list back to the applied state on disk |
| ✅ Toggle during a build stays live | TOGL-01 / D-08 | The not-slot-gated contract | While a build streams: toggle a third package → POST succeeds instantly (no 409), `pending` chip appears; the running build is unaffected |
| ✅ Toggle save failure survives polls | TOGL-01 / UI-SPEC error row | Failure-line persistence vs re-render | (Force a failure — e.g. read-only yml) → the pinned `Couldn't save the toggle for {package}…` fail line renders above the table and SURVIVES ≥2 poll cycles; checkbox keeps server truth; cleared by the next successful mutation or Refresh |
| ✅ Poll-skip: no checkbox bounce mid-POST | TOGL-02 / A8 | Race between POST and the 5s poll | Rapidly toggle a package and watch ≥1 poll cycle land while the POST is in flight: the table (and stamp) does NOT redraw to the old value; the next cycle renders persisted truth |

*All 8 rows executed 2026-09-02 via the D-16 agent-browser probe against a real server and a real scratch project (`/tmp/d16-scratch`) — 8/8 PASS, zero product defects. Row-by-row evidence: 16-06-SUMMARY.md § D-16; tabulated in [16-VERIFICATION.md](16-VERIFICATION.md) § "Browser Truths (D-16)". Row 3 (Apply → convergence) passed with a recorded honesty note: the ignore-only fast-path sync does not regenerate the graph, so the bar clears on the next poll once the graph is rewritten (by design; backlog item, not a defect).*

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 60 s
- [x] `nyquist_compliant: true` set in frontmatter
- [x] Manual-only table executed and recorded (8 rows above, D-14/D-15 pattern)

**Approval:** validated 2026-09-02 — 8/8 map rows green (361 examples, 0 failures, scoped re-run); all 8 manual rows executed 2026-09-02 (D-16 agent-browser) and recorded in 16-06-SUMMARY.md / 16-VERIFICATION.md § Browser Truths.


---

## Validation Audit 2026-09-02

| Metric | Count |
|--------|-------|
| Gaps found | 0 |
| Resolved | 0 |
| Escalated | 0 |

Reconciliation evidence (validate-phase §6, State A):
- All Per-Task Map rows re-run scoped on 2026-09-02: `bundle exec rspec spec/config_mutator_spec.rb spec/command_off_shared_mutator_spec.rb spec/web_toggle_routes_spec.rb spec/web_state_spec.rb spec/web_jobs_spec.rb spec/lockfile_enrichment_spec.rb spec/lockfile_spec.rb spec/web_frontend_spec.rb spec/web_integration_spec.rb` → **361 examples, 0 failures (30.9 s)**.
- Every Wave 0 artifact exists on disk (`spec/config_mutator_spec.rb`, `spec/command_off_shared_mutator_spec.rb`, `spec/web_toggle_routes_spec.rb`, plus the extensions to `spec/web_state_spec.rb`, `spec/web_jobs_spec.rb`, `spec/web_frontend_spec.rb`, `spec/lockfile_enrichment_spec.rb`, `spec/lockfile_spec.rb`, and the integration rows `describe 'POST /api/toggle (16-01 tracer)'` + `describe 'POST /api/apply -> converge (16-04)'`) → `wave_0_complete: true`.
- All 8 manual rows executed 2026-09-02 via the D-16 agent-browser probe against a real server and a real scratch project (`/tmp/d16-scratch`), recorded verbatim in 16-06-SUMMARY.md and tabulated in 16-VERIFICATION.md § "Browser Truths (D-16)" — 8/8 PASS, zero product defects. TOGL-01/02/03 each additionally carry automated evidence → `nyquist_compliant: true`.
