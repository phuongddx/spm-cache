---
phase: 12-run-log-capture-foundation
verified: 2026-09-01T00:00:00Z
status: passed
score: 28/28 must-have truths verified
behavior_unverified: 0 # No PRESENT_BEHAVIOR_UNVERIFIED truths — every behavior-dependent truth has a passing named spec in the suite run below
overrides_applied: 1 # CR-02 --log-dir two-token deviation ACCEPTED by user 2026-09-01 (in-session; see human_verification item 3 resolution below)
re_verification:
  previous_status: none
  previous_score: none
  gaps_closed: []
  gaps_remaining: []
  regressions: []
  note: "Initial verification — no prior VERIFICATION.md existed (Step 0 confirmed empty)."
human_verification:

  - test: "Real-TTY terminal byte-parity (SC3 manual-only item from 12-VALIDATION.md): run `spm-cache use` (or a failing `spm-cache build`) on the reference project with and without `--no-run-log` and diff the terminal transcripts and exit codes."
    expected: "Transcripts and exit codes identical. Hermetic StringIO byte-parity and exit-shape specs are green, and TeeIO delegates tty?/isatty/sync/flush write-through — but a real TTY's buffering/isatty interplay is the one surface no automated spec exercises (12-VALIDATION.md lists it manual-only)."
    why_human: "Visual byte-parity across a real TTY is not automatable hermetically; specs capture via StringIO."
  - test: "Judgment-tier prohibition — confirm no secrets land in run logs (unverified-prohibition — human review recommended)."
    expected: "argv-only capture (no env vars anywhere: grep ENV over run_log.rb/sh.rb/main.rb returns zero matches), header credential redaction active (WR-02 specs green). Non-authoritative LLM-judge verdict recorded: SUBSTANTIALLY HONORED, with documented residual IN-08 (CREDENTIAL_PATTERN misses literal-`/` passwords and empty-user `:token@` forms — 12-REVIEW.md carried Info)."
    why_human: "verification: judgment prohibitions cannot be closed by an autonomous verifier; the flag must never be a silent pass."
  - test: "Accept or reject the CR-02 deviation from the plan-literal '--log-dir X' two-token routing (override suggestion below)."
    expected: "If accepted, record the override in this file's frontmatter (accepted_by/accepted_at). The deviation is live-verified correct this session: CLAide rejects the two-token form in both positions ('Unknown option: `--log-dir` / Did you mean: --log-dir=DIR?'), so the implemented semantics (= form routed anywhere; two-token form consumed-but-not-routed to avoid orphan logs for invocations CLAide rejects) is the only coherent D-01 behavior and is spec-pinned (run_log_spec.rb:490-507)."
    why_human: "Plan truth 12-01 #5 literally promised both forms; the two-token half is unimplementable as written (CLAide parity). A human accepts the documented deviation."
    resolution: ACCEPTED in-session 2026-09-01 — user selected "Accept deviation" during execute-phase handoff; = form routes in any position, two-token form consumed-but-not-routed (spec-pinned run_log_spec.rb:490-507).
gaps: [] # status is human_needed, not gaps_found — no truth FAILED, no artifact MISSING/STUB, no link NOT_WIRED, no blocker anti-pattern
deferred: [] # No later-phase overlap: LOGS-02..05 build ON this phase, none restate its scope
coincidental_reliance_items: [] # Advisory #1955 check: every VERIFIED truth's evidence is spec-driven through the real production seams (real open→prune, real echo subprocesses, real Main.run harness) — no undeclared-precondition / incidental-ordering / fixture-only reliance identified
---

# Phase 12: Run-Log Capture Foundation Verification Report

**Phase Goal:** Every CLI run (build/use/watch) leaves a complete, queryable run log on disk — the keystone every streaming feature consumes — without changing terminal behavior
**Verified:** 2026-09-01
**Status:** human_needed (all 28 truths verified against live code; 3 human confirmation items — real-TTY byte-parity, judgment-tier prohibition, CR-02 deviation acceptance)
**Re-verification:** No — initial verification

## Goal Achievement

Verification basis: LIVE CODE + LIVE RUNS, not SUMMARY claims. Full suite executed once this session:
`bundle exec rspec` → **536 examples, 0 failures, exit 0** (44.75s). CLAide `--log-dir` acceptance probed
live. git history probed for the Watcher-untouched claim.

### Observable Truths

Merged must-haves: ROADMAP SC1–SC4 (non-negotiable contract) + deduplicated plan truths 12-01..12-05.

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | SC1: build/use/watch leave a JSONL run log under the project run dir (outside the sandbox) with header (command, argv, pid, started_at), timestamped stream-tagged body, exit line | ✓ VERIFIED | `Config#runs_dir` = `<project>/.spm-cache/runs` (config.rb:107-112, outside `sandbox_dir` — D-02/Pitfall 7 comment); `Main.run` opens + tees + finishes (main.rb:19-53); `main_run_log_spec.rb:94-133` asserts every header field incl. pid/started_at/spm_cache_version/trigger, filename shape, 4-line file; watch cycle shape in truth 25. Suite green. |
| 2 | SC2: log body captures what the terminal showed — including a failing build's error lines and spawned xcodebuild/swift subprocess output — full run reconstructable offline | ✓ VERIFIED | TeeIO body verbatim incl. ANSI (`main_run_log_spec.rb:127`); Sh popen3 per-stream sinks through REAL echo subprocesses (`sh_run_log_sink_spec.rb:73-77`); failure_detail tails restored with runtime-assembled printf markers that cannot pass vacuously (`sh_run_log_sink_spec.rb:45-69`); pipeline threads run_log → Buildable → StreamSinks (`build_pipeline_spec.rb:1199+`); package/phase structure (truths 19/21). |
| 3 | SC3: terminal output and exit codes unchanged by capture; `spm-cache web` never writes a run log | ✓ VERIFIED (hermetic) | Byte-parity vs `--no-run-log` baseline (`main_run_log_spec.rb:137+`); exit-shape specs re-raise untouched (`:156-186`); web exclusion (`:219`); TeeIO delegation + write-through-first (`run_log_spec.rb:513`, run_log.rb:436-440); pre-existing 441-example suite green = regression net. Real-TTY residual → Human Verification item 1. |
| 4 | SC4: repeated runs accumulate logs without unbounded growth (retention caps old runs) | ✓ VERIFIED | `RunLog#prune` (run_log.rb:316-347) called from `.open` after header lands (run_log.rb:154-158); retention group: count bound, size bound, oldest-first survivor set, current-run immunity at zero budgets, live-pid immunity + dead-pid pruned, CR-03 same-pid bound, under-budget no-op, undeletable-skip degradation (`run_log_spec.rb:302-426`). T-12-04 disposed. |
| 5 | Exit-status parity across the three CLAide leak shapes (SystemExit→e.status, Interrupt→130, StandardError→exit_status or 1, normal→0); every shape re-raises bare | ✓ VERIFIED | main.rb:37-47; specs `main_run_log_spec.rb:156-186` (4 shapes, each asserts propagation + recorded status). |
| 6 | EDGE empty: zero-output run → valid two-line JSONL, every line parses | ✓ VERIFIED | Real-failure `use` in empty dir leaves run_start + run_end status 1 and raises exactly as today (`main_run_log_spec.rb:190-209`). |
| 7 | EDGE adjacency: two opens → two distinct files; concurrent appends never interleave inside a JSON line | ✓ VERIFIED | `run_log_spec.rb:164-217`: distinct paths (ms+pid+collision suffix), 200-line two-thread interleave all-valid-JSON, WR-01 partial-chunk coherence under concurrent writers. |
| 8 | Safety degradation: open/append failure degrades to unlogged-with-single-warning, never raises into the wrapped command | ✓ VERIFIED | safe_append sets `@disabled` before warn_once (run_log.rb:364-374); CR-05 re-entrancy guard in record_line (run_log.rb:216-226); specs: unwritable dir → nil + one warning, forced append failure, CR-05 shapes 1 & 2 (`run_log_spec.rb:221-299`). |
| 9 | D-01: `--log-dir` overrides the run dir, pre-scanned from raw argv before CLAide parses | ✓ VERIFIED (documented deviation — CR-02) | `=` form routed in ANY position, pre- and post-verb, through the real `Main.run` (`main_run_log_spec.rb:233-244`) and at the watch surface (`watch_spec.rb:327+`); pre_scan truth table (`run_log_spec.rb:480-507`). **Deviation:** the plan-literal two-token `--log-dir X` routing was consciously dropped — CLAide rejects that form in every position (live-probed this session: `CLAide::Help: Unknown option: --log-dir / Did you mean: --log-dir=DIR?`), so routing it would orphan logs for invocations that never run. Override suggestion below. |
| 10 | D-08 no-allowlist: exactly {web, watch} verbs + `--no-run-log` flag excluded; every other verb (incl. future verbs) logs; A6: `use --watch` is one session-level use run | ✓ VERIFIED | Exclusion is a 2-verb set test, not membership (`run_log_spec.rb:449-453` future-verb row `frobnicate`); full real-verb row (`:431-446`); A6 row (`:466-477`); `--no-run-log` both positions (`:461-464`); Main-level no-file specs for web/watch/flag (`main_run_log_spec.rb:212-229`). |
| 11 | capture3 calls recorded as one `{event: sh, ts, cmd, status}` line when RunLog.current set; nothing + no crash when nil | ✓ VERIFIED | sh.rb:58-60 single `RunLog.current&.event('sh', ...)`; specs: success line + unchanged return, real exit status recorded before raise, nil → empty runs dir (`sh_run_log_sink_spec.rb:148-176`). |
| 12 | Nil-disables in Core::Sh: no sink opts → byte-identical legacy path | ✓ VERIFIED | sh.rb branch structure (out_sink/err_sink fall back to live_log, else capture3 unchanged); `spec/core_spec.rb` green in the 536-example run; legacy single-object back-compat spec (`sh_run_log_sink_spec.rb:130`). |
| 13 | D-05: full stream reaches the file; the 60-line bound applies only to the raised message/return, never the file | ✓ VERIFIED | Reader threads call sink for EVERY line (sh.rb:40-55); 100-line and 120-line full-fidelity specs (`sh_run_log_sink_spec.rb:82-109`). |
| 14 | EDGE ordering: pruning deletes strictly oldest-first lexicographic; spec names which fabricated files survive | ✓ VERIFIED | `prune` sorts `Dir.glob(*.jsonl)` ascending, walks oldest end (run_log.rb:317-318); survivor-set spec (`run_log_spec.rb:331-340`). |
| 15 | D-07: cleanup at run start AFTER the header lands; the just-opened run is never a prune candidate | ✓ VERIFIED | open → rename → `prune` (run_log.rb:151-158); current-file immunity at zero budgets proves exclusion-by-identity while the file exists (`run_log_spec.rb:343-351`). |
| 16 | Pitfall 6: live-pid foreign run never pruned even over budget; dead-pid is | ✓ VERIFIED | `protected_run?` = Integer && != Process.pid && alive (run_log.rb:407-409); hermetic live-child-pid spec (`run_log_spec.rb:354-384`); CR-03 same-pid prior cycle pruned (`:386-398`). |
| 17 | D-06 config: runs_keep/runs_max_mb flat snake_case, defaults 50/500, Integer() coercion with ArgumentError/TypeError rescue | ✓ VERIFIED | config.rb:118-135 + DEFAULT_CONFIG:23-24; default/override/coercion specs (`config_spec.rb:42-73`). |
| 18 | D-02: Init appends `.spm-cache/` to .gitignore, append-once, comment-labeled, idempotent on re-init | ✓ VERIFIED | init.rb `ensure_gitignore` → two independent append-once entries; anchored per-line regex asserts exactly-once for both entries after init AND re-init (substring trap handled), append-after-blank-line shape (`init_spec.rb:59-66, 200-220`). |
| 19 | package_start/package_end bracket every BuildPipeline.run at the single choke point; package_end status ok/failed | ✓ VERIFIED | build_pipeline.rb:68 + :110 (ensure-driven); both call sites thread `run_log: Core::RunLog.current` (installer/build.rb:175-188, command/pkg/build.rb:43-53); success bracket + failed-from-ensure-with-unchanged-re-raise specs (`build_pipeline_spec.rb:1199-1238`). |
| 20 | xcodebuild subprocess output reaches the run log via pipeline→Buildable→live_log_out/err StreamSinks | ✓ VERIFIED | spm/build.rb:89-93 constructs per-stream StreamSinks when opts[:run_log]; forwarding asserted with real echo through real Core::Sh into the file (`build_pipeline_spec.rb` run-log events group); threaded through perform_build/run_with_scheme (build_pipeline.rb:351, 384, 426). |
| 21 | D-04 phase markers (detect, integrate, build, fidelity) at existing branch boundaries | ✓ VERIFIED | use.rb:23-31 (detect after detect_diff; integrate once before branch); build.rb:53 (build before empty-set early return so zero-pins still records); build_pipeline.rb:92 (fidelity before report_fidelity); specs assert exact marker sequences on fast path, full path, and build (`installer_use_fast_path_spec.rb:296-337`, `installer_build_spec.rb:103-110`). |
| 22 | Nil-disables: every new kwarg/opt defaults nil; callers without a run log byte-identical | ✓ VERIFIED | `run_log: nil` defaults (build_pipeline.rb:58-59, 305, 403); `&.`-guarded markers; all pre-existing pipeline/installer/pkg specs green unmodified in the 536-example run. |
| 23 | EDGE empty (zero-pins): empty missed set → phase markers present, zero package_* lines | ✓ VERIFIED | `installer_build_spec.rb:124-133`: 'No targets to build' path emits `['build']` and no package events. |
| 24 | Never-fail guard: event emission degrades (warn), never fails or alters the build | ✓ VERIFIED | `emit_run_log_event` nil-return + rescue-to-warn (build_pipeline.rb:130-135), mirroring the report_fidelity convention. |
| 25 | SC1/D-09: watch daemon writes one complete run log per regeneration cycle; NO session-level file; cycle header command 'watch', trigger 'watch', cycle true, own argv/pid | ✓ VERIFIED | `CycleWrapper#perform_install` (run_log.rb:497-562): open(cycle: true) → tee → three-shape capture → ensure finish; wrapper unit asserts full cycle shape + stream/current restoration (`watch_spec.rb:204-243`), two-cycles-two-files (`:287+`), Main-level watch no-file (`main_run_log_spec.rb:226-228`). |
| 26 | SC3 watch: terminal behavior unchanged; mid-cycle Interrupt still lands the cycle's run_end before Watcher's rescue proceeds | ✓ VERIFIED | Write-through tee restored per cycle; Interrupt → status 130 + propagates (`watch_spec.rb:261+`); SystemExit(3) and GeneralError(1) shapes too (`:246-284`). |
| 27 | Core::Watcher untouched by this phase | ✓ VERIFIED | `git log -- lib/spm_cache/core/watcher.rb`: last commit `9ab76ea` (v0.4.0) — no Phase 12 commit touches it; capture rides only the injected installer_factory (watch.rb:35-48). |
| 28 | Inter-cycle watch narrative stays terminal-only (A5/D-09: no session file) | ✓ VERIFIED | `watch_spec.rb:367-429`: output written between cycles (no tee active) lands in no file; A5 example asserts emitted-but-unpersisted narrative. |

**Score:** 28/28 truths verified (0 present-but-behavior-unverified)

### Prohibitions (must-NOT checks)

| Statement | Tier | Status | Evidence |
|---|---|---|---|
| MUST NOT truncate/clip/mangle a run log to bound disk (D-05) — only whole-file retention pruning | test | ✓ VERIFIED | Full-stream specs (truth 13); prune unlinks whole `*.jsonl` candidates only, never rewrites (run_log.rb:316-347); header published atomically via Tempfile+rename. |
| MUST NOT alter terminal bytes, stream interleaving, or exit codes when capture is enabled (SC3) | test | ✓ VERIFIED (hermetic) | Byte-parity + exit-shape + write-through-first specs; full-suite regression net. Real-TTY residual → Human item 1. |
| MUST NOT let a run-log write failure fail or change the wrapped command | test | ✓ VERIFIED | Degradation group incl. both CR-05 re-entrancy shapes (truth 8). |
| MUST NOT record secrets or credentials in run logs (argv verbatim only because the flag surface is secret-free; no env vars) | judgment | ⚠ FLAGGED — unverified-prohibition, human review recommended | Non-authoritative LLM-judge verdict: SUBSTANTIALLY HONORED. Grounds: zero `ENV` references in run_log.rb/sh.rb/main.rb (grep this session); argv-only capture; WR-02 header credential redaction with `redacted` flag + specs (`run_log_spec.rb:59-79`); body verbatim by design (D-05). Documented residual IN-08: CREDENTIAL_PATTERN misses literal-`/` passwords and empty-user `:token@` forms (carried Info, 12-REVIEW.md). Never a silent pass → Human item 2. |

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| lib/spm_cache/core/run_log.rb | Core::RunLog + TeeIO + StreamSink + CycleWrapper + pre_scan/open/prune/finish | ✓ VERIFIED | 566 lines, full surface present and substantive (read in full this session) |
| lib/spm_cache/main.rb | tee install + three-shape exit capture around Command.run | ✓ VERIFIED | main.rb:19-53; streams restored BEFORE finish |
| lib/spm_cache/core/sh.rb | live_log_out/err sinks, failure_detail tails, full-output return, sh events | ✓ VERIFIED | Both raise paths + capture3 event; FAILURE_DETAIL_LINES reused, not duplicated |
| lib/spm_cache/core/config.rb | runs_dir / runs_keep / runs_max_mb + DEFAULT_CONFIG keys | ✓ VERIFIED | Outside-sandbox rationale comments cite D-02/Pitfall 7 |
| lib/spm_cache/command.rb + command/base.rb | --no-run-log + --log-dir=DIR declarations; RUN_LOG constant; run_log? reader | ✓ VERIFIED | `argv.flag?('run-log', true)` shape matches --no-merge-slices precedent |
| lib/spm_cache/command/init.rb | .spm-cache/ gitignore entry, idempotent | ✓ VERIFIED | Two independent append-once entries |
| lib/spm_cache/command/watch.rb | cycle-wrapped installer_factory | ✓ VERIFIED | argv: ARGV + CLAide-parsed log_dir threaded (CR-02) |
| lib/spm_cache/installer/use.rb, installer/build.rb | detect/integrate/build phase markers | ✓ VERIFIED | Nil-guarded `&.` calls at the specified boundaries |
| lib/spm_cache/spm/build_pipeline.rb | run_log kwarg + package brackets + fidelity marker + guarded emitter | ✓ VERIFIED | ensure-driven package_end; nil-disables documented |
| lib/spm_cache/spm/build.rb | StreamSink forwarding on the Sh.run calls | ✓ VERIFIED | Both retry and primary paths carry the sinks |
| lib/spm_cache/command/pkg/build.rb | BuildPipeline.run(run_log: current) | ✓ VERIFIED | Second choke-point call site threaded |
| lib/spm_cache/assets/templates/spm-cache.yml.template | commented runs_keep/runs_max_mb docs | ✓ VERIFIED | Matches `# cache_only:` convention; parity asserted by spec |
| spec/main_run_log_spec.rb, spec/run_log_spec.rb, spec/sh_run_log_sink_spec.rb | NEW phase specs | ✓ VERIFIED | All exist; example inventories captured this session; green |
| Extended spec/config_spec.rb, init_spec.rb, build_pipeline_spec.rb, installer_build_spec.rb, installer_use_fast_path_spec.rb, watch_spec.rb | coverage extensions | ✓ VERIFIED | Retention/coercion/gitignore/brackets/markers/cycle groups all present and green |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|----|--------|---------|
| Main.run | RunLog lifecycle | pre_scan → open → tee swap → Command.run → rescue shapes → ensure restore → finish | ✓ WIRED | main.rb:19-53 |
| RunLog.current seam | Plans 02/04/05 consumers | Sh capture3 event, installer markers, pipeline kwarg, CycleWrapper save/restore | ✓ WIRED | sh.rb:58-60; use.rb:23-31; build.rb:53; installer/build.rb:187; run_log.rb:285-292, 560 |
| Installer::Build / pkg build → BuildPipeline.run | run_log: Core::RunLog.current | ✓ WIRED | Both call sites verified |
| BuildPipeline → Buildable#xcodebuild → Core::Sh | live_log_out/live_log_err StreamSinks | ✓ WIRED | build.rb:89-93; real-echo file-line spec |
| Command::Watch#run factory → CycleWrapper → Watcher | factory.call + perform_install (unmodified) | ✓ WIRED | watch.rb:40-48; watcher.rb untouched (git-proven) |
| spm-cache.yml → Config → prune budgets | raw[] \|\| default + Integer coercion | ✓ WIRED | config.rb:118-135; run_log.rb:155-158 |
| Init → .gitignore | append-once entry per concern | ✓ WIRED | init.rb ensure_gitignore |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| RunLog body lines | $stdout/$stderr writes | TeeIO write-through on real streams | Yes — real Command.run/UI/subprocess output | ✓ FLOWING |
| RunLog sh events | capture3 results | Real Open3.capture3 status | Yes — real exitstatus, asserted failing+success | ✓ FLOWING |
| RunLog package/phase events | pipeline/installer state | Real build flow (name, success flag) | Yes — ok/failed derived from real success flag | ✓ FLOWING |
| Cycle files | per-cycle open | Watcher regeneration via factory | Yes — double harness asserts real cycle output only | ✓ FLOWING |
| prune budgets | Config raw | DEFAULT_CONFIG / spm-cache.yml | Yes — override + coercion specs | ✓ FLOWING |

No static returns, hardcoded payloads, or mock-only sources anywhere in the capture chain.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Full suite (single run; superset of every plan's named spec command) | `bundle exec rspec` | 536 examples, 0 failures, exit 0 | ✓ PASS |
| CLAide rejects two-token `--log-dir X` (grounds CR-02) | live `SPMCache::Command.parse([...]).validate!` both positions | `CLAide::Help: Unknown option: --log-dir / Did you mean: --log-dir=DIR?` | ✓ PASS (claim confirmed) |
| CLAide accepts `--log-dir=X` post-verb | live parse | `eq-form PARSED as SPMCache::Command::Use` | ✓ PASS |
| Watcher untouched by phase commits | `git log -- lib/spm_cache/core/watcher.rb` | last commit 9ab76ea (v0.4.0), pre-phase | ✓ PASS |
| No env-var capture | grep `ENV` over run_log.rb/sh.rb/main.rb | zero matches | ✓ PASS |

### Probe Execution

Step 7c SKIPPED — this phase declares no `scripts/*/tests/probe-*.sh` probes; its probe edges (adjacency/empty/ordering) were resolved-explicit into spec groups (verified green above), per each plan's Edge Coverage table.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|---------------------|----------|
| LOGS-01 | 12-01, 12-02, 12-03, 12-04, 12-05 (all declare `requirements: [LOGS-01]`) | Every CLI run (build/use/watch) writes a JSONL run log (header/body/exit lines) under the project run dir, outside the sandbox | ✓ SATISFIED | Truths 1-28; REQUIREMENTS.md marks LOGS-01 Complete; traceability table maps Phase 12 ↔ LOGS-01 only |

Orphaned requirements: none — REQUIREMENTS.md maps exactly LOGS-01 to Phase 12, and all five plans claim it.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| (none) | — | Debt-marker scan (TODO/FIXME/TBD/XXX/HACK/PLACEHOLDER) over all 14 lib + key spec files: zero matches | — | — |

Carried review INFO items (documented, deliberately out of fix scope per the review contract; none blocks the goal): IN-04 (`close` lacks degradation wrapper — unreachable today), IN-08 (credential-pattern residual gaps — feeds Human item 2), IN-09 (`--`-separator orphan log for argv CLAide rejects anyway), IN-10 (pre-existing unquoted `-derivedDataPath`), IN-01..IN-07 (iteration-1 cosmetics). Catalogued for a future hardening pass; not gaps against SC1-SC4.

### Human Verification Required

### 1. Real-TTY terminal byte-parity (SC3)

**Test:** Run `spm-cache use` (and a failing `spm-cache build`) on the reference project with and without `--no-run-log`; diff terminal transcripts and exit codes.
**Expected:** Byte-identical transcripts, identical exit codes. (12-VALIDATION.md's single manual-only item; all hermetic parity specs green.)
**Why human:** Real-TTY buffering/isatty interplay is not automatable hermetically; specs capture via StringIO.

### 2. Judgment-tier prohibition — secrets in run logs (unverified-prohibition — human review recommended)

**Test:** Confirm the no-secrets posture: review that today's flag surface carries no credentials, and accept or remediate the IN-08 redaction residual.
**Expected:** argv-only capture, no env vars (grep-proven zero), WR-02 header redaction active. Autonomous verdict recorded as SUBSTANTIALLY HONORED — non-authoritative, flagged, never silently passed.
**Why human:** `verification: judgment` prohibitions require explicit human resolution in autonomous mode.

### 3. CR-02 deviation acceptance (override suggestion)

**Test:** Accept or reject the documented deviation from plan-literal two-token `--log-dir X` routing.
**Expected:** If accepted, add to frontmatter:

```yaml
overrides:

  - must_have: "D-01: --log-dir (both --log-dir=X and --log-dir X forms) overrides the run dir, pre-scanned from raw argv before CLAide parses"
    reason: "CLAide rejects the two-token --log-dir X form in every position (live-verified: 'Unknown option: --log-dir'), so routing it would orphan logs for invocations that never run; the = form routes in any position (D-01 intent fully met)"
    accepted_by: "{name}"
    accepted_at: "{ISO timestamp}"
```

**Why human:** The plan text promised a form the CLI parser cannot accept; the implemented CLAide-parity semantics (spec-pinned, review-documented as CR-02, iteration-3 clean) needs a recorded acceptance.

### Gaps Summary

No gaps. All 28 merged truths verified against live code with passing behavioral evidence; every artifact exists, is substantive, wired, and carries real data; every key link is connected; LOGS-01 is fully claimed and satisfied; no debt markers; the phase's only high-severity threat (T-12-04 disk-fill) is disposed with spec proof. The three test-tier prohibitions are enforcement-backed and green. Status is **human_needed** (not passed) solely because: (a) the real-TTY byte-parity check is the phase's designated manual-only verification, (b) the judgment-tier secrets prohibition requires a human verdict per the autonomous-mode soft-gate, and (c) the CR-02 plan-text deviation needs a recorded override acceptance.

---

_Verified: 2026-09-01_
_Verifier: Claude (gsd-verifier)_
