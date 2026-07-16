# Phase 3: no fallback when umbrella `swift package resolve` fails (issue #3)

Status: DONE (2026-07-14) — `fallback_xcode_checkouts` (mtime-based selection) + escalated warning applied, 3 new specs added, `bundle exec rspec` green, real DerivedData never touched in tests.

## Context

- Issue: "No fallback when umbrella swift package resolve fails (all checkouts empty)"
- File: `lib/spm_cache/installer/build.rb`

## Root cause verification

Confirmed real at HEAD, exactly as reported.

- `lib/spm_cache/installer/build.rb:60-65` (`resolve_umbrella_checkouts`):
  ```ruby
  def resolve_umbrella_checkouts
    Core::UI.info "Resolving umbrella checkouts..."
    Core::Sh.run("swift package resolve", cwd: @config.umbrella_dir)
  rescue => e
    Core::UI.warn "Umbrella resolve failed: #{e.message}"
  end
  ```
  `rescue => e` swallows the error with only a warning — no fallback, matches issue verbatim.
- Confirmed `Core::Sh.run` (`lib/spm_cache/core/sh.rb:35-40`) does `raise GeneralError.new(...)` on nonzero exit, so any `swift package resolve` failure (dependency conflict, network, etc.) reaches this rescue.
- Confirmed downstream impact: `checkout_map` (`build.rb:69-87`) does `return {} unless File.directory?(checkouts_root)` — with a failed resolve, `.build/checkouts` under the umbrella either doesn't exist or is empty, so `checkout_map` returns `{}` for all targets.
- Confirmed `build_single_target` (`build.rb:106-111`) then hits `unless pkg_dir && File.directory?(pkg_dir)` → `Core::UI.warn "checkout not found for '#{target_name}'; skipping"` for every target, matching the issue's reported log spam exactly.

Issue's suggested fix (fall back to Xcode's `DerivedData/<Project>-*/SourcePackages/checkouts`) is directionally correct and addresses the real gap: there is currently zero fallback path in the code.

Related path the reporter didn't mention: `slug_for` (`build.rb:89-104`) and `checkout_map`'s directory-name matching assume checkout dir basenames equal the URL-derived slug. Verified directly against real DerivedData on the dev machine (2026-07-14) since the user has the actual `luz_epost_ios` project referenced in the original bug reports:

```
$ ls ~/Library/Developer/Xcode/DerivedData/ | grep -i luz
luz_epost_ios-fwdjgtmdobffppgzqgbipnfelirn
luz_epost_ios-gjvqucbyomvomwefiiubgawyhulc
$ ls .../luz_epost_ios-fwdjgtmdobffppgzqgbipnfelirn/SourcePackages/checkouts | head -5
abseil-cpp-binary
AEXML
Alamofire
AlignedCollectionViewFlowLayout
app-check
```

Confirms: (1) checkout basenames match the repo-basename slug convention used elsewhere (`Alamofire`, `AEXML` — same casing SwiftPM/`slug_for` expect), so the fallback's naming assumption is correct; (2) the `#{project_name}-*` glob pattern in the issue's suggested code is correct. **New finding not in the issue**: there were TWO matching DerivedData dirs for the same project (`-fwdjgtmdobffppgzqgbipnfelirn` mtime 12:45, `-gjvqucbyomvomwefiiubgawyhulc` mtime 14:04 — likely from workspace vs. project-level builds, or a stale one from a prior Xcode version/config). `Dir.glob(...).first` (issue's suggested code, and originally this plan's step 1) does NOT guarantee picking the newest — `Dir.glob` order is filesystem-dependent, not mtime-sorted. Picking the stale one could copy outdated/mismatched checkouts. Fix: sort by mtime descending, take the first (most recent).

## Implementation steps

1. Add `fallback_xcode_checkouts` per issue's suggested code, placed in `lib/spm_cache/installer/build.rb` as a private method alongside `resolve_umbrella_checkouts`. **Deviate from issue's snippet**: replace `Dir.glob(...).first` with `Dir.glob(...).max_by { |d| File.mtime(d) }` — verified necessary against real DerivedData (see root-cause verification above: multiple stale DerivedData dirs for the same project are common).
2. Call it from the `rescue` branch of `resolve_umbrella_checkouts`.
3. Improve on issue's suggested fix: after the fallback attempt, if `checkouts_root` (`.build/checkouts` under umbrella dir) is STILL empty, escalate the warning ("Umbrella resolve failed and no DerivedData checkouts found; all targets will be skipped") so the missing-framework outcome is clearly attributable, rather than the current 70x per-target "checkout not found" spam without an upstream explanation. This directly serves the report's own complaint about the noisy log output.
4. Derive `project_name` for the DerivedData glob from `@project_path` (available via `Installer#project_path` reader, `installer.rb:14`) rather than a `@project_path` ivar the issue's snippet assumes exists on `Installer::Build` directly — confirm attr is inherited (it is: `attr_reader :project_path` on base `Installer`, `installer.rb:14`).

## Tests

DerivedData naming verified against real `luz_epost_ios` project (see root-cause verification) — fixture below encodes that exact shape rather than a guessed one.

- Extend `spec/installer_build_spec.rb` (repo already stubs `resolve_umbrella_checkouts` there — `allow_any_instance_of(...).to receive(:resolve_umbrella_checkouts).and_return(nil)`, line 21). Add a **new** spec file or new `describe` block that does NOT stub this method, instead:
  - Stubs `Core::Sh.run` to raise `Core::GeneralError` for the `swift package resolve` call.
  - Creates a fake DerivedData tree under a temp `HOME` (or stub `File.expand_path("~/Library/Developer/Xcode/DerivedData")` via a small wrapper) shaped exactly like the verified real tree: `<project>-<hash>/SourcePackages/checkouts/<PackageName>/` (e.g. `luz_epost_ios-fwdjgtmdobffppgzqgbipnfelirn/SourcePackages/checkouts/Alamofire`).
  - **New case from the mtime finding**: create TWO matching `<project>-*` dirs with different `File.mtime` (touch older one first, sleep briefly or set mtime explicitly via `File.utime`), each with different checkout contents; assert the fallback copies from the newer one only (regression test for the `Dir.glob(...).first` → `.max_by { mtime }` fix).
  - Asserts `fallback_xcode_checkouts` copies them into `<umbrella_dir>/.build/checkouts/<pkg>`.
  - Asserts the escalated warning fires when no DerivedData match exists.
- Run: `bundle exec rspec spec/installer_build_spec.rb`.

## Risks / rollback

- Medium risk: reads from `~/Library/Developer/Xcode/DerivedData`, a real user directory — must be careful in tests to stub/redirect, never touch the actual dev machine's DerivedData in CI.
- `FileUtils.cp_r` of potentially large checkout directories (source trees for 70 dependencies) could be slow/disk-heavy; acceptable since it's a one-time fallback, but worth noting in code comment.
- Rollback: revert the added method + call site; no persisted state changes beyond the copied checkout dirs (harmless leftover files under sandbox `.build/checkouts`, already `rm_rf`'d by `Installer#recreate_dirs` on next run — `installer.rb:48-55`, note that only clears `sandbox_dir`, not umbrella's `.build`, so confirm `recreate_dirs` scope: `sandbox = @config.sandbox_dir; FileUtils.rm_rf(sandbox)` — `umbrella_dir` is under `sandbox_dir` per `config.rb:71-73`, so it IS cleared each run; fallback copies are transient, not accumulating garbage).
