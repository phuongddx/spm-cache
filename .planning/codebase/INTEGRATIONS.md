---
title: External Integrations
focus: tech
mapped_date: 2026-08-31
last_mapped_commit: fdb3a70abe81852ec9310a3ff410341a4adcfa0c
---

# External Integrations

**Analysis Date:** 2026-08-31

## APIs & External Services

**Xcode Toolchain (required):**
- `xcodebuild` — Invoked for building Swift packages into xcframeworks. Shell-outs in `lib/spm_cache/spm/build.rb` (`build_command`: `xcodebuild build` with `-scheme`, `-destination`, `-derivedDataPath`, `CODE_SIGNING_ALLOWED=NO`, library-evolution flags) and `lib/spm_cache/spm/build_pipeline.rb`. Since v0.4.0, builds pass `-clonedSourcePackagesDirPath '<sandbox>/packages/clones'` (`Config#clones_dir`) so N per-package builds share one cloned host checkout instead of each cloning the whole graph. `-onlyUsePackageVersionsFromResolvedFile` is deliberately NOT added (D-02, Phase 7).
- `swift` CLI — Used for package resolution, build, and version detection. See `lib/spm_cache/core/diagnostics.rb` (`swift_version` check expects Swift 6.0+).
- Xcode project manipulation via `xcodeproj` gem — edits `.pbxproj` files to swap SPM dependencies with local proxy packages. Implemented in `lib/spm_cache/xcodeproj/`.

**Host SPM Graph (required, v0.4.0):**
- Canonical `Package.resolved` locator — `lib/spm_cache/core/package_resolved.rb`. Tier 1: exact path `<project>.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`; tier 2: workspace glob; tier 3: filtered recursive search; tier 4: filtered parent-directory search (DiffDetector only). mtime is only a tie-break inside a tier.
- `SPM::ResolvedGraph` — `lib/spm_cache/spm/resolved_graph.rb`. Parses the host resolution (version + revision pins) and atomically writes resolved files (Tempfile-then-rename).
- Checkout seeding — `lib/spm_cache/spm/checkout_resolver.rb` seeds the shared clone dir (`<project>/spm-cache/packages/clones/`) to match the host graph before the first `swift package describe`; restored via ensure-region on any failure (`lib/spm_cache/spm/build_pipeline.rb`).
- Concurrency — process-level blocking flock on `<project>/.spm-cache-build.lock`, shared by `Installer::Build` (held across the whole build loop) and `Installer::Use`'s non-fast-path branch.

**AWS S3 (optional remote backend):**
- SDK/Client: None (no AWS Ruby SDK). Uses `aws s3 sync` CLI via shell-out.
- Implementation: `lib/spm_cache/storage/s3.rb`
- Auth: JSON credentials file path passed via `--creds` flag or `creds:` key in `spm-cache.yml`. File contains `access_key_id` and `secret_access_key`.
- Environment vars injected at runtime: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` (set from credentials file, not env directly).
- Operations: pull `aws s3 sync <uri>/ <cache>/ --exact-timestamps`; push `aws s3 sync <cache>/ <uri>/ --delete`.
- Requires external `aws` CLI installed (validated via `which`; error hint `pip install awscli`).

**Git (remote backend):**
- SDK/Client: Ruby stdlib + `lib/spm_cache/core/git.rb` wrapper around `git` CLI.
- Implementation: `lib/spm_cache/storage/git.rb`
- Auth: Depends on Git's own credential handling (SSH keys, HTTPS tokens, etc.). No explicit auth config from spm-cache.
- Operations: `init`, `ensure_remote`, `fetch --depth=1`, `checkout FETCH_HEAD`, `clean -f`, `add .`, `commit` ("No changes to push" on empty diff), `push`.

## Data Storage

**Local Cache (primary):**
- Directory: `~/.spm-cache/<config>/` — Global binary artifact store, one subdirectory per build configuration (`debug`/`release`), via `Config#cache_dir(config)` in `lib/spm_cache/core/config.rb`.
- Entries: prebuilt `<name>.xcframework` bundles plus JSON sidecars:
  - `<name>.xcframework.provenance.json` — fidelity status (`host-pinned` / `not-graph-pinned` / computed drift status), realized pin map, build config, destinations. Written atomically by `write_provenance_sidecar` in `lib/spm_cache/spm/build_pipeline.rb` (no absolute paths/timestamps — sidecars travel through shared backends). Surfaced by `spm-cache cache list` via `fidelity_status_for` (`lib/spm_cache/command/cache/list.rb`).
  - `<name>.xcframework.shims.json` — companion private-Clang-shim binary names wired into the same `.library` product (`lib/spm_cache/spm/build_pipeline.rb`).
  - Orphaned sidecars are swept by `spm-cache cache clean` (`lib/spm_cache/command/cache/clean.rb`) — a sidecar must never outlive its `.xcframework`.
- Metadata: `spm-cache.lock` per-project — YAML with enriched Package.resolved data, reconciled from the host graph on every non-fast-path run (`Installer#reconcile_lockfile_from_host_graph` in `lib/spm_cache/installer.rb`), guarded by a `spm_cache_version` stamp (missing stamp = stale). Managed by `lib/spm_cache/core/lockfile.rb`.

**Project Sandbox (local, per-project):**
- Directory: `<project>/spm-cache/`
- Implementation: `lib/spm_cache/core/config.rb` (`SANDBOX_DIR = "spm-cache"`)
- Subdirectories: `packages/proxy/` (generated proxy packages), `packages/umbrella/` (umbrella packages), `packages/clones/` (shared host-faithful SPM checkout clones, v0.4.0), `metadata/`, `xcconfigs/`, `local-packages/`.
- Sibling lock file: `<project>/.spm-cache-build.lock` — kept OUTSIDE the sandbox by construction so `recreate_dirs`' `rm_rf` can never delete the path a live flock holds (Pitfall 15).
- Git-ignored: Ensured by `spm-cache init` via `lib/spm_cache/command/init.rb` (`ensure_gitignore`).

**Remote Cache (optional):**
- Git backend: Any Git remote URL. Shallow clone of a single branch. See `lib/spm_cache/storage/git.rb`.
- S3 backend: Any S3 URI (`s3://bucket/path/`). Synced via AWS CLI. See `lib/spm_cache/storage/s3.rb`.
- Storage base class: `lib/spm_cache/storage/base.rb` (no-op defaults with warnings).
- Routing: `lib/spm_cache/storage.rb` selects `GitStorage`, `S3Storage`, or `Base` based on config.

**File Storage:**
- Local filesystem only — no cloud file storage. All artifacts stored in `~/.spm-cache/`.

**Caching:**
- None (no Redis, Memcached, etc.). The entire tool IS a caching system for SPM dependencies. Cache identity is provenance-aware (v0.4.0): a cached `.xcframework` hit is validated against the host graph pins, and the lockfile `spm_cache_version` stamp forces re-derivation after tool upgrades.

## Authentication & Identity

**Auth Provider:**
- None. No user authentication system.
- Remote backend auth is delegated: Git uses native Git credentials; S3 uses AWS credential file.

**GitHub Action Auth (Homebrew tap publish):**
- `secrets.TAP_DEPLOY_KEY` — the SOLE repo secret: a write-access SSH deploy key on `phuongddx/homebrew-spm-cache` (registered via API 2026-08-30, `read_only: false`). Used by `.github/workflows/update-tap.yml` as `ssh-key:` on the tap checkout; the checkout step is pinned by full SHA `actions/checkout@fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09` (v5.1.0) because it receives write credentials.
- The old classic-PAT secret `TAP_REPO_TOKEN` was deleted (2026-08-30). `TAP_APP_ID`/`TAP_APP_PRIVATE_KEY` never existed (GitHub App route abandoned before creation).

## Monitoring & Observability

**Error Tracking:**
- None. No Sentry, Rollbar, or similar.

**Logs:**
- Terminal output via `Core::UI` module (`lib/spm_cache/core/log.rb`).
- Live log with spinner: `lib/spm_cache/live_log.rb`.
- Build-phase cache visualization: `cachemap.js.template` + `cachemap.html.template` + `cachemap.style.css.template` in `lib/spm_cache/assets/templates/`.
- Doctor command diagnostics: `lib/spm_cache/command/doctor.rb` with `--json` flag for CI-consumable output. Read-only checks shell out to `xcodebuild -version`, `swift --version`, `git`, `aws`; covers toolchain versions, cache-dir health, remote-backend config, Swift companion binary.

## CI/CD & Deployment

**Hosting (gem):**
- NOT on RubyGems. `gem build`/`gem push` explicitly deferred by user decision (no RubyGems credentials on this machine; `gem signin` needed first — see `.planning/STATE.md`). Consequence: the composite action's `gem install spm-cache` step cannot resolve externally until publish.

**Homebrew Tap (ONLY distribution channel — v0.4.0 live):**
- Tap repository: `phuongddx/homebrew-spm-cache`.
- Formula: `Formula/spm-cache.rb` (auto-updated on release; pins the release's attached `.tar.gz` asset with a byte-stable sha256; wrapper execs keg-only `ruby@3.3`).
- Install: `brew install phuongddx/spm-cache/spm-cache` (serves 0.4.0 as of 2026-08-31; tap HEAD `47a0600`).
- Automation: `.github/workflows/update-tap.yml` — REWRITTEN in Phase 11 (commit `9ab76ea` lineage). Two triggers: `release: published` and `workflow_dispatch` with a `tag` input (re-publish/retry). Concurrency group `update-tap` (no cancel-in-progress), `permissions: contents: read`. Two jobs:
  1. `update-tap` (ubuntu-latest) — strict-semver tag gate (`^v[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$`); `gh release view` existence assertion on dispatch; `TAP_DEPLOY_KEY` presence guard; integrity-gated download (`curl -fL --retry 3 --retry-delay 2`, non-empty check, `1f8b` gzip magic-byte check BEFORE sha256 is computed); prefers an attached `.tar.gz` release asset (byte-stable) with a loud warning when falling back to GitHub's auto-generated tag archive; tap checkout via deploy key (SHA-pinned action); anchored exactly-one `url`/`sha256` edits (2-space-indented regexes, sed metacharacter escaping, `grep -Fqx` full-line postconditions); idempotent no-diff branch with `::notice::`; commit as `github-actions[bot]` and push.
  2. `verify-publish` (macos-latest) — `brew install phuongddx/spm-cache/spm-cache`, then asserts `spm-cache --version` output equals the released version (`--version` intercept in the CLI makes this assertable; pre-v0.4.0 tarballs failed red here by design — fail-first proof).
- Live-proven: first real formula-changing push `ee27cc7` (run 33354678763, 2026-08-31); v0.4.0 cut went fully green end-to-end (run 33377121583 — update-tap hashed the attached `spm-cache-0.4.0.tar.gz`, pushed tap `47a0600`, verify asserted `installed: 0.4.0`).

**GitHub Action:**
- Composite action source: `action/action.yml` (+ `action/README.md`) in this repo.
- Published as `phuongddx/spm-cache-action@v1` in its own repo; `v1` was force-moved to the corrected commit `7114ba6` (2026-08-27 resync, carrying the Phase 4 F1 fix `--config=` → `--default-config=`).
- Wraps the gem: `ruby/setup-ruby@v1` (Ruby 3.2) → `gem install spm-cache --no-document` (no-op until the gem is published) → `spm-cache init` (configures backend) → `spm-cache remote pull/push`; `sync` is pull+push composed by the action.
- Inputs: `command` (pull/push/sync), `backend` (git/s3), `backend-url`, `branch`, `config`, `creds`.
- Smoke CI: a `workflow_dispatch`-only smoke workflow was added (release-checklist item 6) to the **action repo**, not this repo — it cannot pass until the gem is on RubyGems, so no `smoke.yml` exists in `.github/workflows/` here (verified: only `ci.yml` and `update-tap.yml` are tracked).

**CI Pipeline:**
- GitHub Actions — `.github/workflows/ci.yml`.
- Triggers: push to `main`, pull requests. Concurrency group `ci-<ref>` with cancel-in-progress; `permissions: contents: read`.
- Jobs:
  1. `ruby-tests` — Matrix: Ruby 3.1 / 3.2 / 3.3 on `macos-15`. Xcode 16 via `maxim-lobanov/setup-xcode@v1`, `ruby/setup-ruby@v1` with `bundler-cache: true`, `make proxy.build`, then `bundle exec rspec`.
  2. `swift-tests` — `swift test` in `tools/spm-cache-proxy/` on `macos-15` with Xcode 16.
- Uses `actions/checkout@v5`, `ruby/setup-ruby@v1`, `maxim-lobanov/setup-xcode@v1`.

**Release Flow (as of v0.4.0):**
 1. Bump `VERSION` AND `tools/spm-cache-proxy/Sources/CLI.swift` `proxyVersion` in lockstep (spec-enforced).
 2. Tag `v<semver>`, publish the GitHub release with an attached `spm-cache-<ver>.tar.gz` (git archive from the tag — byte-stable, preferred by the workflow over the auto-archive).
 3. `.github/workflows/update-tap.yml` updates the tap formula and verifies the install (`verify-publish`). Gem publish to RubyGems remains a deferred manual step.

## Environment Configuration

**Required env vars:**
- None at runtime (all config via `spm-cache.yml` and CLI flags).

**Optional env vars (S3 backend):**
- `AWS_ACCESS_KEY_ID` — Set dynamically from `--creds` file by `lib/spm_cache/storage/s3.rb`, not from env.
- `AWS_SECRET_ACCESS_KEY` — Same as above.

**GitHub Actions secrets:**
- `TAP_DEPLOY_KEY` — write-access deploy key on `phuongddx/homebrew-spm-cache` (sole secret; used in `update-tap.yml`).

**Secrets location:**
- S3 credentials: JSON file on disk, path passed via `--creds` flag.
- Git credentials: Native Git credential store.
- CI secrets: GitHub repository secrets (`TAP_DEPLOY_KEY` only).

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
- `watch` uses Ruby stdlib mtime+size polling (no `listen` gem, no FSEvents bindings). See `lib/spm_cache/core/watcher.rb`. Debounce: `DEFAULT_DEBOUNCE = 2` seconds. Watches `Package.resolved` and `project.pbxproj` only. Continue-on-error loop (transient regeneration failures log and continue; only fatal conditions exit non-zero); SIGINT/SIGTERM flush a pending event and exit 0; `watch --once` runs a single sync-and-exit.

---

*Integration audit: 2026-08-31*
<!-- refreshed: 2026-08-31 -->
