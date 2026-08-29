# Deferred Items — Phase 10

## 2026-08-29 — 10-03 executor (out-of-scope discovery, Rule scope-boundary)

### FrameworkSlice is unwired dead code with three independent defects

Discovered while building the TEST-03 class 6/8 (resource bundle) fixture:
`SPMCache::SPM::XCFramework::FrameworkSlice` (`lib/spm_cache/spm/xcframework/slice.rb`)
has no callers anywhere in `lib/` (only the autoload in `xcframework.rb`), and its
public `create_framework` can never complete a real run:

1. `Desc::Target#resource_paths` is **private** (`lib/spm_cache/spm/desc/target.rb:123`
   sits below the first `private` at line 50), so slice.rb:31-32's
   `@target.respond_to?(:resource_paths)` guards are always false —
   `copy_resource_bundles` / `override_resource_bundle_accessor` are unreachable.
2. `slice.rb:64` calls bare `Sh.run(...)` — a `NameError` inside the
   `SPMCache::SPM::XCFramework::FrameworkSlice` namespace (`Sh` resolves only as
   `Core::Sh`).
3. Its `Utils::Template.render_to("framework.info.plist", ...)` renders templates
   whose `<%= module_name %>` placeholders have no binding in `Template#render`
   (`utils/template.rb:22` binds the template's own context). The LIVE assembly path
   (`Buildable#framework_info_plist`, `lib/spm_cache/spm/build.rb:383`) inlines the
   plist via string interpolation and does not use `Utils::Template` at all.

Consequence for production behavior: on the live assembled-framework path
(`Buildable#create_framework`) resource bundles are NOT copied from build products;
the only bundle-preserving route today is `Buildable#use_existing_framework`'s full
`cp_r` of an xcodebuild-produced `.framework` (which already contains `*.bundle`).
Phase 10 is a zero-production-change phase, so `spec/fidelity_edge_matrix_spec.rb`
drives the real `copy_resource_bundles` semantics directly (documented in the spec's
describe-block comment and 10-03-SUMMARY.md). Recommended follow-up: either delete
`FrameworkSlice` or wire and repair it (public `resource_paths`, qualified `Core::Sh`,
fixed template binding) — deciding which is a product decision, not test coverage.
