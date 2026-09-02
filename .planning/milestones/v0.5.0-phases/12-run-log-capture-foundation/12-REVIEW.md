---
phase: 12-run-log-capture-foundation
reviewed: 2026-08-31T19:27:06Z
depth: deep
iteration: 3
files_reviewed: 23
files_reviewed_list:
  - lib/spm_cache/assets/templates/spm-cache.yml.template
  - lib/spm_cache/command.rb
  - lib/spm_cache/command/base.rb
  - lib/spm_cache/command/init.rb
  - lib/spm_cache/command/pkg/build.rb
  - lib/spm_cache/command/watch.rb
  - lib/spm_cache/core/config.rb
  - lib/spm_cache/core/run_log.rb
  - lib/spm_cache/core/sh.rb
  - lib/spm_cache/installer/build.rb
  - lib/spm_cache/installer/use.rb
  - lib/spm_cache/main.rb
  - lib/spm_cache/spm/build.rb
  - lib/spm_cache/spm/build_pipeline.rb
  - spec/build_pipeline_spec.rb
  - spec/config_spec.rb
  - spec/init_spec.rb
  - spec/installer_build_spec.rb
  - spec/installer_use_fast_path_spec.rb
  - spec/main_run_log_spec.rb
  - spec/run_log_spec.rb
  - spec/sh_run_log_sink_spec.rb
  - spec/watch_spec.rb
findings:
  critical: 0
  warning: 0
  info: 0
  total: 0
status: clean
---

# Phase 12: Code Review Report (Final Convergence Re-review, Iteration 3)

**Reviewed:** 2026-08-31T19:27:06Z
**Depth:** deep
**Files Reviewed:** 23
**Status:** clean

## Summary

Final convergence check of the same 23 files after the iteration-2 CR-05 fix (commits `4e83d0a` test-RED / `450a7d2` fix-GREEN, per `12-REVIEW-FIX.md`). Zero new critical or warning findings. **All 10 cumulative fixes verified as holding under independent adversarial re-tracing; the CR-05 re-entrancy guard introduced no new defect.** Scoped proof run in this review: `bundle exec rspec spec/run_log_spec.rb spec/sh_run_log_sink_spec.rb spec/main_run_log_spec.rb spec/watch_spec.rb` → **87 examples, 0 failures** (fixer's full-suite gate: 536 examples, 0 failures).

**CR-05 fix HOLDS.** Verified by tracing every path that can re-enter the log while a lock is held:

- **Guard placement** (`run_log.rb:216-226`): `record_line`'s `return if @disabled` (line 226) precedes `@buffer_mutex.synchronize` (line 228). Any re-entry through the tee — the only re-entrant channel, via `Core::UI.warn` → `$stderr.puts` → `TeeIO#write` (`log.rb:15-17`, `run_log.rb:425-429`) — returns before touching the buffer mutex, so the recursive `ThreadError: deadlock` from CR-05 is structurally unreachable.
- **Guard reliability** (`run_log.rb:364-374`): `safe_append` sets `@disabled = true` (line 371) **before** `warn_once` (line 372), so on exactly the degradation path the re-entrant `record_line` already sees the flag. The guard is the chokepoint shape (inside `record_line`, not `TeeIO#write`), which also covers `StreamSink` and any future caller; the fixer's stated alternative (guard in `TeeIO`) would not have.
- **Degradation semantics intact**: the warning still lands exactly once on the REAL terminal leg — `TeeIO#write` writes `@real_io` first (SC3 write-through), then the log leg no-ops; without a tee the warning goes straight to real stderr. Both shapes are pinned by specs: shape 1 asserts the terminal line AND the `[warn] run log disabled` line on the real leg with the file header-only afterwards (`run_log_spec.rb:254-272`); shape 2 proves a flush failure inside `finish`'s ensure propagates the in-flight `RuntimeError`, never a `ThreadError` (`run_log_spec.rb:274-291`).
- **Buffers still flushed in `finish`**: `flush_partial_buffers` runs at `finish` entry under the same `@buffer_mutex` (`run_log.rb:346-356`); post-disable it drains leftovers through `safe_append`'s `return if @disabled` — silent drop is the documented degradation posture, and `record_line`'s early return prevents any post-disable buffer growth.
- **No new deadlock/livelock**: lock order is strictly `@buffer_mutex` → `@mutex` (record_line:228→record_text→safe_append:365; flush_partial_buffers:347→same); nothing acquires them in reverse; `warn_once` fires after `@mutex` has unwound (method-level rescue). The unsynchronized `@disabled` read at line 226 is a benign flag race: worst case is a dropped body line on the already-degraded path or a no-op append — never corruption, never a raise.
- **Foreign-pid protection intact** (`run_log.rb:407-409`): `protected_run?` still requires `Integer && != Process.pid && pid_alive?`; the CR-03 same-pid prune and the live-foreign-pid survival spec (`run_log_spec.rb:354-384, 386-398`) are unchanged.

### Prior-fix seam spot-checks — all 8 HOLD

| Fix | Seam re-verified | Evidence |
|-----|------------------|----------|
| CR-01 scrub | `record_text` scrubs (`to_s.scrub`) and JSON-generates inside `safe_append`'s block; `event` scrubs String fields via `transform_values`, keeps `status` typed (`run_log.rb:231-256`) | `run_log_spec.rb:101-123`; real `printf '\xff\xfe'` through the sink path (`sh_run_log_sink_spec.rb:120-127`) |
| CR-02 `--log-dir` routing | `pre_scan` routes the `=` form in ANY position, consumes the two-token form without routing; `Main.run` uses `scan.log_dir`; `Watch` passes CLAide-parsed `@log_dir` into the wrapper (`run_log.rb:78-98`, `main.rb:21`, `watch.rb:44-47`) | truth-table rows (`run_log_spec.rb:480-509`), post-verb routing through real `Main.run` (`main_run_log_spec.rb:232+`), watch surface (`watch_spec.rb:306-341`) |
| CR-03 same-pid prune | `protected_run?` foreign-live-pid-only; watch session bounded (`run_log.rb:407-409`) | `run_log_spec.rb:386-398` (third cycle bounds the first), 354-384 (foreign live survives, dead pruned, current immune) |
| CR-04 cycle `--no-run-log` | `CycleWrapper#perform_install` short-circuits on `scan.suppressed?` before any `RunLog.open` (`run_log.rb:496-503`) | zero cycle files both flag positions, `.spm-cache` never created (`watch_spec.rb:345-365`) |
| WR-01 buffer mutex success paths | append + extraction + same-stream order under `@buffer_mutex` in both `record_line` and `flush_partial_buffers` (`run_log.rb:228-233, 346-356`) | 2 writers × 50 chunk pairs → 100 intact lines (`run_log_spec.rb:199-217`) |
| WR-02 argv redaction | header redacted via `CREDENTIAL_PATTERN`, `redacted` flag recorded, body verbatim (`run_log.rb:35-38, 118-152`) | `run_log_spec.rb:59-79` (residual boundary gaps remain IN-08, below) |
| WR-03 popen3 full return | `out_buf`/`err_buf` full accumulation; returns `{ output:, error:, status: wait_thr.value.exitstatus }` (`sh.rb:44-70`) | 120-line subprocess → 120 lines with real status (`sh_run_log_sink_spec.rb:102-110`) |
| WR-04 `full_output` on raise | attached on BOTH `Sh.run` branches (`sh.rb:53-56, 66-68`); `GeneralError#full_output` accessor (`error.rb`); retry matches `e.message` OR `e.full_output` (`build.rb:97-103`) | runtime-assembled `printf` marker spec (`core_spec`), retry-fires-on-`full_output`-only (`buildable_spec`) |

Also re-checked without finding regressions: WR-05's `read_resolved_pins` posture (partial-but-consumable seed, `.gitignore` reached), D-04 event seams (`emit_run_log_event` nil-guard + rescue-to-warn; phase markers before the empty-set early return), the retention budget coercion (`rescue ArgumentError, TypeError → default`), the header atomicity pattern (Tempfile + rename), and the template/DEFAULT_CONFIG key parity.

## Carried Info (out of fix scope — noted, NOT fixed)

Per the fix-scope contract, the three prior INFO findings from iteration 2 remain open and untouched; none escalated during this pass:

- **IN-08** — `CREDENTIAL_PATTERN` misses literal-`/` passwords and empty-user `:token@` forms (WR-02 residual; `run_log.rb:35`). Phase-14 renderers should treat the header as best-effort-redacted.
- **IN-09** — full-argv scan routes `--log-dir=X` after the `--` separator, producing an orphan override log for argv CLAide rejects anyway (`run_log.rb:84-93` + `main.rb`).
- **IN-10** — `-derivedDataPath #{dd}` unquoted in `build_command`, contradicting the neighboring quoting comment (`build.rb`); pre-existing.

Iteration-1's IN-01..IN-07 likewise remain carried and unchanged (including IN-04: `close` still lacks the degradation wrapper — unreachable in practice today because `@file.closed?` guards the only realistic raise, but it is the same class of gap CR-05 demonstrated at `finish`).

None of these blocks convergence; they are catalogued for a future cosmetic/hardening pass.

## Critical Issues

None.

## Warnings

None.

## Info

None new. (The three carried INFO items above are prior findings deliberately left out of fix scope — see `12-REVIEW-FIX.md` and the iteration-2 review.)

---

_Reviewed: 2026-08-31T19:27:06Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep (iteration 3 — final convergence re-review)_
