---
phase: 11-homebrew-release-automation
verified: "2026-08-31T00:35:00Z"
status: human_needed
score: 6/7 must-haves verified
behavior_unverified: 1 # The SC-1 end-to-end publish transition (real formula-changing commit+push) — present, spec-pinned, and live-proven up to the no-diff gate, but never exercised with actual new content; detailed below and in human_verification
overrides_applied: 1
overrides:
  - must_have: "The tap push authenticates exclusively with a GitHub App installation token minted in-job from TAP_APP_ID/TAP_APP_PRIVATE_KEY via actions/create-github-app-token@v3 (REL-04)"
    reason: "Operator pivoted to the plan's pre-authorized deploy-key substitute at the blocking-human checkpoint (2026-08-30, IRC): the claimed UI-set App secrets were verifiably absent from every surface. A write-access SSH deploy key (id 161755962, read_only=false) was registered on phuongddx/homebrew-spm-cache; TAP_DEPLOY_KEY is the sole repo secret; dead TAP_REPO_TOKEN deleted. The substitute satisfies REL-04's actual requirement (non-human, non-expiring credential); the workflow change was visible and spec-pinned (checkout ssh-key input, guard naming TAP_DEPLOY_KEY), never an automatic fallback — honoring the 11-02 prohibition. Recorded verbatim in 11-LIVE-RUN.md and STATE.md."
    accepted_by: "operator (phuongddx)"
    accepted_at: "2026-08-30T16:15:49Z"
re_verification:
  previous_status: none
human_verification:
  - test: "Cut the real v0.4.0 release (or dispatch a scratch-tag drill against a scratch tap branch) and observe update-tap perform an actual formula-changing git commit + git push"
    expected: "update-tap commits the anchored url/sha256 edit and pushes to phuongddx/homebrew-spm-cache; verify-publish installs the new formula and goes fully green (ACTUAL == EXPECTED_VERSION)"
    why_human: "The commit+push of NEW content has never executed live (all 3 dispatch runs ended on the idempotent no-diff branch or before the edit — review finding IN-04). Tap-side branch protection, bot-identity policy, or signing requirements are external-service state no grep can see. The phase prohibition against creating releases to obtain a green correctly prevented the executor from exercising it."
  - test: "Apply the tap-side formula boot fix on phuongddx/homebrew-spm-cache (exec the keg-only ruby@3.3 in the wrapper, per deferred-items.md)"
    expected: "brew-installed spm-cache boots under current Homebrew Ruby >= 3.4 (no kconv/nkf LoadError), so the first fully-green verify-publish at v0.4.0 is reachable on modern runners and the macos-15 pin can eventually be retired"
    why_human: "The formula lives in the tap repo, outside this codebase; the executor holds no tap-push credential by design. Documented in deferred-items.md as required-before-v0.4.0-release. Without it, the first v0.4.0 green verify depends on macos-15 runner availability."
  - test: "Optional pre-release: re-dispatch the idempotent v0.3.0 dry-run once, to live-exercise the post-review workflow text (WR-01 strict semver gate + sed-safe replacements, WR-02 asset-preference fallback + URL output pinning, WR-03 SHA-pinned checkout)"
    expected: "update-tap green on the idempotent notice branch: v0.3.0 has no .tar.gz asset so the archive fallback fires behind its ::warning::, the widened anchor matches the live indented archive-shape url line exactly once, and the round-trip stays byte-identical (no commit, no push)"
    why_human: "The three review-fix commits (ec51795, c6df1a4, a505521) landed after live run 3 (2026-08-30T16:27Z); they are spec-pinned (441 examples, 0 failures) but not yet live-proven. Dispatching mutates external state, which verification must not do."
gaps: []
deferred:
  - truth: "The tap formula cannot boot under Homebrew Ruby >= 3.4 (kconv/nkf bundled-gem promotion hidden by the wrapper's GEM_PATH isolation)"
    addressed_in: "Operator action on the tap repo phuongddx/homebrew-spm-cache (out of this repo's scope) — required before the v0.4.0 release's first green verify-publish"
    evidence: "deferred-items.md (discovered 2026-08-30, plan 11-03 run 2, run 33322245624); LIVE-RUN records macos-15 boots cleanly, masking resolved by the runner pin (commit 943cd0a)"
  - truth: "Formula sha256 pins GitHub's auto-generated tag archive until a .tar.gz release asset is attached (WR-02 operator recommendation)"
    addressed_in: "Operator release-time practice (attach spm-cache-<ver>.tar.gz via gh release upload) — no code change pending"
    evidence: "11-REVIEW.md WR-02 resolved-with-notes (commit c6df1a4); the in-run fallback is loudly ::warning::-annotated and the hashed byte-source URL is pinned as a step output, so hash and URL cannot drift"
behavior_unverified_items:
  - truth: "Publishing a release updates the Homebrew formula unattended end-to-end (SC-1's publish -> commit+push transition)"
    test: "Publish a new release (v0.4.0) and watch update-tap commit and push the formula change"
    expected: "A new commit appears on phuongddx/homebrew-spm-cache HEAD updating url+sha256, with zero human steps and no human-owned expiring credential"
    why_human: "Every step except the final commit+push of changed content is live-proven (runs 1-3); the commit+push transition itself never executed against the real tap (IN-04). External repo state (branch protection, bot policy) is invisible to static checks."
coincidental_reliance_items: []
---

# Phase 11: Homebrew Release Automation Verification Report

**Phase Goal:** Publishing a release updates the Homebrew formula unattended and verifiably, and every failure mode in that path is loud rather than green — no human step, no expiring human-owned credential, no silently-published broken formula.
**Verified:** 2026-08-31T00:35:00Z
**Status:** human_needed
**Re-verification:** No — initial verification (no prior *-VERIFICATION.md existed)

## Goal Achievement

Every claim below was re-established against the codebase, the live GitHub API (names only — no secret values were read or printed), and fresh local execution. SUMMARY claims were not trusted; where a summary asserted a fact, an independent check was run.

### Observable Truths

| # | Truth | Status | Evidence |
| - | ----- | ------ | -------- |
| 1 | **REL-04** — tap workflow authenticates without a human-owned expiring credential | ✓ VERIFIED (override) | Workflow auth = `actions/checkout` (SHA-pinned `fbc6f399…`) with `ssh-key: ${{ secrets.TAP_DEPLOY_KEY }}`; no token mint step; no App-route or PAT names anywhere (spec-pinned). Independently confirmed via API: repo secrets = exactly `TAP_DEPLOY_KEY`; deploy key id 161755962 on `phuongddx/homebrew-spm-cache` is `read_only: false, verified: true`. Deviation from the plan's App-token truth is operator-authorized, dated, and recorded (11-LIVE-RUN.md, STATE.md) — see `overrides` |
| 2 | **REL-05** — non-servable tarball (404/HTML) fails the workflow instead of being hashed | ✓ VERIFIED | Workflow: `curl -fL --retry 3 --retry-delay 2` → `test -s` → `od -An -tx1 -N2` magic gate `1f8b` → only then `shasum -a 256` (order also index-asserted by spec). Live: run 1's gates executed green and its sha was byte-equal to the formula's existing value |
| 3 | **REL-06** — commit/push failure fails loudly; no `|| exit 0` path | ✓ VERIFIED | My grep: no `\|\| exit 0`, no `continue-on-error` in the file; every update-tap run body starts `set -euo pipefail` (spec-pinned); explicit no-diff branch emits `::notice::` then exits 0 (the only sanctioned zero-work exit); `git push` is bare and unguarded. Live: runs 2–3 hit the notice branch; tap HEAD unchanged (`2063fac`) |
| 4 | **REL-07** — anchored, post-condition-checked edits; zero-match/over-broad substitution cannot pass | ✓ VERIFIED | `replace_exactly_one`: `grep -cE` count fails red on any value ≠ 1; `sed -i -E` with indented full-line URL_RE/SHA_RE (matches the live 2-space class-body shape; anchor widened to also match `releases/download/` asset URLs); two `grep -Fqx` full-line postconditions; WR-01 hardening (strict semver bash-regex gate + `,`-delimiter + replacement metacharacter escape) spec-pinned. **Live fail-first proof:** run 1 (33322076287) went red exactly at the 0-match gate — REL-07's enforcement catching a real anchor/formula mismatch |
| 5 | **REL-08** — post-publish job installs the formula and asserts `spm-cache --version` == released tag | ✓ VERIFIED | CLI half: I ran `bundle exec bin/spm-cache --version` → `0.3.0`, exit 0; `Main.run` intercept (`return puts(SPMCache::VERSION) if argv.first == '--version'`) sits between `load_all` and `Command.run`; `SPMCache::VERSION` = `File.read(VERSION).strip` and the gemspec ships the VERSION file, so a formula-installed gem reports the released version. Workflow half: verify-publish (needs update-tap, macos-15, anonymous) brew-installs `phuongddx/spm-cache/spm-cache` and whole-string-asserts `[ "$ACTUAL" = "$EXPECTED_VERSION" ]`. Live: run 3 (33322506805) verify-publish FAILED exactly at the version assertion against the pre-intercept v0.3.0 artifact — the documented fail-first proof the assertion has teeth; first green expected at v0.4.0 (contingent on the deferred tap-side boot fix) |
| 6 | **REL-09** — `workflow_dispatch` with `tag` input re-runs the publish without cutting/re-publishing a release | ✓ VERIFIED | Required string input `tag`; resolve step takes `DISPATCH_TAG` (env-mapped) before the `GITHUB_REF_NAME` fallback (ref reachable only in the fallback); strict shape gate with `::error::`; dispatch-only `gh release view` existence check precedes all credential/tap steps. Live: run 33322506805 is `event: workflow_dispatch` on the phase branch with input tag v0.3.0 — and I confirmed via API that the latest release is still v0.3.0 published 2026-08-11 (nothing created, edited, or re-published by any run) |
| 7 | **SC-1 end-to-end** — publishing a release updates the tap unattended (the publish → commit+push transition itself) | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | All mechanics exist, are spec-pinned, and ran live up to the no-diff gate (runs 2–3: anchors matched exactly once each on the real formula, sed round-trip byte-identical, correct idempotent notice). But no run has ever executed a formula-changing `git commit` + `git push` (IN-04: idempotent branch by design; the phase prohibition rightly forbade cutting a release to force one). External tap-side state (branch protection, bot policy) is invisible statically — routed to Human Verification |

**Score:** 6/7 truths verified (1 present, behavior-unverified)

### Required Artifacts

| Artifact | Expected | Status | Details |
| -------- | -------- | ------ | ------- |
| `lib/spm_cache/main.rb` | `--version` intercept before CLAide dispatch | ✓ VERIFIED | 1-line guard between `load_all` and `Command.run`, prints `SPMCache::VERSION` (no literal); behaviorally proven (exit 0, `0.3.0`) |
| `spec/main_version_spec.rb` | stdout-capture spec, VERSION-file cross-check | ✓ VERIFIED | 2 examples (constant + `File.read('VERSION').strip`), green in the 441-example run |
| `.github/workflows/update-tap.yml` | Two-trigger/two-job tap publish, loud failures (REL-04..09) | ✓ VERIFIED | 141 substantive lines; executed live 3× (dispatch runs 33322076287 / 33322245624 / 33322506805) |
| `spec/update_tap_workflow_spec.rb` | Structural spec pinning every REL property | ✓ VERIFIED | 20 examples incl. WR-01..03 pins; green in the 441-example run |
| `11-LIVE-RUN.md` | Operator gate + live dry-run evidence record | ✓ VERIFIED | Run URLs, per-job conclusions, log excerpts, zero-side-effect confirmation — cross-checked against the live API (all match) |
| `deferred-items.md` | Tap-side boot defect record | ✓ VERIFIED | Present, actionable, correctly scoped out-of-repo |

### Key Link Verification

| From | To | Via | Status | Details |
| ---- | -- | --- | ------ | ------- |
| `bin/spm-cache` | `lib/spm_cache/main.rb` | `SPMCache::Main.run(ARGV)`; intercept before `Command.run` | ✓ WIRED | Entry file read; guard present at the right position |
| `lib/spm_cache/main.rb` | `lib/spm_cache/version.rb` / `VERSION` file | `SPMCache::VERSION` constant | ✓ WIRED | `VERSION = File.read(...VERSION).strip`; gemspec `spec.files` ships `VERSION` — formula installs report the released version |
| deploy-key secret `TAP_DEPLOY_KEY` | tap checkout `ssh-key` input → push credentials | the sole auth path (pivot, 11-03) | ✓ WIRED | Spec pins: no `token:` input, `ssh-key: ${{ secrets.TAP_DEPLOY_KEY }}`, exactly one checkout; guard step precedes checkout in the live file |
| step `version` outputs | job output → `EXPECTED_VERSION` | `needs.update-tap.outputs.version` | ✓ WIRED | Present in job `outputs` and verify-publish env |
| dispatch input `tag` | resolve step body | `DISPATCH_TAG` step env only | ✓ WIRED | Injection guard: no `${{ inputs.` / `${{ github.event.` inside any run body (spec-pinned, text re-checked) |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
| -------- | ------------- | ------ | ------------------ | ------ |
| update-tap.yml | `TAG`/`VERSION` | dispatch input or release ref → `GITHUB_OUTPUT` | ✓ | ✓ FLOWING |
| update-tap.yml | `TARBALL_URL`/`SHA256` | real download (post-integrity-gate) → step outputs | ✓ | ✓ FLOWING |
| update-tap.yml | formula url/sha256 lines | `TARBALL_URL`/`SHA256` env → anchored sed + postconditions | ✓ | ✓ FLOWING (WR-02 fix: the formula pins exactly the byte source that was hashed) |
| verify-publish | `EXPECTED_VERSION` | `needs.update-tap.outputs.version` | ✓ | ✓ FLOWING |
| main.rb | printed version | `SPMCache::VERSION` ← `VERSION` file | ✓ | ✓ FLOWING |

No value chain terminates in a static literal or mock.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| -------- | ------- | ------ | ------ |
| Full suite green | `bundle exec rspec` | **441 examples, 0 failures** (39.7s) — matches the claimed 438+3 | ✓ PASS |
| `spm-cache --version` prints version, exits 0 | `bundle exec bin/spm-cache --version` | `0.3.0`, exit 0 | ✓ PASS |
| Credential surface cutover (names only) | `gh api repos/phuongddx/spm-cache/actions/secrets` | exactly `TAP_DEPLOY_KEY` — `TAP_REPO_TOKEN` gone, no App secrets | ✓ PASS |
| Write deploy key on tap | `gh api /repos/phuongddx/homebrew-spm-cache/keys` | `{id: 161755962, read_only: false, verified: true}` | ✓ PASS |
| Live run conclusions as recorded | `gh api …/runs/33322506805/jobs` | `update-tap: success`, `verify-publish: failure`; event `workflow_dispatch`, ref = phase branch | ✓ PASS |
| Dry-run side-effect-free | `gh api …/releases` | latest = v0.3.0, published 2026-08-11 — nothing re-published by the runs | ✓ PASS |
| Silent-success patterns absent | grep `\|\| exit 0` / `continue-on-error` | no matches in the workflow | ✓ PASS |

### Probe Execution

Not applicable — no `scripts/*/tests/probe-*.sh` declared by the plans; the phase's probe-equivalent evidence is the live dispatch record (11-LIVE-RUN.md), re-verified above via the GitHub API rather than re-executed (re-dispatching mutates external state, which verification must not do).

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
| ----------- | ----------- | ----------- | ------ | -------- |
| REL-04 | 11-02, 11-03 | Authenticates without a human-owned expiring credential | ✓ SATISFIED (override: deploy-key substitute) | API-verified secret surface + write deploy key; live auth 3×; deviation operator-authorized and recorded |
| REL-05 | 11-02 | Tarball download failure fails loudly, never hashes an error page | ✓ SATISFIED | curl -fL + retry + non-empty + 1f8b magic strictly before digest (code, spec index-order, live green) |
| REL-06 | 11-02 | Commit/push failure fails loudly; `\|\| exit 0` removed | ✓ SATISFIED | Suppression absent (my grep); set -euo pipefail everywhere; explicit notice branch; unguarded push |
| REL-07 | 11-02 | Anchored, post-condition-checked edits — zero-match/over-broad cannot pass silently | ✓ SATISFIED | exactly-one gate + grep -Fqx postconditions; live run 1 failed red on a real 0-match; WR-01 semver gate + sed-safety added |
| REL-08 | 11-01, 11-02 | Post-publish install + version assertion | ✓ SATISFIED | CLI intercept behaviorally verified; live run 3 red exactly at the assertion (fail-first proof); first green at v0.4.0 by documented design |
| REL-09 | 11-02 | `workflow_dispatch` retry without re-publishing | ✓ SATISFIED | 3 live dispatch runs; input-sourced tag; existence check; releases untouched (API-verified) |

**Orphaned requirements:** none — all six phase IDs (REL-04..09) appear in plan frontmatter (11-01: REL-08; 11-02: all six; 11-03: all six) and every one has implementation evidence above. REQUIREMENTS.md traceability marks all six Complete, consistent with this verification.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| ---- | ---- | ------- | -------- | ------ |
| (none) | — | No TBD/FIXME/XXX/TODO/HACK/PLACEHOLDER markers, no stub returns, no `return null`-class empties, no console-only implementations in any of the four phase-modified files | — | Clean |

Debt-marker gate: clean — zero unreferenced markers in phase-modified files.

### Review-Tail Weighing (4 open Info findings)

All three Warnings are verifiably closed in the live file (WR-01 strict semver gate + `,`-delimiter escape — spec-pinned; WR-02 asset-preference + URL-source pinning with loud fallback warning; WR-03 full-SHA checkout pin, spec-pinned to the exact commit). The four Info findings were assessed against the phase goal, not just hygiene:

- **IN-01** (unannotated diagnostic when the formula file is missing): run still fails red — the loud-not-green invariant holds; diagnostics-degradation only. Not a goal gap.
- **IN-02** (spec never asserts exit 0): I behaviorally verified exit 0 myself; the regression is guarded end-to-end by the live run-3 signature. Test-coverage nicety, not a gap.
- **IN-03** (guard-before-checkout ordering unpinned by spec): the actual workflow file orders guard (step 3) before checkout (step 6) — verified by direct read; only the spec's pin is missing. Not a gap.
- **IN-04** (commit+push never executed live against the real tap): the one genuine residual — promoted to the SC-1 ⚠️ truth and Human Verification item 1, not waived. Consistent with the review's own framing ("operational-risk note for the release checklist — no code change required").

### Deferred Items

| # | Item | Addressed In | Evidence |
| - | ---- | ------------ | -------- |
| 1 | Tap formula cannot boot under Homebrew Ruby ≥ 3.4 (kconv/nkf + GEM_PATH isolation) | Operator action on the tap repo — required before v0.4.0's first green verify | deferred-items.md; run 33322245624; macos-15 pin (943cd0a) masks it for now |
| 2 | sha256 pins the auto-generated archive until a .tar.gz asset is attached (WR-02) | Operator release-time practice; in-run fallback loudly warned | 11-REVIEW.md WR-02 resolved-with-notes; commit c6df1a4 |

Neither blocks this phase's goal: the phase's own verify mechanism discovered #1 and reports it loudly (that is REL-08 working), and #2 cannot produce a silent breakage (hash and URL are pinned to the same byte source; fallback warns).

### Human Verification Required

### 1. First real publish observation (closes the SC-1 ⚠️ truth / IN-04)

**Test:** Cut the v0.4.0 release (or dispatch a scratch-tag drill against a scratch tap branch) and watch update-tap commit + push the formula change.
**Expected:** New commit on `phuongddx/homebrew-spm-cache` updating url+sha256; verify-publish fully green.
**Why human:** The commit+push of new content never executed live (all runs ended idempotently or pre-edit); tap-side branch protection / bot policy is external state no static check can see; the phase prohibition rightly barred creating releases just to force it.

### 2. Tap-side formula boot fix (operator, before v0.4.0)

**Test:** Edit the tap formula wrapper to exec the keg-only `ruby@3.3` (per deferred-items.md).
**Expected:** brew-installed spm-cache boots under Homebrew Ruby ≥ 3.4; first fully-green verify-publish becomes reachable on modern runners.
**Why human:** Lives in the tap repo, outside this codebase; executor holds no tap-push credential by design.

### 3. Optional pre-release re-dispatch (live-prove the review fixes)

**Test:** Re-dispatch the idempotent v0.3.0 dry-run once (commits ec51795/c6df1a4/a505521 landed after live run 3).
**Expected:** update-tap green on the idempotent branch — v0.3.0 has no `.tar.gz` asset, so the archive fallback fires behind its `::warning::`, the widened anchor matches the live archive-shape url line exactly once, round-trip stays byte-identical.
**Why human:** Spec-pinned (441 green) but not yet live-proven; dispatching mutates external state, which verification must not do.

### Gaps Summary

**No gaps.** All six requirements are implemented, wired, spec-pinned, and — except for the deliberately unexercised formula-changing push — live-proven. The suite is green at 441/0 (run by this verifier, matching the claimed count). Every failure mode in the publish path fails red: the exactly-one gate demonstrably caught a real anchor mismatch live (run 1), and the version assertion demonstrably failed red against a defective artifact (run 3). The REL-04 deviation from the plan's App-token design is operator-authorized, dated, recorded, and satisfies the requirement's actual text (non-human, non-expiring). What remains is inherently forward-looking — the first real release — plus one out-of-repo operator fix, both surfaced for human action rather than silently absorbed.

---

_Verified: 2026-08-31T00:35:00Z_
_Verifier: Claude (gsd-verifier)_
