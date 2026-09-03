# CLAUDE.md

Project-specific guidance for Claude Code in this repo.

## GitHub CLI account

This repo's GitHub remote and releases belong to the `phuongddx` account, not
whatever `gh` account is active by default. Before running any `gh` command
(release, PR, workflow dispatch, etc.), ensure the active account is correct:

```
gh auth switch --hostname github.com --user phuongddx
```
