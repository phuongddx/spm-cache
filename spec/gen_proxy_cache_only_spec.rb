# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "json"
require "shellwords"

# Swift-side fixture check: runs the built spm-cache-proxy binary against
# spec/fixtures/ignore-lockfile.json with --cache-only and asserts graph.json
# statuses and source-fallback manifests. Skipped gracefully when the binary
# is not built (mirrors spec/gen_proxy_ignore_spec.rb).
RSpec.describe "gen-proxy --cache-only (Swift fixture smoke)" do
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

  def run_gen_proxy(cache_only: nil)
    cmd = "#{binary} gen-proxy --umbrella #{umbrella_dir} --lockfile #{lockfile} --output #{output_dir} --cache #{cache_dir}"
    cmd += " --cache-only #{Shellwords.escape(cache_only)}" if cache_only
    system(cmd, out: File::NULL, err: File::NULL)
  end

  it "marks the allowlisted module as cache-eligible, all others excluded" do
    run_gen_proxy(cache_only: "Alamofire")
    graph = JSON.parse(File.read(File.join(output_dir, "graph.json")))
    statuses = graph.each_with_object({}) { |e, h| h[e["module"]] = e["status"] }
    expect(%w[hit missed]).to include(statuses["Alamofire"])
    expect(statuses["SnapKit"]).to eq("excluded")
    expect(statuses["Logging"]).to eq("excluded")
  end

  it "emits a valid source-fallback manifest for an excluded package" do
    run_gen_proxy(cache_only: "Alamofire")
    snap_pkg = File.join(output_dir, ".proxies", "SnapKit_proxy", "Package.swift")
    manifest = File.read(snap_pkg)
    expect(manifest).to include(".package(url:")
    expect(manifest).to include(".product(name:")
  end

  it "produces no excluded statuses when --cache-only is absent (parity guard)" do
    run_gen_proxy(cache_only: nil)
    graph = JSON.parse(File.read(File.join(output_dir, "graph.json")))
    statuses = graph.map { |e| e["status"] }.uniq
    expect(statuses).not_to include("excluded")
  end
end
