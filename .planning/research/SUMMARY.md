# Project Research Summary

> **Derived from:** `docs/project-roadmap.md`, `docs/project-overview-pdr.md`, `docs/superpowers/specs/2026-08-10-v0.3.0-watch-init-doctor-design.md`, `.planning/codebase/*`, `competitive-analysis-2026-07.html`, `scipio-deepdive-features-2026-07.html`
> **Method:** Inline synthesis (existing research already extensive; per-phase researcher agents will still run before each phase per config `workflow.research: true`)

## Key Findings

### Stack (already validated)
- **Ruby gem (>= 3.0)** + **Swift 6.0 companion** (`tools/spm-cache-proxy`); macOS-only (Xcode toolchain)
- Runtime deps: `claide`, `xcodeproj`, `parallel`, `tty-cursor/screen`, `CFPropertyList`
- Swift companion deps: `swift-argument-parser`, `Rainbow`
- Distribution: Homebrew tap (`phuongddx/spm-cache`) + RubyGems; CI releases via `.github/workflows/update-tap.yml`
- Tests: RSpec (~30 specs, ~4.4k LOC) + XCTest (companion); **no CI runs tests today**

### Table Stakes (parity — must keep)
- Proxy-package swap at SPM manifest level; cache-miss→source fallback
- Swift Macro + resource-bundle + library-evolution support
- Git + S3 remote cache from CLI
- Per-config (Debug/Release) caching; multi-slice xcframeworks
- Diff-based auto-sync (DiffDetector) — already a competitive moat

### Differentiators (competitive moat vs Scipio/xccache)
- **Reads Xcode project directly** — no separate hand-written manifest (Scipio's F1/F6 friction)
- **Auto-integrates binaries** via proxy swap — no manual drag-drop (Scipio's F2)
- **CLI-first remote cache** — no Swift script needed (Scipio's F3)
- v0.3.0 deepens moat: `watch` (zero-touch auto-sync), `init` (one-command bootstrap), `doctor` (self-diagnosis)

### Watch Out For (pitfalls)
- **No test CI** — every v0.3.0 feature ships unverified unless `ci.yml` lands early; the regression suite only runs locally. Build test CI first.
- **`build_pipeline.rb` (919 LOC) + `installer.rb` (578 LOC)** complexity — any feature touching the install/build path must respect the existing diff-driven fast path and orphan-purge logic in `installer.rb`.
- **Ruby↔Swift companion version drift** — no explicit handshake; `doctor`'s `companion_binary` check closes this gap.
- **Shell-string interpolation** in `core/git.rb` — new commands must route through `Core::Sh.run`; avoid interpolating untrusted values.
- **`watch` FSEvents binding** — keep minimal; `--once` keeps the core path testable without the OS API. Fall back to `listen` gem behind a flag if brittle.
- **GitHub Action** lives in a separate repo — keep it a thin shell-out; don't duplicate logic or it drifts from the gem.

## Implications for Roadmap

1. **Horizontal Layers mode** suits this project: each feature is a vertical slice but internal layering (command → core → integration → test) maps to clean phase boundaries.
2. **Test CI should land first** (it's the foundation — reliability pillar enables confident delivery of the other two). It is also the smallest, lowest-risk slice.
3. **`doctor` second** — it's self-contained (new command + diagnostics registry), doesn't touch the install/build path, and its `companion_binary` check de-risks the other features.
4. **`init` third** — touches `Config`/`Lockfile` (well-bounded), enables the Action.
5. **`watch` last** — highest integration surface (filesystem API + Installer::Use loop); benefits from the test CI and `doctor` being in place first.
6. **GitHub Action** ships alongside or just after `init` (it depends on the wizard + remote backends).

## Sources
- `.planning/codebase/STACK.md`, `ARCHITECTURE.md`, `CONCERNS.md` (codebase map, 2026-08-10)
- `docs/superpowers/specs/2026-08-10-v0.3.0-watch-init-doctor-design.md` (approved design)
- `docs/project-roadmap.md`, `docs/project-overview-pdr.md` (PDR)
- `competitive-analysis-2026-07.html`, `scipio-deepdive-features-2026-07.html` (competitive research)
