---
phase: 10-fidelity-regression-coverage
plan: 03
subsystem: fidelity-regression-coverage
tags: [testing, fidelity, regression, hermetic, v0.2.x-edge-classes]
requires:
  - "Phase 8 BuildPipeline#report_fidelity (drift read-back + sidecar statuses)"
  - "Phase 9 provenance-aware BinariesCache.hit (tier-3 graph status surfaces)"
  - "compiled spm-cache-proxy binary for the tier-3 legs (skip-guarded)"
provides:
  - "spec/fidelity_edge_matrix_spec.rb — TEST-03 eight-class v0.2.x edge matrix (one example per class + SC4 audit)"
affects: []
tech-stack:
  added: []
  patterns:
    - "tier-1 object-stub seam with default-deny Core::Sh guard on both entry points"
    - "per-command-prefix allowlist stubs layered over the default-deny guard (libtool for the shim/resource legs)"
    - "tier-3 gen-proxy real-binary leg with skip-if-not-built guard (gen_proxy_* precedent)"
key-files:
  created:
    - spec/fidelity_edge_matrix_spec.rb
    - .planning/phases/10-fidelity-regression-coverage/deferred-items.md
  modified: []
decisions:
  - "FrameworkSlice resource-bundle drive: real copy semantics invoked directly (send) against the slice's public framework_path, because the class is unwired dead code with three independent pre-existing defects — zero production changes honored"
  - "Class 2/8 macro pin kept as ONE example covering both directions (agreeing + drifted) so each class number appears exactly once as an example string"
  - "Class numbers appear in `it` example strings (one each); nested describe strings repeat class names for readability"
metrics:
  duration: ~9min (561s)
  completed: 2026-08-29
actuals:
  tokens: 10585
  tasks: 3
  commits: 3
status: complete
requirements_completed: [TEST-03]
---

# Phase 10 Plan 03: v0.2.x Edge-Class Fixture Matrix Summary

**One-liner:** `spec/fidelity_edge_matrix_spec.rb` pins all eight v0.2.x edge classes — binary target (Class E), macro swift-syntax pin, vendored .xcodeproj, plugin-only, transitive-only, resource bundle, private Clang shim, product≠target rename — as one hermetic matrix (9 examples, 0 failures, ~0.26s), additive to the untouched existing specs.

## What Was Built

One new spec file, zero production changes:

- **Tier-1 describe** (`RSpec.describe SPMCache::SPM::BuildPipeline, "TEST-03: v0.2.x edge-class fixture matrix"`) with the proven scaffold (`stub_desc_products` with per-class raw-target override, `write_resolved_pins`, tmpdir/pkg/out lets) under a default-deny `Core::Sh` guard on BOTH entry points (`run` + `capture_output` raise `unexpected real invocation:` on anything the object stubs don't intercept).
- **class 1/8 binary target (Class E)** — the tracer. The checkouts/artifacts sibling layout plus the two-hop `dummy.m` forwarder chain terminating at a BinaryTarget, lifted verbatim from `build_pipeline_provenance_spec.rb:600-640`. Strictest SC4 form (`Buildable not_to receive(:new)`, `Sh not_to receive(:run)`). Asserts the copied xcframework's real content (FIRAnalytics.h bytes + Info.plist) AND the host-pinned sidecar with the `FirebaseAnalytics => "aaa"` pin preserved.
- **class 2/8 macro swift-syntax pin** (no analog — new pure-data shape). One example, both directions: the agreeing narrow pin (`swift-syntax @ aaa111` alongside the macro package's own `macro-kit @ mmm111`) stays host-pinned with NO drift warn; the drift-injected realized revision (`bbb222`) warns naming the swift-syntax identity with both values and flips the sidecar to `resolution-incompatible` with the drifted value on record. The macro shape is carried by the desc raw (macro implementation target depending on swift-syntax) — the class IS the pin-fidelity contract.
- **class 3/8 vendored .xcodeproj** — one `CryptoSwift.xcodeproj` directory (the classifier is a glob); sidecar read from disk asserts `not-graph-pinned` with `pins == {}`.
- **class 7/8 private Clang shim** — the swift-numerics `_NumericsShims` shape: SwiftTarget with a ClangTarget dependency that is not a product name, shim header + object file on disk, `XCFramework.new` dispatching on name; `shims.json` on disk lists `["_NumericsShims"]`. The shim assembly's one genuine tool invocation (`libtool -static -o`) is re-allowed as a prefix-scoped stub over the default-deny guard.
- **class 8/8 product≠target rename** — `Buildable.new` receives `hash_including(scheme: <product>, module_name: <differing target>)`; `create_framework` provably names the framework after the TARGET (recorded pre-rename), while the output xcframework is product-named.
- **Tier-3 describe** (compiled proxy binary, skip-if-not-built, `system()` with `File::NULL` — never `Core::Sh`):
  - **class 4/8 plugin-only** — the existing `spec/fixtures/plugin-lockfile.json` through the real binary; `statuses_from` reports `SwiftGenPlugin => "plugin"` and no proxy folder is generated for it.
  - **class 5/8 transitive-only** — inline lockfile (the `gen_proxy_provenance_spec.rb:29-37` shape) with a consumed `macro-host` and an unconsumed `swift-syntax`; asserts BOTH facts in one example: NO graph entry (`be_nil`, with the consumed sibling's `missed` entry proving the generator ran) AND input-side presence in the lockfile's declared package list.
- **class 6/8 resource bundle** (no analog) — its own describe on `SPMCache::SPM::XCFramework::FrameworkSlice`: the REAL `Desc::Target` parser resolves the describe-JSON `"resources": [{"path": ...}]` array to a joined path under pkg_dir, and the REAL `copy_resource_bundles` delivers the built `SomeResources.bundle` into the assembled framework path (contents intact) while never overwriting an already-present stale destination — Pitfall 14's unless-exists semantics.
- **SC4 audit example** — the default-deny guard itself is proven executable: an attempted `xcodebuild` invocation raises `unexpected real invocation:` instead of running.

## Verification Results

- `bundle exec rspec spec/fidelity_edge_matrix_spec.rb` → **12 examples, 0 failures, 0 pending** (9 matrix examples + 3 pre-existing SPMCache version/ROOT examples embedded in the lib and loaded via spec_helper).
- Three fidelity spec files combined: **0.89s rspec / ~1.4s wall** (`fidelity_drift_regression` + `fidelity_bucket_partition` + `fidelity_edge_matrix`, 32 examples) — inside the 2–3s target.
- `git status` clean of tracked modifications: **no existing spec file touched** (SC3's passes-unchanged is literal — byte-identical).
- Exactly one `it "TEST-03 class N/8..."` example string per class for all of 1/8…8/8 (`grep -c 'it "TEST-03 class N/8'` == 1 for each N).
- Default-deny guard text `unexpected real invocation` present in all three describe blocks (guard is armed tier-1, tier-3, and in the audit example).
- Ruby 3.1-compatible syntax only (keyword args, hash rockets, `send`, `stub_const`, regex matchers — nothing newer than 3.0 constructs).

### Fail-first mutation proofs (all restored green after)

| Mutation | Expected failure | Observed |
|---|---|---|
| class 1/8: remove the prebuilt `Info.plist` from the layout | copy-outcome assertion fails | 1 failure, restored green |
| class 6/8: remove the `resources` array from the target raw | parser assertion fails (`resource_paths` → `[]`) | 1 failure, restored green |
| class 2/8: equalize the drift-injected realized revision (`bbb222` → `aaa111`) | drift-direction assertions fail (no warn, no `resolution-incompatible`) | 1 failure, restored green |

### RuboCop posture

The repo ships NO rubocop config (`.rubocop` referenced in AGENTS.md does not exist; the pre-commit rubocop hook is not installed; every shipped spec carries the configless-default profile — e.g. `build_pipeline_provenance_spec.rb`: 702 offenses, the two sibling fidelity specs: 414). The new file matches that established profile exactly (377 offenses, all Style/Layout/Metrics — 318 of them `Style/StringLiterals`, the repo-wide double-quote idiom) with **zero Syntax/Lint findings** and `# frozen_string_literal: true` on line 1.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking issue] Class 6/8 could not drive FrameworkSlice through its public `create_framework`**
- **Found during:** Task 3
- **Issue:** `FrameworkSlice` is unwired dead code with three independent pre-existing defects: (1) `Desc::Target#resource_paths` is private (`target.rb:123` sits below the first `private` at line 50) so slice.rb's `respond_to?(:resource_paths)` guards are always false; (2) `slice.rb:64` calls bare `Sh` — a `NameError` in that namespace; (3) its `Utils::Template.render_to` calls render templates with `<%= module_name %>` placeholders that have no binding in `Template#render` (the LIVE path `Buildable#framework_info_plist` inlines the plist instead).
- **Fix:** Within the plan's own latitude ("construct/drive the real Slice (or the real XCFramework assembly with shell stubbed)"), the example constructs a real slice, sets its public `framework_path` destination to a freshly assembled `<out>/BundleHost.framework` dir, and invokes the REAL `copy_resource_bundles` via `send` — the semantics this class pins, with the parser asserted on a real `Desc::Target` (also via `send`, same privacy). An intermediate `stub_const` bridge for the bare-`Sh` NameError was tried and then dropped in favor of not invoking the broken assembly at all. Zero production changes (plan prohibition honored).
- **Files modified:** spec/fidelity_edge_matrix_spec.rb only
- **Commit:** d8a5475
- **Also logged:** `.planning/phases/10-fidelity-regression-coverage/deferred-items.md` (scope boundary: pre-existing, not caused by this plan)

**2. [Rule 1 - Bug] Task 1 initial product-hash typo**
- **Found during:** Task 1 (self-caught pre-gate)
- **Issue:** A `.merge("name" => ...)` artifact in the Class E product hash.
- **Fix:** Corrected to the plain product hash before the first run; the tracer gate ran clean.

Otherwise the plan executed exactly as written.

## Flagged Assumption (surfaced for verify time — never auto-resolved)

The plan's must_haves carry one probe category the deterministic classifier could not classify. Assumed meaning (RESEARCH A2): each class's example pins the class's CURRENT production behavior as the non-regression baseline; in particular the resource-bundle class means a describe-JSON `resources` array whose `*.bundle` must reach the assembled framework. **The class 6/8 fixture asserts exactly that.** If the operator intends a different v0.2.x incident shape for any class (most plausibly the resource-bundle one), the corresponding fixture asserts the wrong thing and should be re-pointed at verify time — the matrix structure (one example per class, per-class builders) makes that a single-example edit.

## Known Stubs

None in the deliverable's assertions. All assertions land on production surfaces: sidecar/lockfile/graph JSON on disk, stdout/stderr strings, copied file bytes, or the real parser/copy behavior. The object doubles (`Desc::Description`, `Buildable`, `XCFramework`, the slice buildable) are the documented tier-1 seam, and the only `send` uses (private `resource_paths` / `copy_resource_bundles`) are the documented dead-code workaround above.

## Self-Check: PASSED

- `spec/fidelity_edge_matrix_spec.rb` — FOUND (committed, d8a5475)
- Commits addddbe / 85b3a86 / d8a5475 — FOUND in `git log`
- 12 examples, 0 failures re-confirmed after the last edit
