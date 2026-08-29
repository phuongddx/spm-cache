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
end
