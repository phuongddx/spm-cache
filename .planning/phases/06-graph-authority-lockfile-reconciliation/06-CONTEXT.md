# Phase 6: Graph Authority — Lockfile Reconciliation - Context

**Gathered:** 2026-08-27
**Status:** Ready for planning

<domain>
## Phase Boundary

The lockfile spm-cache builds from always describes the host project's *current* resolved graph, so no later fidelity decision is made against an abandoned first-run snapshot.

In scope: reconciling `spm-cache.lock` package `version`/`revision` from the host's `Package.resolved` (FID-01); a static `doctor` check that reports lock-vs-resolved disagreement without running a build (DIAG-01); and the M1 measurement that attributes the field failure between the lockfile chain and isolated per-package re-resolution.

Out of scope: seeding resolved graphs into package checkouts (Phase 7), drift read-back and provenance (Phase 8), cache invalidation (Phase 9). This phase changes only which graph the umbrella is generated *from* — not how individual packages resolve once checked out.

</domain>

<decisions>
## Implementation Decisions

### Reconciliation Semantics

- A package present in `spm-cache.lock` but absent from the host's `Package.resolved` is **dropped**. The phase goal is that the lock describes the *current* graph; retaining a removed package makes the umbrella declare a dependency the app no longer has. This is not a corner case — it is 100% of the reference project's lock today (see Existing Code Insights).
- A package present in the host's `Package.resolved` but absent from the lock is **added with an empty `products[]`**, leaving existing enrichment to populate products later. This mirrors the shape `generate_lockfile_from_resolved` already produces on first run.
- Reconciliation runs **whenever `DiffDetector` reports a non-empty diff**, before umbrella generation. On the fast path (empty diff) the lock already agrees with the host graph, so there is nothing to reconcile. This matches the success criterion's wording ("after a non-fast-path run") and avoids rewriting the lock on every invocation.
- When the host's `Package.resolved` is missing or unreadable, **warn once and leave the lock untouched** — never crash, and never treat the absent file as an empty graph. Treating it as empty would, combined with the drop rule above, erase the entire lock. This matches the existing malformed-`Package.resolved` handling in `command/init.rb:153-169`.
- Enriched `products[]` must survive reconciliation intact for every package that remains in the graph (success criterion 2). Reconciliation updates `version`/`revision` only.

### doctor Fidelity Check (DIAG-01)

- The check compares **set membership AND version**, not just versions on the intersection. This was established by measurement, not assumption: on the reference project a version-only comparison over the overlapping packages reports "0 drifted" while the lock and host graph share **zero** packages. A version-only check silently passes a maximally-stale lock.
- Drift produces a **`:warn`** verdict with the fix hint "run `spm-cache use` to reconcile". The remedy is automatic on the next non-fast-path run, so a `:fail` would make `doctor --json` exit 1 spuriously in CI before a first `use` has run.
- Comparison uses **`revision` primarily, falling back to `version`** when no revision is held. This mirrors `Lockfile.swift:118-126`'s `versionRequirement` precedence, so the check tests exactly what the umbrella actually emits rather than a parallel notion of equality.
- When no lockfile exists yet the check reports **`:ok`** — a fresh project is not drifted.
- The check is static: it reads two files and compares them. It must not run a build, resolve, or shell out.

### M1 Measurement — Reproduction & Attribution

- Reproduce against the **`feature/spm-cache-integration` branch** of the reference project, where the original ExyteChat/MediaPicker state still exists. The project's `main` no longer contains those packages, so the motivating failure cannot be reproduced there.
- Additionally record **`main`'s zero-overlap finding** as already-captured field evidence of maximal staleness.
- Attribution is recorded in **Phase 6 SUMMARY.md plus a dated STATE.md decision**, keeping it in the artifact trail the verifier reads.
- If reconciliation alone fully explains the field case, **Phase 7 still proceeds, re-scoped by the finding**. The upward-drift mechanism was independently reproduced during research (swift-argument-parser 1.2.0 → 1.8.2, exit 0, no warning), so Phase 7 has a real target regardless of M1's attribution.

### Claude's Discretion

- Internal structure of `Core::PackageResolved` (the new single locator/parser collapsing five duplicated globs), method naming, and how reconciliation is factored out of `generate_lockfile_from_resolved`.
- Spec organization and fixture shape, subject to the hermetic `Core::Sh` seam convention.
- Exact wording of warnings and the `doctor` report line, subject to the existing marker-report format.

</decisions>

<code_context>
## Existing Code Insights

### The defect (source-verified 2026-08-27)

Five-link chain, all read directly:

1. `lib/spm_cache/installer.rb:165-166` — `generate_lockfile_from_resolved` early-returns `if File.exist?(lockfile_path)`. The sole `File.write(lockfile_path, …)` (line 191) is inside that guard, so package `version`/`revision` are frozen at first creation forever.
2. `lib/spm_cache/installer.rb:241` — the umbrella is generated from that lockfile via `gen_umbrella --lockfile`.
3. `tools/spm-cache-proxy/Sources/Core/Lockfile.swift:118-126` — `versionRequirement` returns `revision: "<sha>"` when a revision is held, else `from: "<version>"`.
4. `tools/spm-cache-proxy/Sources/Core/Generator/UmbrellaGenerator.swift:73` — emits `.package(url: "…", <req>)`, i.e. an exact stale commit pin.
5. `swift package resolve` (via `spm/checkout_resolver.rb`) then materializes checkouts at that stale revision.

`@lockfile.save` at `installer.rb:162` persists only the Xcode-target→product map, over data loaded from the stale file at line 133.

### False premise to delete

`UmbrellaGenerator.swift:57-63` justifies revision-pinning as reproducing "the host's resolved graph (`Package.resolved` is consistent, so the commit satisfies every parent's range by construction)". That premise holds only if the lockfile is fresh — it never is. This comment should be corrected as part of the phase.

### Field evidence (measured 2026-08-27)

Reference project `/Users/ddphuong/Projects/next-labs/stress-ai/ios-stress-app/StressMonitor`, branch `main`:

- Host `Package.resolved`: **17 pins** (firebase-ios-sdk, app-check, appauth-ios, googlesignin-ios, …)
- `spm-cache.lock`: **8 packages** (chat, mediapicker, kingfisher, giphy-ios-sdk, swiftuicharts, …)
- **Intersection: 0**
- `spm-cache.lock` mtime: **2026-08-09**; untracked by git; HEAD is `ea7e7cf` (2026-08-24)

The lock describes an application that no longer exists. This is the strongest available confirmation of the defect and is the direct source of the set-membership requirement in DIAG-01.

### Reusable assets

- `Core::Diagnostics` registry (`lib/spm_cache/core/diagnostics.rb`) — `register(name, fix_hint:) { |config:| [status, message] }` returning `[:ok|:warn|:fail, message]`. A raising check is captured as `:fail`, so one broken check never aborts the report. DIAG-01 registers here; no `doctor` command changes needed.
- `Core::DiffDetector` (`lib/spm_cache/core/diff_detector.rb`) — already locates and parses `Package.resolved` and computes the authoritative diff. Its empty/non-empty result is the reconciliation trigger, and its own glob is one of the five `Core::PackageResolved` will collapse.
- `Core::Lockfile` (`lib/spm_cache/core/lockfile.rb`) — load/save surface.
- Malformed-input precedent: `command/init.rb:153-169` warns and degrades rather than aborting on a non-object or unreadable `Package.resolved`.

### Established patterns

- `# frozen_string_literal: true` first line in every `.rb` file, no exceptions.
- Flat namespace under `SPMCache`; directory mirrors namespace; one class/module per file.
- `Core::Sh` is the shell-out seam that specs stub hermetically. This phase is pure file I/O + JSON and should need no shell-out at all.
- Comments explain WHY (non-obvious field-bug rationale), not WHAT — the existing codebase carries dense field-bug provenance comments.

### Integration points

The same `Package.resolved` glob is duplicated in **five** places, all candidates for `Core::PackageResolved`:

- `installer.rb:169`
- `core/diff_detector.rb:150-155`
- `core/watcher.rb:118`
- `command/init.rb:196`
- `command/use.rb:83`

Collapsing them matters beyond DRY: the new pin source and the change detector that must agree with it would otherwise locate the file by independent logic.

</code_context>

<specifics>
## Specific Ideas

- The zero-overlap measurement on the reference project is the concrete motivating example for DIAG-01's set-membership requirement; a spec fixture should encode exactly that shape (lock and host graph sharing no packages) and assert the check reports drift.
- Success criterion 1 is the phase's testable invariant: after a non-fast-path run, re-running `DiffDetector` returns an **empty** diff.

</specifics>

<deferred>
## Deferred Ideas

- Seeding the host graph into per-package checkouts — Phase 7 (FID-02).
- Post-resolve read-back and the `resolution-incompatible` status — Phase 8 (FID-03, FID-04).
- Cache invalidation on provenance mismatch — Phase 9 (CACHE-02).
- Whether the `spm-cache.lock` being untracked by git in the reference project is itself worth a recommendation (gitignore guidance) — noted, not scoped here.

</deferred>
