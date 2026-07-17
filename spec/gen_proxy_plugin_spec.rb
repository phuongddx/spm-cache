# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "json"

# Swift-side fixture check: runs the built spm-cache-proxy binary against
# spec/fixtures/plugin-lockfile.json (a plugin-only package, a library
# package, and a mixed library+plugin package) and asserts the plugin-only
# package is fully skipped by the generators while its status is still
# surfaced in graph.json. Skipped gracefully when the binary is not built
# (mirrors spec/gen_proxy_ignore_spec.rb).
RSpec.describe "gen-proxy plugin-only packages (Swift fixture smoke)" do
  let(:binary) do
    local = SPMCache::ROOT.join("tools", "spm-cache-proxy",
                                ".build", "release", "spm-cache-proxy").to_s
    File.executable?(local) ? local : nil
  end

  let(:lockfile) do
    SPMCache::ROOT.join("spec", "fixtures", "plugin-lockfile.json").to_s
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

  it "omits an already-known plugin-only package from the umbrella manifest" do
    system("#{binary} gen-umbrella --lockfile #{lockfile} --output #{umbrella_dir}", out: File::NULL, err: File::NULL)
    manifest = File.read(File.join(umbrella_dir, "Package.swift"))
    expect(manifest).not_to include("SwiftGenPlugin")
    expect(manifest).to include("Alamofire")
    expect(manifest).to include("mixed-package")
  end

  it "marks the plugin-only package as 'plugin' status in graph.json" do
    run_gen_proxy
    graph = JSON.parse(File.read(File.join(output_dir, "graph.json")))
    statuses = graph.each_with_object({}) { |e, h| h[e["module"]] = e["status"] }
    expect(statuses["SwiftGenPlugin"]).to eq("plugin")
    expect(statuses["Alamofire"]).to eq("missed")
  end

  it "creates no proxy folder for a plugin-only package" do
    run_gen_proxy
    expect(File.directory?(File.join(output_dir, ".proxies", "SwiftGenPlugin_proxy"))).to be false
    expect(File.directory?(File.join(output_dir, ".proxies", "Alamofire_proxy"))).to be true
  end

  it "does not reference the plugin-only package from the root proxy manifest" do
    run_gen_proxy
    root_pkg = File.read(File.join(output_dir, "Package.swift"))
    expect(root_pkg).not_to include("SwiftGenPlugin_proxy")
    expect(root_pkg).to include("Alamofire_proxy")
  end

  it "proxies only the library product of a mixed library+plugin package" do
    run_gen_proxy
    graph = JSON.parse(File.read(File.join(output_dir, "graph.json")))
    statuses = graph.each_with_object({}) { |e, h| h[e["module"]] = e["status"] }
    expect(statuses["MixedLib"]).to eq("missed")
    expect(statuses["MixedPlugin"]).to be_nil
    expect(File.directory?(File.join(output_dir, ".proxies", "mixed-package_proxy"))).to be true
    manifest = File.read(File.join(output_dir, ".proxies", "mixed-package_proxy", "Package.swift"))
    expect(manifest).to include(".library(name: \"MixedLib\"")
    expect(manifest).not_to include("MixedPlugin")
  end
end
