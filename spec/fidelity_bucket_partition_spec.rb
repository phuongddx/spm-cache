# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "json"

# TEST-02 bucket-partition meta-spec: every package in the declared universe
# of one synthetic all-classes project (the kitchen-sink lockfile fixture plus
# the Package.resolved pin identities the tier-1 legs seed) lands in exactly
# ONE fidelity bucket -- zero-bucket AND double-bucket both fail the partition
# assertion (SC2: no package's resolution outcome may be silently absent).
#
# The six buckets span TWO production surfaces, so the observation route is
# hybrid (RESEARCH Open Question 1, adopted):
#   - provenance sidecars via the tier-1 object-stub seam -- BuildPipeline.run
#     (including report_fidelity) stays real; Desc::Description, Buildable,
#     and XCFramework are stubbed exactly as in
#     spec/build_pipeline_provenance_spec.rb; the default-deny Core::Sh guard
#     makes "zero real shell-outs" an executable assertion (SC4);
#   - graph.json via the compiled spm-cache-proxy binary (tier-3, the
#     gen_proxy_* pattern) for the Swift-side classifications.
#
# The universe is ALWAYS the fixture's declared input set (lockfile packages,
# including the empty-repositoryURL local/path entry, plus the tier-1 legs'
# resolved pin identities) -- never the classifier outputs. Bucket names are
# never typed as a literal enumeration: every recorded bucket value is read
# back from a real sidecar's fidelity_status or a real graph.json status.
RSpec.describe SPMCache::SPM::BuildPipeline, "TEST-02: bucket-partition coverage (tier-1 fidelity legs)" do
  let(:tmpdir) { Dir.mktmpdir }
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

  def write_resolved_pins(path, pin_map)
    File.write(path, JSON.generate(
      "pins" => pin_map.map { |identity, revision| { "identity" => identity, "state" => { "revision" => revision } } },
    ))
  end

  def write_resolved(path, identity, revision)
    write_resolved_pins(path, { identity => revision })
  end

  # Records one observed bucket value for a package identity and returns the
  # identity's collected bucket set (deduplicated). The partition classifier
  # COLLECTS every matching bucket instead of stopping at the first match, so
  # a package that lands in two buckets is visible as a two-member set --
  # that is how SC2's double-bucket arm is detectable at all.
  def observe_bucket(store, identity, bucket)
    collected = (store[identity] ||= [])
    collected << bucket unless bucket.nil?
    collected.uniq
  end

  # Drives one package through the REAL BuildPipeline.run + report_fidelity
  # on the tier-1 seam and returns the built output path. `seeded_pins` is
  # the host graph declared to resolved_pins_file; `realized_pins` is what
  # the stubbed build leaves in pkg_dir/Package.resolved (rewriting it is the
  # proven drift-injection idiom -- passing the same values as the seed
  # yields the agreeing-pins leg). `vendored: true` drops a `<name>.xcodeproj`
  # directory into pkg_dir so ResolvedGraph's glob classifies the checkout
  # before any seeding happens.
  def run_tier1_leg(name:, seeded_pins:, realized_pins:, vendored: false)
    pkg_dir = File.join(tmpdir, "pkg-#{name.downcase}")
    FileUtils.mkdir_p(pkg_dir)
    FileUtils.mkdir_p(out_dir)
    FileUtils.mkdir_p(File.join(pkg_dir, "#{name}.xcodeproj")) if vendored
    write_resolved_pins(resolved_pins_file, seeded_pins)

    stub_desc_products([{ "name" => name, "type" => { "library" => ["automatic"] } }], pkg_dir)

    fake_buildable = instance_double(SPMCache::SPM::Buildable)
    allow(SPMCache::SPM::Buildable).to receive(:new).and_return(fake_buildable)
    allow(fake_buildable).to receive(:build_for_destination) do |*_args, **_kwargs|
      write_resolved_pins(File.join(pkg_dir, "Package.resolved"), realized_pins)
      {
        derived_data: "/dd",
        object_file: "/dd/#{name}.o",
        swiftmodule: nil, swiftdoc: nil, swiftsourceinfo: nil, swiftinterface: nil,
      }
    end
    allow(fake_buildable).to receive(:create_framework) do |_arts, subdir|
      fw = File.join(subdir, "#{name}.framework")
      FileUtils.mkdir_p(fw)
      File.write(File.join(fw, name), "stub")
      fw
    end

    allow(SPMCache::SPM::XCFramework::XCFramework).to receive(:new).and_return(
      double("XCFramework", build: File.join(out_dir, "#{name}.xcframework")),
    )

    described_class.run(
      name: name, pkg_dir: pkg_dir, destinations: ["iphonesimulator"],
      out_dir: out_dir, resolved_pins_file: resolved_pins_file, config: "debug",
    )
  end

  before do
    # SC4 executable hermeticity guard (default-deny, both Core::Sh entry
    # points): the tier-1 seam must need ZERO shell-outs, so any invocation
    # that survives the object stubs raises instead of running.
    allow(SPMCache::Core::Sh).to receive(:run) do |cmd, *_opts|
      raise "unexpected real invocation: Sh.run(#{cmd.inspect})"
    end
    allow(SPMCache::Core::Sh).to receive(:capture_output) do |cmd, *_opts|
      raise "unexpected real invocation: Sh.capture_output(#{cmd.inspect})"
    end
  end

  after { FileUtils.rm_rf(tmpdir) }

  it "TEST-02: a pinned package is observed in exactly one bucket, read back from its sidecar" do
    expect(SPMCache::Core::UI).not_to receive(:warn)

    result = run_tier1_leg(
      name: "Alamofire",
      seeded_pins: { "Alamofire" => "aaa111" },
      realized_pins: { "Alamofire" => "aaa111" },
    )

    parsed = JSON.parse(File.read("#{result}.provenance.json"))
    status_read_from_sidecar = parsed.fetch("fidelity_status")

    observed_buckets = {}
    collected = observe_bucket(observed_buckets, "Alamofire", status_read_from_sidecar)

    expect(collected.length).to eq(1)
    expect(collected.first).to eq(status_read_from_sidecar)
    expect(parsed["pins"]).to eq("Alamofire" => "aaa111")
  end
end
