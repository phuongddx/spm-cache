---
phase: 2
title: "Swift status resolution"
status: pending
priority: P2
dependencies: [1]
effort: "2h"
---

# Phase 2: Swift status resolution

## Overview

Teach the Swift proxy tool to parse `--cache-only` and compute the new `"excluded"`
status. When `cacheOnlyPatterns` non-empty: a package that does NOT match any pattern
gets `"excluded"` and takes the SAME source-fallback manifest path `"ignored"` uses
today (no new manifest logic — only the status label and gating branch differ). When
`cacheOnlyPatterns` empty, existing `ignore`-based logic is byte-for-byte unchanged
(critical backward-compat guarantee).

Depends on Phase 1 — the `--cache-only` flag must exist to be parsed.

## Requirements

- Parse `--cache-only` CSV into `cacheOnlyPatterns` (mirror `--ignore` parsing).
- New `Status.excluded` case in `GraphEntry.Status`.
- Non-matching packages (when `cacheOnlyPatterns` non-empty) → `"excluded"`, source
  fallback, cache lookup bypassed.
- Reuse the existing glob helper (`fnmatch`) — inverted condition against the new list.
- Empty `cacheOnlyPatterns` → zero behavioral change vs today.

## Architecture

`ProxyGenerator` currently has `isIgnored(pkg)` (ProxyGenerator.swift:27-38) driving a
3-way status (ProxyGenerator.swift:55-65). Add a parallel `isCacheOnlyExcluded(pkg)`
that returns true when `cacheOnlyPatterns` is non-empty AND the package matches NONE of
the patterns (inverted match). Reuse the same candidate list
(`[pkg.resolvedProductName, pkg.name]`) and `fnmatch` loop — factor the raw glob-match
into a shared private helper `matchesAnyPattern(_ pkg:, _ patterns:)` to keep `isIgnored`
and the new check DRY.

Status precedence within `generate` (ProxyGenerator.swift:55-65): because Phase 1
guarantees only one list is ever populated per run, `ignoredPatterns` and
`cacheOnlyPatterns` are mutually exclusive at the input boundary. So the branch is:
```
excluded (cacheOnly non-empty AND no match) → .excluded, source fallback
ignored  (ignore matches)                   → .ignored,  source fallback  [unchanged]
cache hit                                    → .hit
else                                         → .missed
```
`.excluded` and `.ignored` share the identical `cachedBinary = nil` + shim/source-
fallback code path (ProxyGenerator.swift:57, 78-85, 135-157) — the only difference is
the status label. Do NOT duplicate manifest/shim generation.

Data in: `--cache-only 'A,B'` CLI arg. Data out: `graph.json` entries with
`status: "excluded"` for non-allowlisted packages + valid source-fallback `Package.swift`
for each.

## Related Code Files

- `tools/spm-cache-proxy/Sources/CLI/GenProxy.swift` — `--ignore` option decl
  (GenProxy.swift:22-23), parse (GenProxy.swift:37-40), `ProxyGenerator` init
  (GenProxy.swift:43). MODIFY.
- `tools/spm-cache-proxy/Sources/Core/Generator/ProxyGenerator.swift` — stored props +
  init (ProxyGenerator.swift:4-12), `Status` enum (ProxyGenerator.swift:15-17),
  `isIgnored` (ProxyGenerator.swift:27-38), status branch (ProxyGenerator.swift:55-65),
  source-fallback path (ProxyGenerator.swift:78-85), manifest else-branch
  (ProxyGenerator.swift:135-157). MODIFY.
- `spec/gen_proxy_ignore_spec.rb` — structure/skip-if-binary-unbuilt pattern to mirror
  (whole file). REFERENCE (do not modify).
- `spec/fixtures/ignore-lockfile.json` — reuse as fixture (same Alamofire/SnapKit/
  swift-log packages) OR add `spec/fixtures/cache-only-lockfile.json` if a distinct
  set is clearer. Prefer reuse. REFERENCE / optional new fixture.
- `spec/gen_proxy_cache_only_spec.rb` — NEW.

## Implementation Steps

1. **GenProxy.swift**: add `@Option var cacheOnly: String?` mirroring `ignore`
   (GenProxy.swift:22-23) with help "Comma-separated glob patterns of the ONLY modules
   to cache; all others excluded". Parse into `cacheOnlyPatterns` mirroring
   (GenProxy.swift:37-40). Pass `cacheOnlyPatterns:` into `ProxyGenerator(...)` init
   (GenProxy.swift:43). Note ArgumentParser maps `--cache-only` → property `cacheOnly`
   automatically (kebab of camelCase).

2. **ProxyGenerator.swift**:
   - Add stored `let cacheOnlyPatterns: [String]` + init param (default `[]`)
     (ProxyGenerator.swift:4-12).
   - Add `case excluded` to `Status` enum (ProxyGenerator.swift:15-17). Codable raw
     value `"excluded"`.
   - Extract shared `private func matchesAnyPattern(_ pkg:, _ patterns: [String]) -> Bool`
     from `isIgnored` body (ProxyGenerator.swift:29-37); rewrite `isIgnored` to call it
     with `ignoredPatterns`. Add `private func isCacheOnlyExcluded(_ pkg:) -> Bool`:
     `!cacheOnlyPatterns.isEmpty && !matchesAnyPattern(pkg, cacheOnlyPatterns)`.
   - In `generate` (ProxyGenerator.swift:55-65): compute `let excluded =
     isCacheOnlyExcluded(pkg)`. Treat `excluded || ignored` as the source-fallback
     gate for `cachedBinary` (ProxyGenerator.swift:57). Status branch: `if excluded {
     status = .excluded } else if ignored { status = .ignored } else if cachedBinary
     != nil { .hit } else { .missed }`.
   - `generateProxyManifest` else-branch (ProxyGenerator.swift:135-157) already handles
     any non-`.hit` status as source fallback — verify `.excluded` falls into it (it
     will, since `status == .hit` is the only special-case). No manifest change needed.

3. **spec/gen_proxy_cache_only_spec.rb** (NEW): mirror `gen_proxy_ignore_spec.rb`
   exactly — same `binary`/`lockfile`/`tmpdir` lets, same `skip` guard when binary not
   built, same `run_gen_proxy(cache_only:)` helper shelling `--cache-only`. Cases:
   - `cache_only: "Alamofire"` → Alamofire `hit` or `missed` (cache-eligible), SnapKit
     + swift-log/Logging → `"excluded"`.
   - excluded package still produces a valid source-fallback `Package.swift` (assert
     `.proxies/<slug>/Package.swift` exists and contains `.product(name:` shim line).
   - empty/absent `--cache-only` → no `"excluded"` statuses appear (parity guard).

## Success Criteria

- [ ] `swift build` succeeds in `tools/spm-cache-proxy`.
- [ ] `swift test` passes for any modified Swift test target (if none exists, N/A —
      Swift-side coverage is via the Ruby fixture spec, matching the `ignore` approach).
- [ ] `bundle exec rspec spec/gen_proxy_cache_only_spec.rb` passes, OR documents the
      "skipped, binary not built" pre-existing constraint (same as
      `gen_proxy_ignore_spec.rb`) — a skip here is NOT a phase failure, note as known
      limitation.
- [ ] `graph.json` shows `"excluded"` for non-matching packages, `hit`/`missed` for
      matching ones.
- [ ] Empty `cacheOnlyPatterns` → `bundle exec rspec spec/gen_proxy_ignore_spec.rb`
      unchanged/green (backward-compat).

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Inverted match logic wrong (excludes matched instead of unmatched) | Med | High | `isCacheOnlyExcluded` = non-empty AND NOT match; fixture spec asserts allowlisted pkg is cacheable, others excluded |
| `.excluded` accidentally routes to binary manifest branch | Low | High | Only `status == .hit` special-cases manifest (ProxyGenerator.swift:119); verify `.excluded` hits else-branch |
| Empty-list path drifts from today's behavior | Low | High | `matchesAnyPattern` refactor is behavior-preserving; `gen_proxy_ignore_spec.rb` regression guards it |
| Swift binary not built locally → spec skipped, false confidence | Med | Low | Same pre-existing constraint as ignore spec; documented, not a failure |

**Rollback**: revert both Swift files (removes `--cache-only` parsing + `.excluded`) and
delete the new spec. Phase 1's `--cache-only` flag then hits an unknown-option error
only if a user has `cache_only` set — so roll back Phase 1 and 2 together, or leave
Phase 1's flag unsent by keeping `cache_only` empty.
