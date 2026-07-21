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

  # Field bug: firebase-ios-sdk declares product `FirebaseAnalyticsWithoutAdIdSupport`
  # backed by a single target named `FirebaseAnalyticsWithoutAdIdSupportTarget`
  # (confirmed via `swift package describe`; same `<Product>Target` shape for
  # `FirebaseAnalytics` and `FirebaseAnalyticsOnDeviceConversion`). Xcode links
  # the object file under the TARGET's name, so passing the product name as
  # `module_name` makes `find_object_file`'s exact-name glob find nothing --
  # the build silently "fails" (0 slices) even though xcodebuild succeeded.
  it "resolves module_name to the product's own target name when it differs from the product name" do
    stub_desc_products(
      [
        { "name" => "FirebaseAnalyticsWithoutAdIdSupport", "type" => { "library" => ["automatic"] },
          "targets" => ["FirebaseAnalyticsWithoutAdIdSupportTarget"] },
      ],
    )

    expect(SPMCache::SPM::Buildable).to receive(:new)
      .with(hash_including(scheme: "FirebaseAnalyticsWithoutAdIdSupport",
                            module_name: "FirebaseAnalyticsWithoutAdIdSupportTarget"))
      .and_return(instance_double(SPMCache::SPM::Buildable).tap do |fb|
        allow(fb).to receive(:build_for_destination).and_return(
          object_file: "/dd/FirebaseAnalyticsWithoutAdIdSupportTarget.o",
        )
        allow(fb).to receive(:create_framework) do |_arts, subdir|
          fw = File.join(subdir, "FirebaseAnalyticsWithoutAdIdSupport.framework")
          FileUtils.mkdir_p(fw)
          File.write(File.join(fw, "FirebaseAnalyticsWithoutAdIdSupport"), "stub")
          fw
        end
      end)

    described_class.run(
      name: "FirebaseAnalyticsWithoutAdIdSupport",
      pkg_dir: pkg_dir,
      destinations: ["iphonesimulator"],
      out_dir: out_dir,
    )
  end

  it "keeps module_name equal to the product name when the target list matches or is absent (common case)" do
    stub_desc_products(
      [{ "name" => "FirebaseCore", "type" => { "library" => ["automatic"] }, "targets" => ["FirebaseCore"] }],
    )

    expect(SPMCache::SPM::Buildable).to receive(:new)
      .with(hash_including(scheme: "FirebaseCore", module_name: "FirebaseCore"))
      .and_return(instance_double(SPMCache::SPM::Buildable).tap do |fb|
        allow(fb).to receive(:build_for_destination).and_return(object_file: "/dd/FirebaseCore.o")
        allow(fb).to receive(:create_framework) do |_arts, subdir|
          fw = File.join(subdir, "FirebaseCore.framework")
          FileUtils.mkdir_p(fw)
          File.write(File.join(fw, "FirebaseCore"), "stub")
          fw
        end
      end)

    described_class.run(
      name: "FirebaseCore",
      pkg_dir: pkg_dir,
      destinations: ["iphonesimulator"],
      out_dir: out_dir,
    )
  end

  # Field bug: CryptoSwift's checkout carries its own committed .xcodeproj
  # (Xcode "Framework" target type) -- xcodebuild links a genuine
  # CryptoSwift.framework directly, no raw .o exists anywhere. When
  # build_for_destination returns a `framework:` artifact instead of
  # `object_file:`, the pipeline must dispatch to
  # Buildable#use_existing_framework instead of #create_framework (which
  # would find nothing to assemble from).
  it "uses use_existing_framework instead of create_framework when the artifacts carry a pre-built framework" do
    stub_desc_products([{ "name" => "CryptoSwift", "type" => { "library" => ["automatic"] } }])

    expect(SPMCache::SPM::Buildable).to receive(:new)
      .with(hash_including(scheme: "CryptoSwift", module_name: "CryptoSwift"))
      .and_return(instance_double(SPMCache::SPM::Buildable).tap do |fb|
        allow(fb).to receive(:build_for_destination).and_return(
          object_file: nil,
          framework: "/dd/Build/Products/Debug-iphonesimulator/CryptoSwift.framework",
        )
        expect(fb).not_to receive(:create_framework)
        expect(fb).to receive(:use_existing_framework) do |_arts, subdir|
          fw = File.join(subdir, "CryptoSwift.framework")
          FileUtils.mkdir_p(fw)
          File.write(File.join(fw, "CryptoSwift"), "stub")
          fw
        end
      end)

    described_class.run(
      name: "CryptoSwift",
      pkg_dir: pkg_dir,
      destinations: ["iphonesimulator"],
      out_dir: out_dir,
    )
  end
end
