# Phase 4: build pipeline scheme-resolution failures (issue #4)

Status: DONE (2026-07-14) — `resolve_scheme` wired up-front. Code review caught a critical bug (`Desc::Product#type` didn't handle SwiftPM's real Hash-shaped output, making the fix a silent no-op); fixed + added `spec/desc_product_spec.rb`; re-verified against real `swift package describe` output on 3 local packages. `bundle exec rspec` green (58 examples, 0 failures).

## Context

- Issue: "Build pipeline fails for 47/62 targets due to incorrect scheme resolution"
- File: `lib/spm_cache/spm/build_pipeline.rb` (+ `lib/spm_cache/spm/build.rb` for how `scheme` is consumed)

## Root cause verification

Confirmed real at HEAD, matches issue closely.

- `lib/spm_cache/spm/build_pipeline.rb:33-39` — the initial attempt always uses the raw package identity (`name`, typically lowercase-kebab from `Package.resolved` "identity", e.g. `alamofire`) as BOTH `module_name` and `scheme`:
  ```ruby
  buildable = Buildable.new(
    name: name,
    module_name: name,
    pkg_dir: pkg_dir,
    library_evolution: library_evolution,
    scheme: name,
  )
  ```
- `lib/spm_cache/spm/build.rb:35` confirms `scheme` flows straight into `xcodebuild build -scheme #{@scheme}` with no validation.
- `lib/spm_cache/spm/build_pipeline.rb:132-139` (`resolve_scheme_fallback`) is verbatim what the issue quotes:
  ```ruby
  def resolve_scheme_fallback(name, pkg_dir)
    list_output = Core::Sh.capture_output("xcodebuild -list", cwd: pkg_dir) rescue ""
    schemes = list_output.split("\n").drop_while { |l| !l.match?(/Schemes:/) }
                           .drop(1)
                           .map(&:strip)
                           .reject(&:empty?)
    schemes.find { |s| s.casecmp(name).zero? } || schemes.first
  end
  ```
  Confirmed: `schemes.first` is the only fallback when no case-insensitive exact match exists — arbitrary pick, matches issue's "Conformance"/"Alamofire iOS" failure examples.
- Confirmed via `spec/build_pipeline_spec.rb:60-70` that this exact fallback path is already covered by a stub test ("raises when no slices are built"), so a fix must keep that test's contract (still raises `/No slices were built successfully/` when truly nothing works) while improving the scheme picked before falling through to that raise.

Issue's suggested fix (parse `xcodebuild -list -json`, prefer schemes producing a library/framework, avoid test/demo/executable schemes) is workable but has a real risk: `xcodebuild -list -json`'s scheme list is just names — it does NOT report which scheme builds a library vs. executable vs. test target. The issue's own suggested code comment ("Parse JSON to find schemes that build a .framework or library target") is not actually deliverable purely from `-list -json` output; you'd need `-showBuildSettings` per-scheme (slow, N+1 xcodebuild invocations) or a different data source.

**Related code path the reporter missed**: `SPMCache::SPM::Desc::Description` (`lib/spm_cache/spm/desc/desc.rb`, backed by `swift package describe --type json` in `lib/spm_cache/spm/desc/base.rb:51-56`) already gives authoritative product metadata — `products` array with `name` and `type` (`lib/spm_cache/spm/desc/product.rb:23-25`, `type` reads `raw["type"]` which for `swift package describe` is `"library"` / `"executable"` / etc). This is already used elsewhere in the codebase (`lib/spm_cache/spm/pkg/base.rb:28`) but never wired into `build_pipeline.rb`. Since SPM-native package schemes in Xcode are auto-generated 1:1 from **product names** (not target names, not package identity), the product name from `swift package describe` IS the correct scheme name in the vast majority of cases — no guessing needed. This directly explains the issue's own examples:
  - Alamofire: package identity `alamofire` (lowercase) vs. actual product name `Alamofire` (PascalCase) — `swift package describe` would report product name `Alamofire` directly.
  - swift-protobuf: product is likely named `SwiftProtobuf`, not `Conformance` (a plugin/test executable target) — `type: "executable"` on `Conformance` would let us exclude it definitively, something string heuristics can't reliably do.
  - FSPagerView: product name `FSPagerView` (exact PascalCase) vs. attempted lowercase `fspagerview`.

## Implementation steps

1. In `resolve_scheme_fallback` (or a new `resolve_scheme` called before the first build attempt, not just as a post-failure fallback — since the FIRST attempt already wastes a full multi-destination build cycle on a wrong scheme per the issue's log), do:
   ```ruby
   def resolve_scheme(name, pkg_dir)
     desc = Desc::Description.new(name: name, pkg_dir: pkg_dir)
     desc.fetch
     library_products = desc.products.select { |p| p.type == "library" }
     match = library_products.find { |p| p.name.casecmp(name).zero? } ||
             library_products.find { |p| p.name.downcase.include?(name.downcase) || name.downcase.include?(p.name.downcase) } ||
             library_products.first
     return match.name if match

     # Fall back to xcodebuild -list heuristic only if `swift package describe` gave nothing usable
     resolve_scheme_fallback(name, pkg_dir)
   end
   ```
2. Call `resolve_scheme` once up front in `BuildPipeline.run` to set the INITIAL `scheme:` passed to `Buildable.new` (currently hardcoded to `name`, `build_pipeline.rb:38`), not only after all destinations already failed. This avoids the wasted first-pass build the issue's logs show for every one of the 47 failing targets.
3. Keep `resolve_scheme_fallback` (`xcodebuild -list` + `casecmp`/`schemes.first`) as last-resort for local/path packages with no `Package.swift` describable via SPM tooling (e.g. binary-only or malformed packages) — do not delete it, per issue's own acknowledgment it "rarely matches" but is a valid final fallback.
4. Do NOT implement the issue's literal suggestion of `xcodebuild -list -json` target-type parsing — `swift package describe --type json` is strictly better data already available via `Desc::Description`, avoids adding a second parsing strategy that doesn't actually solve the type-detection problem it's meant to.

## Tests

- Extend `spec/build_pipeline_spec.rb`:
  - New case: stub `Desc::Description#fetch`/`#products` to return `[Product(name: "Alamofire", type: "library"), Product(name: "Alamofire iOS", type: "library"), Product(name: "AlamofireTests", type: "executable")]` for package identity `alamofire`; assert `Buildable.new` is called with `scheme: "Alamofire"` (exact case-insensitive match preferred over other library products).
  - New case: package identity `swift-protobuf` with products `[Product(name: "SwiftProtobuf", type: "library"), Product(name: "Conformance", type: "executable")]`; assert scheme resolves to `SwiftProtobuf`, never `Conformance` (type filter proves this, not just name heuristics).
  - Keep existing "raises when no slices are built" test (`build_pipeline_spec.rb:60-70`) passing — it stubs `Core::Sh.capture_output` to return `""`; also stub `Desc::Description.describe` (or `.fetch`) to return `{}` so `resolve_scheme` correctly falls through to the empty-schemes path and the final raise still fires.
- Run: `bundle exec rspec spec/build_pipeline_spec.rb`.
- Manual e2e (requires phase 2/3 fixed first, per plan.md ordering rationale): run `spm-cache build --recursive` against a project with Alamofire/swift-protobuf-like packages and confirm scheme picked matches product name, no `schemes.first` arbitrary pick.

## Risks / rollback

- Medium risk: changes behavior for every package build, not just the 47 currently-failing ones — must verify the 14 currently-succeeding targets (where package identity already equals scheme) still resolve identically (i.e., `library_products.find { casecmp }` still finds them first).
- Extra `swift package describe` shell-out per target adds latency (~1 process spawn per package) — acceptable, already paid elsewhere in the codebase (`spm/pkg/base.rb`) for the same data, so no new cost class introduced.
- Rollback: revert to always using `name` as initial `scheme:` and keep only the existing `resolve_scheme_fallback`-after-failure behavior.
