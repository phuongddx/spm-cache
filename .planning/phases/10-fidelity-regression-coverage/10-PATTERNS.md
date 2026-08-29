# Phase 10: Fidelity Regression Coverage - Pattern Map

**Mapped:** 2026-08-29
**Files analyzed:** 4 (3 new spec files + 1 optional new fixture)
**Analogs found:** 4 / 4 (2 of the 8 edge classes inside the matrix have NO per-class analog — see No Analog Found)

Zero production files are created or modified this phase. Every deliverable is an RSpec file over
the already-proven hermetic seams (`Core::Sh` / `Desc::Description` / `Buildable` /
`BuildPipeline.run` / compiled proxy binary).

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `spec/fidelity_drift_regression_spec.rb` | test | file-I/O | `spec/build_pipeline_provenance_spec.rb` (+ `spec/gen_proxy_provenance_spec.rb` for the sidecar-disagreement leg) | exact |
| `spec/fidelity_bucket_partition_spec.rb` (name per CONTEXT is planner's choice; RESEARCH recommends this name) | test | file-I/O + batch (partition over fixture universe) | `spec/build_pipeline_provenance_spec.rb` (fidelity legs) + `spec/gen_proxy_provenance_spec.rb` (graph legs) | exact (hybrid of two exact analogs) |
| `spec/fidelity_edge_matrix_spec.rb` | test | file-I/O + transform | `spec/build_pipeline_spec.rb` + `spec/build_pipeline_provenance_spec.rb` (Class E group, lines 566-713) | role-match (6 of 8 edge classes have verbatim shapes; 2 do not) |
| `spec/fixtures/fidelity-kitchen-sink-lockfile.json` (only if the kitchen sink needs lockfile-shaped data) | test fixture | file-I/O | `spec/fixtures/plugin-lockfile.json` | exact |

## Pattern Assignments

### `spec/fidelity_drift_regression_spec.rb` (test, file-I/O)

**Analog:** `spec/build_pipeline_provenance_spec.rb` — this file already unit-tests exactly the
Phase 8 drift read-back contract the new spec pins as a named regression. The provenance spec
stays untouched; the new file reuses its idioms.

**File header / describe pattern** (`spec/build_pipeline_provenance_spec.rb` lines 1-12) — note
the comment block stating what is stubbed and what stays real; carry a TEST-01 ID in the describe
string (precedent: IDs in describe strings at lines 189 `"(WR-02)"`, 404 `"(09-01, Pattern 3)"`,
877 `"(Pitfall 2 regression guard)"`):

```ruby
# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "json"

# Unit-tests Phase 8's drift read-back, resolution-incompatible classification,
# and provenance sidecar write/cleanup logic in BuildPipeline.run. Real
# xcodebuild is never invoked; Buildable/Desc::Description/XCFramework are
# stubbed exactly as in spec/build_pipeline_seeding_spec.rb -- real Dir.mktmpdir
# pkg_dir/out_dir, real filesystem for Package.resolved.
RSpec.describe SPMCache::SPM::BuildPipeline, "drift read-back, resolution-incompatible status, and provenance sidecar" do
```

**let-scaffold + before/after** (lines 13-16, 33-45):

```ruby
let(:tmpdir) { Dir.mktmpdir }
let(:pkg_dir) { File.join(tmpdir, "pkg") }
let(:out_dir) { File.join(tmpdir, "out") }
let(:resolved_pins_file) { File.join(tmpdir, "host-Package.resolved") }

before do
  FileUtils.mkdir_p(pkg_dir)
  FileUtils.mkdir_p(out_dir)
  write_resolved(resolved_pins_file, "SomePkg", "aaa111")
  stub_desc_products([{ "name" => "SomePkg", "type" => { "library" => ["automatic"] } }])
  allow(SPMCache::SPM::XCFramework::XCFramework).to receive(:new).and_return(
    double("XCFramework", build: File.join(out_dir, "SomePkg.xcframework")),
  )
end

after { FileUtils.rm_rf(tmpdir) }
```

**Desc stub helper** (lines 18-27, verbatim — reuse unchanged):

```ruby
def stub_desc_products(products)
  fake_desc = instance_double(SPMCache::SPM::Desc::Description)
  allow(SPMCache::SPM::Desc::Description).to receive(:new).and_return(fake_desc)
  allow(fake_desc).to receive(:fetch)
  allow(fake_desc).to receive(:products).and_return(
    products.map { |p| SPMCache::SPM::Desc::Product.new(raw: p, pkg_dir: pkg_dir) },
  )
  allow(fake_desc).to receive(:raw).and_return({ "targets" => [] })
  fake_desc
end
```

**Package.resolved fabrication helper** (lines 29-31, verbatim):

```ruby
def write_resolved(path, identity, revision)
  File.write(path, JSON.generate("pins" => [{ "identity" => identity, "state" => { "revision" => revision } }]))
end
```

**Core pattern — drift injection** (lines 47-61): the stubbed `build_for_destination` block
rewrites `pkg_dir/Package.resolved` to the drifted value before returning artifacts. This IS
TEST-01's drift-injection source #2 (resolution read-back drift):

```ruby
fake_buildable = instance_double(SPMCache::SPM::Buildable)
allow(SPMCache::SPM::Buildable).to receive(:new).and_return(fake_buildable)
allow(fake_buildable).to receive(:build_for_destination) do |*_args, **_kwargs|
  write_resolved(File.join(pkg_dir, "Package.resolved"), "SomePkg", "bbb222")
  {
    derived_data: "/dd",
    object_file: "/dd/SomePkg.o",
    swiftmodule: nil, swiftdoc: nil, swiftsourceinfo: nil, swiftinterface: nil,
  }
end
allow(fake_buildable).to receive(:create_framework) do |_arts, subdir|
  fw = File.join(subdir, "SomePkg.framework")
  FileUtils.mkdir_p(fw)
  File.write(File.join(fw, "SomePkg"), "stub")
  fw
end
```

**Assertion channels — drift direction MUST warn** (lines 69-93): chain stdout (status line) and
stderr (drift warn) in one `expect` block, then assert the sidecar JSON on disk (never the double):

```ruby
expect {
  result = described_class.run(
    name: "SomePkg", pkg_dir: pkg_dir, destinations: ["iphonesimulator"],
    out_dir: out_dir, resolved_pins_file: resolved_pins_file, config: "debug",
  )
}.to output(/resolution-incompatible/).to_stdout.and output(/SomePkg.*aaa111.*bbb222/).to_stderr

sidecar_path = "#{result}.provenance.json"
parsed = JSON.parse(File.read(sidecar_path))
expect(parsed.keys.sort).to eq(%w[config destinations fidelity_status pins spm_cache_version])
expect(parsed).to eq(
  "fidelity_status" => "resolution-incompatible",
  "pins" => { "SomePkg" => "bbb222" },
  ...
)
```

**Assertion — agreeing pins must NOT warn (false-positive guard)** (lines 96-124, key line 110):

```ruby
expect(SPMCache::Core::UI).not_to receive(:warn)
...
parsed = JSON.parse(File.read("#{result}.provenance.json"))
expect(parsed["fidelity_status"]).to eq("host-pinned")
expect(parsed["pins"]).to eq("SomePkg" => "aaa111")
```

**Parametrized realized-pins runner** (lines 787-806, `run_with_realized_pins`): a local helper
that installs the Buildable stub writing arbitrary realized JSON then calls
`described_class.run` — the cleanest shape for a spec that needs several drift variants
(revision-vs-version drift precedents at lines 852-874: revision wins, version fallback).

**Drift-injection source #1 — provenance-sidecar disagreement (Phase 9 semantics):** copy the
`write_sidecar` + `statuses_from` helpers from `spec/gen_proxy_provenance_spec.rb` (lines 39-44
and 52-55, quoted in the bucket-partition assignment below) and the SC2/SC3 scenarios (lines
81-156): agreeing sidecar pin ⇒ `hit`, disagreeing pin ⇒ `missed`, no sidecar ⇒ `missed`.
The `run_gen_proxy` invocation pattern is quoted below.

---

### `spec/fidelity_bucket_partition_spec.rb` (test, file-I/O + batch)

**Analog (hybrid, per RESEARCH Open Question 1 recommendation):**
- Fidelity legs (pinned / resolution-incompatible / not-graph-pinned): `spec/build_pipeline_provenance_spec.rb` — drive `BuildPipeline.run` on the tier-1 seam exactly as above; read the bucket from the sidecar's `fidelity_status`.
- Graph legs (ignored / excluded / plugin): `spec/gen_proxy_provenance_spec.rb` + `spec/gen_proxy_plugin_spec.rb` + `spec/gen_proxy_ignore_spec.rb` — drive the compiled proxy binary, read the bucket from graph.json `status`.

**Tier-3 skip-guard + binary location** (`spec/gen_proxy_provenance_spec.rb` lines 15-27):

```ruby
let(:binary) do
  local = SPMCache::ROOT.join("tools", "spm-cache-proxy",
                              ".build", "release", "spm-cache-proxy").to_s
  File.executable?(local) ? local : nil
end

let(:tmpdir) { Dir.mktmpdir }

before do
  skip "spm-cache-proxy binary not built (run make proxy.build)" unless binary
end

after { FileUtils.rm_rf(tmpdir) if tmpdir }
```

**Lockfile fabrication helper** (`spec/gen_proxy_provenance_spec.rb` lines 29-37) — use this to
build the kitchen sink inline, or commit `spec/fixtures/fidelity-kitchen-sink-lockfile.json` and
load it the way `spec/gen_proxy_plugin_spec.rb` lines 20-22 loads its fixture:

```ruby
def write_lockfile(path, project_name:, packages:)
  File.write(path, JSON.generate(
    project_name => {
      "packages" => packages,
      "dependencies" => {},
      "platforms" => { "ios" => "16.0" },
    },
  ))
end
```

**Sidecar fabrication** (`spec/gen_proxy_provenance_spec.rb` lines 39-44):

```ruby
def write_sidecar(cache_dir, module_name, pins:, status: "host-pinned")
  File.write(
    File.join(cache_dir, "#{module_name}.xcframework.provenance.json"),
    JSON.generate("fidelity_status" => status, "pins" => pins),
  )
end
```

**Proxy invocation + graph status extraction** (`spec/gen_proxy_provenance_spec.rb` lines 46-55;
flag-passing variant with Shellwords at `spec/gen_proxy_ignore_spec.rb` lines 37-41):

```ruby
def run_gen_proxy(umbrella_dir:, lockfile:, output_dir:, cache_dir:)
  cmd = "#{binary} gen-proxy --umbrella #{umbrella_dir} --lockfile #{lockfile} " \
        "--output #{output_dir} --cache #{cache_dir}"
  system(cmd, out: File::NULL, err: File::NULL)
end

def statuses_from(output_dir)
  graph = JSON.parse(File.read(File.join(output_dir, "graph.json")))
  graph.each_with_object({}) { |e, h| h[e["module"]] = e["status"] }
end
```

For the `ignored` / `excluded` legs: append `--ignore #{Shellwords.escape(pattern)}` (precedent:
`spec/gen_proxy_ignore_spec.rb` lines 43-49 — `expect(statuses["Alamofire"]).to eq("ignored")`)
and the `--cache-only` shape in `spec/gen_proxy_cache_only_spec.rb` (same family).

**Absence-from-graph assertion idiom** for the transitive-only hazard
(`spec/gen_proxy_plugin_spec.rb` line 77):

```ruby
expect(statuses["MixedPlugin"]).to be_nil
```

**Partition semantics to copy (SC2's two arms):**
- Partition per-package identity (lockfile entry `name` / pin `identity`), aggregating graph
  entries by their owning package — graph.json is per-product (`module`), and one package can
  legitimately emit several product entries (`spec/gen_proxy_plugin_spec.rb` lines 72-82 shows a
  mixed package emitting `MixedLib` but not `MixedPlugin`).
- The spec's classifier must COLLECT all matching buckets per package (not first-match) so
  double-bucketing is detectable; iterate the fixture's declared input universe (Package.resolved
  pins + lockfile entries incl. local/path with empty `repositoryURL`), never the outputs.

---

### `spec/fidelity_edge_matrix_spec.rb` (test, file-I/O + transform)

**Analog:** `spec/build_pipeline_spec.rb` for the desc-raw edge-class shapes +
`spec/build_pipeline_provenance_spec.rb` lines 566-713 for the Class E fidelity variant. Build on
the same `stub_desc_products` / tmpdir scaffold as the drift spec above.

**Class 1 — binary target (Class E):** `spec/build_pipeline_spec.rb` lines 450-513 has the desc
raw (two-hop dummy.m wrapper chain terminating at a `BinaryTarget`) plus the required on-disk
artifacts layout and the SC4 guard:

```ruby
# Real SPM layout: {umbrella}/.build/checkouts/<pkg> (pkg_dir) is a
# sibling of {umbrella}/.build/artifacts/<pkg>/<Target>/<Target>.xcframework.
build_root = File.join(tmpdir, "umbrella", ".build")
real_pkg_dir = File.join(build_root, "checkouts", "firebase-ios-sdk")
FileUtils.mkdir_p(real_pkg_dir)
prebuilt = File.join(build_root, "artifacts", "firebase-ios-sdk", "FirebaseAnalytics", "FirebaseAnalytics.xcframework")
FileUtils.mkdir_p(File.join(prebuilt, "ios-arm64", "FirebaseAnalytics.framework", "Headers"))
File.write(File.join(prebuilt, "ios-arm64", "FirebaseAnalytics.framework", "Headers", "FIRAnalytics.h"), "// real header\n")
File.write(File.join(prebuilt, "Info.plist"), "<plist/>")

expect(SPMCache::SPM::Buildable).not_to receive(:new)
expect(SPMCache::Core::Sh).not_to receive(:run)
```

(The same layout + a host-pinned sidecar assertion appears at
`spec/build_pipeline_provenance_spec.rb` lines 600-640 — prefer that variant since TEST-03 wants
the fidelity angle: `expect(parsed["pins"]).to eq("FirebaseAnalytics" => "aaa")`.)

**Class 3 — vendored `.xcodeproj`:** `spec/build_pipeline_seeding_spec.rb` lines 208-221 /
`spec/build_pipeline_provenance_spec.rb` lines 447-470 — one `FileUtils.mkdir_p(File.join(pkg_dir,
"CryptoSwift.xcodeproj"))` plus assertion `parsed["fidelity_status"] == "not-graph-pinned"` with
`"pins" => {}`.

**Class 7 — private Clang shim:** `spec/build_pipeline_spec.rb` lines 113-164 — desc raw with a
SwiftTarget whose `target_dependencies` includes a `ClangTarget` not in product names; shim header
file on disk; `find_object_file` stub returning the shim `.o`; `XCFramework.new` stub
dispatching on `name:`; assert `RealModule.xcframework.shims.json` contains `["_NumericsShims"]`.

**Class 8 — product≠target rename:** `spec/build_pipeline_spec.rb` lines 327-360 — product raw
`"targets" => ["FirebaseAnalyticsWithoutAdIdSupportTarget"]` differing from product name; assert
`Buildable).to receive(:new).with(hash_including(scheme: <product>, module_name: <target>))` and
that `create_framework` names the framework after the target.

**Class 4 — plugin-only:** reuse the fixture `spec/fixtures/plugin-lockfile.json` entry shape
(SwiftGenPlugin, quoted below) driven via the tier-3 pattern; assert
`statuses["SwiftGenPlugin"] == "plugin"` (`spec/gen_proxy_plugin_spec.rb` lines 51-57).

**Class 5 — transitive-only:** no dedicated spec exists; the input-side classification shape is
a lockfile package absent from the consumed set. Assert absence from graph.json via the
`be_nil` idiom above AND explicit membership in the partition universe from the input side
(RESEARCH Pitfall 4).

**Classes 2 and 6 — no existing analog** (see No Analog Found).

**Matrix (table-driven) shape:** there is NO loop-generated-examples precedent in this suite.
Closest in-suite precedent is iterating inside one example
(`spec/gen_proxy_field_regression_spec.rb` line 59 + 85: `[umbrella_manifest, proxy_manifest].each do |manifest|`).
Either form is acceptable: (a) one `it "TEST-03: ..."` per class — matches the suite's dominant
one-behavior-per-example style and gives the clearest failure output, or (b) an `CLASSES.each`
block generating one `it` per class — plain RSpec, Ruby 3.1-safe, but new to this repo. Prefer (a)
unless example count is a concern; per-class local builder methods keep it DRY (the suite's
convention: helpers are plain `def` methods inside the describe block, no `spec/support/`).

---

### `spec/fixtures/fidelity-kitchen-sink-lockfile.json` (test fixture, file-I/O)

**Analog:** `spec/fixtures/plugin-lockfile.json` — exact shape to extend (top level keyed by
project name; `packages` array; `dependencies: {}`; `platforms`). Naming convention across all
four existing fixtures: `spec/fixtures/*-lockfile.json`.

```json
{
  "FixtureApp.xcodeproj": {
    "packages": [
      {
        "repositoryURL": "https://github.com/SwiftGen/SwiftGenPlugin.git",
        "name": "SwiftGenPlugin",
        "version": "6.6.3",
        "products": [
          { "name": "SwiftGenPlugin", "type": "plugin", "targets": ["SwiftGenPlugin"] }
        ]
      },
      {
        "repositoryURL": "https://github.com/Alamofire/Alamofire.git",
        "name": "Alamofire",
        "version": "5.9.1",
        "products": [
          { "name": "Alamofire", "type": "library", "targets": ["Alamofire"] }
        ]
      }
    ],
    "dependencies": {},
    "platforms": {
      "ios": "16.0"
    }
  }
}
```

For the local/path package (empty `repositoryURL` — the excluded/local bucket): emit an entry
with `"repositoryURL": ""`. For product≠target rename in a fixture: product `targets` array
naming a differently-named target. Kitchen-sink entries should use fake URLs/revisions only
(no credentials — existing convention).

---

## Shared Patterns

### Hermetic tier-1 scaffold
**Source:** `spec/build_pipeline_provenance_spec.rb` lines 13-45 (quoted in full above)
**Apply to:** all three new spec files (drift, partition fidelity legs, matrix).
`Dir.mktmpdir` + real filesystem for `Package.resolved`/sidecars + `instance_double` for
`Desc::Description` / `Buildable` / `XCFramework` + `after { FileUtils.rm_rf(tmpdir) }`.

### SC4 executable hermeticity guard — two intensities
**Source:** `spec/build_pipeline_provenance_spec.rb` lines 622-623 (strictest form — specs that
need NO shell at all):
```ruby
expect(SPMCache::SPM::Buildable).not_to receive(:new)
expect(SPMCache::Core::Sh).not_to receive(:run)
```
**Source:** `spec/build_pipeline_seeding_spec.rb` lines 321-322 (permissive tier-2 form — the
base shape to make strict):
```ruby
allow(SPMCache::Core::Sh).to receive(:run)
allow(SPMCache::Core::Sh).to receive(:capture_output).and_return("")
```
**Apply to:** every new spec. Generalize the permissive form into the SC4 allowlist guard
(default-deny, then re-allow expected commands with `.with(...)`):
```ruby
allow(SPMCache::Core::Sh).to receive(:run) do |cmd, *_opts|
  raise "unexpected real invocation: Sh.run(#{cmd.inspect})"
end
allow(SPMCache::Core::Sh).to receive(:capture_output) do |cmd, *_opts|
  raise "unexpected real invocation: Sh.capture_output(#{cmd.inspect})"
end
```
`Sh.run` and `Sh.capture_output` are the only two entry points (`lib/spm_cache/core/sh.rb`).

### Output + sidecar assertion channels
**Source:** `spec/build_pipeline_provenance_spec.rb` lines 69-93 (drift), 476-484 (`not_to output`
negative form)
**Apply to:** drift and matrix specs. Status line → stdout; drift warn → stderr (`Core::UI.warn`
prefixes `[warn] `); the durable contract is the sidecar JSON on disk. Chain both channels; match
the intended/realized pin pair verbatim.

### Tier-3 proxy-binary pattern
**Source:** `spec/gen_proxy_provenance_spec.rb` lines 15-55 (skip-guard, write_lockfile,
write_sidecar, run_gen_proxy, statuses_from); flag variants at `spec/gen_proxy_ignore_spec.rb`
lines 37-41; fixture-loading variant at `spec/gen_proxy_plugin_spec.rb` lines 20-27
**Apply to:** partition spec graph legs; drift spec's sidecar-disagreement leg; matrix spec's
plugin-only class.

### TEST-ID traceability strings
**Source:** describe strings with requirement IDs — `spec/build_pipeline_provenance_spec.rb`
line 404 `"(09-01, Pattern 3)"`, line 189 `"(WR-02)"`, line 877 `"(Pitfall 2 regression guard)"`;
SC IDs in `it` strings — `spec/gen_proxy_provenance_spec.rb` lines 57/81/116/158/182
(`"SC1: ..."`, `"SC2: ..."`)
**Apply to:** all three new files — put `TEST-01` / `TEST-02` / `TEST-03` in the describe (or it)
strings per CONTEXT's verifier-traceability decision.

### Ruby style (RuboCop-enforced)
**Source:** every existing spec — `# frozen_string_literal: true` line 1; requires:
`require "spec_helper"` + `require "tmpdir"` + `require "json"` (+ `require "shellwords"` only
when passing patterns to the binary, per `spec/gen_proxy_ignore_spec.rb` line 6)
**Apply to:** all new files. `spec_helper.rb` only requires `spm_cache/main` — no other setup.
RSpec built-in matchers only; Ruby 3.1-compatible syntax (no 3.2+-only constructs); no sleeps;
helpers are plain local `def` methods inside the describe block (no `spec/support/`).

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `spec/fidelity_edge_matrix_spec.rb` — "macro with narrow `swift-syntax` pin" class | test | file-I/O | No fidelity scenario anywhere covers `swift-syntax` pins (`hasMacro` is hardcoded `false` Swift-side). Coverable as pure pin data: seeded `Package.resolved` with a `"swift-syntax"` identity at a narrow revision + the drift-injection idiom — the class IS the pin-fidelity contract. |
| `spec/fidelity_edge_matrix_spec.rb` — "resource bundle" class | test | file-I/O | Only incidental coverage (a binaryTarget path string). New shape: describe-JSON target carrying `"resources": [{"path": ...}]` (parser: `lib/spm_cache/spm/desc/target.rb` `resource_paths`); assert the `*.bundle` reaches the assembled framework (`lib/spm_cache/spm/xcframework/slice.rb` `copy_resource_bundles`). |
| loop-generated table-driven examples (matrix structure) | test | transform | No precedent in this suite for `each`-generated `it` blocks; nearest is iteration inside a single example (`spec/gen_proxy_field_regression_spec.rb:59,85`). Recommend one `it` per class instead (matches suite style). |

For these, the planner should follow the RESEARCH.md "New fixture shape" guidance rather than a
codebase analog.

## Metadata

**Analog search scope:** `spec/` (44 spec files + `spec/fixtures/`), `CLAUDE.md`, `spec/spec_helper.rb`
**Files read for excerpts:** `spec/build_pipeline_provenance_spec.rb`, `spec/build_pipeline_seeding_spec.rb`, `spec/build_pipeline_spec.rb` (targeted ranges), `spec/gen_proxy_provenance_spec.rb`, `spec/gen_proxy_plugin_spec.rb`, `spec/gen_proxy_ignore_spec.rb`, `spec/resolved_graph_spec.rb`, `spec/fixtures/plugin-lockfile.json`, `spec/spec_helper.rb`
**Pattern extraction date:** 2026-08-29
