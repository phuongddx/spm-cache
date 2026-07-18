# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe SPMCache::SPM::Buildable do
  describe "#create_framework" do
    let(:pkg_dir) { Dir.mktmpdir }
    let(:output_dir) { Dir.mktmpdir }
    let(:buildable) { described_class.new(name: "eHealth", pkg_dir: pkg_dir) }

    after { FileUtils.rm_rf([pkg_dir, output_dir]) }

    def modules_dir_for(fw_dir)
      File.join(fw_dir, "Modules")
    end

    it "copies a flat-file swiftmodule/swiftdoc/swiftsourceinfo (baseline, unchanged behavior)" do
      swiftmodule = File.join(pkg_dir, "eHealth.swiftmodule")
      swiftdoc = File.join(pkg_dir, "eHealth.swiftdoc")
      File.write(swiftmodule, "flat swiftmodule contents")
      File.write(swiftdoc, "flat swiftdoc contents")

      fw_dir = buildable.create_framework(
        { swiftmodule: swiftmodule, swiftdoc: swiftdoc },
        output_dir,
      )

      expect(File.read(File.join(modules_dir_for(fw_dir), "eHealth.swiftmodule"))).to eq("flat swiftmodule contents")
      expect(File.read(File.join(modules_dir_for(fw_dir), "eHealth.swiftdoc"))).to eq("flat swiftdoc contents")
    end

    # Field regression: eh_xcframework's build produced a `.swiftmodule`
    # DIRECTORY bundle (per-arch files inside it) rather than a flat file --
    # find_file's glob matched it anyway, and the old FileUtils.cp call
    # crashed with Errno::EISDIR trying to copy a directory as a file.
    it "recursively copies a directory-shaped swiftmodule instead of raising Errno::EISDIR" do
      swiftmodule_dir = File.join(pkg_dir, "eHealth.swiftmodule")
      FileUtils.mkdir_p(swiftmodule_dir)
      File.write(File.join(swiftmodule_dir, "arm64-apple-ios.swiftmodule"), "arch-specific contents")
      File.write(File.join(swiftmodule_dir, "arm64-apple-ios.swiftdoc"), "arch-specific doc")

      fw_dir = nil
      expect do
        fw_dir = buildable.create_framework({ swiftmodule: swiftmodule_dir }, output_dir)
      end.not_to raise_error

      copied_dir = File.join(modules_dir_for(fw_dir), "eHealth.swiftmodule")
      expect(File.directory?(copied_dir)).to be true
      expect(File.read(File.join(copied_dir, "arm64-apple-ios.swiftmodule"))).to eq("arch-specific contents")
      expect(File.read(File.join(copied_dir, "arm64-apple-ios.swiftdoc"))).to eq("arch-specific doc")
    end

    it "merges a directory-shaped swiftmodule into the same dir already created from swiftinterface, without clobbering it" do
      swiftinterface = File.join(pkg_dir, "eHealth.swiftinterface")
      File.write(swiftinterface, "public interface contents")

      swiftmodule_dir = File.join(pkg_dir, "eHealth.swiftmodule")
      FileUtils.mkdir_p(swiftmodule_dir)
      File.write(File.join(swiftmodule_dir, "arm64-apple-ios.swiftdoc"), "arch-specific doc")

      fw_dir = buildable.create_framework(
        { swiftinterface: swiftinterface, swiftmodule: swiftmodule_dir, derived_data: "/DerivedData" },
        output_dir,
      )

      sm_dir = File.join(modules_dir_for(fw_dir), "eHealth.swiftmodule")
      expect(File.read(File.join(sm_dir, "arm64-apple-ios.swiftinterface"))).to eq("public interface contents")
      expect(File.read(File.join(sm_dir, "arm64-apple-ios.swiftdoc"))).to eq("arch-specific doc")
    end
  end

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
