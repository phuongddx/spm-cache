---
phase: 4
title: 'Real build pipeline in Installer::Build'
status: completed
priority: P1
dependencies:
  - 2
  - 3
effort: L
---

# Phase 4: Real build pipeline in Installer::Build

## Overview

Make `spm-cache build` actually build. Today `Installer::Build#perform_install` (`lib/spm_cache/installer/build.rb:8-17`) only logs "Building X..." per missed target — no compilation happens. The real pipeline (xcodebuild per destination → static lib → framework → xcframework) exists only in `Command::Pkg::Build` (`lib/spm_cache/command/pkg/build.rb`), which assumes it runs *inside* a package checkout. This phase supplies checkouts via umbrella resolution and reuses the existing pipeline per missed target.

## Requirements

- Functional: `spm-cache build [TARGETS]` compiles each selected missed target into a multi-slice xcframework and stores it at `~/.spm-cache/{config}/{module}.xcframework`; a subsequent `spm-cache use` reports those targets as `hit`. Ignored targets are never built. `ignore_build_errors: true` (config exists, `config.rb:112`) continues to the next target on failure instead of aborting.
- Non-functional: DRY — one build pipeline shared by `pkg build` and `Installer::Build`, no copy-paste of the ~80-line xcframework assembly from `pkg/build.rb`.

## Architecture

```
Installer::Build#perform_install
  ├─ super                      (proxy gen + integration, existing)
  ├─ resolve umbrella checkouts ★  swift package resolve  (cwd: umbrella_dir)
  │     → spm-cache/packages/umbrella/.build/checkouts/<repo>/
  ├─ select targets             (Phase 2 filtering: missed ∩ requested, minus ignored)
  └─ for each target:
       locate checkout dir      ★  match Lockfile PackageRef slug → checkouts/<slug>
       BuildPipeline.run        ★  extracted from Command::Pkg::Build#run:
         Buildable#build_for_destination (sim + device per default_sdk/--sdk)
         Buildable#create_framework
         XCFramework::XCFramework#build
       store                    ★  FileUtils.cp_r → Config#cache_dir(config)/{module}.xcframework
```

The umbrella package (`UmbrellaGenerator.swift`) already declares every dependency with real URLs/paths — `swift package resolve` in `Config#umbrella_dir` materializes checkouts without any new Swift-side work.

## Related Code Files

- Create: `lib/spm_cache/spm/build_pipeline.rb` — extraction of the destination-loop + framework assembly + xcframework build from `command/pkg/build.rb` (module `SPMCache::SPM::BuildPipeline`; input: name, pkg_dir, destinations, out_dir; output: xcframework path)
- Modify: `lib/spm_cache/command/pkg/build.rb` — delegate to `BuildPipeline`, keep CLI flag parsing; behavior identical
- Modify: `lib/spm_cache/installer/build.rb` — replace the log-only loop: resolve umbrella, map target → checkout, invoke `BuildPipeline`, copy result into cache dir; honor `ignore_build_errors?`
- Modify: `lib/spm_cache/core/config.rb` — none expected (`cache_dir`, `umbrella_dir` exist)

## Implementation Steps

1. **Extract `BuildPipeline`** from `Command::Pkg::Build#run` (destination loop, tmpdir framework staging, `XCFramework` assembly, slice reporting). Re-run `pkg build` manually on one package to confirm no behavior change.
2. **Umbrella resolution:** in `Installer::Build`, after `super`, run `Core::Sh.run("swift package resolve", cwd: config.umbrella_dir)`. Checkouts land in `{umbrella_dir}/.build/checkouts/`.
3. **Checkout mapping:** for each selected target, find its checkout: match `Lockfile` package slug (repo basename, same rule as `PackageRef.slug` — `Lockfile.swift:15-24`) against checkout directory names. Local packages (`pathFromRoot`) build in place from their existing path. Warn + skip when no checkout matches.
4. **Build + store:** `BuildPipeline.run(name: target, pkg_dir: checkout, destinations: resolve from config.default_sdk, out_dir: tmp)`, then copy to `config.cache_dir(@config_name)`. Wrap per-target in begin/rescue: re-raise unless `config.ignore_build_errors?`, else warn and continue.
5. **Scheme fallback:** `Buildable` uses `-scheme {name}` (`spm/build.rb`); package scheme names usually equal product names for SPM packages opened by xcodebuild, but not always. On build failure with "scheme not found", list schemes (`xcodebuild -list`) and retry with the closest match; otherwise take the warning path.
6. End-to-end verify: empty cache → `spm-cache build Alamofire` → xcframework lands in `~/.spm-cache/debug/` → `spm-cache use` reports it `hit`.

## Success Criteria

- [ ] `spm-cache build <target>` produces `~/.spm-cache/debug/<module>.xcframework` with expected slices (per `default_sdk`)
- [ ] Subsequent `spm-cache use` flips that target from `missed` to `hit` in graph.json
- [ ] `pkg build` behavior unchanged after extraction (same output path, slices, checksum flag)
- [ ] Ignored targets skipped even when named (Phase 2 warning path)
- [ ] Build failure with `ignore_build_errors: false` aborts with a clear error; `true` warns and continues
- [ ] Local packages build from `pathFromRoot` without checkout resolution

## Risk Assessment

- **Scheme name ≠ product name:** biggest practical failure mode across arbitrary packages (mitigation: `xcodebuild -list` fallback, Step 5; and `ignore_build_errors` escape hatch). Known v0.1.0 limitation — the same constraint `pkg build` already has.
- **Resolve time/network:** `swift package resolve` downloads sources on first run; acceptable (it replaces the compile Xcode would do anyway). Cache checkouts persist across runs since sandbox recreate (`installer.rb:48-55`) wipes `spm-cache/` — **verify**: `recreate_dirs` runs `rm_rf(sandbox)` each install, which would nuke checkouts every time. Mitigation: resolve checkouts to a path outside the recreated sandbox (e.g. `~/.spm-cache/checkouts/`) via `--build-path`, or exclude the umbrella `.build` from recreation. Decide at implementation; flagged for cook.
- **Extraction regression in `pkg build`:** covered by manual re-run (Step 1) + existing `buildable_spec.rb`.
