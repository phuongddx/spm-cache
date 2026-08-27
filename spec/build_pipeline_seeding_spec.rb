# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "json"

# Unit-tests the Phase 7 host-graph seeding mechanism: BuildPipeline.run's
# resolved_pins_file: kwarg, and Installer::Build's single per-run source_for
# resolution threaded into every BuildPipeline.run call. Real xcodebuild is
# never invoked; Buildable/Desc::Description/XCFramework are stubbed exactly
# as in spec/build_pipeline_spec.rb.
RSpec.describe SPMCache::SPM::BuildPipeline, "host graph seeding" do
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

  before do
    FileUtils.mkdir_p(pkg_dir)
    FileUtils.mkdir_p(out_dir)
    File.write(resolved_pins_file, '{"pins": [{"identity": "below-manifest-floor"}]}')

    fake_buildable = instance_double(SPMCache::SPM::Buildable)
    allow(SPMCache::SPM::Buildable).to receive(:new).and_return(fake_buildable)
    artifacts = {
      derived_data: "/dd",
      object_file: "/dd/Alamofire.o",
      swiftmodule: nil, swiftdoc: nil, swiftsourceinfo: nil, swiftinterface: nil,
    }
    allow(fake_buildable).to receive(:build_for_destination).and_return(artifacts)
    allow(fake_buildable).to receive(:create_framework) do |_arts, subdir|
      fw = File.join(subdir, "Alamofire.framework")
      FileUtils.mkdir_p(fw)
      File.write(File.join(fw, "Alamofire"), "stub")
      fw
    end
    allow(SPMCache::SPM::XCFramework::XCFramework).to receive(:new).and_return(
      double("XCFramework", build: File.join(out_dir, "Alamofire.xcframework")),
    )
    stub_desc_products([{ "name" => "Alamofire", "type" => { "library" => ["automatic"] } }])
  end

  after { FileUtils.rm_rf(tmpdir) }

  it "seeds pkg_dir/Package.resolved strictly before the first Desc::Description.new construction" do
    seeded_before_construction = nil
    allow(SPMCache::SPM::Desc::Description).to receive(:new) do |**_kwargs|
      seeded_before_construction = File.exist?(File.join(pkg_dir, "Package.resolved")) if seeded_before_construction.nil?
      fake_desc = instance_double(SPMCache::SPM::Desc::Description)
      allow(fake_desc).to receive(:fetch)
      allow(fake_desc).to receive(:products).and_return(
        [SPMCache::SPM::Desc::Product.new(raw: { "name" => "Alamofire", "type" => { "library" => ["automatic"] } }, pkg_dir: pkg_dir)],
      )
      allow(fake_desc).to receive(:raw).and_return({ "targets" => [] })
      fake_desc
    end

    described_class.run(
      name: "Alamofire",
      pkg_dir: pkg_dir,
      destinations: ["iphonesimulator"],
      out_dir: out_dir,
      resolved_pins_file: resolved_pins_file,
    )

    expect(seeded_before_construction).to be true
  end

  it "leaves the seeded file in place, byte-identical to the source, after a successful run" do
    described_class.run(
      name: "Alamofire",
      pkg_dir: pkg_dir,
      destinations: ["iphonesimulator"],
      out_dir: out_dir,
      resolved_pins_file: resolved_pins_file,
    )

    seeded_path = File.join(pkg_dir, "Package.resolved")
    expect(File.exist?(seeded_path)).to be true
    expect(File.read(seeded_path)).to eq(File.read(resolved_pins_file))
  end

  it "restores the pre-seed state (removing the seeded file) when a mid-build StandardError is raised" do
    fake_buildable = instance_double(SPMCache::SPM::Buildable)
    allow(SPMCache::SPM::Buildable).to receive(:new).and_return(fake_buildable)
    allow(fake_buildable).to receive(:build_for_destination).and_raise(StandardError, "boom")

    expect {
      described_class.run(
        name: "Alamofire",
        pkg_dir: pkg_dir,
        destinations: ["iphonesimulator"],
        out_dir: out_dir,
        resolved_pins_file: resolved_pins_file,
      )
    }.to raise_error(/No slices were built successfully/)

    expect(File.exist?(File.join(pkg_dir, "Package.resolved"))).to be false
  end

  it "restores the prior content (not just removal) when pkg_dir already had a Package.resolved before the run" do
    destination = File.join(pkg_dir, "Package.resolved")
    File.write(destination, '{"pins": ["prior-content"]}')

    fake_buildable = instance_double(SPMCache::SPM::Buildable)
    allow(SPMCache::SPM::Buildable).to receive(:new).and_return(fake_buildable)
    allow(fake_buildable).to receive(:build_for_destination).and_raise(StandardError, "boom")

    expect {
      described_class.run(
        name: "Alamofire",
        pkg_dir: pkg_dir,
        destinations: ["iphonesimulator"],
        out_dir: out_dir,
        resolved_pins_file: resolved_pins_file,
      )
    }.to raise_error(/No slices were built successfully/)

    expect(File.read(destination)).to eq('{"pins": ["prior-content"]}')
  end

  it "restores the pre-seed state when the build is interrupted (Interrupt, not just StandardError)" do
    fake_buildable = instance_double(SPMCache::SPM::Buildable)
    allow(SPMCache::SPM::Buildable).to receive(:new).and_return(fake_buildable)
    allow(fake_buildable).to receive(:build_for_destination).and_raise(Interrupt)

    expect {
      described_class.run(
        name: "Alamofire",
        pkg_dir: pkg_dir,
        destinations: ["iphonesimulator"],
        out_dir: out_dir,
        resolved_pins_file: resolved_pins_file,
      )
    }.to raise_error(Interrupt)

    expect(File.exist?(File.join(pkg_dir, "Package.resolved"))).to be false
  end

  it "never calls ResolvedGraph.seed! or .restore! when resolved_pins_file is nil (positive control)" do
    expect(SPMCache::SPM::ResolvedGraph).not_to receive(:seed!)
    expect(SPMCache::SPM::ResolvedGraph).not_to receive(:restore!)

    described_class.run(
      name: "Alamofire",
      pkg_dir: pkg_dir,
      destinations: ["iphonesimulator"],
      out_dir: out_dir,
      resolved_pins_file: nil,
    )
  end
end

RSpec.describe SPMCache::SPM::BuildPipeline, "vendored .xcodeproj classification" do
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
    File.write(resolved_pins_file, '{"pins": [{"identity": "below-manifest-floor"}]}')

    fake_buildable = instance_double(SPMCache::SPM::Buildable)
    allow(SPMCache::SPM::Buildable).to receive(:new).and_return(fake_buildable)
    artifacts = {
      derived_data: "/dd",
      object_file: "/dd/CryptoSwift.o",
      swiftmodule: nil, swiftdoc: nil, swiftsourceinfo: nil, swiftinterface: nil,
    }
    allow(fake_buildable).to receive(:build_for_destination).and_return(artifacts)
    allow(fake_buildable).to receive(:create_framework) do |_arts, subdir|
      fw = File.join(subdir, "CryptoSwift.framework")
      FileUtils.mkdir_p(fw)
      File.write(File.join(fw, "CryptoSwift"), "stub")
      fw
    end
    allow(SPMCache::SPM::XCFramework::XCFramework).to receive(:new).and_return(
      double("XCFramework", build: File.join(out_dir, "CryptoSwift.xcframework")),
    )
  end

  after { FileUtils.rm_rf(tmpdir) }

  it "never writes pkg_dir/Package.resolved for a vendored .xcodeproj checkout, even when a source is available" do
    FileUtils.mkdir_p(File.join(pkg_dir, "CryptoSwift.xcodeproj"))
    stub_desc_products([{ "name" => "CryptoSwift", "type" => { "library" => ["automatic"] } }], pkg_dir)

    described_class.run(
      name: "CryptoSwift",
      pkg_dir: pkg_dir,
      destinations: ["iphonesimulator"],
      out_dir: out_dir,
      resolved_pins_file: resolved_pins_file,
    )

    expect(File.exist?(File.join(pkg_dir, "Package.resolved"))).to be false
  end

  it "emits a UI line naming the package and reporting it as not graph-pinned" do
    FileUtils.mkdir_p(File.join(pkg_dir, "CryptoSwift.xcodeproj"))
    stub_desc_products([{ "name" => "CryptoSwift", "type" => { "library" => ["automatic"] } }], pkg_dir)

    expect {
      described_class.run(
        name: "CryptoSwift",
        pkg_dir: pkg_dir,
        destinations: ["iphonesimulator"],
        out_dir: out_dir,
        resolved_pins_file: resolved_pins_file,
      )
    }.to output(/CryptoSwift.*not graph-pinned/).to_stdout
  end

  it "still seeds a non-vendored checkout in the same run (regression guard for Task 1's behavior)" do
    stub_desc_products([{ "name" => "CryptoSwift", "type" => { "library" => ["automatic"] } }], pkg_dir)

    described_class.run(
      name: "CryptoSwift",
      pkg_dir: pkg_dir,
      destinations: ["iphonesimulator"],
      out_dir: out_dir,
      resolved_pins_file: resolved_pins_file,
    )

    expect(File.exist?(File.join(pkg_dir, "Package.resolved"))).to be true
  end
end

RSpec.describe SPMCache::Installer::Build, "threading the run's single host-graph pin source" do
  let(:tmpdir) { Dir.mktmpdir }
  let(:project_path) { File.join(tmpdir, "Fake.xcodeproj") }

  let(:cachemap) do
    SPMCache::Cache::Cachemap.new(
      graph_data: [
        { "module" => "Alamofire", "status" => "missed" },
        { "module" => "SnapKit", "status" => "missed" },
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
    snapkit_dir = File.join(tmpdir, "checkouts", "SnapKit")
    FileUtils.mkdir_p(alamofire_dir)
    FileUtils.mkdir_p(snapkit_dir)
    allow_any_instance_of(SPMCache::Installer::Build).to receive(:checkout_map).and_return(
      "Alamofire" => alamofire_dir, "SnapKit" => snapkit_dir,
    )
    allow(SPMCache::Core::Config.instance).to receive(:ignore_build_errors?).and_return(false)
    allow(SPMCache::Core::Config.instance).to receive(:default_sdk).and_return("iphonesimulator")
    allow(SPMCache::Core::Config.instance).to receive(:cache_dir).and_return(tmpdir)
    allow(SPMCache::Core::Config.instance).to receive(:umbrella_dir).and_return(File.join(tmpdir, "umbrella"))
  end

  after { FileUtils.rm_rf(tmpdir) }

  it "calls SPM::ResolvedGraph.source_for exactly once per run and threads the same result into every BuildPipeline.run call" do
    inst = described_class.new(project: project_path, targets: [])
    allow(SPMCache::SPM::ResolvedGraph).to receive(:source_for).and_return("/host/Package.resolved")
    allow(SPMCache::SPM::BuildPipeline).to receive(:run).and_return("/out/fake.xcframework")

    inst.perform_install

    expect(SPMCache::SPM::ResolvedGraph).to have_received(:source_for).once
    expect(SPMCache::SPM::BuildPipeline).to have_received(:run)
      .with(hash_including(resolved_pins_file: "/host/Package.resolved")).twice
  end
end
