# frozen_string_literal: true

require "spec_helper"

RSpec.describe SPMCache::Core::Config do
  subject(:config) { described_class.instance }

  before do
    config.reset!
    config.project_dir = "/tmp/test-project"
  end

  describe "#sandbox_dir" do
    it "returns project_dir/spm-cache" do
      expect(config.sandbox_dir).to eq("/tmp/test-project/spm-cache")
    end
  end

  describe "#cache_dir" do
    it "returns global cache without args" do
      expect(config.cache_dir).to match(/\.spm-cache$/)
    end

    it "returns config-specific dir with args" do
      expect(config.cache_dir("debug")).to match(/\.spm-cache\/debug$/)
    end
  end

  describe "#default_sdk" do
    it "returns iphonesimulator by default" do
      expect(config.default_sdk).to eq("iphonesimulator")
    end
  end

  describe "#ignore_list" do
    it "returns empty array by default" do
      expect(config.ignore_list).to eq([])
    end
  end

  describe "#should_ignore?" do
    before { config.raw["ignore"] = ["Test*"] }

    it "matches glob patterns" do
      expect(config.should_ignore?("TestPackage")).to be true
      expect(config.should_ignore?("OtherPackage")).to be false
    end
  end
end
