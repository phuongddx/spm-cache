---
phase: 16-package-toggles-panel-completion
verified: 2026-09-02T08:00:00Z
status: passed
score: 3/3 must-haves verified
behavior_unverified: 0
overrides_applied: 0
---

# Phase 16: Package Toggles + Panel Completion Verification Report

**Phase Goal:** Users can flip per-package caching from the browser through the same config code path `spm-cache off` uses, with honest saved-vs-applied semantics and visible reasons where toggling isn't allowed.
**Verified:** 2026-09-02T08:00:00Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | (SC1/TOGL-01) Toggling a package persists to the same config ignore list `spm-cache off` writes — one source of truth, atomic save that cannot clobber concurrent CLI edits | ✓ VERIFIED | `lib/spm_cache/core/config.rb` `set_ignored`/`set_ignored_all` — sidecar `flock(LOCK_EX)` on `<config_path>.lock`, in-lock `reset!+load`, key-level assign, same-dir Tempfile+`File.rename` atomic save. `lib/spm_cache/command/off.rb:19-24` calls `config.set_ignored_all(...)` — the exact same mutator, with the byte-identical CLI contract pinned by `spec/command_off_shared_mutator_spec.rb`. `router.rb:126,398` — `POST /api/toggle` → `api_toggle` → `@config.set_ignored(package, !cached)`, the identical mutator. `spec/config_mutator_spec.rb` (13 examples, clobber-proof/atomicity/release-on-raise rows) and `spec/web_toggle_routes_spec.rb` both pass (confirmed via scoped run below). CR-01 fix (`router.rb:328-331`, `read_state_packages` helper) closes the one crash path the code reviewer found in the read side of this same write flow. |
| 2 | (SC2/TOGL-02) The toggle UI distinguishes saved vs applied state and offers an explicit Apply-now (re-sync) action that runs the real sync | ✓ VERIFIED | `lib/spm_cache/web/read_models/state.rb` computes `saved_cached`/`applied_cached`/`pending` per row from a fresh per-call disk read (`saved_ignore_list`) joined against the graph. `lib/spm_cache/web/assets/app.js:147-190` renders the checkbox from `saved_cached`, a `pending` chip, and builds `#state-sync-bar` as the panel body's first child whenever any row is pending. `router.rb:120-125` — `POST /api/apply` = `api_mutate(fixed_scope: 'use')`, the same `Web::Jobs` slot Phase 15 spawns real CLI subprocesses through (`Jobs::SCOPES['use'] = ['use']`); `app.js:519-544` `clickApply` POSTs `/api/apply`. Browser-verified end to end in `16-06-SUMMARY.md` § D-16 rows 1, 3, 4, 5, 8 (toggle→save→bar, Apply-now→real `use` run→poll convergence, 409 against a held slot, Revert-all honest lag, poll-skip no-bounce) — all PASS, zero product defects. |
| 3 | (SC3/TOGL-03) Packages that cannot be toggled show WHY (pattern-managed / plugin / binary-target / excluded / fidelity) | ✓ VERIFIED | `state.rb` `toggle_reason` — pinned precedence chain `excluded → plugin → binary-target → pattern-managed → fidelity`, first-hit-wins control flow, matching `spec/web_state_spec.rb` "the reason matrix" (10 examples). `binary-target` fact sourced from `lib/spm_cache/installer.rb` enrichment (`binary_target` beside `products[]`, invalidated with it) and `Core::Lockfile#binary_backed_names`. `app.js:42-46,151-155` `REASON_CLASS` renders the verbatim reason as a title-tooltipped badge, neutral fallback for an unrecognised word. Browser-verified in `16-06-SUMMARY.md` § D-16 row 2 — all five reasons plus an unknown-reason fallback rendered correctly, PASS. |

**Score:** 3/3 truths verified (0 present, behavior-unverified)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/spm_cache/core/config.rb` | Shared mutator (`set_ignored`/`set_ignored_all`), sidecar flock, atomic save | ✓ VERIFIED | Present, substantive, wired (called by `off.rb` and `router.rb`) |
| `lib/spm_cache/command/off.rb` | Routed through the shared mutator, output byte-identical | ✓ VERIFIED | `set_ignored_all` call confirmed at off.rb:24; pinned by `spec/command_off_shared_mutator_spec.rb` |
| `lib/spm_cache/core/lockfile.rb` | `binary_backed_names` reachable Set reader | ✓ VERIFIED | Present; consumed by `state.rb:144-152` |
| `lib/spm_cache/installer.rb` | `binary_target` flag derivation beside `products[]` | ✓ VERIFIED | Present; invalidated together with `products[]` |
| `lib/spm_cache/web/router.rb` | `/api/toggle`, `/api/apply`, `/api/revert` dispatch + handlers | ✓ VERIFIED | All three arms present (lines 120-133), full validation matrix (token → verb → body → package → cached → unknown_package → not_toggleable → still_pattern_ignored → config_write_failed → 2xx), CR-01 guard wired via `read_state_packages` |
| `lib/spm_cache/web/jobs.rb` | `SCOPES['use']` for Apply-now | ✓ VERIFIED | Present (confirmed in 16-04-SUMMARY, code review "Sections confirmed clean") |
| `lib/spm_cache/web/read_models/state.rb` | `toggleable`/`reason`/`saved_cached`/`applied_cached`/`pending` derivation | ✓ VERIFIED | Present, substantive, wired; WR-01/WR-02 review fixes present (`lockfile_binary_names` rescue widened, `would_remain_pattern_ignored?` guard) |
| `lib/spm_cache/web/assets/app.js` | Checkbox column, reason/pending chips, unsaved-changes bar, Apply-now/Revert-all | ✓ VERIFIED | Present, substantive, wired (fetch→render→DOM, no XSS surface per review) |
| `lib/spm_cache/web/assets/styles.css` | Six-column layout, checkbox/badge/bar styling | ✓ VERIFIED | Present; column widths sum to 100% (code review) |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|----|--------|---------|
| `app.js` checkbox `change` | `POST /api/toggle` | `postToggle()` → `requestPost('/api/toggle', {package, cached})` | ✓ WIRED | app.js:368-370 |
| `router.rb api_toggle` | `Config#set_ignored` | direct call | ✓ WIRED | router.rb:398 |
| `command/off.rb` | `Config#set_ignored_all` | direct call | ✓ WIRED | off.rb:24 — same mutator as the web route |
| `app.js clickApply` | `POST /api/apply` | `requestPost('/api/apply', {})` | ✓ WIRED | app.js:519-544 |
| `router.rb /api/apply` | `Web::Jobs` spawn slot | `api_mutate(fixed_scope: 'use')` | ✓ WIRED | router.rb:120-125, `Jobs::SCOPES['use']` |
| `app.js clickRevert` | `POST /api/revert` | `requestPost('/api/revert', {})` | ✓ WIRED | app.js:546+ |
| `router.rb api_revert` | `Config#set_ignored_all` | batched single call over pending rows | ✓ WIRED | router.rb:437 |
| `state.rb toggle_reason` | `app.js REASON_CLASS` badge | server-derived reason string rendered verbatim | ✓ WIRED | state.rb:161-176 → app.js:42-46,151-155 |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|---------------------|--------|
| `state.rb` `saved_cached` | fresh per-call disk read of `spm-cache.yml`'s ignore list | `Config#saved_ignore_list` (no config-singleton staleness) | Yes | ✓ FLOWING |
| `state.rb` `applied_cached` | last-sync graph status (`graph.json`) | existing graph read model | Yes | ✓ FLOWING |
| `state.rb` `toggleable`/`reason` | graph status + binary-backed name Set + fresh ignore list + fidelity | five-fact precedence derivation | Yes | ✓ FLOWING |
| `app.js` checkbox/chip cells | `/api/state` JSON response fields, verbatim | `fetch('/api/state')` → render | Yes | ✓ FLOWING |
| `router.rb api_toggle` write | `Config#set_ignored` → same-dir Tempfile+rename | real disk write, not simulated | Yes | ✓ FLOWING |

### Behavioral Spot-Checks

Scoped RSpec run (not the full suite; phase-touched spec files only), from the repository root:

```
bundle exec rspec spec/web_toggle_routes_spec.rb spec/web_state_spec.rb spec/config_mutator_spec.rb \
  spec/command_off_shared_mutator_spec.rb spec/lockfile_enrichment_spec.rb spec/lockfile_spec.rb \
  spec/web_frontend_spec.rb spec/web_jobs_spec.rb spec/web_integration_spec.rb
```

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| All phase-16 unit/integration specs pass | scoped run above | 361 examples, 0 failures | ✓ PASS |
| Full suite loads and collects the count claimed by 16-06-SUMMARY | `bundle exec rspec --dry-run` | 1095 examples, 0 failures | ✓ PASS |
| No debt markers left in phase-touched files | grep TBD/FIXME/XXX/TODO/HACK/PLACEHOLDER across the 9 touched lib files | no matches | ✓ PASS |

### Probe Execution

Not applicable — this phase's manual/interactive verification is the recorded agent-browser probe (D-16), not a `scripts/*/tests/probe-*.sh` script. See "Browser Truths (D-16)" below.

### Browser Truths (D-16, recorded in 16-06-SUMMARY.md)

All 8 manual rows executed against a real server and a real scratch project (`/tmp/d16-scratch`), zero product defects found:

| Row | Behavior | Requirement | Result |
|-----|----------|-------------|--------|
| 1 | Toggle → instant save + pending chip + bar | TOGL-01/02 | PASS |
| 2 | Disabled rows show WHY, all five reasons + unknown fallback | TOGL-03 | PASS |
| 3 | Apply now → real `use` run → poll convergence | TOGL-02 | PASS (convergence mechanism recorded honestly: ignore-only fast-path sync doesn't regenerate the graph; bar clears on the next poll once the graph is rewritten, per design — backlog item noted, not a defect) |
| 4 | Apply 409 against a held slot | TOGL-02/A4 | PASS |
| 5 | Revert all with honest lag | TOGL-02/A3 | PASS |
| 6 | Toggle during a build stays live | TOGL-01/D-08 | PASS |
| 7 | Write failure survives polls | TOGL-01 | PASS |
| 8 | Poll-skip: no checkbox bounce | TOGL-02/A8 | PASS |

These are the load-bearing runtime/timing/visual truths no source-code grep can reach (poll-race integrity, real checkbox bounce, real 5xx-during-render survival, real spawn-through-slot). Recorded verbatim in `16-06-SUMMARY.md`; treated as verified evidence per the assignment's routing instruction.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|--------------|--------|----------|
| TOGL-01 | 16-01, 16-04, 16-06 | Per-package on/off persists through shared mutators, atomic save | ✓ SATISFIED | Truth 1 above; `requirements-completed: [TOGL-01, TOGL-02, TOGL-03]` in 16-06-SUMMARY.md frontmatter |
| TOGL-02 | 16-03, 16-04, 16-05, 16-06 | Saved-vs-applied UI + explicit Apply-now | ✓ SATISFIED | Truth 2 above |
| TOGL-03 | 16-02, 16-03, 16-05, 16-06 | Non-toggleable rows show WHY (5-word vocabulary) | ✓ SATISFIED | Truth 3 above |

No orphaned requirements — REQUIREMENTS.md maps exactly TOGL-01..03 to Phase 16, all three claimed across the six plans.

**Documentation staleness (not a code gap):** `.planning/ROADMAP.md`'s Phase 16 plan checklist still shows only 16-01..03 checked (`[x]`) and `[ ]` for 16-04..06, and `.planning/REQUIREMENTS.md` still marks TOGL-01..03 as unchecked/"Pending". This contradicts the actual codebase and SUMMARY state (all six plans `status: complete`, all three requirements satisfied in code and browser-verified). Per 16-05-SUMMARY.md's own "Next Phase Readiness" note, ROADMAP/REQUIREMENTS updates were explicitly left to the orchestrator/phase-close step and were not yet applied at the time of this verification. This is a documentation-sync gap, not a goal-achievement gap — flagged here for the orchestrator to correct during phase closure, not blocking `passed` status since it does not reflect an unmet codebase truth.

### Anti-Patterns Found

None. Grep for `TBD|FIXME|XXX|TODO|HACK|PLACEHOLDER|not yet implemented|coming soon` across all 9 phase-touched lib files returned zero matches. Code review (`16-REVIEW.md`) found 3 issues (1 critical, 2 warning), all resolved with atomic RED-first commits (`31b73a2`, `f7c20ba`, `aec5025`) and independently confirmed present in the current codebase by this verification (see Truth 1/3 evidence above).

### Human Verification Required

None. All interactive/timing-dependent behaviors were already executed and recorded via the D-16 agent-browser probe (16-06-SUMMARY.md), which this verification treats as satisfying the "always needs human" category (visual appearance, real-time behavior, poll-race timing) per the assignment's explicit routing instruction.

### Gaps Summary

No gaps. All three ROADMAP Success Criteria and all three REQUIREMENTS (TOGL-01..03) are verified in code, in the scoped test suite, and in the recorded browser probe. The one code-review Critical and two Warnings raised during the phase were all fixed and verified (RED-first, atomic commits) before phase close. The only outstanding item is a documentation-sync gap (ROADMAP.md/REQUIREMENTS.md checkboxes not yet updated to reflect 16-04..06 completion) — informational only, does not affect the `passed` verdict.

---

_Verified: 2026-09-02T08:00:00Z_
_Verifier: Claude (gsd-verifier)_
