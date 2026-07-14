# frozen_string_literal: true

require "spec_helper"

# `swift package describe --type json` emits each product's "type" as a Hash
# (e.g. {"library" => ["automatic"]} or {"executable" => nil}), never a bare
# string. #type must normalize that shape so callers can compare against
# plain strings like "library"/"executable".
RSpec.describe SPMCache::SPM::Desc::Product do
  def product(type)
    described_class.new(raw: { "name" => "Alamofire", "type" => type }, pkg_dir: "/tmp")
  end

  it "extracts the type name from a real swift package describe library hash" do
    expect(product({ "library" => ["automatic"] }).type).to eq("library")
  end

  it "extracts the type name from a real swift package describe executable hash" do
    expect(product({ "executable" => nil }).type).to eq("executable")
  end

  it "still handles a bare string type for backward compatibility" do
    expect(product("library").type).to eq("library")
  end
end
