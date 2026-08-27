---
phase: 06-graph-authority-lockfile-reconciliation
verified: 2026-08-27T16:05:00Z
status: gaps_found
score: 2/5 success criteria verified (1a, 3) · 3 partial (1, 2, 4)
behavior_unverified: 1
overrides_applied: 0
gaps:
  - truth: "Criterion 4 — the residual cause is attributed and recorded"
    status: failed
    reason: >-
      The recorded attribution's decisive falsifier is factually false. 06-M1-MEASUREMENT.md
      falsifier 2, 06-01-SUMMARY.md, and STATE.md all assert that AnchoredPopup 1.1.3 /
      2fb9d1ac101b "appears in none of the 9 committed revisions of the canonical file" and
      that "no revision of it ever contain[ed] the Group-A identities". Independent read-only
      verification shows the canonical Package.resolved at commits 9075971 (2026-06-19),
      64e960d, 3bf9e91 and 893fb8b DOES hold anchoredpopup 1.1.3 / 2fb9d1ac101b, and the
      nested "wrong file" is BYTE-IDENTICAL to canonical@9075971. The lock agrees 8/8 with
      canonical@9075971. H-lock is therefore NOT excluded for Group A — the evidence cannot
      separate H-lock from H-wrongfile, because the wrongly-picked file IS an old canonical
      snapshot. The published counts H-wrongfile 25 · H-lock 0 are unsupported.
    artifacts:
      - path: ".planning/phases/06-graph-authority-lockfile-reconciliation/06-M1-MEASUREMENT.md"
        issue: "Falsifier 2 (lines 260-269) and falsifier 3 (lines 271-275) rest on a false premise; per-verdict counts (line 240, 394) overstate H-wrongfile and understate H-lock"
      - path: ".planning/phases/06-graph-authority-lockfile-reconciliation/06-01-SUMMARY.md"
        issue: "Repeats 'No committed revision of the canonical file ever held 1.1.3'"
      - path: ".planning/STATE.md"
        issue: "Propagates the false claim into project memory as the corrected v0.4.0 root-cause model"
    missing:
      - "Correct the falsifier: state that the nested file is byte-identical to canonical@9075971, so H-lock and H-wrongfile are observationally indistinguishable for Group A"
      - "Revise the per-verdict counts to reflect that Group A is jointly attributable (both mechanisms present, both fixed in Phase 6)"
      - "Preserve the two conclusions that ARE supported: H-float = 0 (exact revision: pins, no range to float — this is what Phase 7's rescope rests on) and the live locator defect (positively reproduced)"
  - truth: >-
      Criterion 1 — after a non-fast-path run on a project whose Package.resolved has changed,
      re-running DiffDetector returns an empty diff
    status: partial
    reason: >-
      Holds for the two dominant project shapes (canonical file inside the .xcodeproj — proven
      at field scale on the reference project's real inputs; and sibling
      App.xcworkspace/xcshareddata/swiftpm — verified). Deterministically FAILS on the shape
      that is reachable only through the locator's parent_fallback tier. DiffDetector calls
      locate(project_path, parent_fallback: true) and finds the file; the reconciler calls
      locate(project_path) with no fallback, gets nil, warns "No Package.resolved found" and
      leaves the lock untouched. The diff stays non-empty on every subsequent run and the lock
      is never reconciled. This is the exact class of disagreement the phase's five-glob
      collapse existed to eliminate.
    artifacts:
      - path: "lib/spm_cache/installer.rb"
        issue: "Line 156: `Core::PackageResolved.locate(@project_path)` — no parent_fallback, while lib/spm_cache/core/diff_detector.rb:194 passes parent_fallback: true"
    missing:
      - "Either pass parent_fallback: true from the reconciler so it agrees with the detector, or derive host_pins from DiffDetector#live_packages (which already located the file) instead of re-locating"
      - "A spec covering the parent-fallback-only project shape end to end (present specs cover the locator tier in isolation, never the reconciliation consequence)"
deferred:
  - truth: "DiffCollector#live_packages aborts `use` on a truncated host Package.resolved before the reconciler's D-04 warn-and-degrade guard is reachable"
    addressed_in: "Already logged, in scope confirmation only"
    evidence: "deferred-items.md records it with file, cause, suggested fix and deferral rationale; diff_detector.rb:140 confirmed unguarded. Pre-existing, not caused by this phase. Guard itself exists and is spec-covered."
behavior_unverified_items:
  - truth: "Criterion 2 — a project that was working before the run still resolves and builds after it"
    test: >-
      On a project wired to spm-cache with a drifted Package.resolved, capture the pre-run
      build state, run `spm-cache use`, then build. Confirm `swift package resolve` succeeds
      for the umbrella and the app build succeeds.
    expected: "No resolution failure and no build regression versus the pre-run state"
    why_human: >-
      Needs a real Xcode toolchain against a real project. The reference project is no longer
      wired to spm-cache on `main` (empty XCLocalSwiftPackageReference) and its working tree is
      dirty with a stash, so it is out of bounds. No hermetic substitute exists — the
      products[] half is proven, the resolve/build half is not.
human_verification:
  - test: >-
      Decide how to correct the M1 attribution record (06-M1-MEASUREMENT.md falsifiers 2-3,
      06-01-SUMMARY.md, STATE.md) now that the decisive observation is falsified.
    expected: "Corrected record; Phase 7's rescope re-confirmed against the surviving H-float = 0 finding"
    why_human: "A published root-cause model and a project-memory entry that gate Phase 7's sizing"
  - test: >-
      Decide whether the parent-fallback-only project shape is in scope for Phase 6 or an
      accepted limitation to record.
    expected: "Either the reconciler/detector locator asymmetry is closed, or the limitation is recorded with its user-visible warning as the mitigation"
    why_human: "Scope decision — the plan deliberately withheld parent_fallback from the four non-detector sites without analysing this consequence"
  - test: "Criterion 2 build half — see behavior_unverified_items"
    expected: "Project still resolves and builds after reconciliation"
    why_human: "Requires an Xcode toolchain and a wired project"
---

# Phase 6: Graph Authority — Lockfile Reconciliation — Verification Report

**Phase Goal:** The lockfile spm-cache builds from always describes the host project's *current* resolved graph, so no later fidelity decision is made against an abandoned first-run snapshot.
**Verified:** 2026-08-27
**Status:** gaps_found
**Re-verification:** No — initial verification

Every finding below was reproduced independently in this session. The reference project was treated
as read-only throughout: no `spm-cache use`, no build, no branch switch. Its inputs were replayed by
copying `project.pbxproj`, both `Package.resolved` copies and `spm-cache.lock` into a scratch tree.

---

## Goal Achievement

### Observable Truths (ROADMAP Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Non-fast-path run on a changed `Package.resolved` leaves `DiffDetector` reporting an empty diff | ⚠️ PARTIAL | Verified at field scale and by a mutation-discriminating spec, but deterministically fails on the parent-fallback-only project shape — see Gap 2 |
| 1a | Reconciliation reads the **canonical** `project.xcworkspace/xcshareddata/swiftpm/Package.resolved`, proven on a fixture with a competing nested copy | ✓ VERIFIED | Discriminating fixture + mutation + live reproduction on the reference project |
| 2 | Reconciling versions never costs metadata: `products[]` survives; a working project still resolves and builds | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | `products[]` half fully verified; resolve/build half never exercised |
| 3 | `spm-cache doctor` reports lock-vs-resolved disagreement, naming each drifted package, without running a build | ✓ VERIFIED | 17 unit examples + doctor integration + executed live against the reference project |
| 4 | Motivating stale-transitive build reproduced, then re-run after reconciliation, or residual cause attributed and recorded | ✗ FAILED | Reproduction half verified; re-run half not performed; the recorded attribution's decisive falsifier is factually false — see Gap 1 |

**Score:** 2/5 verified · 1 present-behavior-unverified · 2 partial/failed

---

### Criterion 1a — VERIFIED (the vacuous-pass hazard is closed)

This was the hardest thing to falsify and it survives three independent checks.

**1. The fixture is genuinely discriminating.** `spec/package_resolved_spec.rb:50-56` asserts both
halves in one example — `expect(legacy_glob(project_path)).to eq(nested_path)` proves the legacy
`Dir.glob(...).find` idiom returns the wrong file for this fixture, then
`expect(described_class.locate(project_path)).to eq(canonical_path)` proves the new locator does not.
The fixture cannot pass by accident.

**2. Mutation-verified.** I redefined `PackageResolved.locate` back to the legacy glob and re-ran:

- `spec/package_resolved_spec.rb` → 6 examples fail (canonical preference, `.xcodeproj` exclusion, parent re-adoption, workspace tier, mtime tie-break, parent fallback)
- the criterion-1 end-to-end example fails at `expect(installer.diff).not_to be_empty` — i.e. under the legacy locator the diff reads **empty** precisely because both sides agree on the stale nested file. That is the vacuous pass, observed directly, and the current spec catches it.

**3. Reproduced live on the reference project** (read-only, no writes):

| locator | returned file | pins | mtime |
|---|---|---|---|
| legacy `Dir.glob(...).find` | `StressMonitor.xcodeproj/StressMonitor.xcodeproj/.../Package.resolved` | 8 | Jul 12 2026 |
| `PackageResolved.locate` | `StressMonitor.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` | **17** | Aug 13 2026 |

**Criterion 1's empty-diff proof is not achievable by agreement on a non-canonical file.** Confirmed.

---

### Criterion 1 — field-scale proof, and one shape where it fails

**Field replay (hermetic copy of the reference project's real inputs):**

```
diff BEFORE:  added=17 removed=8 updated=0   (empty? false)
  → reconcile
lock AFTER:   17 packages, every version/revision equal to the CANONICAL 17-pin file,
              all 8 phantom exyte entries dropped, every new entry with NO `products` key
diff AFTER:   added=0 removed=0 updated=0    (empty? true)
```

The post-run lock matches the canonical file, not the 8-pin nested one — so this empty diff is
non-vacuous at field scale, not just in a fixture. The sibling-`.xcworkspace` shape was also
verified working (`lock AFTER: 2.0.0 / rev-new`, `diff AFTER empty? true`).

**The failing shape.** The reconciler and the detector locate the host graph by *different* rules:

- `lib/spm_cache/installer.rb:156` — `Core::PackageResolved.locate(@project_path)`
- `lib/spm_cache/core/diff_detector.rb:194` — `PackageResolved.locate(@project_path, parent_fallback: true)`

On a project whose `Package.resolved` is reachable only through tier 4, reproduced:

```
[warn] No Package.resolved found for Fake.xcodeproj; leaving spm-cache.lock untouched.
Detected: ~1 updated (alpha: 1.0.0 -> 2.0.0). Regenerating proxy package.
diff BEFORE empty? false
lock AFTER: 1.0.0 / rev-old        ← never reconciled
diff AFTER empty? false            ← criterion 1 violated, permanently
```

`06-02-PLAN.md:415` decided "Only `DiffDetector` passes `parent_fallback: true`. None of these four
sites gains it" — a deliberate decision, reasoned about *not voiding* the pre-existing fallback, never
about criterion 1's agreement invariant. The outcome is fail-safe (lock untouched, warning emitted on
every run) but never converges. The reference project is not this shape, so the field case is
unaffected. `host_pins` is used only for the warning and `drop_pass_allowed?`; the values come from
`live_packages`, which already located the file — so the fix is small.

---

### Criterion 2 — products[] verified, build half not

Verified: the reconciler mutates only `version`/`revision` (`installer.rb:161-177`); `products` is
untouched for surviving entries, spec-covered by `preserves products` and by the end-to-end example.
The D-02 deviation is independently confirmed necessary — `installer.rb:387` is literally
`next if pkg_data["products"]`, and `[]` is truthy in Ruby, so seeding an empty array would suppress
that package's product metadata permanently. The field replay confirms all 17 added entries carry
exactly `%w[repositoryURL name version revision]` with `products` absent, so enrichment can still
populate them.

Not verified: "a project that was working before the run still resolves and builds after it." No
build was run anywhere. Routed to human verification.

---

### Criterion 3 — VERIFIED

`spec/doctor_lock_fidelity_spec.rb` (17 examples) covers set membership both directions, the
revision-before-version precedence in both directions, no-lockfile `:ok`, local-package exclusion,
unreadable-input `:ok`-not-`:fail`, the pre-v2 zero-pins case, and `does not shell out`.
`spec/doctor_spec.rb:210+` covers the report end to end: `! lock_graph_fidelity:` marker line, both
drifted-package names rendered, the `↳ Run \`spm-cache use\` to reconcile` fix hint, and
`Summary: 0 ok, 1 warning, 0 failures` with `not_to receive(:exit)`.

I mutation-verified the one example the SUMMARY admits could not be RED: flipping the drift verdict
from `:warn` to `:fail` in `diagnostics.rb:150` makes it fail with
`received: 1 time with arguments: (#<...Doctor...>, 1)` at `doctor.rb:42`. The claim is accurate.
`diagnostics.rb` was restored; `git status lib/ spec/ tools/` is clean.

Executed live against the reference project (static, no shell-out, no writes):

```
status=warn
message=spm-cache.lock disagrees with the host Package.resolved:
  8 only in the lock (activityindicatorview, anchoredpopup, chat, giphy-ios-sdk, kingfisher and 3 more),
  17 only in the host graph (abseil-cpp-binary, app-check, appauth-ios, firebase-ios-sdk,
  google-ads-on-device-conversion-ios-sdk and 12 more),
  0 at a different revision/version
```

---

### Criterion 4 — the reproduction is real; the attribution is not

**Reproduction half — VERIFIED independently.** Realized checkout HEADs under
`umbrella/.build/checkouts` read exactly as recorded, and four packages are strictly older than the
contemporaneous host pin at `0a73df7`: AnchoredPopup 1.1.3 < 1.2.1, Kingfisher 8.8.1 < 8.11.0,
libwebp-Xcode 1.5.0 < 1.6.0, MediaPicker 3.3.2 < 3.4.2.

**Re-run-after-reconciliation half — not performed.** The live Release build was withheld, and the
withholding rationale is sound and well documented (probative variant needs a detached checkout in a
tree with 3 modified tracked files and `stash@{0}`, and would overwrite the three pre-fix artifacts).
The field replay above is the nearest available substitute and it does show reconciliation producing
the canonical graph — but it stops short of a build.

**Attribution half — the decisive falsifier is factually false.** The question posed was whether the
attribution is genuinely falsifiable rather than narrative. It *is* structured as a falsifiable
decision table — and applying it independently falsifies its own conclusion.

M1 falsifier 2 rests on: *"A stale snapshot of the canonical file could never contain 1.1.3, because
no committed revision of the canonical file ever held that pin."* Read-only verification of the
reference repo's history:

| canonical `Package.resolved` @ | date | anchoredpopup pin |
|---|---|---|
| 893fb8b | 2026-04-16 | **1.1.3 / 2fb9d1ac101b** |
| 3bf9e91 | 2026-04-25 | **1.1.3 / 2fb9d1ac101b** |
| 64e960d | 2026-06-13 | **1.1.3 / 2fb9d1ac101b** |
| 9075971 | 2026-06-19 | **1.1.3 / 2fb9d1ac101b** |
| 0a73df7 | 2026-08-09 | 1.2.1 / dfa61fd6e4e4 |

Four of the nine revisions hold exactly the pin the falsifier says none ever held. Going further:

- the lock's 8 remote entries agree **8/8** (identity, version and revision) with canonical@9075971
- the nested "wrong file" is **byte-identical** to canonical@9075971 (`diff` → IDENTICAL)

So the wrongly-picked file simply *is* an old snapshot of the canonical file. "Which file the lock's
contents match" — the observation M1 nominates as separating H-lock from H-wrongfile — cannot
separate them, because the two candidate sources are the same bytes. Falsifier 3's claim that no
revision of the canonical file "ever contain[ed] the Group-A identities" is false for the same four
revisions (each holds all 8). **H-lock is not excluded for Group A; the published counts
H-wrongfile 25 · H-lock 0 are unsupported.**

What survives unaffected:

- **H-float = 0 is sound.** All 8 packages were emitted as exact `revision:` pins; `Lockfile.swift:114-126`
  confirms `revision:` wins whenever held, and the comment at 105-117 confirms a `revision:` pin has no
  range to float within. `U == L == realized HEAD` for all 8, verified. This is the finding Phase 7's
  rescope actually rests on, so **the Phase 7 demotion decision is not undermined**.
- **The locator defect is positively confirmed, not inferred.** I reproduced it live: the locator
  returns the 8-pin Jul-12 nested file while the canonical holds 17 pins. The forward-looking
  conclusion — reconciliation without a locator fix converts a visible non-empty diff into a false
  green — is correct and load-bearing, and it is what FID-06 fixes.
- **Remediation is unaffected.** Both H-lock (the `installer.rb` early-return freeze) and H-wrongfile
  (the glob) were fixed in this phase. The defect is in the *record*, which STATE.md has promoted to
  project memory.

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|---|---|---|---|
| `lib/spm_cache/core/package_resolved.rb` | Canonical-first locator + strict/tolerant parsers | ✓ VERIFIED | 4-tier chain, sandbox + nested-`.xcodeproj` exclusions, mtime only as intra-tier tie-break; 2 minor rubocop complexity offences (not a CI gate) |
| `lib/spm_cache/installer.rb` (`reconcile_lockfile_from_host_graph`) | Refresh version/revision, drop/add membership, preserve products | ⚠️ PARTIAL | Correct and field-proven; the `locate` call at :156 lacks `parent_fallback` — see Gap 2 |
| `lib/spm_cache/core/diagnostics.rb` (`lock_graph_fidelity`) | Static lock-vs-host check, `:warn` on drift | ✓ VERIFIED | Registered 8th; `only_in_lock` + `only_in_host` + `value_drift`, labels capped at 5 with "and N more" |
| `tools/.../UmbrellaGenerator.swift` | False-premise comment corrected | ✓ VERIFIED | Lines 58-68 now name both conditions (reconciled-this-run AND canonical-file) instead of claiming `Package.resolved` consistency suffices |
| `spec/package_resolved_spec.rb` | FID-06 coverage incl. discriminating fixture | ✓ VERIFIED | 14 examples; mutation-verified |
| `spec/lockfile_reconciliation_spec.rb` | FID-01 semantics | ✓ VERIFIED | 15 examples; criterion-1 example mutation-verified |
| `spec/doctor_lock_fidelity_spec.rb` | DIAG-01 verdicts | ✓ VERIFIED | 17 examples |
| `06-M1-MEASUREMENT.md` | M1 reproduction + falsifiable attribution | ✗ FAILED | Reproduction accurate; falsifiers 2-3 rest on a false premise — see Gap 1 |

### Key Link Verification

| From | To | Via | Status |
|---|---|---|---|
| all 5 former glob sites | `Core::PackageResolved.locate` | direct call | ✓ WIRED — `grep Dir.glob \| grep -i resolved` shows globs only inside `package_resolved.rb` |
| `Installer#sync_lockfile` | `reconcile_lockfile_from_host_graph` | call at `installer.rb:135` after `@lockfile.load` | ✓ WIRED |
| `Installer::Use#perform_install` | `sync_lockfile` | non-fast-path branch, `use.rb:26`, after `detect_diff` | ✓ WIRED — ordering correct, umbrella generated downstream from the reconciled lock |
| reconciler | `DiffDetector#live_packages` | membership basis (pins ∪ pbxproj refs) | ✓ WIRED |
| reconciler locator | detector locator | shared `PackageResolved` | ⚠️ PARTIAL — asymmetric on `parent_fallback` (Gap 2) |
| `Core::Diagnostics` registry | `doctor` report | `register('lock_graph_fidelity', ...)` | ✓ WIRED — verified live |

### Data-Flow Trace (Level 4)

| Value | Source | Real data? | Status |
|---|---|---|---|
| reconciled `version`/`revision` | `DiffDetector#live_packages` ← canonical `Package.resolved` | ✓ | ✓ FLOWING — field replay wrote all 17 real firebase-graph pins |
| new lock entry `products` | intentionally absent | n/a | ✓ FLOWING — absence is load-bearing; enrichment populates later |
| doctor drift labels | lock JSON + host pins | ✓ | ✓ FLOWING — real names rendered live |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|---|---|---|---|
| Ruby suite | `bundle exec rspec` | 303 examples, 0 failures, 31.3s | ✓ PASS |
| Swift companion | `swift build -c release --package-path tools/spm-cache-proxy` | Build complete! (3.40s) | ✓ PASS |
| Criterion 1a live | locator vs legacy glob on reference project | 17-pin canonical vs 8-pin nested | ✓ PASS |
| Criterion 1 field replay | reconcile reference inputs in a scratch tree | 8 dropped, 17 added, diff empty | ✓ PASS |
| Criterion 1 mutation | criterion-1 spec under legacy locator | fails at `diff not_to be_empty` | ✓ PASS (spec is discriminating) |
| Criterion 3 live | `lock_graph_fidelity` against reference project | `warn` + both drift directions named | ✓ PASS |
| DIAG-01 exit contract mutation | `:warn` → `:fail` in `diagnostics.rb` | spec fails via `doctor.rb:42` exit(1) | ✓ PASS (mutation claim accurate) |
| M1 falsifier 2 | anchoredpopup pin across canonical history | 4 of 9 revisions hold 1.1.3 | ✗ FAIL (claim refuted) |
| M1 falsifier 2 | nested file vs canonical@9075971 | byte-IDENTICAL | ✗ FAIL (claim refuted) |
| Criterion 1 parent-fallback shape | reconcile a tier-4-only project | lock untouched, diff stays non-empty | ✗ FAIL |
| Criterion 2 build half | not runnable | — | ? SKIP → human |

### Probe Execution

No `scripts/*/tests/probe-*.sh` exist in this repo and no plan declares one. Not applicable.

### Requirements Coverage

| Requirement | Description | Status | Evidence |
|---|---|---|---|
| FID-01 | Lock `version`/`revision` reconcile from host `Package.resolved` on every non-fast-path run, preserving `products[]` | ⚠️ PARTIAL | Field-proven on the dominant shapes; not satisfied on the parent-fallback-only shape (Gap 2) |
| FID-06 | Locator resolves the canonical file rather than whichever path `Dir.glob` yields first | ✓ SATISFIED | Mutation-verified spec + live reproduction |
| DIAG-01 | Static `doctor` check comparing lock to host `Package.resolved`, no build | ✓ SATISFIED | 17 unit + 1 integration example, executed live |

`REQUIREMENTS.md` marks all three **Complete**. FID-01 should be qualified until Gap 2 is resolved
or accepted.

### Anti-Patterns Found

| File | Pattern | Severity | Impact |
|---|---|---|---|
| — | No `TBD` / `FIXME` / `XXX` / `TODO` / `HACK` / `PLACEHOLDER` in any file touched by this phase | — | none |
| `lib/spm_cache/core/package_resolved.rb:60,81` | `Metrics/CyclomaticComplexity` 8/7 ×2 | ℹ️ Info | rubocop is a Makefile convenience target, not a CI gate |

### Self-Reported Honesty Items — accurate, not minimized

| Item | Recorded? | Independent check |
|---|---|---|
| 06-02 Task 3: two parity examples passed on write, no RED (WINDOWS #4) | ✓ `06-02-SUMMARY.md:166-176` | Explicitly calls them "parity guard rails, not RED evidence" and names which tasks *do* carry genuine RED. Not minimized. |
| 06-03: 6 of 13 new unit examples genuine RED, 7 regression guards | ✓ `06-03-SUMMARY.md:151-165` | Per-task table; notes it is "repeating the same disclosure rather than dressing guard rails up as RED evidence". |
| 06-04: 13 of 14 genuine RED, 14th proven by mutation | ✓ `06-04-SUMMARY.md:173-186` | **Mutation independently reproduced** — the claim is exactly right. |

### Deviations from Locked Decisions — all sound and recorded

| Decision | Deviation | Verdict |
|---|---|---|
| D-02 "add with empty `products[]`" | Key omitted entirely | **SOUND.** `installer.rb:387` is `next if pkg_data["products"]` and `[]` is truthy in Ruby — independently confirmed. Field replay shows all 17 added entries as `%w[repositoryURL name version revision]`, so enrichment *can* populate them later. Recorded as a realization of D-02's intent, with reasoning, at `06-03-SUMMARY.md:96`. |
| D-06 "set membership AND version" | Lock entries with no `repositoryURL` excluded (lock side only) | **SOUND.** `diagnostics.rb:104` skips only entries whose `repositoryURL` is empty — i.e. local/path packages, which SwiftPM never lists in `Package.resolved`. Every remote lock entry is compared. `only_in_host` is computed from the *unfiltered* host map and reported ("17 only in the host graph", verified live). No masking path for remote drift found. |
| 06-03 project-key resolution | Extension-insensitive (`Fake` matches `Fake.xcodeproj`) | **SOUND and narrowly scoped.** `lock_project_data` tries the exact key first, then strips only `.xcodeproj`; `Fake.xcworkspace` does not match `Fake`. No erasure path found — a non-match returns nil and the reconciler returns early, leaving the lock untouched. The deviation and its cause (the plan's action text and its own named example were mutually unsatisfiable) are recorded at `06-03-SUMMARY.md:37,126`. |

### Known Open Gap — scope confirmed, not a new finding

`diff_detector.rb:140` JSON-parses the host `Package.resolved` unguarded, so a *truncated* file aborts
`detect_diff` before the reconciler's D-04 warn-and-degrade can run. Confirmed at that exact line.
`deferred-items.md` records the file, the mechanism, a suggested fix and the deferral rationale, and
the reconciler's guard itself exists and is spec-covered (`leaves the lock untouched when
Package.resolved is unreadable`). Scope confirmed as logged; **not** counted as a gap here.

### Out of Scope (per scope fence)

Checkout seeding (Phase 7), drift read-back/provenance (Phase 8), cache invalidation (Phase 9).
The post-M1 decision to re-plan 7-9 is recorded in `STATE.md` (`415f8be`). Nothing in those areas is
reported as a Phase 6 gap.

---

## Gaps Summary

The engineering is strong and the hardest thing to get right — criterion 1a, the vacuous-pass
guard — is genuinely and independently proven, three ways, including live on the reference project.
Criterion 3 works in the field. Criterion 1 is proven at field scale.

Two things stop this being a pass.

**The M1 attribution record is falsified by its own method.** The document deserves credit for
publishing a falsifiable decision table instead of a narrative — but applying it independently
refutes its conclusion. Four committed revisions of the canonical `Package.resolved` hold the exact
AnchoredPopup pin the falsifier says none ever held, the lock agrees 8/8 with one of them, and the
nested "wrong file" is byte-identical to it. H-lock is not excluded for Group A, and `H-wrongfile 25 ·
H-lock 0` is not what the evidence supports. This costs nothing in code — both mechanisms were fixed
here, and the H-float = 0 finding that Phase 7's rescope actually depends on is untouched — but the
false claim is now in `STATE.md` as project memory, so it should be corrected before it is inherited.

**Criterion 1 is not universally true.** The reconciler and the detector still locate the host graph
by different rules. On a project reachable only through the locator's `parent_fallback` tier, the
detector reports drift the reconciler declines to close, forever. The phase's own stated reason for
collapsing five globs was that the pin source and the change detector "would otherwise locate the
file by independent logic" — on this one shape they still do. It is fail-safe and warned, the
reference project is not this shape, and the fix is small.

Criterion 2's `products[]` half is solid; its resolve/build half was never exercised and needs a
human with a toolchain.

---

*Verified: 2026-08-27*
*Verifier: Claude (gsd-verifier)*
