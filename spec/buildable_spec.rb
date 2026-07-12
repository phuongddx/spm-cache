# frozen_string_literal: true

require "spec_helper"

RSpec.describe SPMCache::SPM::Buildable do
  describe "#initialize" do
    it "sets name and module_name" do
      b = described_class.new(name: "Alamofire", pkg_dir: "/tmp")
      expect(b.name).to eq("Alamofire")
      expect(b.module_name).to eq("Alamofire")
    end

    it "allows overriding module_name" do
      b = described_class.new(name: "test", module_name: "CustomModule", pkg_dir: "/tmp")
      expect(b.module_name).to eq("CustomModule")
    end
  end

  describe "#library_evolution" do
    it "defaults to true" do
      b = described_class.new(name: "test", pkg_dir: "/tmp")
      expect(b.library_evolution).to be true
    end

    it "can be disabled" do
      b = described_class.new(name: "test", pkg_dir: "/tmp", library_evolution: false)
      expect(b.library_evolution).to be false
    end
  end

  describe "DESTINATIONS" do
    it "includes iphonesimulator and iphoneos" do
      expect(described_class::DESTINATIONS).to include("iphonesimulator", "iphoneos")
    end
  end
end

RSpec.describe SPMCache::SPM::Package do
  describe "DEFAULT_DESTINATIONS" do
    it "includes both simulator and device" do
      expect(described_class::DEFAULT_DESTINATIONS).to eq(["iphonesimulator", "iphoneos"])
    end
  end
end
