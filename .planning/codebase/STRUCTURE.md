---
title: Codebase Structure
focus: arch
mapped_date: 2026-08-10
last_mapped_commit: 5687b4641c1d7a36ef4fc99d59fdccf6dc09c5e0
---

# Codebase Structure

## Top-Level Layout

```
spm-cache/
├── bin/spm-cache                # Ruby executable
├── lib/spm_cache/               # Ruby gem (~6k LOC)
│   ├── command/                 # CLaide command tree
│   ├── core/                    # Cross-cutting utilities
│   ├── installer/               # Orchestration
│   ├── spm/                     # SPM domain (build, desc, xcframework, pkg)
│   ├── storage/                 # Remote cache backends
│   ├── xcodeproj/               # Xcodeproj gem extensions
│   ├── cache/cachemap.rb        # Cache visualization model
│   └── swift/, utils/           # Swift SDK helpers, templates
├── spec/                        # RSpec (~4.4k LOC) + fixtures/
├── tools/spm-cache-proxy/       # Swift companion executable
├── docs/                        # Design docs, journals, diagrams
├── plans/                       # Feature planning docs + reports/
├── skills/                      # Spm-cache & issue-collector skills
├── .github/workflows/           # CI (update-tap.yml)
├── spm_cache.gemspec, Gemfile, VERSION, Makefile
└── README.md, CLAUDE.md, LICENSE.txt
```

## Key File Locations

| File | Responsibility |
|---|---|
| `bin/spm-cache` | Executable entry; loads `lib/spm_cache/main.rb` |
| `lib/spm_cache/version.rb` | Reads `VERSION` → `SPMCache::VERSION` |
| `lib/spm_cache/main.rb` | `Main.run` / `Main.load_all` (auto-require all `.rb`) |
| `lib/spm_cache/command.rb` | Root CLAide command + global options |
| `lib/spm_cache/command/base.rb` | `BaseOptions` (sdk, config, merge_slices, library_evolution) |
| `lib/spm_cache/installer.rb` | Orchestrator (`perform_install`, `detect_diff`) |
| `lib/spm_cache/installer/use.rb` | Default `use` command installer (fast path) |
| `lib/spm_cache/installer/build.rb` | `build` command installer |
| `lib/spm_cache/installer/rollback.rb` | Restores original project state |
| `lib/spm_cache/installer/integration.rb` | Integration mixins (supporting_files, viz, descs, build) |
| `lib/spm_cache/spm/build_pipeline.rb` | xcframework build loop (919 LOC) |
| `lib/spm_cache/spm/build.rb` | Lower-level SPM build helpers |
| `lib/spm_cache/spm/desc/desc.rb` | `swift package describe` parser root |
| `lib/spm_cache/spm/xcframework/xcframework.rb` | Framework assembly |
| `lib/spm_cache/spm/pkg/proxy.rb` | Proxy Package.swift model |
| `lib/spm_cache/core/config.rb` | Singleton config + paths |
| `lib/spm_cache/core/lockfile.rb` | Lockfile model + `Pkg` |
| `lib/spm_cache/core/diff_detector.rb` | Graph change detection |
| `lib/spm_cache/core/sh.rb` | Shell-out (`Open3`) |
| `lib/spm_cache/core/git.rb` | Git wrapper (used by GitStorage) |
| `lib/spm_cache/storage/git.rb` | Git remote cache backend |
| `lib/spm_cache/storage/s3.rb` | S3 remote cache backend |
| `tools/spm-cache-proxy/Sources/CLI.swift` | Swift CLI root (`@main`) |
| `tools/spm-cache-proxy/Sources/CLI/GenProxy.swift` | Proxy generator command |
| `tools/spm-cache-proxy/Sources/Core/Generator/ProxyGenerator.swift` | Proxy generation logic |

## Naming Conventions

- **Commands:** `SPMCache::Command::{Name}` (`Command::Use`, `Command::Cache::List`); nested groups (`Command::Cache`, `Command::Remote`, `Command::Pkg`)
- **Installers:** `SPMCache::Installer::{Name}` (`Installer::Use`, `Installer::Build`)
- **Storage:** `SPMCache::Storage::{Backend}` (`GitStorage`, `S3Storage`)
- **SPM model:** `SPMCache::SPM::{Concept}`
- **Ruby files** named after primary class (`config.rb` → `Config`); one module root `.rb` with autoload
- **Specs** mirror feature/area: `*_spec.rb` (e.g. `diff_detector_spec.rb`, `gen_proxy_field_regression_spec.rb`)

## Where to Find Things

- **Add a CLI command:** `lib/spm_cache/command/` (+ register in command tree)
- **Build logic:** `lib/spm_cache/spm/build_pipeline.rb`, `build.rb`
- **Xcode project edits:** `lib/spm_cache/xcodeproj/`, `lib/spm_cache/installer/integration/build.rb`
- **Remote cache:** `lib/spm_cache/storage/`
- **Config/paths:** `lib/spm_cache/core/config.rb` (Singleton)
- **Tests:** `spec/` (Ruby), `tools/spm-cache-proxy/Tests/` (Swift)
- **Planning/history:** `plans/` and `docs/journals/`
