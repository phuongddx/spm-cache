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
  let(:tmpdir) { Dir.mktmpdir }
  let(:pkg_dir) { File.join(tmpdir, "pkg") }
  let(:out_dir) { File.join(tmpdir, "out") }
  let(:resolved_pins_file) { File.join(tmpdir, "host-Package.resolved") }

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

  def write_resolved(path, identity, revision)
    File.write(path, JSON.generate("pins" => [{ "identity" => identity, "state" => { "revision" => revision } }]))
  end

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

  it "reports drift, resolution-incompatible status, and writes a provenance sidecar with exactly five keys" do
    fake_buildable = instance_double(SPMCache::SPM::Buildable)
    allow(SPMCache::SPM::Buildable).to receive(:new).and_return(fake_buildable)
    allow(fake_buildable).to receive(:build_for_destination) do |*_args, **_kwargs|
      # Simulates xcodebuild's silent re-resolution (STACK.md Experiment H3):
      # the seeded intended pin (aaa111) is discarded and re-resolved to
      # bbb222, rewriting pkg_dir/Package.resolved in place before the build
      # "returns" its artifacts.
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

    result = nil
    expect {
      result = described_class.run(
        name: "SomePkg",
        pkg_dir: pkg_dir,
        destinations: ["iphonesimulator"],
        out_dir: out_dir,
        resolved_pins_file: resolved_pins_file,
        config: "debug",
      )
    }.to output(/resolution-incompatible/).to_stdout.and output(/SomePkg.*aaa111.*bbb222/).to_stderr

    expect(result).to eq(File.join(out_dir, "SomePkg.xcframework"))

    sidecar_path = "#{result}.provenance.json"
    expect(File.exist?(sidecar_path)).to be true
    parsed = JSON.parse(File.read(sidecar_path))
    expect(parsed.keys.sort).to eq(%w[config destinations fidelity_status pins spm_cache_version])
    expect(parsed).to eq(
      "fidelity_status" => "resolution-incompatible",
      "pins" => { "SomePkg" => "bbb222" },
      "spm_cache_version" => SPMCache::VERSION,
      "config" => "debug",
      "destinations" => ["iphonesimulator"],
    )
  end

  it "reports host-pinned status with no drift warning when intended and realized pins agree" do
    fake_buildable = instance_double(SPMCache::SPM::Buildable)
    allow(SPMCache::SPM::Buildable).to receive(:new).and_return(fake_buildable)
    allow(fake_buildable).to receive(:build_for_destination).and_return(
      derived_data: "/dd", object_file: "/dd/SomePkg.o",
      swiftmodule: nil, swiftdoc: nil, swiftsourceinfo: nil, swiftinterface: nil,
    )
    allow(fake_buildable).to receive(:create_framework) do |_arts, subdir|
      fw = File.join(subdir, "SomePkg.framework")
      FileUtils.mkdir_p(fw)
      File.write(File.join(fw, "SomePkg"), "stub")
      fw
    end

    expect(SPMCache::Core::UI).not_to receive(:warn)

    result = described_class.run(
      name: "SomePkg",
      pkg_dir: pkg_dir,
      destinations: ["iphonesimulator"],
      out_dir: out_dir,
      resolved_pins_file: resolved_pins_file,
      config: "release",
    )

    parsed = JSON.parse(File.read("#{result}.provenance.json"))
    expect(parsed["fidelity_status"]).to eq("host-pinned")
    expect(parsed["pins"]).to eq("SomePkg" => "aaa111")
  end
end

RSpec.describe SPMCache::SPM::BuildPipeline, "not-graph-pinned paths never write a provenance sidecar, and clean up any stale one" do
  let(:tmpdir) { Dir.mktmpdir }
  let(:pkg_dir) { File.join(tmpdir, "pkg") }
  let(:out_dir) { File.join(tmpdir, "out") }
  let(:resolved_pins_file) { File.join(tmpdir, "host-Package.resolved") }

  def stub_desc_products(products, pkg_dir)
    fake_desc = instance_double(SPMCache::SPM::Desc::Description)
    allow(SPMCache::SPM::Desc::Description).to receive(:new).and_return(fake_desc)
    allow(fake_desc).to receive(:fetch)
    allow(fake_desc).to receive(:products).and_return(
      products.map { |p| SPMCache::SPM::Desc::Product.new(raw: p, pkg_dir: pkg_dir) },
    )
    allow(fake_desc).to receive(:raw).and_return({ "targets" => [] })
    fake_desc
  end

  before do
    FileUtils.mkdir_p(pkg_dir)
    FileUtils.mkdir_p(out_dir)
    File.write(resolved_pins_file,
               JSON.generate("pins" => [{ "identity" => "CryptoSwift", "state" => { "revision" => "aaa" } }]))

    fake_buildable = instance_double(SPMCache::SPM::Buildable)
    allow(SPMCache::SPM::Buildable).to receive(:new).and_return(fake_buildable)
    allow(fake_buildable).to receive(:build_for_destination).and_return(
      derived_data: "/dd", object_file: "/dd/CryptoSwift.o",
      swiftmodule: nil, swiftdoc: nil, swiftsourceinfo: nil, swiftinterface: nil,
    )
    allow(fake_buildable).to receive(:create_framework) do |_arts, subdir|
      fw = File.join(subdir, "CryptoSwift.framework")
      FileUtils.mkdir_p(fw)
      File.write(File.join(fw, "CryptoSwift"), "stub")
      fw
    end
    allow(SPMCache::SPM::XCFramework::XCFramework).to receive(:new).and_return(
      double("XCFramework", build: File.join(out_dir, "CryptoSwift.xcframework")),
    )
    stub_desc_products([{ "name" => "CryptoSwift", "type" => { "library" => ["automatic"] } }], pkg_dir)
  end

  after { FileUtils.rm_rf(tmpdir) }

  it "vendored .xcodeproj checkout: writes no sidecar and removes a pre-existing stale one" do
    FileUtils.mkdir_p(File.join(pkg_dir, "CryptoSwift.xcodeproj"))
    stale_sidecar = File.join(out_dir, "CryptoSwift.xcframework.provenance.json")
    File.write(stale_sidecar, '{"fidelity_status":"host-pinned"}')

    described_class.run(
      name: "CryptoSwift",
      pkg_dir: pkg_dir,
      destinations: ["iphonesimulator"],
      out_dir: out_dir,
      resolved_pins_file: resolved_pins_file,
      config: "debug",
    )

    expect(File.exist?(stale_sidecar)).to be false
  end

  it "nil resolved_pins_file (no host graph anywhere): writes no sidecar, prints no fidelity status line, removes a pre-existing stale one" do
    stale_sidecar = File.join(out_dir, "CryptoSwift.xcframework.provenance.json")
    File.write(stale_sidecar, '{"fidelity_status":"host-pinned"}')

    expect {
      described_class.run(
        name: "CryptoSwift",
        pkg_dir: pkg_dir,
        destinations: ["iphonesimulator"],
        out_dir: out_dir,
        resolved_pins_file: nil,
      )
    }.not_to output(/host-pinned|resolution-incompatible/).to_stdout

    expect(File.exist?(stale_sidecar)).to be false
  end
end

RSpec.describe SPMCache::SPM::BuildPipeline, "Class E (copy_prebuilt_binary_target) gets a provenance sidecar via the same consolidated insertion point" do
  let(:tmpdir) { Dir.mktmpdir }
  let(:out_dir) { File.join(tmpdir, "out") }
  let(:resolved_pins_file) { File.join(tmpdir, "host-Package.resolved") }

  def stub_desc_products(pkg_dir)
    fake_desc = instance_double(SPMCache::SPM::Desc::Description)
    allow(SPMCache::SPM::Desc::Description).to receive(:new).and_return(fake_desc)
    allow(fake_desc).to receive(:fetch)
    allow(fake_desc).to receive(:products).and_return(
      [SPMCache::SPM::Desc::Product.new(
        raw: { "name" => "FirebaseAnalytics", "type" => { "library" => ["automatic"] },
               "targets" => ["FirebaseAnalyticsTarget"] },
        pkg_dir: pkg_dir,
      )],
    )
    allow(fake_desc).to receive(:raw).and_return(
      "targets" => [
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
      ],
    )
  end

  after { FileUtils.rm_rf(tmpdir) }

  it "writes a host-pinned provenance sidecar for a Class E direct-copy build, with no special-casing" do
    File.write(resolved_pins_file,
               JSON.generate("pins" => [{ "identity" => "FirebaseAnalytics", "state" => { "revision" => "aaa" } }]))

    FileUtils.mkdir_p(out_dir)
    build_root = File.join(tmpdir, "umbrella", ".build")
    real_pkg_dir = File.join(build_root, "checkouts", "firebase-ios-sdk")
    FileUtils.mkdir_p(real_pkg_dir)
    prebuilt = File.join(build_root, "artifacts", "firebase-ios-sdk", "FirebaseAnalytics", "FirebaseAnalytics.xcframework")
    FileUtils.mkdir_p(File.join(prebuilt, "ios-arm64", "FirebaseAnalytics.framework", "Headers"))
    File.write(File.join(prebuilt, "ios-arm64", "FirebaseAnalytics.framework", "Headers", "FIRAnalytics.h"), "// real header\n")
    File.write(File.join(prebuilt, "Info.plist"), "<plist/>")

    stub_desc_products(real_pkg_dir)

    # A stale sidecar from a prior non-Class-E build must be removed by
    # copy_prebuilt_binary_target's own explicit rm_f, yet the fresh sidecar
    # written afterward by run's consolidated insertion point must still land
    # correctly -- both must coexist without either one blocking the other.
    stale_sidecar = File.join(out_dir, "FirebaseAnalytics.xcframework.provenance.json")
    File.write(stale_sidecar, '{"fidelity_status":"stale-marker"}')

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

    expect(result).to eq(File.join(out_dir, "FirebaseAnalytics.xcframework"))
    sidecar_path = "#{result}.provenance.json"
    expect(File.exist?(sidecar_path)).to be true
    parsed = JSON.parse(File.read(sidecar_path))
    expect(parsed["fidelity_status"]).to eq("host-pinned")
    expect(parsed["pins"]).to eq("FirebaseAnalytics" => "aaa")
  end
end

RSpec.describe SPMCache::Installer::Build, "threads config: from @config_name into every SPM::BuildPipeline.run call" do
  let(:tmpdir) { Dir.mktmpdir }
  let(:project_path) { File.join(tmpdir, "Fake.xcodeproj") }

  let(:cachemap) do
    SPMCache::Cache::Cachemap.new(
      graph_data: [
        { "module" => "Alamofire", "status" => "missed" },
      ],
    )
  end

  before do
    FileUtils.mkdir_p(project_path)
    allow_any_instance_of(SPMCache::Installer).to receive(:perform_install).and_wrap_original do |original, *_args|
      me = original.receiver
      me.instance_variable_set(:@cachemap, cachemap) if me.respond_to?(:cachemap)
      nil
    end
    allow_any_instance_of(SPMCache::Installer::Build).to receive(:resolve_umbrella_checkouts).and_return(nil)
    alamofire_dir = File.join(tmpdir, "checkouts", "Alamofire")
    FileUtils.mkdir_p(alamofire_dir)
    allow_any_instance_of(SPMCache::Installer::Build).to receive(:checkout_map).and_return(
      "Alamofire" => alamofire_dir,
    )
    allow(SPMCache::Core::Config.instance).to receive(:ignore_build_errors?).and_return(false)
    allow(SPMCache::Core::Config.instance).to receive(:default_sdk).and_return("iphonesimulator")
    allow(SPMCache::Core::Config.instance).to receive(:cache_dir).and_return(tmpdir)
    allow(SPMCache::Core::Config.instance).to receive(:umbrella_dir).and_return(File.join(tmpdir, "umbrella"))
  end

  after { FileUtils.rm_rf(tmpdir) }

  it "passes config: \"debug\" into SPM::BuildPipeline.run" do
    inst = described_class.new(project: project_path, config: "debug", targets: [])
    allow(SPMCache::SPM::ResolvedGraph).to receive(:source_for).and_return("/host/Package.resolved")
    allow(SPMCache::SPM::BuildPipeline).to receive(:run).and_return("/out/fake.xcframework")

    inst.perform_install

    expect(SPMCache::SPM::BuildPipeline).to have_received(:run).with(hash_including(config: "debug"))
  end
end
