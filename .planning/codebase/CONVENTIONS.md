---
title: Coding Conventions
focus: quality
mapped_date: 2026-08-23
last_mapped_commit: f55b9b9a7dc73104b490ed76ec38549b242af03e
---

# Coding Conventions

**Analysis Date:** 2026-08-23

## File Header

Every `.rb` file begins with `# frozen_string_literal: true` as the first line. No exceptions observed.

## Module & Namespace Structure

**Top-level module:** `SPMCache` (defined in `lib/spm_cache.rb`)

**Sub-modules follow a flat namespace under `SPMCache`:**
- `SPMCache::Core` — shell execution, config, error types, logging, diff detection, diagnostics, lockfile, parallelism, caching
- `SPMCache::Command` — CLaide subcommands
- `SPMCache::SPM` — SPM graph model (descriptions, build pipeline, xcframeworks)
- `SPMCache::Installer` — orchestration of build/use/rollback flows
- `SPMCache::Storage` — remote cache backends (git, S3)
- `SPMCache::Xcodeproj` — Xcode project manipulation via xcodeproj gem
- `SPMCache::Cache` — cachemap data structure
- `SPMCache::Utils` — template engine
- `SPMCache::Swift` — SDK abstraction, swiftc wrapper

**Directory structure mirrors namespace:** `lib/spm_cache/core/sh.rb` → `SPMCache::Core::Sh`. One class/module per file.

## CLaide Command Pattern

All CLI subcommands inherit from `SPMCache::Command` (`lib/spm_cache/command.rb`) which extends `CLAide::Command`.

**Required declarations on each subcommand class:**
```ruby
class Watch < Command
  self.summary = 'Short one-line description'
  self.description = 'Longer description for --help'

  def self.options
    [['--flag', 'Description']].concat(super)
  end

  def initialize(argv)
    # Parse flags/options BEFORE calling super
    @once = argv.flag?('once', false)
    super
  end

  def run
    # Command logic here
  end
end
```

**Key rules:**
- `self.abstract_command = true` on `Base` group classes and the root `Command` class
- `self.default_subcommand = "use"` is set on the root `Command` in `lib/spm_cache/command.rb`
- Flag parsing (`argv.flag?`, `argv.option`) happens in `initialize` before `super`
- `include BaseOptions` on leaf commands for shared `--sdk`, `--config`, `--log-dir`, `--merge-slices`, `--library-evolution`
- Commands are auto-registered via `Main.load_all` which `Dir.glob`s all `.rb` files recursively
- Each subcommand lives in `lib/spm_cache/command/<name>.rb`; nested subcommands in `lib/spm_cache/command/<group>/<name>.rb`

**Command examples:** `lib/spm_cache/command/watch.rb`, `lib/spm_cache/command/init.rb`, `lib/spm_cache/command/doctor.rb`, `lib/spm_cache/command/build.rb`

## Naming Patterns

**Files:**
- `snake_case.rb` — always lowercase with underscores. Examples: `diff_detector.rb`, `build_pipeline.rb`, `proxy_executable.rb`
- `lib/spm_cache/command/*.rb` — flat filename matching the command name (e.g., `watch.rb`, `init.rb`, `doctor.rb`)
- `lib/spm_cache/spm/desc/target.rb` — mirrors the namespace path

**Classes:**
- `PascalCase` — e.g., `Buildable`, `Diagnostics`, `DiffDetector`, `ProxyExecutable`, `Watcher`

**Modules:**
- `PascalCase` — e.g., `BaseOptions`, `ParallelExt`, `HashRepresentable`, `YAMLRepresentable`

**Methods:**
- `snake_case` — e.g., `perform_install`, `run_once`, `resolve_platforms`, `should_ignore?`
- Predicate methods end with `?` — e.g., `simulator?`, `library_evolution?`, `ignore_local?`, `ignore_build_errors?`, `interactive?`
- Destructive/bang methods end with `!` — e.g., `reset!`, `verify!`, `deep_merge!`

**Constants:**
- `UPPER_SNAKE_CASE` — e.g., `DEFAULT_DEBOUNCE`, `CACHE_DIR`, `CONFIG_FILENAME`, `FAILURE_DETAIL_LINES`, `LOW_DEPLOYMENT_TARGET_RETRY_VALUE`
- Frozen string/hash constants: `DESTINATIONS = { ... }.freeze`

**Variables:**
- `snake_case` — e.g., `@installer_factory`, `@last_signatures`, `@project_path`, `@watched_files`

## Mixins and Refinements (No Monkey-Patching)

**The codebase uses composition, never monkey-patching:**

1. **`include` for behavior sharing:** `BaseOptions` is included into leaf commands via `include BaseOptions`
2. **Refinements for core extensions:** `Core::ParallelExt` refines `Array` in `lib/spm_cache/core/parallel.rb` — uses `refine Array do` block, not `class Array; def ... end`
3. **Syntax modules as includes:** `Core::Syntax::HashRepresentable` is a module included into classes that need `load`/`save`/`[]`/`[]=` for config files. Subclasses (`YAMLRepresentable`, `JSONRepresentable`, `PlistRepresentable`) implement `read_file`/`write_file` per format
4. **`SPM::PkgMixin`:** Simple attr_accessor mixin in `lib/spm_cache/spm/mixin.rb` — provides `umbrella_pkg`/`proxy_pkg` accessors, mixed into description classes

## Error Handling

**Custom error hierarchy in `lib/spm_cache/core/error.rb`:**
```ruby
module SPMCache::Core
  class BaseError < StandardError; end
  class GeneralError < BaseError
    attr_reader :exit_status
    def initialize(message = nil, exit_status = 1)
```

**Patterns:**
- All command/infra errors raise `Core::GeneralError` — never raw `StandardError` or `RuntimeError` for expected failures
- `Core::Sh.run` raises `GeneralError` with the command, exit code, and bounded tail output (last 60 lines of stdout+stderr) on non-zero exit
- Commands use `raise Core::GeneralError, 'message'` for user-facing errors (e.g., missing `.xcodeproj`)
- `Core::UI.error!` raises `GeneralError` after printing to stderr
- Rescue in long-running loops (watcher) catches `StandardError` broadly and logs it, then continues — only `Interrupt` (Ctrl-C) exits cleanly

## Logging and UI Output

**`Core::UI` module in `lib/spm_cache/core/log.rb`:**
- `Core::UI.info(msg)` — prints to `$stdout`
- `Core::UI.warn(msg)` — prints `[warn] msg` to `$stderr`
- `Core::UI.error(msg)` — prints `[error] msg` to `$stderr`
- `Core::UI.error!(msg)` — prints to stderr then raises `GeneralError`
- `Core::UI.section(title, &block)` — prints a `===` banner, yields block
- `Core::UI.message` is an alias for `Core::UI.info`

**`Core::Log`** is an alias: `module Log; include UI; end`

**Watcher and background processes** use an injected `out:` IO parameter (default `$stdout`) rather than calling `Core::UI` directly — enables StringIO capture in tests.

**No logging framework.** All output is via `puts`/`$stderr.puts` through `Core::UI` or the injected `@out` IO. No structured logging, no log levels beyond info/warn/error.

## Shell Execution

**All external commands go through `Core::Sh` in `lib/spm_cache/core/sh.rb`:**
- `Core::Sh.run(cmd, opts)` — runs command, returns `{output:, error:, status:}` or raises `GeneralError`
- `Core::Sh.capture_output(cmd, opts)` — returns stripped stdout string
- `Core::Sh.run!(cmd, opts)` — alias for `run`
- Options: `cwd:`, `env:`, `live_log:` (for streaming build output)

**Never shell out directly** — always use `Core::Sh`. This is the single point for error formatting and exit-status checking.

## Filesystem Watcher Pattern

**The `watch` command uses portable mtime+size polling (Ruby stdlib only)** — no `listen` gem, no FSEvents native bindings.

**Pattern in `lib/spm_cache/core/watcher.rb`:**
- Constructor takes `project_path:`, `installer_factory:` (Proc), `debounce:`, `out:`
- `run_once` — single sync, fully testable without the poll loop
- `run` — infinite poll loop with `sleep debounce`, `rescue Interrupt` for clean exit
- File signature: `[path, stat.mtime.to_i, stat.size]` — cheap comparison array
- Continue-on-error: transient failures logged, loop continues

## Singleton Pattern

**`Core::Config` uses `include Singleton`** in `lib/spm_cache/core/config.rb`. Accessed via `Core::Config.instance` (overrides `self.instance` with class-variable memoization). Reset between tests via `config.reset!`.

## Template Engine

**`Utils::Template` in `lib/spm_cache/utils/template.rb`** uses ERB with `trim_mode: "-"`. Templates live in `lib/assets/templates/<name>.template`. Two entry points:
- `Template.render(name, vars)` — returns string
- `Template.render_to(name, output_path, vars)` — writes to file

## Struct Usage

**Plain data objects use `Struct`:**
- `Diagnostics::Check = Struct.new(:name, :run, :fix_hint, keyword_init: true)`
- `Diagnostics::Result = Struct.new(:name, :status, :message, :fix_hint, keyword_init: true)`
- `DiffDetector::Diff = Struct.new(:added, :removed, :updated, keyword_init: true)`
- `Lockfile::Pkg` — Struct-based value object for package metadata

**Prefer `Struct` with `keyword_init: true`** over plain classes for data-only objects.

## Swift Companion Conventions

**The Swift proxy tool lives in `tools/spm-cache-proxy/`:**
- Separate Swift Package Manager project with `Package.swift`
- Tests in `Tests/spm-cache-proxyTests/`
- Built via `make proxy.build` (release mode)
- Ruby code invokes it via `Core::Sh.run` — treats it as an external CLI tool
- Version output consumed by `doctor` diagnostics check

## Import Organization

**Requires at file top, grouped logically:**
1. Ruby stdlib (`require 'json'`, `require 'fileutils'`, `require 'tmpdir'`)
2. Gem dependencies (`require 'xcodeproj'`, `require 'claide'`)
3. Internal modules (`require 'spm_cache/core/sh'`, `require 'spm_cache/core/config'`)

**`autoload` for lazy loading:**
- `SPMCache::Main`, `SPMCache::VERSION` autoloaded in `lib/spm_cache.rb`
- `SPMCache::Swift::Sdk`, `SPMCache::Swift::Swiftc` autoloaded in `lib/spm_cache/swift.rb`
- `Core::Syntax` submodules autoloaded in `lib/spm_cache/core/syntax.rb`

## Comments

**When to comment:**
- Field-bug explanations: detailed multi-line comments explaining empirical discoveries (e.g., `lib/spm_cache/spm/build.rb` LOW_DEPLOYMENT_TARGET_RETRY_VALUE)
- Architectural rationale: why a pattern was chosen over alternatives (e.g., `lib/spm_cache/core/watcher.rb` explaining why polling over FSEvents)
- Interface contracts: `@param` and `@return` YARD-style on public methods
- Data-driven registry explanations (e.g., `lib/spm_cache/core/diagnostics.rb`)

**No inline comments for obvious code.** Comments explain *why*, not *what*.

## Formatting

**Tool:** RuboCop v1.50+ (dev dependency, pre-commit hook)

**Configuration:** Default RuboCop rules. Run via:
- `make format` — runs `bundle exec rubocop --auto-correct`
- `.pre-commit-config.yaml` — runs rubocop with `--auto-correct` on commit

**No custom `.rubocop.yml`** observed in repo root — uses default configuration.

## Module Design

**Autoloading over eager require:** `lib/spm_cache/main.rb` loads all files via `Dir.glob` sort for deterministic order, but top-level `lib/spm_cache.rb` uses `autoload` for the main entry points.

**No barrel files.** Each file is required individually by name or via `Main.load_all`.

**`Core::Diagnostics` uses a registry pattern:** checks are registered at load time via `register(name, fix_hint:, &block)`, enabling extensibility without editing the command class.

---

*Convention analysis: 2026-08-23*
