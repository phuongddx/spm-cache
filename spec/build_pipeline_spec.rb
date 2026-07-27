# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "json"

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
    # Default: no targets at all, so #find_private_clang_shims's lookup
    # finds nothing and returns [] -- matches "no private Clang shim
    # dependency" (the common case for every package before this feature).
    # Tests exercising the shim-detection feature itself override this.
    allow(fake_desc).to receive(:raw).and_return({ "targets" => [] })
    fake_desc
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

  # Reproduces swift-numerics' RealModule -> _NumericsShims shape: a Swift
  # target privately depending on an internal Clang target that is never
  # declared as its own library product. See build_pipeline.rb's
  # #find_private_clang_shims for the full root-cause writeup (RealModule's
  # own `.swiftinterface` embeds `import _NumericsShims` as a real public
  # import, so a binary-cached consumer needs that module resolvable on its
  # own).
  it "builds a companion shim xcframework and writes a sidecar when a target has a private ClangTarget dependency" do
    shim_include_dir = File.join(pkg_dir, "Sources", "_NumericsShims", "include")
    FileUtils.mkdir_p(shim_include_dir)
    File.write(File.join(shim_include_dir, "_NumericsShims.h"), "// shim header\n")

    fake_desc = stub_desc_products([{ "name" => "RealModule", "type" => { "library" => ["automatic"] } }])
    allow(fake_desc).to receive(:raw).and_return(
      "targets" => [
        { "name" => "RealModule", "module_type" => "SwiftTarget", "target_dependencies" => ["_NumericsShims"] },
        { "name" => "_NumericsShims", "module_type" => "ClangTarget", "path" => "Sources/_NumericsShims" },
      ],
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
    allow(SPMCache::Core::Sh).to receive(:run)

    main_xc = double("MainXCFramework", build: File.join(out_dir, "RealModule.xcframework"))
    shim_xc = double("ShimXCFramework", build: File.join(out_dir, "_NumericsShims.xcframework"))
    allow(SPMCache::SPM::XCFramework::XCFramework).to receive(:new) do |name:, **_kwargs|
      name == "RealModule" ? main_xc : shim_xc
    end

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

  it "does not build any companion shim, or write a sidecar, for the common case of no private ClangTarget dependency" do
    described_class.run(
      name: "Alamofire",
      pkg_dir: pkg_dir,
      destinations: ["iphonesimulator"],
      out_dir: out_dir,
    )
    expect(File.exist?(File.join(out_dir, "Alamofire.xcframework.shims.json"))).to be false
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

  # Field bug: SVGKit's Package.swift declares an SPM product named exactly
  # "SVGKit", but its checkout carries multiple committed .xcodeproj files
  # (the library plus demo apps) whose real schemes are all prefixed
  # differently (e.g. SVGKit-iOS) -- no scheme named "SVGKit" exists at
  # all. resolve_scheme's exact-match-on-product-name always won before,
  # producing a scheme xcodebuild would reject. Verify it now checks real
  # schemes scraped from every candidate .xcodeproj (bypassing plain
  # `xcodebuild -list`'s ambiguity failure) and substitutes the closest
  # real match instead, only when the checkout is ambiguous (2+ .xcodeproj).
  it "resolves scheme against real .xcodeproj schemes when the product name doesn't match any of them" do
    stub_desc_products([{ "name" => "SVGKit", "type" => { "library" => ["automatic"] } }])
    FileUtils.mkdir_p(File.join(pkg_dir, "SVGKit-iOS.xcodeproj"))
    FileUtils.mkdir_p(File.join(pkg_dir, "Demo-iOS.xcodeproj"))
    allow(SPMCache::Core::Sh).to receive(:capture_output).and_return(
      "Schemes:\nSVGKit-iOS\nSVGKitFramework-iOS",
    )

    expect(SPMCache::SPM::Buildable).to receive(:new)
      .with(hash_including(scheme: "SVGKit-iOS"))
      .and_return(instance_double(SPMCache::SPM::Buildable).tap do |fb|
        allow(fb).to receive(:build_for_destination).and_return(object_file: "/dd/SVGKit-iOS.o")
        allow(fb).to receive(:create_framework) do |_arts, subdir|
          fw = File.join(subdir, "SVGKit.framework")
          FileUtils.mkdir_p(fw)
          File.write(File.join(fw, "SVGKit"), "stub")
          fw
        end
      end)

    described_class.run(
      name: "SVGKit",
      pkg_dir: pkg_dir,
      destinations: ["iphonesimulator"],
      out_dir: out_dir,
    )
  end

  it "leaves the product-name scheme untouched when the checkout has 0 or 1 .xcodeproj (common case)" do
    stub_desc_products([{ "name" => "Alamofire", "type" => { "library" => ["automatic"] } }])
    # no .xcodeproj created under pkg_dir at all

    expect(SPMCache::SPM::Buildable).to receive(:new)
      .with(hash_including(scheme: "Alamofire"))
      .and_return(instance_double(SPMCache::SPM::Buildable).tap do |fb|
        allow(fb).to receive(:build_for_destination).and_return(object_file: "/dd/Alamofire.o")
        allow(fb).to receive(:create_framework) do |_arts, subdir|
          fw = File.join(subdir, "Alamofire.framework")
          FileUtils.mkdir_p(fw)
          File.write(File.join(fw, "Alamofire"), "stub")
          fw
        end
      end)

    described_class.run(
      name: "Alamofire",
      pkg_dir: pkg_dir,
      destinations: ["iphonesimulator"],
      out_dir: out_dir,
    )
  end

  # Field regression: OrderedCollections' .swiftinterface declares
  # `import InternalCollectionsUtilities` -- a Swift target that is not a
  # declared product and was never cached, so consumers hit "Unable to find
  # module dependency". Public-surface scanning must read .swiftinterface
  # files, not just ObjC headers.
  it "detects a companion named only by a .swiftinterface import" do
    products = File.join(tmpdir, "dd", "Build", "Products", "Debug-iphonesimulator")
    interface_dir = File.join(products, "OrderedCollections.framework", "Modules", "OrderedCollections.swiftmodule")
    FileUtils.mkdir_p(interface_dir)
    File.write(
      File.join(interface_dir, "arm64-apple-ios-simulator.swiftinterface"),
      "// swift-interface-format-version: 1.0\nimport InternalCollectionsUtilities\nimport Swift\n",
    )
    FileUtils.mkdir_p(File.join(products, "InternalCollectionsUtilities.framework"))

    companions = described_class.send(
      :find_framework_companions,
      { derived_data: File.join(tmpdir, "dd") },
      "OrderedCollections",
      out_dir,
    )

    expect(companions.keys).to eq(["InternalCollectionsUtilities"])
  end

  it "ignores a .swiftinterface import that is already independently cached" do
    products = File.join(tmpdir, "dd2", "Build", "Products", "Debug-iphonesimulator")
    interface_dir = File.join(products, "OrderedCollections.framework", "Modules", "OrderedCollections.swiftmodule")
    FileUtils.mkdir_p(interface_dir)
    File.write(
      File.join(interface_dir, "arm64-apple-ios-simulator.swiftinterface"),
      "import InternalCollectionsUtilities\n",
    )
    FileUtils.mkdir_p(File.join(products, "InternalCollectionsUtilities.framework"))
    FileUtils.mkdir_p(File.join(out_dir, "InternalCollectionsUtilities.xcframework"))

    companions = described_class.send(
      :find_framework_companions,
      { derived_data: File.join(tmpdir, "dd2") },
      "OrderedCollections",
      out_dir,
    )

    expect(companions).to be_empty
  end
end
