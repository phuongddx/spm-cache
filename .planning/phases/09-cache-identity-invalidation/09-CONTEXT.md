# Phase 9: Cache Identity & Invalidation - Context

**Gathered:** 2026-08-29
**Status:** Ready for planning

<domain>
## Phase Boundary

Users on an existing cache actually receive the fidelity fix delivered in Phases 6-8 — an
artifact built against a graph that no longer matches the host's is treated as a miss and
rebuilt, and two projects on different versions stop sharing one binary. Without this phase,
the correctness fix from Phases 6-8 reaches zero existing users, since `Cache.swift:19-22`
`hit(module:)` is a bare name + `fileExists` check with no identity/version dimension at all.

</domain>

<decisions>
## Implementation Decisions

### Miss Classification & Warning Behavior
- No provenance sidecar at all (v0.3.0 upgrade case) → silent miss + rebuild, no warning spam (exactly SC1)
- Sidecar exists but pins disagree with host graph → miss + rebuild only that artifact, never the whole cache (SC2 partial invalidation)
- `fidelity_status: resolution-incompatible` on a cached artifact is NOT itself an invalidation trigger — status is independent of identity; only pin disagreement invalidates. A resolution-incompatible artifact is a legitimate steady state (e.g. test-only deps) and must still cache normally.
- Corrupted/unreadable sidecar → treat as miss (fail-safe), matching `cache list`'s existing `fidelity_status_for` fallback philosophy from Phase 8

### Cross-Project Identity
- The provenance sidecar's realized pins ARE the identity check: if Project A's host pin for PackageX disagrees with what a cached artifact's sidecar recorded, that artifact is a miss for Project A
- No new per-project cache-directory partitioning in this phase — full content-addressed `~/.spm-cache` partitioning is explicitly deferred to v0.5 (locked decision, 2026-08-27)
- Two projects resolving the SAME version of PackageX continue correctly sharing the one cached artifact — no regression on the shared-cache value proposition
- Accepted, documented tradeoff: alternating builds between two projects with different pins for the same package can thrash the cache (rebuild on every switch) — correctness over hit-rate for v0.4.0; v0.5's content-addressed keys remove this by construction

### cache clean & Orphan Cleanup
- `cache clean` removes orphaned `.provenance.json`/`.shims.json` sidecars that have no matching `.xcframework` (SC4, hard requirement) — sweep by suffix-stripped basename match, mirroring Phase 8's existing `.shims.json` cleanup pattern in `copy_prebuilt_binary_target`
- `cache clean` does NOT proactively purge xcframeworks that have no provenance sidecar at all (stale pre-v0.4.0 cache entries) — SC1's lazy miss-on-no-provenance path handles those naturally on next build; a mass-delete on an unrelated `cache clean` invocation would be surprising

### DerivedData / Resource Bundle Staleness (SC5)
- spm-cache does NOT proactively purge Xcode's DerivedData for an invalidated/rebuilt module — Xcode's own build system already treats a changed `binaryTarget` input as forcing a relink; directly touching DerivedData repeats the same fragile heuristic already flagged in `CONCERNS.md`'s `checkout_resolver.rb` DerivedData-fallback concern
- Rebuilt xcframeworks overwrite the SAME output path (as today), not a rotated/new path per rebuild — this is how an ordinary cache-miss rebuild already works. Flagged as an assumption for the research step to verify empirically (whether Xcode reliably notices an in-place binaryTarget content change), not resolved dogmatically here — this is exactly the kind of question ROADMAP.md's "Research: Needed" note for this phase exists to answer.

### Claude's Discretion
None — all four grey areas were accepted as recommended without changes.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Core::PackageResolved` (Ruby, Phase 6) — canonical Package.resolved locator/reader, already resolves pins by identity with revision-over-version precedence via `host_pin_value`
- `BuildPipeline#report_fidelity`/`write_provenance_sidecar` (Ruby, Phase 8) — the provenance sidecar this phase reads for identity comparison; schema is `{fidelity_status, pins, spm_cache_version, config, destinations}`
- `Command::Cache::List#fidelity_status_for` (Ruby, Phase 8) — existing tolerant-fallback pattern for reading a possibly-missing/malformed sidecar, to mirror for the invalidation check

### Established Patterns
- Sidecar cleanup pattern: `FileUtils.rm_f("#{output_path}.provenance.json")` alongside `.shims.json` cleanup in `copy_prebuilt_binary_target` and the not-seeded branch of `report_fidelity`
- Pin comparison: intersection-only scoping (`drifted_identities` in `build_pipeline.rb`) — compare only identities present on both sides, never assert universal drift on partial data
- "Warn, never hard-fail" philosophy is consistent across all of Phases 6-8 and carries into this phase's design (never crash on ambiguous/missing provenance, treat conservatively as miss instead)

### Integration Points
- `BinariesCache.hit(module:)` in `tools/spm-cache-proxy/Sources/Core/Cache.swift:19-22` (Swift) — the actual cache-hit decision point this phase must change from a bare `fileExists` check to a provenance-aware comparison
- `BinariesCache.cachedModules()` / `dir` structure `~/.spm-cache/<config>/<name>.xcframework` — the flat, unpartitioned directory layout that stays unpartitioned this phase (per the v0.5-deferral decision above)
- `Command::Cache::Clean` (Ruby, not yet read in detail — plan/research step should locate it) — where the orphaned-sidecar sweep belongs

</code_context>

<specifics>
## Specific Ideas

No specific requirements beyond the accepted grey-area decisions above — open to standard approaches for the actual pin-comparison mechanics (Swift vs Ruby side, exact comparison function shape), deferred to the research step per ROADMAP's explicit "Research: Needed" flag for this phase (comparison granularity and DerivedData-fingerprint interaction with the deferred v0.5 content-addressing work).

</specifics>

<deferred>
## Deferred Ideas

- Full content-addressed `~/.spm-cache` partitioning — explicitly v0.5 scope (locked 2026-08-27)
- Proactive DerivedData purging on invalidation — rejected as too invasive/fragile; Xcode's own build system is trusted to notice binaryTarget content changes
- Proactive purge of provenance-less (pre-v0.4.0) cache entries during `cache clean` — left to the lazy miss-on-no-provenance path instead

</deferred>
