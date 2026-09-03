# Phase 8: Drift Read-Back, Fidelity Status & Provenance - Context

**Gathered:** 2026-08-29
**Status:** Ready for planning

<domain>
## Phase Boundary

Every cached artifact carries a verifiable record of the graph it was actually built against, and any
package whose realized versions differ from the intended pins is reported instead of silently shipped.
Covers: reading back realized pins after a build and comparing against the seeded intent (FID-03),
classifying and gracefully handling packages whose declared requirements can't satisfy the host graph
(FID-04), recording build provenance in a sidecar per cached artifact (CACHE-01), and surfacing a
per-package fidelity status in `spm-cache build` output and `cache list` (DIAG-02). Cache invalidation
against provenance (CACHE-02/03) is explicitly Phase 9's scope, not this phase's.

</domain>

<decisions>
## Implementation Decisions

### Drift Reporting Mechanism (FID-03)
- Intended pins = the seeded `<pkg_dir>/Package.resolved` snapshot taken before the build (already
  retained on disk post-build per 07-01-SUMMARY.md, specifically for this comparison)
- Realized pins = re-read `<pkg_dir>/Package.resolved` after the build completes
- Drift reported via `Core::UI.warn` per drifted package (name + intended vs realized version),
  consistent with the Phase 6 DIAG-01 precedent (drift is a warning, never a hard failure)
- Drift never blocks the build — matches the locked Core Value decision that a fidelity violation
  always degrades to source, never hard-fails

### Resolution-Incompatible Handling (FID-04)
- A package is classified `resolution-incompatible` when re-resolving after seeding fails/changes
  because the package's own manifest requirement excludes the host pin (M2 measurement: 0/17 on the
  reference project — a real but uncommon edge case, not a hot path; no proactive pre-check needed)
- On `resolution-incompatible`, the build proceeds from source for that package — the same fallback
  path a cache miss already takes, never a hard failure
- `ignore_build_errors` must never suppress or mask this status — it is always visible, per the
  explicit ROADMAP/REQUIREMENTS wording
- Not separately persisted — logged for the run and surfaced via `cache list`/build output (DIAG-02);
  re-derived from provenance on the next run, no dedicated marker file

### Provenance Sidecar Format (CACHE-01)
- Naming/location: `<name>.xcframework.provenance.json`, sibling to the artifact — mirrors the
  existing `.shims.json` sidecar pattern exactly (`BuildPipeline#write_shim_sidecar`'s
  `File.write`/`JSON.generate` shape and lifecycle)
- Fields: realized pins (name→version/revision map), spm-cache version, config (debug/release),
  destination set (`iphonesimulator`/`iphoneos`/`all`) — exactly what CACHE-01 specifies, no extras
  (no build duration/timestamp)
- Written by `BuildPipeline` once per successful build, at the same call site `.shims.json` is
  written today
- Cleanup: every path that overwrites/replaces an xcframework (e.g. `copy_prebuilt_binary_target`,
  cache clean) must also `rm_f` the stale provenance sidecar, mirroring the existing `.shims.json`
  cleanup rule — never leave a stale sidecar to lie about a rebuilt artifact

### Fidelity Status Surfacing (DIAG-02)
- `spm-cache build` output: one line per package alongside the existing
  `Building N target(s): ...`/cache-hit reporting (e.g. `CachedLib: host-pinned`,
  `SimOnlyLib: resolution-incompatible (built from source)`) — not a separate end-of-run-only table
- `cache list`: a new column/field per cached module, sourced from that module's provenance sidecar;
  falls back to `not-graph-pinned` if no sidecar exists (consistent with the existing FID-05 category)
- Exact status values, verbatim, no renaming: `host-pinned` / `resolution-incompatible` /
  `not-graph-pinned`
- Phase 8's own status-assignment logic must guarantee every package lands in exactly one bucket (no
  silent gaps) — the formal regression proof of this is TEST-02 (Phase 10), but the guarantee itself
  is not deferred

### Claude's Discretion
None — all four areas were accepted as recommended, no "you decide" answers were collected.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `BuildPipeline#write_shim_sidecar` (`lib/spm_cache/spm/build_pipeline.rb:~840-860`) — exact sidecar
  write/lifecycle pattern to replicate for the provenance sidecar (`File.write` + `JSON.generate`,
  sibling-path naming, cleanup on artifact replacement)
- `BuildPipeline#copy_prebuilt_binary_target` (`~880-905`) — the Class E direct-copy path that already
  `rm_f`s a stale `.shims.json`; the provenance sidecar cleanup must be added at the same call site(s)
- `Cache::Cachemap` (`lib/spm_cache/cache/cachemap.rb`) — existing status-bucket pattern (hit/missed/
  ignored/excluded/plugin via `modules_with_status`); the new fidelity status is an orthogonal
  dimension (a package can be simultaneously "hit" and "host-pinned"), not a replacement for this
- `SPM::ResolvedGraph` (`lib/spm_cache/spm/resolved_graph.rb`, Phase 7) — `seed!`/`restore!` already
  retains the pre-build snapshot; the seeded `Package.resolved` is deliberately left in place on
  success (07-01-SUMMARY.md) specifically so this phase can diff it against the post-build file

### Established Patterns
- Drift-as-warning-never-fail: `DIAG-01`'s `lock_graph_fidelity` doctor check (Phase 6) already
  established this posture for a different drift class (lock vs host graph) — same posture applies
  here for realized-vs-intended pin drift
- Sidecar lifecycle: write alongside the artifact it describes, clean up at every replacement path —
  established by `.shims.json`, reused verbatim for `.provenance.json`

### Integration Points
- `BuildPipeline.run`/`perform_build` (post-build, after a successful `perform_build` and before
  `write_shim_sidecar` returns) — natural insertion point for both drift read-back and provenance
  sidecar write
- `Installer::Build#perform_install`'s per-target build loop — natural insertion point for surfacing
  the fidelity status line in `spm-cache build` output
- `cache list` command (`lib/spm_cache/command/`) — needs the new fidelity-status column added

</code_context>

<specifics>
## Specific Ideas

No specific requirements beyond the four grey-area decisions above — open to standard approaches for
implementation details not covered by those decisions.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope. CACHE-02/CACHE-03 (cache invalidation against
provenance) were explicitly named as Phase 9 territory, not deferred from Phase 8 but never in scope
for it.

</deferred>
