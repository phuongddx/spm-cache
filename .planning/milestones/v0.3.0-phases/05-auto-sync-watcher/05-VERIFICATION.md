---
phase: 05-auto-sync-watcher
verified: 2026-08-24T08:42:39Z
status: passed
score: 8/8 must-haves verified
behavior_unverified: 0
overrides_applied: 0
prohibitions:
  - id: P-05-1
    statement: "The watcher MUST NOT regenerate in response to its own regeneration writes (unconditional project.save rewriting the watched project.pbxproj)"
    tier: test
    disposition: respected
    enforcement: "spec/watch_loop_spec.rb 'never re-triggers on its own regeneration writes (self-trigger guard)' — SelfWritingInstaller appends a byte to the watched pbxproj on every install; asserts marker == ['install'] across >=6 poll windows (debounce 0.3, 2.5s sleep). Passing (6 examples, 0 failures). RED pre-fix observed >=3 regenerations (5c59fb5)."
  - id: P-05-2
    statement: "Burst collapsing MUST NOT drop the last event of a burst — regeneration must use the final file state"
    tier: test
    disposition: respected
    enforcement: "spec/watch_loop_spec.rb 'collapses a burst of saves within one poll window into one regeneration using the final state' — 3 rapid increasing-size writes inside one 0.5s window; asserts exactly 2 markers AND last marker == install:<final file byte size>. Passing."
  - id: P-05-3
    statement: "The loop MUST NOT busy-loop (unbounded zero-delay regeneration) when watched files become unreadable or deleted mid-watch"
    tier: test
    disposition: respected
    enforcement: "spec/watch_loop_spec.rb 'logs a mid-watch deletion once as transient and idles without busy-looping' — deletion then >=4 windows; asserts marker count == 2 (bounded), '[watch] integration failed' logged once, clean TERM exitstatus 0 (loop alive and sleeping, not spinning, not dead). Passing."
---

# Phase 5: Auto-Sync Watcher — Verification Report

**Phase Goal:** Deliver `spm-cache watch` — a filesystem-watch mode that auto-regenerates the proxy package when the Xcode SPM graph changes, deepening the structural moat (zero-touch auto-sync that Scipio/xccache cannot match).
**Verified:** 2026-08-24T08:42:39Z (after plan 05-01 execution AND code-review resolution 0a6e888)
**Status:** passed
**Re-verification:** No — initial verification (no prior 05-VERIFICATION.md existed)
**Scope reviewed:** current HEAD `0a6e888` (review-resolution commit), working tree clean for all phase paths.

## Goal Achievement

The goal is a working, self-sustaining `spm-cache watch` mode. All five ROADMAP criteria are proven against live code by executable subprocess specs that run the REAL `Core::Watcher#run` — plus the two mandated fixes (SIGTERM trap + flush; self-trigger guard) landed RED→GREEN with committing evidence, and the resolved review's major defect (WR-01 double-signal kill during flush) is fixed with its own RED→GREEN spec.

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | SIGTERM to a running watch loop exits 0 with `[watch] stopped.` (was 143 pre-fix) — subprocess spec proves it | ✓ VERIFIED | `watcher.rb:47` `Signal.trap('TERM') { raise Interrupt }` → `rescue Interrupt` (:74-79) → flush → stopped → exit 0. Spec `watch_signals_spec.rb` 'exits 0 with "[watch] stopped." on SIGTERM' passes (9 examples, 0 failures). RED 5a15ff0 documented 143; GREEN 94424e2. |
| 2 | SIGINT and SIGTERM each flush a pending change before exiting 0 — marker shows 2 installs, not 1 | ✓ VERIFIED | Spec 'flushes a pending change on interrupt before exiting 0': INT inside debounce window → exit 0, marker `[install, install]`. TERM provably reaches the identical `rescue Interrupt` handler (truth 1: trap raises Interrupt; INT default disposition raises Interrupt — one shared flush path), and TERM mid-flush is exercised green in the double-signal example (exit 0, 2 markers). RED observed 1 marker dropped (5a15ff0). |
| 3 | Regeneration rewriting project.pbxproj never re-triggers the watcher — marker stays at initial install across >=6 poll windows | ✓ VERIFIED | Post-regenerate re-snapshots at `watcher.rb:52`, `:64`, `:100` (every loop-owned regenerate site; pre-snapshots untouched; `run_once` keeps its own contract). Spec 'never re-triggers on its own regeneration writes': SelfWritingInstaller, 2.5s / >=8 windows at 0.3s debounce, marker `['install']`. RED 5c59fb5 observed 10 regenerations. |
| 4 | Three rapid saves within one poll window cause exactly one regeneration using the final file state (burst collapse; last event not dropped) | ✓ VERIFIED | Spec 'collapses a burst of saves within one poll window into one regeneration using the final state': exactly 2 markers, last records the FINAL file byte size. Passing (6 examples, 0 failures). |
| 5 | Mid-watch deletion logs one timestamped transient failure and idles sleep-bounded (no busy-loop, non-zero exit); unstartable-project initial failures exit 1 | ✓ VERIFIED | Loop spec deletion example: marker 2, `[watch] integration failed`, TERM exit 0. Signals spec 'exits 1 with "[watch] fatal:" when the initial install fails': exitstatus 1. Both passing. |
| 6 | `watch --once` remains a hermetic single sync-and-exit (existing specs green, untouched) | ✓ VERIFIED | `watch_spec.rb` 12 examples, 0 failures; `git diff 2f01211..HEAD -- spec/watch_spec.rb` = 0 lines (byte-untouched). `watch.rb` `--once` branch → `run_once` (no loop/sleep), installer injected via factory. |
| 7 | Zero new gem dependencies: d7c0fff touched only 3 source files, no gemspec touched; no Fiddle/listen require in lib/ | ✓ VERIFIED | `git show --stat d7c0fff`: exactly 3 files, 308 insertions, no gemspec. `git diff 2f01211..HEAD -- spm_cache.gemspec Gemfile` empty. `grep -rn "Fiddle\|listen" lib/` → 0 matches. |
| 8 | README/AGENTS/PROJECT/STATE contain no FSEvents claim; ROADMAP criteria 2/4/5 carry dated 2026-08-24 amendments | ✓ VERIFIED | `grep -rn "FSEvents" README.md AGENTS.md .planning/PROJECT.md .planning/STATE.md` → 0 matches. `sed -n '84,89p' .planning/ROADMAP.md \| grep -c "amended 2026-08-24"` → 3 (criteria 2 :85, 4 :87, 5 :88 — original wording preserved, amendments appended). REQUIREMENTS.md AUTO-05 amendment count 1. |

**Score:** 8/8 truths verified (0 present-but-behavior-unverified — every behavior-dependent truth is exercised by a passing subprocess spec against the real `Watcher#run`).

### Review Resolution Verification (05-REVIEW.md → 05-REVIEW-FIX.md, resolved at 0a6e888)

| Finding | Severity | Claimed fix | Verified |
|---|---|---|---|
| WR-01 second signal during flush kills process | major | IGNORE masks in `rescue Interrupt` (2771a69, RED 6fbd052) | ✓ `watcher.rb:76-77` masks TERM+INT before `flush_pending_event`; spec 'completes the flush and exits 0 when a second signal lands mid-flush' (INT → TERM+INT mid-flush → exit 0, 2 markers) passes |
| WR-02 interrupted in-flight regeneration abandons change | minor | documentation acceptance (ad0ea76) | ✓ Comment at `watcher.rb:86-89` states the accepted edge verbatim; 05-01-SUMMARY deviation (f) carries the dated amendment |
| WR-03 flush-failure branch uncovered | minor | subprocess spec (9bf563a) | ✓ Spec 'logs a failing flush and still exits 0': exit 0, `[watch] flush failed` + `[watch] stopped.`, marker 1 — passes, pinning the branch |

### Required Artifacts

| Artifact | Status | Details |
|---|---|---|
| `lib/spm_cache/core/watcher.rb` — TERM trap + flush_pending_event + post-regenerate re-snapshots | ✓ VERIFIED | Read in full (146 lines). Production diff vs pre-phase `2f01211`: +30/−0, only this file — 21 lines from plan tasks (within the plan's ≤~20 tilde budget), +9 more from the resolved review's WR-01 masks and WR-02 comment, which the review explicitly prescribed. `Signal.trap` count is 3 (1 raise-trap + 2 IGNORE masks at :76-77); the plan's "exactly 1" predates and is superseded by the accepted review fix. Syntax OK (`ruby -c`). |
| `spec/watch_signals_spec.rb` — subprocess signal examples | ✓ VERIFIED | 6 authored examples (plan's 4 + WR-01 double-signal + WR-03 flush-failure) + 3 spec_helper globals = 9 examples, 0 failures. Harness: real Watcher via `-I lib`, marker sync, `Timeout.timeout(15)` + KILL/reap in ensure. |
| `spec/watch_loop_spec.rb` — 3 loop-contract subprocess examples | ✓ VERIFIED | Self-trigger, burst-collapse, mid-watch deletion — 3 authored + 3 globals = 6 examples, 0 failures. |
| `.planning/phases/05-auto-sync-watcher/05-01-SUMMARY.md` — proof matrix + deviations | ✓ VERIFIED | Present and substantive: 5-criterion proof matrix with exact commands/results, signal matrix, A1 probe verdict CONFIRMED with stat triples, deviations (a)-(g) (f carries the WR-02 dated amendment), 18-row doc-closure table, 4 recorded deviations. |
| Corrected docs (ROADMAP, REQUIREMENTS, PROJECT, STATE, AGENTS, README, research/SUMMARY, CONCERNS, design spec, 05-SUMMARY) | ✓ VERIFIED | All gates re-run green (truths 7-8); 05-SUMMARY carries "(56 lines)", "9 specs (12 reported", "alongside the retained"; design doc deviation note verified by review. |

### Key Link Verification

| From | To | Via | Status | Details |
|---|---|---|---|---|
| `Signal.trap('TERM') { raise Interrupt }` (watcher.rb:47) | `rescue Interrupt` → `flush_pending_event` → exit 0 | trap-raise + default INT disposition converge on the one rescue clause; IGNORE masks (:76-77) guard the flush | ✓ WIRED | Source read directly; all 6 signal examples pass, incl. double-signal and flush-failure paths |
| `Command::Watch --once` branch (watch.rb) | `Watcher#run_once` → `Installer::Use#perform_install` | `installer_factory: ->(path) { Installer::Use.new(project: path) }` + `if @once ... watcher.run_once` | ✓ WIRED | watch.rb source confirmed; `require 'spm_cache/installer/use'` at run top; watch_spec :52/:98 green |
| Post-regenerate re-snapshot at all 3 loop-owned sites | Unconditional `project.save` (installer.rb:468) | `@last_signatures = current_signatures` after initial (:52), in-loop (:64), and flush (:100) regenerates | ✓ WIRED | `run_once` correctly keeps its own snapshot; `regenerate` itself untouched; self-trigger spec green |
| Subprocess specs → real Watcher | `Process.spawn(RbConfig.ruby, '-I', File.expand_path('lib', SPMCache::ROOT), script, ...)` | marker-file sync + Timeout(15) + KILL/reap ensure | ✓ WIRED | Both spec files read in full; `Watcher#run` never invoked in-process |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|---|---|---|---|---|
| watcher.rb | `current_signatures` | `File.stat` on glob-resolved Package.resolved + project.pbxproj (real filesystem) | Yes — specs mutate real files and the loop reacts | ✓ FLOWING |
| watcher.rb | regeneration target | `@installer_factory.call(project_path)` → `Installer::Use#perform_install` (real install path in production wiring) | Yes — watch.rb:37 constructs the real installer | ✓ FLOWING |
| spec marker files | `marker_lines` | Child processes append per `perform_install` call | Yes — asserted counts/sizes in every example | ✓ FLOWING |

No static returns, hardcoded hollow props, or mock-only termini in the production path.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|---|---|---|---|
| Full suite incl. all new specs | `make proxy.build && bundle exec rspec` | `Build complete! (0.17s)`; **258 examples, 0 failures** (matches claimed local proof) | ✓ PASS |
| Signal matrix | `bundle exec rspec spec/watch_signals_spec.rb` | **9 examples, 0 failures** (TERM 0, INT 0, flush 2-installs, double-signal mid-flush 0, flush-failure logged 0, fatal 1) | ✓ PASS |
| Loop contracts | `bundle exec rspec spec/watch_loop_spec.rb` | **6 examples, 0 failures** (self-trigger 1, burst 2/final-size, deletion bounded 2) | ✓ PASS |
| Existing suite unregressed | `bundle exec rspec spec/watch_spec.rb` | **12 examples, 0 failures**; file byte-untouched vs 2f01211 | ✓ PASS |

### Probe Execution

Phase probes are RSpec-based (no `scripts/*/tests/probe-*.sh` exist); executed via the spot-check commands above. The A1 probe (unmodified reopen+save rewrites pbxproj mtime) verdict CONFIRMED is recorded with raw stat triples in 05-01-SUMMARY.md — consistent with the shipped guard and its RED evidence (10 regenerations pre-fix).

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|---|---|---|---|---|
| AUTO-01 | 05-01 | watch watches Package.resolved + project.pbxproj, auto-regenerates via Installer::Use, no manual re-run | ✓ SATISFIED | watch_spec :46/:60 (12/0); loop burst example (real loop regenerates on change); wiring watch.rb:37 → `Installer::Use#perform_install`; self-trigger caveat closed (truth 3) |
| AUTO-02 | 05-01 | Burst saves collapse via configurable debounce (default 2s) to one regeneration | ✓ SATISFIED | Burst example: one regeneration, final state; debounce value/flag specs watch_spec :109/:118/:124; dated precision amendment (poll-window semantics) on ROADMAP :85 |
| AUTO-03 | 05-01 | `watch --once` single sync-and-exit without the loop | ✓ SATISFIED | watch_spec :52/:98; watch.rb `--once` branch → `run_once`; hermetic via injected factory |
| AUTO-04 | 05-01 | Continue on transient errors (timestamped logs); non-zero only on fatal; SIGINT/SIGTERM flush + exit 0 | ✓ SATISFIED | Signals spec 9/0 (incl. double-signal + flush-failure after review); deletion example; fatal exit 1 example; watch_spec :79; fatal semantics amendment dated on ROADMAP :87 |
| AUTO-05 | 05-01 | stdlib mtime+size polling, no new gem dependency (amended 2026-08-24) | ✓ SATISFIED | d7c0fff = 3 files/308 insertions/no gemspec; no Fiddle/listen in lib/; gemspec+Gemfile untouched; `--once` unit-testable; dated amendment on REQUIREMENTS :27 |

Orphaned requirements: none — REQUIREMENTS.md maps exactly AUTO-01..05 to Phase 5; plan 05-01 claims all five.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|---|---|---|---|---|
| — | — | No TBD/FIXME/XXX/TODO/HACK/PLACEHOLDER in watcher.rb, watch.rb, or either new spec file; no empty implementations; no console-only stubs | — | None |

### Prohibition Dispositions (per honest-verifier contract)

All three prohibitions are test-tier with wired, passing enforcement (see frontmatter `prohibitions`): **P-05-1 respected** (self-trigger spec), **P-05-2 respected** (burst final-size assertion), **P-05-3 respected** (bounded deletion example). No unverified-prohibition flags.

### Human Verification Required

None. Every must-have truth carries executable behavioral proof (subprocess specs run the real `Watcher#run`); no visual, external-service, or subjective-quality surface exists in this phase's scope. The one recorded real-world assumption (A2: Xcode package-add bursts land within one 2s poll window) is explicitly flagged and dated inside the criterion-2 amendment itself — accepted scope, not a verification gap.

### Gaps Summary

No gaps. All 8 truths verified, all artifacts substantive and wired, all 4 key links wired, data flows real, all 5 requirements satisfied, all 3 prohibitions respected with passing enforcement, zero debt markers, full suite 258/0. Working tree clean — all evidence committed through `0a6e888`.

---

_Verified: 2026-08-24T08:42:39Z_
_Verifier: Claude (gsd-verifier, Phase5Verifier)_
