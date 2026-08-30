---
phase: 11-homebrew-release-automation
reviewed: 2026-08-30T16:50:11Z
depth: deep
files_reviewed: 4
files_reviewed_list:
  - .github/workflows/update-tap.yml
  - lib/spm_cache/main.rb
  - spec/main_version_spec.rb
  - spec/update_tap_workflow_spec.rb
findings:
  critical: 0
  warning: 3
  info: 4
  total: 7
status: fixed
fixed_at: 2026-08-31
fix_commits:
  WR-01: ec51795
  WR-02: c6df1a4
  WR-03: a505521
fix_summary:
  resolved: 2
  resolved-with-notes: 1
  waived: 0
---

# Phase 11: Code Review Report

**Reviewed:** 2026-08-30T16:50:11Z
**Depth:** deep
**Files Reviewed:** 4
**Status:** fixed — all 3 warnings addressed 2026-08-31 (2 resolved, 1 resolved-with-notes; info findings out of scope)

## Summary

Reviewed the phase-11 change set at deep depth: the `--version` intercept in
`SPMCache::Main.run` (11-01), the rewritten `update-tap.yml` workflow with deploy-key auth,
anchor fix, and macos-15 pin (11-02 + 11-03), and the two structural spec files. Cross-file
traces performed: `bin/spm-cache` → `Main.run` → `Command.run` (CLAide default-subcommand
routing), `SPMCache::VERSION` → `VERSION` file → `spm_cache.gemspec` packaging, the tag →
env → sed/postcondition data flow in the workflow, and every structural regex in
`update_tap_workflow_spec.rb` against the current workflow text.

Both reviewed spec files pass (25 examples, 0 failures). The known tap-side boot defect
(Homebrew Ruby 3.4 kconv/nkf, `deferred-items.md`) and the documented expected-red
verify-publish at v0.3.0 are treated as established context, not re-reported. The deploy-key
pivot and idempotent no-diff branch are live-proven and sound. No blockers: every failure
path I could construct ends red and loud.

What remains: the tag shape gate is weaker than its error message claims and feeds a sed
replacement where `&`/`\`/`|` are metacharacters (corruption reproduced locally, caught by
the postcondition net); the formula pins a GitHub auto-generated archive whose bytes GitHub
does not guarantee over time; and the one `uses:` action is tag-referenced while carrying
the deploy key. Three info-level diagnostic/coverage gaps round it out.

## Warnings

### WR-01: Tag shape gate accepts sed-metacharacter payloads; validated tag flows unescaped into a sed replacement

**File:** `.github/workflows/update-tap.yml:37-40,98,102`
**Issue:** The gate `case "$TAG" in v[0-9]*)` is a shell glob — `v`, one digit, then *any*
string. It accepts tags like `v1.2.3&calc` (a legal git tag name) despite the error text
promising "must look like v0.4.0". The version then reaches `sed -i -E
"s|$pattern|$replacement|"` (line 98) via the replacement built at line 102, where `&`
expands to the whole match, `\` escapes, and `|` breaks the `s` expression. Reproduced
locally with `VERSION='1.2.3&calc'`: the formula's `url` line becomes
`url ".../tags/v1.2.3  url ".../tags/v0.3.0.tar.gz"calc.tar.gz"` — a corrupted edit. The
`grep -Fqx` postconditions (104-107) catch this and fail the run red, so nothing silent
ships — but the edit step's correctness contract ("exactly-one anchored replacement")
doesn't hold for the accepted input space, and the failure surfaces as a confusing
postcondition error instead of a tag-validation error. The `workflow_dispatch` input makes
this reachable without ever creating an odd git tag — the dispatcher just types the string
(and the release-existence gate only requires that a release with that name exists).
**Fix:** validate the full semver shape, not just a prefix:
```bash
case "$TAG" in
  v[0-9]*.[0-9]*.[0-9]*) ;;   # still glob — prefer a regex:
esac
if ! [[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$ ]]; then
  echo "::error::tag '${TAG}' must look like v0.4.0"; exit 1
fi
```
(drop the `([-+][0-9A-Za-z.-]+)?` tail if prerelease tags are not supported; this rejects
`&`, `\`, `|`, `?`, `#`, and `$` outright). Alternatively, escape sed metacharacters in the
replacement: `printf '%s' "$VERSION" | sed -e 's/[&|\\]/\\&/g'`.

**Status (fix, 2026-08-31):** resolved (commit ec51795). Both halves fixed: the gate is
now a strict bash-regex semver check (`^v[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$` —
rejects `&`, `\`, `|`, `?`, `#`, `$` outright), and the substitution is metacharacter-safe
by construction: the s-expression delimiter moved to `,` and the replacement is sanitized
with `sed -e 's/[&,\\]/\\&/g'` before sed sees it. Note: the reviewer's alternative escape
(`s/[&|\\]/\\&/g` keeping the `|` delimiter) would not survive the widened URL anchor,
whose ERE alternation requires `|` — hence the delimiter change. Hostile
`&`/`|`/`,`/`\` values round-trip verbatim (behaviorally proven locally); both the strict
gate and the escape ordering are pinned in `update_tap_workflow_spec.rb`.

### WR-02: Formula sha256 is pinned to a GitHub auto-generated archive, whose bytes GitHub does not guarantee

**File:** `.github/workflows/update-tap.yml:69-75,102`
**Issue:** The workflow downloads `https://github.com/<repo>/archive/refs/tags/<TAG>.tar.gz`,
hashes it, and pins that hash into the formula — the same URL `brew` downloads at install
time. GitHub's own documentation states auto-generated source archives are not guaranteed to
be byte-stable (compression settings can change; archives are generated on demand). If the
bytes of the v0.4.0 archive ever change, every existing user's `brew install
phuongddx/spm-cache/spm-cache` starts failing with a sha256 mismatch, and stays broken until
the next release republishes. The phase docs (11-RESEARCH.md, 11-PATTERNS.md) don't record
this tradeoff as an accepted decision. The in-run gates (`1f8b` magic, postconditions) are
correct but orthogonal — they protect this run, not future installs.
**Fix:** produce the artifact once and ship it as a stable release asset: `tar --owner=0
--group=0` (or `git archive`) the tag, `gh release upload`, then point the formula's `url`
at the asset URL (`https://github.com/…/releases/download/v0.4.0/spm-cache-0.4.0.tar.gz`)
and keep the same sha256 plumbing. The exactly-one anchors need only their pattern widened.

**Status (fix, 2026-08-31):** resolved-with-notes (commit c6df1a4). The sha step now
prefers an attached `.tar.gz` release asset (byte-stable) and falls back to the
auto-generated archive behind a `::warning::` annotation; the hashed byte-source URL is
published as a step output and the formula's `url` is pinned to exactly it, so hash and
URL can no longer drift; the exactly-one anchor is widened to also match the
`releases/download/` asset shape. **Recommendation (operator):** attach a tarball asset at
release time (build `spm-cache-<ver>.tar.gz` once with `git archive` or
`tar --owner=0 --group=0`, then `gh release upload`); until an asset exists, real runs
still hash the auto-generated archive — loudly warned, never silent.

### WR-03: Credential-bearing workflow references `actions/checkout@v5` by mutable tag

**File:** `.github/workflows/update-tap.yml:78`
**Issue:** The tap checkout step passes `ssh-key: ${{ secrets.TAP_DEPLOY_KEY }}` — a
write-access deploy key — into `actions/checkout`, referenced by mutable major tag. A
compromised or force-moved tag would execute attacker code in a job holding the private key,
with push access to the tap and a formula URL trusted by every user of the tap. This is
GitHub's documented supply-chain hardening case for pinning actions by full commit SHA. It's
the only `uses:` in the file, so the fix is one line.
**Fix:**
```yaml
uses: actions/checkout@<full-length-commit-sha-of-v5>  # v5.x.y
```
(Dependabot can keep the SHA-pinned reference updated via its `package-ecosystem: github-actions` support.)

**Status (fix, 2026-08-31):** resolved (commit a505521). `actions/checkout` is pinned to
`fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09` — the commit the `v5` major tag points at
today (v5.1.0), resolved via the GitHub API (commit object; no annotated-tag peel
needed) — with the version commented beside the SHA for readability. The spec now
requires every `uses:` reference in the workflow to be a full 40-char commit SHA and
pins the exact value.

## Info

### IN-01: `replace_exactly_one` degrades to unannotated, misleading diagnostics when the formula file is missing

**File:** `.github/workflows/update-tap.yml:93-98`
**Issue:** `count=$(grep -cE "$pattern" "$FORMULA" || true)` — if `tap/Formula/spm-cache.rb`
doesn't exist (tap rename, path drift), grep exits 2 with empty stdout, so `count=""` and
`[ "" -ne 1 ]` emits `integer expression expected` and does *not* enter the annotated error
branch. The run still fails red, but via sed's `can't read … No such file` instead of the
intended `::error::expected exactly 1 match …` annotation. Loud failure preserved;
diagnostics degraded.
**Fix:** guard at the top of the step (after `FORMULA=`):
```bash
test -f "$FORMULA" || { echo "::error::$FORMULA not found in tap checkout"; exit 1; }
```

### IN-02: `--version` spec asserts output but never the documented exit 0

**File:** `spec/main_version_spec.rb:5-6,12-14`
**Issue:** The header contract is "print the gem version to stdout and exit 0", but no
example asserts exit status — and the unit path can't: `Main.run` returns `puts(...)` (nil)
and the exit 0 comes from `bin/spm-cache` falling off the end. (Incidentally, the current
examples forbid any explicit `exit` in the intercept, since a raised `SystemExit` fails the
block form — so the mechanism is accidentally over-constrained rather than under-tested.)
The regression being guarded (unknown-option, exit 1) was an end-to-end CLI behavior; the
end-to-end half is unpinned.
**Fix:** add one integration example, e.g. with `Open3.capture2(File.expand_path('../bin/spm-cache', __dir__), '--version')`,
asserting `status.success?` and the stdout payload — or soften the comment to claim output only.

### IN-03: Workflow spec computes guard/tap positions but never pins guard-before-checkout ordering

**File:** `spec/update_tap_workflow_spec.rb:164-167`
**Issue:** The ordering test computes `guard_pos` and `tap_pos` but only asserts
`check_pos < guard_pos` and `check_pos < tap_pos`. The credential guard preceding the tap
checkout — fail with a named-secret error *before* cloning — is unpinned: reordering the
workflow so checkout runs before the guard step passes the suite. Consistent with the test's
own stated intent ("before anything touches credentials or the tap").
**Fix:** add `expect(guard_pos).to be < tap_pos, 'missing credentials must fail red before the tap is cloned'`.

### IN-04: `git commit` / `git push` have never executed against the real tap — first release is the first run

**File:** `.github/workflows/update-tap.yml:122-123`
**Issue:** Live-run evidence shows all three dispatch runs ended at the idempotent no-diff
notice (runs 2-3) or failed before commit (run 1, anchor mismatch). The push path is proven
only to the extent that the deploy key cloned the tap and is `read_only: false`. If the push
path has a latent defect (identity/signing policy on the tap repo, branch protection on the
tap's default branch rejecting `github-actions[bot]` commits, ssh agent persistence quirks),
it first manifests on the real v0.4.0 release run. No code change required — a coverage/
operational-risk note for the release checklist.
**Fix:** one-off drill: dispatch the workflow with a scratch tag against a scratch branch of
the tap (or temporarily point checkout `ref:` at a test branch) to observe a real commit +
push, or explicitly accept the residual risk in the v0.4.0 release checklist.

---

_Reviewed: 2026-08-30T16:50:11Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep_
