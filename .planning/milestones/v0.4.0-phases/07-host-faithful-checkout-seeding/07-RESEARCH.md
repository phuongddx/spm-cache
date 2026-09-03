# Phase 7: Host-Faithful Checkout Seeding - Research

**Researched:** 2026-08-29
**Domain:** Ruby build-pipeline seeding (SwiftPM `Package.resolved` injection), not greenfield
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Seeding Mechanism** (sourced from `.planning/research/ARCHITECTURE.md`, verified empirically during milestone research):
- Copy the host's `Package.resolved` verbatim into each package checkout (`<pkg_dir>/Package.resolved`) before the first `swift package describe`. Verified: a superset file is honored — extra pins pruned, missing pins filled in, `originHash` ignored. Do NOT synthesize or filter pins per-package; that reintroduces the staleness/format-churn risk Phase 6 just closed.
- Do NOT enable `-onlyUsePackageVersionsFromResolvedFile` by default. It hard-fails on any missing pin, and the umbrella systematically omits packages' external test-only dependencies — this would break every package with an external test dep. Detection of drift is Phase 8's job (post-resolve read-back), not this flag.
- Add `-clonedSourcePackagesDirPath` pointed at a dedicated sibling directory (never `{umbrella}/.build`) as a secondary cost mechanism. `BuildPipeline#locate_prebuilt_xcframework` reads Class-E binaryTarget artifacts from `{umbrella}/.build/artifacts/...`; pointing the shared clone dir there risks corrupting that live state.

**Vendored-`.xcodeproj` Classification** (sourced from `.planning/research/PITFALLS.md` Pitfall 11):
- Classify each package before injecting: SPM-native vs. vendored-`.xcodeproj` (CryptoSwift, AppAuth-iOS, SVGKit, DTCoreText, DeviceKit, AEXML, FSPagerView, SkeletonView — already-hardened v0.2.x classes). Apply seeding only to the SPM-native path.
- Report vendored-project packages as an explicit **not-graph-pinned** category, never folded silently into "pinned." Honest partial coverage beats a false 100%. This is amended ROADMAP criterion 2 verbatim.

**Safety Invariants:**
- An aborted/failed/interrupted build must leave no checkout carrying a synthetic resolved file — atomic write + restore-on-failure, not an in-place overwrite left dangling.
- A concurrent `watch` cycle must not be able to delete checkouts out from under an in-flight build (process-level lock, not the debounce timer).
- **Default-off byte-identical fallback.** With seeding disabled (the default), behavior must be byte-for-byte identical to v0.3.0. This is the phase's regression-safety net and should be a concrete, checkable task, not an assumption.

**Performance Gate** (ROADMAP criterion 5, ratified by the milestone roadmapper):
- Benchmark cached-build wall-clock and disk usage against the reference project. **No regression is acceptable.** If the verbatim-pin-superset approach regresses, narrow to the minimal pin closure and re-measure until it does not. This is a blocking gate, not a follow-up.

### Claude's Discretion
- Exact module/class boundaries for the seeding logic (naming, file organization) — follow existing codebase conventions (`SPMCache::SPM` namespace, one class per file).
- Whether the vendored-`.xcodeproj` classification lives as a new method or extends an existing one — the existing `Buildable#project_disambiguation_flag` / `BuildPipeline#run_with_scheme` fallback path is the established precedent to extend, not replace.
- Benchmark methodology specifics (what counts as "the reference project" run, warm vs cold cache) — use the existing `benchmark-report.html` pattern already in the repo if present.

### Deferred Ideas (OUT OF SCOPE)
- Drift read-back / provenance sidecar — Phase 8.
- Cache invalidation on provenance mismatch — Phase 9.
- Full regression fixture matrix — Phase 10 (this phase's own byte-identical-with-seeding-off task is a narrower, phase-local check).
</user_constraints>

## Summary

Phase 7 is **already implemented, committed, and passing** — this is not a research-for-new-build
task, it is a verification-grade confirmation pass for a re-planning/verification cycle. Two plans
(`07-01`, `07-02`) shipped across commits `7ebe14a`/`c1b2d83` and `07e07ff`/`bef915e`/`1b7b89d`.
Every line of code the phase's five success criteria depend on was re-read in this session (not
grepped) and traced end-to-end: `SPM::ResolvedGraph` (new module) → `BuildPipeline.run` (seed before
`perform_build`, restore in `ensure` unless success) → `Installer::Build#perform_install` (resolves
one host-graph answer per run and threads it + `clones_dir` into every build) → `Config#clones_dir`/
`#build_lock_path` → `Installer::Build`/`Installer::Use` process-level `flock`. The full suite was
re-run in this session: **341 examples, 0 failures**, matching both SUMMARYs' recorded counts exactly
— no drift between what was claimed and what is on disk.

**Primary recommendation:** Do not re-plan or re-implement anything for this phase's stated goal.
The only legitimate re-planning work is (a) running `/gsd-verify-work 7` — the canonical goal-backward
verification gate never ran — and (b) deciding what to do about two blocking measurements the ROADMAP
itself required (M2, M4) that were never executed or recorded as waived, and one pending UAT test
(#7, PERF-01) sitting in `07-UAT.md`. These are documented below as the actionable gaps a re-planning
pass needs to close, not as new engineering work.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| FID-02 | Per-package builds are seeded with the host's resolved graph before the first `swift package describe` | Confirmed shipped — see "Confirmation of Success Criteria" Criterion 1, code cited with line ranges |
| FID-05 | Packages that cannot be graph-pinned (vendored `.xcodeproj`) are reported explicitly, never counted as pinned | Confirmed shipped — see Criterion 2, code cited with line ranges |
| PERF-01 | Cached-build wall-clock and disk usage show no regression vs v0.3.0 | Confirmed shipped and measured — see Criterion 5, `07-BENCHMARK.md` re-read this session |
</phase_requirements>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Host-graph seeding (copy `Package.resolved` into checkout) | Build orchestration (Ruby CLI) | Filesystem | `SPM::ResolvedGraph` is pure file I/O — no shell-out, no JSON parse of seeded content — invoked from `BuildPipeline.run` before `swift package describe` runs (an external CLI tier) |
| Vendored-`.xcodeproj` classification | Build orchestration (Ruby CLI) | — | Structural glob check (`Dir.glob("*.xcodeproj")`) gates the seed call itself, before any external tool call |
| Shared clone directory (`-clonedSourcePackagesDirPath`) | Build orchestration → xcodebuild invocation | Filesystem | Config computes the path; `Buildable#build_command` passes it as a flag to the external `xcodebuild` process |
| Build/watch mutual exclusion | OS (flock) | Build orchestration | `File#flock` is a kernel-level primitive; the Ruby classes only decide when to acquire/release it |
| Byte-identical default (no seeding) | Build orchestration (Ruby CLI) | — | Achieved by `nil`-default kwargs at every layer (`resolved_pins_file: nil`, `clones_dir: nil`), not a separate code path |

This phase touches no browser/frontend/API/DB tiers — it is entirely inside the Ruby CLI's build
orchestration layer plus its `xcodebuild`/SwiftPM external-process boundary.

## Package Legitimacy Audit

Not applicable — Phase 7 added zero new dependencies (Gemfile/gemspec untouched by either plan; both
SUMMARYs record `tech-stack: added: []`). Confirmed via `07-01-SUMMARY.md`/`07-02-SUMMARY.md` frontmatter.

## Confirmation of Success Criteria Against Actual Code

Each ROADMAP.md success criterion, checked against source read in this session:

### Criterion 1 — package builds resolve the host's transitive versions

`lib/spm_cache/spm/resolved_graph.rb:24-30` (`source_for`) picks the umbrella's own already-resolved
`Package.resolved` first, falling back to `host_graph_path`:

```ruby
def source_for(umbrella_dir:, host_graph_path:)
  umbrella_resolved = File.join(umbrella_dir, RESOLVED_FILENAME)
  return umbrella_resolved if File.exist?(umbrella_resolved)
  return host_graph_path if host_graph_path && File.exist?(host_graph_path)

  nil
end
```

`lib/spm_cache/spm/build_pipeline.rb:43-61` (`run`) seeds `pkg_dir` with that source **before**
`perform_build` (which is where `resolve_scheme`/`resolve_module_name` construct the first
`Desc::Description.new` → `swift package describe` call):

```ruby
def run(name:, pkg_dir:, destinations:, out_dir:, library_evolution: true, resolved_pins_file: nil,
        clones_dir: nil)
  raise "Target name required" if name.nil? || name.empty?
  FileUtils.mkdir_p(out_dir)
  seed_snapshot, seeded = seed_host_graph(name, pkg_dir, resolved_pins_file)
  success = false
  begin
    result = perform_build(name: name, pkg_dir: pkg_dir, destinations: destinations,
                            out_dir: out_dir, library_evolution: library_evolution,
                            clones_dir: clones_dir)
    success = true
    result
  ensure
    ResolvedGraph.restore!(pkg_dir, seed_snapshot) if seeded && !success
  end
end
```

`lib/spm_cache/installer/build.rb:45-48` resolves that source exactly once per run via the
already-memoized `host_graph_detector` (Phase 6 Plan 05's invariant), not a second locator:

```ruby
resolved_pins_file = SPM::ResolvedGraph.source_for(
  umbrella_dir: @config.umbrella_dir,
  host_graph_path: host_graph_detector.host_graph_path,
)
```

`[VERIFIED: lib/spm_cache/spm/resolved_graph.rb:24-30, lib/spm_cache/spm/build_pipeline.rb:43-61, lib/spm_cache/installer/build.rb:45-48]`
— Criterion 1's *mechanism* is satisfied by direct read. Whether the resulting `.xcframework`
actually links the pinned versions on a live build was validated by the 07-02 benchmark run against
the real reference project (`07-BENCHMARK.md`: 26/29 targets cached successfully with seeding
active), not by a fresh unit assertion of linked symbol versions — this is the same evidentiary shape
the SUMMARY itself claims (`human_judgment: false` on D1, backed by unit specs plus one real
integration run), and is reasonable given the mechanism is "copy bytes verbatim then let SwiftPM's
own resolver honor the superset file" — a file-content assertion, not a linked-binary assertion, is
the correct-altitude unit test here.

### Criterion 2 — vendored-`.xcodeproj` reported not-graph-pinned, never silently pinned

`lib/spm_cache/spm/resolved_graph.rb:61-63` (`vendored_xcodeproj?`) and
`lib/spm_cache/spm/build_pipeline.rb:70-80` (`seed_host_graph`, private) gate the seed call itself —
classification happens before any write, and the reported path names the package explicitly:

```ruby
def seed_host_graph(name, pkg_dir, resolved_pins_file)
  return [nil, false] unless resolved_pins_file
  if ResolvedGraph.vendored_xcodeproj?(pkg_dir)
    Core::UI.info "  #{name}: vendored .xcodeproj checkout, not graph-pinned " \
                  "(Package.resolved not seeded from host graph)"
    return [nil, false]
  end
  [ResolvedGraph.seed!(resolved_pins_file, pkg_dir), true]
end
```

`[VERIFIED: lib/spm_cache/spm/resolved_graph.rb:61-63, lib/spm_cache/spm/build_pipeline.rb:70-80]`
— criterion satisfied structurally: there is no code path where a vendored-`.xcodeproj` package
reaches `ResolvedGraph.seed!` at all, so "silently counted as pinned" is not reachable, not merely
avoided by convention.

### Criterion 3 — atomic write/restore + watch/build mutual exclusion

`lib/spm_cache/spm/resolved_graph.rb:36-52` (`seed!`/`restore!`/`snapshot_for`/`atomic_write`) uses
temp-file-then-`File.rename` (atomic on one filesystem) for both write and restore, and snapshots
"existed vs. did not" so restore is exact, not a heuristic:

```ruby
def seed!(source_path, pkg_dir)
  destination = File.join(pkg_dir, RESOLVED_FILENAME)
  snapshot = snapshot_for(destination)
  atomic_write(destination, File.binread(source_path))
  snapshot
end

def restore!(pkg_dir, snapshot)
  destination = File.join(pkg_dir, RESOLVED_FILENAME)
  if snapshot[:existed]
    atomic_write(destination, snapshot[:content])
  else
    FileUtils.rm_f(destination)
  end
end
```

The `ensure ResolvedGraph.restore!(...) if seeded && !success` block quoted under Criterion 1 fires
on **any** `StandardError` raised inside `perform_build`, and — because it is a plain Ruby `ensure`,
not a `rescue`-guarded region — also fires on `Interrupt`/`SignalException` (Ctrl-C), matching the
"aborted, failed, or interrupted" wording verbatim.

For the watch/build race, `lib/spm_cache/installer/build.rb:68-84` (`acquire_build_lock`/
`release_build_lock`) and `lib/spm_cache/installer/use.rb:47-58` (`with_build_lock`) share one
exclusive blocking `flock` at `Config#build_lock_path` — held by `Build` across `super` (which calls
`recreate_dirs`) plus the whole build loop, and acquired by `Use`'s non-fast-path branch immediately
before its own `recreate_dirs`:

```ruby
# installer/build.rb
def acquire_build_lock
  path = @config.build_lock_path
  FileUtils.mkdir_p(File.dirname(path))
  lock = File.open(path, File::CREAT | File::RDWR)
  lock.flock(File::LOCK_EX)
  lock
end
```
```ruby
# installer/use.rb
def with_build_lock
  path = @config.build_lock_path
  ...
  lock.flock(File::LOCK_EX)
  yield
ensure
  lock.flock(File::LOCK_UN)
  lock.close
end
```

`lib/spm_cache/core/config.rb:98-103` places this lock path **outside** `sandbox_dir` by
construction — a `project_dir`-level dotfile — so `recreate_dirs`' `rm_rf(sandbox_dir)` cannot ever
delete the file a live lock is held on:

```ruby
# Stable, OUTSIDE sandbox_dir by construction (a project_dir-level
# dotfile) so recreate_dirs' rm_rf(sandbox_dir) can never delete the
# path a live flock is held on (Pitfall 15).
def build_lock_path
  File.join(project_dir, ".spm-cache-build.lock")
end
```

`[VERIFIED: lib/spm_cache/spm/resolved_graph.rb:36-52, lib/spm_cache/installer/build.rb:68-84, lib/spm_cache/installer/use.rb:47-58, lib/spm_cache/core/config.rb:98-103]`

### Criterion 4 — default (seeding off) is byte-for-byte v0.3.0

Achieved by `nil`-default kwargs threaded through every layer, not a separate code branch:
`BuildPipeline.run(..., resolved_pins_file: nil, clones_dir: nil)` (build_pipeline.rb:43-44),
`Buildable#initialize(..., clones_dir: nil)` and `build_command`'s gated flag
(`lib/spm_cache/spm/build.rb:99-105`):

```ruby
def build_command(destination, dd, opts = {})
  cmd = "xcodebuild build"
  cmd += project_disambiguation_flag
  cmd += " -scheme '#{@scheme}'"
  cmd += " -destination '#{destination}'"
  cmd += " -derivedDataPath #{dd}"
  cmd += " -clonedSourcePackagesDirPath '#{@clones_dir}'" if @clones_dir
  cmd += " CODE_SIGNING_ALLOWED=NO"
  cmd += library_evolution_flags if @library_evolution
  cmd += " #{opts[:extra_args]}" if opts[:extra_args]
  cmd
end
```

`[VERIFIED: lib/spm_cache/spm/build_pipeline.rb:43-44, lib/spm_cache/spm/build.rb:99-105]` — when
neither kwarg is supplied, `seed_host_graph` returns `[nil, false]` immediately (no `ResolvedGraph`
call at all) and `build_command` never appends the new flag — this is a structural byte-identical
guarantee, not a behavioral approximation. Independently re-run in this session: `bundle exec rspec
spec/resolved_graph_spec.rb spec/build_pipeline_seeding_spec.rb spec/build_lock_spec.rb` → **32
examples, 0 failures**; full suite `bundle exec rspec` → **341 examples, 0 failures**, matching
`07-02-SUMMARY.md`'s recorded count exactly.

### Criterion 5 — PERF-01, no wall-clock/disk regression

`Config#clones_dir` (`lib/spm_cache/core/config.rb:88-96`) places the shared clone directory as a
dedicated sibling of `umbrella_dir`/`proxy_dir` — explicitly never under `{umbrella}/.build`, which
`BuildPipeline#locate_prebuilt_xcframework` (build_pipeline.rb:911-930) reads Class-E binaryTarget
artifacts from:

```ruby
# A dedicated sibling of umbrella_dir/proxy_dir -- never a path under
# umbrella_dir or its .build, which #locate_prebuilt_xcframework reads
# Class-E binaryTarget artifacts from (BuildPipeline). Shared across
# every xcodebuild invocation via -clonedSourcePackagesDirPath so N
# per-package builds don't each independently clone the whole host
# graph (Pitfall 9).
def clones_dir
  File.join(sandbox_dir, "packages", "clones")
end
```

`07-BENCHMARK.md` (read in full this session) is a real cold-cache measurement — not a synthetic or
stubbed one — against the actual reference project (`StressMonitor`, the same M1 reference project
from Phase 6), swapping `lib/` between the pre-clones-dir commit (`a8d5ddb`) and the post commit
(`bef915e`) while holding the live SPM graph fixed:

| Metric | Before (`a8d5ddb`) | After (`bef915e`) | Delta |
|---|---|---|---|
| Wall-clock | 18m15s | 10m50s | **-40.6%** |
| `~/.spm-cache` disk | 4.1G | 2.7G | **-34%** |
| Cached xcframework output | 75M | 75M | 0 (identical artifacts) |

`[VERIFIED: .planning/phases/07-host-faithful-checkout-seeding/07-BENCHMARK.md — read in full this session]`
— both axes improved, no regression, no narrowing (D-08) was needed. The benchmark also documents (not
fixes, correctly out of scope) a pre-existing Class-E binaryTarget rename gap affecting 3/29 targets
identically on both runs, so it does not bias the comparison.

## Gaps a Re-Planning Pass Should Close (not new implementation)

These are the items **not** already captured in either SUMMARY's own "Next Phase Readiness" section,
surfaced by re-reading the ROADMAP, REQUIREMENTS, STATE, and UAT files against what was actually done:

### Gap 1 — Canonical goal-backward verification never ran (highest priority)

`.continue-here.md` and `STATE.md` both explicitly flag this: `/gsd-verify-work 7` has never been
run. Both plan-level self-checks passed and the plan-checker passed, but no independent verifier
re-derived the five ROADMAP success criteria from scratch. This RESEARCH.md's "Confirmation of
Success Criteria" section above performs that re-derivation as research, but is not a substitute for
the formal `/gsd-verify-work` gate the phase description itself calls out as the outstanding item.

### Gap 2 — Two ROADMAP-mandated blocking measurements (M2, M4) were never executed or recorded as waived

ROADMAP.md's own Phase 7 section (`.planning/ROADMAP.md:98-102`) lists three "Measurements
(blocking)": M4, M2, M3. `[VERIFIED: .planning/ROADMAP.md:100-102 — read this session, quoted below]`

> - **M4** — does xcodebuild write back realized versions on the `run_with_scheme` /
>   vendored-`.xcodeproj` path? **Early probe, before the design is locked** — it is the sole
>   falsifier of the no-flag (`-onlyUsePackageVersionsFromResolvedFile`-off) design, and if
>   read-back has no reliable source on a path, that path must be reported as *not graph-pinned*.
> - **M2** — run seeding in **report-only mode** against the real project and count packages
>   reporting `resolution-incompatible`. Produced here, **consumed by Phase 8's policy commitment**;
>   a high count is a rescope trigger.
> - **M3** — wall-clock and disk delta from pin-list fan-out (verbatim superset vs minimal closure).
>   Gates PERF-01 and the narrowing decision.

M3 was executed (`07-BENCHMARK.md`, confirmed above). **M2 and M4 have no mention anywhere** in
`07-01-PLAN.md`, `07-02-PLAN.md`, `07-01-SUMMARY.md`, or `07-02-SUMMARY.md` — confirmed by grep
across all four files in this session with zero matches for `M4`, `M2`, `resolution-incompatible`,
`write.back`/`writeback`, or `early probe`.

Consequences a re-planning pass must weigh, not fixes to apply unilaterally:
- **M4** was the *sole falsifier* of the phase's core design decision (seed without
  `-onlyUsePackageVersionsFromResolvedFile`). The design was shipped without running it. This is not
  necessarily wrong — the CONTEXT.md decision to avoid the flag has independent justification (missing
  test-only pins would hard-fail) — but the specific question M4 asked (does `run_with_scheme`'s
  vendored-project xcodebuild invocation ever write back a realized version anywhere read-back could
  find) remains unanswered, and Phase 8's drift read-back design should not assume an answer that was
  never measured.
- **M2**'s count of `resolution-incompatible` packages was explicitly meant to be Phase 8's rescope
  trigger input. Phase 8 planning currently has no real number to consult — this is worth surfacing
  to Phase 8's own research/planning pass rather than silently treated as "zero" or "acceptable."

Recommendation: neither gap blocks re-confirming Phase 7's own five success criteria (all five are
independently satisfied per the section above, with no dependency on M2/M4's outcome for the code
that shipped). But Phase 8 planning should not proceed as if M2/M4 were run — flag this explicitly in
Phase 8's own CONTEXT/RESEARCH rather than let it silently vanish.

### Gap 3 — 07-UAT.md has one test still pending

`.planning/phases/07-host-faithful-checkout-seeding/07-UAT.md` (status: `testing`) shows 6/7 tests
passed and one pending:

```
### 7. PERF-01 benchmark holds — no wall-clock or disk regression
expected: Cached-build wall-clock and disk usage on the reference project show no regression
          versus the pre-seeding baseline, or the regression is surfaced as a blocking finding
          rather than shipped silently.
result: [pending]
```

This is almost certainly stale relative to `07-BENCHMARK.md` (which already proves this exact claim
with real numbers), but the UAT file itself was never updated to reflect it. A re-planning/
verification pass should close this test explicitly (mark `result: pass`, `source: 07-BENCHMARK.md`)
rather than leave a `[pending]` result sitting alongside a phase marked complete in `STATE.md`.

### Gap 4 — Recorded process notes worth carrying forward (already in STATE.md, not repeated here as new findings)

`STATE.md`'s "Phase 7 Process Notes" section already documents two items a re-planner should be aware
of but does not need to re-investigate: (1) a `git stash` self-correction during 07-02 (recovered,
verified via `git diff`/`git stash list`), and (2) an Xcode auto-migration side effect
(`.xcscheme` `version = "1.7"` → `"1.8"`) on the reference project during the benchmark, caught and
reverted post-hoc by the orchestrator rather than the executor. Both are closed; listed here only so
this RESEARCH.md doesn't omit them from the "what's not in the SUMMARYs" inventory the phase
description asked for — they are not gaps in the code, they are process learnings already filed.

### Gap 5 — Deliberate exclusions confirmed correct, not gaps

Both plans record deliberate omissions that are correct per CONTEXT.md, re-confirmed against the
locked decisions in `07-CONTEXT.md`:
- `-onlyUsePackageVersionsFromResolvedFile` was never added (`07-01-SUMMARY.md` key-decisions) —
  matches CONTEXT.md's explicit "Do NOT enable" instruction verbatim.
- No pins/drift-parsing method was added to `ResolvedGraph` — correctly deferred to Phase 8 (FID-03).
- Lock acquire/release helpers were duplicated in `Installer::Build`/`Installer::Use` rather than
  lifted to the shared `Installer` base class — a Claude's-Discretion-scope choice (module/class
  boundaries), not a defect.

## Runtime State Inventory

Not applicable — this phase is neither a rename nor a refactor/migration; it added new seeding
behavior gated entirely behind `nil`-default kwargs. No renamed identifiers, no data migration.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | RSpec (`bundle exec rspec`) |
| Config file | `.rspec` / `spec_helper.rb` (pre-existing, unchanged by Phase 7) |
| Quick run command | `bundle exec rspec spec/resolved_graph_spec.rb spec/build_pipeline_seeding_spec.rb spec/build_lock_spec.rb` |
| Full suite command | `bundle exec rspec` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| FID-02 | Host graph seeded verbatim before first `describe` call | unit | `bundle exec rspec spec/build_pipeline_seeding_spec.rb spec/resolved_graph_spec.rb` | ✅ (re-run this session: pass) |
| FID-05 | Vendored-`.xcodeproj` reported not-graph-pinned | unit | `bundle exec rspec spec/build_pipeline_seeding_spec.rb` | ✅ |
| PERF-01 | No wall-clock/disk regression | manual/integration | one-time real benchmark, `07-BENCHMARK.md` | ✅ (already run, PASS verdict recorded) |

### Sampling Rate
- **Per task commit:** already exercised historically; no new commits pending for this phase
- **Per wave merge:** full suite (`bundle exec rspec`) — re-run this session, 341/0
- **Phase gate:** `/gsd-verify-work 7` — not yet run (Gap 1 above)

### Wave 0 Gaps
None — existing test infrastructure (`spec/resolved_graph_spec.rb`, `spec/build_pipeline_seeding_spec.rb`,
`spec/build_lock_spec.rb`, `07-BENCHMARK.md`) already covers all three of this phase's requirement IDs.
The only outstanding validation action is running the formal `/gsd-verify-work` gate (Gap 1), not
writing new tests.

## Common Pitfalls

Already fully documented in the shipped code's own comments (re-read this session, not paraphrased):
Pitfall 9 (per-package clone fan-out, closed by `clones_dir`), Pitfall 11 (vendored-`.xcodeproj`
ignores `Package.resolved`, closed by `vendored_xcodeproj?` classification), Pitfall 15 (watch
re-entrancy deleting checkouts mid-build, closed by the shared `flock`). No new pitfalls were
discovered in this research pass beyond what the code comments and `07-BENCHMARK.md` already record
(the pre-existing Class-E Firebase Analytics rename gap, explicitly out of scope and unrelated to
this phase's changes).

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The 07-UAT.md pending test (#7) is stale rather than reflecting a genuine unresolved regression | Gap 3 | Low — 07-BENCHMARK.md's real measured numbers directly answer the same question with a PASS verdict; if wrong, the benchmark itself (not just the UAT file) would need re-running |

All other claims in this document are `[VERIFIED]` against source files read directly in this
session, or reproduced via a live `bundle exec rspec` run in this session — no `[CITED]` or
unverified `[ASSUMED]` claims about the shipped mechanism itself.

## Open Questions

1. **Should M2/M4 be run retroactively before Phase 8 planning starts, or is the current design
   accepted as-is without them?**
   - What we know: the design shipped without either measurement; nothing in the shipped code
     depends on their outcome (Phase 7's own success criteria are independently satisfied).
   - What's unclear: whether Phase 8's drift read-back should assume `run_with_scheme`'s
     vendored-project path has no realized-version write-back source (M4's question) or should
     independently probe it as part of Phase 8's own research.
   - Recommendation: surface this explicitly to Phase 8's discuss-phase/research rather than let the
     user re-decide it here — it's Phase 8's design input, not Phase 7's.

2. **Does the 07-UAT.md pending result need a source citation added before the phase can be marked
   verified?**
   - What we know: `07-BENCHMARK.md` already contains a PASS verdict for the identical claim.
   - What's unclear: whether the GSD verification tooling requires the UAT file itself to be updated
     for the phase to formally close, or whether `/gsd-verify-work` will do this as part of its own run.
   - Recommendation: let `/gsd-verify-work 7` resolve this; do not hand-edit 07-UAT.md preemptively.

## Sources

### Primary (HIGH confidence — read directly this session)
- `lib/spm_cache/spm/resolved_graph.rb` (full file)
- `lib/spm_cache/spm/build_pipeline.rb` (full file)
- `lib/spm_cache/installer/build.rb` (full file)
- `lib/spm_cache/installer/use.rb` (full file)
- `lib/spm_cache/core/config.rb` (lines 60-110)
- `lib/spm_cache/spm/build.rb` (lines 85-115)
- `.planning/phases/07-host-faithful-checkout-seeding/07-01-SUMMARY.md`
- `.planning/phases/07-host-faithful-checkout-seeding/07-02-SUMMARY.md`
- `.planning/phases/07-host-faithful-checkout-seeding/07-BENCHMARK.md`
- `.planning/phases/07-host-faithful-checkout-seeding/07-UAT.md`
- `.planning/phases/07-host-faithful-checkout-seeding/07-CONTEXT.md`
- `.planning/phases/07-host-faithful-checkout-seeding/.continue-here.md`
- `.planning/ROADMAP.md` (Phase 7 section)
- `.planning/REQUIREMENTS.md`
- `.planning/STATE.md`
- Live command: `bundle exec rspec` (341 examples, 0 failures) and targeted spec run (32 examples, 0 failures)

### Secondary / Tertiary
None used — this phase required only direct source verification, no external library research.

## Metadata

**Confidence breakdown:**
- Standard stack: N/A — no new dependencies added
- Architecture: HIGH — every claim traced to source read this session, with line ranges and verbatim quotes
- Pitfalls: HIGH — pitfalls already documented in shipped code comments, cross-checked against 07-BENCHMARK.md
- Gap analysis (M2/M4/UAT): HIGH — confirmed absent via direct grep across all four phase-plan/summary files

**Research date:** 2026-08-29
**Valid until:** Effectively permanent for this phase's own scope (code is committed, tests pass,
no further implementation planned) — re-verify only if Phase 8/9 work causes any of the cited files
to change.
