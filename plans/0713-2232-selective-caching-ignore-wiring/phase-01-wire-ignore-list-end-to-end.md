---
phase: 1
title: Wire ignore list end-to-end
status: completed
priority: P1
dependencies: []
effort: M
---

# Phase 1: Wire ignore list end-to-end

<!-- Updated: Validation Session 1 - ignore patterns match BOTH resolvedProductName and package identity (pkg.name); ignored = always source even on cache hit (confirmed) -->

## Overview

Thread `spm-cache.yml` `ignore:` patterns from Ruby config through the `gen-proxy` CLI into `ProxyGenerator`, so matching modules get `status: ignored` in `graph.json` and a source-mode proxy manifest — making `spm-cache off` and the `ignore:` config actually work.

## Requirements

- Functional: a package matching an `ignore:` glob pattern is never served as a binary target, even when a cached xcframework exists; it appears as `ignored` in graph.json / cache stats / viz.
- Non-functional: no behavior change for projects with an empty ignore list; glob semantics identical on both sides (Ruby `File.fnmatch` ↔ C `fnmatch`, both default flags).

## Architecture

Data flow (one new hop, marked ★):

```
spm-cache.yml (ignore: ["VolatileLib", "MyCompany*"])
  → Core::Config#ignore_list                      (exists, config.rb:104)
  → SPM::Package::Proxy#prepare / #gen_proxy      ★ pass ignore list
  → ProxyExecutable#gen_proxy                     ★ append --ignore "a,b" CSV
  → GenProxy.swift                                ★ new @Option ignore, split CSV
  → ProxyGenerator.generate                       ★ fnmatch → .ignored + source manifest
  → graph.json {"status": "ignored"}              (consumers already exist:
       Cachemap#ignored, #stats, Proxy#cache_ignored, depgraph_for_viz)
```

Matching must happen in Swift because module/product names are only known after umbrella resolution — Ruby has patterns, not resolved names. Keep `Config#should_ignore?` (config.rb:124) as-is; it becomes the Ruby-side mirror used by Phase 2.

## Related Code Files

- Modify: `lib/spm_cache/spm/pkg/proxy.rb` — `prepare` reads `Core::Config.instance.ignore_list`, forwards to `gen_proxy`
- Modify: `lib/spm_cache/spm/pkg/proxy_executable.rb` — `gen_proxy` accepts `ignore:` kwarg, appends `--ignore <csv>` when non-empty (shell-quote the value)
- Modify: `tools/spm-cache-proxy/Sources/CLI/GenProxy.swift` — add `@Option var ignore: String?`, split on `,`, pass patterns into `ProxyGenerator`
- Modify: `tools/spm-cache-proxy/Sources/Core/Generator/ProxyGenerator.swift` — accept `ignoredPatterns: [String]`; in `generate`, check match before cache lookup; matched → `.ignored` + source-mode manifest (reuse existing miss branch: stub sources + `.target` manifest)

## Implementation Steps

1. **Swift — ProxyGenerator:** add `let ignoredPatterns: [String]` (default `[]`) to init. Add private helper `isIgnored(_ pkg: Lockfile.PackageRef) -> Bool` using `fnmatch(pattern, name, 0) == 0` (import Darwin; matches Ruby `File.fnmatch` default semantics) — per validation decision, a package is ignored when ANY pattern matches EITHER `pkg.resolvedProductName` OR `pkg.name` (lockfile identity). In the per-package loop (line ~37): if `isIgnored(pkg)` → skip `cache.hit` lookup, set `status = .ignored`, take the source-mode branch for manifest generation (empty-stub in this phase; upgraded to real source fallback in Phase 3).
2. **Swift — GenProxy.swift:** add `@Option(help: "Comma-separated glob patterns of modules to exclude from caching") var ignore: String?`. Parse `ignore?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []`, pass to `ProxyGenerator(cache:outputDir:ignoredPatterns:)`.
3. **Ruby — proxy_executable.rb:** `gen_proxy(umbrella_dir:, output_dir:, cache_dir:, lockfile_path: nil, ignore: [])`; append `--ignore '#{ignore.join(",")}'` only when `ignore.any?` (single-quoted to survive `*` in shell).
4. **Ruby — proxy.rb:** in `prepare`, read `ignore = Core::Config.instance.ignore_list` and pass through `gen_proxy(..., ignore: ignore)`; update the `gen_proxy` method signature accordingly.
5. Rebuild proxy tool: `make proxy.build`. Manual smoke: run `gen-proxy` against a fixture lockfile with `--ignore 'Foo*'` and inspect `graph.json` + generated `Package.swift` for the ignored module.

## Success Criteria

- [ ] `gen-proxy --ignore 'VolatileLib'` marks that module `"status": "ignored"` in graph.json
- [ ] Ignored module's proxy `Package.swift` uses `.target` (source mode), never `.binaryTarget`, even with a cache hit present in `~/.spm-cache/`
- [ ] Glob pattern `'MyCompany*'` ignores all matching modules
- [ ] Empty/absent `--ignore` → byte-identical behavior to today (hit/missed only)
- [ ] `Cachemap#print_stats` shows non-zero `Ignored:` count after `spm-cache off X && spm-cache use`
- [ ] `make proxy.build` succeeds; `make test` still green

## Risk Assessment

- **Glob semantics drift (Ruby vs Swift):** both use POSIX fnmatch defaults; covered by mirrored test cases in Phase 3. Low risk.
- **Shell quoting of patterns:** `*` in `--ignore` must not glob-expand — single-quote in `proxy_executable.rb`; `Sh.run` passes through a shell, so this is load-bearing. Add a pattern-with-`*` case to manual smoke.
- **CSV delimiter collision:** module names can't contain `,` in SPM; acceptable.
