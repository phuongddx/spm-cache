# Phase 8: Drift Read-Back, Fidelity Status & Provenance - Research

**Researched:** 2026-08-29
**Domain:** SwiftPM/xcodebuild resolution behavior + Ruby build pipeline sidecar/status plumbing
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Drift Reporting Mechanism (FID-03)**
- Intended pins = the seeded `<pkg_dir>/Package.resolved` snapshot taken before the build (already
  retained on disk post-build per 07-01-SUMMARY.md, specifically for this comparison)
- Realized pins = re-read `<pkg_dir>/Package.resolved` after the build completes
- Drift reported via `Core::UI.warn` per drifted package (name + intended vs realized version),
  consistent with the Phase 6 DIAG-01 precedent (drift is a warning, never a hard failure)
- Drift never blocks the build — matches the locked Core Value decision that a fidelity violation
  always degrades to source, never hard-fails

**Resolution-Incompatible Handling (FID-04)**
- A package is classified `resolution-incompatible` when re-resolving after seeding fails/changes
  because the package's own manifest requirement excludes the host pin (M2 measurement: 0/17 on the
  reference project — a real but uncommon edge case, not a hot path; no proactive pre-check needed)
- On `resolution-incompatible`, the build proceeds from source for that package — the same fallback
  path a cache miss already takes, never a hard failure
- `ignore_build_errors` must never suppress or mask this status — it is always visible, per the
  explicit ROADMAP/REQUIREMENTS wording
- Not separately persisted — logged for the run and surfaced via `cache list`/build output (DIAG-02);
  re-derived from provenance on the next run, no dedicated marker file

**Provenance Sidecar Format (CACHE-01)**
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

**Fidelity Status Surfacing (DIAG-02)**
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

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope. CACHE-02/CACHE-03 (cache invalidation against
provenance) were explicitly named as Phase 9 territory, not deferred from Phase 8 but never in scope
for it.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| FID-03 | Realized dependency versions are read back after resolution and compared against the intended pins; any drift is reported | Drift Reporting Mechanism section; empirical proof that xcodebuild rewrites `Package.resolved` in place already exists in `.planning/research/STACK.md`/`PITFALLS.md` (Experiment C/H3) — no new reproduction needed |
| FID-04 | A package whose declared requirements genuinely cannot satisfy the host graph falls back to source with a distinct `resolution-incompatible` status, never masked by `ignore_build_errors` | Resolution-Incompatible Handling section; confirmed `ignore_build_errors?` only intercepts *exceptions*, so a status returned on the success path is structurally unmaskable |
| CACHE-01 | Each cached `.xcframework` records the graph provenance it was built against | Provenance Sidecar Format section; exact `.shims.json` code to mirror, with line numbers |
| DIAG-02 | Per-package fidelity status is surfaced in build output and `cache list` | Fidelity Status Surfacing section; confirms `cache list`'s current implementation is a bare `Dir.entries` walker with zero status concept today — a bigger gap than the ROADMAP note implies |
</phase_requirements>

## Summary

The ROADMAP's claim that this phase "reuses the established `.shims.json` sidecar pattern and the
`Core::Diagnostics` / `GraphEntry.Status` surfaces verbatim" is **half right and half misleading**.
The `.shims.json` sidecar pattern (`BuildPipeline#write_shim_sidecar`) is confirmed byte-for-byte
reusable for the provenance sidecar — same write shape, same call sites, same cleanup discipline.
But `Core::Diagnostics` and `GraphEntry.Status` are **not** directly reusable for DIAG-02's Ruby CLI
output: `Core::Diagnostics` is a `doctor`-only check registry (a different command entirely, per
CONTEXT.md's own locked decision that fidelity status belongs in `build` output and `cache list`, not
`doctor`), and `GraphEntry.Status` is a **Swift-side** enum (`hit/missed/ignored/excluded/plugin`)
generated by the companion binary during proxy generation, consumed only by `Cache::Cachemap`'s
Ruby-side stats/viz — it never reaches `cache list`, which today is a completely separate, far
simpler command that just lists directory entries with no status concept at all. DIAG-02's actual
implementation surface is new Ruby code in `lib/spm_cache/spm/build_pipeline.rb`,
`lib/spm_cache/installer/build.rb`, and `lib/spm_cache/command/cache/list.rb` — none of which read
`Core::Diagnostics` or `GraphEntry.Status`.

The drift-read-back mechanism (FID-03) rests on empirically-verified SwiftPM/xcodebuild behavior
already established in this project's own Phase 6/7 research, not assumption: a real reproduction
package (`Alpha` → `swift-argument-parser`) was built on this machine (Xcode 26.3 / Swift 6.2.4) with
a pin violating the manifest's declared range, using **plain `xcodebuild`, no flag** — exactly Phase
7's chosen design. Result: SwiftPM silently re-resolved to the newest satisfying version, **rewrote
`Package.resolved` in the checkout**, and reported `BUILD SUCCEEDED` exit 0
(`.planning/research/STACK.md` Experiment H3, `.planning/research/PITFALLS.md` Pitfall 3/V2). This is
exactly the mechanism FID-03 must detect and FID-04 must classify. The critical implementation
subtlety CONTEXT.md flags — "the comparison is against separately retained intended pins, never
against the file spm-cache itself wrote" — is a real hazard: `pkg_dir/Package.resolved` holds the
REALIZED content once the build finishes (identical to intended only if no drift occurred), so the
"intended" side of the diff must be captured from `resolved_pins_file` (the host's canonical
`Package.resolved`, already threaded into `BuildPipeline.run`), never by re-reading the same on-disk
path a second time.

**Primary recommendation:** Add drift read-back + provenance sidecar write directly inside
`SPM::BuildPipeline`'s success paths (mirroring `write_shim_sidecar`'s exact call sites), reuse
`Core::PackageResolved.pins_or_nil` for parsing both intended and realized pin sets (do not hand-roll
a second `Package.resolved` parser), and rebuild `cache list` from scratch as a per-module reader
(it currently has no per-module concept whatsoever) rather than trying to bolt a status column onto
its existing bare directory listing.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Drift read-back (diff intended vs realized pins) | Ruby build pipeline (`SPM::BuildPipeline`) | — | Runs once per package build, immediately after `xcodebuild`/`swift package resolve` completes; no Swift companion involvement — the companion never sees per-package resolution state |
| Resolution-incompatible classification | Ruby build pipeline (`SPM::BuildPipeline`) | — | Same read-back diff drives both FID-03 (report drift) and FID-04 (classify one drift subtype); one mechanism, two consumers |
| Provenance sidecar write/cleanup | Ruby build pipeline (`SPM::BuildPipeline`) | — | Sibling file I/O next to the xcframework, identical tier to `.shims.json` |
| Fidelity status in `spm-cache build` output | Ruby CLI (`Installer::Build`) | Ruby build pipeline | `Installer::Build#build_single_target` already prints "Cached: ..." per package; natural site for the one-line status, but the status itself can be computed and even printed inside `BuildPipeline.run` for symmetry with existing internal `Core::UI` calls |
| Fidelity status in `cache list` | Ruby CLI (`Command::Cache::List`) | — | Reads the persisted sidecar independent of any build; must not depend on Swift-side `graph.json`, which `cache list` has never consumed |
| `GraphEntry.Status` (hit/missed/ignored/excluded/plugin) | Swift companion (`ProxyGenerator`) | Ruby (`Cache::Cachemap`) | Pre-existing, orthogonal dimension (proxy-wiring decision) — CONTEXT.md correctly identifies this as a *different* axis from fidelity status, not a replacement |

## Standard Stack

No new external dependencies. This phase is pure Ruby (stdlib `json`/`fileutils`) plumbing on top of
existing in-repo modules.

### Core (in-repo, reused)
| Module | Location | Purpose | Why Standard |
|--------|----------|---------|--------------|
| `Core::PackageResolved.pins_or_nil` | `lib/spm_cache/core/package_resolved.rb:59-71` | Tolerant JSON parse of a `Package.resolved` into an array of pin hashes | Already the single parser Phase 6's `doctor` fidelity check uses; reusing it avoids a second, subtly-different `Package.resolved` parser (Pitfall precedent: Phase 6 M1 root cause was exactly two disagreeing parsers/locators) |
| `SPM::ResolvedGraph` | `lib/spm_cache/spm/resolved_graph.rb` | Already provides `RESOLVED_FILENAME` constant and the seed/restore lifecycle Phase 8 diffs around | No new seeding logic needed — Phase 8 only *reads* what Phase 7 already writes |
| `Core::UI.warn`/`Core::UI.info` | used throughout `build_pipeline.rb`, `installer/build.rb` | Existing UI reporting primitives | Matches DIAG-01's established "drift is a warning" precedent exactly |
| `SPMCache::VERSION` | `lib/spm_cache/version.rb:4` | `File.read(File.expand_path("../../VERSION", __dir__)).strip` — a plain string constant | The "spm-cache version" field CACHE-01 requires in the sidecar |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Reusing `Core::PackageResolved.pins_or_nil` | A dedicated `ProvenanceGraph`/pin-diff parser | Rejected — Phase 6's root cause (M1) was precisely *disagreeing* parsers/locators of the same file; a second parser reintroduces that risk class for no benefit, since the existing one already returns a tolerant `nil`-or-array shape suitable for diffing |
| Doctor-registry-based DIAG-02 (`Core::Diagnostics.register`) | Inline `Core::UI` calls in `BuildPipeline`/`Installer::Build` | CONTEXT.md explicitly locked DIAG-02 as *build output* + `cache list`, not a `doctor` check — a `Core::Diagnostics` check only runs when the user types `spm-cache doctor`, which does not satisfy "no package's resolution outcome is unauditable" during a normal build |

**Installation:** None — no new gems.

## Package Legitimacy Audit

Not applicable. This phase installs no external packages (Ruby gems or SwiftPM dependencies); it is
pure in-repo logic on stdlib `json`/`fileutils`.

## Architecture Patterns

### System Architecture Diagram

```
Installer::Build#perform_install
   |
   |  resolved_pins_file = SPM::ResolvedGraph.source_for(...)   [Phase 7, unchanged]
   v
build_single_target(target_name, ...)
   |
   |  calls SPM::BuildPipeline.run(resolved_pins_file: ..., ...)
   v
SPM::BuildPipeline.run
   |
   |-- seed_host_graph(pkg_dir, resolved_pins_file)              [Phase 7, unchanged]
   |     -> writes pkg_dir/Package.resolved = INTENDED pins
   |
   |-- perform_build(...)  [xcodebuild invoked here, no
   |      onlyUsePackageVersionsFromResolvedFile flag]
   |     -> xcodebuild MAY silently re-resolve + REWRITE
   |        pkg_dir/Package.resolved in place if the intended
   |        pin violates the package's own manifest range
   |        (VERIFIED: STACK.md Experiment H3 / PITFALLS.md V2)
   |
   |-- [NEW, Phase 8] read pkg_dir/Package.resolved again = REALIZED pins
   |-- [NEW, Phase 8] diff INTENDED (captured from resolved_pins_file,
   |        never re-derived from pkg_dir post-build) vs REALIZED
   |     -> per-drifted-package Core::UI.warn (FID-03)
   |     -> classify status: host-pinned | resolution-incompatible
   |        | not-graph-pinned (vendored .xcodeproj, pre-existing FID-05)
   |
   |-- write_shim_sidecar(...)                                    [existing]
   |-- [NEW, Phase 8] write <name>.xcframework.provenance.json
   |        { realized_pins, spm_cache_version, config, destinations }
   v
returns output_path  ->  Installer::Build prints "Cached: ..." +
                          [NEW] one status line per package (DIAG-02)

Independently, at any later time:
Command::Cache::List#run
   |-- [NEW] for each *.xcframework in cache_dir (excluding sidecar
   |         files, which is a pre-existing but currently-unaddressed
   |         listing bug -- see Common Pitfalls)
   |-- read <name>.xcframework.provenance.json if present
   |-- print module + fidelity status (fallback: not-graph-pinned
   |    when no sidecar exists)
```

### Recommended Project Structure

No new files/directories. Modifications land in:
```
lib/spm_cache/spm/build_pipeline.rb        # drift read-back + provenance write/cleanup
lib/spm_cache/installer/build.rb           # per-package status line in build output
lib/spm_cache/command/cache/list.rb        # per-module status column
spec/build_pipeline_seeding_spec.rb        # extend, or new spec/build_pipeline_provenance_spec.rb
spec/installer_build_spec.rb               # extend for the new status line
spec/command_cache_list_spec.rb            # NEW — no test file exists for this command today
```

### Pattern 1: Sidecar write/cleanup (verbatim precedent to mirror)

**What:** `.shims.json` is written once per successful build, at the same two call sites that call
`XCFramework::XCFramework#build`, and cleaned up (`rm_f`) at the one call site that replaces an
xcframework without going through that build path.

**Verified exact locations (`lib/spm_cache/spm/build_pipeline.rb`):**

- Write site 1 — `perform_build`, immediately after the main `xcframework.build` call:
  ```ruby
  # lines 163-171
  xcframework = XCFramework::XCFramework.new(
    name: name,
    framework_paths: framework_paths,
    output_path: output_path,
  )
  result = xcframework.build
  write_shim_sidecar(output_path, shim_framework_paths, out_dir)
  FileUtils.rm_rf(tmpdir)
  result
  ```
- Write site 2 — `run_with_scheme` (the scheme-fallback / vendored-checkout path), structurally
  identical, lines 221-229 (`result = xcframework.build` then `write_shim_sidecar(output_path,
  companion_framework_paths, out_dir)`).
- Cleanup site — `copy_prebuilt_binary_target` (the Class E binary-target direct-copy path), lines
  882-905: copies the prebuilt xcframework directly (`FileUtils.cp_r`), never calls
  `write_shim_sidecar` at all, but explicitly does `FileUtils.rm_f("#{output_path}.shims.json")` at
  line 902 with this exact comment: *"A pre-Class-E cache entry for this product may carry a
  `.shims.json` sidecar from when it was still built (and companion-wired) via the normal
  Buildable/xcodebuild path. `cache clean <name>.xcframework` only removes the xcframework itself, so
  a targeted clean+rebuild would otherwise leave that stale sidecar in place."*
- The actual write implementation (`write_shim_sidecar`, lines 843-860):
  ```ruby
  def write_shim_sidecar(output_path, shim_framework_paths, out_dir)
    built_shim_names = shim_framework_paths.filter_map do |shim_name, paths|
      # ... builds each companion xcframework ...
    end
    return if built_shim_names.empty?

    File.write("#{output_path}.shims.json", JSON.generate(built_shim_names))
  end
  ```

**Implication for the provenance sidecar:** an exact parallel write (`File.write("#{output_path}.provenance.json",
JSON.generate({...}))`) fits at write sites 1 and 2 — trivial, since drift read-back's realized-pins
data is naturally computed right there (`pkg_dir` and `resolved_pins_file` are both in scope). The
cleanup rule (CONTEXT.md: "every path that overwrites/replaces an xcframework must also `rm_f` the
stale provenance sidecar") extends line 902's existing pattern with one more `FileUtils.rm_f` call.

**Open design question (not resolved by CONTEXT.md, needs planner decision):** should
`copy_prebuilt_binary_target` (Class E) *write* a fresh provenance sidecar too, or only clean up a
stale one? Unlike the main/scheme-fallback paths, this path never invokes `xcodebuild` at all — SwiftPM
resolves this package as a side effect of an *earlier* `swift package describe`/scheme-listing call
(see `resolve_forwarded_target`, called at line 96, before the binary-target short-circuit at line 97).
Seeding (`seed_host_graph` in `run`, before `perform_build` is ever invoked) still writes the intended
pins into `pkg_dir/Package.resolved` for Class E packages, since they are not automatically vendored-
`.xcodeproj` (that is a distinct classification). Whether that earlier `describe`/scheme-probe call can
itself trigger a silent re-resolution (making drift possible even on this no-xcodebuild path) was not
established by this research pass and is flagged in Open Questions below. CACHE-01's literal
requirement ("each cached `.xcframework` records the graph provenance it was built against") reads as
applying to Class E artifacts too, since they are cached `.xcframework`s — the planner should decide
whether Class E gets `host-pinned`/`resolution-incompatible` (if provably driftable) or a distinct
"no resolution happens here" status, rather than leaving it with no sidecar at all (which `cache list`
would then report as `not-graph-pinned`, potentially inaccurately implying the package can never be
graph-pinned in principle, when in fact it simply short-circuits before any build).

### Pattern 2: `run`'s single success/ensure region already covers all three artifact-producing paths

**What:** `BuildPipeline.run` wraps `perform_build` in one `success = false ... ensure ... unless
success` region (lines 49-61). `perform_build` internally may return via three different routes —
the direct `xcframework.build` path (line 168), a delegated call to `run_with_scheme` (line 153, when
no slices built and a scheme retry succeeds), or `copy_prebuilt_binary_target` (line 98, Class E) —
but **all three routes return through `perform_build`'s return value back into `run`**, since
`run_with_scheme`/`copy_prebuilt_binary_target` are called with an explicit `return` inside
`perform_build`.

**When to use:** This means a *single* insertion point in `run` (right after `result =
perform_build(...)` succeeds, before the `ensure` block, at line 56-57) can perform drift read-back +
provenance write **once**, covering all three paths uniformly — rather than duplicating the logic at
each of the three call sites the way `write_shim_sidecar` is currently duplicated (which exists
because shim-*framework-building* is genuinely different per path, whereas drift-diffing/provenance-
writing only needs `pkg_dir`, `resolved_pins_file`, and the final `output_path`, all of which are
available at the `run` level already). **This is a refinement the planner should consider over
CONTEXT.md's literal per-call-site phrasing** — it would require threading `resolved_pins_file`
through nothing new (it's already a `run` kwarg) and getting `output_path` back from `perform_build`'s
return value (already the case — `result` is `output_path`).

**Trade-off:** doing it once in `run` is simpler and DRYer, but drift/provenance for the Class E path
becomes automatic rather than an explicit choice — reinforcing the need to resolve the Open Design
Question above before committing to this shape.

### Pattern 3: `Core::Diagnostics` — data-driven check registry (the ROADMAP note's actual referent, doctor-only)

**What:** `Core::Diagnostics.register(name, fix_hint:) { |config:| ... }` (`lib/spm_cache/core/diagnostics.rb:36-38`)
registers a check that returns `[:ok|:warn|:fail, message]`; `spm-cache doctor` calls
`Core::Diagnostics.run_all` (`lib/spm_cache/command/doctor.rb:33`). The existing `lock_graph_fidelity`
check (lines 64-93, registered at line 289) is DIAG-01's implementation — a **static**, no-build
comparison of `spm-cache.lock` vs the host `Package.resolved`.

**Why this is NOT DIAG-02's mechanism:** DIAG-02 per CONTEXT.md's locked decision surfaces in
`spm-cache build` output and `cache list` — two commands that run independently of `doctor` and, for
`build`, that run mid-build with fresh per-package data no static check could have. `Core::Diagnostics`
is confirmed doctor-only: nothing in `command/cache/list.rb` or `installer/build.rb` currently
references it. The ROADMAP's phrase "reuses ... `Core::Diagnostics` ... verbatim" should be read as
"reuses the *drift-is-a-warning-not-a-failure posture* `Core::Diagnostics`'s `lock_graph_fidelity`
established," not "calls into this module."

### Anti-Patterns to Avoid
- **Deriving "intended" pins by re-reading `pkg_dir/Package.resolved` at any point after seeding:**
  once the build starts, that path may already hold the realized (possibly drifted) content by the
  time you get around to reading it "for the intended side." Capture intended content from
  `resolved_pins_file` (or immediately at seed time, before `perform_build` runs), store it in memory,
  and only read `pkg_dir/Package.resolved` a second time, post-build, for the realized side.
- **Writing a second `Package.resolved` parser.** `Core::PackageResolved.pins_or_nil` already exists,
  is tolerant (never raises), and is the same parser Phase 6's `doctor` check uses — reuse it for both
  the intended-pins and realized-pins reads so there is exactly one notion of "what a pin means" in
  the codebase (same argument that motivated FID-06's canonical-locator consolidation).
  Diagnostics also already has extraction helpers worth mirroring exactly: `lock_pin_value`/
  `host_pin_value` (`core/diagnostics.rb:155-164`) resolve `revision` over `version` — the same
  precedence `Lockfile.swift`/`UmbrellaGenerator.swift` use — reuse that precedence rule rather than
  inventing a new one for the intended-vs-realized diff.
- **Treating `Core::Diagnostics`/`GraphEntry.Status` as call targets.** Confirmed: neither is wired
  into `build`/`cache list` today; DIAG-02 is new Ruby code in those two commands' own files.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Parsing `Package.resolved` (intended or realized side) | A new bespoke JSON walker | `Core::PackageResolved.pins_or_nil(path)` | Already tolerant (`nil` on unreadable/malformed, `[]` on zero pins, distinguishable), already used by the closest existing precedent (DIAG-01's `lock_graph_fidelity`) |
| Resolving `revision` vs `version` precedence for a pin value | A new "which field wins" rule | `Core::Diagnostics.lock_pin_value`/`host_pin_value` pattern (`core/diagnostics.rb:155-164`) — mirror, or extract to a shared helper if the planner prefers | Matches `Lockfile.swift:118-126`'s own precedence (revision wins over version); a second, differently-ordered precedence rule would silently disagree with the umbrella generator about what "the pin" even means |
| Sidecar JSON write/cleanup mechanics | A new file-lifecycle abstraction | `File.write("#{output_path}.provenance.json", JSON.generate({...}))` + `FileUtils.rm_f` at the same sites `.shims.json` uses | Exact, already-proven pattern; CONTEXT.md explicitly mandates mirroring it |

**Key insight:** every piece of machinery FID-03/FID-04/CACHE-01 needs (a tolerant `Package.resolved`
parser, a pin-value precedence rule, a sidecar-file lifecycle) already exists in this codebase from
Phase 6/7. This phase's actual work is wiring, not invention — the risk is a subtly-different
reimplementation of one of these three, not the absence of a library.

## Common Pitfalls

### Pitfall 1: Comparing the post-build file against itself
**What goes wrong:** Reading `pkg_dir/Package.resolved` once, "before the build" (but really at some
point after seeding already happened), and again "after," and treating the first read as ground truth
for "intended" — when in fact both reads are of the file spm-cache seeded, and if xcodebuild rewrote it
in between, the "before" read (if taken late enough, e.g. lazily) could itself already reflect the
rewritten content.
**Why it happens:** `seed!` writes the intended content directly into `pkg_dir/Package.resolved`
(the same path xcodebuild will later potentially rewrite) — there is only one physical file, so which
read you treat as "intended" is a code-structure decision, not something the filesystem enforces.
**How to avoid:** Capture "intended" from `resolved_pins_file` (`File.binread`/`Core::PackageResolved.pins_or_nil`
on that path specifically) or from an in-memory value captured at `seed!` time — never from a *second*
read of `pkg_dir/Package.resolved` taken after `perform_build` has already run.
**Warning signs:** A drift-detection spec that always reports zero drift no matter what the stubbed
`xcodebuild` "wrote," because the test's "intended" and "realized" reads both point at the same
already-mutated stub file.

### Pitfall 2: `ignore_build_errors?` cannot mask a status it never sees — but only if the status returns via the success path
**What goes wrong:** If `resolution-incompatible` classification is implemented by having
`BuildPipeline.run` *raise* a special exception that `Installer::Build#build_single_target`'s rescue
then reinterprets, `ignore_build_errors?` (line 177 of `installer/build.rb`) WOULD swallow it — exactly
what CONTEXT.md forbids ("`ignore_build_errors` must never suppress or mask this status").
**Why it happens:** `build_single_target`'s existing `rescue => e` block (`installer/build.rb:176-181`)
is generic — it catches anything `BuildPipeline.run` raises, warn-and-continue if
`@config.ignore_build_errors?`, else re-raise.
**How to avoid:** `resolution-incompatible` must be a **return value**, not an exception —
`BuildPipeline.run` already returns successfully (the build proceeds from source, matching the
existing cache-miss fallback shape) for this case; the status must be reported via `Core::UI` calls
made *inside* the success path, or via a richer return value, never via `raise`.
**Warning signs:** A spec that stubs `ignore_build_errors?` to `true` and finds the
`resolution-incompatible` line silently missing from output.

### Pitfall 3: `xcodebuild`/`swift package resolve` silently discards an out-of-range pin and rewrites the file — this IS the mechanism, not a hypothetical
**What goes wrong:** Assuming a hard failure or a warning would naturally occur when the seeded pin
violates a package's own manifest range.
**Why it happens:** SwiftPM's default posture ("resolve to something that works") applies even to a
freshly-seeded `Package.resolved` unless `-onlyUsePackageVersionsFromResolvedFile`/
`--force-resolved-versions` is passed — and Phase 7 deliberately did NOT add that flag (D-02 in
07-01-SUMMARY.md: *"xcodebuild silently upgrades a seeded pin below a package's manifest floor rather
than hard-failing; detecting that drift is Phase 8's read-back job"*).
**How to avoid:** Design FID-03/FID-04 assuming this WILL happen silently — no build-time signal
(exit code, log line) distinguishes a satisfied pin from a silently-discarded one. Read-back is the
only detection mechanism; there is no shortcut.
**Warning signs:** none at build time — that is exactly the danger. `BUILD SUCCEEDED`, exit 0, in both
the honored and the silently-discarded case.
**Evidence (empirical, not assumed):** `.planning/research/STACK.md` lines 32-49, Experiment Matrix
row H3: *"`0.5.0` (violating) | `xcodebuild …` no flag | Silently re-resolved to `1.8.2`, `BUILD
SUCCEEDED` ← this is spm-cache's bug today"* — executed on this machine, Xcode 26.3/Swift 6.2.4,
against a purpose-built reproduction package (`Alpha` → `swift-argument-parser`). Corroborated in
`.planning/research/PITFALLS.md` lines 100-121 (Pitfall 3) and lines 194-215 (Pitfall 6, "And
xcodebuild writes back. Verified (V2)"). No new reproduction is needed for Phase 8 planning — this
question was already answered empirically during Phase 6/7 research, using the exact no-flag design
Phase 7 shipped.

### Pitfall 4: `cache list` today has no per-module concept at all — a bigger gap than "add a column"
**What goes wrong:** Assuming `cache list` already has a per-module row/loop that a fidelity-status
column can be appended to.
**Why it happens:** `Command::Cache::List#run` (`lib/spm_cache/command/cache/list.rb:11-23`) currently
does exactly this and nothing more:
```ruby
Dir.entries(cache_dir).sort.each do |entry|
  next if entry.start_with?(".")
  puts "  #{entry}"
end
```
This lists **every** top-level filesystem entry under `~/.spm-cache/<config>/` — which today already
includes sidecar files like `Foo.xcframework.shims.json` as a separate printed line (since it doesn't
start with `.`), a pre-existing latent bug this phase's own `.provenance.json` sidecar would make
worse (one more spurious "package" line) unless addressed.
**How to avoid:** Rebuild `cache list` to iterate only `*.xcframework` entries specifically (e.g.
`Dir.glob(File.join(cache_dir, "*.xcframework"))`), derive the module name from the directory name,
then look up `<entry>.provenance.json` for status — rather than trying to retrofit a status lookup
onto the existing bare `Dir.entries` loop.
**Warning signs:** `cache list` output containing a line like `  Alamofire.xcframework.shims.json`
alongside `  Alamofire.xcframework` — confirms the pre-existing bug is live.

## Code Examples

### Reusing `Core::PackageResolved.pins_or_nil` for both sides of the diff

```ruby
# Source: lib/spm_cache/core/package_resolved.rb:59-71 (existing, verified)
def pins_or_nil(path)
  return nil unless path && File.exist?(path)

  data = JSON.parse(File.read(path))
  return nil unless data.is_a?(Hash)

  value = data['pins'] || []
  return nil unless value.is_a?(Array)

  value.select { |pin| pin.is_a?(Hash) }
rescue JSON::ParserError, TypeError
  nil
end
```

### Existing precedent for pin-value precedence (revision wins over version)

```ruby
# Source: lib/spm_cache/core/diagnostics.rb:155-164 (existing, verified)
def lock_pin_value(pkg)
  revision = pkg['revision']
  revision.to_s.empty? ? pkg['version'] : revision
end

def host_pin_value(pin)
  state = pin['state'] || {}
  revision = state['revision']
  revision.to_s.empty? ? state['version'] : revision
end
```

### Existing sidecar write shape to mirror for `.provenance.json`

```ruby
# Source: lib/spm_cache/spm/build_pipeline.rb:843-860 (existing, verified — shims.json precedent)
def write_shim_sidecar(output_path, shim_framework_paths, out_dir)
  built_shim_names = shim_framework_paths.filter_map do |shim_name, paths|
    # ... (shim-specific logic) ...
  end
  return if built_shim_names.empty?

  File.write("#{output_path}.shims.json", JSON.generate(built_shim_names))
end
```

### Existing cleanup precedent (Class E direct-copy path)

```ruby
# Source: lib/spm_cache/spm/build_pipeline.rb:882-905 (existing, verified)
def copy_prebuilt_binary_target(target_name, product_name, pkg_dir, out_dir)
  # ...
  output_path = File.join(out_dir, "#{product_name}.xcframework")
  FileUtils.rm_rf(output_path)
  FileUtils.cp_r(source, output_path)

  # A pre-Class-E cache entry for this product may carry a `.shims.json`
  # sidecar from when it was still built via the normal Buildable/xcodebuild
  # path. `cache clean <name>.xcframework` only removes the xcframework
  # itself, so a targeted clean+rebuild would otherwise leave that stale
  # sidecar in place.
  FileUtils.rm_f("#{output_path}.shims.json")
  # Phase 8 adds an analogous FileUtils.rm_f("#{output_path}.provenance.json") here.

  output_path
end
```

## State of the Art

Not applicable — no external library/API version drift is relevant to this phase. The only
"external" surface (SwiftPM/xcodebuild flag behavior) was empirically re-verified on the current
toolchain (Xcode 26.3 / Swift 6.2.4) during Phase 6/7 research and has not changed since (this same
session, same milestone).

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `copy_prebuilt_binary_target`'s earlier `swift package describe`/scheme-probe call (line 96, before the binary-target short-circuit) cannot itself trigger a silent re-resolution that rewrites `pkg_dir/Package.resolved` | Pattern 1 / Open Questions | If it CAN, Class E packages need the same drift-detection treatment as the main build path, not just sidecar cleanup — the planner should decide this rather than assume it's a non-issue, since this research pass did not empirically test it (M4 was ruled moot for a different reason — vendored-xcodeproj — not for Class E) |
| A2 | Doing drift-read-back + provenance write once in `run` (Pattern 2) rather than duplicated at each of the three `write_shim_sidecar` call sites is a valid simplification the planner can choose | Pattern 2 | If some invariant depends on the per-path duplication (e.g. `run_with_scheme`'s companion-framework bookkeping differs meaningfully), consolidating could miss a case-specific nuance; low risk since `pkg_dir`/`resolved_pins_file`/`output_path` are identical in shape across all three paths |

## Open Questions

1. **Does Class E's `copy_prebuilt_binary_target` path need a fresh provenance sidecar write, or only stale-sidecar cleanup?**
   - What we know: CONTEXT.md's Reusable Assets section only calls out this path for *cleanup*
     (mirroring `.shims.json`'s `rm_f`), not for writing a new sidecar. But CACHE-01 literally requires
     provenance for "each cached `.xcframework`," and this path produces one.
   - What's unclear: whether any resolution/rewrite can happen on this no-xcodebuild path at all (see
     Assumption A1), and if not, what fidelity status a package with no resolution step should report
     (`host-pinned` trivially, since the seeded pin was never contradicted? or a distinct status the
     locked three-value enum doesn't currently have room for?).
   - Recommendation: planner should explicitly decide and record this — either "Class E always reports
     `host-pinned` (no resolution step means no possible drift)" or introduce a documented exception,
     but should not leave Class E silently falling back to the `not-graph-pinned` default just because
     no sidecar was written.

2. **Single consolidated insertion point in `run` vs. per-call-site duplication (Pattern 2)?**
   - What we know: all three artifact-producing paths return through `perform_build`'s return value
     back to `run`, so a single insertion point after `result = perform_build(...)` succeeds would work
     mechanically.
   - What's unclear: whether CONTEXT.md's phrasing ("at the same call site `.shims.json` is written
     today" — plural, since `.shims.json` is written at two sites) was meant literally as a locked
     decision or as a rough pointer to "wherever the xcframework is finalized."
   - Recommendation: the planner has latitude here since CONTEXT.md's "Claude's Discretion" section is
     empty but the underlying phrasing is ambiguous on this specific point — either shape satisfies the
     stated decisions; consolidating in `run` is simpler and DRYer per the Coding Principles' "Simplicity
     First," so is the recommended default absent a reason to duplicate.

## Environment Availability

Skipped — this phase has no new external dependencies (no new gems, no new CLI tools). All
functionality is Ruby stdlib (`json`, `fileutils`) plus in-repo modules already present in
`Gemfile.lock`.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | RSpec (existing, confirmed via `spec/spec_helper.rb` and all files read this session) |
| Config file | `.rspec` / `spec/spec_helper.rb` (pre-existing) |
| Quick run command | `bundle exec rspec spec/build_pipeline_seeding_spec.rb spec/installer_build_spec.rb spec/cachemap_spec.rb` |
| Full suite command | `bundle exec rspec` (342 examples, 0 failures as of Phase 7 completion) |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| FID-03 | Drift between intended and realized pins is detected and `Core::UI.warn`-reported per package | unit | `bundle exec rspec spec/build_pipeline_provenance_spec.rb` | ❌ Wave 0 — new file |
| FID-04 | A resolution-incompatible package builds from source with a distinct status, `ignore_build_errors?` cannot mask it | unit | `bundle exec rspec spec/build_pipeline_provenance_spec.rb -e "resolution-incompatible"` | ❌ Wave 0 — new file |
| CACHE-01 | `.xcframework.provenance.json` sidecar written with realized pins/version/config/destinations; cleaned up on Class E replace | unit | `bundle exec rspec spec/build_pipeline_provenance_spec.rb -e "provenance sidecar"` | ❌ Wave 0 — new file |
| DIAG-02 (build output) | One status line per package in `spm-cache build` output | unit | `bundle exec rspec spec/installer_build_spec.rb -e "fidelity status"` | ❌ Wave 0 — extend existing file |
| DIAG-02 (cache list) | `cache list` names each cached module's fidelity status, falling back to `not-graph-pinned` when no sidecar exists | unit | `bundle exec rspec spec/command_cache_list_spec.rb` | ❌ Wave 0 — new file, no test exists for this command at all today |

### Sampling Rate
- **Per task commit:** the specific new/extended spec file's quick command
- **Per wave merge:** `bundle exec rspec`
- **Phase gate:** Full suite green before `/gsd-verify-work`

### Wave 0 Gaps
- [ ] `spec/build_pipeline_provenance_spec.rb` (or extend `spec/build_pipeline_seeding_spec.rb`) — covers FID-03, FID-04, CACHE-01
- [ ] `spec/command_cache_list_spec.rb` — covers DIAG-02's `cache list` half; **no test file for this command exists anywhere in the repo today** (confirmed by `find spec -iname "*cache*list*"` returning nothing)
- [ ] Extend `spec/installer_build_spec.rb` — covers DIAG-02's build-output half
- Framework install: none — RSpec is already fully configured; no new gem needed

### Established Test Conventions (from Phase 7 precedent, `spec/build_pipeline_seeding_spec.rb`)
- Real filesystem via `Dir.mktmpdir`/`FileUtils`, not a mocked filesystem — `pkg_dir`, `out_dir`,
  `resolved_pins_file` are real temp paths, cleaned up in `after { FileUtils.rm_rf(tmpdir) }`.
- `Buildable`/`Desc::Description`/`XCFramework::XCFramework` are stubbed via `instance_double`/`double`
  at the shell boundary — `Core::Sh.run`/`.capture_output` is the true boundary that gets stubbed in
  the "byte-identical to v0.3.0" spec block; everything else runs real code.
- UI assertions use `expect { ... }.to output(/regex/).to_stdout` (see the "not graph-pinned" example)
  — the same pattern should be used to assert the new fidelity-status line and drift warning text.
  Note `Core::UI.warn` output stream should be confirmed (likely `$stderr` or `$stdout` depending on
  `Core::UI`'s implementation — check `lib/spm_cache/core/log.rb` or wherever `Core::UI` is defined
  before writing the assertion, since `output(...).to_stdout` only matches stdout).
- `hash_including(...)` for asserting kwargs passed into stubbed collaborator calls (see the
  `Installer::Build` "threading" spec).
- One `RSpec.describe` block per named behavior slice within a file (multiple `describe
  SPMCache::SPM::BuildPipeline, "<slice name>"` blocks in the same file is the established style, not
  one monolithic describe).

## Security Domain

Not applicable to this phase in the ASVS sense — no new authentication, session, network input, or
cryptographic surface is introduced. The only "input" this phase parses is a `Package.resolved` file
already trusted as the host project's own resolved graph (same trust boundary as the pre-existing
`Core::PackageResolved`/`DiffDetector` parsers), using the same tolerant, non-raising parse discipline
already established (`pins_or_nil` never raises on malformed input).

## Sources

### Primary (HIGH confidence — read this session)
- `lib/spm_cache/spm/build_pipeline.rb` (full read, lines 1-240 and 820-968) — exact seed/build/sidecar/cleanup call sites and line numbers
- `lib/spm_cache/spm/resolved_graph.rb` (full read) — seed!/restore!/vendored_xcodeproj? mechanics
- `lib/spm_cache/cache/cachemap.rb` (full read) — hit/missed/ignored/excluded/plugin status-bucket pattern
- `lib/spm_cache/command/cache/list.rb` (full read) — confirmed current bare `Dir.entries` implementation, no status concept
- `lib/spm_cache/command/cache/clean.rb` (full read) — confirmed CACHE-03 (provenance sweep on clean) is out of Phase 8 scope
- `lib/spm_cache/core/diagnostics.rb` (full read) — confirmed `Core::Diagnostics` is doctor-only; `lock_graph_fidelity` precedent for drift-as-warning
- `lib/spm_cache/core/package_resolved.rb` (partial read, lines 1-90) — confirmed `pins`/`pins_or_nil` parser to reuse
- `lib/spm_cache/installer/build.rb` (full read) — confirmed `build_single_target`'s "Cached: ..." line and `ignore_build_errors?`'s exception-only scope
- `lib/spm_cache/spm/xcframework/xcframework.rb` (partial read) — confirmed `.build` returns a bare path string
- `lib/spm_cache/spm/build.rb`, `lib/spm_cache/spm/pkg/base.rb` (grep) — confirmed `DESTINATIONS`/`DEFAULT_DESTINATIONS` shape for the sidecar's "destination set" field
- `lib/spm_cache/version.rb` — confirmed `SPMCache::VERSION` constant source
- `tools/spm-cache-proxy/Sources/Core/Generator/ProxyGenerator.swift` (full `GraphEntry`/`generate` read) — confirmed `GraphEntry.Status` is Swift-side, proxy-generation-only, never reaches `cache list`
- `tools/spm-cache-proxy/Sources/Core/Generator/GraphGenerator.swift` (full read) — confirmed `graph.json` consumer chain
- `spec/build_pipeline_seeding_spec.rb` (full read, 367 lines) — established test conventions to follow
- `spec/installer_build_spec.rb` (grep + partial) — confirmed existing describe-block structure
- `spec/cachemap_spec.rb` (full read) — confirmed `Cachemap` test conventions
- `.planning/phases/07-host-faithful-checkout-seeding/07-01-SUMMARY.md` (full read) — confirmed the exact "seeded file left in place for Phase 8's read-back" handoff note and D-02's no-flag rationale
- `.planning/phases/08-drift-read-back-fidelity-status-provenance/08-M2-MEASUREMENT.md` (required reading, full) — 0/17 resolution-incompatible, not a rescope trigger
- `.planning/research/STACK.md` (lines 1-115) — Experiment Matrix (A-H), empirically executed on this machine, Xcode 26.3/Swift 6.2.4, against a real reproduction package
- `.planning/research/PITFALLS.md` (lines 80-215) — Pitfall 3 (silent re-resolution), Pitfall 4 (incompatible-graph policy), Pitfall 5 (cache key/provenance), Pitfall 6 (shared-checkout rewrite hazard) — all corroborating STACK.md's empirical findings
- `.planning/research/SUMMARY.md` (grep + partial) — root-cause model, cross-referenced against STACK.md/PITFALLS.md
- `.planning/REQUIREMENTS.md`, `.planning/STATE.md` (full read, required reading) — locked scope, M2/M4 measurement history

### Secondary (MEDIUM confidence)
None used — every claim above is either read directly from source this session or drawn from this
project's own prior empirically-verified research (Phase 6/7), which itself is tagged HIGH confidence
in `.planning/research/STACK.md`'s own header.

### Tertiary (LOW confidence)
None.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no external dependencies; all reused modules read directly this session
- Architecture: HIGH — every integration point (call site + line number) read directly from source
- Pitfalls: HIGH — the core drift mechanism is empirically verified on this machine (Phase 6/7 research), not assumed; the two Open Questions are honestly flagged as genuinely undetermined rather than guessed at

**Research date:** 2026-08-29
**Valid until:** No expiry pressure — in-repo code and empirically-verified toolchain behavior on a
pinned Xcode/Swift version (26.3/6.2.4) do not drift on their own; re-verify only if the milestone's
toolchain version changes before Phase 8 executes.
