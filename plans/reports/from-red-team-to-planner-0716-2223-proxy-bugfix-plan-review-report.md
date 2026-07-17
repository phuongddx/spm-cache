# Red-team review: plans/0716-2223-fix-proxy-product-metadata-identity-collision

Reviewed: plan.md + phases 1-4, triage report `debugger-0716-2209`, and every cited source file at current working-tree state (branch main, uncommitted mods present in several cited files — all line references below verified against the tree as it stands now).

## Verdict: APPROVE_WITH_AMENDMENTS

Phase 1 survives scrutiny (all cited lines verified accurate; one dead-code mislabel). Phases 2 and 3 each contain one plan-invalidating factual error that must be amended before implementation. Phase 4 is fine contingent on 2-3 being fixed.

---

## BLOCKER 1 — Phase 2's insertion point does not exist: no `swift package resolve` runs before `gen_proxy` in ANY flow

**Hits:** plan.md "Key design decisions" + phase-02 "Architecture".

Phase 2's architecture diagram claims:

> `gen_umbrella + resolve (checkouts now exist) → enrich_lockfile_products (NEW) → gen_proxy`

and plan.md claims "Metadata enrichment runs AFTER umbrella `swift package resolve` (checkouts then exist)". Both are false against the actual code:

- `Proxy#prepare` (`lib/spm_cache/spm/pkg/proxy.rb:21-44`) sequences `gen_umbrella → invalidate_cache → gen_proxy`. No resolve.
- `gen-umbrella` (Swift, `Sources/CLI/GenUmbrella.swift:16-42`) only writes the umbrella `Package.swift` via `UmbrellaGenerator.generate()`. It never shells out to `swift package resolve`.
- The only resolve in the codebase is `Installer::Build#resolve_umbrella_checkouts` (`lib/spm_cache/installer/build.rb:63-74`), which runs AFTER `super` — i.e., after `prepare_proxy` (gen_proxy already done) and after `integrate_proxy_into_project`. In the `use` flow (`lib/spm_cache/installer/use.rb`) resolve never runs at all.
- Leftover checkouts from a prior run cannot save you: `recreate_dirs` (`lib/spm_cache/installer.rb:48-55`) does `FileUtils.rm_rf(sandbox)` on every `perform_install`, and `umbrella_dir` is inside the sandbox (`lib/spm_cache/core/config.rb:64-74`). Checkouts are wiped every run.

**Consequence as written:** `enrich_lockfile_products` finds zero checkouts in every flow, hits its own "skip packages whose checkout can't be found (warn, legacy fallback)" rule for all 59 packages, and Bugs 1+2 ship unfixed — while all planned specs stay green, because enrichment specs mock `Desc` and fixture lockfiles hand-write `products[]`. The triage report explicitly flagged this as an unresolved design decision ("checkout-availability timing... needs a design decision", triage §Unresolved); the plan papered over it by asserting a resolve step that doesn't exist.

**Amendment:**
1. Extract `resolve_umbrella_checkouts` + `fallback_xcode_checkouts` from `Installer::Build` (build.rb:63-107) into shared code and call it in `prepare` (or from the installer) between `gen_umbrella` and enrichment, in ALL flows.
2. Make `Installer::Build` skip its now-duplicate resolve.
3. State the cost: `use` now performs a full dependency fetch/resolve on every run (mitigated by SwiftPM's global cache and the DerivedData fallback, but it is new wall time + a network dependency for a previously offline command). Decide and document the offline behavior (DerivedData fallback → legacy fallback → warn).
4. Note the saving grace explicitly: `swift package resolve` does not validate `.product(name:)` target references (that happens at build), so resolving the pre-enrichment umbrella — which still contains wrong product names on first run — is sound. If resolve fails anyway, the existing DerivedData fallback covers it.
5. Add one test that can actually catch this class of failure: a Ruby spec asserting `prepare` materializes checkouts before enrichment runs (or an integration spec using a local path-based fixture package, no network needed). Nothing currently planned exercises the sequencing.

## BLOCKER 2 — Phase 3's "preserve on no-match" fail-safe recreates Bug 3 at the Xcode layer and accumulates duplicate proxy refs

**Hits:** phase-03 "Risk Assessment" bullet 1 + Implementation step 3.

The risk note says: "on no-match, fail safe by PRESERVING the reference (worst case: a stale duplicate ref, better than a broken plugin)". This is inverted for every non-plugin package:

- If a remote library ref fails to URL-match its lockfile entry and is preserved, the package is now referenced BOTH directly (original `XCRemoteSwiftPackageReference`) AND via the proxy (its product deps were rewired at `installer.rb:165-170`). Two references to the same package identity in one project is exactly the "duplicate product GUID / conflicting identity" failure class this plan exists to fix (Bug 3).
- Worse: on every re-run, the PREVIOUS run's proxy `XCLocalSwiftPackageReference` (relative_path `spm-cache/packages/proxy`, added at installer.rb:158-162) matches no lockfile entry. Under preserve-on-no-match it survives the strip, then a new proxy ref is added — duplicate proxy refs accumulate run over run. Today's strip-all loop (installer.rb:147-149) is what keeps re-runs idempotent.

**Amendment:** invert the rule. The KEEP set is exactly: refs that URL-match (normalized: scheme, host case, trailing `.git`, ssh↔https form) a plugin-only lockfile entry. Everything else — including all `XCLocalSwiftPackageReference`s — is stripped, as today. The plugin-side failure mode is handled on the other side: if a plugin-only lockfile entry matches NO project ref, warn loudly (that is the "broken plugin" case, and it is visible), never by preserving arbitrary unmatched refs.

---

## MAJOR findings

### M1 (Phase 3) — Mechanism for exempting plugin product deps from strip+rewire is unspecified, and the data needed is discarded

`integrate_proxy_into_project` collects `old_deps` as `{target:, product: dep.product_name}` only (installer.rb:139-144) — the `dep.package` association is dropped before the strip. To leave plugin deps untouched you must capture `dep.package` (available: `XCSwiftPackageProductDependency` `has_one :package` in xcodeproj 1.28.1, verified in the installed gem) and exempt deps whose package is a preserved ref from BOTH the delete loop (installer.rb:151-156) and the rewire loop (installer.rb:165-170). Additional trap the plan doesn't mention: Xcode serializes build-tool-plugin product deps with `productName = "plugin:SwiftGenPlugin"` — the `plugin:` prefix. Rewiring those onto the proxy is today's silent corruption; matching by prefix (`product_name.start_with?("plugin:")`) is a cheap second belt alongside the package-ref match. Feasibility of URL matching itself is confirmed: `XCRemoteSwiftPackageReference#repositoryURL` exists (verified in gem source).

### M2 (Phase 2) — Multi-product graph granularity is unspecified and ripples further than the plan admits

Phase 2 says generators "iterate all library products" and "cache-hit lookup keys per product name", but never states what a `GraphEntry` becomes. `module` (ProxyGenerator.swift:104-109) feeds: `Cachemap` stats/lists (cachemap.rb:15-43), `Installer::Build`'s `missed` list and per-target builds (build.rb:20-41), user-facing `spm-cache build <target>` names (`filter_requested_targets!`, build.rb:47-59), and the viz. Per-product entries mean: (a) N `BuildPipeline.run` invocations = N full xcodebuild passes over the SAME checkout for an N-product package — cost unstated; (b) CLI target names silently change from `realm-swift` to `Realm`/`RealmSwift` — user-facing behavior change, undocumented; (c) hit/missed counts change meaning. Also unaddressed consumers of `resolvedProductName`:
- `matchesAnyPattern` (ProxyGenerator.swift:29-39): ignore/cache_only glob semantics with `products[]` need a definition (suggest: match ANY library product name OR identity; package-level status applies to all its products — matches existing spec expectations in gen_proxy_ignore_spec.rb:53-64).
- Shim generation (ProxyGenerator.swift:96-101, 199-205): one shim target per proxy today; multi-product needs one shim target + sources dir PER product. Not mentioned.

**Amendment:** add an explicit "graph.json shape" decision to phase-02 (recommend: one entry per library product, plus the three ripple items above called out with their fixes).

### M3 (blast radius) — Cache-key rename invalidates the binary cache; plan only mentions the multi-product hit rule

`BinariesCache.hit(module:)` looks up `<module>.xcframework` (Cache.swift:19-22); `BuildPipeline.run` writes `<name>.xcframework` where `name` = graph module (build_pipeline.rb:77). Phase 2 flips module names from identity-derived to real product names, so every existing `~/.spm-cache/<config>/<identity>.xcframework` becomes unreachable — silent full rebuild, and stale files linger forever (no GC exists). Mitigating fact worth stating in the changelog: any binary cached under a wrong identity-name was also built with `module_name: name` == identity (build_pipeline.rb:36-42), i.e. it was broken anyway; invalidation is correct, not just tolerable. Phase 2/4 must say this; currently only the hit-rule change is flagged.

---

## MINOR findings

1. **Phase 1, RootProxyPackage.swift:23 is dead code, mislabeled a live site.** Nothing constructs `RootProxyPackage` or `ProxyPackage` (grep: definitions only; `GenProxy` uses `ProxyGenerator.generateRootProxy`). Editing it is harmless; the plan should say "dead code — update for consistency or delete", not "second construction site missed by triage". All other Phase 1 citations verified exact: ProxyGenerator.swift:66/214/215, manifest `name: "\(slug)_proxy"` at :143/:160, spec lines gen_proxy_ignore_spec.rb:66,74 and gen_proxy_cache_only_spec.rb:54, `invalidate_cache` rm_rf at proxy.rb:58-62.
2. **Phase 2 staleness rule is half a fix.** Enrich-when-products-missing handles metadata, but `return if File.exist?` (installer.rb:79) still means pin drift (versions/revisions updated in Package.resolved) never propagates to an existing `spm-cache.lock`. Fine to defer — but state it as an explicit non-goal so it isn't rediscovered as a regression.
3. **Phase 2 schema records `{name, type}` but the shim needs MODULE names.** `@_exported import <productName>` (ProxyGenerator.swift:199-205) breaks when product name != module name. `swift package describe` already gives `products[].targets` and `Desc::Product#target_names` already parses it (desc/product.rb:16-18) — record `targets` in the schema for free and import those in the shim.
4. **Phase 3 URL matching claim is false for local packages.** `XCLocalSwiftPackageReference` has only `path`/`relative_path` (verified in gem). In practice `generate_lockfile_from_resolved` never writes local entries (Package.resolved has no local pins), so local plugin-only packages remain stripped/broken — pre-existing gap; document as out of scope in phase-03.
5. **Enrichment write-path trap.** `Core::Lockfile#save` round-trips `@raw` (safe), but `Core::Lockfile::Pkg#to_h` (core/lockfile.rb:44-52) projects a whitelist and would silently drop `products`. Phase 2 should direct the implementer to write via `@raw`/`deep_merge!` or extend `Pkg`.
6. **Umbrella simplification opportunity (optional).** `GenProxy` parses `--umbrella` but never uses it; the umbrella's only runtime role is checkout materialization via resolve (build.rb:63-74). Its stub `.target` product references (UmbrellaGenerator.swift:30-35) are pure liability — dropping targets from the umbrella manifest makes resolve immune to wrong/plugin product names permanently and shrinks Phase 3's umbrella change to nothing. Worth considering; not required.
7. **Testing realism — verified mostly OK, one gap.** Hand-written `products[]` in fixture lockfiles works: `spec/fixtures/ignore-lockfile.json` already carries `product_name` and the Swift side parses it (Lockfile.swift:64), so Phase 2/3 generator behavior and Phase 4's combined spec are genuinely fixture-testable with empty cache dirs. Ruby enrichment via mocked `Desc` is stated in phase-02 step 6. The untestable part is precisely BLOCKER 1's sequencing — see its amendment 5. Phase 3's preservation spec needs a temp `.xcodeproj` (installer_spec.rb already builds one), feasible.
8. **Scope:** no meaningful YAGNI violations. Cachemap `plugin` status + template styling mirrors the shipped `excluded` pattern (template selectors verified at cachemap.js.template:21-33). The field reporter's `fix-spm-cache-proxies.py` (describe-driven proxy rewrite) is exactly what Phase 2 institutionalizes — nothing from the workaround is missing.

---

## Ranked amendment list

1. (BLOCKER) Phase 2: add explicit checkout materialization (shared `resolve` + DerivedData fallback) to `prepare` before enrichment; correct the false "gen_umbrella runs resolve" claim; document `use`-flow cost + offline behavior; add a sequencing test.
2. (BLOCKER) Phase 3: invert the fail-safe — keep ONLY plugin-matched refs, strip everything unmatched (incl. all local refs) as today; warn when a plugin-only entry matches no ref.
3. (MAJOR) Phase 3: specify the dep-exemption mechanism — capture `dep.package` in `old_deps` before stripping; exempt by package-ref match and/or `plugin:` productName prefix.
4. (MAJOR) Phase 2: specify graph.json granularity (per-product entries), per-product shim targets, N-builds-per-checkout cost, CLI target-name change, and `matchesAnyPattern` semantics under `products[]`.
5. (MAJOR) Phase 2/4: document wholesale cache-key invalidation (identity-named xcframeworks unreachable, no GC) in changelog/docs, with the "old binaries were mis-moduled anyway" rationale.
6. (MINOR) Phase 1: relabel RootProxyPackage.swift as dead code (update-or-delete).
7. (MINOR) Phase 2: record `products[].targets` and use module names in shims; note `Pkg#to_h` projection trap; state pin-drift staleness as a non-goal.
8. (MINOR) Phase 3: note local plugin-only packages as out of scope; consider dropping umbrella stub targets (optional simplification).

Phase 1: APPROVED as written (modulo amendment 6). Phase 4: APPROVED contingent on 1-5.
