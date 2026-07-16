---
phase: 4
title: "Docs + full regression"
status: pending
priority: P2
dependencies: [1, 2, 3]
effort: "1h"
---

# Phase 4: Docs + full regression

## Overview

Document the new key + 4th status, then run the full Ruby suite to validate the
backward-compat guarantee (empty `cache_only` = identical to today). No source changes
beyond docs.

Depends on Phases 1–3 — documents behavior they implement; regression validates them.

## Requirements

- `docs/deployment-guide.md`: add `cache_only: []` to the config template near
  `ignore: []`, with a precedence comment.
- `docs/system-architecture.md`: expand the 3-state status description to 4 states,
  adding `excluded` + the precedence rule.
- Full `bundle exec rspec` pass; confirm pre-existing `ignore` specs unchanged.

## Architecture

Docs-only + verification. The config template lives in the deployment guide
(deployment-guide.md:76-78); the status enumeration lives in the architecture doc
(system-architecture.md:116-125). Both are the canonical user-facing descriptions of
config keys and graph statuses — must stay in sync with the 4 confirmed decisions.

## Related Code Files

- `docs/deployment-guide.md` — config template block, `ignore: []` at
  deployment-guide.md:76 (with `ignore_local`/`ignore_build_errors` at :77-78); ignore
  usage prose at deployment-guide.md:237-244. MODIFY.
- `docs/system-architecture.md` — `graph.json` example (system-architecture.md:116-123),
  `Statuses:` sentence (system-architecture.md:125). MODIFY.
- `docs/code-standards.md` — DO NOT TOUCH (no `ignore` mentions; no change warranted).
- `docs/codebase-summary.md` — optional one-line addition only if the phase author
  judges it genuinely warranted; default = leave untouched (keep phase lean).

## Implementation Steps

1. **deployment-guide.md**: add to the config template after `ignore: []`
   (deployment-guide.md:76):
   ```yaml
   cache_only: []                # Allowlist: cache ONLY these; overrides ignore when non-empty
   ```
   Optionally add a short prose note near the ignore section (deployment-guide.md:237)
   explaining that when `cache_only` is non-empty, `ignore` is skipped entirely and all
   non-listed packages compile from source (status `excluded`). Keep concise.

2. **system-architecture.md**: update the `Statuses:` sentence
   (system-architecture.md:125) from 3 to 4 states. Add:
   `excluded` (does not match any `cache_only` glob when `cache_only` is non-empty;
   compiled from source, never built by `spm-cache build`). State the precedence rule:
   when `cache_only` is non-empty it wins outright — `ignore` is not applied and only
   `hit`/`missed`/`excluded` statuses appear (no `ignored`). Optionally extend the
   `graph.json` example (system-architecture.md:120-121) with an `"excluded"` entry.

3. **Full regression**: run `bundle exec rspec`. Confirm ALL pre-existing specs pass
   unchanged — especially `spec/gen_proxy_ignore_spec.rb`, the old `--ignore` cases in
   `spec/proxy_executable_spec.rb` (proxy_executable_spec.rb:21-67), and
   `spec/installer_build_spec.rb` ignored-target test (installer_build_spec.rb:63-65).
   This is the empirical backward-compat guarantee: empty `cache_only` ⇒ identical
   behavior to today.

## Out of Scope (explicit — do NOT implement in this plan)

**0%-match warning guard-rail**: if `cache_only` is non-empty but matches 0 of N
packages, everything becomes `"excluded"` (soft-fail — same nature as an `ignore` typo;
falls back to source, does NOT break the build). A warning log when `cache_only`
matches 0 packages is a nice-to-have follow-up, NOT part of this plan's scope. Recorded
here so it is neither silently implemented nor silently forgotten. If desired, file as a
separate follow-up task.

## Success Criteria

- [ ] `docs/deployment-guide.md` config template includes `cache_only: []` with
      precedence comment.
- [ ] `docs/system-architecture.md` documents 4 statuses incl. `excluded` + precedence
      rule.
- [ ] `bundle exec rspec` full suite green.
- [ ] `spec/gen_proxy_ignore_spec.rb`, `spec/proxy_executable_spec.rb` old `--ignore`
      cases, `spec/installer_build_spec.rb` ignored test all pass unchanged.
- [ ] `docs/code-standards.md` untouched.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Docs drift from actual behavior (wrong precedence wording) | Low | Med | Cross-check against confirmed decision #1; precedence = cache_only wins, ignore skipped |
| Regression suite reveals empty-`cache_only` behavior changed | Low | High | If any pre-existing spec fails, STOP — Phase 1/2 introduced a regression; fix there, not by weakening the spec |
| Over-editing docs (scope creep into code-standards/codebase-summary) | Low | Low | Explicit DO-NOT-TOUCH list; codebase-summary optional-only |

**Rollback**: revert the two doc files. Docs-only phase — no runtime rollback needed.
The regression step is validation, not a mutation.
