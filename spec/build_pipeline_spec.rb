# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

# Unit-tests SPM::BuildPipeline argument assembly with stubbed Buildable and
# XCFramework layers. No real xcodebuild is invoked. Correctness beyond
# argument assembly is only covered by the manual end-to-end check in
# phase 4 of the plan.
RSpec.describe SPMCache::SPM::BuildPipeline do
  let(:tmpdir) { Dir.mktmpdir }
  let(:pkg_dir) { File.join(tmpdir, "pkg") }
  let(:out_dir) { File.join(tmpdir, "out") }

  # Builds a stubbed Desc::Description double that returns the given raw
  # product hashes from #products (and a no-op #fetch), without shelling out
  # to `swift package describe`.
  def stub_desc_products(products)
    fake_desc = instance_double(SPMCache::SPM::Desc::Description)
    allow(SPMCache::SPM::Desc::Description).to receive(:new).and_return(fake_desc)
    allow(fake_desc).to receive(:fetch)
    allow(fake_desc).to receive(:products).and_return(
      products.map { |p| SPMCache::SPM::Desc::Product.new(raw: p, pkg_dir: pkg_dir) },
    )
  end

  before do
    FileUtils.mkdir_p(pkg_dir)
    FileUtils.mkdir_p(out_dir)
    # Stub Buildable so no xcodebuild runs.
    fake_buildable = instance_double(SPMCache::SPM::Buildable)
    allow(SPMCache::SPM::Buildable).to receive(:new).and_return(fake_buildable)
    artifacts = {
      derived_data: "/dd",
      object_file: "/dd/Alamofire.o",
      swiftmodule: "/dd/Alamofire.swiftmodule",
      swiftdoc: nil,
      swiftsourceinfo: nil,
      swiftinterface: nil,
    }
    allow(fake_buildable).to receive(:build_for_destination).and_return(artifacts)
    allow(fake_buildable).to receive(:create_framework) do |_arts, subdir|
      fw = File.join(subdir, "Alamofire.framework")
      FileUtils.mkdir_p(fw)
      File.write(File.join(fw, "Alamofire"), "stub")
      fw
    end
    # Stub XCFramework so no xcodebuild -create-xcframework runs.
    allow(SPMCache::SPM::XCFramework::XCFramework).to receive(:new).and_return(
      double("XCFramework", build: File.join(out_dir, "Alamofire.xcframework")),
    )
    # Stub `swift package describe` scheme resolution so no real shell-out
    # happens by default; individual examples override this as needed.
    stub_desc_products([{ "name" => "Alamofire", "type" => { "library" => ["automatic"] } }])
  end

  after { FileUtils.rm_rf(tmpdir) }

  it "builds and returns the xcframework path" do
    result = described_class.run(
      name: "Alamofire",
      pkg_dir: pkg_dir,
      destinations: ["iphonesimulator"],
      out_dir: out_dir,
    )
    expect(result).to eq(File.join(out_dir, "Alamofire.xcframework"))
  end

  it "raises when name is empty" do
    expect {
      described_class.run(name: "", pkg_dir: pkg_dir, destinations: [], out_dir: out_dir)
    }.to raise_error(/Target name required/)
  end

  it "raises when no slices are built" do
    fake_buildable = instance_double(SPMCache::SPM::Buildable)
    allow(SPMCache::SPM::Buildable).to receive(:new).and_return(fake_buildable)
    allow(fake_buildable).to receive(:build_for_destination).and_return(object_file: nil)
    allow(fake_buildable).to receive(:create_framework)
    # `swift package describe` yields nothing usable for this package.
    stub_desc_products([])
    # Scheme fallback also fails
    allow(SPMCache::Core::Sh).to receive(:capture_output).and_return("")
    expect {
      described_class.run(name: "Ghost", pkg_dir: pkg_dir, destinations: ["iphonesimulator"], out_dir: out_dir)
    }.to raise_error(/No slices were built successfully/)
  end

  it "resolves the scheme to the exact case-insensitive library product match" do
    stub_desc_products(
      [
        { "name" => "Alamofire", "type" => { "library" => ["automatic"] } },
        { "name" => "Alamofire iOS", "type" => { "library" => ["automatic"] } },
        { "name" => "AlamofireTests", "type" => { "executable" => nil } },
      ],
    )

    expect(SPMCache::SPM::Buildable).to receive(:new)
      .with(hash_including(scheme: "Alamofire"))
      .and_return(instance_double(SPMCache::SPM::Buildable).tap do |fb|
        allow(fb).to receive(:build_for_destination).and_return(
          object_file: "/dd/Alamofire.o",
        )
        allow(fb).to receive(:create_framework) do |_arts, subdir|
          fw = File.join(subdir, "Alamofire.framework")
          FileUtils.mkdir_p(fw)
          File.write(File.join(fw, "Alamofire"), "stub")
          fw
        end
      end)

    described_class.run(
      name: "alamofire",
      pkg_dir: pkg_dir,
      destinations: ["iphonesimulator"],
      out_dir: out_dir,
    )
  end

  it "excludes executable-type products and picks the library scheme" do
    stub_desc_products(
      [
        { "name" => "SwiftProtobuf", "type" => { "library" => ["automatic"] } },
        { "name" => "Conformance", "type" => { "executable" => nil } },
      ],
    )

    expect(SPMCache::SPM::Buildable).to receive(:new)
      .with(hash_including(scheme: "SwiftProtobuf"))
      .and_return(instance_double(SPMCache::SPM::Buildable).tap do |fb|
        allow(fb).to receive(:build_for_destination).and_return(
          object_file: "/dd/SwiftProtobuf.o",
        )
        allow(fb).to receive(:create_framework) do |_arts, subdir|
          fw = File.join(subdir, "SwiftProtobuf.framework")
          FileUtils.mkdir_p(fw)
          File.write(File.join(fw, "SwiftProtobuf"), "stub")
          fw
        end
      end)

    described_class.run(
      name: "swift-protobuf",
      pkg_dir: pkg_dir,
      destinations: ["iphonesimulator"],
      out_dir: out_dir,
    )
  end
end
