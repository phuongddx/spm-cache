# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "json"
require "fileutils"

# Proves the corrected pipeline order for real (red-team BLOCKER 1): checkouts
# must be materialized under {umbrella_dir}/.build/checkouts BEFORE
# enrich_lockfile_products runs `swift package describe` against them. Uses a
# throwaway local git repo cloned over the `file://` transport so `swift
# package resolve` runs for real without needing network access.
RSpec.describe "checkout materialization -> enrichment sequencing (real, offline)" do
  let(:tmpdir) { Dir.mktmpdir }
  let(:project_path) { File.join(tmpdir, "Fake.xcodeproj") }
  let(:repo_source_dir) { File.join(tmpdir, "FixturePkg") }
  let(:bare_repo_dir) { File.join(tmpdir, "FixturePkg.git") }
  let(:umbrella_dir) { File.join(tmpdir, "umbrella") }
  let(:lockfile_path) { File.join(tmpdir, "spm-cache.lock") }

  before do
    FileUtils.mkdir_p(project_path)
    FileUtils.mkdir_p(umbrella_dir)
    SPMCache::Core::Config.instance.reset!
    allow(SPMCache::Core::Config.instance).to receive(:umbrella_dir).and_return(umbrella_dir)
    build_fixture_git_package
    write_umbrella_manifest
    write_lockfile
  end

  after { FileUtils.rm_rf(tmpdir) }

  def build_fixture_git_package
    FileUtils.mkdir_p(File.join(repo_source_dir, "Sources", "FixtureLib"))
    File.write(File.join(repo_source_dir, "Package.swift"), <<~SWIFT)
      // swift-tools-version: 5.9
      import PackageDescription
      let package = Package(
          name: "FixturePkg",
          products: [.library(name: "FixtureLib", targets: ["FixtureLib"])],
          targets: [.target(name: "FixtureLib")]
      )
    SWIFT
    File.write(File.join(repo_source_dir, "Sources", "FixtureLib", "FixtureLib.swift"), "public struct FixtureLib {}\n")

    Dir.chdir(repo_source_dir) do
      system("git", "init", "-q", "-b", "main", ".", exception: true)
      system("git", "config", "user.email", "test@example.com", exception: true)
      system("git", "config", "user.name", "Test", exception: true)
      system("git", "add", "-A", exception: true)
      system("git", "commit", "-q", "-m", "init", exception: true)
      system("git", "tag", "-a", "1.0.0", "-m", "1.0.0", exception: true)
    end
    system("git", "clone", "-q", "--bare", repo_source_dir, bare_repo_dir, exception: true)
  end

  def write_umbrella_manifest
    File.write(File.join(umbrella_dir, "Package.swift"), <<~SWIFT)
      // swift-tools-version: 6.0
      import PackageDescription
      let package = Package(
          name: "spm_cache_umbrella",
          platforms: [.iOS(.v16), .macOS(.v14)],
          dependencies: [
              .package(url: "file://#{bare_repo_dir}", from: "1.0.0")
          ],
          targets: []
      )
    SWIFT
  end

  def write_lockfile
    File.write(lockfile_path, JSON.generate(
      "Fake.xcodeproj" => {
        "packages" => [{ "repositoryURL" => "file://#{bare_repo_dir}", "name" => "FixturePkg", "version" => "1.0.0" }],
        "dependencies" => {},
        "platforms" => { "ios" => "16.0" },
      },
    ))
  end

  it "materializes real checkouts before enrichment can read product metadata" do
    installer = SPMCache::Installer.new(project: project_path)
    installer.instance_variable_set(:@lockfile, SPMCache::Core::Lockfile.new(lockfile_path))

    checkout_dir = File.join(umbrella_dir, ".build", "checkouts", "FixturePkg")
    expect(File.directory?(checkout_dir)).to be false

    installer.send(:resolve_umbrella_checkouts)
    expect(File.directory?(checkout_dir)).to be true

    installer.send(:enrich_lockfile_products)

    saved = JSON.parse(File.read(lockfile_path))
    pkg = saved["Fake.xcodeproj"]["packages"].first
    expect(pkg["products"]).to eq([{ "name" => "FixtureLib", "type" => "library", "targets" => ["FixtureLib"] }])
  end
end
