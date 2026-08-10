---
title: Conventions
focus: quality
mapped_date: 2026-08-10
last_mapped_commit: 5687b4641c1d7a36ef4fc99d59fdccf6dc09c5e0
---

# Conventions

Documented standards live in `docs/code-standards.md`; this file summarizes and confirms them against the actual code.

## Ruby Style

- **`# frozen_string_literal: true`** at the top of every `.rb` file (verified across `lib/`).
- **Enforced by RuboCop** (`~> 1.50`); `make format` runs `bundle exec rubocop --auto-correct`. Config in `.rubocop`.
- **Module structure:** top-level `SPMCache`, nested by concern — `Core`, `SPM`, `Installer`, `Storage`, `Command`, `Swift`, `Utils`, `XcodeprojExt`.
- **Naming:** `CamelCase` classes/modules, `snake_case` methods/vars, `SCREAMING_SNAKE` constants.
- **Loading:** `lib/spm_cache/main.rb` `Main.load_all` recursively `require`s all `.rb` under `lib/spm_cache/` sorted for deterministic order. Module roots declare `autoload`.

## CLaide Command Pattern

- Root command `SPMCache::Command < CLAide::Command` (`lib/spm_cache/command.rb`); `self.abstract_command = true`, `self.command = "spm-cache"`, `default_subcommand = "use"`.
- Global options declared via `self.options`: `--sdk`, `--config`, `--log-dir`, `--no-merge-slices`, `--no-library-evolution`.
- Each subcommand class parses argv in `initialize(argv)` (`argv.option`, `argv.flag?`) and implements `run`.
- `Command::Options` / `BaseOptions` (`lib/spm_cache/command/base.rb`) hold defaults (`SDK="iphonesimulator"`, `CONFIG="debug"`, `MERGE_SLICES=true`, `LIBRARY_EVOLUTION=true`).

## Error Handling

- Custom error hierarchy in `lib/spm_cache/core/error.rb`: `Core::BaseError < StandardError`, `Core::GeneralError` (carries `exit_status`, default 1).
- Expected failures raise `Core::GeneralError.new(msg)`; `Installer` sections wrap in `Core::UI.section`.

## Shell-Out Convention

- **Always via `Core::Sh.run` / `capture_output` / `run!`** (`lib/spm_cache/core/sh.rb`) — `Open3.popen3` (live log) or `Open3.capture3`. Never backticks or `system()`.
- On non-zero exit, raises `GeneralError` with `failure_detail` (tail 60 lines of stdout+stderr, since `xcodebuild` reports to stdout).
- `Core::Git` (`lib/spm_cache/core/git.rb`) wraps git commands over the same helper.

## Logging & UI

- `Core::Log` (`lib/spm_cache/core/log.rb`) — structured logging to optional log dir.
- `Core::UI` — `info`, `section` (block-wrapped), warnings; backed by `tty-cursor`/`tty-screen`.
- `Core::LiveLog` (`lib/spm_cache/core/live_log.rb`) — streams subprocess output live during builds.

## Mixins & Refinements (no monkey-patching)

- Behavior via `include` (`Log`, `BaseOptions`, `Syntax::JSONRepresentable`, `Syntax::YAMLRepresentable`).
- Core extensions via `refine` (`HashExt`, `ParallelExt`, `SystemExt`) — avoids global monkey-patches. E.g. `ParallelExt` (`lib/spm_cache/core/parallel.rb`) adds `parallel_map`/`parallel_each` to Array.

## SPM Metadata Parsing

- `lib/spm_cache/core/syntax/` provides representable mixins: `json.rb`, `hash.rb`, `yml.rb`, `plist.rb`.
- Lockfile is JSON (`JSONRepresentable`); config is YAML (`YAMLRepresentable`).
- `Desc` parsing wraps `swift package describe --type json` output.

## Templates

- ERB templates under `lib/spm_cache/assets/templates/`; rendered via `Utils::Template.render(name, vars)` / `render_to` (`lib/spm_cache/utils/template.rb`).
- Template files named `{name}.template`.

## Swift Companion Conventions

- Tools version 6.0; structure `CLI/` (ArgumentParser commands) + `Core/` (domain).
- `PascalCase` types, `camelCase` members; protocols for abstraction (`CommandRunning`, `ProxyPackageProtocol`).
- Logging via `Logger` struct with Rainbow colors (`tools/spm-cache-proxy/Sources/Core/Log/`).
- Errors via `throws`/`try`; CLI exits via `ExitCode.failure`.
- One primary type per file.
