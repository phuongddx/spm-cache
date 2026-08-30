# Phase 11: Homebrew Release Automation - Context

**Gathered:** 2026-08-30
**Status:** Ready for planning

<domain>
## Phase Boundary

Publishing a GitHub release updates `phuongddx/homebrew-spm-cache` unattended and verifiably,
and every failure mode in that path is loud rather than green — no human step, no expiring
human-owned credential, no silently-published broken formula. Delivers REL-04 through REL-09
by rewriting `.github/workflows/update-tap.yml` (auth, tarball integrity, anchored edits,
post-publish verification, dispatch retry) plus structural specs. Fully independent of
Phases 6–10.

</domain>

<decisions>
## Implementation Decisions

### Authentication & the Operator Gate (REL-04)
- GitHub App installation token via `actions/create-github-app-token@v3` — App owned by
  `phuongddx`, `Contents: read & write` + `Metadata: read`, installed on `homebrew-spm-cache`
  ONLY, never `workflow` scope (locked decision 2026-08-27; classic PAT re-mint rejected).
- Missing-secret behavior: fail loudly with a message naming the exact secrets to configure —
  a red run, never a skip.
- Secret names: `TAP_APP_ID` + `TAP_APP_PRIVATE_KEY`.
- Operator timing: operator intends to create the App + secrets around execution; the run
  pauses at the gate when real credentials are needed (secrets were NOT verifiable from the
  planning session — gh account `phuongdoanduy` lacks admin on `phuongddx/spm-cache`; 403 on
  secret list). A write-access deploy key remains the accepted lower-ceremony substitute if
  the operator pivots.

### Tarball Integrity (REL-05)
- `curl -fL --retry 3 --retry-delay 2` plus post-download sanity: non-empty file AND gzip
  magic bytes (`1f 8b`) — catches HTML/JSON error pages even on HTTP 200.
- sha256 computed only after integrity checks pass.

### Formula Edit Safety (REL-06 / REL-07)
- Keep `sed` but anchor every pattern to the exact field line; require exactly-one match
  (`grep -c` == 1) before and after each substitution; then a post-condition block asserting
  url/version/sha256 all contain the new values — any miss exits non-zero.
- Replace `|| exit 0` with explicit no-diff detection: formula already current (idempotent
  retry) → succeed with an "already up to date" annotation; a real commit or push failure →
  fail (red run).

### Post-Publish Verification & Retry (REL-08 / REL-09)
- Separate `verify-publish` job on `macos-latest` (the formula is macOS-only):
  `brew install phuongddx/spm-cache/spm-cache`, then assert `spm-cache --version` contains
  the released tag.
- "Visible notification" = the red failed check on the release run — no extra messaging
  integration.
- `workflow_dispatch` with a `tag` input re-runs the same update+verify steps for an existing
  tag — never cuts or re-publishes a release.
- Spec strategy: structural specs on the workflow YAML (assert: no `|| exit 0`, `curl -fL`
  present, anchored-edit + post-check block present, dispatch input present), following the
  `spec/action_spec.rb` precedent — nothing live-networked in CI.

### Claude's Discretion
None outstanding — all four areas accepted as recommended by the operator on 2026-08-30.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `.github/workflows/update-tap.yml` — the file being rewritten (release-published trigger,
  version extraction, tarball download+hash, tap checkout with `secrets.TAP_REPO_TOKEN`,
  three unanchored seds, `git commit ... || exit 0`)
- `spec/action_spec.rb` — 11-example structural spec precedent for workflow/action YAML
  assertions
- `.github/workflows/ci.yml` — Ruby 3.1–3.3 matrix + proxy build ordering (not touched here)
- `phuongddx/homebrew-spm-cache` tap repo — READ access confirmed from the planning session

### Established Patterns
- Workflows use `actions/checkout@v5`; jobs run on `ubuntu-latest` unless macOS is required
- Structural specs load YAML and assert properties — no live network in CI

### Integration Points
- Release event payload (`GITHUB_REF_NAME`) drives version extraction
- The tap repo's `Formula/spm-cache.rb` — the substitution target
- GitHub App token must drop into `actions/checkout`'s `token:` input (vendor-documented)

</code_context>

<specifics>
## Specific Ideas

No specific requirements beyond the accepted grey-area answers — open to standard approaches
consistent with the above.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>
