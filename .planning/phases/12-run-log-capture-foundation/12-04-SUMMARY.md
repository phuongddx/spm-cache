---
phase: 12-run-log-capture-foundation
plan: "04"
subsystem: infra
tags: [run-log, event-vocabulary, jsonl, d-04, stream-sinks, xcodebuild, build-pipeline, phase-markers]

requires:
  - phase: 12-run-log-capture-foundation (plan 12-01)
    provides: Core::RunLog JSONL writer with event(), RunLog.current process-wide seam, RunLog::StreamSink per-stream adapter
  - phase: 12-run-log-capture-foundation (plan 12-02)
    provides: Core::Sh opts live_log_out:/live_log_err: + popen3 reader-thread sink wiring
provides:
  - SPM::BuildPipeline.run(run_log: nil) — nil-disables kwarg emitting package_start ({event,ts,name}) at run entry and package_end ({event,ts,name,status: ok|failed}) from the ensure, plus the phase fidelity marker immediately before report_fidelity
  - emit_run_log_event — the pipeline's single rescue-to-warn emission helper (nil-disables + never-fail guard + T-12-01 citation)
  - Buildable#xcodebuild per-stream sink forwarding — live_log_out:/live_log_err: StreamSinks on BOTH Sh.run calls (initial + low-deployment-target retry), activating Plan 12-02's dormant sinks from the real build path
  - Phase markers detect / integrate (Installer::Use#perform_install, single integrate site before the branch) and build (Installer::Build#perform_install, before the missed.each loop and before the empty-set early return) via Core::RunLog.current&.event
  - Both BuildPipeline.run call sites (Installer::Build#build_single_target, Command::Pkg::Build) thread run_log: Core::RunLog.current
  - run_log threading through perform_build AND run_with_scheme (the scheme-fallback build path is not a capture hole)
affects: [14-live-log-streaming (SSE tailer consumes this frozen vocabulary), 12-run-log-capture-foundation (12-05 watch cycles reuse the current&.event seam), 13-server-skeleton]

actuals:
  tokens: 14387   # chars/4 over the realized diff (lib+spec, 57546 added chars incl. rubocop-daemon reformat churn); plan estimated 40000 at confidence low
  tasks: 2
  commits: 5

tech-stack:
  added: []   # stdlib only — no new gems, per project constraint
  patterns:
    - "Guarded emission helper (nil-disables + rescue-to-warn) at the consolidated insertion point — logging can never fail or alter the build (mirrors report_fidelity's rescue)"
    - "Sink construction conditional on the threaded kwarg: opts[:run_log] nil forwards NO sink keys to Sh.run (byte-identical), set forwards the per-stream pair"
    - "Phase markers via Core::RunLog.current&.event('phase', name:) at existing branch boundaries — zero restructuring, nil-safe by construction"

key-files:
  created: []
  modified:
    - lib/spm_cache/spm/build_pipeline.rb
    - lib/spm_cache/spm/build.rb
    - lib/spm_cache/installer/build.rb
    - lib/spm_cache/installer/use.rb
    - lib/spm_cache/command/pkg/build.rb
    - spec/build_pipeline_spec.rb
    - spec/installer_build_spec.rb
    - spec/installer_use_fast_path_spec.rb

key-decisions:
  - "Build marker placed BEFORE the missed.empty? early return, not 'immediately after the Building N line' as the action text said: that info line is unreachable on an empty missed set, contradicting the behavior bullet, the EDGE row, and the must_haves truth (all three require the marker present on zero-pins) — 3-vs-1 in favor of pre-return placement, deviation documented"
  - "xcodebuild forwards sinks only when opts[:run_log] is set — when nil, Sh.run receives no live_log_out/live_log_err keys at all (literal 'forwards nothing'), not nil-valued keys"
  - "run_log threaded into run_with_scheme too (the scheme-fallback path vendored-.xcodeproj packages actually take), mirroring the clones_dir threading precedent — no capture hole on the retry path"
  - "Never-fail guard is two layers by design: RunLog's safe_append degrades file-write failures; emit_run_log_event's rescue-to-warn covers a broken sink object entirely (proven by the broken-double spec)"
  - "Sink-activation spec builds a REAL Buildable via and_wrap_original (the before-block's instance_double .new stub must be wrapped, not re-returned) with build_command stubbed to a real echo pipeline — the xcodebuild forwarding, popen3 reader threads, and StreamSink writes are all real production code"

patterns-established:
  - "The D-04 vocabulary is FROZEN for Phase 14: run_start / phase{name: detect|integrate|build|fidelity} / package_start{name} / package_end{name,status} / run_end — reshape only with the Phase 14 tailer/frontend/specs re-checked together (12-CONTEXT.md D-04 reversibility note)"
  - "Events-from-orchestration shape: kwarg-threaded sink at the pipeline (structure), nil-guarded current&.event at the installers (markers) — Plan 12-05's watch cycles extend the second shape"

requirements-completed: []   # LOGS-01 completes with 12-05 (watch per-cycle files); this plan closes SC2 and freezes the D-04 vocabulary

coverage:
  - id: D1
    description: "Pipeline package/phase events — package_start/package_end brackets (ok on success, failed on raise with the exception propagating unchanged), fidelity phase marker immediately before report_fidelity, zero-pins bracket with no phantom body lines, nil-disables, never-fail guard"
    requirement: LOGS-01
    verification:
      - kind: unit
        ref: "spec/build_pipeline_spec.rb#brackets a successful run with package_start / fidelity phase / package_end ok"
        status: pass
      - kind: unit
        ref: "spec/build_pipeline_spec.rb#writes package_end failed from the ensure and re-raises the build error unchanged"
        status: pass
      - kind: unit
        ref: "spec/build_pipeline_spec.rb#emits nothing when run_log is omitted, even with a RunLog active as current (nil-disables)"
        status: pass
      - kind: unit
        ref: "spec/build_pipeline_spec.rb#brackets an empty build workload with no phantom lines between (EDGE empty)"
        status: pass
      - kind: unit
        ref: "spec/build_pipeline_spec.rb#degrades to a warn when event emission fails -- the build result is untouched (never-fail guard)"
        status: pass
    human_judgment: false
  - id: D2
    description: "xcodebuild sink activation (SC2 subprocess half) — with run_log set, Buildable#xcodebuild forwards per-stream live_log_out/live_log_err StreamSinks on both Sh.run calls; a real echo subprocess standing in for xcodebuild lands stream-tagged lines in the run log through the real Core::Sh popen3 readers"
    requirement: LOGS-01
    verification:
      - kind: unit
        ref: "spec/build_pipeline_spec.rb#streams xcodebuild stdout/stderr into the run log via per-stream live sinks (SC2)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Installer phase markers + threading — detect after detect_diff, integrate exactly once per run regardless of branch, build before the missed loop (present on empty missed with zero package events), and build_single_target threads run_log: Core::RunLog.current into every BuildPipeline.run call"
    requirement: LOGS-01
    verification:
      - kind: unit
        ref: "spec/installer_use_fast_path_spec.rb#emits detect then integrate exactly once on the fast path"
        status: pass
      - kind: unit
        ref: "spec/installer_use_fast_path_spec.rb#emits exactly one integrate marker on the full regeneration branch too (single site, no duplication)"
        status: pass
      - kind: unit
        ref: "spec/installer_build_spec.rb#emits the build phase marker before the missed.each loop"
        status: pass
      - kind: unit
        ref: "spec/installer_build_spec.rb#emits the build marker on an empty missed set with zero package events (EDGE empty zero-pins)"
        status: pass
      - kind: unit
        ref: "spec/installer_build_spec.rb#threads Core::RunLog.current into every BuildPipeline.run call (Task 12-04-01 call site)"
        status: pass
    human_judgment: false

duration: 11min
completed: 2026-08-31
status: complete
---

# Phase 12 Plan 04: Structured event vocabulary + subprocess activation Summary

**D-04's event vocabulary is live from the real seams — package_start/package_end brackets and the fidelity marker from BuildPipeline.run's single choke point (ok/failed from the success flag, ensure-emitted), detect/integrate/build phase markers from the installers' existing boundaries, and xcodebuild output streaming into run logs via per-stream StreamSinks activating Plan 12-02's Sh sinks — full suite 503 examples green, vocabulary frozen for Phase 14**

## Performance

- **Duration:** 11 min
- **Started:** 2026-08-31T17:30:43Z
- **Completed:** 2026-08-31T17:41:40Z
- **Tasks:** 2
- **Files modified:** 8

## Accomplishments
- SC2 complete: a build run's log now reconstructs offline — narrative (Plan 12-01 tee), subprocess output (Plan 12-02 sinks + this plan's activation), per-package brackets, and phase structure, interleaved in one file under one schema
- Every `SPM::BuildPipeline.run` invocation is bracketed exactly once at the consolidated insertion point shared by Installer::Build's loop and `pkg build`: package_start after the name guard, package_end from the ensure (status ok/failed derived from the existing success flag — a raise still lands the bracket before propagating unchanged)
- `Buildable#xcodebuild` constructs per-stream `RunLog::StreamSink`s when the pipeline threads a run log and forwards `live_log_out:`/`live_log_err:` on BOTH Sh.run calls (initial + low-deployment-target retry); proven with a real echo subprocess through the real Core::Sh into the file, tagged `out`/`err` correctly (Pitfall 4)
- Phase markers detect/integrate (Use, single integrate site before the branch — exactly one per run on both paths) and build (Build, present even on a zero-pins run where zero package events follow), all nil-guarded through `Core::RunLog.current&.event` — zero restructuring, every existing caller path a no-op
- Full suite green: 503 examples, 0 failures — 492 pre-existing (the nil-disables regression net, all passing unmodified) + exactly 11 new

## Task Commits

Each task was committed atomically (TDD: RED before GREEN on both):

1. **Task 1 RED: failing pipeline D-04 specs** - `4379466` (test)
2. **Task 1 GREEN: pipeline events + xcodebuild sink activation** - `f33de98` (feat)
3. **Task 2 RED: failing installer marker specs** - `f9ac732` (test)
4. **Task 2 GREEN: installer phase markers detect/integrate/build** - `aad5202` (feat)
5. **T-12-01 emission-site mitigation comment** - `25d8608` (docs)

**Plan metadata:** docs commit (this commit: SUMMARY + STATE + ROADMAP)

## Files Created/Modified
- `lib/spm_cache/spm/build_pipeline.rb` - `run_log: nil` kwarg (nil-disables doc precedent); package_start/package_end emissions; fidelity marker before report_fidelity; run_log threaded into perform_build + run_with_scheme + both build_for_destination calls; private `emit_run_log_event` guarded helper (rescue-to-warn + T-12-01 citation)
- `lib/spm_cache/spm/build.rb` - `Buildable#xcodebuild` constructs per-stream StreamSinks from `opts[:run_log]` and forwards them as live_log_out:/live_log_err: on both Sh.run calls; legacy live_log: untouched
- `lib/spm_cache/installer/build.rb` - build phase marker before the empty-set early return; `build_single_target` passes `run_log: Core::RunLog.current`
- `lib/spm_cache/installer/use.rb` - detect marker after detect_diff, integrate marker once before the fast/full branch
- `lib/spm_cache/command/pkg/build.rb` - BuildPipeline.run call passes `run_log: Core::RunLog.current`
- `spec/build_pipeline_spec.rb` - +6 examples under "run-log events (D-04)": bracket-success/failure, real-echo sink activation, nil-disables anchor, EDGE empty, never-fail guard
- `spec/installer_use_fast_path_spec.rb` - +2 marker examples (fast path + full regeneration branch)
- `spec/installer_build_spec.rb` - +3 examples: build marker, zero-pins EDGE empty, run_log threading (Task-1 call-site pin)

## Decisions Made
- Build-marker placement conflict in the plan resolved for the behavior bullet + EDGE row + must_haves truth over the action text: the marker emits BEFORE the `missed.empty?` early return because the "Building N target(s)" line the action names is unreachable on an empty missed set, and all three truth statements require the marker present on zero-pins
- Sink forwarding is conditional, not nil-valued: no run_log → Sh.run receives no sink keys at all (literal "forwards nothing"), keeping the no-log Sh path byte-identical
- The never-fail guard covers the sink object, not just the file: RunLog's safe_append already degrades write failures, but a broken double (or future non-RunLog sink) must also not fail the build — emit_run_log_event rescues to a UI.warn
- The sink-activation proof uses a REAL Buildable (and_wrap_original around the before-block's .new stub) with only build_command swapped for an echo pipeline, so the forwarding code under test is production code, not a re-description

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Sink-activation spec built the instance_double, not a real Buildable**
- **Found during:** Task 1 (GREEN verification — first run still red)
- **Issue:** The example constructed `Buildable.new(...)` to obtain a "real" buildable AFTER the before-block had already stubbed `.new` to return the shared instance_double — so the run used the double's default build_for_destination stub (no xcodebuild, no sinks) and the file gained zero body lines
- **Fix:** Re-stub with `and_wrap_original`, which reaches the real constructor through the earlier stub, then stubs only `build_command` (echo pipeline standing in for xcodebuild) and `create_framework` on the real instance
- **Files modified:** spec/build_pipeline_spec.rb
- **Verification:** `bundle exec rspec spec/build_pipeline_spec.rb spec/build_pipeline_seeding_spec.rb spec/build_pipeline_provenance_spec.rb` → 74 examples, 0 failures
- **Committed in:** f33de98 (part of Task 1 GREEN commit)

**2. [Rule 1 - Bug] Plan-internal conflict on the build marker's placement**
- **Found during:** Task 2 (RED authoring)
- **Issue:** The task action places the build marker "immediately after the 'Building N target(s)' info line" — a line emitted only AFTER the `missed.empty?` early return, so an empty missed set (the plan's own EDGE empty case) could never emit it, contradicting the behavior bullet ("with an empty missed set the marker still appears"), the Edge Coverage row ("phase markers present, zero package_start/package_end lines"), and the must_haves truth
- **Fix:** Emitted before the early return (right after `missed.uniq!`), satisfying "before the missed.each loop" plus all three zero-pins truth statements; the conflict and resolution are cited in the code comment
- **Files modified:** lib/spm_cache/installer/build.rb
- **Verification:** `bundle exec rspec spec/installer_build_spec.rb` → zero-pins example green alongside the marker example
- **Committed in:** aad5202 (Task 2 GREEN commit)

**3. [Rule 2 - Missing critical] T-12-01 mitigation comment at the emission site**
- **Found during:** Pre-SUMMARY threat-register sweep
- **Issue:** The threat register's T-12-01 mitigation requires the log-forging rationale documented where package names cross into event fields; the emission helper carried the nil-disables/never-fail rationale but not the forging one
- **Fix:** Added the citation to `emit_run_log_event`'s comment: every event routes through RunLog#event's JSON.generate (a lookalike name is escaped into the `name` VALUE, never a forged line); Phase 14 renderers key on `event` and treat text/name values as data
- **Files modified:** lib/spm_cache/spm/build_pipeline.rb
- **Verification:** comment-only; `spec/build_pipeline_spec.rb` 40 examples, 0 failures
- **Committed in:** 25d8608

---

**Total deviations:** 3 auto-fixed (2 × Rule 1 bug/spec corrections, 1 × Rule 2 threat-register comment; zero unplanned behavior changes — both RED signals were the plan's own new-behavior failures)
**Impact on plan:** None on scope or design; the placement conflict was inside the plan text and resolved in favor of its own testable truths.

## Issues Encountered
- The editor's rubocop daemon again auto-corrected style file-wide on save of touched files (quote conversion + trailing-comma removal in spec/build_pipeline_spec.rb, installer_build_spec.rb, installer_use_fast_path_spec.rb, installer/build.rb) — behavior-identical Ruby aligned with the project's own `make format`, same phenomenon 12-01/12-02/12-03 documented; accepted rather than fought (it inflates the diff on untouched lines, hence the 292-line churn in installer_build_spec.rb for ~90 added)
- Full-suite example count: 492 → 503, exactly +11 (6 pipeline + 2 use + 3 build markers); the spec_helper's 3 embedded examples count once per process, matching prior plans' accounting

## User Setup Required
None - no external service configuration required.

## Known Stubs
None — every surface is wired to real behavior; no placeholders, TODOs, or mock data paths were found in the stub scan.

## Threat Flags

None — no security-relevant surface beyond the plan's threat_model. T-12-01 (log-forging via package names) mitigated as planned and now cited at the emission site (JSON.generate escaping, renderers key on `event` only). T-12-04 (disk-fill, high) remains disposed by Plan 12-03's retention, which every RunLog.open already prunes. T-12-05: target names in events are the same identifiers the CLI already prints to the terminal — no env or credential data crosses into events.

## Next Phase Readiness
- The D-04 minimum event vocabulary (run_start, package_start/package_end, phase markers, run_end) is complete, observable end-to-end, and frozen — Phase 14's SSE tailer and browser anchors build on exactly these names and fields
- SC2 is closed; LOGS-01's last open item is Plan 12-05 (watch per-cycle files via the RunLog.cycle_wrapper / installer_factory seam, which now also inherits the detect/integrate markers from Use#perform_install for free)
- The `Core::RunLog.current&.event` marker seam and the kwarg-threaded sink are the two shapes 12-05 and Phase 14 extend; neither changed RunLog's own API

## TDD Gate Compliance

Both tdd tasks followed RED → GREEN with the required commits (validated in git log):
- Task 1: `test(12-04)` RED (4379466, 5 failing with `ArgumentError: unknown keyword :run_log` — the exact pre-implementation signal) before `feat(12-04)` GREEN (f33de98)
- Task 2: `test(12-04)` RED (f9ac732, 4 failing marker examples) before `feat(12-04)` GREEN (aad5202)
- Two anchors were green in RED state by design: the pipeline nil-disables example (pins that run never reaches for RunLog.current on its own) and the build threading example (pins Task 1's already-committed call-site change) — matching 12-03's documented regression-anchor pattern

## Self-Check: PASSED

All modified files exist on disk (5 lib + 3 spec + 12-04-SUMMARY.md); all five task commits (4379466, f33de98, f9ac732, aad5202, 25d8608) present in history; structural greps confirmed (`run_log: nil` in run + perform_build + run_with_scheme signatures, package_start/package_end/`name: "fidelity"` emission sites, both Sh.run calls merging sinks, `run_log: Core::RunLog.current` at both call sites, two `Core::RunLog.current&.event("phase"` sites in use.rb + one in build.rb); full suite 503 examples, 0 failures.

---
*Phase: 12-run-log-capture-foundation*
*Completed: 2026-08-31*
