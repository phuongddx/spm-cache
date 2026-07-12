# Code Standards

> **Project:** spm-cache

## Language Conventions

### Ruby

- **Style:** Frozen string literals (`# frozen_string_literal: true`) at top of every file
- **Module structure:** `SPMCache` top-level module, nested by concern (`Core`, `SPM`, `Installer`, `Storage`, `Command`, `Swift`, `Utils`, `XcodeprojExt`)
- **Naming:** `CamelCase` for classes/modules, `snake_case` for methods/variables, `SCREAMING_SNAKE` for constants
- **Autoload:** Use `autoload` for lazy loading in module roots (e.g., `lib/spm_cache.rb`, `lib/spm_cache/spm.rb`)
- **Auto-require:** `Main.load_all` recursively requires all `.rb` files sorted for deterministic order
- **Mixins:** Use `include` for behavior modules (`Log`, `BaseOptions`, syntax mixins)
- **Refinements:** Used for core extensions (`HashExt`, `ParallelExt`, `SystemExt`) to avoid global monkey-patching
- **Singletons:** `Config` uses `Singleton` mixin with `@@instance` override
- **Error handling:** `Core::GeneralError` for expected failures, `raise` with messages
- **Shell commands:** Always via `Core::Sh.run` (Open3) — never backticks or `system()`

### Swift

- **Tools version:** 6.0
- **Structure:** `CLI/` (ArgumentParser commands), `Core/` (domain logic)
- **Naming:** `PascalCase` for types, `camelCase` for properties/methods
- **Protocols:** Used for abstraction (`ProxyPackageProtocol`, `CommandRunning`)
- **Extensions:** `URL` and `String` extensions in `Core/Extensions/Core.swift`
- **Logging:** `Logger` struct with Rainbow-colored output (debug/info/warning/error)
- **Error handling:** `throws` + `try` for failable operations, `ExitCode.failure` for CLI errors
- **File organization:** One primary type per file, grouped by directory

## Project Conventions

### File Organization

```
lib/spm_cache/
├── {module}.rb          # Module root with autoload declarations
├── {module}/            # Implementation files
└── {module}/{sub}/      # Nested concerns
```

- Each module has a root `.rb` file that declares `autoload` entries
- Implementation files go in the directory named after the module
- Files are named after their primary class/module (e.g., `config.rb` → `Config`)

### Naming Patterns

- **Commands:** `SPMCache::Command::{Name}` (e.g., `Command::Use`, `Command::Cache::List`)
- **Installers:** `SPMCache::Installer::{Name}` (e.g., `Installer::Use`, `Installer::Build`)
- **Integration mixins:** `SPMCache::Installer::{Name}IntegrationMixin` (e.g., `BuildIntegrationMixin`)
- **Storage:** `SPMCache::Storage::{Backend}` (e.g., `GitStorage`, `S3Storage`)
- **SPM model:** `SPMCache::SPM::{Concept}` (e.g., `SPM::Package`, `SPM::Buildable`, `SPM::Macro`)

### Configuration

- Config paths: `Core::Config.instance` provides `sandbox_dir`, `cache_dir`, `umbrella_dir`, `proxy_dir`, `metadata_dir`, `binaries_dir`, `lockfile_path`
- Config file: `spm-cache.yml` (YAML, loaded via `YAMLRepresentable`)
- Lockfile: `spm-cache.lock` (JSON, loaded via `JSONRepresentable`)

### Templates

- ERB templates live in `lib/spm_cache/assets/templates/`
- Rendered via `Utils::Template.render(name, vars)` or `Utils::Template.render_to(name, path, vars)`
- Template naming: `{name}.template` (no extension beyond `.template`)

### Xcodeproj Extensions

- Extensions on `Xcodeproj` classes go in `lib/spm_cache/xcodeproj/`
- Applied via `send(:include, ...)` at file load time
- Extension modules are namespaced under `SPMCache::XcodeprojExt`

## Testing

- **Framework:** RSpec (`spec/` directory — to be created)
- **Run:** `make test` or `bundle exec rspec`
- **Swift tests:** To be added in `tools/spm-cache-proxy/Tests/`

## Linting & Formatting

- **Ruby:** RuboCop (`make format` or `bundle exec rubocop --auto-correct`)
- **Swift:** SwiftFormat or swift-format (to be configured)
- **Pre-commit:** `.pre-commit-config.yaml` present

## Dependencies

### Ruby Runtime

| Gem | Purpose |
|-----|---------|
| `claide` | CLI command framework |
| `xcodeproj` | Xcode project file manipulation |
| `parallel` | Parallel array processing |
| `tty-cursor` | Terminal cursor control (live log) |
| `tty-screen` | Terminal screen size |
| `CFPropertyList` | Plist serialization |

### Ruby Development

| Gem | Purpose |
|-----|---------|
| `bundler` | Dependency management |
| `rspec` | Testing |
| `rubocop` | Linting |

### Swift

| Package | Purpose |
|---------|---------|
| `swift-argument-parser` | CLI parsing |
| `Rainbow` | Colored terminal output |

## Build & Development Commands

| Command | Purpose |
|---------|---------|
| `make install` | Install Ruby dependencies |
| `make test` | Run RSpec tests |
| `make format` | Run RuboCop auto-correct |
| `make proxy.build` | Build Swift proxy tool (release) |
| `make proxy.clean` | Clean Swift build artifacts |
