---
phase: v0.3.0-milestone
threats_open: 0
reviewed_date: 2026-08-11
reviewer: inline (gsd-ship degraded path — typed gsd-security-auditor unavailable)
---

# Security Review — spm-cache v0.3.0

## Scope

New code introduced in the v0.3.0 milestone:
- `lib/spm_cache/core/diagnostics.rb` — diagnostic check registry
- `lib/spm_cache/command/doctor.rb` — `doctor` command
- `lib/spm_cache/core/watcher.rb` — filesystem watch loop
- `lib/spm_cache/command/watch.rb` — `watch` command
- `lib/spm_cache/command/init.rb` — `init` wizard
- `.github/workflows/ci.yml` — test CI pipeline
- `action/action.yml` — GitHub Action (composite)

## Threat Model

### T1 — Command injection via doctor checks
**Surface:** `diagnostics.rb` shells out to `xcodebuild -version`, `swift --version`, `xcrun --find swift`, and `<companion_binary> --version` via `Core::Sh.capture_output`.
**Assessment:** All commands are **static literals** — no user input, no CLI args, no file content interpolated into the command string. The companion-binary path is derived from the constant `ROOT` (not user input).
**Status:** Not vulnerable.

### T2 — Credential leakage via init
**Surface:** `init.rb` accepts `--creds=PATH` (an S3 credentials **file path**) and writes it into `spm-cache.yml` under `remote.s3.creds`.
**Assessment:** Only the **path** is stored, never the credential contents — identical to the existing `storage/s3.rb` pattern. Credentials are read from the file at use-time and passed as env vars to `aws` (existing behavior). No new credential storage or logging introduced. `doctor`'s `remote_backend_connectivity` check reports only whether a backend is configured, never the URL or creds.
**Status:** Not vulnerable.

### T3 — Filesystem write via init
**Surface:** `init.rb` writes `spm-cache.yml`, `spm-cache.lock`, and appends to `.gitignore` in the project directory.
**Assessment:** All write paths are derived from the `--project` option (validated to exist as a directory) — no path traversal (no `..` handling needed since the target must exist on disk). `.gitignore` append is idempotent and bounded to the project dir.
**Status:** Not vulnerable.

### T4 — Watcher loop resource exhaustion
**Surface:** `watcher.rb` runs an unbounded poll loop (`sleep debounce`).
**Assessment:** The loop is bounded by `--debounce` (default 2s, user-configurable) and exits cleanly on SIGINT/SIGTERM. Continue-on-error prevents a failure cascade. No unbounded memory growth (signatures are small arrays).
**Status:** Not vulnerable.

### T5 — GitHub Action secret handling
**Surface:** `action/action.yml` receives `backend-url` (which may be `${{ secrets.SPM_CACHE_S3 }}`) and passes it to `spm-cache init`/`remote`.
**Assessment:** The Action does not log or echo the URL. It runs `gem install spm-cache` (pinned to latest; could be pinned to a version for reproducibility — noted as a minor hardening opportunity, not a vulnerability). Secrets flow through GitHub's standard env-var mechanism into the gem's existing (audited) storage code.
**Status:** Not vulnerable. (Minor: pin gem version in the Action for reproducibility — deferred.)

### T6 — CI workflow permissions
**Surface:** `ci.yml` declares `permissions: contents: read`.
**Assessment:** Least-privilege — the test pipeline needs only to read the repo and write run artifacts. No `GITHUB_TOKEN` write scope exposed. No third-party actions beyond `actions/checkout@v4`, `ruby/setup-ruby@v1`, `maxim-lobanov/setup-xcode@v1` (all widely-trusted, pinned to major).
**Status:** Not vulnerable.

## Summary

| Threat | Surface | Status |
|--------|---------|--------|
| T1 Command injection (doctor) | Static shell-out | Not vulnerable |
| T2 Credential leakage (init) | Path-only, no contents | Not vulnerable |
| T3 Filesystem write (init) | Validated project dir | Not vulnerable |
| T4 Watcher resource exhaustion | Bounded loop + debounce | Not vulnerable |
| T5 Action secret handling | No logging, env-var flow | Not vulnerable |
| T6 CI permissions | Least-privilege (read) | Not vulnerable |

**Open threats: 0**

## Hardening opportunities (non-blocking, deferred)
- Pin `gem install spm-cache` to a version in the GitHub Action for reproducibility
- Add SimpleCov to measure test coverage (deferred to a future phase)
