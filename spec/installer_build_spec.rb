# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

# Unit-tests Installer::Build target-selection logic with a stubbed Cachemap.
# No real xcodebuild is invoked; the build pipeline is not exercised here.
RSpec.describe SPMCache::Installer::Build do
  let(:tmpdir) { Dir.mktmpdir }
  let(:project_path) { File.join(tmpdir, "Fake.xcodeproj") }

  before do
    FileUtils.mkdir_p(project_path)
    # Stub out the heavy Installer#perform_install steps so we can isolate
    # the selection logic added in Phase 2.
    allow_any_instance_of(SPMCache::Installer).to receive(:perform_install).and_wrap_original do |original, *args, &block|
      me = original.receiver
      me.instance_variable_set(:@cachemap, cachemap) if me.respond_to?(:cachemap)
      nil
    end
    allow_any_instance_of(SPMCache::Installer::Build).to receive(:resolve_umbrella_checkouts).and_return(nil)
    allow_any_instance_of(SPMCache::Installer::Build).to receive(:checkout_map).and_return({})
    allow_any_instance_of(SPMCache::Installer::Build).to receive(:build_single_target).and_return(nil)
    allow(SPMCache::Core::Config.instance).to receive(:ignore_build_errors?).and_return(false)
    allow(SPMCache::Core::Config.instance).to receive(:default_sdk).and_return("iphonesimulator")
    allow(SPMCache::Core::Config.instance).to receive(:cache_dir).and_return(tmpdir)
  end

  after { FileUtils.rm_rf(tmpdir) }

  let(:cachemap) do
    SPMCache::Cache::Cachemap.new(
      graph_data: [
        { "module" => "Alamofire", "status" => "missed" },
        { "module" => "SnapKit", "status" => "missed" },
        { "module" => "CachedLib", "status" => "hit" },
        { "module" => "VolatileLib", "status" => "ignored" },
      ],
    )
  end

  def make_installer(targets: [])
    described_class.new(project: project_path, targets: targets)
  end

  it "builds all missed targets when no TARGETS given" do
    inst = make_installer(targets: [])
    expect { inst.perform_install }.to output(%r{Building 2 target.*Alamofire.*SnapKit}m).to_stdout
  end

  it "filters to only requested missed targets" do
    inst = make_installer(targets: ["Alamofire"])
    expect { inst.perform_install }.to output(/Building 1 target.*: Alamofire/).to_stdout
  end

  it "warns on unknown target" do
    inst = make_installer(targets: ["Nonexistent"])
    expect {
      expect { inst.perform_install }.to output(/No targets to build/).to_stdout
    }.to output(/unknown target 'Nonexistent'/).to_stderr
  end

  it "warns when requested target is ignored" do
    inst = make_installer(targets: ["VolatileLib"])
    expect { inst.perform_install }.to output(/'VolatileLib' is in the ignore list; skipping/).to_stderr
  end

  it "does not build already-hit targets" do
    inst = make_installer(targets: ["CachedLib"])
    expect { inst.perform_install }.to output(/unknown target 'CachedLib'|No targets to build/).to_stdout
  end
end
