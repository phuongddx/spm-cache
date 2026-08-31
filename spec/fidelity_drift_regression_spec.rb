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

  # Parametrized realized-pins runner (multi-pin capable): installs the
  # Buildable stub writing an arbitrary realized Package.resolved built from
  # a Hash of identity => pin-state, then drives the standard scaffold and
  # returns the result path. {} writes a readable zero-pin file. nil is the
  # missing-file edge: seeding necessarily creates pkg_dir/Package.resolved
  # (seed_host_graph copies the host graph in before the build), so absence
  # at read-back is simulated by the build consuming it.
  def run_with_realized_pins(realized)
    fake_buildable = instance_double(SPMCache::SPM::Buildable)
    allow(SPMCache::SPM::Buildable).to receive(:new).and_return(fake_buildable)
    allow(fake_buildable).to receive(:build_for_destination) do |*_args, **_kwargs|
      if realized
        File.write(File.join(pkg_dir, "Package.resolved"), JSON.generate(
          "pins" => realized.map { |identity, state| { "identity" => identity, "state" => state } },
        ))
      else
        FileUtils.rm_f(File.join(pkg_dir, "Package.resolved"))
      end
      {
        derived_data: "/dd", object_file: "/dd/SomePkg.o",
        swiftmodule: nil, swiftdoc: nil, swiftsourceinfo: nil, swiftinterface: nil,
      }
    end
    allow(fake_buildable).to receive(:create_framework) do |_arts, subdir|
      fw = File.join(subdir, "SomePkg.framework")
      FileUtils.mkdir_p(fw)
      File.write(File.join(fw, "SomePkg"), "stub")
      fw
    end

    described_class.run(
      name: "SomePkg", pkg_dir: pkg_dir, destinations: ["iphonesimulator"],
      out_dir: out_dir, resolved_pins_file: resolved_pins_file, config: "debug",
    )
  end

  it "TEST-01: agreeing pins never warn (false-positive guard)" do
    expect(SPMCache::Core::UI).not_to receive(:warn)

    result = run_with_realized_pins("SomePkg" => { "revision" => "aaa111" })

    parsed = JSON.parse(File.read("#{result}.provenance.json"))
    expect(parsed["fidelity_status"]).to eq("host-pinned")
    expect(parsed["pins"]).to eq("SomePkg" => "aaa111")
  end

  it "TEST-01: revision wins over version in the drift comparison -- intended revision vs realized version-only pin is drift" do
    result = nil
    expect {
      result = run_with_realized_pins("SomePkg" => { "revision" => "", "version" => "1.0.0" })
    }.to output(/resolution-incompatible/).to_stdout.and output(/SomePkg.*aaa111.*1\.0\.0/).to_stderr

    parsed = JSON.parse(File.read("#{result}.provenance.json"))
    expect(parsed["fidelity_status"]).to eq("resolution-incompatible")
    expect(parsed["pins"]).to eq("SomePkg" => "1.0.0")
  end

  it "TEST-01: equal version-only pins (empty revision on both sides) are not drift" do
    File.write(resolved_pins_file, JSON.generate(
      "pins" => [{ "identity" => "SomePkg", "state" => { "revision" => "", "version" => "1.0.0" } }],
    ))

    expect(SPMCache::Core::UI).not_to receive(:warn)

    result = run_with_realized_pins("SomePkg" => { "revision" => "", "version" => "1.0.0" })

    parsed = JSON.parse(File.read("#{result}.provenance.json"))
    expect(parsed["fidelity_status"]).to eq("host-pinned")
    expect(parsed["pins"]).to eq("SomePkg" => "1.0.0")
  end

  it "TEST-01: an empty realized pins array yields an empty drifted set -- host-pinned, empty pins sidecar, never raises" do
    expect(SPMCache::Core::UI).not_to receive(:warn)

    result = run_with_realized_pins({})

    parsed = JSON.parse(File.read("#{result}.provenance.json"))
    expect(parsed["fidelity_status"]).to eq("host-pinned")
    expect(parsed["pins"]).to eq({})
  end

  it "TEST-01: a missing realized Package.resolved carries no drift evidence -- host-pinned, empty pins sidecar, never raises" do
    expect(SPMCache::Core::UI).not_to receive(:warn)

    result = run_with_realized_pins(nil)

    parsed = JSON.parse(File.read("#{result}.provenance.json"))
    expect(parsed["fidelity_status"]).to eq("host-pinned")
    expect(parsed["pins"]).to eq({})
  end
end

# TEST-01's second drift-injection source: provenance-sidecar disagreement
# under Phase 9's hit/miss semantics. Runs the actual compiled spm-cache-proxy
# binary (tier-3, gen_proxy_provenance_spec.rb pattern), NOT the tier-1
# default-deny Core::Sh guard above -- this block invokes the local proxy via
# system() with output redirected to File::NULL, which involves no Core::Sh
# call, no network, and no xcodebuild. The drift signal at the cache layer:
# a sidecar whose recorded pin disagrees with the current pin (or is absent)
# can never serve the stale artifact as a hit.
RSpec.describe "TEST-01: provenance-sidecar disagreement is a cache miss, never a silent hit (gen-proxy real-binary)" do
  let(:binary) do
    local = SPMCache::ROOT.join("tools", "spm-cache-proxy",
                                ".build", "release", "spm-cache-proxy").to_s
    File.executable?(local) ? local : nil
  end

  let(:tmpdir) { Dir.mktmpdir }

  before do
    skip "spm-cache-proxy binary not built (run make proxy.build)" unless binary
  end

  after { FileUtils.rm_rf(tmpdir) if tmpdir }

  def write_lockfile(path, project_name:, packages:)
    File.write(path, JSON.generate(
      project_name => {
        "packages" => packages,
        "dependencies" => {},
        "platforms" => { "ios" => "16.0" },
      },
    ))
  end

  def write_sidecar(cache_dir, module_name, pins:, status: "host-pinned")
    File.write(
      File.join(cache_dir, "#{module_name}.xcframework.provenance.json"),
      JSON.generate("fidelity_status" => status, "pins" => pins),
    )
  end

  def run_gen_proxy(umbrella_dir:, lockfile:, output_dir:, cache_dir:)
    cmd = "#{binary} gen-proxy --umbrella #{umbrella_dir} --lockfile #{lockfile} " \
          "--output #{output_dir} --cache #{cache_dir}"
    system(cmd, out: File::NULL, err: File::NULL)
  end

  def statuses_from(output_dir)
    graph = JSON.parse(File.read(File.join(output_dir, "graph.json")))
    graph.each_with_object({}) { |e, h| h[e["module"]] = e["status"] }
  end

  it "TEST-01: an agreeing sidecar pin stays a hit" do
    umbrella_dir = File.join(tmpdir, "umbrella")
    output_dir = File.join(tmpdir, "proxy")
    cache_dir = File.join(tmpdir, "cache")
    [umbrella_dir, output_dir, cache_dir].each { |d| FileUtils.mkdir_p(d) }

    FileUtils.mkdir_p(File.join(cache_dir, "SomePkg.xcframework"))
    write_sidecar(cache_dir, "SomePkg", pins: { "SomePkg" => "aaa111" })

    lockfile = File.join(tmpdir, "lockfile.json")
    write_lockfile(lockfile, project_name: "FixtureApp.xcodeproj", packages: [
      {
        "repositoryURL" => "https://example.invalid/SomePkg.git",
        "name" => "SomePkg",
        "product_name" => "SomePkg",
        "revision" => "aaa111",
      },
    ])

    run_gen_proxy(umbrella_dir: umbrella_dir, lockfile: lockfile, output_dir: output_dir, cache_dir: cache_dir)

    expect(statuses_from(output_dir)["SomePkg"]).to eq("hit")
  end

  it "TEST-01: a disagreeing sidecar pin is a cache miss, never a silent hit" do
    umbrella_dir = File.join(tmpdir, "umbrella")
    output_dir = File.join(tmpdir, "proxy")
    cache_dir = File.join(tmpdir, "cache")
    [umbrella_dir, output_dir, cache_dir].each { |d| FileUtils.mkdir_p(d) }

    FileUtils.mkdir_p(File.join(cache_dir, "SomePkg.xcframework"))
    write_sidecar(cache_dir, "SomePkg", pins: { "SomePkg" => "bbb222" })

    lockfile = File.join(tmpdir, "lockfile.json")
    write_lockfile(lockfile, project_name: "FixtureApp.xcodeproj", packages: [
      {
        "repositoryURL" => "https://example.invalid/SomePkg.git",
        "name" => "SomePkg",
        "product_name" => "SomePkg",
        "revision" => "aaa111",
      },
    ])

    run_gen_proxy(umbrella_dir: umbrella_dir, lockfile: lockfile, output_dir: output_dir, cache_dir: cache_dir)

    expect(statuses_from(output_dir)["SomePkg"]).to eq("missed")
  end

  it "TEST-01: no sidecar at all is a miss (the v0.3.0-upgrade signal)" do
    umbrella_dir = File.join(tmpdir, "umbrella")
    output_dir = File.join(tmpdir, "proxy")
    cache_dir = File.join(tmpdir, "cache")
    [umbrella_dir, output_dir, cache_dir].each { |d| FileUtils.mkdir_p(d) }

    FileUtils.mkdir_p(File.join(cache_dir, "SomePkg.xcframework"))
    # Deliberately no provenance.json sidecar written for SomePkg.

    lockfile = File.join(tmpdir, "lockfile.json")
    write_lockfile(lockfile, project_name: "FixtureApp.xcodeproj", packages: [
      {
        "repositoryURL" => "https://example.invalid/SomePkg.git",
        "name" => "SomePkg",
        "product_name" => "SomePkg",
        "revision" => "aaa111",
      },
    ])

    run_gen_proxy(umbrella_dir: umbrella_dir, lockfile: lockfile, output_dir: output_dir, cache_dir: cache_dir)

    expect(statuses_from(output_dir)["SomePkg"]).to eq("missed")
  end
end
