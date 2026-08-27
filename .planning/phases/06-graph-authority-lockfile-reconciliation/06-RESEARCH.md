# Phase 6: Graph Authority — Lockfile Reconciliation - Research

**Researched:** 2026-08-27
**Domain:** Ruby file-I/O reconciliation over SwiftPM `Package.resolved` / `spm-cache.lock`; RSpec hermetic seams
**Confidence:** HIGH (every claim below is a file I opened with `Read` this session, or a command I ran and pasted the output of)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Reconciliation Semantics**

- A package present in `spm-cache.lock` but absent from the host's `Package.resolved` is **dropped**. The phase goal is that the lock describes the *current* graph; retaining a removed package makes the umbrella declare a dependency the app no longer has. This is not a corner case — it is 100% of the reference project's lock today (see Existing Code Insights).
- A package present in the host's `Package.resolved` but absent from the lock is **added with an empty `products[]`**, leaving existing enrichment to populate products later. This mirrors the shape `generate_lockfile_from_resolved` already produces on first run.
- Reconciliation runs **whenever `DiffDetector` reports a non-empty diff**, before umbrella generation. On the fast path (empty diff) the lock already agrees with the host graph, so there is nothing to reconcile. This matches the success criterion's wording ("after a non-fast-path run") and avoids rewriting the lock on every invocation.
- When the host's `Package.resolved` is missing or unreadable, **warn once and leave the lock untouched** — never crash, and never treat the absent file as an empty graph. Treating it as empty would, combined with the drop rule above, erase the entire lock. This matches the existing malformed-`Package.resolved` handling in `command/init.rb:153-169`.
- Enriched `products[]` must survive reconciliation intact for every package that remains in the graph (success criterion 2). Reconciliation updates `version`/`revision` only.

**doctor Fidelity Check (DIAG-01)**

- The check compares **set membership AND version**, not just versions on the intersection.
- Drift produces a **`:warn`** verdict with the fix hint "run `spm-cache use` to reconcile".
- Comparison uses **`revision` primarily, falling back to `version`** when no revision is held.
- When no lockfile exists yet the check reports **`:ok`**.
- The check is static: it reads two files and compares them. It must not run a build, resolve, or shell out.

**M1 Measurement**

- Reproduce against the **`feature/spm-cache-integration` branch** of the reference project.
- Additionally record **`main`'s zero-overlap finding** as already-captured field evidence.
- Attribution is recorded in **Phase 6 SUMMARY.md plus a dated STATE.md decision**.
- If reconciliation alone fully explains the field case, **Phase 7 still proceeds, re-scoped by the finding**.

### Claude's Discretion

- Internal structure of `Core::PackageResolved` (the new single locator/parser collapsing five duplicated globs), method naming, and how reconciliation is factored out of `generate_lockfile_from_resolved`.
- Spec organization and fixture shape, subject to the hermetic `Core::Sh` seam convention.
- Exact wording of warnings and the `doctor` report line, subject to the existing marker-report format.

### Deferred Ideas (OUT OF SCOPE)

- Seeding the host graph into per-package checkouts — Phase 7 (FID-02).
- Post-resolve read-back and the `resolution-incompatible` status — Phase 8 (FID-03, FID-04).
- Cache invalidation on provenance mismatch — Phase 9 (CACHE-02).
- Whether the `spm-cache.lock` being untracked by git in the reference project is itself worth a recommendation (gitignore guidance) — noted, not scoped here.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description (verbatim, `.planning/REQUIREMENTS.md:10,24`) | Research Support |
|----|-------------|------------------|
| FID-01 | "`spm-cache.lock` package `version`/`revision` reconcile from the host project's `Package.resolved` on every non-fast-path run, preserving enriched `products[]`" | Q2 (writable vs. frozen keys), Q3 (exact insertion point), Q1 (locator the reconciler must share with `DiffDetector`), **Finding A** (the locator currently returns the wrong file — reconciling against it would be a no-op on the reference project) |
| DIAG-01 | "A `doctor` check compares `spm-cache.lock` against the host `Package.resolved` statically, requiring no build" | Q4 (register signature, `:warn` → exit 0 confirmed), Q5 (hermetic seams) |

[VERIFIED: .planning/REQUIREMENTS.md:10,24 — quoted verbatim above]
</phase_requirements>

## Summary

The diagnosis handed to this research (lock frozen at first creation by `installer.rb:166`) is confirmed. But a **second, independent defect was measured this session that changes the phase's shape**: `Dir.glob(File.join(project_path, "**/Package.resolved")).find { … }` — the exact idiom duplicated at all five sites — resolves to the **wrong file** on the reference project. The reference `.xcodeproj` bundle contains two `Package.resolved` files, and Ruby's `Dir.glob` returns the stale git-ignored nested copy *first*. spm-cache has therefore been reading a phantom 8-pin host graph (Jul 12) instead of the real 17-pin one (Aug 13) — and those 8 phantom pins are **byte-for-byte the 8 packages in `spm-cache.lock`**. The "0 intersection" recorded in CONTEXT.md is between the lock and the file spm-cache *never reads*.

The consequence for planning is direct: **FID-01 implemented over the current locator is a no-op on the reference project.** Reconciling `version`/`revision` from the phantom resolved graph writes back exactly what is already there; the drop rule drops nothing; success criterion 1 (re-running `DiffDetector` returns an empty diff) would pass *vacuously* because both sides read the same wrong file. Candidate disambiguation must therefore be part of `Core::PackageResolved`, not deferred — and it is a deliberate, observable behavior change at four of the five call sites, which needs to be planned as such rather than smuggled in under "internal structure."

Everything else is mechanical and low-risk. The reconciliation surface is small and well-bounded (`packages[].version`, `packages[].revision`, set membership). The insertion point is unambiguous (`installer.rb` `sync_lockfile`, between line 133 and line 134). The `Diagnostics.register` contract is a two-line block returning `[status, message]`, and `:warn` provably does **not** exit 1. The hermetic seams already exist and need no new infrastructure — but three existing `doctor` assertions hard-code the check count and will fail the moment DIAG-01 registers.

**Primary recommendation:** Build `Core::PackageResolved` as a *deterministic-preference* locator (canonical Xcode path → workspace path → filtered recursive glob), collapse the five globs onto it, then add reconciliation as a self-contained step with its own `save` between `installer.rb:133` and `:134`. Plan the locator change and the check-count spec updates as explicit tasks with their own verification, because both are behavior changes to a field-hardened tool.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Locate + parse host `Package.resolved` | `Core::PackageResolved` (new, Ruby) | — | Single locator; the pin source and the change detector must agree by construction, not by coincidence |
| Compute lock-vs-host diff | `Core::DiffDetector` (Ruby) | — | Already authoritative; becomes a consumer of the new locator |
| Reconcile lock from host graph | `Installer` (Ruby, `sync_lockfile`) | `Core::Lockfile` | Lock mutation belongs where the lock is already loaded/saved in-run |
| Report drift statically | `Core::Diagnostics` check (Ruby) | `Core::PackageResolved` | Registry is the single source of truth for `doctor`; no command change needed |
| Emit umbrella pins | `Core::Lockfile.swift` + `UmbrellaGenerator.swift` | — | Unchanged this phase — Phase 6 changes only *which graph the lock describes* |

## Standard Stack

No new dependencies. This phase is pure Ruby stdlib + the existing gem surface.

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Ruby | 3.2.3 (`ruby -v`, this session) | Host language | Gemspec requires >= 3.1 |
| `json` (stdlib) | bundled | Parse `Package.resolved` / `spm-cache.lock` | Already the only parser used at every site |
| `fileutils` (stdlib) | bundled | `mkdir_p` in `Lockfile#save` | Already required |
| RSpec | 3.13 (rspec-core 3.13.6) | Specs | Existing suite, 258 examples |
| `xcodeproj` | as locked in Gemfile.lock | Only for `merge_project_refs` / `detect_platforms` | Already a dependency |

**Installation:** none. `## Package Legitimacy Audit` is **N/A for this phase** — no external package is installed, so no registry verification is required.

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Deterministic preference-ordered locator | `Dir.glob(...).max_by { File.mtime }` | mtime would also pick correctly on the reference project (Aug 13 > Jul 12) but is non-deterministic under fresh checkout/CI where mtimes are all clone-time. Prefer explicit path preference; use mtime only as a last-resort tie-break inside the recursive tier. |
| Reconcile in `sync_lockfile` | Reconcile inside `generate_lockfile_from_resolved` by deleting the `File.exist?` guard | Deleting the guard makes first-run generation and steady-state reconciliation the same code path, which would clobber `products[]`, `dependencies`, and `platforms` (see Q2). Keep them separate. |

---

## Q1 — The Five Glob Sites: Are They Safely Unifiable?

### Per-site inventory (all five read this session)

| # | Site | Search root | Pattern | Fallback | Selection | Error handling at the caller |
|---|------|-------------|---------|----------|-----------|------------------------------|
| 1 | `installer.rb:169` | `@project_path` (the `.xcodeproj`) | `**/Package.resolved` | none | `.find { \|f\| File.exist?(f) }` | `return unless resolved` (line 171) — silent no-op. **`JSON.parse` at line 173 is NOT rescued** — a malformed host resolved raises out of `use`. |
| 2 | `core/diff_detector.rb:150-155` | `@project_path`, **then `File.dirname(@project_path)`** | `**/Package.resolved` | **yes — parent dir recursive** | `.find { \|f\| File.exist?(f) } \|\| <fallback>.find { … }` | caller guards `if resolved && File.exist?(resolved)` (line 127); **`JSON.parse` at line 128 is NOT rescued** |
| 3 | `core/watcher.rb:118` | `project_path` | `**/Package.resolved` | none | `.find { \|f\| File.exist?(f) }` | `[resolved, pbxproj].compact` (line 122) — nil tolerated, file simply not watched |
| 4 | `command/init.rb:196` | `project_path` | `**/Package.resolved` | none | `.find { \|f\| File.exist?(f) }` | most tolerant: `if resolved && File.exist?` + `rescue JSON::ParserError, TypeError` + `data.is_a?(Hash)` check, each warning and degrading (`init.rb:159-171`) |
| 5 | `command/use.rb:83` | `project_path` | `**/Package.resolved` | none | `.find { \|f\| File.exist?(f) }` | `unless resolved_path` → warn + `return` (use.rb:54-57), `--watch` declines to start |

Verbatim, the shared idiom — identical at sites 1, 3, 4, 5 modulo whitespace [VERIFIED: lib/spm_cache/command/init.rb:195-197]:

```ruby
      def find_package_resolved(project_path)
        Dir.glob(File.join(project_path, '**/Package.resolved')).find { |f| File.exist?(f) }
      end
```

### What a unified `Core::PackageResolved` must preserve

1. **Return `nil`, never raise, when no candidate exists.** All five callers treat nil as a normal state with five *different* responses (silent skip / guarded skip / omit-from-watchlist / seed-empty-with-info / warn-and-decline). The locator must not centralize that decision.
2. **Parse tolerance must be opt-in per caller, or the tolerant behavior must be adopted everywhere deliberately.** Sites 1 and 2 currently raise on malformed JSON; site 4 rescues `JSON::ParserError, TypeError` and additionally rejects a non-Hash root. If the unified parser is tolerant-by-default, sites 1 and 2 change from "crash loudly" to "silently behave as if absent" — which, combined with the locked drop rule, is exactly the erase-the-lock scenario CONTEXT.md forbids. Recommended shape: `locate` (path or nil) and `pins` / `load` with an explicit `tolerant:` or a separate `load!`; the reconciler uses the strict-detect-then-warn form so it can distinguish "unreadable" (→ leave lock untouched) from "readable and empty".
3. **The parent-directory fallback must stay opt-in and only site 2 may take it.** Only `DiffDetector` has it today. Handing it to the other four is a behavior change with a proven hazard: the reference project has `spm-cache/packages/umbrella/Package.resolved` and `spm-cache/packages/proxy/Package.resolved` sitting one level up from the `.xcodeproj` [VERIFIED: `find . -name Package.resolved -not -path "*/.build/*"` in the reference project, this session — output pasted in Finding A]. A fallback that reaches those makes spm-cache's own generated artifact the "host graph".
4. **Pin normalization must remain `DiffDetector`'s, not the locator's.** `identity_key` / `normalize_url` (`diff_detector.rb:195-231`) handle ssh-vs-https, `.git` suffix, and `file://`; three existing specs assert exactly those equivalences (`diff_detector_spec.rb:83,95` and the local-ref cases at `:223-244`). The reconciler must reuse that keying rather than reimplement it, or it will drop packages whose URL merely spells differently in the lock vs. the resolved file.
5. **The `spm-cache` proxy ref exclusion must survive.** `diff_detector.rb:179-181` skips a local ref whose path includes `spm-cache/packages/proxy`; `diff_detector_spec.rb:233-243` asserts it.

### Call sites that CANNOT share the fully-unified path

- **Site 2 (`DiffDetector`) cannot share a fallback-free locator**, and the other four cannot share a fallback-*ful* one. This is the one genuine divergence: unify the *primary* lookup for all five, expose the parent-dir fallback as an explicit argument that only `DiffDetector` passes.
- **Site 3 (`Watcher`) needs a path even when the file is currently absent-but-expected?** No — verified it does not: `resolve_watched_files` compacts nils and `file_signature` returns nil for a missing path (`watcher.rb:129-134`). Site 3 can share cleanly.
- **Site 5 (`use --watch`) is the only caller whose root is a *relative* path** — `find_project` is `Dir.glob('*.xcodeproj').first` [VERIFIED: lib/spm_cache/command/use.rb:34-36, quoted: `Dir.glob('*.xcodeproj').first`]. The locator must not assume an absolute root or `File.expand_path` it in a way that changes the returned path's shape, because that path is printed to the user at `use.rb:59` and stored as a watch signature key.

### Finding A (NEW, measured this session) — the locator returns the wrong file

Reference project `/Users/ddphuong/Projects/next-labs/stress-ai/ios-stress-app/StressMonitor`, branch `main`:

```
$ ruby -e 'p Dir.glob(File.join("StressMonitor.xcodeproj","**/Package.resolved"))'
["StressMonitor.xcodeproj/StressMonitor.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
 "StressMonitor.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"]
```

The **nested** copy sorts first (`S` = 0x53 < `p` = 0x70), so `.find { File.exist?(f) }` returns it. Contents:

| Candidate | mtime | pins | identities |
|---|---|---|---|
| `…xcodeproj/project.xcworkspace/…/Package.resolved` (**real host graph**) | Aug 13 17:27 2026 | 17 | abseil-cpp-binary, app-check, appauth-ios, firebase-ios-sdk, google-ads-on-device-conversion-ios-sdk, googleappmeasurement, googledatatransport, googlesignin-ios, googleutilities, grpc-binary, gtm-session-fetcher, gtmappauth, interop-ios-for-google-sdks, leveldb, nanopb, promises, swift-protobuf |
| `…xcodeproj/StressMonitor.xcodeproj/project.xcworkspace/…/Package.resolved` (**what spm-cache reads**) | Jul 12 13:34 2026 | 8 | activityindicatorview, anchoredpopup, chat, giphy-ios-sdk, kingfisher, libwebp-xcode, mediapicker, swiftuicharts |

`spm-cache.lock` (mtime Aug 9 21:46) contains exactly 8 packages: `activityindicatorview, anchoredpopup, chat, giphy-ios-sdk, kingfisher, libwebp-xcode, mediapicker, swiftuicharts` — **identical set to the nested stale file**. The nested directory is git-ignored junk: `git check-ignore -v` returns `.gitignore:171:StressMonitor/StressMonitor.xcodeproj/StressMonitor.xcodeproj/`.

Live `DiffDetector` verdict on that project, run this session:

```
find_package_resolved → …/StressMonitor.xcodeproj/StressMonitor.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
added=2 removed=0 updated=0 empty=false
Detected: +2 packages (firebase-ios-sdk, GoogleSignIn-iOS). Regenerating proxy package.
```

Only `+2` — and those two come from `merge_project_refs` reading `project.pbxproj` (`diff_detector.rb:145,167-175`), not from the resolved graph. The 15 remaining firebase-graph pins are invisible and the 8 phantom packages are **not** reported as removed.

**Planning consequence:** reconciling `version`/`revision` from `find_package_resolved`'s current answer writes the phantom graph back onto itself. Success criterion 1 ("re-running `DiffDetector` returns an empty diff") would be satisfied by two components agreeing on the wrong file. Candidate disambiguation is therefore in scope for FID-01, not a nice-to-have.

Recommended preference order for `Core::PackageResolved.locate`:
1. `<root>/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` (canonical modern Xcode, exact path — no glob)
2. `<root>/../*.xcworkspace/xcshareddata/swiftpm/Package.resolved` (workspace-level projects)
3. recursive `<root>/**/Package.resolved`, **excluding** any path containing a second `*.xcodeproj` component and any path under the `spm-cache` sandbox dir; tie-break newest mtime.

Tier 1 resolves the reference project correctly and is a pure path check, so it is also cheaper than the glob it replaces.

**Open decision for the planner:** this changes observable behavior at sites 1, 3, 4, 5 (they will now find a different file on any project with a nested/duplicate resolved). CONTEXT.md grants discretion over "internal structure of `Core::PackageResolved`"; preference ordering arguably exceeds that. Surface it in the plan as a named decision with its own verification, and keep the old glob reachable as tier 3 so no project that worked before stops finding *a* file.

---

## Q2 — Lockfile Shape and Reconciliation Surface

### On-disk shape (canonical, `init`-seeded) [VERIFIED: lib/spm_cache/command/init.rb:172-185]

```ruby
        lockfile_data = {
          File.basename(project_path) => {
            'packages' => pins.map do |pin|
              {
                'repositoryURL' => pin['location'],
                'name' => pin['identity'],
                'version' => pin.dig('state', 'version'),
                'revision' => pin.dig('state', 'revision')
              }
            end,
            'dependencies' => {},
            'platforms' => {}
          }
        }
```

`installer.rb:176-189` writes the same four fields plus `"platforms" => detect_platforms` [VERIFIED: lib/spm_cache/installer.rb:176-189].

### In-memory structure

`Core::Lockfile` is a **thin wrapper over the raw parsed Hash**, not a materialized object graph. This matters: `@projects` and `@raw` are the *same object*.

[VERIFIED: lib/spm_cache/core/lockfile.rb:66-74, quoted verbatim]
```ruby
      def load(path = nil)
        @path = path if path
        return @raw = {} unless @path && File.exist?(@path)

        content = File.read(@path)
        @raw = content.strip.empty? ? {} : JSON.parse(content)
        @projects = @raw
        @raw
      end
```

[VERIFIED: lib/spm_cache/core/lockfile.rb:76-82, quoted verbatim]
```ruby
      def save(path = nil)
        @path = path if path
        return unless @path

        FileUtils.mkdir_p(File.dirname(@path))
        File.write(@path, JSON.pretty_generate(@raw))
      end
```

Therefore **mutating `lockfile.projects[proj]['packages']` in place and calling `lockfile.save` is the sanctioned write path** — it is exactly what `refresh_consumed_dependencies` (`installer.rb:160-161`) and `enrich_lockfile_products` (`installer.rb:285,291`) already do. `Pkg` (`lockfile.rb:14-55`) is a **read-only projection** — `pkgs_for_project` builds fresh `Pkg` objects from `pkg_data` hashes (`lockfile.rb:133-136`) and `Pkg#to_h` reconstructs a hash; mutating a `Pkg` does not touch `@raw`. **Do not reconcile through `Pkg`.**

### Field locations

| Datum | Location | Read by |
|---|---|---|
| `version` (per package) | `@raw[proj]['packages'][i]['version']` | `Pkg#initialize` (`lockfile.rb:26`); `DiffDetector#locked_packages` (`diff_detector.rb:109`); Swift `Lockfile.swift:123` |
| `revision` (per package) | `@raw[proj]['packages'][i]['revision']` | `lockfile.rb:28`; `diff_detector.rb:110`; Swift `Lockfile.swift:120` |
| identity (`repositoryURL` / `path_from_root` / `name`) | `@raw[proj]['packages'][i]` | `lockfile.rb:19-25`; `diff_detector.rb:104` |
| enriched `products[]` | `@raw[proj]['packages'][i]['products']` | `lockfile.rb:29`; written at `installer.rb:285`; guarded by `next if pkg_data["products"]` (`installer.rb:268`) |
| Xcode target → product map | `@raw[proj]['dependencies']` (`{ target_name => [product,…] }`) | written at `installer.rb:160`; read by `Lockfile#dependencies_for_target` (`lockfile.rb:138-142`), `unknown_dependencies` (`:121`), Swift `consumedProducts` |
| platforms | `@raw[proj]['platforms']` (`{ "ios" => "16.0" }`) | `platforms_for_project` (`lockfile.rb:144-147`); Swift `UmbrellaGenerator.swift:77+` |
| version stamp | `@raw[proj]['spm_cache_version']` | `invalidate_stale_products!` (`installer.rb:305`) |

### Keys reconciliation MAY write

- `packages[i]['version']` — from `pin.dig('state','version')`
- `packages[i]['revision']` — from `pin.dig('state','revision')`
- **membership of the `packages` array** — remove entries absent from the host graph; append entries present in the host graph but absent from the lock, in the canonical four-field shape above with **no `products` key** (per locked decision; note `Pkg#to_h` at `lockfile.rb:52` omits `products` when empty, and `installer.rb:268`'s `next if pkg_data["products"]` treats an *absent* key as "needs enrichment" while a present-but-`[]` key would suppress enrichment forever — so omit the key, do not write `[]`)

### Keys reconciliation MUST leave byte-identical

- `packages[i]['products']` — for every surviving package (success criterion 2)
- `packages[i]['repositoryURL']` / `path_from_root` / `path` / `name` — identity is matched on, never rewritten. Rewriting `repositoryURL` to the host's spelling would break the ssh/https-equivalence specs (`diff_detector_spec.rb:83-93`) that assert those variants are the same package.
- `packages[i]['branch']` — read by `Pkg` (`lockfile.rb:27`); never produced by generation, so it can only come from a hand-edited lock. Preserve it.
- `dependencies` — Xcode target→product map; owned by `refresh_consumed_dependencies`
- `platforms` — owned by `detect_platforms` / `init`'s `{}` seed
- `spm_cache_version` — owned by `enrich_lockfile_products` (`installer.rb:288`). **Do not stamp it during reconciliation**; stamping early would make `invalidate_stale_products!` skip its clear and preserve stale products across an upgrade — the exact field bug documented at `installer.rb:255-260`.
- any unrecognized top-level project key, and any project key other than the one being reconciled — the lock is a map of *projects*; reconcile only `@raw[File.basename(@project_path)]`.

---

## Q3 — Ordering: `detect_diff` → reconciliation → `gen_umbrella`

Call chain for the non-fast path (`Installer::Use#perform_install`, `installer/use.rb:16-35`):

```
verify_projects!                       installer.rb:101
detect_diff                            installer.rb:54-60   ← DiffDetector reads lock + resolved
fast_path?                             installer/use.rb:45-51
  ├─ empty diff + lock + proxy → skip everything below
  └─ else:
recreate_dirs                          installer.rb:107
ensure_config_file                     installer.rb:116  (Config#load)
sync_lockfile                          installer.rb:125-135
  ├─ generate_lockfile_from_resolved   installer.rb:164   ← early-returns if lock exists (the defect)
  ├─ @lockfile = Core::Lockfile.new    installer.rb:132   ← parse
  ├─ @lockfile.load                    installer.rb:133   ← parse again (redundant; Lockfile.new already loaded)
  └─ refresh_consumed_dependencies     installer.rb:134   → writes 'dependencies', @lockfile.save (line 161)
prepare_proxy                          installer.rb:211
  └─ Proxy#prepare                     spm/pkg/proxy.rb:26
       ├─ gen_umbrella(lockfile_path)  spm/pkg/proxy.rb:39  ← FIRST Swift-side read of the lock
       ├─ block: resolve_umbrella_checkouts; enrich_lockfile_products;
       │         retry_umbrella_resolve_after_enrichment → gen_umbrella  installer.rb:241
       └─ gen_proxy(lockfile_path)     spm/pkg/proxy.rb:45/47
gen_supporting_files / integrate_proxy_into_project / gen_cachemap_viz
```

### Every read of the lock between `detect_diff` and the first `gen_umbrella`

| Order | Site | Kind of read |
|---|---|---|
| 1 | `installer/use.rb:48` — `File.exist?(@config.lockfile_path)` | existence only |
| 2 | `installer.rb:166` — `return if File.exist?(lockfile_path)` | existence only |
| 3 | `installer.rb:132` — `Core::Lockfile.new(lockfile_path)` → `load` at `lockfile.rb:63` | full parse into `@raw` |
| 4 | `installer.rb:133` — `@lockfile.load(lockfile_path)` | full parse again (redundant) |
| 5 | `installer.rb:151` — `@lockfile.projects[File.basename(@project_path)]` | in-memory project lookup; **early-returns if nil** (`installer.rb:152`) |
| 6 | `installer.rb:161` — `@lockfile.save` | write of `@raw` |
| 7 | `spm/pkg/proxy.rb:31` — `Core::Config.instance.lockfile_path` | path only |
| 8 | `spm/pkg/proxy.rb:39` — `gen_umbrella(lockfile_path, umbrella_dir)` | **Swift reads the file from disk** |

(`DiffDetector#locked_packages` at `diff_detector.rb:96-114` is read #0, inside `detect_diff`, and reads the file directly — not through `Core::Lockfile`.)

### Exact insertion point

**Between `installer.rb:133` and `installer.rb:134`**, i.e. after the lock is loaded into `@lockfile` and before `refresh_consumed_dependencies`, inside `sync_lockfile`. Verbatim target [VERIFIED: lib/spm_cache/installer.rb:125-135]:

```ruby
    def sync_lockfile
      Core::UI.info "Syncing lockfile..."
      lockfile_path = @config.lockfile_path

      # Generate lockfile from Package.resolved
      generate_lockfile_from_resolved

      @lockfile = Core::Lockfile.new(lockfile_path)
      @lockfile.load(lockfile_path) if File.exist?(lockfile_path)
      refresh_consumed_dependencies
    end
```

Rationale, all mechanical:
- It is **after** read #3/#4, so the reconciler mutates the same in-memory `@raw` every downstream consumer already shares.
- It is **before** read #8, the first Swift-side read — so the umbrella is generated from the reconciled graph, which is the whole point of the phase.
- It is **before** `enrich_lockfile_products` (which runs inside `Proxy#prepare`'s block, after the first `gen_umbrella`), so newly-added packages with no `products` key get enriched in the same run, and surviving packages' `products` are preserved by the reconciler and then skipped by `installer.rb:268`'s idempotency guard.
- `sync_lockfile` only runs on the non-fast path (`installer/use.rb:26`), which is exactly the locked trigger condition. **Note:** `Installer#perform_install` (the base class, `installer.rb:31-44`) has no fast-path branch and always calls `sync_lockfile` — so on the base installer, reconciliation would run unconditionally. Confirm with the planner whether the reconciler should self-gate on `@diff && !@diff.empty?` (recommended: yes; it makes the trigger explicit at the call site regardless of which installer subclass is running, and `@diff` is already an `attr_reader` at `installer.rb:18`).

**Do not rely on `refresh_consumed_dependencies`'s `save` (line 161) to persist reconciliation.** It early-returns at `installer.rb:149` (`return unless @lockfile`) and `:152` (`return unless proj_data`) — the second fires whenever the lock's project key does not equal `File.basename(@project_path)` (renamed project, hand-written lock, lock written for a workspace). Reconciliation must call `@lockfile.save` itself.

---

## Q4 — DIAG-01 Registration Mechanics

### Exact `register` signature [VERIFIED: lib/spm_cache/core/diagnostics.rb:34-36, quoted verbatim]

```ruby
        def register(name, fix_hint:, &block)
          registry << Check.new(name: name, run: block, fix_hint: fix_hint)
        end
```

- `name` — positional `String` (all seven built-ins use single-quoted strings, e.g. `'cache_dir_health'`)
- `fix_hint` — required keyword `String`
- block — must accept `config:` as a keyword and return `[status, message]` where status ∈ `%i[ok warn fail]`

### How a check receives config [VERIFIED: lib/spm_cache/core/diagnostics.rb:41-49]

```ruby
        def run_all(config: nil)
          registry.map { |check| run_check(check, config: config) }
        end
...
        def run_check(check, config:)
          status, message = check.run.call(config: config)
          Result.new(name: check.name, status: status, message: message, fix_hint: check.fix_hint)
        rescue StandardError => e
```

`config` may be **`nil`** — `doctor_spec.rb:26` calls `run_all(config: nil)` and asserts every check still returns a valid status. The established defensive idiom is `remote_backend_connectivity` [VERIFIED: lib/spm_cache/core/diagnostics.rb:127-132]:

```ruby
        cfg = config || Config.instance
        begin
          cfg.load
        rescue StandardError
          nil
        end
```

`Config#project_dir` defaults to `Dir.pwd` [VERIFIED: lib/spm_cache/core/config.rb:32, quoted: `@project_dir = Dir.pwd`], and `lockfile_path` is `File.join(project_dir, LOCKFILE_FILENAME)` with `LOCKFILE_FILENAME = "spm-cache.lock"` [VERIFIED: lib/spm_cache/core/config.rb:27,96-97]. So DIAG-01 can locate both inputs from `cfg.project_dir`: the lock directly, and the `.xcodeproj` via the `use.rb:34-36` idiom (`Dir.glob('*.xcodeproj').first`, relative to `project_dir`). In the spm-cache repo itself neither exists → the locked `:ok` (no lockfile) branch fires, which is what keeps the suite green.

A raising check is captured as `:fail` with `"Check raised an error: #{e.message}"` (`diagnostics.rb:50-56`) — so a broken DIAG-01 degrades to a failure, not an aborted report. Because a `:fail` *does* exit 1, DIAG-01 must not let a missing project or unreadable file escape as an exception.

### Exit-code mapping — **`:warn` does NOT exit 1. Confirmed.**

[VERIFIED: lib/spm_cache/command/doctor.rb:41-42, quoted verbatim]
```ruby
        # Non-zero exit if any check failed, so CI can gate on it.
        exit 1 if results.any?(&:fail?)
```

`results.any?(&:fail?)` where `fail?` is `status == :fail` (`diagnostics.rb:25`). `:warn` and `:ok` both leave exit status 0, in both text and `--json` mode (the `exit` is after the branch at `doctor.rb:35-39`, so it applies to both). **The locked decision holds — no invalidation.**

JSON payload shape [VERIFIED: lib/spm_cache/command/doctor.rb:67-79]: `{ checks: [{name, status (String), message, fix_hint}], summary: {ok, warnings, failures} }`. Text marker for `:warn` is `!`, and the `fix_hint` line `"\n    ↳ #{result.fix_hint}"` is appended for any non-`:ok` result with a non-empty hint (`doctor.rb:56-65`) — so DIAG-01's "run `spm-cache use` to reconcile" hint will render.

### ⚠️ Three existing assertions break when DIAG-01 registers

| Spec | Line | Assertion | Required update |
|---|---|---|---|
| `spec/doctor_spec.rb` | 174-179 | `expect(...registry.map(&:name)).to eq(%w[xcode_version swift_version toolchain_path cache_dir_health library_evolution_compatibility remote_backend_connectivity companion_binary])` — exact array, exact order | append the new check name in registration order |
| `spec/doctor_spec.rb` | 199 | `expect(marker_lines.length).to eq(7) # none dropped, none extra` | → 8 |
| `spec/doctor_spec.rb` | 248 | `expect(parsed['checks'].length).to eq(8)` (7 built-ins + injected `kaboom_json`) | → 9 |

`spec/doctor_spec.rb:18-23` uses `include(...)`, so it is unaffected. `spec/doctor_companion_version_spec.rb` was checked for registry-count assertions: `grep -rn "registry" spec/*.rb` returns matches only in `doctor_spec.rb` [VERIFIED: grep output, this session]. Registration **order** decides report position; registering after `companion_binary` (i.e. at the end of `diagnostics.rb`, after line 153) keeps the existing seven lines in place and makes the spec deltas append-only.

---

## Q5 — Hermetic Test Seams

`spec/spec_helper.rb` is **not** a helper — it is a 3-example spec asserting `VERSION` and `ROOT` [VERIFIED: spec/spec_helper.rb:1-18]. It only does `require "spm_cache/main"`. There is **no shared configuration block, no fixture loader, no `let` helpers, and no `.rspec` file** (`cat .rspec` produced nothing). Every spec is self-contained: `require 'spec_helper'` + `tmpdir` + hand-written helper methods.

### Existing seams to reuse

| Seam | Where | Use for |
|---|---|---|
| `Dir.mktmpdir` + `after { FileUtils.rm_rf(tmpdir) }` | universal (`diff_detector_spec.rb:15-19`) | real files, no repo pollution |
| `SPMCache::Core::Config.instance.reset!` then `.project_dir = tmpdir` | `installer_use_fast_path_spec.rb:18-21` | redirect `lockfile_path` / `sandbox_dir` into tmpdir |
| `allow(Config.instance).to receive(:umbrella_dir).and_return(...)` | `lockfile_enrichment_spec.rb:21` | per-path override without touching the singleton's state |
| `allow(SPMCache::Core::Sh).to receive(:capture_output)` | `doctor_spec.rb:63-65` | the shell seam. **DIAG-01 needs none** — it is pure file I/O. Note `doctor_spec.rb`'s `before` block makes *every* `capture_output` raise, so a DIAG-01 that shelled out would fail there — a useful accidental guard. |
| `instance_double(SPMCache::Core::Config, load: nil, raw: {})` | `doctor_spec.rb:160` | injecting config into a check with no real project |
| `SPMCache::Core::Diagnostics.registry.dup` … `instance_variable_set(:@registry, saved)` | `doctor_spec.rb:36-49, 232-244` | isolating a single check without the other seven |
| `installer.instance_variable_set(:@lockfile, SPMCache::Core::Lockfile.new(lockfile_path))` + `installer.send(:private_method)` | `lockfile_enrichment_spec.rb:57-60` | unit-testing a private `Installer` method with no `perform_install` |
| `allow(installer).to receive(:prepare_proxy)` etc. | `installer_use_fast_path_spec.rb:99-106` | running `perform_install` end-to-end with zero shell-out |
| `Xcodeproj::Project.new(path)` + `new_target(:application, 'MyApp', :ios)` + `save` | `diff_detector_spec.rb:21-35` | a real, minimal `.xcodeproj` with no Xcode |

`spec/fixtures/` holds only four JSON lockfiles (`field-regression-`, `ignore-`, `plugin-`, `products-lockfile.json`) used by the Swift-side `gen_proxy_*` specs. Ruby-side specs write their JSON inline; follow that.

### Worked example — how an existing spec fakes a project/lock pair

`spec/diff_detector_spec.rb:37-62`, verbatim, is the exact pair the reconciler and DIAG-01 specs should copy:

```ruby
  def write_package_resolved(pins)
    resolved_path = File.join(project_path, 'project.xcworkspace', 'xcshareddata', 'swiftpm', 'Package.resolved')
    FileUtils.mkdir_p(File.dirname(resolved_path))
    File.write(resolved_path, JSON.generate(
                                'version' => 3,
                                'pins' => pins.map do |p|
                                  {
                                    'identity' => p[:identity],
                                    'kind' => 'remoteSourceControl',
                                    'location' => p[:url],
                                    'state' => { 'revision' => p[:revision] || "rev-#{p[:identity]}",
                                                 'version' => p[:version] }
                                  }
                                end
                              ))
  end

  def write_lockfile(packages, project_name = 'Fake.xcodeproj')
    File.write(lockfile_path, JSON.generate(
                                project_name => {
                                  'packages' => packages,
                                  'dependencies' => {},
                                  'platforms' => { 'ios' => '16.0' }
                                }
                              ))
  end
```

Note it writes the resolved file at the **canonical** `project.xcworkspace/xcshareddata/swiftpm/` path — so a tier-1 preference locator (Finding A) keeps every existing `diff_detector_spec` example passing unchanged. `init_spec.rb:23-25` writes to the same canonical path. That is strong evidence the preference reorder is spec-compatible.

For Finding A's own regression spec, add a **second** nested resolved file at `File.join(project_path, 'Fake.xcodeproj', 'project.xcworkspace', 'xcshareddata', 'swiftpm', 'Package.resolved')` with a disjoint pin set, and assert the locator returns the canonical one. That fixture reproduces the reference project's exact shape.

For the zero-overlap DIAG-01 fixture requested in CONTEXT.md `<specifics>`: `write_lockfile` with 8 packages and `write_package_resolved` with 17 disjoint pins, assert `:warn`.

---

## Q6 — Regression Risks from the Drop/Add Rule

| Consumer | Risk | Verdict |
|---|---|---|
| **Local / path packages** | 🔴 **HIGHEST.** `Package.resolved` contains only source-control/registry pins — a local `XCLocalSwiftPackageReference` never appears there. A drop rule keyed on resolved pins alone deletes **every** `path_from_root` package from the lock, then `UmbrellaGenerator.swift:69-70` (`.package(path:)`) stops declaring it and the app loses a real dependency. `DiffDetector` avoids this by unioning `merge_project_refs` into `live_packages` (`diff_detector.rb:145`). **The reconciler MUST use the same union — resolved pins ∪ pbxproj refs — not the pins alone.** `diff_detector_spec.rb:223-231` is the existing spec that would catch it. |
| **Transitive-only packages** | 🟢 Low. SwiftPM pins the whole graph, so a transitive-only package *is* in `Package.resolved` and survives the drop. Reconciliation actively helps here: `UmbrellaGenerator.swift:64-67` skips a transitive-only package only when `pkg.revision == nil`, so refreshing `revision` from the host makes more transitive packages get correctly revision-pinned rather than skipped. Watch for the inverse: if the host pin has no `revision` (unusual, but `state` can carry `branch` only), reconciliation must not *clear* an existing revision — that would flip a package from pinned to skipped. **Recommend: write `revision` only when the host pin has one; never nil it out.** |
| **Plugin-only packages** | 🟡 Medium-low. `pkg.isPluginOnly` gates the umbrella (`UmbrellaGenerator.swift:42`) and `plugin_only_lockfile_urls` gates Xcode ref retention (`installer.rb:370,391`), with `warn_unmatched_plugin_entries` already warning on a lock entry that matches no project ref (`installer.rb:392`). A plugin package is a normal remote pin so it survives the drop — but `isPluginOnly` is derived from `products[]`, so an *added* package with no `products` key is not yet classifiable. It gets enriched later in the same run (`installer.rb:261`), so the window closes before `gen_proxy`. Verify with `spec/gen_proxy_plugin_spec.rb` + `spec/fixtures/plugin-lockfile.json`. |
| **Binary targets** | 🟢 Low. A `binaryTarget` is a target inside a package, not a package; its host package is a normal pin. The relevant fragility is `products_from_manifest_fallback` (`installer.rb:344`), untouched by this phase. |
| **Phase-3 `init`-seeded canonical shape (`platforms {}`)** | 🟡 Medium. `init` seeds `'platforms' => {}` deliberately (`init.rb:151-152`, "init never opens the project via the xcodeproj gem (pure file I/O)"). Reconciliation must not touch `platforms` — writing `detect_platforms` there would make reconciliation open the project with `xcodeproj`, breaking the pure-file-I/O property the DIAG-01 static requirement also depends on. `init_spec.rb` asserts the seeded shape. |
| **`spm_cache_version` stamp** | 🟡 Medium. Do not stamp during reconciliation — see Q2. `spec/lockfile_enrichment_spec.rb`'s `write_lockfile(..., spm_cache_version:)` parameter is the existing lever for testing that interaction. |
| **`dependencies` map with a dropped package** | 🟡 Medium. `Lockfile#unknown_dependencies` (`lockfile.rb:110-131`) raises via `verify!` when a `dependencies` entry names a product whose package is not in `packages`. Dropping a package while `dependencies` still references it could trip that. Mitigated by ordering: `refresh_consumed_dependencies` (`installer.rb:148`) rebuilds `dependencies` from the live project immediately *after* reconciliation, so the stale reference is overwritten in the same run. Confirm `verify!` is not called in between — it is not, on the path traced in Q3. |

---

## Q7 — M1 Method (Falsifiable)

Two hypotheses to separate:
- **H-lock:** the umbrella was generated from a stale/wrong lock, so the stale pin came from the lockfile chain.
- **H-float:** the lock was fine and the umbrella's *isolated* `swift package resolve` floated the version (the `from:` drift mechanism documented at `Lockfile.swift:104-117`, independently reproduced in research as swift-argument-parser 1.2.0 → 1.8.2).

Finding A adds a third, now the leading candidate on `main`:
- **H-wrongfile:** the locator read a different `Package.resolved` than Xcode did, so the lock never described the host graph at all.

### Commands

```bash
REF=/Users/ddphuong/Projects/next-labs/stress-ai/ios-stress-app/StressMonitor
cd "$REF"
git stash list && git status --porcelain | head          # record dirty state before touching anything
cp spm-cache.lock /tmp/m1-lock-main.json                 # preserve the main-branch artifact first
git checkout feature/spm-cache-integration

# 0. Which resolved files exist, and which one does the current locator pick?
find . -name Package.resolved -not -path "*/.build/*" | while read -r f; do
  printf '%s\t%s\t%s\n' "$(stat -f %Sm "$f")" \
    "$(ruby -rjson -e 'puts (JSON.parse(File.read(ARGV[0]))["pins"]||[]).size' "$f")" "$f"
done
ruby -e 'p Dir.glob(File.join(Dir.glob("*.xcodeproj").first, "**/Package.resolved"))'

# 1. What does spm-cache believe the host graph is?
cd /Users/ddphuong/Projects/next-labs/spm-cache
bundle exec ruby -e '
$LOAD_PATH.unshift "lib"; require "spm_cache/core/diff_detector"
r=ARGV[0]; p1=Dir.glob(File.join(r,"*.xcodeproj")).first
d=SPMCache::Core::DiffDetector.new(project_path: p1, lockfile_path: File.join(r,"spm-cache.lock"))
puts "picked: #{d.send(:find_package_resolved)}"; puts d.detect.summary' "$REF"

# 2. Set arithmetic: lock vs EACH candidate resolved file (not just the picked one)
#    -> prints |lock|, |resolved|, |intersection| per candidate

# 3. What did the umbrella actually declare, and what did it resolve to?
grep -n '\.package(' "$REF/spm-cache/packages/umbrella/Package.swift"
ruby -rjson -e 'JSON.parse(File.read(ARGV[0]))["pins"].each{|p| puts "#{p["identity"]}\t#{p.dig("state","version")}\t#{p.dig("state","revision")}"}' \
  "$REF/spm-cache/packages/umbrella/Package.resolved" | sort

# 4. Release build, capturing the failure
xcodebuild -project "$REF"/*.xcodeproj -scheme StressMonitor -configuration Release \
  -destination 'generic/platform=iOS Simulator' build 2>&1 | tee /tmp/m1-release.log
```

### The distinguishing observation

Compare, per package, three values: `H` = host `Package.resolved` pin, `L` = `spm-cache.lock` entry, `U` = `spm-cache/packages/umbrella/Package.resolved` pin (step 3).

| Observation | Attribution |
|---|---|
| `U == L` **and** `L != H` | **H-lock** — the umbrella faithfully reproduced the lock, and the lock disagreed with the host. Reconciliation fixes it. |
| `U == L == H` for the picked resolved file, but the picked file `!=` the file Xcode writes (step 0 shows ≥2 candidates, differing pin counts) | **H-wrongfile** — every component agreed, on the wrong graph. Reconciliation alone does **not** fix it; the locator must. Currently the leading hypothesis on `main`. |
| `U != L` **and** `L == H` | **H-float** — the lock was right and the isolated resolve drifted. Phase 7 territory; reconciliation is not the fix. |
| `U != L` **and** `L != H` | both mechanisms active; report both, and note that `U`'s pins tell you which packages floated (those with a `from:` in `Package.swift`, per `Lockfile.swift:119-126`) versus which were revision-pinned. |

Falsifiability: step 3's `grep '\.package('` shows whether each package was emitted as `revision:` or `from:`. A `revision:` pin **cannot** float (`Lockfile.swift:117`, "A `revision:` pin has no range to float within"), so any package emitted with `revision:` whose umbrella pin differs from its lock entry **refutes H-float for that package** outright. Conversely a package emitted `from:` whose umbrella pin exceeds its lock version confirms H-float for that package. The attribution is therefore per-package and evidence-bound, not narrative.

Pre-recorded `main` evidence (this session, already measured — see Finding A): 17 host pins vs 8 lock packages, intersection 0, **and** the 8 lock packages exactly equal the 8 pins of the stale nested resolved file the locator actually reads. Record both numbers; the second is the one that decides between H-lock and H-wrongfile.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---|---|---|---|
| Package identity comparison | a new URL comparator in the reconciler | `DiffDetector#identity_key` / `normalize_url` (`diff_detector.rb:195-231`) | ssh/https/`.git`/`file://` equivalence is already specced (`diff_detector_spec.rb:83-104`); a parallel notion drops packages that merely spell differently |
| "What is the live graph?" | resolved pins only | `DiffDetector#live_packages` union (resolved ∪ pbxproj refs, `diff_detector.rb:121-148`) | resolved pins exclude local packages — the top regression risk (Q6) |
| Lock read/write | direct `File.read`/`JSON.parse`/`File.write` in the reconciler | `Core::Lockfile#load` / in-place `@raw` mutation / `#save` | `save` does `mkdir_p` + `JSON.pretty_generate`; hand-rolling changes formatting and loses the shared in-memory instance |
| `doctor` wiring | a new command or flag | `Core::Diagnostics.register` | registry is the single source of truth (`diagnostics.rb:10-16`); zero command changes |
| Locating `Package.resolved` | a sixth glob | `Core::PackageResolved` | the whole point of the phase's refactor |

## Common Pitfalls

### Pitfall 1: Reconciling against the wrong `Package.resolved`
**What goes wrong:** FID-01 ships, all specs pass, the reference project is unchanged.
**Why:** `Dir.glob(...).find` is order-dependent and the reference `.xcodeproj` contains a stale nested duplicate (Finding A).
**How to avoid:** deterministic preference order; regression spec with two resolved candidates.
**Warning signs:** `DiffDetector` reports a small diff on a project whose lock is months old.

### Pitfall 2: Tolerant parsing turning "unreadable" into "empty graph"
**What goes wrong:** drop rule + empty graph = lock erased.
**Why:** sites 1 and 2 currently raise on malformed JSON; a unified tolerant parser silently returns nil/`{}`.
**How to avoid:** the reconciler must distinguish absent/unreadable (→ warn, leave lock untouched, per locked decision) from readable-and-empty. Keep `nil` and `{"pins":[]}` distinguishable in the API.
**Warning signs:** a spec that writes a truncated `Package.resolved` and expects the lock to survive — write it.

### Pitfall 3: Writing `products: []` instead of omitting the key
**What goes wrong:** newly added packages never get enriched.
**Why:** `installer.rb:268` — `next if pkg_data["products"]`; `[]` is truthy in Ruby.
**How to avoid:** omit the key entirely for added packages.

### Pitfall 4: Clearing `revision` when the host pin lacks one
**What goes wrong:** a transitive-only package flips from revision-pinned to skipped (`UmbrellaGenerator.swift:64-67`), silently dropping it from the umbrella.
**How to avoid:** write `revision` only when the host pin supplies one.

### Pitfall 5: Forgetting the three hard-coded `doctor` check counts
**What goes wrong:** three green specs go red on an unrelated-looking change.
**How to avoid:** update `doctor_spec.rb:174-179`, `:199`, `:248` in the same commit as the registration.

## Anti-Patterns to Avoid

- **Deleting the `File.exist?` guard at `installer.rb:166`** to "make generation reconcile." That method writes the whole project object, clobbering `products`, `dependencies`, and `platforms`. Reconciliation is a separate, additive step.
- **Reconciling through `Core::Lockfile::Pkg`.** It is a read-only projection (`lockfile.rb:44-54`); mutations do not reach `@raw`.
- **Adding comments that restate the code.** Project rule is strict: WHY-only, and the codebase's existing comments are dense field-bug provenance (e.g. `Lockfile.swift:104-117`). A comment recording *why* the locator prefers the canonical path (Finding A's measurement) is exactly the kind that belongs; a comment saying "locate Package.resolved" is not.

## State of the Art

| Old Approach | Current Approach | Impact |
|---|---|---|
| `Dir.glob("**/Package.resolved").find` × 5 | single preference-ordered locator | correctness, not just DRY (Finding A) |
| Lock frozen at first creation | reconciled per non-fast-path run | FID-01 |
| No static drift visibility | `doctor` check, `:warn`, exit 0 | DIAG-01 |

**False premise to correct** (locked in CONTEXT.md): `UmbrellaGenerator.swift:57-63` justifies revision-pinning as reproducing "the host's resolved graph (`Package.resolved` is consistent, so the commit satisfies every parent's range by construction)". Verified verbatim this session at `UmbrellaGenerator.swift:58-63`. The premise requires a fresh lock; after this phase it is *closer* to true, but Finding A means it also requires the locator to have read the file Xcode wrote. Correct the comment to state both preconditions.

## Project Constraints (from CLAUDE.md and project skills)

- `./CLAUDE.md`: before any `gh` command, run `gh auth switch --hostname github.com --user phuongddx`. (No `gh` use is expected in this phase.)
- Global rules — **STRICT comment policy**: no explanatory/inline/section-divider/TODO comments; comments only for non-obvious business rules, external-library workarounds, critical non-obvious constraints. One line, WHY not WHAT.
- Surgical changes; match existing style; every changed line traceable to the request.
- Preserve public contracts unless the change intentionally updates them — the locator preference change *is* such an intentional update and must be called out, not slipped in.
- `# frozen_string_literal: true` first line of every `.rb` file, no exceptions [VERIFIED: present at line 1 of every Ruby file read this session].
- Flat namespace under `SPMCache`; directory mirrors namespace; one class/module per file → `Core::PackageResolved` lives at `lib/spm_cache/core/package_resolved.rb`.
- Note a live style inconsistency: `installer.rb`, `core/lockfile.rb`, `lockfile_enrichment_spec.rb` use double-quoted strings; `core/diagnostics.rb`, `core/diff_detector.rb`, `command/init.rb`, `command/use.rb`, `doctor_spec.rb`, `diff_detector_spec.rb` use single quotes. Match the file being edited, not a global preference.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|---|---|---|---|---|
| Ruby | everything | ✓ | 3.2.3 | — |
| RSpec | specs | ✓ | 3.13 (core 3.13.6) | — |
| Swift toolchain | `make proxy.build` (companion binary) | ✓ | 6.2.4 / Xcode toolchain | `companion_binary` check degrades to `:warn`; `gen_proxy_*` specs skip |
| Reference project (`StressMonitor`) | M1 only | ✓ | branch `main` checked out; `feature/spm-cache-integration` exists | M1 is measurement, not a code dependency |

**Missing dependencies with no fallback:** none.

## Validation Architecture

### Test Framework
| Property | Value |
|---|---|
| Framework | RSpec 3.13 (rspec-core 3.13.6) |
| Config file | **none** — no `.rspec`; `spec/spec_helper.rb` is itself a spec that only `require "spm_cache/main"` |
| Quick run command | `bundle exec rspec spec/package_resolved_spec.rb spec/lockfile_reconciliation_spec.rb spec/doctor_lock_fidelity_spec.rb` |
| Full suite command | `make proxy.build && bundle exec rspec` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|---|---|---|---|---|
| FID-01 | Reconciliation updates `version`/`revision` from host resolved | unit | `bundle exec rspec spec/lockfile_reconciliation_spec.rb -e "updates version and revision"` | ❌ Wave 0 |
| FID-01 | Enriched `products[]` survives for every surviving package (success criterion 2) | unit | `bundle exec rspec spec/lockfile_reconciliation_spec.rb -e "preserves products"` | ❌ Wave 0 |
| FID-01 | Package absent from host graph is dropped | unit | `… -e "drops a package absent from the host graph"` | ❌ Wave 0 |
| FID-01 | Package new in host graph is added with **no** `products` key | unit | `… -e "adds a new package without a products key"` | ❌ Wave 0 |
| FID-01 | Local / `path_from_root` package is NOT dropped (Q6 top risk) | unit | `… -e "keeps a local package absent from Package.resolved"` | ❌ Wave 0 |
| FID-01 | `dependencies`, `platforms`, `spm_cache_version`, `branch` byte-identical after reconciliation | unit | `… -e "leaves dependencies platforms and version stamp untouched"` | ❌ Wave 0 |
| FID-01 | Missing/unreadable `Package.resolved` → warn, lock untouched | unit | `… -e "leaves the lock untouched when Package.resolved is unreadable"` | ❌ Wave 0 |
| FID-01 | Runs only on non-fast-path; empty diff ⇒ no write | integration | `bundle exec rspec spec/installer_use_fast_path_spec.rb` (extend) | ⚠️ extend existing |
| FID-01 | **Success criterion 1** — after a non-fast-path run, re-running `DiffDetector` returns an empty diff | integration | `… -e "leaves DiffDetector reporting an empty diff"` | ❌ Wave 0 |
| FID-01 | Locator prefers canonical resolved over a nested duplicate (Finding A) | unit | `bundle exec rspec spec/package_resolved_spec.rb -e "prefers the canonical"` | ❌ Wave 0 |
| FID-01 | Locator never returns a path under the `spm-cache` sandbox | unit | `… -e "never returns a sandbox Package.resolved"` | ❌ Wave 0 |
| FID-01 | Five call sites unchanged in observable behavior (nil-tolerance, fallback scoping) | regression | `bundle exec rspec spec/diff_detector_spec.rb spec/init_spec.rb spec/watch_spec.rb spec/watch_loop_spec.rb` | ✅ exists |
| DIAG-01 | Zero-overlap lock vs host graph ⇒ `:warn` + reconcile hint | unit | `bundle exec rspec spec/doctor_lock_fidelity_spec.rb -e "warns on zero overlap"` | ❌ Wave 0 |
| DIAG-01 | Version drift on the intersection ⇒ `:warn` | unit | `… -e "warns on a version drift"` | ❌ Wave 0 |
| DIAG-01 | `revision` takes precedence over `version` | unit | `… -e "compares revision before version"` | ❌ Wave 0 |
| DIAG-01 | No lockfile ⇒ `:ok` | unit | `… -e "reports ok when no lockfile exists"` | ❌ Wave 0 |
| DIAG-01 | Static — no shell-out (`Core::Sh` never called) | unit | `… -e "does not shell out"` (`expect(Core::Sh).not_to receive(:capture_output)`) | ❌ Wave 0 |
| DIAG-01 | `:warn` leaves `doctor` exit 0 | integration | `bundle exec rspec spec/doctor_spec.rb` (extend) | ⚠️ extend existing |
| DIAG-01 | Registry order/count assertions updated | regression | `bundle exec rspec spec/doctor_spec.rb` | ✅ exists (3 assertions must change) |

### Sampling Rate
- **Per task commit:** `bundle exec rspec spec/<the touched spec(s)>` — Ruby-only specs need no `make proxy.build`
- **Per wave merge:** `bundle exec rspec` (full Ruby suite)
- **Phase gate:** `make proxy.build && bundle exec rspec` fully green (baseline 258 examples) before `/gsd-verify-work`

### Wave 0 Gaps
- [ ] `spec/package_resolved_spec.rb` — locator preference + sandbox exclusion + nil-tolerance parity for all five call-site shapes
- [ ] `spec/lockfile_reconciliation_spec.rb` — FID-01 semantics (drop / add / preserve / untouched-keys / unreadable)
- [ ] `spec/doctor_lock_fidelity_spec.rb` — DIAG-01 verdicts, precedence, no-shell-out
- [ ] Update `spec/doctor_spec.rb:174-179` (exact name array), `:199` (7→8), `:248` (8→9)
- [ ] Extend `spec/installer_use_fast_path_spec.rb` with success criterion 1 (empty diff after a non-fast-path run)
- [ ] No framework install needed; no shared `conftest`-equivalent needed (project convention is self-contained specs)

## Security Domain

`security_enforcement: true`, `security_asvs_level: 1`. This phase is a local developer CLI reading and writing files inside the user's own project — no network, no auth, no secrets, no untrusted remote input.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---|---|---|
| V2 Authentication | no | no identity surface |
| V3 Session Management | no | no sessions |
| V4 Access Control | no | single local user; files already user-owned |
| V5 Input Validation | **yes** | `Package.resolved` and `spm-cache.lock` are attacker-influenceable only insofar as a repo you already build is; still, validate structure before use: root must be a Hash, `pins` must be an Array, per-pin `location`/`identity` must be Strings. `init.rb:162-170` is the existing precedent (`data.is_a?(Hash)` + `rescue JSON::ParserError, TypeError`). |
| V6 Cryptography | no | no crypto |
| V12 Files & Resources | **yes** | path handling — see below |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---|---|---|
| Path traversal via `path_from_root` / `location` from a lock or resolved file | Tampering | Reconciliation writes identity fields verbatim, never resolves them to a filesystem path; keep it that way. Do not `File.expand_path`/read a package path during reconciliation. |
| Reading a generated artifact as if it were the host graph (the `spm-cache/packages/umbrella/Package.resolved` case) | Spoofing of authority | Exclude the sandbox dir from the locator's recursive tier — a real, measured issue (Finding A), not a hypothetical |
| Malformed JSON causing an unhandled exception mid-run after partial writes | DoS / integrity | `rescue JSON::ParserError, TypeError` + leave the lock untouched (locked decision) |
| Denial via enormous/adversarial resolved file | DoS | out of scope for a local dev tool; noted, not mitigated |
| Command injection | Tampering | not reachable — the phase adds no shell-out; DIAG-01 must not introduce one (its spec asserts this) |

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|---|---|---|
| A1 | `Dir.glob`'s ordering (which produced the nested-first result) is byte-sort per directory level and stable on APFS/darwin | Q1 Finding A | Low — the *fix* (deterministic preference) removes the dependency on glob order entirely; only the narrative of "why it broke" would change |
| A2 | Registry (`kind: "registry"`) pins in `Package.resolved` may omit `location` | Q6 | Low — `identity_key` already falls back to `"name:#{name}"` (`diff_detector.rb:201-202`); untested, so add a spec if any target project uses the SwiftPM registry |
| A3 | The reference project's `feature/spm-cache-integration` branch still contains the ExyteChat/MediaPicker state described in CONTEXT.md | Q7 | Medium — M1 method would need re-scoping; step 0 of the M1 commands checks this before anything else, so it fails fast |
| A4 | `xcodebuild -scheme StressMonitor` is the correct scheme name for the M1 release build | Q7 | Low — `xcodebuild -list` corrects it in seconds |

## Open Questions

1. **Is the locator preference change inside "Claude's Discretion"?**
   - What we know: CONTEXT.md grants discretion over "internal structure of `Core::PackageResolved`". Finding A shows a naive collapse leaves FID-01 ineffective on the reference project.
   - What's unclear: preference ordering changes *observable* behavior at four call sites, which reads as more than internal structure.
   - Recommendation: plan it as a named, separately-verified task with its own regression spec, and state the behavior change explicitly in SUMMARY.md. Do not treat it as a silent refactor.

2. **Should the reconciler self-gate on `@diff`?**
   - What we know: `Installer::Use` gates `sync_lockfile` behind `fast_path?`; the base `Installer#perform_install` (`installer.rb:31-44`) does not.
   - Recommendation: yes — guard on `@diff && !@diff.empty?` inside the reconciler so the locked trigger holds for any subclass.

3. **Does the `main`-branch field failure need re-attribution before Phase 7 is scoped?**
   - What we know: Finding A makes H-wrongfile the leading hypothesis on `main`, which the M1 method (Q7) resolves per-package.
   - Recommendation: run M1 step 0–3 early in the phase (they are read-only and take under a minute), because the answer may change how much of the field failure Phase 6 is expected to close.

4. **`installer.rb:133` is a redundant second `load`** (`Lockfile.new` already loads at `lockfile.rb:63`).
   - Recommendation: leave it. Removing it is unrelated cleanup and violates the surgical-changes rule.

## Sources

### Primary (HIGH confidence — files opened with `Read` this session, or commands run with output pasted)
- `lib/spm_cache/installer.rb` (1-270, 270-400) — defect chain, `sync_lockfile`, enrichment
- `lib/spm_cache/installer/use.rb` (full) — fast path
- `lib/spm_cache/core/lockfile.rb` (full) — load/save/`Pkg`
- `lib/spm_cache/core/diff_detector.rb` (full) — locator fallback, identity keying, live union
- `lib/spm_cache/core/diagnostics.rb` (full) — `register`, `run_all`, all 7 built-ins
- `lib/spm_cache/command/doctor.rb` (full) — exit-code mapping
- `lib/spm_cache/command/init.rb` (130-213) — canonical seed shape, tolerant parsing
- `lib/spm_cache/command/use.rb` (1-95) — `find_project`, watch locator
- `lib/spm_cache/core/watcher.rb` (1-60, 95-145) — watched-file resolution
- `lib/spm_cache/core/config.rb` (60-110, grep for `project_dir`) — path derivation
- `lib/spm_cache/spm/pkg/proxy.rb` (15-69) — `gen_umbrella` ordering
- `tools/spm-cache-proxy/Sources/Core/Lockfile.swift` (100-135) — `versionRequirement`
- `tools/spm-cache-proxy/Sources/Core/Generator/UmbrellaGenerator.swift` (40-90) — pin emission, transitive skip, false premise
- `spec/spec_helper.rb`, `spec/doctor_spec.rb`, `spec/diff_detector_spec.rb`, `spec/installer_use_fast_path_spec.rb`, `spec/lockfile_enrichment_spec.rb`, `spec/init_spec.rb` — seams and the three count assertions
- `.planning/REQUIREMENTS.md` (10, 24) — FID-01 / DIAG-01 verbatim
- `.planning/config.json` — `nyquist_validation: true`, `security_enforcement: true`
- Reference project measurements (commands + raw output in Q1 Finding A / Q7): `Dir.glob` ordering, both resolved files' pin counts and identities, `spm-cache.lock` contents, mtimes, `git check-ignore`, live `DiffDetector` verdict
- `ruby -v` → 3.2.3; `bundle exec rspec --version` → 3.13; `swift --version` → 6.2.4

### Secondary (MEDIUM)
- none required — every claim is in-repo or measured

### Tertiary (LOW)
- none

## Metadata

**Confidence breakdown:**
- Q1 five-site inventory: HIGH — all five read verbatim
- Q1 Finding A (wrong file): HIGH — reproduced with pasted command output, including the live `DiffDetector` verdict
- Q2 lockfile shape: HIGH — `lockfile.rb` read in full, write paths traced to their call sites
- Q3 ordering: HIGH — every read enumerated from source
- Q4 `:warn` → exit 0: HIGH — `doctor.rb:42` quoted verbatim; **locked decision confirmed valid**
- Q5 seams: HIGH — quoted from existing specs
- Q6 regression risks: HIGH for local-packages (mechanism traced through `Package.resolved` semantics + `merge_project_refs`), MEDIUM for registry-pin edge (A2)
- Q7 M1: HIGH on method and falsifiability; attribution itself is the phase's own measurement, deliberately not pre-judged

**No external packages introduced — Package Legitimacy Audit N/A.**

**Research date:** 2026-08-27
**Valid until:** 2026-09-26 (in-repo facts; invalidated only by edits to the cited files)
