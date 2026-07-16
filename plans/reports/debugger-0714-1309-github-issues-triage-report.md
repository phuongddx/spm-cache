# GitHub issues #1-#4 triage report (spm-cache)

Investigated at HEAD (commit `1952b3c`, main). Fix plan: `plans/0714-1309-fix-github-issues-1-4/plan.md`.

## Summary table

| # | Title | Verified? | Fixed at HEAD? | Suggested fix quality |
|---|---|---|---|---|
| 1 | spm-cache.yml never loaded | YES | No | Correct, minor nuance noted |
| 2 | revision pins -> `from: 0.1.0` | YES | No | Correct but wrong SwiftPM syntax label in suggestion |
| 3 | no fallback on umbrella resolve fail | YES | No | Workable, missing escalated-warning improvement |
| 4 | 47/62 targets fail (scheme resolution) | YES | No | Workable but reinvents data the repo already has |

All 4 introduced/still-present at HEAD. #2/#3/#4 code paths (`build_pipeline.rb`, `installer/build.rb` body) were newly added in commit `1952b3c` ("wire selective caching... real build pipeline") — i.e. this is fresh, untested code, not a regression of older working code. #1 predates that commit (present since initial `a9739dd`).

## #1 — config never loaded

`lib/spm_cache/installer.rb:57-63` `ensure_config_file` only copies template, never calls `@config.load`. Only 2 call sites in whole repo call `config.load`: `command/remote.rb:13`, `command/off.rb:18` (grep confirmed) — neither is in the `build`/`use` path. `Config#initialize` (`core/config.rb:30-34`) starts with `DEFAULT_CONFIG` only. Downstream consumers confirmed broken: `installer/build.rb` calls `@config.ignore_build_errors?` (line ~124) and `@config.default_sdk` (~133) — both silently ignore YAML.

Suggested fix correct. Nuance: use `@config.load(config_path)` with explicit path, not the no-arg `config.load` pattern used in `off.rb`/`remote.rb` — that pattern relies on `@config_path` set at singleton-init time (`Dir.pwd`), which only coincidentally matches `project_dir` in CLI usage; `Installer#initialize` reassigns `project_dir` but not `config_path`, so explicit path avoids latent fragility.

## #2 — revision-only pins default to `from: "0.1.0"`

`tools/spm-cache-proxy/Sources/Core/Lockfile.swift:4-9` `PackageRef` has no `revision` field. `versionRequirement` (`:30-41`) always returns `from: "0.1.0"` when `version` is nil, no revision branch. `init(from dict:)` (`:58-72`) never reads `dict["revision"]` — field silently dropped on ingestion. `UmbrellaGenerator.swift:26-29` confirms this string goes straight into generated `Package.swift`.

Important correction to issue's own claim: the issue says "the Ruby lockfile generator already stores revision in the JSON" implying only the Swift side is behind — verified TRUE. `lib/spm_cache/installer.rb:95` writes `"revision" => pin.dig("state","revision")`, and Ruby's own `Core::Lockfile::Pkg` (`core/lockfile.rb:15,28,50`) reads/writes it fine. So bug is isolated exactly where the issue says: Swift `PackageRef` discarding a field that's already on disk.

Suggested fix mostly correct but has a syntax bug: SwiftPM dependency label for revision pins is `revision:`, not a bare `.revision(...)` call in that argument position — i.e. correct form is `.package(url: url, revision: "<hash>")`. The issue's suggested code `return ".revision(\"\(rev)\")"` would need the interpolation `.package(url: \"\(url)\", \(req))` to become `.package(url: "...", .revision("hash"))` which is NOT valid SwiftPM syntax for `.package(url:)` dependency declarations. Must emit `"revision: \"\(rev)\""` instead. Flagged as implementation detail to get right, not a blocker to the root-cause diagnosis.

Also: `PackageRef` has same missing-field bug for `branch` pins (Ruby side already tracks `@branch`) — not in the issue's repro but same class, noted as follow-on.

No Swift test infra exists (`tools/spm-cache-proxy/Package.swift` has zero `.testTarget`) — testing strategy needs a decision (add XCTest target vs. scripted CLI smoke test), flagged as open question.

## #3 — no fallback on umbrella resolve failure

`lib/spm_cache/installer/build.rb:60-65` `resolve_umbrella_checkouts` — `rescue => e; Core::UI.warn(...)`, nothing else, matches issue verbatim. Confirmed `Core::Sh.run` (`core/sh.rb:35-40`) raises `GeneralError` on nonzero exit — real failures do reach this rescue. Confirmed cascade: `checkout_map` (`build.rb:69-87`) returns `{}` when `.build/checkouts` missing/empty → `build_single_target` (`build.rb:106-111`) warns "checkout not found... skipping" per target — matches the reported 70x log spam.

Suggested fix (fallback to Xcode DerivedData checkouts) is directionally sound — there is currently zero fallback of any kind. Improvement recommended: escalate to a clear top-level warning if fallback ALSO fails, instead of only the per-target spam (serves the issue's own complaint about unclear failure mode). Not independently verified against a real DerivedData tree (sandboxed env has none) — checkout dir naming convention assumed compatible with SwiftPM's own, should be spot-checked during implementation.

## #4 — 47/62 targets fail on scheme resolution

`lib/spm_cache/spm/build_pipeline.rb:33-39` confirmed: first attempt always uses raw package identity as both `module_name` and `scheme`. `resolve_scheme_fallback` (`:132-139`) is verbatim what issue quotes — `schemes.find { casecmp } || schemes.first`, arbitrary pick confirmed. `lib/spm_cache/spm/build.rb:35` confirms scheme flows straight into `xcodebuild -scheme`.

Issue's suggested fix (parse `xcodebuild -list -json`, prefer library-type schemes) has a real gap: `xcodebuild -list -json` does NOT report which scheme builds a library vs. test vs. executable — that data isn't in `-list` output at all (would need per-scheme `-showBuildSettings`, N+1 slow calls). Found a better existing path the reporter missed: `SPMCache::SPM::Desc::Description` (`lib/spm_cache/spm/desc/desc.rb`, backed by `swift package describe --type json`) already returns `products` with authoritative `name` + `type` (`library`/`executable`) fields, and is already used elsewhere (`lib/spm_cache/spm/pkg/base.rb:28`) but never wired into `build_pipeline.rb`. Since Xcode's SPM-generated schemes map 1:1 to product names, this directly resolves all three of the issue's named failure cases (Alamofire identity/PascalCase mismatch, swift-protobuf's `Conformance` being an executable not the library, FSPagerView casing) without string-heuristic guesswork. Recommend using `Desc::Description` as primary scheme source, keep `xcodebuild -list` heuristic only as last-resort fallback for non-describable packages.

Existing `spec/build_pipeline_spec.rb:60-70` covers the current fallback-raises-when-nothing-works contract — any fix must preserve it.

## Dependency ordering rationale

1 -> 2 -> 3 -> 4, see `plans/0714-1309-fix-github-issues-1-4/plan.md` for full reasoning. Short version: #1 is foundational/independent; #2 is the field-observed root cause that triggers #3's symptom; #3 is a general safety net needed regardless of #2; #4 is unit-testable independently via stubs but needs #2/#3 fixed for real end-to-end validation (checkouts must exist to reach the scheme-resolution code path in a live repro).

## Unresolved questions

- #2: Swift test strategy — add XCTest target (new infra) or scripted CLI smoke test (KISS, no precedent either way)? Needs user decision.
- #3: DerivedData checkout naming compatibility not verified against a real Xcode-resolved tree in this environment — spot check during implementation.

Status: DONE
Summary: All 4 issues verified as real, unfixed root causes at HEAD with file:line evidence; consolidated 4-phase fix plan written with dependency ordering, implementation steps, and test strategy per phase, plus 2 stronger-than-reported fixes identified (Desc::Description reuse for #4, revision: label correction for #2).
Concerns/Blockers: none blocking; 2 open questions noted above need user input before implementation starts.
