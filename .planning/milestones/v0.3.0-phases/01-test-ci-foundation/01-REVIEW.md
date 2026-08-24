---
phase: 01-test-ci-foundation
reviewed: 2026-08-23T17:16:59Z
depth: deep
review_type: post-fix
prior_status: issues
fix_commits:
  - 9f919a9 (fix: build proxy in ruby-tests before RSpec; drop dead build from swift-tests — MJ-01/MI-02)
  - 2a8f602 (docs: record delivered Ruby 3.1/3.2/3.3 matrix with gemspec justification — MI-01)
  - 0c14190 (docs: 01-02 plan summary)
files_reviewed: 10
files_reviewed_list:
  - .github/workflows/ci.yml
  - .planning/ROADMAP.md
  - .planning/phases/01-test-ci-foundation/PLAN.md
  - .planning/phases/01-test-ci-foundation/SUMMARY.md
  - .planning/phases/01-test-ci-foundation/01-02-PLAN.md
  - .planning/phases/01-test-ci-foundation/01-02-SUMMARY.md
  - .planning/phases/01-test-ci-foundation/01-VERIFICATION.md
  - Makefile
  - tools/spm-cache-proxy/Package.swift
  - spec/gen_proxy_ignore_spec.rb
findings:
  critical: 0
  major: 0
  minor: 0
  total: 0
  blocker: 0
  warning: 0
  info: 0
status: clean
---

# Phase 1: Code Review Report — Test CI Foundation (Post-Fix Re-Review)

**Reviewed:** 2026-08-23T17:16:59Z
**Depth:** deep (re-review of gap-closure commits 9f919a9 / 2a8f602 / 0c14190 against current HEAD state, prior findings, and local proof evidence)
**Files Reviewed:** 10 (workflow + 3 corrected docs + gap-plan artifacts + build entrypoints + spec guard)
**Status:** clean — all actionable prior findings resolved or documented-deferred; no new defects introduced

## Summary

Re-reviewed the post-fix state of `.github/workflows/ci.yml` (HEAD `d978a19`), the three doc
corrections, and the diffs of the gap-closure commits themselves. The previous review's one
major finding (MJ-01: binary-gated specs silently skip on every Ruby leg) and two of its
three minor findings (MI-01 doc drift, MI-02 dead build) are **resolved with evidence**.
MI-03 (`timeout-minutes`) is **deferred with recorded rationale** — verified present in
01-02-PLAN.md's scope_audit and acknowledged in 01-VERIFICATION.md's anti-pattern table.

The fix commit 9f919a9 is surgical: exactly two hunks, both inside job bodies; the workflow
header (`on:`/`concurrency:`/`permissions:`), matrix, `fail-fast`, and `runs-on` are
byte-untouched; YAML parses; no new `${{ }}` expressions, secrets, `needs:` edges, or
smuggled scope. The doc commit 2a8f602 changes exactly 5 lines across 3 files, leaves
PLAN.md's historical prose byte-identical, and every corrected claim carries the verifiable
justification (`spm_cache.gemspec:27` — `required_ruby_version = ">= 3.1.0"`, confirmed on
disk). No new findings. Status: **clean**.

## Prior-Findings Resolution Table

| Prior ID | Severity (prior) | Finding | Resolution | Evidence |
|---|---|---|---|---|
| MJ-01 | major | 23 binary-gated `gen_proxy_*` examples silently skip on every Ruby leg — `ruby-tests` never builds the proxy; `swift-tests`' binary can't cross the runner boundary | **RESOLVED** | See §MJ-01 evidence below |
| MI-01 | minor | PLAN/SUMMARY (and ROADMAP) claim delivered Ruby 3.0–3.3 matrix; delivered is 3.1–3.3 | **RESOLVED** | See §MI-01 evidence below |
| MI-02 | minor | `make proxy.build` in `swift-tests` produces a release binary nothing consumes | **RESOLVED** | See §MI-02 evidence below |
| MI-03 | minor | No `timeout-minutes` on either job (360-min default burn risk) | **DEFERRED (documented)** | See §MI-03 evidence below |

## Resolution Evidence

### MJ-01 — RESOLVED: proxy binary now built inside `ruby-tests` before RSpec, on every leg

- **Wiring (current ci.yml, verified via `yaml.safe_load` assertions):** `ruby-tests` steps
  are exactly `checkout@v5` → `Select Xcode 16` (`maxim-lobanov/setup-xcode@v1`,
  `xcode-version: '16'`) → `Set up Ruby` (`ruby/setup-ruby@v1`, `bundler-cache: true`) →
  `Build proxy (release)` (`make proxy.build`) → `RSpec` (`bundle exec rspec`, bare and
  unfiltered — no `--example`/`--tag`/`-n`, so the coverage prohibition held).
- **Command reality:** `Makefile:12-13` — `proxy.build: cd tools/spm-cache-proxy && swift
  build -c release`. `Package.swift` declares `.executableTarget(name: "spm-cache-proxy")`,
  so the release build produces exactly `tools/spm-cache-proxy/.build/release/spm-cache-proxy`
  — the precise path the six spec guards test with `File.executable?`
  (e.g. `spec/gen_proxy_ignore_spec.rb:14-18`). The producer and consumer are now in the
  same job on the same runner VM.
- **Toolchain ordering:** the `Select Xcode 16` step precedes both `Set up Ruby` (so
  bundler-cache native-extension compilation uses the pinned Swift-6-capable toolchain) and
  the build itself (`swift build` requires the toolchain). The action+pin is byte-identical
  to the step already production-green in `swift-tests` (run 31504509192), so the moved
  command is production-proven on macos-15, not novel.
- **bundler-cache interplay:** none adverse — bundler-cache completes entirely within the
  `Set up Ruby` step, which finishes before `Build proxy (release)` starts; `make`/`swift
  build` touches no gem state, and the build step runs at repo root (job has no
  `working-directory`; Makefile is at repo root). No ordering conflict exists.
- **Behavioral proof (01-02-SUMMARY.md Task 2, logs at /tmp/01-02-*.log):** RED — binary
  absent → single gated file reports 6 pending with `# spm-cache-proxy binary not built`
  skip lines (guard binds). GREEN — `make proxy.build && bundle exec rspec` → **`218
  examples, 0 failures`**, exit 0, `grep -c "binary not built"` = **0**. (The summary omits
  the `0 pending` clause because RSpec 3 only prints `N pending` when N > 0 — absence at the
  full 218 count IS 0 pending; the `binary not built` grep is the belt-and-suspenders proof.
  Format drift vs the plan's literal expectation is recorded as a zero-impact observation in
  01-02-SUMMARY.md.) All six `gen_proxy_*` describe groups confirmed present via a
  display-only `--format documentation` run — the gated layer executed, not filtered.
- **Production confirmation:** correctly scoped as post-merge (ci.yml triggers only on
  `push: [main]` + `pull_request:`; no `workflow_dispatch` was added, deliberately — see
  01-02-PLAN.md fix_decision). Structural wiring + local behavioral proof are the gap gate,
  per the plan's own verification contract.

### MI-01 — RESOLVED: docs state the delivered 3.1/3.2/3.3 matrix with justification

- `grep "3.0 dropped at merge 5759c5b"` hits all three corrected docs: ROADMAP.md:27
  (1×), PLAN.md:74 (1×), SUMMARY.md:13/19/26 (3×).
- ROADMAP.md:27 now reads `Ruby matrix (3.1/3.2/3.3) runs "bundle exec rspec" on macOS
  (macos-15) and passes — 3.0 dropped at merge 5759c5b: spm_cache.gemspec requires >= 3.1.0,
  so a 3.0 leg can never install`. The stale `3.0/3.1/3.2/3.3` string no longer appears
  anywhere in ROADMAP.md.
- Justification ground truth confirmed on disk: `spm_cache.gemspec:27` —
  `spec.required_ruby_version = ">= 3.1.0"`.
- Historical record preserved: PLAN.md lines 14, 32, 69–70 still contain the original 3.0
  prose byte-for-byte (verified via `sed` and `git diff 67da5d8 HEAD` — the PLAN diff is
  exactly one line: the DELIVERED annotation on the success-mapping item).
- Intentional non-touch verified: 01-VERIFICATION.md, REQUIREMENTS.md, STATE.md keep their
  historical wording, per 01-02-PLAN.md scope_audit ("historical v1-definition records") —
  a recorded scoping decision, not drift.

### MI-02 — RESOLVED: dead release build removed from `swift-tests`

- `swift-tests` steps are exactly 3: `checkout@v5` → `Select Xcode 16` → `Test proxy`
  (`swift test`, `working-directory: tools/spm-cache-proxy`). Zero `proxy.build` runs in the
  job.
- Exactly **one** `make proxy.build` run step exists in the whole workflow, inside
  `ruby-tests` (grep count = 1; YAML assertion confirms) — the release build now has a
  consumer in its own job, resolving MJ-01 and MI-02 jointly as the prior review directed.
- The `Select Xcode 16` step was correctly retained in `swift-tests` (needed by
  `swift test` for the Swift 6.0 tools version).

### MI-03 — DEFERRED (documented, orchestrator-scoped)

- Rationale recorded in **01-02-PLAN.md scope_audit**: "MI-03 (`timeout-minutes` on both
  jobs) — review warning, NOT in the gap's missing list; the orchestrator scoped this plan
  to 'exactly this [gap] + MI-01 docs'. Cheap repo-wide hardening; recommend a follow-up
  alongside `update-tap.yml` (which has the same gap) so both workflows change once,
  together."
- Also tracked as a ⚠️ warning in 01-VERIFICATION.md's anti-pattern table and restated in
  01-02-SUMMARY.md ("Next Phase Readiness": recommended follow-up hardening pass).
- Scope integrity verified: `grep -c 'timeout-minutes' .github/workflows/ci.yml` → 0 (not
  smuggled into the fix, matching the plan's explicit prohibition). Deferral is legitimate —
  the finding never blocked gap closure, and fixing it in isolation would leave sibling
  `update-tap.yml` inconsistent.

## New-Diff Quality Assessment

**9f919a9 (`fix(01-02)`)** — correct and minimal:

- Diff is exactly two hunks, both inside job bodies (`@@ -23,12 +23,20 @@` ruby-tests;
  `@@ -43,9 +51,6 @@` swift-tests). The first hunk starts at old line 23 — after the job
  header, `runs-on`, `strategy`, `fail-fast`, and matrix (lines 16–22) — so
  **triggers/concurrency/permissions/matrix/fail-fast/runs-on are byte-untouched**,
  confirmed both by hunk ranges and by YAML field assertions
  (`on == {push: {branches: [main]}, pull_request: None}`,
  `concurrency == {group: ci-${{ github.ref }}, cancel-in-progress: true}`,
  `permissions == {contents: read}`, `matrix.ruby == ['3.1','3.2','3.3']`,
  `fail-fast is False`).
- YAML valid: `yaml.safe_load` parses; step sequences exactly as intended in both jobs.
- Injection surface unchanged: the only `${{ }}` interpolations remain `github.ref`
  (concurrency group) and `matrix.ruby` (job name, ruby-version) — both safe contexts; no
  new expressions added (T-0102-03 mitigation held). Zero `secrets.`, zero
  `pull_request_target` (T-0102-02 held). No `needs:` edge — jobs remain independent
  (adjacency truth preserved).

**2a8f602 (`docs(01-02)`)** — 3 files, +5/−5: one line each in ROADMAP.md and PLAN.md,
three in SUMMARY.md. All corrections carry the same justification tail; PLAN.md historical
prose untouched (verified above). Commit message documents scope including the intentional
non-touches.

**0c14190 (`docs(01-02): plan summary`)** — adds only 01-02-SUMMARY.md (163 lines); no
source or workflow changes.

## Verified Clean (checked, no finding)

- **Step ordering in ruby-tests** — checkout → Select Xcode 16 → Set up Ruby → Build proxy
  (release) → RSpec; Xcode pin before bundler-cache (native extensions) and before the
  Swift build (toolchain); build before RSpec (guard satisfaction).
- **`make proxy.build` viability on a Ruby leg** — Makefile target exists at repo root
  (Makefile:12-13); `make` ships with macOS runner CLT; the identical command ran green in
  production on macos-15 in the pre-fix swift-tests job (run 31504509192), so dependency
  resolution (swift-argument-parser, Rainbow) over the network is production-proven.
- **Local proof triple** (01-02-SUMMARY.md): full suite `218 examples, 0 failures` (0
  pending — no clause), `binary not built` grep = 0, swift leg 20 tests / 5 suites passed.
- **Job independence** — no artifact upload/download, no `needs:`; each job gates PRs
  independently (plan adjacency truth preserved).
- **No scope creep** — no caching, no `workflow_dispatch`, no new actions beyond the two
  already in use, no timeout settings (MI-03 deference held), RSpec invocation unfiltered.

## Residual Notes (non-blocking, not counted as findings)

1. **Post-merge production confirmation pending (by design):** the fix is proven at the
   structural + local-behavioral level; the first push/PR to main after merge should show
   each Ruby leg's RSpec summary without a pending clause
   (`gh run view <run-id> --log | grep "examples, 0 failures"`). This is the plan's own
   documented verification contract (item 4), not a defect.
2. **MI-03 follow-up should be repo-wide:** when taken, add `timeout-minutes` to both
   ci.yml jobs AND `update-tap.yml` (which shares the gap) in one pass, per the recorded
   deferral rationale.

---

_Reviewed: 2026-08-23T17:16:59Z_
_Reviewer: Phase1ReReview (adversarial post-fix re-review, deep mode)_
_Depth: deep_
_Prior review: 2026-08-23T16:13:12Z (status: issues — MJ-01/MI-01/MI-02/MI-03)_
