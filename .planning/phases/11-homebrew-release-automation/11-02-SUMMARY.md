---
phase: 11-homebrew-release-automation
plan: "02"
subsystem: ci-release-automation
tags: [ci, github-actions, homebrew, release-automation, tdd, rel-04, rel-05, rel-06, rel-07, rel-08, rel-09]
requires:
  - "spec/action_spec.rb structural-YAML spec precedent (idioms ported)"
  - "Tap formula shape: Formula/spm-cache.rb has url + sha256 lines and NO version stanza (verified 11-RESEARCH Pitfall 3)"
  - "Live run only: repo secrets TAP_APP_ID / TAP_APP_PRIVATE_KEY + GitHub App installed on homebrew-spm-cache (operator gate, 11-03)"
provides:
  - "Rewritten .github/workflows/update-tap.yml — two-trigger, two-job tap publish with loud failures (REL-04..09)"
  - "spec/update_tap_workflow_spec.rb — 20-example structural spec pinning every REL property"
affects:
  - "Release publish path only (workflow + spec; zero gem/lib changes)"
tech-stack:
  added:
  - "actions/create-github-app-token@v3 (official GitHub org, major tag)"
  patterns:
  - "env-indirection only for trigger-context values crossing into run: bodies"
  - "replace_exactly_one (grep -cE == 1 gate) + grep -Fqx full-line postconditions"
  - "download integrity gate (test -s + od 1f8b magic) strictly before shasum"
  - "explicit no-diff notice branch replacing || exit 0"
key-files:
  created:
  - spec/update_tap_workflow_spec.rb
  modified:
  - .github/workflows/update-tap.yml
decisions:
  - "Version asserted via the URL-tag postcondition only — no version-field edit, no stanza added (live tap formula has none; Homebrew derives version from the URL tag; planner resolution of RESEARCH Open Question 2)"
  - "verify-publish on macos-latest per locked CONTEXT (resolves to macOS 26 arm64; macos-15 pin is the documented one-line fallback if the first live run hits an OS-specific failure — 11-03 concern)"
  - "Concurrency group update-tap with cancel-in-progress false — releases queue, never cancel mid-push"
metrics:
  duration: 18m
  completed: 2026-08-30
  tasks_completed: 3
  commits: 6
status: complete
actuals:
  tokens: 5701
  tasks: 3
  commits: 6
---

# Phase 11 Plan 02: Homebrew Tap Publish Workflow Rewrite Summary

One-line: `update-tap.yml` rewritten as a release+dispatch two-trigger, update-tap/verify-publish
two-job pipeline where every failure mode is loud — GitHub App token auth (never the dead PAT),
integrity-gated tarball download, exactly-one-match anchored formula edits with full-line
postconditions, explicit no-diff push, and a macOS brew-install version assertion — pinned by a
20-example hermetic structural spec, delivered RED-then-GREEN per task.

## Final Workflow Shape

```yaml
name: Update Homebrew Tap
triggers:            release[published] + workflow_dispatch(input tag: required string)
concurrency:         group update-tap, cancel-in-progress false
permissions:         contents: read

jobs.update-tap      (ubuntu-latest, outputs: { version: steps.version.outputs.version })
  1. Resolve tag                    id=version   env DISPATCH_TAG=${{ inputs.tag }}; dispatch
     branch takes precedence over GITHUB_REF_NAME (reachable ONLY in the release fallback);
     case v-then-digit validation with ::error::; emits tag + version (v stripped) to GITHUB_OUTPUT
  2. Assert the release exists      if dispatch-only; env GH_TOKEN=${{ github.token }},
     TAG=${{ steps.version.outputs.tag }}; gh release view "$TAG" --repo "$GITHUB_REPOSITORY"
  3. Verify tap credentials         env both app secrets; -z guard fails red with ::error::
     naming TAP_APP_ID and TAP_APP_PRIVATE_KEY (never values)
  4. Get app token                  id=app-token, actions/create-github-app-token@v3
     (app-id/private-key from the two secrets, owner phuongddx, repositories homebrew-spm-cache)
  5. Download tarball + sha256      id=sha, env TAG from resolve step; curl -fL --retry 3
     --retry-delay 2; test -s; od 1f8b gzip magic gate; THEN shasum -a 256; output sha256
  6. Checkout tap repository        actions/checkout@v5 (repository phuongddx/homebrew-spm-cache,
     token from steps.app-token.outputs.token, path tap) — the ONLY checkout in the workflow
  7. Update formula                 env VERSION/SHA256 from step outputs; replace_exactly_one
     (grep -cE count, -ne 1 fails red, sed -i -E GNU in-place) on anchored full-line URL_RE and
     SHA_RE (64 lowercase hex); two grep -Fqx full-line postconditions; NO version-field edit
  8. Commit and push                env VERSION; github-actions[bot] identity (kept verbatim);
     git diff --cached --quiet → ::notice:: + exit 0 (the only sanctioned zero-work exit);
     otherwise commit + bare unguarded git push

jobs.verify-publish (needs update-tap, macos-latest, NO token — anonymous public-tap install)
  env: HOMEBREW_NO_AUTO_UPDATE: "1", EXPECTED_VERSION: ${{ needs.update-tap.outputs.version }}
  1. Install published formula      brew install phuongddx/spm-cache/spm-cache
  2. Assert installed version       set -euo pipefail; brew list --versions; ACTUAL captured via
     spm-cache --version | tr -d '[:space:]'; echo installed/expected; [ whole-string equality ]
```

Every run body in update-tap starts with `set -euo pipefail`; no `|| exit 0`, no
`continue-on-error`, no `TAP_REPO_TOKEN` anywhere in the file.

## Spec Example Inventory (spec/update_tap_workflow_spec.rb, 20 examples)

| Example (short) | Guards |
|---|---|
| strict YAML parse, Psych on-key quirk (`workflow[true]`) | foundation (Pitfall 4) |
| trigger set exactly release + workflow_dispatch | T-11-01 spoofing / REL-09 |
| dispatch tag input (required string, described) | REL-09 |
| concurrency group + cancel-in-progress false, permissions contents read | REL-05 race |
| edit job ubuntu-latest / verify job macOS | REL-07 (GNU sed) / REL-08 |
| verify-publish needs + outputs.version → EXPECTED_VERSION, HOMEBREW_NO_AUTO_UPDATE "1" | REL-08 plumbing |
| brew install user/repo/formula form | REL-08 |
| whole-string version equality assertion (set -euo, tr capture, echo, `[ = ]`) | REL-08 teeth |
| verify job anonymous (no token/secret/app in job subtree) | T-11-07 |
| resolve step GITHUB_OUTPUT tag/version with `${TAG#v}` | REL-09 |
| DISPATCH_TAG env mapping + dispatch-before-ref index order + ref reachable once (fallback only) | REL-09 / T-11-02 |
| dispatch-only gh release view before credential/tap steps (step-order indices) | REL-09 |
| app-token step inputs + checkout(token:, path:) + exactly one checkout@v5 | REL-04 |
| no TAP_REPO_TOKEN anywhere in file text | REL-04 |
| credential guard names both secrets in ::error:: | REL-04 |
| curl -fL --retry 3 --retry-delay 2, test -s, od 1f8b, digest index AFTER magic | REL-05 |
| replace_exactly_one: grep -cE + `-ne 1`, sed -i -E, anchored URL_RE/SHA_RE, 2x grep -Fqx, no `version "` | REL-07 |
| no `\|\| exit 0`, git diff --cached --quiet + ::notice:: + bare unguarded git push | REL-06 |
| every update-tap run body starts with set -euo pipefail | REL-06 / T-11-06 |
| no `${{ inputs.` / `${{ github.event.` in any run body | T-11-02 injection (action_spec.rb:77-83 port) |

## RED → GREEN per Task (TDD)

- **Task 1 (tracer):** 16 standalone examples, 9 failed at RED for exactly the plan's expected
  reasons — missing concurrency/permissions, PAT auth still in place (`TAP_REPO_TOKEN`, no
  app-token step, no credential guard), unguarded `curl -L`, no integrity gate, unanchored seds
  (no `replace_exactly_one`, no postconditions), `|| exit 0` present, no `set -euo pipefail`.
  GREEN after the rewrite: 16/16; full suite 431 (418 + 13 new — see Deviation 3).
- **Task 2:** +3 examples and the trigger-pin extension; RED on exactly those 4; GREEN 19/19;
  full suite 434.
- **Task 3:** +4 examples and the job-set extension; RED on exactly those 5; GREEN 23/23
  (standalone = 20 + 3 spec_helper examples); full suite **438 examples, 0 failures**
  (418 baseline + 20 new).
- **Tracer feedback gate (autonomous):** tracer `<verify>` re-run end-to-end after commit —
  targeted spec green AND comment-filtered `|| exit 0` grep negative — passed; expansion
  proceeded.

## Mutation Proofs (spec has teeth)

Each mutation applied to the workflow, spec run, then restored via `git checkout --` (all
restored to the committed state; final runs green):

1. Un-anchored `SHA_RE` (dropped `^`/`$`) → fails `sha256 pattern must be anchored to the full line`.
2. Reintroduced `git commit ... || exit 0` → fails the no-suppression example.
3. Removed `--retry 3 --retry-delay 2` from curl → fails `download must use curl -fL with
   --retry 3 --retry-delay 2`.

Each run showed exactly the intended failure(s) — no vacuous assertions.

## Commit List

| Commit   | Type | Content |
|----------|------|---------|
| `bf139e4` | test(11-02) | Task 1 RED — 13-example structural spec failing on the 4 failure-site categories |
| `bb59ae6` | feat(11-02) | Task 1 GREEN — release-path rewrite (auth, integrity, anchored edits, no-diff push) |
| `2c5825a` | test(11-02) | Task 2 RED — dispatch surface, input-sourced resolution, existence check |
| `fde5475` | feat(11-02) | Task 2 GREEN — workflow_dispatch tag input + dispatch-only gh release view |
| `ad64183` | test(11-02) | Task 3 RED — verify-publish job graph, plumbing, teeth, anonymity |
| `0271b8c` | feat(11-02) | Task 3 GREEN — verify-publish job + rubocop cleanup |

## TDD Gate Compliance

Per-task RED then GREEN, verifiable in `git log`: each `test(11-02)` commit precedes its
`feat(11-02)` counterpart (bf139e4→bb59ae6, 2c5825a→fde5475, ad64183→0271b8c). No missing-gate
warning required.

## Version-Stanza Decision (REL-07)

The live tap formula has no `version` stanza (verified 11-RESEARCH Pitfall 3); Homebrew derives
the version from the URL tag. Per the planner resolution of Open Question 2: only `url` and
`sha256` are anchored-edited, and the version is asserted by the URL postcondition carrying
`v${VERSION}.tar.gz`. The spec enforces this — the edit body must NOT contain a `version "`
substitution (the old workflow's third sed was a guaranteed silent no-op).

## Deviations from Plan / RESEARCH Patterns

### Documented Deviations (no plan constraint violated)

**1. [RED-shape note] Not every Task 1 example was red at RED time**
- The plan said "all FAIL against the current workflow file"; in fact 7 of 16 passed because the
  properties they pin were intentionally KEPT from the current file (release[published] trigger,
  ubuntu-latest runner, YAML parse, injection guard, step-id conventions). The failures occurred
  in exactly the categories the plan listed as the expected RED reasons. No action needed.

**2. [Rule 1 - Lint] RuboCop cleanup on the spec file**
- 31 layout offenses auto-corrected (`rubocop --auto-correct`, the `make format` idiom) plus 5
  over-long failure-message strings restructured manually. Remaining: one
  `Metrics/BlockLength [228/25]` — the identical offense class `spec/action_spec.rb` (the
  precedent, [113/25]) already carries; accepted convention for structural spec files.
- **Commits:** included in `0271b8c`

**3. [Counting note] Standalone spec runs report +3 examples**
- `spec/spec_helper.rb` defines its own 3-example `RSpec.describe SPMCache` block, so
  `rspec spec/update_tap_workflow_spec.rb` shows 23 while the file defines 20. Full-suite
  arithmetic is consistent: 418 baseline + 20 = 438. No duplicates in the full run (helper
  describe registers once).

**4. [RESEARCH fidelity] No deviations from the vendor-verified blocks**
- Patterns 1-5 and both Code Examples blocks were copied verbatim where quoted (token wiring,
  replace_exactly_one, integrity gate, no-diff branch, dispatch trigger, verify job). The only
  adaptations are the ones the plan itself specified: dropped main-repo checkout, credential
  guard step order (before the mint step), and output names lowercased to tag/version/sha256
  per the must_haves key_links.

## Auth Gates

None — the plan is hermetic (file reads only). The operator gate (GitHub App + secrets) is
11-03's checkpoint, untouched here.

## Known Stubs

None. No placeholder values, no TODO/FIXME, no unwired data sources introduced.

## Threat Flags

None. Every new trust-boundary surface is exactly the plan's threat_model register
(T-11-01..T-11-08): trigger-set pin, env-indirection + injection guard, secret-name-only guard
output, scoped mint (owner+repositories), anchored edits, no-suppression + concurrency, anonymous
verify job, integrity gate. No unplanned surface added.

## Self-Check: PASSED

- `.github/workflows/update-tap.yml` (rewritten, two jobs + two triggers) — FOUND
- `spec/update_tap_workflow_spec.rb` (20 examples) — FOUND
- Commits `bf139e4`, `bb59ae6`, `2c5825a`, `fde5475`, `ad64183`, `0271b8c` in `git log` — FOUND
