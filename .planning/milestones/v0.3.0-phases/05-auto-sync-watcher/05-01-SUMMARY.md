---
phase: 05-auto-sync-watcher
plan: 01
subsystem: watcher
tags: [watcher, signals, sigterm, self-trigger, subprocess-testing, polling, doc-closure, tdd]

requires:
  - phase: 05-auto-sync-watcher (implementation d7c0fff)
    provides: Core::Watcher poll loop + watch command + watch_spec.rb (9 specs)
provides:
  - AUTO-04 signal fix — Signal.trap('TERM') wiring + flush_pending_event: SIGINT AND SIGTERM each flush a pending change and exit 0 (SIGTERM was 143 as shipped)
  - Self-trigger guard — post-regenerate @last_signatures re-snapshot at all 3 loop-owned regenerate sites (A1 probe CONFIRMED the unconditional pbxproj rewrite)
  - spec/watch_signals_spec.rb — 4 subprocess signal examples (repo's first subprocess-signal pattern)
  - spec/watch_loop_spec.rb — 3 subprocess loop-contract examples (self-trigger, burst-collapse, mid-watch deletion)
  - 5-criterion proof matrix + dated 2026-08-24 amendments (ROADMAP criteria 2/4/5, REQUIREMENTS AUTO-05) + 18-row doc-drift closure
affects: [milestone-complete v0.3.0, verifier, release checklist]

actuals:
  tokens: 7915    # chars/4 over the realized diff 2f01211..1429748 (31661 chars, code+docs incl. planning corrections, excluding this summary)
  tasks: 3
  commits: 5      # T1 RED, T1 GREEN, T2 RED, T2 GREEN, docs closure (+ this metadata commit)

tech-stack:
  added: []
  patterns:
    - "Subprocess signal/loop test harness: self-contained child script in tmpdir, Process.spawn(RbConfig.ruby, '-I', lib, ...), marker-file synchronization, every interaction under Timeout.timeout(15) with KILL+reap in ensure — Watcher#run is NEVER invoked inside the RSpec process (Signal.trap would leak into the runner)"

key-files:
  created:
    - spec/watch_signals_spec.rb
    - spec/watch_loop_spec.rb
    - .planning/phases/05-auto-sync-watcher/05-01-SUMMARY.md
  modified:
    - lib/spm_cache/core/watcher.rb
    - .planning/ROADMAP.md
    - .planning/REQUIREMENTS.md
    - .planning/PROJECT.md
    - .planning/STATE.md
    - .planning/phases/05-auto-sync-watcher/05-VALIDATION.md
    - .planning/phases/05-auto-sync-watcher/SUMMARY.md
    - .planning/research/SUMMARY.md
    - .planning/codebase/CONCERNS.md
    - AGENTS.md
    - README.md
    - docs/superpowers/specs/2026-08-10-v0.3.0-watch-init-doctor-design.md

key-decisions:
  - "Signal fix shape: Signal.trap('TERM') { raise Interrupt } as the first statement of run joins the existing rescue Interrupt; flush_pending_event regenerates a pending change on interrupt and never lets a failing flush turn Ctrl-C into a non-zero exit"
  - "Self-trigger guard: @last_signatures = current_signatures immediately after every regenerate site the loop owns (initial, in-loop, flush); pre-regenerate snapshots untouched (they still decide WHETHER to regenerate); regenerate itself and run_once untouched; installer.rb untouched"
  - "A1 probe verdict CONFIRMED (see Self-trigger disposition below): the guard is a real defect fix, not merely defensive hardening"
  - "Mid-watch deletion semantics amended to the shipped reading (logged-once transient, loop idles) rather than adding loop-exit logic — smallest honest change, accepted-as-shipped per 05-CONTEXT"
  - "Debounce documented as a fixed poll interval (within-window collapse uses final state; spanning-window bursts regenerate once per window) — no quiet-period debounce added"

patterns-established:
  - "Subprocess signal testing (Pitfall 5 recipe now realized in-repo): child script + marker sync + Timeout/KILL guard"
  - "Self-writing installer modeling: an installer that appends to the watched file faithfully pins the regenerate-consumes-own-write contract"

requirements-completed: [AUTO-01, AUTO-02, AUTO-03, AUTO-04, AUTO-05]

coverage:
  - id: D1
    description: "SIGINT/SIGTERM each flush a pending change and exit 0; fatal initial failure exits 1"
    requirement: AUTO-04
    verification:
      - kind: integration
        ref: "spec/watch_signals_spec.rb — 4 subprocess examples"
        status: pass
  - id: D2
    description: "Watcher never re-triggers on its own regeneration writes"
    requirement: AUTO-01
    verification:
      - kind: integration
        ref: "spec/watch_loop_spec.rb — self-trigger example (marker stays 1 across >=6 windows)"
        status: pass
  - id: D3
    description: "Burst saves within one poll window collapse into one regeneration using the final file state"
    requirement: AUTO-02
    verification:
      - kind: integration
        ref: "spec/watch_loop_spec.rb — burst example (2 markers, last records final size)"
        status: pass
  - id: D4
    description: "Mid-watch deletion logged once as transient, loop idles, clean TERM exit"
    requirement: AUTO-04
    verification:
      - kind: integration
        ref: "spec/watch_loop_spec.rb — deletion example (2 markers, '[watch] integration failed', exit 0)"
        status: pass
  - id: D5
    description: "5-criterion proof matrix + dated amendments + 18-row doc-drift closure"
    requirement: AUTO-05
    verification:
      - kind: other
        ref: "grep gates (FSEvents zero-match; 3 ROADMAP + 1 REQUIREMENTS amendments) + make proxy.build && bundle exec rspec (256 examples, 0 failures)"
        status: pass

metrics:
  duration: ~35 min
  completed: 2026-08-24
status: complete
---

# Phase 5 Plan 1: Auto-Sync Watcher verification-scoped closure — signal/self-trigger fixes + criterion proofs + doc-drift closure

SIGTERM trap + interrupt-flush fix, evidence-confirmed self-trigger guard (post-regenerate re-snapshot), 7 new hermetic subprocess specs, a 5-criterion proof matrix, and the full 18-row doc-drift closure with dated polling amendments.

## What shipped (TDD RED→GREEN, one fix per task)

- **Task 1 — AUTO-04 signals**: `Signal.trap('TERM') { raise Interrupt }` at the top of `Watcher#run` + `flush_pending_event` in the Interrupt branch. RED observed: SIGTERM child killed by signal (Ruby `exitstatus` nil = shell 143), interrupt dropped a pending change (1 marker, expected 2). GREEN: both signals exit 0, pending change flushed, fatal initial failure still exits 1.
- **Task 2 — self-trigger guard**: `@last_signatures = current_signatures` immediately after every regenerate site the loop owns (initial, in-loop, flush). RED observed: a pbxproj-writing installer drove 10 regenerations in 2.5s. GREEN: marker stays at exactly 1 across >=6 poll windows. Burst-collapse and mid-watch-deletion proofs green at birth.
- **Task 3 — proofs + docs**: 5-criterion proof matrix below, dated amendments, 18-row closure, VALIDATION.md flags.

Combined watcher.rb diff across Tasks 1+2: **21 insertions, 0 deletions** (within the plan's <= ~20 budget); `regenerate` itself, `run_once`, `watch.rb`, `installer.rb`, and `spec/watch_spec.rb` untouched.

## Criterion proof matrix (exact commands + results)

| Criterion | Requirement | Proof (command → result) |
|---|---|---|
| 1 — watches both files, regenerates via Installer::Use, no manual re-run | AUTO-01 | `bundle exec rspec spec/watch_spec.rb` → **12 examples, 0 failures** (resolution spec :46, diff-detection spec :60); `bundle exec rspec spec/watch_loop_spec.rb` → **6 examples, 0 failures** (burst example proves the real loop regenerates on change with no manual re-run). Anchors: watcher.rb:53-67 (snapshot→diff→regenerate) → watch.rb:37 (factory `->(path) { Installer::Use.new(project: path) }`) → `Installer::Use#perform_install`. Self-trigger caveat closed by the Task-2 guard. |
| 2 — burst saves collapse to one regeneration | AUTO-02 | Task-2 burst example: 3 rapid writes inside one 0.5s window → exactly 2 marker lines (initial + one for the burst), last line records the FINAL file size (last event never dropped). Value/flag specs: watch_spec.rb:109/:118/:124. Dated precision clause added (poll interval; spanning-window bursts regenerate once per window — flagged assumption A2 stands). |
| 3 — `--once` single sync-and-exit, hermetic | AUTO-03 | watch_spec.rb:52 (run_once single install) + :98 (empty watch list → false) green; anchor watch.rb:41-43 (`if @once ... run_once`). No loop, no sleep, no OS API. |
| 4 — transient continue + fatal exit + signals | AUTO-04 | Task-1 examples: SIGINT → 0, SIGTERM → 0 (was 143), flush → 2 installs + 0, fatal → 1 with `[watch] fatal:`. Task-2 deletion example: marker 2, `[watch] integration failed`, TERM exit 0. Continue-on-error contract spec watch_spec.rb:79. Fatal semantics amended (see deviation d). |
| 5 — no new gem dep; --once unit-testable without OS API | AUTO-05 | `git show --stat d7c0fff` → **3 files, 308 insertions** (watch.rb 56, watcher.rb 115, watch_spec.rb 137 — no gemspec); `grep -rn "Fiddle\|listen" lib/` → **NO MATCHES**; hermetic `--once` spec watch_spec.rb:52. Mechanism clause superseded by the dated polling amendment. |

**Full-suite gate:** `make proxy.build && bundle exec rspec` → **Build complete! (0.40s)** + **256 examples, 0 failures** (was 243 pre-plan; +4 signal examples, +3 loop examples... net +13 including the 6 spec_helper-global re-counts from two new spec files). Per-file: `spec/watch_signals_spec.rb` → **7 examples, 0 failures** (4 file-authored + 3 spec_helper.rb globals); `spec/watch_loop_spec.rb` → **6 examples, 0 failures** (3 + 3 globals).

## Signal matrix (Task-1 subprocess examples)

| Signal / condition | Exit status observed | stdout | Marker lines |
|---|---|---|---|
| SIGINT | 0 (RED and GREEN — green at birth) | `[watch] stopped.` | 1 (no pending change) |
| SIGTERM | RED: killed by signal (exitstatus nil; shell 143) → GREEN: **0** | GREEN: `[watch] stopped.` | 1 |
| SIGINT with pending change (inside debounce window) | RED: 0 but 1 marker → GREEN: **0** | `[watch] stopped.` | GREEN: **2** (initial + flushed) |
| Fatal initial install failure | **1** | `[watch] fatal: simulated build failure` | 0 |

## Self-trigger disposition (A1 probe — verdict: CONFIRMED)

Probe (tmpdir, `bundle exec ruby`, 2026-08-24): create `Probe.xcodeproj` via `Xcodeproj::Project.new(path).save`, then two `Xcodeproj::Project.open(path).save` cycles with NO modifications. Raw stat triples of `project.pbxproj`:

```
create+save   : mtime=1787558413.295765    size=6190
reopen+save #1: mtime=1787558413.3023865   size=6190
reopen+save #2: mtime=1787558413.3047621   size=6190
verdict: unmodified reopen+save changes mtime=true size=false
```

**A1 CONFIRMED via mtime**: every `project.save` rewrites the watched pbxproj unconditionally — even with zero modifications. Combined with the already-verified chain (always-run tail `gen_supporting_files; integrate_proxy_into_project; gen_cachemap_viz` outside `fast_path?` at use.rb:31-33; unconditional `project.save` at installer.rb:468; snapshot-before-regenerate at watcher.rb:50-51/:58; integer-second `mtime.to_i` in the signature vs the >=2s poll interval), regeneration's own write is visible to the next poll whenever the save crosses an integer-second boundary — so the self-trigger loop is REAL on any integrated project. The guard is a **defect fix**, not merely defensive hardening. Nuance recorded honestly: for byte-stable fast-path saves the three probe saves landed in the SAME integer second (`…413`), so `mtime.to_i` matched and re-triggering is probabilistic per window (fires when the save crosses a second boundary); any content-changing save (first integration, orphan purges, ref rewires) changes size and triggers deterministically. The RED spec's SelfWritingInstaller (appends a byte per install) models the deterministic case.

**Known trade-off of the guard (accepted):** a change landing exactly DURING a regeneration is absorbed into the post-regenerate baseline and is not re-processed until the next change or the next `watch`/`use` run's initial sync — the same healing property RESEARCH already documents for dropped interrupts.

## Documented deviations (user-accepted / accepted-as-shipped)

All dated 2026-08-24. Sources: 05-CONTEXT.md (user decisions), RESEARCH.md (Pitfalls 1/2/6, Debounce mechanics), 05-01-PLAN.md.

- **(a) Mechanism FSEvents → polling** — ROADMAP criterion 5's "FSEvents binds via Ruby `Fiddle`" is superseded: `watch` ships stdlib mtime+size polling, user-accepted 2026-08-24 (05-CONTEXT). Amended inline at ROADMAP.md:88 and REQUIREMENTS.md:27; PROJECT.md/STATE.md/AGENTS.md corrected. The two surviving clauses (no new gem dependency; `--once` unit-testable without the OS API) verified true.
- **(b) Signal fix delivered (not amended away)** — as shipped, SIGINT exited 0 incidentally (default-disposition Interrupt), SIGTERM exited 143, and no flush existed for either. 05-01 Task 1 delivers the criterion-4 signal clause: both signals flush a pending event and exit 0 (spec/watch_signals_spec.rb proves it).
- **(c) Self-trigger disposition: defect confirmed** — A1 probe CONFIRMED (stat triples above); the post-regenerate re-snapshot guard (05-01 Task 2) fixes a real ~2s regeneration cycle on integrated projects, pinned by the SelfWritingInstaller example.
- **(d) Mid-watch deletion semantics** — shipped behavior: deleting a watched file mid-watch logs ONE timestamped transient failure (`[watch] integration failed`) and the loop idles sleep-bounded (nil signatures compare equal); it does NOT exit non-zero. Fatal = pre-watch/unstartable project (non-zero exit, proven by the Task-1 fatal example). Criterion 4 amended to this reading (accepted-as-shipped, 05-CONTEXT; proven by the Task-2 deletion example: 2 attempts, no busy-loop, clean TERM exit 0).
- **(e) Debounce mechanics precision** — debounce is a fixed poll interval, not quiet-period debounce: saves within one poll window collapse into one regeneration using the final file state; bursts spanning windows regenerate once per window. Recorded in the criterion-2 amendment + CONCERNS.md:106 tweak; no debounce clamp added (T-05-03 accepted: `--debounce=abc` → 0 tight spin is a self-inflicted local-dev sharp edge, recorded here).
- **(f) Re-snapshot trade-off** — a change landing exactly during a regeneration is absorbed into the post-regenerate baseline; healed by the next change or the next run's initial sync (same property RESEARCH documents for dropped interrupts). Accepted with the guard. *(Amended 2026-08-24, review WR-02: the same acceptance covers an interrupt that aborts an in-flight loop regeneration — the loop consumes the change pre-regeneration, so the interrupt flush sees matching signatures and exits 0 without re-applying it; healed by the next `watch`/`use` run's initial sync. Documented in the `flush_pending_event` comment + here rather than adding a `@regenerating` flag, keeping the watcher diff minimal per the review's documentation option.)*
- **(g) Legacy `use --watch` duplication retained** — command/use.rb:50-80 still carries its own hardcoded polling loop (Package.resolved only, `sleep 2`). Catalogued only; migration out of scope for this verification-scoped plan (RESEARCH Pitfall 7 anti-pattern).

## 18-row doc-drift closure table

| # | File:Line | Action taken | Status |
|---|-----------|--------------|--------|
| 1 | ROADMAP.md:88 | Dated amendment: mechanism → stdlib mtime+size polling; surviving clauses confirmed | ✅ closed (1429748) |
| 2 | ROADMAP.md:87 | Dated amendment: signal clause delivered by Task 1; fatal semantics amended | ✅ closed (1429748) |
| 3 | PROJECT.md:60 | "watch uses stdlib mtime polling to avoid `listen`" | ✅ closed (1429748) |
| 4 | PROJECT.md:68 | Mechanism rationale corrected + Outcome → "✓ Shipped Phase 5 — stdlib polling (amended 2026-08-24)" | ✅ closed (1429748) |
| 5 | STATE.md:51 | "watch: stdlib mtime+size polling (no `listen` gem); …" rest untouched | ✅ closed (1429748) |
| 6 | REQUIREMENTS.md:27 | AUTO-05 amended to polling substance, dated note, [x] kept | ✅ closed (1429748) |
| 7 | AGENTS.md:16 | Identical PROJECT.md:60 correction (lockstep) | ✅ closed (1429748) |
| 8 | research/SUMMARY.md:33 | Polling reality; moot listen-fallback advice dropped | ✅ closed (1429748) |
| 9 | 05-SUMMARY.md:8 | "(58 lines)" → "(56 lines)" | ✅ closed (1429748) |
| 10 | 05-SUMMARY.md:9 | "9 specs (12 reported including 3 spec_helper.rb globals)" | ✅ closed (1429748) |
| 11 | 05-SUMMARY.md:12 | "adds a dedicated `Core::Watcher` alongside the retained `use --watch` loop (command/use.rb:50-80)" | ✅ closed (1429748) |
| 12 | design doc :75 | ONE dated deviation note at the watch-mechanism section; historical body untouched | ✅ closed (1429748) |
| 13 | README.md:40-41 | New "**Auto-Sync Watch** — `spm-cache watch` …" entry + legacy line relabeled "**Watch Mode (use)**" | ✅ closed (1429748) |
| 14 | CONCERNS.md:106 | "collapse into one regeneration at the end of the poll window" | ✅ closed (1429748) |
| 15 | codebase/CONVENTIONS.md:148-149 | Already correct ("portable mtime+size polling (Ruby stdlib only)") — verified verbatim | ✅ verified-no-change |
| 16 | codebase/INTEGRATIONS.md:143-144 | Already correct ("stdlib mtime+size polling (no `listen` gem, no FSEvents bindings)") — verified verbatim | ✅ verified-no-change |
| 17 | lib/spm_cache/command/use.rb:46 | Already correct (explicitly says the FSEvents binding is NOT used) — verified verbatim | ✅ verified-no-change |
| 18 | 05-CONTEXT.md:9,:42 | DO NOT EDIT (user decision record); its "12 specs" count superseded numerically by row 10 | ✅ do-not-edit honored |

Doc gates: `grep -rn "FSEvents" README.md AGENTS.md .planning/PROJECT.md .planning/STATE.md` → **0 matches**; `sed -n '84,89p' .planning/ROADMAP.md | grep -c "amended 2026-08-24"` → **3**; `grep -c "amended 2026-08-24" .planning/REQUIREMENTS.md` → **1**; `grep -c "spm-cache watch" README.md` → **1**.

## Commits

- `5a15ff0` test(05-01): RED add failing SIGTERM/flush subprocess signal specs
- `94424e2` fix(05-01): trap SIGTERM and flush pending change on interrupt (GREEN)
- `5c59fb5` test(05-01): RED add self-trigger loop-contract subprocess specs
- `5be091d` fix(05-01): re-snapshot signatures after regenerate to break self-trigger (GREEN)
- `1429748` docs(05-01): amend criteria 2/4/5, close 18-row doc-drift catalogue
- (this commit) docs(05-01): complete verification-closure plan — SUMMARY + STATE/ROADMAP metadata

## Deviations from Plan

**1. [Rule 3 - Blocking] Criterion-2 line anchor off by one**
- **Found during:** Task 3 Part B
- **Issue:** Plan says "add the criterion-2 precision clause at ROADMAP.md:86"; criterion 2 actually lives at ROADMAP.md:85 (line 86 is criterion 3).
- **Fix:** Amendment applied to the actual criterion-2 line (:85). The acceptance gate (`sed -n '84,89p' … | grep -c` → 3) is unaffected.
- **Files modified:** .planning/ROADMAP.md
- **Verification:** gate returns 3. **Commit:** 1429748

**2. [None - Recording] Spec-count reporting nuance**
- Plan done-criteria say "4 examples" (signals) / "3 examples" (loop); actual reported counts are 7 and 6 because spec_helper.rb registers 3 global examples in every file run (the same nuance the plan itself documents for watch_spec's "12 reported"). File-authored examples are exactly 4 and 3; full suite 256 examples, 0 failures.

**3. [None - Recording] Combined watcher.rb diff = 21 insertions vs "<= ~20"**
- 18 (Task 1: trap + flush call + 15-line flush_pending_event incl. 3 comment lines + blank) + 3 (Task 2 re-snapshots). Within the tilde tolerance; 0 deletions; all prohibitions honored (watch_spec.rb, installer.rb, run_once, regenerate untouched).

**4. [Rule 2 - Missing critical] VALIDATION.md stale task map + flags**
- **Found during:** Task 3 (flagged by plan-checker before dispatch)
- **Issue:** 05-VALIDATION.md mapped 5 phantom task IDs (05-01-01..05) all to watch_spec.rb and carried `nyquist_compliant: false` / `wave_0_complete: false` after the suite was green.
- **Fix:** Task map rewritten to the 3 actual tasks with real commands and green statuses; flags set true after the full suite passed; sign-off checklist ticked.
- **Files modified:** .planning/phases/05-auto-sync-watcher/05-VALIDATION.md
- **Verification:** flags + map verified in file. **Commit:** 1429748

**Total deviations:** 4 (1 auto-fixed blocker, 1 auto-added critical fix, 2 recorded nuances). **Impact:** none on criteria — all 5 proven; full suite green.

## Self-Check: PASSED

All acceptance criteria re-verified post-completion: spec files + SUMMARY exist on disk; all 5 commits present (5a15ff0, 94424e2, 5c59fb5, 5be091d, 1429748); signals 7/0 + loop 6/0 + watch_spec 12/0 + full suite 256/0; Signal.trap count exactly 1; watcher.rb combined diff 21 insertions/0 deletions; spec/watch_spec.rb + installer.rb byte-untouched; FSEvents zero-match gate, 3+1 amendment gates, README entry, 05-SUMMARY content gates ("(56 lines)", "9 specs (12 reported", "alongside the retained") all green; A1 probe verdict + stat triples recorded above.
