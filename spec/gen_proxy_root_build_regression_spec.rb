# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "json"
require "fileutils"

# Regression guard (code-review finding, 2026-07-16): `generateRootProxy` once
# wired every package's root-proxy product dependency to
# `pkg.resolvedProductName` (a single legacy-identity guess) instead of every
# real product the per-package proxy actually declares. For any package whose
# products[] has more than one entry (Realm -> Realm + RealmSwift) or whose
# single real product name differs from the lockfile identity, this made the
# generated root `Package.swift` reference a product that does not exist in
# its own dependency -- a hard `swift build` failure ("product ... not found
# in package ...") that no other spec caught, because none of them actually
# built the generated proxy output.
#
# This spec builds a real (local, offline, `file://`-based) multi-product
# SwiftPM package and runs `swift build` against the ACTUAL generated root
# proxy, so a regression here fails loudly instead of silently.
RSpec.describe "gen-proxy root proxy actually builds (real swift build, offline)" do
  let(:binary) do
    local = SPMCache::ROOT.join("tools", "spm-cache-proxy",
                                ".build", "release", "spm-cache-proxy").to_s
    File.executable?(local) ? local : nil
  end

  let(:tmpdir) { Dir.mktmpdir }
  let(:repo_source_dir) { File.join(tmpdir, "MultiProductPkg") }
  let(:bare_repo_dir) { File.join(tmpdir, "MultiProductPkg.git") }
  let(:umbrella_dir) { File.join(tmpdir, "umbrella") }
  let(:output_dir) { File.join(tmpdir, "proxy") }
  let(:cache_dir) { File.join(tmpdir, "cache") }
  let(:lockfile_path) { File.join(tmpdir, "spm-cache.lock") }

  before do
    skip "spm-cache-proxy binary not built (run make proxy.build)" unless binary
    FileUtils.mkdir_p(umbrella_dir)
    FileUtils.mkdir_p(output_dir)
    FileUtils.mkdir_p(cache_dir)
    build_fixture_git_package
    write_lockfile
  end

  after { FileUtils.rm_rf(tmpdir) if tmpdir }

  def build_fixture_git_package
    FileUtils.mkdir_p(File.join(repo_source_dir, "Sources", "LibA"))
    FileUtils.mkdir_p(File.join(repo_source_dir, "Sources", "LibB"))
    File.write(File.join(repo_source_dir, "Package.swift"), <<~SWIFT)
      // swift-tools-version: 5.9
      import PackageDescription
      let package = Package(
          name: "MultiProductPkg",
          products: [
              .library(name: "LibA", targets: ["LibA"]),
              .library(name: "LibB", targets: ["LibB"]),
          ],
          targets: [.target(name: "LibA"), .target(name: "LibB")]
      )
    SWIFT
    File.write(File.join(repo_source_dir, "Sources", "LibA", "LibA.swift"), "public struct LibA {}\n")
    File.write(File.join(repo_source_dir, "Sources", "LibB", "LibB.swift"), "public struct LibB {}\n")

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

  def write_lockfile
    File.write(lockfile_path, JSON.generate(
      "FixtureApp.xcodeproj" => {
        "packages" => [{
          "repositoryURL" => "file://#{bare_repo_dir}",
          "name" => "MultiProductPkg",
          "version" => "1.0.0",
          "products" => [
            { "name" => "LibA", "type" => "library", "targets" => ["LibA"] },
            { "name" => "LibB", "type" => "library", "targets" => ["LibB"] },
          ],
        }],
        "dependencies" => {},
        "platforms" => { "ios" => "16.0" },
      },
    ))
  end

  it "generates a root proxy that actually compiles for a multi-product package" do
    system("#{binary} gen-proxy --umbrella #{umbrella_dir} --lockfile #{lockfile_path} --output #{output_dir} --cache #{cache_dir}",
           out: File::NULL, err: File::NULL)

    result = Dir.chdir(output_dir) { `swift build 2>&1` }
    expect($?.success?).to be(true), "swift build failed:\n#{result}"
  end
end
