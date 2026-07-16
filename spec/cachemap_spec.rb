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
      ],
    )
  end

  describe "#excluded" do
    it "returns only excluded-status modules" do
      expect(cachemap.excluded).to eq(["ExcludedLib"])
    end
  end

  describe "#stats" do
    it "includes the excluded count" do
      expect(cachemap.stats).to include(excluded: 1, total: 4, hit: 1, missed: 1, ignored: 1)
    end
  end
end
