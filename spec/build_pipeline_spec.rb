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
          # Matches real Buildable#create_framework: the framework and its
          # binary are always named after @module_name (the target name
          # here), not the product name -- rename_framework_to_product is
          # what fixes that up afterward.
          fw = File.join(subdir, "FirebaseAnalyticsWithoutAdIdSupportTarget.framework")
          FileUtils.mkdir_p(fw)
          File.write(File.join(fw, "FirebaseAnalyticsWithoutAdIdSupportTarget"), "stub")
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

  # Field bug (Class D sibling-skip): the guard against re-adding an
  # already-cached companion used to skip it from the returned hash
  # entirely -- avoiding a wasteful rebuild, but ALSO preventing the
  # companion from being wired into a LATER sibling product's own
  # `.library` target list, even though the companion binary is genuinely
  # correct and cached. Confirmed live: InternalCollectionsUtilities.xcframework
  # existed and was correct, but BitCollections/DequeModule/HashTreeCollections/
  # HeapModule/Collections (all of which reference it via their own
  # .swiftinterface) never got it wired into their own
  # .xcframework.shims.json sidecar. The companion must still be recorded
  # for THIS product's own sidecar -- flagged as :cached so the caller
  # (write_shim_sidecar) knows not to rebuild it.
  it "still records an already-cached companion for this product's own sidecar, without rebuilding it" do
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

    expect(companions).to eq("InternalCollectionsUtilities" => :cached)
  end

  # Field bug, discovered while re-verifying the Class D sibling-skip fix above
  # against the real swift-collections package: an umbrella product like
  # Collections re-exports its sibling products with `@_exported import X`
  # rather than a plain `import X` (confirmed against the real compiled
  # arm64-apple-ios-simulator.swiftinterface: "@_exported import
  # BitCollections", "@_exported import DequeModule", etc.) -- the anchored
  # regex (`^\s*import\s+...`) only matches a line that starts with "import",
  # so it never recognizes these lines as referencing a companion at all.
  # Distinct from the sibling-skip bug (this is a detection gap, not a
  # rebuild-vs-record gap), but blocks the same "Class D" companion family:
  # Collections never gets BitCollections/DequeModule/etc. wired into its own
  # sidecar because they're never even detected as referenced.
  it "detects a companion referenced via '@_exported import' (umbrella re-export), not just a plain import" do
    products = File.join(tmpdir, "dd5", "Build", "Products", "Debug-iphonesimulator")
    interface_dir = File.join(products, "Collections.swiftmodule")
    FileUtils.mkdir_p(interface_dir)
    File.write(
      File.join(interface_dir, "arm64-apple-ios-simulator.swiftinterface"),
      "@_exported import BitCollections\n@_exported import OrderedCollections\nimport Swift\n",
    )
    File.write(File.join(products, "Collections.o"), "fake object file")
    FileUtils.mkdir_p(File.join(out_dir, "BitCollections.xcframework"))
    FileUtils.mkdir_p(File.join(out_dir, "OrderedCollections.xcframework"))

    companions = described_class.send(
      :find_framework_companions,
      { derived_data: File.join(tmpdir, "dd5") },
      "Collections",
      out_dir,
    )

    expect(companions).to eq("BitCollections" => :cached, "OrderedCollections" => :cached)
  end

  # Field bug: SPM pure-Swift library builds produce bare .swiftmodule dirs
  # alongside .o files, not wrapped in .framework bundles. The main module's
  # .swiftinterface names a companion via `import InternalCollectionsUtilities`,
  # but no .framework exists yet — we must synthesize one.
  it "synthesizes a companion framework from a bare .swiftmodule for a referenced import" do
    products = File.join(tmpdir, "dd3", "Build", "Products", "Debug-iphonesimulator")
    # Main module: bare (no framework wrapper)
    main_interface_dir = File.join(products, "OrderedCollections.swiftmodule")
    FileUtils.mkdir_p(main_interface_dir)
    File.write(
      File.join(main_interface_dir, "arm64-apple-ios-simulator.swiftinterface"),
      "import InternalCollectionsUtilities\nimport Swift\n",
    )
    File.write(File.join(products, "OrderedCollections.o"), "fake object file")

    # Companion module: also bare (no framework wrapper yet)
    companion_interface_dir = File.join(products, "InternalCollectionsUtilities.swiftmodule")
    FileUtils.mkdir_p(companion_interface_dir)
    File.write(
      File.join(companion_interface_dir, "arm64-apple-ios-simulator.swiftinterface"),
      "import Swift\n",
    )
    File.write(File.join(products, "InternalCollectionsUtilities.o"), "fake companion object")

    fake_buildable = instance_double(SPMCache::SPM::Buildable)
    allow(SPMCache::SPM::Buildable).to receive(:new).and_return(fake_buildable)
    allow(fake_buildable).to receive(:find_object_file).and_return(File.join(products, "InternalCollectionsUtilities.o"))
    allow(fake_buildable).to receive(:find_object_files).and_return([File.join(products, "InternalCollectionsUtilities.o")])
    allow(fake_buildable).to receive(:find_file) do |_dd, basename|
      file = File.join(products, basename)
      File.exist?(file) ? file : nil
    end
    allow(fake_buildable).to receive(:create_framework) do |_arts, subdir|
      fw = File.join(subdir, "InternalCollectionsUtilities.framework")
      FileUtils.mkdir_p(fw)
      fw
    end

    companions = described_class.send(
      :find_framework_companions,
      { derived_data: File.join(tmpdir, "dd3") },
      "OrderedCollections",
      out_dir,
    )

    expect(companions.keys).to eq(["InternalCollectionsUtilities"])
  end

  # Regression test: multi-destination builds must not collide. Each destination
  # gets its own fw_subdir to avoid the second destination overwriting the first
  # destination's synthesized companion framework in the same tmpdir.
  it "produces distinct companion framework paths for different destination subdirs" do
    products = File.join(tmpdir, "dd4", "Build", "Products", "Debug-iphonesimulator")
    # Main module: bare
    main_interface_dir = File.join(products, "OrderedCollections.swiftmodule")
    FileUtils.mkdir_p(main_interface_dir)
    File.write(
      File.join(main_interface_dir, "arm64-apple-ios-simulator.swiftinterface"),
      "import InternalCollectionsUtilities\nimport Swift\n",
    )
    File.write(File.join(products, "OrderedCollections.o"), "fake object file")

    # Companion module: bare
    companion_interface_dir = File.join(products, "InternalCollectionsUtilities.swiftmodule")
    FileUtils.mkdir_p(companion_interface_dir)
    File.write(
      File.join(companion_interface_dir, "arm64-apple-ios-simulator.swiftinterface"),
      "import Swift\n",
    )
    File.write(File.join(products, "InternalCollectionsUtilities.o"), "fake companion object")

    fake_buildable = instance_double(SPMCache::SPM::Buildable)
    allow(SPMCache::SPM::Buildable).to receive(:new).and_return(fake_buildable)
    allow(fake_buildable).to receive(:find_object_file).and_return(File.join(products, "InternalCollectionsUtilities.o"))
    allow(fake_buildable).to receive(:find_object_files).and_return([File.join(products, "InternalCollectionsUtilities.o")])
    allow(fake_buildable).to receive(:find_file) do |_dd, basename|
      file = File.join(products, basename)
      File.exist?(file) ? file : nil
    end
    allow(fake_buildable).to receive(:create_framework) do |_arts, subdir|
      fw = File.join(subdir, "InternalCollectionsUtilities.framework")
      FileUtils.mkdir_p(fw)
      fw
    end

    # Simulate two destinations calling find_framework_companions with different fw_subdirs
    fw_subdir_ios_sim = File.join(tmpdir, "ios-sim-subdir")
    fw_subdir_ios_dev = File.join(tmpdir, "ios-dev-subdir")
    FileUtils.mkdir_p(fw_subdir_ios_sim)
    FileUtils.mkdir_p(fw_subdir_ios_dev)

    # First destination (iphonesimulator)
    companions_sim = described_class.send(
      :find_framework_companions,
      { derived_data: File.join(tmpdir, "dd4") },
      "OrderedCollections",
      out_dir,
      fw_subdir: fw_subdir_ios_sim,
      pkg_dir: tmpdir,
    )

    # Second destination (iphoneos) — should write to a different subdir, not collide
    companions_dev = described_class.send(
      :find_framework_companions,
      { derived_data: File.join(tmpdir, "dd4") },
      "OrderedCollections",
      out_dir,
      fw_subdir: fw_subdir_ios_dev,
      pkg_dir: tmpdir,
    )

    # Both should have found the companion
    expect(companions_sim.keys).to eq(["InternalCollectionsUtilities"])
    expect(companions_dev.keys).to eq(["InternalCollectionsUtilities"])

    # The frameworks should be in different directories (no collision)
    sim_fw_path = companions_sim["InternalCollectionsUtilities"]
    dev_fw_path = companions_dev["InternalCollectionsUtilities"]
    expect(sim_fw_path).not_to eq(dev_fw_path)

    # Both framework paths should still exist (not overwritten by each other)
    expect(File.directory?(sim_fw_path)).to be true
    expect(File.directory?(dev_fw_path)).to be true

    # Verify they're in their respective subdirs
    expect(sim_fw_path).to include("ios-sim-subdir")
    expect(dev_fw_path).to include("ios-dev-subdir")
  end

  # Field regression: FirebaseAnalytics.xcframework contained
  # FirebaseAnalyticsTarget.framework, because Xcode stamps artifacts with
  # the TARGET name while consumers import the PRODUCT name.
  it "renames framework, binary, and module dir from target name to product name" do
    staging = File.join(tmpdir, "staging")
    fw = File.join(staging, "FirebaseAnalyticsTarget.framework")
    FileUtils.mkdir_p(File.join(fw, "Modules", "FirebaseAnalyticsTarget.swiftmodule"))
    File.write(File.join(fw, "FirebaseAnalyticsTarget"), "binary")

    result = described_class.send(
      :rename_framework_to_product, fw, "FirebaseAnalyticsTarget", "FirebaseAnalytics"
    )

    expect(File.basename(result)).to eq("FirebaseAnalytics.framework")
    expect(File.exist?(File.join(result, "FirebaseAnalytics"))).to be(true)
    expect(Dir.exist?(File.join(result, "Modules", "FirebaseAnalytics.swiftmodule"))).to be(true)
    expect(Dir.exist?(fw)).to be(false)
  end

  it "leaves the framework untouched when product and module names match" do
    staging = File.join(tmpdir, "staging2")
    fw = File.join(staging, "Alamofire.framework")
    FileUtils.mkdir_p(fw)
    File.write(File.join(fw, "Alamofire"), "binary")

    result = described_class.send(:rename_framework_to_product, fw, "Alamofire", "Alamofire")

    expect(result).to eq(fw)
    expect(File.exist?(File.join(fw, "Alamofire"))).to be(true)
  end

  # Field bug, confirmed live and blocking the entire app build: rename_framework_to_product
  # renamed the framework directory, binary, and .swiftmodule directory, but never patched
  # the framework's own Info.plist -- CFBundleExecutable/CFBundleName stayed as the pre-rename
  # target name (FirebaseAnalyticsTarget) while everything else on disk was renamed to the
  # product name (FirebaseAnalytics). Xcode's build-plan resolution reads CFBundleExecutable to
  # find the bundle's executable, doesn't find a file by that name, and aborts the whole build
  # before any compilation starts ("could not determine executable path for bundle").
  it "patches Info.plist's CFBundleExecutable and CFBundleName from target name to product name" do
    staging = File.join(tmpdir, "staging3")
    fw = File.join(staging, "FirebaseAnalyticsTarget.framework")
    FileUtils.mkdir_p(fw)
    File.write(File.join(fw, "FirebaseAnalyticsTarget"), "binary")
    File.write(File.join(fw, "Info.plist"), <<~PLIST)
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
      <key>CFBundleExecutable</key><string>FirebaseAnalyticsTarget</string>
      <key>CFBundleIdentifier</key><string>com.spm-cache.firebaseanalyticstarget</string>
      <key>CFBundleName</key><string>FirebaseAnalyticsTarget</string>
      </dict>
      </plist>
    PLIST

    result = described_class.send(:rename_framework_to_product, fw, "FirebaseAnalyticsTarget", "FirebaseAnalytics")

    plist = File.read(File.join(result, "Info.plist"))
    expect(plist).to include("<key>CFBundleExecutable</key><string>FirebaseAnalytics</string>")
    expect(plist).to include("<key>CFBundleName</key><string>FirebaseAnalytics</string>")
    expect(plist).not_to include("FirebaseAnalyticsTarget")
  end

  # Real xcodebuild-produced Info.plist (use_existing_framework path, e.g. CryptoSwift-shaped
  # checkouts) uses Apple's standard multi-line indented format rather than spm-cache's own
  # compact single-line template -- the patch must handle both shapes.
  it "patches a multi-line, Xcode-style Info.plist just as well as the compact template" do
    staging = File.join(tmpdir, "staging3b")
    fw = File.join(staging, "SomeTarget.framework")
    FileUtils.mkdir_p(fw)
    File.write(File.join(fw, "Info.plist"), <<~PLIST)
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
      	<key>CFBundleExecutable</key>
      	<string>SomeTarget</string>
      	<key>CFBundleName</key>
      	<string>SomeTarget</string>
      </dict>
      </plist>
    PLIST

    result = described_class.send(:rename_framework_to_product, fw, "SomeTarget", "SomeProduct")

    plist = File.read(File.join(result, "Info.plist"))
    expect(plist).to include("<string>SomeProduct</string>")
    expect(plist).not_to include("SomeTarget")
  end

  # Field gap, same function: create_objc_module (build.rb) writes
  # Modules/module.modulemap declaring `framework module <module_name>` with
  # `umbrella header "<module_name>.h"`, and the actual file
  # Headers/<module_name>.h. The rename touched dir/binary/swiftmodule/Info.plist
  # but never the modulemap content or the umbrella header filename -- latent
  # today (no current product with product != target also has public headers),
  # but a real gap in the same function.
  it "renames the umbrella header and rewrites the modulemap when an ObjC module was assembled" do
    staging = File.join(tmpdir, "staging4")
    fw = File.join(staging, "FirebaseCoreTarget.framework")
    headers_dir = File.join(fw, "Headers")
    modules_dir = File.join(fw, "Modules")
    FileUtils.mkdir_p(headers_dir)
    FileUtils.mkdir_p(modules_dir)
    File.write(File.join(headers_dir, "FIRApp.h"), "@interface FIRApp @end")
    File.write(File.join(headers_dir, "FirebaseCoreTarget.h"), '#import "FIRApp.h"')
    File.write(File.join(modules_dir, "module.modulemap"), <<~MODULEMAP)
      framework module FirebaseCoreTarget {
        umbrella header "FirebaseCoreTarget.h"
        export *

        module * { export * }
      }
    MODULEMAP

    result = described_class.send(:rename_framework_to_product, fw, "FirebaseCoreTarget", "FirebaseCore")

    expect(File.exist?(File.join(result, "Headers", "FirebaseCore.h"))).to be(true)
    expect(File.exist?(File.join(result, "Headers", "FirebaseCoreTarget.h"))).to be(false)
    expect(File.exist?(File.join(result, "Headers", "FIRApp.h"))).to be(true)

    modulemap = File.read(File.join(result, "Modules", "module.modulemap"))
    expect(modulemap).to include("framework module FirebaseCore {")
    expect(modulemap).to include('umbrella header "FirebaseCore.h"')
    expect(modulemap).not_to include("FirebaseCoreTarget")
  end

  it "leaves modulemap handling a no-op for a Swift-only framework with no modulemap (existing rename tests unaffected)" do
    staging = File.join(tmpdir, "staging5")
    fw = File.join(staging, "FirebaseAnalyticsTarget.framework")
    FileUtils.mkdir_p(File.join(fw, "Modules", "FirebaseAnalyticsTarget.swiftmodule"))
    File.write(File.join(fw, "FirebaseAnalyticsTarget"), "binary")

    result = described_class.send(:rename_framework_to_product, fw, "FirebaseAnalyticsTarget", "FirebaseAnalytics")

    expect(Dir.exist?(File.join(result, "Headers"))).to be(false)
    expect(File.exist?(File.join(result, "Modules", "module.modulemap"))).to be(false)
    expect(Dir.exist?(File.join(result, "Modules", "FirebaseAnalytics.swiftmodule"))).to be(true)
  end

  # Field bug (Class D sibling-skip), completing the fix started in
  # #find_framework_companions above: write_shim_sidecar consumes the
  # per-companion arrays collected across all destinations and, for each
  # name with at least one entry, calls XCFramework.build -- OVERWRITING
  # whatever .xcframework already exists at that name in out_dir. That's
  # presumably why the old guard existed: to avoid a wasteful, redundant
  # full rebuild of an unchanged companion for every sibling that
  # references it. The fix must record the name in THIS product's own
  # sidecar without triggering that rebuild: a :cached marker (rather than
  # a real framework path) means "already built, just note the name."
  describe "#write_shim_sidecar" do
    it "records an already-cached companion in the sidecar without invoking XCFramework.build for it, while still building a genuinely new one" do
      output_path = File.join(out_dir, "BitCollections.xcframework")
      FileUtils.mkdir_p(File.join(out_dir, "InternalCollectionsUtilities.xcframework"))
      cached_mtime = File.mtime(File.join(out_dir, "InternalCollectionsUtilities.xcframework"))

      new_companion_fw = File.join(tmpdir, "NewCompanion.framework")
      FileUtils.mkdir_p(new_companion_fw)

      expect(SPMCache::SPM::XCFramework::XCFramework).to receive(:new)
        .with(hash_including(name: "NewCompanion"))
        .and_return(double("XC", build: File.join(out_dir, "NewCompanion.xcframework")))
      expect(SPMCache::SPM::XCFramework::XCFramework).not_to receive(:new)
        .with(hash_including(name: "InternalCollectionsUtilities"))

      shim_framework_paths = {
        "InternalCollectionsUtilities" => [:cached],
        "NewCompanion" => [new_companion_fw],
      }

      described_class.send(:write_shim_sidecar, output_path, shim_framework_paths, out_dir)

      sidecar = JSON.parse(File.read("#{output_path}.shims.json"))
      expect(sidecar).to match_array(%w[InternalCollectionsUtilities NewCompanion])
      expect(File.mtime(File.join(out_dir, "InternalCollectionsUtilities.xcframework"))).to eq(cached_mtime)
    end
  end
end
