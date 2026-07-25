# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe SPMCache::SPM::XCFramework::XCFramework do
  let(:output_dir) { Dir.mktmpdir }
  let(:output_path) { File.join(output_dir, "Fake.xcframework") }
  let(:fw_path) { Dir.mktmpdir }

  after { FileUtils.rm_rf([output_dir, fw_path]) }

  describe "#build" do
    it "returns the output path on success" do
      xcframework = described_class.new(name: "Fake", framework_paths: [fw_path], output_path: output_path)
      allow(SPMCache::Core::Sh).to receive(:run)

      expect(xcframework.build).to eq(output_path)
    end

    it "removes a partially-written output directory when xcodebuild fails" do
      # Field bug: xcodebuild -create-xcframework can write a partial bundle
      # (e.g. just Info.plist, no framework slice) before erroring out. A
      # later run must not mistake that leftover for a valid cache entry.
      FileUtils.mkdir_p(output_path)
      File.write(File.join(output_path, "Info.plist"), "partial")

      xcframework = described_class.new(name: "Fake", framework_paths: [fw_path], output_path: output_path)
      allow(SPMCache::Core::Sh).to receive(:run).and_raise(SPMCache::Core::GeneralError, "xcodebuild failed")

      expect { xcframework.build }.to raise_error(SPMCache::Core::GeneralError)
      expect(File).not_to exist(output_path)
    end

    it "re-raises the original error after cleanup" do
      xcframework = described_class.new(name: "Fake", framework_paths: [fw_path], output_path: output_path)
      allow(SPMCache::Core::Sh).to receive(:run).and_raise(SPMCache::Core::GeneralError, "boom")

      expect { xcframework.build }.to raise_error(SPMCache::Core::GeneralError, "boom")
    end
  end
end
