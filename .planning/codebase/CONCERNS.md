---
title: Codebase Concerns
focus: concerns
mapped_date: 2026-08-10
last_mapped_commit: 5687b4641c1d7a36ef4fc99d59fdccf6dc09c5e0
---

# Codebase Concerns

A scan of `lib/` and `tools/spm-cache-proxy/Sources/` found **no `TODO`/`FIXME`/`HACK`/`XXX` markers** in source code. The concerns below are inferred from code structure, size, comment blocks, and history in `plans/reports/` and `docs/journals/`.

## Tech Debt & Complex Areas

- **`lib/spm_cache/spm/build_pipeline.rb` (919 LOC)** — the largest, most logic-dense file: per-destination build loop, scheme/module/header/shim resolution, forwarded-binary-target short-circuit, library-evolution flags. High surface area for regressions; a prime refactor candidate (extract scheme/module/header resolvers).
- **`lib/spm_cache/installer.rb` (578 LOC)** — orchestration with multiple responsibilities (verify, diff, dirs, config, lockfile, proxy, integration). The diff-detection + orphan-purge logic carries detailed inline comments referencing field-reported bugs (`#integrate_proxy_into_project` purge-vs-unlink), indicating accumulated edge-case handling worth isolating.
- **`lib/spm_cache/spm/build.rb` (417 LOC)** and **`lib/spm_cache/core/diff_detector.rb` (239 LOC)** — moderately complex; diff detector is the competitive "moat" (reads project directly vs separate manifest) and should stay well-tested.
- **Cross-process coupling** — Ruby invokes the Swift companion binary over shell (`Core::Sh`). The interface contract (lockfile JSON shape, flags) is implicit; a stale or version-mismatched binary can produce subtle proxy-generation bugs. The regression spec suite guards the known cases.

## Known Issues / Field Bugs (historical)

From `plans/reports/` and regression spec provenance (`spec/gen_proxy_field_regression_spec.rb` docblock), three classes of previously-fielded bugs are now guarded:
1. **Identity collision** — proxied wrapper folder must be `<slug>_proxy`, never bare `<slug>` (would collide with the real package's SwiftPM identity).
2. **Wrong product names** — multi-product packages (e.g. Realm) must be proxied under real product names, not the lockfile identity.
3. **Plugin-only packages** — must be skipped by both generators with original reference preserved, not given a broken proxy.

`docs/journals/` contains release/bug-fix logs (e.g. `0716-2300-v013-release-and-three-field-bug-plan.md`) — consult when investigating proxy/product/plugin behavior.

## Security Considerations

- **AWS credentials (S3 storage)** — `lib/spm_cache/storage/s3.rb` reads credentials from a JSON file (`--creds`) and injects `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` as env vars to the `aws` subprocess. Credentials are **not** written to disk or logs. Good practice; ensure the creds file path is gitignored and not logged. The tool requires local `awscli` (`validate_awscli!`).
- **Shell-out injection surface** — `Core::Sh.run` (`lib/spm_cache/core/sh.rb`) executes command strings via `Open3.popen3`/`capture3`. `Core::Git` (`lib/spm_cache/core/git.rb`) interpolates values (branch names, commit messages via `message.inspect`, paths) into git command strings. Branch/remote values originate from config (`spm-cache.yml`) and CLI args — **not network-sourced**, so injection risk is low, but interpolation into shell strings (rather than argument arrays) means untrusted config values could theoretically break out. Prefer array-form args for any future network-sourced inputs.
- **No secrets in CI** — `.github/workflows/update-tap.yml` updates a Homebrew tap; verify it uses GitHub secrets rather than embedded tokens (not deeply audited here).

## Performance Concerns

- **Build pipeline cost** — `spm-cache build` runs `xcodebuild` per destination (SDK × arch), which is inherently slow; `lib/spm_cache/core/parallel.rb` (`Parallel.map`/`each` via the `parallel` gem) parallelizes where possible.
- **Library evolution** — on by default (`LIBRARY_EVOLUTION=true`), adds Swift flags that can slow builds; `--no-library-evolution` disables it.
- **Fast path** — `DiffDetector` empty-diff short-circuit in `Installer::Use` avoids redundant proxy regeneration; critical to keep correct for performance.

## Fragile Areas

- **Manifest manipulation** — editing `project.pbxproj` via the `xcodeproj` gem (`lib/spm_cache/xcodeproj/`) to wire/unwire the proxy is the most fragile integration point; Xcodeproj object-graph quirks (e.g. dangling `XCSwiftPackageProductDependency` keeping refs alive) required explicit orphan-purge logic in `installer.rb`.
- **Proxy generation edge cases** — binary-forwarding targets (`copy_prebuilt_binary_target`), private Clang shims, public-header resolution, and plugin-only packages are all special-cased in `build_pipeline.rb` and the Swift `ProxyGenerator`.
- **Swift companion version drift** — Ruby and Swift must agree on lockfile JSON schema and flag semantics; no explicit version handshake.
- **No CI running the test suite** — only the tap-update workflow exists; regressions are caught locally, not pre-merge (see TESTING.md).
