# frozen_string_literal: true

require "spm_cache/main"

RSpec.describe SPMCache do
  it "has a version" do
    expect(SPMCache::VERSION).to match(/\d+\.\d+\.\d+/)
  end

  it "has ROOT constant" do
    expect(SPMCache::ROOT).to be_a(Pathname)
  end
end
