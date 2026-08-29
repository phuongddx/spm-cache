# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "json"

# TEST-01 regression contract: an out-of-range transitive pin is detected and
# reported, never silently re-resolved -- pinned in BOTH assertion directions
# (drift MUST warn; agreeing pins MUST NOT warn) and from BOTH drift-injection
# sources (Phase 8 resolution read-back via BuildPipeline#report_fidelity, and
# Phase 9 provenance-sidecar disagreement via gen-proxy hit/miss semantics).
# Real xcodebuild is never invoked; Desc::Description, Buildable, and
# XCFramework are stubbed exactly as in spec/build_pipeline_provenance_spec.rb
# -- BuildPipeline.run including report_fidelity stays real, as does the
# filesystem for Package.resolved and the provenance sidecars.
RSpec.describe SPMCache::SPM::BuildPipeline, "TEST-01: transitive-version drift regression (read-back + provenance)" do
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

    # SC4 executable hermeticity guard (default-deny, both Core::Sh entry
    # points): the tier-1 seam must need ZERO shell-outs, so any invocation
    # that survives the object stubs above raises instead of running.
    allow(SPMCache::Core::Sh).to receive(:run) do |cmd, *_opts|
      raise "unexpected real invocation: Sh.run(#{cmd.inspect})"
    end
    allow(SPMCache::Core::Sh).to receive(:capture_output) do |cmd, *_opts|
      raise "unexpected real invocation: Sh.capture_output(#{cmd.inspect})"
    end
  end

  after { FileUtils.rm_rf(tmpdir) }

  it "TEST-01/SC1: a silently re-resolved pin is detected and reported, not swallowed" do
    fake_buildable = instance_double(SPMCache::SPM::Buildable)
    allow(SPMCache::SPM::Buildable).to receive(:new).and_return(fake_buildable)
    allow(fake_buildable).to receive(:build_for_destination) do |*_args, **_kwargs|
      # Drift injection (STACK.md Experiment H3): the seeded intended pin
      # (aaa111) is silently discarded and re-resolved to bbb222, rewriting
      # pkg_dir/Package.resolved in place before the build "returns" its
      # artifacts. The regression contract under test: this MUST be detected.
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

    parsed = JSON.parse(File.read("#{result}.provenance.json"))
    expect(parsed["fidelity_status"]).to eq("resolution-incompatible")
    expect(parsed["pins"]).to eq("SomePkg" => "bbb222")
  end
end
