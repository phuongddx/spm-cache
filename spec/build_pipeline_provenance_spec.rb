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
end
