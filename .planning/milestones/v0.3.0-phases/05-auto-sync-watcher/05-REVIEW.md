---
phase: 05-auto-sync-watcher
reviewed: 2026-08-24T08:26:06Z
depth: deep
commits_reviewed: 5a15ff0, 94424e2, 5c59fb5, 5be091d, 1429748, 99521db
files_reviewed: 15
files_reviewed_list:
  - lib/spm_cache/core/watcher.rb
  - spec/watch_signals_spec.rb
  - spec/watch_loop_spec.rb
  - .planning/ROADMAP.md
  - .planning/REQUIREMENTS.md
  - .planning/PROJECT.md
  - .planning/STATE.md
  - .planning/phases/05-auto-sync-watcher/05-VALIDATION.md
  - .planning/phases/05-auto-sync-watcher/SUMMARY.md
  - .planning/phases/05-auto-sync-watcher/05-01-SUMMARY.md
  - .planning/research/SUMMARY.md
  - .planning/codebase/CONCERNS.md
  - AGENTS.md
  - README.md
  - docs/superpowers/specs/2026-08-10-v0.3.0-watch-init-doctor-design.md
findings:
  critical: 0
  major: 1
  minor: 2
  info: 2
  total: 5
status: resolved
---

# Phase 5: Code Review Report (Auto-Sync Watcher closure)

**Reviewed:** 2026-08-24T08:26:06Z
**Depth:** deep (per-file + cross-file call-chain tracing into CLaide + empirical subprocess probes)
**Files Reviewed:** 15 (production diff: `lib/spm_cache/core/watcher.rb` +21/−0)
**Status:** resolved (fixes applied 2026-08-24 — see 05-REVIEW-FIX.md; WR-01 fixed 2771a69, WR-02 documented ad0ea76, WR-03 pinned 9bf563a)

## Summary

The scope facts all check out: the production diff is exactly 21 insertions / 0 deletions across `94424e2` (+18: TERM trap, `flush_pending_event` call + method) and `5be091d` (+3: post-regenerate re-snapshots); `spec/watch_spec.rb`, `lib/spm_cache/installer.rb`, `installer/use.rb`, the gemspec, and `Gemfile` are untouched by the six commits (the gemspec `required_ruby_version` bump traces to unrelated merge `5759c5b`, not a dependency change); `Signal.trap` appears exactly once; no `Fiddle`/`listen` require in `lib/`; both new spec files carry `frozen_string_literal`; the 3 re-snapshot sites (`watcher.rb:53`, `:64`, `:98`) cover every loop-owned regenerate call with `run_once` correctly excluded; the trap handler mutates no state; no busy-wait was introduced (`--debounce=0` tight-spin is pre-existing `d7c0fff` behavior, accepted as T-05-03); the subprocess harness never runs `Watcher#run` in-process and is Timeout(15)+KILL+reap bounded with tmpdir cleanup; the three spec files pass locally (19 examples, 0 failures); and every doc amendment (ROADMAP 2/4/5, REQUIREMENTS AUTO-05, PROJECT 60/68/69, STATE:51, AGENTS:16, README, CONCERNS:106, design doc :75) is present and accurate — amendments are dated supersession records appended to preserved original wording, not silent rewrites, and the FSEvents zero-match gate passes.

However, adversarial probing of the trap wiring found **one major defect with hard reproduction evidence**: the signal fix itself opens a multi-second window in which a *second* signal kills the process (uncaught `Interrupt`, death by signal, no `"[watch] stopped."`, exit-0 contract broken) and aborts the flush mid-install. Two minor issues (an announced-then-abandoned regeneration on interrupt, and an uncovered flush-failure branch) and two info items follow. The self-trigger guard, burst-collapse, deletion semantics, and spec quality are otherwise sound.

## Warnings

### WR-01: A second signal during `flush_pending_event` kills the process — uncaught Interrupt escapes the rescue handler (Severity: MAJOR)

> **Resolved 2026-08-24 (commit 2771a69, RED spec 6fbd052):** traps set to `IGNORE` for both signals at the top of the `rescue Interrupt` handler, exactly per the review's fix. RED reproduced (`exitstatus: nil`, killed by signal); GREEN: INT→TERM→INT mid-flush → flush completes, `[watch] stopped.`, exitstatus 0, 2 markers. Spec: `spec/watch_signals_spec.rb` "completes the flush and exits 0 when a second signal lands mid-flush".

**File:** `lib/spm_cache/core/watcher.rb:47,71-73,90-101`
**Issue:** `Signal.trap('TERM') { raise Interrupt }` stays armed while `run`'s `rescue Interrupt` handler executes `flush_pending_event` (:72). In Ruby, an exception raised by a trap *inside a rescue handler body* propagates out of the method — it is not matched against the same `rescue` clauses again, and `flush_pending_event`'s inner `rescue StandardError` (:99) does not catch `Interrupt` (`Interrupt < SignalException < Exception`). A second SIGINT or SIGTERM arriving while the flush's `regenerate` is running therefore escapes `run` uncaught: MRI converts it to death-by-signal. This is not theoretical — it is the classic double-Ctrl-C reflex during a slow flush, or Ctrl-C followed by a supervisor TERM, and the flush runs a full real regeneration (seconds on real projects). The fix materially *widened* this window: pre-fix, the Interrupt path was near-instant (`info` + exit), so a second signal practically never landed inside it; post-fix the fatal window is the entire flush duration. The abort lands inside `perform_install` (backtrace below), i.e. a real `project.save` can be interrupted mid-write `[INFERENCE — xcodeproj save atomicity not verified]`, and CLaide 1.1.0 does not save it: `Command.run` uses `rescue Object` (claide/command.rb:336) but `handle_exception` → `report_error` re-raises (claide/command.rb:414-421), so the real CLI dies the same way with a raw backtrace dumped to the user.

**Empirical evidence (subprocess repro against the real `Core::Watcher`, repo `lib/` on load path):**

- INT then TERM mid-flush: `exitstatus: nil, signaled: true, termsig: 2`; `"[watch] stopped."` **never printed**; marker shows install #2 started then abandoned. Backtrace: `watcher.rb:47:in 'block in run': Interrupt` ← `rescue in run` (:72) ← `flush_pending_event` (:97) ← `regenerate` (:84) ← `perform_install → sleep`.
- INT then INT mid-flush (double Ctrl-C): identical fatal outcome.
- Minimal pure-Ruby probe (no spm-cache code) confirms the semantics: trap-raised Interrupt inside a `rescue Interrupt` body is always fatal.
- None of the 4 authored signal specs send a second signal, so the suite cannot catch this.

**Fix:** mask further signals for the shutdown path before flushing:

```ruby
rescue Interrupt
  Signal.trap('TERM', 'IGNORE')
  Signal.trap('INT', 'IGNORE')
  flush_pending_event
  info "\n[watch] stopped."
```

(If instant-kill escape hatch is wanted, trap to `'DEFAULT'` instead — the point is that the trap must not `raise` into the handler that is already unwinding.) Pin it with a 5th subprocess example: slow installer, INT then TERM mid-flush → expect exitstatus 0 and `"[watch] stopped."`.

### WR-02: Interrupt during an in-flight loop regeneration silently abandons the announced change — contradicts the flush contract's own comment (Severity: MINOR)

> **Resolved 2026-08-24 (commit ad0ea76) — documentation option:** `flush_pending_event` comment now states the accepted edge verbatim per the review's wording (mirrors deviation f), and 05-01-SUMMARY deviation (f) carries a dated amendment. No behavioral change — keeping the watcher diff minimal.

**File:** `lib/spm_cache/core/watcher.rb:58-64,90-94` (comment at :86-89)
**Issue:** When a change is detected, the loop consumes it *before* regenerating (`@last_signatures = current` at :60). If the interrupt lands while that regeneration is in flight, the escaping Interrupt reaches `rescue Interrupt` → `flush_pending_event`, whose early return (`return if current == @last_signatures`, :92) now sees equal signatures — the change was already consumed — so no flush runs. Net effect, reproduced empirically: `"SPM graph changed, re-integrating..."` printed, install started, then INT → abort mid-work → `"[watch] stopped."` + exit 0, marker stuck at the initial install. The change is never applied in this session; it heals only on the next `watch`/`use` run's unconditional initial sync. This directly contradicts the shipped comment "flush it so Ctrl-C never silently drops a pending regeneration" (:86-89) — a regeneration that was *announced and started* is exactly a pending regeneration from the user's viewpoint. Note this is distinct from documented deviation (f) (a *new external* change landing during regeneration being absorbed into the baseline). Arguably Ctrl-C during re-integration means "stop now", so accepting + documenting this is defensible — but then the comment and criterion wording overclaim.

**Fix (behavioral option):** treat an interrupted in-flight regeneration as pending:

```ruby
# loop body:
@regenerating = true
begin
  regenerate
  @last_signatures = current_signatures
rescue StandardError => e
  warn_msg "[#{Time.now}] [watch] integration failed: #{e.message}"
ensure
  @regenerating = false # ensure runs during Interrupt unwinding
end

# flush_pending_event:
return if !@regenerating && current == @last_signatures
```

or (documentation option): amend the :86-89 comment and the criterion-4/summary wording to "a change detected but interrupted mid-regeneration is abandoned; healed by the next run's initial sync", mirroring deviation (f).

### WR-03: Flush-failure branch has zero spec coverage (Severity: MINOR)

> **Resolved 2026-08-24 (commit 9bf563a):** subprocess example added exactly per the review's recipe — `fail_flush` mode keys the raise off marker-file line count (not instance state); pending change + INT → exitstatus 0, stdout includes `[watch] flush failed` + `[watch] stopped.`, marker == 1 line. Green at birth (pins existing correct behavior).

**File:** `spec/watch_signals_spec.rb` (missing example); branch at `lib/spm_cache/core/watcher.rb:99-101`
**Issue:** The 4 authored signal examples cover SIGTERM, SIGINT, successful flush, and fatal-initial — but not the flush path where `regenerate` itself fails ("failed flush logged, never crashes" is an explicit contract of this fix, and a listed focus of this review). I verified the branch manually via subprocess probe: pending change + INT + failing installer → `"[2026-08-24 …] [watch] flush failed: simulated flush-time build failure"` + `"[watch] stopped."` + exitstatus 0, marker unchanged — the code is correct today, but nothing pins it. A future refactor of `flush_pending_event` (e.g. someone "simplifying" the inner rescue) could turn a flush-time failure into a non-zero exit or an unhandled crash without any spec failing.

**Fix:** add one subprocess example — installer raising `StandardError` on the second call (key the failure off marker-file line count, *not* instance state: the factory constructs a fresh installer per regenerate), pending change + INT → expect exitstatus 0, stdout includes `"[watch] flush failed"` and `"[watch] stopped."`, marker == 1 line.

## Info

### IN-01: Burst example has a microsecond poll-boundary interleaving race (test reliability only)

**File:** `spec/watch_loop_spec.rb:163-183`
**Issue:** The parent's 3 rapid writes (`~µs` apart) race the child's 0.5s poll: if a poll wakes exactly between write #1 and write #3, an extra regeneration can run → 3 markers → flaky failure. Probability is on the order of 1e-4 per run, and most interleavings self-heal because `RecordingInstaller` reads the file at install time (final size recorded regardless of which write triggered detection). Note the same class of tiny race exists between `wait_for_marker` and a partially-written marker line (`readlines` can observe an unterminated line; `strip.reject(&:empty?)` then counts it). No action required; noted for the record.

### IN-02: `ensure` block KILLs an already-reaped pid

**File:** `spec/watch_signals_spec.rb:111-118`, `spec/watch_loop_spec.rb:135-142`
**Issue:** After a successful `Process.wait2`, the `ensure` still sends `KILL` to the reaped pid (rescued `ESRCH`). Harmless in practice, but the textbook pid-reuse hazard window exists; a `reaped` flag (or only killing when the Timeout fired) would remove it. Cosmetic.

## Verified sound (no findings)

- **Diff scope:** production diff is exactly `watcher.rb` +21/−0 (94424e2 +18, 5be091d +3); `run_once`, `regenerate`, `watch.rb` untouched; no orphans in the diff.
- **Untouched-file claims:** `spec/watch_spec.rb`, `lib/spm_cache/installer.rb`, `installer/use.rb`, `spm_cache.gemspec`, `Gemfile` not touched by the six commits (`git log 2f01211..HEAD -- <paths>` empty). Gemspec delta in the wider range is `required_ruby_version 3.0→3.1` from merge `5759c5b` — not a dependency, not this phase.
- **Self-trigger guard:** re-snapshots after all 3 loop-owned regenerate sites (`:53` initial, `:64` in-loop, `:98` flush); pre-snapshots (`:51`, `:60`, `:94`) still decide *whether* to regenerate; `run_once` keeps its own contract; no regenerate path missed (only 4 call sites exist). Self-trigger subprocess example asserts exact marker `['install']` across ≥6 windows — pre-fix RED documented at ≥3.
- **Signal-handler state race:** the trap body only raises; it never reads/writes `@last_signatures` or any ivar — no data race on watcher state. (The control-flow race that does exist is WR-01.)
- **No busy-wait introduced:** loop always `sleep debounce`; the `--debounce=abc → 0` tight spin is pre-existing (`watch.rb:26` `.to_i`, shipped at d7c0fff) and explicitly accepted (T-05-03, deviation e).
- **Gem conventions:** `# frozen_string_literal: true` in both new spec files and the patched source; zero new dependencies; `Signal.trap` count == 1; no `Fiddle`/`listen` anywhere in `lib/` (verified by grep).
- **Subprocess spec quality:** children run the real `Watcher#run` via `Process.spawn(RbConfig.ruby, '-I', lib, …)` with stdout captured to file and stderr nulled; `Timeout.timeout(15)` wraps every interaction; `ensure` KILL+reap prevents orphans; `after` removes the tmpdir; marker-file synchronization is state-based (correct — the factory builds a fresh installer per regenerate, which my first repro wrongly assumed stateful and initially masked WR-01; the shipped specs key state via the marker file or child-local singletons, which is right).
- **Local spec run:** `bundle exec rspec spec/watch_signals_spec.rb spec/watch_loop_spec.rb spec/watch_spec.rb` → 19 examples, 0 failures (16 authored + 3 shared spec_helper globals).
- **Flush-failure path:** manually verified correct (see WR-03 evidence) — timestamped log, clean stop, exit 0.
- **Doc amendments:** ROADMAP criteria 2 (:85), 4 (:87), 5 (:88) carry dated `amended 2026-08-24` records appended to preserved original wording (amendment-record style, not silent rewrite — criterion 5's superseded FSEvents wording remains visible with the supersession noted); REQUIREMENTS AUTO-05 (:27) dated amendment with `[x]` kept; PROJECT.md :60/:68/:69 corrected + outcomes flipped with date; STATE.md :51 corrected; AGENTS.md :16 in lockstep; README :40-41 new "Auto-Sync Watch" entry + legacy "Watch Mode (use)" relabel; CONCERNS.md :106 poll-window precision; design doc :75 single dated deviation note with historical body untouched; FSEvents zero-match gate passes on README/AGENTS/PROJECT/STATE (verified). 05-SUMMARY corrections ("(56 lines)", "9 specs (12 reported", "alongside the retained") present.
- **A1 probe claim** (unmodified reopen+save rewrites pbxproj mtime, size stable) is consistent with the guard's design and the SelfWritingInstaller example; the guard is correctly classified as a defect fix.

---

_Reviewed: 2026-08-24T08:26:06Z_
_Reviewer: Claude (gsd-code-reviewer, Phase5Review)_
_Depth: deep — evidence via `git log/show/diff`, claide 1.1.0 source inspection, targeted `bundle exec rspec`, and four isolated subprocess probes (`/tmp/phase5_*.rb`, outside the repo; repo left untouched)_
