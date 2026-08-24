# Phase 4: CI GitHub Action - Context

**Gathered:** 2026-08-24
**Status:** Ready for planning

<domain>
## Phase Boundary

Ship `phuongddx/spm-cache-action@v1` as a thin CI wrapper so teams can restore/save cache with a 5-line workflow. IMPORTANT: ALREADY IMPLEMENTED in this repo (commit 9e35030: `action/action.yml` 86-line composite + `action/README.md`). Per the locked distribution decision, the Action source is developed under `action/` here and must be PUBLISHED to the separate repo `phuongddx/spm-cache-action` for GitHub `uses:` resolution. This phase's plan is VERIFICATION-SCOPED: prove action.yml structure/inputs/shell-out locally, record the external-dependency deviation for criterion 3, close doc drift — do NOT re-implement.

</domain>

<decisions>
## Implementation Decisions

### Input surface (accepted as shipped, 2026-08-24)
- Inputs: `command` (pull/push/sync), `backend` (git/s3), `backend-url`, `config`, `branch`, `creds` — superset of the ROADMAP criterion-1 list (mirrors `init`'s remote flags); accepted.

### Execution shape (accepted as shipped)
- 4-step composite: setup-ruby → `gem install spm-cache` → `spm-cache init` → `spm-cache remote <command>` — thin shell-out, zero logic duplication
- `spm-cache init` runs inside the Action to seed config before the remote step (works from flags, no user-authored spm-cache.yml required)
- No gem version pinning input (tracks latest RubyGems release) — accepted; pinning rejected 2026-08-24

### Criterion 3 — external dependency (accepted as deviation)
- ROADMAP criterion 3 ("smoke-tested in its own repo's CI") is UNREACHABLE from this repo: it requires publishing to `phuongddx/spm-cache-action` (repo-owner action). Record as a documented external-dependency deviation + release-checklist item. The plan verifies everything locally verifiable: YAML validity, composite schema, input wiring, shell-out commands matching the gem's actual CLI.

### Claude's Discretion
Verification task granularity; local proof organization (YAML parse, input-to-step wiring assertions, README accuracy); doc phrasing.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `action/action.yml` — composite action; 6 inputs; setup-ruby; gem install; spm-cache init; spm-cache remote
- `action/README.md` — usage docs + design rationale
- `.github/workflows/ci.yml` + `update-tap.yml` — this repo's own workflow conventions (action pinning style, permissions hygiene) as comparison patterns

### Established Patterns
- Thin shell-out wrapper per the locked decision ("GitHub Action: separate thin repo, shell-out only")
- YAML conventions from existing workflows

### Integration Points
- Consumes the gem's CLI surface: `spm-cache init` flags (phase 3), `spm-cache remote pull/push/sync`
- Publication target: separate repo `phuongddx/spm-cache-action` (per `uses:` resolution rules)

</code_context>

<specifics>
## Specific Ideas

- The plan must verify criterion 1 (inputs), criterion 2 (shell-out to installed gem, pull/push/sync), and as much of criterion 3 as is locally provable; the unprovable remainder (own-repo CI smoke test) is recorded as the external-dependency deviation with the publish checklist.

</specifics>

<deferred>

## Deferred Ideas
- Gem version-pinning input — rejected 2026-08-24
- Requiring user-authored spm-cache.yml instead of init-seeding — rejected 2026-08-24

</deferred>
