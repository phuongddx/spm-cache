---
phase: 04-ci-github-action
fixed_at: 2026-08-24T14:35:00+07:00
review_path: .planning/phases/04-ci-github-action/04-REVIEW.md
iteration: 1
findings_in_scope: 6
fixed: 6
skipped: 0
status: all_fixed
---

# Phase 4: Code Review Fix Report

**Fixed at:** 2026-08-24T14:35:00+07:00
**Source review:** .planning/phases/04-ci-github-action/04-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 6 (WR-01..WR-04, IN-01..IN-02 — all minor-grade spec-robustness items)
- Fixed: 6
- Skipped: 0

All fixes land in `spec/action_spec.rb` only; no production or action files touched. The example set is unchanged — still 12 examples (9 action-owned + 3 spec_helper smoke), all green.

**Verification** (ran in the main checkout — `workflow.use_worktrees` is `false` in `.planning/config.json`, so no isolated worktree was created; results are reproducible from this tree):
- `bundle exec rspec spec/action_spec.rb` → **12 examples, 0 failures** after every individual fix.
- `make proxy.build && bundle exec rspec` → build complete, **249 examples, 0 failures**.
- Tier-2 syntax check `ruby -c spec/action_spec.rb` → Syntax OK after every fix.
- IN-01 red-team probe: all six normalized description pairs match, and a mutated description fails the comparison (non-vacuous).

## Fixed Issues

### WR-01: `own_option_flags` crashes opaquely if a probed command file lacks `def self.options`

**Files modified:** `spec/action_spec.rb`
**Commit:** 6461d5c
**Applied fix:** `src.index('def self.options')` and `src.index('.concat(super)', start_idx)` now use `or raise` guards that name the file and the broken invariant ("defines no own options block — update the cross-reference source list" / "composes options without .concat(super) — slice boundary broken"), replacing the opaque `TypeError: no implicit conversion from nil to integer`. Applied together with WR-04 (single helper, review folds them).

### WR-02: the F1 net is blind to space-separated flag emission

**Files modified:** `spec/action_spec.rb`
**Commit:** 22f49cb
**Applied fix:** Both emitted-flag scans (init example and remote example — same net pattern; the review names line 82, the remote twin at line 91 had the identical blind spot) broadened from `/--([a-z0-9-]+)=/` to `/--([a-z0-9-]+)(?:=|\s|["'])/`, so `--flag value` and quote-terminated `--flag"` emission are captured too. No allowlist needed: the step bodies contain no non-CLI `--` tokens (`set -euo pipefail` is single-dash). Verified emitted sets unchanged for current action.yml: init {default-config, remote, remote-url, branch, creds} ⊆ init's own defined flags; remote {config} ⊆ pull/push defined.

### WR-03: injection-safety check misses the whitespace-free macro form `${{inputs.x}}`

**Files modified:** `spec/action_spec.rb`
**Commit:** 18a8d09
**Applied fix:** `expect(s['run']).not_to include('${{ inputs.')` → `expect(s['run']).not_to match(/\$\{\{\s*inputs\./), msg` — matches the macro opener with any (or no) inner whitespace. The env-extraction regex (line ~79) was deliberately left strict: a whitespace-free form there fails loudly (missed reference → `eq` red), not silently.

### WR-04: slice boundary coupled to the `.concat(super)` spelling

**Files modified:** `spec/action_spec.rb`
**Commit:** 6461d5c
**Applied fix:** Folded into WR-01's guards as the review directs: a missing `.concat(super)` (e.g. `super + [[...]]` refactor) now raises instead of silently slicing to EOF, and the defined-flag terminator broadened to `/\[(?:['"]{1,2})?\s*--([a-z0-9-]+)(?:=|['"\s])/` so `%w[--flag VALUE]` / `['--flag', ...]` tuple styles parse instead of false-reding with an empty defined set.

### IN-01: README parity check ignores the Description column and requires Inputs not to be the last section

**Files modified:** `spec/action_spec.rb`
**Commit:** e39def6
**Applied fix:** `readme_rows` now keeps the description cell and raises by name if the `## Inputs` section lacks a terminating `## ` heading (no more `NoMethodError on nil.scan`). The parity example compares `description_core(row)` to `description_core(input)` — normalization strips markdown backticks, parenthetical qualifiers (`(default: main)`, `(debug/release)`), and a leading `Label: ` prefix, tolerating intentional formatting variance between the two files while catching meaning drift (probe-verified: all 6 current rows match; a mutated description fails).

### IN-02: two first-match assumptions hardcode step identity

**Files modified:** `spec/action_spec.rb`
**Commit:** 8abe6ae
**Applied fix:** The ruby-pinning step is now selected by `s['uses']&.start_with?('ruby/setup-ruby')` (with a named raise if absent) instead of "first step with any `uses` key", surviving a step reorder. The invocation assertion derives its pattern from the gemspec via `Regexp.escape(executables.first)` instead of the hardcoded `spm-cache` literal.

---

_Fixed: 2026-08-24T14:35:00+07:00_
_Fixer: Phase4Fixer (gsd-code-fixer)_
_Iteration: 1_
