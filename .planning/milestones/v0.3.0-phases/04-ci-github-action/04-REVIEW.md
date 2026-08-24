---
phase: 04-ci-github-action
reviewed: 2026-08-24T12:05:00+07:00
depth: deep
files_reviewed: 4
files_reviewed_list:
  - spec/action_spec.rb
  - action/action.yml
  - action/README.md
  - .planning/phases/04-ci-github-action/SUMMARY.md
findings:
  critical: 0
  warning: 4
  info: 2
  total: 6
status: resolved
commits_reviewed:
  - 2529d26 (RED spec)
  - d9a4c4e (GREEN one-line fix)
  - 68021c5 (docs closure)
  - 9692984 (summary/metadata)
resolution:
  resolved: 2026-08-24
  resolved_by: Phase4Fixer (gsd-code-fixer)
  fix_report: .planning/phases/04-ci-github-action/04-REVIEW-FIX.md
  fix_commits:
    - 6461d5c (WR-01/WR-04 fix: own_option_flags raises by name on missing `def self.options`/`.concat(super)` markers; flag terminator accepts space so tuple-style options parse — silent EOF-slice and false-RED both eliminated)
    - 22f49cb (WR-02 fix: both emitted-flag scans catch space-separated `--flag value` / quote-terminated emission, not just `--flag=value`)
    - 18a8d09 (WR-03 fix: injection check matches whitespace-free `${{inputs.x}}` via /\$\{\{\s*inputs\./)
    - e39def6 (IN-01 fix: README parity compares normalized description cores; missing `## ` terminator raises by name instead of nil.scan NoMethodError)
    - 8abe6ae (IN-02 fix: setup step selected by `uses.start_with?('ruby/setup-ruby')` with named raise; invocation pattern derived from gemspec executables via Regexp.escape)
  spec_result: spec/action_spec.rb 12 examples 0 failures; full suite 249 examples 0 failures (make proxy.build + bundle exec rspec)
---

# Phase 4: Code Review Report

**Reviewed:** 2026-08-24
**Depth:** deep (per-file + cross-file: spec regexes traced against init.rb/pull.rb/push.rb/command.rb sources; all four commits diffed)
**Files Reviewed:** 4 (+ cross-referenced lib sources, ROADMAP.md, INTEGRATIONS.md, spm_cache.gemspec, storage/base.rb)
**Status:** resolved — 0 critical, 0 major; 6 minor-grade findings (4 warning / 2 info), **all 6 fixed 2026-08-24** (spec hardening only; see frontmatter `resolution` and 04-REVIEW-FIX.md). Nothing blocked ship or the verify gate.

## Summary

Reviewed the four Phase-04 commits. The F1 repair is correct and surgically scoped; the spec is green, hermetic, and its load-bearing slice construction works as designed; all doc edits are factually accurate against the sources they cite. The findings below are all robustness/hardening gaps in the spec's regression net — none is a production defect, and none invalidates the phase's RED→GREEN provenance or acceptance criteria.

### Verified correct (adversarially checked, not assumed)

1. **GREEN commit is exactly one line.** `git show d9a4c4e` touches only `action/action.yml:55` (`ARGS="--config=${CONFIG}"` → `ARGS="--default-config=${CONFIG}"`). Env maps, backend if/elif, `|| true`, remote step byte-identical.
2. **F1 fix chain holds end-to-end.** init.rb:19 defines `--default-config=CONFIG`; init.rb:31 reads `argv.option('default-config')`; `resolve_default_config` (init.rb:86-95) returns it before falling back to `'debug'`. Remote steps correctly keep `--config` — pull.rb:16 and push.rb:16 each define it in their OWN options.
3. **Slice construction is load-bearing as claimed.** The inherited base `--config` (command.rb:19) is appended via `.concat(super)` — outside the `def self.options`…`.concat(super)` slice, so it can never satisfy the emitted-minus-defined check. Verified by reading both files, not by trusting the comment.
4. **Spec run reproduced:** `bundle exec rspec spec/action_spec.rb` → **12 examples, 0 failures** (9 action-owned + 3 spec_helper smoke). Hermetic: only local `File.read`/`YAML.safe_load_file`/`Dir.glob` — no network, clock, or randomness. Deterministic across runs.
5. **No false-positive vector on unrelated CLI changes** (assignment's stated concern): edits to base `command.rb` options fall outside every slice; adding an own option to init.rb only grows the defined set (subset check stays green); removing one the action emits correctly goes red. The `%w[pull push` hardcode (spec:31) is pinned to the `Dir.glob == [pull.rb, push.rb]` assertion (spec:96-97), so a new remote subcommand fails loudly rather than being silently unprobed.
6. **YAML/schema assertions are semantically correct.** `expect(hash).to include('shell')` is a Hash *key* check in RSpec — the right form for the composite shell-required rule; `using == composite`, 4 steps, quoted `"3.2"` String all re-verified against the parsed file.
7. **No secrets in action.yml** — the only credential-adjacent input is `creds`, a JSON file *path*, and it flows exclusively through env indirection (spec example 4 proves all six inputs do).
8. **Doc accuracy spot-checks all pass.** README Caveats warning strings byte-match `storage/base.rb:22-24` ("No remote cache configured. Skipping pull/push." / "Configure remote cache in spm-cache.yml to enable."); the `|| true` F3 disclosure is present; ROADMAP gained exactly 3 dated amendments (count 5→8, Phase-4 criteria only — commit 9692984's ROADMAP hunk is checkbox-only); INTEGRATIONS.md:92 is a single-line reword with line 93 untouched; release checklist order is correct (gem push → verify install → publish action repo → tag v1 **after** steps 2-3 → action-repo smoke CI); the quoted homepage placeholder matches gemspec:12 verbatim; gemspec is untouched (working tree clean for all reviewed files).
9. **README parity logic is sound row-for-row** (name set, required↔yes/no, default↔`value`/em-dash including the nil-default `backend-url` and `''`-default `creds` cases).

## Structural Findings (fallow)

None provided for this phase.

## Narrative Findings (AI reviewer)

All findings below are minor-grade: robustness gaps in a regression test, not shipped defects. Severity mapping for the orchestrator: **critical=0, major=0, minor=6.**

## Warnings (minor-grade — robustness of the spec's net)

### WR-01: `own_option_flags` crashes opaquely if a probed command file lacks `def self.options`

**File:** `spec/action_spec.rb:24-26`
**Issue:** `start_idx = src.index('def self.options')` returns `nil` for a command file with no own-options method; `src[nil...idx]` then raises `TypeError: no implicit conversion from nil to integer` (probe reproduced in isolation) instead of a readable assertion failure. Unreachable today (init/pull/push all define own options, and the Dir.glob pin would fail first for new subcommand files), but the failure mode when reached is a stack-trace, not a diagnosis.
**Fix:** Guard the slice and fail with intent:
```ruby
def own_option_flags(path)
  src = File.read(path)
  start_idx = src.index('def self.options') or
    raise "#{path} defines no own options block — update the cross-reference source list"
  concat_idx = src.index('.concat(super)', start_idx) or
    raise "#{path} composes options without .concat(super) — slice boundary broken"
  src[start_idx...concat_idx].scan(/\[(?:['"]{1,2})?--([a-z0-9-]+)(?:=|['"])/).flatten.uniq
end
```

### WR-02: the F1 net is blind to space-separated flag emission — a style refactor silently disables the cross-reference

**File:** `spec/action_spec.rb:82`
**Issue:** `emitted = init_step['run'].scan(/--([a-z0-9-]+)=/)` only sees `--flag=value` tokens. If action.yml is ever refactored to `ARGS="--default-config ${CONFIG}"` (space-separated, equally valid shell and CLAide), the scan captures nothing, `emitted - defined` is vacuously empty, and the example stays green while checking nothing — the exact F1 class of bug could re-enter unnoticed. The assignment's "brittle against CLI flag refactors?" concern, confirmed: the *defined*-side is resilient, the *emitted*-side is not.
**Fix:** Also scan for `--flag` tokens followed by space/quote-end, then subtract a small allowlist of non-CLI dashes if one ever appears (e.g. `set -euo pipefail` has none today):
```ruby
emitted = init_step['run'].scan(/--([a-z0-9-]+)(?:=|\s|["'])/).flatten.uniq
```

### WR-03: injection-safety check misses the whitespace-free macro form `${{inputs.x}}`

**File:** `spec/action_spec.rb:70`
**Issue:** `not_to include('${{ inputs.')` matches only the spaced form. GitHub's expression parser treats whitespace inside `${{ }}` as optional, so a future edit writing `${{inputs.config}}` in a run body would pass the "injection safety" example while reintroducing the exact expansion surface the example exists to forbid. (No such expansion exists in the current file — this is a net gap, not a live vulnerability.)
**Fix:** Match the macro opener without requiring the inner space:
```ruby
expect(s['run']).not_to match(/\$\{\{\s*inputs\./), msg
```

### WR-04: the slice boundary is coupled to the `.concat(super)` spelling — alternate composition styles silently degrade or false-red

**File:** `spec/action_spec.rb:25-26`
**Issue:** Two refactor styles of the gem's options methods break the extraction in opposite directions (both probes reproduced): (a) `super + [[...]]` instead of `.concat(super)` → `concat_idx` is nil → the slice extends to EOF, so the "inherited base flags excluded by construction" guarantee silently disappears — anything `--flag`-shaped after `def self.options` anywhere in the file would enter the defined set and could mask an F1 recurrence; (b) `%w[--flag VALUE]` tuple style → the regex's `(?:=|['"])` terminator never matches after the flag name (next char is a space) → defined set comes back empty → false RED blaming the spec, not the action. The executor's quote-style broadening (documented deviation 1) fixed the *current* single-quote/double-quote variance but not these structural forms.
**Fix:** Fold into WR-01's guards (raise when the boundary is missing), and loosen the terminator to also accept a following space:
```ruby
src[start_idx...concat_idx].scan(/\[(?:['"]{1,2})?\s*--([a-z0-9-]+)(?:=|['"\s])/)
```

## Info

### IN-01: README parity check ignores the Description column and requires Inputs not to be the last section

**File:** `spec/action_spec.rb:35-36`
**Issue:** The row regex captures the description cell but discards it (`_desc`), so description drift between README and action.yml inputs is undetected; and `[/## Inputs\n(.*?)\n## /m, 1]` returns nil (→ `NoMethodError` on `nil.scan`) if `## Inputs` ever becomes the final section. Both are acceptable scope choices (the plan required name/required/default parity only) — noted for the next editor of either file.
**Fix (optional):** compare a normalized description or at least assert `section` non-nil with a message naming the missing terminator heading.

### IN-02: two first-match assumptions hardcode step identity

**File:** `spec/action_spec.rb:101, 119`
**Issue:** Example 7 finds the ruby-version via `steps.find { |s| s.key?('uses') }` — the first uses-step — and example 8's invocation scan hardcodes the literal `spm-cache` inside the pattern (`/(?:^|\s)(spm-cache)(?:\s|$)/`), making the `eq(executables)` comparison partly self-fulfilling. Both are correct against the current 4-step layout and the gemspec's `["spm-cache"]`; they'd mislead only after a step reorder or executable rename (which would fail loudly elsewhere).
**Fix (optional):** select the uses-step by `uses.start_with?('ruby/setup-ruby')`; derive the invocation pattern from `Regexp.escape(executables.first)`.

---

_Reviewed: 2026-08-24_
_Reviewer: Claude (gsd-code-reviewer, Phase4Review)_
_Depth: deep_
_Result: no critical/major findings; 6 minor-grade (4 WR + 2 IN). Recommend proceed to verify — WR-01..WR-04 are worthwhile hardening for a later spec-maintenance pass, not gates._
