# Phase 1: spm-cache.yml never loaded (issue #1)

Status: DONE (2026-07-14) — `ensure_config_file` fix applied, `spec/installer_spec.rb` added, `bundle exec rspec` green.

## Context

- Issue: https://github.com/<repo>/issues/1 — "spm-cache.yml config file never loaded during build and use commands"
- Files: `lib/spm_cache/installer.rb`, `lib/spm_cache/core/config.rb`

## Root cause verification

Confirmed real at HEAD.

- `lib/spm_cache/installer.rb:57-63` (`ensure_config_file`): only copies the template if missing, never calls `@config.load`:
  ```ruby
  def ensure_config_file
    config_path = File.join(@config.project_dir, "spm-cache.yml")
    return if File.exist?(config_path)
    template_path = SPMCache::LIBEXEC.join("assets", "templates", "spm-cache.yml.template")
    FileUtils.cp(template_path.to_s, config_path) if template_path.exist?
  end
  ```
- `lib/spm_cache/core/config.rb:30-34` (`initialize`): `Config` singleton starts with `@raw = DEFAULT_CONFIG.dup` and never reads YAML unless `load` is explicitly called.
- Only two call sites call `config.load` in the whole codebase:
  - `lib/spm_cache/command/remote.rb:13`
  - `lib/spm_cache/command/off.rb:18`
  (verified via `grep -rn "config.load" lib/`)
- `Installer#perform_install` (`installer.rb:26-38`) calls `ensure_config_file` but not `@config.load` anywhere in the chain used by `build`/`use` commands (`lib/spm_cache/command/build.rb`, `lib/spm_cache/command/use.rb` — neither references `Config` at all).
- Consequence confirmed by tracing consumers: `Installer::Build#build_single_target` (`lib/spm_cache/installer/build.rb:106-130`) calls `@config.ignore_build_errors?`, and `resolve_destinations` (same file, ~132-142) calls `@config.default_sdk` — both silently return `DEFAULT_CONFIG` values (`false`, `"iphonesimulator"`) regardless of what's in `spm-cache.yml`.

Issue's suggested fix is correct: call `@config.load(config_path)` unconditionally in `ensure_config_file`, after the template-copy branch.

One nuance the issue missed: `off.rb`/`remote.rb` call `config.load` with **no argument**, relying on `@config_path` set at `Config#initialize` time (`Dir.pwd/spm-cache.yml`, `config.rb:31-32`). That happens to equal the project dir only because CLI commands assume cwd == project root (`find_project` uses `Dir.glob("*.xcodeproj")`, e.g. `command/build.rb:34-36`). `Installer#initialize` reassigns `@config.project_dir` explicitly (`installer.rb:20`) but does NOT update `@config_path` to match. Passing the explicit `config_path` (as issue's suggested fix does) sidesteps this latent fragility — do it that way, not the no-arg `config.load` pattern used elsewhere.

## Implementation steps

1. In `lib/spm_cache/installer.rb`, change `ensure_config_file` to:
   ```ruby
   def ensure_config_file
     config_path = File.join(@config.project_dir, "spm-cache.yml")
     unless File.exist?(config_path)
       template_path = SPMCache::LIBEXEC.join("assets", "templates", "spm-cache.yml.template")
       FileUtils.cp(template_path.to_s, config_path) if template_path.exist?
     end
     @config.load(config_path)
   end
   ```
2. No change needed to `Config#load` itself — it already merges `DEFAULT_CONFIG.merge(YAML.safe_load(...))` (`config.rb:47-53`), handles missing file gracefully (`File.exist?` guard already covers case where template copy failed).

## Tests

- New spec (or extend `spec/config_spec.rb` / add `spec/installer_spec.rb`, no existing file for `Installer` base class — repo convention is one `_spec.rb` per class per `spec/` listing):
  - Given a temp project dir with a `spm-cache.yml` containing `ignore_build_errors: true`, run `Installer#send(:ensure_config_file)` (or invoke through a minimal `Installer` instance) and assert `Config.instance.ignore_build_errors?` is `true` afterward.
  - Given no `spm-cache.yml`, assert template gets copied AND `Config.instance` reflects the template's defaults (not just `DEFAULT_CONFIG`).
- Existing `spec/installer_build_spec.rb` stubs `perform_install` entirely (`allow_any_instance_of(SPMCache::Installer).to receive(:perform_install)...`), so it does not exercise `ensure_config_file` — safe from regressions but also means it gives no coverage; the new spec above is required.
- Run: `bundle exec rspec spec/config_spec.rb spec/installer_build_spec.rb` plus new spec.

## Risks / rollback

- Low risk: purely additive (one method call). Rollback = revert the one-line addition.
- Watch for: any code path currently relying on `Config` defaults regardless of YAML content (grepped call sites of `ignore_build_errors?`, `default_sdk`, `ignore_list`, `keep_pkgs_in_project?` — all in `installer/build.rb`, `spm/pkg/proxy.rb`, `storage/base.rb`; none appear to depend on defaults intentionally).
