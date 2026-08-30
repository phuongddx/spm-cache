# Phase 11 — Live Dispatch Dry-Run Evidence (Plan 11-03)

**Executed:** 2026-08-30 (16:02–16:35 UTC)
**Workflow:** `update-tap.yml` (rewritten in 11-02, deploy-key pivot + anchor fix in 11-03)
**Dispatch command:**

```
gh workflow run update-tap.yml \
  --ref gsd/v0.4.0-build-fidelity-release-automation \
  -f tag=v0.3.0
```

The ref is the phase branch (never previously pushed — pushed from `5699b07`/`8ac4bd6`/`943cd0a`
during this plan) because it carries the rewritten workflow. `main` still holds the old
release-only workflow (no `workflow_dispatch` trigger); the dispatch was accepted against the
branch ref regardless.

---

## Operator gate — resolution and pivot (transcript, names only)

1. **Original gate (option b) did not land.** The claimed UI-set secrets were absent from every
   surface when verified read-only (names only): `phuongddx/spm-cache` actions secrets held only
   `TAP_REPO_TOKEN` (created 2026-07-16, updated 2026-08-09 — untouched by the claimed action);
   actions variables, dependabot, codespaces: empty; no environments exist; `phuongddx` is a User
   account (no org surface); `phuongddx/homebrew-spm-cache` and `phuongddx/spm-cache-action`
   secret lists: empty. Task 2's verify block failed (exit 1). Reported as blocking-human.
2. **Operator decision (IRC, 2026-08-30): PIVOT to the deploy-key substitute** pre-authorized by
   the plan's Task 1 substitute clause and the locked scope decision.
3. **Applied by executor:**
   - Dedicated passphrase-less ed25519 keypair generated in a temp dir (private key never
     printed, never committed; temp files deleted after use).
   - Public key POSTed via API as a **write deploy key** on `phuongddx/homebrew-spm-cache`:
     `gh api --method POST /repos/phuongddx/homebrew-spm-cache/keys` → id 161755962,
     `read_only: false`, `verified: true` (2026-08-30T16:15:49Z). No human step was needed.
   - Repo secret `TAP_DEPLOY_KEY` set on `phuongddx/spm-cache` via `gh secret set` (value masked).
   - Dead classic-PAT secret `TAP_REPO_TOKEN` deleted (gate-authorized).
   - **Resulting surface (names only): exactly `TAP_DEPLOY_KEY`.** `TAP_APP_ID` /
     `TAP_APP_PRIVATE_KEY` never existed (App route abandoned before creation).

**Accepted deviation (dated, verbatim per operator directive):** REL-04's truth weakens to
"a long-lived machine credential (non-human, non-expiring)" — a write-access SSH deploy key on
`phuongddx/homebrew-spm-cache` instead of a 1-hour-scoped GitHub App installation token.
Workflow change: `actions/create-github-app-token@v3` mint + `token:` checkout replaced by
`actions/checkout@v5` with `ssh-key: ${{ secrets.TAP_DEPLOY_KEY }}`; credential guard asserts
`TAP_DEPLOY_KEY`. Integrity gate, anchored-edit postconditions, no-diff publish branch, and the
verify-publish job are unchanged. Spec updated RED→GREEN (23 examples green; full suite 438).

## Run 1 — defect discovery (intentionally recorded, superseded)

- **Run:** https://github.com/phuongddx/spm-cache/actions/runs/33322076287 (workflow_dispatch,
  tag v0.3.0, branch ref)
- update-tap: **failure** at "Update formula" — `expected exactly 1 match for /^url "https://github\.com/phuongddx/spm-cache/archive/refs/tags/[^"]+\.tar\.gz"$/, got 0 in tap/Formula/spm-cache.rb`
- Everything before the edit step was green: dispatch-input tag resolution, `gh release view`
  existence check, `TAP_DEPLOY_KEY` guard, integrity-gated tarball download (sha computed:
  `e3ff4881afc7484a38089c1d557ab9302e2bc3193447eb0252b68d37f222d33c` — byte-equal to the
  formula's existing sha256), and the **deploy-key tap checkout authenticated** (first live
  proof of the pivot).
- **Root cause:** the live formula indents `url`/`sha256` by two spaces (class body); the
  workflow's column-0 anchors matched 0 lines and the exactly-one gate failed the run red —
  loud, as designed (this is REL-07's enforcement catching a real anchor/formula mismatch the
  structural spec could not see, because the spec pins the workflow text, not the tap).
- **Fix (Rule 1, commit `8ac4bd6`):** URL_RE/SHA_RE, replacement strings, and `grep -Fqx`
  postconditions now carry the 2-space indent. Locally proven before dispatch: indented anchors
  match exactly 1 line each, and the sed round-trip against live tap HEAD is **byte-identical**
  (idempotent no-op on v0.3.0).

## Run 2 — post-fix, macos-latest (macOS 26)

- **Run:** https://github.com/phuongddx/spm-cache/actions/runs/33322245624 (workflow_dispatch,
  tag v0.3.0)
- **update-tap: success** — log excerpt (idempotent branch):

  ```
  update-tap  Commit and push  ##[notice]Formula already at 0.3.0 — nothing to do (idempotent retry).
  ```

  Tap repo HEAD unchanged after the run (`2063fac`, 2026-08-11) — no commit, no push. No release
  was created, edited, or re-published (latest release still v0.3.0, published 2026-08-11).
- **verify-publish: failure at the version assertion, unexpected signature** — `spm-cache
  --version` died at boot: `cannot load such file -- kconv (LoadError)` from
  `CFPropertyList-3.0.8/lib/cfpropertylist/rbCFPropertyList.rb:3`, under
  `/opt/homebrew/lib/ruby/site_ruby/3.4.0/rubygems`. `brew list --versions spm-cache` printed
  `spm-cache 0.3.0` first; the install itself succeeded (ruby@3.3 3.3.12 poured as a keg-only
  dependency; gem built and installed from source; `swift build -c release` OK).
- **Diagnosis:** the tap formula's wrapper execs the gem binstub via `env ruby`, which resolves
  to the image's unversioned Homebrew Ruby 3.4 — where `nkf` left the default-gem set (promoted
  to a bundled gem per the Ruby 3.4.0 release notes) — while the wrapper's
  `GEM_PATH=libexec/gems` isolation hides the bundled copy, so `kconv` cannot load and the CLI
  cannot boot. The wrapper's own comment (`to suppress Homebrew Ruby's nkf warnings` + its
  `2> >(grep -v "^Ignoring nkf" >&2)` stderr filter) shows this friction was previously
  observed and masked rather than fixed. This is a **tap-side formula defect, not OS-specific**
  (any current macOS image with Homebrew Ruby ≥ 3.4 reproduces it) — logged to
  `deferred-items.md`; the fix is out of repo scope (operator edit of `Formula/spm-cache.rb`,
  e.g. exec the keg-only `ruby@3.3` explicitly in the wrapper). It does not affect this plan's
  conclusions; it is flagged for the v0.4.0 release in 11-03-SUMMARY (first fully-green verify
  needs BOTH the 11-01 intercept in the tarball AND a formula that boots on modern Homebrew Ruby).

## Run 3 — final, verify pinned to macos-15 (Pitfall 8 fallback, commit `943cd0a`)

- **Run:** https://github.com/phuongddx/spm-cache/actions/runs/33322506805 (workflow_dispatch,
  input tag v0.3.0, ref `gsd/v0.4.0-build-fidelity-release-automation`)
- **Jobs:**

  | Job | Conclusion | Duration | Notes |
  |-----|------------|----------|-------|
  | update-tap | **success** | 5s | idempotent notice branch, tap untouched |
  | verify-publish | **failure** | 55s | install 43s (from source, no ruby pour needed), red **at the version assertion** |

- **update-tap log excerpt:**

  ```
  update-tap  Commit and push  ##[notice]Formula already at 0.3.0 — nothing to do (idempotent retry).
  ```

  Post-run tap HEAD: `2063fac` (2026-08-11) — unchanged. Post-run latest release: v0.3.0
  (published 2026-08-11T06:52:04Z) — no release events of any kind.
- **verify-publish log excerpt (full failure surface):**

  ```
  verify-publish  Assert installed version matches the release    spm-cache 0.3.0
  verify-publish  Assert installed version matches the release  ##[error]Process completed with exit code 1.
  ```

  On macos-15 the CLI **boots cleanly** (no LoadError — the interpreter has working kconv),
  `brew list --versions` prints `spm-cache 0.3.0`, and `spm-cache --version` exits 1. Under
  `set -euo pipefail` the `ACTUAL="$(spm-cache --version | tr -d '[:space:]')"` assignment then
  terminates the step before the `echo` — the job is red precisely because the version probe
  failed.
- **Why this is the documented pre-intercept fail-first proof (REL-08):** the v0.3.0 tarball's
  entry point (`bin/spm-cache` → `SPMCache::Main.run` → `load_all` → `Command.run`, verified by
  `git show v0.3.0:…`) has no rescue and no silent-exit path; with the CLI booted, the only
  failure mode for `--version` is CLAide rejecting the root-only flag after
  `default_subcommand "use"` routing — the pre-fix unknown-option signature reproduced locally
  in 11-01's RED (`[!] Unknown option: '--version'`, exit 1) on this same v0.3.0 code. The
  banner text itself does not appear in the run log because the tap formula's wrapper pipes
  stderr through an async `2> >(grep -v "^Ignoring nkf" >&2)` process substitution whose output
  is lost at teardown — a tap-side cosmetic quirk, not a different defect. **The first fully
  green verify job is expected at the first release whose tarball contains the 11-01 intercept
  (the v0.4.0 release itself), contingent on the Run 2 formula-boot finding being resolved
  tap-side.**

## Requirement coverage proven live (final run)

| Req | Proof |
|-----|-------|
| REL-04 | Deploy-key auth end-to-end: guard passed, `actions/checkout` with `ssh-key` cloned the tap and left push credentials configured (checkout log: `ssh-key: ***`, `persist-credentials: true`) |
| REL-05 | `curl -fL --retry 3 --retry-delay 2`, non-empty + `1f8b` gzip magic gate, sha256 computed only after the gate; sha matched the formula's existing value exactly |
| REL-06 | Explicit no-diff branch with `::notice::` annotation; tap HEAD unchanged after all three runs |
| REL-07 | Anchored exactly-one edits with full-line postconditions — including catching run 1's 0-match anchor defect red (fixed in `8ac4bd6`) |
| REL-08 | verify-publish red at the whole-string version assertion against the pre-intercept v0.3.0 artifact (fail-first proof; see rationale above) |
| REL-09 | Tag resolved from the dispatch input (`inputs.tag` → `DISPATCH_TAG` env → `TAG=v0.3.0`), shape-validated, release existence asserted before any credential or tap access |

## Zero-side-effect confirmation

- No GitHub release created, edited, re-published, or pre-release-flipped (releases list
  timestamps all predate 2026-08-30).
- Tap repo `phuongddx/homebrew-spm-cache` HEAD unchanged (`2063fac`, 2026-08-11) after all runs.
- No secret value was ever printed, echoed, or logged anywhere in this plan — names only
  (`TAP_DEPLOY_KEY`, `TAP_REPO_TOKEN`); Actions masks secret material in logs regardless.
