# Cache Identity & Hygiene — Design Spec

- **Date:** 2026-09-21
- **Status:** Approved in brainstorm (chat), pending spec review
- **Target milestone:** v0.6.0 (candidate)
- **Scope drivers:** Goals 1 (cache-hit correctness) + 2 (cache hygiene at scale), selected 2026-09-21

## Summary

Replace name-keyed cache artifacts with content-hash-keyed artifacts, and add
local cache hygiene (LRU eviction + garbage collection). Hash-keyed naming
makes stale-binary cache hits structurally impossible for the inputs we hash,
lets multiple versions of a dependency coexist (so upgrades never delete the
previous working binary), and gives eviction something meaningful to do.

The Swift companion tool (`tools/spm-cache-proxy`) is **not modified**. A
canonical-name pointer layer preserves the existing `{module}.xcframework`
lookup contract consumed by `SPM::Pkg::Proxy#gen_proxy` and
`Installer::Build#slice_complete?`.

## Goals

1. **Cache-hit correctness.** Artifact identity derived from resolved pins,
   dependency closure, toolchain, and build context — not module name alone.
2. **Cache hygiene.** Size budget, LRU eviction, explicit `gc` command,
   opt-in auto-eviction, orphan/dangling cleanup.

## Non-goals (deliberately excluded, YAGNI)

- Full source-content hashing of checkouts (catches same-revision mutation;
  revisit if local/mutable packages are ever cached)
- Sharded CAS service / new remote infrastructure
- Remote cache eviction (Git/S3 stores grow; local-only hygiene)
- Cache profiles (`only-external` / `all-possible` / custom)
- Xcode 26 compilation-cache integration
- Grandfathering legacy artifacts via old provenance pins (one-time rebuild
  instead — see Migration)

## Background (verified in source)

Current state:

- Artifacts stored flat: `~/.spm-cache/{config}/{module}.xcframework`
  (`Core::Config#cache_dir`, `Cache::Inventory.scan`)
- Cache identity is name+config only. Version knowledge lives in the
  lockfile/proxy layer and `.provenance.json` sidecar (`pins`,
  `fidelity_status`, `spm_cache_version`) — it does not participate in lookup.
- Hit lookup by plain name in two places: Ruby `Installer::Build#slice_complete?`
  (`lib/spm_cache/installer/build.rb:119-120`) and Swift `GenProxy` (receives
  `cache_dir` via `SPM::Pkg::Proxy#gen_proxy`, scans for
  `{module}.xcframework`).
- Swift version capture exists (`Swift::Swiftc.swift_version`,
  `Core::Diagnostics`) but is not part of cache identity.
- No eviction: `cache clean [--all]` only.

Tuist lessons applied (research 2026-09-21): per-target content hashing with
transitive dependency cascade; Swift version in the key (module stability not
assumed); LRU watermark eviction (85% → 70%); multiple versions coexist in a
content-addressed store.

## Locked decisions

| Decision | Choice |
|---|---|
| Q1 hash depth | **A — pin-level fingerprint** (resolved pins + dep closure + toolchain + build context). No checkout content scan. |
| Q2 layout | **B — hash-suffixed flat + canonical pointer.** `{module}-{hash8}.xcframework` durable; `{module}.xcframework` symlink pointer for lookups. |
| Q3 hygiene | **C — both.** `spm-cache cache gc` command + opt-in auto-eviction after successful store. |

Defaults ratified: `auto_evict: false` (never silently delete user files),
`max_size_gb: 20`.

## Detailed design

### 1. Fingerprint — `Cache::Fingerprint`

New file: `lib/spm_cache/cache/fingerprint.rb`.

```ruby
module SPMCache
  module Cache
    module Fingerprint
      # context: sdk, config, destinations, merge_slices, library_evolution
      # pins:    resolved pin (version/revision) for THIS package
      # dependencies: { dep_name => dep_hash8 } (already computed, bottom-up)
      # @return [String] 8-hex-char cache key
      def self.for(package:, pins:, dependencies:, context:)
      end

      # Toolchain + flags snapshot shared by all targets in one run.
      def self.context(options:)
      end
    end
  end
end
```

Hash inputs (canonical JSON, deterministic key order, SHA-256, first 8 hex):

| Input | Source |
|---|---|
| package identity | lockfile / resolved graph |
| resolved pin (version + revision) | `Core::PackageResolved` (already feeds provenance `pins`) |
| dependency closure | bottom-up `{dep => hash8}` map — dep change cascades upstream (Tuist-style) |
| Swift version | `Swift::Swiftc.swift_version` (existing) |
| Xcode version | `xcodebuild -version` capture (existing pattern in `Core::Diagnostics`) |
| build context | sdk, config, destinations/slices, `library_evolution`, `merge_slices` |
| spm-cache version | `SPMCache::VERSION` (cache-format invalidation) |

Determinism rules: no absolute paths, no mtimes, sorted keys, strings
normalized. Computing per run: one `swift --version` + one
`xcodebuild -version` capture, memoized per process.

Sidecar extension (`.provenance.json`): add `cache_key` (hash8) and
`cache_key_inputs` (the exact input map) for debugging and `doctor`
diagnostics. Existing fields unchanged.

### 2. Storage layout & canonical pointer

``text
~/.spm-cache/debug/
  Alamofire-a1b2c3d4.xcframework                       # durable artifact
  Alamofire-a1b2c3d4.xcframework.provenance.json       # + cache_key, cache_key_inputs, last_used_at
  Alamofire.xcframework -> Alamofire-a1b2c3d4.xcframework  # pointer (symlink)
```

- Pointer is materialized/refreshed by Ruby (`use` flow) from
  lockfile+fingerprint before proxy generation. Atomic replace
  (tmp-symlink + `File.rename`).
- Consumers unchanged: `GenProxy` and `slice_complete?` keep reading
  `{module}.xcframework` through the pointer.
- Pointer rules: one per module per config; refreshed on every `use`;
  missing/dangling pointer ⇒ recomputed; target missing ⇒ cache miss
  (source fallback).
- `cache list` / web: `Inventory` resolves pointers to the hash-suffixed
  target for size/fidelity; adds `hash8` and `last_used` columns. Symlink
  itself never counted twice.

Remote sync (`storage/git.rb`, `storage/s3.rb`): sync artifact selection
changes from "everything ending in `.xcframework`" to "hash-suffixed
names matching `-{hash8}.xcframework` (name filter, not a literal shell
glob)" (+ sidecars). Same content ⇒ same name ⇒ additive pushes, no
overwrites, cross-machine dedupe for free. Pointers are local-only
(never synced).

### 3. Hygiene — `cache gc` + opt-in auto-evict

CLI:

```
spm-cache cache gc [--dry-run] [--max-size 20] [--all-configs]
```

Config (`spm-cache.yml`):

```yaml
cache:
  max_size_gb: 20      # budget per config dir (debug/release each)
  auto_evict: false    # opt-in; gc command always available
```

Semantics:

- **LRU** by sidecar `last_used_at`, touched on every hit/pointer refresh.
- **Auto-evict** (when enabled): after a successful store in the build flow;
  Tuist-style watermark — usage > 85% of budget ⇒ evict LRU until ≤ 70%;
  never evicts the artifact just written or currently pinned by the active
  run.
- **GC cleanup classes:** (a) LRU over budget, (b) legacy plain-name
  artifacts with no hash suffix, (c) dangling pointers, (d) orphan sidecars
  (no artifact), (e) artifacts with malformed/missing sidecar.
- **Locking:** gc refuses to operate on a config dir while
  `.spm-cache-build.lock` is held (existing build lock).
- `--dry-run` prints what would be deleted + bytes reclaimed; exit 0.
- New unit: `lib/spm_cache/cache/gc.rb` (scan + plan + execute, plan/execute
  split for dry-run reuse and specs).

### 4. Data flow

- **`use`:** diff detect (unchanged) → lockfile pins → per-dep fingerprint
  (bottom-up over graph) → refresh pointer per hit → `GenProxy` (unchanged)
  → miss = source fallback (unchanged). Fast path unchanged when pins+env
  stable: no rebuild, no rehash of artifacts (fingerprints recomputed from
  metadata only — cheap).
- **`build`:** same fingerprint → artifact written directly as
  `{module}-{hash8}.xcframework` (out_dir is the cache dir, as today) →
  sidecar with `cache_key_inputs` + `last_used_at` → pointer refresh →
  optional auto-evict.
- **`remote pull/push`:** glob change only.
- **`doctor`:** new check — fingerprint determinism (compute twice, compare;
  warn on absolute-path or environment leakage patterns).

### 5. Error handling

| Failure | Behavior |
|---|---|
| Fingerprint computation raises | **Fail open to source mode** — cache never breaks a build (project invariant) |
| Malformed/missing sidecar | Artifact treated as miss; GC-eligible |
| Dangling pointer | Recompute from lockfile; target gone ⇒ miss |
| Auto-evict error | Warn; never fail the build |
| GC while build lock held | Refuse with message (or `--force` later if asked) |
| Remote pull finds unknown-hash artifact | Ignored until a local fingerprint matches its name |

### 6. Testing plan

- **Fingerprint:** determinism (project dir rename ⇒ same hash); pin bump ⇒
  new hash; Swift/Xcode version bump ⇒ new hash; dep-closure change ⇒
  upstream hash changes; flag changes (`library_evolution`, slices) ⇒ new
  hash.
- **Layout:** store produces hash-suffixed + sidecar + pointer; hit resolves
  via pointer; legacy plain-name artifact ⇒ miss (one-time rebuild).
- **GC:** LRU order; 85/70 watermark; never-evict-just-written; dangling
  pointer cleanup; orphan sidecar cleanup; dry-run output; build-lock
  refusal; `--max-size` override.
- **Regression:** `use` fast-path performs no rebuild when pins+env
  unchanged (pattern: `spec/fidelity_drift_regression_spec.rb`).
- **Inventory/web:** `hash8`, `last_used` columns; pointer not double-counted.
- **Swift companion:** unchanged; existing gen-proxy specs are the contract
  proof (no new Swift tests required).

## Migration & release notes

- First `use` after upgrade: legacy artifacts (no hash suffix) read as
  misses → one rebuild per dependency per config. Release notes must state
  this plainly. GC then removes legacy orphans.
- No remote protocol break: old remote stores keep serving legacy names;
  they simply stop matching until re-pushed under hash names.
- Config keys are additive with safe defaults; existing `spm-cache.yml`
  files valid without changes.

## Open questions (resolve in implementation plan)

1. Pointer as symlink vs hard copy on exotic filesystems — symlink assumed
   fine (macOS-only tool); confirm no `xcodebuild` edge case with symlinked
   `.xcframework` paths in `binaryTarget`.
2. `cache list` grouping: one row per hash-suffixed artifact vs one row per
   module (pointed version highlighted). Default: per module, hash in column.
3. Whether `remote push` should skip pushing artifacts whose sidecar reports
   non-`host-pinned` fidelity (avoid polluting shared cache) — pre-existing
   question, now cheaper to enforce at the hash-name boundary.
