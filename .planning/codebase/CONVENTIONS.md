---
title: Coding Conventions
focus: quality
mapped_date: 2026-08-31
last_mapped_commit: fdb3a70abe81852ec9310a3ff410341a4adcfa0c
---

<!-- refreshed: 2026-08-31 -->

# Coding Conventions

**Analysis Date:** 2026-08-31

## File Header

Every `.rb` file begins with `# frozen_string_literal: true` as the first line. No exceptions observed (verified across `lib/` at v0.4.0).

## Version Declaration

`SPMCache::VERSION` is **read from a `VERSION` file at the repo root**, not hardcoded:

```ruby
# lib/spm_cache/version.rb
VERSION = File.read(File.expand_path("../../VERSION", __dir__)).strip
```

Bump releases by editing the `VERSION` file only.

## Module & Namespace Structure

**Top-level module:** `SPMCache` (defined in `lib/spm_cache.rb`)

**Sub-modules follow a flat namespace under `SPMCache`:**
- `SPMCache::Core` — shell execution, config, error types, logging, diff detection, diagnostics, lockfile, parallelism, caching, canonical `Package.resolved` location (`package_resolved.rb`), process build lock path (`config.rb`)
- `SPMCache::Command` — CLAide subcommands (including the `cache` group: `command/cache/list.rb`, `command/cache/clean.rb`)
- `SPMCache::SPM` — SPM graph model (descriptions, build pipeline, xcframeworks, `resolved_graph.rb`, `checkout_resolver.rb`)
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
- **Every command that adds options composes them with `.concat(super)`** — verified across all current command files (`command/build.rb`, `command/doctor.rb`, `command/init.rb`, `command/use.rb`, `command/watch.rb`, `command/cache/clean.rb`, `command/remote/pull.rb`, `command/remote/push.rb`, `command/pkg/build.rb`). The inherited base `--config` (`command.rb`) must always stay in the accepted surface
- Flag parsing (`argv.flag?`, `argv.option`) happens in `initialize` before `super`
- `include BaseOptions` on leaf commands for shared `--sdk`, `--config`, `--log-dir`, `--merge-slices`, `--library-evolution`
- Commands are auto-registered via `Main.load_all` which `Dir.glob`s all `.rb` files recursively
- Each subcommand lives in `lib/spm_cache/command/<name>.rb`; nested subcommands in `lib/spm_cache/command/<group>/<name>.rb`

**Command examples:** `lib/spm_cache/command/watch.rb`, `lib/spm_cache/command/init.rb`, `lib/spm_cache/command/doctor.rb`, `lib/spm_cache/command/build.rb`, `lib/spm_cache/command/cache.rb` (group with `list.rb`/`clean.rb`)

## Structural Agreement (v0.4.0 Convention)

**One memoized host-graph resolution per run, shared by every consumer. Never a second, independent locator.**

- `Installer#host_graph_detector` (`lib/spm_cache/installer.rb:71`) memoizes a single `Core::DiffDetector` on `@host_graph_detector ||=`; `detect_diff` and lockfile reconciliation both go through it
- `Core::DiffDetector#host_graph_path` (`lib/spm_cache/core/diff_detector.rb:169`) memoizes the located `Package.resolved` path, **guarded on `defined?` not truthiness** — a nil (not-found) answer must stay memoized too:
  ```ruby
  def host_graph_path
    return @host_graph_path if defined?(@host_graph_path)
    @host_graph_path = PackageResolved.locate(@project_path, parent_fallback: true)
  end
  ```
- `Installer::Build` seeds the umbrella graph from `host_graph_detector.host_graph_path` (`lib/spm_cache/installer/build.rb:47`) — the pin source and the change detector cannot disagree because they literally cannot answer with different files

**Single locator class:** every site that needs the host resolved graph calls `Core::PackageResolved` (`lib/spm_cache/core/package_resolved.rb`) — never glob for `Package.resolved` ad hoc. Its API:
- `locate(project_path, parent_fallback: false)` — canonical tier search rooted at `project.xcworkspace/xcshareddata/swiftpm/Package.resolved`; returns path or nil, never raises. `parent_fallback: true` is taken only by DiffDetector
- `pins(path)` — strict parse; propagates `JSON::ParserError`/`TypeError` for callers that must fail loudly
- `pins_or_nil(path)` — tolerant; `nil` = absent/unreadable/malformed, `[]` = readable with zero pins. **Preserve the nil-vs-empty distinction** — reading "unreadable" as "empty host graph" would erase the lock

**`SPM::ResolvedGraph`** (`lib/spm_cache/spm/resolved_graph.rb`): source precedence via `source_for` — the umbrella's own `.build/Package.resolved` (written by `swift package resolve`) wins over the host graph when both exist, because it is what the checkouts on disk were materialized from. `seed!` snapshots before overwriting, `restore!` puts the snapshot back on failure; writes go through `atomic_write` (Tempfile + rename). `vendored_xcodeproj?` classifies Class E checkouts by glob.

## Fidelity Posture (v0.4.0 Convention)

**A fidelity violation is a warning plus a source fallback — never a hard failure.**

- `BuildPipeline#report_fidelity` (`lib/spm_cache/spm/build_pipeline.rb:102`) is the **single consolidated insertion point** for drift read-back, classification, and sidecar write — covering all artifact-producing paths uniformly. It **never raises**: any exception is rescued in `run` and degraded to `Core::UI.warn`, because the xcframework already built successfully and a metadata failure must never mask that (nor be mistaken for a build failure under `ignore_build_errors?`)
- Drift is reported per identity via `Core::UI.warn` ("drift detected (intended X, realized Y)"), the sidecar status becomes `resolution-incompatible`, the build continues from source ("(built from source)")
- The "never raises" claim is enforced by a rescue at every level that claims it — doc comments alone are not trusted (`build_pipeline.rb:73-82` comment)
- Drift scope is the **intersection** of intended and realized pin identities only; an identity on just one side carries no drift evidence. nil on either side yields an empty drifted set, never universal drift
- Pin comparison: **revision wins over version** (`host_pin_value`), mirroring `Core::Diagnostics#host_pin_value` and the Swift side (`Lockfile.swift`/`UmbrellaGenerator.swift`) so all diff sites agree

**Provenance sidecar schema** (`write_provenance_sidecar`): exactly `fidelity_status`, `pins`, `spm_cache_version`, `config`, `destinations`. **No absolute filesystem paths, usernames, hostnames, or build timestamps** — the sidecar travels through shared/remote cache backends. Absent sidecar is an unambiguous cache miss; a not-graph-pinned build writes an explicit `not-graph-pinned` sidecar with empty pins rather than deleting the file, and never clobbers a previous sidecar's non-empty pins (merge instead).

## Concurrency: Build Lock (v0.4.0 Convention)

**Cross-process mutual exclusion via a blocking flock**, not trylock-and-retry — "defer rather than interrupt" is satisfied by the OS's blocking semantics; no polling/backoff.

- Lock path: `Core::Config#build_lock_path` = `<project_dir>/.spm-cache-build.lock` (`lib/spm_cache/core/config.rb:101`); kept inside the project dir (never the sandbox dir) so sandbox recreation can't delete a live lock
- `Installer::Build#acquire_build_lock` (`lib/spm_cache/installer/build.rb:68`) holds `File::LOCK_EX` across the whole build
- `Installer::Use#with_build_lock` (`lib/spm_cache/installer/use.rb:60`) wraps the trailing integration steps (both fast path and full path) on the same lock; always `LOCK_UN` + `close` in `ensure`

## Naming Patterns

**Files:**
- `snake_case.rb` — always lowercase with underscores. Examples: `diff_detector.rb`, `build_pipeline.rb`, `proxy_executable.rb`, `package_resolved.rb`, `resolved_graph.rb`
- `lib/spm_cache/command/*.rb` — flat filename matching the command name (e.g., `watch.rb`, `init.rb`, `doctor.rb`)
- `lib/spm_cache/spm/desc/target.rb` — mirrors the namespace path

**Classes:**
- `PascalCase` — e.g., `Buildable`, `Diagnostics`, `DiffDetector`, `ProxyExecutable`, `Watcher`, `PackageResolved`, `ResolvedGraph`

**Modules:**
- `PascalCase` — e.g., `BaseOptions`, `ParallelExt`, `HashRepresentable`, `YAMLRepresentable`, `Cacheable`, `CheckoutResolver`

**Methods:**
- `snake_case` — e.g., `perform_install`, `run_once`, `resolve_platforms`, `should_ignore?`, `report_fidelity`, `seed_host_graph`
- Predicate methods end with `?` — e.g., `simulator?`, `library_evolution?`, `ignore_local?`, `ignore_build_errors?`, `interactive?`, `vendored_xcodeproj?`
- Destructive/bang methods end with `!` — e.g., `reset!`, `verify!`, `deep_merge!`, `invalidate_cache!`, `restore!`

**Constants:**
- `UPPER_SNAKE_CASE` — e.g., `DEFAULT_DEBOUNCE`, `CACHE_DIR`, `CONFIG_FILENAME`, `LOCKFILE_FILENAME`, `SANDBOX_DIR`, `FAILURE_DETAIL_LINES`, `LOW_DEPLOYMENT_TARGET_RETRY_VALUE`, `CANONICAL_RELATIVE_PATH`, `RESOLVED_FILENAME`
- Frozen string/hash constants: `DESTINATIONS = { ... }.freeze`

**Variables:**
- `snake_case` — e.g., `@installer_factory`, `@last_signatures`, `@project_path`, `@watched_files`, `@host_graph_detector`

## Mixins and Refinements (No Monkey-Patching)

**The codebase uses composition, never monkey-patching:**

1. **`include` for behavior sharing:** `BaseOptions` is included into leaf commands; `SPM::CheckoutResolver` is included into `Installer` so every flow (use/build/rollback) shares one checkout-materialization implementation
2. **Refinements for core extensions:** `Core::ParallelExt` refines `Array` in `lib/spm_cache/core/parallel.rb` — uses `refine Array do` block, not `class Array; def ... end`
3. **Syntax modules as includes:** `Core::Syntax::HashRepresentable` is a module included into classes that need `load`/`save`/`[]`/`[]=` for config files. Subclasses (`YAMLRepresentable`, `JSONRepresentable`, `PlistRepresentable`) implement `read_file`/`write_file` per format
4. **`SPM::PkgMixin`:** Simple attr_accessor mixin in `lib/spm_cache/spm/mixin.rb` — provides `umbrella_pkg`/`proxy_pkg` accessors, mixed into description classes
5. **`Core::Cacheable`** (`lib/spm_cache/core/cacheable.rb`): method-level memoization mixin — `cacheable :method_name` for instance methods, `cacheable_class_method :name` for singleton methods, `invalidate_cache!` to clear. Cache key is `[method_name, args, kwargs]` with `key?`-based lookup so nil results memoize correctly

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
- `Core::Sh.run` raises `GeneralError` with the command, exit code, and bounded tail output (last 60 lines of stdout+stderr via `FAILURE_DETAIL_LINES`) on non-zero exit — xcodebuild writes its real failure reason to stdout, so both streams are tailed
- Commands use `raise Core::GeneralError, 'message'` for user-facing errors (e.g., missing `.xcodeproj`)
- `Core::UI.error!` raises `GeneralError` after printing to stderr
- Rescue in long-running loops (watcher) catches `StandardError` broadly and logs it, then continues — only `Interrupt` (Ctrl-C) exits cleanly
- **Tiered strictness for parsers:** a locator/parser offers BOTH a strict method (`pins` — propagates parse errors) and a tolerant one (`pins_or_nil` — nil on any failure); callers choose deliberately and the choice is documented at the call site
- **Degradable metadata writes** (provenance sidecars) rescue `SystemCallError`/`JSON::ParserError` and degrade to a `Core::UI.warn` — never propagate out of a post-success hook

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

**Never shell out directly** — always use `Core::Sh`. This is the single point for error formatting and exit-status checking, and (since v0.4.0) the seam that makes test hermeticity enforceable: specs stub both entry points with a default-deny guard.

## Filesystem Watcher Pattern

**The `watch` command uses portable mtime+size polling (Ruby stdlib only)** — no `listen` gem, no FSEvents native bindings.

**Pattern in `lib/spm_cache/core/watcher.rb`:**
- Constructor takes `project_path:`, `installer_factory:` (Proc), `debounce:`, `out:`
- `run_once` — single sync, fully testable without the poll loop
- `run` — infinite poll loop with `sleep debounce`, `rescue Interrupt` for clean exit
- File signature: `[path, stat.mtime.to_i, stat.size]` — cheap comparison array
- Continue-on-error: transient failures logged, loop continues; the loop contract (self-trigger guard, burst collapse) is pinned by subprocess specs (`spec/watch_loop_spec.rb`), so behavioral changes to `run` must keep that contract

## Singleton Pattern

**`Core::Config` uses `include Singleton`** in `lib/spm_cache/core/config.rb`. Accessed via `Core::Config.instance` (overrides `self.instance` with class-variable memoization). Reset between tests via `config.reset!`.

**Memoization convention beyond the singleton:** instance-level memoization uses an ivar guarded by `defined?` (nil-safe — see `DiffDetector#host_graph_path`), or `Core::Cacheable` for many small methods. Prefer the `defined?` guard when a nil result is a valid memoized answer.

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
- Tests in `Tests/spm-cache-proxyTests/`, run via `swift test` in CI
- Built via `make proxy.build` (release mode); CI builds it before the RSpec job so the real-binary Ruby specs run non-skipped
- Ruby code invokes it via `Core::Sh.run` — treats it as an external CLI tool
- Version output consumed by `doctor` diagnostics check (pinned by `spec/doctor_companion_version_spec.rb`)
- Ruby-side contract mirrors live in the Swift sources: `Cache.swift#hit()` reads provenance sidecars fail-safe (absent/unreadable/malformed → nil, i.e., a miss) — matching the Ruby side's `existing_sidecar_pins` posture

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
- Interface contracts: `@param` and `@return` YARD-style on public methods (e.g., `BuildPipeline#run` documents `resolved_pins_file:`, `clones_dir:`, `config:` and their nil-semantics explicitly)
- Data-driven registry explanations (e.g., `lib/spm_cache/core/diagnostics.rb`)

**Cite the planning-doc ID.** v0.4.0 comments routinely cite the pitfall/requirement they defend against in parentheses — e.g., "(Pitfall 1)", "(Pitfall 15)", "(CACHE-01)", "(CACHE-02, 09-01)", "(06-05-SUMMARY.md)". Keep this: it lets a reader trace the comment to its phase evidence in `.planning/phases/`.

**No inline comments for obvious code.** Comments explain *why*, not *what*.

## Formatting

**Tool:** RuboCop ~> 1.50 (dev dependency, pre-commit hook)

**Configuration:** Default RuboCop rules. Run via:
- `make format` — runs `bundle exec rubocop --auto-correct`
- `.pre-commit-config.yaml` — rubocop v1.50.0 hook with `--auto-correct` on commit

**No custom `.rubocop.yml`** in repo root — uses default configuration (verified 2026-08-31).

## Module Design

**Autoloading over eager require:** `lib/spm_cache/main.rb` loads all files via `Dir.glob` sort for deterministic order, but top-level `lib/spm_cache.rb` uses `autoload` for the main entry points.

**No barrel files.** Each file is required individually by name or via `Main.load_all`.

**`Core::Diagnostics` uses a registry pattern:** checks are registered at load time via `register(name, fix_hint:, &block)`, enabling extensibility without editing the command class.

---

*Convention analysis: 2026-08-31*
