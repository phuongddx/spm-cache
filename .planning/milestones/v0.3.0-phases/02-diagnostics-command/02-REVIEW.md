---
phase: 02-diagnostics-command
reviewed: 2026-08-24T00:00:00Z
depth: standard
files_reviewed: 8
files_reviewed_list:
  - tools/spm-cache-proxy/Sources/CLI.swift
  - spec/doctor_companion_version_spec.rb
  - spec/doctor_spec.rb
  - lib/spm_cache/command/doctor.rb
  - .planning/ROADMAP.md
  - .planning/phases/02-diagnostics-command/SUMMARY.md
  - .planning/phases/02-diagnostics-command/02-01-SUMMARY.md
  - docs/project-roadmap.md
commits_reviewed:
  - 792576c
  - 789c4e5
  - c627a98
  - b70eeb9
  - 2ef0d29
findings:
  critical: 0
  major: 0
  minor: 3
  total: 3
status: resolved
resolution:
  resolved: 2026-08-24
  resolved_by: Phase2Fixer (gsd-code-fixer)
  fix_commits:
    - cba6b28 (MI-01 docs: summary counts 18→16 new doctor examples, previously 216→218)
    - 5ee156e (MI-02 test: --version output must equal repo VERSION file)
    - 9535821 (MI-03 test: Dir.glob stub constrained to cache_dir prefix)
---

# Phase 02: Code Review Report

**Reviewed:** 2026-08-24
**Depth:** standard (per-file + cross-file trace into `diagnostics.rb`, `sh.rb`, `config.rb`)
**Files Reviewed:** 8 (5 commits)
**Status:** resolved (0 critical, 0 major, 3 minor — all three fixed 2026-08-24, see frontmatter `resolution`)

## Summary

Adversarial review of the 5-commit verification-scoped closure of plan 02-01. The functional changes are sound and minimal; no blockers. The Swift fix is idiomatic; the new specs are hermetic, leak-safe, and convention-consistent; production Ruby is untouched beyond the two mandated wording strings; doc edits match shipped reality with one exception: the executor-authored summary artifact (02-01-SUMMARY.md) misstates its own example counts in three places while contradicting its own Self-Check, which is correct.

**Evidence run this review:** `bundle exec rspec spec/doctor_spec.rb spec/doctor_companion_version_spec.rb` → **25 examples, 0 failures** (my own run, not taken on faith). `wc -l`: diagnostics.rb 156, doctor.rb 82, doctor_spec.rb 257 — all match the phase SUMMARY claims exactly.

## Verified Sound (grounded)

- **CLI.swift (789c4e5)** — `static let proxyVersion = "0.3.0"` declared once (line 25), passed once into `CommandConfiguration(version:)` (line 30); grep over the whole Swift package shows no other declaration/use. Idiomatic swift-argument-parser root-version wiring (`version:` parameter; no subcommand added, per plan OQR-1). Value matches repo `VERSION` (0.3.0). Subcommands unchanged. Comment accurately documents the lockstep-bump invariant and the never-compare deviation (b).
- **spec/doctor_companion_version_spec.rb (792576c)** — binary-gate convention is a faithful clone of gen_proxy_ignore_spec.rb: same `SPMCache::ROOT.join('tools','spm-cache-proxy','.build','release','spm-cache-proxy')` path, same `File.executable?` guard, identical skip message, `frozen_string_literal` header, `require 'spec_helper'` first. `Open3.capture3(binary, '--version')` array form — no shell, no quoting/injection surface. Exit-status and `/\A\d+\.\d+\.\d+\z/` assertions correct.
- **spec/doctor_spec.rb (c627a98)** — diff is 192 insertions / 4 deletions; the only deletions are the stale 4-line header (the prohibited phrase `injected fixtures rather than a real Xcode install` is gone). All 4 pre-existing examples untouched. Leak safety confirmed: (a) `allow(SPMCache::Core::Sh/File/Dir)` module stubs are RSpec-scoped and auto-revert per example; (b) both registry-mutating examples (`captures a check that raises`, `emits valid JSON even when a check raises mid-run`) save `registry.dup` and restore `@registry` in `ensure` — restore survives mid-example failure; (c) Config is never singleton-polluted: hermetic remote examples use `instance_double(Config, ...)`, and the Command-level examples' real `Config.instance.load` is a read-only no-op (no repo-root `spm-cache.yml` exists — verified; `@raw` stays the frozen-default dup). (d) Both stdout swaps restore `$stdout` in `ensure`. Exact-string stub arguments (`'xcodebuild -version'`, `"#{companion_bin} --version 2>/dev/null"`, …) match the production call sites verbatim in diagnostics.rb. The absent-toolchain example is host-independent by construction: with every probe raising, xcode/swift/toolchain each deterministically produce :fail, companion is :ok-or-:warn (never :fail), and the assertions (7 markers, `Summary: \d+ ok, \d+ warnings?, 3 failures`) tolerate both. Exit-stubbing follows the plan-mandated `expect_any_instance_of(Doctor).to receive(:exit).with(1)` idiom.
- **lib/spm_cache/command/doctor.rb (b70eeb9)** — `git show` diff is exactly the two description strings (`green/yellow/red report` → `status report with per-check markers and fix hints`; `color-coded report` → `text report`). No logic, option parsing, formatter, or exit-semantics lines touched. Exit-1-iff-any-:fail and read-only/no-`--fix` prohibitions hold (unchanged code).
- **Docs (b70eeb9)** — ROADMAP SC1/SC3/SC4 carry dated inline amendments (plain markers + count-only health + config-presence remote; register-API "config"; Sh-seam injection) cross-referencing 02-01-SUMMARY deviations (c)/(d)/(e)/(f) — annotations match shipped reality. Phase SUMMARY.md: counts 156/82 verified by `wc -l`; provenance string `4 doctor examples + 3 spec_helper examples = 7` present; 7-record (a)–(g) deviations section present. docs/project-roadmap.md is a one-line hunk flipping the doctor item to `- [x] … shipped in v0.3.0`.
- **Security** — no secrets, no new interpolation of user/config input into shell commands (threat-register T-02-01 invariant upheld); `YAML.safe_load` path untouched; no eval/`dangerously*`/debug artifacts introduced.

## Critical Issues

None.

## Major Issues

None.

## Minor Issues

### MI-01: 02-01-SUMMARY.md misstates example counts — three claims contradict the file's own (correct) Self-Check

**File:** `.planning/phases/02-diagnostics-command/02-01-SUMMARY.md:65,70,83` (vs `:119`)
**Issue:** The summary claims Task 2 added **18** new doctor examples (line 65 "Task 2 — 18 new examples", line 83 "+18 examples", line 70 "2 binary-gated companion examples + 18 new doctor examples; previously 216"), while line 119 correctly says "4 existing doctor + 3 spec_helper + **16** new = 23". Verified ground truth: doctor_spec.rb defines 20 examples (4 pre-existing + **16 new**: 14 hermetic + 1 absent-toolchain + 1 json-raising); the two files + spec_helper's 3 side-effect examples total 25 (my run). The arithmetic on line 70 is also wrong: 236 total − 2 companion − 16 doctor = **218** previous, not 216. Downstream verifier reading the evidence section gets numbers that cannot all be true.
**Fix:** In 02-01-SUMMARY.md change "18 new examples" → "16 new examples" (line 65), "+18 examples" → "+16 examples" (line 83), and "18 new doctor examples; previously 216" → "16 new doctor examples; previously 218" (line 70).

**Resolved:** `cba6b28` — counts corrected (16 new doctor examples; previously 218); post-fix full suite re-verified `236 examples, 0 failures`.

### MI-02: Companion spec never guards the proxyVersion↔VERSION lockstep invariant it documents

**File:** `spec/doctor_companion_version_spec.rb:29-33`
**Issue:** The spec's own header comment (and CLI.swift:22-24) state `proxyVersion` must be bumped in lockstep with the repo `VERSION` file, but no example enforces it. The `--help` example only asserts the literal string `--version` appears — it passes even if `proxyVersion` drifts to any value. Plan Task 1's behavior bullet called for a single-source check ("output … equals the version constant wired into CommandConfiguration"); the delivered second test is weaker than that intent (it follows the plan's action bullet, which specified the `--help` variant — but the invariant is left unguarded by automation). This is a spec-side assertion only and would not violate accepted deviation (b), which constrains the *doctor command* (never compare/gate), not the test suite.
**Fix:** Strengthen the first example (or add a third): `expect(stdout.strip).to eq(File.read(SPMCache::ROOT.join('VERSION')).strip)` — fails the moment the constant and the file drift apart.

**Resolved:** `5ee156e` — first example strengthened with `eq(File.read(SPMCache::ROOT.join('VERSION')).strip)` (no third example added, preserving the recorded 2-example companion count); scoped run green.

### MI-03: Unconditional `Dir.glob` stub breaks the file's own stubbing convention

**File:** `spec/doctor_spec.rb:144`
**Issue:** `allow(Dir).to receive(:glob).and_return([])` stubs **every** `Dir.glob` call with no `and_call_original` baseline and no argument constraint — the only module stub in the new block that deviates from the stated convention (plan Task 2 / sibling stubs at lines 140-143 all use `and_call_original` + specific-argument overrides). No cross-spec leak (RSpec reverts after the example) and it happens to be harmless today (only `cache_dir_health` calls `Dir.glob` in this path), but any incidental `Dir.glob` caller during the example silently receives `[]`.
**Fix:**
```ruby
allow(Dir).to receive(:glob).and_call_original
allow(Dir).to receive(:glob).with(a_string_starting_with(cache_dir.to_s)).and_return([])
```

**Resolved:** `9535821` — stub now `and_call_original` + `a_string_starting_with(cache_dir.to_s)` override, matching the sibling stub convention; scoped run green (25 examples, 0 failures).

---

_Reviewed: 2026-08-24_
_Reviewer: Claude (gsd-code-reviewer, Phase2Review)_
_Depth: standard_
