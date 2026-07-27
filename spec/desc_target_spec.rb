# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe SPMCache::SPM::Desc::Target do
  describe "#header_paths" do
    let(:pkg_dir) { Dir.mktmpdir }
    after { FileUtils.rm_rf(pkg_dir) }

    it "returns empty when there are no public headers declared" do
      target = described_class.new(
        raw: { "name" => "NoHeaders", "path" => "Sources/NoHeaders" },
        pkg_dir: pkg_dir
      )
      expect(target.header_paths).to eq([])
    end

    it "returns describe-based publicHeadersPath when swift package describe provides it" do
      target = described_class.new(
        raw: {
          "name" => "WithHeaders",
          "publicHeadersPath" => "Public",
          "path" => "Sources/WithHeaders"
        },
        pkg_dir: pkg_dir
      )
      expect(target.header_paths).to eq([File.join(pkg_dir, "Public")])
    end

    context "Package.swift fallback for publicHeadersPath" do
      it "falls back to Package.swift when swift package describe returns no publicHeadersPath" do
        # Create a realistic Package.swift with a .target declaration
        package_swift = File.join(pkg_dir, "Package.swift")
        File.write(package_swift, <<~MANIFEST)
          // swift-tools-version: 5.9
          import PackageDescription

          let package = Package(
            name: "TestPackage",
            targets: [
              .target(
                name: "MyTarget",
                path: "Sources/MyTarget",
                publicHeadersPath: "Public"
              )
            ]
          )
        MANIFEST

        target = described_class.new(
          raw: {
            "name" => "MyTarget",
            "path" => "Sources/MyTarget"
            # Note: no publicHeadersPath from describe, to force fallback
          },
          pkg_dir: pkg_dir
        )

        expect(target.header_paths).to eq([File.join(pkg_dir, "Sources/MyTarget", "Public")])
      end

      it "normalizes '.' and './' to the target's own root directory" do
        package_swift = File.join(pkg_dir, "Package.swift")
        File.write(package_swift, <<~MANIFEST)
          let package = Package(
            name: "TestPackage",
            targets: [
              .target(
                name: "MyTarget",
                path: "Sources/MyTarget",
                publicHeadersPath: "."
              )
            ]
          )
        MANIFEST

        target = described_class.new(
          raw: { "name" => "MyTarget", "path" => "Sources/MyTarget" },
          pkg_dir: pkg_dir
        )

        expect(target.header_paths).to eq([File.join(pkg_dir, "Sources/MyTarget")])
      end

      it "returns empty when Package.swift exists but target has no publicHeadersPath" do
        package_swift = File.join(pkg_dir, "Package.swift")
        File.write(package_swift, <<~MANIFEST)
          let package = Package(
            name: "TestPackage",
            targets: [
              .target(name: "NoPublicHeaders", path: "Sources/NoPublicHeaders")
            ]
          )
        MANIFEST

        target = described_class.new(
          raw: { "name" => "NoPublicHeaders", "path" => "Sources/NoPublicHeaders" },
          pkg_dir: pkg_dir
        )

        expect(target.header_paths).to eq([])
      end

      it "handles Firebase-style Package.swift with multiple targets" do
        package_swift = File.join(pkg_dir, "Package.swift")
        File.write(package_swift, <<~MANIFEST)
          let package = Package(
            name: "firebase-ios-sdk",
            targets: [
              .target(
                name: "FirebaseCore",
                path: "FirebaseCore/Sources",
                publicHeadersPath: "Public"
              ),
              .target(
                name: "FirebaseCrashlytics",
                path: "FirebaseCrashlytics/Sources",
                publicHeadersPath: "Public"
              )
            ]
          )
        MANIFEST

        target1 = described_class.new(
          raw: { "name" => "FirebaseCore", "path" => "FirebaseCore/Sources" },
          pkg_dir: pkg_dir
        )
        expect(target1.header_paths).to eq([File.join(pkg_dir, "FirebaseCore/Sources", "Public")])

        target2 = described_class.new(
          raw: { "name" => "FirebaseCrashlytics", "path" => "FirebaseCrashlytics/Sources" },
          pkg_dir: pkg_dir
        )
        expect(target2.header_paths).to eq([File.join(pkg_dir, "FirebaseCrashlytics/Sources", "Public")])
      end

      it "uses default path when raw['path'] is not present" do
        package_swift = File.join(pkg_dir, "Package.swift")
        File.write(package_swift, <<~MANIFEST)
          let package = Package(
            name: "TestPackage",
            targets: [
              .target(
                name: "DefaultPath",
                publicHeadersPath: "Headers"
              )
            ]
          )
        MANIFEST

        target = described_class.new(
          raw: { "name" => "DefaultPath" },
          pkg_dir: pkg_dir
        )

        # Default path is Sources/{name}
        expect(target.header_paths).to eq([File.join(pkg_dir, "Sources/DefaultPath", "Headers")])
      end

      # Regression test: Firebase bug where wrapper target's dependencies array contains
      # inline .target(name: "FirebaseDynamicLinks") reference. Without proper parenthesis
      # tracking, the naive regex matched the WRAPPER's block instead of the real target.
      it "avoids matching inline .target references in another target's dependencies array" do
        package_swift = File.join(pkg_dir, "Package.swift")
        File.write(package_swift, <<~MANIFEST)
          let package = Package(
            name: "FirebaseSDK",
            targets: [
              .target(
                name: "FirebaseDynamicLinksTarget",
                dependencies: [
                  .target(name: "FirebaseDynamicLinks"),
                  .product(name: "GoogleUtilities", package: "GoogleUtilities")
                ]
              ),
              .target(
                name: "FirebaseDynamicLinks",
                path: "FirebaseDynamicLinks/Sources",
                publicHeadersPath: "Public"
              )
            ]
          )
        MANIFEST

        target = described_class.new(
          raw: { "name" => "FirebaseDynamicLinks", "path" => "FirebaseDynamicLinks/Sources" },
          pkg_dir: pkg_dir
        )

        # Should find the REAL target's publicHeadersPath, not the wrapper's inline reference
        expect(target.header_paths).to eq([File.join(pkg_dir, "FirebaseDynamicLinks/Sources", "Public")])
      end
    end
  end
end
