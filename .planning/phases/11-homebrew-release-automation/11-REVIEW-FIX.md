---
phase: 11-homebrew-release-automation
fixed_at: 2026-08-31T00:00:00Z
review_path: .planning/phases/11-homebrew-release-automation/11-REVIEW.md
iteration: 1
findings_in_scope: 3
fixed: 2
resolved_with_notes: 1
skipped: 0
status: partial
---

# Phase 11: Code Review Fix Report

**Fixed at:** 2026-08-31
**Source review:** `.planning/phases/11-homebrew-release-automation/11-REVIEW.md`
**Branch:** `gsd/v0.4.0-build-fidelity-release-automation` (main-tree commits, hooks on)
**Iteration:** 1

**Summary:**
- Findings in scope: 3 (WR-01, WR-02, WR-03 — Critical 0, Info out of scope)
- Fixed: 2
- Resolved-with-notes: 1 (WR-02 — in-workflow half complete; byte-stability fully realized once an operator attaches tarball assets at release time)
- Skipped: 0

## Fixed Issues

### WR-01: Tag shape gate accepts sed-metacharacter payloads; validated tag flows unescaped into a sed replacement

**Files modified:** `.github/workflows/update-tap.yml`, `spec/update_tap_workflow_spec.rb`
**Commit:** ec51795
**Status:** resolved
**Applied fix:** Tag gate replaced with a strict bash-regex semver check
(`^v[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$`; metacharacters rejected outright) and
the substitution made metacharacter-safe: s-expression delimiter moved from `|` to `,` and
the replacement sanitized via `sed -e 's/[&,\\]/\\&/g'` before sed sees it. Note: the
reviewer's suggested escape (`s/[&|\\]/\\&/g` keeping the `|` delimiter) would not survive
the widened URL anchor whose ERE alternation requires `|` — hence the delimiter change.
Verified: behavioral proof on `&`, `|`, `,`, `\` values (verbatim round-trip, no formula
corruption) plus spec examples pinning the gate, delimiter, and escape ordering.

### WR-02: Formula sha256 is pinned to a GitHub auto-generated archive, whose bytes GitHub does not guarantee

**Files modified:** `.github/workflows/update-tap.yml`, `spec/update_tap_workflow_spec.rb`
**Commit:** c6df1a4
**Status:** resolved-with-notes
**Applied fix:** The sha step prefers an attached `.tar.gz` release asset (byte-stable,
discovered via `gh release view --json assets`) and falls back to the auto-generated
archive behind a `::warning::` annotation. The hashed byte-source URL is published as a
step output and the formula's `url` is pinned to exactly that URL — hash and URL can no
longer drift apart. The exactly-one anchor is widened to also match the
`releases/download/` asset shape so idempotent re-runs still anchor. Integrity gates
(curl -fL retry, non-empty, `1f8b` magic before hashing) unchanged.
**Recommendation (operator):** attach a tarball asset at release time (build
`spm-cache-<ver>.tar.gz` once with `git archive` or `tar --owner=0 --group=0`, then
`gh release upload`); until an asset exists, real runs still hash the auto-generated
archive — loudly warned, never silent.

### WR-03: Credential-bearing workflow references `actions/checkout@v5` by mutable tag

**Files modified:** `.github/workflows/update-tap.yml`, `spec/update_tap_workflow_spec.rb`
**Commit:** a505521
**Status:** resolved
**Applied fix:** `actions/checkout` pinned by full 40-char commit SHA
`fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09` — the commit the `v5` major tag points at
(v5.1.0), resolved via the GitHub API (`refs/tags/v5` is a commit object; no
annotated-tag peel needed) — with the version commented beside the SHA. Spec now requires
every `uses:` reference to be a full commit SHA and pins the exact value; Dependabot's
`github-actions` ecosystem keeps SHA pins updated.

## Skipped Issues

None — all in-scope findings were addressed.

## Verification

- Per-fix: spec-first red-green (each new/changed example failed against the pre-fix
  workflow, then passed); Tier 1 re-reads of every touched region.
- Behavioral proofs run locally for the WR-01 bash mechanics (strict tag regex
  accept/reject matrix; comma-delimited sed substitution under hostile values; widened
  anchor against archive and asset URL shapes).
- Full suite after all fixes: `bundle exec rspec` — **441 examples, 0 failures**
  (438 prior + 3 new), run in the main checkout on
  `gsd/v0.4.0-build-fidelity-release-automation`.
- Live-proven contract preserved: exactly-one anchored edits with `grep -Fqx`
  postconditions, explicit no-diff push, idempotent already-up-to-date branch, macos-15
  runner pin, gzip magic gate — all unchanged and still spec-pinned.
- No GitHub release operations, no dispatch runs, no secret values printed.

---

_Fixed: 2026-08-31_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
