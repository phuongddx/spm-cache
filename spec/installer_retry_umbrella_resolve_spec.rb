# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

# Field regression: on a cold run (no `products[]` metadata for anyone yet),
# UmbrellaGenerator can't tell a transitive-only package (e.g. realm-core,
# pulled in solely via realm-swift) apart from a directly-consumed one, so it
# pins everything -- which can conflict and fail `swift package resolve`.
# `Installer#prepare_proxy` must retry the resolve, this time with real
# product metadata available, instead of permanently relying on the
# DerivedData-checkout fallback.
RSpec.describe SPMCache::Installer do
  let(:tmpdir) { Dir.mktmpdir }
  let(:project_path) { File.join(tmpdir, "Fake.xcodeproj") }

  before do
    FileUtils.mkdir_p(project_path)
    SPMCache::Core::Config.instance.reset!
  end

  after { FileUtils.rm_rf(tmpdir) }

  def make_installer
    described_class.new(project: project_path)
  end

  describe "#prepare_proxy" do
    before do
      allow_any_instance_of(SPMCache::SPM::Package::Proxy).to receive(:prepare) { |proxy, &blk| blk.call }
    end

    it "retries the umbrella resolve after enrichment when the first resolve failed" do
      installer = make_installer
      allow(installer).to receive(:resolve_umbrella_checkouts).and_return(false)
      allow(installer).to receive(:enrich_lockfile_products)

      expect(installer).to receive(:retry_umbrella_resolve_after_enrichment)

      installer.send(:prepare_proxy)
    end

    it "does not retry when the first resolve already succeeded" do
      installer = make_installer
      allow(installer).to receive(:resolve_umbrella_checkouts).and_return(true)
      allow(installer).to receive(:enrich_lockfile_products)

      expect(installer).not_to receive(:retry_umbrella_resolve_after_enrichment)

      installer.send(:prepare_proxy)
    end
  end

  describe "#retry_umbrella_resolve_after_enrichment" do
    it "regenerates the umbrella from the (now-enriched) lockfile and resolves again" do
      installer = make_installer
      proxy = instance_double(SPMCache::SPM::Package::Proxy)
      installer.instance_variable_set(:@proxy_pkg, proxy)
      allow(SPMCache::Core::Config.instance).to receive(:lockfile_path).and_return("/fake/spm-cache.lock")
      allow(SPMCache::Core::Config.instance).to receive(:umbrella_dir).and_return("/fake/umbrella")

      expect(proxy).to receive(:gen_umbrella).with("/fake/spm-cache.lock", "/fake/umbrella")
      expect(installer).to receive(:resolve_umbrella_checkouts)

      installer.send(:retry_umbrella_resolve_after_enrichment)
    end
  end
end
