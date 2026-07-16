# Fix plan: GitHub issues #1-#4 (spm-cache)

Status: DONE (2026-07-14) — all 4 phases implemented, tested, code-reviewed. Not yet committed.

All 4 issues verified as real at HEAD (2026-07-14, commit 1952b3c). None already fixed.
Full evidence: `plans/reports/debugger-0714-1309-github-issues-triage-report.md`.

## Phases (in dependency order)

| # | Phase file | Issue | Why this order |
|---|---|---|---|
| 1 | [phase-01-config-load.md](phase-01-config-load.md) | #1 | Foundational: `ignore_build_errors`, `ignore`, `default_sdk` must actually apply before we can trust behavior of phases 3-4 in manual verification. No code dependency on others. |
| 2 | [phase-02-lockfile-revision.md](phase-02-lockfile-revision.md) | #2 | Root cause of the resolve failure that triggers #3 in the field. Fix the cause before hardening the symptom. |
| 3 | [phase-03-umbrella-resolve-fallback.md](phase-03-umbrella-resolve-fallback.md) | #3 | Safety net for *any* remaining resolve failure (not just revision-pins). Depends on #2 conceptually (removes the most common trigger) but must still exist independently. |
| 4 | [phase-04-scheme-resolution.md](phase-04-scheme-resolution.md) | #4 | Unit-testable independently (stubs, no real checkouts needed — see `spec/build_pipeline_spec.rb`), but full end-to-end validation on a real umbrella needs checkouts present, i.e. needs #2/#3 fixed first. |

## Cross-cutting notes

- Issues #2/#3/#4 all stem from the same recent commit `1952b3c` ("wire selective caching ... real build pipeline") which introduced `lib/spm_cache/spm/build_pipeline.rb` and the real body of `lib/spm_cache/installer/build.rb`. Issue #1 predates that commit (present since `a9739dd` initial v0.1.0).
- #2 lives in the Swift proxy tool (`tools/spm-cache-proxy`), not the Ruby gem. That package currently has **zero test targets** (`Package.swift` has no `.testTarget`). **Decided**: add a `.testTarget` using Swift Testing (`@Test`/`#expect`), not XCTest, not CLI-smoke-test-only — `Sources/CLI.swift` uses `@main` so the executable target is directly testable without restructuring; pure branch logic on a `Codable` struct is exactly where Swift Testing's speed (`swift test`, no simulator) pays off, and it would have caught the issue's own `.revision("<hash>")` label-syntax bug at compile time. See phase-02 for full rationale.
- Ruby's own `Core::Lockfile::Pkg` (lib/spm_cache/core/lockfile.rb) already reads/writes `revision` correctly — the bug is isolated to the Swift-side `PackageRef` that consumes the same JSON file. Confirms issue report's claim precisely.
- Issue #4's suggested fix (parse `xcodebuild -list -json`, string-heuristics) is workable but the repo already has a more authoritative source: `SPMCache::SPM::Desc::Description` (`lib/spm_cache/spm/desc/desc.rb`, backed by `swift package describe --type json`, already used in `lib/spm_cache/spm/pkg/base.rb`). This gives real product types (library vs executable) and exact SPM-generated scheme names, avoiding the guesswork the issue's own suggested heuristic still has (e.g. "contains package name" would false-negative on `FSPagerView` vs `fspagerview`, false-positive on `Alamofire iOS` vs `AlamofireTests`). Phase 4 fixes via this route, falling back to the issue's `xcodebuild -list` heuristic only if `swift package describe` yields nothing.
- Phase 3's DerivedData fallback was verified against the real `luz_epost_ios` project on the dev machine (2026-07-14): checkout basenames match the expected slug convention, confirming the `#{project_name}-*` glob works — but this also surfaced a bug in the issue's own suggested code: TWO DerivedData dirs matched the same project (different mtimes), and `Dir.glob(...).first` does not guarantee the newest. Fixed by sorting on `File.mtime` (`max_by`). See phase-03.

## Acceptance criteria (overall)

- `bundle exec rspec` green after each phase (project convention, see `spec/*_spec.rb`).
- No public CLI contract changes (flags, config keys) unless explicitly noted per phase.
- Each phase individually revertable (small, focused diffs per file).

## Unresolved questions

Both prior open questions resolved 2026-07-14 (see phase-02, phase-03 for detail):

- Phase 2: **decided** — Swift Testing test target added to `tools/spm-cache-proxy`, not a CLI-only smoke test. Optional fixture-based smoke test kept as a secondary, non-blocking check.
- Phase 3: **decided** — DerivedData glob pattern confirmed correct against real `luz_epost_ios` project; fallback additionally hardened to pick the most-recently-modified match (`max_by mtime`) after finding two stale candidate dirs on the real machine. CI/environments without DerivedData still no-op as originally designed (`return unless xcode_checkouts`).

## Completion summary (2026-07-14)

All 4 phases implemented in parallel (disjoint files, no conflicts), merged, and verified:

- **Phase 1** (issue #1): `ensure_config_file` now calls `@config.load(config_path)`. `spec/installer_spec.rb` added.
- **Phase 2** (issue #2): `PackageRef.revision` field added, `versionRequirement` emits correctly-labeled `revision: "<hash>"`. New Swift Testing target (`tools/spm-cache-proxy/Tests/`), 4 cases green.
- **Phase 3** (issue #3): `fallback_xcode_checkouts` added with `max_by(mtime)` DerivedData selection + escalated warning on total miss. 3 new specs in `spec/installer_build_spec.rb`, HOME stubbed (never touches real DerivedData).
- **Phase 4** (issue #4): `resolve_scheme` wired up-front using `swift package describe` product-type data.
  - **Critical bug found in first code-review pass and fixed**: `Desc::Product#type` returned `raw["type"]` verbatim, but real `swift package describe --type json` emits `type` as a Hash (e.g. `{"library"=>["automatic"]}`), never a bare string — so `p.type == "library"` was always false and the fix was a silent no-op (fell through to the old `schemes.first` heuristic). Original tests passed only because they stubbed an unrealistic bare-string shape (phantom pass).
  - Fixed `Product#type` to normalize both the Hash shape and bare-string (`t.is_a?(Hash) ? t.keys.first : t`). Added `spec/desc_product_spec.rb` (3 cases) proving the real shape. Updated `spec/build_pipeline_spec.rb` stubs to the realistic Hash shape. Also tightened the substring-fallback tie-break (`.find` → `.select.min_by(length delta)`) per a Medium-priority review note.
  - Re-verified by a second independent code-review pass against real `swift package describe` output on 3 local SwiftPM packages — confirmed correct, no regressions.

**Final test status**: `bundle exec rspec` → 58 examples, 0 failures. `cd tools/spm-cache-proxy && swift test` → 4/4 passing.

**Not yet committed** — working tree has uncommitted changes pending user decision on commit.

**Note**: repo has a pre-existing, unrelated `Gemfile.lock` drift (`spm-cache 0.1.0` vs `VERSION` file `0.1.1`) that gets touched by any `bundle exec` invocation — reverted each time during this work, not part of these 4 phases; worth a separate one-line `bundle lock` fix if desired.
