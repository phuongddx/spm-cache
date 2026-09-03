# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "json"

# Unit-tests Installer#enrich_lockfile_products with a stubbed
# SPM::Desc::Description (no real `swift package describe` shells out).
# Mirrors the stubbing pattern from spec/build_pipeline_spec.rb.
RSpec.describe SPMCache::Installer, "#enrich_lockfile_products" do
  let(:tmpdir) { Dir.mktmpdir }
  let(:project_path) { File.join(tmpdir, "Fake.xcodeproj") }
  let(:lockfile_path) { File.join(tmpdir, "spm-cache.lock") }
  let(:umbrella_dir) { File.join(tmpdir, "umbrella") }
  let(:checkouts_root) { File.join(umbrella_dir, ".build", "checkouts") }

  before do
    FileUtils.mkdir_p(project_path)
    FileUtils.mkdir_p(checkouts_root)
    SPMCache::Core::Config.instance.reset!
    allow(SPMCache::Core::Config.instance).to receive(:umbrella_dir).and_return(umbrella_dir)
  end

  after { FileUtils.rm_rf(tmpdir) }

  # `targets:` defaults to no target metadata so every pre-existing caller
  # keeps its current behavior (describe reported nothing about targets).
  # Target objects are built through the real Target.from_raw factory so a
  # stub can never disagree with the real type dispatch about what counts
  # as binary.
  def stub_desc_products(pkg_dir, products, targets: [])
    fake_desc = instance_double(SPMCache::SPM::Desc::Description)
    allow(SPMCache::SPM::Desc::Description).to receive(:new)
      .with(hash_including(pkg_dir: pkg_dir)).and_return(fake_desc)
    allow(fake_desc).to receive(:fetch)
    allow(fake_desc).to receive(:products).and_return(
      products.map { |p| SPMCache::SPM::Desc::Product.new(raw: p, pkg_dir: pkg_dir) },
    )
    allow(fake_desc).to receive(:targets).and_return(
      targets.map { |t| SPMCache::SPM::Desc::Target.from_raw(t, pkg_dir: pkg_dir) },
    )
  end

  def write_lockfile(packages, spm_cache_version: nil)
    proj_data = {
      "packages" => packages,
      "dependencies" => {},
      "platforms" => { "ios" => "16.0" },
    }
    proj_data["spm_cache_version"] = spm_cache_version if spm_cache_version
    File.write(lockfile_path, JSON.generate("Fake.xcodeproj" => proj_data))
  end

  def make_installer
    described_class.new(project: project_path)
  end

  it "enriches an entry whose checkout is present with real products[] metadata" do
    FileUtils.mkdir_p(File.join(checkouts_root, "Alamofire"))
    stub_desc_products(File.join(checkouts_root, "Alamofire"), [
      { "name" => "Alamofire", "type" => { "library" => ["automatic"] } },
    ])
    write_lockfile([{ "repositoryURL" => "https://github.com/Alamofire/Alamofire.git", "name" => "Alamofire" }])

    installer = make_installer
    installer.instance_variable_set(:@lockfile, SPMCache::Core::Lockfile.new(lockfile_path))

    installer.send(:enrich_lockfile_products)

    saved = JSON.parse(File.read(lockfile_path))
    pkg = saved["Fake.xcodeproj"]["packages"].first
    expect(pkg["products"]).to eq([{ "name" => "Alamofire", "type" => "library", "targets" => [] }])
  end

  it "leaves an entry unchanged and warns when its checkout cannot be found" do
    write_lockfile([{ "repositoryURL" => "https://github.com/missing/NoCheckout.git", "name" => "NoCheckout" }])

    installer = make_installer
    installer.instance_variable_set(:@lockfile, SPMCache::Core::Lockfile.new(lockfile_path))

    expect { installer.send(:enrich_lockfile_products) }.to output(/No checkout found for 'NoCheckout'/).to_stderr

    saved = JSON.parse(File.read(lockfile_path))
    pkg = saved["Fake.xcodeproj"]["packages"].first
    expect(pkg["products"]).to be_nil
  end

  it "leaves an entry unchanged and warns when 'swift package describe' returns no products" do
    FileUtils.mkdir_p(File.join(checkouts_root, "BinaryOnly"))
    stub_desc_products(File.join(checkouts_root, "BinaryOnly"), [])
    write_lockfile([{ "repositoryURL" => "https://github.com/example/BinaryOnly.git", "name" => "BinaryOnly" }])

    installer = make_installer
    installer.instance_variable_set(:@lockfile, SPMCache::Core::Lockfile.new(lockfile_path))

    expect { installer.send(:enrich_lockfile_products) }.to output(
      /'swift package describe' returned no products for 'BinaryOnly'/,
    ).to_stderr

    saved = JSON.parse(File.read(lockfile_path))
    pkg = saved["Fake.xcodeproj"]["packages"].first
    expect(pkg["products"]).to be_nil
  end

  # Field regression: eh_xcframework's real Package.swift wraps an internal
  # binaryTarget ("abcd") inside a plain target ("eHealth"), which is itself
  # the sole declared product. `swift package describe` fails outright for
  # this package (the DerivedData-fallback checkout copy doesn't include the
  # binaryTarget's local artifact, so `describe` errors trying to open it),
  # triggering this text-parsing fallback. The fallback previously also
  # scanned `.binaryTarget(name:)` declarations as if they were independent
  # products, fabricating a bogus "abcd" product that doesn't exist in the
  # real manifest -- this broke proxy resolution project-wide with
  # `product 'abcd' ... not found`. Only `.library(name:)` should ever be
  # treated as a product.
  it "falls back to parsing Package.swift's .library() names when 'describe' fails, without fabricating a product from an internal binaryTarget" do
    checkout_dir = File.join(checkouts_root, "eh_xcframework")
    FileUtils.mkdir_p(checkout_dir)
    File.write(File.join(checkout_dir, "Package.swift"), <<~SWIFT)
      // swift-tools-version: 6.2
      import PackageDescription

      let package = Package(
          name: "eHealth",
          products: [
              .library(name: "eHealth", targets: ["eHealth"]),
          ],
          targets: [
              .target(name: "eHealth", dependencies: ["abcd"], path: "eHealth-Wrapper"),
              .binaryTarget(name: "abcd", path: "eHealth-Wrapper/Resources/eHealth.xcframework.zip"),
          ]
      )
    SWIFT
    stub_desc_products(checkout_dir, [])
    write_lockfile([{ "repositoryURL" => "git@bitbucket.org:axonivy-prod/eh_xcframework.git", "name" => "eh_xcframework" }])

    installer = make_installer
    installer.instance_variable_set(:@lockfile, SPMCache::Core::Lockfile.new(lockfile_path))

    expect { installer.send(:enrich_lockfile_products) }.not_to output(/returned no products/).to_stderr

    saved = JSON.parse(File.read(lockfile_path))
    pkg = saved["Fake.xcodeproj"]["packages"].first
    expect(pkg["products"]).to eq([
      { "name" => "eHealth", "type" => "library", "targets" => ["eHealth"] },
    ])
  end

  it "captures a .library()'s own targets: array instead of assuming it equals [name]" do
    checkout_dir = File.join(checkouts_root, "MultiTargetLib")
    FileUtils.mkdir_p(checkout_dir)
    File.write(File.join(checkout_dir, "Package.swift"), <<~SWIFT)
      // swift-tools-version: 5.9
      import PackageDescription

      let package = Package(
          name: "MultiTargetLib",
          products: [
              .library(name: "Foo", targets: ["Bar", "Baz"]),
              .library(name: "NoTargetsListed"),
          ],
          targets: []
      )
    SWIFT
    stub_desc_products(checkout_dir, [])
    write_lockfile([{ "repositoryURL" => "https://github.com/example/MultiTargetLib.git", "name" => "MultiTargetLib" }])

    installer = make_installer
    installer.instance_variable_set(:@lockfile, SPMCache::Core::Lockfile.new(lockfile_path))

    installer.send(:enrich_lockfile_products)

    saved = JSON.parse(File.read(lockfile_path))
    pkg = saved["Fake.xcodeproj"]["packages"].first
    expect(pkg["products"]).to eq([
      { "name" => "Foo", "type" => "library", "targets" => ["Bar", "Baz"] },
      { "name" => "NoTargetsListed", "type" => "library", "targets" => ["NoTargetsListed"] },
    ])
  end

  it "still warns when 'describe' returns no products and Package.swift has no parseable library names" do
    checkout_dir = File.join(checkouts_root, "TrulyEmpty")
    FileUtils.mkdir_p(checkout_dir)
    File.write(File.join(checkout_dir, "Package.swift"), <<~SWIFT)
      // swift-tools-version: 5.9
      import PackageDescription
      let package = Package(name: "TrulyEmpty", products: [], targets: [])
    SWIFT
    stub_desc_products(checkout_dir, [])
    write_lockfile([{ "repositoryURL" => "https://github.com/example/TrulyEmpty.git", "name" => "TrulyEmpty" }])

    installer = make_installer
    installer.instance_variable_set(:@lockfile, SPMCache::Core::Lockfile.new(lockfile_path))

    expect { installer.send(:enrich_lockfile_products) }.to output(
      /'swift package describe' returned no products for 'TrulyEmpty'/,
    ).to_stderr

    saved = JSON.parse(File.read(lockfile_path))
    pkg = saved["Fake.xcodeproj"]["packages"].first
    expect(pkg["products"]).to be_nil
  end

  it "is idempotent: does not re-describe an entry already enriched by the current spm-cache version" do
    write_lockfile([{
      "repositoryURL" => "https://github.com/Already/Enriched.git",
      "name" => "Enriched",
      "products" => [{ "name" => "Enriched", "type" => "library", "targets" => ["Enriched"] }],
    }], spm_cache_version: SPMCache::VERSION)

    installer = make_installer
    installer.instance_variable_set(:@lockfile, SPMCache::Core::Lockfile.new(lockfile_path))

    expect(SPMCache::SPM::Desc::Description).not_to receive(:new)
    installer.send(:enrich_lockfile_products)
  end

  # Field regression: a fabricated `abcd` product (written by a buggy 0.2.2
  # run) survived the 0.2.3 fix that corrected products_from_manifest_fallback,
  # because the idempotency guard above skips any package that already has
  # `products`, correct or not, and nothing invalidated the stale data on
  # upgrade. `invalidate_stale_products!` closes this: any lockfile whose
  # per-project `spm_cache_version` doesn't match the running version gets
  # every package's `products` cleared before the enrichment loop runs, so
  # they're all freshly re-derived once per version bump.
  it "invalidates and re-derives products[] written by an older spm-cache version" do
    checkout_dir = File.join(checkouts_root, "eh_xcframework")
    FileUtils.mkdir_p(checkout_dir)
    stub_desc_products(checkout_dir, [{ "name" => "eHealth", "type" => "library", "targets" => ["eHealth"] }])
    write_lockfile([{
      "repositoryURL" => "git@bitbucket.org:axonivy-prod/eh_xcframework.git",
      "name" => "eh_xcframework",
      "products" => [
        { "name" => "eHealth", "type" => "library", "targets" => ["eHealth"] },
        { "name" => "abcd", "type" => "library", "targets" => ["abcd"] },
      ],
    }], spm_cache_version: "0.2.2")

    installer = make_installer
    installer.instance_variable_set(:@lockfile, SPMCache::Core::Lockfile.new(lockfile_path))
    installer.send(:enrich_lockfile_products)

    saved = JSON.parse(File.read(lockfile_path))
    pkg = saved["Fake.xcodeproj"]["packages"].first
    expect(pkg["products"]).to eq([{ "name" => "eHealth", "type" => "library", "targets" => ["eHealth"] }])
  end

  it "invalidates and re-derives products[] when no version stamp exists at all (pre-upgrade lockfile)" do
    checkout_dir = File.join(checkouts_root, "Legacy")
    FileUtils.mkdir_p(checkout_dir)
    stub_desc_products(checkout_dir, [{ "name" => "Legacy", "type" => "library", "targets" => ["Legacy"] }])
    write_lockfile([{
      "repositoryURL" => "https://github.com/example/Legacy.git",
      "name" => "Legacy",
      "products" => [{ "name" => "StaleWrongProduct", "type" => "library", "targets" => ["StaleWrongProduct"] }],
    }])

    installer = make_installer
    installer.instance_variable_set(:@lockfile, SPMCache::Core::Lockfile.new(lockfile_path))
    installer.send(:enrich_lockfile_products)

    saved = JSON.parse(File.read(lockfile_path))
    pkg = saved["Fake.xcodeproj"]["packages"].first
    expect(pkg["products"]).to eq([{ "name" => "Legacy", "type" => "library", "targets" => ["Legacy"] }])
  end

  it "stamps the project with the current spm_cache_version after enriching" do
    checkout_dir = File.join(checkouts_root, "Fresh")
    FileUtils.mkdir_p(checkout_dir)
    stub_desc_products(checkout_dir, [{ "name" => "Fresh", "type" => "library", "targets" => ["Fresh"] }])
    write_lockfile([{ "repositoryURL" => "https://github.com/example/Fresh.git", "name" => "Fresh" }])

    installer = make_installer
    installer.instance_variable_set(:@lockfile, SPMCache::Core::Lockfile.new(lockfile_path))
    installer.send(:enrich_lockfile_products)

    saved = JSON.parse(File.read(lockfile_path))
    expect(saved["Fake.xcodeproj"]["spm_cache_version"]).to eq(SPMCache::VERSION)
  end

  # 16-02 / TOGL-03: the enrichment pass already fetches `swift package
  # describe` per package, so it also records -- from the SAME output, in
  # the same pass -- whether the package declares a binary target. The flag
  # is the persisted fact behind the `binary-target` untoggleable reason.
  describe "derived binary-target flag" do
    it "records the flag as true, beside products[], when describe reports a binary target" do
      checkout_dir = File.join(checkouts_root, "FirebaseBinary")
      FileUtils.mkdir_p(checkout_dir)
      stub_desc_products(checkout_dir, [
        { "name" => "FirebaseBinary", "type" => { "library" => ["automatic"] }, "targets" => ["FirebaseBinary"] },
      ], targets: [
        { "name" => "FirebaseBinary", "type" => "binary" },
      ])
      write_lockfile([{ "repositoryURL" => "https://github.com/example/FirebaseBinary.git", "name" => "FirebaseBinary" }])

      installer = make_installer
      installer.instance_variable_set(:@lockfile, SPMCache::Core::Lockfile.new(lockfile_path))
      installer.send(:enrich_lockfile_products)

      saved = JSON.parse(File.read(lockfile_path))
      pkg = saved["Fake.xcodeproj"]["packages"].first
      expect(pkg["products"]).to eq([{ "name" => "FirebaseBinary", "type" => "library", "targets" => ["FirebaseBinary"] }])
      expect(pkg["binary_target"]).to be(true)
    end

    it "records the flag as explicitly false -- not absent -- when describe reports only regular targets" do
      checkout_dir = File.join(checkouts_root, "PlainSwift")
      FileUtils.mkdir_p(checkout_dir)
      stub_desc_products(checkout_dir, [
        { "name" => "PlainSwift", "type" => { "library" => ["automatic"] }, "targets" => ["PlainSwift"] },
      ], targets: [
        { "name" => "PlainSwift", "type" => "regular" },
      ])
      write_lockfile([{ "repositoryURL" => "https://github.com/example/PlainSwift.git", "name" => "PlainSwift" }])

      installer = make_installer
      installer.instance_variable_set(:@lockfile, SPMCache::Core::Lockfile.new(lockfile_path))
      installer.send(:enrich_lockfile_products)

      saved = JSON.parse(File.read(lockfile_path))
      pkg = saved["Fake.xcodeproj"]["packages"].first
      expect(pkg["binary_target"]).to be(false)
    end

    it "leaves an entry untouched, flag included, when its checkout cannot be found" do
      write_lockfile([{ "repositoryURL" => "https://github.com/missing/NoCheckoutForFlag.git", "name" => "NoCheckoutForFlag" }])

      installer = make_installer
      installer.instance_variable_set(:@lockfile, SPMCache::Core::Lockfile.new(lockfile_path))

      expect { installer.send(:enrich_lockfile_products) }.to output(/No checkout found for 'NoCheckoutForFlag'/).to_stderr

      saved = JSON.parse(File.read(lockfile_path))
      pkg = saved["Fake.xcodeproj"]["packages"].first
      expect(pkg["products"]).to be_nil
      expect(pkg).not_to have_key("binary_target")
    end

    it "records the flag as false when describe returns nothing and the manifest fallback supplies the products" do
      checkout_dir = File.join(checkouts_root, "FallbackBin")
      FileUtils.mkdir_p(checkout_dir)
      File.write(File.join(checkout_dir, "Package.swift"), <<~SWIFT)
        // swift-tools-version: 5.9
        import PackageDescription
        let package = Package(
            name: "FallbackBin",
            products: [.library(name: "FallbackBin")],
            targets: [.binaryTarget(name: "FallbackBin", path: "artifacts/FallbackBin.xcframework.zip")]
        )
      SWIFT
      stub_desc_products(checkout_dir, [])
      write_lockfile([{ "repositoryURL" => "https://github.com/example/FallbackBin.git", "name" => "FallbackBin" }])

      installer = make_installer
      installer.instance_variable_set(:@lockfile, SPMCache::Core::Lockfile.new(lockfile_path))
      installer.send(:enrich_lockfile_products)

      saved = JSON.parse(File.read(lockfile_path))
      pkg = saved["Fake.xcodeproj"]["packages"].first
      expect(pkg["products"]).to eq([{ "name" => "FallbackBin", "type" => "library", "targets" => ["FallbackBin"] }])
      # The fallback parses product declarations only and knows nothing
      # about target types -- the flag stays the derived false of an empty
      # describe target list, never a guess.
      expect(pkg["binary_target"]).to be(false)
    end

    it "invalidates the flag together with products[] on a version bump and re-derives both" do
      checkout_dir = File.join(checkouts_root, "BinStamp")
      FileUtils.mkdir_p(checkout_dir)
      stub_desc_products(checkout_dir, [
        { "name" => "BinStamp", "type" => { "library" => ["automatic"] }, "targets" => ["BinStamp"] },
      ], targets: [
        { "name" => "BinStamp", "type" => "binary" },
      ])
      write_lockfile([{
        "repositoryURL" => "https://github.com/example/BinStamp.git",
        "name" => "BinStamp",
        "products" => [{ "name" => "StaleProduct", "type" => "library", "targets" => ["StaleProduct"] }],
        "binary_target" => false,
      }], spm_cache_version: "0.2.2")

      installer = make_installer
      installer.instance_variable_set(:@lockfile, SPMCache::Core::Lockfile.new(lockfile_path))
      installer.send(:enrich_lockfile_products)

      saved = JSON.parse(File.read(lockfile_path))
      pkg = saved["Fake.xcodeproj"]["packages"].first
      expect(pkg["products"]).to eq([{ "name" => "BinStamp", "type" => "library", "targets" => ["BinStamp"] }])
      expect(pkg["binary_target"]).to be(true)
    end

    it "is idempotent: skips a current-version entry entirely, flag included, without describing it" do
      write_lockfile([{
        "repositoryURL" => "https://github.com/Already/Flagged.git",
        "name" => "Flagged",
        "products" => [{ "name" => "Flagged", "type" => "library", "targets" => ["Flagged"] }],
        "binary_target" => false,
      }], spm_cache_version: SPMCache::VERSION)

      installer = make_installer
      installer.instance_variable_set(:@lockfile, SPMCache::Core::Lockfile.new(lockfile_path))

      expect(SPMCache::SPM::Desc::Description).not_to receive(:new)
      installer.send(:enrich_lockfile_products)

      saved = JSON.parse(File.read(lockfile_path))
      pkg = saved["Fake.xcodeproj"]["packages"].first
      expect(pkg["binary_target"]).to be(false)
    end
  end
end
