# Phase 9: Cache Identity & Invalidation - Pattern Map

**Mapped:** 2026-08-29
**Files analyzed:** 10 (6 modified, 4+ new test files)
**Analogs found:** 10 / 10 (all analogs are sibling code within the same modified files, or directly adjacent existing patterns — this phase extends, not creates, subsystems)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|--------------------|------|-----------|-----------------|----------------|
| `tools/spm-cache-proxy/Sources/Core/Cache.swift` (`hit(module:)`, modify) | service | request-response (sync decision, per product) | `Cache.swift:31-42` `shims(for:)` (same file, sidecar-read sibling) | exact |
| `tools/spm-cache-proxy/Sources/Core/Lockfile.swift` (add `pinValue`, modify) | model | transform (pure computed property) | `Lockfile.swift:118-126` `versionRequirement` (same file, same precedence rule) | exact |
| `tools/spm-cache-proxy/Sources/Core/Generator/ProxyGenerator.swift` (line 119 call site, modify) | service | request-response | same file, existing loop at lines 84-119 | exact |
| `lib/spm_cache/spm/build_pipeline.rb` (`report_fidelity`'s `unless seeded` branch, modify) | service | event-driven (build lifecycle hook) | `build_pipeline.rb:1029-1045` `copy_prebuilt_binary_target` sidecar cleanup (same file) | exact |
| `lib/spm_cache/installer/use.rb` (`fast_path?`, modify) | service | request-response (eligibility gate) | `installer.rb:417-437` `invalidate_stale_products!`/`enrich_lockfile_products` staleness-stamp pattern | role-match |
| `lib/spm_cache/command/cache/clean.rb` (`sweep_orphaned_sidecars`, new method) | controller (CLI command) | file-I/O (filesystem sweep) | `build_pipeline.rb:1030-1045` suffix-stripped sidecar cleanup | role-match |
| `tools/spm-cache-proxy/Tests/spm-cache-proxyTests/CacheTests.swift` (new) | test | request-response | `ProxyGeneratorTests.swift:22-38` (real-fixture, no-mock test shape) | exact |
| `spec/build_pipeline_provenance_spec.rb` (extend) | test | CRUD/event-driven | existing file itself (lines 89,123 fixture pattern) | exact |
| `spec/command_cache_clean_spec.rb` (new) | test | file-I/O | `spec/command_cache_list_spec.rb` (sibling command spec) | role-match |
| `spec/gen_proxy_provenance_spec.rb` (new) | test | integration/real-binary | `spec/gen_proxy_cache_only_spec.rb` (real-binary smoke pattern) | exact |
| `spec/installer_use_fast_path_spec.rb` (new) | test | request-response | none dedicated — no existing `Installer::Use` unit spec found | no analog |

## Pattern Assignments

### `tools/spm-cache-proxy/Sources/Core/Cache.swift` (service, request-response)

**Analog:** same file, `shims(for:)` at lines 31-42

**Current code to replace** (lines 19-22):
```swift
func hit(module: String) -> URL? {
    let xcframework = dir.appendingPathComponent("\(module).xcframework")
    return FileManager.default.fileExists(atPath: xcframework.path) ? xcframework : nil
}
```

**Sidecar-read pattern to mirror** (lines 31-42, verbatim, already shipped):
```swift
func shims(for module: String) -> [String] {
    let sidecar = dir.appendingPathComponent("\(module).xcframework.shims.json")
    guard let data = try? Data(contentsOf: sidecar),
          let names = try? JSONDecoder().decode([String].self, from: data) else {
        return []
    }
    return names
}
```

**Recommended replacement:**
```swift
func hit(module: String, identity: String, currentPin: String?) -> URL? {
    let xcframework = dir.appendingPathComponent("\(module).xcframework")
    guard FileManager.default.fileExists(atPath: xcframework.path) else { return nil }

    let sidecar = dir.appendingPathComponent("\(module).xcframework.provenance.json")
    guard let data = try? Data(contentsOf: sidecar),
          let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return nil // sidecar missing or unparsable -> fail-safe miss
    }
    guard let pins = parsed["pins"] as? [String: String] else { return nil }

    if let recorded = pins[identity], let current = currentPin, recorded != current {
        return nil // miss: pin disagreement
    }
    return xcframework
}
```

**Error handling pattern:** identical to `shims(for:)` — `try?` swallow-to-nil/empty, no throw, no logging. Corrupted/missing sidecar and absent identity are NOT distinguished by an error type; both fall through to a conservative default (miss for corrupt, hit for absent-identity — asymmetric fail-safe per CONTEXT.md).

---

### `tools/spm-cache-proxy/Sources/Core/Lockfile.swift` (model, transform)

**Analog:** same file, `versionRequirement` at lines 118-126

**Pattern to extract into a new computed property** (add near `versionRequirement`):
```swift
var pinValue: String? {
    if let revision = revision, !revision.isEmpty { return revision }
    if let version = version, !version.isEmpty { return version }
    return nil
}
```
Revision-over-version precedence must match `versionRequirement`'s existing rule exactly (Swift side) and `build_pipeline.rb:152-155`'s `host_pin_value` (Ruby side) — three implementations of one rule is the anti-pattern to avoid; this is the DRY fix collapsing Swift's count from 2 to 1.

---

### `tools/spm-cache-proxy/Sources/Core/Generator/ProxyGenerator.swift` (service, request-response)

**Analog:** same file, loop at lines 84-119 (no external analog needed — single call-site edit)

**Current call site** (line 119):
```swift
let cachedBinary = (ignored || excluded) ? nil : cache.hit(module: product.name)
```

**Replacement:**
```swift
let cachedBinary = (ignored || excluded) ? nil
    : cache.hit(module: product.name, identity: pkg.name ?? product.name, currentPin: pkg.pinValue)
```

**Critical constraint (Pitfall 3):** key the lookup by `pkg.name` (package identity, outer loop variable), never `product.name` — the sidecar's `pins` hash is keyed by package identity, not product/target name. A multi-product package (e.g. `realm-swift` → `Realm`+`RealmSwift`) will silently always-miss if this is gotten backwards.

---

### `lib/spm_cache/spm/build_pipeline.rb` (service, event-driven)

**Analog:** same file, `copy_prebuilt_binary_target`'s sidecar cleanup at lines 1029-1045

**Current code to replace** (lines 92-101, `unless seeded` branch of `report_fidelity`):
```ruby
unless seeded
  FileUtils.rm_f("#{output_path}.provenance.json")
  return
end
```

**Replacement** (write, don't delete — Pattern 3, closes the Class E cache-defeat hazard):
```ruby
unless seeded
  write_provenance_sidecar(output_path, status: "not-graph-pinned", pins: {},
                                         config: config, destinations: destinations)
  return
end
```

**Also touch:** the redundant second `rm_f` inside `copy_prebuilt_binary_target` at lines 1043-1045 — same fix must apply there or the two call sites disagree.

**Why safe:** `hit()`'s intersection-only comparison treats `pins: {}` identically to a normal sidecar whose intersection is empty (identity never present ⇒ never flagged as disagreeing) — matches `build_pipeline.rb:121-134`'s existing `drifted_identities` intersection-only philosophy.

---

### `lib/spm_cache/installer/use.rb` (service, request-response)

**Analog:** `lib/spm_cache/installer.rb:417-437` `invalidate_stale_products!`/`enrich_lockfile_products` staleness-stamp pattern

**Current gap** (`fast_path?`, `installer/use.rb:73-79`): three checks (empty diff, lockfile exists, proxy `Package.swift` exists), zero version-awareness.

**Recommended fix:** extend `fast_path?` to also read the on-disk lockfile's persisted `spm_cache_version` stamp directly (via `Core::Lockfile`, NOT a hand-rolled JSON reader — `@lockfile` ivar is `nil` at this point since `sync_lockfile` is what populates it, and `sync_lockfile` is exactly what the fast path skips) and require it to equal `SPMCache::VERSION` before taking the fast path. Mirrors the existing stamp-comparison shape already used for `products[]` staleness in `enrich_lockfile_products`.

**Don't hand-roll:** use `Core::Lockfile`, already required by `installer.rb`, rather than a second ad hoc JSON parser for this one field.

---

### `lib/spm_cache/command/cache/clean.rb` (controller/CLI command, file-I/O)

**Analog:** `build_pipeline.rb:1030-1045` suffix-stripped basename sidecar cleanup

**Current file** (lines 23-37, `run` method) has no sidecar-awareness — two modes only (`--all`, named targets).

**New method to add** (runs unconditionally, independent of `--all`/target filtering per locked CONTEXT.md decision):
```ruby
def sweep_orphaned_sidecars(cache_dir)
  Dir.glob(File.join(cache_dir, "*.{provenance,shims}.json")).each do |sidecar|
    basename = File.basename(sidecar).sub(/\.xcframework\.(provenance|shims)\.json\z/, "")
    fw_path = File.join(cache_dir, "#{basename}.xcframework")
    next if File.directory?(fw_path)

    if @dry
      puts "[dry] Would remove orphaned sidecar: #{sidecar}"
    else
      FileUtils.rm_f(sidecar)
      puts "Removed orphaned sidecar: #{sidecar}"
    end
  end
end
```

**Call site:** invoke inside the existing `["debug", "release"].each do |cfg|` loop in `run` (lines 23-37), after the `next unless File.directory?(cache_dir)` guard, before the `if @all` branch — so it always runs regardless of mode.

---

### `tools/spm-cache-proxy/Tests/spm-cache-proxyTests/CacheTests.swift` (test, new)

**Analog:** `ProxyGeneratorTests.swift:22-38` — real temp-dir fixtures, no protocol/mock layer

**Pattern to follow:**
```swift
let cacheDir = tmp.appendingPathComponent("cache")
try cacheDir.mkdir()
try cacheDir.appendingPathComponent("SomePkg.xcframework").mkdir()
try JSONSerialization.data(withJSONObject: ["pins": ["some-pkg": "aaa111"], "fidelity_status": "host-pinned"])
    .write(to: cacheDir.appendingPathComponent("SomePkg.xcframework.provenance.json"))
```
Cases to cover: sidecar absent (miss), sidecar corrupt/non-Hash JSON (miss), pin disagreement (miss), pin agreement (hit), identity absent from `pins` with empty `pins: {}` (hit — Class E steady state).

---

### `spec/command_cache_clean_spec.rb` (test, new)

**Analog:** `spec/command_cache_list_spec.rb` (sibling `cache` command spec — RSpec, real tmpdir fixtures per repo convention, no mocking framework in evidence)

Cover: xcframework + matching sidecar survives sweep; orphaned sidecar (no matching xcframework) removed; sweep runs even without `--all`/targets; `--dry`(if flag exists) reports without deleting.

---

### `spec/gen_proxy_provenance_spec.rb` (test, new)

**Analog:** `spec/gen_proxy_cache_only_spec.rb` — real-binary integration pattern (invokes the actual `spm-cache-proxy` binary, not a Swift-side unit test)

Cover: `graph.json`'s `hit`/`missed` status against fixture sidecars, including the cross-project identity scenario (two lockfiles, same package, different pins, don't share a hit).

---

### `spec/installer_use_fast_path_spec.rb` (test, new)

**No analog found** — no existing spec targets `Installer::Use#fast_path?` in isolation. Use RESEARCH.md's `Common Pitfall 2` and Pattern reasoning directly: assert fast path is taken when `spm_cache_version` stamp matches, and bypassed (falls through to full `sync_lockfile`/`prepare_proxy`) when it doesn't, using `Core::Lockfile` to read/write the stamp exactly as `enrich_lockfile_products`'s staleness check does.

---

## Shared Patterns

### Tolerant JSON sidecar reads (fail-safe on any parse anomaly)
**Source (Ruby):** `lib/spm_cache/command/cache/list.rb:29-38` `fidelity_status_for`
```ruby
def fidelity_status_for(sidecar_path)
  return "not-graph-pinned" unless File.exist?(sidecar_path)

  parsed = JSON.parse(File.read(sidecar_path))
  return "not-graph-pinned" unless parsed.is_a?(Hash)

  parsed["fidelity_status"] || "not-graph-pinned"
rescue JSON::ParserError, SystemCallError
  "not-graph-pinned"
end
```
**Source (Swift):** `Cache.swift:31-42` `shims(for:)` (see above)
**Apply to:** `Cache.swift`'s new `hit()` sidecar read, and any new Ruby code reading a provenance sidecar — never raise, always fall through to a conservative default (miss / `"not-graph-pinned"`).

### Suffix-stripped basename sidecar matching
**Source:** `lib/spm_cache/spm/build_pipeline.rb:1030-1045` (`copy_prebuilt_binary_target`)
**Apply to:** `command/cache/clean.rb`'s new orphan sweep — one matching convention across the whole cache lifecycle (write-time cleanup and clean-time cleanup).

### Intersection-only pin comparison (never assert drift on partial/absent data)
**Source:** `lib/spm_cache/spm/build_pipeline.rb:121-134` (`drifted_identities`)
**Apply to:** `Cache.swift`'s new `hit()` — identity absent from `pins` is NOT evidence of drift; only a present-and-disagreeing entry counts as a miss.

### Revision-over-version pin precedence (single source of truth)
**Source (Swift):** `Lockfile.swift:118-126` (`versionRequirement`)
**Source (Ruby):** `build_pipeline.rb:152-155` (`host_pin_value`)
**Apply to:** new `Lockfile.PackageRef.pinValue` computed property — must match both existing implementations' precedence rule exactly; do not write a third independent version.

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `spec/installer_use_fast_path_spec.rb` | test | request-response | No existing spec exercises `Installer::Use#fast_path?` in isolation; build from RESEARCH.md's Pitfall 2 description and the `enrich_lockfile_products` staleness-stamp pattern instead of a direct file analog |

## Metadata

**Analog search scope:** `tools/spm-cache-proxy/Sources/Core/`, `tools/spm-cache-proxy/Tests/spm-cache-proxyTests/`, `lib/spm_cache/spm/`, `lib/spm_cache/installer*`, `lib/spm_cache/command/cache/`, `spec/`
**Files scanned:** 10 primary source reads (per RESEARCH.md Sources list) + this session's classification pass over CONTEXT.md/RESEARCH.md
**Pattern extraction date:** 2026-08-29
**Note:** This phase is unusually self-contained — every new/modified file's closest analog is either the same file (a sibling method already shipped) or a directly cross-referenced file already named in RESEARCH.md with verified line numbers. No new Glob/Grep search was needed beyond confirming RESEARCH.md's citations were current; all code excerpts above are carried forward verbatim from RESEARCH.md's session-verified reads.
