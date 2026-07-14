---
phase: 2
title: Build command target filtering
status: completed
priority: P2
dependencies:
  - 1
effort: S
---

# Phase 2: Build command target filtering

<!-- Updated: Validation Session 1 - scope expanded: actual build invocation is now Phase 4 of this plan (no longer out of scope); this phase remains selection-logic only -->

## Overview

Make `spm-cache build [TARGETS]` honor its TARGETS argument: pass the parsed list into `Installer::Build` and filter the cachemap's missed list by it. Today `@targets` is parsed then discarded (`lib/spm_cache/command/build.rb:16` vs line 28).

## Requirements

- Functional: `spm-cache build Alamofire SnapKit` processes only those two targets from the missed set; no TARGETS → all missed targets (current behavior). Unknown target names warn, don't crash. Ignored targets (Phase 1) are excluded even when explicitly named — with a warning explaining why.
- Non-functional: this phase fixes the *selection* logic only; the actual build invocation is implemented in Phase 4, which consumes the selected-target list this phase produces.

## Architecture

`Command::Build#run` → `Installer::Build.new(project:, targets:)` → `perform_install` computes `to_build = missed ∩ targets` (or all missed when targets empty). `Config#should_ignore?` (config.rb:124) gains its first Ruby-side caller: warn when a requested target is ignored. Cachemap already separates `missed` / `ignored`, so ignored targets never appear in `missed` after Phase 1 — the ignore-warning is UX clarity, not correctness.

## Related Code Files

- Modify: `lib/spm_cache/command/build.rb` — pass `targets: @targets` to `Installer::Build.new`
- Modify: `lib/spm_cache/installer/build.rb` — accept `targets:` kwarg (default `[]`), filter missed list, warn on unknown/ignored names

## Implementation Steps

1. **command/build.rb:** change line 27 to `Installer::Build.new(project: project_path, targets: @targets)`.
2. **installer/build.rb:** add `def initialize(project:, config: "debug", targets: [])` storing `@requested_targets`, calling `super(project: project, config: config)`.
3. **installer/build.rb — selection logic in `perform_install`:**
   ```ruby
   missed = @cachemap ? @cachemap.missed : []
   if @requested_targets.any?
     unknown = @requested_targets - (missed + @cachemap.hit + @cachemap.ignored)
     unknown.each { |t| Core::UI.info "WARNING: unknown target '#{t}' (not in dependency graph)" }
     @requested_targets.select { |t| @cachemap.ignored.include?(t) }
                       .each { |t| Core::UI.info "WARNING: '#{t}' is in the ignore list; skipping" }
     missed = missed & @requested_targets
   end
   ```
   Then iterate `missed` (existing log loop). Also skip cleanly with an info message when the intersection is empty.
4. Keep the loop body log-only in this phase; Phase 4 replaces it with the real `BuildPipeline` invocation over the selected list.

## Success Criteria

- [ ] `spm-cache build Foo` with Foo missed → only Foo listed for build
- [ ] `spm-cache build` (no args) → all missed targets listed (unchanged behavior)
- [ ] `spm-cache build Nonexistent` → warning, exit 0
- [ ] `spm-cache build IgnoredLib` → "in the ignore list; skipping" warning, not built
- [ ] Targets already `hit` are not re-listed as builds

## Risk Assessment

- **Low blast radius:** two files, additive kwarg with default preserves any other callers.
- **Name mismatch (package identity vs product/module name):** cachemap keys are `resolvedProductName`s from the Swift side; users may type the package repo name. Warning path covers this; document the expected name form in Phase 3 docs.
