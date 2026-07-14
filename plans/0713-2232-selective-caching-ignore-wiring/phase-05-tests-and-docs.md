---
phase: 5
title: Tests and docs
status: completed
priority: P2
dependencies:
  - 1
  - 2
  - 3
  - 4
effort: M
---

# Phase 5: Tests and docs

<!-- Updated: Validation Session 1 - renumbered from phase 3; added coverage for source-fallback (phase 3) and build pipeline (phase 4); Swift-side testing confirmed as fixture smoke -->

## Overview

Cover the new wiring with RSpec (Ruby side) and a fixture-driven check of the Swift side, then correct the docs so they describe verified behavior instead of the previously-unwired design.

## Requirements

- Functional: regression coverage for ignore threading, build target filtering, BuildPipeline extraction, and source-fallback manifest generation; glob-semantics parity cases mirrored between Ruby and Swift.
- Non-functional: keep the existing RSpec layout (`spec/*.rb`, 4 files today); no new test framework. Swift tool has no `Tests/` dir — per validation decision, do not introduce a Swift test target; use a fixture run (YAGNI).

## Related Code Files

- Modify: `spec/config_spec.rb` — extend existing `#should_ignore?` block (line 41) with edge patterns: exact name, `Prefix*`, `?` single-char, non-match, empty list
- Create: `spec/proxy_executable_spec.rb` — assert `gen_proxy(ignore: [...])` produces a command containing single-quoted `--ignore 'A,B*'`; and omits the flag when empty (stub `Sh.run`, capture cmd)
- Create: `spec/installer_build_spec.rb` — unit-test target-selection logic with a stubbed `Cachemap` (missed/hit/ignored sets): named filtering, unknown warning, ignored warning, empty intersection; plus checkout-mapping unit cases (slug → dir name)
- Create: `spec/build_pipeline_spec.rb` — unit-test `SPM::BuildPipeline` argument assembly with stubbed `Buildable`/`XCFramework` (no real xcodebuild in CI)
- Create: `spec/fixtures/ignore-lockfile.json` — 2-3 fake packages derived from a real `spm-cache.lock` sample
- Modify: `skills/spm-cache/SKILL.md` (line 96), `skills/spm-cache/references/troubleshooting.md` (lines 76-78), `docs/deployment-guide.md` (line 237), `docs/system-architecture.md` (line 125) — align `ignore`/`off` descriptions with actual behavior; document that ignore patterns match product name OR package identity; document TARGETS filtering and ignored-target warning in `build`
- Modify: `docs/codebase-summary.md` — new `--ignore` option on `gen-proxy`, `BuildPipeline` module, real build flow in `Installer::Build`

## Implementation Steps

1. Extend `spec/config_spec.rb` glob cases; keep them in one shared list so the same cases are copy-mirrored into the Swift fixture check.
2. Write `spec/proxy_executable_spec.rb` — stub `SPMCache::Core::Sh.run` to capture the command string; assert flag presence/absence and quoting.
3. Write `spec/installer_build_spec.rb` — construct `Installer::Build` with `targets:`, inject a fake cachemap, assert selection + warnings (capture `Core::UI` output or stub it).
4. Write `spec/build_pipeline_spec.rb` — assert destination resolution and output path handling with stubbed build layers.
5. Swift-side check: run built binary `gen-proxy --ignore 'Foo*'` against `spec/fixtures/ignore-lockfile.json` in a tmpdir; assert `graph.json` statuses (hit/missed/ignored) AND that the miss/ignored manifests contain `.package(url:` (source fallback, phase 3) rather than an empty stub. Wire as an RSpec example gated on binary presence (`skip unless File.executable?(...)`) so `make test` never hard-fails when the Swift tool isn't built.
6. Update the doc/skill locations; re-read each before editing; verify claims against implemented behavior (per documentation-management rules). Include the version-drift note from phase 3 (source fallback may resolve newer than the binary was built from).
7. Run `make test` and `make proxy.build`; both green.

## Success Criteria

- [ ] All new specs pass; existing 19 examples still green
- [ ] Ruby and Swift glob cases mirrored and passing (parity documented in the spec file header comment)
- [ ] Fixture `gen-proxy` run yields `ignored`/`missed`/`hit` statuses and source-fallback manifests as expected, skipped gracefully when binary absent
- [ ] Docs no longer over-promise: every `ignore`/`off`/`build TARGETS`/cache-miss-fallback claim matches verified behavior
- [ ] `docs.maxLoc` (500) respected for edited docs

## Risk Assessment

- **Fixture drift:** fixture lockfile schema must match `Lockfile.load` expectations (`Lockfile.PackageRef`); derive it from an existing real `spm-cache.lock` sample rather than hand-writing from memory.
- **Doc sprawl:** four locations describe the same feature — keep wording minimal and consistent; SKILL.md is the user-facing source of truth, others reference behavior briefly.
- **No real xcodebuild in specs:** BuildPipeline correctness beyond argument assembly is only covered by the manual end-to-end check in phase 4 Step 6 — acceptable; note it in the spec header.
