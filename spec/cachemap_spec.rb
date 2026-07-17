# frozen_string_literal: true

require "spec_helper"

RSpec.describe SPMCache::Cache::Cachemap do
  subject(:cachemap) do
    described_class.new(
      graph_data: [
        { "module" => "Alamofire", "status" => "hit" },
        { "module" => "SnapKit", "status" => "missed" },
        { "module" => "VolatileLib", "status" => "ignored" },
        { "module" => "ExcludedLib", "status" => "excluded" },
        { "module" => "SwiftGenPlugin", "status" => "plugin" },
      ],
    )
  end

  describe "#excluded" do
    it "returns only excluded-status modules" do
      expect(cachemap.excluded).to eq(["ExcludedLib"])
    end
  end

  describe "#plugin" do
    it "returns only plugin-status modules" do
      expect(cachemap.plugin).to eq(["SwiftGenPlugin"])
    end
  end

  describe "#stats" do
    it "includes the excluded and plugin counts" do
      expect(cachemap.stats).to include(excluded: 1, total: 5, hit: 1, missed: 1, ignored: 1, plugin: 1)
    end
  end
end
