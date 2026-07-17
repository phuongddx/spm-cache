---
phase: 1
title: "Proxy identity collision fix"
status: pending
effort: "S"
priority: P1
dependencies: []
---

# Phase 1: Proxy identity collision fix

## Overview

Rename the generated proxy wrapper folder from `<slug>` to `<slug>_proxy` so its SwiftPM identity no longer collides with the real package it wraps. Fix already verified by real `swift build` repro (triage report, Bug 3): before rename → "Conflicting identity" warning + `cyclic dependency declaration found` error; after rename → clean build.

## Requirements

- Functional: any cache-miss/ignored/excluded package resolves without identity collision; cache-hit packages unchanged in behavior.
- Non-functional: no lockfile schema change; independent of Phases 2-3.

## Architecture

SwiftPM derives package identity from the on-disk folder name and treats identity as global across the resolved graph. The wrapper at `.proxies/<slug>` and the real checkout both resolve to identity `<slug>`, so SwiftPM collapses them into one node and the wrapper's dependency on the real package becomes a self-cycle. The wrapper's manifest `name:` is already `<slug>_proxy`-style safe; only the folder and the path/package reference strings need to change.

## Related Code Files

- Modify: `tools/spm-cache-proxy/Sources/Core/Generator/ProxyGenerator.swift`
  - `:64-66` — `proxyDir = proxiesDir.appendingPathComponent(slug)` → `"\(slug)_proxy"`
  - `:214` — `.package(path: ".proxies/\(slug)")` → new folder name
  - `:215` — `.product(name:package:)`: the `package:` argument must name the WRAPPER's identity (`\(slug)_proxy`), not the real package's
- Modify or delete: `tools/spm-cache-proxy/Sources/Core/Proxy/RootProxyPackage.swift`
  - `:23` has the same `.package(path: ".proxies/\(slug)")` interpolation, but red-team verified this type (and `ProxyPackage`) is DEAD CODE — nothing constructs it (`GenProxy` uses `ProxyGenerator.generateRootProxy`). Update for consistency or delete; deletion preferred (YAGNI).
- Modify: `spec/gen_proxy_ignore_spec.rb:66,74` and `spec/gen_proxy_cache_only_spec.rb:54` — fixture path assertions `.proxies/<name>` → `.proxies/<name>_proxy`
- Audit (no change expected): grep whole repo for `.proxies/` and `package: "\(slug)"` to confirm no other construction sites (Ruby side confirmed clean; `Resolver.swift` is a no-op stub).

## Implementation Steps

1. Grep `.proxies/` and `appendingPathComponent(slug)` across `tools/` and `lib/`; list every construction/reference site.
2. Apply the folder rename at `ProxyGenerator.swift:64-66` and update both `.package(path:)` interpolations (`ProxyGenerator.swift:214`, `RootProxyPackage.swift:23`).
3. Fix the `.product(name:package:)` `package:` argument to reference the wrapper identity.
4. Update the two fixture specs' path assertions.
5. `cd tools/spm-cache-proxy && swift build -c release` then run the fixture specs (`bundle exec rspec spec/gen_proxy_ignore_spec.rb spec/gen_proxy_cache_only_spec.rb`) — they exercise the real binary.
6. Add one assertion to an existing fixture spec: generated root proxy `Package.swift` references `.proxies/<slug>_proxy` and `package: "<slug>_proxy"` for a miss-status package.

## Success Criteria

- [ ] No `.proxies/<slug>` folder equal to a wrapped package's identity is ever generated.
- [ ] Fixture specs assert and pass on the new `_proxy` folder naming.
- [ ] `swift build -c release` + full `bundle exec rspec` + `swift test` green.
- [ ] Manual smoke (optional if fixture specs cover it): a miss-path package builds without "Conflicting identity" warning.

## Risk Assessment

- Existing user workspaces have stale `.proxies/<slug>` folders → `invalidate_cache` (lib/spm_cache/spm/pkg/proxy.rb) already `rm_rf`s the proxy dir each run, so stale folders self-clean. Verify this in step 5.
- Renaming changes the wrapper identity string; any consumer keying on it (graph.json `module` field) must be checked — graph.json keys on product/module name, not folder, so expected no-op; confirm via fixture spec output.
