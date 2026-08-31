---
phase: 12-run-log-capture-foundation
reviewed: 2026-08-31T18:18:28Z
depth: deep
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
  critical: 4
  warning: 5
  info: 7
  total: 16
status: issues_found
---

# Phase 12: Code Review Report

**Reviewed:** 2026-08-31T18:18:28Z
**Depth:** deep
**Files Reviewed:** 23
**Status:** issues_found

## Summary

The run-log capture foundation (RunLog JSONL writer, Main.run tee, Sh popen3 sinks, retention pruning, D-04 events, watch per-cycle logs) is well-layered and the safe_append degradation design is sound, but adversarial probing found four shipping blockers, all reproduced end-to-end against the real CLI:

1. **One invalid-UTF-8 byte from xcodebuild kills the build.** `record_text` runs `JSON.generate` *before* `safe_append`'s rescue, so `JSON::GeneratorError` escapes the reader thread, `Thread#join` re-raises it into `Sh.run`, and the wrapped command fails — the exact failure mode LOGS-01 forbids ("logging must never mask, fail, or alter the operation").
2. **`--log-dir` works in only 1 of 4 real argument positions.** `pre_scan` stops scanning at the verb, so every post-verb form silently misroutes to the default dir (watch is always post-verb — its override is fully dead), and the documented two-token pre-verb form is rejected by CLAide after a run log has already been written into the override dir.
3. **Retention cannot bound a watch session.** Every prior cycle file carries the watch process's own (still-alive) pid, so `live_pid?` protects all of them; disk growth is unbounded intra-session, contradicting the code's own T-12-04 invariant.
4. **`watch --no-run-log` still writes cycle logs** — D-03's explicit opt-out is a silent no-op on the watch surface.

The 519/0 suite cannot catch these because the specs exercise `pre_scan`/`cycle_wrapper` with flags placed *before* the verb (the only position that works), stub `Command.run` (bypassing CLAide's rejection of the two-token form), and only feed valid UTF-8 through the sinks. Per-file analysis also surfaced 5 warnings and 7 info items.

## Critical Issues

### CR-01: Invalid UTF-8 in subprocess output raises outside safe_append, killing the reader thread and failing the build

**File:** `lib/spm_cache/core/run_log.rb:189-191` (with `lib/spm_cache/core/sh.rb:36-45` and `lib/spm_cache/core/run_log.rb:419-421`)
**Issue:** `record_text` evaluates `JSON.generate(...)` as the *argument* to `safe_append`, so generation happens outside safe_append's `rescue StandardError` degradation. The JSON gem raises `JSON::GeneratorError` ("source sequence is illegal/malformed utf-8") on invalid UTF-8 — and xcodebuild/compiler output is exactly where arbitrary bytes appear. Reproduced live: a single `\xFF\xFE` pair in a subprocess's stdout (a) killed the `Sh` reader thread mid-stream (dropping every subsequent captured line, violating D-05), (b) was re-raised into the main thread by `threads.each(&:join)` (`Thread#join` re-raises a dead thread's exception), so the second reader never joined and `Sh.run` raised `JSON::GeneratorError` into `Buildable#xcodebuild`, whose `rescue GeneralError` doesn't catch it — the build fails because of a logging bug. The same escape applies to `#event` (run_log.rb:203-205) for any field carrying hostile bytes. This is a direct violation of LOGS-01's core guarantee ("a logging failure can never mask the capture's own result") and of D-04's guard design in `emit_run_log_event`.
**Fix:**
```ruby
def record_text(text, stream)
  safe_append(JSON.generate('ts' => ..., 'stream' => stream, 'text' => text.to_s.scrub))
end

def event(name, **fields)
  safe_append(JSON.generate({ 'event' => name, 'ts' => ... }.merge(fields) { |_k, v| v.respond_to?(:to_s) ? v.to_s.scrub : v }))
end
```
Scrubbing replaces only invalid byte sequences (the log stays a valid JSONL document and never aborts a build); keep the generation *inside* the guarded region as defense-in-depth.

### CR-02: `--log-dir` (D-01) silently misroutes in every position except `--log-dir=X` before the verb

**File:** `lib/spm_cache/core/run_log.rb:72-88` (loop `break`s at line 81); also `lib/spm_cache/main.rb:19-24`, `lib/spm_cache/command/watch.rb:44-46`, `lib/spm_cache/core/run_log.rb:446-453`
**Issue:** `pre_scan` `break`s at the first non-flag token, so `--log-dir` appearing after the verb is never seen. Verified end-to-end against the real CLI:
- `spm-cache watch --log-dir=/tmp/x --once` → cycle file written to the **default** `.spm-cache/runs`, override dir never created, no warning. Since `watch` always precedes its flags, the watch override (D-01 at the watch surface, explicitly promised by the CycleWrapper comment "must not silently write cycles to the default runs dir") is **entirely non-functional**.
- `spm-cache use --log-dir=X` → CLAide accepts it, but the run log lands in the default dir. Silent misroute.
- `spm-cache --log-dir X use` (the documented two-token form, covered by the spec truth table) → `pre_scan` honors it and **writes a run log into the override dir**, then CLAide rejects the argv ("Unknown option: \`--log-dir\` / Did you mean: --log-dir=DIR?") and exits 1 — an orphan log plus a Help failure.
Only `--log-dir=X` *before* the verb works. The specs mask this: they test `pre_scan` with `['--log-dir', x, 'watch']` and stub `Command.run`, so CLAide's rejection and the post-verb positions are never exercised.
**Fix:** stop `break`ing at the verb — record the first non-flag token as the verb but keep scanning the remainder for `--log-dir`/`--log-dir=` (the `suppressed?` check already scans the whole argv via `include?`; make `log_dir` consistent with it). For watch, additionally pass the already-parsed `@log_dir` from `Command::Watch` into the factory so the wrapper doesn't depend on raw-argv scanning at all. Align the spec fixtures with the real argv order (`['watch', '--log-dir', x, ...]`).

### CR-03: Retention prune never bounds a watch session — every prior cycle file is protected by its own process's live pid

**File:** `lib/spm_cache/core/run_log.rb:249-271` (`prune`), `324-339` (`live_pid?`), `446-453` (CycleWrapper open)
**Issue:** Cycle files' `run_start` header carries the watch daemon's pid (`Process.pid` inside the same process). `prune` skips any candidate whose header pid is alive, so while a watch session runs, **every** completed cycle file is "live" and exempt; the count+size budgets delete nothing until the process exits. A long watch session (cycles every few seconds-to-minutes, each capturing multi-MB xcodebuild output with `sync = true`) grows `.spm-cache/runs` without bound — directly contradicting the invariant asserted at run_log.rb:445 ("T-12-04: a long watch session stays bounded"). Disk exhaustion then trips safe_append's degradation and disables capture mid-session, and ENOSPC can break the user's builds.
**Fix:** liveness protection exists for *concurrent* runs (Pitfall 6); a same-pid prior cycle is by construction finished (its `run_end` is written in `finish`), and the active file is already excluded by identity. Make the guard:
```ruby
next if pid != Process.pid && live_pid?(candidate)
```
(extracting `run_start_pid(candidate)` once), or mark finished cycle files with a `run_end`-presence check before falling back to pid liveness. Add a spec for "third cycle of the same process prunes the first".

### CR-04: `watch --no-run-log` still writes cycle run logs (D-03 is a no-op on the watch surface)

**File:** `lib/spm_cache/core/run_log.rb:439-453`
**Issue:** `CycleWrapper#perform_install` re-scans `@argv` but never consults `scan.suppressed?`; it opens and tees a cycle log regardless. Reproduced: `spm-cache watch --no-run-log --once` exits and leaves a populated `.spm-cache/runs/*-watch.jsonl` (run_start with full argv, teed output, run_end). The user's explicit opt-out is silently ignored — Main honors it (no main log) while the cycle layer defeats it. Privacy/consent defect: the flag's entire purpose is "persist nothing for this invocation".
**Fix:**
```ruby
scan = RunLog.pre_scan(@argv)
return @installer.perform_install if scan.suppressed?
```
and add a watch_spec row for `argv: ['--no-run-log', 'watch']` producing zero files.

## Warnings

### WR-01: TeeIO partial-line buffering is not thread-safe; safe_append's mutex does not cover it

**File:** `lib/spm_cache/core/run_log.rb:178-186` (`record_line`), `363-367` (`TeeIO#write`)
**Issue:** `record_line` performs an unsynchronized read-modify-write on `@buffers[stream]` plus `String#<<` and in-place `slice!`. `safe_append`'s mutex only serializes the final write. Today only the main thread writes through the tee (Sh reader threads use `StreamSink`), so the race is latent — but the class is explicitly designed for a multi-threaded logging world, and the concurrency spec only exercises `record_text` (the mutexed path), never `record_line`. The first future caller that prints from a thread (e.g. parallel hooks) gets interleaved/lost body lines or corrupted buffer strings.
**Fix:** wrap the buffer append/extract loop in `@buffers`-keyed synchronization (a single `@buffer_mutex` is sufficient), or route `record_line` through the same `@mutex` for the buffer manipulation and keep `safe_append` nested (it is reentrancy-safe only because the outer block releases before warn paths — restructure deliberately, don't stack two locks blindly).

### WR-02: Run logs persist full argv verbatim — no secrets redaction

**File:** `lib/spm_cache/core/run_log.rb:105-117` (header write), `lib/spm_cache/main.rb:22-27`
**Issue:** The `run_start` header records `argv` unredacted. Real invocations carry `--remote-url https://user:token@github.com/...` (embedded PATs are common for private SPM deps) and `--creds <path>`. The runs dir is gitignored (T-12-05), but the token lands in a long-lived plaintext JSONL on disk, replicated into every Phase-14 reconstruction surface. For a capture foundation whose contract is "verbatim forever" (D-05), now is the cheapest point to add a redaction seam.
**Fix:** redact credential-bearing components of option values at open time (e.g. scrub `scheme://user:password@host` → `scheme://user:[REDACTED]@host`, and known secret-flag values), keeping a `redacted: true` marker so renderers know the header is not byte-faithful.

### WR-03: popen3 branch returns 60-line tails and hardcoded `status: 0`, diverging from the capture3 contract

**File:** `lib/spm_cache/core/sh.rb:58`
**Issue:** The sink path returns `{ output: out_tail.join, error: err_tail.join, status: 0 }` where the capture3 path returns the *full* streams and the real exitstatus. `sh_run_log_sink_spec.rb` even enshrines the truncation ("returns the tailed output/error strings"). No current caller consumes the sink-path result (`Buildable#xcodebuild` returns `dd`), but the next caller to trust `result[:output]` gets silently-clipped data, and `status: 0` masks any non-zero success (rare but real: `xcodebuild ... | grep`-style pipelines). Pre-phase this returned `{ output: "", status: 0 }`, so nothing regressed — but the phase is codifying a trap.
**Fix:** accumulate full lines in a capped-memory-safe way for the return value (or return `output: ""` as before) and derive `status` from `wait_thr.value.exitstatus` instead of the literal 0.

### WR-04: Low-deployment-target retry now depends on the error surviving the 60-line failure_detail tail

**File:** `lib/spm_cache/spm/build.rb:97-101` with `lib/spm_cache/core/sh.rb:23-58`
**Issue:** `xcodebuild` retries when `e.message.match?(LOW_DEPLOYMENT_TARGET_ERROR_PATTERN)`. On any logged run (the default), the popen3 branch's message carries only the last 60 lines *per stream*; pre-phase, the capture3 path matched against the full output. If the "is only available in iOS X or newer" / libarclite diagnostic scrolls past the tail (large parallel builds can print hundreds of post-failure lines), the functional recovery silently stops firing — build outcomes now differ between `--no-run-log` and logged runs.
**Fix:** match the pattern against the full streamed content (e.g. set a boolean flag when any reader line matches, instead of re-matching the truncated message), or raise with an untruncated (but still size-capped, e.g. 4 KiB) detail blob.

### WR-05: init's lockfile seed crashes on non-object `pins` entries — outside the guard that promises not to crash

**File:** `lib/spm_cache/command/init.rb:163-181`
**Issue:** The `begin/rescue JSON::ParserError, TypeError` covers only `JSON.parse` and the top-level shape check. The `pins.map` at line 175 runs *after* that block: a valid-JSON `Package.resolved` whose `pins` array contains a non-object (`"pins": ["Alamofire"]` or `[["x"]]`) raises `TypeError`/`NoMethodError` (`String#[]`, `String#dig`), aborting init after the yml is written but before the lockfile and `.gitignore` entries — precisely the "must not abort init mid-run" scenario the guard comment enumerates.
**Fix:** filter/map defensively: `pins = data['pins'].select { |p| p.is_a?(Hash) }` (warn on dropped entries), or move the mapping inside the guarded region.

## Info

### IN-01: `pre_scan` collapses nested subcommands and can misdetect flag values as verbs

**File:** `lib/spm_cache/core/run_log.rb:72-87`
**Issue:** `pkg build X` logs `command: "pkg"` (filename + header lose the actual subcommand; spec-enshrined). Also, for argv shapes CLAide rejects anyway (`--config release build`), the value token becomes the verb, leaving a misnamed orphan log file.
**Fix:** record the first *two* non-flag tokens when the first matches a known group (`pkg`, `cache`, `remote`), or accept the collapse but document it in the header contract.

### IN-02: `runs_max_mb <= 0` (negative) deletes the entire history, ignoring `runs_keep`

**File:** `lib/spm_cache/core/run_log.rb:256` with `lib/spm_cache/core/config.rb` (runs_max_mb)
**Issue:** The break condition can never hold for a negative total budget, so the loop deletes every non-live candidate and `keep` is never consulted. Zero is arguably a valid "keep nothing" setting; a typo'd negative silently wipes all logs at next run.
**Fix:** clamp (`[budget, 0].max` or reject negatives in `runs_max_mb`).

### IN-03: `package_end` can precede the failed build's final output lines on Interrupt

**File:** `lib/spm_cache/spm/build_pipeline.rb:106-112` with `lib/spm_cache/core/sh.rb:34-52`
**Issue:** On SIGINT the main thread exits the popen3 block while reader threads may still hold unsunk lines; the ensure's `package_end` is written before those lines land, so the bracket close can precede trailing subprocess text in the file (lines remain parseable; ordering guarantee is soft exactly where the bracket matters most). Dead reader threads also emit `report_on_exception` noise.
**Fix:** on the interrupt path, drain/join readers with a short timeout before emitting the close bracket (best-effort, still inside the ensure).

### IN-04: `finish`/`close` lack the degradation wrapper; an IO error there would replace the in-flight exception

**File:** `lib/spm_cache/core/run_log.rb:219-236`
**Issue:** `flush_partial_buffers` and `event` are protected via safe_append, but `close`'s `@file.flush`/`@file.close` are not. Called from `Main.run`'s `ensure`, a raise would substitute the close error for the command's real exception (Pitfall 2 adjacent). Low likelihood (`sync = true` makes flush a no-op), but the class's own rule is "never raise into the caller".
**Fix:** rescue around `close` and fall back to `warn_once`.

### IN-05: Unquoted shell interpolation of the build output path

**File:** `lib/spm_cache/command/pkg/build.rb:63`
**Issue:** `` `du -sh #{result}` `` interpolates a user-influenced path into a shell string (breaks on spaces; metacharacters execute). Self-inflicted-only (own argv), pre-existing line reformatted by this phase.
**Fix:** `Open3.capture3('du', '-sh', result)` or `Shellwords.escape`.

### IN-06: `run_log.rb` references `Core::UI`/`Config` without requiring them

**File:** `lib/spm_cache/core/run_log.rb:144,148` (and `warn_once`)
**Issue:** Standalone `require "spm_cache/core/run_log"` fails with NameError inside `open`'s own rescue handler — correctness of the *degradation path* depends on `Main.load_all`'s sorted glob happening to load `config.rb`/`log.rb` first. Any future file split or eager-require change silently breaks the failure handling.
**Fix:** add `require 'spm_cache/core/config'` / `require 'spm_cache/core/log'` at the top of run_log.rb.

### IN-07: `--log-dir=` (empty value) silently disables logging

**File:** `lib/spm_cache/core/run_log.rb:73-75,101`
**Issue:** `scan.log_dir` becomes `""` (truthy in Ruby, so it wins the `||`), `FileUtils.mkdir_p("")` raises `Errno::ENOENT`, and `open` degrades to disabled-with-warning. Behavior is safe but the warning ("could not open run log in : No such file or directory") obscures the cause.
**Fix:** treat an empty override as absent in `pre_scan` (`log_dir = nil if log_dir.to_s.empty?`).

---

_Reviewed: 2026-08-31T18:18:28Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep_
