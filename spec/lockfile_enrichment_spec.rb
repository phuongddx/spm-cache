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

  def stub_desc_products(pkg_dir, products)
    fake_desc = instance_double(SPMCache::SPM::Desc::Description)
    allow(SPMCache::SPM::Desc::Description).to receive(:new)
      .with(hash_including(pkg_dir: pkg_dir)).and_return(fake_desc)
    allow(fake_desc).to receive(:fetch)
    allow(fake_desc).to receive(:products).and_return(
      products.map { |p| SPMCache::SPM::Desc::Product.new(raw: p, pkg_dir: pkg_dir) },
    )
  end

  def write_lockfile(packages)
    File.write(lockfile_path, JSON.generate(
      "Fake.xcodeproj" => {
        "packages" => packages,
        "dependencies" => {},
        "platforms" => { "ios" => "16.0" },
      },
    ))
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

  # Field regression: eh_xcframework (a private binary-target-only package)
  # resolved and checked out fine, but `swift package describe` came back
  # with an empty `products` array for it -- without a fallback, this
  # silently reintroduces the original wrong-product-name bug for exactly
  # the packages `describe` can't fully introspect.
  it "falls back to parsing Package.swift's .library()/.binaryTarget() names when 'describe' returns no products" do
    checkout_dir = File.join(checkouts_root, "eh_xcframework")
    FileUtils.mkdir_p(checkout_dir)
    File.write(File.join(checkout_dir, "Package.swift"), <<~SWIFT)
      // swift-tools-version: 5.9
      import PackageDescription

      let package = Package(
          name: "eh_xcframework",
          products: [
              .library(name: "EHXCFramework", targets: ["EHXCFrameworkTarget"]),
          ],
          targets: [
              .binaryTarget(name: "EHXCFrameworkTarget", path: "EHXCFramework.xcframework"),
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
      { "name" => "EHXCFramework", "type" => "library", "targets" => ["EHXCFramework"] },
      { "name" => "EHXCFrameworkTarget", "type" => "library", "targets" => ["EHXCFrameworkTarget"] },
    ])
  end

  it "still warns when 'describe' returns no products and Package.swift has no parseable library/binaryTarget names" do
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

  it "is idempotent: does not re-describe an entry that already has products[]" do
    write_lockfile([{
      "repositoryURL" => "https://github.com/Already/Enriched.git",
      "name" => "Enriched",
      "products" => [{ "name" => "Enriched", "type" => "library", "targets" => ["Enriched"] }],
    }])

    installer = make_installer
    installer.instance_variable_set(:@lockfile, SPMCache::Core::Lockfile.new(lockfile_path))

    expect(SPMCache::SPM::Desc::Description).not_to receive(:new)
    installer.send(:enrich_lockfile_products)
  end
end
