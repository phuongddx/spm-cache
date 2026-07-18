---
name: spm-cache-issue
description: File a GitHub issue for the spm-cache project when a user encounters a problem, bug, or unexpected behavior. Use when the user reports an issue with spm-cache, wants to report a bug, asks to file an issue, or says something is broken/not working with spm-cache. Triggers include "report issue", "file a bug", "spm-cache not working", "cache miss problem", "build error with spm-cache", "xcframework issue", "I found a bug in spm-cache".
---

# spm-cache-issue

File a GitHub issue to the `phuongddx/spm-cache` repository when a user encounters a problem with spm-cache.

## Prerequisites

Verify `gh` CLI is installed and authenticated:

```bash
command -v gh && gh auth status
```

If `gh` is not installed: `brew install gh && gh auth login`
If not authenticated: `gh auth login`

## Workflow

### 1. Gather Information from the User

Ask the user (one question at a time if needed):

- **What happened?** — Describe the problem or unexpected behavior.
- **What did you expect?** — The expected outcome.
- **How to reproduce** — Steps, commands, or minimal example.
- **Error output** — Any error messages or logs (ask them to paste if available).

### 2. Collect Diagnostics

Run the diagnostics script to auto-collect environment and cache state:

```bash
bash "$(dirname "$0")/../skills/spm-cache-issue/scripts/collect_diagnostics.sh" .
```

Or if running from the skill directory:

```bash
bash scripts/collect_diagnostics.sh /path/to/user/project
```

This collects: OS, Ruby/Swift/Xcode versions, spm-cache version, config, cache state, and graph.json status (every status — `hit`/`missed`/`ignored`/`excluded`/`plugin` — printed generically, not just misses).

If the `skills/spm-cache` skill already ran its Step 1 categorization
(plugin-only/binary-only/local/regular-library) for this project earlier in
the session, include that category summary in the issue body alongside the
diagnostics output instead of re-deriving it.

### 3. Classify the Issue

Determine the issue type and apply labels:

| Issue Type | Labels | Description |
|------------|--------|-------------|
| Build failure | `bug`, `build` | spm-cache build command fails |
| Cache miss | `bug`, `cache-miss` | Dependencies not hitting cache |
| Missing slices | `bug`, `xcframework` | "no library for this platform" |
| Integration issue | `bug`, `integration` | Proxy package or Xcode project issues |
| Transitive conflict | `bug`, `version-conflict` | `swift package resolve` fails with conflicting version requirements on a package never linked directly by the app (e.g. realm-core via realm-swift) |
| Remote cache | `bug`, `remote` | Git/S3 push/pull failures |
| Feature request | `enhancement` | User wants new functionality |
| Documentation | `documentation` | Docs are wrong or missing |

### 4. Draft the Issue

Assemble the issue body in this format:

```markdown
## Description

{user's description of the problem}

## Expected Behavior

{what the user expected}

## Steps to Reproduce

1. {step 1}
2. {step 2}
3. {step 3}

## Error Output

```
{error logs or output}
```

{diagnostics output from collect_diagnostics.sh}
```

Generate a concise title: `[{area}] {brief description}` (e.g., `[cache-miss] All dependencies show missed after build`).

### 5. Create the Issue

```bash
gh issue create \
  --repo phuongddx/spm-cache \
  --title "{title}" \
  --body "{body}" \
  --label "{labels}"
```

Use `--label` for each label. If labels don't exist on the repo, omit `--label` and mention the suggested labels in the issue body.

**Always confirm with the user before creating the issue.** Show them the draft title and body, then ask for confirmation or edits.

### 6. Share the Result

After creating, share the issue URL with the user:

```
Issue created: {url}
```

## Important Notes

- **Always confirm before creating** — never file an issue without user approval.
- **Sanitize sensitive info** — check the diagnostics output for API keys, private URLs, or credentials before including in the issue body.
- **If gh is unavailable** — draft the issue and provide the user with a direct link: `https://github.com/phuongddx/spm-cache/issues/new`
