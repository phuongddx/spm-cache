---
phase: 11-homebrew-release-automation
plan: "03"
subsystem: release-automation
tags: [homebrew, github-actions, deploy-key, workflow-dispatch, rel-04, rel-08]

requires:
  - phase: 11-01
    provides: "spm-cache --version intercept (lib/spm_cache/main.rb) + spec/main_version_spec.rb"
  - phase: 11-02
    provides: "rewritten .github/workflows/update-tap.yml + spec/update_tap_workflow_spec.rb (REL-04..09 structural pins)"
provides:
  - "Live proof of the rewritten publish path: deploy-key auth, integrity-gated download, anchored idempotent edit, dispatch-input tag resolution, verify job red at the version assertion (REL-04..09)"
  - "Repo credential surface: TAP_DEPLOY_KEY only; dead TAP_REPO_TOKEN deleted"
  - "Write deploy key (id 161755962, read_only=false) registered on phuongddx/homebrew-spm-cache via API"
  - "11-LIVE-RUN.md — the evidence record for the operator gate, the pivot, and three dispatch runs"
affects:
  - "v0.4.0 release cut-over (first fully-green verify-publish) and the tap formula (operator-side boot fix, see deferred-items)"

actuals:
  tokens: 5800
  tasks: 3
  commits: 5

tech-stack:
  added: []
  patterns:
  - "Write-access SSH deploy key + actions/checkout ssh-key input as the GitHub-App substitute for tap pushes"
  - "Anchored formula edits must carry the live file's 2-space class-body indentation (pattern AND replacement AND postcondition)"

key-files:
  created:
  - .planning/phases/11-homebrew-release-automation/11-LIVE-RUN.md
  - .planning/phases/11-homebrew-release-automation/deferred-items.md
  modified:
  - .github/workflows/update-tap.yml
  - spec/update_tap_workflow_spec.rb

key-decisions:
  - "Operator pivoted to the deploy-key substitute after the claimed UI-set App secrets were verifiably absent from every surface; deploy key created API-first (no human step), private key exists only as the TAP_DEPLOY_KEY repo secret"
  - "Accepted deviation (2026-08-30): REL-04's truth weakens to a long-lived machine credential (non-human, non-expiring) — verbatim per the operator's pivot directive"
  - "verify-publish pinned to macos-15 (Pitfall 8 documented fallback): macos-latest/macOS 26 runs the tap formula under Homebrew Ruby 3.4 where the v0.3.0 CLI cannot boot (kconv/nkf), masking the documented signature"
  - "Run-1 anchor defect treated as real and fixed in-repo (indentation), not waived — the exactly-one gate failing red on 0 matches is REL-07 working as designed"

patterns-established:
  - "Names-only secret verification: query the secrets LIST endpoint, never a value; delete by name only"
  - "Live dry-run evidence format: per-job conclusions + verbatim log excerpts + zero-side-effect confirmation (tap HEAD + releases timestamps)"

requirements-completed: [REL-04, REL-05, REL-06, REL-07, REL-08, REL-09]

coverage:
  - id: D1
    description: "Credential surface cutover: TAP_DEPLOY_KEY set, TAP_REPO_TOKEN deleted, no App-route secrets"
    requirement: REL-04
    verification:
      - kind: other
        ref: "gh api repos/phuongddx/spm-cache/actions/secrets → {names:[TAP_DEPLOY_KEY], total:1}"
        status: pass
    human_judgment: false
  - id: D2
    description: "Workflow auth pivoted to checkout ssh-key with guard naming TAP_DEPLOY_KEY; no token-mint step; no retired secret names"
    requirement: REL-04
    verification:
      - kind: unit
        ref: "spec/update_tap_workflow_spec.rb — deploy-key contract, retired-names, guard examples (23 examples, 0 failures)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Anchored formula edits match the live indented line shape (url/sha256), replacement preserves indentation"
    requirement: REL-07
    verification:
      - kind: unit
        ref: "spec/update_tap_workflow_spec.rb — indented-anchor + replacement-indentation examples"
        status: pass
      - kind: other
        ref: "run 33322245624/33322506805 update-tap job: exactly-one matches + idempotent notice branch, tap HEAD unchanged"
        status: pass
    human_judgment: false
  - id: D4
    description: "Live dispatch dry-run (tag v0.3.0): update-tap green on the idempotent notice branch, verify-publish red at the version assertion, zero side effects"
    requirement: REL-08
    verification:
      - kind: other
        ref: "run https://github.com/phuongddx/spm-cache/actions/runs/33322506805 jobs query: update-tap=success, verify-publish=failure at ACTUAL=$(spm-cache --version …) under set -euo pipefail"
        status: pass
      - kind: other
        ref: ".planning/phases/11-homebrew-release-automation/11-LIVE-RUN.md — log excerpts + zero-side-effect confirmation"
        status: pass
    human_judgment: false

duration: 30min
completed: 2026-08-30
status: complete
---

# Phase 11 Plan 03: Operator Gate + Live Dispatch Dry-Run Summary

**Deploy-key pivot (App secrets verifiably absent), a fixed anchor defect, and a live v0.3.0 dispatch proving the publish path green end-to-end while the verify job goes red at the version assertion exactly as documented.**

## Performance

- **Duration:** ~30 min (16:02–16:32 UTC, including the blocking-human pause for the pivot decision)
- **Started:** 2026-08-30T16:02:33Z
- **Completed:** 2026-08-30T16:32:17Z
- **Tasks:** 3
- **Files modified:** 4 (+ SUMMARY/tracking)

## Accomplishments

- Gate resolved by operator **pivot to the deploy-key substitute**: write deploy key created on the tap via API (id 161755962, `read_only=false`), `TAP_DEPLOY_KEY` set as the only repo secret, dead `TAP_REPO_TOKEN` deleted — names-only verification throughout
- Workflow auth pivoted RED→GREEN (spec first): `create-github-app-token` mint + `token:` checkout → `actions/checkout@v5` with `ssh-key`, guard asserts `TAP_DEPLOY_KEY`
- Live dry-run (3 dispatches) proved REL-04/05/06/07/09 green on the idempotent path and REL-08 red-at-the-assertion against the pre-intercept v0.3.0 artifact; all evidence in `11-LIVE-RUN.md`

## Task Commits

1. **Task 2+3 (pivot):** `5699b07` (feat) — deploy-key auth + spec contract
2. **Rule 1 fix:** `8ac4bd6` (fix) — indented live-line anchors
3. **Pitfall 8 fallback:** `943cd0a` (fix) — verify-publish pinned to macos-15
4. **Evidence:** `14e3c10` (docs) — 11-LIVE-RUN.md + deferred-items.md
5. **Plan metadata:** this commit (docs)

## Files Created/Modified

- `.github/workflows/update-tap.yml` — deploy-key auth; indented anchors; macos-15 verify runner
- `spec/update_tap_workflow_spec.rb` — deploy-key contract, retired names, indented anchors
- `.planning/phases/11-homebrew-release-automation/11-LIVE-RUN.md` — full evidence record
- `.planning/phases/11-homebrew-release-automation/deferred-items.md` — tap-side boot defect

## Authentication Gates

Task 1 was a `blocking-human` operator gate. Resolved in two steps: (1) the claimed option-(b)
UI secrets were verifiably absent from every surface (repo/env/dependabot/codespaces secrets,
variables, both related repos; User account → no org surface) — reported as blocking with
evidence; (2) operator chose the pre-authorized deploy-key substitute, which the executor then
applied entirely via API/CLI with no further human step. Full names-only transcript in
`11-LIVE-RUN.md`.

## Decisions Made

- Pivot execution was API-first (deploy key POST + `gh secret set`), avoiding a second human step the plan had budgeted for
- The run-1 anchor 0-match was fixed, not waived: the live formula indents `url`/`sha256` two spaces; pattern, replacement, and postcondition now all carry the indent (locally proven byte-identical round-trip before re-dispatch)
- `macos-15` pin retained (documented fallback) because macos-latest/macOS 26 runs the v0.3.0 formula under Homebrew Ruby 3.4 where the CLI cannot boot at all (see Issues)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Anchored edit regexes missed the live formula's indentation**
- **Found during:** Task 3 (run 33322076287)
- **Issue:** column-0 `^url "`/`^sha256 "` anchors matched 0 lines (live formula indents 2 spaces inside the class body); the exactly-one gate failed the run red
- **Fix:** indented URL_RE/SHA_RE, replacement strings, and `grep -Fqx` postconditions
- **Files modified:** `.github/workflows/update-tap.yml`, `spec/update_tap_workflow_spec.rb`
- **Verification:** local grep counts (1/1), byte-identical sed round-trip vs live tap HEAD, live runs 2–3 green on the edit+idempotent branch
- **Committed in:** `8ac4bd6`

**2. [Rule 3 - Blocking] Phase branch had never been pushed; dispatch needs the ref on the remote**
- **Found during:** Task 3 precondition
- **Issue:** remote had only `main` (old release-only workflow) and `gsd/v0.3.0-milestone`
- **Fix:** pushed the phase branch (`git push -u origin …` as phuongddx); dispatch on the branch ref was then accepted
- **Verification:** run 1 dispatched successfully on the ref
- **Committed in:** n/a (git push; branch commits `5699b07`/`8ac4bd6`/`943cd0a`)

**3. [Rule 1 - Bug] verify-publish signature masked on macOS 26 (runner/OS issue → documented fallback)**
- **Found during:** Task 3 (run 33322245624)
- **Issue:** tap formula boots the CLI under the image's unversioned Homebrew Ruby 3.4, where `kconv`/`nkf` are bundled gems hidden by the wrapper's GEM_PATH isolation → `spm-cache --version` dies at boot (LoadError), masking the documented unknown-option signature
- **Fix:** pinned verify-publish to `macos-15` (Pitfall 8's prescribed one-line fallback); on macos-15 the CLI boots and the red lands exactly at the version assertion (assignment under `set -euo pipefail`)
- **Files modified:** `.github/workflows/update-tap.yml`
- **Verification:** run 33322506805 — update-tap success; verify-publish failure at `ACTUAL=$(spm-cache --version …)`; v0.3.0 entry point has no other exit path (code-verified)
- **Committed in:** `943cd0a`

---

**Total deviations:** 3 auto-fixed (2 bug, 1 blocking) + 1 accepted architectural deviation (operator-authorized deploy-key pivot).
**Impact on plan:** All fixes were required to reach the plan's documented live outcomes; no scope creep. The pivot is recorded verbatim in `11-LIVE-RUN.md` and STATE.

## Issues Encountered

- **Tap formula cannot boot under Homebrew Ruby ≥ 3.4** (nkf/kconv bundled-gem promotion + GEM_PATH isolation in the formula wrapper, whose own stderr filter had been masking the warnings). Out of repo scope — logged in `deferred-items.md` with a suggested one-line tap-side fix. Does not affect Phase 11's conclusions, but the **first fully-green verify at v0.4.0 needs this tap fix in addition to the 11-01 intercept being in the tarball.**
- The dispatch was accepted on the branch ref even though `main`'s workflow copy lacks the `workflow_dispatch` trigger (the anticipated 422 did not materialize — no main-side change was needed).

## User Setup Required

None remaining — the operator gate is fully applied (deploy-key route). The tap-side boot fix in
`deferred-items.md` is optional-now, required-before-v0.4.0-release.

## Next Phase Readiness

- Phase 11 complete (3/3 plans). Release path proven live; on the v0.4.0 release the workflow
  publishes and verifies unattended — provided the tap formula boot fix lands first
  (`deferred-items.md`), since `macos-15` will eventually age out and macos-latest shows the
  LoadError on v0.3.0-era formulas.

## Self-Check: PASSED

- `11-LIVE-RUN.md` — FOUND
- `deferred-items.md` — FOUND
- Commits `5699b07`, `8ac4bd6`, `943cd0a`, `14e3c10` — FOUND in `git log`
- Full suite after all changes: 438 examples, 0 failures

---
*Phase: 11-homebrew-release-automation*
*Completed: 2026-08-30*
