# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "json"

# End-to-end regression sweep against the real built binary, combining all
# three field-reported bugs (plans/reports/debugger-0716-2209-proxy-product-
# name-plugin-guid-triage-report.md) in a single lockfile:
#   1. identity collision -- every proxied package's wrapper folder must be
#      `<slug>_proxy`, never bare `<slug>` (which would collide with the real
#      package's own SwiftPM identity).
#   2. wrong product names -- multi-product packages (Realm) must be proxied
#      under their real product names, not the lockfile identity.
#   3. plugin-only packages -- must be skipped by both generators with their
#      original reference preserved (Xcode-side, covered separately in
#      spec/installer_integrate_proxy_spec.rb), not given a broken proxy.
# Skipped gracefully when the binary is not built (mirrors the other fixture
# specs).
RSpec.describe "gen-proxy field regression (Swift fixture smoke)" do
  let(:binary) do
    local = SPMCache::ROOT.join("tools", "spm-cache-proxy",
                                ".build", "release", "spm-cache-proxy").to_s
    File.executable?(local) ? local : nil
  end

  let(:lockfile) do
    SPMCache::ROOT.join("spec", "fixtures", "field-regression-lockfile.json").to_s
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
    system("#{binary} gen-proxy --umbrella #{umbrella_dir} --lockfile #{lockfile} --output #{output_dir} --cache #{cache_dir}",
           out: File::NULL, err: File::NULL)
  end

  after { FileUtils.rm_rf(tmpdir) if tmpdir }

  def graph
    JSON.parse(File.read(File.join(output_dir, "graph.json")))
  end

  it "proxies real product names for a multi-product package (bug: wrong product names)" do
    modules = graph.map { |e| e["module"] }
    expect(modules).to include("RealmSwift", "Realm", "Alamofire")
    expect(modules).not_to include("realm-swift")
  end

  it "never names a proxy wrapper folder identically to the wrapped package's identity (bug: identity collision)" do
    %w[realm-swift Alamofire].each do |slug|
      expect(File.directory?(File.join(output_dir, ".proxies", slug))).to be false
      expect(File.directory?(File.join(output_dir, ".proxies", "#{slug}_proxy"))).to be true
    end

    root_manifest = File.read(File.join(output_dir, "Package.swift"))
    # The wrapper's own package identity must never equal the real package's
    # identity it depends on -- that's exactly the collision the fix closes.
    expect(root_manifest).not_to include(".package(path: \".proxies/realm-swift\")")
    expect(root_manifest).not_to include(".package(path: \".proxies/Alamofire\")")
  end

  it "skips the plugin-only package entirely (bug: plugin-only packages break resolution)" do
    statuses = graph.each_with_object({}) { |e, h| h[e["module"]] = e["status"] }
    expect(statuses["SwiftGenPlugin"]).to eq("plugin")
    expect(File.directory?(File.join(output_dir, ".proxies", "SwiftGenPlugin_proxy"))).to be false

    root_manifest = File.read(File.join(output_dir, "Package.swift"))
    expect(root_manifest).not_to include("SwiftGenPlugin")
  end
end
