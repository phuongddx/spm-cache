# Phase 5: Auto-Sync Watcher - Research

**Researched:** 2026-08-24
**Domain:** Filesystem-watch auto-sync loop (Ruby stdlib polling) — VERIFICATION-SCOPED (implementation shipped at d7c0fff)
**Confidence:** HIGH (all core claims grounded in source read this session + local experiments; two flagged inferences in Assumptions Log)

## Summary

Phase 5's implementation is already shipped at commit `d7c0fff` (verified: `git show --stat d7c0fff` = exactly 3 files, 308 insertions: `lib/spm_cache/core/watcher.rb` 115 lines, `lib/spm_cache/command/watch.rb` 56 lines, `spec/watch_spec.rb` 137 lines). The plan must NOT re-implement; it must (a) prove the 5 ROADMAP criteria against live code, (b) record the USER-ACCEPTED mechanism deviation (mtime+size polling supersedes the FSEvents-via-Fiddle design), and (c) close a fully-catalogued doc-drift list. The watcher works via a **fixed-interval polling loop** — `sleep debounce; compare signatures; regenerate if different` — with constructor-injected `installer_factory` and `out` sink seams making `run_once` fully hermetic.

Three findings need the planner's explicit attention. **First**: there is NO `Signal.trap` anywhere in `lib/` (verified by grep); SIGINT works only via Ruby's default-disposition `Interrupt` hitting `rescue Interrupt` (watcher.rb:68) → exit 0 (empirically confirmed: exit status 0), but SIGTERM kills the process with status 143 — no rescue, no flush (empirically confirmed). "Flush a pending event" is not implemented for either signal. **Second**: `Installer::Use#perform_install` calls `integrate_proxy_into_project` on EVERY run — fast-path included — ending in an unconditional `project.save` (installer.rb:468) that rewrites `project.pbxproj`, a watched file; combined with the loop's snapshot-BEFORE-regenerate ordering (watcher.rb:58) and 2s poll interval, this forms a credible **self-trigger loop** inference (regeneration itself bumps the signature every cycle) — needs one empirical smoke run to settle defect vs false alarm. **Third**: "debounce" is a poll interval, not a wait-then-check-once debounce; bursts inside one window collapse (criterion 2's substance holds for Xcode's sub-second write flurries), bursts spanning windows do not.

**Primary recommendation:** Build the plan as criterion-by-criterion proofs over the live code: a live-loop smoke test (real or fixture `.xcodeproj`, ~6–10s) to settle the self-trigger question and SIGINT/SIGTERM exit codes, targeted hermetic specs only for currently-untested contracts (loop rescue path, burst collapse), the dated ROADMAP criterion-5 amendment, and the doc-drift corrections below (PROJECT.md, STATE.md, REQUIREMENTS.md, AGENTS.md, research/SUMMARY.md, phase SUMMARY numerics, README `watch` entry).

<user_constraints>
## User Constraints (from 05-CONTEXT.md)

### Locked Decisions
- **Watch mechanism (USER DECISION 2026-08-24 — supersedes the earlier FSEvents design note):** mtime+size POLLING (Ruby stdlib only) is the accepted mechanism. The earlier locked decision ("native FSEvents via Fiddle") and ROADMAP criterion 5's mechanism wording are SUPERSEDED by this acceptance; AUTO-05's substance ("no new gem dependency") is satisfied. Poll interval + debounce (default 2s) collapses burst saves; approach is proven via the prior `use --watch` polling.
- ROADMAP criterion 5 must be amended with a dated inline record of this deviation; PROJECT.md/STATE.md claims of "native FSEvents" must be corrected to polling.
- **Loop semantics (accepted as shipped):** Transient regeneration failure → logged with timestamp, loop continues (criterion 4). Fatal conditions only (project deleted/unwatchable) → exit non-zero. SIGINT/SIGTERM flush a pending event and exit 0 (verify the actual trap wiring in Watcher#run).
- **Debounce (accepted as shipped):** Default 2 seconds, `--debounce=SECONDS` flag — matches the locked decision.
- **`--once` (accepted as shipped):** Single sync-and-exit for CI/testing; fully unit-testable via injected `installer_factory` (no poll loop, no OS API).

### Claude's Discretion
- Verification task granularity; proof organization; doc phrasing for the deviation records.

### Deferred Ideas (OUT OF SCOPE)
- FSEvents-via-Fiddle binding — rejected 2026-08-24 (polling accepted; latency adequate for a dev tool)
- Retry-with-backoff on transient failures — rejected 2026-08-24 (continue-on-error log suffices)
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| AUTO-01 | `watch` watches Package.resolved + project.pbxproj and auto-regenerates via `Installer::Use` on a non-empty diff, no manual re-run | Watched-file resolution verified (watcher.rb:87-93 recursive globs); regeneration delegates to `Installer::Use#perform_install` (watcher.rb:78-81, watch.rb:37); initial unconditional sync + diff-triggered loop verified (watcher.rb:50-67). Spec coverage: partial (watch_spec.rb:46-50, 60-77). **Caveat: self-trigger inference may undermine "non-empty diff" reading — see Pitfall 1.** |
| AUTO-02 | Burst saves collapse via configurable debounce (default 2s, `--debounce`) to one regeneration | `DEFAULT_DEBOUNCE = 2` (watcher.rb:15), flag verified (watch.rb:19, 26). Mechanism is a poll interval, not wait-then-check-once — bursts within one window collapse; spanning windows do not (see Debounce Mechanics). Specs cover value storage/parse (watch_spec.rb:109-114, 118-127), not collapse behavior — gap. |
| AUTO-03 | `watch --once` performs single sync-and-exit without the watch loop | `run_once` verified (watcher.rb:36-43): no loop, no sleep, no OS API; command branch verified (watch.rb:41-43). Hermetic specs prove it (watch_spec.rb:52-58, 98-107). Errors propagate uncaught → CI fails loudly. Strongest criterion. |
| AUTO-04 | Loop continues on transient errors (logs with timestamp), exits non-zero only on fatal; SIGINT/SIGTERM flush pending events and exit 0 | Transient path verified (watcher.rb:60-66, timestamp at :65). Fatal path verified for INITIAL regenerate failure (watcher.rb:70-73 re-raise) — but mid-watch project deletion is logged transient and idles, NOT a non-zero exit (see Fatal vs Transient). **Signal claim NOT met as written**: no trap wiring; SIGINT→exit 0 (no flush), SIGTERM→exit 143 (empirically verified). Needs dated amendment or minimal fix — Open Question 1. |
| AUTO-05 | (Amended substance) No new gem dependency; `--once` unit-testable without OS API | d7c0fff touched exactly 3 files, gemspec untouched; runtime deps are claide/xcodeproj/parallel/tty-cursor/tty-screen/CFPropertyList (gemspec:29-34) — none added for watch. `--once` hermetic spec exists (watch_spec.rb:52-58). Mechanism wording "binds FSEvents via Ruby Fiddle" (REQUIREMENTS.md:27, ROADMAP.md:88) is superseded → dated amendment mandated. |
</phase_requirements>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Change detection (what/when to watch) | Core (Core::Watcher) | — | Pure stdlib polling; policy lives in one class |
| SPM-graph regeneration | Installer (Installer::Use#perform_install) | Core (invokes via factory) | Watcher must NOT duplicate integration logic; factory seam keeps it testable |
| CLI surface / flags / project discovery | Command (Command::Watch, CLaide) | — | `--once`/`--debounce` parsing, `.xcodeproj` discovery, `GeneralError` on none |
| CI single-shot entry | Command::Watch `--once` → Watcher#run_once | — | No loop, no signals, no OS API — the testable path |
| Logging/output | Core::Watcher via injected `out` IO | Core::UI (command layer) | Watcher writes plain `puts` to `@out`; command layer uses Core::UI |
| Legacy watch mode | Command::Use#run_watch (`use --watch`) | — | Pre-existing duplicate loop; NOT migrated to Core::Watcher (see Pitfall 7) |

## Verified Implementation Anatomy

### The poll loop (watcher.rb:45-74) — verbatim mechanics

```ruby
# lib/spm_cache/core/watcher.rb:46-74
def run
  info "Watching #{watched_files.join(', ')} for changes (Ctrl-C to stop)..."

  # Initial sync so the proxy is current before watching starts.
  @last_signatures = current_signatures
  regenerate

  loop do
    sleep debounce
    current = current_signatures
    next if current == @last_signatures

    @last_signatures = current
    info "\n[watch] SPM graph changed, re-integrating..."
    begin
      regenerate
    rescue StandardError => e
      warn_msg "[#{Time.now}] [watch] integration failed: #{e.message}"
    end
  end
rescue Interrupt
  info "\n[watch] stopped."
rescue StandardError => e
  warn_msg "[watch] fatal: #{e.message}"
  raise
end
```

[VERIFIED: lib/spm_cache/core/watcher.rb:46-74]

Sequence: announce → snapshot signatures → **initial unconditional regenerate** → loop { sleep `debounce` → compare → if different: update `@last_signatures` THEN regenerate (inner rescue for StandardError) }.

**Signature** (watcher.rb:99-104): `[path, stat.mtime.to_i, stat.size]` — mtime truncated to integer seconds. [VERIFIED: lib/spm_cache/core/watcher.rb:99-104, quoted verbatim in Code Examples]

**Watched-file resolution** (watcher.rb:87-93): recursive `Dir.glob(project_path + '**/Package.resolved')` and `'**/project.pbxproj'`, first existing match each, `[resolved, pbxproj].compact`. Resolved ONCE in the constructor (`@watched_files = resolve_watched_files`, watcher.rb:30) — files deleted mid-watch yield `nil` signatures, not re-resolution. [VERIFIED: lib/spm_cache/core/watcher.rb:30,87-93]

**run_once** (watcher.rb:36-43): `signatures = current_signatures; return false if signatures.empty?; regenerate; @last_signatures = signatures; true`. No diff-check, no sleep — cheap because `perform_install` has its own fast path ("No changes detected. Proxy package up to date.", installer/use.rb:21-23, gated by `fast_path?` at use.rb:45-51). Returns `false` only when NO watched files were resolved at construction. [VERIFIED: lib/spm_cache/core/watcher.rb:36-43]

### Debounce mechanics — poll interval, not wait-then-check-once

Answering the plan's direct question: **burst-collapsing is NOT implemented as wait-then-check-once.** There is no per-change timer and no quiet-period wait. `debounce` is the fixed sleep at the TOP of each iteration (watcher.rb:54). Consequences:

- A burst of saves landing **within one poll window** is seen only at the window's end, comparing against the pre-burst snapshot → **one regeneration** using the final file state. This satisfies criterion 2's substance for Xcode's real behavior (package-add rewrites both files in a sub-second flurry).
- A burst **spanning two windows** (changes at t=1 and t=3 with 2s polls) triggers **two** regenerations. True debouncing would coalesce; this does not.
- Regeneration happens **immediately** upon detecting a diff at poll time — no additional settle wait.
- Changes occurring **during** regeneration are caught next poll, because `@last_signatures = current` executes BEFORE `regenerate` (watcher.rb:58-61) — the same property CONCERNS.md:107 frames as a feature. It becomes a hazard when regeneration itself writes a watched file (Pitfall 1).
- The legacy `use --watch` loop is hardcoded `sleep 2` with NO debounce flag and watches only Package.resolved (command/use.rb:66). [VERIFIED: lib/spm_cache/command/use.rb:50-91]

### Signal handling — the trap wiring question, answered definitively

**There is no `Signal.trap` call anywhere in `lib/`** (verified: `grep -rn "Signal.trap\|trap(" lib/` → no matches). The wiring is:

- **SIGINT**: Ruby's default disposition raises `Interrupt` in the main thread (interrupting `sleep` immediately) → caught by `rescue Interrupt` (watcher.rb:68) → prints `"\n[watch] stopped."` → method returns normally → **exit 0**. Empirically confirmed with a local child-process experiment: `ruby --disable-gems -e 'begin; sleep 10; rescue Interrupt; puts "caught"; end'` + `kill -INT` → **status 0**. [VERIFIED: local experiment + lib/spm_cache/core/watcher.rb:68-69]
- **SIGTERM**: default disposition terminates the process immediately — no Ruby-level rescue runs, no flush. Same experiment + `kill -TERM` → **status 143** (128+15). This contradicts criterion 4's "SIGINT/SIGTERM flush + exit 0" for SIGTERM. [VERIFIED: local experiment]
- **"Flush a pending event"**: NOT implemented for either signal. `rescue Interrupt` does no final signature check; a change made less than `debounce` seconds before the signal is silently dropped. Mitigation: `run` performs an initial unconditional sync on startup, so the next `watch`/`use` run heals the dropped change — nothing is lost long-term.
- Ordering note: `Interrupt` is not a `StandardError`, so the inner continue-on-error rescue can never swallow it — the rescue ordering is correct.

CONTEXT.md itself flagged this: "SIGINT/SIGTERM flush a pending event and exit 0 (**verify the actual trap wiring in Watcher#run**)". Verification result: trap wiring ABSENT; SIGINT exit-0 achieved incidentally via default disposition; SIGTERM unclean (143); flush absent. The planner must either record this as a dated accepted deviation (consistent with "accepted as shipped" + "do NOT re-implement") or schedule a minimal fix (`Signal.trap('TERM') { raise Interrupt }` ≈ 1 line, plus optionally a final signature check for true flush). See Open Question 1.

### Fatal vs transient error paths — what the code actually does

| Path | Where | Behavior | Conforms to criterion 4? |
|------|-------|----------|--------------------------|
| Regeneration fails INSIDE loop (build error, etc.) | watcher.rb:62-66 inner `rescue StandardError` | Logged `"[#{Time.now}] [watch] integration failed: ..."` → loop continues | ✓ transient (timestamp ✓) |
| INITIAL regenerate fails (before loop) | watcher.rb:51 — outside any begin | Outer `rescue StandardError` (watcher.rb:70-73) → `"fatal: ..."` → re-raise → non-zero exit | ✓ fatal |
| Project missing BEFORE start | watch.rb:33 `raise Core::GeneralError, 'No .xcodeproj found...'` → watched_files=[] if .xcodeproj exists but has no SPM graph | CLI error exit / loop mode still does initial regenerate on empty watch list | Partial (see below) |
| Project deleted MID-watch | signatures → `[nil, nil]` ≠ last → "changed" → `verify_projects!` raises `"Project not found: ..."` (installer.rb:103, RuntimeError < StandardError) | **Inner rescue** → logged as transient → `@last_signatures` already updated to nils → loop idles silently | ✗ does NOT exit non-zero (contradicts "project deleted → fatal" reading) |
| `current_signatures` / `sleep` errors inside loop, outside inner begin | watcher.rb:54-55 | Outer rescue → fatal re-raise. TOCTOU: `File.exist?` then `File.stat` (watcher.rb:100-102) — a file vanishing between them raises Errno::ENOENT → fatal. Negative `debounce` → `sleep` ArgumentError → fatal | Edge; narrow |
| Non-StandardError inside loop | — | Not caught by inner rescue → outer is also StandardError-only → propagates (fatal) | ✓ |

[VERIFIED: lib/spm_cache/core/watcher.rb:51-73, lib/spm_cache/installer.rb:101-104 (`raise "Project not found: #{@project_path}"`), lib/spm_cache/command/watch.rb:33]

Honest summary for criterion 4: transient-continue ✓; timestamp ✓; fatal-exit ✓ only for initial-phase failures — **mid-watch deletion behaves transient**, then the watcher goes quiet (nil signatures compare equal). The planner should record this precise behavior rather than the ROADMAP's simplified wording.

### Test seams (verified in spec/watch_spec.rb)

- **`installer_factory:`** — Proc returning anything responding to `perform_install` (watcher.rb:20-21 doc; used at watch.rb:37 in production: `->(path) { Installer::Use.new(project: path) }`). Spec `FakeInstaller` (spec:12-24) records `call_count`, optional `should_fail`.
- **`out:`** — IO sink; specs inject `StringIO.new`; both `info` and `warn_msg` write via `@out.puts` (watcher.rb:106-112). Note: warn lines go to the SAME sink as info (stdout in production — not stderr).
- **Loop avoidance trick** — the specs never run `run`. Change detection simulates ONE iteration via `watcher.send(:current_signatures)` + `instance_variable_get(:@last_signatures)` (spec:74-76, comment: "Simulate one poll iteration manually (avoids a blocking loop in tests)"). This is the established pattern any new loop-behavior spec must follow.
- **Command specs** use CLaide `.parse` + ivar inspection (spec:118-127) and one real `cmd.run` in an empty tmpdir for the GeneralError (spec:129-136).

[VERIFIED: spec/watch_spec.rb:12-44,74-76,118-136; lib/spm_cache/command/watch.rb:37]

### Spec inventory — the "12 specs" claim decoded

`bundle exec rspec spec/watch_spec.rb` reports **12 examples**, but only **9** live in watch_spec.rb; `spec/spec_helper.rb:5-17` defines a global `RSpec.describe SPMCache` with 3 examples ("has a version", "has ROOT constant", "resolves ROOT to the repo root...") included in every spec file run. [VERIFIED: rspec --dry-run --format documentation output 2026-08-24; spec/spec_helper.rb:5-17]

The 9 file-authored examples: (1) watches Package.resolved and project.pbxproj [:46]; (2) run_once performs a single integration [:52]; (3) detects a change to Package.resolved between signatures [:60]; (4) continue-on-error contract [:79]; (5) handles a missing project gracefully [:98]; (6) accepts a custom debounce value [:109]; (7) parses --once and --debounce flags [:118]; (8) defaults debounce to the Watcher default [:124]; (9) errors when no .xcodeproj is found [:129]. All pass (`12 examples, 0 failures`).

**Coverage vs the 5 criteria:** AUTO-03 well covered; AUTO-01 partially (resolution + one simulated diff, no loop/regeneration-link proof); AUTO-02 value-only (no collapse-behavior spec); AUTO-04 partial (the loop's actual rescue path is NEVER executed by any spec — spec:79-96 proves run_once RAISES and that a fresh watcher recovers, i.e. the contract around the loop, not the loop); signals untested; fatal-exit untested; AUTO-05 satisfied by construction.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Ruby stdlib (sleep/File.stat/Dir.glob) | Ruby ≥3.1 (gemspec floor; local 3.2.3) | The entire watch mechanism | USER-ACCEPTED decision 2026-08-24; zero deps, portable, proven via legacy `use --watch` |
| CLaide | ~1.1 (gemspec:29) | `watch` subcommand + flag parsing | Project's existing command framework; `def self.options ... .concat(super)` pattern (watch.rb:16-21) |
| Xcodeproj | ≥1.26.0 (gemspec:30) | `perform_install` integration writes (installer.rb:366) | Existing regeneration target; watcher adds no direct use |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| RSpec | ~3.12 (dev, gemspec:37) | Verification specs | Existing suite; hermetic patterns established |
| StringIO / tmpdir / fileutils (stdlib) | — | Spec fixtures/sinks | Every watch spec (spec:4-6) |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| mtime+size polling | FSEvents via Fiddle | REJECTED by user 2026-08-24 (deferred list); polling latency (≥2s) adequate for dev tool |
| mtime+size polling | `listen` gem | Rejected from the start — new runtime dep violates the zero-dep principle (PROJECT.md:60 intent survives even though its FSEvents mechanism wording doesn't) |
| Fixed-interval poll | Per-change quiet-period debounce | Would collapse spanning-window bursts too; more state; NOT needed for accepted scope — do not add |

**Installation:** none — zero new packages this phase.

**Version verification:** No packages added at d7c0fff (git show --stat: only the 3 source files; gemspec untouched). Runtime dependency list verified at spm_cache.gemspec:29-34: `claide ~1.1`, `xcodeproj >=1.26.0`, `parallel ~1.23`, `tty-cursor ~0.7`, `tty-screen ~0.8`, `CFPropertyList ~3.0`. [VERIFIED: git + spm_cache.gemspec:29-34]

## Package Legitimacy Audit

Not applicable — this phase installs zero external packages (d7c0fff touched exactly 3 files; no gemspec/lockfile change). All recommended "stack" above is existing project dependencies or Ruby stdlib.

## Architecture Patterns

### System Architecture Diagram

```mermaid
flowchart TD
    A[bin/spm-cache watch] --> B[Command::Watch\nparse --once / --debounce=SECONDS]
    B --> C{.xcodeproj found?}
    C -- no --> D[raise GeneralError\nexit non-zero]
    C -- yes --> E[Core::Watcher.new\nresolve_watched_files ONCE:\nPackage.resolved + project.pbxproj]
    E --> F{--once?}
    F -- yes --> G[run_once:\nregenerate unconditionally\nif any watched file, else false]
    F -- no --> H[run:\ninitial sync\nsnapshot THEN regenerate]
    H --> I[sleep debounce\ndefault 2s]
    I --> J{signatures changed?\n[path, mtime.to_i, size]}
    J -- no --> I
    J -- yes --> K[update @last_signatures\nTHEN regenerate]
    K -- StandardError --> L[log '[timestamp] integration failed'\ncontinue loop]
    L --> I
    K --> I
    G & H --> M[Installer::Use#perform_install\nfast-path or full regeneration\nALWAYS ends project.save → pbxproj write]
    H -.SIGINT.-> N[rescue Interrupt → 'stopped.' → exit 0]
    H -.SIGTERM.-> O[default kill → exit 143\nno rescue, no flush]
```

The K→I back-edge plus M's pbxproj write is the self-trigger loop candidate (Pitfall 1).

### Recommended Project Structure
No new files required (verification-scoped). Existing layout confirmed correct:
```
lib/spm_cache/core/watcher.rb      # poll loop, signatures, run_once (115 lines)
lib/spm_cache/command/watch.rb     # CLaide subcommand (56 lines)
spec/watch_spec.rb                 # 9 examples (137 lines)
```

### Pattern 1: Injectable factory + IO sink
**What:** Constructor takes `installer_factory:` (Proc) and `out:` (IO) so the watcher is testable without Xcode, builds, or stdout capture. **When to use:** any new loop-behavior spec must extend, not bypass, these seams. **Example:** watch.rb:35-39 production wiring vs spec:41-44 fake wiring (quoted in Verified Implementation Anatomy).

### Pattern 2: Simulated single poll iteration
**What:** Never run the blocking loop in specs; assert one iteration's decision via `send(:current_signatures)` vs `instance_variable_get(:@last_signatures)`. **When to use:** any criterion-2 burst-collapse spec — write file twice inside one window, run one simulated poll, expect exactly 1 `perform_install` from the real `run`-shaped logic (or extract/verify via a 2-3s live subprocess smoke).

### Pattern 3: Dated inline ROADMAP amendment (project precedent)
**What:** Phases 2-4 corrected drifted criteria by appending "— amended 2026-08-24: ..." to the criterion line (ROADMAP.md:38,40,41,54,69-71). Criterion 5 (ROADMAP.md:88) and the signal clause of criterion 4 (ROADMAP.md:87) must follow the same shape.

### Anti-Patterns to Avoid
- **Adding a real sleep-loop spec**: any spec invoking `Watcher#run` unmodified blocks forever or for `debounce` seconds — flaky and slow. Use the simulated-iteration pattern or a subprocess smoke with a hard timeout.
- **Editing 05-CONTEXT.md to fix its "12 specs" count**: CONTEXT is the user's decision record — note the discrepancy in SUMMARY, don't rewrite history in CONTEXT.
- **Migrating legacy `use --watch` to Core::Watcher "while at it"**: out of scope (surgical-changes principle); catalogue the duplication only.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| SPM-graph regeneration | Any regeneration logic in the watcher | `Installer::Use#perform_install` via factory | Already the single integration path; has fast-path; watcher correctly contains none of it |
| FSEvents/Fiddle native binding | ~80-line FFI binding | mtime+size polling (stdlib) | User-rejected 2026-08-24; portability, zero deps |
| Flag parsing | OptionParser / manual ARGV | CLaide `self.options` + `argv.flag?/option` | Project convention; `.concat(super)` preserves base flags (watch.rb:16-27) |
| Event queue / quiet-period debounce framework | Timer state machine | Fixed-interval poll (shipped) | Accepted scope; bursts within a window already collapse |
| pbxproj rewriting | Raw plist manipulation | Xcodeproj gem (already in use, installer.rb:366) | Object model + field bugs already solved there |

**Key insight:** the moat claim is that the watcher reuses the exact `use` path — any logic duplicated into the watcher erodes that guarantee (the legacy `use --watch` duplicate is the cautionary example already in the repo).

## Runtime State Inventory

Not applicable — verification-scoped phase; no rename/refactor/migration. No stored data, live service config, OS-registered state, secrets, or build artifacts embed the corrected doc strings. Doc corrections are plain file edits (git-tracked).

## Common Pitfalls

### Pitfall 1: Self-trigger loop — regeneration writes a watched file (TOP VERIFICATION RISK)
**What goes wrong:** `perform_install` ALWAYS ends with `integrate_proxy_into_project` → unconditional `project.save` (installer.rb:468) rewriting `project.pbxproj` — even on the fast path (installer/use.rb:31-33 run `gen_supporting_files; integrate_proxy_into_project; gen_cachemap_viz` outside the fast-path `else`). The watcher snapshots signatures BEFORE regenerating (watcher.rb:50-51 initial, :58 in-loop), so every regeneration leaves pbxproj's mtime newer than the snapshot; the next poll (≥2s later, guaranteeing an integer-second difference vs `mtime.to_i`) sees a "change" and regenerates again → potential infinite ~2s loop of "SPM graph changed, re-integrating..." + fast-path no-ops.
**Why it happens:** the legacy `use --watch` watched ONLY Package.resolved (which regeneration never writes) — immune. Core::Watcher newly adds pbxproj to the watch set; nobody has run the loop against a real integrated project yet (feature never shipped to users).
**How to avoid:** verify empirically FIRST (see below) before amending criterion 1 as "proven". If confirmed, the minimal fix is re-snapshotting after regenerate (`@last_signatures = current_signatures` post-regen) — one-line reorder, matching the Phase 2/3 precedent of fixing defects found in verification.
**Warning signs:** "SPM graph changed" lines every ~2s with no user activity in a live run; watch_spec unaffected (FakeInstaller writes nothing).
**Evidence status:** every mechanism link VERIFIED individually (save call installer.rb:468; always-called use.rb:31-33; snapshot order watcher.rb:50-51,58; 2s interval watcher.rb:15,54); the loop conclusion is [INFERENCE] — settle with one live smoke: fixture `.xcodeproj` + real `Installer::Use` (or the spm-cache test harness), run `watch` 6-10s, count regeneration log lines (expect 1 = initial only).

### Pitfall 2: SIGTERM is not SIGINT
**What goes wrong:** criterion 4 says "SIGINT/SIGTERM flush + exit 0"; shipped code handles SIGINT only (via default-disposition Interrupt → `rescue Interrupt`), no `Signal.trap` exists. SIGTERM → exit 143, no flush (empirically verified).
**How to avoid:** decide amendment-vs-fix explicitly (Open Question 1). If fixing: `Signal.trap('TERM') { raise Interrupt }` preserves the clean-exit path with one line; true flush needs a final signature check in the Interrupt handler.
**Warning signs:** any plan prose asserting "trap wiring exists" — it does not; grep-verified.

### Pitfall 3: Blocking sleep / clock dependence in specs
**What goes wrong:** (a) specs that call `run` block; (b) mtime-based assertions can be flaky — the signature truncates to integer seconds (`mtime.to_i`), so same-second same-size rewrites are invisible.
**Why:** APFS has ns-resolution mtimes but the signature deliberately coarsens; the existing suite handles this with exactly one `sleep 1` ("ensure mtime advances by >= 1s on coarse filesystems", spec:72) and by also varying content size in the change-detection spec (spec:71).
**How to avoid:** keep loop-behavior specs on the simulated-iteration pattern; when asserting change detection, vary BOTH size and mtime (write different-length content + sleep 1), or compare `Time.now`-independent size alone.

### Pitfall 4: `--debounce` coercion accepts garbage
**What goes wrong:** `(argv.option('debounce') || DEFAULT).to_i` (watch.rb:26) — `--debounce=abc` → 0 → tight spin (sleep 0 loop, CPU burn); negative → `sleep` ArgumentError → spurious "fatal" exit. No validation, no clamping.
**How to avoid:** verification records it as a minor accepted sharp edge or adds a clamp (`[value, 0.1].max`-style) — flag for the planner; do not silently expand scope.

### Pitfall 5: Kill-signal testing strategy
**What goes wrong:** installing real signal traps inside the RSpec process interferes with the runner's own INT handling; `Process.kill` on self is unreliable.
**How to avoid:** test signals via a child process: spawn `bundle exec bin/spm-cache watch --once`-shaped or a tiny script wiring the real `Watcher#run` with a FakeInstaller, `Process.kill('INT', pid)`, `Process.wait`, assert `wait` status 0 and output includes "stopped."; repeat with TERM asserting today's 143 (documents the gap) or 0 after any fix. Wrap with a timeout so a bug can't hang the suite.

### Pitfall 6: "Debounce" prose overclaiming
**What goes wrong:** CONCERNS.md:106 ("Rapid successive saves within the debounce window are collapsed correctly (single regeneration after the last change)") reads like quiet-period debounce; the code is interval polling. Doc corrections should not propagate the stronger claim into ROADMAP/SUMMARY amendments — phrase as "changes within one poll window collapse into one regeneration".
**How to avoid:** use the precise mechanics language from this research in every amendment text.

### Pitfall 7: Duplicate watch loops diverge
**What goes wrong:** legacy `use --watch` (command/use.rb:50-80) still has its own hardcoded polling loop (watches only Package.resolved, `sleep 2`, signature `[mtime.to_i, size]` WITHOUT path). Core::Watcher did not replace it despite SUMMARY's "refactors that into" phrasing. Future fixes to one loop won't reach the other.
**How to avoid:** catalogue in SUMMARY as known duplication; migrating is out of scope for this verification-scoped phase (deferred unless the user asks).

### Pitfall 8: warn goes to stdout
**What goes wrong:** `warn_msg` writes to `@out` (default `$stdout`) — identical to `info` (watcher.rb:106-112). Scripts piping stdout for structured logs get failures mixed into the same stream; criterion 4's "logs with timestamp" holds but not to stderr.
**How to avoid:** note as accepted behavior in verification records; changing sinks is cosmetic scope creep.

## Code Examples

### Signature comparison (the change-detection contract)
```ruby
# Source: lib/spm_cache/core/watcher.rb:99-104 (verbatim)
def file_signature(path)
  return nil unless path && File.exist?(path)

  stat = File.stat(path)
  [path, stat.mtime.to_i, stat.size]
end
```

### Watched-file resolution (AUTO-01 file set)
```ruby
# Source: lib/spm_cache/core/watcher.rb:87-93 (verbatim)
def resolve_watched_files
  resolved = Dir.glob(File.join(project_path, '**/Package.resolved'))
                .find { |f| File.exist?(f) }
  pbxproj = Dir.glob(File.join(project_path, '**/project.pbxproj'))
               .find { |f| File.exist?(f) }
  [resolved, pbxproj].compact
end
```

### run_once (AUTO-03)
```ruby
# Source: lib/spm_cache/core/watcher.rb:36-43 (verbatim)
def run_once
  signatures = current_signatures
  return false if signatures.empty?

  regenerate
  @last_signatures = signatures
  true
end
```

### Production factory wiring (command → installer seam)
```ruby
# Source: lib/spm_cache/command/watch.rb:35-39 (verbatim)
watcher = Core::Watcher.new(
  project_path: project_path,
  installer_factory: ->(path) { Installer::Use.new(project: path) },
  debounce: @debounce
)
```

### perform_install always-run tail (Pitfall 1 evidence)
```ruby
# Source: lib/spm_cache/installer/use.rb:16-34 (excerpt, verbatim lines 21-33)
if fast_path?
  Core::UI.info 'No changes detected. Proxy package up to date.'
else
  recreate_dirs
  ensure_config_file
  sync_lockfile
  prepare_proxy
  yield self if block_given?
end

gen_supporting_files
integrate_proxy_into_project
gen_cachemap_viz
```
```ruby
# Source: lib/spm_cache/installer.rb:468 (verbatim)
      project.save
```

### Hermetic loop-avoidance spec pattern
```ruby
# Source: spec/watch_spec.rb:74-76 (verbatim)
# Simulate one poll iteration manually (avoids a blocking loop in tests).
current = watcher.send(:current_signatures)
expect(current).not_to eq(watcher.instance_variable_get(:@last_signatures))
```

## Doc Drift Catalogue (mandated corrections)

Every FSEvents/Fiddle occurrence repo-wide (grep 2026-08-24), classified:

| # | File:Line | Current text (verbatim) | Verdict | Action |
|---|-----------|------------------------|---------|--------|
| 1 | .planning/ROADMAP.md:88 | "FSEvents binds via Ruby `Fiddle` (stdlib) with no new gem dependency; `--once` path is unit-testable without the OS API" | DRIFT (mechanism) | **MANDATED** dated amendment: mechanism → mtime+size polling (accepted 2026-08-24, 05-CONTEXT); keep "no new gem dependency" + "`--once` unit-testable" clauses (both verified true) |
| 2 | .planning/ROADMAP.md:87 | "...SIGINT/SIGTERM flush + exit 0" | PARTIAL DRIFT | Amend alongside criterion 4 verification: SIGINT→exit 0 verified; SIGTERM→143 & no flush as shipped (Open Question 1 decides fix-vs-amend wording) |
| 3 | .planning/PROJECT.md:60 | "**Compatibility**: no new runtime gem dependencies without justification (watch uses native FSEvents to avoid `listen`)" | DRIFT | Correct mechanism clause → "watch uses stdlib mtime polling"; keep the no-`listen` compatibility rule (still true) |
| 4 | .planning/PROJECT.md:68 | "`watch` uses native FSEvents via Fiddle, not `listen` gem \| macOS-only tool; avoids new dependency; ~80-line binding \| — Pending" | DRIFT ×2 (mechanism + stale status) | Correct to polling rationale; flip status "— Pending" → "✓ Shipped Phase 5" (matches neighboring rows) |
| 5 | .planning/STATE.md:51 | "watch: native FSEvents via Fiddle (no `listen` gem); watches Package.resolved + project.pbxproj only; continue-on-error loop" | DRIFT (explicitly named by CONTEXT) | Correct to "watch: stdlib mtime+size polling (no `listen` gem); ..." — rest of line already accurate |
| 6 | .planning/REQUIREMENTS.md:27 | "**AUTO-05**: `watch` binds FSEvents via Ruby `Fiddle` (stdlib) with no new gem dependency" | DRIFT (mechanism) | Amend wording to the accepted substance ("no new gem dependency" via stdlib polling), with dated note mirroring the ROADMAP amendment; keep [x] status |
| 7 | AGENTS.md:16 | mirror of PROJECT.md:60 | DRIFT | Correct in lockstep with PROJECT.md:60 (GSD:project sync block) |
| 8 | .planning/research/SUMMARY.md:33 | "**`watch` FSEvents binding** — keep minimal; `--once` keeps the core path testable without the OS API. Fall back to `listen` gem behind a flag if brittle." | DRIFT (SUMMARY-level) | Correct to polling reality; the fallback advice is moot (no binding exists) |
| 9 | .planning/phases/05-auto-sync-watcher/SUMMARY.md:8 | "`lib/spm_cache/command/watch.rb` (58 lines)" | NUMERIC DRIFT | 58 → **56** (wc -l; also 56 at birth per d7c0fff diffstat) |
| 10 | .planning/phases/05-auto-sync-watcher/SUMMARY.md:9 | "`spec/watch_spec.rb` (137 lines) — 12 specs covering..." | NUMERIC DRIFT (nuance) | 137 ✓ but "12 specs" → **9 specs** (12 reported includes 3 spec_helper.rb:5-17 globals). Reword |
| 11 | .planning/phases/05-auto-sync-watcher/SUMMARY.md:12 | "Phase 5 refactors that into a dedicated `Core::Watcher` class" | IMPRECISE | `use --watch` loop still exists (command/use.rb:50-80) — reword "adds a dedicated Core::Watcher alongside the retained `use --watch`" (Pitfall 7) |
| 12 | docs/superpowers/specs/2026-08-10-v0.3.0-watch-init-doctor-design.md:43,67,71,182,200 | FSEvents/Fiddle design wording (e.g. :71 "Watcher mechanism: native `FSEvents` via `Fiddle` (zero new gem). ~80-line binding.") | HISTORICAL | Dated approved design doc. Recommended: single dated deviation note at the watch section pointing to 05-CONTEXT acceptance; NOT mandated by CONTEXT (planner discretion) |
| 13 | README.md:40 | "**Watch Mode** — `--watch` monitors `Package.resolved` and re-integrates on change." | GAP (not drift) | Accurate for legacy `use --watch` but the new `spm-cache watch` command (the phase's deliverable) is absent from README entirely — add a `watch` entry |
| 14 | .planning/codebase/CONCERNS.md:68,70,104-108 | Polling described accurately; FSEvents mentioned only as not-used/task-description | CORRECT | No correction needed; optional nuance on :106 debounce overclaim (Pitfall 6) |
| 15 | .planning/codebase/CONVENTIONS.md:148-149,203 | "The `watch` command uses portable mtime+size polling (Ruby stdlib only)" | CORRECT | None |
| 16 | .planning/codebase/INTEGRATIONS.md:143-144 | "watch uses Ruby stdlib mtime+size polling (no `listen` gem, no FSEvents bindings)" | CORRECT | None |
| 17 | lib/spm_cache/command/use.rb:46 | "rather than a native FSEvents binding to avoid a platform-specific gem dependency" | CORRECT | Explicitly says NOT used; none |
| 18 | .planning/phases/05-auto-sync-watcher/05-CONTEXT.md:9,42 | "spec/watch_spec.rb 12 specs" | INPUT RECORD | Do NOT edit (user decision record); SUMMARY correction (#10) supersedes numerically |

[VERIFIED: grep FSEvents|Fiddle repo-wide 2026-08-24 — all occurrences accounted; wc -l = 115/56/137; git show d7c0fff diffstat]

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| FSEvents via Fiddle (~80-line binding) designed | mtime+size polling (stdlib) accepted | 2026-08-24 (05-CONTEXT user decision) | Zero native-binding maintenance; ≥2s detection latency accepted for a dev tool |
| `use --watch` inline loop (Package.resolved only, hardcoded 2s) | Dedicated `Core::Watcher` + `spm-cache watch` (both files, `--debounce`, `--once`) | d7c0fff | Broader signal (pbxproj), CI mode; legacy loop retained (duplication) |
| — | (unresolved) SIGTERM clean-exit | — | Only if planner opts for the 1-line trap fix |

**Deprecated/outdated:** the FSEvents/Fiddle design decision (PROJECT.md:68, STATE.md:51, ROADMAP.md:88, REQUIREMENTS.md:27, AGENTS.md:16, research/SUMMARY.md:33) — superseded, corrections mandated per catalogue above.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `Xcodeproj::Project#save` rewrites the pbxproj file unconditionally (no dirty-check) — the final link in the Pitfall 1 self-trigger chain | Pitfall 1, Code Examples | If save skips unchanged projects, self-trigger is a false alarm and criterion 1 verifies clean. LOW likelihood (call site installer.rb:468 is unconditional; gem behavior is training knowledge not verified this session) — the live smoke settles it either way |
| A2 | A real Xcode package-add rewrites Package.resolved + project.pbxproj within one 2s window (making interval-poll ≈ debounce for the real workflow) | Debounce mechanics, AUTO-02 | If Xcode's writes span >2s, one package-add triggers 2 regenerations; criterion 2 wording should then be softened to "changes within one poll window collapse" |
| A3 | Ruby 3.1/3.3 signal dispositions match 3.2.3 (INT→Interrupt, TERM→kill 143) — experiment ran on 3.2.3 only | Signal handling | Nil practical risk (stable, documented MRI behavior across the CI matrix versions) |
| A4 | Live smoke feasibility: a fixture/real `.xcodeproj` with SPM deps + working toolchain exists for the Pitfall 1 experiment (init specs used fixture .xcodeproj's per ROADMAP.md:57) | Pitfall 1, Open Question 2 | If no suitable fixture, the self-trigger question stays inference-only and must be recorded as an explicit open deviation |

## Open Questions

1. **Criterion 4 signal clause — amend or fix?**
   - What we know: no trap wiring; SIGINT→exit 0 (verified), no flush; SIGTERM→143 (verified), no flush. CONTEXT accepts loop semantics "as shipped" while explicitly asking to "verify the actual trap wiring".
   - What's unclear: whether the user wants the shipped behavior recorded as the accepted deviation, or the ~1-line `Signal.trap('TERM') { raise Interrupt }` fix (+ optional true flush) before closure.
   - Recommendation: default to the dated amendment (consistent with "do NOT re-implement" + do-not-expand-scope); present the fix as an option in the verification report. The plan should carry BOTH the amendment text and the fix patch as a decision point.

2. **Does the live loop self-trigger? (Pitfall 1)**
   - What we know: all mechanism links verified (unconditional `project.save` on every `perform_install`, snapshot-before-regenerate, 2s poll); conclusion is inference (A1/A4).
   - What's unclear: empirical behavior on a real integrated project.
   - Recommendation: Wave-1 task = live smoke (fixture `.xcodeproj`, run `watch` 6-10s, count regeneration lines). If ≥2 with no external edits → defect; fix = re-snapshot after regenerate (one line), then re-run smoke. If 1 → record criterion 1/2 proven with the snapshot-order note.

3. **Mid-watch project deletion: transient-log-then-idle vs fatal-exit?**
   - What we know: shipped behavior logs ONE transient failure, then idles silently (signatures stabilize at `[nil, nil]`); ROADMAP/CONTEXT describe deletion as fatal/non-zero.
   - What's unclear: whether "fatal on project deleted" means pre-start only (shipped complies) or mid-watch too (it doesn't).
   - Recommendation: amend criterion 4's wording to the shipped semantics ("fatal = pre-watch/unstartable project; mid-watch deletion is logged once and the watcher idles") rather than adding loop-exit logic — smallest honest change.

4. **README `watch` entry scope?**
   - What we know: README documents only legacy `use --watch` (line 40); the flagship v0.3.0 `watch` command is absent.
   - What's unclear: whether user-facing README polish belongs to this closure or the milestone-complete step.
   - Recommendation: include a minimal 1-2 line `watch` entry here (it's the phase's deliverable; doc-drift closure is already in scope).

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Ruby | specs, docs | ✓ | 3.2.3 (arm64-darwin23) | CI matrix 3.1/3.2/3.3 |
| Bundler/RSpec | verification runs | ✓ | bundle exec rspec 3.x (12 examples, 0 failures this session) | — |
| Real/fixture `.xcodeproj` + Xcode toolchain | Pitfall 1 live smoke only | ✗ not probed | — | Hermetic simulated-poll specs + inference record (A4) |
| RubyGems/published gem | none | — | — | Not needed (no packaging this phase) |

**Missing dependencies with no fallback:** none blocking — all mandated work (proofs via hermetic specs + code reading, amendments, doc corrections) runs without external services. The live smoke is the only optional external dependency.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | RSpec ~3.12 (dev dependency, gemspec:37) |
| Config file | spec/spec_helper.rb (defines 3 global SPMCache examples included in every file run; no .rspec file) |
| Quick run command | `bundle exec rspec spec/watch_spec.rb` (~1.5s) |
| Full suite command | `bundle exec rspec` (CI: Ruby 3.1-3.3 × macos-15 per ROADMAP.md:29) |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| AUTO-01 | Watched-file resolution | unit | `bundle exec rspec spec/watch_spec.rb:46` | ✅ |
| AUTO-01 | Diff detection between signatures | unit | `bundle exec rspec spec/watch_spec.rb:60` | ✅ |
| AUTO-01 | Loop regenerates via Installer::Use on change | smoke (live/fixture) | live `watch` run, count regen lines | ❌ Wave 0 (Pitfall 1 settles it) |
| AUTO-02 | Debounce value + flag parse/default | unit | `bundle exec rspec spec/watch_spec.rb:109 spec/watch_spec.rb:118 spec/watch_spec.rb:124` | ✅ |
| AUTO-02 | Burst collapse → single regeneration | unit (simulated poll) or subprocess | new spec | ❌ Wave 0 |
| AUTO-03 | run_once single install, hermetic | unit | `bundle exec rspec spec/watch_spec.rb:52` | ✅ |
| AUTO-03 | Empty watch list → false | unit | `bundle exec rspec spec/watch_spec.rb:98` | ✅ |
| AUTO-03 | Command `--once` wiring | unit (ivar) | `bundle exec rspec spec/watch_spec.rb:118` | ✅ (partial — run branch untested) |
| AUTO-04 | Transient failure → loop continues | unit | `bundle exec rspec spec/watch_spec.rb:79` (contract-around-loop only) | ⚠️ partial |
| AUTO-04 | Loop's actual rescue path executes | unit (new, simulated) or subprocess | new spec | ❌ Wave 0 |
| AUTO-04 | Fatal initial failure → non-zero exit | subprocess (new) | child run + `$?.exitstatus` | ❌ Wave 0 |
| AUTO-04 | SIGINT → exit 0, "stopped." output | subprocess (new) | Pitfall 5 pattern | ❌ Wave 0 |
| AUTO-04 | SIGTERM behavior documented | subprocess (new) | assert 143 today / 0 if fixed | ❌ Wave 0 |
| AUTO-05 | Zero new gem deps | static | `git show --stat d7c0fff` (3 files, no gemspec) | ✅ proof exists |
| AUTO-05 | No OS API in `--once` path | static + unit | grep (no Fiddle/listen) + spec:52 hermetic | ✅ |

### Sampling Rate
- **Per task commit:** `bundle exec rspec spec/watch_spec.rb`
- **Per wave merge:** `bundle exec rspec`
- **Phase gate:** full suite green + live smoke result recorded before `/gsd-verify-work`

### Wave 0 Gaps
- [ ] `spec/watch_spec.rb` (extend) — burst-collapse single-poll spec (AUTO-02), loop rescue-path spec via simulated iteration (AUTO-04) — both follow the existing send/ivar pattern, no blocking sleeps
- [ ] Signal subprocess spec (INT/TERM exit statuses) — Pitfall 5 pattern with timeout
- [ ] Live-loop smoke script or documented manual procedure (fixture .xcodeproj) — settles Pitfall 1 and criterion 1
- No framework install needed.

## Security Domain

ASVS L1 (config: `security_enforcement: true`, `security_asvs_level: 1`, `security_block_on: high`).

### Applicable ASVS Categories
| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | Local CLI tool; no auth surface |
| V3 Session Management | no | — |
| V4 Access Control | no | Runs with user privileges only; no privilege change |
| V5 Input Validation | yes (minor) | `--debounce` coerced `.to_i` with no validation (watch.rb:26) — garbage→0 busy-spin, negative→fatal ArgumentError. Local dev tool, user-supplied argv only: LOW. Record; optional clamp |
| V6 Cryptography | no | — |

### Known Threat Patterns for local Ruby CLI + polling watcher
| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Shell injection | Tampering | None present — watcher shells out to nothing; regeneration paths already route through Core::Sh per project convention |
| Path traversal via project/glob | Tampering | `Dir.glob` under the discovered local `.xcodeproj` only; same-trust local files; no new exposure |
| DoS via flag values (debounce=0 spin) | DoS | Self-inflicted only; Pitfall 4 documents; optional clamp |
| Signal-triggered data loss | Tampering | Unflushed change dropped on interrupt (≤debounce s); healed by next run's initial sync — document in verification |

No HIGH findings; nothing blocks on `security_block_on: high`.

## Sources

### Primary (HIGH confidence — read this session)
- lib/spm_cache/core/watcher.rb (full 115 lines; loop 46-74, run_once 36-43, signature 99-104, resolution 87-93)
- lib/spm_cache/command/watch.rb (full 56 lines; flags 16-27, factory 35-39, once-branch 41-46)
- lib/spm_cache/installer/use.rb (perform_install 16-35, fast_path? 45-51)
- lib/spm_cache/installer.rb (verify_projects! 101-104, integrate_proxy_into_project 364-470, project.save 468)
- lib/spm_cache/command/use.rb (legacy `use --watch` loop 44-91)
- spec/watch_spec.rb (full 137 lines), spec/spec_helper.rb:5-17 (3 global examples)
- .planning/ROADMAP.md (Phase 5 criteria 84-88), .planning/REQUIREMENTS.md:23-27, .planning/STATE.md:51, .planning/phases/05-auto-sync-watcher/05-CONTEXT.md, .planning/phases/05-auto-sync-watcher/SUMMARY.md, .planning/config.json
- spm_cache.gemspec:29-38; README.md:40; AGENTS.md:16; .planning/PROJECT.md:60,68; .planning/research/SUMMARY.md:33; docs/superpowers/specs/2026-08-10-v0.3.0-watch-init-doctor-design.md (grep verbatim excerpts); .planning/codebase/{CONCERNS,CONVENTIONS,INTEGRATIONS}.md (grep verbatim excerpts)

### Tool-verified facts
- `git show --stat d7c0fff` (3 files, 308 insertions, no gemspec); `wc -l` = 115/56/137
- `bundle exec rspec spec/watch_spec.rb --dry-run` → 12 examples, 0 failures; `--format documentation` enumerated (9 file + 3 global)
- `grep -rn "Signal.trap\|trap(" lib/` → no matches
- Local signal experiment (ruby 3.2.3, child processes): SIGINT→status 0 with rescue executed; SIGTERM→status 143, no rescue

### Tertiary (LOW confidence)
- None — no external providers configured (all search flags false in .planning/config.json); zero external claims relied upon. Training-knowledge items are confined to Assumptions A1-A3.

## Metadata

**Confidence breakdown:**
- Implementation anatomy / loop mechanics: HIGH — full-source reads with verbatim quotes
- Signal handling: HIGH — code read + empirical child-process verification (INT 0 / TERM 143)
- Doc drift catalogue: HIGH — exhaustive repo grep, every occurrence classified
- Self-trigger conclusion: MEDIUM — each link verified, conclusion is inference pending live smoke (A1/A4)
- Debounce collapse on real Xcode bursts: MEDIUM — mechanism verified, real-workload timing assumed (A2)

**Research date:** 2026-08-24
**Valid until:** 2026-09-24 (stable codebase; watcher unchanged since d7c0fff)
