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

  describe "Pkg#products" do
    it "defaults to an empty array when no products metadata is present" do
      pkgs = lockfile.pkgs_for_project("MyApp.xcodeproj")
      expect(pkgs.first.products).to eq([])
    end

    it "round-trips products through #to_h instead of silently dropping them" do
      data = {
        "repositoryURL" => "https://github.com/realm/realm-swift.git",
        "name" => "realm-swift",
        "products" => [{ "name" => "RealmSwift", "type" => "library", "targets" => ["RealmSwift"] }],
      }
      pkg = SPMCache::Core::Lockfile::Pkg.new(data)
      expect(pkg.products).to eq(data["products"])
      expect(pkg.to_h["products"]).to eq(data["products"])
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

  # 16-02 / TOGL-03: the reader 16-03's reason derivation asks -- "is this
  # row's name backed by a binary package?" -- answered as one membership-
  # testable Set per project. A cache-state row's `name` is an xcframework
  # basename, so a binary-backed package must be reachable by its identity,
  # any of its product names, or any of those products' target names.
  describe "#binary_backed_names" do
    def write_lockfile_json(data, name = "lock.json")
      path = File.join(tmpdir, name)
      File.write(path, JSON.generate(data))
      described_class.new(path)
    end

    it "answers identity, product, and product-target names for a binary-flagged package as a Set" do
      lockfile = write_lockfile_json({
        "MyApp.xcodeproj" => {
          "packages" => [
            {
              "repositoryURL" => "https://github.com/example/bin-pkg.git",
              "name" => "bin-pkg",
              "binary_target" => true,
              "products" => [
                { "name" => "BinLib", "type" => "library", "targets" => ["BinLib", "BinCore"] },
                { "name" => "SecondLib", "type" => "library", "targets" => ["SecondLib"] },
              ],
            },
          ],
        },
      })

      result = lockfile.binary_backed_names("MyApp.xcodeproj")

      expect(result).to be_a(Set)
      expect(result).to eq(Set["bin-pkg", "BinLib", "BinCore", "SecondLib"])
    end

    it "contributes nothing for packages without the flag or with it false" do
      lockfile = write_lockfile_json({
        "MyApp.xcodeproj" => {
          "packages" => [
            {
              "repositoryURL" => "https://github.com/example/plain.git",
              "name" => "plain",
              "binary_target" => false,
              "products" => [{ "name" => "PlainLib", "type" => "library", "targets" => ["PlainLib"] }],
            },
            {
              "repositoryURL" => "https://github.com/example/legacy.git",
              "name" => "legacy",
              "products" => [{ "name" => "LegacyLib", "type" => "library", "targets" => ["LegacyLib"] }],
            },
          ],
        },
      })

      expect(lockfile.binary_backed_names("MyApp.xcodeproj")).to be_empty
    end

    it "answers an empty set for a legacy lockfile with no flags anywhere" do
      expect(lockfile.binary_backed_names("MyApp.xcodeproj")).to be_empty
    end

    it "still contributes the identity name when a flagged package carries no products[]" do
      lockfile = write_lockfile_json({
        "MyApp.xcodeproj" => {
          "packages" => [
            { "repositoryURL" => "https://github.com/example/bare.git", "name" => "bare", "binary_target" => true },
          ],
        },
      })

      expect(lockfile.binary_backed_names("MyApp.xcodeproj")).to eq(Set["bare"])
    end

    it "answers an empty set for an unknown project, an empty lockfile, and a missing packages key" do
      with_packages = write_lockfile_json({
        "MyApp.xcodeproj" => { "packages" => [{ "name" => "bin", "binary_target" => true }] },
      })
      expect(with_packages.binary_backed_names("Other.xcodeproj")).to be_empty

      expect(described_class.new.binary_backed_names("MyApp.xcodeproj")).to be_empty

      without_packages = write_lockfile_json({
        "MyApp.xcodeproj" => { "dependencies" => {}, "platforms" => { "ios" => "16.0" } },
      }, "no-packages.json")
      expect(without_packages.binary_backed_names("MyApp.xcodeproj")).to be_empty
    end
  end

end
