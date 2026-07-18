# v0.2.3 Release: The Gap Between "Fix Committed" and "Fix Shipped"

**Date**: 2026-07-18 23:00  
**Severity**: High  
**Component**: Release workflow (git push, tag, GitHub release, Homebrew tap automation)  
**Status**: Resolved  

## What Happened

After committing the eh_xcframework binary-target bug fix (d55739a, earlier journal entry), four commits sat unpushed and untagged in local history. The fix existed in the code but was architecturally inert for any downstream consumer—including the `epost-app` project that was blocked by this exact bug—because Homebrew taps only pick up tagged, published releases. The gap was discovered only when a downstream consumer's blocker prompted checking: "Is this fix actually available to install yet?"

Once the gap was flagged, the release chain completed in order:
1. `git push origin main` — pushed 4 commits (527051b..5ec953e) ahead of origin.
2. `git tag -a v0.2.3` + `git push origin v0.2.3`.
3. `gh release create v0.2.3` with release notes following the established v0.2.0/v0.2.1/v0.2.2 format (intro paragraph, ## Fixed, ## Verification, upgrade call-to-action).
4. Verified the `.github/workflows/update-tap.yml` workflow (triggered on `release: published`) completed successfully (`gh run list`). Confirmed via `gh api` that the Homebrew tap formula (`phuongddx/homebrew-spm-cache`) now points at the v0.2.3 tarball with the correct sha256.

## The Brutal Truth

This is frustrating in a specific way: the fix was objectively correct, the code was merged, the tests passed, and the version was bumped—but none of that mattered to a consumer until the release chain closed. The only reason this gap was caught is because the downstream blocker prompted a "is this actually available yet?" check. If that question hadn't been asked, the fix would have continued to be unavailable to Homebrew users indefinitely. It's the difference between "we fixed it" and "it's fixed for you."

The real frustration is that this is not a rare oversight. It's the most common failure mode of local-only fixes: a developer commits, tests, merges, maybe even bumps the version—and then stops. The assumption is silent: "committed = shipped." It's never true. It's especially dangerous in a tool like spm-cache that ships via Homebrew; the consumer cannot access your fix until the artifact is tagged, released, and indexed by the tap formula. The lag is invisible until you check.

## Technical Details

**Before release:**
- 4 commits ahead of `origin/main`: 527051b, 6e23f8d, c625f9a, 5ec953e
- No tag; no GitHub release; no Homebrew tap update
- Downstream consumer: "I'm still hitting the eh_xcframework error"
- Reality: the fix existed locally but was not reachable via `brew install spm-cache`

**After release:**
- Commits pushed to origin
- Tag `v0.2.3` created and pushed
- GitHub release created with release notes
- `.github/workflows/update-tap.yml` workflow triggered (event: `release: published`)
- Homebrew tap formula updated to point at v0.2.3 tarball with correct sha256
- Downstream consumer: can now run `brew upgrade spm-cache` and get the fix

**Verification steps:**
```bash
# Confirmed tag and release exist
gh api repos/phuongddx/spm-cache/releases/tags/v0.2.3

# Confirmed workflow ran
gh run list --workflow=update-tap.yml

# Confirmed tap formula points to correct version
gh api repos/phuongddx/homebrew-spm-cache/contents/Formula/spm-cache.rb
```

## What We Tried

**Initial state:** 4 commits present in local main, 4 commits ahead of origin. Bug fix verified in code and tests. Version bumped to 0.2.3 in Gemfile.lock. No push attempted yet.

**Gap discovery:** During an `/ask` consultation, the flow was: "Fix committed → Version bumped → Next steps?" I flagged: "Is this pushed? Tagged? Released?" Answer: no, no, no. Downstream project cannot access this fix via Homebrew yet. Full release chain required.

**Release workflow:** Executed the standard release sequence: push commits → create tag → create GitHub release → verify tap workflow trigger → confirm tap formula updated. No blockers, no rework needed. The automation (`.github/workflows/update-tap.yml`) works as designed.

## Root Cause Analysis

**Why the gap existed:** The mental model of "commit = done" is deeply ingrained, especially after working through a focused debugging session. Once the code is committed, tested, and merged, the psychological sense of completion is real. But for a Homebrew-distributed tool, completion happens three steps later: tag, GitHub release, tap formula update. The first two are manual (though easily scripted); the third is automated. Skipping any of the first two breaks the chain.

**Why it was only caught because of a downstream blocker:** There is no internal mechanism in this workflow to validate "the fix is actually reachable." If nobody tries to install after a commit, the gap is invisible. The downstream project's blocker forced the question: "Can I get this fix yet?" That's the earliest point where the gap becomes visible.

**Why this is a structural risk:** Homebrew + GitHub Actions makes the release chain fairly automatic once you start it, but the chain still requires someone to *initiate* it. The tool has no "auto-publish on commit" mode; it requires a human to say "publish this version." That's a policy decision (good, actually: it prevents accidental releases), but it means every fix carries a latent risk of being never-released if the author forgets or the release checklist is incomplete.

## Lessons Learned

1. **A local fix is not a shipped fix.** Committed code is local until it's tagged. Tagged commits are inert until they're released. Released artifacts are unreachable unless the distribution chain (in this case, Homebrew tap formula update) completes. Each step is necessary; skipping any one leaves the fix invisible to consumers.

2. **Downstream consumers are the truth detector for release gaps.** If a consumer reports a bug and you say "that's fixed in v0.2.3" but v0.2.3 doesn't exist yet, that's immediately obvious to them. Waiting for a consumer's "is this available yet?" question is a reactive way to discover the gap. Proactive: define a release checklist and run it immediately after committing a fix.

3. **Release workflow automation is good, but it's not automatic without initiation.** The `.github/workflows/update-tap.yml` workflow is solid—it runs on `release: published` and updates the formula correctly. But it only runs *after* the GitHub release is created. The human still has to push the tag and create the release. This is fine (prevents accidents), but it's a two-step manual gate before the automation kicks in.

4. **Tool distribution via Homebrew adds latency but not complexity.** Once the GitHub release exists, the tap update is automatic and reliable. The issue isn't Homebrew; it's the gap between "I committed this" and "I released this." Any distributed tool has this problem. The fix is a checklist, not a different distribution channel.

## Next Steps

1. **Release is live.** v0.2.3 tagged, released, and available via `brew install spm-cache@0.2.3` or `brew upgrade spm-cache` for users on earlier versions.

2. **Downstream blocker unblocked.** epost-app project can now run `brew upgrade spm-cache` and proceed with the SPM category caching migration without the eh_xcframework proxy error.

3. **Release checklist task.** Flag for the next session: define a `RELEASE_CHECKLIST.md` or add to project docs a one-paragraph reminder that "commit + version bump ≠ release" and outline the steps (push, tag, create release, verify workflow). This prevents the oversight from happening again when a fix is critical.

4. **No action on tap formula.** The Homebrew tap formula is up-to-date and correct. No manual edits needed; the automation handled it.

---

**Related artifacts**:
- Commits pushed: 527051b..5ec953e (4 commits)
- Tag: v0.2.3
- GitHub release: https://github.com/phuongddx/spm-cache/releases/tag/v0.2.3
- Tap workflow: `.github/workflows/update-tap.yml` (completed successfully)
- Tap formula: `phuongddx/homebrew-spm-cache/Formula/spm-cache.rb` (updated to v0.2.3)

Status: DONE  
Summary: Released v0.2.3 (eh_xcframework bug fix + 3 earlier commits) through full release chain (push, tag, GitHub release, Homebrew tap update). Gap between "committed" and "shipped" was visible only because a downstream consumer asked "is this available yet?"
