# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "json"

# Real-binary end-to-end proof of CACHE-02 (09-01): SC1 (no-provenance
# upgrade miss), SC2 (partial invalidation within one run), SC3
# (cross-project identity non-sharing on disagreeing pins, D-08), and D-07
# (cross-project sharing preserved on agreeing pins). Runs the actual
# compiled spm-cache-proxy binary, not a Ruby-side simulation. Mirrors
# spec/gen_proxy_cache_only_spec.rb's skip-if-not-built, real-tmpdir,
# graph.json-parsing pattern.
RSpec.describe "gen-proxy provenance-aware cache identity (Swift real-binary smoke)" do
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

  it "SC1: an xcframework with NO sidecar at all for a lockfile-pinned package is reported missed" do
    umbrella_dir = File.join(tmpdir, "umbrella")
    output_dir = File.join(tmpdir, "proxy")
    cache_dir = File.join(tmpdir, "cache")
    [umbrella_dir, output_dir, cache_dir].each { |d| FileUtils.mkdir_p(d) }

    FileUtils.mkdir_p(File.join(cache_dir, "Alamofire.xcframework"))
    # Deliberately no provenance.json sidecar written for Alamofire.

    lockfile = File.join(tmpdir, "lockfile.json")
    write_lockfile(lockfile, project_name: "FixtureApp.xcodeproj", packages: [
      {
        "repositoryURL" => "https://github.com/Alamofire/Alamofire.git",
        "name" => "Alamofire",
        "product_name" => "Alamofire",
        "version" => "5.9.1",
      },
    ])

    run_gen_proxy(umbrella_dir: umbrella_dir, lockfile: lockfile, output_dir: output_dir, cache_dir: cache_dir)

    expect(statuses_from(output_dir)["Alamofire"]).to eq("missed")
  end

  it "SC2: within ONE run, the agreeing package hits and the disagreeing package misses (partial invalidation)" do
    umbrella_dir = File.join(tmpdir, "umbrella")
    output_dir = File.join(tmpdir, "proxy")
    cache_dir = File.join(tmpdir, "cache")
    [umbrella_dir, output_dir, cache_dir].each { |d| FileUtils.mkdir_p(d) }

    FileUtils.mkdir_p(File.join(cache_dir, "Alamofire.xcframework"))
    write_sidecar(cache_dir, "Alamofire", pins: { "Alamofire" => "5.9.1" })

    FileUtils.mkdir_p(File.join(cache_dir, "SnapKit.xcframework"))
    write_sidecar(cache_dir, "SnapKit", pins: { "SnapKit" => "4.0.0" })

    lockfile = File.join(tmpdir, "lockfile.json")
    write_lockfile(lockfile, project_name: "FixtureApp.xcodeproj", packages: [
      {
        "repositoryURL" => "https://github.com/Alamofire/Alamofire.git",
        "name" => "Alamofire",
        "product_name" => "Alamofire",
        "version" => "5.9.1",
      },
      {
        "repositoryURL" => "https://github.com/SnapKit/SnapKit.git",
        "name" => "SnapKit",
        "product_name" => "SnapKit",
        "version" => "5.7.1",
      },
    ])

    run_gen_proxy(umbrella_dir: umbrella_dir, lockfile: lockfile, output_dir: output_dir, cache_dir: cache_dir)

    statuses = statuses_from(output_dir)
    expect(statuses["Alamofire"]).to eq("hit")
    expect(statuses["SnapKit"]).to eq("missed")
  end

  it "SC3/D-08: two projects sharing one cache dir, pinning the SAME identity at DIFFERENT versions, do not share the artifact" do
    cache_dir = File.join(tmpdir, "cache")
    FileUtils.mkdir_p(cache_dir)
    FileUtils.mkdir_p(File.join(cache_dir, "Alamofire.xcframework"))
    # Sidecar records project A's pin only.
    write_sidecar(cache_dir, "Alamofire", pins: { "Alamofire" => "5.9.1" })

    umbrella_a = File.join(tmpdir, "umbrella-a")
    output_a = File.join(tmpdir, "proxy-a")
    FileUtils.mkdir_p(umbrella_a)
    FileUtils.mkdir_p(output_a)
    lockfile_a = File.join(tmpdir, "lockfile-a.json")
    write_lockfile(lockfile_a, project_name: "ProjectA.xcodeproj", packages: [
      {
        "repositoryURL" => "https://github.com/Alamofire/Alamofire.git",
        "name" => "Alamofire",
        "product_name" => "Alamofire",
        "version" => "5.9.1",
      },
    ])

    umbrella_b = File.join(tmpdir, "umbrella-b")
    output_b = File.join(tmpdir, "proxy-b")
    FileUtils.mkdir_p(umbrella_b)
    FileUtils.mkdir_p(output_b)
    lockfile_b = File.join(tmpdir, "lockfile-b.json")
    write_lockfile(lockfile_b, project_name: "ProjectB.xcodeproj", packages: [
      {
        "repositoryURL" => "https://github.com/Alamofire/Alamofire.git",
        "name" => "Alamofire",
        "product_name" => "Alamofire",
        "version" => "5.10.0",
      },
    ])

    run_gen_proxy(umbrella_dir: umbrella_a, lockfile: lockfile_a, output_dir: output_a, cache_dir: cache_dir)
    run_gen_proxy(umbrella_dir: umbrella_b, lockfile: lockfile_b, output_dir: output_b, cache_dir: cache_dir)

    expect(statuses_from(output_a)["Alamofire"]).to eq("hit")
    expect(statuses_from(output_b)["Alamofire"]).to eq("missed")
  end

  it "Class-E-safe hit: a sidecar with pins: {} still reports hit regardless of the lockfile's pinned version" do
    umbrella_dir = File.join(tmpdir, "umbrella")
    output_dir = File.join(tmpdir, "proxy")
    cache_dir = File.join(tmpdir, "cache")
    [umbrella_dir, output_dir, cache_dir].each { |d| FileUtils.mkdir_p(d) }

    FileUtils.mkdir_p(File.join(cache_dir, "CryptoSwift.xcframework"))
    write_sidecar(cache_dir, "CryptoSwift", pins: {}, status: "not-graph-pinned")

    lockfile = File.join(tmpdir, "lockfile.json")
    write_lockfile(lockfile, project_name: "FixtureApp.xcodeproj", packages: [
      {
        "repositoryURL" => "https://github.com/krzyzanowskim/CryptoSwift.git",
        "name" => "CryptoSwift",
        "product_name" => "CryptoSwift",
        "version" => "1.8.3",
      },
    ])

    run_gen_proxy(umbrella_dir: umbrella_dir, lockfile: lockfile, output_dir: output_dir, cache_dir: cache_dir)

    expect(statuses_from(output_dir)["CryptoSwift"]).to eq("hit")
  end

  it "D-07: two projects pinning the SAME version of the same identity continue sharing the one cached artifact" do
    cache_dir = File.join(tmpdir, "cache")
    FileUtils.mkdir_p(cache_dir)
    FileUtils.mkdir_p(File.join(cache_dir, "Alamofire.xcframework"))
    write_sidecar(cache_dir, "Alamofire", pins: { "Alamofire" => "5.9.1" })

    umbrella_a = File.join(tmpdir, "umbrella-a")
    output_a = File.join(tmpdir, "proxy-a")
    FileUtils.mkdir_p(umbrella_a)
    FileUtils.mkdir_p(output_a)
    lockfile_a = File.join(tmpdir, "lockfile-a.json")
    write_lockfile(lockfile_a, project_name: "ProjectA.xcodeproj", packages: [
      {
        "repositoryURL" => "https://github.com/Alamofire/Alamofire.git",
        "name" => "Alamofire",
        "product_name" => "Alamofire",
        "version" => "5.9.1",
      },
    ])

    umbrella_b = File.join(tmpdir, "umbrella-b")
    output_b = File.join(tmpdir, "proxy-b")
    FileUtils.mkdir_p(umbrella_b)
    FileUtils.mkdir_p(output_b)
    lockfile_b = File.join(tmpdir, "lockfile-b.json")
    write_lockfile(lockfile_b, project_name: "ProjectB.xcodeproj", packages: [
      {
        "repositoryURL" => "https://github.com/Alamofire/Alamofire.git",
        "name" => "Alamofire",
        "product_name" => "Alamofire",
        "version" => "5.9.1",
      },
    ])

    run_gen_proxy(umbrella_dir: umbrella_a, lockfile: lockfile_a, output_dir: output_a, cache_dir: cache_dir)
    run_gen_proxy(umbrella_dir: umbrella_b, lockfile: lockfile_b, output_dir: output_b, cache_dir: cache_dir)

    expect(statuses_from(output_a)["Alamofire"]).to eq("hit")
    expect(statuses_from(output_b)["Alamofire"]).to eq("hit")
  end
end
