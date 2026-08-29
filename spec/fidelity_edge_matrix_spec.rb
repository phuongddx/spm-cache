# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "json"

# TEST-03 matrix contract: all eight v0.2.x edge classes pinned in ONE file,
# one example per class, so the compatibility surface of Phases 6-9 cannot
# regress silently --
#   class 1/8 binary target (Class E), class 2/8 macro with a narrow
#   swift-syntax pin, class 3/8 vendored .xcodeproj, class 4/8 plugin-only,
#   class 5/8 transitive-only, class 6/8 resource bundle, class 7/8 private
#   Clang shim, class 8/8 product-not-equal-target rename.
# The existing scattered edge-class specs stay untouched: this matrix is NEW
# coverage running alongside them (SC3's "passes unchanged" means no churn,
# no migration). Everything is hermetic (SC4): the tier-1 legs run under a
# default-deny Core::Sh guard so any surviving real swift/xcodebuild
# invocation raises instead of running -- strict not_to-receive guards where
# NO shell is expected at all, an explicit allowlist otherwise; the tier-3
# legs (plugin/transitive) invoke ONLY the local compiled spm-cache-proxy
# binary via system(), never Core::Sh, never the network.
RSpec.describe SPMCache::SPM::BuildPipeline, "TEST-03: v0.2.x edge-class fixture matrix" do
  let(:tmpdir) { Dir.mktmpdir }
  let(:pkg_dir) { File.join(tmpdir, "pkg") }
  let(:out_dir) { File.join(tmpdir, "out") }
  let(:resolved_pins_file) { File.join(tmpdir, "host-Package.resolved") }

  # Builds a stubbed Desc::Description double (the tier-1 seam intercepting
  # the only real shell-out in the describe path -- `swift package describe`)
  # returning the given raw product hashes and target raw hashes, exactly as
  # spec/build_pipeline_provenance_spec.rb does.
  def stub_desc_products(products, pkg_dir:, raw_targets: [])
    fake_desc = instance_double(SPMCache::SPM::Desc::Description)
    allow(SPMCache::SPM::Desc::Description).to receive(:new).and_return(fake_desc)
    allow(fake_desc).to receive(:fetch)
    allow(fake_desc).to receive(:products).and_return(
      products.map { |p| SPMCache::SPM::Desc::Product.new(raw: p, pkg_dir: pkg_dir) },
    )
    allow(fake_desc).to receive(:raw).and_return({ "targets" => raw_targets })
    fake_desc
  end

  def write_resolved_pins(path, pin_map)
    File.write(path, JSON.generate(
      "pins" => pin_map.map { |identity, revision| { "identity" => identity, "state" => { "revision" => revision } } },
    ))
  end

  # SC4 executable hermeticity guard (default-deny, both Core::Sh entry
  # points): the tier-1 seam must need ZERO real shell-outs, so any
  # invocation that survives the object stubs raises instead of running.
  # Examples that DO expect specific tool invocations (the shim/resource
  # legs' libtool/swiftc) re-allow exactly those command prefixes on top --
  # everything else still raises.
  before do
    FileUtils.mkdir_p(pkg_dir)
    FileUtils.mkdir_p(out_dir)
    allow(SPMCache::Core::Sh).to receive(:run) do |cmd, *_opts|
      raise "unexpected real invocation: Sh.run(#{cmd.inspect})"
    end
    allow(SPMCache::Core::Sh).to receive(:capture_output) do |cmd, *_opts|
      raise "unexpected real invocation: Sh.capture_output(#{cmd.inspect})"
    end
  end

  after { FileUtils.rm_rf(tmpdir) }

  # Real SPM layout: {umbrella}/.build/checkouts/<pkg> (pkg_dir) is a
  # sibling of {umbrella}/.build/artifacts/<pkg>/<Target>/<Target>.xcframework
  # (required by locate_prebuilt_xcframework's checkouts-sibling rule).
  # Returns the checkout dir to use as pkg_dir.
  def class_e_layout
    build_root = File.join(tmpdir, "umbrella", ".build")
    real_pkg_dir = File.join(build_root, "checkouts", "firebase-ios-sdk")
    FileUtils.mkdir_p(real_pkg_dir)
    prebuilt = File.join(build_root, "artifacts", "firebase-ios-sdk", "FirebaseAnalytics", "FirebaseAnalytics.xcframework")
    FileUtils.mkdir_p(File.join(prebuilt, "ios-arm64", "FirebaseAnalytics.framework", "Headers"))
    File.write(File.join(prebuilt, "ios-arm64", "FirebaseAnalytics.framework", "Headers", "FIRAnalytics.h"), "// real header\n")
    File.write(File.join(prebuilt, "Info.plist"), "<plist/>")
    real_pkg_dir
  end

  # The FirebaseAnalytics two-hop dummy.m forwarder chain terminating at a
  # BinaryTarget (Google's "SwiftPM-PlatformExclude" convention).
  def class_e_desc_raw_targets
    [
      { "name" => "FirebaseAnalyticsTarget", "module_type" => "ClangTarget", "sources" => ["dummy.m"],
        "path" => "SwiftPM-PlatformExclude/FirebaseAnalyticsWrap",
        "target_dependencies" => ["FirebaseAnalyticsWrapper"] },
      { "name" => "FirebaseAnalyticsWrapper", "module_type" => "ClangTarget", "sources" => ["dummy.m"],
        "path" => "FirebaseAnalyticsWrapper",
        "target_dependencies" => ["FirebaseAnalytics", "FirebaseCore", "FirebaseInstallations"] },
      { "name" => "FirebaseAnalytics", "module_type" => "BinaryTarget", "path" => "remote/archive/FirebaseAnalytics.zip" },
      { "name" => "FirebaseCore", "module_type" => "ClangTarget", "sources" => ["FIRApp.m"], "path" => "FirebaseCore/Sources" },
      { "name" => "FirebaseInstallations", "module_type" => "ClangTarget", "sources" => ["FIRInstallations.m"],
        "path" => "FirebaseInstallations/Source/Library" },
    ]
  end

  describe "class 1/8: binary target (Class E)" do
    it "TEST-03 class 1/8: binary target (Class E) copies the real prebuilt xcframework and records a fidelity sidecar" do
      write_resolved_pins(resolved_pins_file, "FirebaseAnalytics" => "aaa")
      real_pkg_dir = class_e_layout
      stub_desc_products(
        [{ "name" => "FirebaseAnalytics", "type" => { "library" => ["automatic"] },
           "targets" => ["FirebaseAnalyticsTarget"] }],
        pkg_dir: real_pkg_dir,
        raw_targets: class_e_desc_raw_targets,
      )

      # SC4, strictest form: the direct-copy path must shell out to nothing.
      expect(SPMCache::SPM::Buildable).not_to receive(:new)
      expect(SPMCache::Core::Sh).not_to receive(:run)

      result = described_class.run(
        name: "FirebaseAnalytics",
        pkg_dir: real_pkg_dir,
        destinations: ["iphonesimulator"],
        out_dir: out_dir,
        resolved_pins_file: resolved_pins_file,
        config: "release",
      )

      # Copy outcome: the returned path IS the copied prebuilt xcframework,
      # carrying the real slice content (header + Info.plist), not a stub.
      expect(result).to eq(File.join(out_dir, "FirebaseAnalytics.xcframework"))
      copied_header = File.join(result, "ios-arm64", "FirebaseAnalytics.framework", "Headers", "FIRAnalytics.h")
      expect(File.read(copied_header)).to eq("// real header\n")
      expect(File.exist?(File.join(result, "Info.plist"))).to be true

      # Fidelity angle: the sidecar records host-pinned with the pin preserved.
      sidecar = JSON.parse(File.read("#{result}.provenance.json"))
      expect(sidecar["fidelity_status"]).to eq("host-pinned")
      expect(sidecar["pins"]).to eq("FirebaseAnalytics" => "aaa")
    end
  end

  # Installs the standard tier-1 Buildable/XCFramework stubs for one
  # source-build leg of `name` (no drift injection -- the agreeing-pins
  # shape). Returns the fake buildable so drift-injection examples can layer
  # their own build_for_destination override on top of it.
  def stub_build_leg(name:)
    fake_buildable = instance_double(SPMCache::SPM::Buildable)
    allow(SPMCache::SPM::Buildable).to receive(:new).and_return(fake_buildable)
    allow(fake_buildable).to receive(:build_for_destination) do |*_args, **_kwargs|
      {
        derived_data: "/dd",
        object_file: "/dd/#{name}.o",
        swiftmodule: nil, swiftdoc: nil, swiftsourceinfo: nil, swiftinterface: nil,
      }
    end
    allow(fake_buildable).to receive(:create_framework) do |_arts, subdir|
      fw = File.join(subdir, "#{name}.framework")
      FileUtils.mkdir_p(fw)
      File.write(File.join(fw, name), "stub")
      fw
    end
    allow(SPMCache::SPM::XCFramework::XCFramework).to receive(:new).and_return(
      double("XCFramework", build: File.join(out_dir, "#{name}.xcframework")),
    )
    fake_buildable
  end

  # A vendored-.xcodeproj checkout: one directory is enough, because the
  # classifier (ResolvedGraph.vendored_xcodeproj?) is a plain glob over
  # pkg_dir/*.xcodeproj.
  def vendored_xcodeproj_pkg(name:)
    FileUtils.mkdir_p(File.join(pkg_dir, "#{name}.xcodeproj"))
    pkg_dir
  end

  describe "class 3/8: vendored .xcodeproj" do
    it "TEST-03 class 3/8: a vendored .xcodeproj checkout is classified not-graph-pinned with an empty pins sidecar" do
      write_resolved_pins(resolved_pins_file, "CryptoSwift" => "ccc111")
      vendored_pkg = vendored_xcodeproj_pkg(name: "CryptoSwift")
      stub_desc_products(
        [{ "name" => "CryptoSwift", "type" => { "library" => ["automatic"] } }],
        pkg_dir: vendored_pkg,
      )
      stub_build_leg(name: "CryptoSwift")

      result = described_class.run(
        name: "CryptoSwift",
        pkg_dir: vendored_pkg,
        destinations: ["iphonesimulator"],
        out_dir: out_dir,
        resolved_pins_file: resolved_pins_file,
        config: "debug",
      )

      # The class contract read from disk: Package.resolved is structurally
      # irrelevant for a vendored checkout, so the sidecar says not-graph-
      # pinned with empty pins -- never a silently-assumed pin.
      sidecar = JSON.parse(File.read("#{result}.provenance.json"))
      expect(sidecar["fidelity_status"]).to eq("not-graph-pinned")
      expect(sidecar["pins"]).to eq({})
    end
  end

  # swift-numerics' RealModule -> _NumericsShims shape: a Swift target
  # privately depending on an internal Clang target that is never declared
  # as its own library product.
  def clang_shim_desc_raw
    [
      { "name" => "RealModule", "module_type" => "SwiftTarget", "target_dependencies" => ["_NumericsShims"] },
      { "name" => "_NumericsShims", "module_type" => "ClangTarget", "path" => "Sources/_NumericsShims" },
    ]
  end

  describe "class 7/8: private Clang shim" do
    it "TEST-03 class 7/8: a private ClangTarget dependency is assembled as a companion shim named in shims.json" do
      shim_include_dir = File.join(pkg_dir, "Sources", "_NumericsShims", "include")
      FileUtils.mkdir_p(shim_include_dir)
      File.write(File.join(shim_include_dir, "_NumericsShims.h"), "// shim header\n")

      stub_desc_products(
        [{ "name" => "RealModule", "type" => { "library" => ["automatic"] } }],
        pkg_dir: pkg_dir,
        raw_targets: clang_shim_desc_raw,
      )

      dd_dir = File.join(tmpdir, "dd")
      FileUtils.mkdir_p(dd_dir)
      shim_object_file = File.join(dd_dir, "_NumericsShims.o")
      File.write(shim_object_file, "fake object")

      fake_buildable = instance_double(SPMCache::SPM::Buildable)
      allow(SPMCache::SPM::Buildable).to receive(:new).and_return(fake_buildable)
      artifacts = {
        derived_data: dd_dir,
        object_file: File.join(dd_dir, "RealModule.o"),
        swiftmodule: nil, swiftdoc: nil, swiftsourceinfo: nil, swiftinterface: nil,
      }
      allow(fake_buildable).to receive(:build_for_destination).and_return(artifacts)
      allow(fake_buildable).to receive(:create_framework) do |_arts, subdir|
        fw = File.join(subdir, "RealModule.framework")
        FileUtils.mkdir_p(fw)
        fw
      end
      allow(fake_buildable).to receive(:find_object_file).and_return(shim_object_file)

      main_xc = double("MainXCFramework", build: File.join(out_dir, "RealModule.xcframework"))
      shim_xc = double("ShimXCFramework", build: File.join(out_dir, "_NumericsShims.xcframework"))
      allow(SPMCache::SPM::XCFramework::XCFramework).to receive(:new) do |name:, **_kwargs|
        name == "RealModule" ? main_xc : shim_xc
      end

      # SC4 allowlist over the default-deny guard: the shim assembly's one
      # genuine tool invocation is libtool; any other command still raises.
      allow(SPMCache::Core::Sh).to receive(:run).with(/\Alibtool -static -o /)

      result = described_class.run(
        name: "RealModule",
        pkg_dir: pkg_dir,
        destinations: ["iphonesimulator"],
        out_dir: out_dir,
      )

      expect(result).to eq(File.join(out_dir, "RealModule.xcframework"))
      sidecar = File.join(out_dir, "RealModule.xcframework.shims.json")
      expect(File.exist?(sidecar)).to be true
      expect(JSON.parse(File.read(sidecar))).to eq(["_NumericsShims"])
    end
  end

  # firebase-ios-sdk's rename family: product
  # FirebaseAnalyticsWithoutAdIdSupport backed by a single differently-named
  # target -- Xcode links the object file under the TARGET's name.
  def rename_product_raw
    { "name" => "FirebaseAnalyticsWithoutAdIdSupport", "type" => { "library" => ["automatic"] },
      "targets" => ["FirebaseAnalyticsWithoutAdIdSupportTarget"] }
  end

  describe "class 8/8: product-not-equal-target rename" do
    it "TEST-03 class 8/8: the product names the scheme, its differing target names module_name, and the framework is target-named" do
      stub_desc_products([rename_product_raw], pkg_dir: pkg_dir)
      allow(SPMCache::SPM::XCFramework::XCFramework).to receive(:new).and_return(
        double("XCFramework", build: File.join(out_dir, "FirebaseAnalyticsWithoutAdIdSupport.xcframework")),
      )
      created_frameworks = []

      expect(SPMCache::SPM::Buildable).to receive(:new)
        .with(hash_including(scheme: "FirebaseAnalyticsWithoutAdIdSupport",
                             module_name: "FirebaseAnalyticsWithoutAdIdSupportTarget"))
        .and_return(instance_double(SPMCache::SPM::Buildable).tap do |fb|
          allow(fb).to receive(:build_for_destination).and_return(
            object_file: "/dd/FirebaseAnalyticsWithoutAdIdSupportTarget.o",
          )
          allow(fb).to receive(:create_framework) do |_arts, subdir|
            # Matches real Buildable#create_framework: the framework and its
            # binary are named after @module_name (the target), never the
            # product -- rename_framework_to_product fixes that up afterward.
            fw = File.join(subdir, "FirebaseAnalyticsWithoutAdIdSupportTarget.framework")
            FileUtils.mkdir_p(fw)
            File.write(File.join(fw, "FirebaseAnalyticsWithoutAdIdSupportTarget"), "stub")
            created_frameworks << fw
            fw
          end
        end)

      result = described_class.run(
        name: "FirebaseAnalyticsWithoutAdIdSupport",
        pkg_dir: pkg_dir,
        destinations: ["iphonesimulator"],
        out_dir: out_dir,
      )

      expect(File.basename(created_frameworks.first)).to eq("FirebaseAnalyticsWithoutAdIdSupportTarget.framework")
      expect(result).to eq(File.join(out_dir, "FirebaseAnalyticsWithoutAdIdSupport.xcframework"))
    end
  end

  # The narrow pin shape of a macro package: the macro package's own pin
  # plus the exact swift-syntax revision its implementation target builds
  # against -- the identity whose silent re-resolution is this class's
  # fidelity contract. No macro-specific production code exists to drive;
  # the class IS the pin data.
  def macro_pins
    { "macro-kit" => "mmm111", "swift-syntax" => "aaa111" }
  end

  # Standard tier-1 leg for the macro package whose build_for_destination
  # rewrites pkg_dir/Package.resolved with `realized_pins` before returning
  # its artifacts (the proven drift-injection idiom).
  def run_macro_with_realized_pins(realized_pins)
    fake_buildable = instance_double(SPMCache::SPM::Buildable)
    allow(SPMCache::SPM::Buildable).to receive(:new).and_return(fake_buildable)
    allow(fake_buildable).to receive(:build_for_destination) do |*_args, **_kwargs|
      write_resolved_pins(File.join(pkg_dir, "Package.resolved"), realized_pins)
      {
        derived_data: "/dd",
        object_file: "/dd/MacroKit.o",
        swiftmodule: nil, swiftdoc: nil, swiftsourceinfo: nil, swiftinterface: nil,
      }
    end
    allow(fake_buildable).to receive(:create_framework) do |_arts, subdir|
      fw = File.join(subdir, "MacroKit.framework")
      FileUtils.mkdir_p(fw)
      File.write(File.join(fw, "MacroKit"), "stub")
      fw
    end

    described_class.run(
      name: "MacroKit", pkg_dir: pkg_dir, destinations: ["iphonesimulator"],
      out_dir: out_dir, resolved_pins_file: resolved_pins_file, config: "debug",
    )
  end

  describe "class 2/8: macro with a narrow swift-syntax pin" do
    it "TEST-03 class 2/8: an agreeing narrow swift-syntax pin stays host-pinned silently; a drifted revision warns and is resolution-incompatible" do
      write_resolved_pins(resolved_pins_file, macro_pins)
      stub_desc_products(
        [{ "name" => "MacroKit", "type" => { "library" => ["automatic"] } }],
        pkg_dir: pkg_dir,
        raw_targets: [
          { "name" => "MacroKit", "module_type" => "SwiftTarget", "path" => "Sources/MacroKit",
            "target_dependencies" => ["swift-syntax"] },
        ],
      )
      allow(SPMCache::SPM::XCFramework::XCFramework).to receive(:new).and_return(
        double("XCFramework", build: File.join(out_dir, "MacroKit.xcframework")),
      )

      # Direction 1 -- the agreeing narrow pin: host-pinned, and no drift
      # warn names the swift-syntax identity (false-positive guard).
      agreeing = nil
      expect {
        agreeing = run_macro_with_realized_pins(macro_pins)
      }.to output(/MacroKit: host-pinned/).to_stdout
      expect {
        run_macro_with_realized_pins(macro_pins)
      }.not_to output(/drift detected/).to_stderr
      agreeing_sidecar = JSON.parse(File.read("#{agreeing}.provenance.json"))
      expect(agreeing_sidecar["fidelity_status"]).to eq("host-pinned")
      expect(agreeing_sidecar["pins"]).to include("swift-syntax" => "aaa111")

      # Direction 2 -- the drifted swift-syntax revision (the macro's own
      # pin still agreeing): the warn names the swift-syntax identity with
      # both values, and the sidecar flips to resolution-incompatible with
      # the drifted value on record.
      drifted = nil
      expect {
        drifted = run_macro_with_realized_pins("macro-kit" => "mmm111", "swift-syntax" => "bbb222")
      }.to output(/resolution-incompatible/).to_stdout
        .and output(/swift-syntax.*aaa111.*bbb222/).to_stderr
      drifted_sidecar = JSON.parse(File.read("#{drifted}.provenance.json"))
      expect(drifted_sidecar["fidelity_status"]).to eq("resolution-incompatible")
      expect(drifted_sidecar["pins"]).to include("swift-syntax" => "bbb222")
    end
  end
end

# TEST-03 tier-3 legs: the plugin-only and transitive-only classes are
# decided by the Swift companion's ProxyGenerator, so these examples run the
# actual compiled spm-cache-proxy binary -- offline, via system() with output
# redirected to File::NULL: no Core::Sh, no network, no xcodebuild (SC4).
# CI builds the binary before RSpec on every matrix leg; locally the
# examples skip when it is not built.
RSpec.describe "TEST-03: v0.2.x edge-class fixture matrix (tier-3 legs via compiled spm-cache-proxy)" do
  let(:binary) do
    local = SPMCache::ROOT.join("tools", "spm-cache-proxy",
                                ".build", "release", "spm-cache-proxy").to_s
    File.executable?(local) ? local : nil
  end

  let(:tmpdir) { Dir.mktmpdir }
  let(:umbrella_dir) { File.join(tmpdir, "umbrella") }
  let(:output_dir) { File.join(tmpdir, "proxy") }
  let(:cache_dir) { File.join(tmpdir, "cache") }

  before do
    skip "spm-cache-proxy binary not built (run make proxy.build)" unless binary
    FileUtils.mkdir_p(umbrella_dir)
    FileUtils.mkdir_p(output_dir)
    FileUtils.mkdir_p(cache_dir)
    # SC4 guard stays armed during the tier-3 legs: system() never routes
    # through Core::Sh, so the guard only fires on accidental real
    # shell-outs (spec/fidelity_bucket_partition_spec.rb precedent).
    allow(SPMCache::Core::Sh).to receive(:run) do |cmd, *_opts|
      raise "unexpected real invocation: Sh.run(#{cmd.inspect})"
    end
    allow(SPMCache::Core::Sh).to receive(:capture_output) do |cmd, *_opts|
      raise "unexpected real invocation: Sh.capture_output(#{cmd.inspect})"
    end
  end

  after { FileUtils.rm_rf(tmpdir) if tmpdir }

  def write_lockfile(path, project_name:, packages:, dependencies: {})
    File.write(path, JSON.generate(
      project_name => {
        "packages" => packages,
        "dependencies" => dependencies,
        "platforms" => { "ios" => "16.0" },
      },
    ))
  end

  def run_gen_proxy(lockfile:)
    cmd = "#{binary} gen-proxy --umbrella #{umbrella_dir} --lockfile #{lockfile} " \
          "--output #{output_dir} --cache #{cache_dir}"
    system(cmd, out: File::NULL, err: File::NULL)
  end

  def statuses_from(dir)
    graph = JSON.parse(File.read(File.join(dir, "graph.json")))
    graph.each_with_object({}) { |e, h| h[e["module"]] = e["status"] }
  end

  it "TEST-03 class 4/8: the plugin-only package surfaces the plugin status in graph.json and gets no proxy folder" do
    lockfile = SPMCache::ROOT.join("spec", "fixtures", "plugin-lockfile.json").to_s
    run_gen_proxy(lockfile: lockfile)

    statuses = statuses_from(output_dir)
    expect(statuses["SwiftGenPlugin"]).to eq("plugin")
    expect(File.directory?(File.join(output_dir, ".proxies", "SwiftGenPlugin_proxy"))).to be false
  end

  it "TEST-03 class 5/8: the transitive-only package has NO graph entry yet stays a declared input, pinned via its consumer" do
    packages = [
      { "repositoryURL" => "https://example.invalid/macro-host.git",
        "name" => "macro-host", "revision" => "mmm111",
        "products" => [{ "name" => "MacroHostKit", "type" => "library", "targets" => ["MacroHostKit"] }] },
      { "repositoryURL" => "https://example.invalid/swift-syntax.git",
        "name" => "swift-syntax", "revision" => "sss111",
        "products" => [{ "name" => "SwiftSyntax", "type" => "library", "targets" => ["SwiftSyntax"] }] },
    ]
    lockfile = File.join(tmpdir, "matrix-lockfile.json")
    write_lockfile(lockfile, project_name: "MatrixApp.xcodeproj", packages: packages,
                           dependencies: { "MatrixApp" => ["MacroHostKit"] })

    run_gen_proxy(lockfile: lockfile)
    statuses = statuses_from(output_dir)

    # Production skips transitive-only packages by design (ProxyGenerator's
    # isTransitiveOnly -> continue): referencing them from the root proxy
    # would independently pin them at a conflicting version. Their absence
    # from graph.json is INTENTIONAL -- the class is classified input-side.
    # The consumed sibling's entry proves the generator did run, so the nil
    # is a real decision, not a vacuous lookup.
    expect(statuses["SwiftSyntax"]).to be_nil
    expect(statuses["MacroHostKit"]).to eq("missed")

    # Input-side membership: the transitive package IS in the declared
    # universe (present in the lockfile's package list), pinned via its
    # consumer -- never silently absent from the partition.
    declared = JSON.parse(File.read(lockfile)).fetch("MatrixApp.xcodeproj")
                   .fetch("packages").map { |p| p.fetch("name") }
    expect(declared).to include("swift-syntax")
  end
end

# TEST-03 class 6/8 (resource bundle): the REAL Desc::Target parser resolves
# the describe-JSON resources array, and the REAL slice copy behavior
# (FrameworkSlice#copy_resource_bundles -- glob *.bundle from the build
# products into the framework path, skipping existing destinations, Pitfall
# 14's stale-bundle semantics) delivers the bundle into the assembled
# framework.
#
# DISCOVERED PRE-EXISTING GAPS (logged in 10-03-SUMMARY.md, out of scope for
# this zero-production-change phase) -- FrameworkSlice is unwired dead code
# with three independent defects keeping its public #create_framework from
# ever reaching the resource copy: (1) Desc::Target#resource_paths is PRIVATE
# (target.rb:123 sits below the first `private`), so slice.rb's
# `respond_to?(:resource_paths)` guards are always false; (2) slice.rb:64
# calls bare `Sh`, a NameError inside that namespace; (3) its
# Utils::Template.render_to calls render templates whose `<%= module_name %>`
# placeholders have no binding (the LIVE assembly path,
# Buildable#framework_info_plist, inlines the plist instead). The spec
# therefore drives the real copy behavior directly against the slice's
# public framework_path destination -- the semantics this class pins.
RSpec.describe SPMCache::SPM::XCFramework::FrameworkSlice, "TEST-03 class 6/8: resource bundle" do
  let(:tmpdir) { Dir.mktmpdir }
  let(:pkg_dir) { File.join(tmpdir, "pkg") }

  before do
    FileUtils.mkdir_p(pkg_dir)
    allow(SPMCache::Core::Sh).to receive(:run) do |cmd, *_opts|
      raise "unexpected real invocation: Sh.run(#{cmd.inspect})"
    end
    allow(SPMCache::Core::Sh).to receive(:capture_output) do |cmd, *_opts|
      raise "unexpected real invocation: Sh.capture_output(#{cmd.inspect})"
    end
  end

  after { FileUtils.rm_rf(tmpdir) }

  # A describe-JSON target carrying a resources array (the swift package
  # describe shape: entries with a path plus a copy rule).
  def resource_bundle_target_raw
    {
      "name" => "BundleHost", "module_type" => "SwiftTarget",
      "resources" => [{ "path" => "SomeResources", "rule" => { "copy" => {} } }],
    }
  end

  # Builds a real slice whose framework destination is a freshly assembled
  # <out>/BundleHost.framework directory (the duck-typed buildable supplies
  # only build_products_dir -- the one collaborator the copy reads).
  def slice_against_framework_at(fw_parent)
    build_products = File.join(tmpdir, "products")
    FileUtils.mkdir_p(build_products)
    fw_path = File.join(fw_parent, "BundleHost.framework")
    FileUtils.mkdir_p(fw_path)
    buildable = double("SliceBuildable", build_products_dir: build_products)
    target = SPMCache::SPM::Desc::Target.new(raw: resource_bundle_target_raw, pkg_dir: pkg_dir)
    sdk = double("SDK", triple: "arm64-apple-ios-simulator")
    slice = described_class.new(target: target, sdk: sdk, buildable: buildable)
    slice.instance_variable_set(:@framework_path, fw_path)
    [slice, fw_path]
  end

  it "TEST-03 class 6/8: the resources array parses to a joined path and the built *.bundle is delivered into the assembled framework" do
    target = SPMCache::SPM::Desc::Target.new(raw: resource_bundle_target_raw, pkg_dir: pkg_dir)

    # REAL parser: Desc::Target#resource_paths resolves the resources array
    # into a joined path under pkg_dir. Called via send because the method
    # is private (gap #1 above the describe block).
    expect(target.send(:resource_paths)).to eq([File.join(pkg_dir, "SomeResources")])

    # The built bundle where the real copy behavior globs it from: the build
    # products location (swiftc materializes a target's resource directory
    # as <name>.bundle there).
    built_bundle = File.join(tmpdir, "products", "SomeResources.bundle")
    FileUtils.mkdir_p(built_bundle)
    File.write(File.join(built_bundle, "asset.txt"), "fresh\n")

    # REAL copy behavior, fresh destination: the bundle is delivered into
    # the assembled framework path, contents intact.
    fresh_slice, fw_path = slice_against_framework_at(File.join(tmpdir, "fw-out"))
    fresh_slice.send(:copy_resource_bundles)
    expect(fw_path).to eq(File.join(tmpdir, "fw-out", "BundleHost.framework"))
    copied = File.join(fw_path, "SomeResources.bundle")
    expect(File.directory?(copied)).to be true
    expect(File.read(File.join(copied, "asset.txt"))).to eq("fresh\n")

    # Pitfall 14 semantics (the unless-exists skip): a destination bundle
    # already present is NOT overwritten -- a stale bundle persists rather
    # than being refreshed by the copy.
    stale_slice, _stale_fw = slice_against_framework_at(File.join(tmpdir, "fw-stale"))
    stale_bundle = File.join(stale_slice.framework_path, "SomeResources.bundle")
    FileUtils.mkdir_p(stale_bundle)
    File.write(File.join(stale_bundle, "asset.txt"), "stale\n")
    stale_slice.send(:copy_resource_bundles)
    expect(File.read(File.join(stale_bundle, "asset.txt"))).to eq("stale\n")
  end
end

# SC4 sweep: hermeticity as an executable assertion, not a convention -- the
# default-deny guard itself fails an example the moment any leg attempts an
# unexpected real shell-out (both Core::Sh entry points carry the guard; the
# tier-3 legs' only subprocess is the local compiled proxy binary). The audit
# drives REAL production shell-out seams -- the exact calls the matrix legs'
# object stubs intercept -- and requires the guard to intercept them, so it
# has teeth against production: a change that bypassed Core::Sh (backticks,
# system, raw Open3) or stopped routing an entry point through Sh.run makes
# this example fail (no raise) instead of echoing the stub back to itself.
RSpec.describe "TEST-03 SC4: matrix hermeticity audit" do
  it "TEST-03 SC4: the default-deny guard intercepts real production shell-out paths instead of running them" do
    Dir.mktmpdir do |pkg_dir|
      allow(SPMCache::Core::Sh).to receive(:run) do |cmd, *_opts|
        raise "unexpected real invocation: Sh.run(#{cmd.inspect})"
      end

      # Seam 1 -- Desc::Description#fetch (desc/base.rb) is the tier-1 legs'
      # one real shell-out: `swift package describe --type json` via Sh.run.
      # Nothing else is stubbed here, so production code must genuinely route
      # through Core::Sh for the guard to intercept the call.
      expect {
        SPMCache::SPM::Desc::Description.new(name: "Foo", pkg_dir: pkg_dir).fetch
      }.to raise_error(RuntimeError, /unexpected real invocation: Sh\.run\("swift package describe/)

      # Seam 2 -- BuildPipeline.resolve_scheme_fallback shells out via
      # Sh.capture_output ("xcodebuild -list"), deliberately NOT stubbed
      # directly: capture_output must route through the stubbed Sh.run for
      # the guard to intercept it, proving the second public entry point is
      # covered by the same default-deny guard.
      expect {
        SPMCache::SPM::BuildPipeline.send(:resolve_scheme_fallback, "Foo", pkg_dir)
      }.to raise_error(RuntimeError, /unexpected real invocation: Sh\.run\("xcodebuild -list/)
    end
  end
end
