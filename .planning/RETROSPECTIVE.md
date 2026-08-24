# Project Retrospective

> Living document. A section per milestone, trends across milestones.

## Milestone: v0.3.0 — Mixed Cycle

**Shipped:** 2026-08-24
**Phases:** 5 | **Plans:** 10 (6 GSD-tracked) | **Commits:** 86 | **Timeline:** 2026-07-11 → 2026-08-24

### What Was Built

- Test CI: first-ever pipeline, full suite (258 examples at close) gated on every PR/push with the proxy binary built on every ruby-tests leg.
- `doctor`: 7-check data-driven registry, marker report + fix hints, `--json` with CI exit semantics, working companion `--version` probe.
- `init`: 7-flag bootstrap wizard, idempotent yml diff-merge, canonical lockfile seeding (init→use fast path).
- GitHub Action: 6-input thin composite (in-repo `action/`), structural spec cross-referencing the gem CLI.
- `watch`: stdlib polling auto-sync with 2s debounce, `--once`, signal-safe flush, self-trigger guard.

### What Worked

- **Verification-scoped closure.** Phases 2–5 were implemented-but-unverified; running discuss→plan→execute→verify per phase with the planner explicitly told "verify, don't re-implement" converted 5 stale phases into 5 verified ones and surfaced 4 real defects cheaply.
- **TDD RED→GREEN for defect fixes.** Every fix (proxy-in-CI, companion --version, canonical lock, F1 flag, SIGTERM, self-trigger) got a failing spec first — provenance held up under review and verification.
- **Honest acceptance records.** User-accepted deviations (polling vs FSEvents, markers vs ANSI color, external publish chain) were recorded as dated amendments in ROADMAP/REQUIREMENTS, keeping the verifier honest without blocking closure.
- Review→fix chains caught real regressions the executors missed (double-signal abort, unguarded JSON.parse, doc-count misstatements).

### What Was Inefficient

- Planning state lagged reality at milestone entry: STATE claimed all phases complete while GSD had zero verifications — two sessions of bookkeeping reconciliation (including one staleness re-verify triggered by a mechanical frontmatter edit).
- The legacy hand-rolled STATE.md schema broke several gsd-tools writers (state.advance-plan, update-progress, session handlers); executors hand-updated fields instead.
- Nyquist VALIDATION.md files seeded by plan-phase were never reconciled by validate-phase — carried as audit tech debt rather than run.

### Patterns Established

- Verification-scoped plans for implemented-but-unverified phases (CONTEXT records "as shipped" acceptances; plan proves criteria + fixes defects).
- Subprocess-isolated signal specs (CHILD_SCRIPT + Timeout(15)+KILL) for trap/flush contracts.
- Hermetic spec seams: injected installer_factory/collector stubs over Core::Sh; README↔action.yml parity enforced by spec.
- Dated inline amendments ("— amended 2026-08-24: …") instead of silent requirement rewrites.

### Key Lessons

- An implemented feature is not a done phase: 4 of 5 phases harbored real defects (crash, silent flag ignore, signal violation, infinite-loop risk) that only goal-backward verification exposed.
- A `--version`-style "trivial" probe was dead code shipping green for weeks — empirical probes beat reading intent.
- Empirically reproducing reviewer findings (double-signal, pbxproj rewrite churn) before fixing removed all fix-loop argument.

### Cost Observations

- Model mix: n/a (session-level accounting not recorded)
- Notable: full closure run (5 phases + lifecycle) executed in one session on one branch; heaviest single agents were the phase-5 executor (~24 min) and researcher (~17 min).

## Cross-Milestone Trends

| Milestone | Phases | Commits | Cycle Days | Defects found at verification |
|-----------|--------|---------|-----------|-------------------------------|
| v0.3.0 | 5 | 86 | 44 | 4 (+2 review-only majors fixed in-chain) |
