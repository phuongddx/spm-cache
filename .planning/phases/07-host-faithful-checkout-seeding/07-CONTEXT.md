# Phase 7: Host-Faithful Checkout Seeding - Context

**Gathered:** 2026-08-27
**Status:** Ready for planning
**Mode:** Compressed (context-budget constrained; sourced from existing milestone research rather than fresh discuss-phase). User explicitly overrode the "re-plan 7-9 before executing" decision recorded earlier in STATE.md and authorized proceeding on accepted risk (`/gsd-autonomous --from 7 --to 11`, 2026-08-27).

<domain>
## Phase Boundary

Every per-package build resolves its transitive dependencies from the host app's resolved graph rather than from that package's own requirements — both the metadata `swift package describe` reads and the binary that gets cached. This phase changes only per-package build seeding; it does not touch lockfile reconciliation (Phase 6, done) or cache invalidation (Phase 9).

**Important context for planning:** M1 field measurement (Phase 6) found this phase's target mechanism — fresh upward re-resolution in isolated per-package builds — occurs **zero times** in the reference project (`H-float = 0`; all packages emitted as exact `revision:` pins, leaving no range to float within). The mechanism is still real (reproduced in isolation during milestone research: swift-argument-parser 1.2.0 → 1.8.2), and would bite plugin-only/revision-less-transitive-only packages the umbrella omits by design — but it is hardening against an unobserved-in-the-field risk, not a fix for an active field failure. Plan and prioritize accordingly: correctness of the mechanism matters, but this is not as urgent as Phase 6 was.

</domain>

<decisions>
## Implementation Decisions

### Seeding Mechanism (sourced from `.planning/research/ARCHITECTURE.md`, verified empirically during milestone research)

- **Copy the host's `Package.resolved` verbatim into each package checkout** (`<pkg_dir>/Package.resolved`) before the first `swift package describe`. Verified: a superset file is honored — extra pins pruned, missing pins filled in, `originHash` ignored. Do NOT synthesize or filter pins per-package; that reintroduces the staleness/format-churn risk Phase 6 just closed.
- **Do NOT enable `-onlyUsePackageVersionsFromResolvedFile` by default.** It hard-fails on any missing pin, and the umbrella systematically omits packages' external test-only dependencies — this would break every package with an external test dep. Detection of drift is Phase 8's job (post-resolve read-back), not this flag.
- **Add `-clonedSourcePackagesDirPath` pointed at a dedicated sibling directory** (never `{umbrella}/.build`) as a secondary cost mechanism. `BuildPipeline#locate_prebuilt_xcframework` reads Class-E binaryTarget artifacts from `{umbrella}/.build/artifacts/...`; pointing the shared clone dir there risks corrupting that live state.

### Vendored-`.xcodeproj` Classification (sourced from `.planning/research/PITFALLS.md` Pitfall 11)

- Classify each package before injecting: SPM-native vs. vendored-`.xcodeproj` (CryptoSwift, AppAuth-iOS, SVGKit, DTCoreText, DeviceKit, AEXML, FSPagerView, SkeletonView — already-hardened v0.2.x classes). Apply seeding only to the SPM-native path.
- Report vendored-project packages as an explicit **not-graph-pinned** category, never folded silently into "pinned." Honest partial coverage beats a false 100%. This is amended ROADMAP criterion 2 verbatim.

### Safety Invariants

- An aborted/failed/interrupted build must leave no checkout carrying a synthetic resolved file — atomic write + restore-on-failure, not an in-place overwrite left dangling.
- A concurrent `watch` cycle must not be able to delete checkouts out from under an in-flight build (process-level lock, not the debounce timer — per Phase 6 research's `watch` re-entrancy finding, carried forward as a risk here).
- **Default-off byte-identical fallback.** With seeding disabled (the default until this phase's work is wired in as opt-in-then-promoted), behavior must be byte-for-byte identical to v0.3.0. This is the phase's regression-safety net and should be a concrete, checkable task, not an assumption.

### Performance Gate (ROADMAP criterion 5, ratified by the milestone roadmapper)

- Benchmark cached-build wall-clock and disk usage against the reference project. **No regression is acceptable.** If the verbatim-pin-superset approach regresses, narrow to the minimal pin closure and re-measure until it does not. This is a blocking gate, not a follow-up — matches the milestone's PERF-01 requirement.

### Claude's Discretion

- Exact module/class boundaries for the seeding logic (naming, file organization) — follow existing codebase conventions (`SPMCache::SPM` namespace, one class per file).
- Whether the vendored-`.xcodeproj` classification lives as a new method or extends an existing one — the existing `Buildable#project_disambiguation_flag` / `BuildPipeline#run_with_scheme` fallback path is the established precedent to extend, not replace.
- Benchmark methodology specifics (what counts as "the reference project" run, warm vs cold cache) — use the existing `benchmark-report.html` pattern already in the repo if present.

</decisions>

<code_context>
## Existing Code Insights

### Reusable assets
- `lib/spm_cache/spm/build.rb:98-108` — exact invocation shape the seeding mechanism transfers into verbatim (per research, `-clonedSourcePackagesDirPath` appends here).
- `lib/spm_cache/core/package_resolved.rb` (Phase 6, new) — the canonical locator now exists; this phase's host-graph source should read through it, not re-derive a path.
- `Buildable#project_disambiguation_flag`, `BuildPipeline#run_with_scheme` — existing vendored-`.xcodeproj` fallback path to extend for classification.

### Established patterns
- `# frozen_string_literal: true` first line, flat `SPMCache::` namespace, one class per file, `Core::Sh` hermetic shell-out seam for specs.
- Comments only for non-obvious WHY (field-bug provenance) — strict project convention, no explanatory comments.

### Integration points
- Insertion point is per-package, before `swift package describe` — the same ordering constraint Phase 6 established for lockfile reconciliation (seed before any read of the graph).

</code_context>

<specifics>
## Specific Ideas

None beyond what's captured above — this phase's shape was substantially pre-decided by milestone-level research (`ARCHITECTURE.md` §(a)/(b), `PITFALLS.md` Pitfall 11) before M1 downgraded its priority.

</specifics>

<deferred>
## Deferred Ideas

- Drift read-back / provenance sidecar — Phase 8.
- Cache invalidation on provenance mismatch — Phase 9.
- Full regression fixture matrix — Phase 10 (this phase's own byte-identical-with-seeding-off task is a narrower, phase-local check).

</deferred>
