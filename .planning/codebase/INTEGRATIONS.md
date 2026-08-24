---
title: External Integrations
focus: tech
mapped_date: 2026-08-23
last_mapped_commit: f55b9b9a7dc73104b490ed76ec38549b242af03e
---

# External Integrations

**Analysis Date:** 2026-08-23

## APIs & External Services

**Xcode Toolchain (required):**
- `xcodebuild` — Invoked for building Swift packages into xcframeworks. Shell-outs in `lib/spm_cache/spm/build.rb` and `lib/spm_cache/spm/build_pipeline.rb`.
- `swift` CLI — Used for package resolution, build, and version detection. See `lib/spm_cache/core/diagnostics.rb` for version check.
- Xcode project manipulation via `xcodeproj` gem — edits `.pbxproj` files to swap SPM dependencies with local proxy packages. Implemented in `lib/spm_cache/xcodeproj/`.

**AWS S3 (optional remote backend):**
- SDK/Client: None (no AWS Ruby SDK). Uses `aws s3 sync` CLI via shell-out.
- Implementation: `lib/spm_cache/storage/s3.rb`
- Auth: JSON credentials file path passed via `--creds` flag or `creds:` key in `spm-cache.yml`. File contains `access_key_id` and `secret_access_key`.
- Environment vars injected at runtime: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` (set from credentials file, not env directly).
- Requires external `aws` CLI installed (`pip install awscli`).

**Git (remote backend):**
- SDK/Client: Ruby stdlib + `lib/spm_cache/core/git.rb` wrapper around `git` CLI.
- Implementation: `lib/spm_cache/storage/git.rb`
- Auth: Depends on Git's own credential handling (SSH keys, HTTPS tokens, etc.). No explicit auth config from spm-cache.
- Operations: `init`, `fetch --depth=1`, `checkout FETCH_HEAD`, `clean -f`, `add .`, `commit`, `push`.

## Data Storage

**Local Cache (primary):**
- Directory: `~/.spm-cache/` — Global binary artifact store.
- Implementation: `lib/spm_cache/core/config.rb` (`CACHE_DIR = File.expand_path("~/.spm-cache")`)
- Structure: Subdirectories per build configuration (e.g., `~/.spm-cache/debug/`, `~/.spm-cache/release/`). Contains prebuilt `.xcframework` bundles.
- Metadata: `spm-cache.lock` per-project — YAML file with enriched Package.resolved data. Managed by `lib/spm_cache/core/lockfile.rb`.

**Project Sandbox (local, per-project):**
- Directory: `<project>/spm-cache/`
- Implementation: `lib/spm_cache/core/config.rb` (`SANDBOX_DIR = "spm-cache"`)
- Subdirectories: `packages/proxy/` (generated proxy packages), `packages/umbrella/` (umbrella packages), `metadata/`, `xcconfigs/`, `local-packages/`.
- Git-ignored: Ensured by `spm-cache init` via `lib/spm_cache/command/init.rb` (`ensure_gitignore`).

**Remote Cache (optional):**
- Git backend: Any Git remote URL. Shallow clone of a single branch. See `lib/spm_cache/storage/git.rb`.
- S3 backend: Any S3 URI (`s3://bucket/path/`). Synced via AWS CLI. See `lib/spm_cache/storage/s3.rb`.
- Storage base class: `lib/spm_cache/storage/base.rb` (no-op defaults with warnings).
- Routing: `lib/spm_cache/storage.rb` selects `GitStorage`, `S3Storage`, or `Base` based on config.

**File Storage:**
- Local filesystem only — no cloud file storage. All artifacts stored in `~/.spm-cache/`.

**Caching:**
- None (no Redis, Memcached, etc.). The entire tool IS a caching system for SPM dependencies.

## Authentication & Identity

**Auth Provider:**
- None. No user authentication system.
- Remote backend auth is delegated: Git uses native Git credentials; S3 uses AWS credential file.

**GitHub Action Auth:**
- `secrets.TAP_REPO_TOKEN` — Personal access token for pushing to the Homebrew tap repository. See `.github/workflows/update-tap.yml`.

## Monitoring & Observability

**Error Tracking:**
- None. No Sentry, Rollbar, or similar.

**Logs:**
- Terminal output via `Core::UI` module (`lib/spm_cache/core/log.rb`).
- Live log with spinner: `lib/spm_cache/live_log.rb`.
- Build-phase cache visualization: `cachemap.js.template` + `cachemap.html.template` + `cachemap.style.css.template` in `lib/spm_cache/assets/templates/`.
- Doctor command diagnostics: `lib/spm_cache/command/doctor.rb` with `--json` flag for CI-consumable output.

## CI/CD & Deployment

**Hosting (gem):**
- RubyGems.org — `gem install spm-cache --no-document`. Published as a standard Ruby gem.

**Homebrew Tap:**
- Tap repository: `phuongddx/homebrew-spm-cache`.
- Formula: `Formula/spm-cache.rb` (auto-updated on release).
- Automation: `.github/workflows/update-tap.yml` triggers on GitHub release, computes SHA256 of release tarball, `sed`-updates the formula, commits and pushes.

**GitHub Action:**
- Composite action: `action/action.yml`.
- Name: `spm-cache-action`.
- Published as a GitHub Action for CI integration.
- Wraps the gem: installs via `gem install spm-cache --no-document`, runs `spm-cache init` + `spm-cache remote pull/push`; `sync` is pull+push composed by the action.
- Inputs: `command` (pull/push/sync), `backend` (git/s3), `backend-url`, `branch`, `config`, `creds`.

**CI Pipeline:**
- GitHub Actions — `.github/workflows/ci.yml`.
- Triggers: push to `main`, pull requests.
- Jobs:
  1. `ruby-tests` — Matrix: Ruby 3.1 / 3.2 / 3.3 on `macos-15`. Runs `bundle exec rspec`.
  2. `swift-tests` — Builds proxy tool (`make proxy.build`), runs `swift test` in `tools/spm-cache-proxy/`.
- Uses `actions/checkout@v5`, `ruby/setup-ruby@v1`, `maxim-lobanov/setup-xcode@v1`.

**Release Flow:**
 1. Tag release on GitHub (e.g., `v0.3.0`).
 2. Build and publish gem to RubyGems.org (manual or external automation).
 3. `.github/workflows/update-tap.yml` auto-updates Homebrew tap formula.

## Environment Configuration

**Required env vars:**
- None at runtime (all config via `spm-cache.yml` and CLI flags).

**Optional env vars (S3 backend):**
- `AWS_ACCESS_KEY_ID` — Set dynamically from `--creds` file by `lib/spm_cache/storage/s3.rb`, not from env.
- `AWS_SECRET_ACCESS_KEY` — Same as above.

**GitHub Actions secrets:**
- `TAP_REPO_TOKEN` — PAT for Homebrew tap push (used in `update-tap.yml`).

**Secrets location:**
- S3 credentials: JSON file on disk, path passed via `--creds` flag.
- Git credentials: Native Git credential store.
- CI secrets: GitHub repository secrets.

## Webhooks & Callbacks

**Incoming:**
- None.

**Outgoing:**
- None (no webhook calls). Remote operations are push/pull via Git or S3 sync.

## External Tool Dependencies

**Required:**
- `xcodebuild` — Xcode build tool (ships with Xcode).
- `swift` — Swift compiler (ships with Xcode).
- `git` — Version control (for git remote backend and general VCS).

**Optional:**
- `aws` CLI — AWS command-line tool (for S3 remote backend only). Validated at runtime in `lib/spm_cache/storage/s3.rb`.

**Watch command specifics:**
- `watch` uses Ruby stdlib mtime+size polling (no `listen` gem, no FSEvents bindings). See `lib/spm_cache/core/watcher.rb`. Debounce interval: 2 seconds. Watches `Package.resolved` and `project.pbxproj` only.

---

*Integration audit: 2026-08-23*
<!-- refreshed: 2026-08-23 -->
