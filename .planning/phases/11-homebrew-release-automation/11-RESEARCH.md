# Phase 11: Homebrew Release Automation - Research

**Researched:** 2026-08-29
**Domain:** GitHub Actions release automation, GitHub App auth, Homebrew tap publishing, POSIX shell integrity gates, RSpec structural YAML specs
**Confidence:** HIGH

> Graph context: `.planning/graphs/graph.json` is **stale** (70h old, 151 commits behind HEAD) — a query for "update-tap homebrew tap workflow" returned zero nodes; treat graph relationships as approximate. All findings below come from direct file reads, live local execution, `gh api` reads of the tap repo, and official vendor docs fetched this session.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Authentication & the Operator Gate (REL-04)**
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

**Tarball Integrity (REL-05)**
- `curl -fL --retry 3 --retry-delay 2` plus post-download sanity: non-empty file AND gzip
  magic bytes (`1f 8b`) — catches HTML/JSON error pages even on HTTP 200.
- sha256 computed only after integrity checks pass.

**Formula Edit Safety (REL-06 / REL-07)**
- Keep `sed` but anchor every pattern to the exact field line; require exactly-one match
  (`grep -c` == 1) before and after each substitution; then a post-condition block asserting
  url/version/sha256 all contain the new values — any miss exits non-zero.
- Replace `|| exit 0` with explicit no-diff detection: formula already current (idempotent
  retry) → succeed with an "already up to date" annotation; a real commit or push failure →
  fail (red run).

**Post-Publish Verification & Retry (REL-08 / REL-09)**
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

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope.
</user_constraints>

## Project Constraints (from CLAUDE.md)

- **GitHub CLI account:** "This repo's GitHub remote and releases belong to the `phuongddx` account, not whatever `gh` account is active by default. Before running any `gh` command (release, PR, workflow dispatch, etc.), ensure the active account is correct: `gh auth switch --hostname github.com --user phuongddx`" `[VERIFIED: CLAUDE.md:5-14]`. Applied this session — any executor/verifier step that dispatches the workflow or reads the tap must switch first. Both `phuongdoanduy` and `phuongddx` are logged in locally.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| REL-04 | The tap workflow authenticates without a human-owned expiring credential | `create-github-app-token@v3` wiring (inputs/outputs/expiry verified from official README); operator-gate status audited (secrets `TAP_APP_ID`/`TAP_APP_PRIVATE_KEY` do NOT yet exist — only the dead `TAP_REPO_TOKEN`); missing-secret loud-fail guard idiom |
| REL-05 | A tarball download failure fails the workflow loudly instead of hashing an error page | `curl -fL` semantics + gzip magic-byte gate (`od -An -tx1 -N2` → `1f8b`); sha256 only after integrity passes; tarball URL 302-redirect behavior confirmed live |
| REL-06 | A commit or push failure fails the workflow loudly — the `|| exit 0` silent-success path is removed | Exact current failure line quoted; explicit no-diff idiom (`git diff --quiet` → "already up to date" annotation, else commit+push with `set -euo pipefail`) |
| REL-07 | Formula edits are anchored and post-condition-checked | Actual tap formula fetched via `gh api` — **it has no `version` stanza** (the current `version` sed is a silent zero-match no-op, proving the failure mode is real); exactly-one-match `grep -c` idiom + full-line postcondition compares |
| REL-08 | Post-publish verification installs the published formula and asserts `spm-cache --version` matches the released tag | **`spm-cache --version` currently exits 1** ("Unknown option") — CLAide's `default_subcommand` intercepts root-only `--version`; proven mechanism + proven 3-line fix; brew-on-runner install form `brew install phuongddx/spm-cache/spm-cache` + `HOMEBREW_NO_AUTO_UPDATE` |
| REL-09 | `workflow_dispatch` with a `tag` input allows retrying without re-publishing | Official dispatch docs: `GITHUB_REF_NAME` is the dispatch ref (e.g. `main`), NOT the tag — tag must come from `inputs.tag`; trigger YAML shape + `gh workflow run` |
</phase_requirements>

## Summary

The phase rewrites one file (`.github/workflows/update-tap.yml`, 51 lines, fully read this session), adds structural RSpec coverage modeled on `spec/action_spec.rb`, and — newly discovered by this research — requires a **3-line Ruby CLI fix** because `spm-cache --version` currently fails with exit 1: CLAide routes a bare `--version` through the `default_subcommand` (`use`), which rejects it as an unknown option. Success criterion 4's assertion literally cannot pass without that fix. The fix is proven working locally this session.

The current workflow has every failure mode REL-04..07 describes, mapped line-by-line below: an unanchored `curl -L` that happily hashes a 404 HTML page into the formula, three unanchored `sed` calls of which the `version` one is a **guaranteed silent no-op** (the real tap formula, fetched via `gh api` this session, has no `version` stanza at all — Homebrew derives version from the URL tag), and a `git commit ... || exit 0` that converts every commit/push failure into a green run. The rewrite shape is fully constrained by CONTEXT decisions: GitHub App token → `checkout(token:)`, `curl -fL --retry` + gzip magic gate, anchored edits with exactly-one-match enforcement, explicit no-diff detection, a `macos`-runner verify job, and a `workflow_dispatch` `tag` input.

Two operational facts shape the plan: the operator gate is **open** (repo secrets list contains only `TAP_REPO_TOKEN` — verified via `gh api` on the `phuongddx` account; no GitHub App exists yet), and `macos-latest` has migrated to **macOS 26 arm64** (verified from the runner-images README), while this repo's own `ci.yml` pins `macos-15` explicitly.

**Primary recommendation:** Rewrite `update-tap.yml` as two jobs (`update-tap` on `ubuntu-latest`, `verify-publish` on a macOS runner gated by `needs:`), fix `--version` in `Main.run` before CLAide dispatch, add `spec/update_tap_workflow_spec.rb` (remember: Psych parses the workflow's `on:` key as boolean `true`), and gate the first live run behind the operator checkpoint.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Release-triggered formula publish | CI/CD (GitHub Actions, ubuntu job) | — | Entirely automation-domain logic; nothing belongs in the gem |
| Tap-repo authentication | CI/CD (GitHub App installation token minted in-job) | Repo settings (App install + secrets, operator) | Token minting is vendor-solved (`create-github-app-token`); credential custody belongs to repo secrets, never the codebase |
| Tarball integrity gate | CI/CD (shell step) | — | Download-verify-hash is pipeline concern; the gem never touches release tarballs |
| Formula field substitution | CI/CD (anchored sed + postconditions) | Tap repo (`Formula/spm-cache.rb` structure) | The substitution target lives in the external tap; only the workflow can edit it |
| Post-publish install verification | CI/CD (macOS runner job) | Homebrew (public tap) | Must exercise the real consumer path (brew tap → build → install → run) |
| `--version` reporting | Ruby CLI gem (`lib/spm_cache/main.rb`) | CLAide (root-command option) | The flag is a CLI concern; CLAide's default-subcommand routing is the bug site |
| Structural regression specs | Test tier (RSpec) | — | YAML is data; specs parse and assert properties without network |

## Standard Stack

This phase installs **no packages** — no gem, no npm, no SwiftPM additions. The "stack" is pinned GitHub Actions + vendor tooling, all verified against official sources this session.

### Core
| Component | Version/Tag | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `actions/create-github-app-token` | `v3` | Mint a scoped GitHub App installation token for the tap push | GitHub's own action; the locked REL-04 decision names it explicitly `[CITED: github.com/actions/create-github-app-token]` |
| `actions/checkout@v5` | `v5` (repo convention) | Checkout main repo + tap repo; `token:` input carries the app token into git config so `git push` works | Already used in both existing workflows; `token` input semantics verified from official README `[CITED: github.com/actions/checkout]` |
| `gh` CLI (preinstalled on runners) | runner image | `gh release view` existence check on dispatch path | First-party; authenticated via `GH_TOKEN: ${{ github.token }}` |
| Homebrew (preinstalled on macOS runners) | image default | `brew install phuongddx/spm-cache/spm-cache` verification | First-party; tap install form documented at docs.brew.sh `[CITED: docs.brew.sh/How-to-Create-and-Maintain-a-Tap]` |
| RSpec | `~> 3.12` (Gemfile, existing) | Structural workflow specs | Project test framework; `spec/action_spec.rb` is the 11-example precedent `[VERIFIED: spec/action_spec.rb, read this session]` |

### Supporting
| Component | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| POSIX/GNU coreutils on ubuntu runner (`od`, `grep -cE`, `sed -i -E`, `shasum`) | ubuntu-latest image | Integrity gate + anchored edits | Always — the edit job runs on ubuntu (GNU sed; BSD sed on macOS needs `-i ''`, one reason to keep this job on Linux) |
| `workflow_dispatch` + `inputs` context | GitHub Actions builtin | Tag-input retry path | REL-09 |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| GitHub App token | Write-access deploy key (SSH) | Lower ceremony (one key, no App); accepted substitute per CONTEXT — but key is still a long-lived secret and grants the same repo-wide write; App token is 1-hour scoped and attributable |
| GitHub App token | Fine-grained PAT | Still human-owned + expiring; explicitly rejected by locked decision |
| Anchored `sed` + `grep -c` | `brew bump-formula-pr` / Ruby-based formula rewrite | brew tap tooling targets core/homebrew flows and pulls a big dependency into the job; CONTEXT locks "keep sed" |
| `macos-latest` (verify job) | `macos-15` pin | CONTEXT names `macos-latest`; it now resolves to macOS 26 arm64. Pinning `macos-15` matches ci.yml's convention and dodges gradual `-latest` migrations — planner should honor CONTEXT but may flag the pin (see Open Questions) |

**Installation:** none. `bundle install` state is already correct; no gems added.

**Version verification:** No registry packages to verify. Actions are referenced by immutable-enough major tags (`v3`, `v5`) exactly as the existing workflows already do; both verified live against their official repos this session.

## Package Legitimacy Audit

No external packages are installed by this phase. The only third-party surface referenced is GitHub Actions tags:

| Action | Source Repo | Verdict | Disposition |
|--------|-------------|---------|-------------|
| `actions/create-github-app-token@v3` | github.com/actions/create-github-app-token (official GitHub org) | OK | Approved — README fetched and quoted this session |
| `actions/checkout@v5` | github.com/actions/checkout (official GitHub org) | OK | Approved — already in use in both repo workflows |

**Packages removed due to [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

## Architecture Patterns

### System Architecture Diagram

```
                    ┌──────────────────────────────────────────────┐
                    │              TRIGGERS                        │
                    │  release: [published]   workflow_dispatch    │
                    │                         (input: tag string)  │
                    └───────────────┬──────────────────┬───────────┘
                                    │                  │
                                    ▼                  ▼
                    ┌──────────────────────────────────────────────┐
                    │ JOB 1: update-tap (ubuntu-latest)            │
                    │                                              │
                    │  resolve tag ──── release: GITHUB_REF_NAME   │
                    │        │          dispatch: inputs.tag       │
                    │        │          (validate ^v[0-9] format)  │
                    │        ▼                                     │
                    │  [dispatch only] gh release view "$TAG"      │
                    │        │        (fail loudly if no release)  │
                    │        ▼                                     │
                    │  create-github-app-token@v3                 │
                    │    secrets TAP_APP_ID/TAP_APP_PRIVATE_KEY    │
                    │    ── fail loudly if secrets missing ──      │
                    │    owner: phuongddx                          │
                    │    repositories: homebrew-spm-cache          │
                    │        │                                     │
                    │        ▼                                     │
                    │  curl -fL --retry 3 → release.tar.gz         │
                    │    │ non-empty? gzip magic 1f8b?  ──fail──▶ RED
                    │    ▼                                         │
                    │  shasum -a 256 → SHA256                      │
                    │        │                                     │
                    │        ▼                                     │
                    │  checkout tap (token: app token, path: tap)  │
                    │        │                                     │
                    │        ▼                                     │
                    │  anchored edits: grep -c == 1 per field,     │
                    │  sed, postcondition full-line compares       │
                    │    │ any miss (0 or >1 matches) ────────▶ RED │
                    │    ▼                                         │
                    │  git diff --quiet?                           │
                    │    ├─ yes → "already up to date" note, OK    │
                    │    └─ no → commit + push ── any failure ──▶ RED│
                    └───────────────────┬──────────────────────────┘
                                        │ needs: update-tap
                                        ▼
                    ┌──────────────────────────────────────────────┐
                    │ JOB 2: verify-publish (macOS runner)         │
                    │                                              │
                    │  HOMEBREW_NO_AUTO_UPDATE=1                   │
                    │  brew install phuongddx/spm-cache/spm-cache  │
                    │        │ build failure ─────────────────▶ RED │
                    │        ▼                                     │
                    │  spm-cache --version                         │
                    │    │ output ≠ released tag ─────────────▶ RED │
                    │    ▼                                         │
                    │  GREEN  (red check on the release run = the  │
                    │           "visible notification")            │
                    └──────────────────────────────────────────────┘
                                        │
                    external: github.com/phuongddx/homebrew-spm-cache
                              (Formula/spm-cache.rb — the edit target)
                    external: github.com/phuongddx/spm-cache release
                              tarball (archive/refs/tags/<tag>.tar.gz)
```

A reader tracing the primary use case: release published → tag resolved → app token minted → tarball integrity-gated → formula anchored-edited → pushed → brew-installed on macOS → version asserted. Every dashed `▶ RED` is a REL-mandated loud failure.

### Recommended Project Structure
```
.github/workflows/update-tap.yml   # rewritten: 2 jobs, 2 triggers
lib/spm_cache/main.rb              # +3-line --version intercept before Command.run
spec/update_tap_workflow_spec.rb   # NEW structural spec (action_spec.rb precedent)
spec/main_version_spec.rb          # NEW (or extend core_spec.rb): --version behavior
```

### Pattern 1: Token wiring (create-github-app-token → checkout)
**What:** Mint the installation token in a step, feed it to checkout's `token:` input.
**When to use:** Always in this workflow (REL-04).
**Example:**
```yaml
# Source: github.com/actions/create-github-app-token README (fetched 2026-08-29)
- name: Get app token
  id: app-token
  uses: actions/create-github-app-token@v3
  with:
    app-id: ${{ secrets.TAP_APP_ID }}        # 'app-id' legacy input still accepted in v3
    private-key: ${{ secrets.TAP_APP_PRIVATE_KEY }}
    owner: phuongddx
    repositories: homebrew-spm-cache

- name: Checkout tap repository
  uses: actions/checkout@v5
  with:
    repository: phuongddx/homebrew-spm-cache
    token: ${{ steps.app-token.outputs.token }}
    path: tap
```
Verified semantics `[CITED: github.com/actions/create-github-app-token]`: the token **inherits all the installation's permissions** (Contents RW comes from the App installation on the tap, not from any workflow `permissions:` key); installation tokens **expire after 1 hour** and are **auto-revoked when the job completes** (default `skip-token-revoke: false`) — so the token cannot leak into another job and `verify-publish` needs no token at all (the tap is public). Verified semantics `[CITED: github.com/actions/checkout]`: checkout's `token` is written into the local git config, which is exactly what makes a later `git push` from the `tap/` path work; `persist-credentials` defaults to `true`, so no extra config is needed for the push step.

### Pattern 2: Anchored field edit with exactly-one-match enforcement
**What:** Require `grep -c` == 1 before each substitution, then verify the result by full-line compare.
**When to use:** The formula edit step (REL-07).
**Example:**
```bash
#!/usr/bin/env bash
# ubuntu-latest => GNU sed: `sed -i -E` (no suffix arg). Do NOT run this step on macOS (BSD sed).
set -euo pipefail
FORMULA="tap/Formula/spm-cache.rb"

replace_exactly_one() {
  local pattern="$1" replacement="$2" count
  count=$(grep -cE "$pattern" "$FORMULA" || true)   # `|| true`: grep exits 1 on zero matches
  if [ "$count" -ne 1 ]; then
    echo "::error::expected exactly 1 match for /$pattern/, got $count in $FORMULA"
    exit 1
  fi
  sed -i -E "s|$pattern|$replacement|" "$FORMULA"
}

URL_RE='^url "https://github\.com/phuongddx/spm-cache/archive/refs/tags/[^"]+\.tar\.gz"$'
SHA_RE='^sha256 "[0-9a-f]{64}"$'

replace_exactly_one "$URL_RE" 'url "https://github.com/phuongddx/spm-cache/archive/refs/tags/v'"$VERSION"'.tar.gz"'
replace_exactly_one "$SHA_RE" 'sha256 "'"$SHA"'"'

# Postconditions — full-line equality, stronger than substring containment:
grep -Fqx "url \"https://github.com/phuongddx/spm-cache/archive/refs/tags/v${VERSION}.tar.gz\"" "$FORMULA" \
  || { echo "::error::url postcondition failed"; exit 1; }
grep -Fqx "sha256 \"${SHA}\"" "$FORMULA" \
  || { echo "::error::sha256 postcondition failed"; exit 1; }
```
The `^…$` anchors reject over-broad matches; `grep -c` == 1 rejects zero-match (the current live failure mode — see Pitfall 3) and multi-match; the postconditions reject any edit that did not land exactly. Note the regexes mirror the **actual** formula fields quoted below under Pitfall 3 — there is no `version` stanza to anchor unless one is added (see Open Questions).

### Pattern 3: Explicit no-diff detection (replacing `|| exit 0`)
**What:** Idempotent retry succeeds visibly; real commit/push failures go red.
```bash
cd tap
git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"
git add Formula/spm-cache.rb
if git diff --cached --quiet; then
  echo "::notice::Formula already at ${VERSION} — nothing to do (idempotent retry)."
  exit 0
fi
git commit -m "chore: update spm-cache to ${VERSION}"
git push   # any failure here is a loud red run — there is no `|| exit 0` anywhere
```

### Pattern 4: Tarball integrity gate (REL-05)
```bash
set -euo pipefail
TARBALL_URL="https://github.com/${GITHUB_REPOSITORY}/archive/refs/tags/${TAG}.tar.gz"
curl -fL --retry 3 --retry-delay 2 -o release.tar.gz "$TARBALL_URL"
# -f: HTTP >= 400 fails instead of saving the error page; -L: follow the codeload 302
# (verified live: the tag URL answers 302 → objects.githubusercontent.com)
test -s release.tar.gz || { echo "::error::tarball is empty"; exit 1; }
magic=$(od -An -tx1 -N2 release.tar.gz | tr -d ' \n')
[ "$magic" = "1f8b" ] || { echo "::error::not gzip (magic bytes: ${magic}) — likely an HTML/JSON error page"; exit 1; }
SHA=$(shasum -a 256 release.tar.gz | awk '{print $1}')
```

### Pattern 5: Tag resolution for both triggers (REL-09)
```yaml
- name: Resolve tag (release or dispatch input)
  id: version
  env:
    DISPATCH_TAG: ${{ inputs.tag }}   # env indirection — never interpolate into run: bodies
  run: |
    set -euo pipefail
    if [ -n "$DISPATCH_TAG" ]; then TAG="$DISPATCH_TAG"; else TAG="$GITHUB_REF_NAME"; fi
    case "$TAG" in
      v[0-9]*) ;;
      *) echo "::error::tag '${TAG}' must look like v0.4.0"; exit 1 ;;
    esac
    echo "tag=${TAG}" >> "$GITHUB_OUTPUT"
    echo "version=${TAG#v}" >> "$GITHUB_OUTPUT"
```
Why the dispatch branch must use the input: on `workflow_dispatch`, `GITHUB_REF_NAME` is **the branch or tag the workflow was dispatched on** (e.g. `main`), not the release tag — only the `release` event sets `GITHUB_REF_NAME` to the release tag `[CITED: docs.github.com/en/actions/reference/events-that-trigger-workflows]`. On dispatch, additionally assert the release exists before touching the tap: `gh release view "$TAG" --json tagName` with `GH_TOKEN: ${{ github.token }}` (a nonexistent tag would otherwise produce a 404-hashing failure further downstream — failing at the source is louder).

### Pattern 6: The `--version` intercept (REL-08 enabler — REQUIRED code change)
**What:** `spm-cache --version` currently exits 1. Fix by intercepting before CLAide dispatch.
**Proof of bug** (run this session): `bundle exec bin/spm-cache --version` → `[!] Unknown option: `--version'` … exit=1. Root cause: `Command.parse` sees no positional argument → `abstract_command? && default_subcommand` → `load_default_subcommand("use")` → the `use` instance's options lack `--version` (it is a **root-only** option) → validate! fails `[VERIFIED: local execution + claide-1.1.0/lib/claide/command.rb:215-224, 285-291]`. Verbatim from the installed gem:
```ruby
DEFAULT_ROOT_OPTIONS = [
  ['--version', 'Show the version of the tool'],
]
```
…handled only when `self.class.root_command?` (`handle_root_options` at command.rb:288-291) — which the routed-to `use` instance is not.
**Fix (proven working this session — prints `0.3.0`, exit 0):**
```ruby
# lib/spm_cache/main.rb
def self.run(argv)
  SPMCache::Main.load_all
  return puts(SPMCache::VERSION) if argv.first == "--version"  # before default_subcommand routing
  Command.run(argv)
end
```
`SPMCache::VERSION` comes from the `VERSION` file (`lib/spm_cache/version.rb` reads `../../VERSION`), which the gemspec ships (`spec.files` includes `"VERSION"`) — so the installed formula reports the released version `[VERIFIED: lib/spm_cache/version.rb, spm_cache.gemspec:15-23, both read this session]`. CLAide's `print_version` output format is exactly the bare version string (`puts self.class.version`) `[VERIFIED: claide-1.1.0 command.rb:299-301]`, so the verify assertion is a whole-string compare after trimming whitespace.

### Pattern 7: Structural workflow spec (validation layer)
**What:** Parse the workflow YAML and assert the REL properties — no network, seconds to run.
```ruby
# spec/update_tap_workflow_spec.rb — modeled on spec/action_spec.rb
let(:workflow) { YAML.safe_load_file('.github/workflows/update-tap.yml', permitted_classes: [], aliases: false) }
# ⚠ Psych parses the unquoted `on:` key as boolean true (verified: keys => ["name", true, "jobs"])
let(:triggers) { workflow[true] }
```
Two complementary assertion styles, both used by this codebase's precedent: YAML-walking for structure (jobs, steps, `uses:`, `runs-on`, `needs:`), raw-text regex for shell-body properties (`File.read` + `include`/`match`) — because asserting `"curl -fL"` inside a multi-line shell string via the parsed tree is clumsier and no stronger. `spec/action_spec.rb` already combines both styles (`YAML.safe_load_file` at line 13, `File.read('action/README.md')` at line 45) `[VERIFIED: spec/action_spec.rb, read this session]`.

### Anti-Patterns to Avoid
- **`${{ inputs.tag }}` / `${{ github.event.* }}` interpolated directly inside `run:` bodies** — script injection surface; always pass through `env:` first. This repo already enforces the equivalent rule in `action_spec.rb` ("never expands GitHub input contexts inside run script bodies", lines 77-83).
- **`|| exit 0`, `|| true`, `continue-on-error: true` anywhere in the publish path** — the exact silent-green failure class this phase exists to remove.
- **Unquoted `on:` assumptions in specs** — `workflow['on']` returns `nil` under Psych; the key is `true`.
- **Running the sed job on macOS** — BSD sed's `-i` requires a suffix argument; keep the edit job on ubuntu-latest (as today).
- **Relying on `GITHUB_REF_NAME` under dispatch** — it is the dispatch ref, not the tag.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| GitHub App JWT + installation token minting | Manual JWT signing (RS256 over app id/key, then POST /app/installations/…/access_tokens) | `actions/create-github-app-token@v3` | Vendor-solved; hand-rolled JWT has a decade of footguns (iat/nbf skew, key escaping) for zero benefit |
| Cross-repo git auth for checkout+push | Manual `git remote set-url` with embedded tokens or credential helpers | `actions/checkout@v5` with `token:` | Checkout writes the token into git config itself; embedding tokens in URLs risks leaking them into logs |
| Version extraction/parsing in Ruby | New gem code for release metadata | `GITHUB_REF_NAME` / `inputs.tag` + shell `case` | The event context already carries the tag; no code needed in the gem |
| YAML property testing | Ad-hoc greps in CI that re-parse YAML wrong | RSpec structural spec with `YAML.safe_load_file` | Precedent exists (`action_spec.rb`); the `on:`→`true` gotcha is handled once, in the spec helper |
| Release existence check on dispatch | Raw `curl` against the API | `gh release view "$TAG"` | First-party, authenticated via `GH_TOKEN`, preinstalled on runners |

**Key insight:** every moving part of this phase is either vendor-provided (token action, checkout, gh, brew) or a few dozen lines of POSIX shell whose ONLY job is to fail loudly. The engineering value is in the failure paths, not in building machinery.

## Runtime State Inventory

Not a rename/refactor phase, but the rewrite changes **live CI configuration state** — audited explicitly:

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — no database/datastore in scope. Verified: the workflow persists nothing outside git | None |
| Live service config | Repo secrets on `phuongddx/spm-cache`: **exactly one secret exists, `TAP_REPO_TOKEN`** (the dead classic PAT). `TAP_APP_ID` / `TAP_APP_PRIVATE_KEY` do NOT exist yet `[VERIFIED: gh api repos/phuongddx/spm-cache/actions/secrets --jq '.secrets[].name' → TAP_REPO_TOKEN, run this session as phuongddx]` | Operator: create GitHub App, install on `homebrew-spm-cache` only, add 2 secrets. Then delete the dead `TAP_REPO_TOKEN` (cleanup task in plan) |
| OS-registered state | None — no scheduled tasks/launchd/systemd touched by this workflow | None |
| Secrets/env vars | Workflow references `secrets.TAP_REPO_TOKEN` at `.github/workflows/update-tap.yml:29` — after rewrite this reference disappears | Code edit only (workflow rewrite); secret deletion is the repo-settings step above |
| Build artifacts | None — the workflow clones fresh tap checkouts per run; no cached artifacts survive | None |

## Common Pitfalls

### Pitfall 1: `spm-cache --version` does not exist today (blocks REL-08 literally)
**What goes wrong:** Success criterion 4 asserts `spm-cache --version` matches the tag — but the flag exits 1 today ("Unknown option").
**Why it happens:** CLAide's `--version` is a root-command-only option; `default_subcommand "use"` routes bare invocations to the `use` subcommand before root-option handling (`claide-1.1.0 command.rb:353-354` `elsif abstract_command? && default_subcommand` → `load_default_subcommand`).
**How to avoid:** 3-line intercept in `Main.run` (Pattern 6, proven working this session) + a spec asserting `Main.run(["--version"])` prints `SPMCache::VERSION` and exits 0.
**Warning signs:** verify job failing with `[!] Unknown option: `--version'` in its log.

### Pitfall 2: `GITHUB_REF_NAME` is wrong under `workflow_dispatch`
**What goes wrong:** The retry path resolves "main" (the dispatch ref) as the tag, producing `https://…/tags/main.tar.gz` → 404 → red run at best, garbage at worst.
**Why:** Official docs: dispatch events set `GITHUB_REF`/`GITHUB_REF_NAME` to the ref the workflow runs on, not any release tag `[CITED: docs.github.com events-that-trigger-workflows]`.
**How to avoid:** Pattern 5 — dispatch branch reads `inputs.tag` via `env:`; validate `^v[0-9]` shape; `gh release view` existence check.
**Warning signs:** tarball URL containing a branch name in failed-run logs.

### Pitfall 3: The current `version` sed matches nothing — REL-07's zero-match failure is LIVE, not hypothetical
**What goes wrong:** The existing workflow runs `sed -i "s|version \".*\"|version \"${VERSION}\"|"` — but the real tap formula has **no `version` stanza at all**. Homebrew derives the formula version from the URL tag. `sed` exits 0 on zero matches, so this has been silently doing nothing every release.
**Why:** The workflow was written against an assumed formula shape, and nothing post-conditions the edit.
**Evidence (verbatim, fetched via `gh api repos/phuongddx/homebrew-spm-cache/contents/Formula/spm-cache.rb` this session):
```ruby
  desc "Cache SPM dependencies as xcframeworks to reduce Xcode build times"
  homepage "https://github.com/phuongddx/spm-cache"
  url "https://github.com/phuongddx/spm-cache/archive/refs/tags/v0.3.0.tar.gz"
  sha256 "e3ff4881afc7484a38089c1d557ab9302e2bc3193447eb0252b68d37f222d33c"
  license "MIT"
  head "https://github.com/phuongddx/spm-cache.git", branch: "main"

  depends_on :macos
  depends_on "ruby@3.3"

  uses_from_macos "swift"
```
**How to avoid:** Pattern 2 (exactly-one-match on the two fields that exist: `url`, `sha256`). Decide the `version` question explicitly (Open Question 2): either rely on URL-derived version (postcondition: URL contains `v${VERSION}.tar.gz`) or add an explicit `version` stanza to the tap formula once, then anchor all three.
**Warning signs:** a "success" run whose formula diff shows only 2 changed lines.

### Pitfall 4: Psych parses the workflow's `on:` key as boolean `true`
**What goes wrong:** A structural spec doing `workflow['on']` gets `nil` and every trigger assertion fails vacuously or errors.
**Evidence:** `YAML.safe_load_file('.github/workflows/update-tap.yml').keys` → `["name", true, "jobs"]` — verified this session on Ruby 3.2.3 / Psych 5.0.1.
**How to avoid:** Use `workflow[true]` for the trigger map (Pattern 7).

### Pitfall 5: `curl` without `-f` hashes the error page
**What goes wrong:** GitHub tag-archive URLs answer 302 (verified live: `…/archive/refs/tags/v0.3.0.tar.gz` → 302) and error cases can render 200 HTML; plain `curl -L -o` saves whatever came back and `shasum` happily digests it into the formula.
**How to avoid:** `curl -fL --retry 3 --retry-delay 2` + non-empty + gzip magic `1f8b` gate (Pattern 4) — belt and braces, exactly the locked CONTEXT decision.

### Pitfall 6: App token lifetime and cross-job token reuse
**What goes wrong:** Minting the token once in `update-tap` and referencing `steps.app-token.outputs.token` from `verify-publish` — outputs don't cross jobs without `jobs.<id>.outputs` plumbing, and the token is auto-revoked at the source job's end anyway.
**Why:** Installation tokens expire after 1 hour and are revoked in the minting job's post step by default `[CITED: create-github-app-token README]`.
**How to avoid:** Keep the token entirely inside `update-tap`; `verify-publish` needs no auth (public tap) — its brew install is anonymous.

### Pitfall 7: Two releases racing on the tap push
**What goes wrong:** Release A and B publish near-simultaneously; both check out the tap at the same SHA; B's push non-fast-forwards → red run (loud, but a spurious failure requiring the exact retry REL-09 then provides).
**How to avoid:** `concurrency: { group: update-tap, cancel-in-progress: false }` at workflow level — runs queue instead of racing.

### Pitfall 8: `macos-latest` moved to macOS 26
**What goes wrong:** Assumptions from the macOS 15 era (Xcode default, brew prefix) silently shift under `-latest` during gradual migrations.
**Evidence:** runner-images README (2026-08): `macos-latest` → **macOS 26 Arm64** (GA); `macos-15` remains GA as an explicit label; the repo's own ci.yml pins `macos-15` `[VERIFIED: .github/workflows/ci.yml:18,38]` `[CITED: raw.githubusercontent.com/actions/runner-images/main/README.md]`.
**How to avoid:** CONTEXT names `macos-latest` — honor it, but know it means macOS 26 arm64; if the first verify run hits an OS-specific formula issue, pinning `macos-15` is the fallback (Open Question 1).

### Pitfall 9: Slow brew update on ephemeral runners
**What goes wrong:** `brew install` triggers `brew update` first, adding minutes and nondeterminism.
**How to avoid:** job-level `env: HOMEBREW_NO_AUTO_UPDATE: "1"` — the canonical recommendation for CI runners `[CITED: github.com/actions/runner-images issue #2466]`. Note the install builds from source (gem + `swift build` of the companion — the formula's install method, verbatim above), so expect a job of several minutes, not seconds.

### Pitfall 10: Secrets exist but are empty / misnamed at first run
**What goes wrong:** `create-github-app-token` fails with a vendor error that doesn't say which secret to fix.
**How to avoid:** Preceded guard step (CONTEXT locked decision): `if [ -z "$TAP_APP_ID" ] || [ -z "$TAP_APP_PRIVATE_KEY" ]; then echo "::error::Configure repo secrets TAP_APP_ID and TAP_APP_PRIVATE_KEY (GitHub App, Contents R/W + Metadata R, installed on homebrew-spm-cache only)"; exit 1; fi` with values injected via `env:`.

## Code Examples

### Complete verify job (REL-08)
```yaml
verify-publish:
  needs: update-tap
  runs-on: macos-latest          # resolves to macOS 26 arm64 as of 2026-08 — see Pitfall 8
  env:
    HOMEBREW_NO_AUTO_UPDATE: "1"
    EXPECTED_VERSION: ${{ needs.update-tap.outputs.version }}
  steps:
    - name: Install published formula from the tap
      run: brew install phuongddx/spm-cache/spm-cache   # user/repo/formula form auto-taps
    - name: Assert installed version matches the release
      run: |
        set -euo pipefail
        brew list --versions spm-cache
        ACTUAL="$(spm-cache --version | tr -d '[:space:]')"
        echo "installed: ${ACTUAL}, expected: ${EXPECTED_VERSION}"
        [ "$ACTUAL" = "$EXPECTED_VERSION" ]
```
Install form is Homebrew-documented (`brew install user/repo/formula` implicitly taps) `[CITED: docs.brew.sh/How-to-Create-and-Maintain-a-Tap]`. `needs.update-tap.outputs.version` requires declaring `outputs:` on the update-tap job from the resolve step's `$GITHUB_OUTPUT`.

### workflow_dispatch trigger block (REL-09)
```yaml
on:
  release:
    types: [published]
  workflow_dispatch:
    inputs:
      tag:
        description: 'Existing release tag to re-publish (e.g. v0.4.0)'
        required: true
        type: string
```
`inputs` context values keep declared types; `github.event.inputs` stringifies — irrelevant for a string input, but prefer `inputs.tag` `[CITED: docs.github.com events-that-trigger-workflows]`. Manual invocation: `gh workflow run update-tap.yml -f tag=v0.4.0` (after `gh auth switch --user phuongddx` per CLAUDE.md). Dispatch-only caveat: the workflow file must exist on the **default branch** to be dispatchable.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Classic PAT stored as a repo secret for cross-repo pushes | GitHub App installation tokens via `actions/create-github-app-token` | v3 line current through 2026 | 1-hour tokens, installation-scoped, attributable bot identity — eliminates the "PAT auto-deleted after a year unused" outage class that motivated this phase |
| `actions/checkout@v4` with PAT | `@v5` (repo convention) with App token via `token:` | v5 GA 2025 | No workflow change beyond the token input; `persist-credentials` still defaults true |
| Unanchored `sed` on formula text | exactly-one-match + postcondition gates | — | This phase's contribution |

**Deprecated/outdated:**
- `TAP_REPO_TOKEN` (classic PAT) — dead (auto-deleted); secret exists in repo settings and should be removed after the cutover `[VERIFIED: gh api secret list]`.
- Nothing in the gem/lib is deprecated by this phase.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The brew install of the formula completes on a GitHub macOS runner within a reasonable job time (~10-20 min: gem deps + `swift build` release) | Pitfall 9, Validation | Verify job times out → pin runner / investigate; not verifiable without a live run (operator gate) |
| A2 | The formula installs cleanly on macOS 26 (`macos-latest`) — it installed for v0.3.0 hand-tested on the operator's machine; runner OS differs | Pitfall 8 | First verify run fails on OS/toolchain specifics → fallback pin `macos-15`, formula tweak is tap-side (out of repo) |
| A3 | Adding an explicit `version` stanza to the tap formula is desirable (recommended, Open Question 2) — legal in Homebrew, overrides URL derivation | Pitfall 3 | None functionally; if skipped, version remains URL-derived (still asserted via URL postcondition) |
| A4 | `gh release view` works with `GH_TOKEN: ${{ github.token }}` under `permissions: contents: read` on the dispatch path | Pattern 5 | Existence check fails auth → loosen to contents: read+write at job level or drop check (integrity gate still catches missing tarball) |
| A5 | `shasum -a 256` (perl) is present on ubuntu-latest (it is used by the current workflow's history) — alternatively `sha256sum` | Pattern 4 | Trivial: either utility exists on the image |

## Open Questions (RESOLVED)

> All three resolved at planning time (2026-08-30); pointers inline. Recorded per the plan-checker advisory so future readers do not re-litigate.

1. **Verify-job runner label: `macos-latest` (macOS 26) vs pinned `macos-15`?** — RESOLVED (2026-08-30, plan adoption): ship `macos-latest` per CONTEXT (11-02 Task 3); `macos-15` documented as the one-line fallback if the first live run hits an OS-specific failure.
   - What we know: CONTEXT names `macos-latest`; it resolves to macOS 26 arm64 (verified); ci.yml pins `macos-15`; runner docs recommend pinning to dodge gradual migrations.
   - What's unclear: whether the source-built formula (brewed ruby@3.3 + swift build) has any macOS 26 wrinkle.
   - Recommendation: ship with `macos-latest` per CONTEXT; if the first live run hits an OS-specific failure, pin `macos-15` as a one-line fix.
2. **Explicit `version` stanza in the tap formula?** — RESOLVED (2026-08-30, planner decision recorded in 11-02 must_haves/success criteria): anchor url+sha256 only, assert version via the URL-tag postcondition (matches the verified live formula shape; no out-of-repo manual step added). Adding a stanza later remains compatible with the postcondition block.
   - What we know: no stanza exists today (verified); Homebrew derives version from the URL tag; the current workflow's `version` sed is a live zero-match no-op.
   - What's unclear: whether the operator wants the visible-by-grep version field.
   - Recommendation: add `version "0.3.0"` to `Formula/spm-cache.rb` once (operator or first scripted edit), then anchor all three fields. If declined, anchor url+sha256 and assert version via the URL postcondition — both satisfy SC3's intent.
3. **Sequencing of the operator gate vs merge.** — RESOLVED (2026-08-30, plan adoption): code+specs first (Wave 1: 11-01, 11-02), operator checkpoint + idempotent dispatch dry-run after (Wave 2: 11-03, depends_on both).
   - What we know: secrets don't exist yet (verified); structural specs and CLI fix are mergeable without them; the first live release (or dispatch dry-run of an existing tag, e.g. v0.3.0 — safe because idempotent no-diff) exercises the real path.
   - Recommendation: plan explicitly orders: code+specs → operator checkpoint (App + secrets + delete TAP_REPO_TOKEN) → live verification via `workflow_dispatch` with `tag: v0.3.0` (idempotent — formula already at v0.3.0, so the run exercises everything and lands on "already up to date" + brew verify, with zero side effects).

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| gh CLI (local, for executor/verifier reads + dispatch) | operator gate audit, live retry | ✓ | switched to phuongddx per CLAUDE.md | — |
| Repo secrets `TAP_APP_ID` / `TAP_APP_PRIVATE_KEY` | live run of rewritten workflow | ✗ (verified absent; only `TAP_REPO_TOKEN` exists) | — | Write-access deploy key (CONTEXT-approved substitute); code+specs proceed regardless |
| GitHub App (phuongddx, Contents R/W + Metadata R, installed on homebrew-spm-cache only) | REL-04 live auth | ✗ (not created) | — | Deploy key |
| ubuntu-latest / macOS runners | workflow runtime | ✓ | GitHub-hosted | — |
| Homebrew on macOS runner | REL-08 verify | ✓ (preinstalled, /opt/homebrew arm64) | image default | — |
| Ruby 3.2.3 + bundler + rspec (local) | structural specs | ✓ | ruby 3.2.3, rspec ~>3.12 | — |
| READ access to tap repo | research/planning | ✓ (public — anonymous HTTP 200 verified) | — | — |

**Missing dependencies with no fallback:** none blocking code/spec work. The missing App+secrets block only the live-run checkpoint (planner: `checkpoint:human-verify` task for the operator gate, exactly as the roadmap's Operator gate anticipates).
**Missing dependencies with fallback:** App+secrets → deploy key pivot (small workflow diff: checkout with `ssh-key: ${{ secrets.TAP_DEPLOY_KEY }}` instead of `token:`).

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | RSpec ~> 3.12 (Gemfile; 416 examples currently green) |
| Config file | `spec/spec_helper.rb` (no `.rspec` file — defaults) |
| Quick run command | `bundle exec rspec spec/update_tap_workflow_spec.rb` |
| Full suite command | `bundle exec rspec` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| REL-04 | App-token step present (`app-id`/`private-key` from `TAP_APP_ID`/`TAP_APP_PRIVATE_KEY`), tap checkout uses its output token, zero references to `TAP_REPO_TOKEN`, missing-secret guard step present | structural (YAML) | `bundle exec rspec spec/update_tap_workflow_spec.rb` | ❌ Wave 0 |
| REL-05 | Download step contains `curl -fL` + `--retry`; integrity gate present (`test -s` + `1f8b` magic); sha256 computed downstream of the gate | structural (text) | same | ❌ Wave 0 |
| REL-06 | File contains no `\|\| exit 0`; explicit no-diff branch present (`git diff --cached --quiet` + notice); `git push` present and unguarded | structural (text) | same | ❌ Wave 0 |
| REL-07 | Edit block contains `grep -c` exactly-one enforcement (`-ne 1` error) and postcondition greps (`grep -Fqx` on url/sha lines) | structural (text) | same | ❌ Wave 0 |
| REL-08 | `verify-publish` job: `needs: update-tap`, `runs-on: macos*`, `brew install phuongddx/spm-cache/spm-cache`, `spm-cache --version` comparison against the resolved version output | structural (YAML) | same | ❌ Wave 0 |
| REL-09 | Trigger map (`workflow[true]`) contains `workflow_dispatch` with a `tag` string input; resolve step branches on the dispatch input; `GITHUB_REF_NAME` used only in the release branch | structural (YAML+text) | same | ❌ Wave 0 |
| REL-08 (CLI) | `SPMCache::Main.run(["--version"])` prints `SPMCache::VERSION` to stdout (compare captured stdout) | unit | `bundle exec rspec spec/main_version_spec.rb` | ❌ Wave 0 |
| SC-injection | No `${{ inputs.` / `${{ github.event.` expansions inside any `run:` body (env indirection only) — direct port of `action_spec.rb` lines 77-83 | structural (text) | same | ❌ Wave 0 |

All structural commands are sub-second, hermetic (file reads only — "nothing live-networked in CI" per CONTEXT spec strategy). The unit spec for `--version` needs stdout capture around `Main.run` (the intercept `puts`es directly) — `expect { described_class.run(["--version"]) }.to output("#{SPMCache::VERSION}\n").to_stdout`.

### Sampling Rate
- **Per task commit:** `bundle exec rspec spec/update_tap_workflow_spec.rb spec/main_version_spec.rb`
- **Per wave merge:** `bundle exec rspec` (full suite — guard against regressions in the 416-example baseline)
- **Phase gate:** Full suite green + live dispatch dry-run (`tag: v0.3.0`, idempotent) red/green per operator gate

### Wave 0 Gaps
- [ ] `spec/update_tap_workflow_spec.rb` — covers REL-04..09 + injection guard (structural, Psych `true` key)
- [ ] `spec/main_version_spec.rb` — covers the `--version` intercept (REL-08 CLI half)
- [ ] Framework install: none needed (RSpec already configured)

## Security Domain

`security_enforcement: true`, ASVS level 1, block on `high` `.planning/config.json` `[VERIFIED: .planning/config.json:47-49]`. This phase changes CI authentication — a real threat surface.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | yes (machine auth) | GitHub App installation token (`create-github-app-token@v3`) — never a human PAT; key custody in repo secrets |
| V3 Session Management | yes (token lifetime) | 1-hour expiry, auto-revoke at job end, `skip-token-revoke` left false |
| V4 Access Control | yes | App installed on `homebrew-spm-cache` ONLY; Contents R/W + Metadata R; no `workflow` scope → token cannot alter tap workflows; workflow-level `permissions: contents: read` keeps GITHUB_TOKEN minimal |
| V5 Input Validation | yes | `tag` input validated `^v[0-9]` shape; all context passed via `env:`, never interpolated into `run:` bodies; formula edits anchored (pattern-validated) |
| V6 Cryptography | no | No crypto implemented; sha256 via `shasum`, token signing inside vendor action |

### Known Threat Patterns for GitHub Actions CI-auth changes

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Script injection via `tag` input (e.g. crafted ref names reaching `run:` bodies) | Tampering / Elevation of Privilege | `env:` indirection + `case`-format validation (Pattern 5); structural spec bans `${{ inputs.` inside `run:` (repo precedent, `action_spec.rb:77-83`) |
| Secret exfiltration (`TAP_APP_PRIVATE_KEY` echoed into logs) | Information Disclosure | Secrets are auto-masked by Actions; never `echo` env-mapped secrets; guard step prints secret NAMES only, never values |
| Over-privileged token (app installed org-wide, or with `workflow` scope) | Elevation of Privilege | Installation scoped to the single tap repo; Contents+Metadata only; `repositories: homebrew-spm-cache` narrows the minted token further |
| `pull_request`-trigger abuse (fork PRs running the publish path) | Spoofing / Tampering | Triggers are `release: [published]` (requires maintainer to publish) and `workflow_dispatch` (requires write access) — no `pull_request` trigger must be added; structural spec can pin the trigger set |
| Formula tampering via over-broad substitution | Tampering | Anchored regexes + exactly-one-match + full-line postconditions (REL-07) — an over-broad edit fails red |
| Silent-failure repudiation (`\|\| exit 0` swallowing a failed push) | Repudiation / Integrity | No-skip-step policy; `set -euo pipefail` in every `run:` block; concurrency group prevents push races |
| Token reuse / leakage across jobs | Information Disclosure | Token minted and consumed inside one job; auto-revoked post-job; verify job anonymous |

## Sources

### Primary (HIGH confidence — read/executed this session)
- `.github/workflows/update-tap.yml` — the rewrite target, every failure mode quoted verbatim
- `gh api repos/phuongddx/homebrew-spm-cache/contents/Formula/spm-cache.rb` — actual formula (no `version` stanza; install method; depends_on)
- `gh api repos/phuongddx/spm-cache/actions/secrets` — operator-gate state (only `TAP_REPO_TOKEN`)
- `spec/action_spec.rb`, `lib/spm_cache/main.rb`, `lib/spm_cache/command.rb`, `lib/spm_cache/version.rb`, `spm_cache.gemspec`, `.github/workflows/ci.yml`, `CLAUDE.md`, `.planning/config.json` — read this session
- Local execution: `spm-cache --version` failure + exit code; CLAide 1.1.0 source (`DEFAULT_ROOT_OPTIONS`, `parse`/`load_default_subcommand`, `print_version`); the intercept fix printing `0.3.0`; Psych `on:`→`true`; tarball URL 302; tap repo public 200
- claide-1.1.0 installed gem source at `/Users/ddphuong/.xcframework-cli/gems/claide-1.1.0/lib/claide/command.rb`

### Secondary (MEDIUM confidence — official docs fetched this session)
- [actions/create-github-app-token README](https://github.com/actions/create-github-app-token) — inputs/outputs, installation-permission inheritance, 1-hour expiry, auto-revoke
- [actions/checkout README](https://github.com/actions/checkout) — `token:` semantics, `persist-credentials`, cross-repo auth
- [docs.github.com — Events that trigger workflows](https://docs.github.com/en/actions/reference/events-that-trigger-workflows) — `workflow_dispatch` inputs, `GITHUB_REF_NAME` semantics per event
- [actions/runner-images README](https://github.com/actions/runner-images) — `macos-latest` → macOS 26 arm64; macos-15 GA
- [docs.brew.sh — How to Create and Maintain a Tap](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap) — `brew install user/repo/formula` form

### Tertiary (LOW confidence)
- [actions/runner-images issue #2466](https://github.com/actions/virtual-environments/issues/2466) — `HOMEBREW_NO_AUTO_UPDATE` CI recommendation (community-corroborated; brew behavior is well known but not doc-quoted here)
- Job-duration estimate for the source-built formula (A1) — no live measurement

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — every action verified against its official repo this session; no registry packages involved
- Architecture: HIGH — workflow shape fully constrained by CONTEXT + verified current-state facts; the one code change (`--version`) has a locally proven mechanism AND fix
- Pitfalls: HIGH — Pitfalls 1-5 are verified by direct execution/api-read this session, not inferred

**Research date:** 2026-08-29
**Valid until:** 2026-09-28 (stable domain; re-check runner labels if execution slips past then — `-latest` migrations are gradual)
