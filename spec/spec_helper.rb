# frozen_string_literal: true

require "spm_cache/main"

RSpec.describe SPMCache do
  it "has a version" do
    expect(SPMCache::VERSION).to match(/\d+\.\d+\.\d+/)
  end

  it "has ROOT constant" do
    expect(SPMCache::ROOT).to be_a(Pathname)
  end

  it "resolves ROOT to the repo root, not its parent" do
    expect(File.exist?(SPMCache::ROOT.join("lib", "spm_cache.rb"))).to be true
    expect(File.directory?(SPMCache::ROOT.join("tools", "spm-cache-proxy"))).to be true
  end
end
