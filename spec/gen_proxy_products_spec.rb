# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "json"

# Swift-side fixture check: runs the built spm-cache-proxy binary against
# spec/fixtures/products-lockfile.json (hand-written `products[]` metadata)
# and asserts per-product graph.json entries, real product names in proxy
# manifests, and shim imports using module names (not product names) when
# they differ. Skipped gracefully when the binary is not built (mirrors
# spec/gen_proxy_ignore_spec.rb).
RSpec.describe "gen-proxy products[] metadata (Swift fixture smoke)" do
  let(:binary) do
    local = SPMCache::ROOT.join("tools", "spm-cache-proxy",
                                ".build", "release", "spm-cache-proxy").to_s
    File.executable?(local) ? local : nil
  end

  let(:lockfile) do
    SPMCache::ROOT.join("spec", "fixtures", "products-lockfile.json").to_s
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

  def run_gen_proxy
    cmd = "#{binary} gen-proxy --umbrella #{umbrella_dir} --lockfile #{lockfile} --output #{output_dir} --cache #{cache_dir}"
    system(cmd, out: File::NULL, err: File::NULL)
  end

  it "emits one graph.json entry per real library product for a multi-product package" do
    run_gen_proxy
    graph = JSON.parse(File.read(File.join(output_dir, "graph.json")))
    modules = graph.map { |e| e["module"] }
    expect(modules).to include("RealmSwift", "Realm")
    expect(modules).not_to include("realm-swift")
  end

  it "exports every library product by real name from a single proxy Package.swift" do
    run_gen_proxy
    manifest = File.read(File.join(output_dir, ".proxies", "realm-swift_proxy", "Package.swift"))
    expect(manifest).to include(".library(name: \"RealmSwift\"")
    expect(manifest).to include(".library(name: \"Realm\"")
    # Only one dependency on the real package, even though both products fall back to source.
    expect(manifest.scan(".package(url:").size).to eq(1)
  end

  it "shims import the product's target module names, not the product name, when they differ" do
    run_gen_proxy
    shim_dir = File.join(output_dir, ".proxies", "wrapped-module_proxy", "Sources", "wrapped-module_WrappedProduct_shim")
    shim_source = File.read(File.join(shim_dir, "wrapped-module_WrappedProduct_shim.swift"))
    expect(shim_source).to include("@_exported import InternalModuleA")
    expect(shim_source).to include("@_exported import InternalModuleB")
    expect(shim_source).not_to include("@_exported import WrappedProduct")
  end

  it "falls back to the legacy resolved name for a package with no products[] metadata" do
    run_gen_proxy
    graph = JSON.parse(File.read(File.join(output_dir, "graph.json")))
    modules = graph.map { |e| e["module"] }
    expect(modules).to include("Logging")
  end
end
