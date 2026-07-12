# frozen_string_literal: true

require "spec_helper"
require "json"
require "tmpdir"

RSpec.describe SPMCache::Core::Lockfile do
  let(:tmpdir) { Dir.mktmpdir }
  let(:lockfile_path) { File.join(tmpdir, "spm-cache.lock") }
  let(:lockfile_data) do
    {
      "MyApp.xcodeproj" => {
        "packages" => [
          { "repositoryURL" => "https://github.com/Alamofire/Alamofire.git", "name" => "Alamofire" },
          { "path_from_root" => "LocalPackages/core-utils", "name" => "core-utils" },
        ],
        "dependencies" => { "MyApp" => ["Alamofire/Alamofire", "core-utils/DebugKit"] },
        "platforms" => { "ios" => "16.0" },
      },
    }
  end

  before do
    File.write(lockfile_path, JSON.generate(lockfile_data))
  end

  subject(:lockfile) { described_class.new(lockfile_path) }

  before(:each) { lockfile.load }

  describe "#projects" do
    it "returns project keys" do
      expect(lockfile.projects.keys).to include("MyApp.xcodeproj")
    end
  end

  describe "#pkgs_for_project" do
    it "returns package objects" do
      pkgs = lockfile.pkgs_for_project("MyApp.xcodeproj")
      expect(pkgs.size).to eq(2)
      expect(pkgs.first.name).to eq("Alamofire")
      expect(pkgs.first.remote?).to be true
      expect(pkgs.last.local?).to be true
    end
  end

  describe "#deep_merge!" do
    it "merges packages from another hash" do
      lockfile.deep_merge!(
        "MyApp.xcodeproj" => {
          "packages" => [{ "repositoryURL" => "https://github.com/SwiftyBeaver/SwiftyBeaver.git", "name" => "SwiftyBeaver" }],
        }
      )
      pkgs = lockfile.pkgs_for_project("MyApp.xcodeproj")
      names = pkgs.map(&:name)
      expect(names).to include("Alamofire", "SwiftyBeaver")
    end
  end

  describe "#empty?" do
    it "returns false when data present" do
      expect(lockfile.empty?).to be false
    end

    it "returns true when no data" do
      empty_lf = described_class.new
      expect(empty_lf.empty?).to be true
    end
  end
end
