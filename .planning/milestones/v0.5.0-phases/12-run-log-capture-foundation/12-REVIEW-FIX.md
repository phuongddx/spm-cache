---
phase: 12-run-log-capture-foundation
fixed_at: 2026-08-31T19:19:50Z
review_path: .planning/phases/12-run-log-capture-foundation/12-REVIEW.md
iteration: 2
findings_in_scope: 10
findings_addressed: 10
findings_resolved: 10
fixed: 10
deferred: 0
rejected: 0
status: all_fixed
verification: bundle exec rspec — 536 examples, 0 failures (baseline 519 + 17 net-new examples)
verification_location: main checkout (sequential executor mode; no worktree)
---

# Phase 12: Code Review Fix Report

**Fixed at:** 2026-08-31T19:19:50Z
**Source review:** `.planning/phases/12-run-log-capture-foundation/12-REVIEW.md`
**Iteration:** 2

**Summary:**
- Findings in scope: 10 across both iterations (iteration 1: CR-01..04, WR-01..05; iteration 2: CR-05)
- Addressed: 10
- Resolved (fixed): 10
- Deferred / rejected: 0
- Final gate: `bundle exec rspec` — **536 examples, 0 failures** (519 baseline + 17 net-new)

All fixes applied in the main checkout on `gsd/v0.5.0-web-interface` (sequential executor rules: hooks on, no `--no-verify`, no stash, only touched files staged). TDD discipline observed: every behavioral finding got a failing spec committed first (RED), then the fix (GREEN). WR-01 is the one exception — see its section.

One reviewer factual claim was corrected against the live CLI: **CLAide accepts `--log-dir=X` in any position (parse + validate!) and rejects the two-token `--log-dir X` form in every position** ("Unknown option: `--log-dir` / Did you mean: --log-dir=DIR?"). Probed directly via `Command.parse` + `validate!`. The D-01 contract "the override works wherever CLAide accepts it" therefore resolves to: route the `=` form in any position; the two-token form consumes its value (so it never masquerades as the verb) but routes no override — eliminating CR-02's orphan-override-log failure mode instead of leaving it alive.

## Fixed Issues

### CR-01: Invalid UTF-8 in subprocess output raises outside safe_append, killing the reader thread and failing the build

**Resolution:** fixed
**Rationale:** `record_text`/`event` evaluated `JSON.generate` as an *argument* to `safe_append`, outside its rescue. `safe_append` is now block-based (the line is yielded inside the mutex/rescue), `text` is scrubbed (`String#scrub` → U+FFFD), and `event` scrub String field values via `transform_values` (non-string fields — e.g. `status` integers — keep their JSON types, preserving the D-04 schema). Verified RED: new specs reproduced the exact `JSON::GeneratorError` escape through the real Sh reader thread before the fix.
**Commits:** `927b61d` (test, RED), `918e2a3` (fix, GREEN)
**Spec coverage:** `spec/run_log_spec.rb` "invalid UTF-8 degradation (CR-01)" — body lines scrubbed, run continues; event string fields scrubbed while `status` stays an Integer. `spec/sh_run_log_sink_spec.rb` — real subprocess `printf '\xff\xfe'` through the popen3 sink path; every physical line stays valid JSONL and `finish` does not raise.

### CR-02: `--log-dir` silently misroutes in every position except `--log-dir=X` before the verb

**Resolution:** fixed
**Rationale:** `pre_scan` stopped at the first non-flag token. Rewritten to scan the whole argv: `--log-dir=X` routes in ANY position (the form CLAide actually accepts — see probe note above); the two-token form is consumed without routing (CLAide parity — no orphan override log on CLAide-rejected argv, and the value never becomes the verb). Additionally, `Command::Watch` now passes its already-CLAide-parsed `@log_dir` into `RunLog.cycle_wrapper`/`CycleWrapper` (preferred over the raw-argv scan fallback), so the watch cycle surface honors the override regardless of raw-argv shape. Spec fixtures aligned to the real argv order per the review (`watch_spec` ARGV stub, cycle-wrapper fixtures, `main_run_log_spec` fixtures that pushed the CLAide-rejected two-token form through real `Main.run`).
**Commits:** `2e00cf0` (test, RED), `511c94d` (fix, GREEN)
**Spec coverage:** `spec/run_log_spec.rb` truth-table rows — `--log-dir=X` pre-verb and post-verb routes; two-token form consumes but routes `nil`; watch rows (`=` routes post-verb, two-token routes nowhere). `spec/watch_spec.rb` — cycle wrapper honors `--log-dir=X` after the verb (default runs dir never created). `spec/main_run_log_spec.rb` — `--log-dir override forms` now proves pre-verb AND post-verb `=` routing through real `Main.run`.

### CR-03: Retention prune never bounds a watch session — every prior cycle file is protected by its own live pid

**Resolution:** fixed
**Rationale:** Liveness protection exists for *concurrent* runs (Pitfall 6); a same-pid prior file is by construction a finished run of this process (`finish` wrote its `run_end`). The prune guard is now `protected_run?(pid)` = `pid.is_a?(Integer) && pid != Process.pid && pid_alive?(pid)` (header pid parsed once; unreadable/foreign-dead pids protect nothing — previous semantics preserved for those cases). The pre-existing "never prunes a live-pid run" spec enshrined the buggy same-pid exemption; it was rewritten to its true invariant — a live **foreign** pid (a spawned sleeper child, hermetically) survives over budget.
**Commits:** `d967686` (test, RED), `ed01f4d` (fix, GREEN)
**Spec coverage:** `spec/run_log_spec.rb` retention — "third cycle of the same process bounds the first" (two same-pid fabricated cycles under `runs_keep=1`: oldest pruned, session bounded); foreign-live-pid survives, dead-pid pruned, current-run immune.

### CR-04: `watch --no-run-log` still writes cycle run logs (D-03 is a no-op on the watch surface)

**Resolution:** fixed
**Rationale:** `CycleWrapper#perform_install` now consults `scan.suppressed?` and returns `@installer.perform_install` directly — no file created, no runs dir touched, terminal behavior unchanged.
**Commits:** `40a4803` (test, RED), `815e89f` (fix, GREEN)
**Spec coverage:** `spec/watch_spec.rb` — zero cycle files with `--no-run-log` before the verb AND after the verb (real argv order); `.spm-cache` never created.

### WR-01: TeeIO partial-line buffering is not thread-safe; safe_append's mutex does not cover it

**Resolution:** fixed (single combined commit — see note)
**Rationale:** `record_line`'s read-modify-write on `@buffers` plus the in-place `slice!` loop were unsynchronized. A dedicated `@buffer_mutex` now covers append + extraction + same-stream emission order (lock order buffer→append only, so no deadlock), and `flush_partial_buffers` takes the same lock so `finish` cannot race a straggler writer. **Note on TDD:** the race is latent (only the main thread writes through the tee today) and could not be made to fail deterministically, so no RED commit exists for this finding — the spec was verified green pre-fix and post-fix alike; the fix is defensive hardening for the class's documented multi-threaded design.
**Commits:** `8642c51` (spec + fix combined)
**Spec coverage:** `spec/run_log_spec.rb` concurrency — 2 writers × 50 partial+completing chunk pairs through `record_line` land as exactly 100 complete, uncorrupted body lines.

### WR-02: Run logs persist full argv verbatim — no secrets redaction

**Resolution:** fixed
**Rationale:** The `run_start` header records argv through a redaction seam (`RunLog.redact_credentials` + `CREDENTIAL_PATTERN`): the password half of any `scheme://user:password@` component becomes `[REDACTED]` (embedded PATs in `--remote-url` are the real vector). The header carries `redacted: true/false` so Phase-14 renderers know the identity header is not byte-faithful. Body capture remains verbatim per D-05 — redaction is header-identity only. `user@host` without a password is not redacted (username alone is not a secret).
**Commits:** `1ba3bca` (test, RED), `53cfe4b` (fix, GREEN)
**Spec coverage:** `spec/run_log_spec.rb` "header credential redaction (WR-02)" — `https://user:ghp_secret@github.com/...` → `https://user:[REDACTED]@...` with `redacted: true`; credential-free argv verbatim with `redacted: false`.

### WR-03: popen3 branch returns 60-line tails and hardcoded `status: 0`, diverging from the capture3 contract

**Resolution:** fixed
**Rationale:** The popen3 sink path now accumulates the full streams (`out_buf`/`err_buf` — matching the capture3 branch's memory profile) and returns `{ output:, error:, status: }` with the real `wait_thr.value.exitstatus`. The 60-line bound now applies only where the review scoped it: the raised `failure_detail` message. The spec that enshrined the tailed return was retitled, not deleted — its single-line assertions still hold under full accumulation.
**Commits:** `637d931` (test, RED), `a5751c1` (fix, GREEN)
**Spec coverage:** `spec/sh_run_log_sink_spec.rb` — 120-line subprocess returns 120 lines (not the 60-line tail) with `status: 0`; single-line case unchanged; file capture stays full-fidelity (D-05) independently of the return value.

### WR-04: Low-deployment-target retry now depends on the error surviving the 60-line failure_detail tail

**Resolution:** fixed
**Rationale:** Chose the review's "match the full streamed content" option over the size-capped-blob option (a 4 KiB blob is *smaller* than the 60-line tail and re-introduces the same scroll-past failure). `Core::GeneralError` gained `attr_accessor :full_output`; both `Sh.run` branches attach the complete streamed buffers to the raised error (the message stays tail-bounded for display). `Buildable#xcodebuild` retries when the pattern matches `e.message` **or** `e.full_output`. Full output is already in memory on both branches, so this adds no copying beyond one string concat on the failure path only.
**Commits:** `3025cb5` (test, RED), `4a892b1` (fix, GREEN)
**Spec coverage:** `spec/core_spec.rb` — diagnostic printed before 100 filler lines: absent from the tail-bounded message, present on `full_output` (marker assembled at runtime via `printf` so the cmd text in the message can never match vacuously). `spec/buildable_spec.rb` — retry fires with the bump flag when the diagnostic exists only in `full_output`.

### WR-05: init's lockfile seed crashes on non-object `pins` entries — outside the guard that promises not to crash

**Resolution:** fixed
**Rationale:** Pins parsing extracted to `Init#read_resolved_pins` returning `[pins, seeded]`: non-object entries are dropped with a `dropped N malformed pin(s)` warning (seed stays partial-but-consumable); a non-array `pins` warns and seeds empty; the ParserError/TypeError rescue posture is preserved. `seed_lockfile`'s deep nesting collapsed, keeping the "never abort after the yml but before lockfile/.gitignore" promise.
**Commits:** `54b08ce` (test, RED — reproduced the exact `NoMethodError` from the review), `8125ff7` (fix, GREEN)
**Spec coverage:** `spec/init_spec.rb` — `"pins": ["Alamofire", {...}]`: init completes, warns "dropped 1 malformed pin", seeds exactly the one object pin, and reaches `.gitignore`.

## Verification

- Per-finding: RED verified failing before each fix commit (except WR-01 — latent race, see above); GREEN verified via the targeted spec files; RuboCop checked on every touched file — no net-new offenses (several files already carry advisory Metrics offenses in their committed state; WR-05 finished *below* baseline).
- Full suite (main checkout, after all fixes): `bundle exec rspec` → **534 examples, 0 failures**.
- Ground truth probes: CLAide acceptance matrix for `--log-dir` forms/positions (4 accepted shapes, 2 rejected) run against the real command tree before fixing CR-02.

## Skipped Issues

None — all nine in-scope findings were fixed. The seven IN-* items remain out of scope per `fix_scope: critical_warning`.

## Iteration 2 — CR-05 (the WR-01 regression)

Re-review (12-REVIEW.md, iteration 2) found the WR-01 buffer-mutex fix (`8642c51`) introduced a re-entrancy deadlock: an append failure while the tee is installed makes the degradation warning (`safe_append` rescue → `warn_once` → `Core::UI.warn` → `$stderr.puts`) re-enter `record_line` through `$stderr` — which IS the TeeIO — recursively locking `@buffer_mutex` on the same thread. The `ThreadError: deadlock; recursive locking` is raised inside `safe_append`'s rescue clause, so it escapes it: into the wrapped command (shape 1 — a logging failure alters the build) or out of `flush_partial_buffers` inside `finish`'s ensure, masking the in-flight exception (shape 2). The 534/0 suite missed it because the degradation spec exercised `record_text` directly with no tee installed — the one shape that cannot deadlock.

**Summary:**
- Findings in scope: 1 (CR-05)
- Addressed: 1 — Resolved (fixed): 1 — Deferred / rejected: 0
- Cumulative across both iterations: findings_in_scope 10, resolved 10
- Final gate: `bundle exec rspec` — **536 examples, 0 failures** (534 + 2 net-new)

### CR-05: re-entrancy deadlock — an append failure while the tee is installed raises ThreadError into the command (or replaces the in-flight error from finish)

**Resolution:** fixed
**Rationale:** Chose the review's re-entrancy-guard shape, placed at the `record_line` chokepoint rather than in `TeeIO#write`: once `@disabled` is set, `record_line` returns before touching `@buffer_mutex`, so every path back into the log (TeeIO write and any future caller) is guarded and the tee stays dumb. The guard is reliable on exactly the degradation path because `safe_append` sets `@disabled = true` BEFORE `warn_once` — the ordering is now documented in the source. Post-disable `record_text` no-ops anyway, so a racing writer loses nothing; the terminal leg (`real_io.write`) always runs first and stays live (SC3). The review's alternatives were considered and rejected as broader, not safer: routing `warn_once` to a pre-tee stderr captured at open moves all degradation warnings off `Core::UI` and buys nothing the guard does not; moving append work outside the mutex widens the WR-01 race window the mutex exists to close. The reviewer's blind-spot note is addressed: the `safety degradation` describe now covers the tee-installed shape (the pre-existing no-tee `record_text` spec remains as the control — the review repro's third line).
**Commits:** `4e83d0a` (test, RED — both shapes failed with exactly `ThreadError: deadlock; recursive locking`, matching the review's repro line-for-line), `450a7d2` (fix, GREEN)
**Spec coverage:** `spec/run_log_spec.rb` "safety degradation" — shape 1: tee on `$stderr`, `@file` closed, `puts` through the tee → no raise, the terminal line lands on the real leg, the warning lands once on the real leg, nothing is appended after disable; shape 2: a buffered partial line fails to append inside `finish`'s flush → the in-flight `RuntimeError` propagates (no `ThreadError` from the ensure) and the warning lands on the real leg.

### Verification (iteration 2)

- RED verified failing on HEAD before the fix commit: both new specs failed with `ThreadError: deadlock; recursive locking`.
- GREEN: `spec/run_log_spec.rb` 36/0; full suite (main checkout, after the fix): `bundle exec rspec` → **536 examples, 0 failures**.
- RuboCop delta vs `8125ff7` (advisory posture per iteration 1): `run_log.rb` — 11 → 11 offenses, pure line shifts, zero net-new. `run_log_spec.rb` — every pre-existing site shifts 1:1 (+48 lines); exactly ONE net-new advisory `Metrics/BlockLength` site (the `safety degradation` describe grew 21 → 56 lines), the same cop the file already violates at five committed sites including the whole-file block (346 → 381/25). No style/layout offenses introduced; the repo does not gate on Metrics cops.

---

_Fixed: 2026-08-31T19:19:50Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 2_
