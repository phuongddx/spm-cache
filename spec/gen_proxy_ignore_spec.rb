# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "json"
require "shellwords"

# Swift-side fixture check: runs the built spm-cache-proxy binary against
# spec/fixtures/ignore-lockfile.json with --ignore and asserts graph.json
# statuses and source-fallback manifests. Skipped gracefully when the binary
# is not built (per validation decision: no Swift Tests target).
RSpec.describe "gen-proxy --ignore (Swift fixture smoke)" do
  let(:binary) do
    local = SPMCache::ROOT.join("tools", "spm-cache-proxy",
                                ".build", "release", "spm-cache-proxy").to_s
    File.executable?(local) ? local : nil
  end

  let(:lockfile) do
    SPMCache::ROOT.join("spec", "fixtures", "ignore-lockfile.json").to_s
  end

  let(:tmpdir) { Dir.mktmpdir }
  let(:umbrella_dir) { File.join(tmpdir, "umbrella") }
  let(:output_dir) { File.join(tmpdir, "proxy") }
  let(:cache_dir) { File.join(tmpdir, "cache") }

  before do
    skip "spm-cache-proxy binary not built (run make proxy.build)" unless binary
    FileUtils.mkdir_p(umbrella_dir)
    FileUtils.mkdir_p(output_dir)
    FileUtils.mkdir_p(cache_dir)
  end

  after { FileUtils.rm_rf(tmpdir) if tmpdir }

  def run_gen_proxy(ignore: nil)
    cmd = "#{binary} gen-proxy --umbrella #{umbrella_dir} --lockfile #{lockfile} --output #{output_dir} --cache #{cache_dir}"
    cmd += " --ignore #{Shellwords.escape(ignore)}" if ignore
    system(cmd, out: File::NULL, err: File::NULL)
  end

  it "marks ignored module as ignored in graph.json" do
    run_gen_proxy(ignore: "Alamofire")
    graph = JSON.parse(File.read(File.join(output_dir, "graph.json")))
    statuses = graph.each_with_object({}) { |e, h| h[e["module"]] = e["status"] }
    expect(statuses["Alamofire"]).to eq("ignored")
    expect(statuses["SnapKit"]).to eq("missed")
  end

  it "marks all matching glob modules as ignored" do
    # swift-log product name is "Logging"; the glob should NOT match it,
    # but "swift-log" identity is the package name.
    run_gen_proxy(ignore: "swift-*")
    graph = JSON.parse(File.read(File.join(output_dir, "graph.json")))
    statuses = graph.each_with_object({}) { |e, h| h[e["module"]] = e["status"] }
    # swift-log's resolvedProductName is "Logging" (product_name wins).
    # fnmatch("swift-*", "Logging") is false; fnmatch("swift-*", "swift-log")
    # via name field is true -> it IS ignored.
    expect(statuses["Logging"]).to eq("ignored")
    expect(statuses["Alamofire"]).to eq("missed")
  end

  it "emits source-fallback manifest for missed (not empty stub)" do
    run_gen_proxy(ignore: "Alamofire")
    snap_pkg = File.join(output_dir, ".proxies", "SnapKit", "Package.swift")
    manifest = File.read(snap_pkg)
    expect(manifest).to include(".package(url:")
    expect(manifest).to include(".product(name:")
  end

  it "emits source-fallback manifest for ignored" do
    run_gen_proxy(ignore: "Alamofire")
    af_pkg = File.join(output_dir, ".proxies", "Alamofire", "Package.swift")
    manifest = File.read(af_pkg)
    expect(manifest).to include(".package(url:")
  end

  it "behaves as hit/missed only when --ignore absent" do
    run_gen_proxy(ignore: nil)
    graph = JSON.parse(File.read(File.join(output_dir, "graph.json")))
    statuses = graph.map { |e| e["status"] }.uniq
    expect(statuses).to match_array(["missed"])
  end
end
