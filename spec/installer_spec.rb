# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

# Regression coverage for issue #1: spm-cache.yml was never loaded during
# build/use commands (Installer#ensure_config_file copied the template but
# never called Config#load), so ignore_build_errors/ignore/default_sdk were
# silently ignored.
RSpec.describe SPMCache::Installer do
  let(:tmpdir) { Dir.mktmpdir }
  let(:project_path) { File.join(tmpdir, "Fake.xcodeproj") }
  let(:config_path) { File.join(tmpdir, "spm-cache.yml") }

  before do
    FileUtils.mkdir_p(project_path)
    SPMCache::Core::Config.instance.reset!
  end

  after { FileUtils.rm_rf(tmpdir) }

  def make_installer
    described_class.new(project: project_path)
  end

  context "when spm-cache.yml already exists" do
    before do
      File.write(config_path, "ignore_build_errors: true\n")
    end

    it "loads settings from the existing config into Config.instance" do
      installer = make_installer
      installer.send(:ensure_config_file)

      expect(SPMCache::Core::Config.instance.ignore_build_errors?).to be true
    end

    it "does not overwrite the existing config file" do
      installer = make_installer
      installer.send(:ensure_config_file)

      expect(File.read(config_path)).to eq("ignore_build_errors: true\n")
    end
  end

  context "when spm-cache.yml is missing" do
    it "copies the template and loads its defaults into Config.instance" do
      installer = make_installer
      installer.send(:ensure_config_file)

      expect(File.exist?(config_path)).to be true
      config = SPMCache::Core::Config.instance
      expect(config.ignore_build_errors?).to be false
      expect(config.default_sdk).to eq("iphonesimulator")
      expect(config.ignore_list).to eq([])
    end
  end
end
