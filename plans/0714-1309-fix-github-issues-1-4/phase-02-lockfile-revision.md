# Phase 2: revision-only pins default to `from: "0.1.0"` (issue #2)

Status: DONE (2026-07-14) — `PackageRef.revision` + fixed `versionRequirement` applied, Swift Testing target added (`tools/spm-cache-proxy/Tests/`), 4/4 tests green, `swift build` green.

## Context

- Issue: "Revision-based package pins default to from: \"0.1.0\", breaking umbrella resolve"
- File: `tools/spm-cache-proxy/Sources/Core/Lockfile.swift` (Swift proxy tool, separate SwiftPM package under `tools/spm-cache-proxy/`)

## Root cause verification

Confirmed real at HEAD, exactly as reported.

- `Sources/Core/Lockfile.swift:4-9` — `PackageRef` has no `revision` field:
  ```swift
  struct PackageRef: Codable {
      let repositoryURL: String?
      let pathFromRoot: String?
      let name: String?
      let productName: String?
      let version: String?
  ```
- `Sources/Core/Lockfile.swift:30-41` — `versionRequirement` falls back to `from: "0.1.0"` whenever `version` is nil/empty, with no revision branch:
  ```swift
  var versionRequirement: String {
      guard let version = version, !version.isEmpty else {
          return "from: \"0.1.0\""
      }
      ...
  }
  ```
- `Sources/Core/Lockfile.swift:58-72` (`init(from dict:)`) — never reads `dict["revision"]`, confirming the field is silently dropped on JSON ingestion, not just absent from the struct.
- `Sources/Core/Generator/UmbrellaGenerator.swift:26-29` confirms `versionRequirement` is what actually goes into the generated `Package.swift`:
  ```swift
  let req = pkg.versionRequirement
  dependencies.append(".package(url: \"\(url)\", \(req))")
  ```
- Cross-checked the Ruby side does NOT have this bug: `lib/spm_cache/installer.rb:95` already writes `"revision" => pin.dig("state", "revision")` into the on-disk lockfile JSON, and `lib/spm_cache/core/lockfile.rb:15,28,50` (`Core::Lockfile::Pkg`) already reads/writes `revision` correctly. So the JSON on disk **does** carry the revision — it's the Swift consumer (`PackageRef.init(from:)`) that discards it. This is exactly what the issue's "Additionally" note claims; verified true, not "the Ruby lockfile generator" being at fault at all.

Issue's suggested fix (add `revision: String?`, parse it, prefer `.revision("<hash>")` over the `0.1.0` fallback) is correct and complete for the reported case.

One gap the issue missed: `.revision(...)` in `Package.swift` **requires** the dependency to be declared without a version requirement string in the same `.package(url:)` call format — worth double-checking the exact SwiftPM syntax is `.package(url: "...", revision: "<hash>")`, i.e. the generator's fix must emit `revision: "\(rev)"` (label `revision:`), not `.revision("<hash>")` bare as literal text inside the same argument position as `from:`. The issue's own suggested code (`return ".revision(\"\(rev)\")"`) would need `UmbrellaGenerator.swift:28` to interpolate it as `.package(url: "\(url)", \(req))` — check the label matches SwiftPM's `Package.Dependency` API: correct form is `.package(url: url, revision: rev)`, so `versionRequirement`-equivalent string should be `"revision: \"\(rev)\""`, not `".revision(...)"`. Get this right during implementation — a wrong label will just move the same resolve failure to a Package.swift compile error.

Also worth handling: revision pins where `branch` is set instead (`Lockfile::Pkg` in Ruby already tracks `@branch`, `lockfile.rb:15,27`) — the Swift `PackageRef` also lacks a `branch` field. Not in the issue's repro, but same class of bug; flag as a follow-on if the user wants full parity (`.package(url:, branch:)`).

## Implementation steps

1. Add `let revision: String?` to `PackageRef` (`Lockfile.swift:9`).
2. In `init(from dict:)` (`Lockfile.swift:58-69`), add `revision: pkgDict["revision"] as? String`.
3. Update `versionRequirement` (or introduce a separate `dependencyRequirement` computed prop used by `UmbrellaGenerator`) to emit the correctly-labeled SwiftPM requirement:
   ```swift
   var versionRequirement: String {
       if let version = version, !version.isEmpty {
           return "from: \"\(version)\""
       }
       if let rev = revision, !rev.isEmpty {
           return "revision: \"\(rev)\""
       }
       return "from: \"0.1.0\""
   }
   ```
4. Leave the `"0.1.0"` string as absolute last resort (no version, no revision, no branch) — matches issue's acceptance of it as a fallback-of-last-resort, just no longer the first thing tried.

## Tests — DECIDED: add a Swift Testing target (not XCTest, not CLI-only smoke test)

Resolved (was an open question; decided 2026-07-14 after reviewing axiom-testing skill guidance):

- `tools/spm-cache-proxy/Package.swift` currently has **no test target** (only `.executableTarget`). `Sources/CLI.swift:20` uses `@main` (not a bare `main.swift`), so the executable target CAN be `@testable import`ed directly — no restructuring into a library target needed.
- Add `.testTarget(name: "spm-cache-proxyTests", dependencies: ["spm-cache-proxy"])` to `Package.swift`, and write **Swift Testing** (`@Test`/`#expect`, not XCTest) cases directly against `Lockfile.PackageRef.versionRequirement`:
  - version-only → `from: "x.y.z"`
  - revision-only → `revision: "<hash>"` (this is the case that would have caught the issue's own `.revision("<hash>")` label bug at compile time)
  - neither → `from: "0.1.0"` fallback
  - both set → confirm version wins (existing precedence, unchanged)
- Why this over the alternatives (KISS CLI-smoke-test and XCTest were both considered and rejected):
  - Pure logic on a `Codable` struct's computed property is exactly the case Swift Testing is fastest for (`swift test`, no simulator, ~0.1-0.4s) — see axiom-testing skill "Speed Hierarchy".
  - XCTest offers no advantage here (no UI, no Objective-C, no existing XCTest convention to match — there is no existing Swift test target in this repo at all, so there's no "match existing style" argument either way).
  - A CLI-only fixture smoke test (feed a fixture `Package.resolved` through `gen-umbrella`, grep the output) is worth keeping too, but as an *additional* end-to-end regression check, not a replacement — it's slower and coarser (tells you "output wrong", not "which branch"). Add it as a secondary RSpec-level check per existing `spec/proxy_executable_spec.rb` pattern if time allows; not required for phase completion.
- Validation commands:
  - Unit: `cd tools/spm-cache-proxy && swift test`
  - Optional end-to-end fixture check: `swift run gen-umbrella --lockfile <fixture>.json --output /tmp/umbrella` then `grep 'revision:' /tmp/umbrella/Package.swift`

## Risks / rollback

- Low-medium risk: touches umbrella `Package.swift` generation for ALL packages, not just revision-pinned ones (the `if/else` restructure). Must verify version-pinned packages still get `from: "x.y.z"` unchanged (regression risk if branch ordering swapped).
- Rollback: revert the 3 Swift edits; no persisted state depends on the new `revision` field beyond regeneration.
