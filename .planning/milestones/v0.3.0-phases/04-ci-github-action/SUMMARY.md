# Phase 4 Summary — CI GitHub Action

**Requirement:** ONBD-04
**Status:** Complete

## Deliverables
- `action/action.yml` (86 lines) — composite GitHub Action. Inputs: command (pull/push/sync), backend (git/s3), backend-url, branch, config, creds. Thin shell-out: setup-ruby → gem install → spm-cache init → spm-cache remote.
- `action/README.md` (49 lines) — usage docs + design rationale.

## Note
The action source lives under `action/` for development; for GitHub `uses:` resolution it must be published to its own repo (`phuongddx/spm-cache-action`). Validated: action.yml is well-formed YAML with all required inputs and a 4-step composite — machine-checked since 04-01 by `spec/action_spec.rb` (strict-Psych parse, composite schema, input wiring, CLI flag cross-references, README parity: 12 examples, 0 failures).

## Documented deviations (user-accepted / accepted-as-shipped)

All dated 2026-08-24. Sources: 04-CONTEXT.md (user decisions), RESEARCH.md (F2/F3, Pitfall 6), 04-01-PLAN.md (open-question resolutions).

- **(a) Criterion-3 external deviation — own-repo CI smoke test unreachable from this repo.** Smoke-testing the Action in its own repo's CI requires publishing to `phuongddx/spm-cache-action` (repo-owner action) AND the gem existing on RubyGems — the gem is unpublished as of 2026-08-24 (rubygems.org API 404 probed 2026-08-24, RESEARCH F2), so the action's `gem install spm-cache` step cannot succeed on any runner yet. Everything locally provable is proven by spec/action_spec.rb; the owner-action chain is recorded in the Release checklist below (gem push → verify install → publish action repo → tag v1 → action-repo smoke workflow). User-accepted deviation (04-CONTEXT).
- **(b) Unpinned `gem install spm-cache`.** The action installs the latest published gem with no version-pinning input; a breaking gem release changes action behavior with no action change. Pinning was explicitly rejected 2026-08-24 (04-CONTEXT); the gem's semver discipline is the mitigation. Accepted as shipped.
- **(c) Silent-green misconfiguration mode kept as shipped.** Tolerant init (`|| true`, action.yml) × Storage::Base warn-and-skip means a workflow that restores/saves nothing still exits 0 with warnings. Control-flow changes are outside the verification boundary (04-CONTEXT); the gap is closed by disclosure — README Caveats documents the green-with-warnings behavior, the two warning lines to grep for, and the non-enforcement of `required: true` (RESEARCH F3/F6). Accepted as shipped.

## Release checklist (owner actions, external)

1. Replace the gemspec homepage placeholder — `spm_cache.gemspec:12` currently reads `https://github.com/your-org/spm-cache` — with the real repo URL (recorded here, deliberately NOT edited in 04-01; outside ONBD-04 scope).
2. `gem build spm_cache.gemspec` → `gem push spm-cache-<version>.gem` — publishes the gem to RubyGems, removing the F2 blocker (action step 2 404s until this lands).
3. Verify the install path the action depends on: `gem install spm-cache --no-document` succeeds on a clean machine/runner.
4. Publish the action source (`action/action.yml` + `action/README.md`) to the separate repo `phuongddx/spm-cache-action`.
5. Tag `v1` in the action repo — strictly AFTER steps 2-3 (RESEARCH Pitfall 5: tagging v1 before the gem exists ships an action whose install step always fails).
6. Add the action-repo smoke CI workflow (ROADMAP criterion-3 deferred remainder): a consumer workflow calling `phuongddx/spm-cache-action@v1` with `command: pull` then `push` against a scratch cache backend.

## Commits
- `9e35030` feat: add spm-cache-action GitHub Action (ONBD-04)
- `2529d26` test(04-01): RED add failing spec/action_spec.rb (F1 init-flag mismatch)
- `d9a4c4e` fix(04-01): pass --default-config to spm-cache init (F1) — --config is the inherited base flag, silently ignored
